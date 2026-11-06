// Pencil: lines that grow a little every frame, as if someone were sketching with a coloured
// pencil - the panel's PENCIL box.
//
// A few pencils are on the paper at once, and each moves on by "speed" pixels a frame until its
// line is "line length" long; then it lifts, and (with "passes" above 1) goes down again close to
// where that line began and goes over it again, a little off - the searching, repeated lines of a
// sketch. How each one steers:
//
//   trace the edges   it walks along the edge of the dark parts of the chosen map - where the map
//                     crosses "level" - the way you'd draw round a shape: across the slope of the
//                     map, not down into the dark. Where it drifts off the edge it's turned back
//                     towards it, as tightly as "hold" says
//   flow              postContemp's continuous flow: the map's value where the pencil is gives a
//                     direction (dark 0 degrees, light all the way round), and the pencil keeps
//                     turning towards it - swirls that follow the map's light and dark
//   wander            postContemp's random walk: a new direction to turn towards every so often,
//                     and pulled along the form as much as MOVEMENT's "follow the form" says
//
// The line is thin and grainy: how much colour it leaves is broken up by a paper grain that stays
// put, so lines going over the same place catch the same grain, and it changes with pressure as
// the hand presses harder and lighter. Each line is one colour, picked where it starts (COLOUR).
// "Hatching" adds groups of short parallel strokes in the dark parts. Protected parts
// (ABSTRACTION) lift the pencil.

ArrayList<Pencil> pencils = new ArrayList<Pencil>();
float[] pencilMap;                 // the chosen map, blurred so the pencils steer smoothly
String pencilMapFor = "";          // which picture and map pencilMap was made from
final float PENCIL_STEP = 2;       // pixels a pencil moves at a time

void paintPencils(PGraphics g) {
  smoothPencilMap();
  // finished lines go round again, or make way for new ones
  for (int i = pencils.size() - 1; i >= 0; i--) {
    Pencil p = pencils.get(i);
    if (!p.done) continue;
    pencils.remove(i);
    if (p.passesLeft > 0) pencils.add(p.again());
  }
  int want = (int) t("count");
  for (int tries = 0; pencils.size() < want && tries < want; tries++) {
    Pencil p = newPencil();
    if (p != null) pencils.add(p);
  }
  while (pencils.size() > want) pencils.remove(pencils.size() - 1);

  g.noStroke();
  g.beginShape(TRIANGLES);
  int steps = max(1, round(t("speed") / PENCIL_STEP));
  for (Pencil p : pencils) {
    for (int s = 0; s < steps && !p.done; s++) p.step(g);
  }
  int groups = countFor(t("hatch"));
  for (int k = 0; k < groups; k++) hatchGroup(g);
  g.endShape();
}

// a new pencil going down, or null if there's nowhere for it this time
Pencil newPencil() {
  float[] s = startPoint();
  if (s == null) return null;
  int kind = (int) t("kind");
  if (kind == 0 && t("startAt") != 3) {
    // tracing: it has to start on an edge - try spots until one is
    for (int k = 0; k < 40 && !onEdge(s[0], s[1]); k++) {
      s = startPoint();
      if (s == null) return null;
    }
    if (!onEdge(s[0], s[1])) return null;
  }
  Pencil p = new Pencil(s[0], s[1], 0);
  if (kind == 0) {
    float[] gr = pencilSlope(p.x, p.y);
    p.heading = atan2(gr[0], -gr[1]) + (random(1) < 0.5 ? PI : 0);   // along the edge, either way
  } else if (kind == 1) p.heading = flowAngle(p.x, p.y);
  else p.heading = random(TWO_PI);
  p.firstHeading = p.wanderTo = p.heading;
  p.passesLeft = (int) t("passes") - 1;
  return p;
}

boolean onEdge(float x, float y) {
  float[] gr = pencilSlope(x, y);
  return abs(pencilAt(x, y) - t("level")) < 0.05 && gr[2] > 0.0004;
}

class Pencil {
  float x, y, heading, firstHeading, x0, y0;
  float turning = 0, seed = random(1000), drawn = 0, len;
  int passesLeft = 0, lost = 0, sinceTurn = 0;
  float wanderTo;
  color c;
  float alpha;
  boolean done = false, straight = false, down = false;
  float pax, pay, pbx, pby;        // the last step's two edge points

  Pencil(float x, float y, float heading) {
    this.x = x0 = x;
    this.y = y0 = y;
    this.heading = wanderTo = heading;
    len = t("length") * random(0.7, 1.15);
    c = systemColour(x, y);
    alpha = toolAlpha(x, y);
  }

