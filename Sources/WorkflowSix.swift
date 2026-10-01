import SwiftUI
import AppKit
import AVKit

extension Studio {
    var selectedBrandLogoURL:URL? {guard let project,let root else{return globalAssets.logoURL};return try? resolvedLogo(project,root:root)}
    func setSuppressCaptions(_ off:Bool) {
        guard !busy else{return};project?.suppressCaptions=off;project?.choicePreviews=nil
        do {try save();status=off ? "Added captions hidden. Prepare again to tell AI not to create them.":"Captions enabled";if page==1 && plan != nil {renderChoices()}}catch{self.error=error.localizedDescription}
    }
    func selectBrand(_ id:String) {guard !busy else{return};project?.brandId=id;project?.choicePreviews=nil;do{try save();status="Brand selected. Prepare again to update AI's instructions."}catch{self.error=error.localizedDescription}}
    func setActiveBrand(_ id:String) {do{var g=try GlobalAssets.load();g.activeBrandId=id;try g.save();globalAssets=g}catch{self.error=error.localizedDescription}}
    func addBrand() {
        guard let name=askName("Name new brand",value:""),!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        do{var g=try GlobalAssets.load();let brand=BrandProfile(id:UUID().uuidString,name:String(name.prefix(100)));g.brands=g.brandProfiles+[brand];g.activeBrandId=brand.id;try g.save();globalAssets=g}catch{self.error=error.localizedDescription}
    }
    func renameBrand() {
        guard let name=askName("Rename brand",value:globalAssets.activeBrand.name),!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        do{var g=try GlobalAssets.load();var list=g.brandProfiles;if let i=list.firstIndex(where:{$0.id==g.activeBrand.id}) {list[i].name=String(name.prefix(100))};g.brands=list;try g.save();globalAssets=g}catch{self.error=error.localizedDescription}
    }
    func listenLibraryMusic(_ music:LibraryMusic) {musicPlayer?.pause();musicPlayer=AVPlayer(url:GlobalAssets.root.appendingPathComponent(music.file));musicPlayer?.play()}
    func deleteReference(_ ref:StyleReference) {
        do {var g=try GlobalAssets.load();let folder=GlobalAssets.root.appendingPathComponent(ref.video).deletingLastPathComponent();if fm.fileExists(atPath:folder.path){try fm.trashItem(at:folder,resultingItemURL:nil)};g.references.removeAll{$0.id==ref.id};try g.save();globalAssets=g;globalReferenceId="";if project?.styleReferenceId==ref.id {selectReference(nil)}}catch{self.error=error.localizedDescription}
    }
}
extension StudioView {
    var captionPreference:some View {
        VStack(alignment:.leading,spacing:6) {
            Toggle("Don’t include captions",isOn:Binding(get:{model.project?.suppressCaptions==true},set:model.setSuppressCaptions)).disabled(model.busy || model.project==nil)
            Text("Applies to AI instructions, all three previews and exports. Hides added animated captions and static overlays; keeps your logo, end card and lettering already in the footage.").font(.caption).foregroundStyle(.secondary)
        }
    }
    var projectBrandPicker:some View {
        Picker("Brand",selection:Binding(get:{model.project.map{model.globalAssets.brand(for:$0).id} ?? "rhythm-flash"},set:model.selectBrand)) {ForEach(model.globalAssets.brandProfiles) {Text($0.name).tag($0.id)}}.disabled(model.busy)
    }
    var brandManagement:some View {
        VStack(alignment:.leading,spacing:10) {
            Picker("Brand",selection:Binding(get:{model.globalAssets.activeBrand.id},set:model.setActiveBrand)) {ForEach(model.globalAssets.brandProfiles) {Text($0.name).tag($0.id)}}
            HStack {Button("Add Brand…",action:model.addBrand);Button("Rename Brand…",action:model.renameBrand)}
            Text("Projects choose their brand in Prepare for AI. Each brand keeps its own name and logo; music and style references are shared.").font(.caption).foregroundStyle(.secondary)
        }
    }
    var sharedMusicLibrary:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Text("Music library").font(.title2);Spacer();Button("Add Music…",action:model.addLibraryMusic)}
            Text("Manage reusable tracks here. Choose a track and starting time separately in each project's Prepare for AI screen.").foregroundStyle(.secondary)
            Picker("Saved music",selection:$model.globalMusicId) {
                Text("Choose a track").tag("")
                ForEach((model.globalAssets.music ?? []).sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}) {Text($0.name).tag($0.id)}
            }
            if let music=model.globalAssets.music?.first(where:{$0.id==model.globalMusicId}) {
                Text(music.name+" · "+clockText(music.duration)).font(.headline)
                HStack {Button("Listen"){model.listenLibraryMusic(music)};Button("Pause"){model.musicPlayer?.pause()};Button("Rename…"){model.renameMusic(music)};Button("Delete from Library",role:.destructive){model.deleteMusic(music);model.globalMusicId=""}}
            }
        }.disabled(model.busy)
    }
}
