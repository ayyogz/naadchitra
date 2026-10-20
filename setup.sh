#!/usr/bin/env bash
# Naadchitra setup.
#   ./setup.sh             -> check toolchain + fetch Flutter dependencies (enough to build the app)
#   ./setup.sh --regen-ml  -> additionally rebuild the ONNX model and reference embeddings
#                             in a local .venv (only needed if you change model/photos)
set -euo pipefail
cd "$(dirname "$0")"

echo "=== Naadchitra setup ==="

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: flutter is not on your PATH."
  echo "Install it from https://docs.flutter.dev/get-started/install and re-run."
  exit 1
fi

if ! command -v java >/dev/null 2>&1; then
  echo "WARNING: java not found. Install JDK 21 (Android builds need it)."
else
  echo "Java:    $(java -version 2>&1 | head -1)"
fi

echo "Flutter: $(flutter --version 2>/dev/null | head -1)"

echo "[1/2] Getting Flutter dependencies..."
flutter pub get

if [[ "${1:-}" == "--regen-ml" ]]; then
  echo "[2/2] Rebuilding ML assets in .venv ..."
  python3 -m venv .venv
  # shellcheck disable=SC1091
  source .venv/bin/activate
  pip install --upgrade pip
  pip install -r tool/requirements.txt
  python tool/export_model.py --out assets/models/mobilenet_v3_small_fe.onnx --check
  python tool/compute_embeddings.py \
    --model assets/models/mobilenet_v3_small_fe.onnx \
    --refs assets/refs/images \
    --out assets/refs/embeddings.json \
    --check
else
  echo "[2/2] Skipping ML rebuild (model + embeddings are already committed)."
fi

echo
echo "=== Done ==="
echo "Run on a connected phone:  flutter run"
echo "Build release APKs:        flutter build apk --release --split-per-abi"
