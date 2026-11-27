// painter2DA
// The PoorTrait painter, 2D only (the painter sketch has the 3D mesh as well). One picture's maps
// from the map maker steer thousands of marks - their size, direction, colour and see-through-ness
// - while you change things on the control panel (the Gui tab, which opens in its own window) and
// watch what happens. The point is to experiment: to get a look nobody could predict.
//
// On the panel, SETUP is fixed for a whole run: which picture and the masses.
// Press RUN and everything else can be changed while it paints - new marks use the new settings
// on top of the old ones. STOP ends the run; the painting stays until the next
// RUN starts a fresh one. (What COPY has laid on the layers before the RUN stays - the Copy tab.)
//
// The output window is the photo's size (times windowScale below), and changes size when you
// pick a different picture. The painting itself is always the photo's size, so a saved painting
// lines up with the maps.
//
// Keys in this window: space = pause, n = one step (while paused), c = clear, s = save,
//                      Tab = the control panel to the front (Tab there brings this window back)
//
// The painting is seven see-through layers on white (the Layers tab), combined into one picture
// every frame.
//
// SAVE writes the painting, each layer, the paint's height (impasto),
// SETUP 5's palette (and the masses in its colours, if they're on), and a .json of every setting
// on the panel, into a folder of its own in the saved folder: the picture's name and the next
// free letter (PXL_1234-A, PXL_1234-B, ... after Z, AA, AB ...), each file named the same way.
// LOAD SETTINGS puts a saved .json's settings back on the panel.

// ---- settings ----
float windowScale = 1.5;     // the output window is the photo's size times this - or less, to fit the screen
float ui = 1;                // size of the direction field drawing (used by the Field tab)

// ---- the panel, and what it asks for ----
Panel panel;                 // the control panel window (the Gui tab)
HashMap<String, Float> params = new HashMap<String, Float>();   // the panel's values, read once a frame
java.util.concurrent.ConcurrentLinkedQueue<String> commands = new java.util.concurrent.ConcurrentLinkedQueue<String>();
boolean saveWanted = false;
boolean runWaiting = false;  // RUN was pressed, but the masses aren't made yet
boolean stepWanted = false;  // STEP was pressed: paint one step while paused
float paceOwed = 0;          // painting speed: how many steps are due (see paceDue)
int paceLast = 0;

// ---- state ----
String[] faces;              // folder names in mapsFolder
String faceName;
PGraphics canvas;            // the painting as you see it: the layers combined (Layers tab), at the photo's size
int[] canvasPix;             // the canvas's colours at the start of this frame (for wet paint)
PImage canvasSnap;           // the same as a picture (for chunk and copy from the canvas)
volatile boolean isRunning = false, isPaused = false;
volatile int markCount = 0;
volatile float outputFps = 0;
int runSeed = 0;
boolean around = true;       // used by the Field tab: marks go around the form, or across it
boolean alongOutline = false; // ... or along the outline (MOVEMENT's third choice)

String[] blendNames = { "normal", "multiply", "screen", "lightest", "darkest", "add", "subtract" };
int[] blendModes = { BLEND, MULTIPLY, SCREEN, LIGHTEST, DARKEST, ADD, SUBTRACT };


void settings() {
  // the window starts at the first picture's size
  faces = findFaces();
  int w = 800, h = 800;
  if (faces.length > 0) {
    try {
      java.awt.image.BufferedImage b = javax.imageio.ImageIO.read(new java.io.File(mapsPath() + "/" + faces[0] + "/photo.png"));
      w = b.getWidth();
      h = b.getHeight();
    } catch (Exception e) {
      println("couldn't read the first photo's size: " + e);
    }
  }
  int[] s = windowFor(w, h);
  size(s[0], s[1], P2D);
  // Processing 4 doubles everything on a Windows screen scaled to 200% - the window and the
  // canvas too, so paintings would be painted and saved at twice the photo's size. Keep it 1:1
  pixelDensity(1);
}

void setup() {
  surface.setTitle("painter2DA");
  // Processing can't see the screen size here, so it puts the window off the top left - put it
  // near the top left instead
  surface.setLocation(40, 80);
  if (faces.length == 0) {
    println("no map folders in " + mapsPath() + " - run the map maker on a photo first");
    exit();
    return;
  }
  loadFace(faces[0], 4);
  panel = new Panel();
  PApplet.runSketch(new String[] { "painter panel" }, panel);
}

