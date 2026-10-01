import Foundation
import AppKit
import CryptoKit

func safeBasename(_ s: String) -> Bool {
    !s.isEmpty && s.count <= 200 && s != "." && s != ".." && !s.contains("/") && !s.contains("\\") && !s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
}
func projectFile(_ path: String, root: URL) -> URL { path.hasPrefix("/") ? URL(fileURLWithPath:path) : root.appendingPathComponent(path) }
func relativeProjectPath(_ url: URL, root: URL) -> String { let prefix=root.standardizedFileURL.path+"/"; let p=url.standardizedFileURL.path; return p.hasPrefix(prefix) ? String(p.dropFirst(prefix.count)) : p }
func prepareProjectFolders(_ root: URL) throws { for name in ["Incoming","Edits","Assets","Previews","Exports"] { try fm.createDirectory(at:root.appendingPathComponent(name),withIntermediateDirectories:true) } }

struct ProjectEntry: Identifiable {
    var id: String { root.path }
    var project: Project
    var root: URL
    var created: Date
    var modified: Date
    var managedBytes: Int64
    var needsDeletionConfirmation:Bool {Date().timeIntervalSince(created)<7*24*3600}
}
struct ProjectLibrary {
    var home: URL {
        if let path=ProcessInfo.processInfo.environment["CLIPWEAVER_LIBRARY"] { return URL(fileURLWithPath:path) }
        return fm.homeDirectoryForCurrentUser.appendingPathComponent("Movies/ClipWeaver Projects")
    }
    var registry: URL { home.appendingPathComponent(".projects.json") }
    func paths() -> [String] { (try? readJSON([String].self,registry)) ?? [] }
    func register(_ root: URL) throws {
        try fm.createDirectory(at:home,withIntermediateDirectories:true)
        var list=paths(); let path=root.standardizedFileURL.path
        if !list.contains(path) {list.append(path);try writeJSON(list,registry)}
    }
    func forget(_ root: URL) throws { try writeJSON(paths().filter{$0 != root.standardizedFileURL.path},registry) }
    func entries() -> [ProjectEntry] {
        let all=Set(paths())
        return all.compactMap { path in
            guard let (p,r)=try? Project.open(URL(fileURLWithPath:path,isDirectory:true)) else {return nil}
            let date=(try? r.appendingPathComponent("Project.clipweaver").resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return ProjectEntry(project:p,root:r,created:p.createdAt ?? ((try? r.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? date),modified:date,managedBytes:folderBytes(r))
        }.sorted{$0.modified > $1.modified}
    }
    func create(_ name: String) throws -> (Project,URL) {
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100 else {throw WeaverError("Give the project a name of 1–100 characters.")}
        let p=Project(name:name,createdAt:Date()), root=home.appendingPathComponent("\(cleanName(name)) — \(p.projectId.prefix(8))")
        try prepareProjectFolders(root);try p.save(root);try register(root);return (p,root)
    }
    func trash(_ entry: ProjectEntry) throws {
        let prefix=entry.root.resolvingSymlinksInPath().path+"/"
        guard !entry.project.sources.contains(where:{URL(fileURLWithPath:$0.originalPath).resolvingSymlinksInPath().path.hasPrefix(prefix)}) else {throw WeaverError("This older project contains an original video inside its folder. Move and relink that original before moving the project to Trash, or use Remove from List.")}
        try fm.trashItem(at:entry.root,resultingItemURL:nil);try forget(entry.root)
    }
}

struct ResponseAsset: Codable { var filename:String; var sha256:String; var base64:String }
struct AIResponse: Codable {
    var packageVersion:Int
    var edit:EditPlan
    var assets:[ResponseAsset]
    var edits:[EditPlan]? = nil
    var allEdits:[EditPlan] {edits ?? [edit]}
    static func load(_ url: URL) throws -> AIResponse {
        guard fileSize(url) > 0, fileSize(url) <= 150*1024*1024 else {throw WeaverError("The AI response is empty or exceeds 150 MB. Ask for a smaller response package.")}
        let data=try Data(contentsOf:url)
        guard let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any],let version=obj["package_version"] as? Int else {throw WeaverError("This is not a ClipWeaver response package.")}
        let editObjects:[[String:Any]]
        if version==1,Set(obj.keys)==Set(["package_version","edit","assets"]),let one=obj["edit"] as? [String:Any] {editObjects=[one]}
        else if version==2,Set(obj.keys)==Set(["package_version","edits","assets"]),let choices=obj["edits"] as? [[String:Any]],choices.count==3 {editObjects=choices}
        else {throw WeaverError("A new response must contain package_version 2, exactly three edits, and assets. Older single-edit version 1 responses are also supported.")}
        let scratch=fm.temporaryDirectory.appendingPathComponent("cw-edit-\(UUID().uuidString).json");defer{try? fm.removeItem(at:scratch)}
        var plans:[EditPlan]=[]
        for object in editObjects {try JSONSerialization.data(withJSONObject:object).write(to:scratch);plans.append(try EditPlan.load(scratch))}
        if version==2 {
            guard Set(plans.map(\.projectId)).count==1,Set(plans.map(\.title)).count==3 else {throw WeaverError("All three choices must belong to one project and have distinct titles.")}
            guard plans.allSatisfy({($0.aspect ?? "source")=="source" && ($0.fps ?? "source")=="source" && $0.music==nil}) else {throw WeaverError("New choices must keep source shape and fps, and omit AI music. Select your music in Prepare for AI.")}
        }
        guard let entries=obj["assets"] as? [[String:Any]],entries.count<=101,entries.allSatisfy({Set($0.keys)==Set(["filename","sha256","base64"])}) else {throw WeaverError("Invalid asset entries in response package.")}
        let assets=try jsonDecoder().decode([ResponseAsset].self,from:JSONSerialization.data(withJSONObject:entries))
        let package=AIResponse(packageVersion:version,edit:plans[0],assets:assets,edits:version==2 ? plans:nil)
        return package
    }
    func decodedAssets() throws -> [(String,Data)] {
        var seen=Set<String>(); var total=0
        return try assets.map { a in
            guard safeBasename(a.filename), a.filename != "edit.json", a.filename != "response.clipweaveredit", seen.insert(a.filename.lowercased()).inserted,
                  ["png","jpg","jpeg","m4a","mp3","wav","aac"].contains(URL(fileURLWithPath:a.filename).pathExtension.lowercased()),
                  let data=Data(base64Encoded:a.base64), !data.isEmpty else {throw WeaverError("Invalid or duplicate response asset: \(a.filename)")}
            total += data.count
            guard total<=100*1024*1024, SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==a.sha256 else {throw WeaverError("An AI response asset is damaged or too large: \(a.filename)")}
            return (a.filename,data)
        }
    }
}
extension Engine {
    func importResponse(_ url: URL, project: Project, root: URL, job: JobControl) throws -> (Project,EditPlan) {
        let response=try AIResponse.load(url);for edit in response.allEdits {try edit.validate(project)}
        let assets=try response.decodedAssets();let names=Set(assets.map{$0.0})
        var needed=Set<String>()
        for edit in response.allEdits {
            needed.formUnion((edit.overlays ?? []).compactMap(\.filename))
            if let n=edit.music?.filename {needed.insert(n)}
            if let n=edit.endCard?.filename {needed.insert(n)}
        }
        guard needed.isSubset(of:names) else {throw WeaverError("The response is missing: \(needed.subtracting(names).sorted().joined(separator:", ")). Ask AI to bundle every required asset.")}
        try prepareProjectFolders(root)
        let hash=try fingerprint(url,job:job)
        let dest=root.appendingPathComponent("Edits/\(hash.prefix(20))")
        var p=project
        if !fm.fileExists(atPath:dest.path) {
            let stage=root.appendingPathComponent(".response-\(UUID().uuidString)");try fm.createDirectory(at:stage,withIntermediateDirectories:true);defer{try? fm.removeItem(at:stage)}
            for (name,data) in assets {
                try job.check();let target=stage.appendingPathComponent(name);try data.write(to:target)
                if ["png","jpg","jpeg"].contains(target.pathExtension.lowercased()) { _ = try checkedImage(target) }
                else {
                    let info=try tools.run("ffprobe",["-v","error","-show_streams","-of","json",target.path],job:job)
                    guard let obj=try JSONSerialization.jsonObject(with:info) as? [String:Any], let streams=obj["streams"] as? [[String:Any]], streams.contains(where:{$0["codec_type"] as? String == "audio"}) else {throw WeaverError("\(name) is not a readable audio file.")}
                }
            }
            for (i,edit) in response.allEdits.enumerated() {try writeJSON(edit,stage.appendingPathComponent(i==0 ? "edit.json":"edit-\(i+1).json"))}
            try fm.copyItem(at:url,to:stage.appendingPathComponent("response.clipweaveredit"))
            try fm.moveItem(at:stage,to:dest)
        }
        p.editChoices=response.allEdits.indices.map {relativeProjectPath(dest.appendingPathComponent($0==0 ? "edit.json":"edit-\($0+1).json"),root:root)}
        p.choicePreviews=p.choicePreviews?.filter {p.editChoices?.contains($0.key)==true}
        p.lastEditPath=p.editChoices?.first
        p.musicPath=response.edit.music.map{relativeProjectPath(dest.appendingPathComponent($0.filename),root:root)}
        try p.save(root)
        return (p,response.edit)
    }
}

extension Engine {
    func packReview(_ folder:URL,root:URL,job:JobControl) throws -> URL {
        let temporary=root.appendingPathComponent(".upload-\(UUID().uuidString).zip");defer{try? fm.removeItem(at:temporary)}
        try Toolchain(root:URL(fileURLWithPath:"/usr/bin")).run("ditto",["-c","-k","--keepParent","--norsrc",folder.path,temporary.path],job:job)
        let zip=root.appendingPathComponent("Upload to AI.zip")
        if fm.fileExists(atPath:zip.path) {_ = try fm.replaceItemAt(zip,withItemAt:temporary)} else {try fm.moveItem(at:temporary,to:zip)}
        return zip
    }
}

func folderBytes(_ root:URL) -> Int64 {
    guard let files=fm.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey,.fileSizeKey,.totalFileAllocatedSizeKey,.fileAllocatedSizeKey],options:[]) else{return 0}
    var total:Int64=0
    for case let u as URL in files {if let v=try? u.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey,.totalFileAllocatedSizeKey,.fileAllocatedSizeKey]),v.isRegularFile==true {total+=Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)}}
    return total
}
extension Project {
    func organizeAssets(root:URL) throws -> Project {
        try prepareProjectFolders(root)
        var p=self
        let prefix=root.standardizedFileURL.path+"/"
        if let path=lastEditPath {
            let editURL=projectFile(path,root:root)
            if fm.fileExists(atPath:editURL.path) {
                if !editURL.standardizedFileURL.path.hasPrefix(prefix) {
                    let dest=root.appendingPathComponent("Edits/Legacy-\(UUID().uuidString)");try fm.createDirectory(at:dest,withIntermediateDirectories:true)
                    try fm.copyItem(at:editURL,to:dest.appendingPathComponent("edit.json"));p.lastEditPath=relativeProjectPath(dest.appendingPathComponent("edit.json"),root:root)
                } else {p.lastEditPath=relativeProjectPath(editURL,root:root)}
            }
        }
        if let path=musicPath {
            let u=projectFile(path,root:root)
            if fm.fileExists(atPath:u.path) {
                if !u.standardizedFileURL.path.hasPrefix(prefix) {
                    let dest=root.appendingPathComponent("Assets/Music/\(UUID().uuidString)");try fm.createDirectory(at:dest,withIntermediateDirectories:true)
                    let target=dest.appendingPathComponent(u.lastPathComponent);try fm.copyItem(at:u,to:target);p.musicPath=relativeProjectPath(target,root:root)
                } else {p.musicPath=relativeProjectPath(u,root:root)}
            }
        }
        try p.save(root);return p
    }
}

