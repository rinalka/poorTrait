// Auto: painting from a script instead of the panel - for trying settings out without clicking.
//
// Only when the environment variable PAINTER_SCRIPT names a .json file (otherwise nothing here
// runs). The script:
//   "setup":  settings as in a saved .json (any of them, SETUP's too), with "face": the picture
//   "stages": a list, each { "name", "set": settings changed at its start, "do": commands (as the
//             panel's buttons send them, e.g. "cutObjects"), "frames": how many frames it paints }
//   "out":    a folder for a picture of the painting after each stage (optional)
// It picks the picture, applies "setup", waits for the masses, presses RUN, goes through the
// stages, then SAVEs (into saved/, as SAVE does) and closes.

JSONObject autoScript;
int autoStage = -2;            // -2: not started, -1: waiting to RUN, then the stage painting
int autoFrames = 0;            // frames painted in this stage
int autoWait = 0;

void autoStep() {
  if (autoStage == -2 && autoScript == null) {
    String p = System.getenv("PAINTER_SCRIPT");
    if (p == null || p.equals("")) { autoStage = -99; return; }
    autoScript = loadJSONObject(p);
    JSONObject s = autoScript.getJSONObject("setup");
    panel.applySettings(s, true);
    panel.sourceDone = panel.massesDone = panel.outlineDone = panel.meshDone = true;
    panel.paletteDone = panel.startDone = panel.backdropDone = true;
    println("auto: " + p + " - " + s.getString("face"));
    autoStage = -1;
    return;
  }
  if (autoStage < -1) return;
  JSONArray stages = autoScript.getJSONArray("stages");
  if (autoStage == -1) {
    // the picture loaded and its masses made, then RUN
    String face = autoScript.getJSONObject("setup").getString("face");
    if (!faceName.equals(face) || massesPending() || ++autoWait < 30) return;
    startRun();
    autoBegin(0);
    return;
  }
  if (isRunning && !isPaused) autoFrames++;
  JSONObject st = stages.getJSONObject(autoStage);
  if (autoFrames < st.getInt("frames")) return;
  if (autoScript.hasKey("out")) {
    String out = autoScript.getString("out");
    new java.io.File(out).mkdirs();
    canvas.save(out + "/" + nf(autoStage + 1, 2) + "-" + st.getString("name", "stage") + ".png");
  }
  println("auto: stage " + (autoStage + 1) + " done, " + markCount + " marks");
  if (autoStage + 1 < stages.size()) autoBegin(autoStage + 1);
  else {
    saveAll();
    println("auto: finished");
    exit();
  }
}

void autoBegin(int k) {
  autoStage = k;
  autoFrames = 0;
  JSONObject st = autoScript.getJSONArray("stages").getJSONObject(k);
  if (st.hasKey("set")) {
    JSONObject set = st.getJSONObject("set");
    // the stage's tool on (which switches the others off)
    for (String t : TOOLS) if (set.hasKey(t + "_on") && set.getFloat(t + "_on") > 0.5) panel.all.get(t + "_on").setValue(1);
    panel.applySettings(set, true);
  }
  if (st.hasKey("do")) {
    JSONArray d = st.getJSONArray("do");
    for (int i = 0; i < d.size(); i++) handle(d.getString(i));
  }
  println("auto: stage " + (k + 1) + "  " + st.getString("name", ""));
}