void draw() {
  if (panel == null || !panel.ready) {
    background(30);
    return;
  }
  // take the commands first, then read the panel - a command's control has always changed by
  // the time its command arrives, so this way the command sees the new value
  ArrayList<String> todo = new ArrayList<String>();
  String c;
  while ((c = commands.poll()) != null) todo.add(c);
  autoStep();                // a script painting instead of the panel (the Auto tab) - only if one's given
  params = panel.snapshot();
  applyAutomation();         // AUTOMATION's waves over the tools' sizes (the Automation tab)
  for (String t : todo) handle(t);
  updateMasses();
  updatePaletteMasses();
  updatePaletteMesh();
  updatePatches();           // the blobs, triangles ... to pick from (the Picks tab)
  updatePaletteMatch();
  updatePaletteUse();
  // nothing paints while a map is showing (VIEW's MAPS) - you couldn't see what it's doing
  if (isRunning && !isPaused && mapShowing()) isPaused = true;
  if (runWaiting && !massesPending()) {
    runWaiting = false;
    startRun();
  }

  if (isRunning && !isPaused && paceDue()) paintFrame();
  else if (stepWanted && isRunning && isPaused && !mapShowing()) paintFrame();
  stepWanted = false;

  if (panel.setupComplete()) layersReady();     // from then on the window shows them, white to start with
  lookForPaint();            // (for VIEW's list)
  composite();               // the layers into one picture, every frame - layer settings can change any time
  draw2D();

  if (saveWanted) {
    saveAll();
    saveWanted = false;
  }
  outputFps = frameRate;
}

// a value from the panel (sliders, toggles, and which item a list or radio button has chosen)
float v(String name) {
  Float f = params.get(name);
  return f == null ? 0 : f;
}

// the panel asks for things here; they're done at the start of the next frame, in this window,
// because that's where anything to do with the canvas has to happen
void command(String c) {
  commands.add(c);
}

void handle(String c) {
  if (c.startsWith("recolourPalette ")) {
    recolourWantedLayer = int(c.substring(16));
    recolourWanted = true;
  }
  else if (c.equals("source")) {
    String f = faces[constrain((int) v("source"), 0, faces.length - 1)];
    if (!isRunning && !f.equals(faceName)) loadFace(f, (int) v("smoothing"));
  }
  else if (c.equals("open")) openPicture();
  else if (c.equals("front")) {
    // Tab on the panel: this window to the front - from a thread of its own, as the window waits
    // for the frame being drawn to finish
    new Thread(new Runnable() {
      public void run() {
        surface.setAlwaysOnTop(true);
        surface.setAlwaysOnTop(false);
        ((com.jogamp.newt.opengl.GLWindow) surface.getNative()).requestFocus();
      }
    }).start();
  }
  else if (c.startsWith("picture ")) {
    // a photo of your own, its maps ready: on the list, and loaded - unless a run is going
    String name = c.substring(8);
    faces = findFaces();
    int i = java.util.Arrays.asList(faces).indexOf(name);
    if (isRunning) mapStatus = name + " is ready - STOP, then choose it in SETUP 1";
    else {
      loadFace(name, (int) v("smoothing"));
      panel.sourceDone = true;
      panel.massesDone = false;
      panel.meshDone = false;
    }
    panel.newSources(isRunning ? -1 : i);
  }
  else if (c.equals("run")) {
    // the masses are part of the setup, so a run waits until they're made
    if (mapShowing()) println("a map is showing - choose MAPS: PAINTING to paint");
    else if (massesPending()) runWaiting = true;
    else startRun();
  }
  else if (c.equals("stop")) { isRunning = false; isPaused = false; runWaiting = false; }
  else if (c.equals("pause")) {
    if (isRunning && !(isPaused && mapShowing())) {
      isPaused = !isPaused;
      if (!isPaused) restartGrid();      // CARRY ON: the grid starts another pass at the top left
    }
  }
  else if (c.equals("step")) stepWanted = true;
  else if (c.equals("save")) saveWanted = true;
  else if (c.equals("load")) selectInput("Choose a settings file (.json)", "settingsChosen", new java.io.File(sketchPath("saved") + "/x.json"));
  else if (c.startsWith("clearPicks")) clearPicks(int(c.substring(11)));
  else if (c.equals("copyMap")) copyNow();
  else if (c.equals("field")) buildField(normalImg, (int) v("smoothing"));
  else if (c.equals("eraseArea")) eraseArea();
  else if (c.equals("layMasses")) layMasses(v("layOpacity"));
  else if (c.startsWith("clearLayer")) clearLayer(int(c.substring(10)));
  else if (c.startsWith("moveLayer")) {
    String[] a = split(c, ' ');
    moveLayer(int(a[1]), int(a[2]));
  }
  else if (c.equals("massSeed")) textureSeed = random(1, 1000);
}


