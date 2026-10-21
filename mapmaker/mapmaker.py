"""
PoorTrait map maker
===================

Takes a photo and writes a folder of "information maps" that the
procedural painter can use:

    photo.png          the photo, resized - every map lines up with this exactly
    depth.png          near = white, far = black (8-bit, easy to load anywhere)
    depth16.png        same, but 16-bit for smoother gradients
    normal.png         surface direction as RGB (R = right, G = up, B = towards you)
    light_photo.png    brightness of the original photo
    light_shaded.png   the 3D shape re-lit by a light YOU choose (--light)
    curvature.png      grey = flat, lighter = bumps (nose tip), darker = hollows (eye sockets)
    parts.png          face-part label per pixel (values 0-18, see PART_NAMES below)
    parts_preview.png  the same, in colour, so you can see it
    importance.png     how much each area matters for recognising the face (white = keep)
    landmarks.json     478 3D points on each face, plus named groups (eyes, lips, ...)
    landmarks_preview.png
    overview.jpg       contact sheet of everything

Usage (from this folder):
    .venv\\Scripts\\python mapmaker.py ..\\leoTest.jpg
    .venv\\Scripts\\python mapmaker.py ..\\*.jpg --size 1200 --light 300 40
Or double-click mapmaker.bat to pick photos in a window, or drag photos onto it.
"""

import argparse
import glob
import json
import os
import sys
import urllib.request

import cv2
import numpy as np
from PIL import Image, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.join(HERE, "models")

DEPTH_MODEL = "depth-anything/Depth-Anything-V2-Small-hf"   # Apache-2.0
PARTS_MODEL = "jonathandinu/face-parsing"                   # SegFormer trained on CelebAMask-HQ
LANDMARK_MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/face_landmarker/"
                      "face_landmarker/float16/latest/face_landmarker.task")

PART_NAMES = ["background", "skin", "nose", "eyeglasses", "left_eye", "right_eye",
              "left_brow", "right_brow", "left_ear", "right_ear", "mouth",
              "upper_lip", "lower_lip", "hair", "hat", "earring", "necklace",
              "neck", "cloth"]

# How important each face part is for recognition (0..1). This is only a
# starting point for Stage 6 - the painter is where you take real control.
PART_IMPORTANCE = {"background": 0.0, "skin": 0.3, "nose": 0.8, "eyeglasses": 0.6,
                   "left_eye": 1.0, "right_eye": 1.0, "left_brow": 0.7, "right_brow": 0.7,
                   "left_ear": 0.3, "right_ear": 0.3, "mouth": 0.9, "upper_lip": 0.9,
                   "lower_lip": 0.9, "hair": 0.15, "hat": 0.15, "earring": 0.1,
                   "necklace": 0.1, "neck": 0.2, "cloth": 0.05}

# Colours for parts_preview.png
PART_COLOURS = np.array([
    [0, 0, 0], [230, 190, 160], [255, 120, 40], [120, 120, 120], [40, 120, 255],
    [40, 200, 255], [120, 60, 20], [160, 90, 30], [200, 150, 200], [220, 170, 220],
    [120, 0, 40], [220, 30, 60], [255, 80, 110], [90, 60, 40], [60, 60, 120],
    [255, 230, 0], [200, 200, 0], [200, 160, 130], [60, 120, 60]], dtype=np.uint8)


# ----------------------------------------------------------------------------
# Small helpers
# ----------------------------------------------------------------------------

def load_photo(path, max_size):
    """Open a photo, rotate it the right way up and shrink it to max_size."""
    img = Image.open(path)
    img = ImageOps.exif_transpose(img).convert("RGB")   # phone photos store rotation separately
    img.thumbnail((max_size, max_size), Image.LANCZOS)
    return img


def normalise(a, low_pct=1, high_pct=99):
    """Stretch an array to 0..1, ignoring the extreme 1% at each end."""
    lo, hi = np.percentile(a, [low_pct, high_pct])
    return np.clip((a - lo) / max(hi - lo, 1e-8), 0, 1).astype(np.float32)


