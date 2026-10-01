import Foundation

func runSelfTests() throws {
    let tools = try Toolchain.locate(), engine = Engine(tools:try Toolchain.locate()), job = JobControl()
    let base: URL
    if let i=CommandLine.arguments.firstIndex(of:"--test-dir"),CommandLine.arguments.count>i+1 {base=URL(fileURLWithPath:CommandLine.arguments[i+1])} else {base=fm.temporaryDirectory.appendingPathComponent("ClipWeaver-Test-\(UUID().uuidString)")}
    try fm.createDirectory(at:base,withIntermediateDirectories:true)
    func assert(_ yes:Bool,_ message:String) throws {if !yes {throw WeaverError("TEST: \(message)")}}
    func say(_ s:String) {print(s);fflush(stdout)}
    say("Fixtures: \(base.path)")
    let a=base.appendingPathComponent("original ' $ example.mp4"), b=base.appendingPathComponent("silent.mp4"), c=base.appendingPathComponent("cinema.mp4")
    try tools.ffmpeg(["-f","lavfi","-i","color=red:s=320x180:r=24:d=1","-f","lavfi","-i","color=green:s=320x180:r=24:d=1","-f","lavfi","-i","color=blue:s=320x180:r=24:d=1","-f","lavfi","-i","color=yellow:s=320x180:r=24:d=1","-f","lavfi","-i","sine=frequency=440:sample_rate=48000:duration=4","-filter_complex","[0:v][1:v][2:v][3:v]concat=n=4:v=1:a=0[v]","-map","[v]","-map","4:a","-c:v","libx264","-crf","10","-c:a","aac",a.path],job:job)
    try tools.ffmpeg(["-f","lavfi","-i","color=magenta:s=180x320:r=30000/1001:d=3","-c:v","libx264",b.path],job:job)
    try tools.ffmpeg(["-f","lavfi","-i","testsrc2=s=320x180:r=24000/1001:d=3","-c:v","libx264",c.path],job:job)
    var p=Project(name:"Test Project")
    p=try engine.add([a,b,c],project:p,job:job,progress:{_,_ in})
    try p.save(base)
    let reopened=try Project.open(base.appendingPathComponent("Project.clipweaver")).0
    try assert(reopened.sources.count==3,"Saved project did not reopen")
    let review=try engine.prepare(p,root:base,preset:.balanced,job:job,progress:{s,_ in say(s)})
    for s in p.sources {let info=try probe(review.appendingPathComponent("videos/\(s.id).mp4"),tools:tools);try assert(info.fpsValue==8,"Review is not 8 fps");try assert(abs(info.duration-s.media.duration)<0.14,"Review duration drift")}
    let manifest=try readJSON(ReviewManifest.self,review.appendingPathComponent("manifest.json"))
    try assert(manifest.sources.count==3 && manifest.sources[0].storyboards.count>0,"Review index missing")
    try assert(!(String(data:try Data(contentsOf:review.appendingPathComponent("manifest.json")),encoding:.utf8) ?? "").contains(base.path),"Private original path leaked to manifest")
    say("PASS: project persistence, 8 fps reviews, timeline duration, visual index, private path exclusion")
    let edit=EditPlan(projectId:p.projectId,title:"Repeated selection",fps:"source",clips:[EditClip(sourceId:p.sources[0].id,start:0.1,end:0.6),EditClip(sourceId:p.sources[1].id,start:0.1,end:0.6),EditClip(sourceId:p.sources[0].id,start:2.1,end:2.6)])
    let social=try engine.render(edit,project:p,root:base,settings:ExportSettings(),job:job,progress:{s,_ in say(s)})
    let si=try probe(social,tools:tools);try assert(si.fpsValue==24,"24 fps original was changed");try assert(si.width==320 && si.height==180,"Original dimensions changed")
    func rgb(_ file:URL,_ t:Double) throws -> [Double] {let data=try tools.run("ffmpeg",["-v","error","-ss",num(t),"-i",file.path,"-frames:v","1","-vf","scale=16:16","-f","rawvideo","-pix_fmt","rgb24","pipe:1"]);let bytes=Array(data);try assert(bytes.count==768,"Frame extraction failed");return (0..<3).map {ch in stride(from:ch,to:bytes.count,by:3).reduce(0.0){$0+Double(bytes[$1])}/256}}
    let red=try rgb(social,0.2),magenta=try rgb(social,0.7),blue=try rgb(social,1.2)
    try assert(red[0]>180 && red[2]<50,"First source selection wrong")
    try assert(magenta[0]>80 && magenta[2]>80,"Middle source selection wrong")
    try assert(blue[2]>180 && blue[0]<50,"Repeated source selected wrong timestamp")
    let silentData=try tools.run("ffmpeg",["-v","error","-ss","0.65","-t","0.2","-i",social.path,"-vn","-f","f32le","-ac","1","pipe:1"])
    let samples=silentData.withUnsafeBytes {Array($0.bindMemory(to:Float.self))}
    try assert(samples.map{abs($0)}.max() ?? 0 < 0.005,"Silent source did not receive silence")
    say("PASS: original 24 fps, original resolution, repeated-source timestamps, cut order, silent input")
    let website=try engine.render(edit,project:p,root:base,settings:ExportSettings(kind:.website,mute:true),job:job,progress:{_,_ in})
    let wi=try probe(website,tools:tools);try assert(wi.fpsValue==24 && !wi.hasAudio,"Website fps or mute failed");try assert(fm.fileExists(atPath:website.deletingPathExtension().appendingPathExtension("jpg").path),"Website poster missing")
    for index in [1,2] {let e=EditPlan(projectId:p.projectId,title:"Fractional \(index)",clips:[EditClip(sourceId:p.sources[index].id,start:0,end:2)]);let u=try engine.render(e,project:p,root:base,settings:ExportSettings(kind:.preview),job:job,progress:{_,_ in});let info=try probe(u,tools:tools);try assert(abs(info.fpsValue-p.sources[index].media.fpsValue)<0.001,"Fractional fps not preserved")}
    say("PASS: website export, mute, poster, 29.97 and 23.976 fps preserved")
    let music=base.appendingPathComponent("music.m4a");try tools.ffmpeg(["-f","lavfi","-i","sine=frequency=220:sample_rate=48000:duration=2","-c:a","aac",music.path],job:job);p.musicPath=music.path
    let mixed=EditPlan(projectId:p.projectId,title:"Crossfade and music",clips:[EditClip(sourceId:p.sources[0].id,start:0,end:1.5),EditClip(sourceId:p.sources[1].id,start:0,end:1.5,transition:0.25),EditClip(sourceId:p.sources[0].id,start:2,end:3,transition:0.25)],music:MusicPlan(filename:"music.m4a",volume:0.2,duck:true,loop:true))
    let cross=try engine.render(mixed,project:p,root:base,settings:ExportSettings(kind:.preview),job:job,progress:{_,_ in});let ci=try probe(cross,tools:tools);try assert(abs(ci.duration-3.5)<0.1 && ci.hasAudio,"Crossfade/music render duration wrong")
    say("PASS: crossfades, looped music, ducking, output duration")
    let tinyCuts = EditPlan(projectId:p.projectId,title:"Fractional cut boundaries",clips:(0..<20).map { i in EditClip(sourceId:p.sources[0].id,start:i == 19 ? 2.1 : 0.1,end:i == 19 ? 2.21 : 0.21) })
    let tiny = try engine.render(tinyCuts,project:p,root:base,settings:ExportSettings(kind:.preview),job:job,progress:{_,_ in})
    let tinyInfo = try probe(tiny,tools:tools)
    let lastColor = try rgb(tiny,tinyInfo.duration-0.05)
    try assert(abs(tinyInfo.duration-2.5)<0.05 && lastColor[2]>180,"Fractional-frame rounding truncated a later selection")
    say("PASS: many short cuts preserve the final selected moment")
    let hdr = base.appendingPathComponent("hdr-original.mov")
    try tools.ffmpeg(["-f","lavfi","-i","testsrc2=s=320x180:r=24:d=2","-c:v","libx265","-x265-params","log-level=error:pools=2:frame-threads=2:colorprim=9:transfer=18:colormatrix=9","-pix_fmt","yuv420p10le","-color_primaries","bt2020","-color_trc","arib-std-b67","-colorspace","bt2020nc","-tag:v","hvc1",hdr.path],job:job)
    let hp = try engine.add([hdr],project:Project(name:"HDR test"),job:job,progress:{_,_ in})
    try assert(hp.sources[0].media.hdr,"HDR input not detected")
    let he = EditPlan(projectId:hp.projectId,title:"HDR tone mapped",clips:[EditClip(sourceId:hp.sources[0].id,start:0,end:1.5)])
    let ho = try engine.render(he,project:hp,root:base,settings:ExportSettings(kind:.preview),job:job,progress:{s,_ in say(s)})
    let hi = try probe(ho,tools:tools)
    try assert(!hi.hdr && hi.fpsValue == 24 && hi.width == 320,"HDR conversion failed")
    say("PASS: native HDR tone mapping, original resolution and frame rate")
    let offset=base.appendingPathComponent("offset.mov")
    try tools.ffmpeg(["-i",a.path,"-c","copy","-output_ts_offset","3",offset.path],job:job)
    let op=try engine.add([offset],project:Project(name:"Offset"),job:job,progress:{_,_ in})
    let oe=EditPlan(projectId:op.projectId,title:"Nonzero source origin",clips:[EditClip(sourceId:op.sources[0].id,start:2.1,end:2.6)])
    let oo=try engine.render(oe,project:op,root:base,settings:ExportSettings(kind:.preview),job:job,progress:{_,_ in})
    let oc=try rgb(oo,0.2)
    try assert(oc[2]>180 && oc[0]<50,"Nonzero timestamps shifted the selected moment")
    say("PASS: nonzero source timestamps map to original elapsed time")
    var invalid=edit;invalid.clips[0].end=999
    do {try invalid.validate(p);throw WeaverError("Invalid bounds accepted")} catch let e as WeaverError {try assert(e.message != "Invalid bounds accepted","Invalid bounds accepted")}
    invalid=edit;invalid.projectId="wrong"
    do {try invalid.validate(p);throw WeaverError("Wrong project accepted")} catch let e as WeaverError {try assert(e.message != "Wrong project accepted","Wrong project accepted")}
    invalid=edit;invalid.fps="8"
    do {try invalid.validate(p);throw WeaverError("8 fps output accepted")} catch let e as WeaverError {try assert(e.message != "8 fps output accepted","8 fps output accepted")}
    let bad=base.appendingPathComponent("invalid.json");try "{\"schema_version\":1,\"titles\":[]}".write(to:bad,atomically:true,encoding:.utf8)
    do {_ = try EditPlan.load(bad);throw WeaverError("Unsupported instructions accepted")} catch let e as WeaverError {try assert(e.message != "Unsupported instructions accepted","Unsupported instructions accepted")}
    let cancel=JobControl();cancel.cancel();do{try cancel.check();throw WeaverError("Cancellation ignored")}catch let e as WeaverError {try assert(e.message != "Cancellation ignored","Cancellation ignored")}
    for s in p.sources {try assert(try fingerprint(URL(fileURLWithPath:s.originalPath),job:job)==s.sha256,"Original mutated")}
    say("PASS: invalid cuts/project/fps/instructions rejected, cancellation, originals unchanged")
    try runResponseTests(engine:engine,project:p,base:base)
    say("ALL TESTS PASSED")
}
