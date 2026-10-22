// The bristle stroke (from strokeField): start at a spot, walk along the direction field for the
// stroke's length, and draw a ribbon along that path - blunt at the start, tapering towards the
// end, with slightly ragged edges.

void paintStroke(PGraphics g, float x, float y, float len, float wid, float follow, Paint p) {
  // The starting direction: the field's, turned by up to 90 degrees when following is low.
  // At 0% following that's any direction at all; at 70% it's within about 27 degrees.
  float[] f = fieldAt(x, y);
  float turn = random(-1, 1) * (1 - follow) * HALF_PI;
  float startAngle = f[2] > 0.05 ? atan2(f[1], f[0]) + turn : random(TWO_PI);
  if (random(1) < 0.5) startAngle += PI;            // strokes can go either way along the field
  float hx = cos(startAngle), hy = sin(startAngle);

  // walk along the field
  int steps = max(2, ceil(len / 4));
  float stepLen = len / steps;
  float bend = v("curving");
  float[] px = new float[steps + 1], py = new float[steps + 1];
  px[0] = x;
  py[0] = y;
  for (int s = 1; s <= steps; s++) {
    f = fieldAt(px[s - 1], py[s - 1]);
    // the field has no front or back - pick the way that's closest to where we're heading
    float tx = cos(atan2(f[1], f[0]) + turn), ty = sin(atan2(f[1], f[0]) + turn);
    if (tx * hx + ty * hy < 0) { tx = -tx; ty = -ty; }
    float k = follow * f[2] * bend;                // how hard the field steers this step
    hx = lerp(hx, tx, k);
    hy = lerp(hy, ty, k);
    float hl = max(sqrt(hx * hx + hy * hy), 1e-4);
    hx /= hl;
    hy /= hl;
    px[s] = px[s - 1] + hx * stepLen;
    py[s] = py[s - 1] + hy * stepLen;
  }

  // which way is "sideways" at each point
  float[] sx = new float[steps + 1], sy = new float[steps + 1];
  for (int s = 0; s <= steps; s++) {
    int a = max(0, s - 1), b = min(steps, s + 1);
    float dx = px[b] - px[a], dy = py[b] - py[a];
    float dl = max(sqrt(dx * dx + dy * dy), 1e-4);
    sx[s] = -dy / dl;
    sy[s] = dx / dl;
  }

  // the colours the brush loads
  if (p.carry == ONE) p.c0 = p.pick(px[0], py[0]);
  else if (p.carry == START_END) {
    p.c0 = p.pick(px[0], py[0]);
    p.c1 = p.pick(px[steps], py[steps]);
  } else if (p.carry == TWO) {
    p.c0 = p.pick(px[0] + sx[0] * wid / 4, py[0] + sy[0] * wid / 4);
    p.c1 = p.pick(px[0] - sx[0] * wid / 4, py[0] - sy[0] * wid / 4);
  }

  // draw the ribbon. For chunk, each edge's paint comes from the same distance either side of
  // where the stroke started, so the start gets smeared along the whole stroke
  float seed = random(1000), taper = v("taper"), rough = v("ragged");
  p.begin(g);
  for (int s = 0; s <= steps; s++) {
    float t = s / (float) steps;
    float shape = (0.7 + 0.3 * min(1, t * 5)) * (1 - taper * pow(t, 3));    // blunt start, pointed end
    float wl = wid * 0.5 * shape * (1 + rough * (noise(seed, s * 0.35) - 0.5));
    float wr = wid * 0.5 * shape * (1 + rough * (noise(seed + 50, s * 0.35) - 0.5));
    p.vertex(g, px[s] + sx[s] * wl, py[s] + sy[s] * wl, px[0] + sx[0] * wl, py[0] + sy[0] * wl, t, 0, p.alpha);
    p.vertex(g, px[s] - sx[s] * wr, py[s] - sy[s] * wr, px[0] - sx[0] * wr, py[0] - sy[0] * wr, t, 1, p.alpha);
  }
  p.end(g);
}