def save_grey(path, a01, bits=8):
    """Save a 0..1 float array as a greyscale PNG."""
    if bits == 16:
        cv2.imwrite(path, (a01 * 65535).astype(np.uint16))
    else:
        cv2.imwrite(path, (a01 * 255).round().astype(np.uint8))


def save_rgb(path, rgb):
    cv2.imwrite(path, cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR))


def pick_device():
    import torch
    return "cuda" if torch.cuda.is_available() else "cpu"


# ----------------------------------------------------------------------------
# Map 1 - depth (Depth Anything V2)
# ----------------------------------------------------------------------------

_depth_pipe = None

def make_depth(img):
    """Returns depth as a 0..1 array, near = 1. This is relative depth: it knows
    the nose is in front of the cheeks, but not by how many centimetres."""
    global _depth_pipe
    import torch
    from transformers import pipeline
    if _depth_pipe is None:
        _depth_pipe = pipeline("depth-estimation", model=DEPTH_MODEL, device=pick_device())
    raw = _depth_pipe(img)["predicted_depth"]
    raw = torch.nn.functional.interpolate(raw[None, None] if raw.dim() == 2 else raw[None],
                                          size=(img.height, img.width),
                                          mode="bicubic", align_corners=False)
    return normalise(raw.squeeze().cpu().numpy().astype(np.float32), 0.5, 100)


# ----------------------------------------------------------------------------
# Map 2 - normals, worked out from the depth map
# ----------------------------------------------------------------------------

def make_normals(depth, relief):
    """Treat the depth map as a landscape and measure which way each point faces.
    `relief` exaggerates (bigger) or flattens (smaller) the shape.
    Returns an HxWx3 array of unit vectors (x right, y DOWN, z towards viewer)."""
    h, w = depth.shape
    z = cv2.GaussianBlur(depth, (0, 0), 1.5) * relief * max(h, w) * 0.1
    dzdx = cv2.Sobel(z, cv2.CV_32F, 1, 0, ksize=3) / 8
    dzdy = cv2.Sobel(z, cv2.CV_32F, 0, 1, ksize=3) / 8
    n = np.dstack([-dzdx, -dzdy, np.ones_like(z)])
    return n / np.linalg.norm(n, axis=2, keepdims=True)


def normals_to_rgb(n):
    """Standard normal-map colours: R = right, G = up, B = towards you."""
    rgb = np.dstack([n[..., 0], -n[..., 1], n[..., 2]])
    return ((rgb * 0.5 + 0.5) * 255).round().astype(np.uint8)


# ----------------------------------------------------------------------------
# Map 3 - lighting
# ----------------------------------------------------------------------------

def make_photo_light(img):
    """Perceived lightness of the photo (the L of CIE Lab)."""
    lab = cv2.cvtColor(np.asarray(img), cv2.COLOR_RGB2LAB)
    return lab[..., 0].astype(np.float32) / 255


def make_shaded_light(n, azimuth_deg, elevation_deg, ambient=0.15):
    """Light the 3D shape from a direction you choose.
    azimuth: 0 = from the right, 90 = from above, 180 = left, 270 = below.
    elevation: 0 = grazing from the side, 90 = straight from the front."""
    az, el = np.radians(azimuth_deg), np.radians(elevation_deg)
    light = np.array([np.cos(az) * np.cos(el),
                      -np.sin(az) * np.cos(el),    # minus because image y points down
                      np.sin(el)])
    lambert = np.clip(n @ light, 0, 1)
    return ambient + (1 - ambient) * lambert


# ----------------------------------------------------------------------------
# Map 4 - curvature
# ----------------------------------------------------------------------------

