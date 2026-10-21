// faceRelief
// Shows the 3D models the map maker makes (mesh_face.obj and mesh_full.obj in
// ../mapmaker/maps/<photo>/) so they can be turned round and looked at with different things
// painted on them - including a painting saved from strokeField, which is a first look at the
// design doc's Version 3 (marks that stay on the object as it turns).
//
// The model is the depth map pushed out towards you: a grid of points over the photo, each moved
// forward by how near that spot is. It's a relief - like a carving coming out of a wall - not a
// whole head; there's nothing round the back.
//
// Keys and mouse:
//   drag              turn the model
//   right-drag        move the light
//   wheel             zoom
//   1 2 3 ...         pick a face (every folder in mapmaker/maps that has a model)
//   m                 just the person / the whole photo as a relief plate
//   t                 what's painted on: photo / clay / normal / curvature / parts / painting / blobs
//   space             sway gently from side to side, on / off
//   r                 straight on again
//   s                 save a picture (faceRelief-####.png in the sketch folder)
//
// The painting is the newest strokeField-<photo>-####.png in the strokeField folder - press s
// in strokeField to make one.
//
// "blobs" cuts the photo into blobs of a single colour exactly as blobsCompare does (see the Blobs
// tab), with its sliders down the right: how many blobs, joining neighbours, smoothing the edges
// and how many paints. While blobs are showing:
//   v                 blobs (each its own colour) / flat paints (the limited palette)
//   o                 outlines on / off
// Everything is solid colour - blobsCompare's "paints with texture" look is left out here.

// ---- settings ----
float ui = 2;                 // size of the text (1 = small)
String mapsFolder = "../mapmaker/maps";
String paintingsFolder = "../strokeField";
color clay = color(205, 198, 188);

// ---- state ----
String[] faces;
int current = 0;
boolean wholePlate = false;   // false = mesh_face.obj, true = mesh_full.obj
Mesh mesh;
PShape textured, plain;       // the model with a picture on it, and in plain clay
String[] textureNames = { "photo", "clay", "normal", "curvature", "parts", "painting", "blobs" };
final int BLOBS = 6;
PImage[] textures;
int textureMode = 0;
String paintingName = null;   // which strokeField painting was found, if any
float yaw = 0, pitch = 0, zoom = 1;
float lightYaw = -0.6, lightPitch = -0.5;
boolean sway = false;
float swayTime = 0;
int loadMs;


void setup() {
  size(3200, 2000, P3D);
  // Processing can't see the screen size here, so it puts the window off the top left - put it
  // near the top left instead
  surface.setLocation(40, 80);
  surface.setTitle("faceRelief");

  viewMode = 1;       // flat paints: solid colour, no texture (the Paints tab starts on textured)

  faces = findFaces();
  if (faces.length == 0) {
    println("no models in " + mapsPath() + " - run the map maker (or mesh.py) first");
    exit();
    return;
  }
  loadFace(0);
}

void draw() {
  background(30);

  // the light stays put while the model turns, so it's set before turning
  ambientLight(90, 90, 90);
  directionalLight(200, 196, 190, sin(lightYaw) * cos(lightPitch), -sin(lightPitch), -cos(lightYaw) * cos(lightPitch));

  pushMatrix();
  translate(width / 2, height / 2, 0);
  if (sway) swayTime += 1 / frameRate;
  rotateY(yaw + (sway ? 0.5 * sin(swayTime * 0.8) : 0));
  rotateX(pitch);
  float s = min(width, height / mesh.aspect) * 0.75 * zoom;
  scale(s);
  translate(0, 0, -mesh.depthMid);      // turn round the middle of the model, not its back
  shape(textureMode == 1 ? plain : textured);
  popMatrix();

  // the text, flat on the screen
  hint(DISABLE_DEPTH_TEST);
  noLights();
  camera();
  fill(255, 200);
  textSize(16 * ui);
  textAlign(CENTER, BASELINE);
  String showing = textureNames[textureMode];
  if (textureMode == BLOBS) {
    showing = regionsLeft + " blobs,  " + viewNames[viewMode] + (viewMode > 0 ? " (" + paintCount + " paints)" : "");
    drawBlobPanel();
  }
  if (textureMode == 5) showing = paintingName == null ? "painting (none saved yet - showing the photo)" : "painting: " + paintingName;
  text(faces[current] + "     " + (wholePlate ? "whole photo" : "just the person") + "     " + showing, width / 2, 50 * ui);

  String[][] controls = {
    { "drag", "turn" },
    { "right-drag", "move the light" },
    { "wheel", "zoom" },
    { "1 - " + faces.length, "pick a face" },
    { "m", "person / whole photo" },
    { "t", "change what's painted on" },
    { "space", "sway" },
    { "r", "straight on" },
    { "s", "save a picture" },
  };
  drawControls(controls, 30 * ui, height - 160 * ui);

  fill(255, 130);
  textSize(13 * ui);
  textAlign(LEFT, BASELINE);
  text(mesh.points + " points     " + mesh.triangles + " triangles     loaded in " + loadMs + " ms     "
    + round(frameRate) + " fps", 16 * ui, height - 12 * ui);
  hint(ENABLE_DEPTH_TEST);
}

