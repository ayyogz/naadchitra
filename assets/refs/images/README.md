# Reference photos (embedding source)

`tool/compute_embeddings.py` builds `assets/refs/embeddings.json` from photos in
this tree:

    assets/refs/images/
      sitar/      sitar_1.jpg, ...
      tabla/      tabla_1.jpg, ...
      veena/      veena_1.jpg, ...
      mridangam/  mridangam_1.jpg, ...
      bansuri/    bansuri_1.jpg, ...

**Rule of thumb: 3–5 GOOD, well-lit photos of each real instrument** (not cropped,
not tiny), ideally covering a couple of angles. Wikimedia Commons has plenty
(`https://commons.wikimedia.org` — search "sitar", "tabla", "Saraswati veena",
"mridangam", "bansuri").

After adding photos:

    python tool/compute_embeddings.py --model assets/models/mobilenet_v3_small_fe.onnx --refs assets/refs/images --check

`--check` prints the cosine of every reference photo to its instrument's mean
embedding — you want all values clearly above the cross-instrument scores. If a
class looks weak, add more/varied photos and rerun.

You do NOT ship the JPGs in the APK — only the small `embeddings.json` is bundled.