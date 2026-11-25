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
// IN AREA's "Tri Centers" and "Vertices" put every drop in the middle of a triangle of the mesh (SETUP 4),
// or on one of its corners: the one its scattered place is in, or nearest - one drop there from each cluster.
// A drop's size then goes by the triangle's (or the average of those round the corner): at 1 it just fits
// in it. Droplets and trails, which would land elsewhere, are left out (drips still run).
//
// The paint (COLOUR) is picked up at one spot and put down at another: each cluster picks up at a
// spot of its own, by MOVEMENT's rules, and lands somewhere else by the same rules ("put it down
// somewhere else" off: where it lands). What it picks up there is COLOUR's "carry":
//   one colour     the colour at the spot, for the whole cluster
//   start to end   the colour there in the middle of the cluster, sliding into one picked up a
//                  cluster's reach away at its edge
//   two colours    two colours from either side of the spot - each drop is one or the other
//   chunk          the bit of the picture round the spot - every drop is a dab of the same bit
//   copy           the picture round the spot, seen through the cluster: each drop has its own part
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

Paint splatPaint;                  // the cluster's paint: its carry, and its colours or picture
float splatX, splatY;              // where the cluster lands
float splatPickX, splatPickY;      // where its paint was picked up
float splatReach;                  // how far out "start to end" has got to the end
float splatDU, splatDV;            // chunk and copy: from a corner being drawn to its paint
float splatBig = 24;               // the size of the biggest drops there are now
boolean splatSites = false;        // every drop goes on one of the mesh's triangles or corners
java.util.HashSet<Integer> splatUsed = new java.util.HashSet<Integer>();     // the ones this cluster's been to
float splatSolid = 255;            // how solid what's being drawn is
float splatSmearY = Float.NaN;     // a drip's paint all comes from this height: it runs down

void splatter(PGraphics g) {
  int a = (int) t("inArea");
  splatSites = a == AREA_TRI_CENTERS || a == AREA_VERTICES;
  if (splatSites && !sitesReady()) return;        // (no mesh yet)
  splatUsed.clear();
  float[] s = startPoint();
  if (s == null) return;
  float cx = splatX = s[0], cy = splatY = s[1];
  float alpha = toolAlpha(cx, cy);
  float size = t("size"), spread = t("scatter");
  float tail = lerp(7, 1.5, t("big"));        // higher = more of the drops tiny
  splatBig = size;
  loadSplat(spread);
  g.noStroke();
  g.beginShape(TRIANGLES);
  if (splatPaint.textured()) {
    g.textureMode(IMAGE);
    g.texture(splatPaint.tex);
  }

  if (splatSites) {
    int drops = round(t("drops") * random(0.4, 1.4));
    siteDrop(g, a, cx, cy, alpha);
    for (int d = 0; d < drops; d++) {
      siteDrop(g, a, cx + randomGaussian() * spread, cy + randomGaussian() * spread, alpha * random(0.6, 1));
    }
    g.endShape();
    if (splatPaint.textured()) g.noTint();
    return;
  }

  // the big splat in the middle (not always - some clusters are only drops)
  if (random(1) < 0.7) {
    anyDrop(g, cx, cy, size * random(0.5, 1), splatColour(cx, cy), alpha);
  }

  // drops round it: nearer the middle they're bigger
  int drops = round(t("drops") * random(0.4, 1.4));
  for (int d = 0; d < drops; d++) {
    float gx = randomGaussian(), gy = randomGaussian();
    float x = cx + gx * spread, y = cy + gy * spread;
    if (x < 0 || y < 0 || x >= photo.width || y >= photo.height) continue;
    float far = constrain(sqrt(gx * gx + gy * gy) / 3, 0, 1);
    float r = max(0.7, size * 0.6 * pow(random(1), tail) * (1 - 0.6 * far));
    anyDrop(g, x, y, r, splatColour(x, y), alpha * random(0.6, 1));
  }

  // trails flung out from the middle
  int trails = floor(t("trails") * random(0, 4));
  for (int t = 0; t < trails; t++) {
    trail(g, cx, cy, random(TWO_PI), spread * random(1.2, 4), size * random(0.12, 0.35), splatColour(cx, cy), alpha);
  }
  g.endShape();
  if (splatPaint.textured()) g.noTint();
}

