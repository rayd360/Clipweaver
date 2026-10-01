import Foundation

struct EditClip: Codable, Identifiable {
    var sourceId: String
    var start: Double
    var end: Double
    var volume: Double? = nil
    var transition: Double? = nil // Crossfade into this clip; first must be zero.
    var framing: String? = nil // fit or fill
    var focusX: Double? = nil // center of fill crop, fraction across available crop range
    var focusY: Double? = nil
    var note: String? = nil
    var id: String { "\(sourceId):\(start):\(end)" }
    var duration: Double { end-start }
}
struct MusicPlan: Codable {
    var filename: String
    var start: Double? = nil
    var volume: Double? = nil
    var fadeIn: Double? = nil
    var fadeOut: Double? = nil
    var duck: Bool? = nil
    var loop: Bool? = nil
}
struct EditPlan: Codable {
    var schemaVersion = 1
    var projectId: String
    var title: String
    var aspect: String? = nil
    var fps: String? = nil
    var clips: [EditClip]
    var music: MusicPlan? = nil
    var notes: String? = nil
    var overlays: [TextOverlay]? = nil
    var endCard: EndCard? = nil
    var captionStyles: [String:CaptionStyle]? = nil
    var captions: [Caption]? = nil
    var logoPlacements: [LogoPlacement]? = nil
    var transitionStyle:String? = nil
    var duration: Double { (endCard?.duration ?? 0) - (endCard?.transition ?? 0) + clips.enumerated().reduce(0) { $0 + $1.element.duration - ($1.offset == 0 ? 0 : ($1.element.transition ?? 0)) } }
    static func load(_ url: URL) throws -> EditPlan {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw WeaverError("The edit plan must be a JSON object.") }
        func allowed(_ object: [String:Any], _ keys: Set<String>, _ whereText: String) throws {
            let unknown = Set(object.keys).subtracting(keys)
            if !unknown.isEmpty { throw WeaverError("Unsupported instruction in \(whereText): \(unknown.sorted().joined(separator: ", ")). Ask the AI to follow EDIT-FORMAT.md. This app won't silently omit editing instructions.") }
        }
        try allowed(root, ["schema_version","project_id","title","aspect","fps","clips","music","notes","overlays","end_card","caption_styles","captions","logo_placements","transition_style"], "edit plan")
        for (i,c) in (root["clips"] as? [[String:Any]] ?? []).enumerated() { try allowed(c, ["source_id","start","end","volume","transition","framing","focus_x","focus_y","note"], "clip \(i+1)") }
        if let m = root["music"] as? [String:Any] { try allowed(m, ["filename","start","volume","fade_in","fade_out","duck","loop"], "music") }
        for o in root["overlays"] as? [[String:Any]] ?? [] { try allowed(o,["start","end","text","filename","x","y","width","height","font_size","color","background","alignment"],"overlay") }
        if let card=root["end_card"] as? [String:Any] {try allowed(card,["duration","text","filename","background","transition"],"end card")}
        func entranceKeys(_ object: [String:Any]) throws {if let e=object["entrance"] as? [String:Any] {try allowed(e,["type","direction","duration","distance"],"caption entrance")}}
        for (_,style) in root["caption_styles"] as? [String:[String:Any]] ?? [:] {try allowed(style,["font_size","emphasis_scale","emphasis_color","entrance","contrast_backing"],"caption style");try entranceKeys(style)}
        for c in root["captions"] as? [[String:Any]] ?? [] {
            try allowed(c,["style","x","y","width","height","alignment","words"],"caption")
            for word in c["words"] as? [[String:Any]] ?? [] {try allowed(word,["text","start","end","style","font_size","x","y","line_break_before","entrance"],"caption word");try entranceKeys(word)}
        }
        for l in root["logo_placements"] as? [[String:Any]] ?? [] {try allowed(l,["start","end","x","y","width","height","opacity"],"logo placement")}
        do { return try jsonDecoder().decode(EditPlan.self, from: data) } catch { throw WeaverError("Could not read the edit file: \(error.localizedDescription)\nUse decimal seconds for start/end, and a string such as \"source\" or \"24000/1001\" for fps.") }
    }
    func validate(_ project: Project) throws {
        guard [1,2,3,4].contains(schemaVersion) else { throw WeaverError("Unsupported edit schema. Use schema_version 4.") }
        guard schemaVersion >= 2 || (overlays == nil && endCard == nil) else {throw WeaverError("Overlays and end cards require schema_version 2.")}
        guard schemaVersion >= 3 || (captionStyles == nil && captions == nil && logoPlacements == nil) else {throw WeaverError("Animated captions and project logo placements require schema_version 3.")}
        try validateCaptions()
        guard projectId == project.projectId else { throw WeaverError("This edit belongs to a different project. Open its matching ClipWeaver project.") }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200 else { throw WeaverError("The edit needs a title of 1–200 characters.") }
        guard !clips.isEmpty, clips.count <= 100 else { throw WeaverError("An edit must contain 1–100 selected clips.") }
        guard ["source","portrait","landscape","square"].contains(aspect ?? "source") else { throw WeaverError("aspect must be source, portrait, landscape, or square.") }
        if let f = fps, f != "source" { guard ["23.976","24000/1001","24","25","29.97","30000/1001","30","48","50","59.94","60000/1001","60","120000/1001","120"].contains(f) else { throw WeaverError("Unsupported export frame rate. Use source to preserve the original rate.") } }
        if schemaVersion>=4 {
            guard ["cut","cross_dissolve"].contains(transitionStyle ?? "") else{throw WeaverError("Choose transition_style cut or cross_dissolve for the entire edit.")}
            for clip in clips.dropFirst() {
                let t=clip.transition ?? 0
                guard transitionStyle=="cut" ? t==0:(t>=0.5 && t<=0.8) else{throw WeaverError("All cuts must use the same transition style. Cross-dissolves require 0.5–0.8 seconds on every clip after the first.")}
            }
        }
        if let card=endCard {
            let t=card.transition ?? 0
            guard t.isFinite,t>=0,t<=2,t<card.duration else{throw WeaverError("End-card transition must fit its duration.")}
            if schemaVersion>=4 {guard transitionStyle=="cut" ? t==0:(t>=0.5 && t<=0.8) else{throw WeaverError("The end card must use the same transition style; specify 0.5–0.8 seconds for a dissolve.")}}
        }
        let sourceMap = Dictionary(uniqueKeysWithValues: project.renderSources.map { ($0.id, $0) })
        for (i, c) in clips.enumerated() {
            guard let s = sourceMap[c.sourceId] else { throw WeaverError("Clip \(i+1) refers to unknown source \(c.sourceId).") }
            guard c.start.isFinite, c.end.isFinite, c.start >= 0, c.end > c.start, c.end <= s.media.duration + 0.002 else { throw WeaverError("Clip \(i+1) has invalid times for \(s.filename). Available range: 0–\(num(s.media.duration)) seconds.") }
            if let master=project.combinedMasters?.first(where:{$0.source.id==c.sourceId}) {
                for part in master.parts.dropLast() {
                    let boundary=part.end
                    guard !(c.start < boundary-0.000001 && c.end > boundary+0.000001) else {
                        throw WeaverError("Selection \(i+1) crosses an original-video boundary at \(num(boundary)) seconds in the combined master. Split it into two explicit selections ending and starting at that boundary.")
                    }
                }
            }
            guard c.duration >= 1.0 / s.media.fpsValue else { throw WeaverError("Clip \(i+1) is shorter than one original frame.") }
            guard (c.volume ?? 1).isFinite, (0...2).contains(c.volume ?? 1), ["fit", "fill"].contains(c.framing ?? "fit"), (c.focusX ?? 0.5).isFinite, (0...1).contains(c.focusX ?? 0.5), (c.focusY ?? 0.5).isFinite, (0...1).contains(c.focusY ?? 0.5) else { throw WeaverError("Clip \(i+1) has an invalid volume, framing, or crop position.") }
            let t = c.transition ?? 0
            guard t.isFinite, t >= 0, t <= 2, (i > 0 || t == 0) else { throw WeaverError("Crossfades must be 0–2 seconds; the first clip cannot have one.") }
            let next = i+1 < clips.count ? (clips[i+1].transition ?? 0) : (endCard?.transition ?? 0)
            guard t + next < c.duration else { throw WeaverError("Clip \(i+1) is too short for its incoming and outgoing crossfades.") }
        }
        guard (overlays?.count ?? 0)<=100 else {throw WeaverError("Use at most 100 overlays.")}
        for o in overlays ?? [] {try o.validate(duration:duration)}
        if let c=endCard {
            guard c.duration.isFinite,(0.25...15).contains(c.duration) else {throw WeaverError("End card duration must be 0.25–15 seconds.")}
            try TextOverlay(start:0,end:c.duration,text:c.text,filename:c.filename).validate(duration:c.duration)
            _ = try overlayColor(c.background ?? "#101218")
        }
        if let m = music {
            guard safeBasename(m.filename), (m.start ?? 0).isFinite, (m.start ?? 0) >= 0, (m.volume ?? 0.2).isFinite, (0...2).contains(m.volume ?? 0.2), (m.fadeIn ?? 0.5).isFinite, (m.fadeOut ?? 1).isFinite, (0...duration).contains(m.fadeIn ?? min(0.5,duration)), (0...duration).contains(m.fadeOut ?? min(1,duration)) else { throw WeaverError("Music filename, timing, volume, or fades are invalid.") }
        }
        guard duration.isFinite && duration > 0 && duration <= 3600 else { throw WeaverError("The finished edit must be between one frame and one hour.") }
    }
}
enum ExportKind: String, CaseIterable, Identifiable { case preview = "Preview", social = "Social", website = "Website"; var id: String { rawValue } }
struct ExportSettings {
    var kind: ExportKind = .social
    var aspect = "plan"
    var resolution = "original"
    var websiteQuality = "balanced"
    var mute = false
    var includeLogo = true
}
struct RenderSpec {
    var args: [String]
    var width: Int
    var height: Int
    var fps: String
    var duration: Double
}

