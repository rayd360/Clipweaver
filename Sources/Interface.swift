import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVKit

final class Studio: ObservableObject {
    @Published var project: Project?
    @Published var root: URL?
    @Published var plan: EditPlan?
    @Published var page = 0
    @Published var preset = ReviewPreset.balanced
    @Published var busy = false
    @Published var status = "Ready when you are"
    @Published var progress = 0.0
    @Published var error: String?
    @Published var aspect = "source"
    @Published var resolution = "original"
    @Published var websiteQuality = "balanced"
    @Published var muteWebsite = false
    @Published var lastOutput: URL?
    @Published var isDropTarget = false
    @Published var projectSort = "newest"
    @Published var projects: [ProjectEntry] = []
    @Published var showingProjects = true
    @Published var revisions: [URL] = []
    @Published var globalAssets = GlobalAssets()
    @Published var globalReferenceId = ""
    @Published var globalMusicId = ""
    @Published var referenceSearch = ""
    @Published var musicSearch = ""
    @Published var ideaSearch = ""
    @Published var playAllChoices = false
    @Published var playbackGeneration = 0
    var musicPlayer:AVPlayer?
    let library = ProjectLibrary()
    var inboxTimer: Timer?
    var inboxSeen: [String:String] = [:]
    var inboxStable: [String:String] = [:]
    var job = JobControl()
    let engine: Engine
    init(engine: Engine) {
        self.engine = engine
        if let path = ProcessInfo.processInfo.environment["CLIPWEAVER_UI_PROJECT"] ?? studioDefaults.string(forKey: "lastProject"), let (p,r) = try? Project.open(URL(fileURLWithPath: path)) {
            project = p; root = r
            if let v = p.reviewPreset, let preset = ReviewPreset(rawValue: v) { self.preset = preset }
            if let edit = p.lastEditPath, let e = try? EditPlan.load(projectFile(edit,root:r)), (try? e.validate(p)) != nil { plan = e }
            try? library.register(r)
        }
        refreshProjects();refreshRevisions();refreshGlobal()
        if ProcessInfo.processInfo.environment["CLIPWEAVER_UI_PROJECT"] != nil { showingProjects = false }
        inboxTimer=Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in self?.scanIncoming() }
    }
    func save() throws { if let p = project, let r = root { try p.save(r); try library.register(r); refreshProjects(); refreshRevisions(); studioDefaults.set(r.appendingPathComponent("Project.clipweaver").path, forKey: "lastProject") } }
    func newProject() {
        guard !busy else { return }
        guard let name=askName("New project",value:"My Video") else {return}
        do {
            let (p,r)=try library.create(name);project=p;root=r;plan=nil;lastOutput=nil;page=0;showingProjects=false
            status="Add your original footage to get started";try save()
        } catch {self.error=error.localizedDescription}
    }
    func openProject(_ url: URL? = nil) {
        guard !busy else { return }
        var chosen = url
        if chosen == nil { let panel = NSOpenPanel(); panel.title = "Open ClipWeaver project"; panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; if panel.runModal() == .OK { chosen = panel.url } }
        guard let chosen else { return }
        do {
            let (loaded,r) = try Project.open(chosen); let p = try loaded.organizeAssets(root:r); project = p; root = r; plan = nil; lastOutput = nil
            if let v = p.reviewPreset, let rp = ReviewPreset(rawValue:v) { preset = rp }
            if let edit = p.lastEditPath, let e = try? EditPlan.load(projectFile(edit,root:r)) { try e.validate(p); plan = e }
            refreshGlobal(); showingProjects=false; page = 0; status = "Opened \(p.name)"; try save()
        } catch { self.error = error.localizedDescription }
    }
    func run<T>(_ work: @escaping (JobControl, @escaping ProgressReport) throws -> T, finish: @escaping (T) throws -> Void) {
        guard !busy else { return }; busy = true; progress = 0; job = JobControl(); let current = job
        let report: ProgressReport = { text, value in DispatchQueue.main.async { self.status = text; self.progress = value } }
        DispatchQueue.global(qos: .userInitiated).async {
            do { let result = try work(current,report); DispatchQueue.main.async { self.busy = false; do { try finish(result) } catch { self.error = error.localizedDescription } } }
            catch { DispatchQueue.main.async { self.busy = false; self.status = "Ready"; self.error = error.localizedDescription } }
        }
    }
    func addFiles(_ supplied: [URL]? = nil) {
        guard !busy else { return }
        if project == nil { newProject() }; guard let p = project else { return }
        var urls = supplied ?? []
        if supplied == nil { let panel = NSOpenPanel(); panel.title = "Add videos or DJI LRF previews"; panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, UTType(importedAs:"local.clipweaver.lrf",conformingTo:.movie), UTType(importedAs:"local.clipweaver.osv",conformingTo:.movie)]; panel.allowsMultipleSelection = true; if panel.runModal() == .OK { urls = panel.urls } }
        guard !urls.isEmpty else { return }
        run({ job, report in try self.engine.add(urls,project:p,job:job,progress:report) }, finish: { value in self.project = value; try self.save(); self.status = "\(value.sources.count) source clips ready" })
    }
    func remove(_ id: String) { guard !busy else { return }; project?.nextSourceNumber = max(project?.nextSourceNumber ?? 1,(project?.sources.compactMap{Int($0.id.replacingOccurrences(of:"CLIP_",with:""))}.max() ?? 0)+1); project?.sources.removeAll { $0.id == id }; do { try save(); if let p = project, let plan { try plan.validate(p) } } catch { self.plan = nil; self.project?.lastEditPath=nil; try? self.save(); self.error = error.localizedDescription } }
    func relink(_ source: SourceClip) {
        let panel = NSOpenPanel(); panel.title = "Locate original: \(source.filename)"; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let u = panel.url else { return }
        run({ job, report in report("Checking replacement original",0.2); guard fileSize(u) == source.bytes, try fingerprint(u,job:job) == source.sha256 else { throw WeaverError("That file does not match the original \(source.filename). Choose the unchanged original.") }; return u }, finish: { url in if let ix = self.project?.sources.firstIndex(where: { $0.id == source.id }) { self.project?.sources[ix].originalPath = url.path }; try self.save(); self.status = "Original reconnected" })
    }
    func prepare() {
        guard let p = project, let r = root else { return }; let selected = preset
        run({ job, report in
            let result = try self.engine.prepare(p,root:r,preset:selected,job:job,progress:report)
            report("Packing review files for upload",0.98)
            _ = try self.engine.packReview(result,root:r,job:job)
            return result
        }, finish: { result in self.project=try Project.open(r).0; self.project?.reviewPreset = selected.rawValue; try self.save(); self.status = "Review package ready. Open For AI to choose files, or upload its ZIP."; self.copyUploadZIP(); NSWorkspace.shared.activateFileViewerSelecting([result]); self.progress = 1 })
    }
    func importEdit(_ provided: URL? = nil) {
        guard !busy else { return }; guard let p = project, let r = root else { error = "Open the matching project before loading an edit."; return }
        var u = provided
        if u == nil { let panel = NSOpenPanel(); panel.title = "Open the AI's edit.json"; panel.allowedContentTypes = [.json]; if panel.runModal() == .OK { u = panel.url } }
        guard let u else { return }
        do {
            let e = try EditPlan.load(u); try e.validate(p)
            let folder = r.appendingPathComponent("Edits"); try fm.createDirectory(at: folder,withIntermediateDirectories:true)
            let dest = uniqueURL(folder,cleanName(e.title),"json"); try writeJSON(e,dest)
            plan = e; project?.lastEditPath = relativeProjectPath(dest,root:r); project?.editChoices=[relativeProjectPath(dest,root:r)];project?.choicePreviews=nil;try save(); page = 1; status = "\(e.clips.count) cuts · \(clockText(e.duration)) · ready to preview"
        } catch { self.error = error.localizedDescription }
    }
    func useFullClips() {
        guard let p = project, let r = root, !p.sources.isEmpty else { return }
        do {
            let e = EditPlan(projectId:p.projectId,title:p.name,aspect:"source",fps:"source",clips:p.sources.map { EditClip(sourceId:$0.id,start:0,end:$0.media.duration) })
            let folder = r.appendingPathComponent("Edits"); try fm.createDirectory(at:folder,withIntermediateDirectories:true)
            let dest = uniqueURL(folder,"Full clips","json"); try writeJSON(e,dest); plan = e; project?.lastEditPath = relativeProjectPath(dest,root:r); project?.editChoices=[relativeProjectPath(dest,root:r)];project?.choicePreviews=nil;try save(); page = 1; status = "Full clips added in their current order"
        } catch { self.error = error.localizedDescription }
    }
    func music() {
        guard !busy, let r=root else {return}
        let panel = NSOpenPanel(); panel.title = "Choose the music file named in the edit"; panel.allowedContentTypes = [.audio,.movie]
        guard panel.runModal() == .OK, let u = panel.url else { return }
        do {
            let directory=r.appendingPathComponent("Assets/Music/\(UUID().uuidString)");try fm.createDirectory(at:directory,withIntermediateDirectories:true)
            let dest=directory.appendingPathComponent(u.lastPathComponent);try fm.copyItem(at:u,to:dest)
            project?.musicPath=relativeProjectPath(dest,root:r);try save();status="Music saved with project: \(u.lastPathComponent)"
        } catch {self.error=error.localizedDescription}
    }
    func render(_ kind: ExportKind) {
        guard let p = project, let r = root, let e = plan else { error = "Load an edit plan first."; return }
        let settings = ExportSettings(kind:kind,aspect:aspect,resolution:resolution,websiteQuality:websiteQuality,mute:kind == .website && muteWebsite,includeLogo:editLogoEnabled)
        run({ job, report in try self.engine.render(e,project:p,root:r,settings:settings,job:job,progress:report) }, finish: { result in self.lastOutput = result; self.progress = 1; self.status = "\(kind.rawValue) ready · \(humanSize(fileSize(result)))"; if kind == .preview { NSWorkspace.shared.open(result) } else { NSWorkspace.shared.activateFileViewerSelecting([result]) } })
    }
    func reveal(_ name: String? = nil) { guard let root else { return }; let u = name.map { root.appendingPathComponent($0) } ?? root; if fm.fileExists(atPath:u.path) { NSWorkspace.shared.activateFileViewerSelecting([u]) } else { error = "Prepare this project's AI package first." } }
    func copyPrompt() {
        guard let p = project else { return }
        if p.usesCameraReviews {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(cameraActivityPrompt(p,root:root),forType:.string)
            status = "Activity-review prompt copied — AI will return source time ranges for DJI Studio"; return
        }
        let prompt = """
        Use the attached ClipWeaver editor instructions and EDIT-FORMAT.md to edit project “\(p.name)” (project_id: \(p.projectId)). Inspect the attached videos/storyboards and audio with the tools available. Tell me if you cannot actually see or hear them. Choose the best moments, including multiple sections of the same source when useful, and return ONE downloadable .clipweaveredit package_version 2 response with exactly three edits and their image assets. Give the three edits distinct descriptive titles, different moment selections, sequencing and caption narratives; not just renamed duplicates. Choose runtime and caption timing independently for each version based on the footage and story. Do not reuse a fixed duration or caption timetable unless I specify it. Respect any requested duration or range. If a reference is selected, all three must follow its visual style while offering genuinely different creative choices. Omit music in every edit: ClipWeaver applies my selected music locally. Never compose or generate music. Use the bundled pack_response.py helper. Use original-source seconds, and schema_version 4 for word-level captions and project-logo placements (static overlays and end cards also supported). Use reusable caption_styles; ordinary words are white, emphasized words larger bold italic charcoal. Choose per-word finished-video start/end times, layout and none/fade/slide entrances. Keep captions and logo inside the social safe area. Never put added words or captions over any face, including during entrances, movement and cross-dissolves. Inspect the entire visible interval, not just one frame. Avoid existing lettering unless that is the best readable placement, but faces are never an exception. If you cannot establish a face-free location and timing, omit that caption. Do not claim you checked unseen frames. Do not create per-frame images or fonts. Use only my supplied project logo, never branding from a reference. Choose one transition_style for the whole video: cut (every transition 0) or cross_dissolve (AI chooses 0.5–0.8 seconds for every transition after the first). Never mix styles. If the manifest has a COMBINED_ source, cut that source using its long-timeline seconds and combined_parts to locate original moments. Never cross a combined_parts original-video boundary within one selection; split into explicit selections at the exact boundary. Use strong editorial captions with short phrases, clear filled lettering, expressive staggered slide entrances and deliberate line breaks. Keep fps as "source". Ask only for essential missing creative details.

        If you have local file access, save the completed response atomically in this project's Incoming folder: \(root?.appendingPathComponent("Incoming").path ?? ""). ClipWeaver will detect it. Otherwise return the single response file for me to double-click. Do not modify my originals or project file.

        Project logo: \(p.includeLogoInReview != false && globalAssets.logoURL != nil ? "Included in manifest and branding/project-logo.png. Use logo_placements when the idea calls for it; preserve transparency and proportions." : "Not requested for this review; omit logo_placements and do not invent a logo.")

        Style reference: \(p.styleReferenceId.flatMap{id in globalAssets.references.first{$0.id==id}}.map{"Mock the selected reference named “\($0.name)” in reference/style-reference.mp4. Inspect its pacing, motion and caption treatment at original frame cadence. Use only my project footage in clips; never copy reference footage, wording or branding. Adapt its structure to my idea and supported operations."} ?? "None selected; follow my idea without a reference.")

        Brand: \(globalAssets.brand(for:p).name). Use exactly this brand name when branding is needed; never infer branding from source event frames or reference videos.
        Captions: \(p.suppressCaptions == true ? "DISABLED. Omit captions, caption_styles and text/image caption overlays. Do not add captions in any version." : "Optional when useful. Inspect faces and existing text throughout each caption interval; omit captions if safe placement cannot be established.")

        My video idea: \(p.videoIdea?.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty == false ? p.videoIdea! : "Choose a compelling highlight edit from the footage; choose an appropriate length.")
        Keep aspect and fps as "source" in all three edits. Do not ask me about shape or music.
        Music: \(p.selectedMusic.map {"Use the selected track \($0.name) for pacing, starting at \(num($0.start)) seconds and looping when needed. The manifest includes the listening copy. Omit music from the edit JSON."} ?? "No music selected. Do not generate or supply music. Use appropriate original audio.")
        """
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(prompt,forType:.string); status = "Prompt copied — paste it into ChatGPT with your review files"
    }
    func showSkill() { if let u = resourceSkillURL() { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
    func handle(_ urls: [URL]) {
        if let u=urls.first, u.pathExtension.lowercased()=="clipweaveredit" { receiveResponse(u) }
        else if let u = urls.first, u.pathExtension == "clipweaver" { openProject(u) }
        else if let u = urls.first, u.pathExtension == "json" { importEdit(u) }
        else { addFiles(urls) }
    }
    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !busy else { return false }
        let group = DispatchGroup(); let lock = NSLock(); var urls:[URL] = []
        for provider in providers { group.enter(); provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil) { item,_ in
            let u = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation:$0,relativeTo:nil) }
            if let u { lock.lock(); urls.append(u); lock.unlock() }; group.leave()
        } }
        group.notify(queue:.main) { self.handle(urls.sorted { $0.lastPathComponent < $1.lastPathComponent }) }; return true
    }
    var outputRate: String { guard let p = project, let e = plan, let s = p.renderSources.first(where: { $0.id == e.clips.first?.sourceId }) else { return "source" }; return (e.fps == nil || e.fps == "source") ? s.media.fps : e.fps! }
}