// ---------------------------------------------------------------- a run

// an accent colour: a hue, saturation and brightness picked at random between the limits of
// COLOUR's accent ranges (all tools share them)
color randomAccent() {
  float h = random(v("accentHue_lo"), v("accentHue_hi")) / 360.0;
  float s = random(v("accentSat_lo"), v("accentSat_hi")) / 100.0;
  float b = random(v("accentBri_lo"), v("accentBri_hi")) / 100.0;
  return java.awt.Color.HSBtoRGB(h - floor(h), s, b) | 0xFF000000;
}

void startRun() {
  runSeed = (int) random(1000000);
  randomSeed(runSeed);
  noiseSeed(runSeed);
  layersReady();
  if (painted) clearCanvas();
  else resetTools();           // the layers are as they were: what's been copied on them stays
  isPaused = false;
  isRunning = true;
  println("run: " + faceName + ", seed " + runSeed);
}

// the layers for this picture made, and empty, if they haven't been (once SETUP is done, or at the
// first RUN). After a run the painting stays, until the next RUN or another picture
void layersReady() {
  if (canvas != null) return;
  makeLayers();
  for (int i = 0; i < LAYERS; i++) clearLayer(i);
  painted = false;
}

// every layer empty - white - and the tools back to their starts (the Layers tab)
void clearCanvas() {
  if (canvas == null) return;
  for (int i = 0; i < LAYERS; i++) clearLayer(i);
  painted = false;
  resetTools();
}

void resetTools() {
  pencils.clear();
  flows.clear();
  outlineRestart = true;
  spongePaint = 0;
  composite();
  markCount = 0;
  restartGrid();
  resetCreases();
}

// whether tool number i is switched on
boolean toolOn(int i) {
  return v(TOOLS[i] + "_on") > 0.5;
}

void paintFrame() {
  // tools that pick up wet paint need to see the canvas - read it once a frame
  boolean wet = false, textured = false;
  for (int i = 0; i < TOOLS.length; i++) {
    if (!toolOn(i)) continue;
    int pickup = (int) v(TOOLS[i] + "_pickup");
    if (pickup == 1 || pickup == 2) {
      wet = true;
      textured |= carryTextured((int) v(TOOLS[i] + "_carry"));
    }
  }
  if (wet) {
    canvas.loadPixels();
    canvasPix = canvas.pixels;
    if (textured) {
      if (canvasSnap == null || canvasSnap.width != canvas.width || canvasSnap.height != canvas.height) {
        canvasSnap = createImage(canvas.width, canvas.height, ARGB);
      }
      canvasSnap.loadPixels();
      arrayCopy(canvasPix, canvasSnap.pixels);
      canvasSnap.updatePixels();
    }
  }

  // each tool that's on paints on its layer (LAYERS), with its own blend (APPLY), layer by layer
  // and in the TOOLS order within a layer. Scrape takes paint off afterwards
  // (A tool whose layer hasn't been picked yet - its layer is -1 - doesn't paint, nor one whose IN
  // AREA hasn't been chosen.)
  // A tool with a thickness also adds what it painted to its layer's height (the Impasto tab)
  for (int L = 0; L < LAYERS; L++) {
    for (int i = 0; i < PAINT_TOOLS; i++) {
      if (!toolOn(i) || (int) v(TOOLS[i] + "_layer") != L) continue;
      useTool(i);
      if (!areaAllows()) continue;            // IN AREA not chosen yet (the Area tab)
      painted = true;
      PGraphics g = layers[L];
      float thick = t("thickness");
      boolean shapes = thick > 0 && shaped(i);      // (the Impasto tab)
      if (shapes) startShapes();
      else if (thick > 0) snapLayer(g);
      boolean clip = areaClipping();          // IN AREA (the Area tab)
      if (clip) areaSnapLayer(g);
      g.beginDraw();
      g.blendMode(blendModes[constrain((int) t("blend"), 0, blendModes.length - 1)]);
      if (i <= 1) {
        int n = (int) t("perFrame");
        for (int k = 0; k < n; k++) paintMark(g);
      }
      else if (TOOLS[i].equals("splat")) paintSplatters(g);
      else if (TOOLS[i].equals("line")) paintLines(g);
      else if (TOOLS[i].equals("pencil")) paintPencils(g);
      else if (TOOLS[i].equals("flow")) paintFlows(g);
      else if (TOOLS[i].equals("outline")) paintOutline(g);
      else paintSponges(g);
      g.blendMode(BLEND);
      g.endDraw();
      if (clip) areaClip(g);
      if (shapes) addShapes(L, thick);
      else if (thick > 0) addHeight(L, thick);
      if (layerEmpty[L]) layerChanged[L] = true;
    }
  }
  useTool(T_SCRAPE);
  paintScrapes();
}

