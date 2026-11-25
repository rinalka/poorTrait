// Impasto: thick paint that catches the light (design doc, "Additions": impasto relief).
//
// Each layer has a height to go with its colours (`heights`), starting flat. Whenever a tool
// paints, what changed on its layer is added to the layer's height, as thick as the tool's APPLY
// "thickness" says (data/heightAdd.glsl): a palette-knife mark becomes a slab with steep edges,
// a wash or a pencil line hardly anything. A new mark squashes the paint under it a little, so the
// height doesn't just pile up for ever. Scraping takes height off with the paint, and CLEAR on a
// layer flattens it.
//
// The brush, the knife, the splatter and the sponge have a shape to their paint as well (below, "the shape
// of the paint"), and lie much deeper: a stroke is thick where it starts and along its sides, thinning out
// towards its end.
//
// Every frame the visible layers' heights are added up (`heightAll`), each turned up or down by
// the "impasto" slider in its box, and the panel's LIGHT rakes across them (data/impasto.glsl, run
// over the combined canvas in composite()): slopes facing the light get lighter, slopes facing
// away darker, with a little shine. The canvas and a saved painting both have it. SAVE also
// writes the height as -height.png - white is thick.

PGraphics[] heights = new PGraphics[7];     // one for each layer (LAYERS, which is defined later)
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

// the most any visible layer's "impasto" is
float mostImpasto() {
  float most = 0;
  for (int i = 0; i < LAYERS; i++) if (v("layerOn" + i) > 0.5) most = max(most, v("layerImpasto" + i));
  return most;
}

