// Area: IN AREA (APPLY's second step) - where on its layer a tool may put paint.
//
//   All            anywhere
//   Masses Color   the places where the masses in the palette's colours (VIEW's "masses (palette)")
//                  are one of the chosen colours - or, with "outside it", everywhere else
//   Mesh Color     the same, with the mesh in them (VIEW's "mesh (palette)")
//   Masses         the blobs of the masses (SETUP 2) clicked in the output window, or everywhere else
//   Tris           the same, with the mesh's triangles (SETUP 4)
//   Objects        ... with what the map maker's object finder found
//   Face Parts     ... with the parts of the face (and the hair, the clothes ...) - the Picks tab
// The colours are SETUP 5's, chosen in the strip - click to turn each on or off - or with PICK ON
// THE MASSES / MESH, clicking that picture in the output window. They, and the pieces picked,
// are shared by every tool; which of these a tool goes by, and whether it stays in or out, is its own.
// A tool doesn't paint till the step is done: one of them chosen and, but for All, at least one
// colour or piece. (SCRAPE's erase and COPY do all of it at once, with a fade inside or outside its border - at the end.)
//
// Two things keep a tool where it should be:
//   - its marks only start there (startPoint() tries again until a mark's start is in the right
//     place - a grid's spot in the wrong place is just skipped). OUTLINE's line goes where it goes
//   - "clip at its edge": paint that runs over the edge is cut off. The layer is copied
//     before the tool paints, and afterwards the part of the layer the tool mustn't touch is put
//     back from the copy - all on the graphics card. SCRAPE's scrapes are cut to the area the
//     same way.

// IN AREA's choices, and what each is. -1: not chosen yet
String[] inAreaNames = { "All", "Masses Color", "Mesh Color", "Masses", "Tris", "Objects", "Face Parts" };
final int AREA_ALL = 0, AREA_MASS_COLOUR = 1, AREA_MESH_COLOUR = 2, AREA_MASSES = 3, AREA_TRIS = 4, AREA_OBJECTS = 5, AREA_PARTS = 6;

// whether tool n's IN AREA step is done
boolean areaChosen(String n) {
  int a = (int) v(n + "_inArea");
  if (patchKind(a) >= 0) return patchCount[patchKind(a)] > 0;
  if (a == AREA_MASS_COLOUR || a == AREA_MESH_COLOUR) {
    for (boolean b : panel.areaPick) if (b) return true;
    return false;
  }
  return a == AREA_ALL;
}

// where the tool now in use may paint: 0 anywhere, 1 only in the area, 2 only outside it
int areaWay() {
  return t("inArea") > AREA_ALL ? (t("areaSide") == 0 ? 1 : 2) : 0;
}

// whether the tool now in use can paint: its area chosen, and worked out if there is one
boolean areaAllows() {
  return areaChosen(tool) && (areaWay() == 0 || areaReady());
}

boolean[] areaIn;              // at the masses' size: whether each pixel is in the area
int areaW, areaH;
PImage areaInMask, areaOutMask;  // photo-sized: solid in the area / solid outside it
PGraphics areaSnap;            // the layer as it was before the tool painted (for clipping)
String areaFor = "";
boolean areaWarned = false;
int areaCheckedFrame = -1;     // checked once a frame (startPoint() asks thousands of times)
String areaCheckedTool = "";   // ... for each tool
boolean areaOK = false;

// whether there's an area now, made again if what it's made of or what's chosen has changed
boolean areaReady() {
  if (areaCheckedFrame != frameCount || !areaCheckedTool.equals(tool)) {
    areaCheckedFrame = frameCount;
    areaCheckedTool = tool;
    areaOK = makeArea();
  }
  return areaOK;
}