// RUN's painting speed: whether to paint a step this frame. At full speed every frame paints;
// slower, steps are owed as time goes by and paid one a frame, so the window keeps going at full
// speed while the painting slows down
boolean paceDue() {
  int now = millis();
  float dt = min(0.25, (now - paceLast) / 1000.0);
  paceLast = now;
  float pace = v("pace");
  if (pace >= 0.999) return true;
  paceOwed = min(1, paceOwed + paceRate(pace) * dt);
  if (paceOwed < 1) return false;
  paceOwed -= 1;
  return true;
}

// steps a second for the painting speed slider (0 .. 1): from one every 2 seconds up to 60
float paceRate(float pace) {
  return 0.5 * pow(120, pace);
}

// the painting speed in words, for the slider
String paceText(float rate) {
  if (rate >= 59.5) return "full speed";
  if (rate >= 1.5) return round(rate) + " a second";
  if (rate >= 0.95) return "1 a second";
  return "1 every " + nf(1 / rate, 0, 1) + " s";
}

// make tool i the one painting: t() reads its settings, and the direction field goes around or
// across the form, or along the outline, as its MOVEMENT says
void useTool(int i) {
  tool = TOOLS[i];
  around = t("around") == 0;
  alongOutline = t("around") == 2;
  if (alongOutline) outlineFieldReady();
}


// ---------------------------------------------------------------- showing it

// whether VIEW's MAPS has a map showing instead of the painting (nothing paints then)
boolean mapShowing() {
  return v("showWhat") > 0;
}

// the picture VIEW's MAPS has chosen (0: the painting)
PImage currentView() {
  int s = (int) v("showWhat");
  // RECOLOUR's "masses" or "mesh" being reworked: the exact colours, kept up as the sliders move
  if (recolouringPalette() && !panel.paletteOpen && s == (panel.recolourKind == 1 ? VIEW_PAL_MASSES : VIEW_PAL_MESH)) {
    PImage p = recolourPalettePicture();
    if (p != null) return p;
  }
  if (s == VIEW_PAINTING) return canvas != null ? canvas : photo;
  PImage p = mapPicture(constrain(s, VIEW_PHOTO, VIEW_MESH_LINES));
  if (p == null && s == VIEW_PAL_MASSES) p = massesImg;
  if (p == null && s == VIEW_PAL_MESH) p = meshImg;
  return p != null ? p : photo;
}

void draw2D() {
  background(255);              // (under "mesh (lines)", which is only lines)
  image(currentView(), 0, 0, width, height);
  if (zoneShowing()) drawZone();      // APPLY open with the zone in it: the zone instead (the Zone tab)
  drawPatchPicks();
  if (v("fieldOverlay") > 0.5) {
    // the field of the tool chosen in column 2 (around, across or along the outline)
    String was = tool;
    int e = java.util.Arrays.asList(TOOLS).indexOf(panel.editing);
    if (e >= 0) useTool(e);
    drawField(0, 0, width / (float) photo.width);
    tool = was;
    around = t("around") == 0;
    alongOutline = t("around") == 2;
  }
  if (panel.outlineOpen || v("viewOutline") > 0.5) drawOutlinePreview(width / (float) photo.width);
  if (panel.meshOpen) drawMeshPreview(width / (float) photo.width);     // the mesh's triangles
}


// ---------------------------------------------------------------- saving and loading

