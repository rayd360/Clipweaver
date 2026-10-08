# ClipWeaver 6.1.1

## DJI LRF files: find moments for DJI Studio

Create a project and drop the camera’s **.LRF** files into **Prepare for AI**, or use **Add Footage…**. Keep their original filenames. ClipWeaver uses the small camera previews, makes smaller 8 fps review copies, and keeps every recording separate so its times start at zero. If you drop an OSV file, ClipWeaver uses its matching LRF in the same folder.

1. Write what activity you want AI to find in **My Video Idea**, then prepare the review package.
2. Use **Copy ChatGPT .Zip file** and **Copy ChatGPT Prompt**. Paste both into ChatGPT and ask it to return the ClipWeaver response.
3. Open the **.clipweaveredit** response in ClipWeaver. In **Review & Export**, select one of the three moment selections.
4. Read **Source timestamps** below the choices. It shows the matching **OSV filename**, **Start**, **End**, length and activity note. **Copy timestamps** copies a readable list; **Save timestamps…** saves a CSV with clock times and exact seconds. Each choice also has an automatic CSV beside its imported edit in **Edits**.
5. Find those files and time ranges in DJI Studio and make your original-quality OSV edits there. End times mark the first moment excluded. **Build previews** is optional and uses the LRF footage.

Version 6.1.1 fixes a readiness check that rejected completed LRF packages. An existing valid LRF package now shows **Copy ChatGPT .Zip file** and **Show Upload ZIP** without preparing it again.

AI inspects the supplied review package; ClipWeaver does not detect activity by itself. The camera views can appear as two fisheye circles. The OSV files remain unchanged. Filename matching assumes the camera’s original LRF/OSV names and corresponding recording timelines; review the selected ranges in DJI Studio.

## Ordinary video projects

Open ClipWeaver. The **Projects** screen lists your projects with their stored size. Create and name a project, open it, or use its menu to rename, show its folder, clear rebuildable files, remove it from the list, or move it to Trash. Deleting a project does not delete referenced originals outside its folder. The app refuses to trash a project that contains a referenced original inside it.

New projects live in **Movies → ClipWeaver Projects**, with a separate folder for each project. Videos remain in their existing locations. Keep originals available (including downloading cloud files before use). Missing originals can be relinked; ClipWeaver checks that they match the original content.

1. Open **Prepare for AI**. Select your brand, optional reference video and music, and write or load a saved video idea. Enable **Don’t include captions** if desired. Source clips are at the bottom.
2. Prepare the small copies, then use **Copy ChatGPT .Zip file** and **Copy ChatGPT Prompt**. Paste both into ChatGPT. The ZIP includes editor instructions and 8 fps review footage; style references retain their original frame cadence.
3. Ask AI for one **`.clipweaveredit`** response containing three distinct versions. Save it into the project's **Incoming** folder or open it with ClipWeaver. Invalid responses preserve the current edit.
4. In **Review & Export**, hover each choice or use **Play all together**, select your favorite, and export Social or Website. Exports use original footage, source shape and source frame rate. The caption checkbox also works after import and rebuilds all three previews.
5. To request changes, select a version and use **Refine the selected version**. Describe changes, prepare the revision ZIP, then copy that ZIP and its revision prompt to ChatGPT. It contains the full selected video, all original review materials, the prior AI response and the exact selected edit. AI returns three interpretations of your changes to that selected version.

If a response belongs to an older project that is not listed, open its Project.clipweaver file once. The app can then route responses to it. Previously saved loose edit.json files still work through **More → Import Older edit.json**. Separately supplied music is copied into the project when selected through **More → Add Music**.

## What is stored per project

- **Project.clipweaver**: project name, original file references and current edit.
- **For AI**, **Upload to AI.zip**: review video, audio, storyboards and instructions.
- **Incoming**: complete AI responses delivered locally.
- **Edits**: complete imported response revisions with edit.json and their music/graphics.
- **Assets**: music imported separately or adopted from an older project.
- **Previews**, **Exports**: rendered results. Website exports include a poster and sample HTML player.

Use **Earlier edits** to return to a previous response. Importing the same response again does not duplicate its revision. Changes are validated before becoming active. Bad responses report an error and preserve the previous edit. New project-managed references are relative, so moving the project folder preserves bundled music and graphics. Original paths remain references and may need relinking if the originals move.

## Wording and branding

AI can add promotional text, verified subtitles, transparent PNG/JPEG graphics and a static branded end card. Text is rendered at the final export resolution, with wrapping and a readable background. Timing and positioning come from the response. Always preview wording and spelling. The app does not transcribe speech; the AI must actually hear/transcribe it before claiming to create subtitles. Select your own music in the shared library; AI is instructed not to generate music.

Website output uses a smaller resolution/bitrate with the original frame rate. Its player does not request looping, and the last frame remains at the end. If there is an end card, the website poster uses that card. Social platforms control their own looping behavior.

HDR footage is tone-mapped to SDR using macOS with temporary full-resolution intermediates, which can need several GB of free space. The app includes its video tools and needs no Terminal, Python, Homebrew, API key or network connection for preparation/rendering. It performs no uploads. Review packages contain footage and filenames; original Mac paths are excluded. The copied prompt includes the local response destination so a local AI can save there.

This app is locally signed for your Mac, not notarized for public distribution.


## Version 3: captions, project logo and faster handoff

