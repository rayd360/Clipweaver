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
- Nine existing project/registry/global records remain byte-identical; last-project preference retained. The native file picker changed only its last-folder preference. Prior app/editor instructions are backed up locally.

Checks use temporary projects and separate global/library paths. Test footage, actual camera filenames, generated media, logs and user records remain local and excluded from Git.

```sh
clipweaver_check_root=$(mktemp -d /private/tmp/clipweaver-lrf-check.XXXXXX)
build/ClipWeaver.app/Contents/MacOS/ClipWeaver --camera-review-test "$clipweaver_check_root/CameraCase" /path/to/camera-preview.LRF
CLIPWEAVER_LIBRARY="$clipweaver_check_root/V6Library" build/ClipWeaver.app/Contents/MacOS/ClipWeaver --v6-test "$clipweaver_check_root/V6" tests/fixtures/reported-caption.clipweaveredit
CLIPWEAVER_GLOBAL="$clipweaver_check_root/SelfGlobal" CLIPWEAVER_LIBRARY="$clipweaver_check_root/SelfLibrary" build/ClipWeaver.app/Contents/MacOS/ClipWeaver --self-test --test-dir "$clipweaver_check_root/Self"
```

Limit: tests verify media handling and timestamp delivery, not AI event-selection accuracy. AI still inspects the supplied package externally. OSV names are inferred from unchanged camera basenames. ClipWeaver does not cut/stitch OSV; the user checks and edits those ranges in DJI Studio.