def make_curvature(n, scale):
    """How fast the surface bends. Positive = bump, negative = hollow.
    `scale` (in pixels) picks the size of feature: small = wrinkles, large = cheeks."""
    nx = cv2.GaussianBlur(n[..., 0], (0, 0), scale)
    ny = cv2.GaussianBlur(n[..., 1], (0, 0), scale)
    curv = cv2.Sobel(nx, cv2.CV_32F, 1, 0, ksize=3) + cv2.Sobel(ny, cv2.CV_32F, 0, 1, ksize=3)
    limit = np.percentile(np.abs(curv), 98) + 1e-8
    return np.clip(0.5 + 0.5 * curv / limit, 0, 1)   # 0.5 = flat


# ----------------------------------------------------------------------------
# Landmarks (MediaPipe Face Landmarker)
# ----------------------------------------------------------------------------

_landmarker = None

def get_landmarker():
    global _landmarker
    if _landmarker is None:
        import mediapipe as mp
        from mediapipe.tasks.python import BaseOptions, vision
        os.makedirs(MODELS_DIR, exist_ok=True)
        model_path = os.path.join(MODELS_DIR, "face_landmarker.task")
        if not os.path.exists(model_path):
            print("  downloading MediaPipe face model ...")
            urllib.request.urlretrieve(LANDMARK_MODEL_URL, model_path)
        options = vision.FaceLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=model_path), num_faces=4)
        _landmarker = vision.FaceLandmarker.create_from_options(options)
    return _landmarker


def landmark_groups():
    """Named groups of landmark indices, e.g. which of the 478 points are the lips."""
    from mediapipe.tasks.python.vision import FaceLandmarksConnections as C
    groups = {"face_oval": C.FACE_LANDMARKS_FACE_OVAL, "lips": C.FACE_LANDMARKS_LIPS,
              "left_eye": C.FACE_LANDMARKS_LEFT_EYE, "right_eye": C.FACE_LANDMARKS_RIGHT_EYE,
              "left_eyebrow": C.FACE_LANDMARKS_LEFT_EYEBROW,
              "right_eyebrow": C.FACE_LANDMARKS_RIGHT_EYEBROW,
              "left_iris": C.FACE_LANDMARKS_LEFT_IRIS, "right_iris": C.FACE_LANDMARKS_RIGHT_IRIS,
              "nose": C.FACE_LANDMARKS_NOSE}
    # each group is stored as connected pairs [start, end] so outlines can be drawn
    return {name: [[c.start, c.end] for c in conns] for name, conns in groups.items()}


def make_landmarks(img):
    """Returns a list of faces; each face is a list of 478 [x, y, z] points.
    x, y are in pixels of photo.png; z is relative depth (smaller = nearer)."""
    import mediapipe as mp
    rgb = np.ascontiguousarray(np.asarray(img))
    result = get_landmarker().detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
    faces = []
    for face in result.face_landmarks:
        faces.append([[round(p.x * img.width, 2), round(p.y * img.height, 2),
                       round(p.z * img.width, 2)] for p in face])
    return faces


