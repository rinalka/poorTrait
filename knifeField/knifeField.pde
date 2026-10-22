// knifeField
// Palette-knife marks (design doc Stage 3). The same set-up as strokeField - one folder of maps
// from the map maker, a canvas that keeps being painted, a few marks every frame - but instead
// of brush strokes each mark is a palette-knife mark (see the Knife tab): a short wide blade of
// nearly flat colour with one straight ridged edge, one ragged edge, a second colour dragged
// through it in streaks, and a torn end where the knife skipped.
//
// The marks go the way the direction field says (see the Field tab, copied unchanged from
// strokeField), as much as the "follow the form" slider allows, and get smaller around the eyes,
// nose and mouth as much as the "detail" slider says.
//
// Moving a slider doesn't start again - new marks use the new settings on top of the old ones,
// like picking up a smaller knife halfway through. A good way to work: big marks first, then
// smaller ones, then smaller again. Press c to start again.
//
// Keys:
//   1 2 3 ...  pick a face (every folder in mapmaker/maps, in name order)
//   v          what's shown on the left: photo / normal / light_shaded / curvature / importance / depth
//   f          the direction field drawn over the left picture, on / off
//   a          marks go around the form / across it (downhill)
//   [ / ]      smoother / more detailed direction field
//   - / +      paint slower / faster
//   u          underpaint: cover the canvas with a very blurred photo (big soft colour masses)
//   space      pause / carry on
//   c          clear the canvas and start again
//   s          save the painting (knifeField-<photo>-####.png in the sketch folder - faceRelief
//              can show it wrapped round the 3D model)

// ---- settings ----
float ui = 2;                // size of the text (1 = small)
String mapsFolder = "../mapmaker/maps";   // where the map maker puts its folders, from this sketch
color ground = color(222, 214, 200);      // the canvas colour before any paint
float washChance = 0.15;     // how often a mark is a thin, see-through wash instead of solid paint
float leafChance = 0.35;     // how often a mark is leaf / shard shaped, pointed at both ends
float colourJitter = 14;     // how much each mark's colour wanders from the photo's

// ---- the sliders (0..1, turned into real values in the functions under them) ----
String[] sliderNames = { "follow the form", "knife size", "knife width", "detail", "ragged edges", "streaks" };
float[] sliderValue  = { 0.6, 0.4, 0.45, 0.6, 0.5, 0.4 };
float following()   { return sliderValue[0]; }                  // 0 = random, 1 = follows the form
float knifeLength() { return 8 + sliderValue[1] * 292; }        // longest mark, in canvas pixels
float knifeWidth()  { return 0.1 + sliderValue[2] * 0.9; }      // width as a share of the length
float detail()      { return sliderValue[3]; }                  // 0 = same size everywhere
float roughness()   { return sliderValue[4] * 1.5; }            // 0 = clean edges
float streakAmount(){ return sliderValue[5]; }                  // 0 = no second colour

// ---- state ----
String[] faces;              // folder names in mapsFolder
int current = 0;
PImage photo, normalImg, importanceImg;
PImage[] views;              // what can be shown on the left
String[] viewNames = { "photo", "normal", "light_shaded", "curvature", "importance", "depth" };
int viewMode = 0;
PGraphics canvas;            // the painting, at the photo's size
boolean showField = false;
boolean around = true;       // strokes go around the form (true) or across it
int fieldBlur = 4;           // how much the normals are smoothed before working out directions
int perFrame = 8;            // marks painted every frame
boolean paused = false;
int strokeCount = 0;

float panelScale, leftX, rightX, top;    // where the pictures are drawn (set in draw)
float sliderX, sliderW, sliderY0, sliderGap;
int dragging = -1;           // which slider is being dragged (-1 = none)


void setup() {
  size(3200, 2000, P2D);
  // Processing 4 doubles everything on a Windows screen scaled to 200% - the window and the
  // canvas too, so paintings would be painted and saved at twice the photo's size. Keep it 1:1
  pixelDensity(1);
  // Processing can't see the screen size here, so it puts the window off the top left - put it
  // near the top left instead
  surface.setLocation(40, 80);
  surface.setTitle("knifeField");

  faces = findFaces();
  if (faces.length == 0) {
    println("no map folders in " + mapsPath() + " - run the map maker on a photo first");
    exit();
    return;
  }
  loadFace(0);
}

