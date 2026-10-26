// Recolour: changing the colours of a painting, a few at a time - the panel's RECOLOUR box.
//
// READ COLOURS sums up the paint on the layers as it is now in 40 colours (k-means on a sample of
// the painted pixels of all four layers - not the canvas or backdrop under them), shown as
// numbered swatches in the panel. Click swatches to choose them, and the hue, saturation and
// brightness sliders change just those; choose others and change them, and so on. RANDOM NUDGE
// turns them all (or the chosen ones) a little, at random.
//
// The changes are made to each layer as the layers are combined (composite() draws each through
// recolouredLayer()), so nothing is changed for good: the painting can carry on, "on" switches it
// off to compare, and SAVE, PRINT and the mesh all show it. Every pixel moves by its nearest swatches'
// changes, the nearer ones counting more ("reach" is how near counts - small, and only colours
// very like a swatch move; bigger, and the changes blend smoothly into each other)
// (data/recolour.glsl). Tools that pick up wet paint pick up the recoloured colours.
//
// The swatches and what's been done to them are kept on the panel (Gui's recolourBase and
// recolourAdj), and saved with the settings.

final int RECOLOURS = 40;
PShader recolourShader;
boolean recolourWanted = false;     // READ COLOURS: make a palette at the next composite()
PGraphics[] recolouredLayers = new PGraphics[LAYERS];

// from composite(), before the layers are combined: a new palette if one was asked for
void recolourStep() {
  if (!recolourWanted) return;
  recolourWanted = false;
  makeRecolourPalette();
}

// whether the pass changes anything
boolean recolouring() {
  if (v("recolourOn") < 0.5) return false;
  float[][] adj = panel.recolourAdj;
  for (float[] a : adj) if (a[0] != 0 || a[1] != 1 || a[2] != 1) return true;
  return false;
}

// the paint on the layers summed up in RECOLOURS colours, greys first (dark to light), then
// round the hues. Pixels are picked at random from the layers that are showing, and kept if
// they're mostly paint; with hardly any paint yet, the combined canvas is used instead
void makeRecolourPalette() {
  ArrayList<int[]> from = new ArrayList<int[]>();
  for (int L = 0; L < LAYERS; L++) {
    if (v("layerOn" + L) < 0.5 || layers[L] == null) continue;
    layers[L].loadPixels();
    from.add(layers[L].pixels);
  }
  int want = 30000, samples = 0;
  float[][] px = new float[want][3];
  for (int tries = 0; tries < want * 8 && samples < want && from.size() > 0; tries++) {
    int[] pix = from.get((int) random(from.size()));
    int p = pix[(int) random(pix.length)], a = p >>> 24;
    if (a < 128) continue;
    // the layers are premultiplied: the colour is the paint's divided by how solid it is
    px[samples][0] = min(1, (p >> 16 & 255) / (float) a);
    px[samples][1] = min(1, (p >> 8 & 255) / (float) a);
    px[samples][2] = min(1, (p & 255) / (float) a);
    samples++;
  }
  if (samples < 500) {
    canvas.loadPixels();
    int n = canvas.pixels.length;
    for (samples = 0; samples < want; samples++) {
      int p = canvas.pixels[(int) random(n)];
      px[samples][0] = (p >> 16 & 255) / 255.0;
      px[samples][1] = (p >> 8 & 255) / 255.0;
      px[samples][2] = (p & 255) / 255.0;
    }
  }
  int k = RECOLOURS;
  float[][] centre = new float[k][];
  for (int j = 0; j < k; j++) centre[j] = px[(int) random(samples)].clone();
  int[] of = new int[samples];
  for (int round = 0; round < 15; round++) {
    float[][] sum = new float[k][3];
    int[] count = new int[k];
    for (int i = 0; i < samples; i++) {
      int best = 0;
      float bestD = Float.MAX_VALUE;
      for (int j = 0; j < k; j++) {
        float dr = px[i][0] - centre[j][0], dg = px[i][1] - centre[j][1], db = px[i][2] - centre[j][2];
        float d = dr * dr + dg * dg + db * db;
        if (d < bestD) { bestD = d; best = j; }
      }
      of[i] = best;
      count[best]++;
      for (int q = 0; q < 3; q++) sum[best][q] += px[i][q];
    }
    for (int j = 0; j < k; j++) {
      if (count[j] == 0) centre[j] = px[(int) random(samples)].clone();     // unused: start it again somewhere
      else for (int q = 0; q < 3; q++) centre[j][q] = sum[j][q] / count[j];
    }
  }
  Integer[] order = new Integer[k];
  final float[][] hsb = new float[k][];
  int[] rgb = new int[k];
  for (int j = 0; j < k; j++) {
    order[j] = j;
    rgb[j] = 0xFF000000 | round(centre[j][0] * 255) << 16 | round(centre[j][1] * 255) << 8 | round(centre[j][2] * 255);
    hsb[j] = java.awt.Color.RGBtoHSB(rgb[j] >> 16 & 255, rgb[j] >> 8 & 255, rgb[j] & 255, null);
  }
  java.util.Arrays.sort(order, new java.util.Comparator<Integer>() {
    public int compare(Integer a, Integer b) {
      float[] p = hsb[a], q = hsb[b];
      boolean ga = p[1] < 0.12, gb = q[1] < 0.12;
      if (ga != gb) return ga ? -1 : 1;
      if (ga || abs(p[0] - q[0]) < 0.02) return Float.compare(p[2], q[2]);
      return Float.compare(p[0], q[0]);
    }
  });
  int[] base = new int[k];
  for (int j = 0; j < k; j++) base[j] = rgb[order[j]];
  panel.newRecolourPalette(base);
  println("recolour: the layers' paint read as " + k + " colours");
}

// layer i with RECOLOUR's changes, drawn through the shader into a picture of its own (the layers
// are premultiplied - the shader allows for that)
PGraphics recolouredLayer(int i) {
  if (recolourShader == null) recolourShader = loadShader("recolour.glsl");
  int[] base = panel.recolourBase;
  float[][] adj = panel.recolourAdj;
  int k = min(base.length, adj.length);
  float[] pal = new float[RECOLOURS * 3], ch = new float[RECOLOURS * 3];
  for (int j = 0; j < k; j++) {
    pal[j * 3] = (base[j] >> 16 & 255) / 255.0;
    pal[j * 3 + 1] = (base[j] >> 8 & 255) / 255.0;
    pal[j * 3 + 2] = (base[j] & 255) / 255.0;
    ch[j * 3] = adj[j][0];
    ch[j * 3 + 1] = adj[j][1];
    ch[j * 3 + 2] = adj[j][2];
  }
  recolourShader.set("pal", pal, 3);
  recolourShader.set("adj", ch, 3);
  recolourShader.set("count", k);
  recolourShader.set("reach", v("recolourReach"));
  PGraphics r = recolouredLayers[i] = photoSized(recolouredLayers[i]);
  r.beginDraw();
  r.clear();
  r.shader(recolourShader);
  r.blendMode(REPLACE);
  r.image(layers[i], 0, 0);
  r.resetShader();
  r.blendMode(BLEND);
  r.endDraw();
  return r;
}

// a swatch's colour after its changes (for the panel; the same sums as the shader)
int recoloured(int c, float[] a) {
  float[] hsb = java.awt.Color.RGBtoHSB(c >> 16 & 255, c >> 8 & 255, c & 255, null);
  float h = hsb[0] + a[0] / 360.0;
  return java.awt.Color.HSBtoRGB(h - floor(h), constrain(hsb[1] * a[1], 0, 1), constrain(hsb[2] * a[2], 0, 1)) | 0xFF000000;
}
