// Outline: the face drawn in line, part by part - the panel's OUTLINE box.
//
// The line is planned once for the picture, from what the map maker found:
//   silhouette      the edge of the whole figure - hair, ears, neck and shoulders (parts.png,
//                   wherever it isn't background), leaving out where it runs off the picture
//   hairline        where the hair meets the face (the edge of the hair in parts.png, only where
//                   it's next to skin)
//   neck & clothes  where the clothes meet the neck and skin
//   face, brows, eyes (with the irises), nose, mouth
//                   the face landmarks' outlines (landmarks.json)
// Each part is smoothed ("smoothness"), and they're drawn in order: from the end of one part the
// pen lifts and goes down again on the nearest part not drawn yet. With "one unbroken line" it
// doesn't lift: it sweeps round to the next part in a curve, the way a one-line drawing travels
// from feature to feature.
//
// Then the pen goes along the line, "speed" pixels a frame, with the hand's wobble and pressure.
// "passes" goes round the whole line again, a little off, like going over a drawing; "start
// again when done" keeps it going for ever. A change to the parts or smoothness plans the line
// again and starts over. The colour comes from COLOUR, picked once for each pass, or is COLOUR's
// "one colour". ABSTRACTION doesn't lift this pen - the outline is the face.

float[] outlineX, outlineY;        // every part's line, one after another, a point every 2 pixels
int[] outlineFirst, outlineLast;   // for each point, the first and last points of its part
String outlineFor = "";            // which picture and settings it was planned for
float outlineAt = 0;               // how far along the pen is (points)
int outlinePass = 0;
float outlineSeed, outlineAlpha, outlineOffX, outlineOffY;
color outlineColour;
boolean outlineDown = false;
boolean outlineRestart = true;     // CLEAR and RUN start the pen again from the beginning
float opax, opay, opbx, opby;
final float OUTLINE_STEP = 2;

String[] outlineParts = { "sil", "hair", "clothes", "face", "brows", "eyes", "nose", "mouth" };

void resetOutline() {
  outlineAt = 0;
  outlinePass = 0;
  outlineDown = false;
  outlineNewPass();
}

void paintOutline(PGraphics g) {
  String key = faceName + " " + nf(t("smooth"), 0, 2) + " " + t("join");
  for (String p : outlineParts) key += t(p) > 0.5 ? "1" : "0";
  if (!key.equals(outlineFor)) {
    outlineFor = key;
    planOutline();
    outlineRestart = true;
  }
  if (outlineRestart) {
    outlineRestart = false;
    resetOutline();
  }
  if (outlineX == null || outlineX.length < 2) return;
  if (t("one") > 0.5) outlineColour = panel.colour("outline_ink");
  if (outlinePass >= (int) t("passes")) {
    if (t("loop") < 0.5) return;            // finished
    resetOutline();
  }
  g.noStroke();
  g.beginShape(TRIANGLES);
  int steps = max(1, round(t("speed") / OUTLINE_STEP));
  for (int s = 0; s < steps; s++) {
    if (!outlineStep(g)) {
      outlinePass++;
      outlineAt = 0;
      outlineDown = false;
      if (outlinePass >= (int) t("passes")) break;
      outlineNewPass();
    }
  }
  g.endShape();
}

// a new pass: a new wobble, a little off the last, and the colour where the line starts
void outlineNewPass() {
  outlineSeed = random(1000);
  float off = outlinePass == 0 ? 0 : 1.5 + 3 * t("wobble");
  outlineOffX = randomGaussian() * off;
  outlineOffY = randomGaussian() * off;
  if (outlineX != null && outlineX.length > 0) {
    outlineColour = t("one") > 0.5 ? panel.colour("outline_ink") : systemColour(outlineX[0], outlineY[0]);
    outlineAlpha = toolAlpha(outlineX[0], outlineY[0]);
  }
}

