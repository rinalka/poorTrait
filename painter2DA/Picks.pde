// Picks: pieces of the picture chosen by clicking them - IN AREA's "Masses", "Tris", "Objects" and
// "Face Parts" (APPLY, the Area tab).
//
// Choosing one of those shows the masses, the mesh or (for the last two) the photo in the output
// window, with a line round every piece, and the ones picked in orange. A click picks the one under
// the mouse, or takes it out again; dragging does the same to every one it goes over. The panel shows
// how many are picked and how much of the picture they cover. The button there (CLICK THE MASSES) or
// APPLY's title ends it.
//
// What the pieces are:
//   blobs       SETUP 2's regions (what "start at blob" uses)
//   tris        SETUP 4's shapes - a triangle, or several if "join similar neighbours" joined them
//   objects     what the map maker's object finder (SAM 2) cut the picture into (objects.png), and what
//               was left over. Pictures whose maps were made before it was added haven't got any
//   face parts  the face parser's parts (parts.png): skin, nose, each eye, brow and ear, lips, hair,
//               clothes ... and the background, which is everything else
// The picks are shared by every tool, like the palette colours. They go when there are other pieces -
// the masses or the mesh made again, another picture. SAVE keeps a spot in each, so LOAD SETTINGS can
// pick them again.

final int PICK_BLOBS = 0, PICK_TRIS = 1, PICK_OBJECTS = 2, PICK_PARTS = 3, PICK_KINDS = 4;   // the lots of picks
String[] patchWord = { "blob", "tri", "object", "part" }, patchWhere = { "masses", "mesh", "photo", "photo" };
String[] patchKey = { "areaBlobs", "areaTris", "areaObjects", "areaParts" };     // ... in saved settings
int[] patchView = { VIEW_MASSES, VIEW_MESH, VIEW_PHOTO, VIEW_PHOTO };            // ... and what they're picked on
// parts.png's numbers (the map maker's PART_NAMES; left and right are the sitter's)
String[] partNames = { "background", "skin", "nose", "glasses", "left eye", "right eye", "left brow", "right brow",
  "left ear", "right ear", "mouth", "upper lip", "lower lip", "hair", "hat", "earring", "necklace", "neck", "clothes" };

// the pieces of one kind: which one each pixel is in
class Patches {
  int[] of;                  // every pixel's patch
  int w, h, n;
  int[] size;                // every patch's size, in pixels

  Patches(int[] of, int w, int h) {
    this.of = of;
    this.w = w;
    this.h = h;
    for (int k : of) n = max(n, k + 1);
    size = new int[n];
    for (int k : of) size[k]++;
  }

  // the patch at (x, y) on the photo
  int at(float x, float y) {
    return of[constrain((int) (x * w / photo.width), 0, w - 1) + constrain((int) (y * h / photo.height), 0, h - 1) * w];
  }
}

Patches[] patches = new Patches[PICK_KINDS];              // null until they're made
boolean[][] patchPicked = new boolean[PICK_KINDS][];      // replaced whole, never changed in place
volatile int[] patchCount = new int[PICK_KINDS];          // how many are picked, and their share of the picture
volatile float[] patchShare = new float[PICK_KINDS];
float[][] patchesToPick = new float[PICK_KINDS][];        // loaded settings' picks, waiting for the pieces: x, y, ... (0 .. 1)
volatile boolean patchesWaiting = false;
String patchesToPickFace = "";
int patchesToPickFrame = 0;
String patchMapsFor = "";          // the picture the objects and face parts were read for

// every frame: the pieces as they are now. Other pieces, and the picks go
void updatePatches() {
  MassResult r = massShown;
  MeshResult m = meshShown;
  setPatches(PICK_BLOBS, r != null && massesImg != null && r.face.equals(faceName) ? r.regionOf : null, r == null ? 0 : r.w, r == null ? 0 : r.h);
  setPatches(PICK_TRIS, m != null && meshImg != null && m.face.equals(faceName) ? m.regionOf : null, m == null ? 0 : m.w, m == null ? 0 : m.h);
  if (!patchMapsFor.equals(faceName)) {
    patchMapsFor = faceName;
    readPatches(PICK_OBJECTS, "objects.png");
    readPatches(PICK_PARTS, "parts.png");
  }
  // loaded picks, once everything loaded with them has had time to take (and been made again)
  if (!patchesWaiting || frameCount < patchesToPickFrame + 5 || massesPending()) return;
  patchesWaiting = false;
  if (!faceName.equals(patchesToPickFace)) return;
  for (int k = 0; k < PICK_KINDS; k++) {
    float[] pts = patchesToPick[k];
    if (pts == null || patches[k] == null) continue;
    boolean[] p = new boolean[patches[k].n];
    for (int i = 0; i + 1 < pts.length; i += 2) p[patches[k].at(pts[i] * photo.width, pts[i + 1] * photo.height)] = true;
    setPicked(k, p);
  }
}

