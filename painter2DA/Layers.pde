// Layers: the painting is seven see-through layers, one on top of another, combined every frame
// into `canvas` - the picture you see, and that wet paint picks up from.
//
// They're 1 - 5 and A and B, all alike (A and B took the places of painter2D's canvas and backdrop,
// so they start at the bottom). Under them all is plain white, which shows wherever every layer is
// see-through. The layers start empty: the tools paint on them, and COPY (the Copy tab) lays any
// of VIEW's maps on one - that's how a painting starts on the photo or the masses.
// They're stacked in `layerOrder`, and VIEW's LAYERS list can change the order, and hides and shows
// them. Each tool chooses the layer it paints on in its APPLY, and in its own box on the panel each
// layer can be made see-through and combined with the ones under it in a different way (multiply,
// screen ...). SCRAPE takes paint off one layer, showing what's underneath.
//
// The layers can float apart, as in a shadow box: each has a gap above the stack under it, and its
// own light (in the panel's LIGHT) from one side makes it cast a soft shadow, in a colour of its own, on
// what's under it (further and softer with a bigger gap) and lights up its edges that face the light,
// like cut paper in a shadow box. Each
// layer has its own gap, shadow darkness, softness and lit edges, in its box; they start with no gap and
// no lit edges. It's done here, as the layers are combined.
//
// Each layer also has a height - how thick its paint is - for its impasto (the Impasto tab).
//
// One technical point: on a see-through layer, the colours are stored already multiplied by how
// solid they are ("premultiplied") - that's what OpenGL's ordinary blending produces when painting
// onto an empty layer. So the layers are combined with blending that expects that, set directly
// through OpenGL (blendLayer), and SAVE divides it out again before writing a layer to a file.

final int LAYERS = 7;
final int LAYER_A = 5, LAYER_B = 6;
String[] LAYER_NAMES = { "1", "2", "3", "4", "5", "A", "B" };
PGraphics[] layers = new PGraphics[LAYERS];
String[] layerBlendNames = { "normal", "multiply", "screen", "add", "lightest" };
// the stack, bottom first: which layer is in each place. VIEW's LAYERS list moves them up and
// down; a layer keeps its paint, its settings and the tools that paint on it wherever it goes
volatile int[] layerOrder = { LAYER_B, LAYER_A, 0, 1, 2, 3, 4 };
// the shaders for a layer's shadow and its lit edges (in data), and which way up the
// layers' textures are when they're drawn through them
PShader boxShadow, boxRim;
float boxFlipY = -1;

// where layer i is in the stack (0 = bottom)
int layerPosition(int i) {
  int[] o = layerOrder;
  for (int p = 0; p < LAYERS; p++) if (o[p] == i) return p;
  return i;
}

// swap the layer in place `pos` with the one above it (dir 1) or below it (dir -1)
void moveLayer(int pos, int dir) {
  int other = pos + dir;
  if (pos < 0 || pos >= LAYERS || other < 0 || other >= LAYERS) return;
  int[] o = layerOrder.clone();
  int t = o[pos];
  o[pos] = o[other];
  o[other] = t;
  layerOrder = o;
}

// the layers and the combined picture, at the photo's size
void makeLayers() {
  for (int i = 0; i < LAYERS; i++) {
    layers[i] = photoSized(layers[i]);
    layerChanged[i] = true;
  }
  canvas = photoSized(canvas);
  makeHeights();
}

PGraphics photoSized(PGraphics g) {
  if (g != null && g.width == photo.width && g.height == photo.height) return g;
  return createGraphics(photo.width, photo.height, P2D);
}

// a layer back to empty (and flat)
void clearLayer(int i) {
  if (layers[i] == null) return;
  layers[i].beginDraw();
  layers[i].clear();
  layers[i].endDraw();
  clearHeight(i);
  layerEmpty[i] = true;
  layerChanged[i] = false;
}

// which layers have no paint on them, for VIEW's list (its boxes are white then). A layer is only
// looked at when it might have changed - an empty one's been painted on, or paint's come off one - a
// few times a second, one a frame, as it has to be fetched from the graphics card
volatile boolean[] layerEmpty = { true, true, true, true, true, true, true };
boolean[] layerChanged = new boolean[LAYERS];
int[] layerLookedAt = new int[LAYERS];

void lookForPaint() {
  for (int i = 0; i < LAYERS; i++) {
    if (!layerChanged[i] || layers[i] == null || frameCount - layerLookedAt[i] < 15) continue;
    layerLookedAt[i] = frameCount;
    layerChanged[i] = false;
    layers[i].loadPixels();
    boolean none = true;
    for (int c : layers[i].pixels) {
      if (c >>> 24 > 3) {              // (a trace of what's been scraped off doesn't count)
        none = false;
        break;
      }
    }
    layerEmpty[i] = none;
    return;
  }
}

