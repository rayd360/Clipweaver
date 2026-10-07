import Foundation
import CryptoKit
struct MasterPart:Codable {var sourceId:String;var filename:String;var start:Double;var end:Double}
struct CombinedMaster:Codable {var key:String;var file:String;var source:SourceClip;var parts:[MasterPart]}
extension Engine {
    func masterSignature(_ source:SourceClip,job:JobControl)throws -> (String,Int) {
        let data=try tools.run("ffprobe",["-v","error","-count_frames","-show_streams","-show_data_hash","sha256","-of","json",source.originalPath],job:job)
        guard let obj=try JSONSerialization.jsonObject(with:data) as? [String:Any],let streams=obj["streams"] as? [[String:Any]] else{throw WeaverError("Could not inspect source compatibility.")}
        var values:[[String:Any]]=[];var frames=0
        for stream in streams where ["video","audio"].contains(stream["codec_type"] as? String ?? "") {
            var value:[String:Any]=[:]
            for key in ["codec_type","codec_name","codec_tag_string","profile","level","width","height","pix_fmt","sample_aspect_ratio","field_order","color_range","color_space","color_transfer","color_primaries","r_frame_rate","time_base","sample_fmt","sample_rate","channels","channel_layout","extradata_hash","side_data_list"] {if let v=stream[key] {value[key]=v}}
            if stream["codec_type"] as? String == "video" {
                frames=Int(stream["nb_read_frames"] as? String ?? "0") ?? 0
                guard frames>0,abs(Double(frames)/source.media.fpsValue-source.media.duration)<0.05 else{throw WeaverError("Variable-rate or irregular-timestamp footage is kept separate to preserve timing.")}
            }
            values.append(value)
        }
        return (String(data:try JSONSerialization.data(withJSONObject:values,options:.sortedKeys),encoding:.utf8)!,frames)
    }
    func prepareCombined(_ project:Project,root:URL,job:JobControl,progress:ProgressReport)throws -> (Project,String) {
        if project.usesCameraReviews { return (project, "DJI LRF previews stay separate. Each selection uses elapsed time in its matching OSV file.") }
        guard project.sources.count>1 else{return(project,"One original video; no combination needed.")}
        try verify(project.sources,job:job,progress:progress)
        let inputKey=project.sources.map{$0.id+":"+$0.sha256+":"+$0.media.fps+":"+String($0.media.width)+"x"+String($0.media.height)}.joined(separator:"|")
        let key=SHA256.hash(data:Data(inputKey.utf8)).map{String(format:"%02x",$0)}.joined()
        if let master=project.combinedMasters?.first(where:{$0.key==key}),fm.fileExists(atPath:projectFile(master.file,root:root).path),try fingerprint(projectFile(master.file,root:root),job:job)==master.source.sha256 {return(project,"Using full-quality combined master (\(project.sources.count) originals).")}
        progress("Checking formats for a lossless combined master",0.02)
        var signatures:[String]=[];var frames=0
        for s in project.sources {
            try job.check()
            guard s.media.width==project.sources[0].media.width,s.media.height==project.sources[0].media.height,s.media.fps==project.sources[0].media.fps,s.media.hdr==project.sources[0].media.hdr else{return(project,"Formats differ: sending separate review videos to preserve resolution, frame rate and color.")}
            do {let (sig,count)=try masterSignature(s,job:job);signatures.append(sig);frames+=count}
            catch {try job.check();return(project,"Keeping separate review videos: \(error.localizedDescription)")}
        }
        guard Set(signatures).count==1 else{return(project,"Encoding or audio formats differ: separate review videos preserve the original quality and timing.")}
        let folder=root.appendingPathComponent("Masters");try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        let id="COMBINED_"+String(key.prefix(16)),relative="Masters/\(id).mp4",out=projectFile(relative,root:root)
        let stage=folder.appendingPathComponent(".combining-\(UUID().uuidString).mp4"),list=folder.appendingPathComponent(".concat-\(UUID().uuidString).txt")
        defer{try? fm.removeItem(at:stage);try? fm.removeItem(at:list)}
        var parts:[MasterPart]=[];var elapsed=0.0
        var script="ffconcat version 1.0\n"
        for source in project.sources {
            guard !source.originalPath.contains("\n"),!source.originalPath.contains("\r") else{return(project,"A source filename contains a newline; sending separate reviews.")}
            let escaped=source.originalPath.replacingOccurrences(of:"'",with:"'\\''")
            script += "file '\(escaped)'\nduration \(num(source.media.duration))\n"
            parts.append(MasterPart(sourceId:source.id,filename:source.filename,start:elapsed,end:elapsed+source.media.duration));elapsed+=source.media.duration
        }
        try Data(script.utf8).write(to:list)
        progress("Combining compatible footage without re-encoding",0.04)
        try tools.ffmpeg(["-f","concat","-safe","0","-i",list.path,"-map","0:v:0","-map","0:a:0?","-c","copy","-movflags","+faststart",stage.path],job:job)
        let media=try probe(stage,tools:tools,job:job)
        var candidate=SourceClip(id:id,filename:"Combined footage.mp4",originalPath:stage.path,sha256:"",bytes:fileSize(stage),media:media)
        let (_,actualFrames)=try masterSignature(candidate,job:job)
        guard actualFrames==frames,abs(media.duration-elapsed)<max(0.05,1/media.fpsValue),abs(media.fpsValue-project.sources[0].media.fpsValue)<0.02 else{return(project,"Combined timing could not be verified; sending separate reviews instead.")}
        candidate.sha256=try fingerprint(stage,job:job);candidate.originalPath=out.path
        if fm.fileExists(atPath:out.path) {let retired=folder.appendingPathComponent("replaced-\(UUID().uuidString).mp4");try fm.moveItem(at:out,to:retired)}
        try fm.moveItem(at:stage,to:out)
        var updated=project;updated.combinedMasters=(project.combinedMasters ?? []).filter{$0.key != key}+[CombinedMaster(key:key,file:relative,source:candidate,parts:parts)]
        try updated.save(root)
        return(updated,"Combined \(project.sources.count) originals into one full-quality master. AI cuts use this master's seconds.")
    }
}
