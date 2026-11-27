// LINES' second kind, "darkest creases" (TEST1's black line, brought back): the very darkest parts of the
// light map - its creases: eyelids, nostrils, the mouth, the hair's curls - as spots a few pixels apart
// along the middle of each crease. Then, like the other lines, so many a frame (lines per frame), each
// starting where MOVEMENT's START AT says: it goes to the nearest spot not drawn yet, then on from spot
// to spot, always to the nearest not drawn yet, till it's "length" long. So bit by bit the creases fill
// in, and once every spot's been drawn the tool stops. The colour and opacity are COLOUR's and
// APPLY's, as for the other lines; "follow the form" doesn't come into it - the creases steer.
//
// "lift it between parts": at 0 a line goes straight on to the next crease, however far; turned up, it
// stops at a gap - a long one at first, at 1 any gap over a few pixels - so the parts stay apart.

final float CREASE_STEP = 3;            // the spots' grid (pixels)
float[] creaseX, creaseY;               // the spots, made at a run's first frame (null: not yet)
boolean[] creaseUsed;
int creaseLeft;                         // how many aren't drawn yet
String creaseKey = "";                  // what they were made from: darkest, the area

void resetCreases() {
  creaseX = null;
}

// whether (x, y) is where the spots may be: in the picture, and in IN AREA's area or out of it
boolean creaseInside(float x, float y) {
  if (x < 0 || y < 0 || x >= photo.width || y >= photo.height) return false;
  int a = areaWay();
  return a == 0 || !areaReady() || inArea(x, y) == (a == 1);
}

void paintCreases(PGraphics g) {
  String key = nf(t("darkest"), 0, 2) + " " + areaWay() + " " + System.identityHashCode(areaIn) + " " + photo.width;
  if (creaseX == null || !key.equals(creaseKey)) {
    makeCreases();
    creaseKey = key;
  }
  if (creaseLeft == 0) return;
  int n = countFor(t("rate"));
  if (n == 0) return;
  g.noFill();
  g.strokeJoin(ROUND);
  g.strokeCap(ROUND);
  for (int i = 0; i < n && creaseLeft > 0; i++) creaseLine(g);
}

// the spots: the light map's darkest share (darkest, %) in the area, only along a crease's middle
void makeCreases() {
  int[] count = new int[256];
  int total = 0;
  float step = CREASE_STEP;
  for (float y = step / 2; y < photo.height; y += step) {
    for (float x = step / 2; x < photo.width; x += step) {
      if (!creaseInside(x, y)) continue;
      count[constrain(round(mapAt(4, x, y) * 255), 0, 255)]++;
      total++;
    }
  }
  creaseX = new float[0];
  creaseY = new float[0];
  creaseUsed = new boolean[0];
  creaseLeft = 0;
  if (total == 0) return;
  // how dark is dark enough: the level under which the darkest share lies
  int cut = 0;
  for (int sum = 0; cut < 255; cut++) {
    sum += count[cut];
    if (sum >= total * t("darkest") / 100) break;
  }
  ArrayList<float[]> spots = new ArrayList<float[]>();
  for (float y = step / 2; y < photo.height; y += step) {
    for (float x = step / 2; x < photo.width; x += step) {
      if (!creaseInside(x, y)) continue;
      float v = mapAt(4, x, y);
      if (v * 255 > cut) continue;
      // darker than either side of it, across or down
      boolean across = v <= mapAt(4, x - 3, y) && v <= mapAt(4, x + 3, y);
      boolean down = v <= mapAt(4, x, y - 3) && v <= mapAt(4, x, y + 3);
      if (across || down) spots.add(new float[] { x + random(-0.7, 0.7), y + random(-0.7, 0.7) });
    }
  }
  // fewer of them, farther apart, if there are very many
  while (spots.size() > 6000) {
    ArrayList<float[]> fewer = new ArrayList<float[]>();
    for (int i = 0; i < spots.size(); i += 2) fewer.add(spots.get(i));
    spots = fewer;
  }
  int n = spots.size();
  creaseX = new float[n];
  creaseY = new float[n];
  creaseUsed = new boolean[n];
  creaseLeft = n;
  for (int i = 0; i < n; i++) {
    creaseX[i] = spots.get(i)[0];
    creaseY[i] = spots.get(i)[1];
  }
  println("LINES: darkest creases, " + n + " spots");
}

// the nearest spot to (x, y) not drawn yet, and how far it is squared (-1: none left)
int nearestCrease(float x, float y, float[] far) {
  int best = -1;
  float bd = Float.MAX_VALUE;
  for (int j = 0; j < creaseX.length; j++) {
    if (creaseUsed[j]) continue;
    float dd = sq(creaseX[j] - x) + sq(creaseY[j] - y);
    if (dd < bd) { bd = dd; best = j; }
  }
  far[0] = bd;
  return best;
}

// one line: from START AT's spot to the nearest crease, then on along them
void creaseLine(PGraphics g) {
  float[] s = startPoint();
  if (s == null) return;
  float[] far = new float[1];
  int at = nearestCrease(s[0], s[1], far);
  if (at < 0) return;
  float lift = t("lift");
  float gap = lift <= 0 ? Float.MAX_VALUE : CREASE_STEP * 2 * pow(50, 1 - lift);
  float most = t("length") * random(0.7, 1.3), went = 0;
  FloatList px = new FloatList(), py = new FloatList();
  while (at >= 0) {
    creaseUsed[at] = true;
    creaseLeft--;
    px.append(creaseX[at]);
    py.append(creaseY[at]);
    if (went >= most) break;
    int next = nearestCrease(creaseX[at], creaseY[at], far);
    if (next < 0) break;
    float d = sqrt(far[0]);
    if (d > gap) break;
    went += d;
    at = next;
  }
  int n = px.size();
  float x0 = px.get(0), y0 = py.get(0);
  g.stroke(systemColour(x0, y0), toolAlpha(x0, y0));
  g.strokeWeight(t("width"));
  if (n == 1) {
    g.point(x0, y0);
    return;
  }
  // a smooth curve, each spot pulled a little towards its neighbours when they're close
  float near = CREASE_STEP * 4;
  g.beginShape();
  g.curveVertex(x0, y0);
  for (int k = 0; k < n; k++) {
    int a = max(0, k - 1), b = min(n - 1, k + 1);
    float x = px.get(k), y = py.get(k);
    if (dist(px.get(a), py.get(a), x, y) < near && dist(px.get(b), py.get(b), x, y) < near) {
      x = (px.get(a) + 2 * x + px.get(b)) / 4;
      y = (py.get(a) + 2 * y + py.get(b)) / 4;
    }
    g.curveVertex(x, y);
  }
  g.curveVertex(px.get(n - 1), py.get(n - 1));
  g.endShape();
}