// one step of the pen; false once it's got to the end of the line
boolean outlineStep(PGraphics g) {
  int n = outlineX.length;
  int i = (int) outlineAt;
  if (i >= n - 1) return false;
  outlineAt += 1;
  float x = outlineX[i], y = outlineY[i];
  int first = outlineFirst[i], last = outlineLast[i];
  int j = i < last ? i + 1 : max(first, i - 1);              // the way the line goes here
  float dx = (outlineX[j] - x) * (j > i ? 1 : -1), dy = (outlineY[j] - y) * (j > i ? 1 : -1);
  float d = max(0.001, sqrt(dx * dx + dy * dy));
  float nx = -dy / d, ny = dx / d;
  // the hand: wandering a little off the line, pressing harder and lighter
  float wob = t("wobble") * 7 * (noise(outlineSeed, i * 0.012) - 0.5) * 2;
  x += nx * wob + outlineOffX;
  y += ny * wob + outlineOffY;
  float press = lerp(1, 0.3 + 1.1 * noise(outlineSeed + 50, i * 0.008), t("pressure"));
  float ends = min(1, min(i - first, last - i) / 10.0 + 0.2);
  float half = max(0.3, t("width") / 2 * press * ends);
  float ax = x + nx * half, ay = y + ny * half, bx = x - nx * half, by = y - ny * half;
  if (outlineDown) {
    g.fill(outlineColour, outlineAlpha);
    g.vertex(opax, opay); g.vertex(opbx, opby); g.vertex(ax, ay);
    g.vertex(opbx, opby); g.vertex(bx, by); g.vertex(ax, ay);
    markCount++;
  }
  outlineDown = i < last;                  // at the end of a part the pen lifts
  opax = ax; opay = ay; opbx = bx; opby = by;
  return true;
}


// ---------------------------------------------------------------- planning the line

// one part of the drawing: a line of points, open or going round
class OutlinePart {
  FloatList x = new FloatList(), y = new FloatList();
  boolean closed;
  int size() { return x.size(); }
}

void planOutline() {
  ArrayList<OutlinePart> parts = new ArrayList<OutlinePart>();
  String dir = mapsPath() + "/" + faceName + "/";
  int w = photo.width, h = photo.height;

  // the parts picture: the silhouette, the hairline, the neck of the clothes
  if (new java.io.File(dir + "parts.png").exists() && (t("sil") > 0.5 || t("hair") > 0.5 || t("clothes") > 0.5)) {
    PImage pi = loadImage(dir + "parts.png");
    if (pi.width != w || pi.height != h) pi.resize(w, h);
    pi.loadPixels();
    int[] part = new int[w * h];
    for (int i = 0; i < w * h; i++) part[i] = pi.pixels[i] >> 16 & 255;
    boolean[] figure = new boolean[w * h], hair = new boolean[w * h], skin = new boolean[w * h], cloth = new boolean[w * h];
    for (int i = 0; i < w * h; i++) {
      int p = part[i];
      figure[i] = p != 0;
      hair[i] = p == 13 || p == 14;
      skin[i] = p == 1 || p == 6 || p == 7 || p == 8 || p == 9 || p == 17;
      cloth[i] = p == 18 || p == 16;
    }
    if (t("sil") > 0.5) parts.addAll(edgeOf(figure, null, w, h));
    if (t("hair") > 0.5) parts.addAll(edgeOf(hair, skin, w, h));
    if (t("clothes") > 0.5) parts.addAll(edgeOf(cloth, skin, w, h));
  }

  // the landmarks' outlines
  if (new java.io.File(dir + "landmarks.json").exists()) {
    JSONObject lm = loadJSONObject(dir + "landmarks.json");
    JSONArray faces = lm.getJSONArray("faces");
    if (faces.size() > 0) {
      JSONArray pts = faces.getJSONArray(0);
      float sx = w / lm.getFloat("width"), sy = h / lm.getFloat("height");
      float[] px = new float[pts.size()], py = new float[pts.size()];
      for (int i = 0; i < pts.size(); i++) {
        px[i] = pts.getJSONArray(i).getFloat(0) * sx;
        py[i] = pts.getJSONArray(i).getFloat(1) * sy;
      }
      JSONObject groups = lm.getJSONObject("groups");
      String[][] wanted = {
        { "face", "face_oval" }, { "brows", "left_eyebrow", "right_eyebrow" },
        { "eyes", "left_eye", "right_eye", "left_iris", "right_iris" }, { "nose", "nose" }, { "mouth", "lips" } };
      for (String[] wnt : wanted) {
        if (t(wnt[0]) < 0.5) continue;
        for (int k = 1; k < wnt.length; k++) {
          if (!groups.hasKey(wnt[k])) continue;
          ArrayList<OutlinePart> found = chains(groups.getJSONArray(wnt[k]), px, py);
          if (wnt[k].endsWith("iris")) for (OutlinePart p : found) drawnCircle(p);
          parts.addAll(found);
        }
      }
    }
  }

  // smooth each part, then join them into one line
  ArrayList<OutlinePart> smooth = new ArrayList<OutlinePart>();
  for (OutlinePart p : parts) {
    OutlinePart s = smoothPart(p);
    if (s.size() >= 3) smooth.add(s);
  }
  int count = smooth.size();
  ArrayList<FloatList[]> strokes = new ArrayList<FloatList[]>();
  joinParts(smooth, strokes, t("join") > 0.5);
  FloatList lx = new FloatList(), ly = new FloatList();
  IntList firsts = new IntList(), lasts = new IntList();
  for (FloatList[] st : strokes) {
    resampleInto(st[0], st[1], OUTLINE_STEP);
    int a = lx.size(), b = a + st[0].size() - 1;
    for (int q = a; q <= b; q++) { firsts.append(a); lasts.append(b); }
    lx.append(st[0].array());
    ly.append(st[1].array());
  }
  outlineX = lx.array();
  outlineY = ly.array();
  outlineFirst = firsts.array();
  outlineLast = lasts.array();
  println("outline: " + count + " parts, " + round(outlineX.length * OUTLINE_STEP) + " pixels of line");
}

