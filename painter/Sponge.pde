// Sponge: a torn chunk of sponge, dipped in paint and dabbed - the panel's SPONGE box.
//
// The chunk is an irregular lump - a wobbly outline, with a straight side or two where it was cut
// ("torn edges") - full of pores ("pore size"; "how open" is how much of it is holes). It's
// dipped where MOVEMENT's "start at" says, taking up paint from COLOUR's "pick up from" there, and
// then stamped "stamps per dip" times, each stamp a little way on from the last ("distance between
// stamps") and turned to a new angle ("rotation"). Each stamp leaves some of its paint behind
// ("paint lost each stamp"), so the prints get fainter and more broken up - only the fullest
// pores still print - until it's dipped again.
//
// The sponge soaks up the picture where it's dipped - COLOUR's "pick up from": the photo, the wet
// canvas, a mix, or the masses - as much as "picks up" says, and carries it. The first stamp goes
// straight back down where it was dipped, unturned: a broken-up copy of what was there. The paint
// in the sponge smears a little more with every stamp ("smearing"), so the later ones, moved and
// turned, are blurrier and blurrier versions of it. (An accent dip is all the accent colour.)
//
// Each print is made as a small picture of the sponge's face - the paint it carries, how much of
// it prints in the alpha - and drawn turned. Pressing is never quite even, so every print differs
// a little. The same chunk is used dip after dip, unless "a new chunk each dip".
// Stamps respect ABSTRACTION: a stamp doesn't land where it's protected.

float[] spongeHolds;               // the chunk: how much paint each pixel of its face holds, 0 = outside
int spongeN = 0;                   // the chunk's picture is spongeN x spongeN
String spongeFor = "";             // the settings it was made with
float[] spongeR, spongeG, spongeB; // the paint it carries, a colour for each pixel of its face
float spongePaint = 0;             // paint left, 0 .. 1 - 0 means dip it again
int spongeStamps = 0;              // stamps since the last dip
float spongeX, spongeY;            // where the last stamp was
ArrayList<PImage> spongePrints = new ArrayList<PImage>();   // a picture for each stamp in a frame

void paintSponges(PGraphics g) {
  int n = countFor(t("rate"));
  for (int i = 0; i < n; i++) {
    // a picture of its own for each stamp this frame: one drawn into again before the frame's
    // drawing is done would change the stamps already made with it
    if (spongePrints.size() <= i) spongePrints.add(null);
    spongeStamp(g, i);
  }
}

void spongeStamp(PGraphics g, int k) {
  if (spongePaint < 0.03 || spongeStamps >= (int) t("stamps")) {
    // dip it
    float[] s = startPoint();
    if (s == null) return;
    spongeX = s[0];
    spongeY = s[1];
    makeSponge(t("fresh") > 0.5);
    soakUp(spongeX, spongeY);
    spongePaint = t("load") / 100;
    spongeStamps = 0;
  } else {
    smearSponge(t("smear"));
    // the next stamp, a little way on
    float a = random(TWO_PI), d = t("step") * t("size") * random(0.5, 1.2);
    spongeX = constrain(spongeX + cos(a) * d, 0, photo.width - 1);
    spongeY = constrain(spongeY + sin(a) * d, 0, photo.height - 1);
  }
  spongeStamps++;
  float paint = spongePaint;
  spongePaint *= 1 - t("loss") / 100;
  if (random(1) < protection(spongeX, spongeY)) return;

  PImage p = spongePrint(k, paint);
  float alpha = toolAlpha(spongeX, spongeY) * (0.55 + 0.45 * paint);
  g.pushMatrix();
  g.translate(spongeX, spongeY);
  if (spongeStamps > 1) g.rotate(radians(random(-1, 1) * t("turn")));    // the first goes back as it was
  g.tint(255, alpha);
  g.image(p, -spongeN / 2.0, -spongeN / 2.0);
  g.noTint();
  g.popMatrix();
  markCount++;
}

