// Deciding one mark: where it goes, how big it is, which way the form pulls it, how see-through
// it is, and what paint it carries - then handing it to a brush (the Strokes or Knife tab).
//
// Most amounts can be "modulated": the slider sets the amount, and a map chosen in the "by" list
// under it (importance, curvature, depth ...) turns it down from place to place - see modulated().
//
// ABSTRACTION (design doc Stage 6) decides where the picture may be broken up. The importance map
// says how much each spot matters for recognising the face; spots that matter more than the
// abstraction slider allows are "protected" - see protection(). A mark landing on a protected
// spot is either left out, so whatever is underneath (the masses, say) stays readable, or made a
// careful mark: small, following the form, in the photo's exact colours. Anchors are the most
// important few spots (eyes, nostrils, mouth), protected however high the abstraction goes.

final int ONE = 0, START_END = 1, TWO = 2, CHUNK = 3, COPY = 4;   // the panel's "carry" choices
int gridI = 0;               // how far the grid start has got

// The tools (the panel's column 2), in the order they paint. Each has its own settings - its
// shape in its box, and its MOVEMENT, COLOUR and APPLY - named with the tool's name in front:
// "knife_size", "splat_drops" ... `tool` is the one painting now, and t("size") reads its setting.
String[] TOOLS = { "brush", "knife", "splat", "line", "frag", "pencil", "scrape" };
String[] toolTitles = { "BRUSH", "PALETTE KNIFE", "SPLATTER", "LINES", "FRAGMENTS", "PENCIL", "SCRAPE" };
String tool = "brush";

float t(String name) {
  return v(tool + "_" + name);
}

void paintMark(PGraphics g) {
  float[] s = startPoint();
  if (s == null) return;
  float x = s[0], y = s[1];
  boolean careful = random(1) < protection(x, y);
  if (careful && v("protectWith") == 0) return;               // protected spots get no marks
  float len = max(3, modulated("size", x, y) * random(0.5, 1) * (careful ? v("carefulSize") : 1));
  float wid = max(1, len * t("width") * random(0.7, 1.3));
  float follow = careful ? max(0.9, modulated("follow", x, y)) : modulated("follow", x, y);
  Paint p = careful ? carefulPaint(toolAlpha(x, y)) : newPaint(toolAlpha(x, y));
  if (tool.equals("brush")) paintStroke(g, x, y, len, wid, follow, p);
  else paintKnife(g, x, y, len, wid, follow, p);
  markCount++;
}

// the tool's slider `name` at (x, y). Its map (if it has one) turns it down where the map is dark -
// or where it's light, with invert on. "amount" is how far down: at 1, black on the map takes it
// all the way to 0; at 0 the map does nothing
float modulated(String name, float x, float y) {
  float base = t(name);
  int by = (int) t(name + "_by");
  if (by <= 0) return base;
  float m = mapAt(by, x, y);
  if (t(name + "_inv") > 0.5) m = 1 - m;
  return base * lerp(1, m, t(name + "_amt"));
}

// how protected (x, y) is from being broken up, 0 .. 1: spots more important than the abstraction
// slider allows, and the anchors whatever it says. At abstraction 0 everything that matters at all
// is protected; at 1 only the anchors are
float protection(float x, float y) {
  if (v("abstractionOn") < 0.5) return 0;      // ABSTRACTION switched off: nothing is protected
  float imp = mapAt(1, x, y);                   // the importance map
  float t = v("abstraction") * 1.2;
  float p = smoothstep(t - 0.15, t + 0.15, imp);
  float a = v("anchors");
  if (a > 0) p = max(p, smoothstep(0.95 - a * 0.6, 1.05 - a * 0.6, imp));
  return p;
}

float smoothstep(float e0, float e1, float x) {
  float t = constrain((x - e0) / (e1 - e0), 0, 1);
  return t * t * (3 - 2 * t);
}

// where the next mark starts, or null for no mark this time
float[] startPoint() {
  int mode = (int) t("startAt");
  if (mode == 1) {
    // weighted by a map: try spots until the map says yes - light places get more marks
    int by = (int) t("startMap");
    boolean inv = t("startInv") > 0.5;
    float x = 0, y = 0;
    for (int k = 0; k < 40; k++) {
      x = random(photo.width);
      y = random(photo.height);
      float m = by <= 0 ? 1 : mapAt(by, x, y);
      if (inv) m = 1 - m;
      if (random(1) < m) break;
    }
    return new float[] { x, y };
  }
  if (mode == 2) {
    // a grid, row by row like reading a page, each mark a little off its spot
    float step = max(3, max(t("size"), 30) * 0.35);
    int cols = ceil(photo.width / step), rows = ceil(photo.height / step);
    int i = gridI++ % (cols * rows);
    return new float[] { constrain((i % cols + random(1)) * step, 0, photo.width - 1),
                         constrain((i / cols + random(1)) * step, 0, photo.height - 1) };
  }
  if (mode == 3 && outputMode == 0) {
    // round the mouse, only while a button is held down in the output window
    if (!mousePressed) return null;
    float sc = width / (float) photo.width;
    return new float[] { constrain(mouseX / sc + randomGaussian() * t("spread"), 0, photo.width - 1),
                         constrain(mouseY / sc + randomGaussian() * t("spread"), 0, photo.height - 1) };
  }
  return new float[] { random(photo.width), random(photo.height) };
}

