import SwiftUI
import AppKit
import CryptoKit

struct RevisionContext:Codable {
    var projectId:String
    var selectedChoice:Int
    var selectedTitle:String
    var selectedEdit:String="selected-edit.json"
    var renderedEdit:String="rendered-edit.json"
    var selectedOutput:String="selected-output.mp4"
    var previousResponse:String?
    var requestedChanges:String
    var captionsEnabled:Bool
    var brandName:String
    var instruction:String="Revise ONLY the selected choice as the baseline. Inspect its complete rendered video, selected-edit.json, rendered-edit.json and previous AI response, then the original review footage and style reference. User change-note times refer to selected-output.mp4 finished-video seconds; convert to original source seconds using selected-edit.json, including transition overlaps. Return three distinct interpretations of these changes in one package_version 2 response. Preserve what was not requested to change. Choose runtime and caption timing independently unless constrained by the user. The current root manifest and instructions override the preserved original-review instructions. Never place captions over faces; omit any caption whose placement cannot be verified."
}
extension Engine {
    func revisionPackage(project:Project,root:URL,edit:EditPlan,notes:String,job:JobControl,progress:@escaping ProgressReport)throws->URL {
        let clean=notes.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty,clean.count<=12000,let editPath=project.lastEditPath else{throw WeaverError("Select an edit and describe the changes you want first.")}
        let originalZIP=root.appendingPathComponent("Upload to AI.zip")
        guard fm.fileExists(atPath:originalZIP.path) else{throw WeaverError("Prepare this project's AI upload first so the revision includes all original review materials.")}
        let directory=root.appendingPathComponent("Revisions/\(UUID().uuidString)")
        try fm.createDirectory(at:directory,withIntermediateDirectories:true)
        var complete=false;defer{if !complete {try? fm.removeItem(at:directory)}}
        let stage=directory.appendingPathComponent("Revision for AI"),original=stage.appendingPathComponent("original-review")
        try fm.createDirectory(at:original,withIntermediateDirectories:true)
        progress("Gathering the original AI review materials",0.02)
        let listing=try Toolchain(root:URL(fileURLWithPath:"/usr/bin")).run("unzip",["-Z1",originalZIP.path],job:job)
        let entries=String(decoding:listing,as:UTF8.self).split(separator:"\n")
        guard entries.allSatisfy({!$0.hasPrefix("/") && !$0.split(separator:"/").contains("..")}) else{throw WeaverError("The original upload ZIP contains invalid paths. Prepare it again.")}
        try Toolchain(root:URL(fileURLWithPath:"/usr/bin")).run("ditto",["-x","-k",originalZIP.path,original.path],job:job)
        let manifestURL=original.appendingPathComponent("For AI/manifest.json")
        var manifest=try readJSON(ReviewManifest.self,manifestURL)
        guard manifest.projectId==project.projectId else{throw WeaverError("The original review ZIP belongs to a different project. Prepare this project again.")}
        guard Set(edit.clips.map(\.sourceId)).isSubset(of:Set(manifest.sources.map(\.id))) else {throw WeaverError("The selected edit uses footage from a different review package. Restore its original Upload to AI.zip before preparing this revision.")}
        let prefix="original-review/For AI/"
        for i in manifest.sources.indices {
            manifest.sources[i].reviewVideo=prefix+manifest.sources[i].reviewVideo
            manifest.sources[i].reviewAudio=manifest.sources[i].reviewAudio.map{prefix+$0}
            manifest.sources[i].storyboards=manifest.sources[i].storyboards.map{prefix+$0}
        }
        manifest.projectLogo=nil
        let global=try GlobalAssets.load()
        if project.includeLogoInReview != false,let logo=try resolvedLogo(project,root:root) {
            try fm.createDirectory(at:stage.appendingPathComponent("branding"),withIntermediateDirectories:true)
            try fm.copyItem(at:logo,to:stage.appendingPathComponent("branding/project-logo.png"))
            let im=try checkedImage(logo);manifest.projectLogo=ReviewLogo(file:"branding/project-logo.png",width:Int(im.size.width),height:Int(im.size.height),sha256:try fingerprint(logo,job:job))
        }
        // Carry the current selected reference too if the user changed it after preparation.
        if let id=project.styleReferenceId {
            guard let ref=global.references.first(where:{$0.id==id}) else{throw WeaverError("The selected style reference is missing. Choose another reference or clear it before revising.")}
            try fm.createDirectory(at:stage.appendingPathComponent("reference"),withIntermediateDirectories:true)
            try fm.copyItem(at:GlobalAssets.root.appendingPathComponent(ref.video),to:stage.appendingPathComponent("reference/style-reference.mp4"))
            manifest.styleReference=ReviewReference(id:id,name:ref.name,file:"reference/style-reference.mp4",duration:ref.media.duration,fps:ref.media.fps,width:ref.media.width,height:ref.media.height)
        }else{manifest.styleReference=nil}
        manifest.selectedMusic=try prepareReviewMusic(project,root:root,folder:stage,job:job)
        manifest.videoIdea=project.videoIdea;manifest.requestedVersions=3;manifest.captionsEnabled=project.suppressCaptions != true;manifest.brand=global.brand(for:project).reviewValue;manifest.editingPolicyVersion=6
        try writeJSON(manifest,stage.appendingPathComponent("manifest.json"))
        let sourceEdit=projectFile(editPath,root:root)
        try fm.copyItem(at:sourceEdit,to:stage.appendingPathComponent("selected-edit.json"))
        let response=sourceEdit.deletingLastPathComponent().appendingPathComponent("response.clipweaveredit")
        var responseName:String?=nil
        if fm.fileExists(atPath:response.path) {responseName="previous-response.clipweaveredit";try fm.copyItem(at:response,to:stage.appendingPathComponent(responseName!))}
        else {
            // Legacy edit.json responses may have separate graphics/audio.
            let assets=stage.appendingPathComponent("legacy-assets");try fm.createDirectory(at:assets,withIntermediateDirectories:true)
            var names=Set((edit.overlays ?? []).compactMap(\.filename));if let n=edit.endCard?.filename {names.insert(n)}
            for name in names {try fm.copyItem(at:sourceEdit.deletingLastPathComponent().appendingPathComponent(name),to:assets.appendingPathComponent(name))}
            if let path=project.musicPath {let url=projectFile(path,root:root);if fm.fileExists(atPath:url.path){try fm.copyItem(at:url,to:assets.appendingPathComponent(url.lastPathComponent))}}
        }
        let settings=ExportSettings(kind:.social,aspect:"source",resolution:"original",includeLogo:!(project.logoHiddenEdits ?? []).contains(editPath))
        let output=try render(edit,project:project,root:root,settings:settings,job:job,progress:{text,value in progress("Rendering selected version for AI: "+text,0.1+value*0.8)})
        try fm.moveItem(at:output,to:stage.appendingPathComponent("selected-output.mp4"))
        try fm.moveItem(at:output.deletingPathExtension().appendingPathExtension("edit.json"),to:stage.appendingPathComponent("rendered-edit.json"))
        let choice=(project.editChoices?.firstIndex(of:editPath) ?? 0)+1
        let context=RevisionContext(projectId:project.projectId,selectedChoice:choice,selectedTitle:edit.title,previousResponse:responseName,requestedChanges:clean,captionsEnabled:project.suppressCaptions != true,brandName:global.brand(for:project).name)
        try writeJSON(context,stage.appendingPathComponent("revision.json"))
        try clean.write(to:stage.appendingPathComponent("REQUESTED-CHANGES.txt"),atomically:true,encoding:.utf8)
        if let skill=resourceSkillURL() {
            try fm.copyItem(at:skill,to:stage.appendingPathComponent("clipweaver-editor"))
            try fm.copyItem(at:skill.appendingPathComponent("SKILL.md"),to:stage.appendingPathComponent("EDITOR-INSTRUCTIONS.md"))
            try fm.copyItem(at:skill.appendingPathComponent("references/edit-format.md"),to:stage.appendingPathComponent("EDIT-FORMAT.md"))
        }
        try ("CLIPWEAVER REVISION\nRead revision.json first, then the root manifest.json, EDITOR-INSTRUCTIONS.md and EDIT-FORMAT.md. Root instructions override the preserved older instructions in original-review. The full selected-output.mp4 uses original export resolution and frame rate, not the 8 fps review. Revise selected-edit.json only as the baseline, returning three creative alternatives. All original ZIP contents are preserved in original-review. Do not use finished-output timestamps as original-source cuts.\n").write(to:stage.appendingPathComponent("START-HERE.txt"),atomically:true,encoding:.utf8)
        progress("Packing the full video and revision context",0.94)
        let zip=directory.appendingPathComponent("Upload Revision to AI.zip")
        try Toolchain(root:URL(fileURLWithPath:"/usr/bin")).run("ditto",["-c","-k","--keepParent","--norsrc",stage.path,zip.path],job:job)
        // The archive is the durable deliverable; avoid keeping a second full copy.
        try fm.removeItem(at:stage);complete=true;return zip
    }
}
extension Studio {
    var revisionStamp:String {
        guard let p=project,let root,let path=p.lastEditPath else{return ""}
        let editData=(try? Data(contentsOf:projectFile(path,root:root))) ?? Data()
        let upload=root.appendingPathComponent("Upload to AI.zip")
        let uploadDate=(try? upload.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let settings="\(uploadDate)|\(fileSize(upload))|\(path)|\(p.revisionNotes ?? "")|\(p.suppressCaptions==true)|\(p.styleReferenceId ?? "")|\(p.includeLogoInReview != false)|\(editLogoEnabled)|\(globalAssets.brand(for:p))|\(p.selectedMusic.map{String(describing:$0)} ?? "")|\(p.videoIdea ?? "")"
        return SHA256.hash(data:editData+Data(settings.utf8)).map{String(format:"%02x",$0)}.joined()
    }
    var readyRevisionZIP:URL? {guard !busy,let p=project,let root,p.lastRevisionStamp==revisionStamp,let path=p.lastRevisionZIP else{return nil};let u=projectFile(path,root:root);return fm.fileExists(atPath:u.path) ? u:nil}
    func buildRevisionPackage() {
        guard let p=project,let root,let plan else{return};let stamp=revisionStamp
        run({job,report in try self.engine.revisionPackage(project:p,root:root,edit:plan,notes:p.revisionNotes ?? "",job:job,progress:report)},finish:{url in self.project?.lastRevisionZIP=relativeProjectPath(url,root:root);self.project?.lastRevisionStamp=stamp;try self.save();self.copyRevisionZIP();self.status="Revision ZIP ready: \(humanSize(fileSize(url))). Includes the full selected video and original review materials."})
    }
    func copyRevisionZIP() {guard let url=readyRevisionZIP else{return};NSPasteboard.general.clearContents();NSPasteboard.general.writeObjects([url as NSURL]);NSPasteboard.general.setPropertyList([url.path],forType:NSPasteboard.PasteboardType("NSFilenamesPboardType"))}
    func copyRevisionPrompt() {
        guard let plan,let project else{return}
        let text="""
        Use the attached ClipWeaver revision ZIP. Read revision.json and the root manifest/instructions first. I selected “\(plan.title)” in project \(project.projectId). Inspect the complete selected-output.mp4, selected-edit.json, rendered-edit.json, previous response and original-review media. Revise ONLY my selected version as the baseline. Return one package_version 2 .clipweaveredit with three distinct interpretations of my changes, using original-source seconds, source shape and source fps. Choose each version's duration and caption timing independently unless my notes constrain them. Never overlay captions on faces; omit them if safe placement cannot be checked. Captions are \(project.suppressCaptions == true ? "DISABLED":"optional when helpful"). Do not compose music. Preserve the supplied brand and my selected music. My requested changes (times refer to the selected finished video):
        \(project.revisionNotes ?? "")
        """
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string);status="Revision prompt copied"
    }
}
extension StudioView {
    var revisionPanel:some View {
        card {
            Text("Refine the selected version").font(.title2)
            Text("Describe what to keep and change. Times such as ‘at 5 seconds’ refer to the selected finished video. AI will return three new variations of this version.").foregroundStyle(.secondary)
            TextEditor(text:Binding(get:{model.project?.revisionNotes ?? ""},set:{model.project?.revisionNotes=String($0.prefix(12000));model.saveCreativeState()})).frame(height:100).border(Color.gray.opacity(0.4))
            Button("Prepare Revision for AI",action:model.buildRevisionPackage).buttonStyle(.borderedProminent).disabled(model.busy || (model.project?.revisionNotes ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            Text("Includes a fresh full-resolution render with current caption/music settings, original AI review materials, the prior AI response and your selected edit. This ZIP may be larger than the initial upload.").font(.caption).foregroundStyle(.secondary)
            if let url=model.readyRevisionZIP {
                HStack {Button("Copy Revision .Zip file",action:model.copyRevisionZIP);Button("Copy Revision Prompt",action:model.copyRevisionPrompt);Button("Show ZIP"){NSWorkspace.shared.activateFileViewerSelecting([url])}}
                Text("Paste the ZIP into ChatGPT, then copy and paste the revision prompt. If attachment paste is unavailable, use Show ZIP and drag it into the chat.").font(.caption).foregroundStyle(.secondary)
            }
        }.disabled(model.busy)
    }
}