// the painting (photo size), its parts, and every setting on the panel
void saveAll() {
  String base = saveFolder();
  if (canvas != null) {
    canvas.save(base + ".png");
    for (int i = 0; i < LAYERS; i++) layerPicture(i).save(base + "-layer" + LAYER_NAMES[i] + ".png");
    combineHeights();
    heightAll.save(base + "-height.png");
  }
  PImage pal = palettePicture();
  if (pal != null) pal.save(base + "-palette.png");
  if (paletteMassesImg != null) paletteMassesImg.save(base + "-masses-palette.png");
  JSONObject j = panel.settingsJSON();
  j.setString("layerOrder", join(str(layerOrder), " "));
  j.setInt("seed", runSeed);
  j.setFloat("textureSeed", textureSeed);
  j.setInt("marks", markCount);
  j.setString("savedAt", nf(year(), 4) + "-" + nf(month(), 2) + "-" + nf(day(), 2) + " " + nf(hour(), 2) + ":" + nf(minute(), 2) + ":" + nf(second(), 2));
  saveJSONObject(j, base + ".json");
  println("saved to " + new java.io.File(base).getParent() + "  (the painting, each layer, the height, the palette, .json)");
}

// SAVE's folder: the picture's name and the next letter not used yet - made, and returned with
// the start of its files' names (the folder's own name)
String saveFolder() {
  String dir = sketchPath("saved");
  for (int n = 0; ; n++) {
    String name = faceName + "-" + saveLetters(n);
    java.io.File f = new java.io.File(dir, name);
    if (f.exists()) continue;
    f.mkdirs();
    return f.getPath().replace('\\', '/') + "/" + name;
  }
}

// 0 = A, 25 = Z, 26 = AA, 27 = AB ... (like spreadsheet columns)
String saveLetters(int n) {
  String s = "";
  for (n++; n > 0; n = (n - 1) / 26) s = (char) ('A' + (n - 1) % 26) + s;
  return s;
}

void settingsChosen(java.io.File f) {
  if (f == null) return;
  JSONObject j = loadJSONObject(f.getAbsolutePath());
  panel.applySettings(j, !isRunning);
  if (j.hasKey("textureSeed")) textureSeed = j.getFloat("textureSeed");
  if (j.hasKey("layerOrder")) {
    int[] o = int(split(j.getString("layerOrder"), ' '));
    if (o.length == LAYERS) layerOrder = o;
  }
  println("settings from " + f.getName() + (isRunning ? " (SETUP left as it is while running)" : ""));
}


// ---------------------------------------------------------------- mouse and keys

// a click in this window while a PICK ON THE MASSES is on (until it's pressed again) turns the
// palette colour of the mass under it on or off - one of IN AREA's - and isn't a "start at: mouse" mark. (For IN AREA's Masses, Tris, Objects and Face Parts,
// it picks those, and dragging goes on picking - the Picks tab)
boolean pickClick = false;

void mousePressed() {
  // (for finding a fault - take out once "start at: mouse" works) what the painter is doing
  String s = "painting click " + mouseX + "," + mouseY + "  running=" + isRunning + " paused=" + isPaused
    + " view=" + showNames[constrain((int) v("showWhat"), 0, showNames.length - 1)] + " picking=" + panel.picking + "  tools on:";
  for (int i = 0; i < TOOLS.length; i++) if (toolOn(i)) {
    String n = TOOLS[i];
    s += "  " + n + " (start at " + (int) v(n + "_startAt") + ", in area " + (int) v(n + "_inArea") + ", layer " + (v(n + "_layer") < 0 ? "none" : LAYER_NAMES[(int) v(n + "_layer")])
      + (v("layerOn" + (int) v(n + "_layer")) < 0.5 ? " HIDDEN" : "") + ")";
  }
  println(s);
  if (panel.picking == panel.PICK_NONE) return;
  pickClick = true;
  float px = mouseX * photo.width / (float) width, py = mouseY * photo.height / (float) height;
  int kind = pickingPatches();
  if (kind >= 0) {
    patchPressed(kind, px, py);
    return;
  }
  int pick = v(panel.editing + "_inArea") == AREA_MESH_COLOUR ? meshPaletteColourAt(px, py) : paletteColourAt(px, py);
  if (pick < 0 || pick >= PALETTE_SIZE) return;
  boolean[] picks = panel.areaPick;
  picks[pick] = !picks[pick];
  println("IN AREA: palette colour " + (pick + 1)
    + (picks[pick] ? " added" : " taken out"));
}

void mouseDragged() {
  int k = pickingPatches();
  if (!pickClick || k < 0) return;
  float sx = photo.width / (float) width, sy = photo.height / (float) height;
  patchDragged(k, pmouseX * sx, pmouseY * sy, mouseX * sx, mouseY * sy);
}

void mouseReleased() {
  pickClick = false;
}

void keyPressed() {
  if (key == TAB) panel.toFront();
  else if (key == ' ') command("pause");
  else if (key == 'n') command("step");
  else if (key == 's') command("save");
}
