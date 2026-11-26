// Zone: a picture made from two of the maps - IN AREA's "Zone" (the Area tab), and MOVEMENT's
// "start at: in zone" (the Marks tab).
//
// Each of the two maps (importance, curvature, depth or light) is cut to 24 greys, levels 0 .. 23,
// from its darkest to its lightest - the depth map's from black, the background, to white, the
// nearest. Wherever the depth map is at 0 (the background), every map is at 0. Each map has a range
// of levels in the zone, and a transparency; the second lies on top of the first. A pixel is in the
// zone if its level on either map is in that map's range (and the map isn't wholly see-through) -
// level 0, black, too. While APPLY is open with the zone in it, the output window shows the zone
// instead of the painting: what's in it in its greys (the two maps' blended by their transparency,
// from black to a light grey - never white), and everything that isn't in it white.
//
// There's one zone, shared by every tool, set in APPLY: with IN AREA's Zone chosen, or "in zone" in
// MOVEMENT's START AT.

final int ZONE_LEVELS = 24;
final int ZONE_LIGHTEST = 200;     // the grey the lightest level shows as (white is "not in the zone")
String[] zoneMapNames = { "importance", "curvature", "depth", "light" };   // (mapNames 1 .. 4)
byte[][] zoneLevel = new byte[zoneMapNames.length][];   // each map's level at each photo pixel
String zoneLevelsFor = "";
boolean[] zoneOn;            // whether each photo pixel is in the zone
PImage zoneImage;            // the zone, to see
String zoneFor = "";
volatile String zoneStatus = "";
float zoneShare = 0;

// a map's value (0 .. 1) as one of the levels
int zoneLevelOf(float v) {
  return constrain(floor(v * ZONE_LEVELS), 0, ZONE_LEVELS - 1);
}

// map k's levels (k: 0 .. 3, zoneMapNames), for the picture now
byte[] zoneLevels(int k) {
  if (!zoneLevelsFor.equals(faceName + " " + photo.width + "x" + photo.height)) {
    for (int i = 0; i < zoneLevel.length; i++) zoneLevel[i] = null;
    zoneLevelsFor = faceName + " " + photo.width + "x" + photo.height;
  }
  int depth = 2;
  if (zoneLevel[depth] == null) zoneLevel[depth] = mapLevels(3, null);
  if (zoneLevel[k] == null) zoneLevel[k] = mapLevels(k + 1, zoneLevel[depth]);
  return zoneLevel[k];
}

// map m (mapNames) in levels, 0 wherever `background` is (if there is one)
byte[] mapLevels(int m, byte[] background) {
  int w = photo.width, h = photo.height;
  byte[] out = new byte[w * h];
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      int i = x + y * w;
      out[i] = (byte) (background != null && background[i] == 0 ? 0 : zoneLevelOf(mapAt(m, x + 0.5, y + 0.5)));
    }
  }
  return out;
}

// the zone, made again if its settings (or the picture) have changed. Returns whether there is one
boolean zoneReady() {
  if (photo == null) return false;
  int a = constrain((int) v("zoneMapA"), 0, 3), b = constrain((int) v("zoneMapB"), 0, 3);
  int aLo = round(v("zoneALevels_lo")), aHi = round(v("zoneALevels_hi"));
  int bLo = round(v("zoneBLevels_lo")), bHi = round(v("zoneBLevels_hi"));
  float aA = 1 - v("zoneAClear"), bA = 1 - v("zoneBClear");
  String key = faceName + " " + photo.width + " " + a + " " + aLo + "-" + aHi + " " + nf(aA, 0, 3) + " " + b + " " + bLo + "-" + bHi + " " + nf(bA, 0, 3);
  if (key.equals(zoneFor)) return true;
  byte[] la = zoneLevels(a), lb = zoneLevels(b);
  int n = photo.width * photo.height, count = 0;
  zoneOn = new boolean[n];
  PImage img = createImage(photo.width, photo.height, ARGB);
  img.loadPixels();
  for (int i = 0; i < n; i++) {
    int da = la[i], db = lb[i];
    float a1 = da >= aLo && da <= aHi ? aA : 0, a2 = db >= bLo && db <= bHi ? bA : 0;
    float al = a2 + a1 * (1 - a2);
    if (al <= 0) {
      img.pixels[i] = 0xFFFFFFFF;            // not in the zone: white
      continue;
    }
    // in it: the second map's grey over the first's, the lightest level a light grey (ZONE_LIGHTEST)
    float grey = (db * a2 + da * a1 * (1 - a2)) / al * ZONE_LIGHTEST / (ZONE_LEVELS - 1);
    int g = round(grey);
    img.pixels[i] = 0xFF000000 | g << 16 | g << 8 | g;
    zoneOn[i] = true;
    count++;
  }
  img.updatePixels();
  zoneImage = img;
  zoneFor = key;
  zoneShare = count / (float) n;
  zoneStatus = "the zone:  " + nf(100 * zoneShare, 0, 1) + "% of the picture";
  return true;
}

boolean inZone(float x, float y) {
  return zoneOn != null && zoneOn[pixelIndex(x, y)];
}

// START AT "in zone": a spot at random in the zone (null if none is found - an empty zone, or a tiny one)
float[] zoneStart() {
  if (!zoneReady() || zoneShare <= 0) return null;
  for (int k = 0; k < 200; k++) {
    float x = random(photo.width), y = random(photo.height);
    if (inZone(x, y)) return new float[] { x, y };
  }
  return null;
}

// whether the output window shows the zone: APPLY's open, with the zone in it
boolean zoneShowing() {
  return !panel.applyShut() && panel.zoneShown();
}

void drawZone() {
  if (!zoneReady()) return;
  image(zoneImage, 0, 0, width, height);
}
