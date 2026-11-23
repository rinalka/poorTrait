// Mesh: the photo cut into triangles - the "low poly" look of Pastiche's MeshMap - beside the
// masses (SETUP 4, MESH), and used the same ways: VIEW's "mesh", START's "mesh", and COLOUR's
// "pick up from: mesh". Each triangle is the photo's average colour over it.
//
// The points the triangles join up:
//   - brightness (always): the photo is looked at every "point spacing" pixels, and a point is
//     kept wherever its brightness changes faster than "edge strength" (a Sobel filter, as in
//     Pastiche's EdgeDetector) - so busy places get lots of small triangles and flat ones a few big
//     ones. Each point is nudged a little at random, so the triangles don't line up on the grid
//   - "points in flat places": a sparser grid everywhere, so flat places (a clear sky) get
//     triangles of a size instead of long slivers reaching across them (0: none, as Pastiche)
//   - along the outline ("points along the outline"): SETUP 3's line as it's set there - a face's
//     parts or the objects' edges - with "points on the edges" points spaced evenly along all of
//     it, so the triangles' sides follow it. SETUP 3 comes first so the line is there; with
//     nothing in it, the box's line says so (meshNote)
//   - points round the picture's border, so the triangles reach the corners
// They're joined into triangles (Delaunay: Bowyer-Watson, the same as Pastiche's Triangulator).
// The mesh's "join similar neighbours" joins touching triangles of nearly the same colour into
// bigger flat shapes (as the masses' does with blobs).
//
// The triangles are kept (MeshResult.tri, in the photo's pixels) for later - to draw with, or as
// a guide for the other tools. While SETUP 4 is open, they're drawn over it.
//
// Like the masses, it's made in a thread of its own, again whenever a setting changes (once the
// slider is let go), and RUN waits for it. The edges are found here, in this window, first
// (meshEdges()).

final int MESH_MOST = 20000;        // brightness points at most (more are thinned out at random)

PImage meshImg;                     // the mesh at the photo's size (null until made)
String meshStatus = "mesh: not made yet";
String meshNote = "";               // shown in the box's line instead: "points along the outline" has no outline

class MeshResult {
  String face;
  int w, h;                         // the size it was worked out at
  int[] regionOf;                   // every pixel's shape (a triangle, or triangles joined)
  int[] rgb;                        // every shape's colour
  FloatList tri;                    // the triangles, x1, y1, x2, y2, x3, y3 each, in the photo's pixels
  int points, triangles, regions, ms;
}
volatile MeshResult meshResult;
volatile boolean meshBusy = false;
float[] meshAsked;
String meshAskedFace, meshAskedEdges = "";
MeshResult meshShown;

float[] meshSettings() {
  return new float[] { v("meshSpacing"), v("meshStrength"), v("meshFill"), v("meshEdgePoints"),
    0, v("meshOutline"), v("meshJoin") };
}

boolean meshPending() {
  return meshBusy || meshImg == null || meshShown == null || !meshShown.face.equals(faceName)
    || !java.util.Arrays.equals(meshSettings(), meshAsked) || !meshEdgeKey().equals(meshAskedEdges);
}

// every frame (from updateMasses): a new mesh if the settings or the picture changed, and a
// finished one shown
void updateMesh() {
  final float[] want = meshSettings();
  final String edgeKey = meshEdgeKey();
  boolean changed = meshAsked == null || !java.util.Arrays.equals(want, meshAsked) || !faceName.equals(meshAskedFace)
    || !edgeKey.equals(meshAskedEdges);
  if (changed && !meshBusy && !panel.mousePressed && !isRunning) {
    meshAsked = want;
    meshAskedFace = faceName;
    meshAskedEdges = edgeKey;
    meshBusy = true;
    meshStatus = "mesh: working ...";
    final ArrayList<float[]> edges = meshEdges();
    meshNote = v("meshOutline") > 0.5 && edges.isEmpty() ? "no outline yet  -  set SETUP 3 (until then, no points along it)" : "";
    final PImage src = photo;
    final String face = faceName;
    new Thread(new Runnable() {
      public void run() {
        try {
          synchronized (massLock) {
            meshResult = makeMesh(src, face, want, edges, edgeKey);
          }
        } catch (Exception e) {
          println("mesh failed: " + e);
          e.printStackTrace();
        }
        meshBusy = false;
      }
    }).start();
  }

  MeshResult r = meshResult;
  if (r == null || !r.face.equals(faceName)) {
    meshImg = null;
    return;
  }
  if (r != meshShown || meshImg == null) {
    meshImg = meshPicture(r);
    meshShown = r;
  }
  if (!meshBusy) meshStatus = "mesh: " + r.points + " points, " + r.triangles + " triangles, " + r.regions + " shapes (" + r.ms + " ms)";
}

