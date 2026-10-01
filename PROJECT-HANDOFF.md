# ClipWeaver project handoff

Updated: 2026-09-30 (America/Chicago). Read this and CODE-MAP.md first; inspect only files relevant to the next task.

## Purpose and desired outcome

ClipWeaver is a personal, local Apple Silicon Mac video editor. The user adds original footage, chooses an idea/music/brand/reference, prepares a compact AI review package, imports three creative edit choices, previews them, and exports Social or Website video. Version 6 also prepares revision packages for a selected edit. Success means usable exports from original-quality media, preserved projects/originals, and straightforward continuation of development.

## Confirmed by the user

On 2026-09-30 the user requested the build-my-program skill for ClipWeaver and approved: “Yes, set up the handoff.” Approved scope: persistent project notes, a code map, verified source/app locations and build/test instructions, and a ready-to-copy continuation message. This approval is for the handoff setup; preserve it so another chat does not request approval again for the same work.

That setup is complete. On 2026-09-30 the user also requested that this program be put into GitHub. This authorizes the source backup and repository setup; no app behavior change was requested. Existing features below are observed implementation/documentation, not a reconstruction of past user approvals.

## Locations and project identity

- Canonical editable source and these notes: `/Users/jonathandouglas/.codex/.chatgpt-projects/g-p-6a7f34c62ce48191a75f041f246e5e84/ClipWeaver`.
- Installed app: `/Users/jonathandouglas/Applications/ClipWeaver.app`.
- Local build: `build/ClipWeaver.app`; installed/built version **6.0**, bundle build **7**.
- Launching chat workspace: `/Users/jonathandouglas/.codex/.chatgpt-projects/g-p-6abd634b83408191989cd6ece699f67a`. Its PROJECT-HANDOFF.md and CODE-MAP.md are pointers to this project, not duplicate status records.
- User video projects default to `~/Movies/ClipWeaver Projects`; registry: `.projects.json`.
- Shared brands/music/ideas/references: `~/Library/Application Support/ClipWeaver/Global/Library.json` and associated files.
- Editor skill source: `skill/clipweaver-editor`; installed copy: `~/.codex/skills/clipweaver-editor`.

The source currently sits under the older “DJ trainer” mirror. Its enclosing project name is not the app's name. Do not relocate it merely to continue. A local Git repository is initialized on `main` in this source folder. The remote is `https://github.com/rayd360/Clipweaver`, default branch `main`. The user created this repository and explicitly chose to keep it **public** on 2026-09-30; repository identity, visibility and write permission were verified through the GitHub connector. Source upload is in progress; record the exact verified checkpoint after completion. Both enclosing mirrors protect synced lowercase `sources/`; leave those files and their AGENTS.md untouched.

## What exists and essential invariants

The native app uses SwiftUI/AppKit with local bundled FFmpeg/FFprobe. It provides project persistence/relinking, 8 fps review media, compatible lossless combined masters, response validation and edit history, three-choice playback, shared creative libraries, captions/logos/end cards, and source-rate exports.

Version 6 adds Prepare for AI → Review & Export, multiple brand profiles, caption suppression without altering the saved AI response, and selected-choice revision ZIPs. Revision packages preserve the original review, prior response, and current output settings.

Preserve originals, previous valid edits, stable source/reference identities, relative managed-asset paths, and legacy single-edit support. Reject selections crossing an original recording boundary. Use selected music locally; retain current original-shape/frame-rate behavior. Local preparation does not upload files. AI caption placement requirements are not a local face-detection guarantee.

## Chosen defaults / assumptions

Use this source folder as the single development record. AGENTS.md instructs future chats to refresh both compact notes after material changes and before a handoff. CONTINUE-IN-NEW-CHAT.md supplies the reusable message. Keep START-HERE.md as the existing app manual and TESTED.md as historical evidence.

Use isolated test folders and redirect `CLIPWEAVER_GLOBAL`/`CLIPWEAVER_LIBRARY`. Back up affected real records before a future update that can change them. Exclude media, private project records, credentials, generated builds, and long logs from handoff notes.

## Commands

Run from the canonical source folder. Build prerequisites found on this Mac: Python 3, Xcode command-line tools, Homebrew FFmpeg/FFprobe, codesign, otool and install_name_tool. Runtime app use requires none of Python/Homebrew.

```sh
python3 scripts/build.py
open "/Users/jonathandouglas/Applications/ClipWeaver.app"
```

Install after an authorized, verified app update, with the app closed:

```sh
python3 scripts/install-local.py
```

The installer backs up the previous app/editor skill under `build/install-backups`. It does not back up real project/global-library data.

For future affected checks, choose the relevant command; each test destination must be fresh. Do not run every suite for a documentation change.

```sh
clipweaver_check_root=$(mktemp -d /private/tmp/clipweaver-check.XXXXXX)
CLIPWEAVER_GLOBAL="$clipweaver_check_root/SelfGlobal" CLIPWEAVER_LIBRARY="$clipweaver_check_root/Library" build/ClipWeaver.app/Contents/MacOS/ClipWeaver --self-test --test-dir "$clipweaver_check_root/Self" > "$clipweaver_check_root/self.log" 2>&1
CLIPWEAVER_LIBRARY="$clipweaver_check_root/Library" build/ClipWeaver.app/Contents/MacOS/ClipWeaver --v6-test "$clipweaver_check_root/V6" tests/fixtures/reported-caption.clipweaveredit > "$clipweaver_check_root/v6.log" 2>&1
CLIPWEAVER_LIBRARY="$clipweaver_check_root/Library" build/ClipWeaver.app/Contents/MacOS/ClipWeaver --global-test "$clipweaver_check_root/GlobalTest" > "$clipweaver_check_root/global.log" 2>&1
```

V6/global suites set their own isolated global-library paths. Native video/HDR services may require normal Mac permissions.

## Validation and remaining work

On 2026-09-30: handoff paths, source symbols, test flags/fixture, document links and compactness checked; installed signature verified; installed and local-build executable SHA-256 matched (`b63bdd355ec2ba4c80792a2ca9eb2bef9df86ef6c4ae45ea2ccd673685f7de55`). App source/scripts and installed app were unchanged.

Existing `build/test-6.log` and `build/test-6-global.log`, dated 2026-09-28, end in passing summaries. They cover revisions, caption suppression, brands, prior-response/history/original preservation and global libraries; V6 includes V5 checks. These suites and the UI were not rerun during this documentation session. TESTED.md is older evidence, not a current release certificate.

GitHub preparation: source, scripts, icon, editor skill, test code/reports and notes are selected; generated test folders, Edits, Deliverables, builds, media and credentials are excluded. A generic caption fixture preserves layout/style/timing while omitting original event metadata; the original response remains local and unchanged. App source and installed app are unchanged; app suites/UI were not rerun for this source-backup task.

Remaining work: upload the prepared source checkpoint to the public repository the user chose, then verify the remote tree and branch. Unanswered question afterward: what app change should come next? If this Mac is unavailable, obtain source from the verified GitHub backup when complete; do not reconstruct it from old chats or the installed binary.