// a drop on the mesh's triangle or corner at (x, y) - if this cluster hasn't put one there - its size going by the
// triangle's
void siteDrop(PGraphics g, int where, float x, float y, float alpha) {
  if (x < 0 || y < 0 || x >= photo.width || y >= photo.height) return;
  boolean vertex = where == AREA_VERTICES;
  int i = siteAt(vertex, x, y);
  if (i < 0 || !splatUsed.add(i)) return;
  float sx = vertex ? siteVertX[i] : siteTriX[i], sy = vertex ? siteVertY[i] : siteTriY[i];
  float r = (vertex ? siteVertR[i] : siteTriR[i]) * t("triSize");
  // (AUTOMATION moves it too: as its size now is to its largest)
  if (t("autoOn") > 0.5) r *= t("size") / max(1, t("autoMax"));
  if (r < 0.4) return;
  splatBig = r;
  anyDrop(g, sx, sy, r, splatColour(constrain(sx, 0, photo.width - 1), constrain(sy, 0, photo.height - 1)), alpha);
}

// how many sides a round shape r across needs to look round: more the bigger it is, so that its
// sides are never more than a sixth of a pixel off a circle
int roundSides(float r) {
  return constrain(ceil(5.5 * sqrt(r)), 8, 160);
}

// where the cluster's paint is picked up: somewhere else by MOVEMENT's rules, or where it lands.
// "grid" and "mouse" say where clusters land, so with those the paint comes from anywhere IN
// AREA allows
float[] splatPickPoint() {
  if (t("elsewhere") < 0.5) return new float[] { splatX, splatY };
  int mode = (int) t("startAt"), a = areaWay();
  float[] s = null;
  if (mode != 2 && mode != 3) s = startPoint();
  else {
    boolean any = a == 0 || !areaReady();
    for (int k = 0; k < 200 && s == null; k++) {
      float x = random(photo.width), y = random(photo.height);
      if (any || inArea(x, y) == (a == 1)) s = new float[] { x, y };
    }
  }
  return s != null ? s : new float[] { splatX, splatY };
}

// the cluster's paint, as "carry" says (see the top of this tab)
void loadSplat(float spread) {
  float[] s = splatPickPoint();
  splatPickX = s[0];
  splatPickY = s[1];
  splatReach = max(1, spread * 2);
  Paint p = splatPaint = newPaint(255);
  if (p.textured()) return;
  if ((int) t("carry") >= CHUNK) {                // an accent instead of a picture
    p.c0 = p.c1 = withContrast(p.accentColour, splatX, splatY);
    return;
  }
  float a = random(TWO_PI), ca = cos(a), sa = sin(a);
  if (p.carry == TWO) {
    p.c0 = splatPick(splatPickX + ca * spread / 2, splatPickY + sa * spread / 2);
    p.c1 = splatPick(splatPickX - ca * spread / 2, splatPickY - sa * spread / 2);
  } else {
    p.c0 = p.c1 = splatPick(splatPickX, splatPickY);
    if (p.carry == START_END) p.c1 = splatPick(splatPickX + ca * splatReach, splatPickY + sa * splatReach);
  }
}

// the colour picked up at (x, y) - its contrast is with the photo where the cluster lands
color splatPick(float x, float y) {
  x = constrain(x, 0, photo.width - 1);
  y = constrain(y, 0, photo.height - 1);
  return withContrast(pickedColour(x, y), splatX, splatY);       // (in the Lines tab)
}

// the colour of a drop at (x, y)
color splatColour(float x, float y) {
  return dropColour(splatMix(x, y, random(1) < 0.5));
}

// (second: for "two colours", the second one)
color splatMix(float x, float y, boolean second) {
  Paint p = splatPaint;
  if (p.carry == TWO) return second ? p.c1 : p.c0;
  if (p.carry == START_END) return lerpColor(p.c0, p.c1, constrain(dist(x, y, splatX, splatY) / splatReach, 0, 1));
  return p.c0;
}

// the paint for what's drawn next, and a corner of it
void splatInk(PGraphics g, color c, float a) {
  splatSolid = a;
  if (splatPaint.textured()) g.tint(255, a);
  else g.fill(c, a);
}

void splatVertex(PGraphics g, float x, float y) {
  if (!splatPaint.textured()) g.vertex(x, y);
  else g.vertex(x, y, constrain(x + splatDU, 0, photo.width - 1),
                constrain((Float.isNaN(splatSmearY) ? y : splatSmearY) + splatDV, 0, photo.height - 1));
}

// chunk and copy: where the paint of something at (x, y) comes from. Chunk: all of them from
// round the spot it was picked up; copy: each from as far from the spot as it is from the middle
void splatFrom(float x, float y) {
  boolean chunk = splatPaint.carry == CHUNK;
  splatDU = splatPickX - (chunk ? x : splatX);
  splatDV = splatPickY - (chunk ? y : splatY);
}