// the visible layers' heights added up, each as much as its layer shows and as its "impasto" says,
// next to the most any of them has (finish() makes up for that: so a little impasto doesn't lose the fine
// steps of the heights) - at 0 its paint lies flat
void combineHeights() {
  float most = max(0.001, mostImpasto());
  heightAll.beginDraw();
  heightAll.background(0);
  int[] o = layerOrder;
  for (int p = 0; p < LAYERS; p++) {
    int i = o[p];
    if (v("layerOn" + i) < 0.5) continue;
    float op = 255 * (1 - v("layerSeeThrough" + i)) * v("layerImpasto" + i) / most;
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

// whether the finishing pass (the light on the paint) does anything
boolean finishing() {
  return mostImpasto() > 0;
}

// the finishing pass, over the canvas once it's combined (composite() calls it last). Drawn into
// `finished` and copied back - filter() would be simpler, but it scales an offscreen picture by
// the window's size
void finish(PGraphics c) {
  float from = radians(v("lightFrom")), up = radians(v("lightHeight"));
  impastoShader.set("heights", heightAll);
  impastoShader.set("relief", mostImpasto());
  impastoShader.set("gloss", v("lightShine"));
  impastoShader.set("toLight", cos(from) * cos(up), -sin(from) * cos(up), sin(up));
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


// ---------------------------------------------------------------- the shape of the paint
// While one of these tools paints, each of its marks also leaves its shape here - triangles, each corner
// with how thick the paint is there (0 .. 1) and how solid (0 .. 255) - or, the sponge, a picture for each
// print (thickness in its colours). Afterwards they're drawn into `depthMap`, later marks over earlier ones, and
// that's put on the layer's height (data/depthAdd.glsl): most of the height under a mark is pressed flat, and
// the mark's own goes on top.

PGraphics depthMap;
PShader depthAdd;
boolean shaping = false;              // the tool painting now leaves its marks' shapes
float[] shape = new float[4096];      // x, y, thickness, solidity of each corner
int shapeN = 0;
ArrayList<float[]> shapePrints = new ArrayList<float[]>();     // the sponge: x, y, turn, solidity of each print
final float DEPTH = 0.55;             // how high the thickest paint is, with the tool's thickness at 1 (0 .. 1)
final float PRESSED = 0.75;           // how much of the height under a solid mark is pressed flat

// whether tool i's marks have a shape
boolean shaped(int i) {
  return TOOLS[i].equals("brush") || TOOLS[i].equals("knife") || TOOLS[i].equals("splat") || TOOLS[i].equals("sponge");
}

void startShapes() {
  shaping = true;
  shapeN = 0;
  shapePrints.clear();
}

void shapeCorner(float x, float y, float thick, float solid) {
  if (shapeN + 4 > shape.length) shape = expand(shape);
  shape[shapeN++] = x;
  shape[shapeN++] = y;
  shape[shapeN++] = thick;
  shape[shapeN++] = solid;
}

// a ribbon's piece: two rows of corners across it, each the same number of points (x, y, thickness)
void shapeRows(float[] a, float[] b, float solidA, float solidB) {
  for (int i = 0; i + 5 < a.length; i += 3) {
    shapeCorner(a[i], a[i + 1], a[i + 2], solidA);
    shapeCorner(a[i + 3], a[i + 4], a[i + 5], solidA);
    shapeCorner(b[i], b[i + 1], b[i + 2], solidB);
    shapeCorner(a[i + 3], a[i + 4], a[i + 5], solidA);
    shapeCorner(b[i + 3], b[i + 4], b[i + 5], solidB);
    shapeCorner(b[i], b[i + 1], b[i + 2], solidB);
  }
}

// a blob with the outline (px, py): `middle` thick in the middle, up to `rim` just inside its edge
void shapeBlob(float[] px, float[] py, float middle, float rim, float solid) {
  int n = px.length;
  float cx = 0, cy = 0;
  for (int i = 0; i < n; i++) {
    cx += px[i] / n;
    cy += py[i] / n;
  }
  for (int i = 0; i < n; i++) {
    int j = (i + 1) % n;
    float ix = lerp(cx, px[i], 0.76), iy = lerp(cy, py[i], 0.76), jx = lerp(cx, px[j], 0.76), jy = lerp(cy, py[j], 0.76);
    shapeCorner(cx, cy, middle, solid);
    shapeCorner(ix, iy, rim, solid);
    shapeCorner(jx, jy, rim, solid);
    shapeRows(new float[] { ix, iy, rim, jx, jy, rim }, new float[] { px[i], py[i], rim * 0.55, px[j], py[j], rim * 0.55 }, solid, solid);
  }
}

void shapeDisc(float x, float y, float r, int pts, float middle, float rim, float solid) {
  pts = max(pts, min(24, round(r * 2.5)));
  float[] px = new float[pts], py = new float[pts];
  for (int i = 0; i < pts; i++) {
    px[i] = x + cos(TWO_PI * i / pts) * r;
    py[i] = y + sin(TWO_PI * i / pts) * r;
  }
  if (r >= 2) {
    shapeBlob(px, py, middle, rim, solid);
    return;
  }
  for (int i = 0; i < pts; i++) {
    int j = (i + 1) % pts;
    shapeCorner(x, y, rim, solid);
    shapeCorner(px[i], py[i], rim, solid);
    shapeCorner(px[j], py[j], rim, solid);
  }
}

// how thick a stroke is, u along it (0 .. 1) and v across it (-1 .. 1): a lip of paint along both sides and
// a heap where it starts, all of it thinning out towards the end
float strokeThickness(float u, float v) {
  float a = abs(v);
  float side = a > 0.82 ? lerp(1, 0.6, (a - 0.82) / 0.18) : 0.3 + 0.7 * pow(a / 0.82, 4);
  float heap = 0.95 * (1 - smoothstep(0, 0.22, u));
  return max(side, heap) * lerp(1, 0.08, pow(constrain(u, 0, 1), 0.8));
}

// the shapes left since startShapes() put on layer i's height, `thickness` thick
void addShapes(int i, float thickness) {
  shaping = false;
  if (shapeN == 0 && shapePrints.size() == 0) return;
  depthMap = photoSized(depthMap);
  if (depthAdd == null) depthAdd = loadShader("depthAdd.glsl");
  depthMap.beginDraw();
  depthMap.clear();
  depthMap.noStroke();
  if (shapeN > 0) {
    depthMap.beginShape(TRIANGLES);
    for (int k = 0; k < shapeN; k += 4) {
      depthMap.fill(255 * shape[k + 2], shape[k + 3]);
      depthMap.vertex(shape[k], shape[k + 1]);
    }
    depthMap.endShape();
  }
  for (int k = 0; k < shapePrints.size(); k++) {
    float[] p = shapePrints.get(k);
    PImage im = spongeDepths.get(k);
    depthMap.pushMatrix();
    depthMap.translate(p[0], p[1]);
    depthMap.rotate(p[2]);
    depthMap.tint(255, p[3]);
    depthMap.image(im, -im.width / 2.0, -im.height / 2.0);
    depthMap.noTint();
    depthMap.popMatrix();
  }
  depthMap.endDraw();
  areaClipMask(depthMap);                // IN AREA (the Area tab)
  PGraphics h = heights[i];
  depthAdd.set("thickness", thickness * DEPTH);
  depthAdd.set("pressed", PRESSED);
  h.beginDraw();
  PGL pgl = h.beginPGL();
  blendLayer(pgl, 0);
  h.shader(depthAdd);
  h.image(depthMap, 0, 0);
  h.flush();
  h.resetShader();
  h.endPGL();
  h.endDraw();
}
