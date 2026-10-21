// One palette-knife mark.
//
// A knife mark is laid out along a short, slightly bent line - the way the knife was dragged -
// and described by how far its two edges are from that line at each point along it:
//
//      u = 0 (where the knife landed: blunt)  ...........  u = 1 (where it lifted: torn)
//
// One edge is the knife's edge: fairly straight, with a ridge of paint piled up along it.
// The other is where the paint ran out: ragged. Both wander with smooth noise, plus one or two
// sudden steps - the design doc's "smooth noise combined with a few sharp discontinuities", so
// it doesn't look like every point was jiggled on its own.
//
// Inside, the paint is nearly one colour (the photo's average under the mark), with streaks of
// a second colour dragged through it from where the knife picked it up. The end is torn: the
// paint reaches further in some places than others (smoothly, so it reads as torn rather than
// as a comb), with the odd gap where the knife skipped. Some marks are leaf or shard shaped -
// pointed at both ends - instead of square-ended.

void paintKnife(PGraphics g) {
  float cx = random(photo.width), cy = random(photo.height);

  // smaller marks where the face matters most
  float importance = (importanceImg.pixels[(int) cx + (int) cy * photo.width] >> 16 & 255) / 255.0;
  float size = lerp(1, 0.2, importance * detail());
  float len = random(0.5, 1) * knifeLength() * size;
  float wid = len * random(0.6, 1.3) * knifeWidth();

  // which way the knife is dragged - the field's direction, turned by up to 90 degrees when
  // following is low (the same rule as strokeField's strokes)
  float[] f = fieldAt(cx, cy);
  float turn = random(-1, 1) * (1 - following()) * HALF_PI;
  float angle = f[2] > 0.05 ? atan2(f[1], f[0]) + turn : random(TWO_PI);
  if (random(1) < 0.5) angle += PI;
  Blade b = new Blade(cx, cy, angle, len, wid);

  // colours: the main one is the average of the photo under the mark, so it's nearly flat;
  // the streak colour comes from just beside the mark, as if the knife dragged it in
  color main = jitter(averageUnder(b));
  float side = random(1) < 0.5 ? 1 : -1;
  float[] p = b.at(random(0, 0.3), side * wid * random(0.6, 1.1));
  color streak = jitter(photoAt(p[0], p[1]));
  float alpha = random(1) < washChance ? random(70, 130) : random(225, 255);

  g.noStroke();
  // the body, stopping short of the end where it breaks up
  float bodyEnd = random(0.72, 0.88);
  b.band(g, 0, bodyEnd, -1, 1, main, alpha, alpha);

  // the torn end: thin slices across the mark, each reaching a different distance past the
  // body. The reach changes smoothly from slice to slice, and now and then a slice is missing
  int slices = 16;
  float tearSeed = random(1000);
  float tear = 0.1 + 0.25 * roughness();
  for (int k = 0; k < slices; k++) {
    if (random(1) < 0.08 * roughness()) continue;      // a gap where the knife skipped
    float reach = bodyEnd + tear * noise(tearSeed, k * 0.3);
    b.band(g, bodyEnd - 0.01, reach, map(k, 0, slices, -1, 1), map(k + 1, 0, slices, -1, 1), main, alpha, alpha * 0.6);
  }

  // streaks of the second colour, strongest where the knife landed, fading out along the drag
  int streaks = round(streakAmount() * random(1, 4));
  for (int k = 0; k < streaks; k++) {
    float v0 = random(-1, 0.7), v1 = v0 + random(0.08, 0.4);
    b.band(g, random(0, 0.1), random(0.3, 0.9), v0, v1, streak, alpha * 0.6, 0);
  }

  // the ridge along the knife's edge: a thin strip, lighter if that edge faces the light
  // (from the upper left), darker if it faces away
  float[] edgeNormal = b.sideNormal(b.ridgeSide);
  boolean lit = edgeNormal[0] * -0.7 + edgeNormal[1] * -0.7 > 0;
  color ridge = lit ? lerpColor(main, color(255), 0.35) : lerpColor(main, color(0), 0.35);
  float r = b.ridgeSide;
  b.band(g, 0.02, bodyEnd, r * 0.9, r * 1.0, ridge, alpha * 0.5, alpha * 0.15);
}

// The shape of one mark, and how to draw parts of it.
class Blade {
  float x0, y0, dx, dy, nx, ny;   // start of the line, its direction, and sideways
  float len, wid, bend;
  int samples;                    // points along each edge
  float[] edgeA, edgeB;           // how far each edge is from the line, in pixels, at each sample
  float ridgeSide;                // +1 or -1: which edge is the knife's straight edge
  boolean leaf;                   // pointed at both ends instead of square-ended