boolean makeArea() {
  int kind = (int) t("inArea");
  String why = null, key = "";
  // what each pixel is - its palette colour, its blob, its object ... - and which of them are chosen
  int[] of = null, through = null;       // (of a pixel, then through this if there is one)
  boolean[] picks;
  int w = 0, h = 0;
  int k = patchKind(kind);
  if (k >= 0) {
    Patches p = patches[k];
    picks = patchPicked[k];
    if (p == null) why = patchLine(k);
    else if (patchCount[k] == 0) why = "no " + patchWord[k] + "s picked";
    else {
      of = p.of;
      w = p.w;
      h = p.h;
      key = System.identityHashCode(p) + " " + System.identityHashCode(picks);
    }
  } else {
    int[] pal = panel.paletteFinal();
    boolean fromMesh = kind == AREA_MESH_COLOUR;
    MassResult r = massShown;
    MeshResult mr = meshShown;
    int[] mIdx = meshPalIndex;
    picks = panel.areaPick;
    boolean any = false;
    for (boolean b : picks) any |= b;
    if (!any) why = "no colours chosen";
    else if (pal.length == 0) why = "no palette yet";
    else if (fromMesh && (mr == null || mIdx == null)) why = "the mesh in palette colours isn't ready";
    else if (!fromMesh && r == null) why = "the masses aren't ready";
    else {
      of = fromMesh ? mr.regionOf : r.paintOf;
      through = fromMesh ? mIdx : paletteMassChoice(r, pal);
      w = fromMesh ? mr.w : r.w;
      h = fromMesh ? mr.h : r.h;
      key = System.identityHashCode(of) + " " + System.identityHashCode(through) + " " + java.util.Arrays.toString(picks);
    }
  }
  if (why != null) {
    if (!areaWarned) println("IN AREA: " + why + " - not painting");
    areaWarned = true;
    return false;
  }
  areaWarned = false;
  key = kind + " " + key + " " + photo.width + "x" + photo.height;
  if (key.equals(areaFor)) return true;
  areaFor = key;
  areaW = w;
  areaH = h;
  areaIn = new boolean[w * h];
  PImage in = createImage(w, h, ARGB), out = createImage(w, h, ARGB);
  in.loadPixels();
  out.loadPixels();
  int n = 0;
  for (int i = 0; i < areaIn.length; i++) {
    int c = through == null ? of[i] : through[of[i]];
    areaIn[i] = c >= 0 && c < picks.length && picks[c];
    in.pixels[i] = areaIn[i] ? 0xFFFFFFFF : 0;
    out.pixels[i] = areaIn[i] ? 0 : 0xFFFFFFFF;
    if (areaIn[i]) n++;
  }
  in.updatePixels();
  out.updatePixels();
  if (in.width != photo.width || in.height != photo.height) {
    in.resize(photo.width, photo.height);
    out.resize(photo.width, photo.height);
  }
  areaInMask = in;
  areaOutMask = out;
  println("IN AREA: " + nf(100.0 * n / areaIn.length, 0, 1) + "% of the picture");
  return true;
}

boolean inArea(float x, float y) {
  int mx = constrain((int) (x * areaW / photo.width), 0, areaW - 1);
  int my = constrain((int) (y * areaH / photo.height), 0, areaH - 1);
  return areaIn[mx + my * areaW];
}

// where the next mark starts (null: no mark this time), kept in or out of the area as the tool's
// IN AREA says
float[] startPoint() {
  int a = areaWay();
  if (a == 0 || !areaReady()) return startPointAnywhere();
  boolean want = a == 1;
  int tries = (int) t("startAt") == 2 ? 1 : 40;     // a grid goes on to its next spot instead
  for (int k = 0; k < tries; k++) {
    float[] s = startPointAnywhere();
    if (s == null) return null;
    if (inArea(s[0], s[1]) == want) return s;
  }
  return null;
}

// whether the tool now in use is clipped to the area
boolean areaClipping() {
  return areaWay() > 0 && t("areaClip") > 0.5 && areaReady();
}

// before the tool paints on g: a copy of it
void areaSnapLayer(PGraphics g) {
  if (areaSnap == null || areaSnap.width != g.width || areaSnap.height != g.height) {
    areaSnap = createGraphics(g.width, g.height, P2D);
  }
  areaSnap.beginDraw();
  areaSnap.clear();
  areaSnap.blendMode(REPLACE);
  areaSnap.image(g, 0, 0);
  areaSnap.blendMode(BLEND);
  areaSnap.endDraw();
}

// after it has: where it mustn't paint, g as it was. The new paint comes off there, and the copy
// - cut to just there - goes back in its place. (Premultiplied, so adding them up is exact, and
// the masks' soft edges blend the two.)
void areaClip(PGraphics g) {
  boolean only = areaWay() == 1;
  PImage keepOut = only ? areaOutMask : areaInMask, mayPaint = only ? areaInMask : areaOutMask;
  eraseWith(g, keepOut);
  eraseWith(areaSnap, mayPaint);
  g.beginDraw();
  PGL pgl = g.beginPGL();
  pgl.blendEquation(PGL.FUNC_ADD);
  pgl.blendFuncSeparate(PGL.ONE, PGL.ONE, PGL.ONE, PGL.ONE);
  g.image(areaSnap, 0, 0);
  g.flush();
  g.endPGL();
  g.endDraw();
}

// SCRAPE's mask for this frame, cut to where the scrape may go
void areaClipMask(PGraphics m) {
  if (!areaClipping()) return;
  eraseWith(m, areaWay() == 1 ? areaOutMask : areaInMask);
}


// ---------------------------------------------------------------- all of it at once (ERASE, COPY)

// the widest the fade at the border can be, either side of it (photo pixels)
final int FADE_MOST = 50;

// where the tool now in use goes, as a mask at the photo's size: the area, or everywhere else. Solid in
// it, with a fade `edge` pixels wide along the area's border - inside the area (less than 0), or outside
// it (more). So with "outside it", a fade inside the area runs on past where the tool goes
PImage areaMask(float edge) {
  boolean[] where = areaIn;
  if (areaWay() == 2) {
    where = new boolean[areaIn.length];
    for (int i = 0; i < where.length; i++) where[i] = !areaIn[i];
  }
  boolean inward = edge < 0 == (areaWay() == 1);
  float wide = round(abs(edge));
  return inward ? fadedMask(where, areaW, areaH, wide) : spreadMask(where, areaW, areaH, wide);
}

