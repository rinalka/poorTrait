// The large colour masses (design doc Stage 2): the photo cut into blobs of a single colour and
// grouped into a few paints, exactly as blobsCompare does it.
//
// slic, joinUp and toLab below are copied unchanged from blobsCompare.pde, and the Join and
// Smooth tabs are copied unchanged from blobsCompare. makePalette is the Paints tab's, turned into
// a function, and paintNoise.glsl (in data) is the same shader.
//
// How the photo is cut into masses is part of SETUP, fixed for a run, so the masses can later be
// used like the other maps. Making them takes a few seconds, so it's done in a thread of its own,
// and starts again whenever a picture is chosen or one of SETUP's masses sliders changes (once
// it's been let go); RUN waits until they're made. Only the steps after the slider that changed
// are done again: changing the number of colours doesn't cut the blobs again. The palette's hue,
// saturation and brightness, and the texture, only change how the paints look, so they're
// instant and can change during a run.
//
// The masses can start the canvas (MASSES "start the canvas with"), be laid over it at any time
// (LAY ON NOW), and be where the brushes pick up their paint (COLOUR "pick up from: masses").

PImage massesImg;              // the masses as they look now, at the photo's size (null until made)
String massStatus = "masses: not made yet";

// what the worker thread hands over when it's done
class MassResult {
  String face;
  int w, h;                    // the size they were worked out at
  int[] regionOf;              // every pixel's mass (region) number
  int[] paintOf;               // every pixel's paint
  int[] rgb;                   // every paint's colour, the average of the photo where it's used
  int blobs, regions, ms;
}
volatile MassResult massResult;
volatile boolean massBusy = false;
float[] massAsked;             // the settings the newest masses were (or are being) made with
String massAskedFace;
MassResult massShown;          // what massesImg was made from
float[] lookShown;             // and how it was made to look
float textureSeed = 1;
PShader paintShader;
PGraphics massCanvas;          // where the shader paints them

// the settings that need the work done again, in the order the work is done
float[] massSettings() {
  return new float[] { v("massBlobs"), v("massRound"), v("massJoin"), v("massSmooth"), v("massPaints") };
}

// true until the masses for this picture and these settings are made and showing
boolean massesPending() {
  return massBusy || massesImg == null || massShown == null || !massShown.face.equals(faceName)
    || !java.util.Arrays.equals(massSettings(), massAsked);
}

// Every frame: start new masses if the settings or the picture changed (but not while a panel
// slider is still being dragged), and show finished ones.
void updateMasses() {
  float[] want = massSettings();
  boolean changed = massAsked == null || !java.util.Arrays.equals(want, massAsked) || !faceName.equals(massAskedFace);
  if (changed && !massBusy && !panel.mousePressed && !isRunning) {
    massAsked = want;
    massAskedFace = faceName;
    massBusy = true;
    massStatus = "masses: working ...";
    final PImage src = photo;
    final String face = faceName;
    new Thread(new Runnable() {
      public void run() {
        try {
          massResult = makeMasses(src, face, want);
        } catch (Exception e) {
          println("masses failed: " + e);
          e.printStackTrace();
        }
        massBusy = false;
      }
    }).start();
  }

  MassResult r = massResult;
  if (r == null || !r.face.equals(faceName)) return;
  float[] look = { v("massHue"), v("massSat"), v("massBri"), v("massTexture"), textureSeed };
  if (r != massShown || massesImg == null || !java.util.Arrays.equals(look, lookShown)) {
    renderMasses(r);
    massShown = r;
    lookShown = look;
    if (!massBusy) massStatus = "masses: " + r.blobs + " blobs, " + r.regions + " regions, " + r.rgb.length + " paints (" + r.ms + " ms)";
    if (outputMode > 0 && showNames[(int) v("showWhat")].equals("masses")) rebuildShape();
  }
}


// ---------------------------------------------------------------- the work (in its own thread)

// the worker's copies from last time, so it can start part way along
PImage mWork;
String mFace;
int[] mLabels, mSmoothed;
int mBlobCount, mRegions;
float[] mHave;

