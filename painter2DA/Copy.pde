// Copy: VIEW's maps as pictures, and COPY (the first box in the panel's column 2), which lays any of
// them on any layer.
//
// COPY is switched on and off like the tools, but it doesn't paint as the run goes along: its COPY
// button lays the chosen map on the chosen layer there and then - before RUN, while it's painting or
// while it's paused. It's SCRAPE's erase the other way round: the map goes on in APPLY's IN AREA (or
// outside it), all at once, fading at the area's edge into what's on the layer already, which stays
// everywhere else. With All, it covers the whole layer. Where it covers, it lies flat (the layer's
// IMPASTO height goes). "mesh (lines)" is only the lines, in black: they go over what's there, which stays.
//
// The grey maps (importance, curvature, depth, light) can be tinted: their greys made shades of one
// colour, from black, through the colour (where the grey is as light as it is), to white.
//
// What's copied before RUN is there when the run starts: RUN only clears the layers if there's been
// painting since they were last cleared (`painted`).

// VIEW's MAPS, in the order of its list (0 is the painting itself)
final int VIEW_PAINTING = 0, VIEW_PHOTO = 1, VIEW_MASSES = 6, VIEW_PAL_MASSES = 7, VIEW_MESH = 8, VIEW_PAL_MESH = 9, VIEW_MESH_LINES = 10;
String[] showNames = { "painting", "photo", "importance", "curvature", "depth", "light",
  "masses (photo)", "masses (palette)", "mesh (photo)", "mesh (palette)", "mesh (lines)" };
volatile String copyStatus = "";       // what COPY did last, for its box
boolean painted = false;               // there's been painting since the layers were last cleared

// map number m of VIEW's list as a picture, or null if it isn't ready. The map maker's are smaller
// than the photo; "mesh (lines)" is black lines on nothing
PImage mapPicture(int m) {
  if (m == VIEW_PHOTO) return photo;
  if (m == VIEW_MASSES) return massesImg;
  if (m == VIEW_PAL_MASSES) return paletteMassesImg;
  if (m == VIEW_MESH) return meshImg;
  if (m == VIEW_PAL_MESH) return paletteMeshImg;
  if (m == VIEW_MESH_LINES) return meshLines();
  return maps[m - 1];                  // importance, curvature, depth, light
}

// whether map m is one of the grey ones
boolean greyMap(int m) {
  return m > VIEW_PHOTO && m < VIEW_MASSES;
}

// COPY's button: what its box and APPLY say
void copyNow() {
  String was = tool;
  useTool(T_COPY);
  int m = constrain((int) v("copyWhat") + VIEW_PHOTO, VIEW_PHOTO, VIEW_MESH_LINES);
  int L = constrain((int) v("copyTo"), 0, LAYERS - 1);
  layersReady();
  if (!areaChosen(tool)) copyStatus = "choose the area, in APPLY";
  else if (areaWay() > 0 && !areaReady()) copyStatus = "the area isn't ready";
  else {
    PImage mask = areaWay() == 0 ? null : areaMask(t("fade"));
    if (!layMap(m, L, mask, greyMap(m) && v("copyTint") > 0.5, panel.colour("copyInk"))) copyStatus = showNames[m] + " isn't ready";
    else copyStatus = showNames[m] + (mask == null ? " on " : " on " + nf(100 * areaShare(), 0, 1) + "% of ")
      + "layer " + LAYER_NAMES[L] + (v("layerOn" + L) < 0.5 ? "  (hidden)" : "");
  }
  println("COPY: " + copyStatus);
  useTool(java.util.Arrays.asList(TOOLS).indexOf(was));
}

// map m laid on layer L: where `mask` is solid (as much as it's solid), or all over (null); its greys
// made shades of `ink` if it's tinted. Returns whether the map was ready
boolean layMap(int m, int L, PImage mask, boolean tinted, int ink) {
  PImage p = mapPicture(m);
  if (p == null) return false;
  if (tinted) p = tintedMap(p, ink);
  if (mask != null) p = maskedMap(p, mask);
  if (m != VIEW_MESH_LINES) {
    if (mask == null) clearLayer(L);
    else eraseWith(heights[L], mask);
  }
  PGraphics g = layers[L];
  g.beginDraw();
  g.image(p, 0, 0, photo.width, photo.height);
  g.endDraw();
  return true;
}

// a grey map in shades of one colour: the grey that's as light as the colour becomes the colour itself,
// darker greys go down to black, and lighter ones up to white
PImage tintedMap(PImage p, int ink) {
  float r = ink >> 16 & 255, g = ink >> 8 & 255, b = ink & 255;
  float at = 0.299 * r + 0.587 * g + 0.114 * b;
  int[] shade = new int[256];
  for (int k = 0; k < 256; k++) {
    if (k <= at) shade[k] = rgbOf(round(r * k / max(1, at)), round(g * k / max(1, at)), round(b * k / max(1, at)));
    else {
      float u = (k - at) / (255 - at);
      shade[k] = rgbOf(round(lerp(r, 255, u)), round(lerp(g, 255, u)), round(lerp(b, 255, u)));
    }
  }
  PImage out = createImage(p.width, p.height, ARGB);
  p.loadPixels();
  out.loadPixels();
  for (int i = 0; i < out.pixels.length; i++) out.pixels[i] = shade[p.pixels[i] & 255];
  out.updatePixels();
  return out;
}

// a map cut to a photo-sized mask: at the photo's size, only as solid as the mask is
PImage maskedMap(PImage p, PImage mask) {
  PImage out = p.get();
  if (out.width != mask.width || out.height != mask.height) out.resize(mask.width, mask.height);
  out.loadPixels();
  mask.loadPixels();
  boolean solid = p.format == RGB;
  for (int i = 0; i < out.pixels.length; i++) {
    int c = out.pixels[i], a = (mask.pixels[i] >>> 24) * (solid ? 255 : c >>> 24) / 255;
    out.pixels[i] = a << 24 | c & 0xFFFFFF;
  }
  out.format = ARGB;
  out.updatePixels();
  return out;
}
