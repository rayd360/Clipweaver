# ClipWeaver 5.0 verification — September 28, 2026

Passed native workflow tests (`build/test-5.log`):
- Loaded the exact user-reported package. All caption groups fit at 270×480, 1080×1920, 1920×1080 and 640×640 without dropping words or leaving the canvas.
- Rendered its first caption group; visually inspected READY / TO / CELEBRATE fitting the portrait frame.
- Imported a reusable music track; included the selected start, listening copy, saved brief and requested three versions in the review manifest.
- Imported three versions atomically, rendered each with source shape and 24 fps, and verified audio is still present beyond the source song's length.
- Rejected an invalid third version without replacing the current edit.
- Verified portable project music and three edit paths after relocation; original hashes unchanged.

Passed caption/logo regression (`build/test-5-captions.log`) and legacy regression (`build/test-5-legacy.log`): captions, timing, transparency, HDR, original frame rates, original offsets, embedded music/images, end cards, response deduplication and transactional imports.

Python three-choice validator and packer passed, including rejection of AI-supplied music in new responses. Editor skill metadata validated.

Installed-app UI checks:
- Prepare controls occur before the source clip list.
- Saved a disposable idea and updated it; removed the test entry afterward, preserving the test record.
- Three previews displayed side by side. Play All showed matching elapsed positions across all three (test sources start one second apart).
- Selecting Choice 3 updated the export screen to Choice 3 with source shape and source fps.
- Replaced the SwiftUI video-player wrapper with native AVPlayerLayer and disabled automatic stalling waits for synchronized host-time playback, resolving crashes found during testing.
- Removed the disposable project from the library list without deleting test evidence; restored the user's military project.

Old single-edit packages remain supported. New creative variations depend on the AI's selections and narrative; the app validates the three-edit structure, timing, assets and source constraints.
