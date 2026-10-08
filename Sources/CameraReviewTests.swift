import Foundation

func runCameraReviewTests(_ suppliedBase: URL, realReview: URL?) throws {
    let base = suppliedBase.resolvingSymlinksInPath()
    guard !fm.fileExists(atPath: base.path) else { throw WeaverError("Use a fresh test folder.") }
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    setenv("CLIPWEAVER_GLOBAL", base.appendingPathComponent("Global").path, 1)
    setenv("CLIPWEAVER_LIBRARY", base.appendingPathComponent("Library").path, 1)
    let tools = try Toolchain.locate(), engine = Engine(tools: try Toolchain.locate()), job = JobControl()
    func check(_ value: Bool, _ message: String) throws { if !value { throw WeaverError(message) } }
    let footage = base.appendingPathComponent("Camera")
    try fm.createDirectory(at: footage, withIntermediateDirectories: true)
    let a = footage.appendingPathComponent("CAM_TEST_A_D.LRF"), b = footage.appendingPathComponent("CAM_TEST_B_D.lrf")
    for (i, url) in [a, b].enumerated() {
        try tools.ffmpeg(["-f", "lavfi", "-i", "testsrc2=s=640x320:r=24000/1001:d=6", "-f", "lavfi", "-i", "sine=frequency=\(440+i*220):duration=6", "-c:v", "libx264", "-preset", "veryfast", "-c:a", "aac", "-shortest", "-f", "mp4", url.path], job: job)
    }
    let original = a.deletingPathExtension().appendingPathExtension("OSV")
    let originalBytes = Data("UNTOUCHED CAMERA ORIGINAL".utf8)
    try originalBytes.write(to: original)
    let root = base.appendingPathComponent("Project")
    try prepareProjectFolders(root)
    var p = try engine.add([a, original, b], project: Project(name: "LRF timestamp check"), job: job, progress: { _,_ in })
    try check(p.sources.count == 2 && p.usesCameraReviews, "LRF and paired OSV were not deduplicated")
    try check(p.sources[0].filename == a.lastPathComponent && p.sources[0].cameraOriginalFilename == original.lastPathComponent, "Camera filename mapping is wrong")
    do {
        _ = try cameraReviewInput(footage.appendingPathComponent("MISSING.OSV"))
        throw WeaverError("Missing camera preview was accepted")
    } catch { try check(error.localizedDescription != "Missing camera preview was accepted", "Missing-preview rejection failed") }
    try p.save(root)
    p = try Project.open(root).0
    try check(p.usesCameraReviews && p.sources.count == 2, "LRF projects do not reopen")
    let review = try engine.prepare(p, root: root, preset: .small, job: job, progress: { text,_ in print(text); fflush(stdout) })
    let manifest = try readJSON(ReviewManifest.self, review.appendingPathComponent("manifest.json"))
    try check(manifest.sources.count == 2 && manifest.combinedParts == nil && !fm.fileExists(atPath: root.appendingPathComponent("Masters").path), "Camera files were combined; original-file times would be lost")
    try check(manifest.reviewPurpose == "activity_timestamps" && manifest.captionsEnabled == false, "Activity-review instructions are missing")
    let assets = GlobalAssets()
    try check(p.reviewManifestIsCurrent(manifest, assets: assets, root: root), "Completed LRF review was rejected by the upload readiness check")
    var cameraSettings = p
    cameraSettings.styleReferenceId = "ignored-camera-reference"
    cameraSettings.selectedMusic = ProjectMusic(id: "ignored-camera-music", name: "Ignored", path: "unused.m4a", duration: 30, start: 4)
    cameraSettings.logoPath = "unused.png"; cameraSettings.suppressCaptions = false
    try check(cameraSettings.reviewManifestIsCurrent(manifest, assets: assets, root: root), "Camera review incorrectly requires ordinary music, reference, logo or caption settings")
    var stale = manifest; stale.reviewPurpose = nil
    try check(!p.reviewManifestIsCurrent(stale, assets: assets, root: root), "Missing camera purpose was accepted")
    stale = manifest; stale.projectId = "OTHER_PROJECT"
    try check(!p.reviewManifestIsCurrent(stale, assets: assets, root: root), "A different project's package was accepted")
    stale = manifest; stale.sources.removeLast()
    try check(!p.reviewManifestIsCurrent(stale, assets: assets, root: root), "Missing camera sources were accepted")
    stale = manifest; stale.sources[0].sha256 = "changed"
    try check(!p.reviewManifestIsCurrent(stale, assets: assets, root: root), "Changed camera sources were accepted")
    stale = manifest; stale.videoIdea = "Changed activity request"
    try check(!p.reviewManifestIsCurrent(stale, assets: assets, root: root), "A changed activity request was accepted")
    var ordinary = p; ordinary.sources[0].filename = "ordinary-a.mp4"; ordinary.sources[1].filename = "ordinary-b.mp4"
    var ordinaryManifest = manifest; ordinaryManifest.reviewPurpose = nil; ordinaryManifest.captionsEnabled = true; ordinaryManifest.brand = assets.brand(for: ordinary).reviewValue
    try check(ordinary.reviewManifestIsCurrent(ordinaryManifest, assets: assets, root: root), "Ordinary video review readiness regressed")
    ordinary.suppressCaptions = true
    try check(!ordinary.reviewManifestIsCurrent(ordinaryManifest, assets: assets, root: root), "Changed ordinary caption setting was accepted")
    let upload = try engine.packReview(review, root: root, job: job)
    try check(fileSize(upload) > 0, "Camera upload ZIP was not created")
    _ = try engine.packReview(review, root: root, job: job)
    try check(fileSize(upload) > 0, "Re-preparing removed the camera upload ZIP")
    let packedManifest = try Toolchain(root: URL(fileURLWithPath: "/usr/bin")).run("unzip", ["-p", upload.path, "For AI/manifest.json"], job: job)
    try check(try jsonDecoder().decode(ReviewManifest.self, from: packedManifest).projectId == p.projectId, "Camera ZIP contains the wrong project")
    print("PASS: camera and ordinary upload readiness, ignored camera creative settings, stale/changed-package rejection, initial and repeated ZIP preparation")
    for (index, source) in manifest.sources.enumerated() {
        let info = try probe(review.appendingPathComponent(source.reviewVideo), tools: tools)
        try check(info.fpsValue == 8 && abs(info.duration - p.sources[index].media.duration) < 0.14, "LRF review timing drifted")
        try check(source.cameraOriginalFilename == p.sources[index].cameraOriginalFilename, "OSV filename missing from manifest")
    }
    let json = try String(contentsOf: review.appendingPathComponent("manifest.json"), encoding: .utf8)
    try check(!json.contains(footage.path), "Original disk paths leaked into the review package")
    let clips = [EditClip(sourceId: p.sources[0].id, start: 1.125, end: 2.625, note: "Observed gesture, then \"reaction\""), EditClip(sourceId: p.sources[1].id, start: 0.25, end: 1.75, note: "Second recording activity"), EditClip(sourceId: p.sources[0].id, start: 3.125, end: 4.125, note: "Return to first recording")]
    let choices = (0..<3).map { index in EditPlan(schemaVersion: 4, projectId: p.projectId, title: "Timestamp choice \(index+1)", aspect: "source", fps: "source", clips: index == 0 ? clips : [clips[index]], transitionStyle: "cut") }
    let response = root.appendingPathComponent("Incoming/Timestamp-check.clipweaveredit")
    let encodedChoices = try JSONSerialization.jsonObject(with: jsonEncoder().encode(choices))
    try JSONSerialization.data(withJSONObject: ["package_version": 2, "edits": encodedChoices, "assets": []], options: [.prettyPrinted, .sortedKeys]).write(to: response)
    let imported = try engine.importResponse(response, project: p, root: root, job: job)
    p = imported.0
    let rows = try p.sourceTimestamps(for: imported.1)
    try check(rows.count == 3 && rows[0].start == 1.125 && rows[1].start == 0.25 && rows[2].start == 3.125, "Selections were converted to finished-video or combined time")
    try check(rows[0].filename == "CAM_TEST_A_D.OSV" && rows[1].filename == "CAM_TEST_B_D.OSV" && rows[2].filename == rows[0].filename, "Repeated-source OSV labels are wrong")
    let text = try p.sourceTimestampText(for: imported.1)
    let csv = try p.sourceTimestampCSV(for: imported.1)
    try check(text.contains("00:00:01.125") && text.contains("00:00:02.625") && csv.contains("1.125000,2.625000") && csv.contains("\"\"reaction\"\""), "Copy or CSV times/escaping are wrong")
    for path in p.editChoices ?? [] {
        let folder = projectFile(path, root: root).deletingLastPathComponent()
        let name = URL(fileURLWithPath: path).lastPathComponent
        let csvName = name == "edit.json" ? "source-timestamps.csv" : name.replacingOccurrences(of: "edit-", with: "source-timestamps-").replacingOccurrences(of: ".json", with: ".csv")
        try check(fm.fileExists(atPath: folder.appendingPathComponent(csvName).path), "An imported choice is missing its timestamp CSV")
    }
    let preview = try engine.render(imported.1, project: p, root: root, settings: ExportSettings(kind: .preview), job: job, progress: { _,_ in })
    let previewInfo = try probe(preview, tools: tools)
    try check(abs(previewInfo.duration - imported.1.duration) < 0.1 && abs(previewInfo.fpsValue - 24000.0/1001) < 0.001, "LRF selections do not preview at the source frame rate")
    p.choicePreviews = [p.lastEditPath!: relativeProjectPath(preview, root: root)]
    try p.save(root)
    var regular = p
    regular.sources[0].filename = "ordinary-a.mp4"; regular.sources[1].filename = "ordinary-b.mp4"
    var combinedSource = regular.sources[0]
    combinedSource.id = "COMBINED_TEST"; combinedSource.media.duration = 12
    regular.combinedMasters = [CombinedMaster(key: "test", file: "Masters/test.mp4", source: combinedSource, parts: [MasterPart(sourceId: regular.sources[0].id, filename: "ordinary-a.mp4", start: 0, end: 6), MasterPart(sourceId: regular.sources[1].id, filename: "ordinary-b.mp4", start: 6, end: 12)])]
    let combinedEdit = EditPlan(projectId: regular.projectId, title: "Combined source check", clips: [EditClip(sourceId: combinedSource.id, start: 7.25, end: 9.5)])
    let mapped = try regular.sourceTimestamps(for: combinedEdit)
    try check(mapped[0].filename == "ordinary-b.mp4" && mapped[0].start == 1.25 && mapped[0].end == 3.5, "Existing combined footage is not mapped back to its own file")
    var bad = combinedEdit; bad.clips[0].start = 5.5; bad.clips[0].end = 6.5
    do { _ = try regular.sourceTimestamps(for: bad); throw WeaverError("Cross-boundary times were accepted") }
    catch { try check(error.localizedDescription != "Cross-boundary times were accepted", "Boundary rejection failed") }
    try check(try Data(contentsOf: original) == originalBytes, "Camera original was changed")
    try engine.verify(p.sources, job: job, progress: { _,_ in })
    let prompt = cameraActivityPrompt(p, root: root)
    try check(prompt.contains("each source") && prompt.contains("camera_original_filename") && prompt.contains("Give each clip a short note"), "Activity prompt omits timestamp requirements")
    print("PASS: LRF/OSV pairing, deduplication, separate 8 fps reviews, OSV filename labels, activity prompt, project reopen, selected/repeated-source timestamps, CSV delivery/escaping, source-rate preview, legacy combined-time mapping, boundary rejection, unchanged source files")
    if let realReview {
        guard realReview.pathExtension.lowercased() == "lrf" else { throw WeaverError("The real camera test requires an LRF file.") }
        let originalHash = try fingerprint(realReview, job: job)
        let realRoot = base.appendingPathComponent("RealCamera")
        try prepareProjectFolders(realRoot)
        var realProject = try engine.add([realReview], project: Project(name: "Real camera review check"), job: job, progress: { _,_ in })
        try realProject.save(realRoot)
        let realFolder = try engine.prepare(realProject, root: realRoot, preset: .small, job: job, progress: { text,_ in print(text); fflush(stdout) })
        let realManifest = try readJSON(ReviewManifest.self, realFolder.appendingPathComponent("manifest.json"))
        let realInfo = try probe(realFolder.appendingPathComponent(realManifest.sources[0].reviewVideo), tools: tools)
        try check(realInfo.fpsValue == 8 && abs(realInfo.duration - realProject.sources[0].media.duration) < 0.14, "Real LRF review lost original elapsed timing")
        let edit = EditPlan(projectId: realProject.projectId, title: "Real source timestamp check", clips: [EditClip(sourceId: realProject.sources[0].id, start: 4, end: 9)])
        let times = try realProject.sourceTimestamps(for: edit)
        try check(times[0].start == 4 && times[0].end == 9 && times[0].filename.hasSuffix(".OSV"), "Real LRF timestamps are wrong")
        try realProject.sourceTimestampCSV(for: edit).write(to: realRoot.appendingPathComponent("timestamp-check.csv"), atomically: true, encoding: .utf8)
        try check(try fingerprint(realReview, job: job) == originalHash, "Real camera preview was changed")
        realProject.lastEditPath = nil
        print("PASS: actual camera LRF imported, compressed to 8 fps, original duration preserved, 4–9 second OSV timestamp mapping, unchanged camera preview")
    }
    print("CAMERA REVIEW TESTS PASSED")
}
