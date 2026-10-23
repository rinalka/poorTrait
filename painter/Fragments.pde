// Fragments (design doc Stage 5): tiny dots, dashes, triangles and shards - a mark system of
// their own in the panel's FRAGMENTS block.
//
// Each fragment is placed by "start at" like the other marks, or, with "clumping", near the one
// before it, so they gather in little drifts. Sizes are mostly small with a few bigger ones.
// "Lined up with the form" turns that share of them along the direction field; the rest point
// anywhere. Fragments respect ABSTRACTION.
//
// All the fragments in a frame are one shape made of triangles.

void paintFragments(PGraphics g) {
  if (v("fragOn") < 0.5) return;
  IntList kinds = new IntList();                 // 0 dots, 1 dashes, 2 triangles, 3 shards
  if (v("fragDots") > 0.5) kinds.append(0);
  if (v("fragDashes") > 0.5) kinds.append(1);
  if (v("fragTris") > 0.5) kinds.append(2);
  if (v("fragShards") > 0.5) kinds.append(3);
  int n = countFor(v("fragRate"));
  if (kinds.size() == 0 || n == 0) return;

  g.noStroke();
  g.beginShape(TRIANGLES);
  float lastX = -1, lastY = -1;
  for (int i = 0; i < n; i++) {
    float x, y;
    if (lastX >= 0 && random(1) < v("fragClump")) {
      // near the last one
      x = constrain(lastX + randomGaussian() * v("fragSize") * 4, 0, photo.width - 1);
      y = constrain(lastY + randomGaussian() * v("fragSize") * 4, 0, photo.height - 1);
    } else {
      float[] s = startPoint();
      if (s == null) continue;
      x = s[0];
      y = s[1];
    }
    if (random(1) < protection(x, y)) continue;
    lastX = x;
    lastY = y;
    fragment(g, x, y, kinds.get((int) random(kinds.size())));
  }
  g.endShape();
}

void fragment(PGraphics g, float x, float y, int kind) {
  float size = v("fragSize") * pow(random(0.2, 1), 1.5);
  float[] f = fieldAt(x, y);
  float ang = random(1) < v("fragFollow") && f[2] > 0.05 ? atan2(f[1], f[0]) : random(TWO_PI);
  float ca = cos(ang), sa = sin(ang);
  g.fill(systemColour("frag", x, y), 255 * v("fragOpacity") * random(0.7, 1));

  if (kind == 0) {                                // a dot
    disc(g, x, y, max(0.6, size * 0.4), 7);
  } else if (kind == 1) {                         // a dash: a short thin bar
    float l = size * random(1, 2.5) / 2, w = max(0.4, size * random(0.12, 0.3) / 2);
    float ax = ca * l, ay = sa * l, bx = -sa * w, by = ca * w;
    g.vertex(x - ax - bx, y - ay - by); g.vertex(x + ax - bx, y + ay - by); g.vertex(x + ax + bx, y + ay + by);
    g.vertex(x - ax - bx, y - ay - by); g.vertex(x + ax + bx, y + ay + by); g.vertex(x - ax + bx, y - ay + by);
  } else if (kind == 2) {                         // a triangle, never quite regular
    for (int k = 0; k < 3; k++) {
      float a = ang + TWO_PI * k / 3 + random(-0.4, 0.4), r = size * random(0.4, 0.7);
      g.vertex(x + cos(a) * r, y + sin(a) * r);
    }
  } else {                                        // a shard: a long, thin, sharp sliver
    float l = size * random(0.8, 1.6), w = size * random(0.1, 0.3), off = random(-0.4, 0.4);
    // tip, side, other tip, other side - the widest point off-centre, so it isn't a neat diamond
    float[][] p = { { l, 0 }, { off * l, w }, { -l * random(0.5, 1), 0 }, { off * l * 0.5, -w * random(0.3, 1) } };
    float[] px = new float[4], py = new float[4];
    for (int k = 0; k < 4; k++) {
      px[k] = x + p[k][0] * ca - p[k][1] * sa;
      py[k] = y + p[k][0] * sa + p[k][1] * ca;
    }
    g.vertex(px[0], py[0]); g.vertex(px[1], py[1]); g.vertex(px[2], py[2]);
    g.vertex(px[0], py[0]); g.vertex(px[2], py[2]); g.vertex(px[3], py[3]);
  }
}