// an iris has only four points - a circle through them, drawn by hand: a little squashed and
// lumpy, starting anywhere, and going on past where it started, a little inside it
void drawnCircle(OutlinePart p) {
  float cx = 0, cy = 0, r = 0;
  int n = p.size();
  for (int i = 0; i < n; i++) { cx += p.x.get(i) / n; cy += p.y.get(i) / n; }
  for (int i = 0; i < n; i++) r += dist(cx, cy, p.x.get(i), p.y.get(i)) / n;
  p.x.clear();
  p.y.clear();
  float rx = r * random(0.88, 1.06), ry = r * random(0.88, 1.06), tilt = random(TWO_PI);
  float start = random(TWO_PI), sweep = TWO_PI * random(1.08, 1.25), seed = random(100);
  int k = 24;
  for (int i = 0; i <= k; i++) {
    float u = i / (float) k, a = start + sweep * u;
    float lump = 1 + 0.12 * (noise(seed, u * 3) - 0.5) - 0.1 * u;
    float ex = cos(a) * rx * lump, ey = sin(a) * ry * lump;
    p.x.append(cx + ex * cos(tilt) - ey * sin(tilt));
    p.y.append(cy + ex * sin(tilt) + ey * cos(tilt));
  }
  p.closed = false;
}

// the landmark pairs of a group as lines: each run of joined-up points, and the loops
ArrayList<OutlinePart> chains(JSONArray edges, float[] px, float[] py) {
  HashMap<Integer, IntList> next = new HashMap<Integer, IntList>();
  for (int i = 0; i < edges.size(); i++) {
    int a = edges.getJSONArray(i).getInt(0), b = edges.getJSONArray(i).getInt(1);
    if (!next.containsKey(a)) next.put(a, new IntList());
    if (!next.containsKey(b)) next.put(b, new IntList());
    next.get(a).append(b);
    next.get(b).append(a);
  }
  java.util.HashSet<String> used = new java.util.HashSet<String>();
  ArrayList<OutlinePart> out = new ArrayList<OutlinePart>();
  // the open runs first (from the ends), then whatever's left goes round
  for (int pass = 0; pass < 2; pass++) {
    for (int start : next.keySet()) {
      if (pass == 0 && next.get(start).size() == 2) continue;
      for (int first : next.get(start)) {
        if (used.contains(min(start, first) + " " + max(start, first))) continue;
        OutlinePart p = new OutlinePart();
        int prev = start, cur = first;
        p.x.append(px[start]);
        p.y.append(py[start]);
        used.add(min(prev, cur) + " " + max(prev, cur));
        while (true) {
          p.x.append(px[cur]);
          p.y.append(py[cur]);
          if (cur == start) { p.closed = true; break; }
          int go = -1;
          for (int nb : next.get(cur)) {
            if (!used.contains(min(cur, nb) + " " + max(cur, nb))) { go = nb; break; }
          }
          if (go < 0) break;
          used.add(min(cur, go) + " " + max(cur, go));
          prev = cur;
          cur = go;
        }
        if (p.closed) { p.x.remove(p.size() - 1); p.y.remove(p.size() - 1); }
        if (p.size() >= 2) out.add(p);
      }
    }
  }
  return out;
}

// the edge of the region `in` (marching squares on a grid of 3 pixel cells), as lines. With
// `near`, only the stretches next to that region are kept; the edge of the picture never is
final int OUTLINE_CELL = 3;

