// The control panel: a second window, built with controlP5.
//
// Four columns:
//   SETUP 1 - 5                   source, masses, outline, mesh, palette: a box
//                                 each, two lines (a square, red until it's done and then green,
//                                 with the title; and where it's got to). Clicking one opens it
//                                 over the boxes below; clicking its title closes it and marks it
//                                 done. Until all five are done the rest of the panel (but VIEW) is greyed
//                                 out and locked
//   the tools                     COPY, which lays a map on a layer (the Copy tab), and SCRAPE, which
//                                 takes paint off one, then what does the drawing: brush, palette
//                                 knife, sponge, splatter (purples), lines, pencil, flow, outline
//                                 (blues) - one at a time, with its shape settings. At the bottom,
//                                 above RUN and coloured like VIEW: LIGHT, each layer's light (its
//                                 shadow and lit edges) and the thick paint's; and RECOLOUR, changing
//                                 the painting's colours a few at a time (a layer's, or the palette's
//                                 on the masses or the mesh)
//   APPLY, MOVEMENT, COLOUR       two steps to be done first - ON LAYER, which layer the chosen tool
//                                 paints on and how solid it is, and IN AREA, where on it - then
//                                 how it moves, and where its colour comes from
//   LAYER 1 - 5, A, B             a box for each layer, the layers floating apart, each lit from
//                                 one side by its own light (in LIGHT)
// and along the bottom, AUTOMATION (the painting speed, the chosen tool's size or length moved up and
// down by a wave - the Automation tab - and NUDGE) and under it VIEW (MAPS, and LAYERS with the outline
// and the direction field under it) under column 1, and RUN at the very bottom of column 2.
//
// VIEW's MAPS starts with PAINTING, with a box like the tools': green while the painting shows, red
// while a map does. While it's red nothing runs, and the rest of the panel is greyed out and locked
// as it is before SETUP is done - but not when it was RECOLOUR (on the masses or the mesh) or a PICK
// ON button that showed the map, as those are used with it showing.
//
// Every tool has its own MOVEMENT, COLOUR and APPLY settings, named with the tool in front
// ("knife_follow", "splat_opacity" ...). Only one tool is on at a time: switching one on (its
// box turns from red to green) switches the others off and chooses it (`editing`) - its box
// opens and column 3 shows its settings. With every tool off (as at the start), it shows the last
// one's under a grey cover. The painter reads them with t("follow") while that tool paints (the Marks tab).
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
  IntList colBottom = new IntList();   // 1 for the ones along the bottom of the window, 2 for those just above RUN
  IntList colLevel = new IntList();    // a bottom column whose top this one's is level with, or -1
  int topColumns = 0;
  Row cur;                   // the row being built
  int curBand = 0;           // the band rows being built go in (Row's band)
  boolean live;              // whether the controls being built can change while running
  volatile boolean layoutWanted = true;
  boolean shownRunning = false;
  boolean listOpen = false;  // one of the dropdown lists is open
  Button runButton, pauseButton, stepButton;
  Slider paceSlider;
  Row layerRow;                                   // VIEW's lists, with the layers' tick boxes
  int[] layerItem = new int[LAYERS];              // each layer's tick box in layerRow's items
  String shownOrder = "";
  final int VIEW_TOP = 28;                        // how far down that row its lists start
  // the tools' boxes, in the order of TOOLS: the brushes, sponge and splatter purples, the lines blues, and
  // SCRAPE and COPY alike
  int[] TOOL_COLOURS = { 0xFFD8C8EE, 0xFFCCB9E7, 0xFFB29AD6, 0xFFC3D8F0, 0xFFB3CDEA, 0xFFA5C2E2, 0xFF91B3D8, 0xFFC1ABE0, 0xFFCFABA2, 0xFFCFABA2 };
  int viewBase = 0xFFDCE6F2, mapsBlue = 0xFF9FC1E8, layersBlue = 0xFFC3DAF3;   // VIEW, and its two columns
  int[] layerSection = new int[LAYERS];         // each layer's box
  // their colours: reds, LAYER 1 the lightest to LAYER B the darkest
  int[] LAYER_COLOURS = { 0xFFFBE2E0, 0xFFF3CECB, 0xFFEBB9B7, 0xFFE3A5A2, 0xFFDB918D, 0xFFD37C79, 0xFFCB6864 };
  int runGreen = 0xFF2E9E48, runGreenHover = 0xFF45B860, runRed = 0xFFCC3B2E, runRedHover = 0xFFE26A5E;
  int orange = 0xFFE08A1E, orangeHover = 0xFFF0A040;
  // the setup boxes (1 SOURCE, 2 MASSES, 3 OUTLINE, 4 MESH, 5 PALETTE GEN): their colour blocks, the line under each title, and whether each is done.
  // S_SRC ... are their numbers (SETUP 1 is 0); one at a time is open (openSetup, -1: none)
  final int S_SRC = 0, S_MASS = 1, S_OUTL = 2, S_MESH = 3, S_PAL = 4, S_COUNT = 5;
  int sourceBox, massBox, meshBox;
  int[] boxRowFrom = new int[S_COUNT + 1], boxContentFrom = new int[S_COUNT];   // their rows in column 1
  Textlabel[] boxTitles = new Textlabel[S_COUNT], boxTexts = new Textlabel[S_COUNT];
  String[] boxNames = new String[S_COUNT];
  volatile int openSetup = -1;
  volatile boolean meshOpen = false, meshDone = false, paletteDone = false;
  boolean inSetup = false;            // the controls being built are in a setup box
  boolean inView = false;             // ... or in VIEW, which is never greyed out
  java.util.HashSet<String> viewGroup = new java.util.HashSet<String>();
  boolean gated = false;              // the rest of the panel is greyed out (not every box done yet, or a map showing)
  HashMap<String, Button> buttons = new HashMap<String, Button>();
  // ... but for these, which work (and show) all the same
  String[] alwaysButtons = { "saveNow", "loadSettings" };
  java.util.HashSet<String> setupGroup = new java.util.HashSet<String>();
  int viewSection, autoSection, recolourSection, lightSection;      // (all coloured like VIEW)
  float shownFor = -1;                // the view an open box switched to
  int boxRed = 0xFFD9B8B4, boxGreen = 0xFFBBD3B6;   // a setup box's block: not done, done
  Textlabel boxTitle, massTitle, sourceText, massText, meshText;
  Textlabel copyText;                 // COPY: what it did last
  Textlabel zoneText;                 // the zone: how much of the picture it is
  volatile boolean sourceDone, massesDone;
  volatile boolean massesOpen = false;
  float showBefore;                   // put back when the masses box closes
  int pressedIn = -1;                 // the setup box a click started in
  ScrollableList picked;              // a setup list an item was just picked from
  volatile boolean sourcesChanged = false;   // SETUP 1's list wants its items again (a new picture)
  volatile int sourceWanted = -1;     // ... and this item chosen
  final String OPEN_PICTURE = "open a picture ...";
  int doneGreen = 0xFF2E9E48, notDoneRed = 0xFFCC3B2E;   // a setup box's square

  // RECOLOUR (the Recolour tab): the palette's colours, what's been done to each (hue shift in
  // degrees, saturation and brightness multiplied by), and which are chosen. Replaced whole, never
  // changed in place, as the painter reads them from its own thread
  volatile int[] recolourBase = new int[0];
  volatile float[][] recolourAdj = new float[0][];
  boolean[] recolourPicked = new boolean[0];
  // ... those are the chosen layer's (recolourL); every layer's are kept here
  volatile int[][] recolourBases = new int[LAYERS][0];
  volatile float[][][] recolourAdjs = new float[LAYERS][0][];
  boolean[][] recolourPickeds = new boolean[LAYERS][0];
  int recolourL = 0;
  Row recolourGrid, recolourPalGrid;  // the rows the swatches are drawn in: a layer's, the palette's
  // 0: a layer, 1: the masses, 2: the mesh - for those two the swatches are SETUP 5's palette
  volatile int recolourKind = 0;
  int recolourShown = -1;             // the map VIEW was switched to for that (-1: none)
  float recolourShowBefore = 0;       // ... and what it showed before
  boolean applying = false;           // saved settings are being put back: don't switch the view
  Row accentBar;                      // the row COLOUR's accent hue bar is drawn in
  Textlabel recolourText;
  boolean recolourSyncing = false;    // the sliders are being set to show a swatch, not moved
  final int SWATCH_COLS = 5, SWATCH_H = 35;
  final int SWATCH_PAL_COLS = 8;      // ... the palette's 24, in fewer rows

  // SETUP 5, PALETTE GEN (the Palette Gen tab): the palette's colours as generated, what's been
  // done to each (hue shift in degrees, saturation and brightness multiplied by), which are chosen,
  // and the scheme and hue it was made from. Replaced whole, never changed in place, as the painter
  // reads them from its own thread
  int paletteBox;
  volatile boolean paletteOpen = false;
  // SETUP 3, OUTLINE: done once it's been looked at
  int outlineBox;
  volatile boolean outlineOpen = false, outlineDone = false;
  Textlabel outlineTitle, outlineText;
  volatile int[] paletteBase = new int[0];
  volatile float[][] paletteAdj = new float[0][];
  boolean[] palettePicked = new boolean[0];
  int paletteSchemeMade = 0, paletteHueMade = 0;
  java.util.Random paletteRnd = new java.util.Random();
  Row paletteGrid;                    // the row the palette's swatches are drawn in
  Textlabel paletteTitle, paletteText;
  boolean paletteSyncing = false;     // the chosen-colour sliders are being set to show a swatch
  final int PAL_COLS = 6, PAL_H = 34;
  // IN AREA's colours can be picked by clicking the masses in the output window: PICK ON THE MASSES
  // shows them there, and each click turns the colour under it on or off (the output window's
  // mousePressed) until the button is pressed again; then the view goes back. `picking` is whether
  // clicks there are for that (or for IN AREA's blobs, tris ...)
  // (never give a variable here the same name as a control: controlP5 sets a variable with a
  // control's name whenever that control is used)
  final int PICK_NONE = 0, PICK_AREA = 1;
  volatile int picking = PICK_NONE;
  int pickingShown = PICK_NONE;       // what the panel has switched the view for
  float viewBeforePick;
  int pickMapShown = -1;              // ... to this map
  Button areaPickButton;
  Textlabel eraseText;                // SCRAPE's ERASE: what it did last
  Textlabel patchText, partsText1, partsText2;     // IN AREA's Masses, Tris ...: how many are picked - and which, of the face parts
  // IN AREA (APPLY, the Area tab): the palette colours it's made of - the places the masses in
  // the palette's colours are one of them. Each tool can draw only in it, or only outside it
  volatile boolean[] areaPick = new boolean[PALETTE_SIZE];
  Row areaStrip;
  volatile float[] paletteUse = new float[0];   // each palette colour's share of the masses (from the painter)
  volatile float[] meshPaletteUse = new float[0];   // ... and of the mesh in palette colours
  final int STRIP_COLS = 12, STRIP_H = 22;
  int colW = 340;            // width of a column
  int runSection = -1;       // RUN's box, at the bottom of column 2
  int sections = 0;          // SETUP, RUN, VIEW ... each gets a block of colour behind it
  int[] blockColour = new int[0];
  float[][] block = new float[0][];   // each section's x, top, bottom as laid out, or null if hidden
  int dark = 0xFF232323;     // text on the coloured blocks (dark grey)
  volatile String editing = "knife";   // the tool switched on in column 2, whose settings columns 3 - 4 show
  String shownEditing = "";
  int toolOff = 0xFFCC3B2E, toolOffHover = 0xFFE26A5E, toolOn = 0xFF2E9E48;   // a tool's on / off box
  int[] toolSection = new int[TOOLS.length];   // each tool box's colour block
  String curTool;            // the tool whose box is being built
  boolean inTools = false;   // ... and the rows being made are its settings
  boolean toolFolded = false;         // there's no room for the chosen tool's settings: RECOLOUR is open
  Textlabel moveHeader, colourHeader, applyHeader;
  int applySection, moveSection;      // APPLY's and MOVEMENT's colour blocks
  boolean[] moveFolded = new boolean[TOOLS.length];   // each tool's MOVEMENT: folded, by clicking its title
  boolean movePressed = false;        // its title has been pressed (it folds or opens on letting go)
  Textlabel moveText;                 // what's chosen in it, while it's folded
  volatile boolean applyOpen = false; // opened by its title (it's open anyway till both its steps are done)
  boolean applyPressed = false;       // its title has been pressed (it opens or closes on letting go)
  volatile boolean layerClicked = false;   // a layer or an area's been clicked: APPLY may close on letting go
  Row autoWave;              // the row AUTOMATION's wave is drawn in
  int viewColumn;            // the column along the bottom of column 1: AUTOMATION, then VIEW

  // one row of controls, and when it's shown (see shown())
  class Row {
    String when = "";
    float h;
    float y = -1;            // where layout() put it, or -1 if it's hidden
    int section;
    boolean autoSetting;     // one of AUTOMATION's
    boolean toolSetting;     // one of a tool's settings, in its box in column 2
    int band;                // 0, or a part of its section drawn a shade lighter or darker (drawBands)
    ArrayList<ControllerInterface> items = new ArrayList<ControllerInterface>();
    ArrayList<String> itemWhen = new ArrayList<String>();
    FloatList dx = new FloatList(), dy = new FloatList();
  }

  public void settings() {
    size(1400, 1000);
  }

  public void setup() {
    surface.setTitle("painter2DA - controls");
    // just to the right of the output window. Window positions are in the screen's scaled
    // units (half the pixels on a screen at 200%), but the output window's size is in pixels
    double scale = java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment().getDefaultScreenDevice()
      .getDefaultConfiguration().getDefaultTransform().getScaleX();
    // ... but not off the right of the screen
    java.awt.Rectangle screen = java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment().getMaximumWindowBounds();
    surface.setLocation(min((int) ((40 + painter2DA.this.width) / scale) + 30, screen.x + screen.width - width - 16), 40);
    textFont(createFont("Arial", 12, true));
    cp5 = new ControlP5(this);
    cp5.setAutoDraw(false);    // drawn in draw(), so the cover over column 3 can go on top
    cp5.setFont(createFont("Arial", 12, true), 12);
    cp5.setColorForeground(color(70, 130, 200));
    cp5.setColorActive(color(110, 170, 240));
    cp5.setColorBackground(color(60));

    // ---------------------------------------------------- column 1: SETUP 1 - 5
    // Five boxes, each two lines - a square (red, then green once it's done) with the title, and
    // a line saying where it's got to. They all start not done. Clicking a box opens it, over the
    // boxes below it (and VIEW); clicking its title again closes it and marks it done (SOURCE
    // closes itself once a choice is made). Until every box is done, the rest of the
    // panel is greyed out. While a run is going they're all locked (and can't be opened). See
    // openBox() and closeBox()
    column();
    live = false;
    inSetup = true;
    setupStart(S_SRC);
    sourceBox = setupBox("SETUP 1   SOURCE");
    boxTitles[S_SRC] = boxTitle;
    sourceText = boxText("source");
    boxTexts[S_SRC] = sourceText;
    setupList("source", sourceItems());
    setupContent(S_SRC);

    // the masses (the Masses tab): opening the box shows them. They're made again when one of the
    // sliders is let go, and RUN waits for them
    setupStart(S_MASS);
    massBox = setupBox("SETUP 2   MASSES");
    boxTitles[S_MASS] = boxTitle;
    massText = boxText("");
    boxTexts[S_MASS] = massText;
    setupContent(S_MASS);
    massSlider("massBlobs", "blobs", 200, 6000, 1500).setDecimalPrecision(0);
    massSlider("massRound", "roundness", 1, 40, 10).setDecimalPrecision(1);
    massSlider("massJoin", "join similar neighbours", 0, 40, 8).setDecimalPrecision(1);
    massSlider("massSmooth", "smooth edges", 0, 16, 3).setDecimalPrecision(1);
    // (always 24 colours, one for each of SETUP 5's - see MASS_PAINTS in the Masses tab)
    live = true;
    massSlider("massHue", "palette hue", -0.5, 0.5, 0);
    massSlider("massSat", "palette saturation", 0, 2, 1);
    massSlider("massBri", "palette brightness", 0, 2, 1);
    row(6);
    // for later: laying the masses on during a run, and textured paint (never shown for now)
    row(32);
    button("layMasses", "LAY ON NOW", 0, 110);
    sliderAt("layOpacity", "opacity", 0, 1, 0.5, 120, 5, 110);
    onlyWhen("later");
    row(30);
    toggle("massTexture", "textured paint", false, 0);
    button("massSeed", "NEW TEXTURE", 170, 110);
    onlyWhen("later");

    // SETUP 3, OUTLINE (the Outline tab plans it): the face in one line - which parts of the parts
    // map and the face landmarks it traces, and how smooth. The OUTLINE tool draws it, and
    // MOVEMENT's "along the outline" follows it. Open, the line is drawn over the picture
    setupStart(S_OUTL);
    outlineBox = setupBox("SETUP 3   OUTLINE");
    boxTitles[S_OUTL] = boxTitle;
    outlineText = boxText("");
    boxTexts[S_OUTL] = outlineText;
    setupContent(S_OUTL);
    // a face (its parts, from parts.png and the landmarks) or the objects (objects.png) - only
    // the chosen one's options show
    radio("outline_kind", new String[] { "face", "objects" }, 2, 0);
    row(24);
    toggle("outline_sil", "silhouette", true, 0);
    toggle("outline_hair", "hairline", true, 100);
    toggle("outline_clothes", "neck & clothes", true, 190);
    onlyWhen("outlineFace");
    row(24);
    toggle("outline_face", "face", true, 0);
    toggle("outline_brows", "brows", true, 60);
    toggle("outline_eyes", "eyes", true, 128);
    toggle("outline_nose", "nose", true, 190);
    toggle("outline_mouth", "mouth", true, 252);
    onlyWhen("outlineFace");
    // objects bigger than "over" (the sky, a field) or smaller than "under" are left out
    slider("outline_bigObj", "leave out over  (% of picture)", 1, 100, 30).setDecimalPrecision(0);
    onlyWhen("outlineObjects");
    slider("outline_smallObj", "leave out under  (% of picture)", 0, 5, 0.1);
    onlyWhen("outlineObjects");
    slider("outline_smooth", "smoothness", 0, 1, 0.5);
    row(2);

    // SETUP 4, the mesh (the Mesh tab): triangles, made beside the masses - opening the box shows
    // it, with the triangles' sides. It comes after the outline, which it can put points along
    live = false;
    setupStart(S_MESH);
    meshBox = setupBox("SETUP 4   MESH");
    boxTitles[S_MESH] = boxTitle;
    meshText = boxText("");
    boxTexts[S_MESH] = meshText;
    setupContent(S_MESH);
    slider("meshSpacing", "point spacing  (pixels)", 3, 40, 10).setDecimalPrecision(0);
    slider("meshStrength", "edge strength  (fewer points)", 0, 100, 20).setDecimalPrecision(0);
    slider("meshFill", "points in flat places", 0, 1, 0.3);
    row(24);
    toggle("meshOutline", "points along the outline  (SETUP 3: face or objects)", false, 0);
    slider("meshEdgePoints", "points on the edges", 0, 4000, 800).setDecimalPrecision(0);
    onlyWhen("meshEdges");
    slider("meshJoin", "join similar neighbours", 0, 40, 0).setDecimalPrecision(1);
    row(6);
    live = true;

    // SETUP 5, PALETTE GEN (the Palette Gen tab): a palette of 24 colours on a colour scheme.
    // Opening it the first time makes one, and shows the masses in its colours. Choosing a scheme
    // or GENERATE makes a new palette; the "whole palette" sliders change every colour, and the
    // "chosen colours" ones the swatches clicked
    setupStart(S_PAL);
    paletteBox = setupBox("SETUP 5   PALETTE GEN");
    boxTitles[S_PAL] = boxTitle;
    paletteText = boxText("");
    boxTexts[S_PAL] = paletteText;
    setupContent(S_PAL);
    radio("paletteScheme", schemeNames, 2, 0);
    row(32);
    button("paletteGenerate", "GENERATE", 0, 100);
    row(PAL_H * ((PALETTE_SIZE + PAL_COLS - 1) / PAL_COLS) + 6);
    paletteGrid = cur;
    row(20);
    label("whole palette", 0);
    slider("paletteHue", "hue  (degrees)", -180, 180, 0).setDecimalPrecision(0);
    slider("paletteSat", "saturation", 0, 2, 1);
    slider("paletteBri", "brightness", 0, 2, 1);
    row(20);
    label("chosen colours  (click the swatches)", 0);
    slider("paletteHueC", "hue  (degrees)", -180, 180, 0).setDecimalPrecision(0);
    slider("paletteSatC", "saturation", 0, 2, 1);
    slider("paletteBriC", "brightness", 0, 2, 1);
    row(32);
    button("paletteAll", "ALL", 0, 50);
    button("paletteNone", "NONE", 56, 60);
    button("paletteResetPicked", "RESET CHOSEN", 122, 112);
    button("paletteResetAll", "RESET ALL", 240, 80);
    // there's always a second masses picture in the palette's colours (VIEW's "masses (palette)")
    slider("paletteKeepLight", "keep the masses' lightness", 0, 1, 0.5);
    row(2);

    setupStart(S_COUNT);
    inSetup = false;
    // each box's title and line show unless a box above it is open; the rest only while it's open
    ArrayList<Row> col1 = columns.get(columns.size() - 1);
    for (int k = 0; k < S_COUNT; k++) {
      for (int i = boxRowFrom[k]; i < boxRowFrom[k + 1]; i++) {
        Row r = col1.get(i);
        String w = i < boxContentFrom[k] ? "boxShown " + k : "boxOpen " + k;
        r.when = r.when.equals("") ? w : r.when + "&" + w;
      }
    }

    // ---------------------------------------------------- along the bottom: VIEW and RUN
    // VIEW, under column 1 at the very bottom (hidden while a SETUP box is open over it): two
    // columns, each its own blue (drawn in draw()) - MAPS (the painting, or a map in place of it)
    // and LAYERS (which parts of the painting show, and the outline and the direction field)
    viewColumn = bottomColumn(0, -1);
    inView = true;                       // (AUTOMATION isn't greyed out either)
    // AUTOMATION (the Automation tab), above VIEW in column 1 (if the setup boxes don't leave room for
    // its sliders, they're folded away: see layout()). At the top the painting speed (how fast it
    // paints - the window and the panel keep going at full speed). Then the chosen tool's size (or
    // length) moved up and down by a sine wave while it paints, between its shortest and longest -
    // each tool has its own; only the chosen one's shows, with an on / off box like the tools' (red
    // off, green on). Last NUDGE, which moves every slider that can change while running a random bit
    header("AUTOMATION");
    autoSection = sections - 1;
    paceSlider = slider("pace", "painting speed", 0, 1, 1);
    for (int i = 0; i <= T_SCRAPE; i++) {
      String n = TOOLS[i];
      String what = AUTO_TARGET[i].equals("length") ? "length" : AUTO_TARGET[i].equals("width") ? "width" : "size";
      String lo = what.equals("length") ? "shortest" : what.equals("width") ? "thinnest" : "smallest";
      String hi = what.equals("length") ? "longest" : what.equals("width") ? "thickest" : "largest";
      row(31);
      Toggle on = cp5.addToggle(n + "_autoOn").setSize(20, 20).setValue(false);
      on.setColorBackground(toolOff).setColorForeground(toolOffHover).setColorActive(toolOn);
      on.setCaptionLabel(toolTitles[i].toLowerCase() + "  (" + what + " follows a wave)");
      on.getCaptionLabel().align(ControlP5.RIGHT_OUTSIDE, ControlP5.CENTER).setPaddingX(8);
      register(n + "_autoOn", on);
      put(on, 0, 6);
      onlyWhen("edit " + n + "&notErase");
      Slider a = slider(n + "_autoMin", lo, AUTO_LIMITS[i][0], AUTO_LIMITS[i][1], AUTO_DEFAULT[i][0]);
      onlyWhen("edit " + n + "&autoOn");
      Slider b = slider(n + "_autoMax", hi, AUTO_LIMITS[i][0], AUTO_LIMITS[i][1], AUTO_DEFAULT[i][1]);
      onlyWhen("edit " + n + "&autoOn");
      if (!what.equals("width")) {
        a.setDecimalPrecision(0);
        b.setDecimalPrecision(0);
      }
      slider(n + "_autoSpeed", "speed  (waves a second)", 0.01, 3, 0.25);
      onlyWhen("edit " + n + "&autoOn");
    }
    // the wave, with where it is now (drawn in drawAutoWave())
    row(30);
    autoWave = cur;
    for (Row ar : columns.get(columns.size() - 1)) ar.autoSetting = ar.when.endsWith("autoOn");
    onlyWhen("autoOn");
    row(32);
    button("nudge", "NUDGE", 0, 66);
    sliderAt("nudgeAmount", "how far", 0, 1, 0.2, 76, 5, 100);
    row(6);

    header("VIEW");
    viewSection = sections - 1;
    inView = true;
    row(VIEW_TOP + 284);
    layerRow = cur;
    label("MAPS", 2);
    label("LAYERS", 160);
    for (int k = 0; k < 2; k++) cur.dy.set(k, 6);
    // three groups: PAINTING, with a box like the tools' (green while it's showing, red while a map
    // is); what the map maker made; and the masses and the mesh
    RadioButton r = cp5.addRadioButton("showWhat").setSize(16, 16).setItemsPerRow(1).setSpacingRow(6);
    for (int i = 0; i < showNames.length; i++) {
      r.addItem("showWhat " + i, i);
      r.getItem(i).setCaptionLabel(i == VIEW_PAINTING ? "PAINTING" : showNames[i]);
    }
    // (once they're all there: each one added lays them all out again)
    for (int i = 0; i < showNames.length; i++) {
      r.getItem(i).setPosition(i == VIEW_PAINTING ? 0 : 2, i == VIEW_PAINTING ? 0 : i < VIEW_MASSES ? 14 + 22 * i : 28 + 22 * i);
    }
    Toggle pt = r.getItem(VIEW_PAINTING);
    pt.setSize(20, 20).setColorBackground(toolOff).setColorForeground(toolOffHover).setColorActive(toolOn);
    pt.getCaptionLabel().setPaddingX(8);
    r.activate(VIEW_PAINTING);
    r.setNoneSelectedAllowed(false);
    register("showWhat", r);
    put(r, 2, VIEW_TOP);
    // (an empty layer's box is white, and the one the tool that's on paints on has a green frame)
    // the stack, top first, as in Photoshop: the seven layers, which can be hidden and moved up
    // and down (layerOrder, the Layers tab). A layer's tick box moves to its place in draw(); the
    // up / down buttons stay put
    for (int i = 0; i < LAYERS; i++) {
      toggle("layerOn" + i, "layer " + LAYER_NAMES[i], true, 160);
      layerItem[i] = cur.items.size() - 1;
    }
    for (int k = 0; k < LAYERS; k++) {
      int pos = LAYERS - 1 - k;                  // the place in the stack shown on line k
      if (k > 0) moveButton("layerUp" + pos, "^", 258, VIEW_TOP + 22 * k);
      if (k < LAYERS - 1) moveButton("layerDown" + pos, "v", 286, VIEW_TOP + 22 * k);
    }
    // under the stack: SETUP 3's outline in red over whatever's showing (the painting or a map),
    // and the direction field (the Field tab) over it, and how smooth that is
    float under = VIEW_TOP + 22 * LAYERS + 30;
    toggle("viewOutline", "outline  (SETUP 3)", false, 160);
    cur.dy.set(cur.dy.size() - 1, under);
    toggle("fieldOverlay", "direction field", false, 160);
    cur.dy.set(cur.dy.size() - 1, under + 26);
    Slider sm = sliderAt("smoothing", "smoothing", 0, 24, 4, 160, under + 50, 84);
    sm.setNumberOfTickMarks(13).snapToTickMarks(true).showTickMarks(false);
    sm.setTriggerEvent(Slider.RELEASE);          // rebuilding the field takes a moment - only on letting go
    row(4);
    inView = false;
    for (Row vr : columns.get(columns.size() - 1)) vr.when = vr.when.equals("") ? "noSetupOpen" : vr.when + "&noSetupOpen";

    // RUN: at the very bottom of column 2, so no box above can grow over it. Two rows: RUN (STOP while
    // it runs) and PAUSE (CARRY ON while paused); then STEP, which paints one step at a time while
    // paused, SAVE and LOAD SETTINGS. (The painting speed is at the top of AUTOMATION.)
    bottomColumn(1, -1);
    sections++;
    runSection = sections - 1;
    row(34);
    Textlabel runTitle = cp5.addTextlabel("header RUN").setText("RUN").setColorValue(color(20));
    put(runTitle, -4, 14);
    runButton = button("runStop", "RUN", 40, 76);
    pauseButton = button("pauseRun", "PAUSE", 122, 90);
    for (int k = 1; k < cur.items.size(); k++) cur.dy.set(k, 6);
    row(34);
    stepButton = button("stepRun", "STEP", 40, 60);
    button("saveNow", "SAVE", 106, 66);
    button("loadSettings", "LOAD SETTINGS", 178, 124);
    for (int k = 0; k < cur.items.size(); k++) cur.dy.set(k, 2);

    // ---------------------------------------------------- column 2: the tools
    // Each tool's box: switched on or off (only one at a time), and - while it's on - its shape
    // settings
    column();
    // COPY (the Copy tab): a map and a layer. (The button that lays the one on the other is in MOVEMENT)
    toolBox(T_COPY, false);
    row(20);
    label("map", 0);
    onlyWhen("on copy");
    radio("copyWhat", java.util.Arrays.copyOfRange(showNames, VIEW_PHOTO, showNames.length), 2, 0);
    onlyWhen("on copy");
    // (in VIEW's two groups, side by side)
    for (int i = 0; i < showNames.length - 1; i++) {
      ((RadioButton) all.get("copyWhat")).getItem(i).setPosition(i / 5 * 150, i % 5 * 22);
    }
    // (the grey maps: in shades of one colour)
    row(24);
    toggle("copyTint", "tint the grey", false, 0);
    onlyWhen("on copy&copyGrey");
    colourPicker("copyInk", "the colour", color(40, 90, 150));
    onlyWhen("on copy&copyGrey&copyTint");

    toolBox(8, false);
    radio("scrape_kind", scrapeNames, 3, 0);
    onlyWhen("on scrape");
    toolSlider("rate", "scrapes per frame", 0.05, 20, 1);
    onlyWhen("on scrape&notErase");
    toolSlider("length", "length", 10, 500, 140).setDecimalPrecision(0);
    onlyWhen("on scrape&notErase");
    toolSlider("width", "width", 2, 150, 40).setDecimalPrecision(0);
    onlyWhen("on scrape&notErase");
    toolSlider("ragged", "ragged edges", 0, 1, 0.5);
    onlyWhen("on scrape&notErase");
    toolSlider("strength", "how much comes off", 0, 1, 0.8);
    onlyWhen("on scrape&notErase");
    // erase: all that's in IN AREA's area, at once (Scrape tab, eraseArea), by MOVEMENT's button

    toolBox(0, false);
    toolSlider("perFrame", "marks per frame", 1, 400, 20).setDecimalPrecision(0);
    toolSlider("size", "size (pixels, longest)", 4, 400, 110).setDecimalPrecision(0);
    toolModRow("size", 1, 0.8, true);
    toolSlider("width", "width (share of length)", 0.05, 1, 0.35);
    toolSlider("ragged", "ragged edges", 0, 1, 0.5);
    toolSlider("taper", "pointed end", 0, 1, 1);
    toolSlider("curving", "bend along the form", 0, 1, 0.5);

    toolBox(1, false);
    toolSlider("perFrame", "marks per frame", 1, 400, 20).setDecimalPrecision(0);
    toolSlider("size", "size (pixels, longest)", 4, 400, 110).setDecimalPrecision(0);
    toolModRow("size", 1, 0.8, true);
    toolSlider("width", "width (share of length)", 0.05, 1, 0.35);
    toolSlider("ragged", "ragged edges", 0, 1, 0.5);
    toolSlider("streaks", "streaks of a second colour", 0, 1, 0.4);
    onlyWhen("on knife&knifeFlat");
    toolSlider("leaf", "leaf shapes", 0, 1, 0.35);
    toolSlider("ridge", "ridge along the edge", 0, 1, 0.5);

    // the sponge (the Sponge tab): the chunk, and how it's dabbed
    toolBox(7, false);
    toolSlider("rate", "stamps per frame", 0.05, 20, 2);
    // its size: one picked from this range - kept, or a new one every dip
    range("sponge_sizeRange", "size range  (pixels across)", 10, 300, 50, 90);
    onlyWhen("on sponge");
    // or where in the range by a map at the dip: dark the small end, light the big end
    toolModRow("size", 0, 1, false);
    row(24);
    toggle("sponge_sizeEachDip", "a new size each dip", false, 0);
    onlyWhen("on sponge");
    toolSlider("ragged", "torn edges", 0, 1, 0.5);
    toolSlider("pores", "pore size", 1, 12, 3);
    toolSlider("open", "how open  (holes even when full)", 0, 1, 0.4);
    toolSlider("load", "picks up  (% of the picture)", 10, 100, 85).setDecimalPrecision(0);
    toolSlider("smear", "smearing  (each stamp)", 0, 8, 2);
    toolSlider("loss", "paint lost each stamp  (%)", 1, 80, 20).setDecimalPrecision(0);
    toolSlider("stamps", "stamps per dip", 1, 40, 8).setDecimalPrecision(0);
    toolSlider("step", "distance between stamps", 0, 3, 0.7);
    toolSlider("turn", "rotation  (degrees either way)", 0, 180, 180).setDecimalPrecision(0);
    row(24);
    toggle("sponge_fresh", "a new chunk each dip", false, 0);
    onlyWhen("on sponge");
    // copy: every stamp prints the picture right under it (COLOUR's "pick up from"), not paint carried
    row(24);
    toggle("sponge_copy", "copy  (each stamp prints the picture under it)", false, 0);
    onlyWhen("on sponge");

    // the splatter: what its drops are - any mix of round splatter drops, dots, dashes and
    // triangles - then the cluster settings they all share
    toolBox(2, false);
    row(26);
    toggle("splat_kSplat", "splatter", true, 0);
    toggle("splat_kDots", "dots", false, 84);
    toggle("splat_kDashes", "dashes", false, 150);
    toggle("splat_kTris", "triangles", false, 230);
    onlyWhen("on splat");
    toolSlider("rate", "clusters per frame", 0.05, 10, 0.5);
    toolSlider("drops", "drops per cluster", 0, 200, 40).setDecimalPrecision(0);
    toolSlider("size", "size (biggest splat)", 2, 120, 24).setDecimalPrecision(0);
    onlyWhen("on splat&splatFree");
    // (IN AREA's Tri Centers and Vertices: how big a drop is beside its triangle)
    toolSlider("triSize", "size  (1 = fits its tri)", 0.1, 4, 1);
    onlyWhen("on splat&splatSites");
    toolSlider("big", "how many big drops", 0, 1, 0.3);
    onlyWhen("on splat&splatFree");
    toolSlider("scatter", "scatter", 5, 400, 60).setDecimalPrecision(0);
    toolSlider("trails", "flung trails", 0, 1, 0.3);
    onlyWhen("on splat&splatFree");
    toolSlider("vary", "drop colour variation", 0, 0.5, 0.1);
    onlyWhen("on splat&splatFlat");
    toolSlider("drip", "drips", 0, 1, 0);
    toolSlider("dripLength", "drip length", 10, 400, 120).setDecimalPrecision(0);

    // lines (the Lines tab): wandering lines, or a line along the light map's darkest creases (the Creases tab)
    toolBox(3, false);
    radio("line_kind", new String[] { "wandering", "darkest creases" }, 2, 0);
    onlyWhen("on line");
    toolSlider("rate", "lines per frame", 0.05, 20, 1);
    toolSlider("length", "length", 10, 800, 200).setDecimalPrecision(0);
    toolSlider("width", "width", 0.3, 8, 1.2);
    toolSlider("wander", "wander", 0, 1, 0.4);
    onlyWhen("on line&lineWander");
    toolSlider("broken", "broken", 0, 1, 0.2);
    onlyWhen("on line&lineWander");
    toolSlider("darkest", "darkest  (% of light map)", 0.5, 15, 4);
    onlyWhen("on line&lineCreases");
    toolSlider("lift", "lift it between parts", 0, 1, 0);
    onlyWhen("on line&lineCreases");

    // the pencil (the Pencil tab): how it steers, on which map, and the hand
    toolBox(4, false);
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

    // flow (the Flow tab): postContemp's continuous flow - which picture steers it, and the line
    toolBox(5, false);
    row(28);
    label("steered by", 0);
    list("flow_src", flowSources, 0, 70, 120);
    onlyWhen("on flow");
    radio("flow_channel", flowChannels, 3, 0);
    onlyWhen("on flow&flowColour");
    toolSlider("smooth", "smoothing", 0, 30, 2).setDecimalPrecision(0);
    toolSlider("turn", "turn the flow  (degrees)", 0, 360, 0).setDecimalPrecision(0);
    toolSlider("steer", "how hard it turns", 0, 1, 0.4);
    toolSlider("count", "lines at once", 1, 40, 4).setDecimalPrecision(0);
    toolSlider("speed", "speed  (pixels a frame)", 2, 120, 30).setDecimalPrecision(0);
    toolSlider("length", "line length", 10, 1000, 300).setDecimalPrecision(0);
    toolSlider("width", "width", 0.3, 20, 2);
    toolSlider("pressure", "width changes", 0, 1, 0.3);
    row(24);
    toggle("flow_along", "colour changes along the line", true, 0);
    onlyWhen("on flow");
    toolSlider("every", "pixels till a new colour", 2, 500, 24).setDecimalPrecision(0);
    onlyWhen("on flow&along flow");
    toolSlider("blendOver", "blend  (0: at once)", 0, 1, 1);
    onlyWhen("on flow&along flow");

    // outline (the Outline tab): the face in one line - which parts it takes in, and the pen
    // (what it traces, and how smooth, are in SETUP 3)
    toolBox(6, false);
    row(20);
    label("the line itself: SETUP 3  OUTLINE", 0);
    onlyWhen("on outline");
    toolSlider("speed", "speed  (pixels a frame)", 2, 200, 20).setDecimalPrecision(0);
    toolSlider("passes", "passes", 1, 6, 1).setDecimalPrecision(0);
    toolSlider("wobble", "wobble", 0, 1, 0.3);
    toolSlider("width", "width", 0.3, 12, 2);
    toolSlider("pressure", "pressure changes", 0, 1, 0.5);
    row(24);
    toggle("outline_loop", "start again when done", false, 0);
    toggle("outline_join", "one unbroken line", false, 180);
    onlyWhen("on outline");
    row(24);
    toggle("outline_along", "colour changes along the line", false, 0);
    onlyWhen("on outline");
    toolSlider("every", "pixels till a new colour", 2, 500, 24).setDecimalPrecision(0);
    onlyWhen("on outline&along outline");
    toolSlider("blendOver", "blend  (0: at once)", 0, 1, 1);
    onlyWhen("on outline&along outline");

    // RECOLOUR (the Recolour tab), along the bottom of column 2, above RUN (if a tool's settings don't leave
    // room for it, they're folded away meanwhile: see layout()): one layer at a time - READ COLOURS divides its
    // paint into 40 colours; click swatches to choose them, and the sliders change those. Its title
    // line has a box like the tools' (red shut, green open)
    bottomColumn(1, -1);
    colBottom.set(colBottom.size() - 1, 2);
    // LIGHT, above RECOLOUR (in the same column along the bottom of column 2). Each layer has a light of
    // its own: where it's from and how high, which casts that layer's shadow and lights its edges (the
    // Layers tab's composite), and the shadow's colour - the layer buttons choose whose show. The thick
    // paint has one light for all of it, as its heights are combined first (the Impasto tab - how thick
    // each tool's paint is is in its APPLY). Its title line has a box like RECOLOUR's (red shut, green open)
    sections++;
    lightSection = sections - 1;
    row(31);
    Toggle lo = cp5.addToggle("lightOpen").setSize(20, 20).setValue(false);
    lo.setColorBackground(toolOff).setColorForeground(toolOffHover).setColorActive(toolOn);
    lo.setCaptionLabel("LIGHT");
    lo.getCaptionLabel().align(ControlP5.RIGHT_OUTSIDE, ControlP5.CENTER).setPaddingX(8);
    register("lightOpen", lo);
    put(lo, 0, 6);
    row(26);
    label("layer", 0);
    radioAt("lightLayer", LAYER_NAMES, 0, 60, 36);
    onlyWhen("light");
    for (int i = 0; i < LAYERS; i++) {
      slider("lightFrom" + i, "from  (90 = above)", 0, 360, 135).setDecimalPrecision(0);
      onlyWhen("light&lightLayer " + i);
      slider("lightHeight" + i, "height", 10, 80, 35).setDecimalPrecision(0);
      onlyWhen("light&lightLayer " + i);
      colourPicker("shadowColour" + i, "its shadow's colour", color(0));
      onlyWhen("light&lightLayer " + i);
    }
    row(20);
    label("THICK PAINT  (all the layers)", 0);
    onlyWhen("light");
    slider("lightFrom", "from  (90 = above)", 0, 360, 135).setDecimalPrecision(0);
    onlyWhen("light");
    slider("lightHeight", "height", 10, 80, 35).setDecimalPrecision(0);
    onlyWhen("light");
    slider("lightShine", "shine", 0, 1, 0.3);
    onlyWhen("light");
    row(6);
    onlyWhen("light");

    sections++;
    recolourSection = sections - 1;
    row(31);
    Toggle ro = cp5.addToggle("recolourOpen").setSize(20, 20).setValue(false);
    ro.setColorBackground(toolOff).setColorForeground(toolOffHover).setColorActive(toolOn);
    ro.setCaptionLabel("RECOLOUR");
    ro.getCaptionLabel().align(ControlP5.RIGHT_OUTSIDE, ControlP5.CENTER).setPaddingX(8);
    register("recolourOpen", ro);
    put(ro, 0, 6);
    toggle("recolourOn", "on", true, 240);
    cur.dy.set(cur.dy.size() - 1, 8);
    cur.itemWhen.set(cur.itemWhen.size() - 1, "recolour&recolourLayers");
    // (on the masses or the mesh: the output window shows the palette without its changes)
    toggle("recolourAsMade", "as generated", false, 180);
    cur.dy.set(cur.dy.size() - 1, 8);
    cur.itemWhen.set(cur.itemWhen.size() - 1, "recolourPal");
    row(6);
    onlyWhen("recolour");
    row(48);
    label("layer", 0);
    radioAt("recolourLayer", concat(LAYER_NAMES, new String[] { "masses", "mesh" }), 0, 60, 36);
    RadioButton rl = (RadioButton) all.get("recolourLayer");
    rl.getItem(LAYERS).setPosition(0, 24);          // the palette's two on a line of their own
    rl.getItem(LAYERS + 1).setPosition(88, 24);
    Textlabel rp = cp5.addTextlabel("recolourPalLabel").setText("palette").setColorValue(dark);
    put(rp, -4, 26);
    onlyWhen("recolour");
    row(32);
    button("recolourNew", "READ COLOURS", 0, 100);
    cur.itemWhen.set(cur.itemWhen.size() - 1, "recolourLayers");
    button("recolourRandom", "RANDOM NUDGE", 106, 110);
    recolourText = cp5.addTextlabel("recolourText").setText("").setColorValue(dark);
    put(recolourText, 222, 6);
    onlyWhen("recolour");
    row(SWATCH_H * ((RECOLOURS + SWATCH_COLS - 1) / SWATCH_COLS) + 6);
    recolourGrid = cur;
    onlyWhen("recolour&recolourLayers");
    row(SWATCH_H * ((PALETTE_SIZE + SWATCH_PAL_COLS - 1) / SWATCH_PAL_COLS) + 6);
    recolourPalGrid = cur;
    onlyWhen("recolour&recolourPal");
    slider("recolourHue", "hue  (degrees)", -180, 180, 0).setDecimalPrecision(0);
    onlyWhen("recolour");
    slider("recolourSat", "saturation", 0, 2, 1);
    onlyWhen("recolour");
    slider("recolourBri", "brightness", 0, 2, 1);
    onlyWhen("recolour");
    slider("recolourReach", "reach  (how far it spreads)", 0.02, 0.3, 0.08);
    onlyWhen("recolour&recolourLayers");
    row(32);
    button("recolourAll", "ALL", 0, 50);
    button("recolourNone", "NONE", 56, 60);
    button("recolourResetPicked", "RESET CHOSEN", 122, 112);
    button("recolourResetAll", "RESET ALL", 240, 80);
    onlyWhen("recolour");
    row(4);

    // ---------------------------------------------------- column 3: APPLY, MOVEMENT, COLOUR
    // ... of the tool chosen in column 2. Every tool has its own set; only the chosen one's shows
    column();
    // APPLY first, in two steps: ON LAYER, which layer the tool paints on, and IN AREA, where on it
    // (on a slightly darker strip). Both have to be done before its MOVEMENT and COLOUR show, and it
    // doesn't paint till they are. With IN AREA's All, the box then closes to one line saying which layer
    // and area; with the others it stays open to choose the colours or pieces, and its title (or the PICK
    // button) closes it. Clicking its title opens it again, over the others (see applyShut()). SCRAPE and COPY only
    // have the layer in ON LAYER - the one paint comes off, or the map goes on
    applyHeader = header("APPLY");
    cur.dx.set(0, 20);                   // room for the square before it (drawn in draw())
    applySection = sections - 1;
    float[] opacityDefault = { 0.9, 0.9, 0.9, 0.8, 0.9, 0.9, 0.95, 0.9 };
    float[] washesDefault = { 0.15, 0.15, 0, 0, 0, 0, 0, 0 };
    float[] thicknessDefault = { 0.5, 0.6, 0.5, 0.1, 0, 0.2, 0, 0.4 };
    for (int i = 0; i < TOOLS.length; i++) {
      String n = TOOLS[i], when = "edit " + n + "&applyOpen";
      row(24);
      label("ON LAYER", 0);
      radioAt(n + "_layer", LAYER_NAMES, -1, 90, 33);
      onlyWhen(when);
      closesApply(n + "_layer");
      if (i >= PAINT_TOOLS) continue;
      slider(n + "_opacity", "opacity", 0, 1, opacityDefault[i]);
      onlyWhen(when);
      modRow(n + "_opacity", 0, 0.5, false);
      onlyWhen(when);
      slider(n + "_washes", "see-through washes", 0, 1, washesDefault[i]);
      onlyWhen(when);
      slider(n + "_thickness", "thickness  (impasto)", 0, 1, thicknessDefault[i]);
      onlyWhen(when);
      row(28);
      label("blend", 0);
      list(n + "_blend", blendNames, 0, 50, 140);
      onlyWhen(when);
    }
    // IN AREA (the Area tab): each tool's choice, and the colours' own settings - the colours
    // themselves are shared by every tool, chosen in the strip or on the masses (or the mesh)
    curBand = 2;
    row(24);
    label("IN AREA", 0);
    cur.dy.set(0, 6);
    onlyWhen("applyOpen");
    for (int i = 0; i < TOOLS.length; i++) {
      String n = TOOLS[i], when = "edit " + n + "&applyOpen";
      // (Tri Centers and Vertices are only the splatter's)
      int choices = n.equals("splat") ? inAreaNames.length : AREA_TRI_CENTERS;
      radio(n + "_inArea", java.util.Arrays.copyOf(inAreaNames, choices), 3, -1);
      cur.h += 22;
      onlyWhen(when);
      RadioButton a = (RadioButton) all.get(n + "_inArea");
      for (int k = 0; k < choices; k++) {
        a.getItem(k).setPosition(k == 0 ? 0 : k % 2 == 1 ? 70 : 190, max(0, (k - 1) / 2) * 22);
      }
      closesApply(n + "_inArea");
      row(24);
      radioAt(n + "_areaSide", new String[] { "in the area", "outside it" }, 0, 0, 88);
      toggle(n + "_areaClip", "clip at its edge  (slow)", true, 170);
      cur.dy.set(cur.dy.size() - 1, 2);
      cur.itemWhen.set(cur.itemWhen.size() - 1, "makesMarks");      // (erase and COPY always stop at the edge)
      onlyWhen(when + "&areaUsed");
    }
    // the zone (the Zone tab): two maps in levels, the second on top - which levels of each show, and how
    // see-through each is. One zone, for every tool; here with IN AREA's Zone, or START AT's "in zone"
    row(22);
    label("THE ZONE  -  two maps in 24 greys, the second on top", 0);
    onlyWhen("applyOpen&zoneShown");
    for (int k = 0; k < 2; k++) {
      String z = k == 0 ? "zoneA" : "zoneB";
      row(24);
      label(k == 0 ? "map 1" : "map 2", 0);
      list(k == 0 ? "zoneMapA" : "zoneMapB", zoneMapNames, k == 0 ? 2 : 3, 60, 130);
      onlyWhen("applyOpen&zoneShown");
      range(z + "Levels", "levels shown", 0, ZONE_LEVELS - 1, 0, ZONE_LEVELS - 1);
      onlyWhen("applyOpen&zoneShown");
      slider(z + "Clear", "transparency", 0, 1, k == 0 ? 0 : 0.4);
      onlyWhen("applyOpen&zoneShown");
    }
    // expand: the levels left in the zone spread over 1 .. 24, gaps and all (COLOUR's carry "expand" uses them)
    row(24);
    toggle("zoneExpand", "expand  (the levels left, spread over 1 .. 24)", false, 0);
    onlyWhen("applyOpen&zoneShown");
    row(22);
    zoneText = cp5.addTextlabel("zoneText").setText("").setColorValue(dark);
    put(zoneText, -4, 2);
    onlyWhen("applyOpen&zoneShown");
    row(20);
    label("in these colours", 0);
    onlyWhen("applyOpen&areaColours");
    row(2 * STRIP_H + 4);
    areaStrip = cur;
    onlyWhen("applyOpen&areaColours");
    // (Masses, Tris, Objects, Face Parts: the ones clicked in the output window - the Picks tab)
    row(26);
    patchText = cp5.addTextlabel("patchText").setText("").setColorValue(dark);
    put(patchText, -4, 4);
    onlyWhen("applyOpen&areaPatches");
    row(36);
    partsText1 = cp5.addTextlabel("partsText1").setText("").setColorValue(dark);
    put(partsText1, -4, 0);
    partsText2 = cp5.addTextlabel("partsText2").setText("").setColorValue(dark);
    put(partsText2, -4, 16);
    onlyWhen("applyOpen&areaParts");
    row(34);
    areaPickButton = button("areaPickMasses", "PICK ON THE MASSES", 0, 222);
    button("areaClear", "CLEAR", 230, 80);
    onlyWhen("applyOpen&areaPickable");
    curBand = 0;
    row(5);
    onlyWhen("applyOpen");
    int applyRows = columns.get(columns.size() - 1).size();

    float[] followDefault = { 0.6, 0.6, 0, 0.5, 0.3, 0, 0, 0, 0.5 };
    moveHeader = header("MOVEMENT");
    moveSection = sections - 1;
    onlyWhen("hasMove");
    // clicking its title folds it to that and a line saying what's chosen, or opens it again
    row(24);
    moveText = cp5.addTextlabel("moveText").setText("").setColorValue(dark);
    put(moveText, -4, 2);
    onlyWhen("hasMove&makesMarks&moveFolded");
    // COPY and SCRAPE's erase do the whole area at once: all they have here is the button that does it
    row(34);
    button("copyMap", "COPY", 0, 76);
    copyText = cp5.addTextlabel("copyText").setText("").setColorValue(dark);
    put(copyText, 82, 6);
    onlyWhen("on copy");
    row(34);
    button("scrapeEraseNow", "ERASE", 0, 76);
    eraseText = cp5.addTextlabel("eraseText").setText("").setColorValue(dark);
    put(eraseText, 82, 6);
    onlyWhen("on scrape&erase");
    // ... and, with an area, how wide the fade at its border is, and which side of it
    for (String n : new String[] { "copy", "scrape" }) {
      String when = n.equals("copy") ? "on copy&areaUsed" : "on scrape&erase&areaUsed";
      row(20);
      label("fade at the area's border", 0);
      onlyWhen(when);
      slider(n + "_edgeFade", "", -FADE_MOST, FADE_MOST, -10).setDecimalPrecision(0).setSliderMode(Slider.FLEXIBLE).setHandleSize(8);
      onlyWhen(when);
      row(20);
      label("inside", 0);
      label("none", 70);
      label("outside", 126);
      onlyWhen(when);
    }
    int moveRows = columns.get(columns.size() - 1).size();
    // its two parts - which way marks go, and where they start - each on a slightly different shade of the box's colour (Row's band, drawn in drawBands)
    for (int i = 0; i <= T_SCRAPE; i++) {
      String n = TOOLS[i];
      if (n.equals("outline")) continue;       // it goes where the face is
      curBand = 1;
      if (!n.equals("splat") && !n.equals("flow") && !n.equals("sponge")) {
        // (LINES' darkest creases go where the creases do)
        String steers = "edit " + n + (n.equals("line") ? "&lineWander" : "");
        slider(n + "_follow", "follow the form", 0, 1, followDefault[i]);
        onlyWhen(steers);
        if (i <= 1) {
          modRow(n + "_follow", 0, 0.5, false);
          onlyWhen(steers);
        }
        radio(n + "_around", new String[] { "around the form", "across it", "along the outline" }, 2, 0);
        onlyWhen(steers);
      }
      curBand = 2;
      row(20);
      label("START AT", 0);
      onlyWhen("edit " + n);
      // vertex / tri: a corner or the middle of a triangle of the mesh (SETUP 4); blob: the middle
      // of one of the masses (SETUP 2) - each one as likely as any other (Marks tab)
      radio(n + "_startAt", new String[] { "random", "weighted by map", "grid", "mouse (2D, hold button)",
        "on the outline  (SETUP 3)", "at vertex  (mesh)", "at tri  (mesh)", "at blob  (masses)", "in zone  (set in APPLY)" }, 2, 0);
      onlyWhen("edit " + n);
      // the grid: one pass from the top left, started again by RUN and CARRY ON
      slider(n + "_gridSize", "grid spacing  (x the usual)", 0.2, 5, 1);
      onlyWhen("edit " + n + "&grid " + n);
      row(28);
      label("map", 12);
      list(n + "_startMap", mapNames, 1, 50, 120);
      toggle(n + "_startInv", "invert", false, 182);
      onlyWhen("edit " + n + "&weighted " + n);
      slider(n + "_spread", "spread round the mouse", 0, 300, 60).setDecimalPrecision(0);
      onlyWhen("edit " + n + "&mouse " + n);
    }
    ArrayList<Row> moveCol = columns.get(columns.size() - 1);
    for (int i = moveRows; i < moveCol.size(); i++) moveCol.get(i).when += "&makesMarks&moveOpen";
    curBand = 0;
    row(6);
    onlyWhen("hasMove");

    colourHeader = header("COLOUR");
    onlyWhen("hasColour");
    float[] contrastDefault = { 0, 0, 0.5, 0.6, 0.55, 0, 0.9, 0 };
    for (int i = 0; i < PAINT_TOOLS; i++) {
      String n = TOOLS[i];
      // flow and outline can draw in one colour of your own instead
      if (n.equals("flow") || n.equals("outline")) {
        row(24);
        toggle(n + "_one", "one colour", false, 0);
        onlyWhen("edit " + n);
        colourPicker(n + "_ink", "the colour", color(35, 30, 28));
        onlyWhen("edit " + n + "&one " + n);
      }
      row(20);
      label("pick up from", 0);
      onlyWhen("edit " + n);
      radio(n + "_pickup", new String[] { "photo", "canvas (wet)", "mix", "masses", "random  (accent ranges)", "palette  (SETUP 5)", "mesh", "mesh  (palette)" }, 2, 0);
      onlyWhen("edit " + n);
      // (palette: the palette colour of the mass under the point, exactly - the Palette Gen tab;
      // mesh (palette): of the mesh's shape under it - the Mesh tab)
      slider(n + "_mix", "mix: share from the canvas", 0, 1, 0.5);
      onlyWhen("edit " + n + "&mix " + n);
      if (i <= 2) {
        row(20);
        label("carry", 0);
        onlyWhen("edit " + n);
        radio(n + "_carry", new String[] { "one colour", "start to end", "two colours", "chunk", "copy", "expChunk  (zone)", "expTwo  (zone)" }, 3, n.equals("splat") ? 0 : 1);
        onlyWhen("edit " + n);
      }
      if (n.equals("splat")) {
        // a cluster's paint from one spot, the cluster at another (the Splatter tab)
        row(24);
        toggle("splat_elsewhere", "put it down somewhere else", true, 0);
        onlyWhen("edit splat");
      }
      if (i >= 2) {
        slider(n + "_contrast", "contrast with the photo", 0, 1, contrastDefault[i]);
        onlyWhen(n.equals("splat") ? "edit splat&splatFlat" : "edit " + n);
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
    // the accent colours: each accent is a new colour, picked at random between these limits
    row(20);
    label("accent colours  (all tools) - at random between", 0);
    onlyWhen("hasColour");
    row(12);
    accentBar = cur;
    onlyWhen("hasColour");
    range("accentHue", "hue  (degrees)", 0, 360, 0, 25);
    onlyWhen("hasColour");
    range("accentSat", "saturation  (%)", 0, 100, 70, 95);
    onlyWhen("hasColour");
    range("accentBri", "brightness  (%)", 0, 100, 60, 85);
    onlyWhen("hasColour");
    row(6);
    onlyWhen("hasColour");

    // MOVEMENT and COLOUR only show while APPLY is closed
    ArrayList<Row> col3 = columns.get(columns.size() - 1);
    for (int i = applyRows; i < col3.size(); i++) {
      Row cr = col3.get(i);
      cr.when = cr.when.equals("") ? "applyShut" : cr.when + "&applyShut";
    }

    // ---------------------------------------------------- column 4: LAYER 1 - 5, A, B, LIGHT
    column();

    // a box for each of the layers (the Layers tab), each its own red (LAYER_COLOURS):
    // CLEAR empties it; how see-through it is and how it's combined with the layers under it; how far
    // it floats above them (its gap - 0 is not at all), its shadow, softness and lit edges; and how
    // much its thick paint catches the light (impasto). (Whether each shows is in VIEW's LAYERS list;
    // which layer each tool paints on is in its APPLY)
    // (the boxes are kept tight so the column fits the window)
    for (int i = 0; i < LAYERS; i++) {
      layerSection[i] = layerHeader("LAYER " + LAYER_NAMES[i]);
      button("clearLayer" + i, "CLEAR", 240, 64).setHeight(18);
      cur.dy.set(cur.dy.size() - 1, 4);
      row(24);
      sliderAt("layerSeeThrough" + i, "transparency", 0, 1, 0, 0, 1, 100);
      list("layerBlend" + i, layerBlendNames, 0, 200, 110);
      row(34);
      boxSlider("layerGap" + i, "gap", 0, 60, 0, 0).setDecimalPrecision(0);
      boxSlider("boxShadow" + i, "shadow", 0, 1, 0.6, 80);
      boxSlider("boxSoftness" + i, "softness", 0, 1, 0.4, 160);
      boxSlider("boxRim" + i, "lit edges", 0, 1, 0, 240);
      slider("layerImpasto" + i, "impasto", 0, 1, 0.5);
      row(2);
    }

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
    for (int i = 0; i < layerSection.length; i++) blockColour[layerSection[i]] = LAYER_COLOURS[i];
    for (int i = 0; i < TOOLS.length; i++) blockColour[toolSection[i]] = TOOL_COLOURS[i];
    for (int s : new int[] { viewSection, autoSection, recolourSection, lightSection }) blockColour[s] = viewBase;
    layout();
    ready = true;
  }

  public void draw() {
    background(38);
    // (picking ends if VIEW is changed from what it's showing)
    if (picking != PICK_NONE && picking == pickingShown && value("showWhat") != pickMapShown) picking = PICK_NONE;
    if (picking != pickingShown || picking != PICK_NONE && pickMap() != pickMapShown) showPicking(picking);
    if (sourcesChanged) {
      sourcesChanged = false;
      ScrollableList l = (ScrollableList) all.get("source");
      String[] items = sourceItems();
      l.setItems(items);
      l.setSize(colW - 30, 20 * min(items.length, 24));
    }
    if (sourceWanted >= 0) {
      all.get("source").setValue(sourceWanted);
      sourceWanted = -1;
    }
    if (picked != null) {
      picked.close();
      picked = null;
      layoutWanted = true;
    }
    // each layer's tick box on its line in VIEW's LAYERS list, top of the stack first
    String order = join(str(layerOrder), " ");
    if (!order.equals(shownOrder)) {
      shownOrder = order;
      for (int i = 0; i < LAYERS; i++) layerRow.dy.set(layerItem[i], VIEW_TOP + 22 * (LAYERS - 1 - layerPosition(i)));
      layoutWanted = true;
    }
    if (layoutWanted) layout();
    // the coloured blocks behind the sections (the controls are drawn on top after this)
    noStroke();
    int[] boxSecs = boxSections();
    boolean[] setupDone = boxesDone();
    for (int i = 0; i < sections; i++) {
      if (block[i] == null) continue;
      int k = java.util.Arrays.asList(boxSecsList(boxSecs)).indexOf(i);
      fill(k >= 0 ? (setupDone[k] ? boxGreen : boxRed) : blockColour[i]);
      rect(block[i][0] - 8, block[i][1], colW - 12, block[i][2] - block[i][1], 8);
    }
    drawBands();
    // what's in AUTOMATION, RECOLOUR and LIGHT, on one of VIEW's blues
    for (int s : new int[] { autoSection, recolourSection, lightSection }) {
      float[] b = block[s];
      if (b == null || b[2] - b[1] < 40) continue;       // (only its title)
      fill(layersBlue);
      rect(b[0] - 4, b[1] + 28, 320, b[2] - b[1] - 28, 6);
    }
    // VIEW's two columns
    if (block[viewSection] != null && layerRow.y >= 0) {
      float vx = block[viewSection][0];
      fill(mapsBlue);
      rect(vx - 4, layerRow.y, 150, layerRow.h, 6);
      fill(layersBlue);
      rect(vx + 150, layerRow.y, 166, layerRow.h, 6);
    }
    // each setup box's square, before its title: red, then green once it's done
    for (int k = 0; k < S_COUNT; k++) {
      float[] b = block[boxSecs[k]];
      if (b == null) continue;
      fill(setupDone[k] ? doneGreen : notDoneRed);
      rect(b[0] - 1, b[1] + 9, 15, 15, 3);
    }
    float[] ab = block[applySection];
    if (ab != null) {
      fill(applyDone() ? doneGreen : notDoneRed);
      rect(ab[0] - 1, ab[1] + 9, 15, 15, 3);
    }
    drawSwatches();
    drawPaletteSwatches();
    drawStrip(areaStrip, areaPick);
    drawAccentBar();
    drawAutoWave();
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
      if (shownRunning) closeBox(false);       // the setup boxes can't be changed while it runs
      lockSetup(shownRunning);
    }
    // the rest of the panel greyed out and locked until every setup box is done, and while a map
    // is showing (VIEW's PAINTING is red) - but not one the panel itself is showing, to be used
    boolean mapShown = value("showWhat") > 0;
    boolean mapInUse = recolourShown >= 0 && value("showWhat") == recolourShown
      || picking != PICK_NONE && value("showWhat") == pickMapShown;
    boolean g = !setupComplete() || mapShown && !mapInUse;
    if (g != gated) {
      gated = g;
      lockSetup(shownRunning);
      layoutWanted = true;
    }
    // RUN green, STOP red. PAUSE green while painting, CARRY ON orange while paused. While a map
    // is showing nothing paints (the painter pauses), so RUN and CARRY ON are greyed out and locked
    boolean going = isRunning || runWaiting;
    runButton.setCaptionLabel(going ? "STOP" : "RUN");
    buttonColour(runButton, going ? runRed : runGreen, going ? runRedHover : runGreenHover, !going && mapShown);
    pauseButton.setCaptionLabel(isPaused ? "CARRY ON" : "PAUSE");
    if (!isRunning) buttonColour(pauseButton, color(60), color(70, 130, 200), false);
    else if (isPaused) buttonColour(pauseButton, orange, orangeHover, mapShown);
    else buttonColour(pauseButton, runGreen, runGreenHover, false);
    buttonColour(stepButton, color(60), color(70, 130, 200), !(isRunning && isPaused) || mapShown);
    paceSlider.getValueLabel().setText(paceText(paceRate(value("pace"))));
    copyText.setText(copyStatus);
    zoneText.setText(zoneStatus);
    // the zone's level ranges: the handles' numbers rounded, as the levels used are (a range only gets as
    // near a whole number as its pixels let it - 11.96 for 12)
    for (String n : new String[] { "zoneALevels", "zoneBLevels" }) {
      Range r = (Range) all.get(n);
      r.setLowValueLabel(str(round(r.getLowValue())));
      r.setHighValueLabel(str(round(r.getHighValue())));
    }
    eraseText.setText(eraseStatus);
    for (String n : new String[] { "copy", "scrape" }) {
      int p = round(value(n + "_edgeFade"));
      ((Slider) all.get(n + "_edgeFade")).getCaptionLabel().setText(p == 0 ? "no fade" : abs(p) + (p < 0 ? " pixels inside" : " pixels outside"));
      ((Slider) all.get(n + "_edgeFade")).getValueLabel().setText("");
    }
    if (areaPatches()) {
      patchText.setText(patchLine(areaKind()));
      String[] which = split(partsLine(), '\n');
      partsText1.setText(which[0]);
      partsText2.setText(which.length > 1 ? which[1] : "");
    }
    if (!editing.equals(shownEditing)) {
      shownEditing = editing;
      applyOpen = false;
      if (picking == PICK_AREA) picking = PICK_NONE;     // (it was for the tool before)
      layoutWanted = true;
    }
    for (int i = 0; i < TOOLS.length; i++) {
      ((Toggle) all.get(TOOLS[i] + "_on")).setCaptionLabel(toolTitles[i]
        + (toolFolded && value(TOOLS[i] + "_on") > 0.5 ? "     (RECOLOUR is open)" : ""));
    }
    if (areaUsed() && !areaPicked()) applyOpen = true;     // (it stays open till its title's clicked)
    showPickButtons();
    String toolNow = "  -  " + toolTitles[toolIndex()].toLowerCase();
    moveHeader.setText("MOVEMENT" + toolNow + (shown("makesMarks&moveOpen") ? "     click here when done" : ""));
    moveText.setText(moveLine());
    colourHeader.setText("COLOUR" + toolNow);
    applyHeader.setText("APPLY  -  " + toolTitles[max(0, java.util.Arrays.asList(TOOLS).indexOf(editing))].toLowerCase()
      + "     " + (!layerPicked() ? "pick a layer" : !areaPicked() ? (areaUsed() ? areaChoose() : "pick an area")
      : applyShut() ? applyLine() : "click here when done"));
    for (int k = 0; k < S_COUNT; k++) boxTitles[k].setText(boxNames[k] + (openSetup == k ? "     click here when done" : ""));
    sourceText.setText(sourceDone ? faceName + "     " + photo.width + " x " + photo.height + " pixels" : "click to choose a picture");
    massText.setText(massesOpen ? massStatus : massesDone ? "done  -  " + massStatus.replace("masses: ", "")
      : "click to make the masses");
    meshText.setText(!meshNote.equals("") ? meshNote : meshOpen ? meshStatus : meshDone ? "done  -  " + meshStatus.replace("mesh: ", "")
      : "click to make the mesh  (triangles)");
    paletteText.setText(paletteOpen || paletteDone ? paletteStatus() : "click to make a palette of " + PALETTE_SIZE + " colours");
    outlineText.setText(outlineStatus());

    // VIEW's layers: an empty one's box is white (grey while it's hidden)
    for (int i = 0; i < LAYERS; i++) {
      Toggle t = (Toggle) all.get("layerOn" + i);
      t.setColorActive(layerEmpty[i] ? color(255) : color(110, 170, 240)).setColorBackground(layerEmpty[i] ? color(150) : color(60));
    }
    cp5.draw();
    frameLayer();
    // until every setup box is done, and while a map is showing, everything but them and VIEW is
    // greyed out (and locked)
    if (gated) {
      fill(128, 160);
      noStroke();
      rect(16 + colW - 12, 0, width - colW, height - 28);
      String why = !setupComplete() ? "finish SETUP 1 - 5 first  (every square green)"
        : "a map is showing, so nothing runs  -  click PAINTING, in VIEW";
      textAlign(CENTER, CENTER);
      textSize(16);
      float mid = 16 + colW + (width - colW) / 2, half = textWidth(why) / 2 + 14;
      fill(225);
      rect(mid - half, 5, 2 * half, 30, 6);
      fill(40);
      text(why, mid, 19);
      textSize(12);
      for (String n : alwaysButtons) buttons.get(n).draw(this.g);
    }
    // with every tool off, column 3 still shows the last tool's settings, under a grey cover
    boolean anyOn = false;
    for (String t : TOOLS) anyOn |= value(t + "_on") > 0.5;
    if (!anyOn) {
      fill(128, 124);
      noStroke();
      rect(16 + 2 * colW - 12, 0, colW, height - 28);
    }

    // the status line along the bottom
    fill(50);
    noStroke();
    rect(0, height - 28, width, 28);
    fill(220);
    textAlign(LEFT, CENTER);
    if (!mapStatus.equals("")) {
      text(mapStatus, 16, height - 14);
      return;
    }
    String state = isRunning ? (isPaused ? (value("showWhat") > 0 ? "paused  (showing a map)" : "paused") : "painting") : runWaiting ? "waiting for the masses" : "stopped";
    if (isRunning && !isPaused && value("copy_on") > 0.5) state += " nothing - COPY, in MOVEMENT, does it";
    else if (value("scrape_on") > 0.5 && isRunning && !isPaused && erasing()) state += " nothing - ERASE, in MOVEMENT, does it";
    else if (anyOn && isRunning && !isPaused && !applyDone()) state += " nothing - " + (!layerPicked() ? "pick a layer" : areaUsed() ? areaChoose() : "pick an area")
      + " in APPLY";
    text(faceName + "   " + photo.width + " x " + photo.height + "      " + state + "      " + markCount + " marks      "
      + round(outputFps) + " fps      " + massStatus, 16, height - 14);
  }

  // controlP5 only counts a click on a radio button's or toggle's little square - make a click on
  // the words beside it count too
  public void mousePressed() {
    pressedIn = -1;
    clickReport();
    // a click off an open setup list closes it
    ScrollableList sl = (ScrollableList) all.get("source");
    if (sl.isOpen() && !sl.isMouseOver()) {
      sl.close();
      layoutWanted = true;
      return;
    }
    if (listOpen) return;
    if (gated && !overSetup() && !inBlock(viewSection, 0)) return;   // the rest is greyed out
    if (swatchClicked()) return;
    if (paletteSwatchClicked()) return;
    if (areaSwatchClicked()) return;
    int[] secs = boxSections();
    for (int k = 0; k < S_COUNT; k++) {
      // an open box only counts its title - its controls take their own clicks
      if (inBlock(secs[k], openSetup == k ? 34 : 0)) {
        pressedIn = k;
        return;
      }
    }
    if (applyDone() && inBlock(applySection, 30)) {
      applyPressed = true;
      return;
    }
    if (shown("hasMove&makesMarks&applyShut") && inBlock(moveSection, 30)) {
      movePressed = true;
      return;
    }
    for (ControllerInterface c : all.values()) {
      if (!c.isVisible()) continue;
      if (c instanceof RadioButton) {
        java.util.List<Toggle> items = ((RadioButton) c).getItems();
        for (int i = 0; i < items.size(); i++) {
          if (onLabel(items.get(i), ((RadioButton) c).getPosition())) {
            ((RadioButton) c).activate(i);
            if (c == all.get(editing + "_layer") || c == all.get(editing + "_inArea")) layerClicked = true;
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

  // (for finding a fault - take out once the panel's clicks all work) what the click landed on, in the console
  void clickReport() {
    String s = "panel click " + mouseX + "," + mouseY + "  gated=" + gated + " listOpen=" + listOpen + " openSetup=" + openSetup
      + " running=" + isRunning + "  done=" + java.util.Arrays.toString(boxesDone()) + "  under it:";
    for (ControllerInterface c : cp5.getAll()) {
      if (!(c instanceof Controller)) continue;
      Controller k = (Controller) c;
      float[] p = k.getAbsolutePosition();
      if (mouseX >= p[0] && mouseX <= p[0] + k.getWidth() && mouseY >= p[1] && mouseY <= p[1] + k.getHeight())
        s += "  " + k.getName() + (k.isVisible() ? "" : "(hidden)") + (k.isLock() ? "(locked)" : "");
    }
    for (ScrollableList l : lists) if (l.isOpen()) s += "   OPEN LIST: " + l.getName() + (l.isVisible() ? "" : " (hidden)");
    println(s);
  }

  // a click on a setup box: SOURCE opens its list; the others open, or (on the open one's title)
  // close and are done. Done when the button is let go - the list opens under the mouse, and
  // controlP5 picks a list item on letting go
  public void mouseReleased() {
    boolean layerWas = layerClicked;
    layerClicked = false;
    if (layerWas) applyOpen = areaUsed();        // (the colours, blobs ... are chosen with it open)
    else if (applyPressed && inBlock(applySection, 30)) applyOpen = !applyOpen;
    if (applyShut() && picking == PICK_AREA) picking = PICK_NONE;      // its title ends the picking too
    if (movePressed && inBlock(moveSection, 30)) moveFolded[toolIndex()] = !moveFolded[toolIndex()];
    if (layerWas || applyPressed || movePressed) layoutWanted = true;
    movePressed = false;
    applyPressed = false;
    int k = pressedIn;
    pressedIn = -1;
    if (k < 0 || !inBlock(boxSections()[k], 0) || isRunning) return;     // locked while running
    if (k == S_SRC) {
      closeBox(false);
      ScrollableList l = (ScrollableList) all.get("source");
      l.open();
      l.show();
      layoutWanted = true;
    } else if (openSetup == k) closeBox(true);
    else openBox(k);
  }

  // the setup boxes' colour blocks, SETUP 1 first
  int[] boxSections() {
    return new int[] { sourceBox, massBox, outlineBox, meshBox, paletteBox };
  }
  Integer[] boxSecsList(int[] secs) {
    Integer[] l = new Integer[secs.length];
    for (int i = 0; i < secs.length; i++) l[i] = secs[i];
    return l;
  }

  boolean[] boxesDone() {
    return new boolean[] { sourceDone, massesDone, outlineDone, meshDone, paletteDone };
  }

  boolean setupComplete() {
    for (boolean b : boxesDone()) if (!b) return false;
    return true;
  }

  // whether the chosen tool is SCRAPE, at its erase
  boolean erasing() {
    return editing.equals("scrape") && value("scrape_kind") == SCRAPE_ERASE;
  }

  // whether the chosen tool puts paint on (so has COLOUR, and all of ON LAYER)
  boolean hasColour() {
    return !editing.equals("copy") && !editing.equals("scrape");
  }

  boolean areaPicked() {
    int a = (int) value(editing + "_inArea");
    if (!areaUsed()) return a == AREA_ALL || a >= AREA_TRI_CENTERS;
    if (a == AREA_ZONE) return true;
    if (areaPatches()) return patchCount[areaKind()] > 0;
    for (boolean b : areaPick) if (b) return true;
    return false;
  }

  // whether its area is one that needs some choosing - colours, or blobs, triangles ...
  // whether APPLY shows the zone's settings: IN AREA's Zone, or START AT's "in zone"
  boolean zoneShown() {
    return (int) value(editing + "_inArea") == AREA_ZONE || (int) value(editing + "_startAt") == 8;
  }

  boolean areaUsed() {
    return areaIsPart((int) value(editing + "_inArea"));
  }

  boolean areaColours() {
    int a = (int) value(editing + "_inArea");
    return a == AREA_MASS_COLOUR || a == AREA_MESH_COLOUR;
  }

  boolean areaPatches() {
    return areaKind() >= 0;
  }

  // which of the Picks tab's kinds it is, or -1
  int areaKind() {
    return patchKind((int) value(editing + "_inArea"));
  }

  // ... and what's to be done about it
  String areaChoose() {
    int a = (int) value(editing + "_inArea");
    return patchKind(a) >= 0 ? "click some " + patchWord[patchKind(a)] + "s" : "choose colours";
  }

  // APPLY: whether its two steps - the layer, and the area - are done, and whether the box is closed
  // (MOVEMENT and COLOUR show then)
  boolean applyDone() {
    return layerPicked() && areaPicked();
  }

  // the PICK button's "HERE: DONE": as a click on APPLY's title
  void areaDone() {
    if (picking == PICK_AREA) picking = PICK_NONE;
    if (applyDone()) applyOpen = false;
    layoutWanted = true;
  }

  // what's been chosen, for the closed box's line: the layer and the area
  String applyLine() {
    int a = constrain((int) value(editing + "_inArea"), 0, inAreaNames.length - 1);
    return "layer " + LAYER_NAMES[constrain((int) value(editing + "_layer"), 0, LAYERS - 1)] + ",  "
      + (areaUsed() && value(editing + "_areaSide") == 1 ? "not " : "") + inAreaNames[a];
  }

  // MOVEMENT folded: which way its marks go, and where they start
  String moveLine() {
    ControllerInterface around = all.get(editing + "_around");
    ControllerInterface start = all.get(editing + "_startAt");
    if (start == null) return "";
    String[] ways = { "around the form", "across the form", "along the outline" };
    String way = around == null ? "" : ways[constrain((int) around.getValue(), 0, 2)] + ",   ";
    int s = max(0, (int) start.getValue());
    String at = ((RadioButton) start).getItem(s).getCaptionLabel().getText();
    if (at.startsWith("weighted")) at = "weighted by " + mapNames[constrain((int) value(editing + "_startMap"), 0, mapNames.length - 1)];
    return way + "start at:  " + at.replace("at ", "").replace("  (SETUP 3)", "").replace(" (2D, hold button)", "").replace("  (set in APPLY)", "");
  }

  int toolIndex() {
    return max(0, java.util.Arrays.asList(TOOLS).indexOf(editing));
  }

  boolean layerPicked() {
    return value(editing + "_layer") >= 0;
  }

  boolean applyShut() {
    return applyDone() && !applyOpen && !layerClicked;
  }

  // whether the mouse is on one of the setup boxes
  boolean overSetup() {
    for (int b : boxSections()) if (inBlock(b, 0)) return true;
    return false;
  }

  // box k opened (any other closes, not done): it shows what it's about - the masses, the mesh,
  // the masses in the palette's colours (making a palette the first time), the outline
  void openBox(int k) {
    closeBox(false);
    RadioButton show = (RadioButton) all.get("showWhat");
    int want = -1;
    if (k == S_MASS) {
      massesOpen = true;
      want = VIEW_MASSES;
    } else if (k == S_MESH) {
      meshOpen = true;
      want = VIEW_MESH;
    } else if (k == S_PAL) {
      if (paletteBase.length == 0) newPalette();
      paletteOpen = true;
      showPaletteChosen();         // (RECOLOUR may have changed them meanwhile)
      want = VIEW_PAL_MASSES;
    } else if (k == S_OUTL) {
      outlineOpen = true;
    }
    shownFor = want;
    if (want >= 0) {
      showBefore = show.getValue();
      show.activate(want);
    }
    openSetup = k;
    layoutWanted = true;
  }

  // the open box closed - done, if it was its title that was clicked - and the view put back
  void closeBox(boolean done) {
    int k = openSetup;
    if (k < 0) return;
    openSetup = -1;
    massesOpen = meshOpen = paletteOpen = outlineOpen = false;
    RadioButton show = (RadioButton) all.get("showWhat");
    if (shownFor >= 0 && show.getValue() == shownFor) show.activate(showBefore == shownFor ? 0 : (int) showBefore);
    shownFor = -1;
    if (done) {
      if (k == S_MASS) massesDone = true;
      else if (k == S_MESH) meshDone = true;
      else if (k == S_PAL) paletteDone = true;
      else if (k == S_OUTL) outlineDone = true;
    }
    if (k == S_PAL && recolourKind > 0) showChosen();      // RECOLOUR shows the same palette
    layoutWanted = true;
  }

  // a button's colour, and its hover colour - or grey and locked (and the lists lock everything
  // while one is open)
  void buttonColour(Button b, int c, int hover, boolean off) {
    b.setColorBackground(off ? color(85) : c).setColorForeground(off ? color(85) : hover);
    b.getCaptionLabel().setColor(off ? color(150) : color(255));
    b.setLock(off || listOpen || gated);
  }

  // whether the mouse is in section b's colour block - only its top `h` if h > 0
  boolean inBlock(int b, float h) {
    float[] k = block[b];
    if (k == null) return false;
    float bottom = h > 0 ? k[1] + h : k[2];
    return mouseX >= k[0] - 8 && mouseX <= k[0] - 20 + colW && mouseY >= k[1] && mouseY <= bottom;
  }

  // ---------------------------------------------------- RECOLOUR

  // a new palette for layer L from the painter (makeRecolourPalette): nothing changed, nothing chosen
  void newRecolourPalette(int L, int[] base) {
    float[][] adj = new float[base.length][];
    for (int i = 0; i < base.length; i++) adj[i] = new float[] { 0, 1, 1 };
    recolourPickeds[L] = new boolean[base.length];
    recolourAdjs[L] = adj;
    recolourBases[L] = base;
    if (L == recolourL) showLayer(L);
  }

  // the swatches and sliders show layer L's palette
  void showLayer(int L) {
    recolourL = L;
    recolourPicked = recolourPickeds[L];
    recolourAdj = recolourAdjs[L];
    recolourBase = recolourBases[L];
    showChosen();
  }

  // what the swatches show and the sliders change: the chosen layer's, or the palette's (the masses
  // and the mesh). They're replaced whole, never changed in place
  int[] swatchBase() { return recolourKind > 0 ? paletteBase : recolourBase; }
  float[][] swatchAdj() { return recolourKind > 0 ? paletteAdj : recolourAdj; }
  boolean[] swatchPicked() { return recolourKind > 0 ? palettePicked : recolourPicked; }
  int swatchCols() { return recolourKind > 0 ? SWATCH_PAL_COLS : SWATCH_COLS; }
  Row swatchGrid() { return recolourKind > 0 ? recolourPalGrid : recolourGrid; }

  void setSwatchAdj(float[][] adj) {
    if (recolourKind > 0) paletteAdj = adj;
    else recolourAdj = recolourAdjs[recolourL] = adj;
  }

  void setSwatchPicked(boolean[] p) {
    if (recolourKind > 0) palettePicked = p;
    else recolourPicked = recolourPickeds[recolourL] = p;
  }

  // what RECOLOUR is on: a layer (with its palette shown), or the masses or the mesh
  void chooseRecolour(int i) {
    recolourKind = constrain(i - LAYERS + 1, 0, 2);
    if (recolourKind == 0) showLayer(constrain(i, 0, LAYERS - 1));
    else showChosen();
  }

  // the swatches' palette made if there isn't one yet: a layer's colours read, or SETUP 5's palette
  void needSwatches() {
    if (recolourKind > 0) {
      if (paletteBase.length == 0) newPalette();
    }
    else if (recolourBase.length == 0) command("recolourPalette " + recolourL);
  }

  // the map that goes with what RECOLOUR is open on (-1: none)
  int recolourMap() {
    if (recolourKind == 0 || value("recolourOpen") < 0.5) return -1;
    return recolourKind == 1 ? VIEW_PAL_MASSES : VIEW_PAL_MESH;
  }

  // the masses or the mesh in the palette's colours in the output window while RECOLOUR is open on
  // them; then the view as it was, unless it's been changed meanwhile
  void showRecolourMap() {
    int want = recolourMap();
    if (applying || want == recolourShown) return;
    RadioButton show = (RadioButton) all.get("showWhat");
    int was = recolourShown;
    recolourShown = want;
    if (want >= 0) {
      if (was < 0 || show.getValue() != was) recolourShowBefore = show.getValue();
      show.activate(want);
    }
    else if (show.getValue() == was) show.activate(recolourShowBefore == was ? 0 : (int) recolourShowBefore);
  }

  void recolourEvent(String n, float value) {
    if (n.equals("recolourNew")) command("recolourPalette " + recolourL);
    else if (n.equals("recolourRandom")) randomRecolour();
    else if (n.equals("recolourOpen")) {
      if (value > 0.5) needSwatches();
      showRecolourMap();
    }
    else if (n.equals("recolourLayer")) {
      // another layer: its palette shows, read now if it hasn't one yet
      chooseRecolour((int) value);
      if (value("recolourOpen") > 0.5) {
        needSwatches();
        showRecolourMap();
      }
    }
    else if (n.equals("recolourAll") || n.equals("recolourNone")) {
      boolean[] p = new boolean[swatchBase().length];
      java.util.Arrays.fill(p, n.equals("recolourAll"));
      setSwatchPicked(p);
      showChosen();
    }
    else if (n.equals("recolourResetPicked") || n.equals("recolourResetAll")) {
      float[][] adj = copyAdj();
      for (int i = 0; i < adj.length; i++) {
        if (n.equals("recolourResetAll") || swatchPicked()[i]) adj[i] = new float[] { 0, 1, 1 };
      }
      setSwatchAdj(adj);
      showChosen();
    }
    else if (!recolourSyncing && (n.equals("recolourHue") || n.equals("recolourSat") || n.equals("recolourBri"))) {
      // a slider moved: the chosen swatches all take its value
      int q = n.equals("recolourHue") ? 0 : n.equals("recolourSat") ? 1 : 2;
      float[][] adj = copyAdj();
      boolean[] p = swatchPicked();
      for (int i = 0; i < adj.length && i < p.length; i++) if (p[i]) adj[i][q] = value;
      setSwatchAdj(adj);
    }
  }

  // RANDOM NUDGE: each chosen swatch (all of them if none are) has its hue turned a little and
  // its saturation changed a little, from where they are now - brightness is left alone, so
  // pressing it again and again drifts the colours further
  void randomRecolour() {
    float[][] adj = copyAdj();
    boolean any = false;
    boolean[] p = swatchPicked();
    for (boolean b : p) any |= b;
    for (int i = 0; i < adj.length; i++) {
      if (any && !p[i]) continue;
      adj[i][0] = constrain(adj[i][0] + random(-40, 40), -180, 180);
      adj[i][1] = constrain(adj[i][1] * random(0.75, 1.28), 0, 2);
    }
    setSwatchAdj(adj);
    showChosen();
  }

  float[][] copyAdj() {
    float[][] a = swatchAdj(), c = new float[a.length][];
    for (int i = 0; i < a.length; i++) c[i] = a[i].clone();
    return c;
  }

  void loadRecolour(int L, JSONArray pal, JSONArray ch) {
    int[] base = new int[pal.size()];
    float[][] adj = new float[pal.size()][];
    for (int i = 0; i < base.length; i++) {
      base[i] = pal.getInt(i);
      adj[i] = new float[] { ch.getFloat(i * 3), ch.getFloat(i * 3 + 1), ch.getFloat(i * 3 + 2) };
    }
    recolourPickeds[L] = new boolean[base.length];
    recolourAdjs[L] = adj;
    recolourBases[L] = base;
  }

  // the sliders show the first chosen swatch's changes (or none)
  void showChosen() {
    float[] a = { 0, 1, 1 };
    int chosen = 0;
    boolean[] p = swatchPicked();
    float[][] adj = swatchAdj();
    for (int i = 0; i < p.length && i < adj.length; i++) {
      if (!p[i]) continue;
      if (chosen == 0) a = adj[i];
      chosen++;
    }
    recolourSyncing = true;
    all.get("recolourHue").setValue(a[0]);
    all.get("recolourSat").setValue(a[1]);
    all.get("recolourBri").setValue(a[2]);
    recolourSyncing = false;
  }

  // the swatch under the mouse, or -1
  int swatchAt(float mx, float my) {
    Row grid = swatchGrid();
    if (value("recolourOpen") < 0.5 || grid == null || grid.y < 0) return -1;
    float[] b = block[grid.section];
    if (b == null) return -1;
    int cols = swatchCols();
    float w = (colW - 28) / (float) cols;
    int col = floor((mx - b[0]) / w), row = floor((my - grid.y) / SWATCH_H);
    if (col < 0 || col >= cols || row < 0) return -1;
    int i = row * cols + col;
    return i < swatchBase().length ? i : -1;
  }

  boolean swatchClicked() {
    int i = swatchAt(mouseX, mouseY);
    if (i < 0 || i >= swatchPicked().length) return false;
    boolean[] p = swatchPicked().clone();
    p[i] = !p[i];
    setSwatchPicked(p);
    showChosen();
    return true;
  }

  // the swatches: each the colour it was on the left, as it is now on the right, with its number,
  // and a thick frame if it's chosen
  // over COLOUR's accent hue range: the hues, darkened outside the range, and to the right a few
  // accents as they could come out, with the saturation and brightness ranges too
  void drawAccentBar() {
    if (accentBar == null || accentBar.y < 0 || block[accentBar.section] == null) return;
    float x = block[accentBar.section][0], y = accentBar.y + 1;
    Range h = (Range) all.get("accentHue"), sa = (Range) all.get("accentSat"), br = (Range) all.get("accentBri");
    float lo = h.getLowValue(), hi = h.getHighValue();
    int w = 170;
    noStroke();
    for (int i = 0; i < w; i++) {
      float hue = i / (float) (w - 1) * 360;
      int c = java.awt.Color.HSBtoRGB(hue / 360, 1, 1);
      fill(hue >= lo && hue <= hi ? c : lerpColor(c, color(40), 0.7));
      rect(x + i, y, 1, 9);
    }
    for (int k = 0; k < 6; k++) {
      float f = k / 5.0;
      float hue = lerp(lo, hi, f) / 360;
      float s = lerp(sa.getLowValue(), sa.getHighValue(), (k % 3) / 2.0) / 100;
      float b = lerp(br.getLowValue(), br.getHighValue(), ((k + 1) % 3) / 2.0) / 100;
      fill(java.awt.Color.HSBtoRGB(hue - floor(hue), s, b));
      rect(x + w + 6 + k * 18, y - 1, 16, 11, 2);
    }
  }

  // AUTOMATION's wave for the chosen tool: one whole wave, shortest at the bottom and longest at
  // the top, a dot where it is now, and the value now beside it. Faint while it's off
  void drawAutoWave() {
    if (autoWave == null || autoWave.y < 0 || block[autoWave.section] == null) return;
    int i = java.util.Arrays.asList(TOOLS).indexOf(editing);
    if (i < 0) return;
    boolean on = value(editing + "_autoOn") > 0.5;
    float x = block[autoWave.section][0], y = autoWave.y + 2, w = 170, h = 24;
    noFill();
    stroke(dark, on ? 255 : 90);
    strokeWeight(1.5);
    beginShape();
    for (int k = 0; k <= 60; k++) {
      float p = k / 60.0;
      vertex(x + p * w, y + h - autoShape(p) * h);
    }
    endShape();
    float p = autoPhase[i];
    noStroke();
    fill(on ? color(204, 59, 46) : color(dark, 90));
    ellipse(x + p * w, y + h - autoShape(p) * h, 9, 9);
    float[] now = autoNow;
    fill(dark, on ? 255 : 120);
    textAlign(LEFT, CENTER);
    String val = AUTO_TARGET[i].equals("width") ? nf(now[i], 0, 1) : str(round(now[i]));
    text(on ? "now  " + val : "off", x + w + 12, y + h / 2);
    textAlign(LEFT, BASELINE);
  }

  void drawSwatches() {
    Row grid = swatchGrid();
    if (value("recolourOpen") < 0.5 || grid == null || grid.y < 0) return;
    float[] b = block[grid.section];
    if (b == null) return;
    int[] base = swatchBase();
    float[][] adj = swatchAdj();
    boolean[] picked = swatchPicked();
    int[] whole = recolourKind > 0 ? paletteFinal() : null;    // (with SETUP 5's "whole palette" changes)
    int cols = swatchCols();
    float w = (colW - 28) / (float) cols;
    int chosen = 0;
    for (int i = 0; i < base.length && i < adj.length; i++) {
      float x = b[0] + (i % cols) * w, y = grid.y + (i / cols) * SWATCH_H;
      boolean on = i < picked.length && picked[i];
      if (on) chosen++;
      int now = whole != null && i < whole.length ? whole[i] : recoloured(base[i], adj[i]);
      noStroke();
      fill(base[i]);
      rect(x, y, (w - 6) / 2, SWATCH_H - 6);
      fill(now);
      rect(x + (w - 6) / 2, y, (w - 6) / 2, SWATCH_H - 6);
      if (on) {
        noFill();
        stroke(20);
        strokeWeight(3);
        rect(x - 1, y - 1, w - 4, SWATCH_H - 4);
        stroke(255);
        strokeWeight(1);
        rect(x + 1.5, y + 1.5, w - 9, SWATCH_H - 9);
        noStroke();
      }
      fill(brightness(base[i]) > 140 ? 20 : 240);
      textAlign(LEFT, TOP);
      text(i + 1, x + 4, y + 3);
    }
    textAlign(LEFT, BASELINE);
    recolourText.setText(base.length == 0 ? (recolourKind > 0 ? "no palette yet" : "no palette yet  (needs paint)") : chosen + "/" + base.length + " chosen");
  }

  // ---------------------------------------------------- PALETTE GEN

  // a new palette on the scheme chosen (generatePalette, the Palette Gen tab): nothing changed,
  // nothing chosen. The "whole palette" sliders stay as they are
  void newPalette() {
    paletteSchemeMade = constrain((int) value("paletteScheme"), 0, schemeNames.length - 1);
    int[] g = generatePalette(paletteSchemeMade, paletteRnd);
    float[][] adj = new float[PALETTE_SIZE][];
    for (int i = 0; i < PALETTE_SIZE; i++) adj[i] = new float[] { 0, 1, 1 };
    palettePicked = new boolean[PALETTE_SIZE];
    paletteAdj = adj;
    paletteBase = java.util.Arrays.copyOf(g, PALETTE_SIZE);
    paletteHueMade = g[PALETTE_SIZE];
    showPaletteChosen();
  }

  // the palette as it is now: each colour with its own changes, then the whole palette's
  int[] paletteFinal() {
    int[] base = paletteBase;
    float[][] adj = paletteAdj;
    float[] whole = { value("paletteHue"), value("paletteSat"), value("paletteBri") };
    int[] out = new int[min(base.length, adj.length)];
    for (int i = 0; i < out.length; i++) out[i] = recoloured(recoloured(base[i], adj[i]), whole);
    return out;
  }

  // the line under SETUP 3's title: how many parts it traces, and how smooth
  String outlineStatus() {
    int on = 0;
    for (String p : outlineParts) if (value("outline_" + p) > 0.5) on++;
    String s = (value("outline_kind") == 1 ? "objects" : "face, " + on + " of " + outlineParts.length + " parts")
      + ",  smoothness " + nf(value("outline_smooth"), 0, 2);
    if (value("outline_kind") == 1 && !new java.io.File(mapsPath() + "/" + faceName + "/objects.png").exists())
      return "objects: none found for this picture  -  make its maps again with the map maker";
    if (outlineOpen) return s + "   (red on the picture)";
    return outlineDone ? "done  -  " + s : "click to choose what the outline traces";
  }

  String paletteStatus() {
    if (paletteBase.length == 0) return "click to make a palette of " + PALETTE_SIZE + " colours";
    int chosen = 0;
    for (boolean b : palettePicked) if (b) chosen++;
    return schemeNames[paletteSchemeMade] + " on hue " + paletteHueMade + (paletteOpen ? "      " + chosen + "/" + paletteBase.length + " chosen" : "");
  }

  void paletteEvent(String n, float value) {
    if (n.equals("paletteGenerate") || n.equals("paletteScheme")) newPalette();
    else if (n.equals("paletteAll") || n.equals("paletteNone")) {
      boolean[] p = new boolean[paletteBase.length];
      java.util.Arrays.fill(p, n.equals("paletteAll"));
      palettePicked = p;
      showPaletteChosen();
    }
    else if (n.equals("paletteResetPicked") || n.equals("paletteResetAll")) {
      float[][] adj = copyPaletteAdj();
      for (int i = 0; i < adj.length; i++) {
        if (n.equals("paletteResetAll") || palettePicked[i]) adj[i] = new float[] { 0, 1, 1 };
      }
      paletteAdj = adj;
      // RESET ALL puts the whole palette's sliders back too
      if (n.equals("paletteResetAll")) {
        all.get("paletteHue").setValue(0);
        all.get("paletteSat").setValue(1);
        all.get("paletteBri").setValue(1);
      }
      showPaletteChosen();
    }
    else if (!paletteSyncing && (n.equals("paletteHueC") || n.equals("paletteSatC") || n.equals("paletteBriC"))) {
      // a chosen-colour slider moved: the chosen swatches all take its value
      int q = n.equals("paletteHueC") ? 0 : n.equals("paletteSatC") ? 1 : 2;
      float[][] adj = copyPaletteAdj();
      for (int i = 0; i < adj.length && i < palettePicked.length; i++) if (palettePicked[i]) adj[i][q] = value;
      paletteAdj = adj;
    }
  }

  float[][] copyPaletteAdj() {
    float[][] a = paletteAdj, c = new float[a.length][];
    for (int i = 0; i < a.length; i++) c[i] = a[i].clone();
    return c;
  }

  // the chosen-colour sliders show the first chosen swatch's changes (or none)
  void showPaletteChosen() {
    float[] a = { 0, 1, 1 };
    for (int i = 0; i < palettePicked.length && i < paletteAdj.length; i++) {
      if (palettePicked[i]) {
        a = paletteAdj[i];
        break;
      }
    }
    paletteSyncing = true;
    all.get("paletteHueC").setValue(a[0]);
    all.get("paletteSatC").setValue(a[1]);
    all.get("paletteBriC").setValue(a[2]);
    paletteSyncing = false;
  }

  // the palette swatch under the mouse, or -1
  int paletteSwatchAt(float mx, float my) {
    if (!paletteOpen || paletteGrid == null || paletteGrid.y < 0) return -1;
    float[] b = block[paletteGrid.section];
    if (b == null) return -1;
    float w = (colW - 28) / (float) PAL_COLS;
    int col = floor((mx - b[0]) / w), row = floor((my - paletteGrid.y) / PAL_H);
    if (col < 0 || col >= PAL_COLS || row < 0) return -1;
    int i = row * PAL_COLS + col;
    return i < paletteBase.length ? i : -1;
  }

  boolean paletteSwatchClicked() {
    int i = paletteSwatchAt(mouseX, mouseY);
    if (i < 0 || i >= palettePicked.length) return false;
    boolean[] p = palettePicked.clone();
    p[i] = !p[i];
    palettePicked = p;
    showPaletteChosen();
    return true;
  }

  // the palette's swatches: each colour as generated on the left, as it is now on the right, with
  // its number, and a thick frame if it's chosen
  void drawPaletteSwatches() {
    if (!paletteOpen || paletteGrid == null || paletteGrid.y < 0) return;
    float[] b = block[paletteGrid.section];
    if (b == null) return;
    int[] base = paletteBase, now = paletteFinal();
    float w = (colW - 28) / (float) PAL_COLS;
    for (int i = 0; i < now.length; i++) {
      float x = b[0] + (i % PAL_COLS) * w, y = paletteGrid.y + (i / PAL_COLS) * PAL_H;
      noStroke();
      fill(base[i]);
      rect(x, y, (w - 6) / 2, PAL_H - 6);
      fill(now[i]);
      rect(x + (w - 6) / 2, y, (w - 6) / 2, PAL_H - 6);
      if (i < palettePicked.length && palettePicked[i]) {
        noFill();
        stroke(20);
        strokeWeight(3);
        rect(x - 1, y - 1, w - 4, PAL_H - 4);
        stroke(255);
        strokeWeight(1);
        rect(x + 1.5, y + 1.5, w - 9, PAL_H - 9);
        noStroke();
      }
      fill(brightness(base[i]) > 140 ? 20 : 240);
      textAlign(LEFT, TOP);
      text(i + 1, x + 3, y + 2);
    }
    textAlign(LEFT, BASELINE);
  }

  // a strip of the palette's colours (IN AREA's): the one under the mouse, or -1
  int stripSwatchAt(Row strip, float mx, float my) {
    if (strip == null || strip.y < 0) return -1;
    float[] b = block[strip.section];
    if (b == null) return -1;
    float w = (colW - 28) / (float) STRIP_COLS;
    int col = floor((mx - b[0]) / w), row = floor((my - strip.y) / STRIP_H);
    if (col < 0 || col >= STRIP_COLS || row < 0 || row > 1) return -1;
    int i = row * STRIP_COLS + col;
    return i < paletteBase.length ? i : -1;
  }

  // IN AREA's strip: any number chosen, each click turns one on or off
  boolean areaSwatchClicked() {
    int i = stripSwatchAt(areaStrip, mouseX, mouseY);
    if (i < 0 || i >= areaPick.length) return false;
    areaPick[i] = !areaPick[i];
    return true;
  }

  void drawStrip(Row strip, boolean[] chosen) {
    if (strip == null || strip.y < 0) return;
    float[] b = block[strip.section];
    if (b == null) return;
    int[] now = paletteFinal();
    if (now.length == 0) {
      fill(dark);
      textAlign(LEFT, TOP);
      text("no palette yet - make one in SETUP 5", b[0], strip.y + 4);
      textAlign(LEFT, BASELINE);
      return;
    }
    // each colour with how much of the picture it covers in the masses (%), or crossed out if no
    // mass is given it - that one has no area
    float[] use = value(editing + "_inArea") == AREA_MESH_COLOUR ? meshPaletteUse : paletteUse;
    float w = (colW - 28) / (float) STRIP_COLS;
    textSize(10);
    for (int i = 0; i < now.length; i++) {
      float x = b[0] + (i % STRIP_COLS) * w, y = strip.y + (i / STRIP_COLS) * STRIP_H;
      noStroke();
      fill(now[i]);
      rect(x, y, w - 3, STRIP_H - 3);
      boolean known = i < use.length;
      int ink = brightness(now[i]) > 140 ? color(20) : color(240);
      if (known && use[i] > 0) {
        fill(ink);
        textAlign(CENTER, CENTER);
        text(use[i] < 0.01 ? "<1" : str(round(use[i] * 100)), x + (w - 3) / 2, y + (STRIP_H - 3) / 2 - 1);
      } else if (known) {
        stroke(ink);
        strokeWeight(1);
        line(x + 3, y + 3, x + w - 6, y + STRIP_H - 6);
        line(x + w - 6, y + 3, x + 3, y + STRIP_H - 6);
        noStroke();
      }
      if (i < chosen.length && chosen[i]) {
        noFill();
        stroke(20);
        strokeWeight(3);
        rect(x - 1, y - 1, w - 1, STRIP_H - 1);
        stroke(255);
        strokeWeight(1);
        rect(x + 1.5, y + 1.5, w - 6, STRIP_H - 6);
        noStroke();
      }
    }
    textSize(12);
    textAlign(LEFT, BASELINE);
  }

  // picking on the masses starts (the output window shows the masses in the palette's colours) or
  // ends (the view as it was, unless it's been changed meanwhile)
  void showPicking(int p) {
    RadioButton show = (RadioButton) all.get("showWhat");
    if (p != PICK_NONE) {
      if (pickingShown == PICK_NONE) viewBeforePick = show.getValue();
      pickMapShown = pickMap();
      show.activate(pickMapShown);
    }
    else if (show.getValue() == pickMapShown && viewBeforePick != pickMapShown) show.activate((int) viewBeforePick);
    pickingShown = p;
  }

  // the PICK buttons say what they're for now
  void showPickButtons() {
    String waiting = "CLICK THE MASSES  (HERE: DONE)", ready = "PICK ON THE MASSES";
    areaPickButton.setCaptionLabel((picking == PICK_AREA ? waiting : ready).replace("MASSES", areaWhat()));
  }

  // the map picking is done on: the masses in the palette's colours - or, for IN AREA, the picture its
  // choice goes by
  int pickMap() {
    int a = (int) value(editing + "_inArea");
    return patchKind(a) >= 0 ? patchView[patchKind(a)] : a == AREA_MESH_COLOUR ? VIEW_PAL_MESH : VIEW_PAL_MASSES;
  }

  // what IN AREA's choosing is done on: "MASSES", "MESH" or "PHOTO"
  String areaWhat() {
    int a = (int) value(editing + "_inArea");
    return patchKind(a) >= 0 ? patchWhere[patchKind(a)].toUpperCase() : a == AREA_MESH_COLOUR ? "MESH" : "MASSES";
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
    else if (n.equals("saveNow")) command("save");
    else if (n.equals("scrapeEraseNow")) command("eraseArea");
    else if (n.equals("areaPickMasses")) {
      if (picking == PICK_AREA) areaDone();
      else picking = PICK_AREA;
    }
    // another kind of area: any picking for it stops - but Masses, Tris, Objects and Face Parts
    // are picked straight away
    else if (n.endsWith("_inArea")) {
      if (!applying && n.equals(editing + "_inArea") && areaPatches()) picking = PICK_AREA;
      else if (picking == PICK_AREA) picking = PICK_NONE;
    }
    else if (n.equals("areaClear")) {
      if (areaPatches()) command("clearPicks " + areaKind());
      else areaPick = new boolean[PALETTE_SIZE];
    }
    else if (n.equals("loadSettings")) command("load");
    else if (n.equals("nudge")) nudgeAll();
    else if (n.startsWith("recolour")) recolourEvent(n, e.getValue());
    else if (n.startsWith("palette")) paletteEvent(n, e.getValue());
    else if (n.equals("source")) {
      // the last item opens a photo of your own; the list goes back to the picture there is now
      if (e.getValue() >= faces.length) {
        command("open");
        sourceWanted = max(0, java.util.Arrays.asList(faces).indexOf(faceName));
      } else {
        command("source");
        sourceDone = true;
        if (!faces[(int) e.getValue()].equals(faceName)) massesDone = meshDone = false;   // a new picture needs its masses and mesh looked at again
      }
    }
    else if (n.equals("smoothing")) command("field");
    else if (n.equals("showWhat")) command("show");
    else if (n.equals("copyMap")) command("copyMap");
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
    if (when.equals("meshEdges")) return value("meshOutline") > 0.5;
    if (when.equals("later")) return false;
    if (when.equals("applyShut")) return applyShut();
    if (when.equals("applyOpen")) return !applyShut();
    if (when.equals("moveOpen")) return !moveFolded[toolIndex()];
    if (when.equals("moveFolded")) return moveFolded[toolIndex()];
    if (when.equals("hasColour")) return hasColour();
    if (when.startsWith("one ")) return value(when.substring(4) + "_one") > 0.5;
    if (when.equals("recolour")) return value("recolourOpen") > 0.5;
    if (when.equals("light")) return value("lightOpen") > 0.5;
    if (when.startsWith("lightLayer ")) return round(value("lightLayer")) == Integer.parseInt(when.substring(11));
    if (when.equals("recolourLayers")) return recolourKind == 0;
    if (when.equals("recolourPal")) return recolourKind > 0 && value("recolourOpen") > 0.5;
    if (when.equals("autoOn")) return value(editing + "_autoOn") > 0.5 && !erasing();
    if (when.equals("erase")) return erasing();
    if (when.equals("notErase")) return !erasing();
    if (when.equals("makesMarks")) return !erasing() && !editing.equals("copy");
    if (when.equals("zoneShown")) return zoneShown();
    if (when.equals("areaPickable")) return areaUsed() && (int) value(editing + "_inArea") != AREA_ZONE;
    if (when.equals("copyGrey")) return greyMap((int) value("copyWhat") + VIEW_PHOTO);
    if (when.equals("copyTint")) return value("copyTint") > 0.5;
    if (when.startsWith("boxShown ")) return openSetup < 0 || Integer.parseInt(when.substring(9)) <= openSetup;
    if (when.startsWith("boxOpen ")) return openSetup == Integer.parseInt(when.substring(8));
    if (when.equals("noSetupOpen")) return openSetup < 0;
    if (when.equals("outlineFace")) return value("outline_kind") == 0;
    if (when.equals("outlineObjects")) return value("outline_kind") == 1;
    if (when.equals("hasMove")) return !editing.equals("outline");
    if (when.equals("flowColour")) return value("flow_src") < 2;     // the photo or the masses
    if (when.equals("lineWander")) return value("line_kind") == 0;
    if (when.equals("lineCreases")) return value("line_kind") == 1;
    if (when.equals("pencilSteers")) return value("pencil_kind") < 2;
    if (when.equals("pencilFlow")) return value("pencil_kind") == 1;
    if (when.equals("pencilHatch")) return value("pencil_hatch") > 0;
    if (when.equals("knifeFlat")) return !carryTextured((int) value("knife_carry"));   // chunk and copy have no streaks
    if (when.equals("splatSites")) return value("splat_inArea") >= AREA_TRI_CENTERS;
    if (when.equals("splatFree")) return value("splat_inArea") < AREA_TRI_CENTERS;
    if (when.equals("splatFlat")) return !carryTextured((int) value("splat_carry"));   // (nor colours to vary)
    if (when.startsWith("along ")) return value(when.substring(6) + "_along") > 0.5;
    if (when.startsWith("mix ")) return value(when.substring(4) + "_pickup") == 2;
    if (when.startsWith("palette ")) return value(when.substring(8) + "_pickup") == PICK_PALETTE;
    if (when.startsWith("weighted ")) return value(when.substring(9) + "_startAt") == 1;
    if (when.startsWith("mouse ")) return value(when.substring(6) + "_startAt") == 3;
    if (when.startsWith("grid ")) return value(when.substring(5) + "_startAt") == 2;
    if (when.equals("areaUsed")) return areaUsed();
    if (when.equals("areaColours")) return areaColours();
    if (when.equals("areaPatches")) return areaPatches();
    if (when.equals("areaParts")) return areaKind() == PICK_PARTS;
    if (when.startsWith("map ")) return value(when.substring(4) + "_by") > 0;   // a "by" row with a map chosen
    return true;
  }

  // (0 for a control a tool doesn't have - COPY has no "copy_opacity")
  float value(String name) {
    ControllerInterface c = all.get(name);
    return c == null ? 0 : c.getValue();
  }

  // the parts of a section (rows with a band) on shades of its colour: band 1 a little lighter,
  // 2 a little darker, 3 darker again. Each run of shown rows in one band is one strip
  void drawBands() {
    noStroke();
    for (ArrayList<Row> col : columns) {
      int band = 0, sec = -1;
      float top = 0, bottom = 0;
      for (int k = 0; k <= col.size(); k++) {
        Row r = k < col.size() ? col.get(k) : null;
        boolean on = r != null && r.y >= 0 && r.band > 0 && r.section >= 0 && block[r.section] != null;
        if (band > 0 && (!on || r.band != band || r.section != sec)) {
          // the run before ends here
          int c = blockColour[sec];
          fill(band == 1 ? lerpColor(c, color(255), 0.3) : lerpColor(c, color(0), band == 2 ? 0.05 : 0.11));
          rect(block[sec][0] - 8, top, colW - 12, bottom - top);
          band = 0;
        }
        if (!on) continue;
        if (band == 0) { band = r.band; sec = r.section; top = r.y; }
        bottom = r.y + r.h;
      }
    }
  }

  // a green frame, in VIEW's list, round the box of the layer the tool that's on paints on (or scrapes, or
  // copies to)
  void frameLayer() {
    int L = (int) value(editing + "_layer");
    if (value(editing + "_on") < 0.5 || L < 0) return;
    Toggle t = (Toggle) all.get("layerOn" + L);
    if (!t.isVisible()) return;
    float[] p = t.getPosition();
    noFill();
    stroke(doneGreen);
    strokeWeight(3);
    rect(p[0] - 2.5, p[1] - 2.5, t.getWidth() + 5, t.getHeight() + 5);
    noStroke();
  }

  // where RUN's box starts
  float runTop() {
    float y = height - 36;
    for (int i = 0; i < columns.size(); i++) {
      if (colBottom.get(i) != 1 || colAt.get(i) != 1) continue;
      for (Row r : columns.get(i)) if (shown(r.when)) y -= r.h;
    }
    return y;
  }

  // put every shown row in place, top to bottom in each column, and hide the rest. The columns
  // along the bottom end just above the status line, or above RUN
  void layout() {
    layoutWanted = false;
    float[][] b = new float[sections][];
    float[] top = new float[columns.size()];
    float runY = runTop();
    // column 2: if the tool's settings leave no room for RECOLOUR, only its title shows. Column 1: if the
    // setup boxes leave no room for AUTOMATION's sliders (above VIEW), they're folded away
    float[] used = new float[topColumns];
    for (int i = 0; i < columns.size(); i++) {
      if (colBottom.get(i) == 1) continue;
      for (Row r : columns.get(i)) if (shown(r.when)) used[colAt.get(i)] += r.h;
    }
    toolFolded = 8 + used[1] > runY;
    float under = 0;
    for (Row r : columns.get(viewColumn)) if (shown(r.when)) under += r.h;
    boolean autoFolded = 8 + used[0] + under > height - 36;
    for (int i = 0; i < columns.size(); i++) {
      float x = 16 + colAt.get(i) * colW, y = 8;
      if (colBottom.get(i) > 0) {
        float total = 0;
        for (Row r : columns.get(i)) if (shown(r.when) && !(autoFolded && r.autoSetting)) total += r.h;
        y = (colBottom.get(i) == 2 ? runY : height - 36) - total;
        if (colLevel.get(i) >= 0) y = min(y, top[colLevel.get(i)]);
      }
      top[i] = y;
      for (Row r : columns.get(i)) {
        boolean rowShown = shown(r.when) && !(toolFolded && r.toolSetting) && !(autoFolded && r.autoSetting);
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
    for (String n : all.keySet()) {
      ControllerInterface c = all.get(n);
      if (c instanceof Range) {
        s.put(n + "_lo", ((Range) c).getLowValue());
        s.put(n + "_hi", ((Range) c).getHighValue());
      }
      else s.put(n, c.getValue());
    }
    return s;
  }

  int colour(String name) {
    return ((ColorPicker) all.get(name)).getColorValue() | 0xFF000000;
  }

  JSONObject settingsJSON() {
    JSONObject j = new JSONObject();
    for (String n : all.keySet()) {
      ControllerInterface c = all.get(n);
      if (c instanceof ColorPicker) j.setInt(n, ((ColorPicker) c).getColorValue() | 0xFF000000);
      else if (c instanceof Range) {
        j.setFloat(n + "_lo", ((Range) c).getLowValue());
        j.setFloat(n + "_hi", ((Range) c).getHighValue());
      }
      else j.setFloat(n, c.getValue());
    }
    j.setString("face", faceName);
    // RECOLOUR: each layer's palette and what's been done to it
    JSONArray layersJ = new JSONArray();
    for (int L = 0; L < LAYERS; L++) {
      int[] base = recolourBases[L];
      float[][] adj = recolourAdjs[L];
      JSONArray pal = new JSONArray(), ch = new JSONArray();
      for (int i = 0; i < base.length && i < adj.length; i++) {
        pal.append(base[i]);
        for (float a : adj[i]) ch.append(a);
      }
      JSONObject o = new JSONObject();
      o.setJSONArray("palette", pal);
      o.setJSONArray("changes", ch);
      layersJ.append(o);
    }
    j.setJSONArray("recolourLayers", layersJ);
    // PALETTE GEN: the palette as generated and what's been done to each colour
    int[] pb = paletteBase;
    float[][] pa = paletteAdj;
    JSONArray pal = new JSONArray(), ch = new JSONArray();
    for (int i = 0; i < pb.length && i < pa.length; i++) {
      pal.append(pb[i]);
      for (float a : pa[i]) ch.append(a);
    }
    JSONObject po = new JSONObject();
    po.setJSONArray("palette", pal);
    po.setJSONArray("changes", ch);
    po.setInt("scheme", paletteSchemeMade);
    po.setInt("hue", paletteHueMade);
    j.setJSONObject("paletteGen", po);
    // IN AREA's palette colours
    JSONArray ap = new JSONArray();
    for (int i = 0; i < areaPick.length; i++) if (areaPick[i]) ap.append(i);
    j.setJSONArray("areaColours", ap);
    // ... and its blobs, triangles, objects and face parts (the Picks tab)
    for (int k = 0; k < PICK_KINDS; k++) j.setJSONArray(patchKey[k], picksJSON(k));
    return j;
  }

  // put saved settings back on the panel; SETUP too if we're not running
  void applySettings(JSONObject j, boolean includeSetup) {
    applying = true;
    for (String n : all.keySet()) {
      ControllerInterface r = all.get(n);
      if (r instanceof Range && j.hasKey(n + "_lo") && j.hasKey(n + "_hi")) {
        ((Range) r).setRangeValues(j.getFloat(n + "_lo"), j.getFloat(n + "_hi"));
      }
      if (!j.hasKey(n) || n.equals("source")) continue;
      if (setupNames.contains(n) && !includeSetup) continue;
      ControllerInterface c = all.get(n);
      if (c instanceof ColorPicker) ((ColorPicker) c).setColorValue(j.getInt(n) | 0xFF000000);
      else if (c instanceof RadioButton) {
        if (j.getFloat(n) >= 0) ((RadioButton) c).activate((int) j.getFloat(n));
        else ((RadioButton) c).setNoneSelectedAllowed(true).deactivateAll().setNoneSelectedAllowed(false);   // a layer not picked
      }
      else c.setValue(j.getFloat(n));
    }
    // (settings saved before IN AREA had Zone: SPLATTER's Tri Centers and Vertices were one lower - a whole
    // file has every tool's IN AREA)
    if (!j.hasKey("zoneMapA") && j.hasKey("brush_inArea") && j.hasKey("copy_inArea") && j.getFloat("splat_inArea", -1) >= AREA_ZONE) {
      ((RadioButton) all.get("splat_inArea")).activate((int) j.getFloat("splat_inArea") + 1);
    }
    // (settings saved when these two's layer was in their own box)
    if (j.hasKey("copyTo")) ((RadioButton) all.get("copy_layer")).activate((int) j.getFloat("copyTo"));
    if (j.getFloat("scrape_only", -1) >= 0) ((RadioButton) all.get("scrape_layer")).activate((int) j.getFloat("scrape_only"));
    if (j.hasKey("boxOn")) {
      // settings saved when SHADOW BOX and IMPASTO were boxes of their own, with a light each
      boolean box = j.getFloat("boxOn") > 0.5, thick = j.getFloat("impastoOn", 0) > 0.5;
      for (int i = 0; i < LAYERS; i++) {
        if (!box || !j.hasKey("layerGap" + i)) {
          all.get("layerGap" + i).setValue(0);
          all.get("boxRim" + i).setValue(0);
        }
        all.get("layerImpasto" + i).setValue(thick ? j.getFloat("layerImpasto" + i, 1) * j.getFloat("impastoRelief", 0.5) : 0);
      }
      if (thick && !box) {
        all.get("lightFrom").setValue(j.getFloat("impastoFrom", 135));
        all.get("lightHeight").setValue(j.getFloat("impastoHeight", 35));
      }
      all.get("lightShine").setValue(j.getFloat("impastoGloss", 0.3));
    }
    if (j.hasKey("lightFrom") && !j.hasKey("lightFrom0")) {
      // settings saved when there was one light for every layer: each layer's is that one
      for (int i = 0; i < LAYERS; i++) {
        all.get("lightFrom" + i).setValue(j.getFloat("lightFrom", 135));
        all.get("lightHeight" + i).setValue(j.getFloat("lightHeight", 35));
        ((ColorPicker) all.get("shadowColour" + i)).setColorValue(j.getInt("shadowColour", 0xFF000000) | 0xFF000000);
      }
    }
    if (j.hasKey("accent") && !j.hasKey("accentHue_lo")) {
      // settings saved when the accent was one colour: ranges just round it
      int a = j.getInt("accent");
      float[] hsb = java.awt.Color.RGBtoHSB(a >> 16 & 255, a >> 8 & 255, a & 255, null);
      ((Range) all.get("accentHue")).setRangeValues(max(0, hsb[0] * 360 - 5), min(360, hsb[0] * 360 + 5));
      ((Range) all.get("accentSat")).setRangeValues(max(0, hsb[1] * 100 - 5), min(100, hsb[1] * 100 + 5));
      ((Range) all.get("accentBri")).setRangeValues(max(0, hsb[2] * 100 - 5), min(100, hsb[2] * 100 + 5));
    }
    if (j.hasKey("areaColours")) {
      boolean[] ap = new boolean[PALETTE_SIZE];
      JSONArray a = j.getJSONArray("areaColours");
      for (int i = 0; i < a.size(); i++) if (a.getInt(i) >= 0 && a.getInt(i) < ap.length) ap[a.getInt(i)] = true;
      areaPick = ap;
    }
    if (j.hasKey(patchKey[0])) loadPicks(j);
    if (j.hasKey("recolourLayers")) {
      JSONArray layersJ = j.getJSONArray("recolourLayers");
      for (int L = 0; L < LAYERS && L < layersJ.size(); L++) {
        JSONObject o = layersJ.getJSONObject(L);
        loadRecolour(L, o.getJSONArray("palette"), o.getJSONArray("changes"));
      }
    } else if (j.hasKey("recolourPalette") && j.hasKey("recolourChanges")) {
      // settings saved before each layer had its own: the one palette on every layer
      for (int L = 0; L < LAYERS; L++) loadRecolour(L, j.getJSONArray("recolourPalette"), j.getJSONArray("recolourChanges"));
    }
    // (after the controls: choosing the scheme above made a new palette, and this replaces it)
    if (j.hasKey("paletteGen")) {
      JSONObject po = j.getJSONObject("paletteGen");
      JSONArray pal = po.getJSONArray("palette"), ch = po.getJSONArray("changes");
      int[] base = new int[pal.size()];
      float[][] adj = new float[pal.size()][];
      for (int i = 0; i < base.length; i++) {
        base[i] = pal.getInt(i);
        adj[i] = new float[] { ch.getFloat(i * 3), ch.getFloat(i * 3 + 1), ch.getFloat(i * 3 + 2) };
      }
      palettePicked = new boolean[base.length];
      paletteAdj = adj;
      paletteBase = base;
      paletteSchemeMade = po.getInt("scheme", 0);
      paletteHueMade = po.getInt("hue", 0);
      showPaletteChosen();
    }
    if (includeSetup && j.hasKey("face")) {
      int i = java.util.Arrays.asList(faces).indexOf(j.getString("face"));
      if (i >= 0) all.get("source").setValue(i);
    }
    // (after the palette) RECOLOUR's swatches as loaded. The view is left as the settings have it
    chooseRecolour((int) value("recolourLayer"));
    recolourShown = recolourMap();
    recolourShowBefore = 0;
    applying = false;
    layoutWanted = true;
  }

  // move every slider that can change while running a random bit (not the speed, and not
  // "how far" itself) - a quick way to stumble on settings you wouldn't have tried
  void nudgeAll() {
    float amount = all.get("nudgeAmount").getValue();
    for (String n : liveNames) {
      ControllerInterface c = all.get(n);
      if (!(c instanceof Slider) || n.equals("nudgeAmount") || n.equals("pace") || n.endsWith("perFrame") || n.endsWith("_rate")) continue;
      if (n.startsWith("palette") || (recolourKind > 0 && n.startsWith("recolour"))) continue;      // PALETTE GEN isn't part of the painting (yet)
      Slider s = (Slider) c;
      // (a layer that's flat stays flat)
      if ((n.startsWith("layerGap") || n.startsWith("boxRim") || n.startsWith("layerImpasto")) && s.getValue() == 0) continue;
      float range = s.getMax() - s.getMin();
      s.setValue(constrain(s.getValue() + random(-0.5, 0.5) * range * amount, s.getMin(), s.getMax()));
    }
  }

  // every setup box's controls locked while running (`on`), all the others (but VIEW's) while the
  // rest of the panel is greyed out. (RUN, PAUSE and STEP are seen to in draw())
  void lockSetup(boolean on) {
    for (String n : all.keySet()) {
      ControllerInterface c = all.get(n);
      boolean lock = (on && setupGroup.contains(n)) || (gated && !setupGroup.contains(n) && !viewGroup.contains(n));
      if (c instanceof RadioButton) {
        for (Toggle t : ((RadioButton) c).getItems()) t.setLock(lock);
      } else if (c instanceof Controller) {
        ((Controller) c).setLock(lock);
      } else if (c instanceof ColorPicker) {
        for (String k : new String[] { "-red", "-green", "-blue" }) cp5.getController(n + k).setLock(lock);
      }
    }
    for (String n : buttons.keySet()) {
      if (n.equals("runStop") || n.equals("pauseRun") || n.equals("stepRun")) continue;
      buttons.get(n).setLock(gated && !setupGroup.contains(n) && !java.util.Arrays.asList(alwaysButtons).contains(n));
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
    inTools = false;
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
    cur.band = curBand;
    cur.section = sections - 1;
    cur.toolSetting = inTools;
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
    if (inSetup) setupGroup.add(name);
    if (inView) viewGroup.add(name);
  }

  // a tool's box in column 2: its name with an on / off box - red off, green on. The rows made
  // after it with toolSlider() etc. are its shape settings, shown while it's on
  void toolBox(int i, boolean on) {
    inTools = false;                     // (its title isn't one of its settings)
    curTool = TOOLS[i];
    sections++;
    toolSection[i] = sections - 1;
    row(31);                             // (kept tight so the column ends above RUN's strip)
    Toggle t = cp5.addToggle(curTool + "_on").setSize(20, 20).setValue(on);
    t.setColorBackground(toolOff).setColorForeground(toolOffHover).setColorActive(toolOn);
    t.setCaptionLabel(toolTitles[i]);
    t.getCaptionLabel().align(ControlP5.RIGHT_OUTSIDE, ControlP5.CENTER).setPaddingX(8);
    register(curTool + "_on", t);
    put(t, 0, 6);
    inTools = true;
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
    for (int k = 0; k < S_COUNT; k++) if (boxNames[k] == null) { boxNames[k] = title; break; }
    cur.dx.set(0, 20);                   // room for the square before it (drawn in draw())
    return sections - 1;
  }

  // where setup box k's rows start in column 1 (k = S_COUNT: where the last one ends), and where
  // the rows only shown while it's open start
  void setupStart(int k) {
    boxRowFrom[k] = columns.get(columns.size() - 1).size();
  }
  void setupContent(int k) {
    boxContentFrom[k] = columns.get(columns.size() - 1).size();
  }

  // SETUP 1's list: the pictures with maps, then opening a photo of your own
  String[] sourceItems() {
    String[] items = java.util.Arrays.copyOf(faces, faces.length + 1);
    items[faces.length] = OPEN_PICTURE;
    return items;
  }

  // (from the painter) the pictures have changed - a new one has its maps. i: the one to choose
  void newSources(int i) {
    sourceWanted = i;
    sourcesChanged = true;
    layoutWanted = true;
  }

  // Tab: this window to the front, or (Tab in this window) the painting's
  void toFront() {
    final java.awt.Frame f = ((processing.awt.PSurfaceAWT.SmoothCanvas) getSurface().getNative()).getFrame();
    java.awt.EventQueue.invokeLater(new Runnable() {
      public void run() {
        f.setState(java.awt.Frame.NORMAL);
        f.setAlwaysOnTop(true);
        f.toFront();
        f.requestFocus();
        f.setAlwaysOnTop(false);
      }
    });
  }

  // (the painting's window has to bring itself forward, on its own thread). The space bar pauses
  // and carries on, as PAUSE does - here as in the painting's window
  public void keyPressed() {
    if (key == TAB) command("front");
    else if (key == ' ') command("pause");
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
        sourceDone = true;
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
    if (chosen >= 0) r.activate(chosen);
    else r.deactivateAll();           // none
    r.setNoneSelectedAllowed(false);
    register(name, r);
    put(r, 0, 0);
  }

  // one of APPLY's choices: a click on it may close the box (see mouseReleased)
  void closesApply(String name) {
    for (Toggle t : ((RadioButton) all.get(name)).getItems()) {
      // (a callback: the one it already has sends no event)
      t.addCallback(new CallbackListener() {
        public void controlEvent(CallbackEvent e) {
          if (e.getAction() == ControlP5.ACTION_PRESS && !((Toggle) e.getController()).isLock()) layerClicked = true;
        }
      });
    }
  }

  // radio buttons in the current row, at dx, spaced `step` apart (for short items like "1" "2" "3").
  // chosen -1: none is, until one's clicked
  void radioAt(String name, String[] items, int chosen, float dx, int step) {
    RadioButton r = cp5.addRadioButton(name).setSize(16, 16).setItemsPerRow(items.length)
      .setSpacingColumn(step - 16);
    for (int i = 0; i < items.length; i++) {
      r.addItem(name + " " + i, i);
      r.getItem(i).setCaptionLabel(items[i]);
    }
    if (chosen >= 0) r.activate(chosen);
    else r.deactivateAll();           // none
    r.setNoneSelectedAllowed(false);
    register(name, r);
    put(r, dx, 2);
  }

  // a layer box's title: a shorter header row than header()'s. Returns its section
  int layerHeader(String text) {
    sections++;
    row(26);
    Textlabel t = cp5.addTextlabel("header " + text).setText(text).setColorValue(color(20));
    put(t, -4, 8);
    return sections - 1;
  }

  // one of a layer box's small sliders, its caption above it
  Slider boxSlider(String name, String caption, float lo, float hi, float value, float dx) {
    Slider s = sliderAt(name, caption, lo, hi, value, dx, 14, 70);
    s.getCaptionLabel().align(ControlP5.LEFT, ControlP5.TOP_OUTSIDE).setPaddingX(0);
    return s;
  }

  // a colour: its name, then red, green and blue sliders over a strip of the colour
  // a range slider: two handles, a low and a high limit (the painter reads name_lo and name_hi)
  void range(String name, String caption, float lo, float hi, float low, float high) {
    row(22);
    Range r = cp5.addRange(name).setSize(170, 16).setRange(lo, hi);
    r.setDecimalPrecision(0);       // first, so the handles' numbers are whole too
    r.setRangeValues(low, high);
    r.setCaptionLabel(caption);
    register(name, r);
    put(r, 0, 0);
  }

  void colourPicker(String name, String caption, int c) {
    row(84);
    label(caption, 0);
    ColorPicker p = cp5.addColorPicker(name).setColorValue(c | 0xFF000000);
    cp5.getController(name + "-alpha").hide();     // always solid
    register(name, p);
    put(p, 0, 20);
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
    buttons.put(name, b);
    if (inSetup) setupGroup.add(name);
    put(b, dx, 0);
    return b;
  }
}
