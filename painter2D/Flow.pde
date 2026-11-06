// Flow: postContemp's "continuous flow" stroke - the panel's FLOW box.
//
// A few lines are on the canvas at once, each going on by "speed" pixels a frame until it's
// "line length" long or runs off the picture; then a new one starts (MOVEMENT's "start at").
// Wherever a line is, the chosen picture gives it a direction to go in: its red (or green, blue,
// hue, saturation or brightness) from 0 to 255 is turned into an angle from 0 all the way round
// to 360 degrees, plus "turn the flow". The line doesn't go that way at once - like postContemp,
// it adds a push that way to the way it's already going, as hard as "how hard it turns" says -
// so it sweeps round in curves and loops that follow the picture's light and dark.
//
// The picture can be the photo, the masses, or one of the maps (they're grey, so only their
// brightness counts). "smoothing" blurs it first: none gives postContemp's nervous, kinked lines,
// more gives long smooth swirls. Protected parts (ABSTRACTION) lift the line, as with the pencil.
//
// The line's colour comes from COLOUR: picked where it starts, or ("colour changes along the
// line") picked up again as it goes and blended in, so the line slowly takes on the colours it
// passes over - or it's COLOUR's "one colour".

String[] flowSources = { "photo", "masses", "importance", "curvature", "depth", "light", "photo lightness", "saturation" };
String[] flowChannels = { "red", "green", "blue", "hue", "saturation", "brightness" };
ArrayList<FlowLine> flows = new ArrayList<FlowLine>();
float[] flowMap;                   // the chosen picture and channel, 0 .. 1, blurred
String flowMapFor = "";
final float FLOW_STEP = 2;         // pixels a line moves at a time
color flowInk;                     // COLOUR's "one colour", read once a frame

void paintFlows(PGraphics g) {
  makeFlowMap();
  flowInk = panel.colour("flow_ink");
  for (int i = flows.size() - 1; i >= 0; i--) if (flows.get(i).done) flows.remove(i);
  int want = (int) t("count");
  for (int tries = 0; flows.size() < want && tries < want; tries++) {
    float[] s = startPoint();
    if (s != null) flows.add(new FlowLine(s[0], s[1]));
  }
  while (flows.size() > want) flows.remove(flows.size() - 1);

  g.noStroke();
  g.beginShape(TRIANGLES);
  int steps = max(1, round(t("speed") / FLOW_STEP));
  for (FlowLine f : flows) {
    for (int s = 0; s < steps && !f.done; s++) f.step(g);
  }
  g.endShape();
}

class FlowLine {
  float x, y, heading, drawn = 0, len, seed = random(1000), alpha;
  color c, target;
  boolean done = false, down = false;
  float pax, pay, pbx, pby;

  FlowLine(float x, float y) {
    this.x = x;
    this.y = y;
    heading = flowDirection(x, y);
    len = t("length") * random(0.8, 1.1);
    c = target = systemColour(x, y);
    alpha = toolAlpha(x, y);
  }

  void step(PGraphics g) {
    // postContemp's move: the push towards the picture's direction is added to the way it's
    // going, and the sum is the new way
    float a = flowDirection(x, y), k = 0.02 * pow(100, t("steer"));
    heading = atan2(sin(heading) + k * sin(a), cos(heading) + k * cos(a));
    x += cos(heading) * FLOW_STEP;
    y += sin(heading) * FLOW_STEP;
    drawn += FLOW_STEP;
    if (x < 1 || y < 1 || x >= photo.width - 2 || y >= photo.height - 2 || drawn > len) {
      done = true;
      return;
    }
    if (t("one") > 0.5) c = flowInk;
    else if (t("along") > 0.5) {
      if (drawn % 24 < FLOW_STEP) target = systemColour(x, y);
      c = lerpColor(c, target, 0.08);
    }
    float press = lerp(1, 0.3 + 1.2 * noise(seed, drawn * 0.004), t("pressure"));
    float ends = min(1, min(drawn, len - drawn) / 20 + 0.2);
    float half = max(0.3, t("width") / 2 * press * ends);
    float nx = -sin(heading), ny = cos(heading);
    float ax = x + nx * half, ay = y + ny * half, bx = x - nx * half, by = y - ny * half;
    boolean drawing = protection(x, y) < 0.5;
    if (drawing && down) {
      g.fill(c, alpha);
      g.vertex(pax, pay); g.vertex(pbx, pby); g.vertex(ax, ay);
      g.vertex(pbx, pby); g.vertex(bx, by); g.vertex(ax, ay);
      markCount++;
    }
    down = drawing;
    pax = ax; pay = ay; pbx = bx; pby = by;
  }
}

// the way the picture says to go at (x, y): its value 0 .. 1 as an angle all the way round,
// turned by "turn the flow"
float flowDirection(float x, float y) {
  int w = photo.width, h = photo.height;
  x = constrain(x, 0, w - 1.001);
  y = constrain(y, 0, h - 1.001);
  int i = (int) x, j = (int) y, k = i + j * w;
  float fx = x - i, fy = y - j;
  float a = lerp(flowMap[k], flowMap[k + 1], fx), b = lerp(flowMap[k + w], flowMap[k + w + 1], fx);
  return lerp(a, b, fy) * TWO_PI + radians(t("turn"));
}

// the chosen picture's channel, 0 .. 1, blurred as "smoothing" says - made again when any of
// those, the picture or the masses change
void makeFlowMap() {
  int src = (int) t("src"), ch = (int) t("channel"), r = round(t("smooth"));
  String key = faceName + " " + src + " " + ch + " " + r + " " + (src == 1 ? System.identityHashCode(massesImg) : 0);
  if (key.equals(flowMapFor) && flowMap != null) return;
  int w = photo.width, h = photo.height;
  float[] a = new float[w * h];
  float[] hsb = new float[3];
  for (int i = 0; i < w * h; i++) {
    float x = i % w, y = i / w;
    if (src >= 2) {
      a[i] = mapAt(src - 1, x, y);           // flowSources leaves out mapNames' "none"
      continue;
    }
    int c = src == 1 ? massesAt(x, y) : photo.pixels[i];
    int cr = c >> 16 & 255, cg = c >> 8 & 255, cb = c & 255;
    if (ch == 0) a[i] = cr / 255.0;
    else if (ch == 1) a[i] = cg / 255.0;
    else if (ch == 2) a[i] = cb / 255.0;
    else {
      java.awt.Color.RGBtoHSB(cr, cg, cb, hsb);
      a[i] = hsb[ch - 3];
    }
  }
  if (r > 0) {
    for (int pass = 0; pass < 2; pass++) {
      boxBlur(a, w, h, r, true);
      boxBlur(a, w, h, r, false);
    }
  }
  flowMap = a;
  flowMapFor = key;
}
