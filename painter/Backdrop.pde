// Backdrop: what the painting is painted on (design doc, "Additions": ground / substrate layer).
//
// SETUP 4 chooses it: nothing (plain white), a canvas weave, paper or a collage of newspaper
// cuttings. It's the bottom of the stack (the Layers tab), under the canvas the painting starts
// with: it shows wherever the canvas is made see-through (or hidden) in LAYERS. "strength" fades
// it towards white. "shows through the paint" lets it come through everything above it as well,
// the way a coarse canvas's weave does (that part is in the Impasto tab's finishing pass, and a
// weave or paper also gets bumps there that the IMPASTO light catches).
//
// It can change at any time. A texture is made the first time it's needed (and again for another
// choice or picture size).

String[] backdropNames = { "none", "canvas weave", "paper", "newspaper" };
PImage backdropImg;          // the texture, at full strength
PGraphics backdropLayer;     // the backdrop as drawn: the texture at SETUP 4's strength
String backdropKey = "", backdropLayerKey = "";

// the texture for SETUP 4's choice, made if it isn't already
PImage backdropTexture() {
  int kind = (int) v("backdropKind");
  String key = kind + " " + photo.width + " " + photo.height;
  if (!key.equals(backdropKey)) {
    backdropKey = key;
    backdropImg = kind == 1 ? weave(photo.width, photo.height)
                : kind == 2 ? paper(photo.width, photo.height)
                : kind == 3 ? newspaper(photo.width, photo.height)
                : blank(photo.width, photo.height);
  }
  return backdropImg;
}

// the backdrop, faded towards white as "strength" says. Not while another picture is being drawn
// on: drawing on two at once upsets OpenGL
PGraphics backdropGraphics() {
  backdropTexture();
  String key = backdropKey + " " + nf(v("backdropAmount"), 0, 2);
  if (!key.equals(backdropLayerKey)) {
    backdropLayerKey = key;
    PImage t = backdropImg.copy();
    float s = v("backdropAmount");
    t.loadPixels();
    for (int i = 0; i < t.pixels.length; i++) {
      int c = t.pixels[i];
      int r = round(lerp(255, c >> 16 & 255, s)), gr = round(lerp(255, c >> 8 & 255, s)), b = round(lerp(255, c & 255, s));
      t.pixels[i] = 0xFF000000 | r << 16 | gr << 8 | b;
    }
    t.updatePixels();
    backdropLayer = photoSized(backdropLayer);
    backdropLayer.beginDraw();
    backdropLayer.blendMode(REPLACE);
    backdropLayer.image(t, 0, 0);
    backdropLayer.blendMode(BLEND);
    backdropLayer.endDraw();
  }
  return backdropLayer;
}

PImage blank(int w, int h) {
  PImage img = createImage(w, h, RGB);
  img.loadPixels();
  java.util.Arrays.fill(img.pixels, 0xFFFFFFFF);
  img.updatePixels();
  return img;
}

// Canvas: threads over and under each other in a plain weave, each a slightly different shade
// and thickening and thinning along its length (slubs), with dark gaps between them
PImage weave(int w, int h) {
  int pitch = 7;
  int cols = w / pitch + 2, rows = h / pitch + 2, seg = 24;
  // each thread's shade along its length, every `seg` pixels
  float[][] warp = new float[cols][h / seg + 2], weft = new float[rows][w / seg + 2];
  for (int i = 0; i < cols; i++) for (int k = 0; k < warp[i].length; k++) warp[i][k] = 0.85 + 0.15 * noise(i * 0.9, k * 0.35);
  for (int j = 0; j < rows; j++) for (int k = 0; k < weft[j].length; k++) weft[j][k] = 0.85 + 0.15 * noise(500 + j * 0.9, k * 0.35);
  PImage img = createImage(w, h, RGB);
  img.loadPixels();
  for (int y = 0; y < h; y++) {
    int j = y / pitch;
    float fy = (y % pitch + 0.5) / pitch;
    for (int x = 0; x < w; x++) {
      int i = x / pitch;
      float fx = (x % pitch + 0.5) / pitch;
      float across = sin(PI * fx), down = sin(PI * fy);   // rounded threads
      boolean warpOver = (i + j) % 2 == 0;
      float v = warpOver ? (0.62 + 0.38 * across) * lerp(warp[i][y / seg], warp[i][y / seg + 1], (y % seg) / (float) seg)
                         : (0.62 + 0.38 * down) * lerp(weft[j][x / seg], weft[j][x / seg + 1], (x % seg) / (float) seg);
      v *= 0.8 + 0.2 * sqrt(max(across, down));            // the gaps between threads
      int g = round(255 * constrain(v, 0, 1));
      img.pixels[y * w + x] = 0xFF000000 | min(255, g + 6) << 16 | g << 8 | max(0, g - 10);
    }
  }
  img.updatePixels();
  return img;
}