Paint newPaint(float alpha) {
  Paint p = new Paint();
  p.alpha = alpha;
  p.carry = (int) t("carry");
  p.pickup = (int) t("pickup");
  p.mix = t("mix");
  if (random(1) < t("accentChance")) {
    p.accent = true;
    p.accentColour = accentNow;
    if (p.textured()) p.carry = ONE;
  }
  if (p.textured()) {
    boolean fromCanvas = p.pickup == 1 || (p.pickup == 2 && random(1) < p.mix);
    p.tex = fromCanvas && canvasSnap != null ? canvasSnap : p.pickup == 3 && massesImg != null ? massesImg : photo;
  }
  return p;
}

// a careful mark's paint: the photo's own colours, no jitter, no accent. Chunk would smear, so
// it copies instead
Paint carefulPaint(float alpha) {
  Paint p = new Paint();
  p.alpha = alpha;
  p.carry = (int) t("carry") == CHUNK ? COPY : (int) t("carry");
  p.pickup = 0;
  p.exact = true;
  p.tex = photo;
  return p;
}

// What a brush carries, and how it puts it down.
//   one colour     picked up once
//   start to end   the colour where the mark starts, sliding into the colour where it ends
//   two colours    two colours side by side, as if the brush was loaded twice
//   chunk          a strip of the picture where the brush landed, smeared along the mark
//   copy           the picture right under the mark, as if seen through a hole in the shape of it
// The paint is picked up from the photo, from what's already on the canvas (wet paint), a mix of
// the two, or from the masses (the Masses tab).
class Paint {
  int carry, pickup;
  float mix, alpha;
  boolean accent;
  boolean exact;             // no jitter (careful marks)
  color accentColour;
  PImage tex;                // chunk and copy: the picture the paint comes from
  color c0, c1;              // the colours the brush loaded (the brush sets these)

  boolean textured() {
    return carry == CHUNK || carry == COPY;
  }

  // the colour at (x, y) where this paint is picked up from
  color pickRaw(float x, float y) {
    if (accent) return accentColour;
    if (pickup == 1) return canvasAt(x, y);
    if (pickup == 2) return lerpColor(photoAt(x, y), canvasAt(x, y), mix);
    if (pickup == 3) return massesAt(x, y);
    return photoAt(x, y);
  }

  color pick(float x, float y) {
    return vary(pickRaw(x, y));
  }

  color vary(color c) {
    return exact ? c : jitter(c);
  }

  // one plain colour (the knife's streaks and ridge)
  Paint flat(color c) {
    Paint p = new Paint();
    p.carry = ONE;
    p.c0 = p.c1 = c;
    return p;
  }

  void begin(PGraphics g) {
    g.noStroke();
    g.beginShape(TRIANGLE_STRIP);
    if (textured()) {
      g.textureMode(IMAGE);
      g.texture(tex);
    }
  }

  // One corner of the mark, at (x, y). t is how far along the mark it is (0 .. 1) and side which
  // edge (0 = one, 1 = the other). For chunk the paint comes from (pickX, pickY), where the brush
  // picked it up; for copy from right under the corner.
  void vertex(PGraphics g, float x, float y, float pickX, float pickY, float t, float side, float a) {
    if (textured()) {
      g.tint(255, a);
      if (carry == CHUNK) g.vertex(x, y, pickX, pickY);
      else g.vertex(x, y, x, y);
      return;
    }
    color c = carry == START_END ? lerpColor(c0, c1, t) : carry == TWO ? lerpColor(c0, c1, side) : c0;
    g.fill(c, a);
    g.vertex(x, y);
  }

  void end(PGraphics g) {
    g.endShape();
    if (textured()) g.noTint();
  }
}

// a little lighter or darker, a little off in hue and saturation, as much as the jitter sliders say
color jitter(color c) {
  float[] hsb = java.awt.Color.RGBtoHSB(c >> 16 & 255, c >> 8 & 255, c & 255, null);
  float h = hsb[0] + random(-1, 1) * t("jitterH");
  float s = constrain(hsb[1] + random(-1, 1) * t("jitterS"), 0, 1);
  float b = constrain(hsb[2] + random(-1, 1) * t("jitterB"), 0, 1);
  return java.awt.Color.HSBtoRGB(h - floor(h), s, b) | 0xFF000000;
}