// one of the map maker's pictures of numbers (it may not have made it)
void readPatches(int k, String file) {
  String path = mapsPath() + "/" + faceName + "/" + file;
  PImage p = new java.io.File(path).exists() ? loadImage(path) : null;
  if (p == null || p.width <= 0) {
    setPatches(k, null, 0, 0);
    return;
  }
  p.loadPixels();
  int[] of = new int[p.pixels.length];
  for (int i = 0; i < of.length; i++) of[i] = p.pixels[i] >> 16 & 255;
  setPatches(k, of, p.width, p.height);
}

void setPatches(int k, int[] of, int w, int h) {
  if ((patches[k] == null ? null : patches[k].of) == of) return;
  patches[k] = of == null ? null : new Patches(of, w, h);
  setPicked(k, of == null ? null : new boolean[patches[k].n]);
}

void setPicked(int k, boolean[] picked) {
  patchPicked[k] = picked;
  int n = 0;
  long area = 0;
  if (picked != null) {
    for (int i = 0; i < picked.length; i++) if (picked[i] && patches[k].size[i] > 0) { n++; area += patches[k].size[i]; }
  }
  int[] c = patchCount.clone();
  float[] s = patchShare.clone();
  c[k] = n;
  s[k] = n == 0 ? 0 : area / (float) patches[k].of.length;
  patchShare = s;
  patchCount = c;
}

// (CLEAR on the panel) nothing picked
void clearPicks(int k) {
  if (patches[k] != null) setPicked(k, new boolean[patches[k].n]);
}

// ---------------------------------------------------------------- picking

// which picks IN AREA's choice a goes by (-1: none), and which the clicks in this window are for now
int patchKind(int a) {
  return a >= AREA_MASSES && a < AREA_MASSES + PICK_KINDS ? a - AREA_MASSES : -1;
}

int pickingPatches() {
  if (panel.picking != panel.PICK_AREA) return -1;
  return patchKind((int) panel.value(panel.editing + "_inArea"));
}

boolean patchDragOn = true;        // whether the drag going on picks patches or takes them out

// a press at (x, y) on the photo: the patch there picked, or taken out
void patchPressed(int k, float x, float y) {
  if (patches[k] == null) return;
  int i = patches[k].at(x, y);
  patchDragOn = !patchPicked[k][i];
  pickPatch(k, i);
}

// the mouse dragged from one spot to another: every patch on the way
void patchDragged(int k, float x0, float y0, float x1, float y1) {
  if (patches[k] == null) return;
  int steps = max(1, ceil(dist(x0, y0, x1, y1) / 2));
  for (int s = 1; s <= steps; s++) pickPatch(k, patches[k].at(lerp(x0, x1, s / (float) steps), lerp(y0, y1, s / (float) steps)));
}

void pickPatch(int k, int i) {
  if (patchPicked[k][i] == patchDragOn) return;
  boolean[] p = patchPicked[k].clone();
  p[i] = patchDragOn;
  setPicked(k, p);
}

// over the masses, the mesh or the photo while they're being picked on: a line round every piece, and
// the ones picked in orange. (On the photo, each piece has a faint tint of its own as well)
PImage patchOverlay;
Patches patchOverlayOf;
boolean[] patchOverlayPicks;

