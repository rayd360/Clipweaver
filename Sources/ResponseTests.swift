import Foundation
import AppKit
import CryptoKit

func runResponseTests(engine:Engine,project:Project,base:URL) throws {
    func check(_ ok:Bool,_ message:String) throws {if !ok {throw WeaverError("V2 TEST: \(message)")}}
    let root=base.appendingPathComponent("Managed project"),job=JobControl()
    try prepareProjectFolders(root);var p=project;try p.save(root)
    let graphic=root.appendingPathComponent("test-logo.png")
    try overlayPNG(TextOverlay(start:0,end:1,text:"CW",x:0,y:0,width:1,height:1,fontSize:0.15,background:"#00FF00"),width:160,height:90,assets:nil,output:graphic,canvas:"#00FF00")
    let music=URL(fileURLWithPath:project.musicPath!)
    func asset(_ url:URL) throws -> ResponseAsset {let d=try Data(contentsOf:url);return ResponseAsset(filename:url.lastPathComponent,sha256:SHA256.hash(data:d).map{String(format:"%02x",$0)}.joined(),base64:d.base64EncodedString())}
    let edit=EditPlan(schemaVersion:2,projectId:p.projectId,title:"Packaged overlay test",fps:"source",clips:[EditClip(sourceId:p.sources[0].id,start:0,end:1,volume:0)],music:MusicPlan(filename:music.lastPathComponent,volume:0.2,loop:true),overlays:[TextOverlay(start:0.125,end:0.5,text:"Let's party! \"Hello\"",x:0.1,y:0.1,width:0.8,height:0.2,fontSize:0.05,background:"#0000FF"),TextOverlay(start:0.5,end:0.875,filename:graphic.lastPathComponent,x:0.4,y:0.4,width:0.3,height:0.3)],endCard:EndCard(duration:1,text:"CLIPWEAVER\nTEST CARD"))
    let bundle=root.appendingPathComponent("Incoming/Test.clipweaveredit")
    try writeJSON(AIResponse(packageVersion:1,edit:edit,assets:[try asset(music),try asset(graphic)]),bundle)
    (p,_) = try engine.importResponse(bundle,project:p,root:root,job:job)
    try check(!(p.lastEditPath ?? "").hasPrefix("/") && !(p.musicPath ?? "").hasPrefix("/"),"Managed assets must use relative paths")
    let originalPath=p.lastEditPath
    let again=try engine.importResponse(bundle,project:p,root:root,job:job)
    try check(again.0.lastEditPath==originalPath,"Identical response created a duplicate revision")
    let output=try engine.render(edit,project:p,root:root,settings:ExportSettings(kind:.preview),job:job,progress:{_,_ in})
    let info=try probe(output,tools:engine.tools)
    try check(abs(info.duration-2)<0.05 && info.fpsValue==24,"Overlay/end card changed duration or source fps")
    func pixel(_ time:Double,_ x:Int,_ y:Int) throws -> [UInt8] {
        Array(try engine.tools.run("ffmpeg",["-v","error","-ss",num(time),"-i",output.path,"-frames:v","1","-vf","crop=2:2:\(x):\(y),scale=1:1","-pix_fmt","rgb24","-f","rawvideo","pipe:1"]))
    }
    let before=try pixel(0.04,40,24),during=try pixel(0.25,40,24),after=try pixel(0.65,40,24),logo=try pixel(0.65,140,82),card=try pixel(1.5,5,5)
    try check(before.count==3 && before[0]>150 && before[2]<70,"Unexpected baseline")
    try check(during.count==3 && during[2]>150 && during[0]<90,"Text background did not appear at correct position/time")
    try check(after[0]>150 && after[2]<70,"Text did not end at requested time")
    try check(logo[1]>120 && logo[0]<90,"Packaged PNG not visible")
    try check(card.max()!<50,"End card did not replace final footage")
    let moved=base.appendingPathComponent("Moved managed project");try fm.copyItem(at:root,to:moved)
    let restored=try Project.open(moved).0
    try check(fm.fileExists(atPath:projectFile(restored.musicPath!,root:moved).path),"Moved project lost music")
    _ = try engine.render(edit,project:restored,root:moved,settings:ExportSettings(kind:.website,mute:true),job:job,progress:{_,_ in})
    let validState=try Data(contentsOf:root.appendingPathComponent("Project.clipweaver"))
    var broken=try AIResponse.load(bundle);broken.assets[0].sha256="bad"
    let bad=root.appendingPathComponent("bad.clipweaveredit");try writeJSON(broken,bad)
    do {_ = try engine.importResponse(bad,project:p,root:root,job:job);throw WeaverError("accepted damaged asset")}catch {try check(error.localizedDescription != "accepted damaged asset","Damaged asset accepted")}
    try check(try Data(contentsOf:root.appendingPathComponent("Project.clipweaver"))==validState,"Failed import changed active project")
    broken=try AIResponse.load(bundle);broken.assets[0].filename="../escape.m4a";try writeJSON(broken,bad)
    do {_ = try engine.importResponse(bad,project:p,root:root,job:job);throw WeaverError("accepted path traversal")}catch {try check(error.localizedDescription != "accepted path traversal","Unsafe asset path accepted")}
    broken=try AIResponse.load(bundle);broken.assets=[];try writeJSON(broken,bad)
    do {_ = try engine.importResponse(bad,project:p,root:root,job:job);throw WeaverError("accepted missing assets")}catch {try check(error.localizedDescription != "accepted missing assets","Missing assets accepted")}
    print("PASS: single response import, embedded music/PNG, timed text appearance/removal, end card, source fps, relocation, duplicate detection, transactional invalid imports")
}
