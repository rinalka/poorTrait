// Area: THE AREA (in MOVEMENT) - a part of the picture the tools can be kept in, or kept out of.
//
// It's made of palette colours (SETUP 5): the places where the masses in the palette's colours
// (VIEW's "masses (palette)") are one of the chosen colours. They're chosen in the strip under
// MOVEMENT - click to turn each on or off - or with PICK ON THE MASSES, clicking the masses in
// the output window. The area is shared by every tool; each tool's "draw" says what it does with
// it: anywhere (the area doesn't matter), only in the area, or only outside it.
//
// Two things keep a tool where it should be:
//   - its marks only start there (startPoint() tries again until a mark's start is in the right
//     place - a grid's spot in the wrong place is just skipped)
//   - "clip at the area's edge": paint that runs over the edge is cut off. The layer is copied
//     before the tool paints, and afterwards the part of the layer the tool mustn't touch is put
//     back from the copy - all on the graphics card. SCRAPE's scrapes are cut to the area the
//     same way.
// With no colours chosen (or no palette or masses yet) there's no area, and the tools draw
// anywhere.

boolean[] areaIn;              // at the masses' size: whether each pixel is in the area
int areaW, areaH;
PImage areaInMask, areaOutMask;  // photo-sized: solid in the area / solid outside it
PGraphics areaSnap;            // the layer as it was before the tool painted (for clipping)
String areaFor = "";
boolean areaWarned = false;
int areaCheckedFrame = -1;     // checked once a frame (startPoint() asks thousands of times)
boolean areaOK = false;

// whether there's an area now, made again if the masses, the palette or the chosen colours have
// changed
boolean areaReady() {
  if (areaCheckedFrame != frameCount) {
    areaCheckedFrame = frameCount;
    areaOK = makeArea();
  }
  return areaOK;
}

boolean makeArea() {
  int[] pal = panel.paletteFinal();
  boolean[] picks = panel.areaPick;
  boolean any = false;
  for (boolean b : picks) any |= b;
  MassResult r = massShown;
  if (!any || pal.length == 0 || r == null) {
    if (!areaWarned) println("THE AREA: " + (!any ? "no colours chosen" : pal.length == 0 ? "no palette yet" : "the masses aren't ready")
      + " - drawing anywhere");
    areaWarned = true;
    return false;
  }
  areaWarned = false;
  String key = System.identityHashCode(r) + " " + java.util.Arrays.toString(lookShown) + " "
    + java.util.Arrays.toString(pal) + " " + java.util.Arrays.toString(picks) + " " + photo.width + "x" + photo.height;
  if (key.equals(areaFor)) return true;
  areaFor = key;
  int[] choice = paletteMassChoice(r, pal);
  areaW = r.w;
  areaH = r.h;
  areaIn = new boolean[r.w * r.h];
  PImage in = createImage(r.w, r.h, ARGB), out = createImage(r.w, r.h, ARGB);
  in.loadPixels();
  out.loadPixels();
  int n = 0;
  for (int i = 0; i < areaIn.length; i++) {
    int c = choice[r.paintOf[i]];
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
  println("THE AREA: " + nf(100.0 * n / areaIn.length, 0, 1) + "% of the picture");
  return true;
}

boolean inArea(float x, float y) {
  int mx = constrain((int) (x * areaW / photo.width), 0, areaW - 1);
  int my = constrain((int) (y * areaH / photo.height), 0, areaH - 1);
  return areaIn[mx + my * areaW];
}

// where the next mark starts (null: no mark this time), kept in or out of the area as the tool's
// "draw" says
float[] startPoint() {
  int a = (int) t("area");
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
  return t("area") > 0 && t("areaClip") > 0.5 && areaReady();
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
  boolean only = t("area") == 1;
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
  eraseWith(m, t("area") == 1 ? areaOutMask : areaInMask);
}