void drawPatchPicks() {
  int k = pickingPatches();
  if (k < 0 || patches[k] == null || v("showWhat") != patchView[k]) return;
  Patches p = patches[k];
  boolean[] on = patchPicked[k];
  if (p != patchOverlayOf || on != patchOverlayPicks || patchOverlay == null) {
    patchOverlayOf = p;
    patchOverlayPicks = on;
    if (patchOverlay == null || patchOverlay.width != p.w || patchOverlay.height != p.h) patchOverlay = createImage(p.w, p.h, ARGB);
    patchOverlay.loadPixels();
    PImage under = k == PICK_BLOBS ? massesImg : k == PICK_TRIS ? meshImg : photo;
    int[] tint = new int[p.n];
    if (under == photo) {
      for (int i = 0; i < p.n; i++) tint[i] = java.awt.Color.HSBtoRGB(i * 0.618, 0.8, 1) & 0xFFFFFF | 0x38000000;
      if (k == PICK_PARTS || k == PICK_OBJECTS) tint[0] = 0;        // the background, what's left over
    }
    int line = under == photo ? 0xD0000000 : 0x70000000;
    for (int y = 0; y < p.h; y++) {
      for (int x = 0; x < p.w; x++) {
        int i = y * p.w + x, a = p.of[i];
        int right = x + 1 < p.w ? p.of[i + 1] : a, below = y + 1 < p.h ? p.of[i + p.w] : a;
        int c = on[a] ? 0xAAFF5A00 : tint[a];
        if (right != a || below != a) {
          if (on[a] != on[right] || on[a] != on[below]) c = 0xFFFFFFFF;
          else if (on[a]) c = 0xC8802000;
          else {
            // a line that shows on what's there
            int u = under.pixels[x * under.width / p.w + y * under.height / p.h * under.width];
            c = (u >> 16 & 255) + 2 * (u >> 8 & 255) + (u & 255) > 440 ? line : line | 0xFFFFFF;
          }
        }
        patchOverlay.pixels[i] = c;
      }
    }
    patchOverlay.updatePixels();
  }
  image(patchOverlay, 0, 0, width, height);
}

// ---------------------------------------------------------------- saving

// a spot in each patch picked: x, y, ... as shares of the picture
JSONArray picksJSON(int k) {
  JSONArray a = new JSONArray();
  Patches p = patches[k];
  boolean[] on = patchPicked[k];
  if (p == null || on == null) return a;
  // the middle one of its pixels, in reading order: well inside it, most likely
  int[] seen = new int[p.n];
  for (int i = 0; i < p.of.length; i++) {
    int q = p.of[i];
    if (!on[q] || seen[q]++ != p.size[q] / 2) continue;
    a.append((i % p.w + 0.5) / p.w);
    a.append((i / p.w + 0.5) / p.h);
  }
  return a;
}

// picks loaded with a picture's settings
void loadPicks(JSONObject j) {
  patchesToPickFace = j.getString("face", faceName);
  patchesToPickFrame = frameCount;
  for (int k = 0; k < PICK_KINDS; k++) {
    patchesToPick[k] = null;
    if (!j.hasKey(patchKey[k])) continue;
    JSONArray a = j.getJSONArray(patchKey[k]);
    float[] p = new float[a.size()];
    for (int i = 0; i < p.length; i++) p[i] = a.getFloat(i);
    patchesToPick[k] = p;
  }
  patchesWaiting = true;
}

// ---------------------------------------------------------------- for the panel

// how many of kind k are picked, and how much of the picture that is - or why there's nothing to pick
String patchLine(int k) {
  Patches p = patches[k];
  int n = patchCount[k];
  if (p == null) return k == PICK_OBJECTS ? "no objects for this picture  -  its maps need making again"
    : k == PICK_PARTS ? "no face parts for this picture" : "the " + patchWhere[k] + " aren't ready";
  if (k == PICK_PARTS && p.size[0] == p.of.length) return "no face was found in this picture";
  if (n == 0) return "no " + patchWord[k] + "s yet  -  click them on the " + patchWhere[k];
  return n + " " + patchWord[k] + (n == 1 ? "" : "s") + "      " + nf(100 * patchShare[k], 0, 1) + "% of the picture";
}

// the face parts picked, by name, on two lines
String partsLine() {
  boolean[] on = patchPicked[PICK_PARTS];
  Patches p = patches[PICK_PARTS];
  String s = "", l = "";
  if (on == null || p == null) return s;
  int lines = 1;
  for (int i = 0; i < on.length && i < p.n; i++) {
    if (!on[i] || p.size[i] == 0) continue;
    String name = i < partNames.length ? partNames[i] : str(i);
    if (l.length() + name.length() > 42) {
      if (lines++ == 2) return s + l + " ...";
      s += l + ",\n";
      l = "";
    }
    l += (l.equals("") ? "" : ", ") + name;
  }
  return s + l;
}