// a mask at the photo's size, solid in all of the area, and fading to nothing over the `fade` pixels
// outside its edge
PImage spreadMask(boolean[] in, int w, int h, float fade) {
  boolean[] off = new boolean[in.length];
  for (int i = 0; i < in.length; i++) off[i] = !in[i];
  float[] d = distanceIn(off, w, h);           // (0 in the area)
  float over = max(0.5, fade * w / photo.width);
  PImage mask = createImage(w, h, ARGB);
  mask.loadPixels();
  for (int i = 0; i < in.length; i++) {
    float u = in[i] ? 1 : fade <= 0 ? 0 : constrain(1 - (d[i] - 0.5) / over, 0, 1);
    mask.pixels[i] = round(255 * u * u * (3 - 2 * u)) << 24 | 0xFFFFFF;
  }
  mask.updatePixels();
  if (w != photo.width || h != photo.height) mask.resize(photo.width, photo.height);
  return mask;
}

// how much of the picture that is (0 .. 1)
float areaShare() {
  int n = 0;
  for (boolean b : areaIn) if (b == (areaWay() == 1)) n++;
  return n / (float) areaIn.length;
}

// a mask at the photo's size, solid in the area (`in`, w x h), fading to nothing over the `fade` pixels
// inside its edge (photo pixels; the picture's own edge doesn't count). In a space too narrow for
// that the fade is narrower, so its middle is always solid: half way in to its deepest place.
// Spaces that touch are one
PImage fadedMask(boolean[] in, int w, int h, float fade) {
  PImage mask = createImage(w, h, ARGB);
  mask.loadPixels();
  if (fade <= 0) {
    for (int i = 0; i < in.length; i++) mask.pixels[i] = in[i] ? 0xFFFFFFFF : 0;
  } else {
    float toPhoto = photo.width / (float) w;
    float[] d = distanceIn(in, w, h);
    int[] stack = new int[in.length];
    boolean[] done = new boolean[in.length];
    for (int s = 0; s < in.length; s++) {
      if (!in[s] || done[s]) continue;
      // one space: all the pixels joined to this one, and the deepest of them
      int top = 0, end = 0;
      float deepest = 0;
      stack[end++] = s;
      done[s] = true;
      while (top < end) {
        int i = stack[top++], x = i % w, y = i / w;
        deepest = max(deepest, d[i]);
        if (x > 0 && in[i - 1] && !done[i - 1]) { done[i - 1] = true; stack[end++] = i - 1; }
        if (x < w - 1 && in[i + 1] && !done[i + 1]) { done[i + 1] = true; stack[end++] = i + 1; }
        if (y > 0 && in[i - w] && !done[i - w]) { done[i - w] = true; stack[end++] = i - w; }
        if (y < h - 1 && in[i + w] && !done[i + w]) { done[i + w] = true; stack[end++] = i + w; }
      }
      float over = min(fade / toPhoto, deepest / 2);
      for (int k = 0; k < end; k++) {
        float u = constrain((d[stack[k]] - 0.5) / max(0.5, over), 0, 1);
        mask.pixels[stack[k]] = round(255 * u * u * (3 - 2 * u)) << 24 | 0xFFFFFF;
      }
    }
  }
  mask.updatePixels();
  if (w != photo.width || h != photo.height) mask.resize(photo.width, photo.height);
  return mask;
}

// how far each pixel of the area is from the nearest one that isn't in it (in pixels, exactly): down
// the columns, then along each row the lowest of the parabolas the columns' distances make
float[] distanceIn(boolean[] in, int w, int h) {
  final float FAR = w + h;                     // (nothing outside the area in this column)
  float[] g = new float[w * h], out = new float[w * h];
  for (int x = 0; x < w; x++) {
    float c = FAR;
    for (int y = 0; y < h; y++) {
      int i = x + y * w;
      c = in[i] ? min(FAR, c + 1) : 0;
      g[i] = c;
    }
    c = FAR;
    for (int y = h - 1; y >= 0; y--) {
      int i = x + y * w;
      c = in[i] ? min(FAR, c + 1) : 0;
      g[i] = min(g[i], c);
    }
  }
  int[] at = new int[w];
  double[] from = new double[w + 1];
  for (int y = 0; y < h; y++) {
    int r = y * w, k = 0;
    at[0] = 0;
    from[0] = -1e12;
    from[1] = 1e12;
    for (int x = 1; x < w; x++) {
      double fx = g[r + x] * (double) g[r + x] + x * (double) x, s;
      while (true) {
        int q = at[k];
        s = (fx - (g[r + q] * (double) g[r + q] + q * (double) q)) / (2.0 * (x - q));
        if (s > from[k] || k == 0) break;
        k--;
      }
      if (s <= from[k]) { at[0] = x; k = 0; from[1] = 1e12; continue; }
      at[++k] = x;
      from[k] = s;
      from[k + 1] = 1e12;
    }
    k = 0;
    for (int x = 0; x < w; x++) {
      while (from[k + 1] < x) k++;
      int q = at[k];
      out[r + x] = sqrt(g[r + q] * g[r + q] + (x - q) * (float) (x - q));
    }
  }
  return out;
}
