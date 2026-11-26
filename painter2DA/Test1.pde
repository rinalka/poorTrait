// Test1: the first TEST1's black line, kept to work on later - nothing uses it now. (TEST1 itself is
// gone: its two maps in levels became IN AREA's Zone - the Zone tab.)
//
// The very darkest parts of the light map (its creases: eyelids, nostrils, the mouth, the hair's curls)
// drawn as one black line, from each dark spot to the nearest one not drawn yet - or lifted between
// parts. Its settings were sliders in TEST1's box: test1_darkest (% of the light map, 0.5 .. 15, 4),
// test1_lineWidth (0.5 .. 8, 2.5) and test1_lift (a toggle, off); TEST1 drew it with
//   PGraphics d = createGraphics(photo.width, photo.height, JAVA2D);  d.beginDraw();  d.clear();  d.smooth();
//   test1Line(d, mask);  d.endDraw();
// then laid d.get() on the layer (cut to the area's mask with maskedMap, if there was one).

boolean test1Inside(PImage mask, float x, float y) {
  if (x < 0 || y < 0 || x >= photo.width || y >= photo.height) return false;
  return mask == null || (mask.pixels[pixelIndex(x, y)] >>> 24) >= 128;
}

// the light map's darkest share (in the area) as spots a few pixels apart along the middle of its creases,
// joined into one black line, each spot to the nearest not yet on it. Returns how many spots it went through
int test1Line(PGraphics d, PImage mask) {
  // how dark is dark enough: the level under which the darkest share of the light map lies
  int[] count = new int[256];
  int total = 0;
  float step = 3;
  for (float y = step / 2; y < photo.height; y += step) {
    for (float x = step / 2; x < photo.width; x += step) {
      if (!test1Inside(mask, x, y)) continue;
      count[constrain(round(mapAt(4, x, y) * 255), 0, 255)]++;
      total++;
    }
  }
  if (total == 0) return 0;
  int cut = 0;
  for (int sum = 0; cut < 255; cut++) {
    sum += count[cut];
    if (sum >= total * t("darkest") / 100) break;
  }
  // the spots (with fewer of them, farther apart, if there are very many)
  ArrayList<float[]> spots = new ArrayList<float[]>();
  for (float y = step / 2; y < photo.height; y += step) {
    for (float x = step / 2; x < photo.width; x += step) {
      if (!test1Inside(mask, x, y)) continue;
      float v = mapAt(4, x, y);
      if (v * 255 > cut) continue;
      // only along a crease's middle: darker than either side of it, across or down
      boolean across = v <= mapAt(4, x - 3, y) && v <= mapAt(4, x + 3, y);
      boolean down = v <= mapAt(4, x, y - 3) && v <= mapAt(4, x, y + 3);
      if (across || down) spots.add(new float[] { x + random(-0.7, 0.7), y + random(-0.7, 0.7) });
    }
  }
  while (spots.size() > 6000) {
    ArrayList<float[]> fewer = new ArrayList<float[]>();
    for (int i = 0; i < spots.size(); i += 2) fewer.add(spots.get(i));
    spots = fewer;
  }
  int n = spots.size();
  if (n < 2) return 0;
  float[] sx = new float[n], sy = new float[n];
  for (int i = 0; i < n; i++) {
    sx[i] = spots.get(i)[0];
    sy[i] = spots.get(i)[1];
  }
  // the path: from a spot at random, always to the nearest not yet visited
  int[] order = new int[n];
  boolean[] used = new boolean[n];
  int at = (int) random(n);
  for (int k = 0; k < n; k++) {
    order[k] = at;
    used[at] = true;
    int best = -1;
    float bd = Float.MAX_VALUE;
    for (int j = 0; j < n; j++) {
      if (used[j]) continue;
      float dd = sq(sx[j] - sx[at]) + sq(sy[j] - sy[at]);
      if (dd < bd) { bd = dd; best = j; }
    }
    if (best < 0) break;
    at = best;
  }
  // drawn as a smooth curve, each spot pulled a little towards its neighbours on the path
  boolean lift = t("lift") > 0.5;
  float jump = step * 4;
  d.noFill();
  d.stroke(0);
  d.strokeWeight(t("lineWidth"));
  d.strokeJoin(ROUND);
  d.strokeCap(ROUND);
  d.beginShape();
  for (int k = 0; k < n; k++) {
    int i = order[k], a = order[max(0, k - 1)], b = order[min(n - 1, k + 1)];
    if (lift && k > 0 && dist(sx[i], sy[i], sx[a], sy[a]) > jump) {
      d.curveVertex(sx[a], sy[a]);
      d.endShape();
      d.beginShape();
      a = i;
      d.curveVertex(sx[i], sy[i]);
    }
    if (k == 0) d.curveVertex(sx[i], sy[i]);
    boolean near = dist(sx[a], sy[a], sx[i], sy[i]) < jump && dist(sx[b], sy[b], sx[i], sy[i]) < jump;
    float x = near ? (sx[a] + 2 * sx[i] + sx[b]) / 4 : sx[i], y = near ? (sy[a] + 2 * sy[i] + sy[b]) / 4 : sy[i];
    d.curveVertex(x, y);
  }
  d.curveVertex(sx[order[n - 1]], sy[order[n - 1]]);
  d.endShape();
  return n;
}