// one drop: a wobbly round shape, with satellite droplets round the big ones. Added to the
// cluster's shape as a fan of triangles round its middle
void drop(PGraphics g, float x, float y, float r, color c, float a) {
  splatInk(g, c, a);
  if (r < 1.5) {
    disc(g, x, y, r);
    return;
  }
  int pts = max(constrain(round(r * 1.5), 8, 32), roundSides(r));
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
    splatVertex(g, x, y);
    splatVertex(g, rx[i], ry[i]);
    splatVertex(g, rx[j], ry[j]);
  }
  if (shaping) shapeBlob(rx, ry, 0.3, 1, a);      // thickest round its edge (the Impasto tab)
  // a drip, more likely from a bigger drop, hanging off its lowest point
  int low = 0;
  for (int i = 1; i < pts; i++) if (ry[i] > ry[low]) low = i;
  maybeDrip(g, lerp(rx[low], x, 0.25), ry[low], r);
  if (r > 5 && !splatSites) {
    int sats = (int) random(0, r / 3);
    for (int i = 0; i < sats; i++) {
      float ang = random(TWO_PI), dist = r * random(1.1, 1.9), sr = r * random(0.05, 0.18);
      disc(g, x + cos(ang) * dist, y + sin(ang) * dist, sr);
    }
  }
}

// one drop of a kind chosen at random from the box's ticked kinds, r about its radius
void anyDrop(PGraphics g, float x, float y, float r, color c, float a) {
  int kind = splatKinds.get((int) random(splatKinds.size()));
  splatFrom(x, y);
  if (kind == 0) drop(g, x, y, r, c, a);
  else fragment(g, x, y, r, kind, c, a);
}

// a dot, a dash (a short thin bar) or a triangle (never quite regular), about r across, pointing
// anywhere. Like a round drop, it can drip from its lowest point
void fragment(PGraphics g, float x, float y, float r, int kind, color c, float a) {
  splatInk(g, c, a);
  float ang = random(TWO_PI), ca = cos(ang), sa = sin(ang);
  float lowX = x, lowY = y;
  if (kind == 1) {
    disc(g, x, y, max(0.6, r));
    lowY = y + r;
  } else if (kind == 2) {
    float l = max(0.8, r * random(1.2, 3)), w = max(0.4, r * random(0.15, 0.4));
    float ax = ca * l, ay = sa * l, bx = -sa * w, by = ca * w;
    float[] px = { x - ax - bx, x + ax - bx, x + ax + bx, x - ax + bx };
    float[] py = { y - ay - by, y + ay - by, y + ay + by, y - ay + by };
    splatVertex(g, px[0], py[0]); splatVertex(g, px[1], py[1]); splatVertex(g, px[2], py[2]);
    splatVertex(g, px[0], py[0]); splatVertex(g, px[2], py[2]); splatVertex(g, px[3], py[3]);
    if (shaping) shapeBlob(px, py, 0.3, 1, a);
    for (int k = 0; k < 4; k++) if (py[k] > lowY) { lowX = px[k]; lowY = py[k]; }
  } else {
    float[] tx = new float[3], ty = new float[3];
    for (int k = 0; k < 3; k++) {
      float a3 = ang + TWO_PI * k / 3 + random(-0.4, 0.4), rr = max(0.8, r * random(1, 1.75));
      float px = x + cos(a3) * rr, py = y + sin(a3) * rr;
      splatVertex(g, px, py);
      tx[k] = px;
      ty[k] = py;
      if (py > lowY) { lowX = px; lowY = py; }
    }
    if (shaping) shapeBlob(tx, ty, 0.3, 1, a);
  }
  maybeDrip(g, lerp(lowX, x, 0.25), lowY, r);
}

// a drip off a drop r across, from (x, y), its lowest point: more likely from a bigger drop
void maybeDrip(PGraphics g, float x, float y, float r) {
  if (r > 3 && random(1) < t("drip") * min(1, 0.3 + r / max(1, splatBig))) drip(g, x, y, r);
}