PImage meshPicture(MeshResult r) {
  return meshPicture(r, r.rgb);
}

// the mesh with each shape in the colour `rgb` gives it
PImage meshPicture(MeshResult r, int[] rgb) {
  PImage img = createImage(r.w, r.h, RGB);
  img.loadPixels();
  for (int i = 0; i < r.regionOf.length; i++) img.pixels[i] = rgb[r.regionOf[i]];
  img.updatePixels();
  if (img.width != photo.width || img.height != photo.height) img.resize(photo.width, photo.height);
  img.loadPixels();
  return img;
}

// the mesh in SETUP 5's palette colours (SETUP 6's "mesh (palette colours)"): each shape the
// nearest palette colour (lightness counting half), moved back towards its own lightness as much
// as SETUP 5's "keep the masses' lightness" says. Made again when the mesh or the palette changes
PImage paletteMeshImg;
String paletteMeshKey = "";
int[] meshPalIndex;                 // which palette colour each of meshShown's shapes was given

void updatePaletteMesh() {
  MeshResult r = meshShown;
  int[] pal = panel.paletteFinal();
  if (r == null || meshImg == null || pal.length == 0) {
    paletteMeshImg = null;
    paletteMeshKey = "";
    meshPalIndex = null;
    panel.meshPaletteUse = new float[0];
    return;
  }
  MassResult mr = massShown;
  String key = System.identityHashCode(r) + " " + java.util.Arrays.toString(pal) + " " + v("paletteKeepLight")
    + " " + (mr == null ? "" : System.identityHashCode(mr) + java.util.Arrays.toString(lookShown));
  if (key.equals(paletteMeshKey) && paletteMeshImg != null) return;
  paletteMeshKey = key;
  float keep = v("paletteKeepLight");
  float[][] pl = new float[pal.length][3];
  for (int p = 0; p < pal.length; p++) toLab(pal[p], pl[p]);
  // the colours are given out as the masses give them: each shape the masses' paint nearest its
  // colour, then that paint's palette colour - so every palette colour is used, as in the masses
  // (each shape simply taking its nearest palette colour left most of a bright palette unused)
  // Without the masses, the nearest palette colour
  int[] paints = mr == null ? pal : adjustedPalette(mr.rgb);
  int[] paintTo = mr == null ? null : paletteMassChoice(mr, pal);
  float[][] kl = new float[paints.length][3];
  for (int p = 0; p < paints.length; p++) toLab(paints[p], kl[p]);
  float[] ml = new float[3];
  int[] mapped = new int[r.rgb.length];
  int[] idx = new int[r.rgb.length];
  for (int k = 0; k < r.rgb.length; k++) {
    toLab(r.rgb[k], ml);
    int best = 0;
    float bestD = Float.MAX_VALUE;
    for (int p = 0; p < paints.length; p++) {
      float dd = 0.5 * sq(ml[0] - kl[p][0]) + sq(ml[1] - kl[p][1]) + sq(ml[2] - kl[p][2]);
      if (dd < bestD) { bestD = dd; best = p; }
    }
    if (paintTo != null) best = paintTo[best];
    mapped[k] = fromLab(lerp(pl[best][0], ml[0], keep), pl[best][1], pl[best][2]);
    idx[k] = best;
  }
  meshPalIndex = idx;
  // each palette colour's share of the picture in the mesh (THE AREA's strip, "from: mesh")
  float[] use = new float[pal.length];
  for (int i = 0; i < r.regionOf.length; i++) use[idx[r.regionOf[i]]]++;
  for (int p = 0; p < use.length; p++) use[p] /= r.regionOf.length;
  panel.meshPaletteUse = use;
  paletteMeshImg = meshPicture(r, mapped);
}

// the palette colour the mesh's shape at (x, y) on the photo was given, or -1 (with why, on the console)
int meshPaletteColourAt(float x, float y) {
  MeshResult r = meshShown;
  int[] idx = meshPalIndex;
  if (r == null || idx == null) { println("the mesh in palette colours isn't ready - SETUP 4 and 5"); return -1; }
  int mx = constrain((int) (x * r.w / photo.width), 0, r.w - 1);
  int my = constrain((int) (y * r.h / photo.height), 0, r.h - 1);
  return idx[r.regionOf[mx + my * r.w]];
}

