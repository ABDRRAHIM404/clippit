# Clippit — AI-Powered YouTube Highlight Clipper

A free, personal-use Android app that takes a YouTube video (or a local video file), uses Gemini AI to find the best highlight-worthy moments, and exports ready-to-share clips — with captions, vertical cropping, and speaker tracking. Built to run entirely on free tools and free API tiers.

---

## What This App Does

1. Accepts either a **YouTube URL** or a **local video file** as input
2. Sends the video to **Gemini** for analysis — no manual download needed for the YouTube-URL path, since Gemini can read directly from the link
3. Gemini returns a list of suggested clips: timestamps, titles, and a reasoning for why each moment is highlight-worthy, scored for "virality" potential
4. User picks (or fine-tunes) the clip(s) they want
5. App downloads only the needed segment, cuts it, optionally crops to vertical (9:16) with speaker tracking, and burns in styled captions
6. Finished clip is saved to the device or shared directly

---

## Processing Pipeline (Two-Pass Gemini Approach)

1. **Pass 1 — Highlight detection (full video):** Before calling Gemini, check Hive cache by video URL/file hash — if already analyzed, skip straight to results. Otherwise, Gemini analyzes the full YouTube URL or local file, returns rough timestamps, titles, and reasoning for the best moments, and the result is cached. This pass doesn't need word-level transcript accuracy — just good moment detection.
2. **User selects a clip** from the suggestions
3. **Cut:** `ffmpeg` trims the clip from the source video
4. **Pass 2 — Caption transcription (clip only):** Gemini transcribes *just the cut clip*, not the full video. Timestamps come back clip-relative (starting at 0:00), which avoids offset math and keeps the transcript focused and accurate
5. **Caption generation:** transcript converted into styled `.srt`/`.ass`, with keyword emphasis if enabled
6. **Burn-in:** `ffmpeg` overlays captions onto the final clip
7. **Export:** crop, watermark, and save/share

This two-pass design avoids over-processing parts of the source video that never make it into a clip, and keeps caption sync simple since timestamps are always relative to the clip itself.

---

## Clip Length

Target range: **60–75 seconds** per clip. This is enforced at the prompt level during Pass 1 (highlight detection) — Gemini is instructed to suggest moments that naturally fit this window rather than arbitrary-length highlights that need manual trimming afterward. This range comfortably fits current platform limits (YouTube Shorts, TikTok, and Reels all support up to 3 minutes).

---

## Core Features

| Feature | Status | Notes |
|---|---|---|
| YouTube URL input | ✅ | Via `yt-dlp` (Android wrapper) |
| Local file input | ✅ | Direct upload to Gemini Files API |
| AI highlight detection | ✅ | Gemini, prompt-driven, structured JSON output |
| Virality scoring | ✅ | Same Gemini call, no extra cost |
| Clip trimming | ✅ | `ffmpeg` via FFmpegKit, fast-copy when possible |
| Vertical (9:16) crop | ✅ | `ffmpeg` re-encode |
| Speaker/face tracking crop | ✅ | Google ML Kit, on-device, free |
| Captions (auto-generated) | ✅ | Clip is cut first, then Gemini transcribes just that segment (clip-relative timestamps, more accurate, less wasted analysis) |
| Keyword highlight in captions | ✅ | Prompt-driven emphasis detection |
| Multi-language captions | ✅ | Gemini translation |
| Watermark/branding overlay | ✅ | Simple `ffmpeg` overlay |
| Batch processing | ✅ | Pipeline looped over multiple sources |
| Platform export presets (TikTok/Shorts/Reels) | ✅ | Same 9:16 ratio across platforms; presets adjust resolution/bitrate/codec per platform, one-tap export |
| Gemini result caching | ✅ | Pass 1 highlight results cached in Hive by video URL/file hash — reopening a previously analyzed video costs zero extra API calls |
| Clip thumbnail generation | ✅ | `ffmpeg` frame grab per saved clip, stored alongside Hive history entry |
| B-roll insertion | ❌ Skipped | Not worth the complexity for personal use |
| Analytics on clip performance | ❌ Skipped | Out of scope — no external platform tracking |

---

## Tech Stack

- **Framework:** Flutter (cross-platform, strong FFmpeg/ML Kit support, fast UI development)
- **AI:** Gemini API only — handles video understanding, transcript generation, highlight detection, scoring, and translation. No additional LLM providers needed (Grok evaluated and ruled out — no genuine free tier).
- **Video download:** `youtubedl-android` (Android-native `yt-dlp` wrapper)
- **Video processing:** `FFmpegKit` (trimming, cropping, caption burn-in, watermarking)
- **Face/speaker tracking:** Google ML Kit (on-device, free, no API key required)
- **Local storage:** Hive (clip history, metadata, saved Gemini highlight results) + `shared_preferences` (user settings) — fully on-device, no account, no sync
- **Hosting/build:** None needed — fully on-device app, no backend server

---

## Why Gemini Only (No Grok/NVIDIA)

Every task in the pipeline — video analysis, transcript generation, highlight scoring, caption text, translation — is a job Gemini already handles natively via its video-understanding capability. Adding a second LLM provider would only add API key management overhead and code complexity with no functional gain. The one non-LLM task (face/speaker tracking) is better solved by an on-device vision tool (ML Kit) than any cloud API, since it's free, fast, and doesn't depend on network calls.

