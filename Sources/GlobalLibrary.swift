import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers

struct StyleReference: Codable, Identifiable {
    var id:String
    var name:String
    var video:String
    var thumbnail:String
    var media:MediaInfo
    var bytes:Int64
}
struct BrandProfile:Codable,Identifiable {
    var id:String;var name:String;var logoPath:String? = nil
    var reviewValue:BrandProfile {BrandProfile(id:id,name:name)}
}
struct GlobalAssets: Codable {
    var brands:[BrandProfile]? = nil
    var activeBrandId:String? = nil
    var brandProfiles:[BrandProfile] {(brands?.isEmpty == false ? brands:nil) ?? [BrandProfile(id:"rhythm-flash",name:"Rhythm & Flash Events",logoPath:logoPath)]}
    var activeBrand:BrandProfile {brandProfiles.first{$0.id==(activeBrandId ?? "rhythm-flash")} ?? brandProfiles[0]}
    func brand(for project:Project)->BrandProfile {brandProfiles.first{$0.id==(project.brandId ?? "rhythm-flash")} ?? brandProfiles[0]}
    mutating func setBrandLogo(_ path:String?) {var list=brandProfiles;if let i=list.firstIndex(where:{$0.id==activeBrand.id}) {list[i].logoPath=path};if activeBrand.id=="rhythm-flash" {logoPath=path};brands=list}
    var music:[LibraryMusic]? = nil
    var ideas:[SavedIdea]? = nil
    var logoPath:String? = nil
    var references:[StyleReference] = []
    static var root:URL {if let path=ProcessInfo.processInfo.environment["CLIPWEAVER_GLOBAL"] {return URL(fileURLWithPath:path)};return fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ClipWeaver/Global")}
    static var file:URL {root.appendingPathComponent("Library.json")}
    static func load() throws -> GlobalAssets {fm.fileExists(atPath:file.path) ? try readJSON(GlobalAssets.self,file):GlobalAssets()}
    func save() throws {try fm.createDirectory(at:Self.root,withIntermediateDirectories:true);try writeJSON(self,Self.file)}
    var logoURL:URL? {activeBrand.logoPath.map{Self.root.appendingPathComponent($0)}}
}
func resolvedLogo(_ project:Project,root:URL) throws -> URL? {
    if fm.fileExists(atPath:GlobalAssets.file.path) {return try GlobalAssets.load().brand(for:project).logoPath.map{GlobalAssets.root.appendingPathComponent($0)}}
    return project.logoPath.map{projectFile($0,root:root)} // Legacy edits before global branding is configured.
}
struct ReviewReference:Codable {
    var id:String;var name:String;var file:String;var duration:Double;var fps:String;var width:Int;var height:Int
    var role:String = "style_reference_only"
    var instruction:String = "Mock the pacing, shot rhythm, caption treatment and structure with the project's source footage. Do not include reference footage, copy its wording or branding, or treat it as a source_id. Adapt to the user's idea and supported edit operations."
}
extension Engine {
    func importReference(_ url:URL,name:String,job:JobControl,progress:ProgressReport) throws -> StyleReference {
        let info=try probe(url,tools:tools)
        guard info.duration>0,info.duration<=600 else {throw WeaverError("Reference videos must be ten minutes or shorter. Choose a representative excerpt.")}
        let id=UUID().uuidString,folder=GlobalAssets.root.appendingPathComponent("References/\(id)")
        try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        var completed=false;defer{if !completed {try? fm.removeItem(at:folder)}}
        let original=SourceClip(id:"REFERENCE",filename:url.lastPathComponent,originalPath:url.path,sha256:"",bytes:fileSize(url),media:info)
        let hdr=folder.appendingPathComponent(".hdr")
        defer{try? fm.removeItem(at:hdr)}
        progress("Making detailed reference copy at original frame rate",0.1)
        let input=try editingSource(original,temporaryFolder:hdr,job:job)
        let out=folder.appendingPathComponent("reference.mp4")
        let args=["-i",input.originalPath,"-map","0:v:0","-map","0:a:0?","-vf","scale=w='min(1080,iw)':h='min(1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1","-fps_mode","passthrough","-c:v","libx264","-preset","slow","-crf","20","-pix_fmt","yuv420p","-c:a","aac","-b:a","128k","-movflags","+faststart",out.path]
        // No fps filter or -r: preserve source frame cadence, including VFR.
        try tools.ffmpeg(args,job:job)
        let result=try probe(out,tools:tools)
        guard abs(result.duration-info.duration)<0.25,abs(result.fpsValue-info.fpsValue)<max(0.1,info.fpsValue*0.01) else {throw WeaverError("Reference conversion changed timing or frame rate; it was not added.")}
        let thumbnail=folder.appendingPathComponent("thumbnail.jpg")
        try tools.ffmpeg(["-ss",num(min(0.5,info.duration/2)),"-i",out.path,"-frames:v","1","-vf","scale=320:320:force_original_aspect_ratio=decrease","-q:v","2",thumbnail.path],job:job)
        completed=true;progress("Reference video ready",1)
        return StyleReference(id:id,name:name,video:"References/\(id)/reference.mp4",thumbnail:"References/\(id)/thumbnail.jpg",media:result,bytes:fileSize(out))
    }
}
extension Studio {
    func refreshGlobal() {do{globalAssets=try GlobalAssets.load()}catch{self.error="Global library could not be read: \(error.localizedDescription)"}}
    func chooseGlobalLogo() {
        guard !busy else{return};let p=NSOpenPanel();p.title="Choose Global Brand Logo";p.allowedContentTypes=[.png,.jpeg]
        guard p.runModal() == .OK,let url=p.url else{return};storeGlobalLogo(url)
    }
    func storeGlobalLogo(_ url:URL) {do {var assets=try GlobalAssets.load();assets.setBrandLogo(try saveProjectLogo(url,root:GlobalAssets.root));try assets.save();globalAssets=assets;status="Brand logo updated. Prepare again to refresh AI packages."}catch{self.error=error.localizedDescription}}
    func removeGlobalLogo() {do{var assets=try GlobalAssets.load();assets.setBrandLogo(nil);try assets.save();globalAssets=assets;status="Global logo removed. Existing files remain available in the library folder."}catch{self.error=error.localizedDescription}}
    func addReference() {
        guard !busy else{return};let p=NSOpenPanel();p.title="Add Style Reference Video";p.allowedContentTypes=[.movie,.mpeg4Movie,.quickTimeMovie]
        guard p.runModal() == .OK,let url=p.url,let name=askName("Name reference video",value:url.deletingPathExtension().lastPathComponent) else{return}
        let clean=name.trimmingCharacters(in:.whitespacesAndNewlines);guard !clean.isEmpty,clean.count<=100 else{error="Use a name of 1–100 characters.";return}
        run({job,report in try self.engine.importReference(url,name:clean,job:job,progress:report)},finish:{ref in var assets=try GlobalAssets.load();assets.references.append(ref);try assets.save();self.globalAssets=assets;self.globalReferenceId=ref.id;if self.page==0 {self.selectReference(ref.id)};self.status="Reference saved in your library."})
    }
    func renameReference(_ ref:StyleReference) {guard let name=askName("Rename reference",value:ref.name) else{return};let clean=name.trimmingCharacters(in:.whitespacesAndNewlines);guard !clean.isEmpty,clean.count<=100 else{error="Use a name of 1–100 characters.";return};do{var assets=try GlobalAssets.load();if let i=assets.references.firstIndex(where:{$0.id==ref.id}) {assets.references[i].name=clean};try assets.save();globalAssets=assets}catch{self.error=error.localizedDescription}}
    func selectReference(_ id:String?) {guard !busy else{return};project?.styleReferenceId=id;do{try save();status="Reference selection saved. Prepare for AI again to update the upload ZIP."}catch{self.error=error.localizedDescription}}
}
final class ReferencePlayerCanvas:NSView {
    let videoLayer=AVPlayerLayer()
    var playback:AVQueuePlayer?
    var looping:AVPlayerLooper?
    override init(frame:NSRect) {super.init(frame:frame);wantsLayer=true;videoLayer.videoGravity = .resizeAspect;layer?.addSublayer(videoLayer)}
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    override func layout() {super.layout();videoLayer.frame=bounds}
    func start(_ url:URL) {let player=AVQueuePlayer();player.isMuted=true;playback=player;looping=AVPlayerLooper(player:player,templateItem:AVPlayerItem(url:url));videoLayer.player=player;player.play()}
    func stop() {playback?.pause();looping?.disableLooping();looping=nil;videoLayer.player=nil;playback=nil}
}
struct HoverReferenceVideo:NSViewRepresentable {
    let url:URL
    func makeNSView(context:Context)->ReferencePlayerCanvas {let view=ReferencePlayerCanvas(frame:.zero);view.start(url);return view}
    func updateNSView(_ view:ReferencePlayerCanvas,context:Context) {}
    static func dismantleNSView(_ view:ReferencePlayerCanvas,coordinator:()) {view.stop()}
}
struct ReferenceTile:View {
    let reference:StyleReference;let selected:Bool;let select:(()->Void)?;let rename:()->Void
    @State private var hovering=false
    var body:some View {
        HStack(spacing:12) {
            ZStack {
                if hovering {HoverReferenceVideo(url:GlobalAssets.root.appendingPathComponent(reference.video))}
                else if let im=NSImage(contentsOf:GlobalAssets.root.appendingPathComponent(reference.thumbnail)) {Image(nsImage:im).resizable().scaledToFit()}
                else {Image(systemName:"film")}
            }.frame(width:140,height:105).background(Color.black).clipShape(RoundedRectangle(cornerRadius:8)).onHover{hovering=$0}.onDisappear{hovering=false}
            VStack(alignment:.leading,spacing:7) {
                Text(reference.name).font(.headline).lineLimit(2).help(reference.name)
                Text("\(clockText(reference.media.duration)) · \(reference.media.fps) fps · \(humanSize(reference.bytes))").font(.caption).foregroundStyle(.secondary)
                HStack {if let select {Button(selected ? "Selected":"Use reference",action:select).disabled(selected)};Button("Play") {NSWorkspace.shared.open(GlobalAssets.root.appendingPathComponent(reference.video))};Button("Rename…",action:rename)}
            };Spacer(minLength:0)
        }.padding(12).background(selected ? Color.orange.opacity(0.17):Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius:10))
    }
}
extension StudioView {
    var globalPage:some View {
        VStack(alignment:.leading,spacing:20) {
            Text("Branding & References").font(.largeTitle)
            Text("Set your brand once. Keep a reusable library of videos whose editing style you want AI to mock.").foregroundStyle(.secondary)
            card {
                brandManagement
                label("BRAND LOGO")
                HStack {
                    if let u=model.globalAssets.logoURL,let im=NSImage(contentsOf:u) {Image(nsImage:im).resizable().scaledToFit().frame(width:120,height:90)}
                    VStack(alignment:.leading,spacing:10) {
                        Text("Used by projects selecting this brand; each edit can still hide it.")
                        HStack {Button("Choose Logo…",action:model.chooseGlobalLogo);if model.globalAssets.logoURL != nil {Button("Remove Logo",action:model.removeGlobalLogo)}}
                        if model.globalAssets.logoURL==nil {
                            Menu("Use an existing project's logo") {ForEach(model.projects.filter{$0.project.logoPath != nil}) {entry in Button(entry.project.name) {model.storeGlobalLogo(projectFile(entry.project.logoPath!,root:entry.root))}}}
                        }
                    }
                }
            }
            referenceGallery(global:true)
            sharedMusicLibrary
        }.disabled(model.busy)
    }
    func referenceGallery(global:Bool)->some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text(global ? "Reference video library":"Style reference · optional").font(.title2);Spacer();if global {Button("Add Reference Video…",action:model.addReference)}else{Button("Manage library") {model.showingProjects=false;model.page=3;model.refreshGlobal()}}}
            Text(global ? "Detailed 1080-pixel copies preserve original frame cadence and audio. Hover a thumbnail for silent playback; Play opens the full video. Originals are never changed or stored here." : "Select one video for AI to mock using your own footage. Only the selected reference travels with this project's AI upload.").font(.callout).foregroundStyle(.secondary)
            Picker("Saved style references",selection:Binding(get:{global ? model.globalReferenceId:(model.project?.styleReferenceId ?? "")},set:{id in if global {model.globalReferenceId=id}else{model.selectReference(id.isEmpty ? nil:id)}})) {
                Text(global ? "Choose a reference":"No reference").tag("")
                ForEach(model.globalAssets.references.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}) {Text($0.name).tag($0.id)}
            }
            if let ref=model.globalAssets.references.first(where:{$0.id==(global ? model.globalReferenceId:(model.project?.styleReferenceId ?? ""))}) {
                ReferenceTile(reference:ref,selected:false,select:nil,rename:{model.renameReference(ref)}).id(ref.id)
                if global {Button("Delete from Library",role:.destructive){model.deleteReference(ref)}}
            }
            if !global {Button("Add Reference Video…",action:model.addReference)}

        }.disabled(model.busy)
    }
}
