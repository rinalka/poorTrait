// AUTOMATION (the box at the bottom of column 2): a tool's size or length moved up and down by
// itself while it paints.
//
// Each tool has its own: switched on, its size (or length, or width) follows a sine wave between
// "shortest" and "longest", at "speed" waves a second, in real time. It takes the place of the
// tool's own size slider while it's on - once a frame, just after the panel is read, the wave's
// value is written over that setting, so every tool picks it up without knowing about it.
// The wave only moves while the painting is going (paused, it holds still).

// what each tool's wave moves (in the TOOLS order), and the slider's limits for the panel
String[] AUTO_TARGET = { "size", "size", "size", "length", "length", "length", "width", "sizeRange", "length" };
float[][] AUTO_LIMITS = { { 4, 400 }, { 4, 400 }, { 2, 120 }, { 10, 800 }, { 50, 3000 }, { 10, 1000 }, { 0.3, 12 }, { 10, 300 }, { 10, 500 } };
float[][] AUTO_DEFAULT = { { 30, 160 }, { 30, 160 }, { 8, 40 }, { 60, 300 }, { 200, 1000 }, { 100, 400 }, { 1, 5 }, { 30, 120 }, { 60, 200 } };

// (sized by AUTO_TARGET, not TOOLS: this tab's variables are made before the Marks tab's)
float[] autoPhase = new float[AUTO_TARGET.length];   // how far along each tool's wave (in waves)
volatile float[] autoNow = new float[AUTO_TARGET.length];   // each wave's value now, for the panel to show
int autoLast = -1;

// after the panel's been read: each tool with its automation on has its size set from its wave
void applyAutomation() {
  int now = millis();
  float dt = autoLast < 0 ? 0 : min(0.5, (now - autoLast) / 1000.0);
  autoLast = now;
  boolean painting = isRunning && !isPaused;
  float[] shown = new float[AUTO_TARGET.length];
  for (int i = 0; i < TOOLS.length; i++) {
    String n = TOOLS[i];
    if (painting) autoPhase[i] = (autoPhase[i] + dt * v(n + "_autoSpeed")) % 1;
    // from the shortest (at the start) up to the longest and back
    float s = autoShape(autoPhase[i]);
    float value = lerp(v(n + "_autoMin"), v(n + "_autoMax"), s);
    shown[i] = value;
    if (v(n + "_autoOn") < 0.5) continue;
    if (AUTO_TARGET[i].equals("sizeRange")) {
      params.put(n + "_sizeRange_lo", value);
      params.put(n + "_sizeRange_hi", value);
    } else {
      params.put(n + "_" + AUTO_TARGET[i], value);
    }
  }
  autoNow = shown;
}

// the wave at `phase` (0 - 1): 0 at the start, 1 half way, 0 again at the end
float autoShape(float phase) {
  return 0.5 - 0.5 * cos(TWO_PI * phase);
}
