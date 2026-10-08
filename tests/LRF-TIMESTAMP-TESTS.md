# ClipWeaver 6.1 LRF and timestamp checks

Fresh execution: 2026-10-07, Apple Silicon Mac. Version 6.1, bundle build 8.

Passed:

- LRF picker/import and OSV-to-sibling-LRF resolution; duplicate and missing-preview handling; source filenames retained; project reopen.
- Two compatible camera previews remain separate, with one 8 fps review per recording and activity metadata/OSV labels in the manifest.
- Selected and repeated-source ranges retain their own file’s elapsed seconds. Visible/copy/CSV clock times include milliseconds; CSV also includes exact decimal seconds and quoted notes.
- Each imported response choice saves its own CSV transactionally. Existing combined-master selections map back to their original file; boundary crossings remain rejected.
- Optional LRF selection preview renders at source frame rate. Camera originals and test previews remain unchanged.
- A real DJI camera LRF imported successfully: 17,557,399 bytes became a 547,726-byte review video; 16.683333-second source timing was preserved within one 8 fps sample. A synthetic 4–9-second selection mapped to the OSV filename. This measured video size excludes storyboards/audio/ZIP overhead.
- The bundled Python validator and response packer accept all three camera choices.
- Existing self-test and V6 regression suite (including V5) passed: response validity/history, original preservation, captions, brands, selected-choice revisions, HDR, source time offsets and rendering.
- Installed app UI: LRF file selectable through Add Footage; camera help/version visible; switching choices updates Source timestamps; Copy reports success; Save produces a CSV whose filename and 0.250000–1.750000 range match the selected choice. Panel layout visually checked.
- Installed signature valid; installed and built executable SHA-256 match: `ee3789206987c56735a6663c6a823779a7f36496ac119ea2492bbb855248d87d`.
- Existing project/registry/global records remain byte-identical; last-project preference retained. The native file picker changed only its last-folder preference. Prior app/editor instructions are backed up locally.

Checks use temporary projects and separate global/library paths. Test footage, actual camera filenames, generated media, logs and user records remain local and excluded from Git.

```sh
clipweaver_check_root=$(python3 -c 'import tempfile; print(tempfile.mkdtemp(prefix="clipweaver-lrf-check-"))')
build/ClipWeaver.app/Contents/MacOS/ClipWeaver --camera-review-test "$clipweaver_check_root/CameraCase"
CLIPWEAVER_LIBRARY="$clipweaver_check_root/V6Library" build/ClipWeaver.app/Contents/MacOS/ClipWeaver --v6-test "$clipweaver_check_root/V6" tests/fixtures/reported-caption.clipweaveredit
CLIPWEAVER_GLOBAL="$clipweaver_check_root/SelfGlobal" CLIPWEAVER_LIBRARY="$clipweaver_check_root/SelfLibrary" build/ClipWeaver.app/Contents/MacOS/ClipWeaver --self-test --test-dir "$clipweaver_check_root/Self"
```

Limit: tests verify media handling and timestamp delivery, not AI event-selection accuracy. AI still inspects the supplied package externally. OSV names are inferred from unchanged camera basenames. ClipWeaver does not cut/stitch OSV; the user checks and edits those ranges in DJI Studio.

## Preparation repair: 6.1.1, build 9

Fresh execution: 2026-10-07. Completed LRF packages were incorrectly rejected by the ordinary-video readiness check, which expected enabled captions and branding. Readiness now checks activity-review metadata and exact camera source identities; camera projects omit ordinary creative settings intentionally. Ordinary-video caption/brand/music/reference/logo checks remain intact. Paired-preview lookup also retains the supplied folder spelling to deduplicate in aliased Mac folders.

Passed: current camera/ordinary reviews, ignored camera creative settings, changed request/source/project rejection, initial and repeated ZIP preparation, all existing camera timestamp checks, and V6 regressions. Installed UI Prepare for AI completed and automatically copied the ZIP without an alert. A previously prepared real package passed complete ZIP integrity, was recognized and copied in the installed repair without rebuilding. Project/manifest/registry/shared-library data and the completed ZIP were unchanged.

Installed/build executable SHA-256 matched: `77472d1e743c75eb0029d71ca316ef4151f42695a918df44b84046cb419ac04f`. Installed signature verified. The app/editor instructions and affected saved records were preserved locally before installation. Private project names, paths, footage and test logs are excluded from source history.