// a list of key / what-it-does pairs in columns
void drawControls(String[][] rows, float x, float y) {
  int columns = 3;
  int perColumn = ceil(rows.length / (float) columns);
  float lineH = 24 * ui, colW = 300 * ui;
  textSize(13 * ui);
  for (int i = 0; i < rows.length; i++) {
    float cx = x + (i / perColumn) * colW;
    float cy = y + (i % perColumn) * lineH;
    textAlign(RIGHT, TOP);
    fill(120, 180, 240);
    text(rows[i][0], cx + 90 * ui, cy);
    textAlign(LEFT, TOP);
    fill(255, 210);
    text(rows[i][1], cx + 104 * ui, cy);
  }
}


// ---------------------------------------------------------------- loading

String fullPath(String relative) {
  try {
    return new java.io.File(sketchPath(relative)).getCanonicalPath();
  } catch (java.io.IOException e) {
    return sketchPath(relative);
  }
}

String mapsPath() {
  return fullPath(mapsFolder);
}

String[] findFaces() {
  ArrayList<String> found = new ArrayList<String>();
  java.io.File[] dirs = new java.io.File(mapsPath()).listFiles();
  if (dirs != null) {
    for (java.io.File d : dirs) {
      if (d.isDirectory() && new java.io.File(d, "mesh_face.obj").exists()) found.add(d.getName());
    }
  }
  java.util.Collections.sort(found);
  return found.toArray(new String[0]);
}

void loadFace(int i) {
  int t0 = millis();
  current = i;
  String dir = mapsPath() + "/" + faces[i] + "/";
  mesh = new Mesh(dir + (wholePlate ? "mesh_full.obj" : "mesh_face.obj"));

  PImage photo = loadImage(dir + "photo.png");
  textures = new PImage[textureNames.length];
  textures[0] = photo;
  textures[1] = photo;                                  // not used - clay has no picture
  textures[2] = loadOr(dir + "normal.png", photo);
  textures[3] = loadOr(dir + "curvature.png", photo);
  textures[4] = loadOr(dir + "parts_preview.png", photo);
  paintingName = newestPainting(faces[i]);
  textures[5] = paintingName == null ? photo : loadImage(fullPath(paintingsFolder) + "/" + paintingName);
  textures[6] = photo;                                  // not used - blobs come from blobTexture
  blobsStale = true;
  if (textureMode == BLOBS) makeBlobs(photo);

  textured = mesh.toShape(currentTexture());
  plain = mesh.toShape(null);
  loadMs = millis() - t0;
  println(faces[i] + ": " + mesh.points + " points, " + mesh.triangles + " triangles in " + loadMs + " ms");
}

// the picture for the current texture mode
PImage currentTexture() {
  if (textureMode == 1) return textures[0];           // clay has no picture
  if (textureMode == BLOBS) return blobTexture;
  return textures[textureMode];
}

PImage loadOr(String path, PImage fallback) {
  return new java.io.File(path).exists() ? loadImage(path) : fallback;
}

// the newest strokeField-<face>-####.png, or null
String newestPainting(String face) {
  java.io.File[] files = new java.io.File(fullPath(paintingsFolder)).listFiles();
  String best = null;
  long bestTime = 0;
  if (files == null) return null;
  for (java.io.File f : files) {
    String n = f.getName();
    if (n.startsWith("strokeField-" + face + "-") && n.endsWith(".png") && f.lastModified() > bestTime) {
      best = n;
      bestTime = f.lastModified();
    }
  }
  return best;
}


// ---------------------------------------------------------------- mouse and keys

void mousePressed() {
  if (textureMode == BLOBS) blobPanelPressed();
}

void mouseReleased() {
  if (blobDragging >= 0) blobSliderReleased();
}

void mouseDragged() {
  if (blobDragging >= 0) {
    blobSlideTo(mouseX);
    return;
  }
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
  if (key >= '1' && key <= '9' && key - '1' < faces.length) loadFace(key - '1');
  else if (key == 'm') { wholePlate = !wholePlate; loadFace(current); }
  else if (key == 't') {
    textureMode = (textureMode + 1) % textureNames.length;
    if (textureMode == BLOBS) makeBlobs(textures[0]);
    if (textureMode != 1) textured.setTexture(currentTexture());
  }
  else if (textureMode == BLOBS && key == 'v') { viewMode = viewMode == 0 ? 1 : 0; paintPicture(); updateBlobTexture(); }
  else if (textureMode == BLOBS && key == 'o') { outlines = !outlines; blobbed = fillBlobs(original, smoothed, outlines); updateBlobTexture(); }
  else if (key == ' ') sway = !sway;
  else if (key == 'r') { yaw = 0; pitch = 0; zoom = 1; swayTime = 0; }
  else if (key == 's') {
    String name = "faceRelief-" + nf(frameCount, 4) + ".png";
    save(sketchPath(name));
    println("saved " + name);
  }
}
