// The paint-by-number palette, and a noise texture for each paint.
//
// After joining and smoothing, the regions' average colours are grouped into `paints` colours
// (k-means in Lab, where distance matches how different colours look, with big regions counting
// more). Every region takes its group's colour, so the picture uses at most 32 paints.
//
// Each paint also gets its own look - how big its texture's features are, how swirly, how much
// lighter / darker it varies, whether it's streaked in some direction, and a slight colour drift -
// picked at random from textureSeed (n picks new ones). The shader in data/paintNoise.glsl draws it.

int paints = 16;              // how many paints (2 .. 32)
final int MAX_PAINTS = 32;
int viewMode = 2;             // what the right-hand picture shows: 0 blobs, 1 flat paints, 2 paints with texture
String[] viewNames = { "blobs", "flat paints", "paints with texture" };
float textureSeed = 1;

int paintCount;               // how many paints were actually used (fewer if there are fewer regions)
int[] paintOfRegion;          // which paint each region got
int[] paintRGB;               // each paint's colour
PImage paintMap;              // every pixel's paint number, for the shader
PGraphics painted;            // the paint-by-number picture
PShader paintShader;

// group the regions' colours into the palette and paint the picture
void updatePaints() {
  makePalette();
  paintPicture();
}

void makePalette() {
  int[] label = smoothed;
  int n = label.length;
  int regions = 0;
  for (int l : label) regions = max(regions, l + 1);

  // each region's size, average colour (RGB) and the same in Lab
  long[][] rgb = new long[regions][3];
  int[] size = new int[regions];
  for (int i = 0; i < n; i++) {
    int c = original.pixels[i], r = label[i];
    rgb[r][0] += (c >> 16) & 0xFF; rgb[r][1] += (c >> 8) & 0xFF; rgb[r][2] += c & 0xFF;
    size[r]++;
  }
  IntList used = new IntList();   // regions that still have pixels
  float[][] lab = new float[regions][3];
  for (int r = 0; r < regions; r++) {
    if (size[r] == 0) continue;
    used.append(r);
    toLab(color(rgb[r][0] / size[r], rgb[r][1] / size[r], rgb[r][2] / size[r]), lab[r]);
  }
  int k = min(paints, used.size());

  // k-means: start from colours spread far apart (k-means++), then repeatedly give each region
  // the nearest paint and move each paint to the average of its regions
  java.util.Random rnd = new java.util.Random(12345);
  float[][] centre = new float[k][3];
  int first = used.get(rnd.nextInt(used.size()));
  centre[0] = lab[first].clone();
  for (int c = 1; c < k; c++) {
    // the next start is a region far from the starts so far, weighted by size
    double total = 0;
    double[] d = new double[used.size()];
    for (int u = 0; u < used.size(); u++) {
      int r = used.get(u);
      float best = Float.MAX_VALUE;
      for (int j = 0; j < c; j++) best = min(best, labDist2(lab[r], centre[j]));
      d[u] = best * size[r];
      total += d[u];
    }
    double pick = rnd.nextDouble() * total;
    int chosen = used.get(used.size() - 1);
    for (int u = 0; u < used.size(); u++) { pick -= d[u]; if (pick <= 0) { chosen = used.get(u); break; } }
    centre[c] = lab[chosen].clone();
  }

  paintOfRegion = new int[regions];
  for (int it = 0; it < 25; it++) {
    for (int u = 0; u < used.size(); u++) {
      int r = used.get(u), best = 0;
      float bestD = Float.MAX_VALUE;
      for (int c = 0; c < k; c++) {
        float dd = labDist2(lab[r], centre[c]);
        if (dd < bestD) { bestD = dd; best = c; }
      }
      paintOfRegion[r] = best;
    }
    double[][] sum = new double[k][4];
    for (int u = 0; u < used.size(); u++) {
      int r = used.get(u), c = paintOfRegion[r];
      for (int j = 0; j < 3; j++) sum[c][j] += lab[r][j] * size[r];
      sum[c][3] += size[r];
    }
    for (int c = 0; c < k; c++) if (sum[c][3] > 0) for (int j = 0; j < 3; j++) centre[c][j] = (float) (sum[c][j] / sum[c][3]);
  }

  // each paint's colour: the average of all the pixels it covers
  long[][] prgb = new long[k][4];
  for (int u = 0; u < used.size(); u++) {
    int r = used.get(u), c = paintOfRegion[r];
    for (int j = 0; j < 3; j++) prgb[c][j] += rgb[r][j];
    prgb[c][3] += size[r];
  }
  paintRGB = new int[k];
  for (int c = 0; c < k; c++) {
    long cnt = Math.max(1L, prgb[c][3]);
    paintRGB[c] = color(prgb[c][0] / cnt, prgb[c][1] / cnt, prgb[c][2] / cnt);
  }
  paintCount = k;

  // the paint map: each pixel's paint number in the red channel
  if (paintMap == null || paintMap.width != original.width || paintMap.height != original.height) {
    paintMap = createImage(original.width, original.height, RGB);
  }
  paintMap.loadPixels();
  for (int i = 0; i < n; i++) {
    int code = paintOfRegion[label[i]] * 8 + 4;
    paintMap.pixels[i] = 0xFF000000 | (code << 16);
  }
  paintMap.updatePixels();
}

