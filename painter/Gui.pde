// The control panel: a second window, built with controlP5.
//
// Three columns:
//   SETUP, RUN, VIEW              what to paint and where - SETUP is locked while a run is going
//   BRUSH, MOVEMENT, ABSTRACTION  the kind of mark, its size and shape, how it travels, and
//                                 where the face may be broken up
//   COLOUR, APPLY, MASSES         what paint it picks up and carries, how it goes onto the
//                                 canvas, and the large colour masses underneath
//   SPLATTER                      mark systems of their own (design doc Stage 5), painted
//                                 alongside the brushes
//
// Every control has a name (its first argument below), and the painter asks for values by that
// name with v("name") - sliders give their value, toggles 0 or 1, lists and radio buttons the
// number of the chosen item (counting from 0). A slider with a "by" row under it can also be
// turned up and down by a map: see modulated() in the Marks tab.
//
// The controls are laid out in rows, and a row (or one control in it) can be shown only when
// it means something - the knife's controls only when the knife is chosen, and so on: see
// onlyWhen() and shown(). Hidden rows take no space; the rows under them move up.
//
// The panel runs in its own window and thread. It never touches the canvas itself: buttons
// send a command() to the painter, which does it at the start of its next frame.
//
// To add a control: make it in setup() below with slider() / radio() / list() etc. and read it
// in the painter with v("its name"). It's saved, loaded and nudged with everything else.

import controlP5.*;

public class Panel extends PApplet {
  ControlP5 cp5;
  volatile boolean ready = false;
  HashMap<String, ControllerInterface> all = new HashMap<String, ControllerInterface>();
  ArrayList<String> setupNames = new ArrayList<String>();   // fixed while running
  ArrayList<String> liveNames = new ArrayList<String>();    // can change while running
  ArrayList<ScrollableList> lists = new ArrayList<ScrollableList>();
  ArrayList<ArrayList<Row>> columns = new ArrayList<ArrayList<Row>>();
  Row cur;                   // the row being built
  boolean live;              // whether the controls being built can change while running
  volatile boolean layoutWanted = true;
  boolean shownRunning = false;
  boolean listOpen = false;  // one of the dropdown lists is open
  Button runButton, pauseButton;
  Textlabel setupLabel;
  int colW = 340;            // width of a column
  int sections = 0;          // SETUP, RUN, VIEW ... each gets a block of colour behind it
  int[] blockColour = new int[0];
  float[][] block = new float[0][];   // each section's x, top, bottom as laid out, or null if hidden
  int dark = 0xFF232323;     // text on the coloured blocks (dark grey)

  // one row of controls, and when it's shown (see shown())
  class Row {
    String when = "";
    float h;
    int section;
    ArrayList<ControllerInterface> items = new ArrayList<ControllerInterface>();
    ArrayList<String> itemWhen = new ArrayList<String>();
    FloatList dx = new FloatList(), dy = new FloatList();
  }

  public void settings() {
    size(1400, 1000);
  }