---

## Backend & Database

**No backend server.** The app talks directly to Gemini's API from the phone, and all video processing (download, ffmpeg, ML Kit) happens on-device. There's no server to host, maintain, or pay for.

**Local database only.** Since this is single-device, personal use (no cross-device sync needed):
- **Hive** stores clip history — source video, generated clips, thumbnails, Gemini's highlight suggestions (so re-opening the app doesn't lose prior analysis)
- **`shared_preferences`** stores simple user settings (default crop style, caption style, export quality)

If cross-device sync is ever wanted later, a free-tier backend like Firebase could be added — but it's intentionally out of scope for now to keep things simple and fully free/offline-capable.

---

## Project Structure

```
clippit/
├── lib/
│   ├── main.dart
│   ├── theme/
│   │   ├── app_theme.dart          # ThemeData, type scale, spacing
│   │   └── app_colors.dart         # custom palette (not default Material)
│   ├── screens/
│   │   ├── home_screen.dart        # URL input / file picker entry point
│   │   ├── processing_screen.dart  # download/analysis progress
│   │   ├── highlights_screen.dart  # Gemini's suggested clips, card list
│   │   ├── edit_screen.dart        # timestamp fine-tuning, crop toggle
│   │   └── export_screen.dart      # final render + save/share
│   ├── services/
│   │   ├── youtube_service.dart    # download, video info, URL validation
│   │   ├── gemini_service.dart     # analysis, transcript, highlight parsing
│   │   ├── ffmpeg_service.dart     # trim, crop, export, thumbnail extraction
│   │   ├── export_service.dart     # platform presets (TikTok/Shorts/Reels)
│   │   ├── caption_service.dart    # subtitle generation, styling, burn-in
│   │   ├── face_tracking_service.dart  # ML Kit speaker tracking
│   │   ├── storage_service.dart    # save, cleanup temp files, share
│   │   └── db_service.dart         # Hive local database (clip history + Gemini result cache)
│   ├── controllers/
│   │   └── clipper_controller.dart # pipeline state machine
│   ├── models/
│   │   ├── clip_suggestion.dart    # timestamps, title, reason, score
│   │   ├── video_source.dart       # type (url/local), path, duration
│   │   └── clip_history_entry.dart # Hive object: clip record, thumbnail path, cached Gemini results
│   └── widgets/
│       ├── clip_card.dart
│       ├── timeline_scrubber.dart
│       ├── progress_indicator.dart
│       └── primary_button.dart
├── android/
├── .github/workflows/build.yml     # CI build pipeline (see below)
└── pubspec.yaml
```

---

## Design Direction

- **Dark-first theme** — fits the video/content-tool category (CapCut, Premiere, etc. default dark), makes thumbnails and previews stand out
- **One strong accent color** on a near-black background — used sparingly (buttons, active states, scrubber handle), not the default Material blue/teal
- **Card-based highlight list** — each suggested clip shown with thumbnail, duration badge, and Gemini's reasoning, generously spaced
- **Bold, slightly oversized titles**, more restrained body text — confident, modern feel
- **Subtle transitions** between pipeline stages so waiting doesn't feel static
- Custom `ThemeData` and defined spacing constants throughout — no ad-hoc default styling

---

## Development Workflow

Given the dev hardware (HP EliteBook 8440p, i7, 4GB RAM, Linux Mint) and target device (Poco X7 Pro, 24GB RAM):

1. **Write code** in VS Code on the laptop (lightweight, no issue)
2. **Push to GitHub**
3. **GitHub Actions builds the APK** — offloads the RAM-heavy Gradle build off the laptop entirely, using free CI build minutes
4. **Download the built APK** from the Actions run artifacts
5. **Install on the Poco X7 Pro** (enable "install from unknown sources" once) and test
6. **Iterate** — fix, push, auto-rebuild, reinstall

This avoids ever running a full Android/Gradle build locally on the constrained laptop.

---

## Hardware & Resource Notes

- **Sequential pipeline execution** (download → analyze → cut → export, one step at a time, nothing parallel) keeps RAM usage low and predictable — relevant for any lower-spec testing, though the target phone has ample headroom (24GB RAM)
- **`-c copy` used wherever possible** in `ffmpeg` (pure trimming) to avoid unnecessary re-encoding; full re-encode only happens for crop, caption burn-in, and watermarking
- **Temp file cleanup** after each export to avoid storage buildup from full downloaded source videos

---

## Known Limitations / Things to Keep in Mind

- Downloading YouTube videos technically falls into a ToS gray area — acceptable risk for personal use, not intended for redistribution or public deployment
- `yt-dlp` occasionally needs updates when YouTube changes its backend — update the dependency if downloads start failing
- Gemini's free tier has request rate limits (per-minute/per-day caps) — fine for personal/occasional use, may need pacing if batch-processing many videos in one session
- "Virality scoring" reflects Gemini's judgment of narrative/emotional strength, not a guarantee of actual performance — treat it as a strong starting point, not gospel
- This is a personal-use tool, not built for Play Store distribution or multi-user scale

---

## Out of Scope (Intentionally)

- B-roll auto-insertion (needs stock footage API/library — disproportionate effort)
- Post-performance analytics (needs external platform data tracking)
- Multi-LLM redundancy (Gemini alone covers every AI task needed)
