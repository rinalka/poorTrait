// Palette Gen: a palette of 24 colours built on a colour scheme - the panel's SETUP 5 box.
//
// Choose the scheme - complementary (two hues opposite each other), triad (three hues a third of
// the way round from each other) or split complementary (one hue and the two either side of its
// opposite) - and GENERATE makes a palette on it, from a hue picked at random: each of the
// scheme's hues as a run of tones from dark to light, the first hue with the most colours, and a
// few greys tinted by the scheme. Choosing another scheme generates a new palette straight away.
//
// Then, as in RECOLOUR: the "whole palette" sliders turn the hue and change the saturation and
// brightness of every colour, and clicking swatches chooses them so the "chosen colours" sliders
// change just those. Each swatch shows the colour as it was generated on the left and as it is now
// on the right.
//
// "masses in these colours" makes a second masses picture (VIEW's "masses (palette)"): the masses
// (SETUP 2) always have 24 paints, and each is given one of the palette's 24 colours - every colour
// used once, shared out so the picture changes as little as it can (a paint may get a colour a
// little off its own). "keep the masses' lightness" keeps how light or dark each paint was (so the
// picture stays readable even with a palette that hasn't the right darks and lights).
//
// Each tool can paint in the palette's colours: COLOUR's "pick up from: palette" (see further down).
//
// The palette and what's been done to it are kept on the panel (Gui's paletteBase and paletteAdj)
// and saved with the settings.

final int PALETTE_SIZE = 24;
String[] schemeNames = { "complementary", "triad", "split complementary" };

PImage paletteMassesImg;       // the masses in the palette's colours (null when it's off)
String paletteMassesKey = "";

// a new palette on scheme `scheme`, from a random hue. Returns the colours and, last, the base hue
// (in degrees) as a number of its own
int[] generatePalette(int scheme, java.util.Random rnd) {
  float base = rnd.nextFloat() * 360;
  float[] hues;
  int[] counts;
  if (scheme == 1) {
    hues = new float[] { base, base + 120, base + 240 };
    counts = new int[] { 9, 6, 6 };
  } else if (scheme == 2) {
    hues = new float[] { base, base + 150, base + 210 };
    counts = new int[] { 11, 5, 5 };
  } else {
    hues = new float[] { base, base + 180 };
    counts = new int[] { 12, 9 };
  }
  int[] out = new int[PALETTE_SIZE + 1];
  int n = 0;
  for (int g = 0; g < hues.length; g++) {
    // this hue's own character: how strong its colours are, and how far they wander from it
    float sat = 0.45 + 0.45 * rnd.nextFloat();
    float wander = 6 + 10 * rnd.nextFloat();
    int k = counts[g];
    for (int j = 0; j < k; j++) {
      float t = (j + 0.2 + 0.6 * rnd.nextFloat()) / k;           // dark .. light
      float b = 0.16 + 0.8 * t;
      // strongest in the middle tones, paler in the lights and duller in the darks
      float s = sat * (0.45 + 0.55 * sin(PI * min(1, t * 1.15))) * (0.8 + 0.4 * rnd.nextFloat());
      // the lights lean a little towards yellow and the darks away from it, as paint does
      float h = hues[g] + (rnd.nextFloat() - 0.5) * 2 * wander + towardsYellow(hues[g]) * (t - 0.5) * 16;
      out[n++] = hsbColour(h, s, b);
    }
  }
  // greys tinted by the scheme: a near black, a middle and a near white
  float[] greyB = { 0.12, 0.5, 0.93 };
  for (int j = 0; j < 3; j++) {
    float h = hues[j % hues.length] + (rnd.nextFloat() - 0.5) * 20;
    out[n++] = hsbColour(h, 0.05 + 0.1 * rnd.nextFloat(), greyB[j] + (rnd.nextFloat() - 0.5) * 0.06);
  }
  out[PALETTE_SIZE] = round(base);
  return out;
}

// +1 if turning hue h up moves it towards yellow (60 degrees), -1 if turning it down does
float towardsYellow(float h) {
  float d = ((60 - h) % 360 + 540) % 360 - 180;
  return d >= 0 ? 1 : -1;
}

// a colour from hue (degrees, any number), saturation and brightness (0 .. 1). java.awt's, not
// color() - this is called from the panel's thread
int hsbColour(float h, float s, float b) {
  h = h / 360;
  return java.awt.Color.HSBtoRGB(h - floor(h), constrain(s, 0, 1), constrain(b, 0, 1)) | 0xFF000000;
}

