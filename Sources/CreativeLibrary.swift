import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers

struct LibraryMusic:Codable,Identifiable {var id:String;var name:String;var file:String;var duration:Double}
struct SavedIdea:Codable,Identifiable {var id:String;var name:String;var text:String}
struct ProjectMusic:Codable {var id:String;var name:String;var path:String;var duration:Double;var start:Double;var volume:Double=0.3}
struct ReviewMusic:Codable {var name:String;var file:String;var duration:Double;var start:Double;var loop:Bool=true;var instruction:String="User-selected music. Never generate or replace it. Plan all three edits to its rhythm starting at start seconds. ClipWeaver applies and loops it locally; omit music from edit JSON."}
func withSelectedMusic(_ edit:EditPlan,project:Project)->EditPlan {
    var e=edit
    if project.suppressCaptions == true {e.captions=nil;e.captionStyles=nil;e.overlays=nil}
    if !project.usesCameraReviews,let m=project.selectedMusic {e.music=MusicPlan(filename:URL(fileURLWithPath:m.path).lastPathComponent,start:m.start,volume:m.volume,fadeIn:min(0.3,e.duration/4),fadeOut:min(0.8,e.duration/4),duck:true,loop:true)}
    return e
}
extension Engine {
    func importMusic(_ url:URL,name:String,job:JobControl)throws->LibraryMusic {
        let id=UUID().uuidString,folder=GlobalAssets.root.appendingPathComponent("Music/\(id)")
        try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        var complete=false;defer{if !complete {try? fm.removeItem(at:folder)}}
        let out=folder.appendingPathComponent("track.m4a")
        try tools.ffmpeg(["-i",url.path,"-map","0:a:0","-vn","-c:a","aac","-b:a","192k","-ar","48000","-ac","2",out.path],job:job)
        let data=try tools.run("ffprobe",["-v","error","-show_format","-of","json",out.path],job:job)
        let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any]
        guard let f=obj?["format"] as? [String:Any],let duration=Double(f["duration"] as? String ?? ""),duration.isFinite,duration>0 else {throw WeaverError("This file does not contain readable music.")}
        complete=true;return LibraryMusic(id:id,name:name,file:"Music/\(id)/track.m4a",duration:duration)
    }
    func prepareReviewMusic(_ project:Project,root:URL,folder:URL,job:JobControl)throws->ReviewMusic? {
        guard let m=project.selectedMusic else{return nil}
        let dir=folder.appendingPathComponent("music");try fm.createDirectory(at:dir,withIntermediateDirectories:true)
        let out=dir.appendingPathComponent("selected-track.m4a")
        try tools.ffmpeg(["-i",projectFile(m.path,root:root).path,"-vn","-c:a","aac","-b:a","96k",out.path],job:job)
        return ReviewMusic(name:m.name,file:"music/selected-track.m4a",duration:m.duration,start:m.start)
    }
}
extension Studio {
    func saveCreativeState() {if let root,let project {do{try project.save(root)}catch{self.error=error.localizedDescription}}}
    func addLibraryMusic() {
        guard !busy else{return};let panel=NSOpenPanel();panel.title="Add music to your library";panel.allowedContentTypes=[.audio,.movie]
        guard panel.runModal() == .OK,let url=panel.url,let name=askName("Name this music",value:url.deletingPathExtension().lastPathComponent),!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        run({job,report in report("Saving music for reuse",0.2);return try self.engine.importMusic(url,name:String(name.prefix(100)),job:job)},finish:{music in
            var g=try GlobalAssets.load();g.music=(g.music ?? [])+[music];try g.save();self.globalAssets=g;if self.page != 3 {self.selectMusic(music)}else{self.globalMusicId=music.id;self.status="Music saved in the shared library"}
        })
    }
    func selectMusic(_ music:LibraryMusic?) {
        guard !busy,let root else{return}
        do {
            musicPlayer?.pause();musicPlayer=nil
            if let music {
                let path="Assets/Music/\(music.id)/track.m4a",out=root.appendingPathComponent(path)
                try fm.createDirectory(at:out.deletingLastPathComponent(),withIntermediateDirectories:true)
                if !fm.fileExists(atPath:out.path) {try fm.copyItem(at:GlobalAssets.root.appendingPathComponent(music.file),to:out)}
                project?.selectedMusic=ProjectMusic(id:music.id,name:music.name,path:path,duration:music.duration,start:0)
            }else{project?.selectedMusic=nil}
            project?.choicePreviews=nil;try save();status="Music selection saved. Prepare again to update AI's review."
        }catch{self.error=error.localizedDescription}
    }
    func updateMusicStart(_ value:Double) {
        guard value.isFinite,var m=project?.selectedMusic else{return}
        m.start=min(max(0,value),max(0,m.duration-0.05));project?.selectedMusic=m;project?.choicePreviews=nil
        saveCreativeState()
        musicPlayer?.seek(to:CMTime(seconds:m.start,preferredTimescale:600))
    }
    func listenMusic() {
        guard let m=project?.selectedMusic,let root else{return}
        musicPlayer?.pause();let player=AVPlayer(url:projectFile(m.path,root:root));musicPlayer=player
        player.seek(to:CMTime(seconds:m.start,preferredTimescale:600));player.play()
    }
    func renameMusic(_ music:LibraryMusic) {
        guard let name=askName("Rename music",value:music.name),!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        do {var g=try GlobalAssets.load();if let i=g.music?.firstIndex(where:{$0.id==music.id}) {g.music?[i].name=String(name.prefix(100))};try g.save();globalAssets=g}catch{self.error=error.localizedDescription}
    }
    func deleteMusic(_ music:LibraryMusic) {
        do {var g=try GlobalAssets.load();let folder=GlobalAssets.root.appendingPathComponent(music.file).deletingLastPathComponent();if fm.fileExists(atPath:folder.path){try fm.trashItem(at:folder,resultingItemURL:nil)};g.music?.removeAll{$0.id==music.id};try g.save();globalAssets=g;status="Music removed from library. Project copies remain available."}catch{self.error=error.localizedDescription}
    }
    func saveIdea(asNew:Bool) {
        guard let text=project?.videoIdea,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{error="Write your video idea first.";return}
        do {
            var g=try GlobalAssets.load();let existing=project?.savedIdeaId.flatMap{id in g.ideas?.first{$0.id==id}}
            if !asNew,let existing,let index=g.ideas?.firstIndex(where:{$0.id==existing.id}) {g.ideas?[index].text=text}
            else {guard let name=askName("Name saved video idea",value:existing?.name ?? "My video idea"),!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return};let idea=SavedIdea(id:UUID().uuidString,name:String(name.prefix(100)),text:text);g.ideas=(g.ideas ?? [])+[idea];project?.savedIdeaId=idea.id}
            try g.save();globalAssets=g;try save();status="Video idea saved for reuse"
        }catch{self.error=error.localizedDescription}
    }
    func useIdea(_ idea:SavedIdea) {project?.videoIdea=idea.text;project?.savedIdeaId=idea.id;do{try save()}catch{self.error=error.localizedDescription}}
    func renameIdea(_ idea:SavedIdea) {guard let name=askName("Rename saved idea",value:idea.name),!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return};do{var g=try GlobalAssets.load();if let i=g.ideas?.firstIndex(where:{$0.id==idea.id}){g.ideas?[i].name=String(name.prefix(100))};try g.save();globalAssets=g}catch{self.error=error.localizedDescription}}
    func deleteIdea(_ idea:SavedIdea) {do{var g=try GlobalAssets.load();g.ideas?.removeAll{$0.id==idea.id};try g.save();globalAssets=g;if project?.savedIdeaId==idea.id {project?.savedIdeaId=nil;try save()}}catch{self.error=error.localizedDescription}}
}
extension StudioView {
    var musicGallery:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text("Music library · optional").font(.title2);Spacer();Button("Add Music…",action:model.addLibraryMusic)}
            Text("Choose your own track. It is saved for other projects and copied into this project. Longer edits loop the song automatically; AI never composes music.").foregroundStyle(.secondary)
            Picker("Saved music",selection:Binding(get:{model.project?.selectedMusic?.id ?? ""},set:{id in model.selectMusic(model.globalAssets.music?.first{$0.id==id})})) {
                Text("No music").tag("")
                ForEach((model.globalAssets.music ?? []).sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}) {Text($0.name).tag($0.id)}
                if let selected=model.project?.selectedMusic,!(model.globalAssets.music ?? []).contains(where:{$0.id==selected.id}) {Text(selected.name+" (project copy)").tag(selected.id)}
            }
            if let selected=model.project?.selectedMusic,let entry=model.globalAssets.music?.first(where:{$0.id==selected.id}) {
                HStack {Button("Rename…"){model.renameMusic(entry)};Button("Delete from Library",role:.destructive){model.deleteMusic(entry)}}
            }
            if let music=model.project?.selectedMusic {
                Text("Selected: \(music.name)").font(.headline)
                HStack {Text("Start at (seconds)");TextField("Start",value:Binding(get:{model.project?.selectedMusic?.start ?? 0},set:model.updateMusicStart),format:.number).frame(width:90);Text("of \(clockText(music.duration))")}
                Slider(value:Binding(get:{model.project?.selectedMusic?.start ?? 0},set:model.updateMusicStart),in:0...max(0.01,music.duration-0.05))
                HStack {Button("Listen from start",action:model.listenMusic);Button("Pause"){model.musicPlayer?.pause()};Button("No music"){model.selectMusic(nil)}}
            }
        }.disabled(model.busy)
    }
    var ideaLibrary:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("My video idea").font(.title2)
            Text(model.project?.usesCameraReviews == true ? "Describe the activity you want to find, such as people interacting, reactions or useful movement. Save it to reuse on future recordings." : "Describe the audience, length, mood and message once. Save ideas to reuse and adapt for future projects.").foregroundStyle(.secondary)
            Picker("Saved video ideas",selection:Binding(get:{model.project?.savedIdeaId ?? ""},set:{id in if let idea=model.globalAssets.ideas?.first(where:{$0.id==id}) {model.useIdea(idea)}else{model.project?.savedIdeaId=nil;model.saveCreativeState()}})) {
                Text("Custom idea").tag("")
                ForEach((model.globalAssets.ideas ?? []).sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}) {Text($0.name).tag($0.id)}
            }
            if let id=model.project?.savedIdeaId,let idea=model.globalAssets.ideas?.first(where:{$0.id==id}) {
                HStack {Button("Rename…"){model.renameIdea(idea)};Button("Delete Saved Idea",role:.destructive){model.deleteIdea(idea)}}
            }
            TextEditor(text:Binding(get:{model.project?.videoIdea ?? ""},set:{model.project?.videoIdea=String($0.prefix(12000));model.saveCreativeState()})).frame(height:110).border(Color.gray.opacity(0.4))
            HStack {Button("Save as New Idea…"){model.saveIdea(asNew:true)};if model.project?.savedIdeaId != nil {Button("Update Saved Idea"){model.saveIdea(asNew:false)}};Button("Clear"){model.project?.videoIdea="";model.project?.savedIdeaId=nil;try? model.save()}}
            Text(model.project?.usesCameraReviews == true ? "AI returns three selections of useful moments with original-file times and activity notes." : "Shape always follows your source footage. Music is controlled by your selection above. The AI makes three distinct versions of this idea.").font(.caption).foregroundStyle(.secondary)
        }.disabled(model.busy || model.project==nil)
    }
}
