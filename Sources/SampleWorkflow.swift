import Foundation

func sampleWorkflow() throws {
    let args=CommandLine.arguments
    func argument(_ key:String) throws -> String {guard let i=args.firstIndex(of:key),i+1<args.count else{throw WeaverError("Missing \(key)")};return args[i+1]}
    let mode=try argument("--sample-workflow"),root=URL(fileURLWithPath:try argument("--sample-root"),isDirectory:true)
    let engine=Engine(tools:try Toolchain.locate()),job=JobControl()
    let report:ProgressReport={s,_ in print(s);fflush(stdout)}
    if mode=="prepare" {
        guard !fm.fileExists(atPath:root.appendingPathComponent("Project.clipweaver").path) else{throw WeaverError("Sample project already exists; use it without rebuilding.")}
        let source=URL(fileURLWithPath:try argument("--sample-source"),isDirectory:true)
        let urls=try fm.contentsOfDirectory(at:source,includingPropertiesForKeys:nil).filter{["mp4","mov"].contains($0.pathExtension.lowercased())}.sorted{$0.lastPathComponent<$1.lastPathComponent}
        try prepareProjectFolders(root)
        let p=try engine.add(urls,project:Project(name:"Star Party — September samples"),job:job,progress:report);try p.save(root)
        let review=try engine.prepare(p,root:root,preset:.balanced,job:job,progress:report)
        _ = try engine.packReview(review,root:root,job:job)
        for s in p.sources {let info=try probe(review.appendingPathComponent("videos/\(s.id).mp4"),tools:engine.tools);guard info.fpsValue==8,abs(info.duration-s.media.duration)<0.15 else{throw WeaverError("Sample review changed timing.")}}
        print("SAMPLE PREPARATION PASSED: \(urls.count) originals referenced; all review copies 8 fps.")
    } else if mode=="reprepare" {
        let p=try Project.open(root).0
        let review=try engine.prepare(p,root:root,preset:.balanced,job:job,progress:report)
        _ = try engine.packReview(review,root:root,job:job)
        print("EXISTING PROJECT PREPARATION PASSED")
    } else if mode=="render" {
        let p=try Project.open(root).0
        let (updated,edit)=try engine.importResponse(URL(fileURLWithPath:try argument("--sample-response")),project:p,root:root,job:job)
        var outputs:[String:String]=[:]
        for kind in [ExportKind.preview,.social,.website] {
            let u=try engine.render(edit,project:updated,root:root,settings:ExportSettings(kind:kind,mute:kind == .website),job:job,progress:report)
            outputs[kind.rawValue]=u.path
        }
        try engine.verify(updated.sources,job:job,progress:report)
        try writeJSON(outputs,root.appendingPathComponent("test-outputs.json"))
        print("SAMPLE WORKFLOW PASSED: response imported; preview/social/website verified; originals unchanged.")
    } else {throw WeaverError("Unknown sample workflow stage")}
}
