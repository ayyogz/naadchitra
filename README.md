# Naadchitra 🎵 — Full Developer Handover

> **Read this entire file before touching anything.** It is written so a fresh
> Claude instance (or developer) with **zero prior context** can pick up this
> project from the `SIH2/` folder alone.

**Project status: near demo-complete.** On-device classification works, cultural
cards + full recordings + real per-note segments all ship in the APK. What remains
is device-side verification of the note grid, removing one temporary debug button,
and a final release build. Every build gotcha discovered so far is recorded here.

---

## 1. What this app is

**Naadchitra** — built for **Smart India Hackathon 2026, PS SIH26197** ("showcase
Indian cultural heritage"). A Flutter Android app that:

1. Lets the visitor **photograph a piece of Indian artwork** (gallery or camera).
2. **Identifies the musical instrument** depicted inside it, using **fully
   on-device ML** (no cloud, no internet, no training).
3. Shows a **cultural context card** (Natya Shastra family, region, period).
4. **Plays the instrument's real recorded sound** and lets the visitor **"play" it**
   via a **Saptak** (7-note + octave) grid — each note is a **real 1-second segment**
   cut from the instrument's own recording.

### The Classical 5 instruments (catalogue is fixed)

| id         | name                 | Natya Shastra family        | Region          |
|------------|----------------------|-----------------------------|-----------------|
| `sitar`    | Sitar                | तत (tata) — chordophone     | North India     |
| `veena`    | Saraswati Veena      | तत (tata) — chordophone     | Pan-Indian / S  |
| `tabla`    | Tabla                | अवनद्ध (avanaddha) — membrane | North India   |
| `mridangam`| Mridangam            | अवनद्ध (avanaddha) — membrane | South India   |
| `bansuri`  | Bansuri              | सुषिर (sushira) — aerophone  | Pan-Indian      |

## 2. ⚠️ Hard constraints (do not violate)

- **The UI is FINAL. The user explicitly said "i love the app ui dont change anything
  ui wise its perfect." Do NOT change any UI**: colors, layout, text, spacing,
  cards, the note grid, buttons. Only fix logic/functionality behind it.
- **The note grid must play REAL extracted note segments** — never pitch-shift the
  full clip. This was the user's explicit design decision ("the notes playing
  feature was like it would play the most prominent 1 sec time clip of that specific
  note from the whole audio"). This is already implemented; preserve it.
- **Everything must work fully offline** — model, embeddings, audio all bundled.
- No backend, no accounts, no analytics. Keep it a barebones demo app.
- The repo is **NOT under git** — there is no version control safety net. Be
  careful; back up APKs to `backup_apps/` after any build the user might want.

## 3. How the recognition works (end to end)

```
photo (gallery / camera)
  → Kotlin decodes + downsamples + resizes 224×224 (bilinear)
  → normalize RGB: (x/255 − mean)/std   mean=[0.485,0.456,0.406] std=[0.229,0.224,0.225]
  → NCHW float [1,3,224,224]
  → MobileNet V3 Small feature extractor ONNX
       assets/models/mobilenet_v3_small_fe.onnx   (3.7 MB, output [1,576], L2-normalized in-graph)
  → 576-d unit vector
  → cosine similarity vs each of 5 per-instrument mean embeddings
       assets/refs/embeddings.json
  → winner by raw cosine; gate best_cosine < 0.50 ⇒ "no instrument"
  → displayed confidence = normalized score (cosine−0.50)/0.40 clamped to 0..1
```

Key points:
- Mean embeddings are computed **with the exact same ONNX graph** that runs on the
  phone (`tool/compute_embeddings.py`), so no train/test drift.
- The normalized score exists because real-match cosines sit ~0.65–0.95 while
  class means correlate 0.66–0.86 — a softmax could never show >~35%. The
  normalized scale is the honest, demo-legible presentation.
- The preprocessing contract must match **byte-for-byte** between
  `tool/compute_embeddings.py`, `android/.../MainActivity.kt`, and the Dart side
  does the cosine. If you ever change preprocessing, change all three.

## 4. How note playback works (the "play it" pad)

- The PlayScreen grid has 8 keys: **Sa Re Ga Ma Pa Dha Ni Sa'** (tags
  `sa re ga ma pa dha ni sa2`).
- Tapping a key plays **`assets/audio/note_<instrument>_<tag>.mp3`** — a real
  1-second clip, loudness-faded, cut from the instrument's own recording by
  `tool/extract_notes.py`. There is **no pitch shifting anywhere** in the note grid.
- The "Listen to the Instrument" button plays the full clip
  `assets/audio/<instrument>.mp3` at rate 1.0.
