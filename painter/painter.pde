// painter
// The PoorTrait painter. One picture's maps from the map maker steer thousands of marks - their
// size, direction, colour and see-through-ness - while you change things on the control panel
// (the Gui tab, which opens in its own window) and watch what happens. The point is to
// experiment: to get a look nobody could predict.
//
// On the panel, SETUP is fixed for a whole run: which picture, 2D canvas or 3D mesh, and the
// canvas colour. Press RUN and everything else can be changed while it paints - new marks use
// the new settings on top of the old ones. STOP ends the run; the painting stays until the next
// RUN starts a fresh one.
//
// The output window is the photo's size (times windowScale below), and changes size when you
// pick a different picture. The painting itself is always the photo's size, so a saved painting
// lines up with the maps and the 3D models.
//
// Showing a mesh:   drag = turn the model   right-drag = move the light   wheel = zoom
// Keys in this window: space = pause, c = clear, s = save, r = straight on again,
//                      l = light on / off
//
// The painting is four see-through layers (the Layers tab), combined into one picture every frame.
//
// SAVE writes the painting, each layer, and a .json of every setting on the panel, to the saved
// folder.
// LOAD SETTINGS puts a saved .json's settings back on the panel.

// ---- settings ----
float windowScale = 1.5;     // the output window is the photo's size times this
float ui = 1;                // size of the direction field drawing (used by the Field tab)
color clay = color(205, 198, 188);   // the Mesh tab's plain colour

// ---- the panel, and what it asks for ----
Panel panel;                 // the control panel window (the Gui tab)
HashMap<String, Float> params = new HashMap<String, Float>();   // the panel's values, read once a frame
java.util.concurrent.ConcurrentLinkedQueue<String> commands = new java.util.concurrent.ConcurrentLinkedQueue<String>();
boolean saveWanted = false;
boolean runWaiting = false;  // RUN was pressed, but the masses aren't made yet

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
int outputMode = 0;          // 0 = 2D canvas, 1 = mesh: just the person, 2 = mesh: whole photo
color ground;                // the canvas colour, fixed for a run
color accentNow;             // the accent colour this frame
Mesh mesh;
PShape meshShape;            // the model with the chosen picture (usually the painting) on it
float yaw = 0, pitch = 0, zoom = 1, lightYaw = -0.6, lightPitch = -0.5, swayTime = 0;
boolean around = true;       // used by the Field tab: marks go around the form, or across it

String[] showNames = { "painting", "photo", "normal", "importance", "curvature", "depth", "light", "masses" };
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
  size(round(w * windowScale), round(h * windowScale), P3D);
  // Processing 4 doubles everything on a Windows screen scaled to 200% - the window and the
  // canvas too, so paintings would be painted and saved at twice the photo's size. Keep it 1:1
  pixelDensity(1);
}

void setup() {
  surface.setTitle("painter");
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
  params = panel.snapshot();
  around = v("around") == 0;
  for (String t : todo) handle(t);
  updateMasses();
  if (runWaiting && !massesPending()) {
    runWaiting = false;
    startRun();
  }

  if (isRunning && !isPaused) paintFrame();

  composite();               // the layers into one picture, every frame - layer settings can change any time
  if (outputMode > 0 && meshShape != null) drawMesh();
  else draw2D();

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
  if (c.equals("source")) {
    String f = faces[constrain((int) v("source"), 0, faces.length - 1)];
    if (!isRunning && !f.equals(faceName)) loadFace(f, (int) v("smoothing"));
  }
  else if (c.equals("run")) {
    // the masses are part of the setup, so a run waits until they're made
    if (massesPending()) runWaiting = true;
    else startRun();
  }
  else if (c.equals("stop")) { isRunning = false; isPaused = false; runWaiting = false; }
  else if (c.equals("pause")) { if (isRunning) isPaused = !isPaused; }
  else if (c.equals("clear")) clearCanvas();
  else if (c.equals("save")) saveWanted = true;
  else if (c.equals("load")) selectInput("Choose a settings file (.json)", "settingsChosen", new java.io.File(sketchPath("saved") + "/x.json"));
  else if (c.equals("field")) buildField(normalImg, (int) v("smoothing"));
  else if (c.equals("show")) rebuildShape();
  else if (c.equals("resetView")) { yaw = 0; pitch = 0; zoom = 1; swayTime = 0; }
  else if (c.equals("layMasses")) layMasses(v("layOpacity"));
  else if (c.startsWith("clearLayer")) clearLayer(int(c.substring(10)));
  else if (c.equals("massSeed")) textureSeed = random(1, 1000);
}