  public void setup() {
    surface.setTitle("painter - controls");
    // just to the right of the output window. Window positions are in the screen's scaled
    // units (half the pixels on a screen at 200%), but the output window's size is in pixels
    double scale = java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment().getDefaultScreenDevice()
      .getDefaultConfiguration().getDefaultTransform().getScaleX();
    // ... but not off the right of the screen
    java.awt.Rectangle screen = java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment().getMaximumWindowBounds();
    surface.setLocation(min((int) ((40 + painter.this.width) / scale) + 30, screen.x + screen.width - width - 16), 40);
    textFont(createFont("Arial", 12, true));
    cp5 = new ControlP5(this);
    cp5.setFont(createFont("Arial", 12, true), 12);
    cp5.setColorForeground(color(70, 130, 200));
    cp5.setColorActive(color(110, 170, 240));
    cp5.setColorBackground(color(60));

    // ---------------------------------------------------- column 1: SETUP, RUN, VIEW
    column();
    live = false;
    setupLabel = header("SETUP  (fixed for a run)");
    row(20 * (faces.length + 1) + 12);
    ScrollableList src = cp5.addScrollableList("source").setSize(300, 20 * (faces.length + 1))
      .setBarHeight(20).setItemHeight(20).addItems(java.util.Arrays.asList(faces)).setType(ScrollableList.LIST);
    src.setCaptionLabel("source picture");
    src.setValue(0);
    register("source", src);
    put(src, 0, 0);
    radio("output", new String[] { "2D canvas", "mesh: just the person", "mesh: whole photo" }, 1, 0);
    colourWheel("ground", "canvas colour", color(222, 214, 200));
    // the masses (the Masses tab) are part of the setup: made again when one of these is let go,
    // and RUN waits for them
    row(22);
    label("masses: how the photo is cut up", 0);
    slider("massBlobs", "blobs", 200, 6000, 1500).setDecimalPrecision(0);
    slider("massRound", "roundness", 1, 40, 10).setDecimalPrecision(1);
    slider("massJoin", "join similar neighbours", 0, 40, 8).setDecimalPrecision(1);
    slider("massSmooth", "smooth edges", 0, 16, 3).setDecimalPrecision(1);
    Slider mp = slider("massPaints", "number of colours", 2, 32, 12).setDecimalPrecision(0);
    mp.setNumberOfTickMarks(31).snapToTickMarks(true).showTickMarks(false);

    live = true;
    header("RUN");
    row(32);
    runButton = button("runStop", "RUN", 0, 96);
    pauseButton = button("pauseRun", "PAUSE", 106, 96);
    button("clearCanvas", "CLEAR", 212, 96);
    row(32);
    button("saveNow", "SAVE", 0, 96);
    button("loadSettings", "LOAD SETTINGS", 106, 150);
    row(36);
    button("nudge", "NUDGE", 0, 96);
    sliderAt("nudgeAmount", "how far", 0, 1, 0.2, 106, 4, 110);

    header("VIEW");
    row(28);
    label("show", 0);
    list("showWhat", showNames, 0, 50, 140);
    row(26);
    toggle("fieldOverlay", "direction field over the picture", false, 0);
    onlyWhen("2D");
    colourWheel("meshBg", "mesh background", color(30));
    onlyWhen("mesh");
    row(30);
    toggle("sway", "sway", false, 0);
    button("resetView", "STRAIGHT ON", 160, 120);
    onlyWhen("mesh");
    row(26);
    toggle("light", "light on  (off shows the true colours)", true, 0);
    onlyWhen("mesh");

    // ---------------------------------------------------- column 2: BRUSH, MOVEMENT
    column();
    header("BRUSH");
    radio("brushType", new String[] { "bristle stroke", "palette knife" }, 2, 1);
    slider("perFrame", "marks per frame", 0, 400, 20).setDecimalPrecision(0);
    slider("markSize", "size (pixels, longest)", 4, 400, 110).setDecimalPrecision(0);
    modRow("markSize", 1, 0.8, true);
    slider("markWidth", "width (share of length)", 0.05, 1, 0.35);
    slider("ragged", "ragged edges", 0, 1, 0.5);
    slider("taper", "pointed end", 0, 1, 1);
    onlyWhen("stroke");
    slider("streaks", "streaks of a second colour", 0, 1, 0.4);
    onlyWhen("knifeFlat");
    slider("leaf", "leaf shapes", 0, 1, 0.35);
    onlyWhen("knife");
    slider("ridge", "ridge along the edge", 0, 1, 0.5);
    onlyWhen("knife");
    row(10);

    header("MOVEMENT");
    slider("follow", "follow the form", 0, 1, 0.6);
    modRow("follow", 0, 0.5, false);
    radio("around", new String[] { "around the form", "across it" }, 2, 0);
    Slider sm = slider("smoothing", "field smoothing", 0, 24, 4);
    sm.setNumberOfTickMarks(13).snapToTickMarks(true).showTickMarks(false);
    sm.setTriggerEvent(Slider.RELEASE);          // rebuilding the field takes a moment - only on letting go
    slider("curving", "bend along the form", 0, 1, 0.5);
    onlyWhen("stroke");
    row(20);
    label("start at", 0);
    radio("startAt", new String[] { "random", "weighted by map", "grid", "mouse (2D, hold button)" }, 2, 0);
    row(28);
    label("map", 12);
    list("startMap", mapNames, 1, 50, 120);
    toggle("startInv", "invert", false, 182);
    onlyWhen("weighted");
    slider("spread", "spread round the mouse", 0, 300, 60).setDecimalPrecision(0);
    onlyWhen("mouse");
    row(10);

    header("ABSTRACTION");
    row(26);
    toggle("abstractionOn", "on  (off: nothing is protected)", true, 0);
    slider("abstraction", "abstraction", 0, 1, 0.6);
    onlyWhen("abstraction");
    slider("anchors", "anchors (always kept)", 0, 1, 0.3);
    onlyWhen("abstraction");
    row(20);
    label("protected parts get", 0);
    onlyWhen("abstraction");
    radio("protectWith", new String[] { "no marks", "careful marks" }, 2, 1);
    onlyWhen("abstraction");
    slider("carefulSize", "careful mark size", 0.1, 1, 0.35);
    onlyWhen("careful");
    row(26);
    toggle("showProtected", "show protected parts (red)", false, 0);
    onlyWhen("2D abstraction");

    // ---------------------------------------------------- column 3: COLOUR, APPLY
    column();
    header("COLOUR");
    row(20);
    label("pick up from", 0);
    radio("pickup", new String[] { "photo", "canvas (wet)", "mix", "masses" }, 2, 0);
    slider("mix", "mix: share from the canvas", 0, 1, 0.5);
    onlyWhen("mix");
    row(20);
    label("carry", 0);
    radio("carry", new String[] { "one colour", "start to end", "two colours", "chunk (dipped)", "copy" }, 2, 1);
    slider("jitterH", "hue jitter", 0, 0.2, 0.02);
    slider("jitterS", "saturation jitter", 0, 0.5, 0.06);
    slider("jitterB", "brightness jitter", 0, 0.5, 0.08);
    colourWheel("accent", "accent colour", color(200, 60, 30));
    cur.h += 6;
    sliderAt("accentChance", "accent chance", 0, 0.2, 0, 120, 40, 90);

    header("APPLY");
    slider("opacity", "opacity", 0, 1, 0.9);
    modRow("opacity", 0, 0.5, false);
    slider("washes", "see-through washes", 0, 1, 0.15);
    row(28);
    label("blend", 0);
    list("blendType", blendNames, 0, 50, 140);
    row(6);

    // how the masses look and how they're used - how they're cut is in SETUP
    header("MASSES");
    row(20);
    label("start the canvas with  (at RUN and CLEAR)", 0);
    radio("startWith", new String[] { "plain", "masses", "photo" }, 3, 1);
    row(32);
    button("layMasses", "LAY ON NOW", 0, 110);
    sliderAt("layOpacity", "opacity", 0, 1, 0.5, 120, 5, 110);
    row(30);
    toggle("massTexture", "textured paint", false, 0);
    button("massSeed", "NEW TEXTURE", 170, 110);
    slider("massHue", "palette hue", -0.5, 0.5, 0);
    slider("massSat", "palette saturation", 0, 2, 1);
    slider("massBri", "palette brightness", 0, 2, 1);

    // ---------------------------------------------------- column 4: SPLATTER (Stage 5)
    column();
    header("SPLATTER");
    row(26);
    toggle("splatterOn", "splatter", false, 0);
    slider("splatRate", "clusters per frame", 0.05, 10, 0.5);
    onlyWhen("splatter");
    slider("splatDrops", "drops per cluster", 0, 200, 40).setDecimalPrecision(0);
    onlyWhen("splatter");
    slider("splatSize", "size (biggest splat)", 2, 120, 24).setDecimalPrecision(0);
    onlyWhen("splatter");
    slider("splatBig", "how many big drops", 0, 1, 0.3);
    onlyWhen("splatter");
    slider("splatSpread", "spread", 5, 400, 60).setDecimalPrecision(0);
    onlyWhen("splatter");
    slider("splatTrails", "flung trails", 0, 1, 0.3);
    onlyWhen("splatter");
    slider("splatOpacity", "opacity", 0, 1, 0.9);
    onlyWhen("splatter");
    row(20);
    label("colour", 0);
    onlyWhen("splatter");
    radio("splatColour", new String[] { "picked up", "accent colour" }, 2, 0);
    onlyWhen("splatter");
    slider("splatContrast", "contrast with the photo", 0, 1, 0.5);
    onlyWhen("splatter");
    slider("splatVary", "colour variation", 0, 0.5, 0.1);
    onlyWhen("splatter");

    // the lists open downwards over the controls under them, so draw them last - the higher
    // ones last of all, so an open list is never hidden behind the one below it
    for (int i = lists.size() - 1; i >= 0; i--) lists.get(i).bringToFront();
    for (ControllerInterface c : cp5.getAll()) {
      if (c instanceof RadioButton) {
        for (Toggle t : ((RadioButton) c).getItems()) t.getCaptionLabel().toUpperCase(false).setColor(dark);
      }
      if (c instanceof Controller) {
        Controller k = (Controller) c;
        k.getCaptionLabel().toUpperCase(false);
        k.getValueLabel().toUpperCase(false);
        // captions beside a control sit on the coloured block, so they're dark; buttons and
        // lists have theirs inside, on the control's own dark colour
        if (!(c instanceof Button) && !(c instanceof ScrollableList)) k.getCaptionLabel().setColor(dark);
      }
    }
    // a random light pastel for each section, the hues spread out so neighbours differ
    blockColour = new int[sections];
    block = new float[sections][];
    float hue = random(1);
    colorMode(HSB, 1);
    for (int i = 0; i < sections; i++) {
      blockColour[i] = color((hue + i * 0.382) % 1, random(0.10, 0.22), random(0.78, 0.86));
    }
    colorMode(RGB, 255);
    layout();
    ready = true;
  }