- `tool/extract_notes.py` details:
  - **Melodic** (sitar, veena, bansuri): librosa PYIN pitch → workspace tonic
    estimated by octave-fold alignment to the shuddha scale → tonic octave picked
    by best total column match (`pick_tonic_octave`) → for each of the 8 degrees,
    the 1 s window with best sustained pitch match (`match * voicing prob`), with a
    prominence fallback for degrees the recording never plays. Drums aside, each
    degree yields a distinct, real clip.
  - **Percussion** (tabla, mridangam): no melodic scale — it picks the 8 most
    prominent, pitch-distinct 1 s windows and labels them Sa→Sa' by ascending
    median pitch. The listener still gets 8 real, audibly-different drum clips.
- Output: 40 files (8 × 5) + `assets/audio/notes.json` manifest.

## 5. Project layout

```
SIH2/
├── lib/
│   ├── main.dart        UI (ScanScreen → InstrumentResultCard → PlayScreen). LOCKED.
│   ├── inference.dart   MethodChannel calls + embeddings load + cosine + score.
│   └── models.dart      instrument catalogue (the 5 + Natya Shastra families).
├── android/
│   ├── app/src/main/kotlin/com/naadchitra/naadchitra/MainActivity.kt
│   │                     ONNX Runtime bridge; channel "com.naadchitra/embedder"
│   │                     (initialize / embed / release). Preprocessing lives here.
│   ├── app/build.gradle.kts   onnxruntime-android 1.21.1, kotlinx-coroutines 1.9.0,
│   │                          minSdk 26, release signed with debug key, assets
│   │                          bundled from ../../assets.
│   ├── build.gradle.kts       AGP 9.1.0, Kotlin 2.4.0.
│   └── gradle.properties      pins org.gradle.java.home = java-21. KEEP.
├── assets/
│   ├── models/mobilenet_v3_small_fe.onnx        (committed, do not change)
│   ├── refs/embeddings.json                     (committed, do not change)
│   ├── refs/images/<instrument>/*.jpg           reference photos (23 total)
│   ├── audio/<instrument>.mp3                   full recordings (5)
│   ├── audio/note_<instrument>_<swar>.mp3       40 real note segments
│   ├── audio/notes.json                         extraction manifest
│   └── audio/README.md  ⚠ STALE — still describes the pitch-shift fallback.
├── tool/                 (build-time Python; see §7)
├── backup_apps/          APK snapshots (see §8, §9)
├── pubspec.yaml          assets: refs/embeddings.json, audio/, models/
└── CN-study/             ☢ IGNORE — the user's unrelated Computer Networks study
                          material, not app code. Never build or bundle it.
```

## 6. Environment (machine-specific, verified)

This machine is **CachyOS Linux**. The following are not obvious and will bite you:

| Item | Value / how to use |
|---|---|
| Flutter SDK | `/home/ayaan/development/flutter/bin/flutter` (NOT on the default bash PATH — use the full path, or add it). |
| Android SDK | `/home/ayaan/android-sdk` → `export ANDROID_HOME=/home/ayaan/android-sdk` before builds. Also in `android/local.properties` (`sdk.dir`). |
| Java | System default is **Java 26, which breaks AGP** (jdkImage/jlink transform). Java 21 is pinned in `android/gradle.properties`; still `export JAVA_HOME=/usr/lib/jvm/java-21-openjdk` when running Gradle. |
| Python venv | `/home/ayaan/code/SIH/paddleocr_venv` → `$VENV/bin/python`. Has torch, torchvision, onnxruntime 1.30, librosa 1.0.0, soundfile, scipy, numba, pillow. **All tool/ scripts must run under this venv.** |
| ffmpeg | Installed on PATH (used by `tool/extract_notes.py`, and for the raw-track decode). |
| Target device | **Redmi 6 Pro, LineageOS 22.3 (Android 15)**. Package `com.naadchitra.naadchitra`. |
| VCS | **None.** This project is not a git repository. |

Flags that make builds pass (combine all three):
```bash
export ANDROID_HOME=/home/ayaan/android-sdk
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
FLUTTER=/home/ayaan/development/flutter/bin/flutter
```

## 7. Tooling (build-time scripts — all already run, results committed)

| Script | Purpose | Status |
|---|---|---|
| `tool/export_model.py` | Export MobileNet V3 Small → ONNX (`--out`, `--check`). Needs network on first run (ImageNet weights). | ✅ Model committed. Re-export only if you change the extractor. |
| `tool/fetch_refs.py` | Download reference photos from Wikimedia Commons (`--limit`, `--output`). | ✅ 23 images present. |
| `tool/compute_embeddings.py` | Embed every ref with the phone's exact ONNX → `embeddings.json` (`--check` sanity). Top-1 = 23/23. | ✅ Committed. |
| `tool/extract_notes.py` | Cut the 40 real 1 s note segments from full recordings (see §4). | ✅ Run; outputs committed. |
| `tool/_raw/` | **Raw source recordings** used to generate the note segments (`*_full.ogg`/`.webm`). Keep until all note files are regenerated; otherwise deletable to save space. | Temporary. |

To regenerate note segments (only if you get new audio):
```bash
cd /home/ayaan/code/SIH2
/home/ayaan/code/SIH/paddleocr_venv/bin/python tool/extract_notes.py
```
It reads `tool/_raw/*`, writes `assets/audio/note_*.mp3` + `notes.json`. Requires
`ffmpeg` on PATH.

