# Advance Audio Editor

A 100% TalkBack-accessible, offline Naat / Tilawat recording studio for blind users.
Developer: **Hafiz Qasim**. English-only voice prompts. No ads. No data collection.

## Build steps

```bash
flutter create . --project-name advance_audio_editor --platforms android   # regenerates missing tooling
flutter pub get
flutter build apk --release        # or: flutter build appbundle
```

Requirements: Flutter 3.22+, Android SDK 35, Java 17. minSdk 28 (Android 9),
targetSdk 35 (Android 15/16 ready).

## What is real in this code

- **Recording**: `record` package, 48 kHz stereo WAV, `echoCancel: false`,
  `autoGain: false`, `noiseSuppress: true` (real-time noise gate). One button
  does Start (after a spoken 3-2-1 countdown) / Pause / Resume.
- **Import**: `file_picker` (SAF — works from Internal Storage, SD Card,
  WhatsApp, Downloads, Google Drive, File Manager). FFmpeg converts any
  decodable format to a 48 kHz stereo working WAV. Undecodable files produce
  the spoken message "This file format is not supported".
- **8 Voices Chorus**: real FFmpeg filter graph — 8 layers with 0–126 ms
  delays, ±6-cent detune, 0.55 volume mix; original pitch/tempo preserved.
- **Merge**: concat demuxer, one track, no gap.
- **Split**: segments with silence removal (pieces have no internal silence).
- **Save**: speaks a preview (total time vs after-silence time), then removes
  silence (−38 dB / 350 ms) and leading breath/cough, then exports to
  MP3 / WAV / M4A / AAC / OGG / OPUS / FLAC / AMR / 3GP / AIFF.
- **Course**: 19 lessons, 3 levels, spoken walkthrough, 1-minute practice
  timer, record-and-compare, and an honest "Check My Voice" that measures
  average and peak loudness on-device (ffmpeg volumedetect) and speaks
  feedback. Direction lessons (6–14) include real stereo demos (hard pan,
  moving pan, space, brightness/depth) applied to your own recording.
- **Accessibility**: every control has a `Semantics` label, minimum 70 dp
  height, spoken confirmations after every action, two-step Delete
  confirmation, Dark / Light / High Contrast themes.
- **Background recording**: foreground service with
  `foregroundServiceType="microphone"`, battery-optimization exemption
  permission, plus in-app OEM guidance (Samsung / Xiaomi / Vivo / Oppo...).
- **Permissions**: `READ_EXTERNAL_STORAGE` limited to maxSdk 32;
  `READ_MEDIA_AUDIO` for Android 13+; microphone runtime request.

## Known limits (honest)

- **MIDI / MID files**: MIDI is event data, not audio — it cannot be decoded
  to sound by FFmpeg without a soundfont. Import will report "not supported".
- **True "up / down" 3D**: stereo speakers cannot place sound vertically.
  Lessons 10–11 use tone-shaping (brighter = higher, deeper = lower) as an
  honest approximation.
- **The chorus is a real studio effect**, not eight separate singers;
  identity of pitch is preserved, harmony layers are delayed/detuned copies.
- **"Teacher example" audio**: there are no recorded teacher files in the
  app; the example is the app's English voice reading the exercise.
- **Check My Voice** measures loudness and stability, not musical accuracy.
- ffmpeg_kit_flutter was retired in Jan 2025; this project pins the
  maintained fork `ffmpeg_kit_flutter_new`.
- The project has been code-reviewed but **not compiled or tested on
  devices** in this environment — run `flutter analyze` and a build on your
  machine before release.
