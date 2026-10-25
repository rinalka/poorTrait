// Impasto: thick paint that catches the light (design doc, "Additions": impasto relief).
//
// Each layer has a height to go with its colours (`heights`), starting flat. Whenever a tool
// paints, what changed on its layer is added to the layer's height, as thick as the tool's APPLY
// "thickness" says (data/heightAdd.glsl): a palette-knife mark becomes a slab with steep edges,
// a wash or a pencil line hardly anything. A new mark squashes the paint under it a little, so the
// height doesn't just pile up for ever. Scraping takes height off with the paint, and CLEAR on a
// layer flattens it.
//
// Every frame the visible layers' heights are added up (`heightAll`), each turned up or down by
// its "impasto" slider in LAYERS, and the IMPASTO light rakes across them (data/impasto.glsl, run
// over the combined canvas in composite()): slopes facing the light get lighter, slopes facing
// away darker, with a little shine. The canvas, the mesh and a
// saved painting all have it. SAVE also writes the height as -height.png - white is thick - which
// could later push the mesh's surface out.
//
// The same pass lets the backdrop's texture show through the paint (the Backdrop tab).

PGraphics[] heights = new PGraphics[4];     // one for each layer (LAYERS, which is defined later)
PGraphics heightAll;         // every visible layer's height, added up
PGraphics heightSnap;        // the layer being painted, as it was before the tool painted
PGraphics finished;          // the canvas through the finishing pass, before it's copied back
PShader heightAdd, impastoShader;

void makeHeights() {
  for (int i = 0; i < LAYERS; i++) heights[i] = photoSized(heights[i]);
  heightAll = photoSized(heightAll);
  heightSnap = photoSized(heightSnap);
  finished = photoSized(finished);
  if (heightAdd == null) {
    heightAdd = loadShader("heightAdd.glsl");
    impastoShader = loadShader("impasto.glsl");
  }
}

void clearHeight(int i) {
  if (heights[i] == null) return;
  heights[i].beginDraw();
  heights[i].clear();
  heights[i].endDraw();
}

// before a tool paints on layer g: remember how it looks
void snapLayer(PGraphics g) {
  heightSnap.beginDraw();
  heightSnap.clear();
  heightSnap.blendMode(REPLACE);
  heightSnap.image(g, 0, 0);
  heightSnap.blendMode(BLEND);
  heightSnap.endDraw();
}

// after it has: whatever changed on layer i is new paint, `thickness` thick
void addHeight(int i, float thickness) {
  PGraphics h = heights[i];
  heightAdd.set("prev", heightSnap);
  heightAdd.set("thickness", thickness * 0.12);
  heightAdd.set("squash", 0.4);
  h.beginDraw();
  PGL pgl = h.beginPGL();
  blendLayer(pgl, 0);          // (ONE, ONE_MINUS_SRC_ALPHA): the shader's squash and new height
  h.shader(heightAdd);
  h.image(layers[i], 0, 0);
  h.flush();
  h.resetShader();
  h.endPGL();
  h.endDraw();
}

// the visible layers' heights added up, each as much as its layer shows and as its "impasto"
// in LAYERS says - at 0 its paint lies flat
void combineHeights() {
  heightAll.beginDraw();
  heightAll.background(0);
  int[] o = layerOrder;
  for (int p = 0; p < LAYERS; p++) {
    int i = o[p];
    if (v("layerOn" + i) < 0.5) continue;
    float op = 255 * (1 - v("layerSeeThrough" + i)) * v("layerImpasto" + i);
    PGL pgl = heightAll.beginPGL();
    pgl.blendEquation(PGL.FUNC_ADD);
    pgl.blendFuncSeparate(PGL.ONE, PGL.ONE, PGL.ONE, PGL.ONE);
    heightAll.tint(op, op);
    heightAll.image(heights[i], 0, 0);
    heightAll.flush();
    heightAll.endPGL();
    heightAll.noTint();
  }
  heightAll.endDraw();
}

// whether the finishing pass (the light on the paint, the backdrop showing through) does anything
boolean finishing() {
  return v("impastoOn") > 0.5 || (v("backdropKind") > 0 && v("backdropThrough") > 0);
}

// the finishing pass, over the canvas once it's combined (composite() calls it last). Drawn into
// `finished` and copied back - filter() would be simpler, but it scales an offscreen picture by
// the window's size
void finish(PGraphics c) {
  boolean on = v("impastoOn") > 0.5;
  boolean textured = v("backdropKind") > 0;
  float from = radians(v("impastoFrom")), up = radians(v("impastoHeight"));
  impastoShader.set("heights", heightAll);
  impastoShader.set("groundTex", backdropGraphics());
  impastoShader.set("relief", on ? v("impastoRelief") : 0);
  impastoShader.set("gloss", on ? v("impastoGloss") : 0);
  impastoShader.set("toLight", cos(from) * cos(up), -sin(from) * cos(up), sin(up));
  impastoShader.set("through", textured ? v("backdropThrough") : 0);
  // a weave or paper is bumpy where it shows through; newspaper's print is flat
  impastoShader.set("groundBumps", textured && v("backdropKind") != 3 ? v("backdropThrough") * (on ? 1 : 0) : 0);
  impastoShader.set("flipY", boxFlipY);
  finished.beginDraw();
  finished.shader(impastoShader);
  finished.blendMode(REPLACE);
  finished.image(c, 0, 0);
  finished.resetShader();
  finished.blendMode(BLEND);
  finished.endDraw();
  c.beginDraw();
  c.blendMode(REPLACE);
  c.image(finished, 0, 0);
  c.blendMode(BLEND);
  c.endDraw();
}