MassResult makeMasses(PImage src, String face, float[] s) {
  int t0 = millis();
  int from = 0;              // 0 = cut the blobs, 1 = join and smooth them, 2 = only the palette
  if (face.equals(mFace) && mHave != null) {
    if (s[0] == mHave[0] && s[1] == mHave[1]) from = (s[2] == mHave[2] && s[3] == mHave[3]) ? 2 : 1;
  } else {
    mFace = face;
    mWork = src.copy();
    if (mWork.width > 1024) mWork.resize(1024, 0);    // big photos are cut at this width
    mWork.loadPixels();
  }
  if (from <= 0) {
    mLabels = slic(mWork, round(s[0]), s[1], 10);
    mBlobCount = blobCount;
    blobStats(mWork, mLabels, mBlobCount);
  }
  if (from <= 1) {
    mSmoothed = smoothLabels(joinBlobs(mLabels, mBlobCount, s[2]), mWork.width, mWork.height, s[3]);
    mRegions = countRegions(mSmoothed);
  }
  MassResult r = makePalette(mWork, mSmoothed, round(s[4]));
  r.regionOf = mSmoothed;
  mHave = s.clone();
  r.face = face;
  r.blobs = mBlobCount;
  r.regions = mRegions;
  r.ms = millis() - t0;
  return r;
}

