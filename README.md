# ClipWeaver

ClipWeaver is a personal video editor for Apple Silicon Macs. Add original
footage, prepare an AI review package, import three creative edit choices,
preview them, and export a Social or Website video. Version 6 also supports
selected-choice revision packages, reusable brands, music, and style references.

The app prepares files locally. Sending a review package to an AI service is a
separate user action. Exports use the original-quality media.

## Build

Requirements: Apple Silicon Mac, macOS 14 or newer, Xcode command-line tools,
Python 3, and Homebrew FFmpeg/FFprobe available on the build machine. The build
bundles FFmpeg and its libraries; the resulting app does not require Python or
Homebrew at runtime.

```sh
python3 scripts/build.py
open build/ClipWeaver.app
```

After verifying an update, close ClipWeaver and install it with:

```sh
python3 scripts/install-local.py
```

The installer backs up the previous installed app and editor skill under
`build/install-backups`. It installs to `~/Applications/ClipWeaver.app` and
updates `~/.codex/skills/clipweaver-editor`. It does not back up user projects.

## Continue development

Read [AGENTS.md](AGENTS.md), [PROJECT-HANDOFF.md](PROJECT-HANDOFF.md), and
[CODE-MAP.md](CODE-MAP.md) first. [START-HERE.md](START-HERE.md) is the app manual.
Test commands and their isolation requirements are in the handoff. The portable
V5/V6 caption fixture is `tests/fixtures/reported-caption.clipweaveredit`.
Historical test reports describe prior runs; they do not certify a fresh build.

## Source backup contents

This repository contains native Swift source and test suites, build/install
scripts, the app icon, the ClipWeaver editor skill, selected generic test
inputs, and documentation. `.gitignore` keeps video projects, original footage,
generated media, installed/build output, dependency binaries, caches, and
credentials out of source history.