  Blade(float cx, float cy, float angle, float len, float wid) {
    this.len = len;
    this.wid = wid;
    dx = cos(angle);
    dy = sin(angle);
    nx = -dy;
    ny = dx;
    x0 = cx - dx * len / 2;
    y0 = cy - dy * len / 2;
    bend = random(-0.08, 0.08);
    samples = (int) random(8, 16);
    ridgeSide = random(1) < 0.5 ? 1 : -1;
    leaf = random(1) < leafChance;

    float rough = roughness();
    float seedA = random(1000), seedB = random(1000);
    // one or two places where an edge suddenly jumps in or out
    float stepAt = random(0.2, 0.8), stepBy = random(-0.25, 0.25) * rough;
    float step2At = random(1) < 0.5 ? random(0.3, 0.9) : 2, step2By = random(-0.2, 0.2) * rough;

    edgeA = new float[samples];
    edgeB = new float[samples];
    for (int i = 0; i < samples; i++) {
      float u = i / (float) (samples - 1);
      // lands blunt (a little narrower at the very start), full width in the middle,
      // narrowing towards the end
      float profile = leaf ? pow(sin(PI * (0.06 + 0.88 * u)), 0.6)
                           : (0.8 + 0.2 * min(1, u * 6)) * (1 - 0.35 * u * u);
      float straight = 1 + rough * 0.15 * (noise(seedA, u * 2) - 0.5);           // the knife's edge
      float ragged = 1 + rough * 0.9 * (noise(seedB, u * 4) - 0.5)                // where paint ran out
                     + (u > stepAt ? stepBy : 0) + (u > step2At ? step2By : 0);
      float half = wid / 2 * profile;
      if (ridgeSide > 0) { edgeA[i] = half * straight; edgeB[i] = half * max(0.2, ragged); }
      else               { edgeA[i] = half * max(0.2, ragged); edgeB[i] = half * straight; }
    }
  }

  // a point on the mark: u along it (0 .. 1, a little past 1 for the torn end), v sideways in pixels
  float[] at(float u, float v) {
    float b = bend * len * sin(PI * constrain(u, 0, 1));
    float ax = x0 + dx * len * u + nx * b, ay = y0 + dy * len * u + ny * b;
    return new float[] { ax + nx * v, ay + ny * v };
  }

  // how far the +1 / -1 edge is from the line at u (in between the samples it's interpolated)
  float edge(float u, float sideSign) {
    float t = constrain(u, 0, 1) * (samples - 1);
    int i = min((int) t, samples - 2);
    float[] e = sideSign > 0 ? edgeA : edgeB;
    return lerp(e[i], e[i + 1], t - i);
  }

  // the direction the +1 / -1 edge faces, outwards
  float[] sideNormal(float sideSign) {
    return new float[] { nx * sideSign, ny * sideSign };
  }

  // Fill the part of the mark from u0 to u1 and from v0 to v1 across it, where v -1 is one edge
  // and +1 the other (so a band is always inside the mark's outline). The colour fades from
  // alpha a0 at u0 to a1 at u1.
  void band(PGraphics g, float u0, float u1, float v0, float v1, color c, float a0, float a1) {
    int steps = max(2, round(samples * (u1 - u0)) + 1);
    g.beginShape(TRIANGLE_STRIP);
    for (int s = 0; s <= steps; s++) {
      float t = s / (float) steps;
      float u = lerp(u0, u1, t);
      // where -1 and +1 are at this u
      float plus = edge(u, 1), minus = -edge(u, -1);
      float va = lerp(minus, plus, (v0 + 1) / 2), vb = lerp(minus, plus, (v1 + 1) / 2);
      g.fill(c, lerp(a0, a1, t));
      float[] p = at(u, va), q = at(u, vb);
      g.vertex(p[0], p[1]);
      g.vertex(q[0], q[1]);
    }
    g.endShape();
  }
}

// the photo's average colour over a few points spread through the mark
color averageUnder(Blade b) {
  float r = 0, gr = 0, bl = 0;
  int n = 0;
  for (float u = 0.15; u < 0.9; u += 0.25) {
    for (float v = -0.5; v <= 0.5; v += 0.5) {
      float[] p = b.at(u, v * b.wid / 2);
      color c = photoAt(p[0], p[1]);
      r += red(c);
      gr += green(c);
      bl += blue(c);
      n++;
    }
  }
  return color(r / n, gr / n, bl / n);
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