// Group the regions' colours into k paints (k-means in Lab, big regions counting more) - the
// Paints tab's makePalette
MassResult makePalette(PImage img, int[] label, int paints) {
  int n = label.length;
  int regions = 0;
  for (int l : label) regions = max(regions, l + 1);

  // each region's size, average colour (RGB) and the same in Lab
  long[][] rgb = new long[regions][3];
  int[] size = new int[regions];
  for (int i = 0; i < n; i++) {
    int c = img.pixels[i], r = label[i];
    rgb[r][0] += (c >> 16) & 0xFF; rgb[r][1] += (c >> 8) & 0xFF; rgb[r][2] += c & 0xFF;
    size[r]++;
  }
  IntList used = new IntList();   // regions that still have pixels
  float[][] lab = new float[regions][3];
  for (int r = 0; r < regions; r++) {
    if (size[r] == 0) continue;
    used.append(r);
    toLab(rgbOf(rgb[r][0] / size[r], rgb[r][1] / size[r], rgb[r][2] / size[r]), lab[r]);
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

  int[] paintOfRegion = new int[regions];
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
  MassResult res = new MassResult();
  res.rgb = new int[k];
  for (int c = 0; c < k; c++) {
    long cnt = Math.max(1L, prgb[c][3]);
    res.rgb[c] = rgbOf(prgb[c][0] / cnt, prgb[c][1] / cnt, prgb[c][2] / cnt);
  }
  res.w = img.width;
  res.h = img.height;
  res.paintOf = new int[n];
  for (int i = 0; i < n; i++) res.paintOf[i] = paintOfRegion[label[i]];
  return res;
}

// a colour from red, green and blue, without color() - that isn't safe outside this window's own
// thread, because it shares its working space with whatever this window is drawing
int rgbOf(long r, long g, long b) {
  return 0xFF000000 | (int) r << 16 | (int) g << 8 | (int) b;
}

float labDist2(float[] p, float[] q) {
  return sq(p[0] - q[0]) + sq(p[1] - q[1]) + sq(p[2] - q[2]);
}


// ---------------------------------------------------------------- how they look (this window)

// the palette with the panel's hue, saturation and brightness applied
int[] adjustedPalette(int[] rgb) {
  int[] out = new int[rgb.length];
  float dh = v("massHue"), ks = v("massSat"), kb = v("massBri");
  for (int c = 0; c < rgb.length; c++) {
    float[] hsb = java.awt.Color.RGBtoHSB(rgb[c] >> 16 & 255, rgb[c] >> 8 & 255, rgb[c] & 255, null);
    float h = hsb[0] + dh;
    out[c] = java.awt.Color.HSBtoRGB(h - floor(h), constrain(hsb[1] * ks, 0, 1), constrain(hsb[2] * kb, 0, 1)) | 0xFF000000;
  }
  return out;
}

void renderMasses(MassResult r) {
  int[] pal = adjustedPalette(r.rgb);
  PImage img;
  if (v("massTexture") > 0.5) {
    img = texturedMasses(r, pal);
  } else {
    img = createImage(r.w, r.h, RGB);
    img.loadPixels();
    for (int i = 0; i < r.paintOf.length; i++) img.pixels[i] = pal[r.paintOf[i]];
    img.updatePixels();
  }
  if (img.width != photo.width || img.height != photo.height) img.resize(photo.width, photo.height);
  img.loadPixels();
  massesImg = img;
}

// each paint with its own noise texture, through the Paints tab's shader
PImage texturedMasses(MassResult r, int[] pal) {
  if (paintShader == null) paintShader = loadShader("paintNoise.glsl");
  if (massCanvas == null || massCanvas.width != r.w || massCanvas.height != r.h) {
    massCanvas = createGraphics(r.w, r.h, P2D);
  }
  // the paint map: each pixel's paint number in the red channel
  PImage paintMap = createImage(r.w, r.h, RGB);
  paintMap.loadPixels();
  for (int i = 0; i < r.paintOf.length; i++) paintMap.pixels[i] = 0xFF000000 | ((r.paintOf[i] * 8 + 4) << 16);
  paintMap.updatePixels();

  int most = 32;
  float[] colours = new float[most * 3], look1 = new float[most * 4], look2 = new float[most * 4];
  for (int c = 0; c < most; c++) {
    int col = c < pal.length ? pal[c] : color(0);
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
  paintShader.set("resolution", (float) r.w, (float) r.h);
  paintShader.set("paintColour", colours, 3);
  paintShader.set("look1", look1, 4);
  paintShader.set("look2", look2, 4);
  paintShader.set("textured", 1.0);

  massCanvas.beginDraw();
  massCanvas.shader(paintShader);
  massCanvas.image(paintMap, 0, 0);
  massCanvas.resetShader();
  massCanvas.endDraw();
  return massCanvas.get();
}

color massesAt(float x, float y) {
  return massesImg == null ? photoAt(x, y) : massesImg.pixels[pixelIndex(x, y)];
}

// lay the masses over the canvas, as see-through as `opacity` says
void layMasses(float opacity) {
  if (canvas == null) return;
  if (massesImg == null) {
    println("the masses aren't ready yet");
    return;
  }
  canvas.beginDraw();
  canvas.tint(255, 255 * opacity);
  canvas.image(massesImg, 0, 0);
  canvas.noTint();
  canvas.endDraw();
}


// ---------------------------------------------------------------- slic (copied from blobsCompare)

// the number of blobs slic made (set by joinUp)
int blobCount;

// Returns a blob number for every pixel of img. About `wanted` blobs; compactness trades
// following the edges (low) against round, even blobs (high).
int[] slic(PImage img, int wanted, float compactness, int iterations) {
  int w = img.width, h = img.height, n = w * h;

  // colours in Lab, where distance matches how different colours look
  float[] L = new float[n], A = new float[n], B = new float[n];
  float[] lab = new float[3];
  for (int i = 0; i < n; i++) {
    toLab(img.pixels[i], lab);
    L[i] = lab[0]; A[i] = lab[1]; B[i] = lab[2];
  }

  // seeds on a grid S pixels apart, each nudged to the smoothest spot nearby so it doesn't start on an edge
  int S = max(2, round(sqrt((float) n / wanted)));
  ArrayList<float[]> seeds = new ArrayList<float[]>();   // l, a, b, x, y
  for (int y = S / 2; y < h; y += S) {
    for (int x = S / 2; x < w; x += S) {
      int bx = x, by = y;
      float best = Float.MAX_VALUE;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          int xx = x + dx, yy = y + dy;
          if (xx < 1 || yy < 1 || xx >= w - 1 || yy >= h - 1) continue;
          float g = sq(L[yy * w + xx + 1] - L[yy * w + xx - 1]) + sq(L[(yy + 1) * w + xx] - L[(yy - 1) * w + xx]);
          if (g < best) { best = g; bx = xx; by = yy; }
        }
      }
      int i = by * w + bx;
      seeds.add(new float[] { L[i], A[i], B[i], bx, by });
    }
  }
  int k = seeds.size();

  int[] label = new int[n];
  float[] dist = new float[n];
  float spatial = sq(compactness / S);   // how much a pixel of distance counts against a unit of colour difference

  for (int it = 0; it < iterations; it++) {
    java.util.Arrays.fill(dist, Float.MAX_VALUE);
    // each seed claims the pixels within 2S x 2S of it that are closer to it than to any other seed
    for (int c = 0; c < k; c++) {
      float[] s = seeds.get(c);
      int x0 = max(0, (int) (s[3] - S)), x1 = min(w, (int) (s[3] + S) + 1);
      int y0 = max(0, (int) (s[4] - S)), y1 = min(h, (int) (s[4] + S) + 1);
      for (int y = y0; y < y1; y++) {
        for (int x = x0; x < x1; x++) {
          int i = y * w + x;
          float d = sq(L[i] - s[0]) + sq(A[i] - s[1]) + sq(B[i] - s[2])
                  + (sq(x - s[3]) + sq(y - s[4])) * spatial;
          if (d < dist[i]) { dist[i] = d; label[i] = c; }
        }
      }
    }
    // move each seed to the middle (and average colour) of what it claimed
    float[][] sum = new float[k][6];
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int i = y * w + x;
        float[] t = sum[label[i]];
        t[0] += L[i]; t[1] += A[i]; t[2] += B[i]; t[3] += x; t[4] += y; t[5]++;
      }
    }
    for (int c = 0; c < k; c++) {
      float cnt = sum[c][5];
      if (cnt == 0) continue;
      float[] s = seeds.get(c);
      for (int j = 0; j < 5; j++) s[j] = sum[c][j] / cnt;
    }
  }

  return joinUp(label, w, h, S * S / 4);
}