extension Engine {
    func specification(_ originalPlan: EditPlan, project: Project, settings: ExportSettings, output: URL, musicURL: URL?, overlayInputs: [URL] = [], endCardInput: URL? = nil, captionLayer: CaptionLayer? = nil) throws -> RenderSpec {
        try originalPlan.validate(project)
        var plan = originalPlan
        let map = Dictionary(uniqueKeysWithValues: project.renderSources.map { ($0.id,$0) }); let first = map[plan.clips[0].sourceId]!
        let fps = (plan.fps == nil || plan.fps == "source") ? first.media.fps : canonicalRate(rateValue(plan.fps!))
        // Quantize every selection and overlap once, avoiding cumulative fractional-frame
        // drift or truncating later selections when many short cuts are concatenated.
        let frameRate = rateValue(fps)
        for i in plan.clips.indices {
            var frames = max(1,(plan.clips[i].duration*frameRate).rounded())
            // Frame alignment may shorten a boundary-adjacent selection, never extend
            // it into the next original recording.
            if let master = project.combinedMasters?.first(where: {$0.source.id == plan.clips[i].sourceId}),
               let part = master.parts.first(where: {plan.clips[i].start >= $0.start-0.000001 && plan.clips[i].start < $0.end-0.000001}) {
                frames = min(frames, floor((part.end-plan.clips[i].start)*frameRate+0.00001))
                guard frames >= 1 else {throw WeaverError("A selection next to an original-video boundary is shorter than one output frame. Choose a longer selection within that original video.")}
            }
            plan.clips[i].end = plan.clips[i].start + frames/frameRate
            if let transition = plan.clips[i].transition { plan.clips[i].transition = (transition*frameRate).rounded()/frameRate }
        }
        if let t=plan.endCard?.transition {plan.endCard?.transition=(t*frameRate).rounded()/frameRate}
        for i in plan.clips.indices {
            let incoming = plan.clips[i].transition ?? 0
            let outgoing = i+1 < plan.clips.count ? (plan.clips[i+1].transition ?? 0) : (plan.endCard?.transition ?? 0)
            guard incoming+outgoing < plan.clips[i].duration-0.000001 else { throw WeaverError("A clip is too short for its crossfades after aligning cuts to output frames. Shorten those crossfades.") }
        }
        let aspect = settings.aspect == "plan" ? (plan.aspect ?? "source") : settings.aspect
        let ratio: Double = aspect == "portrait" ? 9.0/16 : (aspect == "landscape" ? 16.0/9 : (aspect == "square" ? 1 : Double(first.media.width)/Double(first.media.height)))
        let sourceLong = max(first.media.width,first.media.height)
        var long = sourceLong
        if settings.kind == .preview { long = min(sourceLong, 960) }
        else if settings.kind == .website { long = min(sourceLong, settings.websiteQuality == "small" ? 854 : 1280) }
        else if settings.resolution == "1080" { long = min(sourceLong, 1920) }
        else if settings.resolution == "2160" { long = min(sourceLong, 3840) }
        let w = max(2, Int((ratio >= 1 ? Double(long) : Double(long)*ratio)/2)*2)
        let h = max(2, Int((ratio >= 1 ? Double(long)/ratio : Double(long))/2)*2)
        var args = ["-copyts"]
        // Open each selection separately, so repeated selections from one original are independent.
        for c in plan.clips { args += ["-ss", num(c.start), "-t", num(c.duration+0.25), "-i", map[c.sourceId]!.originalPath] }
        if let m = plan.music, let mu = musicURL {
            if m.loop ?? false { args += ["-stream_loop", "-1"] }
            args += ["-ss", num(m.start ?? 0), "-i", mu.path]
        }
        let assetIndex=plan.clips.count + ((plan.music != nil && musicURL != nil) ? 1:0)
        for u in overlayInputs {args += ["-loop","1","-framerate",fps,"-i",u.path]}
        if let u=endCardInput {args += ["-loop","1","-framerate",fps,"-i",u.path]}
        if let layer=captionLayer {args += ["-i",layer.url.path]}
        var f: [String] = []
        for (i,c) in plan.clips.enumerated() {
            let s = map[c.sourceId]!, origin = s.media.videoStart+c.start
            var video = "[\(i):v:0]trim=start=\(num(origin)):end=\(num(origin+c.duration)),setpts=PTS-\(num(origin))/TB,fps=fps=\(fps):start_time=0,"
            if c.framing == "fill" {
                video += "scale=\(w):\(h):force_original_aspect_ratio=increase:force_divisible_by=2,crop=\(w):\(h):(iw-ow)*\(num(c.focusX ?? 0.5)):(ih-oh)*\(num(c.focusY ?? 0.5)),"
            } else {
                video += "scale=\(w):\(h):force_original_aspect_ratio=decrease:force_divisible_by=2,pad=\(w):\(h):(ow-iw)/2:(oh-ih)/2:color=black,"
            }
            video += "setsar=1,format=yuv420p,settb=AVTB,tpad=stop_mode=clone:stop_duration=0.1,trim=duration=\(num(c.duration))[v\(i)]"
            f.append(video)
            if s.media.hasAudio {
                f.append("[\(i):a:0]atrim=start=\(num(origin)):end=\(num(origin+c.duration)),asetpts=PTS-\(num(origin))/TB,aresample=48000:async=1:first_pts=0,aformat=sample_fmts=fltp:channel_layouts=stereo,apad,atrim=duration=\(num(c.duration)),volume=\(num(c.volume ?? 1))[a\(i)]")
            } else { f.append("anullsrc=r=48000:cl=stereo,atrim=duration=\(num(c.duration)),asetpts=PTS-STARTPTS[a\(i)]") }
        }
        var v = "v0", a = "a0", elapsed = plan.clips[0].duration
        for i in 1..<plan.clips.count {
            let cross = plan.clips[i].transition ?? 0
            if cross > 0 {
                f.append("[\(v)][v\(i)]xfade=transition=fade:duration=\(num(cross)):offset=\(num(elapsed-cross))[vx\(i)]")
                f.append("[\(a)][a\(i)]acrossfade=d=\(num(cross)):c1=tri:c2=tri[ax\(i)]")
            } else {
                f.append("[\(v)][\(a)][v\(i)][a\(i)]concat=n=2:v=1:a=1[vx\(i)][ax\(i)]")
            }
            v = "vx\(i)"; a = "ax\(i)"; elapsed += plan.clips[i].duration-cross
            // concat emits AVTB, but reset explicitly before a following xfade.
            f.append("[\(v)]fps=\(fps),settb=AVTB[vn\(i)]"); v = "vn\(i)"
        }
        if let card=plan.endCard {
            guard endCardInput != nil else {throw WeaverError("The end card has not been prepared.")}
            let d=(card.duration*frameRate).rounded()/frameRate
            f.append("[\(assetIndex+overlayInputs.count):v]scale=\(w):\(h),setsar=1,format=yuv420p,fps=\(fps),trim=duration=\(num(d)),setpts=PTS-STARTPTS,settb=AVTB[card]")
            f.append("anullsrc=r=48000:cl=stereo,atrim=duration=\(num(d))[cardsound]")
            let cross=card.transition ?? 0
            guard cross<d else{throw WeaverError("End card is too short after frame alignment.")}
            if cross>0 {
                f.append("[\(v)]settb=AVTB[cardbase]")
                f.append("[cardbase][card]xfade=transition=fade:duration=\(num(cross)):offset=\(num(elapsed-cross))[withcard]")
                f.append("[\(a)][cardsound]acrossfade=d=\(num(cross)):c1=tri:c2=tri[withcardsound]")
            } else {f.append("[\(v)][\(a)][card][cardsound]concat=n=2:v=1:a=1[withcard][withcardsound]")}
            v="withcard";a="withcardsound";elapsed+=d-cross
        }
        guard overlayInputs.count == (plan.overlays?.count ?? 0) else {throw WeaverError("Overlay assets have not been prepared.")}
        for (i,o) in (plan.overlays ?? []).enumerated() {
            f.append("[\(assetIndex+i):v]format=rgba[graphic\(i)]")
            f.append("[\(v)][graphic\(i)]overlay=0:0:enable='gte(t,\(num(o.start)))*lt(t,\(num(o.end)))':eof_action=repeat[overlaid\(i)]")
            v="overlaid\(i)"
        }
        if let layer=captionLayer {
            let index=assetIndex+overlayInputs.count+(endCardInput == nil ? 0:1)
            f.append("[\(index):v]setpts=PTS-STARTPTS+\(num(layer.start))/TB[captionlayer]")
            f.append("[\(v)]format=rgba[captionbase]")
            f.append("[captionbase][captionlayer]overlay=0:0:format=auto:alpha=straight:eof_action=pass:repeatlast=0:enable='gte(t,\(num(layer.start)))*lt(t,\(num(layer.start+layer.duration)))'[captionresult]")
            v="captionresult"
        }
        if let m = plan.music, musicURL != nil {
            let idx = plan.clips.count
            let fi = m.fadeIn ?? min(0.5,elapsed), fo = m.fadeOut ?? min(1,elapsed)
            f.append("[\(idx):a:0]asetpts=PTS-STARTPTS,aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,apad,atrim=duration=\(num(elapsed)),volume=\(num(m.volume ?? 0.2)),afade=t=in:st=0:d=\(num(fi)),afade=t=out:st=\(num(max(0,elapsed-fo))):d=\(num(fo))[music]")
            if m.duck ?? true {
                f.append("[\(a)]asplit=2[original][trigger]")
                f.append("[music][trigger]sidechaincompress=threshold=0.04:ratio=6:attack=20:release=350[ducked]")
                f.append("[original][ducked]amix=inputs=2:duration=first:normalize=0[mixed]")
            } else { f.append("[\(a)][music]amix=inputs=2:duration=first:normalize=0[mixed]") }
            a = "mixed"
        }
        f.append("[\(a)]alimiter=limit=0.95:level=false:latency=true,atrim=duration=\(num(elapsed))[audio]")
        args += ["-filter_complex", f.joined(separator: ";"), "-map", "[\(v)]"]
        if settings.mute { args += ["-an"] ; f[f.count-1] += ";[audio]anullsink"; if let ix = args.firstIndex(of: "-filter_complex") { args[ix+1] = f.joined(separator: ";") } }
        else { args += ["-map", "[audio]", "-c:a", "aac", "-b:a", settings.kind == .website ? "96k" : "192k"] }
        args += ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", fps, "-fps_mode", "cfr"]
        if settings.kind == .social { args += ["-crf", "17", "-preset", "medium"] }
        else if settings.kind == .preview { args += ["-crf", "25", "-preset", "veryfast"] }
        else { args += ["-crf", settings.websiteQuality == "small" ? "29" : "25", "-preset", "slow", "-maxrate", settings.websiteQuality == "small" ? "900k" : "1800k", "-bufsize", settings.websiteQuality == "small" ? "1800k" : "3600k"] }
        args += ["-t", num(elapsed), "-map_metadata", "-1", "-movflags", "+faststart", output.path]
        return RenderSpec(args: args, width: w, height: h, fps: fps, duration: elapsed)
    }
    func render(_ plan: EditPlan, project: Project, root: URL, settings: ExportSettings, job: JobControl, progress: @escaping ProgressReport) throws -> URL {
        let plan=withSelectedMusic(plan,project:project)
        try plan.validate(project)
        let ids = Set(plan.clips.map(\.sourceId))
        try verify(project.renderSources.filter { ids.contains($0.id) }, job: job, progress: { progress($0,$1*0.15) })
        var musicURL: URL? = nil
        if let m = plan.music {
            guard let path = project.selectedMusic?.path ?? project.musicPath, fm.fileExists(atPath: projectFile(path,root:root).path) else { throw WeaverError("This edit needs \(m.filename). Choose its audio file with Add Music before rendering.") }
            let mu = projectFile(path,root:root)
            guard mu.lastPathComponent == m.filename else { throw WeaverError("The edit requests \(m.filename), but the selected music is \(mu.lastPathComponent). Select the requested track or revise the edit.") }
            let data = try tools.run("ffprobe", ["-v","error","-show_streams","-show_format","-of","json",mu.path], job: job)
            guard let info = try JSONSerialization.jsonObject(with: data) as? [String:Any], let streams = info["streams"] as? [[String:Any]], streams.contains(where: { $0["codec_type"] as? String == "audio" }) else { throw WeaverError("The selected music file has no audio.") }
            let format = info["format"] as? [String:Any] ?? [:]
            if let duration = Double(format["duration"] as? String ?? ""), (m.start ?? 0) >= duration { throw WeaverError("The requested music start is beyond the end of the music file.") }
            musicURL = mu
        }
        let folder = root.appendingPathComponent(settings.kind == .preview ? "Previews" : "Exports")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = uniqueURL(folder, "\(cleanName(plan.title)) — \(settings.kind.rawValue)", "mp4")
        let temp = folder.appendingPathComponent(".render-\(UUID().uuidString).mp4")
        defer { try? fm.removeItem(at: temp) }
        let hdrFolder = folder.appendingPathComponent(".hdr-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: hdrFolder) }
        var processingProject = project
        processingProject.sources=project.renderSources
        for i in processingProject.sources.indices where ids.contains(processingProject.sources[i].id) && processingProject.sources[i].media.hdr {
            progress("Preparing HDR at original resolution and frame rate",0.17)
            processingProject.sources[i] = try editingSource(processingProject.sources[i],temporaryFolder:hdrFolder,job:job)
        }
        let graphicFolder=folder.appendingPathComponent(".graphics-\(UUID().uuidString)")
        try fm.createDirectory(at:graphicFolder,withIntermediateDirectories:true);defer{try? fm.removeItem(at:graphicFolder)}
        var bare=plan;bare.overlays=nil;bare.endCard=nil;bare.music?.fadeIn=nil;bare.music?.fadeOut=nil;bare.captions=nil;bare.captionStyles=nil;bare.logoPlacements=nil
        let dimensions=try specification(bare,project:processingProject,settings:settings,output:temp,musicURL:musicURL)
        let assets=project.lastEditPath.map{projectFile($0,root:root).deletingLastPathComponent()}
        var graphics:[URL]=[]
        for (i,o) in (plan.overlays ?? []).enumerated() {
            let u=graphicFolder.appendingPathComponent("overlay-\(i).png")
            try overlayPNG(o,width:dimensions.width,height:dimensions.height,assets:assets,output:u);graphics.append(u)
        }
        var cardURL:URL?=nil
        if let c=plan.endCard {
            let u=graphicFolder.appendingPathComponent("end-card.png")
            let o=TextOverlay(start:0,end:c.duration,text:c.text,filename:c.filename,x:0.1,y:0.25,width:0.8,height:0.5,fontSize:0.065,background:"#00000000")
            try overlayPNG(o,width:dimensions.width,height:dimensions.height,assets:assets,output:u,canvas:c.background ?? "#101218");cardURL=u
        }
        let logoURL=try resolvedLogo(project,root:root)
        let layer=try makeCaptionLayer(plan,width:dimensions.width,height:dimensions.height,fps:dimensions.fps,logoURL:logoURL,includeLogo:settings.includeLogo,folder:graphicFolder,job:job,progress:progress)
        let spec = try specification(plan, project: processingProject, settings: settings, output: temp, musicURL: musicURL,overlayInputs:graphics,endCardInput:cardURL,captionLayer:layer)
        progress("Rendering from originals · \(spec.width) × \(spec.height) · \(spec.fps) fps",0.2)
        try tools.ffmpeg(spec.args, job: job)
        progress("Checking exported video",0.92)
        let result = try probe(temp, tools: tools, job: job)
        guard abs(result.fpsValue-rateValue(spec.fps)) < 0.01, abs(result.duration-spec.duration) <= max(0.12,2/rateValue(spec.fps)), result.width == spec.width, result.height == spec.height else { throw WeaverError("Export verification failed. The output duration, dimensions, or frame rate did not match the edit.") }
        try fm.moveItem(at: temp, to: output)
        let editCopy = output.deletingPathExtension().appendingPathExtension("edit.json"); try writeJSON(plan, editCopy)
        if settings.kind == .website {
            let poster = output.deletingPathExtension().appendingPathExtension("jpg")
            try tools.ffmpeg(["-ss", num(plan.endCard == nil ? min(0.2,spec.duration/2) : max(0,spec.duration-0.1)), "-i", output.path, "-frames:v", "1", "-q:v", "3", poster.path], job: job)
            let name = output.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? output.lastPathComponent
            let posterName = poster.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? poster.lastPathComponent
            let html = """
            <!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Video preview</title>
            <body style="margin:24px;background:#151619;color:#eee;font-family:system-ui">
            <video controls playsinline preload="none" poster="\(posterName)" width="\(spec.width)" height="\(spec.height)" style="display:block;width:100%;max-width:960px;height:auto"><source src="\(name)" type="video/mp4"></video>
            <p>Copy the video and poster to your website, then adapt the video element above. preload="none" avoids downloading video before playback. The MP4 is prepared for streaming playback.</p>
            </body></html>
            """
            try html.write(to: output.deletingPathExtension().appendingPathExtension("html"), atomically: true, encoding: .utf8)
        }
        progress("\(settings.kind.rawValue) ready · \(humanSize(fileSize(output)))",1)
        return output
    }
}
