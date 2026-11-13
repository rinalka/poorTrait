// Backdrop: what the painting is painted on (design doc, "Additions": ground / substrate layer).
//
// SETUP 3 chooses it: nothing (plain white), a canvas weave, paper, or a picture of your own
// ("load ..."). It's the bottom of the stack (the Layers tab), under the canvas the painting starts
// with: it shows wherever the canvas is made see-through (or hidden) in LAYERS. "strength" fades
// it towards white. "shows through the paint" lets it come through everything above it as well,
// the way a coarse canvas's weave does (that part is in the Impasto tab's finishing pass, and a
// weave or paper also gets bumps there that the IMPASTO light catches).
//
// It can change at any time. A texture is made the first time it's needed (and again for another
// choice or picture size).
//
// A loaded picture that isn't the photo's size is either scaled to it (each way on its own, so it
// may be stretched) or tiled: one tile in the middle, the others round it, cut off at the edges.
// SAVE keeps where it came from, so LOAD SETTINGS can load it again.

String[] backdropNames = { "none", "canvas weave", "paper", "load ..." };
final int BACKDROP_FILE = 3;
PImage backdropImg;          // the texture, at full strength
volatile PImage backdropFile;                  // the picture loaded for "load ...", at its own size
volatile String backdropFilePath = "", backdropFileName = "";
PGraphics backdropLayer;     // the backdrop as drawn: the texture at SETUP 3's strength
String backdropKey = "", backdropLayerKey = "";

// the texture for SETUP 3's choice, made if it isn't already
PImage backdropTexture() {
  int kind = (int) v("backdropKind");
  PImage file = backdropFile;
  boolean tile = v("backdropFit") > 0.5;
  String key = kind + " " + photo.width + " " + photo.height;
  if (kind == BACKDROP_FILE) key += " " + System.identityHashCode(file) + " " + tile;
  if (!key.equals(backdropKey)) {
    backdropKey = key;
    backdropImg = kind == 1 ? weave(photo.width, photo.height)
                : kind == 2 ? paper(photo.width, photo.height)
                : kind == BACKDROP_FILE && file != null ? fitted(file, photo.width, photo.height, tile)
                : blank(photo.width, photo.height);
  }
  return backdropImg;
}

// the backdrop with the BACKDROP box's hue, saturation and brightness, faded towards white as
// "strength" says - on the graphics card (data/backdropAdjust.glsl), so the sliders are quick on
// a big picture. Not while another picture is being drawn on: drawing on two at once upsets OpenGL
PShader backdropShader;

PGraphics backdropGraphics() {
  backdropTexture();
  String key = backdropKey + " " + nf(v("backdropAmount"), 0, 3) + " " + nf(v("backdropHue"), 0, 1)
    + " " + nf(v("backdropSat"), 0, 3) + " " + nf(v("backdropBri"), 0, 3);
  if (!key.equals(backdropLayerKey)) {
    backdropLayerKey = key;
    if (backdropShader == null) backdropShader = loadShader("backdropAdjust.glsl");
    backdropShader.set("hueShift", v("backdropHue") / 360);
    backdropShader.set("sat", v("backdropSat"));
    backdropShader.set("bri", v("backdropBri"));
    backdropShader.set("strength", v("backdropAmount"));
    backdropLayer = photoSized(backdropLayer);
    backdropLayer.beginDraw();
    backdropLayer.blendMode(REPLACE);
    backdropLayer.shader(backdropShader);
    backdropLayer.image(backdropImg, 0, 0);
    backdropLayer.resetShader();
    backdropLayer.blendMode(BLEND);
    backdropLayer.endDraw();
  }
  return backdropLayer;
}

// "load ...": choose a picture
void chooseBackdrop() {
  selectInput("Choose a backdrop picture", "backdropChosen", new java.io.File(sketchPath("..") + "/x.jpg"));
}

// (on selectInput's own thread) a picture was chosen
void backdropChosen(java.io.File f) {
  if (f != null) loadBackdropFile(f.getAbsolutePath());
}

boolean loadBackdropFile(String path) {
  PImage p = new java.io.File(path).exists() ? loadImage(path) : null;
  if (p == null || p.width <= 0) {
    println("couldn't load the backdrop " + path);
    return false;
  }
  p.loadPixels();
  backdropFilePath = path;
  backdropFileName = new java.io.File(path).getName();
  backdropFile = p;
  println("backdrop " + backdropFileName + ": " + p.width + " x " + p.height
    + (backdropMismatch() ? "  (the picture is " + photo.width + " x " + photo.height + ")" : ""));
  if (panel != null) panel.layoutWanted = true;     // the scale / tile choice may show or hide
  return true;
}

// whether the loaded picture is a different size from the photo
boolean backdropMismatch() {
  PImage f = backdropFile;
  return f != null && photo != null && (f.width != photo.width || f.height != photo.height);
}

// the loaded picture made w x h: scaled (each way on its own), or tiled - the first tile in the
// middle, the rest round it, cut off at the edges
PImage fitted(PImage f, int w, int h, boolean tile) {
  if (f.width == w && f.height == h) return f.copy();
  if (!tile) {
    PImage p = f.copy();
    p.resize(w, h);
    return p;
  }
  int tw = f.width, th = f.height;
  int x0 = (w - tw) / 2, y0 = (h - th) / 2;      // the middle tile's top left (may be off the picture)
  PImage p = createImage(w, h, RGB);
  p.loadPixels();
  f.loadPixels();
  for (int y = 0; y < h; y++) {
    int row = Math.floorMod(y - y0, th) * tw;
    for (int x = 0; x < w; x++) p.pixels[y * w + x] = f.pixels[row + Math.floorMod(x - x0, tw)];
  }
  p.updatePixels();
  return p;
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
