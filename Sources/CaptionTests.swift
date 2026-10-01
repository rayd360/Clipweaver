import AppKit
import Foundation

func runCaptionTests(base:URL) throws {
    setenv("CLIPWEAVER_GLOBAL",base.appendingPathComponent("Isolated Global").path,1)
    let engine=Engine(tools:try Toolchain.locate()),job=JobControl()
    func check(_ ok:Bool,_ text:String) throws {if !ok {throw WeaverError("CAPTION TEST: \(text)")}}
    func report(_ text:String,_ progress:Double) {print(text);fflush(stdout)}
    try fm.createDirectory(at:base,withIntermediateDirectories:true)
    let original=base.appendingPathComponent("gray-original.mp4")
    try engine.tools.ffmpeg(["-f","lavfi","-i","color=gray:s=360x640:r=24:d=3.5","-c:v","libx264","-crf","10",original.path],job:job)
    let root=base.appendingPathComponent("Caption Test Project");try prepareProjectFolders(root)
    var project=try engine.add([original],project:Project(name:"Caption & Logo Tests"),job:job,progress:report)
    let logo=base.appendingPathComponent("test-logo.png")
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:200,pixelsHigh:100,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    NSColor.clear.setFill();NSRect(x:0,y:0,width:200,height:100).fill(using:.copy);NSColor.red.setFill();NSBezierPath(ovalIn:NSRect(x:50,y:0,width:100,height:100)).fill();NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using:.png,properties:[:])!.write(to:logo)
    project.logoPath=try saveProjectLogo(logo,root:root);project.includeLogoInReview=true;try project.save(root)
    let style=CaptionStyle(fontSize:0.04,emphasisScale:1.3,entrance:CaptionEntrance())
    let caption=Caption(style:"social",x:0.12,y:0.3,width:0.70,height:0.3,alignment:"left",words:[CaptionWord(text:"Good",start:0.25,end:1.7),CaptionWord(text:"energy.",start:0.5,end:1.7,style:"emphasis",entrance:CaptionEntrance(type:"slide",direction:"down",duration:0.3,distance:0.035))])
    let second=Caption(style:"social",x:0.12,y:0.3,width:0.70,height:0.3,alignment:"left",words:[CaptionWord(text:"Here",start:2,end:3.2,entrance:CaptionEntrance(type:"fade",duration:0.25)),CaptionWord(text:"together.",start:2.3,end:3.2,style:"emphasis",lineBreakBefore:true)])
    let edit=EditPlan(schemaVersion:3,projectId:project.projectId,title:"Word captions and project logo",aspect:"portrait",fps:"source",clips:[EditClip(sourceId:project.sources[0].id,start:0,end:3.5)],captionStyles:["social":style],captions:[caption,second],logoPlacements:[LogoPlacement(start:0.8,end:3.2,x:0.64,y:0.66,width:0.16,height:0.08,opacity:0.5)])
    try edit.validate(project)
    let package=root.appendingPathComponent("Incoming/Test.clipweaveredit");try writeJSON(AIResponse(packageVersion:1,edit:edit,assets:[]),package)
    let found=try engine.findIncoming(project:project,root:root,job:job);try check(found != nil && found!.imported==false,"Incoming response wasn't discovered immediately")
    (project,_) = try engine.importResponse(package,project:project,root:root,job:job)
    try check(try engine.findIncoming(project:project,root:root,job:job)?.imported==true,"Duplicate response wasn't recognized")
    let output=try engine.render(edit,project:project,root:root,settings:ExportSettings(kind:.preview),job:job,progress:report)
    let info=try probe(output,tools:engine.tools);try check(info.fpsValue==24 && abs(info.duration-3.5)<0.05,"Captions changed source frame rate or length")
    func frame(_ t:Double,_ file:URL?=nil) throws -> [UInt8] {Array(try engine.tools.run("ffmpeg",["-v","error","-ss",num(t),"-i",(file ?? output).path,"-frames:v","1","-pix_fmt","rgb24","-f","rawvideo","pipe:1"]))}
    func pixel(_ pixels:[UInt8],_ x:Int,_ y:Int) -> [Int] {let i=(y*360+x)*3;return (0..<3).map{Int(pixels[i+$0])}}
    let blank=try frame(0.1),normal=try frame(0.4),both=try frame(1),gap=try frame(1.8),fade=try frame(2.08),settled=try frame(2.7),ended=try frame(3.3)
    try check(blank.count==360*640*3,"Invalid decoded frame")
    let textRegion=(175..<310).flatMap {y in (35..<315).map{x in (y*360+x)*3}}
    func whiteCount(_ pixels:[UInt8]) -> Int {textRegion.filter{pixels[$0]>220 && pixels[$0+1]>220 && pixels[$0+2]>220}.count}
    try check(whiteCount(blank)==0 && whiteCount(normal)>80,"Ordinary white words didn't begin at requested time")
    try check(textRegion.filter{both[$0]<100 && both[$0+1]<105 && both[$0+2]<115}.count>100,"Charcoal emphasis didn't render")
    try check(whiteCount(gap)==0 && whiteCount(ended)==0,"Words remained after end time")
    try check(whiteCount(fade)<whiteCount(settled),"Fade did not increase opacity")
    let center=pixel(both,259,448),transparent=pixel(both,232,425)
    try check(center[0]>165 && center[1]<100,"Logo opacity/compositing failed")
    try check(abs(transparent[0]-transparent[1])<8,"Transparent logo margins filled the video")
    let off=try engine.render(edit,project:project,root:root,settings:ExportSettings(kind:.website,mute:true,includeLogo:false),job:job,progress:report)
    let noLogo=try frame(1,off);let noCenter=pixel(noLogo,259,448)
    try check(abs(noCenter[0]-noCenter[1])<8,"Logo off switch failed")
    _ = try engine.render(edit,project:project,root:root,settings:ExportSettings(kind:.social),job:job,progress:report)
    let review=try engine.prepare(project,root:root,preset:.small,job:job,progress:report)
    let manifest=try readJSON(ReviewManifest.self,review.appendingPathComponent("manifest.json"))
    try check(manifest.projectLogo != nil && fm.fileExists(atPath:review.appendingPathComponent(manifest.projectLogo!.file).path),"Requested logo missing from AI review")
    _ = try engine.packReview(review,root:root,job:job)
    var invalid=edit;invalid.captions![0].words[0].entrance=CaptionEntrance(type:"spin")
    do {try invalid.validate(project);throw WeaverError("accepted spin")}catch{try check(error.localizedDescription != "accepted spin","Uncontrolled animation accepted")}
    invalid=edit;invalid.captions![0].x=0.99
    do {try invalid.validate(project);throw WeaverError("accepted unsafe box")}catch{try check(error.localizedDescription != "accepted unsafe box","Unsafe positioning accepted")}
    let oldState=try Data(contentsOf:root.appendingPathComponent("Project.clipweaver"))
    let broken=root.appendingPathComponent("Incoming/Broken.clipweaveredit");try Data("{broken".utf8).write(to:broken)
    do {_ = try engine.findIncoming(project:project,root:root,job:job);throw WeaverError("accepted broken response")}catch{try check(error.localizedDescription != "accepted broken response","Damaged Incoming response accepted")}
    try check(try Data(contentsOf:root.appendingPathComponent("Project.clipweaver"))==oldState,"Damaged response replaced active edit")
    try fm.moveItem(at:broken,to:base.appendingPathComponent("Broken-response-test.clipweaveredit"))
    let moved=base.appendingPathComponent("Relocated Caption Project");try fm.copyItem(at:root,to:moved)
    let relocated=try Project.open(moved).0;try check(fm.fileExists(atPath:projectFile(relocated.logoPath!,root:moved).path),"Moving project lost its logo")
    for t in [0.1,0.4,0.55,0.65,0.9,1.8,2.1,2.7,3.3] {try engine.tools.ffmpeg(["-ss",num(t),"-i",output.path,"-frames:v","1",base.appendingPathComponent("caption-\(t).png").path],job:job)}
    try check(try fingerprint(original,job:job)==project.sources[0].sha256,"Original was changed")
    print("CAPTION TESTS PASSED: white/charcoal mixed styling, timing, fade, logo opacity/transparency/off switch, all exports, review inclusion, incoming deduplication/errors, relocation, originals unchanged")
}