// Every frame: the masses in the palette's colours, made again when the masses, the palette or the
// two sliders change
void updatePaletteMasses() {
  if (v("paletteMasses") < 0.5 || massShown == null) {
    paletteMassesImg = null;
    paletteMassesKey = "";
    return;
  }
  int[] pal = panel.paletteFinal();
  if (pal.length == 0) {
    paletteMassesImg = null;
    return;
  }
  String key = System.identityHashCode(massShown) + " " + java.util.Arrays.toString(lookShown) + " "
    + java.util.Arrays.toString(pal) + " " + v("paletteKeepLight");
  if (key.equals(paletteMassesKey) && paletteMassesImg != null) return;
  paletteMassesKey = key;
  int[] paints = adjustedPalette(massShown.rgb), choice = paletteMassChoice(massShown, pal);
  float keep = v("paletteKeepLight");
  float[] ml = new float[3], pl = new float[3];
  int[] mapped = new int[paints.length];
  for (int m = 0; m < paints.length; m++) {
    // the palette colour, moved back towards the paint's own lightness as much as "keep" says
    toLab(paints[m], ml);
    toLab(pal[choice[m]], pl);
    mapped[m] = fromLab(lerp(pl[0], ml[0], keep), pl[1], pl[2]);
  }
  paletteMassesImg = massesPicture(massShown, mapped);
}

// which palette colour each of the masses' (r's) paints is given, for the masses in the
// palette's colours and SCRAPE's ERASE A PALETTE COLOUR
int[] paletteMassChoice(MassResult r, int[] pal) {
  int[] size = new int[r.rgb.length];
  for (int p : r.paintOf) size[p]++;
  return paletteMassPaints(adjustedPalette(r.rgb), size, pal);
}

// each of the masses' paints given a palette colour (its number), one each: the masses have as many
// paints as the palette has colours (MASS_PAINTS), and each palette colour goes to one paint, so
// every one of them is used. They're shared out so the paints, all together, change as little as
// possible (in Lab, where distance matches how different colours look - lightness counting a
// little less, as "keep the masses' lightness" can put it back; a big paint's change counting
// more than a small one's). So a paint may get its second or third nearest colour, a little off,
// when another paint needs its nearest more
int[] paletteMassPaints(int[] paints, int[] size, int[] pal) {
  float[][] pl = new float[pal.length][3], ml = new float[paints.length][3];
  for (int p = 0; p < pal.length; p++) toLab(pal[p], pl[p]);
  for (int m = 0; m < paints.length; m++) toLab(paints[m], ml[m]);
  long total = 0;
  for (int s : size) total += s;
  // the cost of each paint taking each colour; a square table, with empty rows or columns if
  // there are more of one than the other
  int n = max(paints.length, pal.length);
  double[][] cost = new double[n][n];
  for (int m = 0; m < paints.length; m++) {
    double weight = 0.5 + 0.5 * paints.length * size[m] / (double) max(1, total);   // bigger paints count more
    for (int p = 0; p < pal.length; p++) {
      double d = sqrt(0.6 * sq(ml[m][0] - pl[p][0]) + sq(ml[m][1] - pl[p][1]) + sq(ml[m][2] - pl[p][2]));
      cost[m][p] = d * weight;
    }
  }
  int[] given = assignment(cost);
  int[] out = new int[paints.length];
  for (int m = 0; m < paints.length; m++) {
    int p = given[m];
    if (p >= pal.length) {
      // more paints than colours (only with a palette of fewer colours): the nearest
      float best = Float.MAX_VALUE;
      for (int q = 0; q < pal.length; q++) {
        float d = 0.6 * sq(ml[m][0] - pl[q][0]) + sq(ml[m][1] - pl[q][1]) + sq(ml[m][2] - pl[q][2]);
        if (d < best) { best = d; p = q; }
      }
    }
    out[m] = p;
  }
  return out;
}

// the cheapest way to give each row of a square table of costs its own column (the Hungarian
// method). Returns each row's column
int[] assignment(double[][] a) {
  int n = a.length;
  double[] u = new double[n + 1], v = new double[n + 1];
  int[] p = new int[n + 1], way = new int[n + 1];
  for (int i = 1; i <= n; i++) {
    p[0] = i;
    int j0 = 0;
    double[] minv = new double[n + 1];
    java.util.Arrays.fill(minv, Double.MAX_VALUE);
    boolean[] used = new boolean[n + 1];
    do {
      used[j0] = true;
      int i0 = p[j0], j1 = 0;
      double delta = Double.MAX_VALUE;
      for (int j = 1; j <= n; j++) {
        if (used[j]) continue;
        double cur = a[i0 - 1][j - 1] - u[i0] - v[j];
        if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
        if (minv[j] < delta) { delta = minv[j]; j1 = j; }
      }
      for (int j = 0; j <= n; j++) {
        if (used[j]) { u[p[j]] += delta; v[j] -= delta; }
        else minv[j] -= delta;
      }
      j0 = j1;
    } while (p[j0] != 0);
    do {
      int j1 = way[j0];
      p[j0] = p[j1];
      j0 = j1;
    } while (j0 != 0);
  }
  int[] rowCol = new int[n];
  for (int j = 1; j <= n; j++) if (p[j] > 0) rowCol[p[j] - 1] = j - 1;
  return rowCol;
}

