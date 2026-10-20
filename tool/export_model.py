#!/usr/bin/env python3
"""Export MobileNet V3 Small feature extractor -> ONNX for the Naadchitra demo.

The exported graph:
  input    : "image"    float32 [1,3,224,224] NCHW  -- RGB, already resized to
             224x224 (bilinear) and normalized with ImageNet stats
             ((x/255 - mean)/std), mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225]
  output   : "features" float32 [1,576]  -- L2-normalized embedding vector

L2-normalization lives INSIDE the graph, so the only contract shared with the
on-device Kotlin code is the preprocessing above; both get a unit vector back.

Usage:
    python tool/export_model.py --out assets/models/mobilenet_v3_small_fe.onnx

Prerequisites (best in the paddleocr venv): torch, torchvision, onnx, onnxruntime.
The first run downloads the ImageNet weights (needs network).
"""

import argparse
import sys

import pathlib


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default="assets/models/mobilenet_v3_small_fe.onnx")
    ap.add_argument("--check", action="store_true", help="verify the exported graph with onnxruntime")
    args = ap.parse_args()

    try:
        import torch
        import torch.nn as nn
        import torch.nn.functional as F
        from torchvision.models import mobilenet_v3_small, MobileNet_V3_Small_Weights
    except ImportError as e:
        print(f"[export] missing dependency: {e}", file=sys.stderr)
        print("[export] install into the venv: pip install torch torchvision onnx onnxruntime", file=sys.stderr)
        return 1

    print("[export] building MobileNet V3 Small feature extractor ...")
    backbone = mobilenet_v3_small(weights=MobileNet_V3_Small_Weights.IMAGENET1K_V1)

    # Register the backbone as a submodule (not a closure capture) so the ONNX
    # tracer binds its weights as graph parameters instead of treating them as
    # free tensors (which fails with "Cannot insert a Tensor that requires grad").
    class FeatureExtractor(nn.Module):
        def __init__(self, backbone: nn.Module) -> None:
            super().__init__()
            self.backbone = backbone

        def forward(self, x):
            x = self.backbone.features(x)   # (1, 576, 7, 7)
            x = x.mean(dim=(2, 3))          # global average pool -> (1, 576)
            return F.normalize(x, p=2, dim=1)  # L2 normalize

    fe = FeatureExtractor(backbone)
    fe.eval()

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    dummy = torch.randn(1, 3, 224, 224)
    print(f"[export] tracing and exporting to {out} ...")
    with torch.no_grad():
        torch.onnx.export(
            fe,
            dummy,
            str(out),
            input_names=["image"],
            output_names=["features"],
            opset_version=12,
            do_constant_folding=True,
            dynamic_axes={"image": {0: "batch"}, "features": {0: "batch"}},
            # dynamo=False: torch 2.14's default dynamo exporter fails on
            # MobileNetV3's fused in-place activations ("Constant lifted_tensor_1
            # is mutated"); the legacy TorchScript tracer handles this graph fine.
            dynamo=False,
        )
    size_mb = out.stat().st_size / 1e6
    print(f"[export] wrote {out} ({size_mb:.1f} MB)")

    if args.check:
        try:
            import numpy as np
            import onnxruntime as ort
        except ImportError as e:
            print(f"[export] cannot verify (no numpy/onnxruntime): {e}", file=sys.stderr)
            return 0
        sess = ort.InferenceSession(str(out), providers=["CPUExecutionProvider"])
        inp = np.random.randn(1, 3, 224, 224).astype(np.float32)
        (emb,) = sess.run(["features"], {"image": inp})
        norm = np.linalg.norm(emb)
        print(f"[export] check: output shape={emb.shape} L2 norm={norm:.4f} (expect ~1.0)")
        assert emb.shape == (1, 576), emb.shape
        assert abs(norm - 1.0) < 1e-3, norm
        print("[export] OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())