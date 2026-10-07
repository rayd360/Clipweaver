# ClipWeaver 6.0 workflow metadata

The root manifest adds `captions_enabled` (boolean), `brand` (`id`, `name`), and `editing_policy_version: 6`. If captions_enabled is false, omit captions, caption_styles, and caption/text image overlays. The app can also hide these locally after import without modifying the original AI response. Logos and separate end cards remain available.

Never overlay captions on any face during their whole visible interval or entrance. Inspect motion and both sides of cross-dissolves; omit captions if you cannot verify face-free placement. Prefer positions clear of existing words. Existing-word overlap is allowed only when best for readability, never as an excuse to cover a face.

Three alternatives choose duration and caption timing independently unless the user's brief constrains them. Distinct titles alone are not enough.

Revision packages include revision.json, full-resolution selected-output.mp4, selected-edit.json, rendered-edit.json, the previous AI response, and the complete original ZIP contents under original-review/. Use the current root manifest and instructions. Revise only the explicitly selected baseline into three choices. User revision times refer to the finished selected video; edit clip times still refer to original sources. Do not list selected-output.mp4 as an editable source.

# Current delivery contract: ClipWeaver 5.0

New responses use `{ "package_version": 2, "edits": [edit1, edit2, edit3], "assets": [...] }`. Exactly three edits, all same project_id, distinct descriptive titles, each schema_version 4 with aspect and fps "source". They should differ in moment selection, opening, sequencing and caption narrative, while all respecting the chosen reference and brief. Do not rename identical edits. Each version has its own uniform transition style and timeline.

Omit music in all new edits and do not embed audio. The user selects a reusable track and start time in ClipWeaver; manifest.selected_music gives name, listening file, duration, start and loop. The app applies that music to every version and loops when needed. No selected track means no added music. Never ask about shape or compose music.

manifest.video_idea contains the saved project brief; requested_versions is 3. The app imports all choices atomically, builds previews and lets the user select an export. Caption font_size is a desired size: the native renderer wraps phrases and fits whole caption groups while preserving style proportions and timing. Use concise text to retain large readable typography.

Use pack_response.py with choices.json containing the three-edit array. Existing package_version 1 single-edit responses and their assets remain readable. Legacy music and shape fields below describe backward compatibility, not new response instructions.

---

# ClipWeaver edit format, version 4

The Mac app reads JSON and rejects unknown fields. It resolves sources using local project records. It does not execute commands supplied by the AI.

## Root fields

| Field | Type | Meaning |
|---|---|---|
| schema_version | integer, required | 4 for new edits; 1–3 remain supported for older edits |
| project_id | string, required | Exact `project_id` from manifest |
| title | string, required | 1–200 characters; used for export filenames |
| aspect | string, optional | `source` (default), `portrait` (9:16), `landscape` (16:9), `square` |
| fps | string, optional | `source` (default); original rate of the first selection |
| clips | array, required | 1–100 selections in output order |
| music | object or null, optional | One actual local music file |
| notes | string, optional | Human-readable editing notes, not rendering commands |

Explicit fps values supported: `24000/1001`, `23.976`, `24`, `25`, `30000/1001`, `29.97`, `30`, `48`, `50`, `60000/1001`, `59.94`, `60`, `120000/1001`, `120`. Use rational values for fractional rates. Eight fps is exclusively for review; do not use it for output.

## Each selection in clips

| Field | Type | Meaning |
|---|---|---|
| source_id | string, required | Exact source `id`, such as `CLIP_001` |
| start | number, required | Inclusive elapsed seconds on the original timeline |
| end | number, required | Exclusive elapsed seconds on the original timeline |
| volume | number, optional | Original audio gain 0–2; default 1; 0 mutes |
| transition | number, optional | Crossfade duration INTO this selection, 0–2 seconds; default 0 |
| framing | string, optional | `fit` (default, may letterbox) or `fill` (crops) |
| focus_x | number, optional | 0–1; horizontal crop position across the available crop range; default 0.5 |
| focus_y | number, optional | 0–1; vertical crop position; default 0.5 |
| note | string, optional | Why this selection belongs in the edit |

Start must be at least zero. End must exceed start and not exceed manifest duration. Each selection must last at least one original frame. The first transition is zero. For every selection, incoming transition plus the following selection's incoming transition must be shorter than that selection. Transitions overlap shots and sound; total runtime is sum(end-start) minus all transitions. Maximum final runtime is one hour.

