// The direction field: which way strokes should go at every pixel.
//
// normal.png says which way the surface faces. Its red and green tell us which way the surface
// slopes away from us (towards the edge of the cheek, down the side of the nose). Strokes that go
// "across" follow that slope; strokes that go "around" turn 90 degrees and follow the contour
// lines instead - like lines of latitude on a globe.
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

// the stroke direction at (x, y) for the current mode, as { dx, dy, strength }
float[] fieldAt(float x, float y) {
  int i = constrain((int) x, 0, fieldW - 1) + constrain((int) y, 0, fieldH - 1) * fieldW;
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
  for (float y = step / 2; y < fieldH; y += step) {
    for (float x = step / 2; x < fieldW; x += step) {
      float[] f = fieldAt(x, y);
      stroke(255, 230, 60, 40 + 215 * f[2]);
      line(x0 + (x - f[0] * half) * s, y0 + (y - f[1] * half) * s,
           x0 + (x + f[0] * half) * s, y0 + (y + f[1] * half) * s);
    }
  }
}
