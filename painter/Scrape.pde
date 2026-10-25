// Scraping (the panel's SCRAPE block): taking paint off, instead of putting it on. Every scrape
// removes paint from all the layers above the "down to" layer, so whatever is on that layer (or
// under it) shows through - an earlier stage of the painting, or, down to the canvas, what it
// started with (the masses, the photo or the bare canvas). Or it scrapes just one layer, leaving
// the others as they are.
//
//   knife scrape   a palette knife dragged across wet paint: a broad mark, the same shape as the
//                  knife's (the Knife tab's Blade), that doesn't take everything - streaks of
//                  paint are left behind where the knife didn't quite catch, more towards its end
//   scratches      short, thin wandering lines scored through to what's underneath (Stage 5's
//                  scratches)
//
// The frame's scrapes are drawn first into a mask (solid where paint comes off), and the mask is
// then taken off each layer above "down to" (Layers tab, eraseWith). Scrapes are placed by "start
// at" like the other marks, and respect ABSTRACTION.

PGraphics scrapeMask;

void paintScrapes() {
  if (t("on") < 0.5) return;
  // "down to": 0 = the canvas, so every layer is scraped; 1 = layer 1, so the layers above it in
  // the stack are scraped ... "one layer": only that layer
  boolean one = t("which") == 1;
  int down = (int) t("layer");
  int from = down == 0 ? 0 : layerPosition(down - 1) + 1;
  int n = countFor(t("rate"));
  if (n == 0 || !one && from >= LAYERS) return;
  if (scrapeMask == null || scrapeMask.width != photo.width || scrapeMask.height != photo.height) {
    scrapeMask = createGraphics(photo.width, photo.height, P2D);
  }
  scrapeMask.beginDraw();
  scrapeMask.clear();
  scrapeMask.noStroke();
  int made = 0;
  for (int i = 0; i < n; i++) {
    float[] s = startPoint();
    if (s == null || random(1) < protection(s[0], s[1])) continue;
    if (t("kind") == 0) knifeScrape(scrapeMask, s[0], s[1]);
    else scratch(scrapeMask, s[0], s[1]);
    made++;
  }
  scrapeMask.endDraw();
  if (made == 0) return;
  if (one) {
    int L = (int) t("only");
    eraseWith(layers[L], scrapeMask);
    eraseWith(heights[L], scrapeMask);          // the paint's thickness goes with it (Impasto)
    return;
  }
  int[] o = layerOrder;
  for (int p = from; p < LAYERS; p++) {
    eraseWith(layers[o[p]], scrapeMask);
    eraseWith(heights[o[p]], scrapeMask);
  }
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
  float heading = scrapeAngle(x, y), turning = 0;
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