Times are numeric decimal seconds, not timestamp strings. The renderer rounds each selection duration and crossfade to the nearest output frame (minimum one frame per selection), so the final runtime can differ slightly from the decimal sum. It does not truncate later selections to force an unaligned target duration. Selections from a source may repeat or overlap. Do not send filesystem paths or substitute filenames for IDs. Crop coordinates are positions within available excess pixels, not tracked facial coordinates. There is no crop animation, speed adjustment, or arbitrary effect field. Use the overlays field below for text and subtitles.

## Music fields

| Field | Type | Meaning |
|---|---|---|
| filename | string, required | Exact basename, e.g. `gentle-piano.m4a`; no directories or URLs |
| start | number, optional | Seconds into the music file, default 0 |
| volume | number, optional | Gain 0–2; default 0.2 |
| fade_in | number, optional | Seconds, default min(0.5, final runtime) |
| fade_out | number, optional | Seconds, default min(1, final runtime) |
| duck | boolean, optional | Default true; lowers music beneath all retained original sound |
| loop | boolean, optional | Default false; true repeats music if needed |

Fades must be between zero and final runtime. Without looping, short music ends in silence. The Mac app requires the user to select a file with the exact requested basename. Do not include a music object unless that actual track is available to deliver/select. Generated music requires an external tool; the Mac app mixes it but does not generate it.

## Example only — replace identities and times with observed evidence

```json
{
  "schema_version": 1,
  "project_id": "COPY-EXACT-PROJECT-ID-FROM-MANIFEST",
  "title": "A day by the water",
  "aspect": "portrait",
  "fps": "source",
  "clips": [
    {"source_id":"CLIP_001","start":12.4,"end":17.8,"volume":0.7,"note":"Opening view"},
    {"source_id":"CLIP_002","start":3.0,"end":9.2,"volume":1,"transition":0.3,"note":"Complete spoken thought"},
    {"source_id":"CLIP_001","start":46.1,"end":50.6,"volume":0.5,"note":"Return to the first location"}
  ],
  "notes": "15.8 seconds including the 0.3-second crossfade."
}
```

This example repeats the same original at two different ranges. It does not establish that those clips or events exist in a real project. Return only selections verified against the provided media and manifest.

Website resolution/bitrate and social quality are chosen in the app, outside this format. Both export modes use the same original frame rate. The user may override output shape in the app; framing remains per-selection. For destination-specific reframing decisions, provide separate plans when useful.


## Timed text and image overlays (schema_version 2)

Root `overlays` is an optional array of at most 100 entries. These use **finished-video seconds**, not original-source seconds. The end is exclusive. Overlay timing includes clip crossfade overlaps. Each entry supplies exactly one of `text` (1–500 characters) or `filename` (a bundled PNG/JPEG basename). Do not invent subtitle dialogue: transcribe audio only when it can actually be heard/transcribed; editorial promotional wording is separate.

Fields: `start`, `end` required; `x` default 0.1; `y` default 0.72; `width` default 0.8; `height` default 0.18; `font_size` default 0.05; `color` default "#FFFFFF"; `background` default "#000000B3"; `alignment` is left/center/right, default center. Coordinates and box dimensions are fractions of the output frame, measured from its top-left. The entire box must fit inside the frame. Font size is a fraction of frame height, allowed 0.015–0.15. Colors accept #RRGGBB or #RRGGBBAA. Text wraps and shrinks to fit; overly long text is rejected rather than clipped. All text uses bold system type, rasterized at export resolution. Avoid the extreme top, bottom, and right edges used by social-app controls. Preview for readability. PNG transparency is preserved; images fit inside the specified box without stretching. Later overlays appear over earlier ones.

Example: `{"start":0,"end":2,"text":"Make it a night to remember.","x":0.1,"y":0.15,"width":0.8,"height":0.2}`.

## Branded end card