void draw() {
  background(20);
  if (!paused) {
    canvas.beginDraw();
    for (int i = 0; i < perFrame; i++) paintKnife(canvas);
    canvas.endDraw();
    strokeCount += perFrame;
  }

  // two pictures side by side, as big as fits above the sliders
  top = 50 * ui;
  float sliderSpace = sliderNames.length * 48 * ui + 50 * ui;
  panelScale = min((width / 2 - 60 * ui) / photo.width, (height - top - sliderSpace) / photo.height);
  float pw = photo.width * panelScale, ph = photo.height * panelScale;
  leftX = width / 4 - pw / 2;
  rightX = 3 * width / 4 - pw / 2;
  image(views[viewMode], leftX, top, pw, ph);
  if (showField) drawField(leftX, top, panelScale);
  image(canvas, rightX, top, pw, ph);

  fill(255, 200);
  textSize(16 * ui);
  textAlign(CENTER, BASELINE);
  text(viewNames[viewMode] + (showField ? "  +  direction field" : ""), leftX + pw / 2, top - 12 * ui);
  text(strokeCount + " knife marks" + (paused ? "  (paused)" : ""), rightX + pw / 2, top - 12 * ui);

  // the sliders, under the painting
  sliderX = rightX;
  sliderW = pw;
  sliderY0 = top + ph + 34 * ui;
  sliderGap = 48 * ui;
  String[] labels = {
    "follow the form  " + round(following() * 100) + "%     (0 = random directions, 100 = always along the form)",
    "knife marks up to " + round(knifeLength()) + " pixels long",
    "knife width " + round(knifeWidth() * 100) + "% of its length",
    "detail " + round(detail() * 100) + "%     (how much smaller marks get around eyes, nose and mouth)",
    "ragged edges " + round(sliderValue[4] * 100) + "%",
    "streaks of a second colour " + round(streakAmount() * 100) + "%",
  };
  for (int i = 0; i < labels.length; i++) drawSlider(sliderY0 + i * sliderGap, sliderValue[i], labels[i]);

  // the controls, under the left picture
  String[][] controls = {
    { "1 - " + faces.length, "pick a face" },
    { "v", "left picture" },
    { "f", "direction field" },
    { "a", around ? "now: around the form" : "now: across the form" },
    { "[  ]", "smoother / finer field" },
    { "-  +", "slower / faster" },
    { "u", "underpaint" },
    { "space", "pause" },
    { "c", "start again" },
    { "s", "save" },
  };
  drawControls(controls, leftX, sliderY0 - 10 * ui, pw);

  fill(255, 130);
  textSize(13 * ui);
  textAlign(LEFT, BASELINE);
  text(faces[current] + "     " + photo.width + " x " + photo.height + "     field smoothing " + fieldBlur
    + "     " + perFrame + " marks a frame     " + round(frameRate) + " fps", 16 * ui, height - 12 * ui);
}

// a list of key / what-it-does pairs in columns
void drawControls(String[][] rows, float x, float y, float w) {
  int columns = 3;
  int perColumn = ceil(rows.length / (float) columns);
  float lineH = 24 * ui;
  textSize(13 * ui);
  for (int i = 0; i < rows.length; i++) {
    float cx = x + (i / perColumn) * w / columns;
    float cy = y + (i % perColumn) * lineH;
    textAlign(RIGHT, TOP);
    fill(120, 180, 240);
    text(rows[i][0], cx + 50 * ui, cy);
    textAlign(LEFT, TOP);
    fill(255, 210);
    text(rows[i][1], cx + 64 * ui, cy);
  }
}


// ---------------------------------------------------------------- loading

String mapsPath() {
  try {
    return new java.io.File(sketchPath(mapsFolder)).getCanonicalPath();
  } catch (java.io.IOException e) {
    return sketchPath(mapsFolder);
  }
}

// every folder in mapsFolder that has the maps we need
String[] findFaces() {
  ArrayList<String> found = new ArrayList<String>();
  java.io.File[] dirs = new java.io.File(mapsPath()).listFiles();
  if (dirs != null) {
    for (java.io.File d : dirs) {
      if (d.isDirectory() && new java.io.File(d, "normal.png").exists() && new java.io.File(d, "photo.png").exists()) {
        found.add(d.getName());
      }
    }
  }
  java.util.Collections.sort(found);
  return found.toArray(new String[0]);
}

