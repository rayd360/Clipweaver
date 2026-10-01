import Foundation
import CryptoKit
import AppKit

struct WeaverError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
let fm = FileManager.default
func jsonEncoder() -> JSONEncoder { let e = JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase; e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return e }
func jsonDecoder() -> JSONDecoder { let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d }
func writeJSON<T: Encodable>(_ value: T, _ url: URL) throws { try jsonEncoder().encode(value).write(to: url, options: .atomic) }
func readJSON<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T { try jsonDecoder().decode(type, from: Data(contentsOf: url)) }
func num(_ v: Double) -> String { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), v) }
func clockText(_ seconds: Double) -> String { let ms = Int((max(0, seconds) * 1000).rounded()); return String(format: "%02d:%02d:%02d.%03d", ms/3600000, (ms/60000)%60, (ms/1000)%60, ms%1000) }
func humanSize(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
func fileSize(_ url: URL) -> Int64 { ((try? fm.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0 }
func cleanName(_ text: String) -> String { let s = text.replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces); return String((s.isEmpty ? "My Video" : s).prefix(70)) }
func uniqueURL(_ parent: URL, _ stem: String, _ ext: String) -> URL { var u = parent.appendingPathComponent(stem).appendingPathExtension(ext); var n = 2; while fm.fileExists(atPath: u.path) { u = parent.appendingPathComponent("\(stem) \(n)").appendingPathExtension(ext); n += 1 }; return u }

final class JobControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func check() throws { lock.lock(); let c = cancelled; lock.unlock(); if c { throw WeaverError("Cancelled. Your original files are safe. You can run this step again.") } }
    func attach(_ p: Process) throws { lock.lock(); defer { lock.unlock() }; if cancelled { throw WeaverError("Cancelled.") }; process = p }
    func launched(_ p: Process) { lock.lock(); defer { lock.unlock() }; if cancelled && p.isRunning { p.terminate() } }
    func detach() { lock.lock(); process = nil; lock.unlock() }
    func cancel() { lock.lock(); cancelled = true; if let p = process, p.isRunning { p.terminate() }; lock.unlock() }
}

struct Toolchain {
    let root: URL
    static func locate() throws -> Toolchain {
        if let r = Bundle.main.resourceURL, fm.isExecutableFile(atPath: r.appendingPathComponent("bin/ffmpeg").path) { return Toolchain(root: r.appendingPathComponent("bin")) }
        if let p = ProcessInfo.processInfo.environment["CLIPWEAVER_TOOLS"] { return Toolchain(root: URL(fileURLWithPath: p)) }
        throw WeaverError("The bundled video tools are missing. Please rebuild or reinstall ClipWeaver.")
    }
    @discardableResult func run(_ name: String, _ args: [String], job: JobControl = JobControl()) throws -> Data {
        try job.check()
        let p = Process(); p.executableURL = root.appendingPathComponent(name); p.arguments = args
        let output = Pipe(); p.standardOutput = output
        let errorURL = fm.temporaryDirectory.appendingPathComponent("clipweaver-\(UUID().uuidString).log")
        fm.createFile(atPath: errorURL.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorURL); p.standardError = errorHandle; p.standardInput = FileHandle.nullDevice
        defer { try? errorHandle.close(); try? fm.removeItem(at: errorURL); job.detach() }
        try job.attach(p); try p.run(); job.launched(p)
        let data = output.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); try job.check()
        if p.terminationStatus != 0 {
            let detail = String(data: (try? Data(contentsOf: errorURL)) ?? Data(), encoding: .utf8) ?? ""
            throw WeaverError("Video processing could not finish.\n\n\(detail.suffix(2800))")
        }
        return data
    }
    func ffmpeg(_ args: [String], job: JobControl) throws { try run("ffmpeg", ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-threads", "4", "-filter_threads", "2", "-filter_complex_threads", "2"] + args, job: job) }
}

struct MediaInfo: Codable {
    var duration: Double
    var width: Int
    var height: Int
    var fps: String
    var hasAudio: Bool
    var hdr: Bool
    var videoStart: Double
    var audioStart: Double
    var fpsValue: Double { rateValue(fps) }
}
func rateValue(_ text: String) -> Double { let parts = text.split(separator: "/").compactMap { Double($0) }; return parts.count == 2 && parts[1] != 0 ? parts[0]/parts[1] : (Double(text) ?? 0) }
func canonicalRate(_ rate: Double) -> String { for s in ["24000/1001", "24", "25", "30000/1001", "30", "48", "50", "60000/1001", "60", "120000/1001", "120"] { if abs(rateValue(s) - rate) < 0.015 { return s } }; return num(rate) }
func probe(_ url: URL, tools: Toolchain, job: JobControl = JobControl()) throws -> MediaInfo {
    let data = try tools.run("ffprobe", ["-v", "error", "-show_streams", "-show_format", "-of", "json", url.path], job: job)
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let streams = obj["streams"] as? [[String: Any]], let v = streams.first(where: { ($0["codec_type"] as? String) == "video" && (($0["disposition"] as? [String:Any])?["attached_pic"] as? Int ?? 0) == 0 }) else { throw WeaverError("\(url.lastPathComponent) has no readable video track.") }
    func number(_ value: Any?) -> Double { if let n = value as? NSNumber { return n.doubleValue }; return Double(value as? String ?? "") ?? 0 }
    let format = obj["format"] as? [String: Any] ?? [:]
    var duration = number(v["duration"]); if duration <= 0 { duration = number(format["duration"]) }
    var w = v["width"] as? Int ?? 0, h = v["height"] as? Int ?? 0
    let rotation = (v["side_data_list"] as? [[String: Any]])?.compactMap { $0["rotation"] as? Int }.first ?? Int((v["tags"] as? [String: String])?["rotate"] ?? "0") ?? 0
    if abs(rotation) % 180 == 90 { swap(&w, &h) }
    let sar = (v["sample_aspect_ratio"] as? String ?? "1:1").split(separator: ":").compactMap { Double($0) }
    if sar.count == 2 && sar[0] > 0 && sar[1] > 0 && abs(rotation) % 180 == 0 { w = Int((Double(w)*sar[0]/sar[1]).rounded()) }
    var fps = v["avg_frame_rate"] as? String ?? "0/0"; if rateValue(fps) <= 0 { fps = v["r_frame_rate"] as? String ?? "24" }
    guard duration.isFinite && duration > 0 && w > 0 && h > 0 && rateValue(fps) > 0 else { throw WeaverError("Could not read duration, dimensions, or frame rate for \(url.lastPathComponent).") }
    let a = streams.first { ($0["codec_type"] as? String) == "audio" }
    return MediaInfo(duration: duration, width: w, height: h, fps: canonicalRate(rateValue(fps)), hasAudio: a != nil, hdr: ["smpte2084", "arib-std-b67"].contains(v["color_transfer"] as? String ?? ""), videoStart: number(v["start_time"]), audioStart: number(a?["start_time"]))
}
func fingerprint(_ url: URL, job: JobControl) throws -> String {
    let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }; var hash = SHA256()
    while let data = try h.read(upToCount: 4*1024*1024), !data.isEmpty { try job.check(); hash.update(data: data) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
struct SourceClip: Codable, Identifiable {
    var id: String
    var filename: String
    var originalPath: String
    var sha256: String
    var bytes: Int64
    var media: MediaInfo
}
struct Project: Codable {
    var schemaVersion = 1
    var projectId = UUID().uuidString
    var name: String
    var sources: [SourceClip] = []
    var musicPath: String? = nil
    var selectedMusic: ProjectMusic? = nil
    var videoIdea: String? = nil
    var suppressCaptions: Bool? = nil
    var brandId: String? = nil
    var revisionNotes: String? = nil
    var lastRevisionZIP: String? = nil
    var lastRevisionStamp: String? = nil
    var savedIdeaId: String? = nil
    var editChoices: [String]? = nil
    var choicePreviews: [String:String]? = nil
    var lastEditPath: String? = nil
    var reviewPreset: String? = nil
    var nextSourceNumber: Int? = nil
    var createdAt: Date? = nil
    var combinedMasters: [CombinedMaster]? = nil
    var renderSources:[SourceClip] {sources + (combinedMasters ?? []).map(\.source).filter { master in !sources.contains(where: {$0.id == master.id}) }}
    var styleReferenceId: String? = nil
    var logoPath: String? = nil
    var includeLogoInReview: Bool? = nil
    var logoHiddenEdits: [String]? = nil
    func save(_ root: URL) throws {
        var stored=self
        for i in stored.combinedMasters?.indices ?? 0..<0 {stored.combinedMasters![i].source.originalPath=stored.combinedMasters![i].file}
        try writeJSON(stored, root.appendingPathComponent("Project.clipweaver"))
    }
    static func open(_ url: URL) throws -> (Project, URL) {
        var isDirectory:ObjCBool=false
        _ = fm.fileExists(atPath:url.path,isDirectory:&isDirectory)
        let path = isDirectory.boolValue ? url.appendingPathComponent("Project.clipweaver") : url
        var p = try readJSON(Project.self, path); guard p.schemaVersion == 1 else { throw WeaverError("This project needs a newer ClipWeaver version.") }; for i in p.combinedMasters?.indices ?? 0..<0 {p.combinedMasters![i].source.originalPath=projectFile(p.combinedMasters![i].file,root:path.deletingLastPathComponent()).path}; return (p, path.deletingLastPathComponent())
    }
}

enum ReviewPreset: String, CaseIterable, Identifiable {
    case small = "Smallest", balanced = "Balanced", detail = "More Detail"
    var id: String { rawValue }
    var edge: Int { self == .small ? 640 : (self == .balanced ? 854 : 1280) }
    var crf: String { self == .small ? "31" : (self == .balanced ? "28" : "23") }
    var audioBitrate: String { self == .small ? "48k" : (self == .balanced ? "80k" : "128k") }
    var audioChannels: String { self == .small ? "1" : "2" }
}
struct ReviewSource: Codable {
    var id: String
    var filename: String
    var duration: Double
    var originalFps: String
    var originalWidth: Int
    var originalHeight: Int
    var hasAudio: Bool
    var sha256: String
    var reviewVideo: String
    var reviewAudio: String?
    var storyboards: [String]
    var reviewTimeOffset = 0.0
    var sampleInterval = 2.0
}
struct ReviewLogo: Codable {var file:String;var width:Int;var height:Int;var sha256:String}
struct ReviewManifest: Codable {
    var schemaVersion = 1
    var projectId: String
    var projectName: String
    var reviewFps = 8
    var timeUnits = "seconds from the first displayed frame of the original; end is exclusive"
    var sources: [ReviewSource]
    var projectLogo: ReviewLogo? = nil
    var styleReference: ReviewReference? = nil
    var combinedParts:[MasterPart]? = nil
    var preparationNote:String? = nil
    var selectedMusic: ReviewMusic? = nil
    var videoIdea:String? = nil
    var requestedVersions:Int? = nil
    var captionsEnabled:Bool? = nil
    var brand:BrandProfile? = nil
    var editingPolicyVersion:Int? = nil
}

typealias ProgressReport = (String, Double) -> Void

final class Engine {
    let tools: Toolchain
    init(tools: Toolchain) { self.tools = tools }
    func add(_ urls: [URL], project: Project, job: JobControl, progress: ProgressReport) throws -> Project {
        var p = project
        for (i, u) in urls.enumerated() {
            try job.check(); if p.sources.contains(where: { $0.originalPath == u.path }) { continue }
            progress("Reading \(u.lastPathComponent)", Double(i)/Double(max(urls.count,1)))
            let media = try probe(u, tools: tools, job: job)
            let hash = try fingerprint(u, job: job)
            let next = max(p.nextSourceNumber ?? 1, (p.sources.compactMap { Int($0.id.replacingOccurrences(of: "CLIP_", with: "")) }.max() ?? 0) + 1)
            p.nextSourceNumber = next + 1
            p.sources.append(SourceClip(id: String(format: "CLIP_%03d", next), filename: u.lastPathComponent, originalPath: u.path, sha256: hash, bytes: fileSize(u), media: media))
        }
        return p
    }
    func verify(_ sources: [SourceClip], job: JobControl, progress: ProgressReport) throws {
        for (i, s) in sources.enumerated() {
            progress("Checking original: \(s.filename)", Double(i)/Double(max(1,sources.count)))
            let u = URL(fileURLWithPath: s.originalPath)
            guard fm.fileExists(atPath: u.path) else { throw WeaverError("Original missing: \(s.filename). Use Relink Original in the footage list.") }
            guard fileSize(u) == s.bytes, try fingerprint(u, job: job) == s.sha256 else { throw WeaverError("\(s.filename) has changed since it was added. Restore the original, or create a new project for the changed footage.") }
        }
    }
    func prepare(_ originalProject: Project, root: URL, preset: ReviewPreset, job: JobControl, progress: @escaping ProgressReport) throws -> URL {
        let (updated,note)=try prepareCombined(originalProject,root:root,job:job,progress:progress)
        var p=updated
        let combined=updated.combinedMasters?.last(where:{$0.parts.map(\.sourceId)==updated.sources.map(\.id) && $0.parts.count==updated.sources.count})
        if note.hasPrefix("Using full-quality") || note.hasPrefix("Combined "),let combined {p.sources=[combined.source]}
        guard !p.sources.isEmpty else { throw WeaverError("Add some footage first.") }
        if originalProject.sources.count<=1 {try verify(p.sources, job: job, progress: { progress($0, $1*0.08) })}
        let dest = root.appendingPathComponent("For AI")
        let temp = root.appendingPathComponent(".preparing-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        for name in ["videos", "audio", "storyboards"] { try fm.createDirectory(at: temp.appendingPathComponent(name), withIntermediateDirectories: true) }
        var manifestSources: [ReviewSource] = []
        for (i, s) in p.sources.enumerated() {
            try job.check(); let base = 0.08 + 0.88*Double(i)/Double(p.sources.count)
            progress("Making 8 fps review: \(s.filename)", base)
            let videoRel = "videos/\(s.id).mp4"; let videoURL = temp.appendingPathComponent(videoRel)
            // Use a shared timestamp origin to keep audio offsets relative to the first video frame.
            let hdrFolder = temp.appendingPathComponent(".hdr-intermediate")
            if s.media.hdr { progress("Preparing HDR color at original quality: \(s.filename)", base) }
            let input = try editingSource(s, temporaryFolder: hdrFolder, job: job)
            let shift = input.media.videoStart
            var filters = "[0:v:0]setpts=PTS-\(num(shift))/TB,fps=fps=8:start_time=0:round=near,scale=w='min(\(preset.edge),iw)':h='min(\(preset.edge),ih)':force_original_aspect_ratio=decrease:force_divisible_by=2,setsar=1[v]"
            if s.media.hasAudio { filters += ";[0:a:0]asetpts=PTS-\(num(shift))/TB,aresample=async=1:first_pts=0,apad,atrim=duration=\(num(s.media.duration))[a]" }
            var args = ["-copyts", "-i", input.originalPath, "-filter_complex", filters, "-map", "[v]"]
            if s.media.hasAudio { args += ["-map", "[a]", "-c:a", "aac", "-b:a", preset.audioBitrate, "-ac", preset.audioChannels] }
            args += ["-c:v", "libx264", "-preset", "slow", "-crf", preset.crf, "-pix_fmt", "yuv420p", "-t", num(s.media.duration), "-movflags", "+faststart", videoURL.path]
            try tools.ffmpeg(args, job: job)
            if s.media.hdr { try? fm.removeItem(at: hdrFolder) }
            var audioRel: String? = nil
            if s.media.hasAudio {
                audioRel = "audio/\(s.id).m4a"
                try tools.ffmpeg(["-i", videoURL.path, "-vn", "-c:a", "copy", temp.appendingPathComponent(audioRel!).path], job: job)
            }
            progress("Making visual index: \(s.filename)", base + 0.4*0.88/Double(p.sources.count))
            let frames = temp.appendingPathComponent(".frames")
            try fm.createDirectory(at: frames, withIntermediateDirectories: true)
            try tools.ffmpeg(["-i", videoURL.path, "-vf", "select=not(mod(n\\,16)),scale=360:202:force_original_aspect_ratio=decrease,pad=360:202:(ow-iw)/2:(oh-ih)/2", "-fps_mode", "vfr", "-q:v", "3", frames.appendingPathComponent("frame-%05d.jpg").path], job: job)
            var files = try fm.contentsOfDirectory(at: frames, includingPropertiesForKeys: nil).filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            if files.isEmpty {
                let one = frames.appendingPathComponent("frame-00001.jpg")
                try tools.ffmpeg(["-i", videoURL.path, "-frames:v", "1", "-vf", "scale=360:202:force_original_aspect_ratio=decrease,pad=360:202:(ow-iw)/2:(oh-ih)/2", one.path], job: job); files = [one]
            }
            var sheets: [String] = []
            for page in 0..<Int(ceil(Double(files.count)/12)) {
                let rel = String(format: "storyboards/%@-%02d.jpg", s.id, page+1)
                try storyboard(Array(files.dropFirst(page*12).prefix(12)), firstIndex: page*12, source: s, output: temp.appendingPathComponent(rel))
                sheets.append(rel)
            }
            try fm.removeItem(at: frames)
            manifestSources.append(ReviewSource(id: s.id, filename: s.filename, duration: s.media.duration, originalFps: s.media.fps, originalWidth: s.media.width, originalHeight: s.media.height, hasAudio: s.media.hasAudio, sha256: s.sha256, reviewVideo: videoRel, reviewAudio: audioRel, storyboards: sheets))
        }
        var reviewLogo:ReviewLogo?=nil
        if p.includeLogoInReview != false,let original=try resolvedLogo(p,root:root) {
            let im=try checkedImage(original)
            try fm.createDirectory(at:temp.appendingPathComponent("branding"),withIntermediateDirectories:true)
            try fm.copyItem(at:original,to:temp.appendingPathComponent("branding/project-logo.png"))
            reviewLogo=ReviewLogo(file:"branding/project-logo.png",width:Int(im.size.width),height:Int(im.size.height),sha256:try fingerprint(original,job:job))
        }
        var reference:ReviewReference?=nil
        if let id=p.styleReferenceId {
            guard let ref=try GlobalAssets.load().references.first(where:{$0.id==id}) else {throw WeaverError("Selected style reference is missing. Select another reference or clear the selection.")}
            let folder=temp.appendingPathComponent("reference");try fm.createDirectory(at:folder,withIntermediateDirectories:true)
            try fm.copyItem(at:GlobalAssets.root.appendingPathComponent(ref.video),to:folder.appendingPathComponent("style-reference.mp4"))
            try fm.copyItem(at:GlobalAssets.root.appendingPathComponent(ref.thumbnail),to:folder.appendingPathComponent("thumbnail.jpg"))
            reference=ReviewReference(id:ref.id,name:ref.name,file:"reference/style-reference.mp4",duration:ref.media.duration,fps:ref.media.fps,width:ref.media.width,height:ref.media.height)
            try Data("STYLE REFERENCE ONLY: \(ref.name)\nMock its editing style using the project footage. Preserve your own brand and wording. This video is not an editable source and must never appear in clips. Inspect its original-cadence motion, pacing and caption entrances.\n".utf8).write(to:folder.appendingPathComponent("READ-ME.txt"))
        }
        let reviewMusic=try prepareReviewMusic(originalProject,root:root,folder:temp,job:job)
        try writeJSON(ReviewManifest(projectId: p.projectId, projectName: p.name, timeUnits:p.sources.first?.id.hasPrefix("COMBINED_")==true ? "seconds from the first displayed frame of the full-quality combined master; end is exclusive":"seconds from the first displayed frame of the original; end is exclusive", sources: manifestSources,projectLogo:reviewLogo,styleReference:reference,combinedParts:p.sources.first?.id.hasPrefix("COMBINED_")==true ? combined?.parts:nil,preparationNote:note,selectedMusic:reviewMusic,videoIdea:originalProject.videoIdea,requestedVersions:3,captionsEnabled:originalProject.suppressCaptions != true,brand:try GlobalAssets.load().brand(for:originalProject).reviewValue,editingPolicyVersion:6), temp.appendingPathComponent("manifest.json"))
        if let skill = resourceSkillURL() {
            try fm.copyItem(at: skill, to: temp.appendingPathComponent("clipweaver-editor"))
            try fm.copyItem(at: skill.appendingPathComponent("SKILL.md"), to: temp.appendingPathComponent("EDITOR-INSTRUCTIONS.md"))
            try fm.copyItem(at: skill.appendingPathComponent("references/edit-format.md"), to: temp.appendingPathComponent("EDIT-FORMAT.md"))
        }
        let guide = """
        CLIPWEAVER — REVIEW PACKAGE
        Project: \(p.name)
        Project ID: \(p.projectId)

        Upload manifest.json, EDITOR-INSTRUCTIONS.md, EDIT-FORMAT.md, and the review media relevant to your idea to ChatGPT Work. You can also upload the whole ZIP if its tools can unpack it. Ask it to use the ClipWeaver editor instructions and tell it your idea and duration; output shape always stays source. It must inspect the actual footage/images and audio using available tools. Uploading MP4 alone does not establish audiovisual understanding.

        videos/: small 8 fps review copies with audio. Their speed and timeline match the originals.
        storyboards/: visual navigation sampled about every 2 seconds. Labels refer to original seconds; these sheets do not show all action.
        audio/: separate synchronized audio for listening/transcription when supported. It contains music and ambient sounds as well as speech.
        manifest.json: stable clip IDs, exact durations, original frame rates, and review paths. Original Mac paths are excluded.

        Ask for ONE .clipweaveredit response following EDIT-FORMAT.md, using the bundled pack_response.py helper to embed three distinct edits and their graphics. Do not compose or generate music; the app applies the user-selected track. Double-click the response, or save it into this project’s Incoming folder; ClipWeaver loads everything automatically. Preview and export. Final videos use original files and the original project frame rate; 8 fps is ONLY for AI review. If the AI cannot inspect a needed moment or hear the audio, ask it to report that gap. Do not accept invented descriptions or dialogue.

        Upload in smaller batches if needed. Keep manifest.json with every batch. Original files stay on your Mac. Each storyboard timestamp is an approximate sampled view; exact edits should be checked in the final preview.
        """
        try guide.write(to: temp.appendingPathComponent("START-HERE.txt"), atomically: true, encoding: .utf8)
        try job.check()
        // Stage a complete package, keeping the prior successful package until this one is ready.
        let backup = root.appendingPathComponent(".previous-review-\(UUID().uuidString)")
        if fm.fileExists(atPath: dest.path) { try fm.moveItem(at: dest, to: backup) }
        do { try fm.moveItem(at: temp, to: dest); try? fm.removeItem(at: backup) }
        catch { if fm.fileExists(atPath: backup.path) { try? fm.moveItem(at: backup, to: dest) }; throw error }
        progress("Review package ready", 1)
        return dest
    }
    private func storyboard(_ images: [URL], firstIndex: Int, source: SourceClip, output: URL) throws {
        let width = 1128, height = 1004
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { throw WeaverError("Could not create the visual index.") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
        NSColor(calibratedWhite: 0.07, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        let title = "\(source.id)  •  \(source.filename)" as NSString
        title.draw(at: NSPoint(x: 16, y: height-34), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.white])
        for (j,u) in images.enumerated() {
            let x = 16+(j%3)*368, top = height-60-(j/3)*234
            NSImage(contentsOf: u)?.draw(in: NSRect(x: x, y: top-202, width: 360, height: 202))
            let text = "\(source.id)  \(clockText(Double(firstIndex+j)*2))" as NSString
            text.draw(at: NSPoint(x: x+4, y: top-225), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white])
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.78]) else { throw WeaverError("Could not save a visual index.") }
        try data.write(to: output)
    }
}
func resourceSkillURL() -> URL? {
    if let u = Bundle.main.resourceURL?.appendingPathComponent("clipweaver-editor"), fm.fileExists(atPath: u.path) { return u }
    if let p = ProcessInfo.processInfo.environment["CLIPWEAVER_SKILL"] { return URL(fileURLWithPath: p) }
    return nil
}
