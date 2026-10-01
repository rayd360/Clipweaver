import SwiftUI
import AVKit

struct EditChoice:Identifiable {var id:String;var plan:EditPlan;var preview:URL?}
extension Studio {
    var choices:[EditChoice] {
        guard let p=project,let root else{return []}
        return (p.editChoices ?? p.lastEditPath.map{[$0]} ?? []).compactMap {path in
            guard let edit=try? EditPlan.load(projectFile(path,root:root)) else{return nil}
            let preview=p.choicePreviews?[path].map{projectFile($0,root:root)}.flatMap{fm.fileExists(atPath:$0.path) ? $0:nil}
            return EditChoice(id:path,plan:edit,preview:preview)
        }
    }
    func selectChoice(_ choice:EditChoice) {restoreRevision(projectFile(choice.id,root:root!));status="Selected for export: \(choice.plan.title)"}
    func renderChoices() {
        guard let p=project,let root,!choices.isEmpty else{return}
        let choices=self.choices
        run({job,report -> [String:String] in
            var result=p.choicePreviews ?? [:]
            for (i,choice) in choices.enumerated() {
                if let preview=choice.preview {result[choice.id]=relativeProjectPath(preview,root:root);continue}
                var versionProject=p;versionProject.lastEditPath=choice.id
                if let music=choice.plan.music {versionProject.musicPath=relativeProjectPath(projectFile(choice.id,root:root).deletingLastPathComponent().appendingPathComponent(music.filename),root:root)}
                let settings=ExportSettings(kind:.preview,aspect:"source",includeLogo:!(p.logoHiddenEdits ?? []).contains(choice.id))
                let out=try self.engine.render(choice.plan,project:versionProject,root:root,settings:settings,job:job,progress:{text,value in report("Choice \(i+1) of \(choices.count): \(text)",(Double(i)+value)/Double(choices.count))})
                result[choice.id]=relativeProjectPath(out,root:root)
            };return result
        },finish:{previews in self.project?.choicePreviews=previews;try self.save();self.status="Choices ready. Hover to preview or play all together."})
    }
}
final class ChoicePlayback:ObservableObject {
    @Published var players:[String:AVPlayer]=[:]
    @Published var allPlaying=false
    var observers:[NSObjectProtocol]=[]
    func load(_ choices:[EditChoice]) {
        stop();observers.forEach{NotificationCenter.default.removeObserver($0)};observers=[]
        players=Dictionary(uniqueKeysWithValues:choices.compactMap {c -> (String,AVPlayer)? in
            guard let url=c.preview else{return nil};let player=AVPlayer(url:url);player.automaticallyWaitsToMinimizeStalling=false;player.isMuted=true;return(c.id,player)
        })
    }
    func stop() {players.values.forEach{$0.pause()};allPlaying=false}
    func hover(_ id:String,_ active:Bool) {guard !allPlaying,let player=players[id] else{return};player.isMuted=true;if active {player.seek(to:.zero);player.play()}else{player.pause()}}
    func playAll(selected:String?) {
        stop();allPlaying=true
        let group=DispatchGroup()
        for (id,p) in players {p.isMuted=id != selected;group.enter();p.seek(to:.zero,toleranceBefore:.zero,toleranceAfter:.zero){_ in group.leave()}}
        group.notify(queue:.main) {guard self.allPlaying else{return};let host=CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()),CMTime(seconds:0.3,preferredTimescale:600));for p in self.players.values {p.setRate(1,time:.zero,atHostTime:host)}}
    }
    deinit {players.values.forEach{$0.pause()};observers.forEach{NotificationCenter.default.removeObserver($0)}}
}
struct ChoiceVideoCanvas:NSViewRepresentable {
    let player:AVPlayer
    func makeNSView(context:Context)->ReferencePlayerCanvas {let view=ReferencePlayerCanvas(frame:.zero);view.videoLayer.player=player;return view}
    func updateNSView(_ view:ReferencePlayerCanvas,context:Context) {view.videoLayer.player=player}
    static func dismantleNSView(_ view:ReferencePlayerCanvas,coordinator:()) {view.videoLayer.player=nil}
}
struct ChoicesComparison:View {
    @ObservedObject var model:Studio
    @StateObject private var playback=ChoicePlayback()
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text("Your edit choices").font(.title2);Spacer();Button("Build previews",action:model.renderChoices).disabled(model.busy);Button(playback.allPlaying ? "Pause all":"Play all together") {if playback.allPlaying {playback.stop()}else{playback.playAll(selected:model.project?.lastEditPath)}}.disabled(playback.players.count != model.choices.count || playback.players.isEmpty)}
            Text("Hover for a silent preview. Play all starts every version together; only the selected version has sound. Select a version before exporting.").font(.caption).foregroundStyle(.secondary)
            HStack(alignment:.top,spacing:12) {
                ForEach(model.choices) {choice in
                    VStack(alignment:.leading,spacing:10) {
                        if let player=playback.players[choice.id] {ChoiceVideoCanvas(player:player).frame(height:220).onHover{playback.hover(choice.id,$0)}}
                        else {Rectangle().fill(Color.black).frame(height:220).overlay(Text("Preview not built yet").foregroundStyle(.secondary))}
                        Text(choice.plan.title).font(.headline).lineLimit(3)
                        Text("\(choice.plan.clips.count) shots · \(clockText(choice.plan.duration))").font(.caption)
                        Button(model.project?.lastEditPath==choice.id ? "Selected for export":"Select this version") {playback.stop();model.selectChoice(choice)}.buttonStyle(.borderedProminent).disabled(model.busy || model.project?.lastEditPath==choice.id)
                    }.frame(maxWidth:.infinity).padding(10).background(model.project?.lastEditPath==choice.id ? Color.orange.opacity(0.15):Color.white.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius:10))
                }
            }
        }.onChange(of:model.choices.map{$0.id+($0.preview?.path ?? "")}.joined(),initial:true){_,_ in playback.load(model.choices)}.onDisappear{playback.stop()}
    }
}
extension StudioView {var choiceGallery:some View {ChoicesComparison(model:model)}}
