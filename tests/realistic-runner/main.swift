import Foundation
let base=URL(fileURLWithPath:CommandLine.arguments[1])
let tools=try Toolchain.locate(), engine=Engine(tools:try Toolchain.locate()),job=JobControl()
func require(_ condition:Bool,_ message:String)throws{if !condition{throw WeaverError(message)}}
func log(_ s:String){print(s);fflush(stdout)}
var times:[String:Double]=[:]
func timed<T>(_ name:String,_ action:()throws->T)rethrows->T{let start=Date();defer{times[name]=Date().timeIntervalSince(start)};return try action()}
do {
 let original=base.appendingPathComponent("Original-60s-1080p-24fps.mp4")
 let project=try engine.add([original],project:Project(name:"One-minute footage test"),job:job,progress:{s,_ in log(s)})
 try project.save(base)
 let review=try timed("prepare_seconds"){try engine.prepare(project,root:base,preset:.balanced,job:job,progress:{s,_ in log(s)})}
 let edit=EditPlan(projectId:project.projectId,title:"One-minute source test",fps:"source",clips:[EditClip(sourceId:"CLIP_001",start:4.25,end:12.25),EditClip(sourceId:"CLIP_001",start:20.25,end:28.25),EditClip(sourceId:"CLIP_001",start:45.25,end:53.25)])
 let editURL=base.appendingPathComponent("edit.json");try writeJSON(edit,editURL)
 let decoded=try EditPlan.load(editURL);try decoded.validate(project)
 let social=try timed("social_seconds"){try engine.render(decoded,project:project,root:base,settings:ExportSettings(kind:.social),job:job,progress:{s,_ in log(s)})}
 let website=try timed("website_seconds"){try engine.render(decoded,project:project,root:base,settings:ExportSettings(kind:.website),job:job,progress:{s,_ in log(s)})}
 let reviewURL=review.appendingPathComponent("videos/CLIP_001.mp4")
 let ri=try probe(reviewURL,tools:tools),si=try probe(social,tools:tools),wi=try probe(website,tools:tools)
 try require(ri.fpsValue==8 && abs(ri.duration-60)<0.13,"Review frame rate or length incorrect")
 try require(si.fpsValue==24 && si.width==1920 && si.height==1080 && abs(si.duration-24)<0.05,"Social quality/rate/length incorrect")
 try require(wi.fpsValue==24 && wi.width==1280 && wi.height==720 && abs(wi.duration-24)<0.05,"Website rate/size/length incorrect")
 try require(fileSize(website)<fileSize(social),"Website export was not smaller")
 try require(try fingerprint(original,job:job)==project.sources[0].sha256,"Original changed")
 let result:[String:Any]=["passed":true,"original_bytes":fileSize(original),"review_bytes":fileSize(reviewURL),"social_bytes":fileSize(social),"website_bytes":fileSize(website),"review_fps":ri.fps,"final_fps":si.fps,"source_seconds":ri.duration,"final_seconds":si.duration,"timings":times,"social_path":social.path,"website_path":website.path,"review_path":reviewURL.path]
 try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:base.appendingPathComponent("realistic-results.json"))
 log("PASS: one-minute original, 8 fps review, original-resolution 24 fps social, smaller 24 fps website, original unchanged")
}catch{fputs("FAIL: \(error.localizedDescription)\n",stderr);exit(1)}