// Every frame: how much of the picture each palette colour covers in the masses in the palette's
// colours (for SCRAPE's strip, which shows it - a colour no mass is given has nothing to erase),
// worked out again when the masses or the palette change
String paletteUseFor = "";

void updatePaletteUse() {
  int[] pal = panel.paletteFinal();
  String key = massShown == null || pal.length == 0 ? "" : System.identityHashCode(massShown) + " "
    + java.util.Arrays.toString(lookShown) + " " + java.util.Arrays.toString(pal);
  if (key.equals(paletteUseFor)) return;
  paletteUseFor = key;
  if (key.equals("")) {
    panel.paletteUse = new float[0];
    return;
  }
  MassResult r = massShown;
  int[] choice = paletteMassChoice(r, pal);
  float[] use = new float[pal.length];
  for (int p : r.paintOf) use[choice[p]]++;
  for (int i = 0; i < use.length; i++) use[i] /= r.paintOf.length;
  panel.paletteUse = use;
}

// SCRAPE's ERASE A PALETTE COLOUR: everything on layer L where the masses in the palette's colours
// (VIEW's "masses (palette)", as SETUP 5 sets it - worked out here even if that's off) are palette
// colour number `colour` comes off, and its thickness with it
void erasePaletteColour(int L, int colour) {
  int[] pal = panel.paletteFinal();
  if (layers[L] == null) println("nothing painted yet - RUN first");
  else if (pal.length == 0) println("no palette yet - make one in SETUP 5");
  else if (colour < 0 || colour >= pal.length) println("choose a palette colour first (click one in the SCRAPE box)");
  else if (massShown == null) println("the masses aren't ready yet");
  else {
    MassResult r = massShown;
    int[] choice = paletteMassChoice(r, pal);
    PImage mask = createImage(r.w, r.h, ARGB);
    mask.loadPixels();
    int n = 0;
    for (int i = 0; i < r.paintOf.length; i++) {
      boolean off = choice[r.paintOf[i]] == colour;
      mask.pixels[i] = off ? 0xFFFFFFFF : 0;
      if (off) n++;
    }
    mask.updatePixels();
    if (n == 0) {
      println("palette colour " + (colour + 1) + " isn't given to any of the masses - nothing to erase"
        + " (the colours with a number in SCRAPE's strip are)");
      return;
    }
    if (mask.width != photo.width || mask.height != photo.height) mask.resize(photo.width, photo.height);
    eraseWith(layers[L], mask);
    eraseWith(heights[L], mask);          // the paint's thickness goes with it (Impasto)
    println("layer " + (L + 1) + ": erased where the masses are palette colour " + (colour + 1)
      + " (" + nf(100.0 * n / r.paintOf.length, 0, 1) + "% of the picture)");
  }
}

// CIE Lab (D65) back to an sRGB colour - toLab (the Masses tab) the other way
int fromLab(float L, float A, float B) {
  float fy = (L + 16) / 116, fx = fy + A / 500, fz = fy - B / 200;
  float x = labFInv(fx) * 0.95047, y = labFInv(fy), z = labFInv(fz) * 1.08883;
  float r = 3.2406 * x - 1.5372 * y - 0.4986 * z;
  float g = -0.9689 * x + 1.8758 * y + 0.0415 * z;
  float b = 0.0557 * x - 0.2040 * y + 1.0570 * z;
  return rgbOf(gamma8(r), gamma8(g), gamma8(b));
}
float labFInv(float t) { return t > 0.206893 ? t * t * t : (t - 16.0 / 116) / 7.787; }
int gamma8(float v) {
  v = constrain(v, 0, 1);
  v = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055;
  return round(v * 255);
}

// ---------------------------------------------------------------- pick up from: palette
// A tool's COLOUR "pick up from: palette": the colour of the masses (SETUP 2) where the paint is
// picked up, swapped for the palette colour that matches it best. "match by" is the order the
// palette's colours are compared in - brightness first, say: of the palette's colours, keep those
// whose brightness is nearest the masses' (within "how close counts as a match" of the nearest),
// of those keep the ones whose hue is nearest, and of those take the one whose saturation is.
// The bigger "how close", the more the later ones get a say.
// It's worked out once per paint of the masses, as a picture like the masses' own, and made again
// when the masses or the palette change.

final int PICK_PALETTE = 5;
String[] matchOrders = { "hue, saturation, brightness", "hue, brightness, saturation", "saturation, hue, brightness",
                         "saturation, brightness, hue", "brightness, hue, saturation", "brightness, saturation, hue" };