  public void draw() {
    background(38);
    if (layoutWanted) layout();
    // the coloured blocks behind the sections (the controls are drawn on top after this)
    noStroke();
    for (int i = 0; i < sections; i++) {
      if (block[i] == null) continue;
      fill(blockColour[i]);
      rect(block[i][0] - 8, block[i][1], colW - 12, block[i][2] - block[i][1], 8);
    }
    // while a list is open it covers the controls under it - lock them so a click on the list
    // can't move a slider underneath as well
    boolean open = false;
    for (ScrollableList l : lists) open |= l.isOpen();
    if (open != listOpen) {
      listOpen = open;
      for (ControllerInterface c : cp5.getAll()) {
        if (c instanceof Controller && !(c instanceof ScrollableList)) ((Controller) c).setLock(open);
      }
      if (!open) lockSetup(shownRunning);
    }
    if (isRunning != shownRunning) {
      shownRunning = isRunning;
      lockSetup(shownRunning);
    }
    runButton.setCaptionLabel(isRunning || runWaiting ? "STOP" : "RUN");
    pauseButton.setCaptionLabel(isPaused ? "CARRY ON" : "PAUSE");

    // the status line along the bottom
    fill(50);
    noStroke();
    rect(0, height - 28, width, 28);
    fill(220);
    textAlign(LEFT, CENTER);
    String state = isRunning ? (isPaused ? "paused" : "painting") : runWaiting ? "waiting for the masses" : "stopped";
    text(faceName + "   " + photo.width + " x " + photo.height + "      " + state + "      " + markCount + " marks      "
      + round(outputFps) + " fps      " + massStatus, 16, height - 14);
  }