// MOVEMENT's "start at vertex" and "at tri": the mesh's corners (each once), and its triangles'
// middles, as x, y, ... in the photo's pixels. Made again when the mesh changes; null without one
float[] meshVertexPts, meshTriPts;
MeshResult meshPtsFor;

void meshStartPoints() {
  MeshResult r = meshShown;
  if (r == meshPtsFor) return;
  meshPtsFor = r;
  meshVertexPts = meshTriPts = null;
  if (r == null || r.tri == null) return;
  int n = r.tri.size() / 6;
  meshTriPts = new float[n * 2];
  java.util.HashSet<Long> seen = new java.util.HashSet<Long>();
  FloatList v = new FloatList();
  for (int t = 0; t < n; t++) {
    float sx = 0, sy = 0;
    for (int c = 0; c < 3; c++) {
      float x = r.tri.get(t * 6 + c * 2), y = r.tri.get(t * 6 + c * 2 + 1);
      sx += x;
      sy += y;
      // the same corner is shared by several triangles: keep it once
      if (seen.add(((long) round(x * 4) << 32) ^ (round(y * 4) & 0xFFFFFFFFL))) { v.append(x); v.append(y); }
    }
    meshTriPts[t * 2] = sx / 3;
    meshTriPts[t * 2 + 1] = sy / 3;
  }
  meshVertexPts = v.array();
}

float[] meshVertices() {
  meshStartPoints();
  return meshVertexPts;
}

float[] meshTriangleMiddles() {
  meshStartPoints();
  return meshTriPts;
}

color meshAt(float x, float y) {
  return meshImg == null ? photoAt(x, y) : meshImg.pixels[pixelIndex(x, y)];
}

// the worker's copies from last time: only the joining is done again when only "join" changed
PImage meshWork;
String meshFace, meshCutFor = "";
int[] meshCut;
int meshCutCount, meshCutPoints;
FloatList meshCutTri;

MeshResult makeMesh(PImage src, String face, float[] s, ArrayList<float[]> edges, String edgeKey) {
  int t0 = millis();
  if (!face.equals(meshFace)) {
    meshFace = face;
    meshCutFor = "";
    meshWork = src.copy();
    if (meshWork.width > 1024) meshWork.resize(1024, 0);    // as the masses
    meshWork.loadPixels();
  }
  String cutKey = s[0] + " " + s[1] + " " + s[2] + " " + s[3] + " " + edgeKey;
  if (!cutKey.equals(meshCutFor)) {
    meshCutTri = new FloatList();
    meshCut = meshLabels(meshWork, s[0], s[1], s[2], round(s[3]), edges, src.width, meshCutTri);
    meshCutCount = blobCount;
    meshCutPoints = meshPoints;
    meshCutFor = cutKey;
  }
  blobStats(meshWork, meshCut, meshCutCount);       // (again each time: the masses share these)
  int[] joined = joinBlobs(meshCut, meshCutCount, s[6]);
  int n = 0;
  for (int l : joined) n = max(n, l + 1);
  long[][] sum = new long[n][4];
  for (int i = 0; i < joined.length; i++) {
    int c = meshWork.pixels[i];
    long[] q = sum[joined[i]];
    q[0] += c >> 16 & 255; q[1] += c >> 8 & 255; q[2] += c & 255; q[3]++;
  }
  MeshResult r = new MeshResult();
  r.rgb = new int[n];
  for (int k = 0; k < n; k++) {
    long cnt = Math.max(1L, sum[k][3]);
    r.rgb[k] = rgbOf(sum[k][0] / cnt, sum[k][1] / cnt, sum[k][2] / cnt);
  }
  r.face = face;
  r.w = meshWork.width;
  r.h = meshWork.height;
  r.regionOf = joined;
  r.tri = meshCutTri;
  r.points = meshCutPoints;
  r.triangles = meshCutTri.size() / 6;
  r.regions = countRegions(joined);
  r.ms = millis() - t0;
  return r;
}

// what the edge points depend on: the picture, the two ticks, and the outline's settings
String meshEdgeKey() {
  String k = faceName + " " + v("meshOutline");
  if (v("meshOutline") > 0.5) {
    k += " " + nf(v("outline_smooth"), 0, 2) + " " + v("outline_kind") + " " + v("outline_bigObj") + " " + v("outline_smallObj");
    for (String p : outlineParts) k += v("outline_" + p) > 0.5 ? "1" : "0";
  }
  return k;
}