// ---------------------------------------------------------------- a run

void startRun() {
  outputMode = (int) v("output");
  ground = panel.colour("ground");
  runSeed = (int) random(1000000);
  randomSeed(runSeed);
  noiseSeed(runSeed);
  makeLayers();
  clearCanvas();
  mesh = null;
  meshShape = null;
  if (outputMode > 0) {
    String path = mapsPath() + "/" + faceName + "/" + (outputMode == 1 ? "mesh_face.obj" : "mesh_full.obj");
    if (new java.io.File(path).exists()) mesh = new Mesh(path);
    else {
      println("no " + path + " - painting in 2D instead");
      outputMode = 0;
    }
  }
  rebuildShape();
  isPaused = false;
  isRunning = true;
  println("run: " + faceName + ", " + (outputMode == 0 ? "2D" : "mesh") + ", seed " + runSeed);
}

// every layer back to its start (the Layers tab's clearLayer)
void clearCanvas() {
  if (canvas == null) return;
  for (int i = 0; i < LAYERS; i++) clearLayer(i);
  composite();
  markCount = 0;
  gridI = 0;
}

void paintFrame() {
  // brushes that pick up wet paint need to see the canvas - read it once a frame
  int pickup = (int) v("pickup");
  boolean textured = v("carry") >= CHUNK;
  if (pickup == 1 || pickup == 2) {
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
  accentNow = panel.colour("accent");

  // each mark system paints on the layer LAYERS says, in this order
  String[] layerChoice = { "layerBrush", "layerSplat", "layerLines", "layerFrag" };
  int blend = blendModes[constrain((int) v("blendType"), 0, blendModes.length - 1)];
  for (int L = 0; L < LAYERS; L++) {
    boolean used = false;
    for (String ch : layerChoice) used |= (int) v(ch) == L;
    if (!used) continue;
    PGraphics g = layers[L];
    g.beginDraw();
    g.blendMode(blend);
    if ((int) v("layerBrush") == L) {
      int n = (int) v("perFrame");
      for (int i = 0; i < n; i++) paintMark(g);
    }
    if ((int) v("layerSplat") == L) paintSplatters(g);
    if ((int) v("layerLines") == L) paintLines(g);
    if ((int) v("layerFrag") == L) paintFragments(g);
    g.blendMode(BLEND);
    g.endDraw();
  }
  paintScrapes();
}


// ---------------------------------------------------------------- showing it

// the picture the panel's "show" list has chosen
PImage currentView() {
  int s = (int) v("showWhat");
  if (s == 0) return canvas != null ? canvas : photo;
  if (s == 1) return photo;
  if (s == 2) return normalImg;
  if (s == 7) return massesImg != null ? massesImg : photo;
  return maps[s - 2];        // importance, curvature, depth, light
}

void draw2D() {
  background(20);
  image(currentView(), 0, 0, width, height);
  if (v("fieldOverlay") > 0.5) drawField(0, 0, width / (float) photo.width);
  if (v("showProtected") > 0.5 && v("abstractionOn") > 0.5) image(protectedPicture(), 0, 0, width, height);
  if (canvas == null) {
    fill(255, 200);
    textSize(14);
    textAlign(CENTER, BOTTOM);
    text("pick a picture and press RUN on the panel", width / 2, height - 12);
  }
}

void rebuildShape() {
  meshShape = (outputMode > 0 && mesh != null) ? mesh.toShape(currentView()) : null;
}

void drawMesh() {
  background(panel.colour("meshBg"));
  // the light stays put while the model turns, so it's set before turning. With it off the
  // model shows its picture's colours exactly, with no shading
  if (v("light") > 0.5) {
    ambientLight(90, 90, 90);
    directionalLight(200, 196, 190, sin(lightYaw) * cos(lightPitch), -sin(lightPitch), -cos(lightYaw) * cos(lightPitch));
  }
  pushMatrix();
  translate(width / 2, height / 2, 0);
  boolean sway = v("sway") > 0.5;
  if (sway) swayTime += 1 / frameRate;
  rotateY(yaw + (sway ? 0.5 * sin(swayTime * 0.8) : 0));
  rotateX(pitch);
  scale(min(width, height / mesh.aspect) * 0.75 * zoom);
  translate(0, 0, -mesh.depthMid);      // turn round the middle of the model, not its back
  shape(meshShape);
  popMatrix();
  noLights();
}


// the protected spots in see-through red (ABSTRACTION's "show protected parts"), made again only
// when the abstraction, the anchors or the picture change
PImage protectedImg;
String protectedKey = "";

PImage protectedPicture() {
  String key = faceName + " " + v("abstraction") + " " + v("anchors");
  if (!key.equals(protectedKey)) {
    protectedKey = key;
    protectedImg = createImage(photo.width, photo.height, ARGB);
    protectedImg.loadPixels();
    for (int y = 0; y < photo.height; y++) {
      for (int x = 0; x < photo.width; x++) {
        protectedImg.pixels[y * photo.width + x] = color(255, 30, 30, 170 * protection(x, y));
      }
    }
    protectedImg.updatePixels();
  }
  return protectedImg;
}


// ---------------------------------------------------------------- saving and loading

// the painting (photo size), the window too if it's a mesh, and every setting on the panel
void saveAll() {
  String dir = sketchPath("saved");
  new java.io.File(dir).mkdirs();
  String base = dir + "/" + faceName + "-" + nf(year(), 4) + nf(month(), 2) + nf(day(), 2) + "-" + nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2);
  if (canvas != null) {
    canvas.save(base + ".png");
    for (int i = 0; i < LAYERS; i++) layerPicture(i).save(base + "-layer" + (i + 1) + ".png");
  }
  if (outputMode > 0 && meshShape != null) save(base + "-view.png");
  JSONObject j = panel.settingsJSON();
  j.setInt("seed", runSeed);
  j.setFloat("textureSeed", textureSeed);
  j.setInt("marks", markCount);
  saveJSONObject(j, base + ".json");
  println("saved " + base + " (.png, each layer, .json)");
}

