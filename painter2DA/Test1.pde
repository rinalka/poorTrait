// TEST1 (the last box in the panel's column 2): a drawing in two parts, made all at once by its DRAW
// button (in MOVEMENT, like COPY's), on APPLY's layer, in its IN AREA.
//
// First cross hatching that matches the depth map's shading: dark where the depth map is dark (far
// away), none where it's lightest. Only short straight lines - never longer than 70 pixels - in sets,
// each set crossing the others at its own angle, and only where it's darker than that set's level, so
// the darker it is, the more sets cross there. Each line turns a little from place to place (the
// direction slider), and is thicker the darker it is under it. Every DRAW picks new angles.
//
// Then the very darkest parts of the light map (its creases: eyelids, nostrils, the mouth, the hair's
// curls) drawn on top as one black line, from each dark spot to the nearest one not drawn yet - or
// lifted between parts, if that's on.

final int T_TEST1 = 10;
volatile String test1Status = "";       // what DRAW did last, shown by its button
final float TEST1_LONGEST = 70;         // no hatch is longer than this (pixels)

// TEST1's DRAW button
void test1Now() {
  String was = tool;
  useTool(T_TEST1);
  int L = (int) t("layer");
  layersReady();
  if (L < 0) test1Status = "pick a layer";
  else if (!areaChosen(tool)) test1Status = "choose the area, in APPLY";
  else if (areaWay() > 0 && !areaReady()) test1Status = "the area isn't ready";
  else {
    int t0 = millis();
    PImage mask = areaWay() == 0 ? null : areaMask(0);
    if (mask != null) mask.loadPixels();
    PGraphics d = createGraphics(photo.width, photo.height, JAVA2D);
    d.beginDraw();
    d.clear();
    d.smooth();
    int hatches = test1Hatch(d, mask);
    int spots = t("lineOn") > 0.5 ? test1Line(d, mask) : 0;
    d.endDraw();
    PImage p = d.get();
    if (mask != null) p = maskedMap(p, mask);
    if (t("clear") > 0.5) {
      if (mask == null) clearLayer(L);
      else {
        eraseWith(layers[L], mask);
        eraseWith(heights[L], mask);
      }
    }
    PGraphics g = layers[L];
    g.beginDraw();
    g.image(p, 0, 0, photo.width, photo.height);
    g.endDraw();
    layerChanged[L] = true;
    test1Status = hatches + " hatches" + (spots > 0 ? ", a line through " + spots + " dark spots" : "")
      + " on layer " + LAYER_NAMES[L] + (v("layerOn" + L) < 0.5 ? "  (hidden)" : "") + "   " + (millis() - t0) + " ms";
  }
  println("TEST1: " + test1Status);
  useTool(java.util.Arrays.asList(TOOLS).indexOf(was));
}

// how dark the hatching should be at (x, y), 0 .. 1: the depth map's darkness, made darker or lighter
// by the tone slider (or its lightness, hatching the near parts, with invert)
float test1Tone(float x, float y) {
  float dark = 1 - mapAt(3, x, y);
  if (t("invert") > 0.5) dark = 1 - dark;
  return pow(constrain(dark, 0, 1), 1 / t("tone"));
}

boolean test1Inside(PImage mask, float x, float y) {
  if (x < 0 || y < 0 || x >= photo.width || y >= photo.height) return false;
  return mask == null || (mask.pixels[pixelIndex(x, y)] >>> 24) >= 128;
}

// the sets of hatching. Each set is rows of short lines across the picture at its angle, `spacing`
// apart; a line is kept where it's darker than the set's level, and cut back to where it stays so.
// Returns how many lines it drew
int test1Hatch(PGraphics d, PImage mask) {
  int sets = max(1, round(t("sets")));
  float gap = t("spacing"), most = min(TEST1_LONGEST, t("length")), turn = t("turn");
  float thin = t("thin"), thick = max(thin, t("thick"));
  int ink = panel.colour("test1_ink");
  float base = random(PI), seed = random(1000);
  float diag = dist(0, 0, photo.width, photo.height), cx = photo.width / 2.0, cy = photo.height / 2.0;
  int made = 0;
  d.strokeCap(ROUND);
  d.noFill();
  for (int k = 0; k < sets; k++) {
    float level = 0.14 + 0.8 * k / sets;           // where this set starts
    float ang = base + k * PI / sets + random(-0.2, 0.2);
    float ca = cos(ang), sa = sin(ang);
    for (float u = -diag / 2; u < diag / 2; u += gap * random(0.75, 1.25)) {
      float along = -diag / 2 - random(most);
      while (along < diag / 2) {
        float len = random(0.4, 1) * most;
        float mid = along + len / 2;
        along += len + random(2, max(3, 0.3 * most));
        float px = cx + ca * mid - sa * u, py = cy + sa * mid + ca * u;
        if (!test1Inside(mask, px, py)) continue;
        float tone = test1Tone(px, py);
        if (tone < level) continue;
        // its own direction: the set's, turned by how the drawing wanders there, and a little shake
        float a = ang + turn * (noise(px / 220.0, py / 220.0, seed + k * 5) - 0.5) * PI + random(-0.06, 0.06);
        float dx = cos(a), dy = sin(a);
        // out from the middle, each way, while it's still dark enough
        float back = 0, fwd = 0;
        for (float s = 2; s <= len / 2; s += 2) {
          if (test1Tone(px - dx * s, py - dy * s) < level - 0.03 || !test1Inside(mask, px - dx * s, py - dy * s)) break;
          back = s;
        }
        for (float s = 2; s <= len / 2; s += 2) {
          if (test1Tone(px + dx * s, py + dy * s) < level - 0.03 || !test1Inside(mask, px + dx * s, py + dy * s)) break;
          fwd = s;
        }
        if (back + fwd < 4) continue;
        float how = constrain((tone - level) / max(0.05, 1 - level) * random(0.6, 1.4), 0, 1);
        d.stroke(ink, random(190, 245));
        d.strokeWeight(lerp(thin, thick, how));
        d.line(px - dx * back, py - dy * back, px + dx * fwd, py + dy * fwd);
        made++;
      }
    }
  }
  return made;
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
