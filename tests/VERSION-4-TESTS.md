# ClipWeaver 4.0 verification — September 27, 2026

## Passed

- Native combined-master tests: lossless joining of compatible clips, one 8 fps AI footage review, original-to-master timeline map, repeated selections from the master, cached-master reuse, project relocation, and separate-file fallback for incompatible formats.
- Real-footage preparation: two compatible originals became one full-quality master and one review video. Their join is recorded at 8.833333 seconds in `v4-real-compatible/For AI/manifest.json`.
- Original hashes remained unchanged.
- Uniform transition validation: mixed cuts/dissolves and dissolves outside 0.5–0.8 seconds rejected; actual rendered dissolve pixels and end-card overlap duration checked.
- Boundary protection: a 3–5 second selection spanning a 4-second original join rejected; explicit 3–4 and 4–5 selections accepted. A 3.89–4 selection rendered only frames from the first original after output-frame rounding. Python editor validator independently rejects crossings and accepts explicit adjacent selections.
- Caption regression: filled white and bold italic emphasis, contrast backing, word entrances/end times, logo transparency/disable, previews and exports, package validation, duplicate/damaged responses, relocation.
- Legacy regression: HDR conversion, 24/23.976/29.97 fps, source offsets, repeated selections, frame rounding, static overlays, embedded music, end cards, response import and relocation.
- Real sample rendered at source 24 fps to Preview, Social and Website. Reference and output frames visually inspected. New example: `v2-real/Star Party Samples/Exports/Star Party  Editorial Captions v4 — Website.mp4`.
- Native UI: project sizes and separate sorting buttons present; disposable recent project showed confirmation before Trash; disposable eight-day-old project went directly to Trash without a confirmation dialog. Neither test touched a user project.
- Skill metadata validator passed.

## Evidence

Native logs: `../build/test-4-boundary.log`, `test-4-caption.log`, `test-4-legacy.log`, `test-4-real.log`, `test-4-real-combined.log`.

Compatible masters require matching codec details, dimensions, constant frame cadence, color, and audio layout. Incompatible footage intentionally remains separate. Optional style-reference media remains a separate upload. Caption effects are locally rendered approximations within the documented entrance controls; AI chooses the final wording and composition.

Deletion moves project folders to the Mac Trash. Originals outside those folders and global branding/reference files are retained. Projects containing original footage inside their own folder are protected from deletion.