  // the same line again: down a little off where it started, the same colour
  Pencil again() {
    float off = 1.5 + t("width") + 6 * t("wobble");
    Pencil p = new Pencil(constrain(x0 + randomGaussian() * off, 0, photo.width - 1),
                          constrain(y0 + randomGaussian() * off, 0, photo.height - 1), 0);
    p.heading = p.firstHeading = firstHeading + randomGaussian() * 0.1;
    p.wanderTo = p.heading;
    p.c = c;
    p.alpha = alpha;
    p.passesLeft = passesLeft - 1;
    return p;
  }

  void step(PGraphics g) {
    if (!straight) steer();
    x += cos(heading) * PENCIL_STEP;
    y += sin(heading) * PENCIL_STEP;
    drawn += PENCIL_STEP;
    if (x < 2 || y < 2 || x >= photo.width - 3 || y >= photo.height - 3 || drawn > len) {
      done = true;
      return;
    }
    // the hand: pressing harder and lighter, and lighter still where it goes down and lifts off
    float ends = min(1, min(drawn, len - drawn) / 16 + 0.15);
    float press = lerp(1, 0.25 + 1.1 * noise(seed, drawn * 0.006), t("pressure")) * ends;
    float half = max(0.25, t("width") / 2 * (0.6 + 0.4 * press));
    float nx = -sin(heading), ny = cos(heading);
    float ax = x + nx * half, ay = y + ny * half, bx = x - nx * half, by = y - ny * half;
    // protected parts lift the pencil
    boolean drawing = protection(x, y) < 0.5;
    if (drawing && down) {
      float a = alpha * (0.35 + 0.65 * min(1, press));
      grainVertex(g, pax, pay, a);
      grainVertex(g, pbx, pby, a);
      grainVertex(g, ax, ay, a);
      grainVertex(g, pbx, pby, a);
      grainVertex(g, bx, by, a);
      grainVertex(g, ax, ay, a);
      markCount++;
    }
    down = drawing;
    pax = ax; pay = ay; pbx = bx; pby = by;
  }

  void grainVertex(PGraphics g, float vx, float vy, float a) {
    g.fill(c, a * paperGrain(vx, vy));
    g.vertex(vx, vy);
  }

  // which way to go next, for the kind of line, with the hand's wobble on top
  void steer() {
    int kind = (int) t("kind");
    float hold = t("hold");
    if (kind == 0) {
      float m = pencilAt(x, y);
      float[] gr = pencilSlope(x, y);
      if (gr[2] > 0.0004) {
        // along the edge (across the slope), keeping on the way it's going ...
        float ux = gr[0] / gr[2], uy = gr[1] / gr[2];          // uphill: towards the light
        float tx = -uy, ty = ux;
        if (tx * cos(heading) + ty * sin(heading) < 0) { tx = -tx; ty = -ty; }
        // ... and back towards the edge: downhill where it's too light, uphill where too dark
        float pull = constrain((m - t("level")) / 0.08, -1, 1) * (0.3 + 1.5 * hold);
        float target = atan2(ty - uy * pull, tx - ux * pull);
        heading += angleBetween(heading, target) * (0.08 + 0.4 * hold);
      }
      // wandered off into flat or far-off parts: lift
      lost = gr[2] < 0.0004 || abs(m - t("level")) > 0.2 ? lost + 1 : 0;
      if (lost > 40) done = true;
    } else if (kind == 1) {
      heading += angleBetween(heading, flowAngle(x, y)) * (0.03 + 0.3 * hold);
    } else {
      // a new direction to turn towards every 20 steps or so ...
      if (++sinceTurn > 20 * random(0.5, 1.5)) {
        wanderTo = heading + random(-PI, PI) * 0.8;
        sinceTurn = 0;
      }
      heading += angleBetween(heading, wanderTo) * 0.08;
      // ... and pulled along the form (whichever way along it is nearer)
      float follow = t("follow");
      if (follow > 0) {
        float[] f = fieldAt(x, y);
        float d = angleBetween(heading, atan2(f[1], f[0]));
        if (abs(d) > HALF_PI) d = angleBetween(heading, atan2(f[1], f[0]) + PI);
        heading += d * 0.2 * follow * f[2];
      }
    }
    // the wobble of a hand: a turning that drifts, so it curves one way then the other
    turning = turning * 0.9 + randomGaussian() * t("wobble") * 0.035;
    heading += turning;
  }
}

// flow: the direction the map gives at (x, y) - dark 0, light all the way round - turned by "turn"
float flowAngle(float x, float y) {
  return pencilAt(x, y) * TWO_PI + radians(t("turn"));
}

