# PoorTrait map maker

The preprocessor for PoorTrait. Give it a photo; it writes a folder of
information maps that the painter uses to decide where and how to place marks.

## Using it

**Easiest:** double-click `mapmaker.bat`. A window opens where you pick one or more
photos (hold Ctrl to pick several). Or drag photos straight onto `mapmaker.bat`.

**From a terminal** (in this folder):

```
.venv\Scripts\python mapmaker.py ..\leoTest.jpg
.venv\Scripts\python mapmaker.py ..\*.jpg
.venv\Scripts\python mapmaker.py ..\leoTest.jpg --relief 5 --light 300 30
```

Results go to `maps\<photo name>\`. Open `overview.jpg` first to see everything at once.
The first run downloads about 450 MB of models; after that a photo takes a few seconds.

## Options

| Option | Default | What it does |
|---|---|---|
| `--size` | 1536 | Longest side of the output in pixels |
| `--relief` | 3 | Exaggerate (higher) or flatten (lower) the 3D shape. Affects normals, curvature and shading |
| `--light AZ EL` | 120 45 | Light direction for `light_shaded.png`. Azimuth: 0 = right, 90 = above, 180 = left, 270 = below. Elevation: 0 = grazing, 90 = head-on |
| `--curve-scale` | 4 | Size of forms the curvature map responds to: small = fine detail, large = broad forms |
| `--softness` | 8 | Blur on the importance map edges (0 = hard edges) |
| `--out` | `maps` | Output folder |

## The maps

Every map is exactly the same size as `photo.png`, so pixel (x, y) means the same spot in all of them.

| File | Meaning |
|---|---|
| `photo.png` | The photo, resized and turned the right way up |
| `depth.png` / `depth16.png` | White = near, black = far. Relative only (the nose is in front of the cheeks, but not by how many cm). 16-bit version has smoother gradients |
| `normal.png` | Which way the surface faces. R = right, G = up, B = towards you. Decode with `n = colour / 255 * 2 - 1` |
| `light_photo.png` | Lightness of the original photo |
| `light_shaded.png` | The 3D shape lit by the `--light` direction: a light you control |
| `curvature.png` | Mid-grey = flat, lighter = bumps (nose tip, lips), darker = hollows (eye sockets, creases) |
| `parts.png` | Each pixel's value (0-18) is a face part. It looks black because the numbers are small; see `parts_preview.png` |
| `importance.png` | How much each area matters for recognising the face. White = protect, black = free to destroy. Starting point for Stage 6 |
| `landmarks.json` | 478 3D points per face (`[x, y, z]` in pixels), plus `groups` listing which points form the eyes, lips, brows, nose, irises and face outline |

Face part numbers in `parts.png`:
0 background, 1 skin, 2 nose, 3 eyeglasses, 4 left eye, 5 right eye, 6 left brow,
7 right brow, 8 left ear, 9 right ear, 10 mouth, 11 upper lip, 12 lower lip, 13 hair,
14 hat, 15 earring, 16 necklace, 17 neck, 18 cloth.

## What's inside

| Map | Source | Licence |
|---|---|---|
| Depth | [Depth Anything V2 Small](https://huggingface.co/depth-anything/Depth-Anything-V2-Small-hf) | Apache-2.0 |
| Normals, curvature, shading | Calculated from depth (no AI) | - |
| Landmarks | [MediaPipe Face Landmarker](https://ai.google.dev/edge/mediapipe/solutions/vision/face_landmarker) | Apache-2.0 |
| Face parts | [jonathandinu/face-parsing](https://huggingface.co/jonathandinu/face-parsing) | Not stated; trained on CelebAMask-HQ (non-commercial research data). Fine for personal art; check before selling work made with it |

## Known limits

- Face parts are found by cropping around the face, so in wide shots the body
  and surroundings far from the face are labelled background.
- Depth is estimated from a single photo, so faces come out a bit flat.
  `--relief` compensates. Marigold (better normals, needs the GPU) is a possible upgrade.

## Reinstalling from scratch

```
python -m venv .venv
.venv\Scripts\python -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
.venv\Scripts\python -m pip install transformers numpy pillow opencv-python mediapipe
```
