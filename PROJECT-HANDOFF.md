# ClipWeaver project handoff

Updated: 2026-10-07 (America/Chicago). Read this and CODE-MAP.md first; inspect only files relevant to the next task.

## Purpose and desired outcome

ClipWeaver is a personal local Apple Silicon Mac editor. Ordinary videos use compact AI reviews, three creative choices and original-quality exports. Version 6.1 also accepts DJI LRF camera previews and delivers per-original-file timestamps so the user can manually edit OSV footage in DJI Studio.

## Confirmed by the user

The handoff setup was approved on 2026-09-30 (“Yes, set up the handoff”) and is complete. Preserve that approval; do not ask again for the same setup. The user requested GitHub source backup, created rayd360/Clipweaver and explicitly chose to keep it public.

On 2026-10-07 the user requested LRF support and visible timestamps, stating they will handle OSV clips themselves. This short, clear request authorized implementation under the current build-my-program skill. Scope completed: LRF import/review, activity-focused AI instructions, selected-choice timestamps with OSV names, copy/save CSV, installation and validation. No OSV extraction is requested. The prior attempted generic lossless OSV trim failed on proprietary data tracks; do not claim OSV/DJI Studio trimming compatibility.

## Source and installation

Continue in the existing repository folder. On the development Mac, the local-only `.local/PROJECT-LOCATIONS.md` records exact source/app paths and recovery locations; it is excluded from GitHub. Launching chat pointers also identify the canonical source. Do not relocate the app or modify enclosing synced reference files.

Installed and built release: **6.1**, bundle build **8**. The installer places ClipWeaver in the user’s Applications folder; build output is `build/ClipWeaver.app`. User projects and shared libraries use the standard locations implemented in Projects.swift and GlobalLibrary.swift. Editor instructions live in `skill/clipweaver-editor` and are bundled/installed by the scripts.

Repository: local `main` tracks `origin/main`, `https://github.com/rayd360/Clipweaver`, public by user choice. Pre-update checkpoint: `37946373ad6f8a4ecefc69b46d233b0b3bbb2d39`. LRF source milestone `367ef59eb186749bb5734a2ed3b577a21885bc1f` reached GitHub main; its complete tree matched the staged local source. Final public notes omit local environment details. No uncommitted program work remains at completion; recheck `git status` and remote state before synchronization, and use `git log -1` for the latest notes revision.

## Essential behavior and invariants

The native SwiftUI/AppKit app bundles FFmpeg/FFprobe, preserves source hashes, supports portable managed assets, edit history, legacy responses, compatible lossless combined masters, shared creative libraries, captions/logos/end cards, source-rate exports and selected-choice revision packages.

For camera projects, add LRF files with unchanged camera names. Dropped OSV files resolve only to a matching sibling LRF; OSV is never opened or modified. All review sources remain separate when any LRF is present. Manifest `review_purpose: activity_timestamps` and optional `camera_original_filename` guide AI to chronological useful moments with activity notes. Preparation is local; AI inspection remains an external user action.

Review & Export shows Source timestamps for the selected choice: original filename, own-file start/end/length and note. Copy timestamps gives readable text; Save timestamps writes CSV with clock/decimal times. Every imported choice also stores its CSV beside edit JSON. Previews are optional for LRF projects. Ordinary combined-master selections map back to original-file offsets; cuts crossing recording boundaries remain rejected.

Preserve originals, prior valid edits, stable identities, relative managed paths and legacy single-edit support. LRF/OSV matching assumes camera basenames and corresponding recording timelines; the user checks cuts in DJI Studio. Do not claim local automatic event detection, stitched previews, or OSV exports.

## Chosen defaults / assumptions

These notes own live status, CODE-MAP owns navigation, START-HERE is the manual, TESTED is older evidence. Keep notes compact and exclude private runtime data/media/credentials. Use isolated tests; preserve affected real records before updates. UI isolation uses `CLIPWEAVER_DEFAULTS_SUITE`, `CLIPWEAVER_UI_PROJECT`, `CLIPWEAVER_GLOBAL` and `CLIPWEAVER_LIBRARY`.

## Commands

From the canonical source, with Xcode tools, Python and Homebrew FFmpeg installed:

```sh
python3 scripts/build.py
python3 scripts/install-local.py
open build/ClipWeaver.app
```

Close the app before installation. Installer preserves previous app/editor skill under `build/install-backups`; it does not back up user data. Exact local recovery locations are recorded in `.local/PROJECT-LOCATIONS.md`, excluded from source backups.

Relevant fresh-folder checks:

```sh
clipweaver_check_root=$(python3 -c 'import tempfile; print(tempfile.mkdtemp(prefix="clipweaver-check-"))')
build/ClipWeaver.app/Contents/MacOS/ClipWeaver --camera-review-test "$clipweaver_check_root/CameraCase"
CLIPWEAVER_LIBRARY="$clipweaver_check_root/V6Library" build/ClipWeaver.app/Contents/MacOS/ClipWeaver --v6-test "$clipweaver_check_root/V6" tests/fixtures/reported-caption.clipweaveredit
CLIPWEAVER_GLOBAL="$clipweaver_check_root/SelfGlobal" CLIPWEAVER_LIBRARY="$clipweaver_check_root/SelfLibrary" build/ClipWeaver.app/Contents/MacOS/ClipWeaver --self-test --test-dir "$clipweaver_check_root/Self"
```

## Validation, remaining work and unanswered questions

On 2026-10-07: build/signature passed; installed and built executable hashes match. Camera tests, real DJI LRF, validator/packer, self-test and V6 (including V5) passed. Installed UI verified LRF picker, camera instructions, selected-choice time changes, copy/save CSV and panel layout. Existing project/registry/global records and the last-project preference were preserved. The native picker updated only its last-folder preference. The installed app was reopened with regular user projects. See `tests/LRF-TIMESTAMP-TESTS.md` for exact evidence/limits.

Measured real LRF: 17,557,399 bytes became a 547,726-byte review video, excluding package overhead; source duration retained within one 8 fps sample. Timestamp selections were synthetic: these tests do not establish AI event-selection accuracy.

The requested update and verified GitHub backup are complete. No unanswered product decision or required work remains; the next feature has not been requested.