Optional root `end_card`: `duration` (0.25–15 seconds), exactly one of `text` or `filename` (bundled PNG/JPEG), and optional `background` color (default #101218). Appends a static card after all footage. Its duration is included in total runtime. Text or the image fits inside the central 80% width and 50% height of the frame. For edge-to-edge artwork use overlays across the card with a full-frame rectangle. The music continues through the card. Do not invent a business identity; use supplied branding or ask for essential missing wording. Playing once and retaining the last frame is a player setting; a video cannot prevent a social platform from looping it.

## ONE response file — required delivery for ClipWeaver 2

Return one file with extension `.clipweaveredit`. It is UTF-8 JSON with exactly three root fields:

- `package_version`: 1 (the package container version, separate from edit schema).
- `edit`: the complete edit object described above.
- `assets`: an array of `{ "filename": "track.m4a", "sha256": "lowercase SHA256 of decoded bytes", "base64": "base64-encoded file bytes" }`.

Include every image/music asset referenced by the edit. Basenames only; no directories, URLs, scripts, originals, or review videos. Allowed asset extensions: png, jpg, jpeg, m4a, mp3, wav, aac. Limit total decoded assets to 100 MB and package to 150 MB; use compressed music and reasonably sized graphics. Asset filenames must be unique ignoring case. Images: maximum 8192 pixels per side, 32 megapixels total. Do not hand-write base64 or hashes.

Use `scripts/pack_response.py edit.json manifest.json asset_directory output.clipweaveredit`; it validates and writes the complete response atomically. If the user's copied prompt provides a local Incoming path and local tools can write there, save the response there. Otherwise return the single downloadable response; double-clicking it routes it to the matching registered project. The app unpacks assets, records a revision, and selects the edit/music automatically. No separate Add Music or Load Edit step is needed. Never modify Project.clipweaver or original files. A schema-1 loose edit.json remains importable via More for backward compatibility.


## Word captions and project logo (schema_version 3)

These optional root fields preserve `overlays` and `end_card`. Package version stays 1. All caption/logo times use **finished-video seconds**, including crossfade overlap and the end card, with start inclusive and end exclusive. Source clip times still use original-source seconds. Positions use normalized full-frame coordinates, origin at top left. Text and logo are rendered locally at each export's resolution, at the source timeline frame rate.

### caption_styles

Object mapping 1–40 character names to reusable styles; maximum 12. Each style accepts only:

| Field | Default | Limits |
|---|---|---|
| font_size | 0.04 | 0.018–0.07 of frame height |
| emphasis_scale | 1.3 | 1.1–1.6; multiplied size at most 0.10 |
| emphasis_color | #363B43 | #30343B, #363B43, or #464B52 |
| entrance | {"type":"none"} | Entrance object below |

Ordinary text is white, medium-weight system sans. Emphasis is bold italic and larger. Subtle contrasting outlines improve readability. Do not provide fonts, font files, gradients or arbitrary colors. Choose placement over a suitable background and avoid covering faces.

### captions

Array of at most 80 caption groups, 400 total words/segments and 80 simultaneously visible. Each group accepts `style` (optional preset name), `x`, `y`, `width`, `height` (defaults 0.10, 0.36, 0.76, 0.32), `alignment` (left/center/right, default center), and required `words` (1–60 entries). Boxes must fit x=0.08–0.86 and y=0.12–0.80, reserving space for typical social controls. These are conservative guides, not platform-specific guarantees.

Each word entry may represent one word or a short uniformly styled segment:

| Field | Required/default | Meaning |
|---|---|---|
| text | required | 1–80 characters, no newline; meaningful text, not a path |
| start, end | required | Finished-video seconds, 0 ≤ start < end ≤ runtime |
| style | normal | normal or emphasis |
| font_size | inherited | Optional final size, 0.018–0.10 of frame height; emphasis must exceed preset normal size |
| x, y | auto layout | Supply both for explicit full-frame placement of this segment; safe-area bounds apply |
| line_break_before | false | Start a new line during auto layout |
| entrance | inherited | Per-word override |

Auto layout reserves space for all entries from the beginning, preventing earlier words from jumping as later words appear. It wraps by measured width, mixes styles inline, and honors explicit line breaks. Explicit positions remove a segment from this flow. Keep enough room for italic overhang and movement. Native validation rejects text that does not fit; split long segments or reduce size. Do not animate every word without a creative reason.

Entrance fields: `type` is none/fade/slide. None accepts no other fields. Fade accepts `duration` (default 0.25, range 0.05–0.8 seconds, no longer than the segment's display duration). Slide also accepts `direction` (left/right/up/down, default up) and `distance` (default 0.025, range 0.005–0.08 of the corresponding frame axis). Direction denotes the side it starts from. Slide uses a short ease-out movement plus a fade. All words settle at their specified position; there is no exit animation. Keep the entire entrance inside the safe area. Total caption/logo span is limited to ten minutes.

### logo_placements

Optional array of up to 30 objects, only when `manifest.project_logo` supplies the user's requested logo. Inspect that image. Each placement requires `start`, `end`, `x`, `y`, `width`, `height`; optional `opacity` defaults to 1, range 0–1. The rectangle must fit the same safe area. The local project logo is fitted proportionally and centered in this rectangle; transparency is preserved. There is no filename field and no need to embed the existing project logo in response assets. Omit this array when no logo was requested. The user can disable the logo per edit in Review Edit. Never substitute reference-video branding. Old static image overlays still work.

### Example fields added to a valid edit

```json
{
  "caption_styles": {
    "social": {"font_size": 0.04, "emphasis_scale": 1.3, "emphasis_color": "#363B43"}
  },
  "captions": [{
    "style": "social", "x": 0.12, "y": 0.30, "width": 0.70, "height": 0.28,
    "alignment": "left",
    "words": [
      {"text": "Good", "start": 0.3, "end": 2.0},
      {"text": "energy.", "style": "emphasis", "start": 0.5, "end": 2.0,
       "entrance": {"type": "slide", "direction": "down", "duration": 0.25, "distance": 0.025}}
    ]
  }],
  "logo_placements": [{"start": 2.0, "end": 4.0, "x": 0.65, "y": 0.66,
                        "width": 0.16, "height": 0.08, "opacity": 0.85}]
}
```

The example is a fragment, not a complete response. Supply valid project_id, clips and schema_version 3, and only include its logo field when the manifest contains the requested project logo.


## Global branding and selected reference (ClipWeaver 3.1)

Branding is configured once in the global library, shared by all projects. `project_logo` remains the manifest field name for backward compatibility; it now contains a snapshot of that shared logo when enabled for this project. `logo_placements` remains unchanged and resolves to the current global logo during local rendering. It is still optional and can be hidden per edit.

The optional manifest `style_reference` object contains `id`, `name`, `file`, `duration`, `fps`, `width`, `height`, `role: "style_reference_only"`, and an instruction. Its media lives at `reference/style-reference.mp4`; unlike footage review videos, this detailed compressed copy preserves the original frame cadence rather than reducing it to 8 fps. Inspect it for the style the user wants to mock, including motion and word entrances. It is never a valid `source_id`, never part of the editable sources list, and should not be embedded in the AI response. Only one reference selected in the project is packaged; unselected global library videos are not uploaded. A rename keeps its stable ID. User footage and global branding supply the final content.


## Version 4: consistent transitions, combined timeline and editorial captions

New responses must set `schema_version: 4` and root `transition_style` to either `cut` or `cross_dissolve`. All inter-shot boundaries must follow that choice. For cut, omit transition or set 0 everywhere. For cross_dissolve, the first clip must have transition 0 and every later clip must specify an AI-chosen value from 0.5 to 0.8 seconds. Durations may vary within this range, but the transition type may not vary. Include overlap when computing total duration, and leave each clip longer than the sum of incoming and outgoing transitions. An appended end_card must follow the same transition style: its optional numeric transition is 0 for cuts or a required AI-chosen 0.5–0.8 seconds for dissolves. Subtract that overlap from total runtime too; the final shot and end card must be long enough. Older schemas remain readable with their original transition behavior.

Compatible input files are stream-copied into a project-local master before the 8 fps review is made. The AI manifest then lists one COMBINED_ source. Use that exact source ID and elapsed seconds on the master. `combined_parts` maps each constituent source_id/filename to its start/end in the master for navigation only. These constituent IDs are not valid clips in a new combined edit. Final rendering cuts the stored full-quality master, including repeated/noncontiguous selections. `preparation_note` explains combination or why formats remain separate. Full-quality masters stay in Masters/ and are reused when sources are unchanged; older masters are retained for edit history. Never use the low-resolution review as a render source.

Caption style now optionally accepts boolean `contrast_backing`. It defaults true for charcoal emphasis and false for light emphasis. A soft light backing keeps filled charcoal letters legible on busy footage. `emphasis_color` additionally supports #E8E9EC for luminous emphasis on dark shots. All other palette entries remain. Defaults are font_size 0.052, emphasis_scale 1.45; explicit older values remain valid. The renderer uses filled Helvetica Neue with bold italic emphasis and a subtle shadow instead of thin outlines. Use larger focal words, tight purposeful line composition, and staggered slide entrances to match the visual energy of a reference. Local layout still validates fit and safe areas; shorten or split text instead of shrinking everything.


### Original-video boundaries in a combined master

`combined_parts` records the exact start and end of every original in the long master. Never let a single clip selection cross an internal boundary. The app and validator reject it. Choose separate selections explicitly if both originals should appear. For three ten-second originals, 8–11 is invalid; use 8–10 and 10–11 as two selections. Apply the edit's uniform transition rule between them and account for overlap; for dissolves, lengthen selections if necessary to leave room for the required 0.5–0.8 seconds. Do not infer boundaries from visual changes; use the manifest's exact times.


## DJI LRF activity review metadata

`review_purpose: "activity_timestamps"` identifies a review for original-file moment selection. Each source can add `camera_original_filename`, the matching OSV filename. Keep using the source `id` in clips and that source's elapsed seconds; end is exclusive. Camera previews remain separate. Choose chronological observed moments with a readable activity `note`, zero-transition cuts, and no graphics or music. The Mac displays and exports per-file times for manual DJI Studio edits. These additions are manifest metadata, not new edit-plan fields.
