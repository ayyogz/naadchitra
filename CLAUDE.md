# Naadchitra (SIH 2026, PS SIH26197)

Start with `README.md`, then `docs/DEVELOPER_NOTES.md` for architecture and the Kotlin/Dart contract.

## Ground rules

- **The UI is final.** Only change logic behind it.
- **The Saptak note grid plays real 1-second segments** (`assets/audio/note_<id>_<swar>.mp3`). Never pitch-shift the full clip.
- The app stays **fully offline**.
- Preprocessing must stay identical in `tool/compute_embeddings.py`, `MainActivity.kt` and `lib/inference.dart`.

## Environment

```bash
export JAVA_HOME=/path/to/jdk-21      # JDK 26 breaks the Android Gradle Plugin
export ANDROID_HOME=/path/to/android-sdk
flutter build apk --release --split-per-abi
```

Python tooling lives in `tool/` and runs from the `.venv` created by `./setup.sh --regen-ml`.

## Notes

- `lib/main.dart` still has a temporary debug button. Remove it before the final release build.
- The project is under git. Do not commit APKs, keystores, `.env` or `android/local.properties`. Publish APKs as GitHub Releases.