// the edges the edge points go along, as lines of x, y, x, y ... in the photo's pixels (found
// again only when meshEdgeKey changes)
ArrayList<float[]> meshEdgeLines = new ArrayList<float[]>();
String meshEdgesFor = "";

ArrayList<float[]> meshEdges() {
  String key = meshEdgeKey();
  if (!key.equals(meshEdgesFor)) {
    meshEdgesFor = key;
    meshEdgeLines = findMeshEdges();
  }
  return meshEdgeLines;
}

ArrayList<float[]> findMeshEdges() {
  ArrayList<float[]> lines = new ArrayList<float[]>();
  if (v("meshOutline") > 0.5) {
    String was = tool;
    tool = "outline";
    outlinePlanned();
    tool = was;
    for (OutlinePart e : outlineShapes) lines.add(partLine(e, 1, 1));
  }
  return lines;
}

float[] partLine(OutlinePart e, float sx, float sy) {
  int n = e.size(), m = e.closed ? n + 1 : n;
  float[] l = new float[m * 2];
  for (int i = 0; i < m; i++) {
    l[i * 2] = e.x.get(i % n) * sx;
    l[i * 2 + 1] = e.y.get(i % n) * sy;
  }
  return l;
}


// ---------------------------------------------------------------- the work (the masses' thread)

int meshPoints;                     // how many points the last mesh had

