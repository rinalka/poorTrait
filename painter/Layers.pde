// Layers: the painting is four see-through layers, one on top of another, combined every frame
// into `canvas` - the picture you see, that the mesh wears, and that wet paint picks up from.
//
// Layer 1 is the bottom one. It starts solid: the canvas colour with the masses or the photo on
// it (MASSES "start the canvas with"). Layers 2 - 4 start empty. In the panel's LAYERS block, each
// mark system chooses the layer it paints on, and each layer can be hidden, faded or combined with
// the ones under it in a different way (multiply, screen ...). SCRAPE takes paint off the layers
// above a chosen layer, showing what's underneath.
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
String[] layerBlendNames = { "normal", "multiply", "screen", "add", "lightest" };

// the layers (and the combined picture) at the photo's size
void makeLayers() {
  for (int i = 0; i < LAYERS; i++) {
    if (layers[i] == null || layers[i].width != photo.width || layers[i].height != photo.height) {
      layers[i] = createGraphics(photo.width, photo.height, P2D);
    }
  }
  if (canvas == null || canvas.width != photo.width || canvas.height != photo.height) {
    canvas = createGraphics(photo.width, photo.height, P2D);
  }
}

// layer 1 back to its start (canvas colour, and the masses or photo); the others to empty
void clearLayer(int i) {
  if (layers[i] == null) return;
  PGraphics g = layers[i];
  g.beginDraw();
  if (i == 0) {
    int start = (int) v("startWith");
    PImage under = start == 1 ? massesImg : start == 2 ? photo : null;
    if (start == 1 && massesImg == null) println("the masses aren't ready yet - starting with the plain canvas colour");
    g.background(ground);
    if (under != null) g.image(under, 0, 0);
  } else {
    g.clear();
  }
  g.endDraw();
}

// combine the layers into `canvas`, bottom to top
void composite() {
  if (canvas == null) return;
  canvas.beginDraw();
  canvas.background(ground);
  for (int i = 0; i < LAYERS; i++) {
    if (v("layerOn" + i) < 0.5) continue;
    float op = 255 * v("layerOpacity" + i);
    PGL pgl = canvas.beginPGL();
    blendLayer(pgl, (int) v("layerBlend" + i));
    canvas.tint(op, op);          // premultiplied, so fading scales the colour as well as the alpha
    canvas.image(layers[i], 0, 0);
    canvas.flush();
    canvas.endPGL();              // puts Processing's own blending back
  }
  canvas.noTint();
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