  // controlP5 only counts a click on a radio button's or toggle's little square - make a click on
  // the words beside it count too
  public void mousePressed() {
    if (listOpen) return;
    for (ControllerInterface c : all.values()) {
      if (!c.isVisible()) continue;
      if (c instanceof RadioButton) {
        java.util.List<Toggle> items = ((RadioButton) c).getItems();
        for (int i = 0; i < items.size(); i++) {
          if (onLabel(items.get(i), ((RadioButton) c).getPosition())) {
            ((RadioButton) c).activate(i);
            layoutWanted = true;
            return;
          }
        }
      } else if (c instanceof Toggle && onLabel((Toggle) c, new float[] { 0, 0 })) {
        ((Toggle) c).toggle();
        return;
      }
    }
  }

  // whether the mouse is on the caption to the right of this toggle (and it isn't locked). A radio
  // button's toggles are placed relative to the radio button, at `origin`
  boolean onLabel(Toggle t, float[] origin) {
    if (t.isLock()) return false;
    float[] p = t.getPosition();
    float x = origin[0] + p[0], y = origin[1] + p[1];
    float x0 = x + t.getWidth(), x1 = x0 + 10 + textWidth(t.getCaptionLabel().getText());
    return mouseX >= x0 && mouseX <= x1 && mouseY >= y - 3 && mouseY <= y + t.getHeight() + 3;
  }

