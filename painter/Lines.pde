// Fine lines (design doc Stage 5): thin wandering lines, a mark system of their own in the panel's
// LINES block.
//
// Each line is a correlated random walk: it turns a little at every step, and how fast it's
// turning changes gradually, so it curves and wanders instead of jittering. Some lines (the
// "share following the form") are also pulled along the direction field, so they follow contours;
// the rest ignore the form. A line's width changes along it like pen pressure, thin at both ends,
// and "broken" lines skip, leaving gaps. Lines respect ABSTRACTION.
//
// All the lines in a frame are drawn as one shape made of triangles, which is much faster than a
// shape for each.

void paintLines(PGraphics g) {
  if (v("linesOn") < 0.5) return;
  int n = countFor(v("lineRate"));
  if (n == 0) return;
  g.noStroke();
  g.beginShape(TRIANGLES);
  for (int i = 0; i < n; i++) fineLine(g);
  g.endShape();
}

void fineLine(PGraphics g) {
  float[] s = startPoint();
  if (s == null) return;
  float x = s[0], y = s[1];
  boolean follows = random(1) < v("lineFollow");
  float[] f = fieldAt(x, y);
  float heading = follows && f[2] > 0.05 ? atan2(f[1], f[0]) + (random(1) < 0.5 ? PI : 0) : random(TWO_PI);
  float len = v("lineLength") * random(0.4, 1.2);
  float w = v("lineWidth"), wander = v("lineWander"), broken = v("lineBroken");
  g.fill(systemColour("line", x, y), 255 * v("lineOpacity"));

  int steps = max(2, round(len / 3));
  float stepLen = len / steps, turning = 0, seed = random(1000);
  boolean gap = false;
  float pax = 0, pay = 0, pbx = 0, pby = 0;      // the last step's two edge points
  for (int st = 0; st <= steps; st++) {
    float t = st / (float) steps;
    if (st > 0) {
      // the turning drifts, so the line curves smoothly one way then another
      turning = turning * 0.85 + randomGaussian() * wander * 0.06;
      heading += turning;
      if (follows) {
        // pulled towards the field's direction (whichever way along it is nearer)
        f = fieldAt(x, y);
        float d = angleBetween(heading, atan2(f[1], f[0]));
        if (abs(d) > HALF_PI) d = angleBetween(heading, atan2(f[1], f[0]) + PI);
        heading += d * 0.25 * f[2];
      }
      x += cos(heading) * stepLen;
      y += sin(heading) * stepLen;
      if (x < 0 || y < 0 || x >= photo.width || y >= photo.height) break;
      // skips: now and then a gap starts, and each gap ends after a few steps
      if (gap) gap = random(1) > 0.25;
      else gap = random(1) < broken * 0.06;
    }
    // pen pressure: wavering width, thin at both ends
    float half = max(0.3, w / 2 * (0.5 + 0.9 * noise(seed, t * 3)) * min(1, min(t, 1 - t) * 8 + 0.2));
    float nx = -sin(heading), ny = cos(heading);
    float ax = x + nx * half, ay = y + ny * half, bx = x - nx * half, by = y - ny * half;
    if (st > 0 && !gap && random(1) >= protection(x, y)) {
      g.vertex(pax, pay); g.vertex(pbx, pby); g.vertex(ax, ay);
      g.vertex(pbx, pby); g.vertex(bx, by); g.vertex(ax, ay);
    }
    pax = ax; pay = ay; pbx = bx; pby = by;
  }
}

// the smallest turn from angle a to angle b, -PI .. PI
float angleBetween(float a, float b) {
  return atan2(sin(b - a), cos(b - a));
}

// how many to make this frame from a rate that can be a fraction: 0.3 gives one about 3 frames
// in 10, 2.5 gives two or three
int countFor(float rate) {
  return (int) rate + (random(1) < rate - (int) rate ? 1 : 0);
}

// the colour for one of the mark systems (prefix "splat", "line" or "frag"): picked up where it
// lands (as COLOUR's "pick up from" says) or the accent, then pushed away from the photo's
// lightness there by the system's "contrast" - dark spots get light marks and light spots dark ones
color systemColour(String prefix, float x, float y) {
  color c;
  if (v(prefix + "Colour") == 1) c = accentNow;
  else {
    Paint p = new Paint();
    p.pickup = (int) v("pickup");
    p.mix = v("mix");
    c = p.pickRaw(x, y);
  }
  float k = v(prefix + "Contrast");
  if (k > 0) c = lerpColor(c, brightness(photoAt(x, y)) > 128 ? color(0) : color(255), k * 0.85);
  return c;
}
