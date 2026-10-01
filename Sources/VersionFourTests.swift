import Foundation
func runVersionFourTests(_ base:URL)throws {
    setenv("CLIPWEAVER_GLOBAL",base.appendingPathComponent("Global").path,1)
    try fm.createDirectory(at:base,withIntermediateDirectories:true)
    let engine=Engine(tools:try Toolchain.locate()),job=JobControl()
    let report:ProgressReport={text,_ in print(text);fflush(stdout)}
    func check(_ ok:Bool,_ why:String)throws {if !ok {throw WeaverError(why)}}
    var urls:[URL]=[]
    for (i,color) in ["red","blue","green"].enumerated() {
        let url=base.appendingPathComponent("original-\(i).mp4")
        try engine.tools.ffmpeg(["-f","lavfi","-i","color=\(color):s=360x640:r=24:d=4","-f","lavfi","-i","sine=frequency=\(440+i*100):duration=4","-c:v","libx264","-preset","fast","-crf","18","-c:a","aac","-shortest",url.path],job:job);urls.append(url)
    }
    let root=base.appendingPathComponent("Project");try prepareProjectFolders(root)
    var p=try engine.add(urls,project:Project(name:"Combined Test",createdAt:Date()),job:job,progress:report);try p.save(root)
    let review=try engine.prepare(p,root:root,preset:.small,job:job,progress:report)
    p=try Project.open(root).0
    let manifest=try readJSON(ReviewManifest.self,review.appendingPathComponent("manifest.json"))
    try check(manifest.sources.count==1 && manifest.sources[0].id.hasPrefix("COMBINED_"),"Matching footage wasn't combined")
    try check(manifest.combinedParts?.count==3,"Missing long-timeline map")
    let master=p.combinedMasters![0]
    try check(abs(master.source.media.duration-12)<0.05,"Master duration wrong")
    try check(try probe(review.appendingPathComponent(manifest.sources[0].reviewVideo),tools:engine.tools).fpsValue==8,"Review fps wrong")
    let edit=EditPlan(schemaVersion:4,projectId:p.projectId,title:"Uniform dissolves",fps:"source",clips:[EditClip(sourceId:master.source.id,start:0.2,end:2.7),EditClip(sourceId:master.source.id,start:4.2,end:6.7,transition:0.6)],transitionStyle:"cross_dissolve")
    try edit.validate(p)
    let output=try engine.render(edit,project:p,root:root,settings:ExportSettings(kind:.preview),job:job,progress:report)
    let info=try probe(output,tools:engine.tools);try check(abs(info.duration-4.416667)<0.06 && info.fpsValue==24,"Master render timing/fps wrong")
    func pixel(_ time:Double)throws->[UInt8] {Array(try engine.tools.run("ffmpeg",["-v","error","-ss",num(time),"-i",output.path,"-frames:v","1","-vf","scale=1:1","-pix_fmt","rgb24","-f","rawvideo","pipe:1"]))}
    let red=try pixel(0.5),blue=try pixel(3.5),blend=try pixel(2.2)
    try check(red[0]>180 && blue[2]>180 && blend[0]>30 && blend[2]>30,"Cuts/dissolve did not use correct combined timeline")
    var cardEdit=edit;cardEdit.title="Dissolve into end card";cardEdit.endCard=EndCard(transition:0.6,duration:1.5,text:"Celebrate")
    let cardOutput=try engine.render(cardEdit,project:p,root:root,settings:ExportSettings(kind:.preview),job:job,progress:report)
    try check(abs((try probe(cardOutput,tools:engine.tools)).duration-5.316667)<0.06,"End-card dissolve duration wrong")
    var invalid=edit;invalid.clips.append(EditClip(sourceId:master.source.id,start:8,end:10,transition:0))
    do {try invalid.validate(p);throw WeaverError("accepted mixed styles")}catch{try check(error.localizedDescription != "accepted mixed styles","Mixed transition styles accepted")}
    invalid=edit;invalid.clips[1].transition=0.4
    do {try invalid.validate(p);throw WeaverError("accepted short dissolve")}catch{try check(error.localizedDescription != "accepted short dissolve","Out-of-range dissolve accepted")}
    var crossing=edit;crossing.clips=[EditClip(sourceId:master.source.id,start:3,end:5)];crossing.transitionStyle="cut"
    do {try crossing.validate(p);throw WeaverError("accepted crossed boundary")}catch{try check(error.localizedDescription != "accepted crossed boundary","Original boundary crossing accepted")}
    crossing.clips=[EditClip(sourceId:master.source.id,start:3,end:4),EditClip(sourceId:master.source.id,start:4,end:5)]
    try crossing.validate(p)
    crossing.clips=[EditClip(sourceId:master.source.id,start:3.89,end:4)]
    crossing.title="Boundary frame rounding"
    let boundaryOutput=try engine.render(crossing,project:p,root:root,settings:ExportSettings(kind:.preview),job:job,progress:report)
    let boundaryPixels=Array(try engine.tools.run("ffmpeg",["-v","error","-i",boundaryOutput.path,"-vf","scale=1:1","-pix_fmt","rgb24","-f","rawvideo","pipe:1"]))
    try check(!boundaryPixels.isEmpty,"No boundary frames rendered")
    for i in stride(from:0,to:boundaryPixels.count,by:3) {try check(boundaryPixels[i]>180 && boundaryPixels[i+2]<50,"Frame rounding included the next original")}
    let cached=try engine.prepareCombined(p,root:root,job:job,progress:report)
    try check(cached.0.combinedMasters?.count==1,"Re-preparation duplicated master")
    let moved=base.appendingPathComponent("Moved Project");try fm.copyItem(at:root,to:moved)
    let relocated=try Project.open(moved).0
    try check(relocated.combinedMasters![0].source.originalPath.hasPrefix(moved.path),"Master did not relocate with project")
    var mismatched=p;mismatched.sources[1].media.width=640
    let separate=try engine.prepareCombined(mismatched,root:root,job:job,progress:report)
    try check(separate.1.hasPrefix("Formats differ"),"Mismatched formats not kept separate")
    try engine.verify(p.sources,job:job,progress:report)
    let recent=ProjectEntry(project:p,root:root,created:Date(),modified:Date(),managedBytes:folderBytes(root))
    let old=ProjectEntry(project:p,root:root,created:Date().addingTimeInterval(-8*86400),modified:Date(),managedBytes:folderBytes(root))
    try check(recent.needsDeletionConfirmation && !old.needsDeletionConfirmation,"Delete age rules wrong")
    try check(recent.managedBytes>master.source.bytes,"Project disk accounting omitted generated files")
    print("VERSION FOUR TESTS PASSED: lossless compatible master, 1 review video, original timeline map, repeated master selections, dissolve pixels, uniform transition validation, cache reuse, relocation, mismatched fallback, unchanged originals")
}