ArrayList<OutlinePart> edgeOf(boolean[] in, boolean[] near, int w, int h) {
  int c = OUTLINE_CELL, gw = w / c + 2, gh = h / c + 2;
  // how much of each cell is inside, with an empty ring round the outside so every edge closes
  float[] f = new float[gw * gh];
  for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
    if (!in[x + y * w]) continue;
    int i = x / c + 1, j = y / c + 1;
    if (i < gw - 1 && j < gh - 1) f[i + j * gw] += 1.0 / (c * c);
  }
  boxBlur(f, gw, gh, 1, true);
  boxBlur(f, gw, gh, 1, false);
  for (int i = 0; i < gw; i++) { f[i] = 0; f[i + (gh - 1) * gw] = 0; }
  for (int j = 0; j < gh; j++) { f[j * gw] = 0; f[gw - 1 + j * gw] = 0; }
  // the region `near` grown by a few pixels, to test against
  boolean[] nearBy = null;
  if (near != null) {
    float[] nf = new float[gw * gh];
    for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
      if (near[x + y * w]) nf[min(gw - 1, x / c + 1) + min(gh - 1, y / c + 1) * gw] = 1;
    }
    boxBlur(nf, gw, gh, 3, true);
    boxBlur(nf, gw, gh, 3, false);
    nearBy = new boolean[gw * gh];
    for (int i = 0; i < gw * gh; i++) nearBy[i] = nf[i] > 0.01;
  }

  // marching squares: each crossing is on a grid edge, numbered so the cells either side meet
  // there; each cell joins up two or four of them
  HashMap<Integer, IntList> link = new HashMap<Integer, IntList>();
  HashMap<Integer, float[]> where = new HashMap<Integer, float[]>();
  for (int j = 0; j < gh - 1; j++) for (int i = 0; i < gw - 1; i++) {
    float a = f[i + j * gw], b = f[i + 1 + j * gw], d = f[i + (j + 1) * gw], e = f[i + 1 + (j + 1) * gw];
    int k = (a > 0.5 ? 1 : 0) | (b > 0.5 ? 2 : 0) | (e > 0.5 ? 4 : 0) | (d > 0.5 ? 8 : 0);
    if (k == 0 || k == 15) continue;
    // the four sides: top (a-b), right (b-e), bottom (d-e), left (a-d)
    int top = (i + j * gw) * 2, left = (i + j * gw) * 2 + 1;
    int bottom = (i + (j + 1) * gw) * 2, right = (i + 1 + j * gw) * 2 + 1;
    crossing(where, top, i, j, a, b, true);
    crossing(where, bottom, i, j + 1, d, e, true);
    crossing(where, left, i, j, a, d, false);
    crossing(where, right, i + 1, j, b, e, false);
    int[][] segs;
    switch (k) {
      case 1: case 14: segs = new int[][] { { left, top } }; break;
      case 2: case 13: segs = new int[][] { { top, right } }; break;
      case 3: case 12: segs = new int[][] { { left, right } }; break;
      case 4: case 11: segs = new int[][] { { right, bottom } }; break;
      case 6: case 9:  segs = new int[][] { { top, bottom } }; break;
      case 7: case 8:  segs = new int[][] { { left, bottom } }; break;
      case 5:  segs = new int[][] { { left, top }, { right, bottom } }; break;
      default: segs = new int[][] { { top, right }, { left, bottom } }; break;    // 10
    }
    for (int[] s : segs) {
      if (!link.containsKey(s[0])) link.put(s[0], new IntList());
      if (!link.containsKey(s[1])) link.put(s[1], new IntList());
      link.get(s[0]).append(s[1]);
      link.get(s[1]).append(s[0]);
    }
  }

  // follow the crossings round into loops, then cut out the stretches that don't count
  ArrayList<OutlinePart> out = new ArrayList<OutlinePart>();
  java.util.HashSet<Integer> seen = new java.util.HashSet<Integer>();
  for (int start : link.keySet()) {
    if (seen.contains(start)) continue;
    IntList loop = new IntList();
    int prev = -1, cur = start;
    while (cur >= 0 && !seen.contains(cur)) {
      seen.add(cur);
      loop.append(cur);
      int go = -1;
      for (int nb : link.get(cur)) if (nb != prev && !seen.contains(nb)) { go = nb; break; }
      prev = cur;
      cur = go;
    }
    if (loop.size() * c < 60) continue;            // specks
    // which points count, and the loop turned so it starts on one that doesn't (if any does)
    int n = loop.size();
    boolean[] keep = new boolean[n];
    int off = -1;
    for (int q = 0; q < n; q++) {
      float[] p = where.get(loop.get(q));
      int gi = constrain(round(p[0] / c) + 1, 0, gw - 1), gj = constrain(round(p[1] / c) + 1, 0, gh - 1);
      boolean edge = p[0] < 4 || p[1] < 4 || p[0] > w - 5 || p[1] > h - 5;
      keep[q] = !edge && (nearBy == null || nearBy[gi + gj * gw]);
      if (!keep[q] && off < 0) off = q;
    }
    if (off < 0) {                                  // all of it: a loop
      OutlinePart part = new OutlinePart();
      part.closed = true;
      for (int q = 0; q < n; q++) { float[] p = where.get(loop.get(q)); part.x.append(p[0]); part.y.append(p[1]); }
      out.add(part);
      continue;
    }
    OutlinePart part = null;
    for (int s = 1; s <= n; s++) {
      int q = (off + s) % n;
      if (keep[q]) {
        if (part == null) part = new OutlinePart();
        float[] p = where.get(loop.get(q));
        part.x.append(p[0]);
        part.y.append(p[1]);
      } else if (part != null) {
        if (part.size() * c >= 40) out.add(part);
        part = null;
      }
    }
    if (part != null && part.size() * c >= 40) out.add(part);
  }
  return out;
}

