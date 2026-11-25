// Joining neighbouring blobs that are close in colour.
//
// Colour difference is measured in Lab, where distance roughly matches how different two colours
// look (a "delta E"): about 2 is barely noticeable, 10 is clearly different, 25+ is another colour.
//
// The closest touching pair is joined first, then the next closest, and so on until no touching
// pair is closer than the setting. After each join the bigger blob's colour is the average of all
// its pixels, and its differences from its neighbours are worked out again - so a chain of
// slightly-different neighbours can't creep across from one colour to a very different one.
//
// blobStats is worked out once per set of blobs; joinBlobs is fast enough to run while the
// slider is being dragged.

// per blob, from the SLIC labels: Lab sums and pixel count, and which blobs touch it
float[] statL, statA, statB;
int[] statN;
ArrayList<java.util.HashSet<Integer>> touching;

void blobStats(PImage img, int[] label, int count) {
  int w = img.width, h = img.height;
  statL = new float[count]; statA = new float[count]; statB = new float[count];
  statN = new int[count];
  touching = new ArrayList<java.util.HashSet<Integer>>();
  for (int b = 0; b < count; b++) touching.add(new java.util.HashSet<Integer>());

  float[] lab = new float[3];
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int i = y * w + x;
      int b = label[i];
      toLab(img.pixels[i], lab);
      statL[b] += lab[0]; statA[b] += lab[1]; statB[b] += lab[2];
      statN[b]++;
      // record the blobs to the right and below that are different
      if (x + 1 < w && label[i + 1] != b) { touching.get(b).add(label[i + 1]); touching.get(label[i + 1]).add(b); }
      if (y + 1 < h && label[i + w] != b) { touching.get(b).add(label[i + w]); touching.get(label[i + w]).add(b); }
    }
  }
}

// Joins neighbouring blobs closer than maxDiff. Returns the new label for every pixel
// (numbered 0 .. regions-1) and sets joinedCount.
int joinedCount;

int[] joinBlobs(int[] label, int count, float maxDiff) {
  // each blob starts as its own region; sums are copied so the stats stay as they were
  int[] parent = new int[count];
  float[] L = statL.clone(), A = statA.clone(), B = statB.clone();
  int[] N = statN.clone();
  ArrayList<java.util.HashSet<Integer>> nb = new ArrayList<java.util.HashSet<Integer>>();
  for (int b = 0; b < count; b++) {
    parent[b] = b;
    nb.add(new java.util.HashSet<Integer>(touching.get(b)));
  }

  // every touching pair, closest first. Entries are {difference, a, b}
  java.util.PriorityQueue<float[]> queue = new java.util.PriorityQueue<float[]>((p, q) -> Float.compare(p[0], q[0]));
  for (int a = 0; a < count; a++) {
    for (int b : nb.get(a)) {
      if (a < b) {
        float d = colourDiff(L, A, B, N, a, b);
        if (d <= maxDiff) queue.add(new float[] { d, a, b });
      }
    }
  }

  while (!queue.isEmpty()) {
    float[] e = queue.poll();
    int a = root(parent, (int) e[1]), b = root(parent, (int) e[2]);
    if (a == b) continue;                          // already joined
    float d = colourDiff(L, A, B, N, a, b);
    if (d > e[0] + 0.0001) {                       // their colours changed since this was queued
      if (d <= maxDiff) queue.add(new float[] { d, a, b });
      continue;
    }
    if (d > maxDiff) continue;

    // join the smaller into the bigger
    if (N[a] < N[b]) { int t = a; a = b; b = t; }
    parent[b] = a;
    L[a] += L[b]; A[a] += A[b]; B[a] += B[b]; N[a] += N[b];
    nb.get(a).addAll(nb.get(b));
    nb.get(b).clear();

    // the joined region's colour changed, so queue its neighbours again
    java.util.HashSet<Integer> fresh = new java.util.HashSet<Integer>();
    for (int n : nb.get(a)) {
      int r = root(parent, n);
      if (r != a) fresh.add(r);
    }
    nb.set(a, fresh);
    for (int r : fresh) {
      float dn = colourDiff(L, A, B, N, a, r);
      if (dn <= maxDiff) queue.add(new float[] { dn, a, r });
    }
  }

  // number the regions 0 .. joinedCount-1 and relabel the pixels
  int[] number = new int[count];
  java.util.Arrays.fill(number, -1);
  joinedCount = 0;
  for (int b = 0; b < count; b++) {
    int r = root(parent, b);
    if (number[r] < 0) number[r] = joinedCount++;
    number[b] = number[r];
  }
  int[] out = new int[label.length];
  for (int i = 0; i < label.length; i++) out[i] = number[label[i]];
  return out;
}

// which region a blob is in now (following the joins, and shortening the path as it goes)
int root(int[] parent, int b) {
  while (parent[b] != b) {
    parent[b] = parent[parent[b]];
    b = parent[b];
  }
  return b;
}

// how different two regions' average colours look (delta E in Lab)
float colourDiff(float[] L, float[] A, float[] B, int[] N, int a, int b) {
  float dl = L[a] / N[a] - L[b] / N[b];
  float da = A[a] / N[a] - A[b] / N[b];
  float db = B[a] / N[a] - B[b] / N[b];
  return sqrt(dl * dl + da * da + db * db);
}
