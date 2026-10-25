// The control panel: a second window, built with controlP5.
//
// Four columns:
//   SETUP 1 - 5                   the source picture, the target (2D or a mesh), the masses, the
//                                 backdrop and what the canvas starts with, each a box whose
//                                 square turns from red to green once it's done - 1 - 3 are
//                                 locked while a run is going
//   the tools                     what does the drawing: brush, palette knife, splatter, lines,
//                                 fragments, pencil, scrape - one at a time, with its shape settings
//   MOVEMENT, COLOUR, APPLY       how the chosen tool moves, where its colour comes from, and
//                                 how solid it is
//   ABSTRACTION, LAYERS,          where the face may be broken up, the four layers, the
//   SHADOW BOX, IMPASTO           layers floating apart, lit from one side, and thick paint
//                                 catching the light
// and along the bottom, VIEW (the MAPS and LAYERS lists) and CAMERA under column 1, and RUN under
// column 2, level with VIEW.
//
// Every tool has its own MOVEMENT, COLOUR and APPLY settings, named with the tool in front
// ("knife_follow", "splat_opacity" ...). Only one tool is on at a time: switching one on (its
// box turns from red to green) switches the others off and chooses it (`editing`) - its box
// opens and columns 3 - 4 show its settings. With every tool off, they show the last one's under a
// grey cover. The painter reads them with t("follow") while that tool paints (the Marks tab).
//
// Every control has a name (its first argument below), and the painter asks for values by that
// name with v("name") - sliders give their value, toggles 0 or 1, lists and radio buttons the
// number of the chosen item (counting from 0). A slider with a "by" row under it can also be
// turned up and down by a map: see modulated() in the Marks tab.
//
// The controls are laid out in rows, and a row (or one control in it) can be shown only when
// it means something - the chosen tool's settings, the map row only for "weighted by map", and
// so on: see onlyWhen() and shown(). Hidden rows take no space; the rows under them move up.
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
  IntList colAt = new IntList();       // which column each one is laid out in, counting from 0
  IntList colBottom = new IntList();   // 1 for the ones along the bottom of the window
  IntList colLevel = new IntList();    // a bottom column whose top this one's is level with, or -1
  int topColumns = 0;
  Row cur;                   // the row being built
  boolean live;              // whether the controls being built can change while running
  volatile boolean layoutWanted = true;
  boolean shownRunning = false;
  boolean listOpen = false;  // one of the dropdown lists is open
  Button runButton, pauseButton, stepButton;
  Slider paceSlider;
  Row layerRow;                                   // VIEW's lists, with the layers' tick boxes
  int[] layerItem = new int[LAYERS];              // each layer's tick box in layerRow's items
  String shownOrder = "";
  Toggle canvasShown, backdropShown;            // VIEW's LAYERS: the canvas, and the backdrop (always on)
  Row[][] layerBands = new Row[LAYERS + 1][];   // LAYERS' first and last rows for each layer, then the canvas's
  int runGreen = 0xFF2E9E48, runGreenHover = 0xFF45B860, runRed = 0xFFCC3B2E, runRedHover = 0xFFE26A5E;
  int orange = 0xFFE08A1E, orangeHover = 0xFFF0A040;
  String[] startNames = { "plain", "masses", "photo" };
  // the setup boxes: their colour blocks, the line under each title, and whether each is done
  int sourceBox, targetBox, massBox, backdropBox, startBox;
  Textlabel boxTitle, massTitle, sourceText, targetText, massText;
  volatile boolean sourceDone, targetDone, massesDone, backdropDone, startDone;
  volatile boolean massesOpen = false;
  float showBefore, lightBefore;      // put back when the masses box closes
  int pressedIn = -1;                 // the setup box a click started in
  ScrollableList picked;              // a setup list an item was just picked from
  int doneGreen = 0xFF2E9E48, notDoneRed = 0xFFCC3B2E;   // a setup box's square
  String[] outputNames = { "2D canvas", "mesh: just the person", "mesh: whole photo" };
  int colW = 340;            // width of a column
  int sections = 0;          // SETUP, RUN, VIEW ... each gets a block of colour behind it
  int[] blockColour = new int[0];
  float[][] block = new float[0][];   // each section's x, top, bottom as laid out, or null if hidden
  int dark = 0xFF232323;     // text on the coloured blocks (dark grey)
  volatile String editing = "knife";   // the tool switched on in column 2, whose settings columns 3 - 4 show
  String shownEditing = "";
  int toolOff = 0xFFCC3B2E, toolOffHover = 0xFFE26A5E, toolOn = 0xFF2E9E48;   // a tool's on / off box
  int[] toolSection = new int[TOOLS.length];   // each tool box's colour block
  String curTool;            // the tool whose box is being built
  Textlabel moveHeader, colourHeader, applyHeader;

  // one row of controls, and when it's shown (see shown())
  class Row {
    String when = "";
    float h;
    float y = -1;            // where layout() put it, or -1 if it's hidden
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
    cp5.setAutoDraw(false);    // drawn in draw(), so the cover over columns 3 - 4 can go on top
    cp5.setFont(createFont("Arial", 12, true), 12);
    cp5.setColorForeground(color(70, 130, 200));
    cp5.setColorActive(color(110, 170, 240));
    cp5.setColorBackground(color(60));

    // ---------------------------------------------------- column 1: SETUP 1 - 5
    // The setup is five boxes, done in order: click one to choose. Each has a square before its
    // title, red until it's done and then green. 1 - 3 are locked while a run is going (all but the
    // masses' palette sliders)
    column();
    live = false;
    sourceBox = setupBox("SETUP 1   SOURCE");
    sourceText = boxText("source");
    setupList("source", faces);
    targetBox = setupBox("SETUP 2   TARGET");
    targetText = boxText("output");
    setupList("output", outputNames);
    colourWheel("ground", "canvas colour", color(222, 214, 200));
    onlyWhen("ground");
    // the masses (the Masses tab): clicking the box opens these and shows the masses; clicking
    // its title again closes them. They're made again when one of the sliders is let go, and RUN
    // waits for them
    massBox = setupBox("SETUP 3   MASSES");
    massTitle = boxTitle;
    massText = boxText("");
    massSlider("massBlobs", "blobs", 200, 6000, 1500).setDecimalPrecision(0);
    massSlider("massRound", "roundness", 1, 40, 10).setDecimalPrecision(1);
    massSlider("massJoin", "join similar neighbours", 0, 40, 8).setDecimalPrecision(1);
    massSlider("massSmooth", "smooth edges", 0, 16, 3).setDecimalPrecision(1);
    Slider mp = massSlider("massPaints", "number of colours", 2, 32, 12).setDecimalPrecision(0);
    mp.setNumberOfTickMarks(31).snapToTickMarks(true).showTickMarks(false);
    live = true;
    massSlider("massHue", "palette hue", -0.5, 0.5, 0);
    massSlider("massSat", "palette saturation", 0, 2, 1);
    massSlider("massBri", "palette brightness", 0, 2, 1);
    row(6);
    onlyWhen("massesOpen");
    // for later: laying the masses on during a run, and textured paint (never shown for now)
    row(32);
    button("layMasses", "LAY ON NOW", 0, 110);
    sliderAt("layOpacity", "opacity", 0, 1, 0.5, 120, 5, 110);
    onlyWhen("later");
    row(30);
    toggle("massTexture", "textured paint", false, 0);
    button("massSeed", "NEW TEXTURE", 170, 110);
    onlyWhen("later");
    // the backdrop, under the canvas (the Backdrop tab) - always open, done once it's clicked,
    // and it can change any time
    backdropBox = setupBox("SETUP 4   BACKDROP");
    boxText("").setText("what the canvas sits on");
    row(28);
    list("backdropKind", backdropNames, 0, 0, 150);
    slider("backdropAmount", "strength", 0, 1, 0.6);
    onlyWhen("backdropKind");
    slider("backdropThrough", "shows through the paint", 0, 1, 0.25);
    onlyWhen("backdropKind");
    row(2);
    // what the canvas starts with at RUN and CLEAR - always open, and done once a choice is
    // clicked. It can change during a run (it's used at the next CLEAR)
    startBox = setupBox("SETUP 5   START");
    boxText("").setText("start the canvas with  (at RUN and CLEAR)");
    radio("startWith", startNames, 3, 1);
    row(2);

    // ---------------------------------------------------- along the bottom: VIEW, CAMERA and RUN
    // VIEW is two lists side by side, always open: MAPS (a map in place of the painting) and
    // LAYERS (which parts of the painting show)
    int viewColumn = bottomColumn(0, -1);
    header("VIEW");
    row(20);
    label("MAPS", 0);
    label("LAYERS", 160);
    row(showNames.length * 22 + 8);
    RadioButton r = cp5.addRadioButton("showWhat").setSize(16, 16).setItemsPerRow(1).setSpacingRow(6);
    for (int i = 0; i < showNames.length; i++) {
      r.addItem("showWhat " + i, i);
      r.getItem(i).setCaptionLabel(i == 0 ? "none  (the painting)" : showNames[i]);
    }
    r.activate(0);
    r.setNoneSelectedAllowed(false);
    register("showWhat", r);
    put(r, 0, 4);
    // the stack, top first, as in Photoshop: the four layers, which can be hidden and moved up
    // and down (layerOrder, the Layers tab), then the canvas (SETUP 5's start), which can be
    // hidden, and the backdrop (SETUP 4), always shown - those two stay at the bottom. A layer's
    // tick box moves to its place in draw(); the up / down buttons stay put
    layerRow = cur;
    for (int i = 0; i < LAYERS; i++) {
      toggle("layerOn" + i, "layer " + (i + 1), true, 160);
      layerItem[i] = cur.items.size() - 1;
    }
    for (int k = 0; k < LAYERS; k++) {
      int pos = LAYERS - 1 - k;                  // the place in the stack shown on line k
      if (k > 0) moveButton("layerUp" + pos, "^", 262, 4 + 22 * k);
      if (k < LAYERS - 1) moveButton("layerDown" + pos, "v", 290, 4 + 22 * k);
    }
    toggle("canvasOn", "canvas", true, 160);
    cur.dy.set(cur.dy.size() - 1, 4 + 22 * LAYERS);
    canvasShown = (Toggle) all.get("canvasOn");
    backdropShown = cp5.addToggle("backdropShown").setSize(16, 16).setValue(true).lock();
    backdropShown.getCaptionLabel().align(ControlP5.RIGHT_OUTSIDE, ControlP5.CENTER).setPaddingX(6);
    put(backdropShown, 160, 4 + 22 * (LAYERS + 1));

    header("CAMERA");
    row(26);
    toggle("fieldOverlay", "direction field over the picture", false, 0);
    onlyWhen("2D");
    Slider sm = slider("smoothing", "direction field smoothing", 0, 24, 4);
    sm.setNumberOfTickMarks(13).snapToTickMarks(true).showTickMarks(false);
    sm.setTriggerEvent(Slider.RELEASE);          // rebuilding the field takes a moment - only on letting go
    colourWheel("meshBg", "mesh background", color(30));
    onlyWhen("mesh");
    row(30);
    toggle("sway", "sway", false, 0);
    button("resetView", "STRAIGHT ON", 160, 120);
    onlyWhen("mesh");
    row(26);
    toggle("light", "light on  (off shows the true colours)", true, 0);
    onlyWhen("mesh");

    // RUN's top is level with VIEW's. PRINT saves what the output window shows now, at the
    // photo's size
    bottomColumn(1, viewColumn);
    header("RUN");
    row(32);
    runButton = button("runStop", "RUN", 0, 96);
    pauseButton = button("pauseRun", "PAUSE", 106, 96);
    button("clearCanvas", "CLEAR", 212, 96);
    // how fast it paints (the window and the panel keep going at full speed), and while paused,
    // STEP paints one step at a time
    row(36);
    stepButton = button("stepRun", "STEP", 0, 96);
    paceSlider = sliderAt("pace", "painting speed", 0, 1, 1, 106, 4, 110);
    row(32);
    button("saveNow", "SAVE", 0, 96);
    button("loadSettings", "LOAD SETTINGS", 106, 150);
    row(36);
    button("nudge", "NUDGE", 0, 96);
    sliderAt("nudgeAmount", "how far", 0, 1, 0.2, 106, 4, 110);
    row(32);
    button("printView", "PRINT", 0, 96);

    // ---------------------------------------------------- column 2: the tools
    // Each tool's box: switched on or off (only one at a time), and - while it's on - its shape
    // settings
    column();
    toolBox(0, false);
    toolSlider("perFrame", "marks per frame", 0, 400, 20).setDecimalPrecision(0);
    toolSlider("size", "size (pixels, longest)", 4, 400, 110).setDecimalPrecision(0);
    toolModRow("size", 1, 0.8, true);
    toolSlider("width", "width (share of length)", 0.05, 1, 0.35);
    toolSlider("ragged", "ragged edges", 0, 1, 0.5);
    toolSlider("taper", "pointed end", 0, 1, 1);
    toolSlider("curving", "bend along the form", 0, 1, 0.5);

    toolBox(1, true);
    toolSlider("perFrame", "marks per frame", 0, 400, 20).setDecimalPrecision(0);
    toolSlider("size", "size (pixels, longest)", 4, 400, 110).setDecimalPrecision(0);
    toolModRow("size", 1, 0.8, true);
    toolSlider("width", "width (share of length)", 0.05, 1, 0.35);
    toolSlider("ragged", "ragged edges", 0, 1, 0.5);
    toolSlider("streaks", "streaks of a second colour", 0, 1, 0.4);
    onlyWhen("on knife&knifeFlat");
    toolSlider("leaf", "leaf shapes", 0, 1, 0.35);
    toolSlider("ridge", "ridge along the edge", 0, 1, 0.5);

    toolBox(2, false);
    toolSlider("rate", "clusters per frame", 0.05, 10, 0.5);
    toolSlider("drops", "drops per cluster", 0, 200, 40).setDecimalPrecision(0);
    toolSlider("size", "size (biggest splat)", 2, 120, 24).setDecimalPrecision(0);
    toolSlider("big", "how many big drops", 0, 1, 0.3);
    toolSlider("scatter", "scatter", 5, 400, 60).setDecimalPrecision(0);
    toolSlider("trails", "flung trails", 0, 1, 0.3);
    toolSlider("vary", "drop colour variation", 0, 0.5, 0.1);

    toolBox(3, false);
    toolSlider("rate", "lines per frame", 0.05, 20, 1);
    toolSlider("length", "length", 10, 800, 200).setDecimalPrecision(0);
    toolSlider("width", "width", 0.3, 8, 1.2);
    toolSlider("wander", "wander", 0, 1, 0.4);
    toolSlider("broken", "broken", 0, 1, 0.2);

    toolBox(4, false);
    toolSlider("rate", "fragments per frame", 0.1, 100, 10).setDecimalPrecision(1);
    toolSlider("size", "size", 1, 60, 8).setDecimalPrecision(1);
    toolSlider("clump", "clumping", 0, 1, 0.5);
    row(26);
    toggle("frag_dots", "dots", true, 0);
    toggle("frag_dashes", "dashes", true, 66);
    toggle("frag_tris", "triangles", true, 146);
    toggle("frag_shards", "shards", true, 236);
    onlyWhen("on frag");

    // the pencil (the Pencil tab): how it steers, on which map, and the hand
    toolBox(5, false);
    radio("pencil_kind", new String[] { "trace the edges", "flow from the map", "wander" }, 2, 0);
    onlyWhen("on pencil");
    row(28);
    label("map", 0);
    list("pencil_map", java.util.Arrays.copyOfRange(mapNames, 1, mapNames.length), 3, 34, 130);
    toggle("pencil_inv", "follow the light parts", false, 176);
    onlyWhen("on pencil");
    toolSlider("level", "level  (where the edge is)", 0, 1, 0.45);
    toolSlider("hold", "how tightly it steers", 0, 1, 0.5);
    onlyWhen("on pencil&pencilSteers");
    toolSlider("turn", "turn the flow  (degrees)", 0, 360, 0).setDecimalPrecision(0);
    onlyWhen("on pencil&pencilFlow");
    toolSlider("count", "pencils at once", 1, 40, 10).setDecimalPrecision(0);
    toolSlider("speed", "speed  (pixels a frame)", 2, 80, 24).setDecimalPrecision(0);
    toolSlider("length", "line length", 50, 3000, 700).setDecimalPrecision(0);
    toolSlider("passes", "passes over each line", 1, 6, 2).setDecimalPrecision(0);
    toolSlider("wobble", "wobble", 0, 1, 0.35);
    toolSlider("width", "width", 0.3, 6, 1.8);
    toolSlider("pressure", "pressure changes", 0, 1, 0.6);
    toolSlider("grain", "paper grain", 0, 1, 0.5);
    toolSlider("hatch", "hatching  (groups a frame)", 0, 5, 0);
    toolSlider("hatchAngle", "hatching angle", 0, 180, 45).setDecimalPrecision(0);
    onlyWhen("on pencil&pencilHatch");

    toolBox(6, false);
    radio("scrape_kind", new String[] { "knife scrape", "scratches" }, 2, 0);
    onlyWhen("on scrape");
    toolSlider("rate", "scrapes per frame", 0.05, 20, 1);
    toolSlider("length", "length", 10, 500, 140).setDecimalPrecision(0);
    toolSlider("width", "width", 2, 150, 40).setDecimalPrecision(0);
    toolSlider("ragged", "ragged edges", 0, 1, 0.5);
    toolSlider("strength", "how much comes off", 0, 1, 0.8);
    row(24);
    label("scrape down to", 0);
    radioAt("scrape_layer", new String[] { "canvas", "1", "2", "3" }, 0, 100, 54);
    onlyWhen("on scrape");

    // ---------------------------------------------------- column 3: MOVEMENT, COLOUR, APPLY
    // ... of the tool chosen in column 2. Every tool has its own set; only the chosen one's shows
    column();
    float[] followDefault = { 0.6, 0.6, 0, 0.5, 0.3, 0.3, 0.5 };
    moveHeader = header("MOVEMENT");
    for (int i = 0; i < TOOLS.length; i++) {
      String n = TOOLS[i];
      if (!n.equals("splat")) {
        slider(n + "_follow", "follow the form", 0, 1, followDefault[i]);
        onlyWhen("edit " + n);
        if (i <= 1) {
          modRow(n + "_follow", 0, 0.5, false);
          onlyWhen("edit " + n);
        }
        radio(n + "_around", new String[] { "around the form", "across it" }, 2, 0);
        onlyWhen("edit " + n);
      }
      row(20);
      label("start at", 0);
      onlyWhen("edit " + n);
      radio(n + "_startAt", new String[] { "random", "weighted by map", "grid", "mouse (2D, hold button)" }, 2, 0);
      onlyWhen("edit " + n);
      row(28);
      label("map", 12);
      list(n + "_startMap", mapNames, 1, 50, 120);
      toggle(n + "_startInv", "invert", false, 182);
      onlyWhen("edit " + n + "&weighted " + n);
      slider(n + "_spread", "spread round the mouse", 0, 300, 60).setDecimalPrecision(0);
      onlyWhen("edit " + n + "&mouse " + n);
    }
    row(6);

    colourHeader = header("COLOUR");
    onlyWhen("notScrape");
    float[] contrastDefault = { 0, 0, 0.5, 0.6, 0.5, 0.55 };
    for (int i = 0; i < TOOLS.length - 1; i++) {
      String n = TOOLS[i];
      row(20);
      label("pick up from", 0);
      onlyWhen("edit " + n);
      radio(n + "_pickup", new String[] { "photo", "canvas (wet)", "mix", "masses" }, 2, 0);
      onlyWhen("edit " + n);
      slider(n + "_mix", "mix: share from the canvas", 0, 1, 0.5);
      onlyWhen("edit " + n + "&mix " + n);
      if (i <= 1) {
        row(20);
        label("carry", 0);
        onlyWhen("edit " + n);
        radio(n + "_carry", new String[] { "one colour", "start to end", "two colours", "chunk (dipped)", "copy" }, 2, 1);
        onlyWhen("edit " + n);
      } else {
        slider(n + "_contrast", "contrast with the photo", 0, 1, contrastDefault[i]);
        onlyWhen("edit " + n);
      }
      slider(n + "_jitterH", "hue jitter", 0, 0.2, 0.02);
      onlyWhen("edit " + n);
      slider(n + "_jitterS", "saturation jitter", 0, 0.5, 0.06);
      onlyWhen("edit " + n);
      slider(n + "_jitterB", "brightness jitter", 0, 0.5, 0.08);
      onlyWhen("edit " + n);
      slider(n + "_accentChance", "accent chance", 0, 1, 0);
      onlyWhen("edit " + n);
    }
    colourWheel("accent", "accent colour  (all tools)", color(200, 60, 30));
    onlyWhen("notScrape");
    row(6);
    onlyWhen("notScrape");

    applyHeader = header("APPLY");
    onlyWhen("notScrape");
    float[] opacityDefault = { 0.9, 0.9, 0.9, 0.8, 0.9, 0.9 };
    float[] washesDefault = { 0.15, 0.15, 0, 0, 0, 0 };
    int[] layerDefault = { 1, 1, 3, 2, 2, 3 };
    float[] thicknessDefault = { 0.5, 0.8, 0.4, 0.1, 0.25, 0 };
    for (int i = 0; i < TOOLS.length - 1; i++) {
      String n = TOOLS[i];
      row(24);
      label("paints on layer", 0);
      radioAt(n + "_layer", new String[] { "1", "2", "3", "4" }, layerDefault[i], 110, 44);
      onlyWhen("edit " + n);
      slider(n + "_opacity", "opacity", 0, 1, opacityDefault[i]);
      onlyWhen("edit " + n);
      modRow(n + "_opacity", 0, 0.5, false);
      onlyWhen("edit " + n);
      slider(n + "_washes", "see-through washes", 0, 1, washesDefault[i]);
      onlyWhen("edit " + n);
      slider(n + "_thickness", "thickness  (impasto)", 0, 1, thicknessDefault[i]);
      onlyWhen("edit " + n);
      row(28);
      label("blend", 0);
      list(n + "_blend", blendNames, 0, 50, 140);
      onlyWhen("edit " + n);
    }

    // ---------------------------------------------------- column 4: ABSTRACTION, LAYERS, SHADOW BOX, IMPASTO
    column();
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
    row(6);

    // the four layers (the Layers tab): how it's combined with the layers under it, a button to
    // empty it, how see-through it is, and how much IMPASTO's light catches its paint - and the
    // canvas, which can only be made see-through (showing the backdrop). Layers 1 and 3 and the
    // canvas have a darker band behind them, drawn in draw(). (Whether each shows is in VIEW's
    // LAYERS list; which layer each tool paints on is in its APPLY)
    header("LAYERS");
    for (int i = 0; i < LAYERS; i++) {
      row(28);
      Row first = cur;
      label("layer " + (i + 1), 0);
      list("layerBlend" + i, layerBlendNames, 0, 60, 110);
      button("clearLayer" + i, "CLEAR", 240, 64).setHeight(18);
      row(26);
      sliderAt("layerSeeThrough" + i, "transparency", 0, 1, 0, 0, 0, 100);
      sliderAt("layerImpasto" + i, "impasto", 0, 1, 1, 200, 0, 70);
      layerBands[i] = new Row[] { first, cur };
    }
    row(30);
    label("canvas", 0);
    sliderAt("canvasSeeThrough", "transparency", 0, 1, 0, 60, 2, 100);
    layerBands[LAYERS] = new Row[] { cur, cur };
    row(6);

    // the layers floating apart, lit from one side (the Layers tab's composite)
    header("SHADOW BOX");
    row(26);
    toggle("boxOn", "on  (the layers float apart)", false, 0);
    slider("lightFrom", "light from  (90 = above)", 0, 360, 135).setDecimalPrecision(0);
    onlyWhen("box");
    slider("lightHeight", "light height", 10, 80, 45).setDecimalPrecision(0);
    onlyWhen("box");
    slider("boxShadow", "shadow darkness", 0, 1, 0.6);
    onlyWhen("box");
    slider("boxSoftness", "shadow softness", 0, 1, 0.4);
    onlyWhen("box");
    slider("boxRim", "lit edges", 0, 1, 0.4);
    onlyWhen("box");
    row(20);
    label("gap above the layers under it  (pixels)", 0);
    onlyWhen("box");
    for (int i = 0; i < LAYERS; i++) {
      slider("layerGap" + i, "layer " + (i + 1), 0, 60, 12).setDecimalPrecision(0);
      onlyWhen("box");
    }
    row(6);

    // thick paint catching a raking light (the Impasto tab); how thick each tool's paint is is in
    // its APPLY
    header("IMPASTO");
    row(26);
    toggle("impastoOn", "on  (the light catches thick paint)", true, 0);
    slider("impastoRelief", "relief", 0, 1, 0.5);
    onlyWhen("impasto");
    slider("impastoFrom", "light from  (90 = above)", 0, 360, 135).setDecimalPrecision(0);
    onlyWhen("impasto");
    slider("impastoHeight", "light height", 10, 80, 35).setDecimalPrecision(0);
    onlyWhen("impasto");
    slider("impastoGloss", "shine", 0, 1, 0.3);
    onlyWhen("impasto");

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
    if (picked != null) {
      picked.close();
      picked = null;
      layoutWanted = true;
    }
    // each layer's tick box on its line in VIEW's LAYERS list, top of the stack first
    String order = join(str(layerOrder), " ");
    if (!order.equals(shownOrder)) {
      shownOrder = order;
      for (int i = 0; i < LAYERS; i++) layerRow.dy.set(layerItem[i], 4 + 22 * (LAYERS - 1 - layerPosition(i)));
      layoutWanted = true;
    }
    if (layoutWanted) layout();
    // the coloured blocks behind the sections (the controls are drawn on top after this)
    noStroke();
    for (int i = 0; i < sections; i++) {
      if (block[i] == null) continue;
      fill(blockColour[i]);
      rect(block[i][0] - 8, block[i][1], colW - 12, block[i][2] - block[i][1], 8);
    }
    // each setup box's square, before its title: red, then green once it's done
    int[] setupBoxes = { sourceBox, targetBox, massBox, backdropBox, startBox };
    boolean[] setupDone = { sourceDone, targetDone, massesDone, backdropDone, startDone };
    for (int k = 0; k < setupBoxes.length; k++) {
      float[] b = block[setupBoxes[k]];
      if (b == null) continue;
      fill(setupDone[k] ? doneGreen : notDoneRed);
      rect(b[0] - 1, b[1] + 9, 15, 15, 3);
    }
    // LAYERS: a darker band behind layers 1 and 3 and the canvas
    for (int i = 0; i <= LAYERS; i += 2) {
      Row a = layerBands[i][0], z = layerBands[i][1];
      if (a.y < 0 || block[a.section] == null) continue;
      fill(lerpColor(blockColour[a.section], color(0), 0.12));
      rect(block[a.section][0] - 4, a.y - 2, colW - 20, z.y + z.h - a.y, 5);
    }
    // a frame round the box of the tool that's on
    int ch = toolSection[max(0, java.util.Arrays.asList(TOOLS).indexOf(editing))];
    if (block[ch] != null && value(editing + "_on") > 0.5) {
      noFill();
      stroke(dark);
      strokeWeight(2);
      rect(block[ch][0] - 8, block[ch][1], colW - 12, block[ch][2] - block[ch][1], 8);
      noStroke();
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
    // RUN green, STOP red. PAUSE green while painting, CARRY ON orange while paused. While a map
    // is showing nothing paints (the painter pauses), so RUN and CARRY ON are greyed out and locked
    boolean going = isRunning || runWaiting;
    boolean mapShown = value("showWhat") > 0;
    runButton.setCaptionLabel(going ? "STOP" : "RUN");
    buttonColour(runButton, going ? runRed : runGreen, going ? runRedHover : runGreenHover, !going && mapShown);
    pauseButton.setCaptionLabel(isPaused ? "CARRY ON" : "PAUSE");
    if (!isRunning) buttonColour(pauseButton, color(60), color(70, 130, 200), false);
    else if (isPaused) buttonColour(pauseButton, orange, orangeHover, mapShown);
    else buttonColour(pauseButton, runGreen, runGreenHover, false);
    buttonColour(stepButton, color(60), color(70, 130, 200), !(isRunning && isPaused) || mapShown);
    paceSlider.getValueLabel().setText(paceText(paceRate(value("pace"))));
    canvasShown.setCaptionLabel("canvas  (" + startNames[(int) value("startWith")] + ")");
    backdropShown.setCaptionLabel("backdrop  (" + backdropNames[(int) value("backdropKind")] + ")");
    backdropShown.setValue(1);
    backdropShown.setLock(true);
    if (!editing.equals(shownEditing)) {
      shownEditing = editing;
      int e = java.util.Arrays.asList(TOOLS).indexOf(editing);
      moveHeader.setText("MOVEMENT  -  " + toolTitles[e].toLowerCase());
      colourHeader.setText("COLOUR  -  " + toolTitles[e].toLowerCase());
      applyHeader.setText("APPLY  -  " + toolTitles[e].toLowerCase());
    }
    String locked = shownRunning ? "   (locked while running)" : "";
    sourceText.setText(sourceDone ? faces[(int) value("source")] + locked : "click to choose a picture");
    targetText.setText(targetDone ? outputNames[(int) value("output")] + locked : "click to choose 2D or a mesh");
    massTitle.setText(massesOpen ? "SETUP 3   MASSES     click here when they look right" : "SETUP 3   MASSES");
    massText.setText(massesOpen ? massStatus : massesDone ? "done  -  " + massStatus.replace("masses: ", "")
      : "click to make the masses");

    cp5.draw();
    // with every tool off, columns 3 - 4 still show the last tool's settings, under a grey cover
    boolean anyOn = false;
    for (String t : TOOLS) anyOn |= value(t + "_on") > 0.5;
    if (!anyOn) {
      fill(128, 124);
      noStroke();
      rect(16 + 2 * colW - 12, 0, 2 * colW, height - 28);
    }

    // the status line along the bottom
    fill(50);
    noStroke();
    rect(0, height - 28, width, 28);
    fill(220);
    textAlign(LEFT, CENTER);
    String state = isRunning ? (isPaused ? (value("showWhat") > 0 ? "paused  (showing a map)" : "paused") : "painting") : runWaiting ? "waiting for the masses" : "stopped";
    text(faceName + "   " + photo.width + " x " + photo.height + "      " + state + "      " + markCount + " marks      "
      + round(outputFps) + " fps      " + massStatus, 16, height - 14);
  }

  // controlP5 only counts a click on a radio button's or toggle's little square - make a click on
  // the words beside it count too
  public void mousePressed() {
    pressedIn = -1;
    // a click off an open setup list closes it
    for (String n : new String[] { "source", "output" }) {
      ScrollableList l = (ScrollableList) all.get(n);
      if (l.isOpen() && !l.isMouseOver()) {
        l.close();
        layoutWanted = true;
        return;
      }
    }
    if (listOpen) return;
    if (inBlock(startBox, 0)) startDone = true;
    if (inBlock(backdropBox, 0)) backdropDone = true;
    for (int b : new int[] { sourceBox, targetBox, massBox }) {
      if (inBlock(b, 0)) {
        pressedIn = b;
        return;
      }
    }
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

  // a click on a setup box: opens its list, or opens and closes the masses. Done when the button
  // is let go - the list opens under the mouse, and controlP5 picks a list item on letting go
  public void mouseReleased() {
    int b = pressedIn;
    pressedIn = -1;
    if (b < 0 || !inBlock(b, 0)) return;
    if (b == massBox) {
      if (!massesOpen) openMasses(true);
      else if (inBlock(b, 34)) openMasses(false);    // only the title closes it
    } else if (!isRunning) {
      ScrollableList l = (ScrollableList) all.get(b == sourceBox ? "source" : "output");
      l.open();
      l.show();
      layoutWanted = true;
    }
  }

  // a button's colour, and its hover colour - or grey and locked (and the lists lock everything
  // while one is open)
  void buttonColour(Button b, int c, int hover, boolean off) {
    b.setColorBackground(off ? color(85) : c).setColorForeground(off ? color(85) : hover);
    b.getCaptionLabel().setColor(off ? color(150) : color(255));
    b.setLock(off || listOpen);
  }

  // whether the mouse is in section b's colour block - only its top `h` if h > 0
  boolean inBlock(int b, float h) {
    float[] k = block[b];
    if (k == null) return false;
    float bottom = h > 0 ? k[1] + h : k[2];
    return mouseX >= k[0] - 8 && mouseX <= k[0] - 20 + colW && mouseY >= k[1] && mouseY <= bottom;
  }

  // opening the masses box shows the masses (with the light off, so their colours are true);
  // closing it puts the view back and marks them done
  void openMasses(boolean open) {
    massesOpen = open;
    RadioButton show = (RadioButton) all.get("showWhat");
    Toggle light = (Toggle) all.get("light");
    int masses = java.util.Arrays.asList(showNames).indexOf("masses");
    if (open) {
      showBefore = show.getValue();
      lightBefore = light.getValue();
      show.activate(masses);
      light.setValue(0);
    } else {
      massesDone = true;
      if (show.getValue() == masses) show.activate(showBefore == masses ? 0 : (int) showBefore);
      light.setValue(lightBefore);
    }
    layoutWanted = true;
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
    else if (n.equals("stepRun")) command("step");
    else if (n.equals("clearCanvas")) command("clear");
    else if (n.equals("saveNow")) command("save");
    else if (n.equals("printView")) command("print");
    else if (n.equals("loadSettings")) command("load");
    else if (n.equals("nudge")) nudgeAll();
    else if (n.equals("resetView")) command("resetView");
    else if (n.equals("source")) {
      command("source");
      sourceDone = true;
      massesDone = false;      // a new picture needs its masses looked at again
    }
    else if (n.equals("output")) targetDone = true;
    else if (n.equals("startWith")) startDone = true;
    else if (n.equals("backdropKind")) backdropDone = true;
    else if (n.equals("smoothing")) command("field");
    else if (n.equals("showWhat")) command("show");
    else if (n.equals("layMasses")) command("layMasses");
    else if (n.equals("massSeed")) command("massSeed");
    else if (n.startsWith("clearLayer")) command(n);
    else if (n.startsWith("layerUp")) command("moveLayer " + n.substring(7) + " 1");
    else if (n.startsWith("layerDown")) command("moveLayer " + n.substring(9) + " -1");
    // switching a tool on chooses it, so its settings show, and switches the others off
    else if (n.endsWith("_on") && e.getValue() > 0.5) {
      editing = n.substring(0, n.length() - 3);
      for (String t : TOOLS) {
        if (!t.equals(editing) && value(t + "_on") > 0.5) all.get(t + "_on").setValue(0);
      }
    }
  }


  // ---------------------------------------------------- showing and hiding

  // whether a row marked `when` means anything with the choices as they are now
  // Several conditions can be joined with &, e.g. "edit knife&mix knife": all must be true.
  // Most take a tool's name: "edit knife" is true while the knife is chosen in column 2
  boolean shown(String when) {
    if (when.equals("")) return true;
    if (when.contains("&")) {
      for (String w : when.split("&")) if (!shown(w)) return false;
      return true;
    }
    if (when.startsWith("edit ")) return editing.equals(when.substring(5));
    if (when.startsWith("on ")) return value(when.substring(3) + "_on") > 0.5;
    if (when.startsWith("open ")) return ((ScrollableList) all.get(when.substring(5))).isOpen();
    if (when.startsWith("shut ")) return !((ScrollableList) all.get(when.substring(5))).isOpen();
    if (when.equals("massesOpen")) return massesOpen;
    if (when.equals("ground")) return targetDone && value("output") == 0;
    if (when.equals("later")) return false;
    if (when.equals("notScrape")) return !editing.equals("scrape");
    if (when.equals("pencilSteers")) return value("pencil_kind") < 2;
    if (when.equals("pencilFlow")) return value("pencil_kind") == 1;
    if (when.equals("pencilHatch")) return value("pencil_hatch") > 0;
    if (when.equals("knifeFlat")) return value("knife_carry") < CHUNK;   // chunk and copy have no streaks
    if (when.startsWith("mix ")) return value(when.substring(4) + "_pickup") == 2;
    if (when.startsWith("weighted ")) return value(when.substring(9) + "_startAt") == 1;
    if (when.startsWith("mouse ")) return value(when.substring(6) + "_startAt") == 3;
    if (when.equals("abstraction")) return value("abstractionOn") > 0.5;
    if (when.equals("box")) return value("boxOn") > 0.5;
    if (when.equals("impasto")) return value("impastoOn") > 0.5;
    if (when.equals("backdropKind")) return value("backdropKind") > 0;
    if (when.equals("careful")) return value("abstractionOn") > 0.5 && value("protectWith") == 1;
    if (when.equals("2D abstraction")) return value("output") == 0 && value("abstractionOn") > 0.5;
    if (when.equals("2D")) return value("output") == 0;
    if (when.equals("mesh")) return value("output") > 0;
    if (when.startsWith("map ")) return value(when.substring(4) + "_by") > 0;   // a "by" row with a map chosen
    return true;
  }

  float value(String name) {
    return all.get(name).getValue();
  }

  // put every shown row in place, top to bottom in each column, and hide the rest. The columns
  // along the bottom end just above the status line
  void layout() {
    layoutWanted = false;
    float[][] b = new float[sections][];
    float[] top = new float[columns.size()];
    for (int i = 0; i < columns.size(); i++) {
      float x = 16 + colAt.get(i) * colW, y = 8;
      if (colBottom.get(i) == 1) {
        float total = 0;
        for (Row r : columns.get(i)) if (shown(r.when)) total += r.h;
        y = height - 36 - total;
        if (colLevel.get(i) >= 0) y = min(y, top[colLevel.get(i)]);
      }
      top[i] = y;
      for (Row r : columns.get(i)) {
        boolean rowShown = shown(r.when);
        r.y = rowShown ? y : -1;
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
      if (!(c instanceof Slider) || n.equals("nudgeAmount") || n.equals("pace") || n.endsWith("perFrame") || n.endsWith("_rate")) continue;
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
  }


  // ---------------------------------------------------- building the panel
  // Each control is made at (0, 0) and put() in a row; layout() moves it to its place.

  void column() {
    columns.add(new ArrayList<Row>());
    colAt.append(topColumns++);
    colBottom.append(0);
    colLevel.append(-1);
  }

  // a column along the bottom of the window, under top column `at`. Its top is level with column
  // `level`'s (if that's not -1, and it fits). Returns its number, for `level`
  int bottomColumn(int at, int level) {
    columns.add(new ArrayList<Row>());
    colAt.append(at);
    colBottom.append(1);
    colLevel.append(level);
    return columns.size() - 1;
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

  // a tool's box in column 2: its name with an on / off box - red off, green on. The rows made
  // after it with toolSlider() etc. are its shape settings, shown while it's on
  void toolBox(int i, boolean on) {
    curTool = TOOLS[i];
    sections++;
    toolSection[i] = sections - 1;
    row(36);
    Toggle t = cp5.addToggle(curTool + "_on").setSize(20, 20).setValue(on);
    t.setColorBackground(toolOff).setColorForeground(toolOffHover).setColorActive(toolOn);
    t.setCaptionLabel(toolTitles[i]);
    t.getCaptionLabel().align(ControlP5.RIGHT_OUTSIDE, ControlP5.CENTER).setPaddingX(8);
    register(curTool + "_on", t);
    put(t, 0, 10);
  }

  // a slider on a row of its own in the current tool's box, named "tool_name"
  Slider toolSlider(String name, String caption, float lo, float hi, float value) {
    Slider s = slider(curTool + "_" + name, caption, lo, hi, value);
    onlyWhen("on " + curTool);
    return s;
  }

  void toolModRow(String name, int by, float amount, boolean invert) {
    modRow(curTool + "_" + name, by, amount, invert);
    onlyWhen("on " + curTool);
  }

  // a setup box: a section whose title is clicked (see mouseReleased). Returns its section
  int setupBox(String title) {
    boxTitle = header(title);
    cur.dx.set(0, 20);                   // room for the square before it (drawn in draw())
    return sections - 1;
  }

  // the line under a setup box's title, set in draw(). It's hidden while the box's list is open -
  // the list covers it, and it would take the list's clicks
  Textlabel boxText(String list) {
    row(24);
    Textlabel t = cp5.addTextlabel("text " + sections).setText("").setColorValue(dark);
    put(t, -4, 0, list.equals("") ? "" : "shut " + list);
    return t;
  }

  // a setup box's list: no bar of its own - clicking the box opens it, over the box's other rows
  void setupList(String name, String[] items) {
    ScrollableList l = cp5.addScrollableList(name).setSize(colW - 30, 20 * items.length)
      .setBarHeight(0).setItemHeight(20).addItems(java.util.Arrays.asList(items)).setType(ScrollableList.DROPDOWN);
    l.setBarVisible(false);
    // picking an item marks the box done - even the one already chosen, which sends no event
    l.addCallback(new CallbackListener() {
      public void controlEvent(CallbackEvent e) {
        if (e.getAction() != ControlP5.ACTION_RELEASE) return;
            if (name.equals("source")) sourceDone = true;
        else targetDone = true;
        picked = (ScrollableList) e.getController();   // closed in draw(), after controlP5 has used the click
      }
    });
    l.setValue(0);
    l.close();
    register(name, l);
    lists.add(l);
    // only there while it's open: closed, controlP5 still counts clicks on the space it would cover
    put(l, -4, -2, "open " + name);
  }

  // a slider in the masses box, shown while it's open
  Slider massSlider(String name, String caption, float lo, float hi, float value) {
    Slider s = slider(name, caption, lo, hi, value);
    onlyWhen("massesOpen");
    return s;
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

  // radio buttons in the current row, at dx, spaced `step` apart (for short items like "1" "2" "3")
  void radioAt(String name, String[] items, int chosen, float dx, int step) {
    RadioButton r = cp5.addRadioButton(name).setSize(16, 16).setItemsPerRow(items.length)
      .setSpacingColumn(step - 16);
    for (int i = 0; i < items.length; i++) {
      r.addItem(name + " " + i, i);
      r.getItem(i).setCaptionLabel(items[i]);
    }
    r.activate(chosen);
    r.setNoneSelectedAllowed(false);
    register(name, r);
    put(r, dx, 2);
  }

  // a row choosing the layer a mark system paints on: its name, then 1 2 3 4
  void layerChoice(String name, String caption, int chosen) {
    row(24);
    label(caption, 12);
    radioAt(name, new String[] { "1", "2", "3", "4" }, chosen, 110, 44);
  }

  // a colour wheel on a row of its own
  void colourWheel(String name, String caption, int c) {
    row(128);
    ColorWheel w = cp5.addColorWheel(name, 0, 0, 100).setRGB(c);
    w.setCaptionLabel(caption);
    register(name, w);
    put(w, 0, 0);
  }

  // a small up or down button in VIEW's LAYERS list
  void moveButton(String name, String caption, float dx, float dy) {
    Button b = cp5.addButton(name).setSize(22, 16);
    b.setCaptionLabel(caption);
    put(b, dx, dy);
  }

  Button button(String name, String caption, float dx, int w) {
    Button b = cp5.addButton(name).setSize(w, 26);
    b.setCaptionLabel(caption);
    put(b, dx, 0);
    return b;
  }
}
