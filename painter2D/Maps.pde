// One picture's maps from the map maker (../maps/<photo>/), and reading them - and making them
// for a photo of your own.
//
// Every map is the photo's size, so (x, y) is the same spot in all of them. mapAt() gives any of
// them as 0 .. 1 - the panel's "by" lists use these to turn amounts up and down from place to place.
//
// SETUP 1's last item, "open a picture ...", asks for a photo. If it has maps already (a folder of
// the same name), it's loaded; if not, the map maker (../mapmaker) is run on it in the background
// - a few seconds, or a few minutes the very first time, when it downloads its models - with what
// it's doing on the panel's status line, and the picture is loaded once its maps are made.

// where the map folders are, from this sketch - the map maker is told to put new ones there too
String mapsFolder = "../maps";
String mapmakerFolder = "../mapmaker";
String defaultFace = "leoTest";    // the picture loaded at the start (first in SETUP 1's list)
int mapSize = 1536;                // the map maker makes a new picture this big (its longest side)
volatile String mapStatus = "";    // what the map maker is doing, for the status line
volatile boolean mapMaking = false;
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
  // the default picture goes first, so it's the one loaded at the start
  if (found.remove(defaultFace)) found.add(0, defaultFace);
  return found.toArray(new String[0]);
}

boolean hasMaps(String name) {
  java.io.File d = new java.io.File(mapsPath(), name);
  return new java.io.File(d, "normal.png").exists() && new java.io.File(d, "photo.png").exists();
}

// "open a picture ...": choose a photo
void openPicture() {
  if (mapMaking) return;
  selectInput("Choose a photo", "pictureChosen", new java.io.File(sketchPath("..") + "/x.jpg"));
}

// (on selectInput's own thread) a photo was chosen: load it, or make its maps first
void pictureChosen(java.io.File f) {
  if (f == null) return;
  String name = f.getName();
  if (name.lastIndexOf('.') > 0) name = name.substring(0, name.lastIndexOf('.'));
  if (hasMaps(name)) command("picture " + name);
  else makeMaps(f, name);
}

// the map maker on a photo, in a thread of its own; when it's done, the picture is loaded
void makeMaps(final java.io.File photoFile, final String name) {
  mapMaking = true;
  mapStatus = "making maps for " + name + " ...";
  new Thread(new Runnable() {
    public void run() {
      String last = "";
      try {
        java.io.File mm = new java.io.File(sketchPath(mapmakerFolder)).getCanonicalFile();
        ProcessBuilder pb = new ProcessBuilder(new java.io.File(mm, ".venv/Scripts/python.exe").getPath(), "-u",
          new java.io.File(mm, "mapmaker.py").getPath(), photoFile.getPath(), "--out", mapsPath(), "--size", str(mapSize));
        pb.directory(mm);
        pb.redirectErrorStream(true);
        Process p = pb.start();
        java.io.BufferedReader r = new java.io.BufferedReader(new java.io.InputStreamReader(p.getInputStream()));
        String line;
        while ((line = r.readLine()) != null) {
          println("map maker: " + line);
          if (line.trim().length() > 0) {
            last = line.trim();
            mapStatus = "making maps for " + name + ":  " + last;
          }
        }
        if (p.waitFor() == 0 && hasMaps(name)) {
          mapStatus = "";
          command("picture " + name);
        } else {
          mapStatus = "the map maker failed on " + name + ":  " + last;
        }
      } catch (Exception e) {
        mapStatus = "couldn't run the map maker: " + e.getMessage();
      }
      mapMaking = false;
    }
  }).start();
}

// the output window's size for a picture w x h: windowScale times it, but no bigger than the
// screen (less room for the title bar and the taskbar). The screen's size is in its scaled units
// (half the pixels on a screen at 200%); the window's is in pixels
int[] windowFor(int w, int h) {
  java.awt.GraphicsEnvironment ge = java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment();
  double ds = ge.getDefaultScreenDevice().getDefaultConfiguration().getDefaultTransform().getScaleX();
  java.awt.Rectangle screen = ge.getMaximumWindowBounds();
  float s = min(windowScale, min((float) ((screen.width - 80) * ds) / w, (float) ((screen.height - 130) * ds) / h));
  return new int[] { round(w * s), round(h * s) };
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
  previewing = false;
  massesImg = null;          // the Masses tab makes this picture's masses next frame
  int[] s = windowFor(photo.width, photo.height);
  if (s[0] != width || s[1] != height) surface.setSize(s[0], s[1]);
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