  public void controlEvent(ControlEvent e) {
    if (!ready) return;
    layoutWanted = true;       // whatever changed might show or hide something
    String n = e.getName();
    if (n.equals("runStop")) command(isRunning || runWaiting ? "stop" : "run");
    else if (n.equals("pauseRun")) command("pause");
    else if (n.equals("clearCanvas")) command("clear");
    else if (n.equals("saveNow")) command("save");
    else if (n.equals("loadSettings")) command("load");
    else if (n.equals("nudge")) nudgeAll();
    else if (n.equals("resetView")) command("resetView");
    else if (n.equals("source")) command("source");
    else if (n.equals("smoothing")) command("field");
    else if (n.equals("showWhat")) command("show");
    else if (n.equals("layMasses")) command("layMasses");
    else if (n.equals("massSeed")) command("massSeed");
  }


  // ---------------------------------------------------- showing and hiding

  // whether a row marked `when` means anything with the choices as they are now
  boolean shown(String when) {
    if (when.equals("")) return true;
    if (when.equals("stroke")) return value("brushType") == 0;
    if (when.equals("knife")) return value("brushType") == 1;
    if (when.equals("knifeFlat")) return value("brushType") == 1 && value("carry") < CHUNK;   // chunk and copy have no streaks
    if (when.equals("mix")) return value("pickup") == 2;
    if (when.equals("abstraction")) return value("abstractionOn") > 0.5;
    if (when.equals("careful")) return value("abstractionOn") > 0.5 && value("protectWith") == 1;
    if (when.equals("2D abstraction")) return value("output") == 0 && value("abstractionOn") > 0.5;
    if (when.equals("splatter")) return value("splatterOn") > 0.5;
    if (when.equals("weighted")) return value("startAt") == 1;
    if (when.equals("mouse")) return value("startAt") == 3;
    if (when.equals("2D")) return value("output") == 0;
    if (when.equals("mesh")) return value("output") > 0;
    if (when.startsWith("map ")) return value(when.substring(4) + "_by") > 0;   // a "by" row with a map chosen
    return true;
  }

  float value(String name) {
    return all.get(name).getValue();
  }

  // put every shown row in place, top to bottom in each column, and hide the rest
  void layout() {
    layoutWanted = false;
    float[][] b = new float[sections][];
    for (int i = 0; i < columns.size(); i++) {
      float x = 16 + i * colW, y = 8;
      for (Row r : columns.get(i)) {
        boolean rowShown = shown(r.when);
        if (rowShown && r.section >= 0) {
          // the block runs from just inside its header row to just above the next header
          if (b[r.section] == null) b[r.section] = new float[] { x, y + 4, 0 };
          b[r.section][2] = y + r.h - 4;
        }
        for (int k = 0; k < r.items.size(); k++) {
          ControllerInterface c = r.items.get(k);
          if (rowShown && shown(r.itemWhen.get(k))) {
            c.setPosition(x + r.dx.get(k), y + r.dy.get(k));
            c.show();
          } else {
            if (c instanceof ScrollableList) ((ScrollableList) c).close();
            c.hide();
          }
        }
        if (rowShown) y += r.h;
      }
    }
    block = b;
  }


