// Splatters (design doc Stage 5): a mark system of its own, painted alongside the brushes, with
// its own controls in the panel's SPLATTER block.
//
// A splatter is a cluster: a centre (placed the same way as brush marks - the "start at" choice),
// usually a big splat there, and a lot of drops scattered round it - Gaussian, so most land near
// the centre and a few fly far. Drop sizes are heavy-tailed: most are tiny, a few are
// conspicuously big. Big drops have satellite droplets round their edge, and some clusters fling
// long thin trails out from the centre, tapering as they go and ending in a drop.
//
// The drops can be of four kinds, chosen at the top of the box: round splatter drops, dots,
// dashes and triangles (the old FRAGMENTS tool), any mix of them - each drop is one of the chosen
// kinds at random, and the splat in the middle and a trail's end drop too. All of them share the
// cluster settings, drips included; only the round drops have satellite droplets.
//
// Splatter drops aren't circles: each has a wobbly outline, slightly different every time. Some drops
// ("drips") are wet enough to run: paint hangs off the bottom of the drop and runs straight down,
// thinning a little, and gathers in a blob at the end.
//
// A cluster can be hundreds of drops, so the whole cluster is drawn as one shape made of
// triangles - drawing each drop as a shape of its own is several times slower.

IntList splatKinds = new IntList();             // 0 splatter drops, 1 dots, 2 dashes, 3 triangles

