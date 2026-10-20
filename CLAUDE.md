# Naadchitra (SIH 2026 · PS SIH26197)

**Start here: read `README.md` fully** — it is the complete developer handover for
this project (toolchain, gotchas, architecture, build steps, current status).
Everything below is a pointer, not a substitute.

## Ground rules

- **The UI is FINAL.** The user said "i love the app ui dont change anything ui wise
  its perfect." Do not change any UI — code changes only behind it.
- **The Saptak note grid plays REAL 1-second segments** (`assets/audio/note_<id>_<swar>.mp3`).
  Never revert to pitch-shifting the full clip.
- App must stay **fully offline**.

## Environment shortcuts (else builds fail)

```bash
export ANDROID_HOME=/home/ayaan/android-sdk
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk      # Java 26 breaks AGP
FLUTTER=/home/ayaan/development/flutter/bin/flutter # not on default PATH
VENV=/home/ayaan/code/SIH/paddleocr_venv            # python for tool/*.py
```

- Not a git repo. Back up APKs to `backup_apps/` after builds.
- Device: Redmi 6 Pro (Android 15), package `com.naadchitra.naadchitra`.
- Debug test image lives at `/data/data/com.naadchitra.naadchitra/cache/test/sitar_test.jpg`
  (write via `adb shell run-as com.naadchitra.naadchitra`).
- `lib/main.dart` has a **temporary debug button** — remove it before the final
  release build (details in `README.md` §9).
- `CN-study/` is the user's unrelated study material — ignore it.