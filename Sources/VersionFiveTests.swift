import Foundation
import AppKit
func runVersionFiveTests(_ base:URL,reported:URL)throws {
    setenv("CLIPWEAVER_GLOBAL",base.appendingPathComponent("Global").path,1)
    try fm.createDirectory(at:base,withIntermediateDirectories:true)
    let engine=Engine(tools:try Toolchain.locate()),job=JobControl()
    let report:ProgressReport={text,_ in print(text);fflush(stdout)}
    func check(_ ok:Bool,_ why:String)throws{if !ok {throw WeaverError(why)}}
    let attached=try AIResponse.load(reported)
    for (w,h) in [(270,480),(1080,1920),(1920,1080),(640,640)] {
        let sprites=try captionSprites(attached.edit,width:w,height:h,logoURL:nil,includeLogo:false)
        try check(sprites.count==attached.edit.captions!.reduce(0){$0+$1.words.count},"Caption words were lost")
        try check(sprites.allSatisfy{$0.rect.minX>=0 && $0.rect.minY>=0 && $0.rect.maxX<=Double(w) && $0.rect.maxY<=Double(h)},"Caption fit left canvas")
    }
    print("Reported response captions fit portrait, landscape and square at preview and export sizes")
    let video=base.appendingPathComponent("original.mp4")
    try engine.tools.ffmpeg(["-f","lavfi","-i","testsrc2=s=360x640:r=24:d=8","-c:v","libx264","-pix_fmt","yuv420p",video.path],job:job)
    let track=base.appendingPathComponent("original-song.wav")
    try engine.tools.ffmpeg(["-f","lavfi","-i","sine=frequency=650:duration=2","-c:a","pcm_s16le",track.path],job:job)
    let music=try engine.importMusic(track,name:"Test song",job:job)
    var global=GlobalAssets();global.music=[music];global.ideas=[SavedIdea(id:"idea",name:"Test brief",text:"Three different energetic highlights")];try global.save()
    let projectRoot=base.appendingPathComponent("Project");try prepareProjectFolders(projectRoot)
    var p=try engine.add([video],project:Project(name:"Version Five Test"),job:job,progress:report)
    let local="Assets/Music/\(music.id)/track.m4a",localURL=projectRoot.appendingPathComponent(local)
    try fm.createDirectory(at:localURL.deletingLastPathComponent(),withIntermediateDirectories:true);try fm.copyItem(at:GlobalAssets.root.appendingPathComponent(music.file),to:localURL)
    p.selectedMusic=ProjectMusic(id:music.id,name:music.name,path:local,duration:music.duration,start:1.5)
    p.videoIdea="Three energetic party highlights";try p.save(projectRoot)
    let review=try engine.prepare(p,root:projectRoot,preset:.small,job:job,progress:report)
    let manifest=try readJSON(ReviewManifest.self,review.appendingPathComponent("manifest.json"))
    try check(manifest.requestedVersions==3 && manifest.selectedMusic?.start==1.5 && manifest.videoIdea==p.videoIdea,"Review choices/music/idea not recorded")
    try check(fm.fileExists(atPath:review.appendingPathComponent(manifest.selectedMusic!.file).path),"Music listening copy missing")
    var plans:[EditPlan]=[]
    for i in 0..<3 {
        var e=EditPlan(schemaVersion:4,projectId:p.projectId,title:"Choice \(i+1)",aspect:"source",fps:"source",clips:[EditClip(sourceId:p.sources[0].id,start:Double(i),end:Double(i)+5,volume:0)],captionStyles:attached.edit.captionStyles,captions:[attached.edit.captions![0]],transitionStyle:"cut")
        if i==1 {e.captions?[0].words[0].text="GOOD"};if i==2 {e.captions?[0].words[0].text="TIME"}
        plans.append(e)
    }
    let encoded=try JSONSerialization.jsonObject(with:jsonEncoder().encode(plans))
    let response=projectRoot.appendingPathComponent("Incoming/Choices.clipweaveredit")
    try JSONSerialization.data(withJSONObject:["package_version":2,"edits":encoded,"assets":[]],options:.sortedKeys).write(to:response)
    p=try engine.importResponse(response,project:p,root:projectRoot,job:job).0
    try check(p.editChoices?.count==3,"Three choices not imported")
    for (i,path) in p.editChoices!.enumerated() {
        var pp=p;pp.lastEditPath=path
        let edit=try EditPlan.load(projectFile(path,root:projectRoot))
        let output=try engine.render(edit,project:pp,root:projectRoot,settings:ExportSettings(kind:i==0 ? .website:.preview,aspect:"source"),job:job,progress:report)
        let media=try probe(output,tools:engine.tools)
        try check(media.fpsValue==24 && media.width<media.height && abs(media.duration-5)<0.1,"Choice export changed shape/fps/duration")
        // Last second must contain the looping song, beyond its original two-second duration.
        let raw=try engine.tools.run("ffmpeg",["-v","error","-ss","3","-i",output.path,"-t","0.5","-vn","-f","s16le","-ac","1","pipe:1"])
        let energy=raw.withUnsafeBytes {buf -> Double in let v=buf.bindMemory(to:Int16.self);return v.reduce(0){$0+abs(Double($1))}/Double(max(1,v.count))}
        try check(energy>50,"Music did not loop to end of edit")
    }
    let current=p.lastEditPath
    var bad=plans;bad[2].clips[0].end=999
    try JSONSerialization.data(withJSONObject:["package_version":2,"edits":try JSONSerialization.jsonObject(with:jsonEncoder().encode(bad)),"assets":[]]).write(to:response)
    do {_ = try engine.importResponse(response,project:p,root:projectRoot,job:job);throw WeaverError("Invalid third choice accepted")}catch{try check(error.localizedDescription != "Invalid third choice accepted","Invalid third choice accepted")}
    try check(try Project.open(projectRoot).0.lastEditPath==current,"Bad response replaced current edit")
    let moved=base.appendingPathComponent("Moved Project");try fm.copyItem(at:projectRoot,to:moved)
    let reopened=try Project.open(moved).0
    try check(reopened.editChoices?.count==3 && fm.fileExists(atPath:projectFile(reopened.selectedMusic!.path,root:moved).path),"Choices/music did not relocate")
    try engine.verify(p.sources,job:job,progress:report)
    print("VERSION FIVE TESTS PASSED: reported captions fit, music library and looping, saved idea review, three-choice atomic import, all choices rendered, source shape/fps, invalid third choice preservation, relocation, originals unchanged")
}
