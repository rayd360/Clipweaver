import AppKit
import ImageIO

struct TextOverlay: Codable {
    var start:Double
    var end:Double
    var text:String? = nil
    var filename:String? = nil
    var x:Double? = nil
    var y:Double? = nil
    var width:Double? = nil
    var height:Double? = nil
    var fontSize:Double? = nil
    var color:String? = nil
    var background:String? = nil
    var alignment:String? = nil
    func validate(duration:Double) throws {
        guard start.isFinite,end.isFinite,start>=0,end>start,end<=duration+0.002,
              (text != nil) != (filename != nil) else {throw WeaverError("Each overlay needs valid finished-video times and either text or an image filename.")}
        if let text {guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,text.count<=500 else {throw WeaverError("Overlay text must contain 1–500 characters. Split long subtitles into shorter entries.")}}
        if let filename {guard safeBasename(filename),["png","jpg","jpeg"].contains(URL(fileURLWithPath:filename).pathExtension.lowercased()) else {throw WeaverError("An overlay image needs a PNG or JPEG basename.")}}
        let a=x ?? 0.1,b=y ?? 0.72,w=width ?? 0.8,h=height ?? 0.18
        guard [a,b,w,h,fontSize ?? 0.05].allSatisfy(\.isFinite),a>=0,b>=0,w>0,h>0,a+w<=1.00001,b+h<=1.00001,(0.015...0.15).contains(fontSize ?? 0.05),["left","center","right"].contains(alignment ?? "center") else {throw WeaverError("Overlay positions must fit inside the video; font_size must be 0.015–0.15 of its height.")}
        _ = try overlayColor(color ?? "#FFFFFF"); _ = try overlayColor(background ?? "#000000B3")
    }
}
struct EndCard: Codable {
    var transition:Double? = nil
    var duration:Double
    var text:String? = nil
    var filename:String? = nil
    var background:String? = nil
}
func overlayColor(_ s:String) throws -> NSColor {
    let hex=s.hasPrefix("#") ? String(s.dropFirst()) : ""
    guard [6,8].contains(hex.count),let v=UInt64(hex,radix:16) else {throw WeaverError("Use #RRGGBB or #RRGGBBAA for overlay colors.")}
    let n=hex.count==6 ? (v<<8)|255:v
    return NSColor(srgbRed:Double((n>>24)&255)/255,green:Double((n>>16)&255)/255,blue:Double((n>>8)&255)/255,alpha:Double(n&255)/255)
}
func checkedImage(_ url:URL) throws -> NSImage {
    guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any],let w=props[kCGImagePropertyPixelWidth as String] as? Int,let h=props[kCGImagePropertyPixelHeight as String] as? Int,w>0,h>0,w<=8192,h<=8192,w*h<=32_000_000,let cg=CGImageSourceCreateImageAtIndex(source,0,nil) else {throw WeaverError("Image is unreadable or too large: \(url.lastPathComponent). Use PNG/JPEG up to 8192 pixels per side and 32 megapixels.")}
    return NSImage(cgImage:cg,size:NSSize(width:w,height:h))
}
func overlayPNG(_ o:TextOverlay,width:Int,height:Int,assets:URL?,output:URL,canvas:String? = nil) throws {
    guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let ctx=NSGraphicsContext(bitmapImageRep:rep) else {throw WeaverError("Could not render overlay.")}
    NSGraphicsContext.saveGraphicsState();defer{NSGraphicsContext.restoreGraphicsState()};NSGraphicsContext.current=ctx
    NSColor.clear.setFill();NSRect(x:0,y:0,width:width,height:height).fill(using:.copy)
    if let canvas {try overlayColor(canvas).setFill();NSRect(x:0,y:0,width:width,height:height).fill()}
    let rect=NSRect(x:(o.x ?? 0.1)*Double(width),y:(1-(o.y ?? 0.72)-(o.height ?? 0.18))*Double(height),width:(o.width ?? 0.8)*Double(width),height:(o.height ?? 0.18)*Double(height))
    if let name=o.filename {
        guard let assets else {throw WeaverError("Import the complete AI response to supply \(name).")}
        let im=try checkedImage(assets.appendingPathComponent(name));let scale=min(rect.width/im.size.width,rect.height/im.size.height)
        let size=NSSize(width:im.size.width*scale,height:im.size.height*scale)
        im.draw(in:NSRect(x:rect.midX-size.width/2,y:rect.midY-size.height/2,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1)
    } else if let text=o.text {
        let padding=Double(height)*0.012;let box=rect.insetBy(dx:padding,dy:padding)
        let paragraph=NSMutableParagraphStyle();paragraph.alignment=o.alignment=="left" ? .left:(o.alignment=="right" ? .right:.center);paragraph.lineBreakMode = .byWordWrapping
        var size=(o.fontSize ?? 0.05)*Double(height)
        var attrs:[NSAttributedString.Key:Any]=[:];var bounds=NSRect.zero
        repeat {
            attrs=[.font:NSFont.systemFont(ofSize:size,weight:.bold),.foregroundColor:try overlayColor(o.color ?? "#FFFFFF"),.paragraphStyle:paragraph]
            bounds=(text as NSString).boundingRect(with:NSSize(width:box.width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attrs)
            if bounds.height<=box.height && bounds.width<=box.width+1 {break};size-=1
        } while size>=max(8,Double(height)*0.015)
        guard bounds.height<=box.height+1 else {throw WeaverError("Overlay wording does not fit. Shorten it or increase its height.")}
        try overlayColor(o.background ?? "#000000B3").setFill();NSBezierPath(roundedRect:rect,xRadius:padding,yRadius:padding).fill()
        (text as NSString).draw(with:NSRect(x:box.minX,y:box.midY-bounds.height/2,width:box.width,height:bounds.height),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attrs)
    }
    guard let data=rep.representation(using:.png,properties:[:]) else {throw WeaverError("Could not save overlay.")};try data.write(to:output)
}