  // ---------------------------------------------------- what the painter asks for

  // every control's value, by name (read once a frame by the painter)
  HashMap<String, Float> snapshot() {
    HashMap<String, Float> s = new HashMap<String, Float>();
    for (String n : all.keySet()) s.put(n, all.get(n).getValue());
    return s;
  }

  int colour(String name) {
    return ((ColorWheel) all.get(name)).getRGB();
  }

  JSONObject settingsJSON() {
    JSONObject j = new JSONObject();
    for (String n : all.keySet()) {
      ControllerInterface c = all.get(n);
      if (c instanceof ColorWheel) j.setInt(n, ((ColorWheel) c).getRGB());
      else j.setFloat(n, c.getValue());
    }
    j.setString("face", faceName);
    return j;
  }

  // put saved settings back on the panel; SETUP too if we're not running
  void applySettings(JSONObject j, boolean includeSetup) {
    for (String n : all.keySet()) {
      if (!j.hasKey(n) || n.equals("source")) continue;
      if (setupNames.contains(n) && !includeSetup) continue;
      ControllerInterface c = all.get(n);
      if (c instanceof ColorWheel) ((ColorWheel) c).setRGB(j.getInt(n));
      else if (c instanceof RadioButton) ((RadioButton) c).activate((int) j.getFloat(n));
      else c.setValue(j.getFloat(n));
    }
    if (includeSetup && j.hasKey("face")) {
      int i = java.util.Arrays.asList(faces).indexOf(j.getString("face"));
      if (i >= 0) all.get("source").setValue(i);
    }
    layoutWanted = true;
  }

  // move every slider that can change while running a random bit (not the speed, and not
  // "how far" itself) - a quick way to stumble on settings you wouldn't have tried
  void nudgeAll() {
    float amount = all.get("nudgeAmount").getValue();
    for (String n : liveNames) {
      ControllerInterface c = all.get(n);
      if (!(c instanceof Slider) || n.equals("nudgeAmount") || n.equals("perFrame")) continue;
      Slider s = (Slider) c;
      float range = s.getMax() - s.getMin();
      s.setValue(constrain(s.getValue() + random(-0.5, 0.5) * range * amount, s.getMin(), s.getMax()));
    }
  }

  // the l key in the output window
  void toggleLight() {
    Toggle t = (Toggle) all.get("light");
    t.setValue(t.getValue() > 0.5 ? 0 : 1);
  }

  void lockSetup(boolean on) {
    for (String n : setupNames) {
      ControllerInterface c = all.get(n);
      if (c instanceof RadioButton) {
        for (Toggle t : ((RadioButton) c).getItems()) t.setLock(on);
      } else if (c instanceof Controller) {
        ((Controller) c).setLock(on);
      }
    }
    setupLabel.setText(on ? "SETUP  (locked while running)" : "SETUP  (fixed for a run)");
  }


  // ---------------------------------------------------- building the panel
  // Each control is made at (0, 0) and put() in a row; layout() moves it to its place.

  void column() {
    columns.add(new ArrayList<Row>());
  }

  // start a new row, h high, in the newest column
  void row(float h) {
    cur = new Row();
    cur.h = h;
    cur.section = sections - 1;
    columns.get(columns.size() - 1).add(cur);
  }

  // only show the row just made when `when` is true (see shown())
  void onlyWhen(String when) {
    cur.when = when;
  }

  void put(ControllerInterface c, float dx, float dy) {
    put(c, dx, dy, "");
  }

