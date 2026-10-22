// One picture's maps from the map maker (../mapmaker/maps/<photo>/), and reading them.
//
// Every map is the photo's size, so (x, y) is the same spot in all of them. mapAt() gives any of
// them as 0 .. 1 - the panel's "by" lists use these to turn amounts up and down from place to place.

// where the map folders are, from this sketch. The map maker puts them in ../mapmaker/maps unless
// it's given --out; the closeTest photos' maps were made with --out ../closeTest/maps
String mapsFolder = "../closeTest/maps";
String[] mapNames = { "none", "importance", "curvature", "depth", "light", "photo lightness", "saturation" };
String[] mapFiles = { null, "importance.png", "curvature.png", "depth.png", "light_shaded.png", "light_photo.png", null };
PImage[] maps = new PImage[mapNames.length];
PImage photo, normalImg;

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

void loadFace(String face, int smoothing) {
  int t0 = millis();
  faceName = face;
  String dir = mapsPath() + "/" + face + "/";
  photo = loadImage(dir + "photo.png");
  photo.loadPixels();
  normalImg = loadImage(dir + "normal.png");
  for (int m = 1; m < maps.length; m++) {
    if (mapFiles[m] == null) continue;
    maps[m] = loadMap(dir + mapFiles[m], 128);
    maps[m].loadPixels();
  }
  buildField(normalImg, smoothing);
  canvas = null;
  meshShape = null;
  outputMode = 0;
  int w = round(photo.width * windowScale), h = round(photo.height * windowScale);
  if (w != width || h != height) surface.setSize(w, h);
  println(face + ": " + photo.width + " x " + photo.height + " loaded in " + (millis() - t0) + " ms");
}

// a map, or a plain grey picture if the map maker didn't make it
PImage loadMap(String path, int fallback) {
  if (new java.io.File(path).exists()) return loadImage(path);
  PImage p = createImage(photo.width, photo.height, RGB);
  java.util.Arrays.fill(p.pixels, color(fallback));
  p.updatePixels();
  return p;
}

int pixelIndex(float x, float y) {
  return constrain((int) x, 0, photo.width - 1) + constrain((int) y, 0, photo.height - 1) * photo.width;
}

// map number m (see mapNames) at (x, y), 0 .. 1
float mapAt(int m, float x, float y) {
  int i = pixelIndex(x, y);
  if (m == 6) {                     // saturation, worked out from the photo
    int c = photo.pixels[i];
    int r = c >> 16 & 255, g = c >> 8 & 255, b = c & 255;
    int hi = max(r, max(g, b)), lo = min(r, min(g, b));
    return hi == 0 ? 0 : (hi - lo) / (float) hi;
  }
  return (maps[m].pixels[i] >> 16 & 255) / 255.0;
}

color photoAt(float x, float y) {
  return photo.pixels[pixelIndex(x, y)];
}

// what's already painted at (x, y), as it was at the start of this frame
color canvasAt(float x, float y) {
  return canvasPix == null ? photoAt(x, y) : canvasPix[pixelIndex(x, y)];
}