// a region number for every pixel of img (at its size): the triangle it's in. Also hands back the
// triangles, in the photo's pixels, in `tris` (x1, y1, x2, y2, x3, y3 for each)
int[] meshLabels(PImage img, float spacing, float strength, float fill, int edgePoints, ArrayList<float[]> edges,
                 float photoW, FloatList tris) {
  int w = img.width, h = img.height;
  java.util.Random rnd = new java.util.Random(7);
  FloatList px = new FloatList(), py = new FloatList();
  java.util.HashSet<Integer> taken = new java.util.HashSet<Integer>();

  // brightness: a Sobel filter every `spacing` pixels
  float[] lum = new float[w * h];
  for (int i = 0; i < w * h; i++) {
    int c = img.pixels[i];
    lum[i] = ((c >> 16 & 255) + (c >> 8 & 255) + (c & 255)) / 3.0;
  }
  int step = max(2, round(spacing));
  FloatList bx = new FloatList(), by = new FloatList();
  for (int y = 1; y < h - 1; y += step) {
    for (int x = 1; x < w - 1; x += step) {
      int i = x + y * w;
      float gx = lum[i - w + 1] + 2 * lum[i + 1] + lum[i + w + 1] - lum[i - w - 1] - 2 * lum[i - 1] - lum[i + w - 1];
      float gy = lum[i + w - 1] + 2 * lum[i + w] + lum[i + w + 1] - lum[i - w - 1] - 2 * lum[i - w] - lum[i - w + 1];
      if (sqrt(gx * gx + gy * gy) / 4 <= strength) continue;
      float j = step * 0.35;
      bx.append(constrain(x + (rnd.nextFloat() * 2 - 1) * j, 0, w - 1));
      by.append(constrain(y + (rnd.nextFloat() * 2 - 1) * j, 0, h - 1));
    }
  }
  // flat places: a grid 12 (fill near 0) down to 3 (fill 1) spacings apart
  if (fill > 0.001) {
    float far = step * lerp(12, 3, fill);
    for (float y = far / 2; y < h; y += far) for (float x = far / 2; x < w; x += far) {
      bx.append(constrain(x + (rnd.nextFloat() * 2 - 1) * far * 0.3, 0, w - 1));
      by.append(constrain(y + (rnd.nextFloat() * 2 - 1) * far * 0.3, 0, h - 1));
    }
  }
  float keep = bx.size() > MESH_MOST ? MESH_MOST / (float) bx.size() : 1;
  for (int i = 0; i < bx.size(); i++) if (keep >= 1 || rnd.nextFloat() < keep) meshAdd(px, py, taken, bx.get(i), by.get(i), w, h);

  // the edges: edgePoints points spaced evenly along all of them
  float s = w / photoW;
  if (edgePoints > 0 && edges.size() > 0) {
    float total = 0;
    for (float[] l : edges) for (int i = 2; i < l.length; i += 2) total += dist(l[i - 2], l[i - 1], l[i], l[i + 1]) * s;
    float gap = total / edgePoints, left = gap * 0.5;
    if (gap > 0) for (float[] l : edges) {
      for (int i = 2; i < l.length; i += 2) {
        float x0 = l[i - 2] * s, y0 = l[i - 1] * s, x1 = l[i] * s, y1 = l[i + 1] * s;
        float d = dist(x0, y0, x1, y1), at = 0;
        while (d - at >= left) {
          at += left;
          meshAdd(px, py, taken, lerp(x0, x1, at / d), lerp(y0, y1, at / d), w, h);
          left = gap;
        }
        left -= d - at;
      }
    }
  }

  // the border, with the corners
  int along = max(8, round(max(w, h) / (step * 4.0)));
  for (int k = 0; k <= along; k++) {
    float fx = (w - 1) * k / (float) along, fy = (h - 1) * k / (float) along;
    meshAdd(px, py, taken, fx, 0, w, h);
    meshAdd(px, py, taken, fx, h - 1, w, h);
    meshAdd(px, py, taken, 0, fy, w, h);
    meshAdd(px, py, taken, w - 1, fy, w, h);
  }
  meshPoints = px.size();

  // join them up, and give every pixel its triangle
  int[] t = delaunay(px.array(), py.array());
  int nt = t.length / 3;
  int[] label = new int[w * h];
  java.util.Arrays.fill(label, -1);
  float[] X = px.array(), Y = py.array();
  for (int k = 0; k < nt; k++) {
    float ax = X[t[k * 3]], ay = Y[t[k * 3]], bx2 = X[t[k * 3 + 1]], by2 = Y[t[k * 3 + 1]], cx = X[t[k * 3 + 2]], cy = Y[t[k * 3 + 2]];
    tris.append(new float[] { ax / s, ay / s, bx2 / s, by2 / s, cx / s, cy / s });
    float area = (bx2 - ax) * (cy - ay) - (by2 - ay) * (cx - ax);
    if (abs(area) < 1e-6) continue;
    int x0 = max(0, floor(min(ax, min(bx2, cx)))), x1 = min(w - 1, ceil(max(ax, max(bx2, cx))));
    int y0 = max(0, floor(min(ay, min(by2, cy)))), y1 = min(h - 1, ceil(max(ay, max(by2, cy))));
    float sg = area > 0 ? 1 : -1, e = -0.01 * abs(area);
    for (int y = y0; y <= y1; y++) {
      float qy = y + 0.5;
      for (int x = x0; x <= x1; x++) {
        float qx = x + 0.5;
        float w0 = sg * ((bx2 - ax) * (qy - ay) - (by2 - ay) * (qx - ax));
        float w1 = sg * ((cx - bx2) * (qy - by2) - (cy - by2) * (qx - bx2));
        float w2 = sg * ((ax - cx) * (qy - cy) - (ay - cy) * (qx - cx));
        if (w0 >= e && w1 >= e && w2 >= e) label[x + y * w] = k;
      }
    }
  }
  // the odd pixel no triangle quite covered takes its neighbour's
  for (int i = 0; i < w * h; i++) {
    if (label[i] >= 0) continue;
    if (i % w > 0 && label[i - 1] >= 0) label[i] = label[i - 1];
    else if (i >= w && label[i - w] >= 0) label[i] = label[i - w];
  }
  for (int i = w * h - 1; i >= 0; i--) {
    if (label[i] >= 0) continue;
    label[i] = i % w < w - 1 && label[i + 1] >= 0 ? label[i + 1] : i + w < w * h && label[i + w] >= 0 ? label[i + w] : 0;
  }
  return joinUp(label, w, h, 4);       // each triangle numbered, slivers folded into a neighbour
}

void meshAdd(FloatList px, FloatList py, java.util.HashSet<Integer> taken, float x, float y, int w, int h) {
  x = constrain(x, 0, w - 1);
  y = constrain(y, 0, h - 1);
  if (!taken.add(round(x) + round(y) * (w + 1))) return;      // one point to a pixel
  px.append(x);
  py.append(y);
}

