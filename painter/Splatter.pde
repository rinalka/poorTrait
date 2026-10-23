// Splatters (design doc Stage 5): a mark system of its own, painted alongside the brushes, with
// its own controls in the panel's SPLATTER block.
//
// A splatter is a cluster: a centre (placed the same way as brush marks - the "start at" choice),
// usually a big splat there, and a lot of drops scattered round it - Gaussian, so most land near
// the centre and a few fly far. Drop sizes are heavy-tailed: most are tiny, a few are
// conspicuously big. Big drops have satellite droplets round their edge, and some clusters fling
// long thin trails out from the centre, tapering as they go and ending in a drop.
//
// Drops aren't circles: each has a wobbly outline, slightly different every time.
// Splatters respect ABSTRACTION: no drop lands where it's protected.
//
// A cluster can be hundreds of drops, so the whole cluster is drawn as one shape made of
// triangles - drawing each drop as a shape of its own is several times slower.

void paintSplatters(PGraphics g) {
  if (t("on") < 0.5) return;
  // clusters per frame can be a fraction: 0.3 means a cluster on about 3 frames in 10
  int n = countFor(t("rate"));
  for (int i = 0; i < n; i++) splatter(g);
}

void splatter(PGraphics g) {
  float[] s = startPoint();
  if (s == null) return;
  float cx = s[0], cy = s[1];
  color c = systemColour(cx, cy);      // (in the Lines tab)
  float alpha = toolAlpha(cx, cy);
  float size = t("size"), spread = t("scatter");
  float tail = lerp(7, 1.5, t("big"));        // higher = more of the drops tiny
  g.noStroke();
  g.beginShape(TRIANGLES);

  // the big splat in the middle (not always - some clusters are only drops)
  if (random(1) < 0.7 && random(1) >= protection(cx, cy)) {
    drop(g, cx, cy, size * random(0.5, 1), dropColour(c), alpha);
  }

  // drops round it: nearer the middle they're bigger
  int drops = round(t("drops") * random(0.4, 1.4));
  for (int d = 0; d < drops; d++) {
    float gx = randomGaussian(), gy = randomGaussian();
    float x = cx + gx * spread, y = cy + gy * spread;
    if (x < 0 || y < 0 || x >= photo.width || y >= photo.height) continue;
    if (random(1) < protection(x, y)) continue;
    float far = constrain(sqrt(gx * gx + gy * gy) / 3, 0, 1);
    float r = max(0.7, size * 0.6 * pow(random(1), tail) * (1 - 0.6 * far));
    drop(g, x, y, r, dropColour(c), alpha * random(0.6, 1));
  }

  // trails flung out from the middle
  int trails = floor(t("trails") * random(0, 4));
  for (int t = 0; t < trails; t++) {
    trail(g, cx, cy, random(TWO_PI), spread * random(1.2, 4), size * random(0.12, 0.35), dropColour(c), alpha);
  }
  g.endShape();
}

// one drop: a wobbly round shape, with satellite droplets round the big ones. Added to the
// cluster's shape as a fan of triangles round its middle
void drop(PGraphics g, float x, float y, float r, color c, float a) {
  g.fill(c, a);
  if (r < 1.5) {
    disc(g, x, y, r, 6);
    return;
  }
  int pts = constrain(round(r * 1.5), 8, 32);
  float seed = random(1000), squash = random(0.75, 1), turn = random(TWO_PI);
  float[] rx = new float[pts], ry = new float[pts];
  for (int i = 0; i < pts; i++) {
    float ang = TWO_PI * i / pts;
    float rr = r * (0.75 + 0.5 * noise(seed + cos(ang) * 1.3, seed + sin(ang) * 1.3));
    float px = cos(ang) * rr, py = sin(ang) * rr * squash;
    rx[i] = x + px * cos(turn) - py * sin(turn);
    ry[i] = y + px * sin(turn) + py * cos(turn);
  }
  for (int i = 0; i < pts; i++) {
    int j = (i + 1) % pts;
    g.vertex(x, y);
    g.vertex(rx[i], ry[i]);
    g.vertex(rx[j], ry[j]);
  }
  if (r > 5) {
    int sats = (int) random(0, r / 3);
    for (int i = 0; i < sats; i++) {
      float ang = random(TWO_PI), dist = r * random(1.1, 1.9), sr = r * random(0.05, 0.18);
      if (random(1) < protection(x + cos(ang) * dist, y + sin(ang) * dist)) continue;
      disc(g, x + cos(ang) * dist, y + sin(ang) * dist, sr, 6);
    }
  }
}

// a small round dot, as triangles
void disc(PGraphics g, float x, float y, float r, int pts) {
  for (int i = 0; i < pts; i++) {
    float a0 = TWO_PI * i / pts, a1 = TWO_PI * (i + 1) / pts;
    g.vertex(x, y);
    g.vertex(x + cos(a0) * r, y + sin(a0) * r);
    g.vertex(x + cos(a1) * r, y + sin(a1) * r);
  }
}

// a long thin trail from (x, y) outwards, bending a little and tapering, ending in a drop
void trail(PGraphics g, float x, float y, float ang, float len, float w, color c, float a) {
  int steps = max(4, round(len / 4));
  float stepLen = len / steps, bend = random(-0.02, 0.02);
  g.fill(c, a);
  float pax = 0, pay = 0, pbx = 0, pby = 0;      // the last step's two edge points
  for (int s = 0; s <= steps; s++) {
    float t = s / (float) steps;
    if (s > 0) {
      ang += bend;
      x += cos(ang) * stepLen;
      y += sin(ang) * stepLen;
    }
    float half = w / 2 * pow(1 - t, 0.7) + 0.4;
    float nx = -sin(ang), ny = cos(ang);
    float ax = x + nx * half, ay = y + ny * half, bx = x - nx * half, by = y - ny * half;
    if (s > 0) {
      g.vertex(pax, pay); g.vertex(pbx, pby); g.vertex(ax, ay);
      g.vertex(pbx, pby); g.vertex(bx, by); g.vertex(ax, ay);
    }
    pax = ax; pay = ay; pbx = bx; pby = by;
  }
  if (random(1) >= protection(x, y)) drop(g, x, y, w * random(0.4, 1), c, a);
}

// a drop's colour: the cluster's, varied a little in lightness and hue
color dropColour(color c) {
  float amt = t("vary");
  if (amt <= 0) return c;
  float[] hsb = java.awt.Color.RGBtoHSB(c >> 16 & 255, c >> 8 & 255, c & 255, null);
  float h = hsb[0] + random(-0.3, 0.3) * amt;
  return java.awt.Color.HSBtoRGB(h - floor(h), hsb[1], constrain(hsb[2] + random(-1, 1) * amt, 0, 1)) | 0xFF000000;
}
