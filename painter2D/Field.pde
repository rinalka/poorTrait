// The direction field: which way strokes should go at every pixel.
//
// normal.png says which way the surface faces. Its red and green tell us which way the surface
// slopes away from us (towards the edge of the cheek, down the side of the nose). Strokes that go
// "across" follow that slope; strokes that go "around" turn 90 degrees and follow the contour
// lines instead - like lines of latitude on a globe.
//
// MOVEMENT can choose "along the outline" instead: see the end of this tab.
//
// Where the surface faces straight at us (middle of the forehead, tip of the nose) there is no
// slope, so the direction there is unreliable - `fieldStrength` is low and strokes keep going the
// way they were going.

float[] slopeX, slopeY;      // the slope direction at each pixel (unit length)
float[] fieldStrength;       // 0 = no clear direction here, 1 = a clear slope
int fieldW, fieldH;

void buildField(PImage normals, int blur) {
  int t0 = millis();
  PImage n = normals.copy();
  if (blur > 0) n.filter(BLUR, blur);
  n.loadPixels();
  fieldW = n.width;
  fieldH = n.height;
  slopeX = new float[fieldW * fieldH];
  slopeY = new float[fieldW * fieldH];
  fieldStrength = new float[fieldW * fieldH];
  for (int i = 0; i < n.pixels.length; i++) {
    int c = n.pixels[i];
    float nx = ((c >> 16) & 255) / 255.0 * 2 - 1;
    float ny = -(((c >> 8) & 255) / 255.0 * 2 - 1);    // green is "up", but pixels count down
    float len = sqrt(nx * nx + ny * ny);
    if (len > 1e-5) {
      slopeX[i] = nx / len;
      slopeY[i] = ny / len;
    }
    // 0.03 is barely tilted, 0.2 is clearly turning away from us
    fieldStrength[i] = constrain(map(len, 0.03, 0.2, 0, 1), 0, 1);
  }
  println("field built in " + (millis() - t0) + " ms (smoothing " + blur + ")");
}

// the stroke direction at (x, y) on the photo for the current mode, as { dx, dy, strength }. The
// field is the normal map's size, which can be smaller than the photo
float[] fieldAt(float x, float y) {
  if (alongOutline && olineCos != null) return outlineFieldAt(x, y);
  int fx = (int) (x * fieldW / photo.width), fy = (int) (y * fieldH / photo.height);
  int i = constrain(fx, 0, fieldW - 1) + constrain(fy, 0, fieldH - 1) * fieldW;
  float dx = slopeX[i], dy = slopeY[i];
  if (around) {
    float t = dx;
    dx = -dy;
    dy = t;
  }
  return new float[] { dx, dy, fieldStrength[i] };
}

// short lines on a grid over the left picture, so the field can be seen
void drawField(float x0, float y0, float s) {
  float step = 18 * ui / s;          // grid spacing in photo pixels
  float half = step * 0.4;
  strokeWeight(1.5 * ui);
  for (float y = step / 2; y < photo.height; y += step) {
    for (float x = step / 2; x < photo.width; x += step) {
      float[] f = fieldAt(x, y);
      stroke(255, 230, 60, 40 + 215 * f[2]);
      line(x0 + (x - f[0] * half) * s, y0 + (y - f[1] * half) * s,
           x0 + (x + f[0] * half) * s, y0 + (y + f[1] * half) * s);
    }
  }
}


// ---------------------------------------------------------------- along the outline

// MOVEMENT's "along the outline": the way the nearest bit of the OUTLINE tool's line goes, at every
// spot - so marks run alongside the drawing, like echoes of it further out. It's the outline
// SETUP 6 chooses (its parts and smoothness), made on a coarse grid (the longest side 512 cells)
// and smoothed a little, so where two parts' directions meet they blend - and count for less
// there. Made again when the outline changes.
float[] olineCos, olineSin;        // twice each cell's angle (so a line has no front or back)
int olineW, olineH;
float olineCell;
String olineFor = "";
boolean olineWarned = false;

void outlineFieldReady() {
  String was = tool;
  tool = "outline";
  outlinePlanned();
  tool = was;
  if (outlineFor.equals(olineFor)) return;
  olineFor = outlineFor;
  olineCos = olineSin = null;
  int n = outlineX == null ? 0 : outlineX.length;
  olineCell = max(1, max(photo.width, photo.height) / 512.0);
  int gw = max(1, ceil(photo.width / olineCell)), gh = max(1, ceil(photo.height / olineCell));
  float[] c2 = new float[gw * gh], s2 = new float[gw * gh];
  boolean[] set = new boolean[gw * gh];
  IntList queue = new IntList();
  // the outline's own cells: each point's direction, from the points either side in its part
  for (int i = 0; i < n; i++) {
    int i0 = max(outlineFirst[i], i - 2), i1 = min(outlineLast[i], i + 2);
    float dx = outlineX[i1] - outlineX[i0], dy = outlineY[i1] - outlineY[i0];
    if (dx * dx + dy * dy < 1e-6) continue;
    int k = constrain((int) (outlineX[i] / olineCell), 0, gw - 1) + constrain((int) (outlineY[i] / olineCell), 0, gh - 1) * gw;
    if (set[k]) continue;
    float a = 2 * atan2(dy, dx);
    c2[k] = cos(a);
    s2[k] = sin(a);
    set[k] = true;
    queue.append(k);
  }
  if (queue.size() == 0) {
    if (!olineWarned) println("along the outline: the outline has no parts - choose some in SETUP 6");
    olineWarned = true;
    return;
  }
  olineWarned = false;
  // out from there, each cell taking the direction of the outline cell that reached it first
  for (int h = 0; h < queue.size(); h++) {
    int k = queue.get(h), x = k % gw, y = k / gw;
    for (int oy = -1; oy <= 1; oy++) for (int ox = -1; ox <= 1; ox++) {
      int nx = x + ox, ny = y + oy;
      if (nx < 0 || ny < 0 || nx >= gw || ny >= gh) continue;
      int m = nx + ny * gw;
      if (set[m]) continue;
      set[m] = true;
      c2[m] = c2[k];
      s2[m] = s2[k];
      queue.append(m);
    }
  }
  for (int pass = 0; pass < 2; pass++) {
    boxBlur(c2, gw, gh, 2, true);
    boxBlur(c2, gw, gh, 2, false);
    boxBlur(s2, gw, gh, 2, true);
    boxBlur(s2, gw, gh, 2, false);
  }
  olineW = gw;
  olineH = gh;
  olineCos = c2;
  olineSin = s2;
}

// the outline's direction at (x, y), as fieldAt gives it: { dx, dy, strength }
float[] outlineFieldAt(float x, float y) {
  int i = constrain((int) (x / olineCell), 0, olineW - 1) + constrain((int) (y / olineCell), 0, olineH - 1) * olineW;
  float c = olineCos[i], s = olineSin[i];
  float a = atan2(s, c) / 2;
  return new float[] { cos(a), sin(a), min(1, sqrt(c * c + s * s)) };
}
