// strokeField
// The first PoorTrait painter test. It loads one folder of maps made by the map maker
// (../mapmaker/maps/<photo>/) and keeps painting strokes onto a canvas, a few dozen every frame.
//
// Each stroke picks up the photo's colour where it starts and where it ends, and travels along a
// direction field worked out from normal.png - so the strokes wrap around the cheeks, nose and
// jaw the way a painter who understands the form would (see the Field tab).
//
// The "follow the form" slider is the design doc's structure_following: at 100% every stroke
// follows the 3D shape, at 0% every stroke is a straight line in a random direction.
// The "detail" slider uses importance.png to make strokes smaller around the eyes, nose and mouth
// so those stay readable while the rest gets broad and loose.
//
// Moving a slider doesn't start again - new strokes just use the new settings, on top of the old
// ones, like changing brushes halfway through. Press c to start again.
//
// Keys:
//   1 2 3 ...  pick a face (every folder in mapmaker/maps, in name order)
//   v          what's shown on the left: photo / normal / light_shaded / curvature / importance / depth
//   f          the direction field drawn over the left picture, on / off
//   a          strokes go around the form / across it (downhill)
//   [ / ]      smoother / more detailed direction field
//   - / +      paint slower / faster
//   space      pause / carry on
//   c          clear the canvas and start again
//   s          save the painting (strokeField-<photo>-####.png in the sketch folder - faceRelief
//              can show it wrapped round the 3D model)

// ---- settings ----
float ui = 2;                // size of the text (1 = small)
String mapsFolder = "../mapmaker/maps";   // where the map maker puts its folders, from this sketch
color ground = color(222, 214, 200);      // the canvas colour before any paint
float alphaPaint = 225;      // how opaque each stroke is (0 - 255)
float colourJitter = 18;     // how much each stroke's colour wanders from the photo's

// ---- the sliders (0..1, turned into real values in the functions under them) ----
String[] sliderNames = { "follow the form", "stroke length", "stroke width", "detail" };
float[] sliderValue  = { 0.6, 0.35, 0.3, 0.6 };
float following() { return sliderValue[0]; }                    // 0 = random, 1 = follows the form
float lengthMax()  { return 4 + sliderValue[1] * 196; }         // in canvas pixels
float widthMax()   { return 1 + sliderValue[2] * 39; }
float detail()     { return sliderValue[3]; }                   // 0 = same size everywhere

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
int perFrame = 40;           // strokes painted every frame
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
  surface.setTitle("strokeField");

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
    for (int i = 0; i < perFrame; i++) paintStroke(canvas);
    canvas.endDraw();
    strokeCount += perFrame;
  }

  // two pictures side by side, as big as fits above the sliders
  top = 50 * ui;
  float sliderSpace = sliderNames.length * 56 * ui + 50 * ui;
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
  text(strokeCount + " strokes" + (paused ? "  (paused)" : ""), rightX + pw / 2, top - 12 * ui);

  // the sliders, under the painting
  sliderX = rightX;
  sliderW = pw;
  sliderY0 = top + ph + 34 * ui;
  sliderGap = 56 * ui;
  String[] labels = {
    "follow the form  " + round(following() * 100) + "%     (0 = random directions, 100 = always along the form)",
    "stroke length up to " + round(lengthMax()) + " pixels",
    "stroke width up to " + nf(widthMax(), 0, 1) + " pixels",
    "detail " + round(detail() * 100) + "%     (how much smaller strokes get around eyes, nose and mouth)",
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
    { "space", "pause" },
    { "c", "start again" },
    { "s", "save" },
  };
  drawControls(controls, leftX, sliderY0 - 10 * ui, pw);

  fill(255, 130);
  textSize(13 * ui);
  textAlign(LEFT, BASELINE);
  text(faces[current] + "     " + photo.width + " x " + photo.height + "     field smoothing " + fieldBlur
    + "     " + perFrame + " strokes a frame     " + round(frameRate) + " fps", 16 * ui, height - 12 * ui);
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
  else if (key == 's') {
    // named after the face, so faceRelief can find it and wrap it round that face's model
    String name = "strokeField-" + faces[current] + "-" + nf(frameCount, 4) + ".png";
    canvas.save(sketchPath(name));
    println("saved " + name);
  }
}