Prepare for AI now has an optional Project Logo area. Choose your PNG or JPEG; a small copy stays inside that project. Enable **Include logo in AI review** when requesting logo use, then prepare again. The AI chooses its placement and timing. Review Edit has a per-edit logo switch.

The editor can use compact timed words or styled segments: white ordinary text, larger bold italic charcoal emphasis, and selective fade/slide entrances. The Mac renders crisp text at final export resolution. Existing static overlays and older edits remain supported.

**Review Edit** and **Open AI Response** immediately check Incoming for a new valid response. Repeated responses stay in edit history without reimporting; damaged responses preserve the current edit.

After preparing, **Copy ChatGPT .Zip file** copies the latest upload ZIP as a file. Paste into ChatGPT's message box. **Show Upload ZIP** reveals it in Finder for attachment workflows that need dragging or a file chooser.


## Version 3.1: shared branding and reference library

Open **Branding & References** in the sidebar. Choose your global logo once, or import an existing project's logo from its menu. All projects use the shared logo; each project can omit it from AI review, and each edit can hide it at export. Old projects remain readable.

Use **Add Reference Video…**, then give it a name. ClipWeaver makes a detailed compressed copy with a 1080-pixel maximum edge, retaining source frame cadence and audio. References can be up to ten minutes long. Originals stay unchanged. Search names, rename at any time, hover a thumbnail for silent playback, or click Play for audio and controls.

In a project's **Prepare for AI**, select one reference or leave it empty. Then prepare again. Only that reference goes in the ZIP alongside the 8 fps footage reviews and instructions telling AI to mock its style using your footage and global brand. Selection is remembered by ID, so renaming does not break it. Global files are stored in `~/Library/Application Support/ClipWeaver/Global`; project folders keep their own upload packages.


## Version 4.0

New AI edits choose one transition style for the entire sequence: cuts, or cross-dissolves lasting 0.5–0.8 seconds each. Older responses remain supported.

Preparing matching footage now builds a lossless combined master in the project's Masters folder, then makes one 8 fps footage review from it. The AI chooses multiple ranges from this long timeline, and final rendering uses the full-quality master. Matching requires compatible codec, dimensions, frame rate, color and audio. Incompatible footage remains separate and the preparation screen explains why. The optional style reference still travels separately. Masters need extra disk space and remain with edit history; the originals are not changed. Moving the project also moves its masters.

Projects show allocated disk space for their folders (including masters and generated files; originals outside the folder are excluded). Use **Biggest to smallest** or **Newest to oldest**. **Delete Project** moves the project and its contents to the Mac Trash; recover it there if needed. Projects less than seven days old require confirmation. Older projects go directly to Trash. Unknown legacy creation dates use the folder's creation date. Global branding/references and originals outside the folder are not removed.

Captions now have solid editorial lettering, larger defaults and clearer contrast, with soft backing for charcoal emphasis or light emphasis on dark footage. The editor instructions encourage short phrases, purposeful line breaks and expressive staggered entrances. AI still chooses the wording, size, timing and placement; reference effects beyond the supported caption/transition controls must be approximated.

The AI manifest lists each original recording’s start and end on the combined timeline. A selection must stay within one original recording. To use both sides of a join, AI must return two explicit selections; the app rejects accidental crossings and keeps frame rounding inside the original boundary.


## Version 5.0: three creative choices

Prepare for AI now has reusable Music and My Video Idea libraries. Add a track once, select it for a project, listen, and choose a starting second. The project keeps its own portable music copy. Music loops when an edit outlasts the song; AI never generates it. Rename or remove shared tracks without breaking project copies. Saved ideas can be searched, loaded, edited, updated, saved as new, renamed or deleted. Each project also saves its current idea independently.

Prepare again after changing music, idea or reference. The copied prompt includes the idea and music selection and always requests source shape and frame rate. AI returns one response with three distinctly named versions. All three follow a selected reference but differ creatively. Review Edit imports them together and automatically builds previews. Hover for silent playback; Play all together synchronizes the previews, with sound only from the selected version. Select a version, then export Social or Website. Build previews again after changing the project music or logo visibility.

Source clips are at the bottom of Prepare for AI, below Small Copies for AI. Caption groups wrap and scale to fit automatically while preserving words, emphasis and timings. Older single-edit responses are supported, including responses created before automatic fitting.


## Version 6.0: review, export and revisions

The main workflow has two steps: Prepare for AI and Review & Export. Saved ideas, music and style references use consistent dropdown selectors. Music is also managed in Branding & References. The initial brand is Rhythm & Flash Events; additional brands can have their own names and logos. Existing shared logos remain available under the initial brand.

The shared Don’t include captions setting hides added animated captions and static overlays in previews and exports without changing the saved AI response. It preserves logos, end cards and lettering recorded in the footage. Prepare again after changing this option to send updated instructions to AI.

The editor must inspect caption placement throughout the whole caption, including moving faces, entrances and dissolves. Captions must never cover faces; avoid existing lettering where possible. Omit captions if safe placement cannot be verified. This is an AI editing requirement, not a local face-detection guarantee: review the output before publishing. The three alternatives choose their durations and caption schedules independently unless your brief specifies otherwise.

Revision ZIPs are stored under each project's Revisions folder. They contain a full-resolution, source-frame-rate rendering of the selected version with current local caption/music/logo settings, so they can be larger than the original review ZIP. Original review contents are preserved unchanged under original-review; current root instructions and settings take precedence. Previous responses remain in edit history.
