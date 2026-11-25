// Smoothing the lines between regions.
//
// Every pixel near a boundary takes a vote of the region labels around it, out to `radius` pixels,
// with nearer pixels counting more (a Gaussian weighting). Whichever region gets the most weight
// gets the pixel. Jagged, stair-stepped edges become smooth curves, thin spikes and narrow necks
// get rounded off, and at big radii small regions can vanish into their neighbours.
//
// Only pixels within `radius` of a boundary can change, so the rest are skipped.

int[] smoothLabels(int[] label, int w, int h, float radius) {
  if (radius < 0.5) return label;
  int n = w * h;
  int R = ceil(radius);
  float sigma = radius / 2;

  // the offsets in a disc of radius R and their weights
  ArrayList<int[]> offs = new ArrayList<int[]>();
  ArrayList<Float> wts = new ArrayList<Float>();
  for (int dy = -R; dy <= R; dy++) {
    for (int dx = -R; dx <= R; dx++) {
      if (dx * dx + dy * dy > radius * radius) continue;
      offs.add(new int[] { dx, dy });
      wts.add(exp(-(dx * dx + dy * dy) / (2 * sigma * sigma)));
    }
  }
  int m = offs.size();
  int[] ox = new int[m], oy = new int[m];
  float[] ow = new float[m];
  for (int k = 0; k < m; k++) { ox[k] = offs.get(k)[0]; oy[k] = offs.get(k)[1]; ow[k] = wts.get(k); }

  // how far each pixel is from a boundary (counting diagonal steps as 1), so far-away pixels can be skipped
  int[] dist = new int[n];
  int far = R + 1;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int i = y * w + x;
      boolean edge = (x > 0 && label[i - 1] != label[i]) || (x + 1 < w && label[i + 1] != label[i])
                  || (y > 0 && label[i - w] != label[i]) || (y + 1 < h && label[i + w] != label[i]);
      dist[i] = edge ? 0 : far;
    }
  }
  for (int y = 0; y < h; y++) {            // forward pass
    for (int x = 0; x < w; x++) {
      int i = y * w + x, d = dist[i];
      if (x > 0) d = min(d, dist[i - 1] + 1);
      if (y > 0) {
        d = min(d, dist[i - w] + 1);
        if (x > 0) d = min(d, dist[i - w - 1] + 1);
        if (x + 1 < w) d = min(d, dist[i - w + 1] + 1);
      }
      dist[i] = d;
    }
  }
  for (int y = h - 1; y >= 0; y--) {       // backward pass
    for (int x = w - 1; x >= 0; x--) {
      int i = y * w + x, d = dist[i];
      if (x + 1 < w) d = min(d, dist[i + 1] + 1);
      if (y + 1 < h) {
        d = min(d, dist[i + w] + 1);
        if (x + 1 < w) d = min(d, dist[i + w + 1] + 1);
        if (x > 0) d = min(d, dist[i + w - 1] + 1);
      }
      dist[i] = d;
    }
  }

  // the vote, for the pixels close enough to a boundary to change
  int[] out = label.clone();
  int[] candLabel = new int[m];
  float[] candWeight = new float[m];
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int i = y * w + x;
      if (dist[i] > R) continue;
      int cands = 0;
      for (int k = 0; k < m; k++) {
        int xx = x + ox[k], yy = y + oy[k];
        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
        int l = label[yy * w + xx];
        int c = 0;
        while (c < cands && candLabel[c] != l) c++;
        if (c == cands) { candLabel[c] = l; candWeight[c] = 0; cands++; }
        candWeight[c] += ow[k];
      }
      int best = label[i];
      float bestW = -1;
      for (int c = 0; c < cands; c++) {
        if (candWeight[c] > bestW) { bestW = candWeight[c]; best = candLabel[c]; }
      }
      out[i] = best;
    }
  }
  return out;
}

// how many different regions are left in a label map (smoothing can make small ones vanish)
int countRegions(int[] label) {
  java.util.HashSet<Integer> seen = new java.util.HashSet<Integer>();
  for (int l : label) seen.add(l);
  return seen.size();
}
