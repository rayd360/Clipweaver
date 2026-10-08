import AppKit
import UniformTypeIdentifiers

func saveProjectLogo(_ source:URL,root:URL) throws -> String {
    let image=try checkedImage(source),scale=min(1,1024/max(image.size.width,image.size.height))
    let w=max(1,Int((image.size.width*scale).rounded())),h=max(1,Int((image.size.height*scale).rounded()))
    guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let ctx=NSGraphicsContext(bitmapImageRep:rep) else {throw WeaverError("Could not resize project logo.")}
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=ctx
    NSColor.clear.setFill();NSRect(x:0,y:0,width:w,height:h).fill(using:.copy)
    ctx.imageInterpolation = .high;image.draw(in:NSRect(x:0,y:0,width:w,height:h),from:.zero,operation:.sourceOver,fraction:1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data=rep.representation(using:.png,properties:[:]) else{throw WeaverError("Could not save project logo.")}
    let folder=root.appendingPathComponent("Assets/Logo");try fm.createDirectory(at:folder,withIntermediateDirectories:true)
    let dest=folder.appendingPathComponent("logo-\(UUID().uuidString).png");try data.write(to:dest,options:.atomic)
    return relativeProjectPath(dest,root:root)
}
extension Project {
    func reviewManifestIsCurrent(_ manifest: ReviewManifest, assets: GlobalAssets, root: URL) -> Bool {
        guard manifest.projectId == projectId, manifest.editingPolicyVersion == 6,
              manifest.requestedVersions == 3, manifest.videoIdea == videoIdea else { return false }
        if usesCameraReviews {
            // Camera reviews deliberately omit ordinary video branding, captions and music.
            guard manifest.reviewPurpose == "activity_timestamps", manifest.captionsEnabled == false,
                  manifest.brand == nil, manifest.projectLogo == nil, manifest.styleReference == nil,
                  manifest.selectedMusic == nil, manifest.combinedParts == nil,
                  manifest.sources.count == sources.count else { return false }
            return zip(manifest.sources, sources).allSatisfy { review, source in
                review.id == source.id && review.sha256 == source.sha256 &&
                review.filename == source.filename && review.cameraOriginalFilename == source.cameraOriginalFilename &&
                review.duration == source.media.duration
            }
        }
        guard manifest.reviewPurpose == nil, manifest.styleReference?.id == styleReferenceId,
              manifest.captionsEnabled == (suppressCaptions != true),
              manifest.brand?.id == assets.brand(for: self).id, manifest.brand?.name == assets.brand(for: self).name,
              manifest.selectedMusic?.name == selectedMusic?.name, manifest.selectedMusic?.start == selectedMusic?.start else { return false }
        if let id = styleReferenceId {
            guard let ref = assets.references.first(where: { $0.id == id }), ref.name == manifest.styleReference?.name else { return false }
        }
        let logo = (includeLogoInReview != false) ? (try? resolvedLogo(self, root: root)) : nil
        if let logo { return (try? fingerprint(logo, job: JobControl())) == manifest.projectLogo?.sha256 }
        return manifest.projectLogo == nil
    }
}
extension Studio {
    var projectLogoURL:URL? {guard let root,let path=project?.logoPath else{return nil};return projectFile(path,root:root)}
    var editLogoEnabled:Bool {guard let path=project?.lastEditPath else{return true};return !(project?.logoHiddenEdits ?? []).contains(path)}
    func setEditLogoEnabled(_ enabled:Bool) {guard !busy,let path=project?.lastEditPath else{return};var list=project?.logoHiddenEdits ?? [];list.removeAll{$0==path};if !enabled {list.append(path)};project?.logoHiddenEdits=list;project?.choicePreviews?[path]=nil;do{try save()}catch{self.error=error.localizedDescription}}
    func setLogoReview(_ value:Bool) {guard !busy else{return};project?.includeLogoInReview=value;do{try save();status="Prepare for AI again to update the logo information"}catch{self.error=error.localizedDescription}}
    func chooseLogo() {
        guard !busy,let root else{return}
        let panel=NSOpenPanel();panel.title="Choose Project Logo";panel.allowedContentTypes=[.png,.jpeg];guard panel.runModal() == .OK,let u=panel.url else{return}
        do {project?.logoPath=try saveProjectLogo(u,root:root);try save();status="Logo saved inside this project. Enable Include logo in AI review when you want AI to use it."}catch{self.error=error.localizedDescription}
    }
    func removeLogo() {guard !busy else{return};project?.logoPath=nil;project?.includeLogoInReview=false;do{try save();status="Project logo removed; prepare a fresh AI package"}catch{self.error=error.localizedDescription}}
    var readyUploadZIP:URL? {
        guard !busy,let root,let project else{return nil}
        let u=root.appendingPathComponent("Upload to AI.zip")
        guard fileSize(u)>0,
              let manifest=try? readJSON(ReviewManifest.self,root.appendingPathComponent("For AI/manifest.json")),
              project.reviewManifestIsCurrent(manifest,assets:globalAssets,root:root) else{return nil}
        return u
    }
    func copyUploadZIP() {
        guard let url=readyUploadZIP else{error="Prepare this project's AI package first.";return}
        let board=NSPasteboard.general;board.clearContents()
        guard board.writeObjects([url as NSURL]) else{error="The ZIP could not be copied. Use Show Upload ZIP and drag it into ChatGPT.";return}
        // Finder's legacy file-list flavor complements the standard public.file-url flavor.
        board.setPropertyList([url.path],forType:NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        status="ZIP copied as a file. Paste into ChatGPT with ⌘V; if no attachment appears, use Show Upload ZIP and drag it in."
    }
}