// A blob can end up in several unconnected pieces. Give each connected piece its own number, and
// fold pieces smaller than minSize into the blob next to them.
int[] joinUp(int[] label, int w, int h, int minSize) {
  int n = w * h;
  int[] out = new int[n];
  java.util.Arrays.fill(out, -1);
  int[] queue = new int[n];
  int[] dx = { -1, 1, 0, 0 }, dy = { 0, 0, -1, 1 };
  int next = 0;

  for (int start = 0; start < n; start++) {
    if (out[start] >= 0) continue;
    // a neighbour that's already numbered - small pieces join it
    int adjacent = -1;
    int sx = start % w, sy = start / w;
    for (int d = 0; d < 4; d++) {
      int xx = sx + dx[d], yy = sy + dy[d];
      if (xx >= 0 && yy >= 0 && xx < w && yy < h && out[yy * w + xx] >= 0) adjacent = out[yy * w + xx];
    }
    // flood fill the piece
    int head = 0, tail = 0;
    queue[tail++] = start;
    out[start] = next;
    while (head < tail) {
      int i = queue[head++];
      int x = i % w, y = i / w;
      for (int d = 0; d < 4; d++) {
        int xx = x + dx[d], yy = y + dy[d];
        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
        int j = yy * w + xx;
        if (out[j] < 0 && label[j] == label[start]) { out[j] = next; queue[tail++] = j; }
      }
    }
    if (tail < minSize && adjacent >= 0) {
      for (int q = 0; q < tail; q++) out[queue[q]] = adjacent;
    } else {
      next++;
    }
  }
  blobCount = next;
  return out;
}

// sRGB colour to CIE Lab (D65)
void toLab(int c, float[] lab) {
  float r = lin(((c >> 16) & 0xFF) / 255.0), g = lin(((c >> 8) & 0xFF) / 255.0), b = lin((c & 0xFF) / 255.0);
  float x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047;
  float y = (r * 0.2126 + g * 0.7152 + b * 0.0722);
  float z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883;
  x = labF(x); y = labF(y); z = labF(z);
  lab[0] = 116 * y - 16;
  lab[1] = 500 * (x - y);
  lab[2] = 200 * (y - z);
}
float lin(float v)  { return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4); }
float labF(float t) { return t > 0.008856 ? pow(t, 1.0 / 3) : 7.787 * t + 16.0 / 116; }
