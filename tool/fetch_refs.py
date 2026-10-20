#!/usr/bin/env python3
"""Fetch public-domain reference photos for the 5 instruments from Wikimedia Commons.

Writes into assets/refs/images/<instrument>/ so compute_embeddings.py can build
real embeddings (replaces the placeholder ones). Re-run any time you want fresh
reference images; existing files are kept and new ones added up to --limit each.

Usage:
    python tool/fetch_refs.py [--limit 5] [--output assets/refs/images]
"""

import argparse
import json
import pathlib
import sys
import urllib.parse
import urllib.request

API = "https://commons.wikimedia.org/w/api.php"
UA = "Naadchitra/1.0 (SIH2026 demo; contact: demo@example.in) python-urllib"

QUERIES = {
    "sitar": "sitar instrument",
    "tabla": "tabla drums",
    "veena": "Saraswati veena",
    "mridangam": "mridangam",
    "bansuri": "bansuri flute",
}

SUFFIXES = {".jpg", ".jpeg", ".png"}


def api(params: dict) -> dict:
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def fetch(key: str, limit: int, out_root: pathlib.Path) -> list[str]:
    params = {
        "action": "query",
        "generator": "search",
        "gsrsearch": QUERIES[key],
        "gsrnamespace": "6",  # File namespace
        "gsrlimit": str(min(limit * 3, 20)),
        "prop": "imageinfo",
        "iiprop": "url|mime|size",
        "iiurlwidth": "800",
        "format": "json",
    }
    data = api(params)
    pages = (data.get("query") or {}).get("pages") or {}
    dest = out_root / key
    dest.mkdir(parents=True, exist_ok=True)
    existing = {p.stem for p in dest.glob("*") if p.suffix in SUFFIXES}
    saved = []

    for p in sorted(pages.values(), key=lambda x: x.get("index", 999)):
        if len(saved) >= limit:
            break
        info = (p.get("imageinfo") or [{}])[0]
        mime = info.get("mime", "")
        url = info.get("thumburl") or info.get("url")
        if mime not in ("image/jpeg", "image/png") or not url:
            continue
        stem = p["title"].rsplit(":", 1)[-1].rsplit(".", 1)[0]
        stem = "".join(c if c.isalnum() or c in "-_" else "_" for c in stem)[:60]
        if stem in existing:
            continue
        ext = ".jpg" if mime == "image/jpeg" else ".png"
        fname = dest / f"{stem}{ext}"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                data = r.read()
            if data and len(data) > 20_000:  # sanity: non-trivial image
                fname.write_bytes(data)
                saved.append(fname.name)
                existing.add(stem)
                print(f"[fetch] {key}: {fname.name}")
        except Exception as e:
            print(f"[fetch] {key}: skip {stem}: {e}", file=sys.stderr)
    return saved


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--limit", type=int, default=5)
    ap.add_argument("--output", default="assets/refs/images")
    args = ap.parse_args()

    out_root = pathlib.Path(args.output)
    total = 0
    for key in QUERIES:
        got = fetch(key, args.limit, out_root)
        total += len(got)
        print(f"[fetch] {key}: {len(got)} new images")
    print(f"[fetch] done, {total} new files in {out_root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())