// paint running straight down from (x, y), the bottom of a drop r across: it leaves the drop
// wide, thins as it goes with a little waver, and ends in a blob a bit fatter than the run
void drip(PGraphics g, float x, float y, float r) {
  float w = r * random(0.25, 0.5);
  float len = t("dripLength") * random(0.4, 1.2) * sqrt(min(1, r / max(1, splatBig) + 0.3));
  int steps = max(3, round(len / 3));
  float seed = random(1000), drift = random(-0.03, 0.03);
  y -= w * 0.6;                                   // starts inside the drop, so they're joined
  float pl = 0, pr = 0, py = 0;
  float[] row = null;
  splatSmearY = y;
  for (int s = 0; s <= steps; s++) {
    float u = s / (float) steps, yy = y + len * u;
    float xx = x + drift * len * u * u + (noise(seed, u * 4) - 0.5) * w * 0.3;
    // wide where it leaves the drop, then thinning, swelling a little here and there
    float half = w / 2 * (lerp(1.6, 0.55, sqrt(u)) + 0.25 * (noise(seed + 9, u * 6) - 0.5));
    if (s > 0) {
      splatVertex(g, pl, py); splatVertex(g, pr, py); splatVertex(g, xx - half, yy);
      splatVertex(g, pr, py); splatVertex(g, xx + half, yy); splatVertex(g, xx - half, yy);
    }
    // the run's thickest along its sides, and thicker all the way down
    if (shaping) {
      float lip = lerp(0.45, 0.9, u), mid = lerp(0.25, 0.7, u);
      float[] next = { xx - half, yy, lip * 0.6, xx - half * 0.7, yy, lip, xx, yy, mid, xx + half * 0.7, yy, lip, xx + half, yy, lip * 0.6 };
      if (s > 0) shapeRows(row, next, splatSolid, splatSolid);
      row = next;
    }
    pl = xx - half; pr = xx + half; py = yy;
    if (s == steps) {
      // the blob: a fat drop, a little longer than it's wide, hanging just below the run's end
      float br = w * random(0.65, 0.95);
      int pts = roundSides(br);
      float cy = yy + br * 0.35;
      if (shaping) shapeDisc(xx, cy, br, pts, 1, 0.95, splatSolid);      // (the thickest of it)
      for (int i = 0; i < pts; i++) {
        float a0 = TWO_PI * i / pts, a1 = TWO_PI * (i + 1) / pts;
        splatVertex(g, xx, cy);
        splatVertex(g, xx + cos(a0) * br, cy + sin(a0) * br * (sin(a0) > 0 ? 1.2 : 0.9));
        splatVertex(g, xx + cos(a1) * br, cy + sin(a1) * br * (sin(a1) > 0 ? 1.2 : 0.9));
      }
    }
  }
  splatSmearY = Float.NaN;
}

// a round dot, as triangles (all of a cluster is one shape, so it's quick, and can be filled with a picture -
// circle() would be a shape of its own every time, and only a plain colour)
void disc(PGraphics g, float x, float y, float r) {
  int pts = r < 1 ? 6 : roundSides(r);
  if (shaping) shapeDisc(x, y, r, pts, r < 6 ? 0.8 : 0.3, 0.9, splatSolid);   // (specks are just beads)
  for (int i = 0; i < pts; i++) {
    float a0 = TWO_PI * i / pts, a1 = TWO_PI * (i + 1) / pts;
    splatVertex(g, x, y);
    splatVertex(g, x + cos(a0) * r, y + sin(a0) * r);
    splatVertex(g, x + cos(a1) * r, y + sin(a1) * r);
  }
}

// a long thin trail from (x, y) outwards, bending a little and tapering, ending in a drop
void trail(PGraphics g, float x, float y, float ang, float len, float w, color c, float a) {
  int steps = max(4, round(len / 4));
  float stepLen = len / steps, bend = random(-0.02, 0.02);
  boolean slides = splatPaint.carry == START_END;        // its colour changes on the way out
  splatFrom(x, y);
  splatInk(g, c, a);
  float pax = 0, pay = 0, pbx = 0, pby = 0;      // the last step's two edge points
  for (int s = 0; s <= steps; s++) {
    float t = s / (float) steps;
    if (s > 0) {
      ang += bend;
      x += cos(ang) * stepLen;
      y += sin(ang) * stepLen;
      if (slides) splatInk(g, c = splatMix(x, y, false), a);
    }
    float half = w / 2 * pow(1 - t, 0.7) + 0.4;
    float nx = -sin(ang), ny = cos(ang);
    float ax = x + nx * half, ay = y + ny * half, bx = x - nx * half, by = y - ny * half;
    if (s > 0) {
      splatVertex(g, pax, pay); splatVertex(g, pbx, pby); splatVertex(g, ax, ay);
      splatVertex(g, pbx, pby); splatVertex(g, bx, by); splatVertex(g, ax, ay);
      if (shaping) shapeRows(new float[] { pax, pay, 0.7, (pax + pbx) / 2, (pay + pby) / 2, 0.35, pbx, pby, 0.7 },
        new float[] { ax, ay, 0.7, (ax + bx) / 2, (ay + by) / 2, 0.35, bx, by, 0.7 }, a, a);
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