void settingsChosen(java.io.File f) {
  if (f == null) return;
  JSONObject j = loadJSONObject(f.getAbsolutePath());
  panel.applySettings(j, !isRunning);
  if (j.hasKey("textureSeed")) textureSeed = j.getFloat("textureSeed");
  println("settings from " + f.getName() + (isRunning ? " (SETUP left as it is while running)" : ""));
}


// ---------------------------------------------------------------- mouse and keys

void mouseDragged() {
  if (outputMode == 0 || meshShape == null) return;
  float dx = (mouseX - pmouseX) / (float) width, dy = (mouseY - pmouseY) / (float) height;
  if (mouseButton == RIGHT) {
    lightYaw += dx * 4;
    lightPitch = constrain(lightPitch + dy * 4, -1.4, 1.4);
  } else {
    yaw += dx * 4;
    pitch = constrain(pitch - dy * 4, -1.4, 1.4);
  }
}

void mouseWheel(MouseEvent e) {
  zoom = constrain(zoom * pow(1.1, -e.getCount()), 0.3, 6);
}

void keyPressed() {
  if (key == ' ') command("pause");
  else if (key == 'c') command("clear");
  else if (key == 's') command("save");
  else if (key == 'r') command("resetView");
  else if (key == 'l') panel.toggleLight();
}