void paintSplatters(PGraphics g) {
  if (t("on") < 0.5) return;
  splatKinds.clear();
  if (t("kSplat") > 0.5) splatKinds.append(0);
  if (t("kDots") > 0.5) splatKinds.append(1);
  if (t("kDashes") > 0.5) splatKinds.append(2);
  if (t("kTris") > 0.5) splatKinds.append(3);
  if (splatKinds.size() == 0) return;
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
  if (random(1) < 0.7) {
    anyDrop(g, cx, cy, size * random(0.5, 1), dropColour(c), alpha);
  }

  // drops round it: nearer the middle they're bigger
  int drops = round(t("drops") * random(0.4, 1.4));
  for (int d = 0; d < drops; d++) {
    float gx = randomGaussian(), gy = randomGaussian();
    float x = cx + gx * spread, y = cy + gy * spread;
    if (x < 0 || y < 0 || x >= photo.width || y >= photo.height) continue;
    float far = constrain(sqrt(gx * gx + gy * gy) / 3, 0, 1);
    float r = max(0.7, size * 0.6 * pow(random(1), tail) * (1 - 0.6 * far));
    anyDrop(g, x, y, r, dropColour(c), alpha * random(0.6, 1));
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
  // a drip, more likely from a bigger drop, hanging off its lowest point
  int low = 0;
  for (int i = 1; i < pts; i++) if (ry[i] > ry[low]) low = i;
  maybeDrip(g, lerp(rx[low], x, 0.25), ry[low], r);
  if (r > 5) {
    int sats = (int) random(0, r / 3);
    for (int i = 0; i < sats; i++) {
      float ang = random(TWO_PI), dist = r * random(1.1, 1.9), sr = r * random(0.05, 0.18);
      disc(g, x + cos(ang) * dist, y + sin(ang) * dist, sr, 6);
    }
  }
}

// one drop of a kind chosen at random from the box's ticked kinds, r about its radius
void anyDrop(PGraphics g, float x, float y, float r, color c, float a) {
  int kind = splatKinds.get((int) random(splatKinds.size()));
  if (kind == 0) drop(g, x, y, r, c, a);
  else fragment(g, x, y, r, kind, c, a);
}

// a dot, a dash (a short thin bar) or a triangle (never quite regular), about r across, pointing
// anywhere. Like a round drop, it can drip from its lowest point
void fragment(PGraphics g, float x, float y, float r, int kind, color c, float a) {
  g.fill(c, a);
  float ang = random(TWO_PI), ca = cos(ang), sa = sin(ang);
  float lowX = x, lowY = y;
  if (kind == 1) {
    disc(g, x, y, max(0.6, r), 7);
    lowY = y + r;
  } else if (kind == 2) {
    float l = max(0.8, r * random(1.2, 3)), w = max(0.4, r * random(0.15, 0.4));
    float ax = ca * l, ay = sa * l, bx = -sa * w, by = ca * w;
    float[] px = { x - ax - bx, x + ax - bx, x + ax + bx, x - ax + bx };
    float[] py = { y - ay - by, y + ay - by, y + ay + by, y - ay + by };
    g.vertex(px[0], py[0]); g.vertex(px[1], py[1]); g.vertex(px[2], py[2]);
    g.vertex(px[0], py[0]); g.vertex(px[2], py[2]); g.vertex(px[3], py[3]);
    for (int k = 0; k < 4; k++) if (py[k] > lowY) { lowX = px[k]; lowY = py[k]; }
  } else {
    for (int k = 0; k < 3; k++) {
      float a3 = ang + TWO_PI * k / 3 + random(-0.4, 0.4), rr = max(0.8, r * random(1, 1.75));
      float px = x + cos(a3) * rr, py = y + sin(a3) * rr;
      g.vertex(px, py);
      if (py > lowY) { lowX = px; lowY = py; }
    }
  }
  maybeDrip(g, lerp(lowX, x, 0.25), lowY, r);
}

// a drip off a drop r across, from (x, y), its lowest point: more likely from a bigger drop
void maybeDrip(PGraphics g, float x, float y, float r) {
  if (r > 3 && random(1) < t("drip") * min(1, 0.3 + r / max(1, t("size")))) drip(g, x, y, r);
}

// paint running straight down from (x, y), the bottom of a drop r across: it leaves the drop
// wide, thins as it goes with a little waver, and ends in a blob a bit fatter than the run
void drip(PGraphics g, float x, float y, float r) {
  float w = r * random(0.25, 0.5);
  float len = t("dripLength") * random(0.4, 1.2) * sqrt(min(1, r / max(1, t("size")) + 0.3));
  int steps = max(3, round(len / 3));
  float seed = random(1000), drift = random(-0.03, 0.03);
  y -= w * 0.6;                                   // starts inside the drop, so they're joined
  float pl = 0, pr = 0, py = 0;
  for (int s = 0; s <= steps; s++) {
    float u = s / (float) steps, yy = y + len * u;
    float xx = x + drift * len * u * u + (noise(seed, u * 4) - 0.5) * w * 0.3;
    // wide where it leaves the drop, then thinning, swelling a little here and there
    float half = w / 2 * (lerp(1.6, 0.55, sqrt(u)) + 0.25 * (noise(seed + 9, u * 6) - 0.5));
    if (s > 0) {
      g.vertex(pl, py); g.vertex(pr, py); g.vertex(xx - half, yy);
      g.vertex(pr, py); g.vertex(xx + half, yy); g.vertex(xx - half, yy);
    }
    pl = xx - half; pr = xx + half; py = yy;
    if (s == steps) {
      // the blob: a fat drop, a little longer than it's wide, hanging just below the run's end
      float br = w * random(0.65, 0.95);
      int pts = 14;
      float cy = yy + br * 0.35;
      for (int i = 0; i < pts; i++) {
        float a0 = TWO_PI * i / pts, a1 = TWO_PI * (i + 1) / pts;
        g.vertex(xx, cy);
        g.vertex(xx + cos(a0) * br, cy + sin(a0) * br * (sin(a0) > 0 ? 1.2 : 0.9));
        g.vertex(xx + cos(a1) * br, cy + sin(a1) * br * (sin(a1) > 0 ? 1.2 : 0.9));
      }
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
  anyDrop(g, x, y, w * random(0.4, 1), c, a);
}

// a drop's colour: the cluster's, varied a little in lightness and hue
color dropColour(color c) {
  float amt = t("vary");
  if (amt <= 0) return c;
  float[] hsb = java.awt.Color.RGBtoHSB(c >> 16 & 255, c >> 8 & 255, c & 255, null);
  float h = hsb[0] + random(-0.3, 0.3) * amt;
  return java.awt.Color.HSBtoRGB(h - floor(h), hsb[1], constrain(hsb[2] + random(-1, 1) * amt, 0, 1)) | 0xFF000000;
}
