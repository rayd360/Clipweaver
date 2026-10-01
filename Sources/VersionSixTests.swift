import Foundation
func runVersionSixTests(_ base:URL,reported:URL)throws {
    try runVersionFiveTests(base,reported:reported)
    let engine=Engine(tools:try Toolchain.locate()),job=JobControl(),root=base.appendingPathComponent("Project")
    let report:ProgressReport={text,_ in print(text);fflush(stdout)}
    func check(_ ok:Bool,_ message:String)throws {if !ok {throw WeaverError(message)}}
    var p=try Project.open(root).0
    let original=try EditPlan.load(projectFile(p.editChoices![1],root:root))
    p.lastEditPath=p.editChoices![1];p.suppressCaptions=true;p.revisionNotes="Keep this opening, but make the ending more energetic. Offer different lengths.";try p.save(root)
    let suppressed=withSelectedMusic(original,project:p)
    try check(suppressed.captions==nil && suppressed.captionStyles==nil && suppressed.overlays==nil,"Captions were not suppressed")
    try check(original.captions != nil,"Original edit was modified")
    var staticEdit=original;staticEdit.overlays=[TextOverlay(start:0,end:1,text:"Static wording",x:0.1,y:0.2,width:0.7,height:0.2)]
    try check(withSelectedMusic(staticEdit,project:p).overlays==nil,"Legacy caption overlay was not suppressed")
    var global=try GlobalAssets.load()
    try check(global.brand(for:p).name=="Rhythm & Flash Events","Default brand wrong")
    global.brands=global.brandProfiles+[BrandProfile(id:"second",name:"Second test brand")];global.activeBrandId="second";try global.save()
    try check(global.brand(for:p).name=="Rhythm & Flash Events","Global management selection changed existing project brand")
    p.brandId="second";try check(global.brand(for:p).name=="Second test brand","Project brand selection failed");p.brandId="rhythm-flash"
    let review=try engine.prepare(p,root:root,preset:.small,job:job,progress:report)
    let manifest=try readJSON(ReviewManifest.self,review.appendingPathComponent("manifest.json"))
    try check(manifest.captionsEnabled==false && manifest.brand?.name=="Rhythm & Flash Events" && manifest.editingPolicyVersion==6,"Current AI preferences missing")
    _ = try engine.packReview(review,root:root,job:job)
    let zipped=try engine.revisionPackage(project:p,root:root,edit:original,notes:p.revisionNotes!,job:job,progress:report)
    let inspect=base.appendingPathComponent("Revision Inspection")
    try Toolchain(root:URL(fileURLWithPath:"/usr/bin")).run("ditto",["-x","-k",zipped.path,inspect.path],job:job)
    let folder=inspect.appendingPathComponent("Revision for AI")
    let context=try readJSON(RevisionContext.self,folder.appendingPathComponent("revision.json"))
    try check(context.selectedChoice==2 && context.selectedTitle==original.title && !context.captionsEnabled,"Revision selected wrong version/preferences")
    let rm=try readJSON(ReviewManifest.self,folder.appendingPathComponent("manifest.json"))
    for source in rm.sources {try check(fm.fileExists(atPath:folder.appendingPathComponent(source.reviewVideo).path),"Revision review source missing")}
    let copied=folder.appendingPathComponent("previous-response.clipweaveredit")
    let originalResponse=projectFile(p.lastEditPath!,root:root).deletingLastPathComponent().appendingPathComponent("response.clipweaveredit")
    try check(try Data(contentsOf:copied)==Data(contentsOf:originalResponse),"Previous AI response changed")
    let rendered=try EditPlan.load(folder.appendingPathComponent("rendered-edit.json"))
    try check(rendered.captions==nil && rendered.music != nil,"Revision did not reflect local caption/music settings")
    let media=try probe(folder.appendingPathComponent("selected-output.mp4"),tools:engine.tools)
    try check(media.width==360 && media.height==640 && media.fpsValue==24 && abs(media.duration-original.duration)<0.1,"Revision video is not complete source-resolution/frame-rate output")
    let originalFiles=(fm.enumerator(at:review,includingPropertiesForKeys:[.isRegularFileKey])!.allObjects as! [URL]).filter{(try? $0.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true}
    for file in originalFiles {
        let path=relativeProjectPath(file,root:review),copy=folder.appendingPathComponent("original-review/For AI/"+path)
        try check(try Data(contentsOf:file)==Data(contentsOf:copy),"Original review file not preserved: "+path)
    }
    var revisions:[EditPlan]=[]
    for i in 0..<3 {var edit=original;edit.title="Revised choice \(i+1)";edit.captions=nil;edit.captionStyles=nil;edit.clips[0].start=0;edit.clips[0].end=Double(4+i);revisions.append(edit)}
    let response=root.appendingPathComponent("Incoming/Revised.clipweaveredit")
    let objects=try JSONSerialization.jsonObject(with:jsonEncoder().encode(revisions))
    try JSONSerialization.data(withJSONObject:["package_version":2,"edits":objects,"assets":[]]).write(to:response)
    let new=try engine.importResponse(response,project:p,root:root,job:job).0
    let durations=try new.editChoices!.map{try EditPlan.load(projectFile($0,root:root)).duration}
    try check(durations==[4,5,6],"Revised choices were forced to one duration")
    try check(fm.fileExists(atPath:originalResponse.path),"Earlier response lost after revision")
    try engine.verify(p.sources,job:job,progress:report)
    print("VERSION SIX TESTS PASSED: caption suppression, legacy overlays, brand isolation, AI preference metadata, selected-choice revision ZIP, complete original materials, exact prior response, full output/music settings, three different revised runtimes, history and originals preserved")
}