  void put(ControllerInterface c, float dx, float dy, String when) {
    cur.items.add(c);
    cur.itemWhen.add(when);
    cur.dx.append(dx);
    cur.dy.append(dy);
  }

  void register(String name, ControllerInterface c) {
    all.put(name, c);
    (live ? liveNames : setupNames).add(name);
  }

  // a section's title - it starts a new section, with its own colour block
  Textlabel header(String text) {
    sections++;
    row(34);
    Textlabel t = cp5.addTextlabel("header " + text).setText(text).setColorValue(color(20));
    put(t, -4, 12);
    return t;
  }

  int labels = 0;
  void label(String text, float dx) {
    Textlabel t = cp5.addTextlabel("label " + labels++).setText(text).setColorValue(dark);
    put(t, dx - 4, 2);
  }

  // a slider on a row of its own
  Slider slider(String name, String caption, float lo, float hi, float value) {
    row(22);
    return sliderAt(name, caption, lo, hi, value, 0, 0, 170);
  }

  // a slider in the current row
  Slider sliderAt(String name, String caption, float lo, float hi, float value, float dx, float dy, int w) {
    Slider s = cp5.addSlider(name).setSize(w, 16).setRange(lo, hi).setValue(value);
    s.setCaptionLabel(caption);
    register(name, s);
    put(s, dx, dy);
    return s;
  }

  // the "by" row under a slider: which map turns it up and down, how much, and which way.
  // "amount" and "invert" only show once a map is chosen
  void modRow(String name, int by, float amount, boolean invert) {
    row(28);
    label("by", 12);
    list(name + "_by", mapNames, by, 34, 110);
    Slider a = cp5.addSlider(name + "_amt").setSize(50, 16).setRange(0, 1).setValue(amount);
    a.setCaptionLabel("amount");
    register(name + "_amt", a);
    put(a, 150, 0, "map " + name);
    toggle(name + "_inv", "invert", invert, 254);
    cur.itemWhen.set(cur.itemWhen.size() - 1, "map " + name);
  }

  void list(String name, String[] items, int chosen, float dx, float w) {
    ScrollableList l = cp5.addScrollableList(name).setSize((int) w, 20 * (items.length + 1))
      .setBarHeight(18).setItemHeight(18).addItems(java.util.Arrays.asList(items)).setType(ScrollableList.DROPDOWN);
    l.setValue(chosen);
    l.close();
    register(name, l);
    lists.add(l);
    put(l, dx, 0);
  }

  void toggle(String name, String caption, boolean on, float dx) {
    Toggle t = cp5.addToggle(name).setSize(16, 16).setValue(on);
    t.setCaptionLabel(caption);
    t.getCaptionLabel().align(ControlP5.RIGHT_OUTSIDE, ControlP5.CENTER).setPaddingX(6);
    register(name, t);
    put(t, dx, 0);
  }

  // radio buttons on a row of their own, perRow to a line
  void radio(String name, String[] items, int perRow, int chosen) {
    row(ceil(items.length / (float) perRow) * 22 + 6);
    RadioButton r = cp5.addRadioButton(name).setSize(16, 16).setItemsPerRow(perRow)
      .setSpacingColumn(colW / perRow - 30).setSpacingRow(6);
    for (int i = 0; i < items.length; i++) {
      r.addItem(name + " " + i, i);
      r.getItem(i).setCaptionLabel(items[i]);
    }
    r.activate(chosen);
    r.setNoneSelectedAllowed(false);
    register(name, r);
    put(r, 0, 0);
  }

  // a colour wheel on a row of its own
  void colourWheel(String name, String caption, int c) {
    row(128);
    ColorWheel w = cp5.addColorWheel(name, 0, 0, 100).setRGB(c);
    w.setCaptionLabel(caption);
    register(name, w);
    put(w, 0, 0);
  }

  Button button(String name, String caption, float dx, int w) {
    Button b = cp5.addButton(name).setSize(w, 26);
    b.setCaptionLabel(caption);
    put(b, dx, 0);
    return b;
  }
}
