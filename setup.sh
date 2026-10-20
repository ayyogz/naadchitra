#!/bin/bash
set -e
cd "$(dirname "$0")"

VENV=/home/ayaan/code/SIH/paddleocr_venv
FLUTTER=/home/ayaan/development/flutter/bin/flutter
PYTHON=$VENV/bin/python
PIP=$VENV/bin/pip

echo "=== Naadchitra Setup ==="

# Step 1: Install Python dependencies
echo "[1/4] Installing Python deps..."
$PIP install torch torchvision onnx onnxruntime pillow 2>&1 | tail -3

# Step 2: Export MobileNet V3 Small feature extractor to ONNX
echo "[2/4] Exporting MobileNet model to ONNX..."
$PYTHON tool/export_model.py --out assets/models/mobilenet_v3_small_fe.onnx --check

# Step 3: Compute embeddings from reference images (if any exist)
echo "[3/4] Computing reference embeddings..."
if [ -d assets/refs/images/sitar ] || [ -d assets/refs/images/tabla ]; then
    $PYTHON tool/compute_embeddings.py \
        --model assets/models/mobilenet_v3_small_fe.onnx \
        --refs assets/refs/images \
        --out assets/refs/embeddings.json \
        --check
else
    echo "  No reference images found — using placeholder embeddings."
    echo "  Add images to assets/refs/images/<instrument>/ and rerun this script."
fi

# Step 4: Get dependencies
echo "[4/4] Getting Flutter dependencies..."
$FLUTTER pub get

echo ""
echo "=== Setup complete ==="
echo "To build APK: $FLUTTER build apk --debug"
echo "To run on device: $FLUTTER run"
