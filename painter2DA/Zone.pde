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
//
// "expand": the levels left in the zone (each pixel's grey, to the nearest level) spread out so the
// darkest of them is 1 and the lightest 24, the ones between where they fall in proportion - gaps and
// all. Ten levels left, 5 to 15: 5 becomes 1, 15 becomes 24, 6 about 3, and so on. (Just one level
// left: it stays as it was.) Then the zone shows in its expanded greys, and COLOUR's carry "expand"
// (brush, knife, splatter) paints in them: chunk, picked up from a copy of the picture whose
// brightness, level by level of the zone, is moved so its average is the expanded level's (level E:
// E / 24) - its ups and downs within the level kept. Outside the zone the picture is as it was.
// Its carry "expTwo" is two colours, each one's brightness the expanded level's where it's picked up.

final int ZONE_LEVELS = 24;
final int ZONE_LIGHTEST = 200;     // the grey the lightest level shows as (white is "not in the zone")
String[] zoneMapNames = { "importance", "curvature", "depth", "light" };   // (mapNames 1 .. 4)
byte[][] zoneLevel = new byte[zoneMapNames.length][];   // each map's level at each photo pixel
String zoneLevelsFor = "";
boolean[] zoneOn;            // whether each photo pixel is in the zone
byte[] zoneGrey;             // each photo pixel's level in the zone (0 .. 23, the nearest), -1 if not in it
int[] zoneExpanded;          // with expand on: each level's expanded level (1 .. 24); null: not expanded
PImage expandedImg;          // carry expChunk's picture, and what it was made from
String expandedFor = "";
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
  boolean expand = v("zoneExpand") > 0.5;
  String key = faceName + " " + photo.width + " " + a + " " + aLo + "-" + aHi + " " + nf(aA, 0, 3) + " " + b + " " + bLo + "-" + bHi + " " + nf(bA, 0, 3)
    + (expand ? " expanded" : "");
  if (key.equals(zoneFor)) return true;
  byte[] la = zoneLevels(a), lb = zoneLevels(b);
  int n = photo.width * photo.height, count = 0;
  zoneOn = new boolean[n];
  zoneGrey = new byte[n];
  boolean[] left = new boolean[ZONE_LEVELS];
  for (int i = 0; i < n; i++) {
    int da = la[i], db = lb[i];
    float a1 = da >= aLo && da <= aHi ? aA : 0, a2 = db >= bLo && db <= bHi ? bA : 0;
    float al = a2 + a1 * (1 - a2);
    zoneGrey[i] = -1;
    if (al <= 0) continue;                   // not in the zone
    // in it: the second map's level over the first's
    int lv = constrain(round((db * a2 + da * a1 * (1 - a2)) / al), 0, ZONE_LEVELS - 1);
    zoneGrey[i] = (byte) lv;
    left[lv] = true;
    zoneOn[i] = true;
    count++;
  }
  // expand: the lowest level left to 1, the highest to 24, the rest in proportion
  int lo = -1, hi = -1, kinds = 0;
  for (int lv = 0; lv < ZONE_LEVELS; lv++) {
    if (!left[lv]) continue;
    if (lo < 0) lo = lv;
    hi = lv;
    kinds++;
  }
  zoneExpanded = null;
  if (expand && kinds > 0) {
    zoneExpanded = new int[ZONE_LEVELS];
    for (int lv = 0; lv < ZONE_LEVELS; lv++) {
      zoneExpanded[lv] = hi > lo ? 1 + round((lv - lo) * (ZONE_LEVELS - 1) / (float) (hi - lo)) : lv + 1;
    }
  }
  // to see: the levels in greys (expanded ones 1 .. 24 as 0 .. 23), the lightest a light grey
  // (ZONE_LIGHTEST), and white where it isn't in the zone
  PImage img = createImage(photo.width, photo.height, ARGB);
  img.loadPixels();
  for (int i = 0; i < n; i++) {
    int lv = zoneGrey[i];
    if (lv < 0) {
      img.pixels[i] = 0xFFFFFFFF;
      continue;
    }
    if (zoneExpanded != null) lv = zoneExpanded[lv] - 1;
    int g = round(lv * ZONE_LIGHTEST / (float) (ZONE_LEVELS - 1));
    img.pixels[i] = 0xFF000000 | g << 16 | g << 8 | g;
  }
  img.updatePixels();
  zoneImage = img;
  zoneFor = key;
  zoneShare = count / (float) n;
  String levels = kinds == 0 ? "" : zoneExpanded != null && hi > lo ? ",  levels " + (lo + 1) + " .. " + (hi + 1) + " expanded to 1 .. 24"
    : ",  levels " + (lo + 1) + " .. " + (hi + 1);
  zoneStatus = "the zone:  " + nf(100 * zoneShare, 0, 1) + "% of the picture,  " + kinds + " levels left" + levels;
  expandedFor = "";
  return true;
}

