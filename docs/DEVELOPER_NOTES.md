# Naadchitra: Developer Notes

Deeper technical notes for anyone changing the code. For install and build instructions see the top-level [README](../README.md).

## Design rules

- **The UI is final.** Change logic behind it, not layout, colours or text.
- **The note pad plays real 1-second segments** (`assets/audio/note_<instrument>_<swar>.mp3`). Never pitch-shift the full clip.
- **Everything works offline.** Model, embeddings and audio are all bundled. No backend, accounts or analytics.

## Recognition pipeline

```
photo (gallery / camera)
  -> Kotlin decodes, downsamples, resizes to 224x224 (bilinear)
  -> normalise RGB: (x/255 - mean) / std
       mean = [0.485, 0.456, 0.406]   std = [0.229, 0.224, 0.225]
  -> NCHW float [1, 3, 224, 224]
  -> MobileNetV3-Small feature extractor (ONNX)
       assets/models/mobilenet_v3_small_fe.onnx   (3.7 MB, output [1, 576], L2-normalised in-graph)
  -> cosine similarity against 5 per-instrument mean embeddings (assets/refs/embeddings.json)
  -> winner by raw cosine; best cosine < 0.50 means "no instrument"
  -> displayed confidence = clamp((cosine - 0.50) / 0.40, 0, 1)
```

- Mean embeddings are computed with the **same ONNX graph** that runs on the phone, so there is no train/test drift.
- The rescaled score exists because real matches have cosines around 0.65 to 0.95 while the class means correlate at 0.66 to 0.86. A softmax could never show more than about 35%.
- **Preprocessing must match** in `tool/compute_embeddings.py`, `android/.../MainActivity.kt` and the Dart scoring in `lib/inference.dart` (`_gate = 0.50`, `_span = 0.40`). Change one, change all three.

## Note pad

- 8 keys: **Sa Re Ga Ma Pa Dha Ni Sa'** (tags `sa re ga ma pa dha ni sa2`).
- A key plays `assets/audio/note_<instrument>_<tag>.mp3`. "Listen to the Instrument" plays `assets/audio/<instrument>.mp3`.
- `tool/extract_notes.py` generates the 40 clips plus `assets/audio/notes.json`:
  - **Melodic** (sitar, veena, bansuri): librosa PYIN pitch tracking, tonic estimated by octave-fold alignment to the shuddha scale, then for each degree the 1 s window with the best sustained pitch match, with a prominence fallback.
  - **Percussion** (tabla, mridangam): no scale, so it picks the 8 most prominent, pitch-distinct windows and labels them Sa to Sa' by ascending median pitch.
- Regenerate (needs `ffmpeg`, your own recordings in `tool/_raw/`, and the `--regen-ml` virtualenv):
  ```bash
  source .venv/bin/activate
  python tool/extract_notes.py
  ```

## Kotlin and Dart bridge

Channel `com.naadchitra/embedder`:

| Method | Arguments | Returns |
|---|---|---|
| `initialize` | none | `{success: bool, outputs: [names]}` |
| `embed` | `{imagePath}` | `{embedding: [576 floats]}` |
| `release` | none | `true` |

## Build configuration

| Item | Value |
|---|---|
| Android Gradle Plugin | 9.1.0 |
| Kotlin | 2.4.0 |
| ONNX Runtime | `onnxruntime-android` 1.21.1 |
| minSdk | 26 (Android 8.0) |
| JDK | 21. Newer JDKs (for example 26) break AGP's `jlink` transform |
| Release signing | debug key (fine for a demo) |

If you use a different JDK path, set `JAVA_HOME` in your shell. Do not hard-code `org.gradle.java.home` in `android/gradle.properties`, because it breaks other machines and CI.

## Scripts in `tool/`

| Script | Purpose |
|---|---|
| `export_model.py` | Export MobileNetV3-Small to ONNX (needs network on first run for the ImageNet weights) |
| `fetch_refs.py` | Download reference photos from Wikimedia Commons |
| `compute_embeddings.py` | Embed every reference photo with the phone's ONNX model and write `embeddings.json` (top-1 accuracy on the 23 refs: 23/23) |
| `extract_notes.py` | Cut the 40 note clips from the full recordings |
| `_raw/` | Source recordings used to cut the notes. Delete if you do not need to regenerate them |

## Testing on a device

```bash
adb devices
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
adb logcat | grep -i naadchitra
```

Tested on a Redmi 6 Pro running LineageOS 22.3 (Android 15).

## Status and to-do

- Verified on device: model init, embedding, cosine matching, navigation, 8-key note grid renders (a tabla test image correctly returned Tabla at 72%).
- Still to verify: that every one of the 8 notes sounds different on the device, and classification of correct images for all 5 instruments.
- Before the final build: remove the temporary debug button in `lib/main.dart` (label "Debug: Test Sitar Image", `_debugTest()` and its constants).
