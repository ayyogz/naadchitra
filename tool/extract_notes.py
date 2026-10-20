#!/usr/bin/env python
"""Extract the most prominent 1-second clip of each saptak note from each
instrument recording, so the PlayScreen plays REAL note segments.

Design
------
* Melodic instruments (sitar, veena, bansuri): estimate the tonic by
  octave-fold alignment to the shuddha scale, then for each degree column
  (Sa..Sa') take the 1s window with the best sustained pitch match.
* Percussion (tabla, mridangam) don't sing a scale, so pitch-column matching
  is meaningless. Instead take the 8 most prominent 1s windows that are
  pitch-distinct and label them Sa(R). Sa'(R) in ascending median pitch --
  the listener still gets 8 real, audibly-different drum clips.

Every note gets a REAL 1s segment; the app never pitch-shifts the full clip
for the note grid. Emits assets/audio/note_<id>_<swar>.mp3 + notes.json.
"""

import json
import os
import subprocess
import tempfile
from pathlib import Path

import librosa
import numpy as np
import soundfile as sf

SR = 22050
NOTE_WIN = 1.0        # seconds per note segment
FADE = 0.03           # fade in/out, avoids clicks
HOP = 256
FR_WIN = 2048
WIN_FRAMES = int(round(NOTE_WIN * SR / HOP))

RAW = Path("tool/_raw")
OUT = Path("assets/audio")

DEGREES = [
    ("Sa", 0, "sa"),
    ("Re", 2, "re"),
    ("Ga", 4, "ga"),
    ("Ma", 5, "ma"),
    ("Pa", 7, "pa"),
    ("Dha", 9, "dha"),
    ("Ni", 11, "ni"),
    ("Sa'", 12, "sa2"),
]
DEG_SEMIS = np.array([d for _, d, _ in DEGREES])
TOL_SEMI = 0.7

SOURCES = {
    "sitar": "sitar_full.ogg",
    "tabla": "tabla_full.webm",
    "veena": "veena_full.ogg",
    "mridangam": "mridangam_full.ogg",
    "bansuri": "bansuri_full.ogg",
}
PERCUSSION = {"tabla", "mridangam"}