// the chunk: made again when its settings change, or every dip if `fresh`
void makeSponge(boolean fresh) {
  float size = t("size"), ragged = t("ragged"), pore = t("pores");
  String key = size + " " + ragged + " " + pore;
  if (!fresh && key.equals(spongeFor) && spongeHolds != null) return;
  spongeFor = key;
  int n = ceil(size) + 4;
  float c = n / 2.0, r = size / 2, seed = random(1000);
  float squash = random(1 - 0.35 * ragged, 1), turn = random(TWO_PI);
  // the cut sides: straight edges where it was torn off a bigger sponge
  int cuts = round(ragged * random(0.5, 3));
  float[] cutA = new float[cuts], cutD = new float[cuts];
  for (int i = 0; i < cuts; i++) {
    cutA[i] = random(TWO_PI);
    cutD[i] = r * random(0.45, 0.85);
  }
  float[] holds = new float[n * n];
  for (int j = 0; j < n; j++) {
    for (int i = 0; i < n; i++) {
      float dx = i - c, dy = j - c;
      // squashed and turned, so it's a lump, not a circle
      float lx = (dx * cos(turn) + dy * sin(turn)) / squash, ly = -dx * sin(turn) + dy * cos(turn);
      float ang = atan2(ly, lx), d = sqrt(lx * lx + ly * ly);
      float edge = r * (1 - 0.45 * ragged * noise(seed + cos(ang) * 1.6, seed + sin(ang) * 1.6));
      edge += (noise(seed + i / pore * 0.7, seed + j / pore * 0.7) - 0.5) * pore * 2.5;   // crumbly
      boolean in = d < edge;
      for (int q = 0; q < cuts && in; q++) in = dx * cos(cutA[q]) + dy * sin(cutA[q]) < cutD[q];
      if (!in) continue;
      // the pores: fine holes in bigger, looser ones
      float fine = noise(seed + 50 + i / pore, seed + j / pore);
      float coarse = noise(seed + 90 + i / (pore * 4), seed + j / (pore * 4));
      holds[i + j * n] = max(0.001, constrain((0.7 * fine + 0.3 * coarse - 0.28) / 0.44, 0, 1));
    }
  }
  spongeHolds = holds;
  spongeN = n;
}

// dipping it at (x, y): every pixel of its face takes the colour under it
void soakUp(float x, float y) {
  int n = spongeN;
  float c = n / 2.0;
  Paint p = new Paint();
  p.pickup = (int) t("pickup");
  p.mix = t("mix");
  if (random(1) < t("accentChance")) {
    p.accent = true;
    p.accentColour = accentNow;
  }
  spongeR = new float[n * n];
  spongeG = new float[n * n];
  spongeB = new float[n * n];
  for (int i = 0; i < n * n; i++) {
    if (spongeHolds[i] <= 0) continue;
    color col = p.pickRaw(constrain(x + i % n - c, 0, photo.width - 1), constrain(y + i / n - c, 0, photo.height - 1));
    spongeR[i] = col >> 16 & 255;
    spongeG[i] = col >> 8 & 255;
    spongeB[i] = col & 255;
  }
}

// the paint in it smearing between stamps: a blur, kept to the sponge's face
void smearSponge(float r) {
  int rad = round(r);
  if (rad < 1 || spongeR == null) return;
  int n = spongeN;
  float[] in = new float[n * n];
  for (int i = 0; i < n * n; i++) in[i] = spongeHolds[i] > 0 ? 1 : 0;
  float[] w = in.clone(), r0 = spongeR.clone(), g0 = spongeG.clone(), b0 = spongeB.clone();
  for (int pass = 0; pass < 2; pass++) {
    boolean across = pass == 0;
    boxBlur(w, n, n, rad, across);
    boxBlur(r0, n, n, rad, across);
    boxBlur(g0, n, n, rad, across);
    boxBlur(b0, n, n, rad, across);
  }
  for (int i = 0; i < n * n; i++) {
    if (in[i] == 0 || w[i] <= 0) continue;
    spongeR[i] = r0[i] / w[i];
    spongeG[i] = g0[i] / w[i];
    spongeB[i] = b0[i] / w[i];
  }
}

// stamp k's picture: the pores that still have enough paint print, the fuller the sponge the
// more of them - with the press a little uneven every time
PImage spongePrint(int k, float paint) {
  int n = spongeN;
  PImage p = spongePrints.get(k);
  if (p == null || p.width != n) {
    p = createImage(n, n, ARGB);
    spongePrints.set(k, p);
  }
  float cover = paint * (1 - 0.65 * t("open"));
  float level = 1 - cover, seed = random(1000);
  p.loadPixels();
  for (int i = 0; i < n * n; i++) {
    float h = spongeHolds[i];
    if (h <= 0) {
      p.pixels[i] = 0x00FFFFFF;
      continue;
    }
    float press = (noise(seed + (i % n) * 0.06, seed + (i / n) * 0.06) - 0.5) * 0.35 + random(-0.08, 0.08);
    float a = smoothstep(level - 0.07, level + 0.07, h + press);
    p.pixels[i] = (int) (a * 255) << 24 | (int) spongeR[i] << 16 | (int) spongeG[i] << 8 | (int) spongeB[i];
  }
  p.updatePixels();
  return p;
}