float labDist2(float[] p, float[] q) {
  return sq(p[0] - q[0]) + sq(p[1] - q[1]) + sq(p[2] - q[2]);
}

// draw the paint-by-number picture through the shader, at the working copy's size so each pixel
// of the paint map lines up exactly with one pixel of the result
void paintPicture() {
  if (paintShader == null) paintShader = loadShader("paintNoise.glsl");
  if (painted == null || painted.width != original.width || painted.height != original.height) {
    painted = createGraphics(original.width, original.height, P2D);
  }

  float[] colours = new float[MAX_PAINTS * 3], look1 = new float[MAX_PAINTS * 4], look2 = new float[MAX_PAINTS * 4];
  for (int c = 0; c < MAX_PAINTS; c++) {
    int col = c < paintCount ? paintRGB[c] : color(0);
    colours[c * 3] = red(col) / 255; colours[c * 3 + 1] = green(col) / 255; colours[c * 3 + 2] = blue(col) / 255;

    // this paint's look, the same every time for the same textureSeed
    java.util.Random rnd = new java.util.Random((long) (textureSeed * 100000) + c * 7919L);
    float featurePx = exp(lerp(log(25), log(250), rnd.nextFloat()));   // 25 .. 250 pixels
    look1[c * 4]     = 1 / featurePx;                                     // scale
    look1[c * 4 + 1] = rnd.nextFloat() * 4.5;                             // warp
    look1[c * 4 + 2] = lerp(0.08, 0.35, rnd.nextFloat());                 // contrast
    look1[c * 4 + 3] = rnd.nextFloat() * 1000;                            // seed
    look2[c * 4]     = rnd.nextFloat() * PI;                              // stretch direction
    look2[c * 4 + 1] = rnd.nextFloat() < 0.5 ? 1 : lerp(1.5, 5, rnd.nextFloat());   // half the paints are streaky
    look2[c * 4 + 2] = lerp(0.35, 0.65, rnd.nextFloat());                 // persistence
    look2[c * 4 + 3] = rnd.nextFloat() * 0.2;                             // colour drift
  }
  paintShader.set("resolution", (float) original.width, (float) original.height);
  paintShader.set("paintColour", colours, 3);
  paintShader.set("look1", look1, 4);
  paintShader.set("look2", look2, 4);
  paintShader.set("textured", viewMode == 2 ? 1.0 : 0.0);

  painted.beginDraw();
  painted.shader(paintShader);
  painted.image(paintMap, 0, 0);
  painted.resetShader();
  painted.endDraw();
}
