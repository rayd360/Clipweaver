# ClipWeaver code map

Updated: 2026-10-07. Paths are relative to the canonical ClipWeaver folder identified in PROJECT-HANDOFF.md. Tests listed are existing checks to select when affected, not claims of fresh execution.

| Feature | Main files / stable symbols | Relevant tests |
| --- | --- | --- |
| Native launch, command modes, main screens | `Sources/main.swift`; `Sources/Interface.swift`: `AppDelegate`, `Studio`, `StudioView` | Native UI checks; command modes route to the suites below |
| Project persistence, sources, preparation | `Sources/Core.swift`: `Project`, `SourceClip`, `Engine.prepare`, `fingerprint`, `ReviewManifest` | `Sources/SelfTests.swift`: `runSelfTests` |
| Project list, storage, deletion, relinking | `Sources/Projects.swift`: `ProjectLibrary`, `projectFile`; `Sources/ProjectInterface.swift`; `Studio.relink` in Interface | SelfTests, ResponseTests, VersionFourTests |
| AI response import, incoming detection, history | `Sources/Projects.swift`: `AIResponse.load`, `Engine.importResponse`, `Engine.findIncoming`; ProjectInterface: `receiveResponse`, `restoreRevision` | `Sources/ResponseTests.swift`: `runResponseTests` (called by self-test); V5/V6 |
| DJI LRF activity review and OSV labels | `Sources/CameraReviews.swift`: `cameraReviewInput`, `cameraActivityPrompt`, `SourceClip.cameraOriginalFilename`; Core: `Engine.add`, `ReviewManifest.reviewPurpose`; CombinedFootage: `prepareCombined` | `Sources/CameraReviewTests.swift`: `runCameraReviewTests` |
| Per-original-file timestamps, copy/save CSV | `Sources/SourceTimestamps.swift`: `Project.sourceTimestamps`, `sourceTimestampCSV`, `Studio.copySourceTimestamps`, `StudioView.sourceTimestampsPanel`; Projects: `Engine.importResponse` | CameraReviewTests; installed UI choice/copy/save checks |
| Compatible combined master and original boundaries | `Sources/CombinedFootage.swift`: `CombinedMaster`, `Engine.prepareCombined`; `Sources/Editing.swift`: `EditPlan.validate` | `Sources/VersionFourTests.swift`: `runVersionFourTests` |
| Rendering, sound, transitions, website output | `Sources/Editing.swift`: `EditPlan`, `ExportSettings`, `Engine.specification`, `Engine.render`; `Sources/HDR.swift` | SelfTests, ResponseTests, VersionFourTests |
| Captions, image overlays, logos, end cards | `Sources/Captions.swift`: `Caption`, `CaptionStyle`, `captionSprites`; `Sources/Overlays.swift`: `TextOverlay`, `EndCard`; `Sources/Logo.swift` | `Sources/CaptionTests.swift`: `runCaptionTests`; V5 caption fitting; V6 suppression |
| Brands and style references | `Sources/GlobalLibrary.swift`: `GlobalAssets`, `BrandProfile`, `StyleReference`, `resolvedLogo`; `Sources/WorkflowSix.swift`: `selectBrand` | `Sources/GlobalTests.swift`: `runGlobalTests`; V6 brand isolation |
| Saved music/ideas and local caption setting | `Sources/CreativeLibrary.swift`: `LibraryMusic`, `SavedIdea`, `withSelectedMusic`; WorkflowSix: `setSuppressCaptions` | `Sources/VersionFiveTests.swift`: `runVersionFiveTests`; V6 |
| Three-choice preview/selection | `Sources/EditChoices.swift`: `EditChoice`, `ChoicePlayback`, `ChoicesComparison`, `Studio.renderChoices` | V5 import/render checks; UI playback checks |
| Selected-edit revision exchange | `Sources/Revisions.swift`: `RevisionContext`, `Engine.revisionPackage`, `Studio.buildRevisionPackage` | `Sources/VersionSixTests.swift`: `runVersionSixTests` (first runs V5) |
| Build, install, bundled editing instructions | `scripts/build.py`; `scripts/install-local.py`; `skill/clipweaver-editor/` (SKILL.md, references/edit-format.md, scripts/validate_edit.py, scripts/pack_response.py) | Build/signature verification; response validator/packer |

UI tests can isolate project preferences with `CLIPWEAVER_DEFAULTS_SUITE` and select a temporary project with `CLIPWEAVER_UI_PROJECT`, alongside the usual global/library isolation.

Dependencies: Swift compiler targeting arm64 macOS 14+, Apple AppKit/SwiftUI/CryptoKit/AVFoundation/AVKit, bundled FFmpeg/FFprobe and copied dylibs. Python is used by build/install/editor scripts, not by the running native app. There is no Swift Package manifest.

Test flags in main.swift: `--camera-review-test DIR [REAL_LRF_PATH]`, `--self-test` (+ optional `--test-dir`), `--v6-test DIR RESPONSE`, `--v5-test DIR RESPONSE`, `--v4-test DIR`, `--global-test DIR`, `--caption-test DIR`. Use isolated paths as documented in PROJECT-HANDOFF.md. V5/V6 use the generic `tests/fixtures/reported-caption.clipweaveredit` in source backups; the original event response remains local and excluded from Git. `Sources/SampleWorkflow.swift` is a separate sample workflow, not the default test route.

Development continuity: PROJECT-HANDOFF.md owns status/decisions/commands; this file owns code navigation; AGENTS.md owns note-maintenance instructions; CONTINUE-IN-NEW-CHAT.md owns the copyable message. START-HERE.md is the user manual.
