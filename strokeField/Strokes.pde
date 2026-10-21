// One stroke: pick a spot, decide how big the stroke is there, then walk along the direction
// field for the stroke's length, and draw a ribbon along that path.
//
// The ribbon starts blunt and tapers to a point at the end, with slightly ragged edges, and its
// colour slides from the photo's colour at the start to the photo's colour at the end - as if the
// brush dragged one colour into the next.

void paintStroke(PGraphics g) {
  float x = random(photo.width), y = random(photo.height);

  // smaller strokes where the face matters most
  float importance = (importanceImg.pixels[(int) x + (int) y * photo.width] >> 16 & 255) / 255.0;
  float size = lerp(1, 0.2, importance * detail());
  float len = random(0.4, 1) * lengthMax() * size;
  float wid = random(0.4, 1) * widthMax() * size;

  // The starting direction: the field's, turned by up to 90 degrees when following is low.
  // At 0% following that's any direction at all; at 70% it's within about 27 degrees.
  float[] f = fieldAt(x, y);
  float turn = random(-1, 1) * (1 - following()) * HALF_PI;
  float startAngle = f[2] > 0.05 ? atan2(f[1], f[0]) + turn : random(TWO_PI);
  if (random(1) < 0.5) startAngle += PI;            // strokes can go either way along the field
  float hx = cos(startAngle), hy = sin(startAngle);

  // walk along the field
  int steps = max(2, ceil(len / 4));
  float stepLen = len / steps;
  float[] px = new float[steps + 1], py = new float[steps + 1];
  px[0] = x;
  py[0] = y;
  for (int s = 1; s <= steps; s++) {
    f = fieldAt(px[s - 1], py[s - 1]);
    // the field has no front or back - pick the way that's closest to where we're heading
    float tx = cos(atan2(f[1], f[0]) + turn), ty = sin(atan2(f[1], f[0]) + turn);
    if (tx * hx + ty * hy < 0) { tx = -tx; ty = -ty; }
    float k = following() * f[2] * 0.5;            // how hard the field steers this step
    hx = lerp(hx, tx, k);
    hy = lerp(hy, ty, k);
    float hl = sqrt(hx * hx + hy * hy);
    hx /= hl;
    hy /= hl;
    px[s] = px[s - 1] + hx * stepLen;
    py[s] = py[s - 1] + hy * stepLen;
  }

  color c0 = jitter(photoAt(px[0], py[0]));
  color c1 = jitter(photoAt(px[steps], py[steps]));

  // draw the ribbon
  float seed = random(1000);
  g.noStroke();
  g.beginShape(TRIANGLE_STRIP);
  for (int s = 0; s <= steps; s++) {
    float t = s / (float) steps;
    // which way is "sideways" here
    int a = max(0, s - 1), b = min(steps, s + 1);
    float dx = px[b] - px[a], dy = py[b] - py[a];
    float dl = max(sqrt(dx * dx + dy * dy), 1e-4);
    float sx = -dy / dl, sy = dx / dl;
    // blunt start, pointed end, ragged edges
    float shape = (0.7 + 0.3 * min(1, t * 5)) * (1 - pow(t, 3));
    float wl = wid * 0.5 * shape * (0.75 + 0.5 * noise(seed, s * 0.35));
    float wr = wid * 0.5 * shape * (0.75 + 0.5 * noise(seed + 50, s * 0.35));
    g.fill(lerpColor(c0, c1, t), alphaPaint);
    g.vertex(px[s] + sx * wl, py[s] + sy * wl);
    g.vertex(px[s] - sx * wr, py[s] - sy * wr);
  }
  g.endShape();
}

color photoAt(float x, float y) {
  int ix = constrain((int) x, 0, photo.width - 1), iy = constrain((int) y, 0, photo.height - 1);
  return photo.pixels[ix + iy * photo.width];
}

// a little lighter or darker, a little warmer or cooler
color jitter(color c) {
  float l = random(-1, 1) * colourJitter;
  float w = random(-1, 1) * colourJitter * 0.5;
  return color(constrain(red(c) + l + w, 0, 255), constrain(green(c) + l, 0, 255), constrain(blue(c) + l - w, 0, 255));
}
