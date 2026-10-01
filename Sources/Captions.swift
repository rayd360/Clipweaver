import Foundation
import AppKit
import Darwin

struct CaptionEntrance: Codable {
    var type:String = "none"
    var direction:String? = nil
    var duration:Double? = nil
    var distance:Double? = nil
    func validate(visible:Double) throws {
        guard ["none","fade","slide"].contains(type) else {throw WeaverError("Caption entrance must be none, fade or slide.")}
        if type=="none" {guard direction==nil,duration==nil,distance==nil else {throw WeaverError("A none entrance cannot have motion settings.")};return}
        let d=duration ?? 0.25
        guard d.isFinite,(0.05...0.8).contains(d),d<=visible else {throw WeaverError("Entrance duration must be 0.05–0.8 seconds and fit the word's visible time.")}
        if type=="fade" {guard direction==nil,distance==nil else {throw WeaverError("A fade entrance cannot have a slide direction or distance.")}}
        if type=="slide" {guard ["left","right","up","down"].contains(direction ?? "up"),(distance ?? 0.025).isFinite,(0.005...0.08).contains(distance ?? 0.025) else {throw WeaverError("Slide direction must be left/right/up/down; distance must be 0.005–0.08 of the frame.")}}
    }
}
struct CaptionStyle: Codable {
    var fontSize:Double? = nil
    var emphasisScale:Double? = nil
    var emphasisColor:String? = nil
    var contrastBacking:Bool? = nil
    var entrance:CaptionEntrance? = nil
    var size:Double {fontSize ?? 0.052}
    var scale:Double {emphasisScale ?? 1.45}
    var tint:String {emphasisColor ?? "#363B43"}
    func validate() throws {
        guard size.isFinite,(0.018...0.07).contains(size),scale.isFinite,(1.1...1.6).contains(scale),size*scale<=0.10,["#30343B","#363B43","#464B52","#E8E9EC"].contains(tint.uppercased()) else {throw WeaverError("Caption style uses an invalid size, emphasis scale or charcoal tint.")}
        try entrance?.validate(visible:3600)
    }
}
struct CaptionWord: Codable {
    var text:String
    var start:Double
    var end:Double
    var style:String? = nil
    var fontSize:Double? = nil
    var x:Double? = nil
    var y:Double? = nil
    var lineBreakBefore:Bool? = nil
    var entrance:CaptionEntrance? = nil
}
struct Caption: Codable {
    var style:String? = nil
    var x:Double? = nil
    var y:Double? = nil
    var width:Double? = nil
    var height:Double? = nil
    var alignment:String? = nil
    var words:[CaptionWord]
}
struct LogoPlacement: Codable {
    var start:Double
    var end:Double
    var x:Double
    var y:Double
    var width:Double
    var height:Double
    var opacity:Double? = nil
}
let captionSafe=NSRect(x:0.08,y:0.12,width:0.78,height:0.68)
func safeVisualBox(_ x:Double,_ y:Double,_ w:Double,_ h:Double) -> Bool {
    [x,y,w,h].allSatisfy(\.isFinite) && w>0 && h>0 && x>=captionSafe.minX-0.000001 && y>=captionSafe.minY-0.000001 && x+w<=captionSafe.maxX+0.000001 && y+h<=captionSafe.maxY+0.000001
}
extension EditPlan {
    func validateCaptions() throws {
        guard (captionStyles?.count ?? 0)<=12,(captions?.count ?? 0)<=80,(captions ?? []).reduce(0,{$0+$1.words.count})<=400,(logoPlacements?.count ?? 0)<=30 else {throw WeaverError("Use at most 12 caption styles, 80 captions, 400 words/segments and 30 logo placements.")}
        for (key,style) in captionStyles ?? [:] {guard !key.isEmpty,key.count<=40 else{throw WeaverError("Caption style names must be 1–40 characters.")};try style.validate()}
        var intervals:[(Double,Int)]=[]
        for c in captions ?? [] {
            if let key=c.style,captionStyles?[key]==nil {throw WeaverError("Unknown caption style: \(key)")}
            let preset=c.style.flatMap{captionStyles?[$0]} ?? CaptionStyle()
            guard !c.words.isEmpty,c.words.count<=60,safeVisualBox(c.x ?? 0.1,c.y ?? 0.36,c.width ?? 0.76,c.height ?? 0.32),["left","center","right"].contains(c.alignment ?? "center") else {throw WeaverError("Caption box must stay in the social safe area: x 0.08–0.86, y 0.12–0.80, with 1–60 words/segments.")}
            for word in c.words {
                guard !word.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,word.text.count<=80,!word.text.contains("\n"),!word.text.contains("\r"),word.start.isFinite,word.end.isFinite,word.start>=0,word.end>word.start,word.end<=duration+0.002,["normal","emphasis"].contains(word.style ?? "normal") else {throw WeaverError("Each caption word/segment needs 1–80 characters, normal/emphasis style, and valid finished-video seconds. Use line_break_before for line breaks.")}
                let size=word.fontSize ?? preset.size*(word.style=="emphasis" ? preset.scale:1)
                guard size.isFinite,(0.018...0.10).contains(size),(word.x==nil)==(word.y==nil) else {throw WeaverError("Word font_size must be 0.018–0.10; supply both x and y for explicit placement.")}
                if word.style=="emphasis",size<=preset.size {throw WeaverError("Emphasized words must be larger than the style’s ordinary words.")}
                if let x=word.x,let y=word.y {guard x.isFinite,y.isFinite,x>=captionSafe.minX,x<captionSafe.maxX,y>=captionSafe.minY,y<captionSafe.maxY else {throw WeaverError("Word placement is outside the social safe area.")}}
                try (word.entrance ?? preset.entrance ?? CaptionEntrance()).validate(visible:word.end-word.start)
                intervals += [(word.start,1),(word.end,-1)]
            }
        }
        var active=0
        for event in intervals.sorted(by:{$0.0==$1.0 ? $0.1<$1.1:$0.0<$1.0}) {active+=event.1;guard active<=80 else{throw WeaverError("At most 80 caption words/segments can be visible at once.")}}
        for l in logoPlacements ?? [] {guard l.start.isFinite,l.end.isFinite,l.start>=0,l.end>l.start,l.end<=duration+0.002,safeVisualBox(l.x,l.y,l.width,l.height),(l.opacity ?? 1).isFinite,(0...1).contains(l.opacity ?? 1) else {throw WeaverError("Logo timing, opacity or position is invalid. Keep it inside the social safe area.")}}
        let all=(captions ?? []).flatMap{$0.words.map{($0.start,$0.end)}}+(logoPlacements ?? []).map{($0.start,$0.end)}
        if let start=all.map({$0.0}).min(),let end=all.map({$0.1}).max() {guard end-start<=600 else{throw WeaverError("Animated caption/logo span is limited to ten minutes per edit.")}}
    }
}
struct CaptionSprite {
    var image:CGImage
    var rect:NSRect // top-left coordinates in output pixels
    var start:Double
    var end:Double
    var opacity:Double
    var entrance:CaptionEntrance
}
func captionWordImage(_ word:CaptionWord,preset:CaptionStyle,height:Int) throws -> (CGImage,Double,Double) {
    let emphasis=word.style=="emphasis"
    let size=(word.fontSize ?? preset.size*(emphasis ? preset.scale:1))*Double(height)
    let font=NSFont(name:emphasis ? "HelveticaNeue-BoldItalic":"HelveticaNeue",size:size) ?? NSFont.systemFont(ofSize:size,weight:emphasis ? .heavy:.regular)
    let stroke=max(0.8,Double(height)*0.0009),pad=ceil(size*0.20+stroke*2)
    let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.32);shadow.shadowBlurRadius=size*0.07;shadow.shadowOffset=NSSize(width:0,height:-size*0.025)
    let attrs:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:try overlayColor(emphasis ? preset.tint:"#FFFFFF"),.shadow:shadow]
    let text=word.text as NSString
    let extent=text.size(withAttributes:attrs)
    let w=Int(ceil(extent.width+2*pad)),h=Int(ceil(font.ascender-font.descender+2*pad))
    guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:bitmap) else {throw WeaverError("Cannot draw caption text.")}
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
    NSColor.clear.setFill();NSRect(x:0,y:0,width:w,height:h).fill(using:.copy)
    // Solid lettering instead of the old hollow-looking outline. A restrained
    // backing gives dark emphasis enough contrast on busy or dark footage.
    if emphasis,preset.contrastBacking ?? (preset.tint.uppercased() != "#E8E9EC") {
        NSColor(calibratedWhite:0.97,alpha:0.94).setFill()
        NSBezierPath(roundedRect:NSRect(x:pad-size*0.09,y:pad-size*0.02,width:extent.width+size*0.18,height:font.ascender-font.descender+size*0.02),xRadius:size*0.10,yRadius:size*0.10).fill()
    }
    text.draw(at:NSPoint(x:pad,y:pad),withAttributes:attrs)
    NSGraphicsContext.restoreGraphicsState()
    guard let image=bitmap.cgImage else{throw WeaverError("Cannot rasterize caption text.")}
    return (image,pad,font.ascender-font.descender)
}
func captionSprites(_ plan:EditPlan,width:Int,height:Int,logoURL:URL?,includeLogo:Bool) throws -> [CaptionSprite] {
    var sprites:[CaptionSprite]=[];let W=Double(width),H=Double(height)
    for caption in plan.captions ?? [] {
        let preset=caption.style.flatMap{plan.captionStyles?[$0]} ?? CaptionStyle()
        let box=NSRect(x:(caption.x ?? 0.1)*W,y:(caption.y ?? 0.36)*H,width:(caption.width ?? 0.76)*W,height:(caption.height ?? 0.32)*H)
        struct Item {var word:CaptionWord;var image:CGImage;var pad:Double;var height:Double;var advance:Double}
        // Preserve segment timing and style while allowing phrases to wrap at spaces.
        let words=caption.words.flatMap {word -> [CaptionWord] in
            if word.x != nil {return [word]}
            return word.text.split(whereSeparator: {$0.isWhitespace}).enumerated().map {index,text in
                var w=word;w.text=String(text);if index>0 {w.lineBreakBefore=false};return w
            }
        }
        var fit=1.0
        var items:[Item]=[]
        for _ in 0..<80 {
            items=try words.map {word -> Item in
                var sized=word;sized.fontSize=(word.fontSize ?? preset.size*(word.style=="emphasis" ? preset.scale:1))*fit
                let (im,pad,h)=try captionWordImage(sized,preset:preset,height:height)
                return Item(word:word,image:im,pad:pad,height:h,advance:Double(im.width)-2*pad)
            }
            let gap=preset.size*H*0.25*fit
            var used=0.0,lineH=0.0,totalH=0.0,overflow=false
            for item in items {
                if item.word.x != nil {continue}
                if item.advance>box.width {overflow=true}
                if used>0 && (item.word.lineBreakBefore==true || used+gap+item.advance>box.width) {totalH+=lineH+preset.size*H*0.18*fit;used=0;lineH=0}
                used+=(used>0 ? gap:0)+item.advance;lineH=max(lineH,item.height)
            }
            if !overflow && totalH+lineH<=box.height {break}
            fit*=0.92
        }
        var lines:[[Item]]=[[]];var lineWidth=0.0
        let gap=preset.size*H*0.25*fit
        for item in items {
            if let x=item.word.x,let y=item.word.y {
                sprites.append(CaptionSprite(image:item.image,rect:NSRect(x:x*W-item.pad,y:y*H-item.pad,width:Double(item.image.width),height:Double(item.image.height)),start:item.word.start,end:item.word.end,opacity:1,entrance:item.word.entrance ?? preset.entrance ?? CaptionEntrance()));continue
            }
            guard item.advance<=box.width else{throw WeaverError("Caption segment is wider than its box. Split it into words or reduce font_size.")}
            if !lines[lines.count-1].isEmpty && (item.word.lineBreakBefore==true || lineWidth+gap+item.advance>box.width) {lines.append([]);lineWidth=0}
            if lineWidth>0 {lineWidth+=gap};lineWidth+=item.advance;lines[lines.count-1].append(item)
        }
        var y=box.minY
        for line in lines where !line.isEmpty {
            let h=line.map(\.height).max() ?? 0
            let lineW=line.reduce(0,{$0+$1.advance})+gap*Double(line.count-1)
            var x=box.minX+(caption.alignment=="left" ? 0:(caption.alignment=="right" ? box.width-lineW:(box.width-lineW)/2))
            guard y+h<=box.maxY+0.01 else{throw WeaverError("Caption has too many lines for its box. Increase height, reduce size or split the caption.")}
            for item in line {
                sprites.append(CaptionSprite(image:item.image,rect:NSRect(x:x-item.pad,y:y+h-item.height-item.pad,width:Double(item.image.width),height:Double(item.image.height)),start:item.word.start,end:item.word.end,opacity:1,entrance:item.word.entrance ?? preset.entrance ?? CaptionEntrance()));x+=item.advance+gap
            }
            y+=h+preset.size*H*0.18*fit
        }
    }
    if includeLogo,!(plan.logoPlacements ?? []).isEmpty {
        guard let logoURL else{throw WeaverError("This edit requests your Project Logo. Choose a logo, or turn it off for this edit.")}
        let image=try checkedImage(logoURL);var rect=NSRect(origin:.zero,size:image.size)
        guard let cg=image.cgImage(forProposedRect:&rect,context:nil,hints:nil) else{throw WeaverError("Project logo cannot be decoded.")}
        for l in plan.logoPlacements ?? [] {
            let scale=min(l.width*W/Double(cg.width),l.height*H/Double(cg.height)),w=Double(cg.width)*scale,h=Double(cg.height)*scale
            sprites.append(CaptionSprite(image:cg,rect:NSRect(x:l.x*W+(l.width*W-w)/2,y:l.y*H+(l.height*H-h)/2,width:w,height:h),start:l.start,end:l.end,opacity:l.opacity ?? 1,entrance:CaptionEntrance()))
        }
    }
    let safe=NSRect(x:captionSafe.minX*W,y:captionSafe.minY*H,width:captionSafe.width*W,height:captionSafe.height*H)
    var pixels=0
    for index in sprites.indices {
        var s=sprites[index]
        // Padding protects italic overhang; enforce the complete sprite plus its entrance path.
        let tolerance=H*0.025
        var bounds=s.rect
        if s.entrance.type=="slide" {
            let horizontal=["left","right"].contains(s.entrance.direction ?? "up"),d=(s.entrance.distance ?? 0.025)*(horizontal ? W:H)
            var initial=s.rect
            switch s.entrance.direction ?? "up" {case "left":initial.origin.x-=d;case "right":initial.origin.x+=d;case "down":initial.origin.y+=d;default:initial.origin.y-=d}
            bounds=bounds.union(initial)
        }
        let available=safe.insetBy(dx:-tolerance,dy:-tolerance)
        if bounds.width>available.width || bounds.height>available.height {
            let scale=min(available.width/bounds.width,available.height/bounds.height)
            s.rect.size.width*=scale;s.rect.size.height*=scale
            s.entrance=CaptionEntrance(type:"fade",duration:min(0.25,s.end-s.start));bounds=s.rect
        }
        s.rect.origin.x+=max(0,available.minX-bounds.minX)-max(0,bounds.maxX-available.maxX)
        s.rect.origin.y+=max(0,available.minY-bounds.minY)-max(0,bounds.maxY-available.maxY)
        sprites[index]=s
        pixels+=s.image.width*s.image.height
    }
    guard pixels<=64_000_000 else{throw WeaverError("Caption artwork is too large. Reduce the number or size of text segments.")}
    return sprites
}
struct CaptionLayer {var url:URL;var start:Double;var duration:Double}
extension Engine {
    func makeCaptionLayer(_ plan:EditPlan,width:Int,height:Int,fps:String,logoURL:URL?,includeLogo:Bool,folder:URL,job:JobControl,progress:ProgressReport) throws -> CaptionLayer? {
        let sprites=try captionSprites(plan,width:width,height:height,logoURL:logoURL,includeLogo:includeLogo)
        guard !sprites.isEmpty else{return nil}
        let rate=rateValue(fps),start=floor(sprites.map(\.start).min()!*rate)/rate,end=ceil(sprites.map(\.end).max()!*rate)/rate
        let count=Int(((end-start)*rate).rounded()),url=folder.appendingPathComponent("captions.mov")
        signal(SIGPIPE,SIG_IGN)
        let process=Process();process.executableURL=tools.root.appendingPathComponent("ffmpeg")
        process.arguments=["-v","error","-nostdin","-y","-threads","2","-f","rawvideo","-pixel_format","bgra","-video_size","\(width)x\(height)","-framerate",fps,"-i","pipe:0","-an","-c:v","qtrle","-pix_fmt","argb",url.path]
        let pipe=Pipe();process.standardInput=pipe;process.standardOutput=FileHandle.nullDevice
        let log=folder.appendingPathComponent("caption-encode.log");fm.createFile(atPath:log.path,contents:nil);let errors=try FileHandle(forWritingTo:log);process.standardError=errors
        try job.attach(process);defer{job.detach();try? pipe.fileHandleForWriting.close();try? errors.close();if process.isRunning {process.terminate();process.waitUntilExit()}}
        try process.run();job.launched(process)
        let bytes=width*height*4;let memory=UnsafeMutableRawPointer.allocate(byteCount:bytes,alignment:64);defer{memory.deallocate()}
        guard let ctx=CGContext(data:memory,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue|CGBitmapInfo.byteOrder32Little.rawValue) else{throw WeaverError("Cannot create animation canvas.")}
        ctx.interpolationQuality = .high
        for frame in 0..<count {
            try job.check();memset(memory,0,bytes)
            let time=start+Double(frame)/rate
            for sprite in sprites where time+0.0000001>=sprite.start && time<sprite.end-0.0000001 {
                var rect=sprite.rect;var alpha=sprite.opacity
                let entrance=sprite.entrance
                let p=min(1,max(0,(time-sprite.start)/(entrance.duration ?? 0.25)))
                if entrance.type=="fade" {alpha*=p}
                if entrance.type=="slide" {
                    alpha*=p
                    let remaining=pow(1-p,3),d=(entrance.distance ?? 0.025)*remaining
                    switch entrance.direction ?? "up" {case "left":rect.origin.x-=d*Double(width);case "right":rect.origin.x+=d*Double(width);case "down":rect.origin.y+=d*Double(height);default:rect.origin.y-=d*Double(height)}
                }
                ctx.saveGState();ctx.setAlpha(alpha)
                ctx.draw(sprite.image,in:NSRect(x:rect.minX,y:Double(height)-rect.maxY,width:rect.width,height:rect.height));ctx.restoreGState()
            }
            // Encode straight alpha explicitly so FFmpeg's RGB conversions cannot
            // apply the premultiplication a second time to translucent logos.
            let rgba=memory.assumingMemoryBound(to:UInt8.self)
            for i in stride(from:0,to:bytes,by:4) {
                let a=Int(rgba[i+3])
                if a>0 && a<255 {for c in 0..<3 {rgba[i+c]=UInt8(min(255,(Int(rgba[i+c])*255+a/2)/a))}}
            }
            do {try pipe.fileHandleForWriting.write(contentsOf:Data(bytesNoCopy:memory,count:bytes,deallocator:.none))}
            catch {throw WeaverError("Caption animation could not be encoded. \((try? String(contentsOf:log,encoding:.utf8)) ?? error.localizedDescription)")}
            if frame % max(1,Int(rate))==0 {progress("Drawing captions and logo at export resolution",0.17+0.02*Double(frame)/Double(count))}
        }
        try pipe.fileHandleForWriting.close();process.waitUntilExit();try job.check()
        guard process.terminationStatus==0 else{throw WeaverError("Caption renderer failed: \((try? String(contentsOf:log,encoding:.utf8)) ?? "Unknown encoding error")")}
        return CaptionLayer(url:url,start:start,duration:end-start)
    }
}