private let ink = Color(red:0.075,green:0.085,blue:0.105)
private let panelColor = Color(red:0.115,green:0.13,blue:0.15)
private let accent = Color(red:1,green:0.59,blue:0.32)
private let pale = Color(red:0.94,green:0.93,blue:0.89)

struct StudioView: View {
    @ObservedObject var model: Studio
    var body: some View {
        HStack(spacing:0) {
            sidebar.frame(width:224)
            VStack(spacing:0) {
                HStack {
                    VStack(alignment:.leading,spacing:5) { Text(model.page == 3 && !model.showingProjects ? "Global library" : model.showingProjects ? "Your projects" : (model.project?.name ?? "Your next video starts here")).font(.system(size:24,weight:.semibold)); Text("Small files for AI. Original footage for the final cut.").font(.system(size:13)).foregroundStyle(.secondary) }
                    Spacer()
                    if model.project != nil { Button { model.reveal() } label: { Image(systemName:"folder") }.help("Show project folder") }
                }.padding(28)
                Divider().opacity(0.3)
                ScrollView { VStack(alignment:.leading,spacing:22) {
                    if model.page == 3 && !model.showingProjects { globalPage } else if model.showingProjects { projectsPage } else if model.page == 0 { preparePage } else if model.page == 1 { editPage } else { editPage }
                }.padding(28).frame(maxWidth:.infinity,alignment:.leading) }
                footer
            }.background(ink)
        }
        .foregroundStyle(pale).preferredColorScheme(.dark).tint(accent)
        .frame(minWidth:980,minHeight:690)
        .onDrop(of:[UTType.fileURL.identifier],isTargeted:$model.isDropTarget,perform:model.acceptDrop)
        .overlay { if model.isDropTarget { RoundedRectangle(cornerRadius:12).stroke(accent,lineWidth:3).padding(6).allowsHitTesting(false) } }
        .alert("ClipWeaver",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error=nil}})) { Button("OK",role:.cancel) {model.error=nil} } message: { Text(model.error ?? "") }
    }
    var sidebar: some View {
        VStack(alignment:.leading,spacing:28) {
            HStack(spacing:11) {
                Image(systemName:"film.stack.fill").font(.system(size:27)).foregroundStyle(accent)
                VStack(alignment:.leading,spacing:2) { Text("ClipWeaver").font(.system(size:20,weight:.bold)); Text("YOUR FOOTAGE. YOUR STORY.").font(.system(size:8,weight:.medium)).tracking(1.3).foregroundStyle(.secondary) }
            }.padding(.top,10)
            VStack(spacing:8) {
                Button {model.refreshProjects();model.showingProjects=true} label: {Label("Projects",systemImage:"square.grid.2x2").frame(maxWidth:.infinity,alignment:.leading).padding(12)}.buttonStyle(.plain)
                Button {model.showingProjects=false;model.page=3;model.refreshGlobal()} label: {Label("Branding & References",systemImage:"photo.on.rectangle").frame(maxWidth:.infinity,alignment:.leading).padding(12)}.buttonStyle(.plain)
                nav(0,"01","Prepare for AI","square.stack.3d.up")
                nav(1,"02","Review & Export","scissors")
            }
            Spacer()
            VStack(alignment:.leading,spacing:12) {
                HStack { Image(systemName:"lock.shield"); Text("Originals stay on your Mac") }.font(.system(size:11)).foregroundStyle(.secondary)
                Button("New Project…",action:model.newProject).frame(maxWidth:.infinity,alignment:.leading)
                Button("Open Project…") { model.openProject() }.frame(maxWidth:.infinity,alignment:.leading)
                Button("Editing Skill") { model.showSkill() }.frame(maxWidth:.infinity,alignment:.leading)
            }.buttonStyle(.plain).disabled(model.busy)
            Text("LOCAL EDITOR  ·  VERSION 6.1.1").font(.system(size:9,weight:.medium)).tracking(1).foregroundStyle(.tertiary)
        }.padding(22).background(Color(red:0.055,green:0.065,blue:0.08))
    }
    func nav(_ index:Int,_ number:String,_ title:String,_ icon:String) -> some View {
        Button {if index==1 {model.reviewEdit()} else {model.showingProjects=false;model.page=index}} label: {
            HStack(spacing:10) { Image(systemName:icon).frame(width:19); Text(title).font(.system(size:13,weight:.medium)); Spacer(); Text(number).font(.system(size:10,design:.monospaced)).opacity(0.45) }.padding(.vertical,13).padding(.horizontal,12).background(model.page==index ? accent.opacity(0.13) : .clear).clipShape(RoundedRectangle(cornerRadius:9)).foregroundStyle(model.page==index ? accent:pale.opacity(0.65))
        }.buttonStyle(.plain)
    }
    func card<Content:View>(@ViewBuilder _ content:()->Content) -> some View { VStack(alignment:.leading,spacing:16,content:content).padding(22).frame(maxWidth:.infinity,alignment:.leading).background(panelColor).clipShape(RoundedRectangle(cornerRadius:14)) }
    func label(_ text:String) -> some View { Text(text).font(.system(size:10,weight:.semibold)).tracking(1.8).foregroundStyle(accent) }
    var projectsPage: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {Text("Your projects").font(.system(size:28,weight:.semibold));Spacer();Button("New Project…",action:model.newProject).buttonStyle(.borderedProminent);Button("Open Existing…") {model.openProject()}}.disabled(model.busy)
            Text("Each project keeps its review copies, AI responses, edit history, previews and exports together. Original videos stay where they are.").foregroundStyle(.secondary)
            HStack {Button("Biggest to smallest") {model.projectSort="size";model.refreshProjects()};Button("Newest to oldest") {model.projectSort="newest";model.refreshProjects()}}
            if model.projects.isEmpty {Text("Create your first project to begin.").padding(.vertical,30)}
            ForEach(model.projects.sorted{model.projectSort=="size" ? $0.managedBytes>$1.managedBytes:$0.created>$1.created}) {entry in
                card {
                    HStack {
                        VStack(alignment:.leading,spacing:6) {Text(entry.project.name).font(.system(size:20,weight:.semibold));Text("\(entry.project.sources.count) original clips · \(humanSize(entry.managedBytes)) stored · \(entry.created.formatted(date:.abbreviated,time:.shortened))").font(.system(size:12)).foregroundStyle(.secondary)}
                        Spacer();Button("Delete Project",role:.destructive) {model.trashProject(entry)}.tint(.red).buttonStyle(.borderedProminent);Button("Open") {model.openProject(entry.root)}.buttonStyle(.borderedProminent)
                        Menu {Button("Rename…") {model.renameProject(entry)};Button("Show Folder") {NSWorkspace.shared.activateFileViewerSelecting([entry.root])};Button("Clear Review Copies & Previews…") {model.clearCaches(entry)};Button("Remove from List") {model.forgetProject(entry)};Button("Move Project to Trash…",role:.destructive) {model.trashProject(entry)}} label: {Image(systemName:"ellipsis")}
                    }.disabled(model.busy)
                }
            }
        }
    }
    var preparePage: some View {
        VStack(alignment:.leading,spacing:22) {
            card {
                label("THE ORIGINALS")
                HStack(alignment:.top,spacing:20) {
                    Image(systemName:"square.and.arrow.down.on.square").font(.system(size:36,weight:.light)).foregroundStyle(accent).padding(.top,3)
                    VStack(alignment:.leading,spacing:7) { Text("Drop your video clips here").font(.system(size:21,weight:.semibold)); Text("MP4, MOV and DJI LRF · Add camera previews to find moments and timestamps for your OSV footage. Keep the files in their current folder.").font(.system(size:13)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                    Spacer()
                    Button("Add Footage…") {model.addFiles()}.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy)
                }
            }
            if model.project?.usesCameraReviews == true {
                card {
                    label("DJI ACTIVITY REVIEW")
                    Text("Find the moments to edit in DJI Studio").font(.title2)
                    Text("Small LRF previews show both camera views. Tell AI what activity to look for; its selected times will be listed with the matching OSV filenames.").foregroundStyle(.secondary)
                    ideaLibrary
                }
            } else if model.project != nil {
                card {
                    label("PROJECT BRAND")
                    projectBrandPicker
                    HStack {
                        if let u=model.selectedBrandLogoURL,let image=NSImage(contentsOf:u) {Image(nsImage:image).resizable().scaledToFit().frame(width:80,height:60)}
                        Text(model.selectedBrandLogoURL == nil ? "Set your shared logo in Branding & References." : "Your shared brand logo is available to this project.")
                        Spacer();Button("Manage branding") {model.showingProjects=false;model.page=3;model.refreshGlobal()}
                    }
                    if model.selectedBrandLogoURL != nil {Toggle("Include global logo in AI review",isOn:Binding(get:{model.project?.includeLogoInReview != false},set:model.setLogoReview))}
                }
                card {referenceGallery(global:false)}
                card {musicGallery}
                card {ideaLibrary;captionPreference}
            }
            if let p = model.project, !p.sources.isEmpty {
                card {
                    label("SMALL COPIES FOR AI")
                    HStack(alignment:.top) {
                        VStack(alignment:.leading,spacing:8) { Text(p.usesCameraReviews ? "Small review files with original-file times" : "One review video when footage matches").font(.system(size:20,weight:.semibold)); Text(p.usesCameraReviews ? "Each LRF becomes a smaller 8 fps review. Files stay separate so the times match each OSV recording in DJI Studio. Keep the camera filenames when adding LRF files." : "Matching formats are combined without re-encoding into a full-quality master, then reduced to one 8 fps AI review. Different formats stay separate. The master uses additional disk space; original files stay unchanged.").font(.system(size:13)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                        Spacer(minLength:28)
                        Picker("Detail",selection:$model.preset) {ForEach(ReviewPreset.allCases){Text($0.rawValue).tag($0)}}.labelsHidden().frame(width:150)
                    }
                    if let root=model.root,let manifest=try? readJSON(ReviewManifest.self,root.appendingPathComponent("For AI/manifest.json")),let note=manifest.preparationNote {Text(note).font(.callout).foregroundStyle(.secondary)}
                    HStack { Button("Prepare for AI",action:model.prepare).buttonStyle(.borderedProminent).controlSize(.large); Button("Show Upload Files") {model.reveal("For AI")}; Button("Copy ChatGPT Prompt",action:model.copyPrompt) }.disabled(model.busy)
                    if model.readyUploadZIP != nil {
                        HStack {Button("Copy ChatGPT .Zip file",action:model.copyUploadZIP).buttonStyle(.borderedProminent);Button("Show Upload ZIP") {model.reveal("Upload to AI.zip")}}
                        Text("Copies the ZIP as a file. Paste into ChatGPT with ⌘V. Desktop paste compatibility could not be verified because automated access to ChatGPT is blocked. If no attachment appears, click Show Upload ZIP and drag the selected file into the chat.").font(.system(size:11)).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment:.leading,spacing:9) {
                    HStack { label("\(p.sources.count) SOURCE CLIPS"); Spacer(); Text(humanSize(p.sources.reduce(0){$0+$1.bytes})).font(.system(size:12)).foregroundStyle(.secondary) }
                    ForEach(p.sources) { s in
                        HStack(spacing:14) {
                            Image(systemName:"film").font(.system(size:22)).foregroundStyle(accent.opacity(0.8)).frame(width:36)
                            VStack(alignment:.leading,spacing:4) { Text(s.filename).font(.system(size:13,weight:.medium)).lineLimit(1); if let original=s.cameraOriginalFilename { Text("DJI Studio: " + original).font(.caption).foregroundStyle(.secondary) }; Text("\(s.id)  ·  \(clockText(s.media.duration))  ·  \(s.media.width) × \(s.media.height)  ·  \(s.media.fps) fps").font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary) }
                            Spacer()
                            if !fm.fileExists(atPath:s.originalPath) { Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.yellow) }
                            Menu { Button("Open Original") {NSWorkspace.shared.open(URL(fileURLWithPath:s.originalPath))}; Button("Relink Original…") {model.relink(s)}; Button("Remove from Project",role:.destructive) {model.remove(s.id)} } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).frame(width:26).disabled(model.busy)
                        }.padding(13).background(panelColor).clipShape(RoundedRectangle(cornerRadius:9))
                    }
                }
            } else {
                Text("Start with a few clips. You can add more footage to a project at any time.").font(.system(size:14)).foregroundStyle(.secondary).padding(.vertical,20)
            }
        }
    }
    var editPage: some View {
        VStack(alignment:.leading,spacing:22) {
            card {
                label("YOUR AI EDITOR → YOUR MAC")
                Text(model.project?.usesCameraReviews == true ? "Your useful moments and source times." : "One response. Everything included.").font(.system(size:25,weight:.semibold))
                Text(model.project?.usesCameraReviews == true ? "Open AI’s ClipWeaver response, select a choice, and use Source timestamps below to find those moments in DJI Studio. A timestamp CSV is also saved beside each imported edit." : "Ask AI for one ClipWeaver response. Double-click it, drop it here, or save it in the project’s Incoming folder. Three edit choices and their graphics are filed together automatically. Your selected music is applied locally.").font(.system(size:14)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                HStack { Button("Open AI Response…") {model.chooseResponse()}.buttonStyle(.borderedProminent).controlSize(.large); Menu("More") {Button("Import Older edit.json…") {model.importEdit()};Button("Use Full Clips in Order",action:model.useFullClips);Button("Add Music…",action:model.music)}; Button("Show Incoming") {model.reveal("Incoming")} }.disabled(model.busy || model.project == nil)
            }
            if model.project?.usesCameraReviews != true { captionPreference }
            if !model.revisions.isEmpty {
                Menu("Earlier edits (\(model.revisions.count))") {ForEach(model.revisions,id:\.path) {u in Button(model.revisionLabel(u)) {model.restoreRevision(u)}}}.disabled(model.busy)
            }
            if let e = model.plan {
                choiceGallery
                sourceTimestampsPanel
                if !(e.logoPlacements ?? []).isEmpty {Toggle("Show brand logo in this edit",isOn:Binding(get:{model.editLogoEnabled},set:model.setEditLogoEnabled)).disabled(model.busy)}
                if let notes=e.notes {Text(notes).font(.callout).foregroundStyle(.secondary)}
                if model.project?.usesCameraReviews != true {
                    exportPage
                    revisionPanel
                }

            }
        }
    }
    var exportPage: some View {
        VStack(alignment:.leading,spacing:22) {
            card {
                label("BUILT FROM YOUR ORIGINALS")
                Text("One edit. Two destinations.").font(.system(size:26,weight:.semibold))
                Text("Output frame rate: \(model.outputRate) fps. Social and website exports use this rate. Your 8 fps AI copies are never used to render the final video.").font(.system(size:14)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Text("Shape: original source footage")
                if let title=model.plan?.title {Text("Selected edit: \(title)").font(.headline)}
                Text("Shots fit inside the frame by default. The AI can specify a crop when your idea calls for it.").font(.system(size:11)).foregroundStyle(.secondary)
            }
            HStack(alignment:.top,spacing:18) {
                card {
                    Image(systemName:"sparkles.tv").font(.system(size:30,weight:.light)).foregroundStyle(accent)
                    Text("Social").font(.system(size:24,weight:.semibold))
                    Text("High quality for sharing. Preserves fine detail and the original frame rate.").font(.system(size:13)).foregroundStyle(.secondary).frame(height:45,alignment:.top)
                    Picker("Size",selection:$model.resolution) { Text("Original resolution").tag("original");Text("Up to 1080p").tag("1080");Text("Up to 4K").tag("2160") }.labelsHidden()
                    Button("Export for Social") {model.render(.social)}.buttonStyle(.borderedProminent).controlSize(.large)
                }
                card {
                    Image(systemName:"iphone.gen3.radiowaves.left.and.right").font(.system(size:30,weight:.light)).foregroundStyle(accent)
                    Text("Website").font(.system(size:24,weight:.semibold))
                    Text("Smaller files for mobile visitors, plus a poster image and sample video embed.").font(.system(size:13)).foregroundStyle(.secondary).frame(height:45,alignment:.top)
                    Picker("Size",selection:$model.websiteQuality) {Text("Balanced · up to 720p").tag("balanced");Text("Smaller · up to 480p").tag("small")}.labelsHidden()
                    Toggle("Silent website video",isOn:$model.muteWebsite).font(.system(size:12))
                    Button("Export for Website") {model.render(.website)}.buttonStyle(.borderedProminent).controlSize(.large)
                }
            }.disabled(model.busy || model.plan == nil)
            if model.plan == nil {Text("Load an edit in step 02 to enable exports.").font(.system(size:13)).foregroundStyle(accent)}
            if let u=model.lastOutput {Button("Show Latest Video in Finder") {NSWorkspace.shared.activateFileViewerSelecting([u])}}
        }
    }
    var footer: some View {
        VStack(spacing:0) {
            if model.busy { ProgressView(value:model.progress).progressViewStyle(.linear).tint(accent) }
            HStack(spacing:10) {Circle().fill(model.busy ? accent:Color.green.opacity(0.7)).frame(width:6,height:6); Text(model.status).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2); Spacer(); if model.busy {ProgressView().controlSize(.small);Button("Cancel") {model.job.cancel()}.controlSize(.small)} }.padding(.horizontal,26).padding(.vertical,15)
        }.background(panelColor.opacity(0.5))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var studio: Studio!
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            studio = Studio(engine:Engine(tools:try Toolchain.locate()))
            let root = StudioView(model:studio)
            window = NSWindow(contentRect:NSRect(x:0,y:0,width:1120,height:800),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title = "ClipWeaver"; window.titlebarAppearsTransparent = true; window.backgroundColor = NSColor(calibratedRed:0.075,green:0.085,blue:0.105,alpha:1); window.contentView = NSHostingView(rootView:root); window.minSize = NSSize(width:980,height:690); window.center(); window.setFrameAutosaveName("ClipWeaverMain"); window.makeKeyAndOrderFront(nil)
            let main = NSMenu(); let appItem=NSMenuItem(); main.addItem(appItem); let appMenu=NSMenu(); appItem.submenu=appMenu
            appMenu.addItem(withTitle:"About ClipWeaver",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:""); appMenu.addItem(.separator()); appMenu.addItem(withTitle:"Quit ClipWeaver",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
            let editItem = NSMenuItem(); main.addItem(editItem); let edit = NSMenu(title:"Edit"); editItem.submenu=edit
            for (name,key,action) in [("Copy","c",#selector(NSText.copy(_:))),("Paste","v",#selector(NSText.paste(_:))),("Select All","a",#selector(NSText.selectAll(_:)))] {edit.addItem(withTitle:name,action:action,keyEquivalent:key)}
            NSApp.mainMenu=main; NSApp.activate(ignoringOtherApps:true)
        } catch { let alert=NSAlert(); alert.messageText="ClipWeaver could not start"; alert.informativeText=error.localizedDescription; alert.runModal(); NSApp.terminate(nil) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if studio?.busy == true {let alert=NSAlert();alert.messageText="A video task is running";alert.informativeText="Quit and cancel this task? You can run it again when you reopen the project.";alert.addButton(withTitle:"Keep Working");alert.addButton(withTitle:"Quit");if alert.runModal() == .alertFirstButtonReturn {return .terminateCancel};studio.job.cancel()};return .terminateNow
    }
    func application(_ sender:NSApplication,openFiles filenames:[String]) { DispatchQueue.main.async { self.studio?.handle(filenames.map{URL(fileURLWithPath:$0)}) } }
}