## 8. Building & installing

```bash
cd /home/ayaan/code/SIH2
export ANDROID_HOME=/home/ayaan/android-sdk
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk

# Debug (fast, includes everything, ~238 MB):
/home/ayaan/development/flutter/bin/flutter build apk --debug

# Release for a phone — split-per-abi:
/home/ayaan/development/flutter/bin/flutter build apk --release --split-per-abi
# → app-arm64-v8a-release.apk (~39–53 MB) is THE ONE for the Redmi 6 Pro.
```

Outputs land in `build/app/outputs/flutter-apk/`. The release APK is signed with
**the debug key** (set in `android/app/build.gradle.kts`) — fine for a demo.

Install & drive over USB:
```bash
ADB=/home/ayaan/android-sdk/platform-tools/adb
$ADB devices                          # phone must be listed (USB debugging on)
$ADB install -r build/app/outputs/flutter-apk/app-debug.apk
$ADB shell input tap <x> <y>          # tap UI without touching the phone
$ADB logcat | grep -i naadchitra      # watch DG/dart logs
```

**Debug test image** (used by the temporary Debug button in `main.dart`): the app
reads `/data/data/com.naadchitra.naadchitra/cache/test/sitar_test.jpg`. To replace it:
```bash
$ADB push <local.jpg> /data/local/tmp/img.jpg
$ADB shell run-as com.naadchitra.naadchitra cp /data/local/tmp/img.jpg \
    /data/data/com.naadchitra.naadchitra/cache/test/sitar_test.jpg
```
⚠ The image currently pushed there is **actually a tabla photo**, so pressing the
Debug button classifies Tabla (~72%) even though its label says "Test Sitar".

## 9. Current status & known issues (as of 2026-09-14)

**Working / verified:**
- Model init, embedding, cosine matching all run ON-DEVICE. Classifying the
  (tabla) test image correctly returned **Tabla 72%**.
- Navigation Scan → result card → PlayScreen works; the 8-note grid renders.

**Not yet verified:**
- **Per-note audio distinction on the device.** The note-grid fix (real segments)
  is built and installed in the debug APK; tapping Sa/Re/Ga was tested but the
  sound couldn't be confirmed remotely. **Next steps: reconnect the phone, install
  the latest APK, tap all 8 notes while listening / watching `logcat` for
  asset-not-found errors, confirm each sounds different.**
- Classification against *correct* images for all 5 instruments (test with a real
  sitar photo, veena, mridangam, bansuri).

**To-do before the final demo build:**
1. ✅ Back up current APK → `backup_apps/` (done for debug; release snapshot pending).
2. Remove the temporary **debug button** in `lib/main.dart`
   (label "Debug: Test Sitar Image", around line ~174, plus `_debugTest()` and the
   unused `_debugTest`/directory constants) — UI doc is otherwise unchanged.
3. Fix the stale text in `assets/audio/README.md` (it still says the pad
   pitch-shifts; it now plays real 1 s segments).
4. Final release build (`--split-per-abi`), back it up, `adb install` and demo.
5. Optionally delete `tool/_raw/` (raw source tracks) and the stale
   `build/app/outputs/flutter-apk/app-release.apk` / old split releases are replaced
   by the fresh ones in §8.

**APK backups in `backup_apps/` (dated 2026-09-14):**
| File | Notes |
|---|---|
| `naadchitra-debug-2026-09-14.apk` | Current debug build (238 MB), includes the real-note-segment fix. The tested state. |
| `naadchitra-release-arm64-v8a-2026-09-14.apk` (52 MB) | **Fresh release, use this for the demo phone.** Contains the current code + all note segments. |
| `naadchitra-release-armeabi-v7a-2026-09-14.apk` / `-x86_64-…` | Fresh release for older 32-bit ARM / x86 emulators. |

## 10. MethodChannel contract (Kotlin ⇄ Dart)

Channel **`com.naadchitra/embedder`**:
- `initialize()` → `{success: bool, outputs: [names]}`
- `embed({imagePath})` → `{embedding: [576 floats]}`
- `release()` → `true`

Preprocessing in `MainActivity.kt` must match §3 exactly. Model loaded from
`assets/models/mobilenet_v3_small_fe.onnx`. Dart cosine + scoring in
`lib/inference.dart` (`_gate=0.50`, `_span=0.40`).

## 11. Demo script (for the SIH pitch)

1. Open app → screen says "Ready — pick or photograph artwork".
2. **Gallery** (fast, reliable for rehearsals) → pick a photo of an instrument.
3. Watch the scan → instrument card: name, family, region, period, confidence bar,
   per-instrument score bars.
4. **Play This Instrument** → **Listen to the Instrument** (full real clip).
5. Tap the **Saptak grid** up and down — each key is a different, real note from
   the recording.
6. Mention: fully offline, on-device model, five instruments, Natya Shastra families.