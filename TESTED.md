# ClipWeaver verification

The native Apple Silicon application was built and ad-hoc signed on this Mac. Its private FFmpeg/FFprobe binaries include 18 bundled libraries; runtime use does not require Homebrew or Python.

Automated integration checks passed using generated fixtures:
- Project save/reopen and unchanged-original SHA-256 verification.
- Eight-fps review videos with matching source duration and synchronized audio.
- Timestamped visual-index generation and private local-path exclusion from upload manifests.
- Final 24 fps exports at original dimensions.
- Final 24000/1001 and 30000/1001 rates preserved.
- Correct color-coded source selections, including returning to another portion of the same original.
- Silent source clips, crossfades, music looping/ducking, website mute, and poster output.
- Twenty short selections without cumulative rounding dropping the final selected moment.
- HDR detection and macOS tone mapping, preserving resolution and frame rate. Native video services require normal Mac permissions; this test passed outside the build sandbox.
- Nonzero source timestamps mapped correctly to elapsed cut times.
- Rejection of invalid source ranges, project IDs, output frame rates, and unsupported effects.
- Cancellation handling.

Interface checks passed: native launch, saved-project opening, AI package preparation and ZIP creation, edit import, displayed cut list, output frame-rate display, and website export.

The skill passed quick_validate.py. Its standard-library validator accepted an actual exported plan and rejected invalid bounds and mismatched project IDs.

No user footage or external ChatGPT audiovisual-analysis session was available for an end-to-end creative evaluation. The app creates review media and instructions; the AI session must have suitable tools to inspect that media. Music generation is optional and requires an available generation tool; the local app mixes supplied audio.
