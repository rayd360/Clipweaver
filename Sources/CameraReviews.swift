import Foundation

extension SourceClip {
    var isCameraReview: Bool { URL(fileURLWithPath: filename).pathExtension.lowercased() == "lrf" }
    var cameraOriginalFilename: String? {
        guard isCameraReview else { return nil }
        return URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent + ".OSV"
    }
    var timestampFilename: String { cameraOriginalFilename ?? filename }
}

extension Project {
    var usesCameraReviews: Bool { sources.contains(where: \.isCameraReview) }
}

// Only the small camera review is imported. The paired OSV is never opened or modified.
func cameraReviewInput(_ supplied: URL) throws -> URL {
    guard supplied.pathExtension.lowercased() == "osv" else { return supplied }
    let stem = supplied.deletingPathExtension().lastPathComponent
    let siblings = try fm.contentsOfDirectory(at: supplied.deletingLastPathComponent(), includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
    let matches = siblings.filter {
        $0.pathExtension.lowercased() == "lrf" &&
        $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(stem) == .orderedSame
    }
    guard matches.count == 1, let review = matches.first else {
        throw WeaverError("Add the matching .LRF camera preview for \(supplied.lastPathComponent). Keep its original filename so the timestamps identify the correct OSV in DJI Studio.")
    }
    return review
}

func cameraActivityPrompt(_ project: Project, root: URL?) -> String {
    """
    Inspect this ClipWeaver DJI activity-review package (project_id: \(project.projectId)). Read manifest.json and the bundled editor instructions. The review videos come from small .LRF camera previews; the user will edit the original .OSV files in DJI Studio using your selected time ranges.

    Find useful moments when meaningful activity actually happens. Inspect both fisheye views and motion around candidate intervals. Use storyboards to find candidates, then inspect denser video frames before setting the start/end. A sparse storyboard is not proof that nothing happened between its frames. Disclose any footage or sound you could not inspect. Never claim an unseen action or unheard dialogue.

    Activity to look for: \(project.videoIdea?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? project.videoIdea! : "People interacting, meaningful movement, reactions, and other clearly visible events. Keep enough lead-in and ending to make each event usable; avoid long inactive stretches.")

    Return ONE .clipweaveredit package_version 2 response with exactly three choices: a broad useful-moments selection, a tighter best-moments selection, and a concise highlights selection. Keep source order and chronological order within each source. Choose lengths from the actual events; do not force a fixed runtime. Give each clip a short note explaining the observed activity. Use each manifest source ID and that file's elapsed seconds, starting at its first displayed frame. Times reset to zero for every source. camera_original_filename identifies the matching OSV; it is a filename label, not a source ID. The app displays and saves these original-file times. End is exclusive.

    Keep schema_version 4, aspect and fps "source", transition_style "cut", and every clip transition zero. Omit captions, caption_styles, overlays, logo_placements, end_card, music, and embedded assets. Do not stitch, reframe, stabilize, or render OSV files. Validate and package the three edit plans with the bundled validate_edit.py and pack_response.py helpers. Honor all source bounds and return distinct descriptive titles.

    If you have local file access, save the response atomically in \(root?.appendingPathComponent("Incoming").path ?? "the project's Incoming folder"). Otherwise return one downloadable response for opening in ClipWeaver. Keep the source files unchanged.
    """
}