// where the edge crosses the grid edge between points (i, j) and the next one along (or down),
// in pixels
void crossing(HashMap<Integer, float[]> where, int id, int i, int j, float a, float b, boolean along) {
  if (where.containsKey(id) || (a > 0.5) == (b > 0.5)) return;
  float s = constrain((0.5 - a) / (b - a), 0, 1);
  float gx = i + (along ? s : 0), gy = j + (along ? 0 : s);
  where.put(id, new float[] { (gx - 1 + 0.5) * OUTLINE_CELL, (gy - 1 + 0.5) * OUTLINE_CELL });
}

// a part made into a smooth curve: a point every 3 pixels (a Catmull-Rom curve through its
// points), then averaged along as much as "smoothness" says - less for small parts like eyes
OutlinePart smoothPart(OutlinePart p) {
  OutlinePart d = new OutlinePart();
  d.closed = p.closed;
  int n = p.size();
  int segs = p.closed ? n : n - 1;
  for (int s = 0; s < segs; s++) {
    int i0 = p.closed ? (s - 1 + n) % n : max(0, s - 1), i1 = s, i2 = (s + 1) % n, i3 = p.closed ? (s + 2) % n : min(n - 1, s + 2);
    float len = dist(p.x.get(i1), p.y.get(i1), p.x.get(i2), p.y.get(i2));
    int k = max(1, ceil(len / 3));
    for (int q = 0; q < k; q++) {
      float u = q / (float) k;
      d.x.append(curvePoint(p.x.get(i0), p.x.get(i1), p.x.get(i2), p.x.get(i3), u));
      d.y.append(curvePoint(p.y.get(i0), p.y.get(i1), p.y.get(i2), p.y.get(i3), u));
    }
  }
  if (!p.closed) { d.x.append(p.x.get(n - 1)); d.y.append(p.y.get(n - 1)); }
  int m = d.size();
  int r = round(t("smooth") * min(8, m / 12.0));
  if (r < 1 || m < 5) return d;
  OutlinePart a = new OutlinePart();
  a.closed = d.closed;
  for (int i = 0; i < m; i++) {
    float sx = 0, sy = 0;
    int cnt = 0;
    for (int o = -r; o <= r; o++) {
      int q = i + o;
      if (d.closed) q = (q % m + m) % m;
      else if (q < 0 || q >= m) continue;
      sx += d.x.get(q);
      sy += d.y.get(q);
      cnt++;
    }
    a.x.append(sx / cnt);
    a.y.append(sy / cnt);
  }
  return a;
}