int[][] MATCH_ORDER = { { 0, 1, 2 }, { 0, 2, 1 }, { 1, 0, 2 }, { 1, 2, 0 }, { 2, 0, 1 }, { 2, 1, 0 } };
HashMap<Integer, PImage> paletteMatched = new HashMap<Integer, PImage>();   // by order and tolerance
String paletteMatchedFor = "";

// Every frame: forget the matched pictures if the masses or the palette have changed
void updatePaletteMatch() {
  String key = massShown == null ? "" : System.identityHashCode(massShown) + " " + java.util.Arrays.toString(lookShown)
    + " " + java.util.Arrays.toString(panel.paletteFinal());
  if (!key.equals(paletteMatchedFor)) {
    paletteMatchedFor = key;
    paletteMatched.clear();
  }
}

// the masses in the palette's colours, matched as the tool painting now asks (null if there are
// no masses yet). A tool picking up from the palette before SETUP 5 has made one makes one, as
// clicking SETUP 5 does - otherwise it would quietly paint the masses' colours, which look like
// the photo's
boolean paletteMassesWarned = false;

PImage paletteMatchedMasses() {
  if (massShown == null) {
    if (!paletteMassesWarned) println("palette: the masses aren't ready yet - using the photo's colours until they are");
    paletteMassesWarned = true;
    return null;
  }
  paletteMassesWarned = false;
  if (panel.paletteBase.length == 0) {
    panel.newPalette();
    println("palette: SETUP 5 hadn't made one yet - made one (open SETUP 5 to change it)");
  }
  int order = constrain((int) t("palOrder"), 0, MATCH_ORDER.length - 1);
  float tol = t("palTolerance");
  int key = order * 100000 + round(tol * 10000);
  PImage img = paletteMatched.get(key);
  if (img == null) {
    int[] pal = panel.paletteFinal();
    if (pal.length == 0) return null;
    int[] paints = adjustedPalette(massShown.rgb), mapped = new int[paints.length];
    float[][] ph = new float[pal.length][];
    for (int p = 0; p < pal.length; p++) ph[p] = hsbOf(pal[p]);
    for (int m = 0; m < paints.length; m++) mapped[m] = matchInPalette(hsbOf(paints[m]), pal, ph, MATCH_ORDER[order], tol);
    img = massesPicture(massShown, mapped);
    paletteMatched.put(key, img);
  }
  return img;
}

color paletteAt(float x, float y) {
  PImage m = paletteMatchedMasses();
  return m == null ? massesAt(x, y) : m.pixels[pixelIndex(x, y)];
}

float[] hsbOf(int c) {
  return java.awt.Color.RGBtoHSB(c >> 16 & 255, c >> 8 & 255, c & 255, null);
}

// the palette colour that best matches colour `h` (hue, saturation, brightness), comparing in
// `order`: after each comparison only the colours within `tol` of the nearest stay in
int matchInPalette(float[] h, int[] pal, float[][] ph, int[] order, float tol) {
  boolean[] in = new boolean[pal.length];
  java.util.Arrays.fill(in, true);
  int best = 0;
  for (int k = 0; k < 3; k++) {
    float nearest = Float.MAX_VALUE;
    float[] d = new float[pal.length];
    for (int p = 0; p < pal.length; p++) {
      if (!in[p]) continue;
      d[p] = hsbDistance(h, ph[p], order[k]);
      if (d[p] < nearest) { nearest = d[p]; best = p; }
    }
    if (k == 2) break;
    for (int p = 0; p < pal.length; p++) if (in[p] && d[p] > nearest + tol) in[p] = false;
  }
  return pal[best];
}

// how far apart two colours are in hue (0), saturation (1) or brightness (2), 0 .. 1. Hue goes
// round, and means little for greys: where either colour is nearly grey, its hue counts less and
// the distance moves to halfway
float hsbDistance(float[] a, float[] b, int ch) {
  if (ch == 1) return abs(a[1] - b[1]);
  if (ch == 2) return abs(a[2] - b[2]);
  float d = abs(a[0] - b[0]);
  d = min(d, 1 - d) * 2;
  float w = min(1, min(a[1], b[1]) * 4);
  return lerp(0.5, d, w);
}

// the palette as a picture, for SAVE: the 24 colours as they are now, 6 to a row
PImage palettePicture() {
  int[] pal = panel.paletteFinal();
  if (pal.length == 0) return null;
  int cell = 80, cols = 6, rows = (pal.length + cols - 1) / cols;
  PImage img = createImage(cols * cell, rows * cell, RGB);
  img.loadPixels();
  for (int y = 0; y < img.height; y++) {
    for (int x = 0; x < img.width; x++) {
      int i = (y / cell) * cols + x / cell;
      img.pixels[y * img.width + x] = i < pal.length ? pal[i] : 0xFF202020;
    }
  }
  img.updatePixels();
  return img;
}
