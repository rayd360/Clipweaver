# ClipWeaver test results — September 20, 2026

## Result

The installed app's automated integration suite passed. A separate test of the same processing-engine source with a generated one-minute 1080p/24 fps clip also passed, using the installed app's bundled video tools. No app changes were needed.

The fresh button-by-button interface test is now complete and passed. Verified saved-project opening, preparing and refreshing the AI ZIP, importing edit.json, rendering a preview, and exporting Social and Website through the installed app. The new exports were independently checked: 24 seconds at 24 fps, social at 1920 × 1080, website at 1280 × 720, with audio and the website poster/embed/edit files present. The refreshed upload ZIP passed its archive integrity check. No real user footage was used or uploaded. The creative AI-analysis workflow was not tested against an external ChatGPT session.

## One-minute footage test

| File | Duration | Resolution | Frame rate | Size |
|---|---:|---|---:|---:|
| Generated original | 60 sec | 1920 × 1080 | 24 fps | 57.60 MB |
| AI review copy | 60 sec | Up to 854 px on longest side | 8 fps | 1.86 MB |
| Social edit | 24 sec | 1920 × 1080 | 24 fps | 25.41 MB |
| Website edit | 24 sec | 1280 × 720 | 24 fps | 3.23 MB |

The AI video was 96.8% smaller than its original. The website export was 87.3% smaller than the social export of the same edit. These measurements are for a moving synthetic test pattern and are not promised reduction rates for real footage. Package audio files and storyboard images are additional to the AI video size.

## Independent output checks

- Compared three rendered frames with the requested moments in the original; all matched with minimal encoding differences.
- Confirmed 24 different frames in the first second of the final video, rather than repeated frames from an 8 fps copy.
- Confirmed timed audio pulses remained aligned in the review, social, and website copies, including after each cut.
- Confirmed website MP4 layout supports fast-start playback.
- Validated the actual edit JSON with the installed skill's validator.
- Confirmed the original file's checksum stayed unchanged.

## Installed-app integration checks

Project save/open, review creation, selected cut order, multiple cuts from one source, 24/23.976/29.97 fps exports, silent footage, music looping/ducking, crossfades, website mute and poster, short-cut rounding, native HDR conversion, nonzero source timestamps, invalid-plan rejection, and cancellation checks all passed.

Evidence is in `2026-09-20-installed/integration-test.log`, `2026-09-20-ui/realistic-results.json`, and `2026-09-20-ui/independent-verification.json`.