void loadFace(int i) {
  current = i;
  String dir = mapsPath() + "/" + faces[i] + "/";
  photo = loadImage(dir + "photo.png");
  normalImg = loadImage(dir + "normal.png");
  importanceImg = loadMap(dir + "importance.png", 0);
  photo.loadPixels();
  importanceImg.loadPixels();
  views = new PImage[viewNames.length];
  views[0] = photo;
  views[1] = normalImg;
  for (int v = 2; v < viewNames.length; v++) views[v] = loadMap(dir + viewNames[v] + ".png", 128);
  views[4] = importanceImg;
  buildField(normalImg, fieldBlur);
  clearCanvas();
  println(faces[i] + ": " + photo.width + " x " + photo.height);
}

// a map, or a plain grey picture if the map maker didn't make it
PImage loadMap(String path, int fallback) {
  if (new java.io.File(path).exists()) return loadImage(path);
  PImage p = createImage(photo.width, photo.height, RGB);
  java.util.Arrays.fill(p.pixels, color(fallback));
  p.updatePixels();
  return p;
}

// big soft colour masses to paint into: the photo, blurred until only the broad colours are left
void underpaint() {
  PImage soft = photo.copy();
  soft.resize(photo.width / 8, 0);           // blurring a small copy is much quicker
  soft.filter(BLUR, 3);
  canvas.beginDraw();
  canvas.tint(255, 230);
  canvas.image(soft, 0, 0, photo.width, photo.height);
  canvas.noTint();
  canvas.endDraw();
}

void clearCanvas() {
  if (canvas == null || canvas.width != photo.width || canvas.height != photo.height) {
    canvas = createGraphics(photo.width, photo.height, P2D);
  }
  canvas.beginDraw();
  canvas.background(ground);
  canvas.endDraw();
  strokeCount = 0;
}


// ---------------------------------------------------------------- the sliders

// a slider: a line, a knob at position f (0..1) along it, and a label underneath
void drawSlider(float y, float f, String label) {
  stroke(255, 90);
  strokeWeight(2 * ui);
  line(sliderX, y, sliderX + sliderW, y);
  noStroke();
  fill(70, 130, 200);
  circle(sliderX + sliderW * f, y, 18 * ui);
  fill(255, 200);
  textSize(14 * ui);
  textAlign(CENTER, TOP);
  text(label, sliderX + sliderW / 2, y + 16 * ui);
}

boolean onSlider(float y) {
  return abs(mouseY - y) < 20 * ui && mouseX > sliderX - 20 * ui && mouseX < sliderX + sliderW + 20 * ui;
}

void mousePressed() {
  for (int i = 0; i < sliderNames.length; i++) {
    if (onSlider(sliderY0 + i * sliderGap)) dragging = i;
  }
  if (dragging >= 0) slideTo(mouseX);
}

void mouseDragged() {
  if (dragging >= 0) slideTo(mouseX);
}

void mouseReleased() {
  dragging = -1;
}

void slideTo(float mx) {
  sliderValue[dragging] = constrain((mx - sliderX) / sliderW, 0, 1);
}


// ---------------------------------------------------------------- keys

void keyPressed() {
  if (key >= '1' && key <= '9' && key - '1' < faces.length) loadFace(key - '1');
  else if (key == 'v') viewMode = (viewMode + 1) % viewNames.length;
  else if (key == 'f') showField = !showField;
  else if (key == 'a') around = !around;
  else if (key == '[') { fieldBlur = min(fieldBlur + 2, 24); buildField(normalImg, fieldBlur); }
  else if (key == ']') { fieldBlur = max(fieldBlur - 2, 0); buildField(normalImg, fieldBlur); }
  else if (key == '-') perFrame = max(1, perFrame / 2);
  else if (key == '+' || key == '=') perFrame = min(5000, perFrame * 2);
  else if (key == ' ') paused = !paused;
  else if (key == 'c') clearCanvas();
  else if (key == 'u') underpaint();
  else if (key == 's') {
    // named after the face, so faceRelief can find it and wrap it round that face's model
    String name = "knifeField-" + faces[current] + "-" + nf(frameCount, 4) + ".png";
    canvas.save(sketchPath(name));
    println("saved " + name);
  }
}
