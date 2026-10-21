"""
PoorTrait mesh maker
====================

Turns a map folder (made by mapmaker.py) into 3D models: a grid of points over the photo, each
pushed towards you by the depth map, with the photo wrapped on as a texture.

    mesh_face.obj   just the person - background cut away
    mesh_full.obj   the whole photo as a relief plate
    mesh.mtl        tells 3D programs to use photo.png as the texture

The .obj files open in Blender (File > Import > Wavefront) and in the faceRelief Processing sketch.
Units: the photo is 1 wide, so a 1024 x 1536 photo is 1 x 1.5. y is up, z points towards you.

mapmaker.py makes these automatically. To (re)make them for folders that already exist:
    .venv\\Scripts\\python mesh.py maps\\leoTest
    .venv\\Scripts\\python mesh.py maps\\* --depth-scale 0.5 --step 3
"""

import argparse
import glob
import os

import cv2
import numpy as np

BACKGROUND = 0    # label 0 in parts.png


def load_depth(folder):
    """Depth as 0..1 floats, near = 1. Prefers the smooth 16-bit version."""
    d16 = os.path.join(folder, "depth16.png")
    if os.path.exists(d16):
        return cv2.imread(d16, cv2.IMREAD_UNCHANGED).astype(np.float32) / 65535
    return cv2.imread(os.path.join(folder, "depth.png"), cv2.IMREAD_GRAYSCALE).astype(np.float32) / 255


def vertex_normals(xyz):
    """Normals for a grid of points (H x W x 3), from the neighbours on each side."""
    dx = np.gradient(xyz, axis=1)
    dy = np.gradient(xyz, axis=0)
    n = np.cross(dy, dx)
    return n / np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-12)


def write_obj(path, xyz, uv, normals, keep_cell, mtl_name):
    """Write the grid as triangles. keep_cell[r, c] says whether the square whose top-left
    corner is grid point (r, c) is part of the model."""
    gh, gw = xyz.shape[:2]
    # only write the points some kept square uses, and renumber them
    used = np.zeros((gh, gw), bool)
    used[:-1, :-1] |= keep_cell
    used[1:, :-1] |= keep_cell
    used[:-1, 1:] |= keep_cell
    used[1:, 1:] |= keep_cell
    index = np.full((gh, gw), -1, np.int64)
    index[used] = np.arange(1, used.sum() + 1)       # .obj counts from 1

    rows, cols = np.nonzero(keep_cell)
    a = index[rows, cols]
    b = index[rows, cols + 1]
    c = index[rows + 1, cols]
    d = index[rows + 1, cols + 1]
    # two triangles per square, wound so the front faces the viewer
    tris = np.concatenate([np.stack([a, c, b], 1), np.stack([b, c, d], 1)])

    with open(path, "w") as f:
        f.write("# PoorTrait relief mesh\n")
        f.write(f"mtllib {mtl_name}\nusemtl photo\n")
        np.savetxt(f, xyz[used], fmt="v %.5f %.5f %.5f")
        np.savetxt(f, uv[used], fmt="vt %.5f %.5f")
        np.savetxt(f, normals[used], fmt="vn %.4f %.4f %.4f")
        t = np.repeat(tris, 3, axis=1)                 # each corner as v/vt/vn, all the same number
        np.savetxt(f, t, fmt="f %d/%d/%d %d/%d/%d %d/%d/%d")
    return int(used.sum()), len(tris)


def make_mesh(folder, depth_scale=0.4, step=4, smooth=1.5, max_jump=0.03):
    """depth_scale: how deep the nearest point is, as a fraction of the photo's width.
    step: pixels between grid points (smaller = finer and bigger files).
    smooth: blur on the depth first, in pixels, to take the grain off.
    max_jump: in the face model, squares whose corners differ in depth by more than this
              (as a fraction of the width) are dropped - that's where the person's outline
              would otherwise stretch back into the background."""
    depth = load_depth(folder)
    h, w = depth.shape
    if smooth > 0:
        depth = cv2.GaussianBlur(depth, (0, 0), smooth)

    parts_path = os.path.join(folder, "parts.png")
    parts = cv2.imread(parts_path, cv2.IMREAD_GRAYSCALE) if os.path.exists(parts_path) else None
    person = parts != BACKGROUND if parts is not None else np.ones((h, w), bool)

    # The face model gets its own depth range, stretched over just the person, so their shape
    # uses all of the depth instead of sharing it with the background.
    lo, hi = np.percentile(depth[person], [1, 99.8])
    face_depth = np.clip((depth - lo) / max(hi - lo, 1e-6), 0, 1)

    ys = np.arange(0, h, step)
    xs = np.arange(0, w, step)
    if ys[-1] != h - 1: ys = np.append(ys, h - 1)
    if xs[-1] != w - 1: xs = np.append(xs, w - 1)
    gx, gy = np.meshgrid(xs, ys)
    uv = np.dstack([gx / (w - 1), 1 - gy / (h - 1)])
    scale = 1 / (w - 1)                                  # photo is 1 wide

    def grid(z01):
        return np.dstack([(gx - (w - 1) / 2) * scale, ((h - 1) / 2 - gy) * scale,
                          z01[gy, gx] * depth_scale]).astype(np.float64)

    written = {}
    mtl = "mesh.mtl"
    with open(os.path.join(folder, mtl), "w") as f:
        f.write("newmtl photo\nKa 1 1 1\nKd 1 1 1\nKs 0 0 0\nillum 1\nmap_Kd photo.png\n")

    # full relief plate
    xyz = grid(depth)
    keep = np.ones((len(ys) - 1, len(xs) - 1), bool)
    written["mesh_full.obj"] = write_obj(os.path.join(folder, "mesh_full.obj"), xyz, uv,
                                         vertex_normals(xyz), keep, mtl)

    # just the person
    xyz = grid(face_depth)
    inside = person[gy, gx]
    z = xyz[..., 2]
    corners_in = inside[:-1, :-1] & inside[1:, :-1] & inside[:-1, 1:] & inside[1:, 1:]
    zs = np.stack([z[:-1, :-1], z[1:, :-1], z[:-1, 1:], z[1:, 1:]])
    keep = corners_in & (zs.max(0) - zs.min(0) < max_jump)
    written["mesh_face.obj"] = write_obj(os.path.join(folder, "mesh_face.obj"), xyz, uv,
                                         vertex_normals(xyz), keep, mtl)
    return written


def main():
    p = argparse.ArgumentParser(description="Make 3D relief models from PoorTrait map folders.")
    p.add_argument("folders", nargs="+", help="map folders (wildcards are fine)")
    p.add_argument("--depth-scale", type=float, default=0.4,
                   help="how deep the model is, as a fraction of its width (default 0.4)")
    p.add_argument("--step", type=int, default=4, help="pixels between grid points (default 4)")
    p.add_argument("--smooth", type=float, default=1.5, help="blur on the depth in pixels (default 1.5)")
    args = p.parse_args()
    folders = [f for pattern in args.folders for f in (sorted(glob.glob(pattern)) or [pattern])]
    for folder in folders:
        if not os.path.exists(os.path.join(folder, "photo.png")):
            print(f"skipping {folder}: not a map folder")
            continue
        written = make_mesh(folder, args.depth_scale, args.step, args.smooth)
        print(os.path.basename(os.path.normpath(folder)) + ": " +
              ",  ".join(f"{name} {v} points {t} triangles" for name, (v, t) in written.items()))


if __name__ == "__main__":
    main()
