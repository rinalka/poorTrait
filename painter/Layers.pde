// Layers: the painting is four see-through layers, one on top of another, combined every frame
// into `canvas` - the picture you see, that the mesh wears, and that wet paint picks up from.
//
// Under them is the canvas (`startLayer`): solid, the canvas colour with the masses or the photo
// on it (SETUP 4), made at RUN and CLEAR and never painted on. The layers start empty; they're
// stacked in `layerOrder`, layer 1 at the bottom to start with, and VIEW's LAYERS list can change
// the order. Each tool chooses the layer it paints on in its APPLY, and in the panel's LAYERS
// block each layer can be made see-through or combined with the ones under it in a different way
// (multiply, screen ...); VIEW's LAYERS list hides and shows them (the canvas always shows). SCRAPE takes
// paint off the layers above a chosen layer, or all of them, showing what's underneath.
//
// SHADOW BOX fakes the layers floating apart: each has a gap above the stack under it, and a
// light from one side makes it cast a soft shadow on what's under it (further and softer with a
// bigger gap) and lights up its edges that face the light, like cut paper in a shadow box. It's
// done here, as the layers are combined, so the mesh wears it too.
//
// This is built so the layers can later be spread over more than one copy of the mesh ("sheets",
// for real shadows between them), but for now they're all on the one.
//
// One technical point: on a see-through layer, the colours are stored already multiplied by how
// solid they are ("premultiplied") - that's what OpenGL's ordinary blending produces when painting
// onto an empty layer. So the layers are combined with blending that expects that, set directly
// through OpenGL (blendLayer), and SAVE divides it out again before writing a layer to a file.

final int LAYERS = 4;
PGraphics[] layers = new PGraphics[LAYERS];
PGraphics startLayer;        // the canvas under the layers
String[] layerBlendNames = { "normal", "multiply", "screen", "add", "lightest" };
// the stack, bottom first: which layer is in each place. VIEW's LAYERS list moves them up and
// down; a layer keeps its paint, its settings and the tools that paint on it wherever it goes
volatile int[] layerOrder = { 0, 1, 2, 3 };
// SHADOW BOX: the shaders for a layer's shadow and its lit edges (in data), and which way up the
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

// the canvas, the layers and the combined picture, at the photo's size
void makeLayers() {
  for (int i = 0; i < LAYERS; i++) layers[i] = photoSized(layers[i]);
  startLayer = photoSized(startLayer);
  canvas = photoSized(canvas);
}

PGraphics photoSized(PGraphics g) {
  if (g != null && g.width == photo.width && g.height == photo.height) return g;
  return createGraphics(photo.width, photo.height, P2D);
}

// the canvas back to its start: the canvas colour, and the masses or the photo
void clearStart() {
  if (startLayer == null) return;
  int start = (int) v("startWith");
  PImage under = start == 1 ? massesImg : start == 2 ? photo : null;
  if (start == 1 && massesImg == null) println("the masses aren't ready yet - starting with the plain canvas colour");
  startLayer.beginDraw();
  startLayer.background(ground);
  if (under != null) startLayer.image(under, 0, 0);
  startLayer.endDraw();
}

// a layer back to empty
void clearLayer(int i) {
  if (layers[i] == null) return;
  layers[i].beginDraw();
  layers[i].clear();
  layers[i].endDraw();
}

// combine the canvas and the layers into `canvas`, bottom to top. With SHADOW BOX on, each layer
// first casts its shadow on what's under it, and is drawn with its lit edges
void composite() {
  if (canvas == null) return;
  if (boxShadow == null) {
    boxShadow = loadShader("boxShadow.glsl");
    boxRim = loadShader("boxRim.glsl");
  }
  boolean box = v("boxOn") > 0.5;
  // which way the light is, in pixels with y down the picture, and how long a shadow is for each
  // pixel of gap: the lower the light, the longer
  float from = radians(v("lightFrom")), lx = cos(from), ly = -sin(from);
  float reach = 1 / tan(radians(v("lightHeight")));
  canvas.beginDraw();
  canvas.background(ground);
  canvas.image(startLayer, 0, 0);
  int[] o = layerOrder;
  for (int p = 0; p < LAYERS; p++) {
    int i = o[p];
    if (v("layerOn" + i) < 0.5) continue;
    float solid = 1 - v("layerSeeThrough" + i);
    float op = 255 * solid;
    float gap = box ? v("layerGap" + i) : 0;
    if (gap > 0 && v("boxShadow") > 0) {
      float len = gap * reach;
      boxShadow.set("offset", -lx * len, -ly * len);
      boxShadow.set("radius", 1 + v("boxSoftness") * len);
      boxShadow.set("strength", v("boxShadow") * solid);
      boxShadow.set("flipY", boxFlipY);
      PGL pgl = canvas.beginPGL();
      blendLayer(pgl, 0);
      canvas.shader(boxShadow);
      canvas.image(layers[i], 0, 0);
      canvas.flush();
      canvas.resetShader();
      canvas.endPGL();
    }
    boolean rim = box && v("boxRim") > 0;
    if (rim) {
      boxRim.set("toLight", lx, ly);
      boxRim.set("width", 2 + gap * 0.15);
      boxRim.set("amount", v("boxRim"));
      boxRim.set("flipY", boxFlipY);
      canvas.shader(boxRim);
    }
    PGL pgl = canvas.beginPGL();
    blendLayer(pgl, (int) v("layerBlend" + i));
    canvas.tint(op, op);          // premultiplied, so fading scales the colour as well as the alpha
    canvas.image(layers[i], 0, 0);
    canvas.flush();
    canvas.endPGL();              // puts Processing's own blending back
    canvas.noTint();
    if (rim) canvas.resetShader();
  }
  canvas.endDraw();
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
void eraseWith(PGraphics g, PGraphics mask) {
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
