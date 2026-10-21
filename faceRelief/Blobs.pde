// Blobs: the photo cut into blobs of a single colour, the same way blobsCompare does it, so they
// can go on the 3D model (press t until it says "blobs").
//
// slic, joinUp, fillBlobs and toLab below are copied unchanged from blobsCompare.pde, and the
// Join, Smooth and Paints tabs are copied unchanged from blobsCompare - so the blobs here are the
// same as there. The glue at the bottom (the blob settings, the sliders and blobTexture) is new.


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

// paint every blob its average colour, with black outlines where neighbouring blobs meet if asked
PImage fillBlobs(PImage img, int[] label, boolean withOutlines) {
  int w = img.width, h = img.height, n = w * h;
  int count = 0;                       // labels run 0 .. count-1
  for (int i = 0; i < n; i++) count = max(count, label[i] + 1);
  long[][] sum = new long[count][4];
  for (int i = 0; i < n; i++) {
    int c = img.pixels[i];
    long[] s = sum[label[i]];
    s[0] += (c >> 16) & 0xFF; s[1] += (c >> 8) & 0xFF; s[2] += c & 0xFF; s[3]++;
  }
  int[] colour = new int[count];
  for (int b = 0; b < count; b++) {
    long cnt = Math.max(1L, sum[b][3]);
    colour[b] = color(sum[b][0] / cnt, sum[b][1] / cnt, sum[b][2] / cnt);
  }

  PImage out = createImage(w, h, RGB);
  out.loadPixels();
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int i = y * w + x;
      boolean edge = withOutlines && ((x + 1 < w && label[i + 1] != label[i]) || (y + 1 < h && label[i + w] != label[i]));
      out.pixels[i] = edge ? color(0) : colour[label[i]];
    }
  }
  out.updatePixels();
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



// ---------------------------------------------------------------- glue for faceRelief

// ---- settings ----
int detectWidth = 1000;      // the blobs are worked out on a copy of the photo this wide
int blobsWanted = 1500;      // about how many blobs
float compactness = 10;      // low = blobs follow edges closely and wiggle, high = rounder and more even
int iterations = 10;         // how many times the blobs are refined
float joinBelow = 0;         // join touching blobs whose colours differ by less than this (0 = no joining)
float joinMax = 40;          // the slider's top end
float smoothRadius = 0;      // how far round each boundary pixel the smoothing looks, in pixels (0 = off)
float smoothMax = 16;        // the slider's top end
boolean outlines = false;

// ---- state ----
PImage original;             // the detection-sized copy of the photo
PImage blobbed;              // every blob its average colour
int[] labels, joined, smoothed;
int blobCount, regionsLeft, processMs, buildMs;
PImage blobTexture;          // what goes on the model: blobbed or the paints
boolean blobsStale = true;   // the face changed since the blobs were made
float blobSliderX, blobSliderW, blobSliderY0, blobSliderGap;
int blobDragging = -1;       // which blob slider is being dragged (-1 = none)
boolean blobPending = false; // a slider moved but the update has to wait until it's let go

// make the blobs for this photo, if they aren't made already
void makeBlobs(PImage photo) {
  if (!blobsStale) return;
  int t0 = millis();
  original = photo.copy();
  original.resize(detectWidth, 0);
  original.loadPixels();
  labels = slic(original, blobsWanted, compactness, iterations);
  blobStats(original, labels, blobCount);
  applyJoin();
  blobsStale = false;
  buildMs = millis() - t0;
  println("blobs: " + blobCount + " (asked for " + blobsWanted + ") in " + buildMs + " ms");
}

// join neighbours for the current setting and repaint - as in blobsCompare
void applyJoin() {
  int t0 = millis();
  joined = joinBlobs(labels, blobCount, joinBelow);
  smoothed = smoothLabels(joined, original.width, original.height, smoothRadius);
  regionsLeft = countRegions(smoothed);
  blobbed = fillBlobs(original, smoothed, outlines);
  updatePaints();
  processMs = millis() - t0;
  updateBlobTexture();
}

// pick the right blob picture and put it on the model
void updateBlobTexture() {
  blobTexture = viewMode == 0 || painted == null ? blobbed : painted.get();
  if (textureMode == BLOBS && textured != null) textured.setTexture(blobTexture);
}

// the four sliders, down the right-hand side
void drawBlobPanel() {
  blobSliderW = 440 * ui;
  blobSliderX = width - blobSliderW - 50 * ui;
  blobSliderY0 = 140 * ui;
  blobSliderGap = 70 * ui;
  String[] captions = {
    blobCount + " blobs     (about " + blobsWanted + " asked for - updates when you let go)",
    "join neighbours closer in colour than " + nf(joinBelow, 0, 2) + "     (" + regionsLeft + " regions)",
    "smooth edges over " + nf(smoothRadius, 0, 1) + " pixels" + (blobPending ? "  - updates when you let go" : ""),
    paints + " paints     showing: " + viewNames[viewMode] + "  (v)",
  };
  float[] f = {
    log(blobsWanted / 200.0) / log(30), sqrt(joinBelow / joinMax), smoothRadius / smoothMax, (paints - 2) / 30.0
  };
  for (int i = 0; i < 4; i++) {
    float y = blobSliderY0 + i * blobSliderGap;
    stroke(255, 90);
    strokeWeight(2 * ui);
    line(blobSliderX, y, blobSliderX + blobSliderW, y);
    noStroke();
    fill(70, 130, 200);
    circle(blobSliderX + blobSliderW * f[i], y, 18 * ui);
    fill(255, 200);
    textSize(13 * ui);
    textAlign(CENTER, TOP);
    text(captions[i], blobSliderX + blobSliderW / 2, y + 16 * ui);
  }
}

// true if the mouse went down on a blob slider (and starts dragging it)
boolean blobPanelPressed() {
  for (int i = 0; i < 4; i++) {
    float y = blobSliderY0 + i * blobSliderGap;
    if (abs(mouseY - y) < 20 * ui && mouseX > blobSliderX - 20 * ui && mouseX < blobSliderX + blobSliderW + 20 * ui) {
      blobDragging = i;
      blobSlideTo(mouseX);
      return true;
    }
  }
  return false;
}

// move the slider being dragged. Slow updates wait until the mouse is let go
void blobSlideTo(float mx) {
  float f = constrain((mx - blobSliderX) / blobSliderW, 0, 1);
  if (blobDragging == 0) {
    blobsWanted = round(200 * pow(30, f));        // 200 .. 6000, more room at the low end
    blobPending = true;                           // making blobs is always too slow to do live
  } else if (blobDragging == 1) {
    // squared, so the low end - where small changes matter most - gets more of the slider
    float v = round(f * f * joinMax * 4) / 4.0;   // steps of 0.25
    if (v == joinBelow) return;
    joinBelow = v;
    if (processMs > 150) blobPending = true; else applyJoin();
  } else if (blobDragging == 2) {
    float v = round(f * smoothMax * 2) / 2.0;     // steps of 0.5
    if (v == smoothRadius) return;
    smoothRadius = v;
    if (processMs > 150) blobPending = true; else applyJoin();
  } else if (blobDragging == 3) {
    int v = round(2 + f * 30);
    if (v != paints) { paints = v; updatePaints(); updateBlobTexture(); }
  }
}

void blobSliderReleased() {
  if (blobPending) {
    if (blobDragging == 0) { blobsStale = true; makeBlobs(textures[0]); }
    else applyJoin();
  }
  blobPending = false;
  blobDragging = -1;
}