// Paper: a soft mottle, short fibres lighter and darker than the paper, and a fine tooth
PImage paper(int w, int h) {
  // the mottle, made small and stretched up so it's smooth
  PImage mottle = createImage(w / 12 + 1, h / 12 + 1, RGB);
  mottle.loadPixels();
  for (int y = 0; y < mottle.height; y++) {
    for (int x = 0; x < mottle.width; x++) {
      int g = round(255 * noise(x * 0.12, y * 0.12, 7));
      mottle.pixels[y * mottle.width + x] = 0xFF000000 | g << 16 | g << 8 | g;
    }
  }
  mottle.updatePixels();
  mottle.resize(w, h);
  PGraphics f = createGraphics(w, h);
  f.beginDraw();
  f.background(128);
  f.noFill();
  int fibres = w * h / 900;
  for (int k = 0; k < fibres; k++) {
    float x = random(w), y = random(h), a = random(TWO_PI), len = random(6, 30);
    f.stroke(random(1) < 0.6 ? 175 : 80, random(30, 70));
    f.strokeWeight(random(0.5, 1.2));
    f.bezier(x, y, x + cos(a) * len * 0.3 + random(-4, 4), y + sin(a) * len * 0.3 + random(-4, 4),
             x + cos(a) * len * 0.7 + random(-4, 4), y + sin(a) * len * 0.7 + random(-4, 4), x + cos(a) * len, y + sin(a) * len);
  }
  f.endDraw();
  f.loadPixels();
  PImage img = createImage(w, h, RGB);
  img.loadPixels();
  for (int i = 0; i < w * h; i++) {
    float m = (mottle.pixels[i] & 255) / 255.0;
    float fib = ((f.pixels[i] & 255) - 128) / 255.0;
    float tooth = random(-1, 1);
    float v = 0.78 + 0.2 * m + 0.5 * fib + 0.05 * tooth;
    int g = round(255 * constrain(v, 0, 1));
    img.pixels[i] = 0xFF000000 | g << 16 | min(255, g + 2) << 8 | max(0, g - 6);
  }
  img.updatePixels();
  return img;
}

// Newspaper: cuttings stuck down overlapping, each a little crooked - columns of small print
// with now and then a headline, on yellowed newsprint, each cutting a slightly different shade.
// They're spread over a rough grid so they cover most of the picture
PImage newspaper(int w, int h) {
  PGraphics g = createGraphics(w, h);
  PFont body = createFont("Georgia", 11, true), head = createFont("Georgia Bold", 26, true);
  g.beginDraw();
  g.background(255);
  g.noStroke();
  int across = 3, down = 4;
  for (int c = 0; c < across * down; c++) {
    float cw = random(0.3, 0.55) * w, ch = random(0.18, 0.32) * h;
    g.pushMatrix();
    g.translate(((c % across) + random(-0.3, 0.5)) * w / across - cw * 0.15, ((c / across) + random(-0.3, 0.5)) * h / down - ch * 0.15);
    g.rotate(random(-0.12, 0.12));
    g.clip(0, 0, cw, ch);
    float tone = random(205, 235);
    g.fill(tone + 12, tone + 8, tone - 8);
    g.rect(0, 0, cw, ch);
    // columns of print, a headline over some of them
    int columns = max(1, round(cw / 150));
    float colW = (cw - 16) / columns;
    for (int k = 0; k < columns; k++) {
      float x = 8 + k * colW, y = 10;
      g.fill(45, 42, 40);
      if (random(1) < 0.5) {
        g.textFont(head);
        g.text(words(2 + (int) random(3)), x, y, colW - 8, 70);
        y += 66;
      }
      g.textFont(body);
      g.textLeading(13);
      g.fill(60, 56, 52);
      StringBuilder s = new StringBuilder();
      while (s.length() < (ch - y) * colW / 30) s.append(words(8 + (int) random(10))).append(". ");
      g.text(s.toString(), x, y, colW - 10, ch - y - 6);
    }
    g.noClip();
    g.popMatrix();
  }
  g.endDraw();
  return g.get();
}

String[] newsWords = { "the", "council", "said", "on", "monday", "that", "plans", "for", "a", "new", "bridge",
  "would", "go", "ahead", "despite", "local", "concerns", "about", "cost", "and", "traffic", "residents",
  "of", "street", "were", "told", "in", "letter", "last", "week", "market", "prices", "rose", "sharply",
  "after", "weather", "harvest", "minister", "will", "visit", "town", "hall", "spring", "fair", "police",
  "report", "late", "night", "returned", "home", "winning", "goal", "season", "museum", "opens", "doors" };

String words(int n) {
  StringBuilder s = new StringBuilder();
  for (int k = 0; k < n; k++) {
    String w = newsWords[(int) random(newsWords.length)];
    if (k == 0) w = Character.toUpperCase(w.charAt(0)) + w.substring(1);
    s.append(k > 0 ? " " : "").append(w);
  }
  return s.toString();
}