def load_track(path):
    fd, wname = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    subprocess.run(
        ["ffmpeg", "-y", "-i", str(path), "-ac", "1", "-acodec", "pcm_s16le", wname],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        y, _sr = librosa.load(wname, sr=SR, mono=True)
    finally:
        os.unlink(wname)
    f0, voiced, prob = librosa.pyin(
        y, fmin=60.0, fmax=1200.0, sr=SR,
        frame_length=FR_WIN, hop_length=HOP,
    )
    n = y.size
    rms = np.asarray([
        np.sqrt(np.mean(y[i * HOP: i * HOP + FR_WIN] ** 2))
        for i in range(len(f0))
    ], dtype=float)
    rms /= (rms.max() + 1e-9)
    return y, f0, voiced, prob, rms


def sliding_mean(a, win=WIN_FRAMES):
    if len(a) <= win:
        return None, 0.0
    csum = np.convolve(a, np.ones(win), mode="valid")
    return csum, csum / win


def pick_best_window(score, blacklist=()):
    """Highest-scoring 1s window, excluding windows overlapping blacklist."""
    csum, mean = sliding_mean(score)
    if mean is None:
        return None, 0.0
    mean = mean.copy()
    for bl in blacklist:
        b0 = max(0, int(bl / (HOP / SR)) - WIN_FRAMES)
        b1 = min(len(mean), int(bl / (HOP / SR)) + WIN_FRAMES)
        mean[b0:b1] = -np.inf
    with np.errstate(invalid="ignore"):
        best_i = int(np.nanargmax(np.nan_to_num(mean, nan=-1.0)))
    start = best_i * HOP / SR
    return start, float(mean[best_i])


def estimate_tonic(f0, voiced, prob):
    idx = np.where(voiced & np.isfinite(f0) & (prob > 0.3))[0]
    if len(idx) < 50:
        return None
    freqs = f0[idx]
    best_score = -1.0
    scores = []
    for step in range(int(round(12 * np.log2(880 / 55))) + 1):
        t = 55.0 * 2 ** (step / 12.0)
        semi = (12.0 * np.log2(freqs / t)) % 12.0
        m = np.abs(semi[:, None] - DEG_SEMIS[None, :]).min(axis=1)
        scores.append((t, float(np.mean(m < TOL_SEMI))))
    best_score = max(s for _, s in scores)
    # Prefer the LOWEST tonic that is within 3% of the best fit (tonic = lowest
    # sustained pitch in Indian music).
    low = [t for t, s in scores if s >= best_score - 0.03]
    return min(low), best_score, len(idx)


def note_targets(tonic):
    return {tag: tonic * 2 ** (st / 12.0) for _, st, tag in DEGREES}


def match_vs_target(f0, target):
    with np.errstate(invalid="ignore", divide="ignore"):
        cents = 1200.0 * np.log2(np.where((f0 > 1) & np.isfinite(f0), f0, np.nan) / target)
    cents = np.nan_to_num(cents, nan=1e4, posinf=1e4, neginf=-1e4)
    return np.exp(-0.5 * (cents / 50.0) ** 2)


def cut_to_mp3(y, start, path):
    n_start = int(start * SR)
    n_end = min(n_start + int(NOTE_WIN * SR), y.size)
    if n_end - n_start < SR * 0.5:
        return False
    seg = y[n_start:n_end].copy()
    f = int(FADE * SR)
    seg[:f] *= np.linspace(0, 1, f)
    seg[-f:] *= np.linspace(1, 0, f)
    fd, wname = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    sf.write(wname, seg, SR)
    subprocess.run(
        ["ffmpeg", "-y", "-i", wname, "-ac", "1", "-ar", "22050",
         "-b:a", "96k", str(path)],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    os.unlink(wname)
    return True


def window_median_freq(f0, start):
    b = int(start / (HOP / SR))
    seg = f0[b: b + WIN_FRAMES]
    seg = seg[np.isfinite(seg)]
    return float(np.median(seg)) if len(seg) else 0.0


def melodic_notes(y, f0, voiced, prob, rms, tonic):
    """Pitch-column extraction for melodic instruments.

    Returns list of (start_sec, final_quality, match_quality) per degree in
    DEGREES order. match_quality is the pure pitch-match window quality (used
    to pick the right tonic octave); final_quality is what the app gets, with
    a prominence fallback when the recording never plays that degree.
    """
    prom = np.nan_to_num(prob * np.sqrt(rms), nan=0.0)
    prom[~voiced] = 0.0
    results = []
    blacklist = []
    for name, st, tag in DEGREES:
        target = tonic * 2 ** (st / 12.0)
        match = match_vs_target(f0, target)
        score = np.nan_to_num(match * prob, nan=0.0)
        score[~voiced] = 0.0
        start, mq = pick_best_window(score, blacklist)
        # fall back to prominence (recorded note may be slightly off target)
        fq, start = mq, start
        if start is None or fq < 0.15:
            start2, q2 = pick_best_window(prom, blacklist)
            if start2 is not None and q2 > 0.10:
                start, fq = start2, q2
        if start is None:
            results.append((None, 0.0, 0.0))
            continue
        blacklist.append(start)
        results.append((start, fq, mq))
    return results


def pick_tonic_octave(f0, voiced, prob, rms, base):
    """Choose among {base, 2*base, 4*base, ...} the tonic whose pitch columns
    give the best real matches (fold-fit can't distinguish octaves)."""
    cands = []
    c = base
    while c * 2 <= 440:
        c *= 2
    # start from the highest octave ≤ 440 and try downward copies within range
    total = -1.0
    chosen = base
    arr = f0
    for div in range(4):
        t = min(c, 440.0) / 2.0 ** (3 - div)
        if t < 42:
            continue
        res = melodic_notes(None, arr, voiced, prob, rms, t)
        s = sum(r[2] for r in res)  # sum of match qualities
        if s > total:
            total, chosen = s, float(t)
    return chosen


def percussion_notes(y, f0, voiced, prob, rms):
    """8 pitch-distinct prominent windows for drums, labeled low->high."""
    prom = np.nan_to_num(prob * np.sqrt(rms), nan=0.0)
    prom[~voiced] = 0.0
    picks = []
    blacklist = []
    for _ in range(8):
        start, q = pick_best_window(prom, blacklist)
        if start is None:
            break
        blacklist.append(start)
        picks.append((start, q, window_median_freq(f0, start)))
    # order by median pitch, low to high = Sa .. Sa'
    picks.sort(key=lambda p: p[2])
    labels = [tag for _, _, tag in DEGREES]
    out = []
    for i, (start, q, mf) in enumerate(picks):
        out.append((labels[i] if i < len(labels) else "sa", labels[i] if i < len(labels) else "sa",
                    start, q, mf))
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {}

    for inst, raw in SOURCES.items():
        src = RAW / raw
        if not src.exists():
            print(f"[{inst}] MISSING {src}")
            continue
        y, f0, voiced, prob, rms = load_track(src)

        if inst in PERCUSSION:
            notes = percussion_notes(y, f0, voiced, prob, rms)
            print(f"[{inst}] percussion -> 1s pitch-ranked clips")
            entries = []
            for i, (name, tag, start, q, mf) in enumerate(notes):
                fn = OUT / f"note_{inst}_{tag}.mp3"
                ok = cut_to_mp3(y, start, fn)
                entries.append({"swar": DEGREES[i][0], "file": fn.name if ok else None,
                                "start": round(start, 2), "q": round(q, 3),
                                "med_hz": round(mf, 1)})
                print(f"    {DEGREES[i][0]:>3} <- {mf:6.1f}Hz  cut{start:7.2f}s  q={q:.2f}")
            manifest[inst] = entries
            continue

        tr = estimate_tonic(f0, voiced, prob)
        if tr[0] is None:
            print(f"[{inst}] ! no voiced frames")
            manifest[inst] = [{"swar": n, "file": None} for n, _, _ in DEGREES]
            continue
        tonic, fit, nfr = tr
        tonic = pick_tonic_octave(f0, voiced, prob, rms, tonic)
        print(f"[{inst}] melodic tonic={tonic:.1f}Hz  (fit~{fit:.0%}, voiced={nfr})")
        entries = []
        for (name, _st, tag), (start, q, _mq) in zip(DEGREES, melodic_notes(y, f0, voiced, prob, rms, tonic)):
            if start is None:
                entries.append({"swar": name, "file": None})
                print(f"    {name:>3}  none -> skip")
                continue
            target = tonic * 2 ** (_st / 12.0)
            fn = OUT / f"note_{inst}_{tag}.mp3"
            ok = cut_to_mp3(y, start, fn)
            entries.append({"swar": name, "file": fn.name if ok else None,
                            "start": round(start, 2), "q": round(q, 3)})
            print(f"    {name:>3}  target~{target:6.1f}Hz  cut{start:7.2f}s  q={q:.2f} -> {fn.name}")
        manifest[inst] = entries

    with open(OUT / "notes.json", "w") as fh:
        json.dump(manifest, fh, indent=2)
    print("wrote", OUT / "notes.json")


if __name__ == "__main__":
    main()