// the parts in the order they're drawn: start with the longest (from its lower end), then on to
// whichever part is nearest the end so far. A loop is gone all the way round, from its nearest
// point. Each part is a line of its own in `strokes` - or, with `join`, they're all one line,
// joined by curves that leave the way the line was going and arrive the way the next part sets off
void joinParts(ArrayList<OutlinePart> parts, ArrayList<FloatList[]> strokes, boolean join) {
  if (parts.isEmpty()) return;
  FloatList lx = new FloatList(), ly = new FloatList();
  strokes.add(new FloatList[] { lx, ly });
  int first = 0;
  for (int i = 1; i < parts.size(); i++) if (parts.get(i).size() > parts.get(first).size()) first = i;
  OutlinePart p0 = parts.remove(first);
  FloatList fx = p0.x.copy(), fy = p0.y.copy();
  if (p0.closed) {
    int low = 0;
    for (int i = 1; i < fy.size(); i++) if (fy.get(i) > fy.get(low)) low = i;
    rotateTo(fx, fy, low);
    fx.append(fx.get(0));
    fy.append(fy.get(0));
  } else if (fy.get(0) < fy.get(fy.size() - 1)) {
    fx.reverse();
    fy.reverse();
  }
  lx.append(fx.array());
  ly.append(fy.array());
  while (!parts.isEmpty()) {
    float ex = lx.get(lx.size() - 1), ey = ly.get(ly.size() - 1);
    int best = -1, bestAt = 0;
    float bestD = Float.MAX_VALUE;
    for (int i = 0; i < parts.size(); i++) {
      OutlinePart p = parts.get(i);
      if (p.closed) {
        for (int q = 0; q < p.size(); q++) {
          float dd = sq(p.x.get(q) - ex) + sq(p.y.get(q) - ey);
          if (dd < bestD) { bestD = dd; best = i; bestAt = q; }
        }
      } else {
        float d0 = sq(p.x.get(0) - ex) + sq(p.y.get(0) - ey);
        float d1 = sq(p.x.get(p.size() - 1) - ex) + sq(p.y.get(p.size() - 1) - ey);
        if (d0 < bestD) { bestD = d0; best = i; bestAt = 0; }
        if (d1 < bestD) { bestD = d1; best = i; bestAt = -1; }
      }
    }
    OutlinePart p = parts.remove(best);
    FloatList nx = p.x.copy(), ny = p.y.copy();
    if (p.closed) {
      rotateTo(nx, ny, bestAt);
      nx.append(nx.get(0));
      ny.append(ny.get(0));
    } else if (bestAt == -1) {
      nx.reverse();
      ny.reverse();
    }
    if (!join) {
      lx = new FloatList();
      ly = new FloatList();
      strokes.add(new FloatList[] { lx, ly });
      lx.append(nx.array());
      ly.append(ny.array());
      continue;
    }
    // the curve across: a Hermite curve with the directions at both ends
    int L = lx.size();
    float t0x = ex - lx.get(max(0, L - 4)), t0y = ey - ly.get(max(0, L - 4));
    float t1x = nx.get(min(3, nx.size() - 1)) - nx.get(0), t1y = ny.get(min(3, ny.size() - 1)) - ny.get(0);
    float d = sqrt(bestD);
    float m0 = d * 0.6 / max(0.001, mag(t0x, t0y)), m1 = d * 0.6 / max(0.001, mag(t1x, t1y));
    t0x *= m0; t0y *= m0; t1x *= m1; t1y *= m1;
    int k = max(1, ceil(d / 3));
    for (int q = 1; q < k; q++) {
      float u = q / (float) k, u2 = u * u, u3 = u2 * u;
      float h00 = 2 * u3 - 3 * u2 + 1, h10 = u3 - 2 * u2 + u, h01 = -2 * u3 + 3 * u2, h11 = u3 - u2;
      lx.append(h00 * ex + h10 * t0x + h01 * nx.get(0) + h11 * t1x);
      ly.append(h00 * ey + h10 * t0y + h01 * ny.get(0) + h11 * t1y);
    }
    lx.append(nx.array());
    ly.append(ny.array());
  }
}

void rotateTo(FloatList x, FloatList y, int at) {
  float[] ax = x.array(), ay = y.array();
  int n = ax.length;
  for (int i = 0; i < n; i++) {
    x.set(i, ax[(i + at) % n]);
    y.set(i, ay[(i + at) % n]);
  }
}

// the line with its points moved to be `step` pixels apart all along it
void resampleInto(FloatList x, FloatList y, float step) {
  if (x.size() < 2) return;
  FloatList rx = new FloatList(), ry = new FloatList();
  rx.append(x.get(0));
  ry.append(y.get(0));
  float carry = 0;
  for (int i = 1; i < x.size(); i++) {
    float ax = x.get(i - 1), ay = y.get(i - 1), bx = x.get(i), by = y.get(i);
    float d = dist(ax, ay, bx, by);
    float s = step - carry;
    while (s <= d) {
      rx.append(lerp(ax, bx, s / d));
      ry.append(lerp(ay, by, s / d));
      s += step;
    }
    carry = d - (s - step);
  }
  x.clear(); y.clear();
  x.append(rx.array());
  y.append(ry.array());
}
