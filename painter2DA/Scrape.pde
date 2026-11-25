// Scraping (the panel's SCRAPE block): taking paint off one layer, instead of putting it on, so
// what's on the layers under it shows through.
//
//   knife      a palette knife dragged across wet paint: a broad mark, the same shape as the
//              knife's (the Knife tab's Blade), that doesn't take everything - streaks of
//              paint are left behind where the knife didn't quite catch, more towards its end
//   scratches  short, thin wandering lines scored through to what's underneath
//   erase      not marks: its ERASE button takes everything off in APPLY's IN AREA (or outside it),
//              all at once - see eraseArea()
//
// The knife and the scratches go as the run does. The frame's marks are drawn first into a mask
// (solid where paint comes off), which is cut to IN AREA and then taken off the layer (Layers tab,
// eraseWith). They're placed by MOVEMENT's "start at" like the other tools' marks.

// "kind"
String[] scrapeNames = { "knife", "scratches", "erase" };
final int SCRAPE_KNIFE = 0, SCRAPE_SCRATCHES = 1, SCRAPE_ERASE = 2;
PGraphics scrapeMask;
volatile String eraseStatus = "";      // what ERASE did last, for its box

void paintScrapes() {
  int L = (int) t("only");               // its layer (-1: not picked yet)
  if (t("on") < 0.5 || t("kind") == SCRAPE_ERASE || L < 0 || !areaAllows()) return;
  int n = countFor(t("rate"));
  if (n == 0) return;
  if (scrapeMask == null || scrapeMask.width != photo.width || scrapeMask.height != photo.height) {
    scrapeMask = createGraphics(photo.width, photo.height, P2D);
  }
  scrapeMask.beginDraw();
  scrapeMask.clear();
  scrapeMask.noStroke();
  int made = 0;
  for (int i = 0; i < n; i++) {
    float[] s = startPoint();
    if (s == null) continue;
    if (t("kind") == SCRAPE_KNIFE) knifeScrape(scrapeMask, s[0], s[1]);
    else scratch(scrapeMask, s[0], s[1]);
    made++;
  }
  scrapeMask.endDraw();
  if (made == 0) return;
  areaClipMask(scrapeMask);                    // IN AREA (the Area tab)
  eraseWith(layers[L], scrapeMask);
  eraseWith(heights[L], scrapeMask);           // the paint's thickness goes with it (Impasto)
}

// the direction a scrape goes: along the form, turned by up to 90 degrees as "follow" drops
float scrapeAngle(float x, float y) {
  float[] f = fieldAt(x, y);
  float turn = random(-1, 1) * (1 - t("follow")) * HALF_PI;
  float a = f[2] > 0.05 ? atan2(f[1], f[0]) + turn : random(TWO_PI);
  return random(1) < 0.5 ? a : a + PI;
}

void knifeScrape(PGraphics m, float x, float y) {
  float len = t("length") * random(0.5, 1), wid = t("width") * random(0.7, 1.3);
  Blade b = new Blade(x, y, scrapeAngle(x, y), len, wid, false);
  Paint white = new Paint().flat(color(255));
  float strength = 255 * t("strength"), seed = random(1000);
  // bands across the knife, each taking a different amount: the streaks it leaves
  int bands = 12;
  float reach = random(0.85, 1.05);
  for (int k = 0; k < bands; k++) {
    float a = strength * (0.35 + 0.65 * noise(seed, k * 0.6));
    b.band(m, 0, reach, map(k, 0, bands, -1, 1), map(k + 1, 0, bands, -1, 1), white, a, a * random(0.2, 0.8));
  }
}

void scratch(PGraphics m, float x, float y) {
  float len = t("length") * random(0.3, 1);
  float half = max(0.4, t("width") * 0.03 * random(0.5, 1.5));
  float heading = scrapeAngle(x, y), turning = 0, seed = random(1000);
  int steps = max(2, round(len / 3));
  float stepLen = len / steps;
  m.fill(255, 255 * t("strength"));
  m.beginShape(TRIANGLES);
  float pax = 0, pay = 0, pbx = 0, pby = 0;
  for (int st = 0; st <= steps; st++) {
    if (st > 0) {
      turning = turning * 0.8 + randomGaussian() * 0.015;
      heading += turning;
      x += cos(heading) * stepLen;
      y += sin(heading) * stepLen;
    }
    float t = st / (float) steps;
    float h = half * min(1, min(t, 1 - t) * 6 + 0.3);       // thin where the point went in and came out
    h *= max(0.15, 1 + t("ragged") * 2.5 * (noise(seed, st * 0.4) - 0.5));      // "ragged edges": thick and thin
    float nx = -sin(heading), ny = cos(heading);
    float ax = x + nx * h, ay = y + ny * h, bx = x - nx * h, by = y - ny * h;
    if (st > 0) {
      m.vertex(pax, pay); m.vertex(pbx, pby); m.vertex(ax, ay);
      m.vertex(pbx, pby); m.vertex(bx, by); m.vertex(ax, ay);
    }
    pax = ax; pay = ay; pbx = bx; pby = by;
  }
  m.endShape();
}


// ---------------------------------------------------------------- erase

// ERASE's button: everything on SCRAPE's layer in IN AREA's area (or outside it) comes off at once,
// fading at the area's edge - nothing off at the edge itself, everything from "fade" pixels in.
// (All: the whole layer, with no edge to fade at.)
void eraseArea() {
  String was = tool;
  useTool(T_SCRAPE);
  eraseStatus = eraseNow();
  println("ERASE: " + eraseStatus);
  useTool(java.util.Arrays.asList(TOOLS).indexOf(was));
}

String eraseNow() {
  int L = (int) t("only");
  if (L < 0) return "pick a layer";
  if (!areaChosen(tool)) return "choose the area, in APPLY";
  layersReady();
  String hidden = v("layerOn" + L) < 0.5 ? "  (hidden)" : "";
  if (areaWay() == 0) {
    clearLayer(L);
    return "all of layer " + LAYER_NAMES[L] + " is off" + hidden;
  }
  if (!areaReady()) return "the area isn't ready";
  PImage mask = areaMask(t("fade"));
  eraseWith(layers[L], mask);
  eraseWith(heights[L], mask);                 // the paint's thickness goes with it (Impasto)
  return nf(100 * areaShare(), 0, 1) + "% of layer " + LAYER_NAMES[L] + " is off" + hidden;
}