// carry expTwo: colour c, picked up at (x, y), with the expanded level's brightness there (E / 24) -
// as it is outside the zone, or without an expanded one
color zoneBright(color c, float x, float y) {
  if (!zoneReady() || zoneExpanded == null) return c;
  int lv = zoneGrey[pixelIndex(constrain(x, 0, photo.width - 1), constrain(y, 0, photo.height - 1))];
  if (lv < 0) return c;
  float[] hsb = java.awt.Color.RGBtoHSB(c >> 16 & 255, c >> 8 & 255, c & 255, null);
  return (c & 0xFF000000) | (java.awt.Color.HSBtoRGB(hsb[0], hsb[1], zoneExpanded[lv] / (float) ZONE_LEVELS) & 0xFFFFFF);
}

// carry expChunk: a copy of `tex` (the picture paint is picked up from) with, in the zone, each level's
// brightness moved so its average is the expanded level's (E / 24) - each pixel's difference from that
// average kept. Without an expanded zone, tex as it is (so it's chunk). Made again when the zone or the
// picture changes - and every frame for the wet canvas, which does
PImage expandedTex(PImage tex, boolean wet) {
  if (!zoneReady() || zoneExpanded == null) return tex;
  String key = zoneFor + " " + System.identityHashCode(tex) + " " + tex.width + "x" + tex.height + (wet ? " " + frameCount : "");
  if (key.equals(expandedFor) && expandedImg != null) return expandedImg;
  int w = tex.width, h = tex.height, pw = photo.width, ph = photo.height;
  tex.loadPixels();
  int[] lvAt = new int[w * h];
  float[] bright = new float[w * h], sum = new float[ZONE_LEVELS];
  int[] count = new int[ZONE_LEVELS];
  float[] hsb = new float[3];
  for (int y = 0; y < h; y++) {
    int py = min(ph - 1, y * ph / h);
    for (int x = 0; x < w; x++) {
      int i = x + y * w, lv = zoneGrey[min(pw - 1, x * pw / w) + py * pw];
      lvAt[i] = lv;
      if (lv < 0) continue;
      int c = tex.pixels[i];
      java.awt.Color.RGBtoHSB(c >> 16 & 255, c >> 8 & 255, c & 255, hsb);
      bright[i] = hsb[2];
      sum[lv] += hsb[2];
      count[lv]++;
    }
  }
  if (expandedImg == null || expandedImg.width != w || expandedImg.height != h) expandedImg = createImage(w, h, ARGB);
  expandedImg.loadPixels();
  for (int i = 0; i < w * h; i++) {
    int c = tex.pixels[i], lv = lvAt[i];
    if (lv < 0) {
      expandedImg.pixels[i] = c;
      continue;
    }
    java.awt.Color.RGBtoHSB(c >> 16 & 255, c >> 8 & 255, c & 255, hsb);
    float b = constrain(bright[i] - sum[lv] / count[lv] + zoneExpanded[lv] / (float) ZONE_LEVELS, 0, 1);
    expandedImg.pixels[i] = (c & 0xFF000000) | (java.awt.Color.HSBtoRGB(hsb[0], hsb[1], b) & 0xFFFFFF);
  }
  expandedImg.updatePixels();
  expandedFor = key;
  return expandedImg;
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
