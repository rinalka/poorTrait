// One palette-knife mark (from knifeField).
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
// Inside, the paint is whatever the panel's "carry" says (see the Paint class in the Marks tab),
// with streaks of a second colour dragged through it from beside the mark. The end is torn: the
// paint reaches further in some places than others, with the odd gap where the knife skipped.
// Some marks are leaf or shard shaped - pointed at both ends - instead of square-ended.

void paintKnife(PGraphics g, float cx, float cy, float len, float wid, float follow, Paint p) {
  // which way the knife is dragged - the field's direction, turned by up to 90 degrees when
  // following is low (the same rule as the bristle strokes)
  float[] f = fieldAt(cx, cy);
  float turn = random(-1, 1) * (1 - follow) * HALF_PI;
  float angle = f[2] > 0.05 ? atan2(f[1], f[0]) + turn : random(TWO_PI);
  if (random(1) < 0.5) angle += PI;
  Blade b = new Blade(cx, cy, angle, len, wid);

  // colours: the main one is the average under the mark, so it's nearly flat
  color main = averageUnder(b, p);
  if (p.carry == ONE) p.c0 = main;
  else if (p.carry == START_END) {
    float[] q0 = b.at(0.1, 0), q1 = b.at(0.9, 0);
    p.c0 = p.pick(q0[0], q0[1]);
    p.c1 = p.pick(q1[0], q1[1]);
  } else if (p.carry == TWO) {
    float[] q0 = b.at(0.4, -wid * 0.25), q1 = b.at(0.4, wid * 0.25);
    p.c0 = p.pick(q0[0], q0[1]);
    p.c1 = p.pick(q1[0], q1[1]);
  }
  float alpha = p.alpha;

  // the body, stopping short of the end where it breaks up
  float bodyEnd = random(0.72, 0.88);
  b.band(g, 0, bodyEnd, -1, 1, p, alpha, alpha);

  // the torn end: thin slices across the mark, each reaching a different distance past the
  // body. The reach changes smoothly from slice to slice, and now and then a slice is missing
  int slices = 16;
  float tearSeed = random(1000);
  float rough = b.rough;
  float tear = 0.1 + 0.25 * rough;
  for (int k = 0; k < slices; k++) {
    if (random(1) < 0.08 * rough) continue;      // a gap where the knife skipped
    float reach = bodyEnd + tear * noise(tearSeed, k * 0.3);
    b.band(g, bodyEnd - 0.01, reach, map(k, 0, slices, -1, 1), map(k + 1, 0, slices, -1, 1), p, alpha, alpha * 0.6);
  }

  // streaks of a second colour from just beside the mark, as if the knife dragged it in -
  // strongest where the knife landed, fading out along the drag. Chunk and copy carry the
  // picture's own streaks, so they don't get these
  if (!p.textured()) {
    float side = random(1) < 0.5 ? 1 : -1;
    float[] q = b.at(random(0, 0.3), side * wid * random(0.6, 1.1));
    Paint streak = p.flat(p.pick(q[0], q[1]));
    int streaks = round(v("streaks") * random(1, 4));
    for (int k = 0; k < streaks; k++) {
      float v0 = random(-1, 0.7), v1 = v0 + random(0.08, 0.4);
      b.band(g, random(0, 0.1), random(0.3, 0.9), v0, v1, streak, alpha * 0.6, 0);
    }
  }

  // the ridge along the knife's edge: a thin strip, lighter if that edge faces the light
  // (from the upper left), darker if it faces away
  float ridge = v("ridge");
  if (ridge > 0) {
    float[] edgeNormal = b.sideNormal(b.ridgeSide);
    boolean lit = edgeNormal[0] * -0.7 + edgeNormal[1] * -0.7 > 0;
    Paint rp = p.flat(lerpColor(main, lit ? color(255) : color(0), 0.7 * ridge));
    float r = b.ridgeSide;
    b.band(g, 0.02, bodyEnd, r * 0.9, r * 1.0, rp, alpha * ridge, alpha * 0.3 * ridge);
  }
}

// The shape of one mark, and how to draw parts of it.
class Blade {
  float x0, y0, dx, dy, nx, ny;   // start of the line, its direction, and sideways
  float len, wid, bend, rough;
  int samples;                    // points along each edge
  float[] edgeA, edgeB;           // how far each edge is from the line, in pixels, at each sample
  float ridgeSide;                // +1 or -1: which edge is the knife's straight edge
  boolean leaf;                   // pointed at both ends instead of square-ended

  Blade(float cx, float cy, float angle, float len, float wid) {
    this(cx, cy, angle, len, wid, true);
  }

  // allowLeaf false: never leaf-shaped (scrapes)
  Blade(float cx, float cy, float angle, float len, float wid, boolean allowLeaf) {
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
    leaf = allowLeaf && random(1) < v("leaf");

    rough = v("ragged") * 1.5;
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
  // and +1 the other (so a band is always inside the mark's outline), with paint p. The paint
  // fades from alpha a0 at u0 to a1 at u1. For chunk, the paint at each corner comes from the
  // same distance across the mark where the knife landed (u = 0), so it's smeared along the drag.
  void band(PGraphics g, float u0, float u1, float v0, float v1, Paint p, float a0, float a1) {
    int steps = max(2, round(samples * (u1 - u0)) + 1);
    p.begin(g);
    for (int s = 0; s <= steps; s++) {
      float t = s / (float) steps;
      float u = lerp(u0, u1, t);
      // where -1 and +1 are at this u
      float plus = edge(u, 1), minus = -edge(u, -1);
      float va = lerp(minus, plus, (v0 + 1) / 2), vb = lerp(minus, plus, (v1 + 1) / 2);
      float a = lerp(a0, a1, t);
      float[] pa = at(u, va), pb = at(u, vb);
      float[] ka = at(0, va), kb = at(0, vb);
      p.vertex(g, pa[0], pa[1], ka[0], ka[1], constrain(u, 0, 1), (v0 + 1) / 2, a);
      p.vertex(g, pb[0], pb[1], kb[0], kb[1], constrain(u, 0, 1), (v1 + 1) / 2, a);
    }
    p.end(g);
  }
}

// the average colour the paint would pick up over a few points spread through the mark
color averageUnder(Blade b, Paint p) {
  float r = 0, gr = 0, bl = 0;
  int n = 0;
  for (float u = 0.15; u < 0.9; u += 0.25) {
    for (float v = -0.5; v <= 0.5; v += 0.5) {
      float[] q = b.at(u, v * b.wid / 2);
      color c = p.pickRaw(q[0], q[1]);
      r += red(c);
      gr += green(c);
      bl += blue(c);
      n++;
    }
  }
  return p.vary(color(r / n, gr / n, bl / n));
}