struct IncomingResponse {var url:URL;var imported:Bool;var editURL:URL}
extension Engine {
    func findIncoming(project:Project,root:URL,job:JobControl) throws -> IncomingResponse? {
        let folder=root.appendingPathComponent("Incoming")
        let urls=((try? fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.contentModificationDateKey],options:.skipsHiddenFiles)) ?? []).filter{$0.pathExtension.lowercased()=="clipweaveredit"}.sorted {a,b in
            let da=(try? a.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db=(try? b.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da==db ? a.lastPathComponent<b.lastPathComponent:da>db
        }
        var errors:[String]=[];var existing:IncomingResponse?=nil
        for url in urls {
            try job.check()
            do {
                let hash=try fingerprint(url,job:job),editURL=root.appendingPathComponent("Edits/\(hash.prefix(20))/edit.json")
                if fm.fileExists(atPath:editURL.path) {let edit=try EditPlan.load(editURL);try edit.validate(project);if existing==nil {existing=IncomingResponse(url:url,imported:true,editURL:editURL)};continue}
                let response=try AIResponse.load(url);for edit in response.allEdits {try edit.validate(project)};_ = try response.decodedAssets()
                let names=Set(response.assets.map(\.filename))
                var needed=Set<String>();for edit in response.allEdits {needed.formUnion((edit.overlays ?? []).compactMap(\.filename));if let name=edit.music?.filename {needed.insert(name)};if let name=edit.endCard?.filename {needed.insert(name)}}
                guard needed.isSubset(of:names) else {throw WeaverError("Response is missing required assets.")}
                return IncomingResponse(url:url,imported:false,editURL:editURL)
            } catch {errors.append("\(url.lastPathComponent): \(error.localizedDescription)")}
        }
        if !errors.isEmpty {throw WeaverError("An Incoming response is damaged or incomplete. Your current edit has not been replaced. Finish the download or ask AI to regenerate it.\n\n"+errors.prefix(2).joined(separator:"\n"))}
        return existing
    }
}