// Delaunay triangles of the points (Bowyer-Watson, sweeping across in x as Paul Bourke's does):
// three point numbers for each triangle
int[] delaunay(float[] xs, float[] ys) {
  int n = xs.length;
  if (n < 3) return new int[0];
  Integer[] order = new Integer[n];
  for (int i = 0; i < n; i++) order[i] = i;
  final float[] fx = xs;
  java.util.Arrays.sort(order, new java.util.Comparator<Integer>() {
    public int compare(Integer a, Integer b) { return Float.compare(fx[a], fx[b]); }
  });
  double[] X = new double[n + 3], Y = new double[n + 3];
  double xmin = Double.MAX_VALUE, xmax = -Double.MAX_VALUE, ymin = Double.MAX_VALUE, ymax = -Double.MAX_VALUE;
  for (int i = 0; i < n; i++) {
    X[i] = xs[order[i]];
    Y[i] = ys[order[i]];
    xmin = Math.min(xmin, X[i]); xmax = Math.max(xmax, X[i]);
    ymin = Math.min(ymin, Y[i]); ymax = Math.max(ymax, Y[i]);
  }
  double d = Math.max(xmax - xmin, ymax - ymin) * 20, mx = (xmin + xmax) / 2, my = (ymin + ymax) / 2;
  X[n] = mx - d;     Y[n] = my - d;
  X[n + 1] = mx;     Y[n + 1] = my + d;
  X[n + 2] = mx + d; Y[n + 2] = my - d;

  ArrayList<double[]> open = new ArrayList<double[]>();     // a, b, c, centre x, centre y, radius squared
  ArrayList<double[]> done = new ArrayList<double[]>();
  open.add(meshTri(n, n + 1, n + 2, X, Y));
  java.util.HashMap<Long, Integer> edges = new java.util.HashMap<Long, Integer>();
  for (int p = 0; p < n; p++) {
    edges.clear();
    double x = X[p], y = Y[p];
    for (int j = open.size() - 1; j >= 0; j--) {
      double[] t = open.get(j);
      double dx = x - t[3], dy = y - t[4];
      boolean finished = dx > 0 && dx * dx > t[5];          // its circle is all to the left now
      boolean inside = !finished && dx * dx + dy * dy <= t[5];
      if (!finished && !inside) continue;
      if (finished) done.add(t);
      else for (int k = 0; k < 3; k++) {
        int a = (int) t[k], b = (int) t[(k + 1) % 3];
        long key = (long) Math.min(a, b) * (n + 3) + Math.max(a, b);
        Integer c = edges.get(key);
        edges.put(key, c == null ? 1 : c + 1);
      }
      open.set(j, open.get(open.size() - 1));
      open.remove(open.size() - 1);
    }
    // the hole's edges (those only one removed triangle had) each make a triangle with p
    for (java.util.Map.Entry<Long, Integer> e : edges.entrySet()) {
      if (e.getValue() != 1) continue;
      int a = (int) (e.getKey() / (n + 3)), b = (int) (e.getKey() % (n + 3));
      open.add(meshTri(a, b, p, X, Y));
    }
  }
  done.addAll(open);
  IntList out = new IntList();
  for (double[] t : done) {
    int a = (int) t[0], b = (int) t[1], c = (int) t[2];
    if (a >= n || b >= n || c >= n) continue;          // one of the big triangle's corners
    out.append(order[a]);
    out.append(order[b]);
    out.append(order[c]);
  }
  return out.array();
}

double[] meshTri(int a, int b, int c, double[] X, double[] Y) {
  double ax = X[a], ay = Y[a], bx = X[b], by = Y[b], cx = X[c], cy = Y[c];
  double d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by));
  if (Math.abs(d) < 1e-12) return new double[] { a, b, c, (ax + bx + cx) / 3, (ay + by + cy) / 3, Double.MAX_VALUE };
  double a2 = ax * ax + ay * ay, b2 = bx * bx + by * by, c2 = cx * cx + cy * cy;
  double ux = (a2 * (by - cy) + b2 * (cy - ay) + c2 * (ay - by)) / d;
  double uy = (a2 * (cx - bx) + b2 * (ax - cx) + c2 * (bx - ax)) / d;
  return new double[] { a, b, c, ux, uy, (ax - ux) * (ax - ux) + (ay - uy) * (ay - uy) };
}


// ---------------------------------------------------------------- showing it

// the triangles' sides over the picture (while SETUP 4 is open)
void drawMeshPreview(float s) {
  MeshResult r = meshShown;
  if (r == null || r.tri == null || r.tri.size() == 0) return;
  noFill();
  stroke(255, 255, 255, 90);
  strokeWeight(ui);
  beginShape(TRIANGLES);
  for (int k = 0; k + 5 < r.tri.size(); k += 6) {
    vertex(r.tri.get(k) * s, r.tri.get(k + 1) * s);
    vertex(r.tri.get(k + 2) * s, r.tri.get(k + 3) * s);
    vertex(r.tri.get(k + 4) * s, r.tri.get(k + 5) * s);
  }
  endShape();
  noStroke();
}