// a group of short parallel strokes somewhere darker than "level", closer together, longer and
// more of them the darker it is
void hatchGroup(PGraphics g) {
  float level = t("level");
  float x = 0, y = 0, m = 1;
  for (int k = 0; k < 30 && m >= level; k++) {
    float[] s = startPoint();
    if (s == null) return;
    x = s[0];
    y = s[1];
    m = pencilAt(x, y);
  }
  if (m >= level || protection(x, y) >= 0.5) return;
  float dark = constrain((level - m) / max(level, 0.05), 0, 1);
  float ang = radians(t("hatchAngle")) + randomGaussian() * 0.08;
  float ca = cos(ang), sa = sin(ang);
  int n = 3 + (int) random(3 + 6 * dark);
  float gap = t("width") * 1.5 + 2 + (1 - dark) * 5;
  float L = (10 + 30 * dark) * random(0.7, 1.2);
  color c = systemColour(x, y);
  float a = toolAlpha(x, y);
  for (int k = 0; k < n; k++) {
    float o = (k - n / 2.0) * gap;
    float cx = x - sa * o + ca * randomGaussian() * 2, cy = y + ca * o + sa * randomGaussian() * 2;
    if (pencilAt(cx, cy) >= level) continue;            // the strokes stay in the dark part
    float l = L * random(0.7, 1.1);
    Pencil p = new Pencil(cx - ca * l / 2, cy - sa * l / 2, ang + randomGaussian() * 0.04);
    p.straight = true;
    p.len = l;
    p.c = c;
    p.alpha = a;
    while (!p.done) p.step(g);
  }
}

// paper grain at (x, y), 0 .. 1 - fixed in place, so every line over a spot catches the same tooth
float paperGrain(float x, float y) {
  float k = t("grain");
  if (k <= 0) return 1;
  float fine = (float) (Math.sin(floor(x) * 12.9898 + floor(y) * 78.233) * 43758.5453);
  fine -= floor(fine);
  float tooth = 0.55 * noise(x * 0.45, y * 0.45, 77) + 0.45 * fine;
  return lerp(1, smoothstep(0.3, 0.7, tooth), k);
}

// the chosen map at (x, y), 0 .. 1, blurred, smooth between pixels - turned over with
// "follow the light parts", so the light parts count as the dark
float pencilAt(float x, float y) {
  int w = photo.width, h = photo.height;
  x = constrain(x, 0, w - 1.001);
  y = constrain(y, 0, h - 1.001);
  int i = (int) x, j = (int) y, k = i + j * w;
  float fx = x - i, fy = y - j;
  float a = lerp(pencilMap[k], pencilMap[k + 1], fx), b = lerp(pencilMap[k + w], pencilMap[k + w + 1], fx);
  float m = lerp(a, b, fy);
  return t("inv") > 0.5 ? 1 - m : m;
}

// which way is uphill (towards the light) at (x, y), and how steeply: { x, y, steepness }
float[] pencilSlope(float x, float y) {
  float gx = (pencilAt(x + 2, y) - pencilAt(x - 2, y)) / 4, gy = (pencilAt(x, y + 2) - pencilAt(x, y - 2)) / 4;
  return new float[] { gx, gy, sqrt(gx * gx + gy * gy) };
}

// the chosen map, blurred, made again when the map or the picture changes
void smoothPencilMap() {
  int m = (int) t("map") + 1;                    // the list leaves out "none"
  String key = faceName + " " + m;
  if (key.equals(pencilMapFor) && pencilMap != null) return;
  int w = photo.width, h = photo.height;
  float[] a = new float[w * h];
  for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) a[x + y * w] = mapAt(m, x, y);
  for (int pass = 0; pass < 2; pass++) {
    boxBlur(a, w, h, 4, true);
    boxBlur(a, w, h, 4, false);
  }
  pencilMap = a;
  pencilMapFor = key;
}

// a box blur of radius r along the rows (or down the columns), in place
void boxBlur(float[] a, int w, int h, int r, boolean rows) {
  int n = rows ? w : h, lines = rows ? h : w;
  float[] line = new float[n];
  for (int l = 0; l < lines; l++) {
    for (int i = 0; i < n; i++) line[i] = a[rows ? i + l * w : l + i * w];
    float sum = 0;
    for (int i = -r; i <= r; i++) sum += line[constrain(i, 0, n - 1)];
    for (int i = 0; i < n; i++) {
      a[rows ? i + l * w : l + i * w] = sum / (2 * r + 1);
      sum += line[min(i + r + 1, n - 1)] - line[max(i - r, 0)];
    }
  }
}