// combine the layers into `canvas`, bottom to top, on white. A layer with a gap first casts
// its shadow on what's under it, and one with lit edges is drawn with them
void composite() {
  if (canvas == null) return;
  if (boxShadow == null) {
    boxShadow = loadShader("boxShadow.glsl");
    boxRim = loadShader("boxRim.glsl");
  }
  boolean fin = finishing();
  if (fin) combineHeights();
  // RECOLOUR (the Recolour tab): a new palette if asked for, and the layers with its changes -
  // made before drawing on the canvas too
  recolourStep();
  PGraphics[] shown = layers.clone();
  if (recolouring()) {
    for (int i = 0; i < LAYERS; i++) if (v("layerOn" + i) > 0.5) shown[i] = recolouredLayer(i);
  }
  canvas.beginDraw();
  canvas.background(255);
  int[] o = layerOrder;
  for (int p = 0; p < LAYERS; p++) {
    int i = o[p];
    if (v("layerOn" + i) < 0.5) continue;
    PGraphics layer = shown[i];
    float solid = 1 - v("layerSeeThrough" + i);
    float op = 255 * solid;
    float gap = v("layerGap" + i);
    // the layer's own light (LIGHT): which way it is, in pixels with y down the picture, and how long a
    // shadow is for each pixel of gap - the lower the light, the longer
    float from = radians(v("lightFrom" + i)), lx = cos(from), ly = -sin(from);
    float reach = 1 / tan(radians(v("lightHeight" + i)));
    if (gap > 0 && v("boxShadow" + i) > 0) {
      float len = gap * reach;
      boxShadow.set("offset", -lx * len, -ly * len);
      boxShadow.set("radius", 1 + v("boxSoftness" + i) * len);
      boxShadow.set("strength", v("boxShadow" + i) * solid);
      boxShadow.set("flipY", boxFlipY);
      int sc = panel.colour("shadowColour" + i);   // (in LIGHT; black to start)
      boxShadow.set("colour", (sc >> 16 & 255) / 255.0, (sc >> 8 & 255) / 255.0, (sc & 255) / 255.0);
      PGL pgl = canvas.beginPGL();
      blendLayer(pgl, 0);
      canvas.shader(boxShadow);
      canvas.image(layer, 0, 0);
      canvas.flush();
      canvas.resetShader();
      canvas.endPGL();
    }
    boolean rim = v("boxRim" + i) > 0;
    if (rim) {
      boxRim.set("toLight", lx, ly);
      boxRim.set("width", 2 + gap * 0.15);
      boxRim.set("amount", v("boxRim" + i));
      boxRim.set("flipY", boxFlipY);
      canvas.shader(boxRim);
    }
    PGL pgl = canvas.beginPGL();
    blendLayer(pgl, (int) v("layerBlend" + i));
    canvas.tint(op, op);          // premultiplied, so fading scales the colour as well as the alpha
    canvas.image(layer, 0, 0);
    canvas.flush();
    canvas.endPGL();              // puts Processing's own blending back
    canvas.noTint();
    if (rim) canvas.resetShader();
  }
  canvas.endDraw();
  if (fin) finish(canvas);        // the light on the thick paint (the Impasto tab)
}

// OpenGL blending for drawing a premultiplied layer onto what's under it
void blendLayer(PGL pgl, int mode) {
  pgl.blendEquation(PGL.FUNC_ADD);
  if (mode == 1) pgl.blendFuncSeparate(PGL.DST_COLOR, PGL.ONE_MINUS_SRC_ALPHA, PGL.ONE, PGL.ONE_MINUS_SRC_ALPHA);        // multiply
  else if (mode == 2) pgl.blendFuncSeparate(PGL.ONE, PGL.ONE_MINUS_SRC_COLOR, PGL.ONE, PGL.ONE_MINUS_SRC_ALPHA);    // screen
  else if (mode == 3) pgl.blendFuncSeparate(PGL.ONE, PGL.ONE, PGL.ONE, PGL.ONE_MINUS_SRC_ALPHA);                    // add
  else if (mode == 4) {                                                                                             // lightest
    pgl.blendEquation(0x8008);                  // GL_MAX (PGL has no name for it)
    pgl.blendFuncSeparate(PGL.ONE, PGL.ONE, PGL.ONE, PGL.ONE);
  }
  else pgl.blendFuncSeparate(PGL.ONE, PGL.ONE_MINUS_SRC_ALPHA, PGL.ONE, PGL.ONE_MINUS_SRC_ALPHA);                   // normal
}

// take paint off layer g wherever `mask` is solid (as much as it's solid) - SCRAPE
void eraseWith(PGraphics g, PImage mask) {
  for (int i = 0; i < LAYERS; i++) if (g == layers[i]) layerChanged[i] = true;
  g.beginDraw();
  PGL pgl = g.beginPGL();
  pgl.blendEquation(PGL.FUNC_ADD);
  pgl.blendFuncSeparate(PGL.ZERO, PGL.ONE_MINUS_SRC_ALPHA, PGL.ZERO, PGL.ONE_MINUS_SRC_ALPHA);
  g.image(mask, 0, 0);
  g.flush();
  g.endPGL();
  g.endDraw();
}

// a layer as an ordinary picture (not premultiplied), to save
PImage layerPicture(int i) {
  PImage p = layers[i].get();
  p.loadPixels();
  for (int k = 0; k < p.pixels.length; k++) {
    int c = p.pixels[k], a = c >>> 24;
    if (a == 0 || a == 255) continue;
    int r = min(255, (c >> 16 & 255) * 255 / a), gr = min(255, (c >> 8 & 255) * 255 / a), b = min(255, (c & 255) * 255 / a);
    p.pixels[k] = a << 24 | r << 16 | gr << 8 | b;
  }
  p.updatePixels();
  return p;
}
