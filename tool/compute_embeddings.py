#!/usr/bin/env python3
"""Precompute per-instrument mean embeddings for the Naadchitra demo.

Reads reference photos from assets/refs/images/<instrument>/*.{jpg,jpeg,png},
embeds each with the SAME onnx feature model that runs on-device, and writes
assets/refs/embeddings.json.

The preprocessing here must stay byte-for-byte consistent with the Kotlin side
(ImagePreprocess.kt): 224x224 bilinear resize + ImageNet normalization + NCHW.
The model graph already L2-normalizes, so each row in the JSON is a unit vector
and the on-device cosine distance is a plain dot product.

Usage:
    python tool/compute_embeddings.py \
        --model assets/models/mobilenet_v3_small_fe.onnx \
        --refs assets/refs/images \
        --out  assets/refs/embeddings.json

Check mode (sanity: every reference image close to its instrument mean):
    python tool/compute_embeddings.py --model ... --refs ... --check
"""

import argparse
import json
import pathlib
import sys

INSTRUMENTS = ["sitar", "tabla", "veena", "mridangam", "bansuri"]
MEAN = (0.485, 0.456, 0.406)
STD = (0.229, 0.224, 0.225)
SIZE = 224


def preprocess(path: pathlib.Path) -> "object":  # np.ndarray [1,3,224,224] (we import lazily)
    from PIL import Image
    import numpy as np

    img = Image.open(path).convert("RGB")          # drop alpha
    img = img.resize((SIZE, SIZE), Image.BILINEAR)  # match ImagePreprocess.kt
    x = np.asarray(img, dtype=np.float32) / 255.0
    mean = np.array(MEAN, dtype=np.float32)
    std = np.array(STD, dtype=np.float32)
    x = (x - mean) / std
    return x.transpose(2, 0, 1)[None]               # (1,3,H,W)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--model", default="assets/models/mobilenet_v3_small_fe.onnx")
    ap.add_argument("--refs", default="assets/refs/images")
    ap.add_argument("--out", default="assets/refs/embeddings.json")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    try:
        import numpy as np
        import onnxruntime as ort
    except ImportError as e:
        print(f"[embeds] missing dependency: {e}", file=sys.stderr)
        print("[embeds] need: pip install onnxruntime pillow numpy", file=sys.stderr)
        return 1

    model = pathlib.Path(args.model)
    refs_root = pathlib.Path(args.refs)
    if not model.exists():
        print(f"[embeds] model not found: {model} (run tool/export_model.py first)", file=sys.stderr)
        return 1

    print(f"[embeds] loading model {model} ...")
    sess = ort.InferenceSession(str(model), providers=["CPUExecutionProvider"])

    def embed(p: pathlib.Path):
        (e,) = sess.run(["features"], {"image": preprocess(p)})
        return e[0]  # (1, 576) -> (576,); L2-normalized by the graph

    out = {}
    missing = []
    for key in INSTRUMENTS:
        d = refs_root / key
        imgs = sorted(p for p in d.glob("*") if p.suffix.lower() in (".jpg", ".jpeg", ".png"))
        if not imgs:
            missing.append(str(d))
            print(f"[embeds] WARNING no reference images for '{key}' in {d} -- skipping")
            continue
        embs = [embed(p) for p in imgs]
        mean = np.mean(np.stack(embs), axis=0)
        mean = mean / np.linalg.norm(mean)
        out[key] = {
            "images": [p.name for p in imgs],
            "embedding": [round(float(v), 6) for v in mean.tolist()],
        }
        print(f"[embeds] {key:10s} ({len(imgs)} imgs) dim={len(out[key]['embedding'])}")

        if args.check:
            cos = [(float(mean @ e), p.name) for e, p in zip(embs, imgs)]
            print(f"[embeds]   check cos(mean,img): {', '.join(f'{c:.3f} {n}' for c, n in sorted(cos, reverse=True))}")

    if out:
        out_path = pathlib.Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(
            json.dumps(
                {
                    "model": model.name,
                    "dim": 576,
                    "preprocess": "bilinear_224_imagenet",
                    "instruments": out,
                },
                indent=1,
            )
        )
        print(f"[embeds] wrote {out_path} with {len(out)} instruments")

    if missing:
        print("[embeds] NOTE: add reference photos to those dirs (3+ good photos each), then rerun.", file=sys.stderr)
        return 1 if not out else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())