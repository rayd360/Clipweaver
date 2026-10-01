# ClipWeaver 3.1 global library verification

- Native test suite `--global-test tests/global-3-1` passed: 59.94 fps retained, compressed 1080-edge reference with audio, stable rename identity, selected reference separated from editable sources in manifest, ZIP creation, deselection removes media, shared logo resolves across projects, logo opt-out, original hash unchanged.
- Installed 3.1 in ~/Applications/ClipWeaver.app and verified the version and new sidebar tab in the running installed app. Previous app and skill backed up in build/install-backups.
- Imported the supplied caption recording through the actual chooser. UI naming/rename and persistence across restart verified. Original 6,171,448 bytes; reference roughly 1.7 MB. ffprobe decoded 773 frames in both. Variable-frame-rate average metadata differs slightly due to final frame duration rounding (13.521667 versus 13.533333 seconds); no frame was dropped.
- Project selector tested in Star Party sample project: selecting the reference marks it Selected and hides the stale ZIP-copy button; clearing the selection restores the previous state. The test selection was cleared afterward.
- Hover player uses a muted looping AVQueuePlayer with AVPlayerLayer, created on hover and stopped/released on exit. Automated screenshots did not establish hover frame progression; Play and hover implementation are present, but this particular motion interaction is not claimed as visually verified.
- Global branding starts unset, with a chooser and migration menu for existing project logos. No test logo or reference-video branding was installed as the user's global logo.
- Skill frontmatter validated. Bundled and installed editor instructions distinguish reference-only media from editable original sources and explain global branding.