def draw_landmarks(img, faces, groups):
    out = np.asarray(img).copy()
    out = (out * 0.6).astype(np.uint8)
    thick = max(1, img.width // 600)
    for pts in faces:
        for x, y, _ in pts:
            cv2.circle(out, (int(x), int(y)), thick, (255, 255, 255), -1)
        for name, pairs in groups.items():
            colour = (255, 60, 60) if "lip" in name else (60, 200, 255)
            for a, b in pairs:
                cv2.line(out, (int(pts[a][0]), int(pts[a][1])),
                         (int(pts[b][0]), int(pts[b][1])), colour, thick + 1)
    return out


# ----------------------------------------------------------------------------
# Face parts (SegFormer face parser) and importance
# ----------------------------------------------------------------------------

_parser = None

def make_parts(img, faces):
    """Label every pixel as skin, nose, eye, hair ... The parser was trained on
    close-up portraits, so if we found a face we crop around it first."""
    global _parser
    import torch
    from transformers import SegformerForSemanticSegmentation, SegformerImageProcessor
    if _parser is None:
        _parser = (SegformerImageProcessor.from_pretrained(PARTS_MODEL),
                   SegformerForSemanticSegmentation.from_pretrained(PARTS_MODEL).to(pick_device()).eval())
    processor, model = _parser

    # Crop: a square around all detected faces, big enough to include hair and neck.
    x0, y0, x1, y1 = 0, 0, img.width, img.height
    if faces:
        pts = np.array([p[:2] for face in faces for p in face])
        (fx0, fy0), (fx1, fy1) = pts.min(0), pts.max(0)
        cx, cy = (fx0 + fx1) / 2, (fy0 + fy1) / 2 - 0.1 * (fy1 - fy0)
        half = max(fx1 - fx0, fy1 - fy0) * 1.3
        x0, y0 = int(max(0, cx - half)), int(max(0, cy - half))
        x1, y1 = int(min(img.width, cx + half)), int(min(img.height, cy + half))
    crop = img.crop((x0, y0, x1, y1))

    with torch.no_grad():
        inputs = processor(images=crop, return_tensors="pt").to(model.device)
        logits = model(**inputs).logits
        logits = torch.nn.functional.interpolate(logits, size=(crop.height, crop.width),
                                                 mode="bilinear", align_corners=False)
    labels = np.zeros((img.height, img.width), np.uint8)
    labels[y0:y1, x0:x1] = logits.argmax(1)[0].cpu().numpy().astype(np.uint8)
    return labels


def make_importance(labels, softness):
    weights = np.array([PART_IMPORTANCE[name] for name in PART_NAMES], np.float32)
    imp = weights[labels]
    blur = softness * max(labels.shape) / 1000
    return np.clip(cv2.GaussianBlur(imp, (0, 0), blur), 0, 1) if blur > 0 else imp


# ----------------------------------------------------------------------------
# Overview contact sheet
# ----------------------------------------------------------------------------

def make_overview(tiles, tile_width=400):
    """tiles: list of (label, image array). Returns one big RGB image."""
    cells = []
    for label, a in tiles:
        if a.ndim == 2:
            a = np.dstack([a] * 3)
        h = int(a.shape[0] * tile_width / a.shape[1])
        a = cv2.resize(a, (tile_width, h), interpolation=cv2.INTER_AREA)
        a = cv2.copyMakeBorder(a, 0, 28, 0, 0, cv2.BORDER_CONSTANT, value=(255, 255, 255))
        cv2.putText(a, label, (6, h + 20), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (20, 20, 20), 1, cv2.LINE_AA)
        cells.append(a)
    cols = 4
    while len(cells) % cols:
        cells.append(np.full_like(cells[0], 255))
    rows = [np.hstack(cells[i:i + cols]) for i in range(0, len(cells), cols)]
    return np.vstack(rows)


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

def process(path, args):
    name = os.path.splitext(os.path.basename(path))[0]
    out = os.path.join(args.out, name)
    os.makedirs(out, exist_ok=True)
    print(f"{name}")

    img = load_photo(path, args.size)
    img.save(os.path.join(out, "photo.png"))
    print(f"  size {img.width} x {img.height}")

    print("  depth ...")
    depth = make_depth(img)
    save_grey(os.path.join(out, "depth.png"), depth)
    save_grey(os.path.join(out, "depth16.png"), depth, bits=16)

    print("  normals, lighting, curvature ...")
    n = make_normals(depth, args.relief)
    normal_rgb = normals_to_rgb(n)
    save_rgb(os.path.join(out, "normal.png"), normal_rgb)
    light_photo = make_photo_light(img)
    save_grey(os.path.join(out, "light_photo.png"), light_photo)
    light_shaded = make_shaded_light(n, *args.light)
    save_grey(os.path.join(out, "light_shaded.png"), light_shaded)
    curvature = make_curvature(n, args.curve_scale * max(img.size) / 1000)
    save_grey(os.path.join(out, "curvature.png"), curvature)

    print("  landmarks ...")
    faces = make_landmarks(img)
    groups = landmark_groups()
    with open(os.path.join(out, "landmarks.json"), "w") as f:
        json.dump({"width": img.width, "height": img.height, "faces": faces,
                   "groups": groups}, f)
    landmarks_preview = draw_landmarks(img, faces, groups)
    save_rgb(os.path.join(out, "landmarks_preview.png"), landmarks_preview)
    print(f"  found {len(faces)} face(s)")

    print("  face parts ...")
    labels = make_parts(img, faces)
    cv2.imwrite(os.path.join(out, "parts.png"), labels)
    parts_preview = PART_COLOURS[labels]
    save_rgb(os.path.join(out, "parts_preview.png"), parts_preview)
    importance = make_importance(labels, args.softness)
    save_grey(os.path.join(out, "importance.png"), importance)

    to8 = lambda a: (a * 255).astype(np.uint8)
    sheet = make_overview([
        ("photo", np.asarray(img)), ("depth", to8(depth)), ("normal", normal_rgb),
        ("curvature", to8(curvature)), ("light_photo", to8(light_photo)),
        ("light_shaded", to8(light_shaded)), ("parts", parts_preview),
        ("importance", to8(importance)), ("landmarks", landmarks_preview)])
    cv2.imwrite(os.path.join(out, "overview.jpg"), cv2.cvtColor(sheet, cv2.COLOR_RGB2BGR),
                [cv2.IMWRITE_JPEG_QUALITY, 90])
    print(f"  -> {out}")


def choose_photos():
    """Open a normal Windows 'Open file' window so photos can be picked by clicking."""
    # Python 3.13 in a venv can't find its own Tcl/Tk files, so point it at them.
    tcl_dir = os.path.join(sys.base_prefix, "tcl")
    os.environ.setdefault("TCL_LIBRARY", os.path.join(tcl_dir, "tcl8.6"))
    os.environ.setdefault("TK_LIBRARY", os.path.join(tcl_dir, "tk8.6"))
    import tkinter
    from tkinter import filedialog
    root = tkinter.Tk()
    root.withdraw()                       # hide the empty main window
    root.attributes("-topmost", True)     # make sure the picker appears in front
    print("Choose one or more photos in the window that just opened ...")
    files = filedialog.askopenfilenames(
        title="PoorTrait map maker - choose photos",
        initialdir=os.path.dirname(HERE),
        filetypes=[("Photos", "*.jpg *.jpeg *.png *.webp *.bmp *.tif *.tiff"), ("All files", "*.*")])
    root.destroy()
    return list(files)


def main():
    p = argparse.ArgumentParser(description="Turn photos into PoorTrait information maps.")
    p.add_argument("photos", nargs="*",
                   help="photo files (wildcards like *.jpg are fine). Leave out to pick them in a window")
    p.add_argument("--out", default=os.path.join(HERE, "maps"), help="output folder")
    p.add_argument("--size", type=int, default=1536, help="longest side in pixels (default 1536)")
    p.add_argument("--relief", type=float, default=3.0,
                   help="exaggerate (>1) or flatten (<1) the 3D shape for normals (default 3)")
    p.add_argument("--light", type=float, nargs=2, default=[120, 45], metavar=("AZIMUTH", "ELEVATION"),
                   help="light direction in degrees for light_shaded.png (default 120 45 = upper left)")
    p.add_argument("--curve-scale", type=float, default=4.0,
                   help="feature size for curvature: small = fine detail, large = broad forms (default 4)")
    p.add_argument("--softness", type=float, default=8.0,
                   help="how much to blur the importance map edges (default 8, 0 = hard)")
    args = p.parse_args()

    if not args.photos:
        args.photos = choose_photos()
        if not args.photos:
            print("No photos chosen.")
            return

    paths = []
    for pattern in args.photos:
        paths.extend(sorted(glob.glob(pattern)) or [pattern])
    for path in paths:
        if not os.path.isfile(path):
            print(f"skipping {path}: not found")
            continue
        try:
            process(path, args)
        except Exception as e:
            print(f"  FAILED on {path}: {e}")
            if len(paths) == 1:
                raise


if __name__ == "__main__":
    sys.exit(main())
