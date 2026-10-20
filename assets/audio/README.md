# Audio assets (drop real recordings here)

For each instrument place a clip named exactly:

    assets/audio/sitar.mp3     (or .wav / .ogg)
    assets/audio/tabla.mp3
    assets/audio/veena.mp3
    assets/audio/mridangam.mp3
    assets/audio/bansuri.mp3

The clip is the "Hear the real sound" sample. Keep it short (3–10 s) so the APK
stays small. OGG at ~96–128 kbps mono is a fine trade-off.

## Optional: per-note samples for the "Play it" pad

If you drop short single-note clips they take precedence over the pitch-shift
fallback (the app pitch-shifts the main clip with `setPlaybackRate` otherwise):

    assets/audio/<instrument>_sa.wav
    assets/audio/<instrument>_re.wav
    assets/audio/<instrument>_ga.wav
    assets/audio/<instrument>_ma.wav
    assets/audio/<instrument>_pa.wav
    assets/audio/<instrument>_dha.wav
    assets/audio/<instrument>_ni.wav

Sources you can use today: Wikimedia Commons recordings (many instrument demos are
CC/copyleft), the Indian Culture Portal, or a friend with an instrument — just
match each to the SWAR row in `lib/models.dart` so the card's facts stay honest.

Any file that is missing is simply skipped; the player still works for the rest.