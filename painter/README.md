# PoorTrait painter: a quick guide

The painter turns a photo into a semi-abstract painting. It lays down thousands of marks,
and maps worked out from the photo steer them: their size, direction, colour and how see-through
they are. You can paint on a flat 2D canvas or straight onto a 3D model of the face.

You change things on a control panel while it paints. The point is to experiment and find
looks you couldn't have planned.

## What you need

- **Processing 4** (made with 4.5.7): <https://processing.org/download>
- **controlP5**, a library for Processing. In Processing, go to *Sketch > Import Library >
  Manage Libraries*, search for *controlP5* and click Install.
- **Maps for your photos**, made by the map maker in [../mapmaker](../mapmaker). Its README
  explains how to set up Python for it.

## 1. Make the maps

From the `mapmaker` folder:

```
.venv\Scripts\python mapmaker.py ..\myPhotos\*.jpg --out ..\myPhotos\maps
```

Or double-click `mapmaker.bat` and pick the photos. Each photo gets its own folder of maps:
the normal map, depth, importance, curvature, lighting, and two 3D models.

Photos with one clear face, front-on or three-quarter, work best. The first run downloads
about 450 MB of models.

## 2. Point the painter at the maps

Open `painter/painter.pde` in Processing. In the **Maps** tab, set the `mapsFolder` line to
where your maps are, relative to the `painter` folder:

```java
String mapsFolder = "../myPhotos/maps";
```

If you made the maps without `--out`, use `"../mapmaker/maps"`.

## 3. Run it

Press **Ctrl+R** in Processing (or the play button). Two windows open:

- **The output window**, which is the size of the photo
- **The control panel**

Pick a photo under SETUP, then press **RUN**.

## The control panel

Controls that don't apply to your current choices are hidden. For example, the knife
settings only appear when the palette knife is chosen.

### SETUP: fixed for a whole run

| Control | What it does |
|---|---|
| source | Which photo to paint |
| output | **2D canvas**, **mesh: just the person** (a 3D model of the face), or **mesh: whole photo** (the whole picture as a relief) |
| canvas colour | The colour the painting starts on |

These controls are locked while a run is going. Press STOP to change them.

### RUN

| Button | What it does |
|---|---|
| RUN / STOP | Start a new painting, or end the run. The painting stays on screen after STOP. |
| PAUSE | Freeze the painting. You can still turn the mesh. |
| CLEAR | Wipe the canvas and keep painting |
| SAVE | Save the painting and every setting to `painter/saved/`. For a mesh it also saves the view as you see it. |
| LOAD SETTINGS | Load the settings from a saved `.json` |
| NUDGE + how far | Shift every live setting by a random amount. "how far" sets how big the change is. Good for when you're stuck. |

### VIEW

| Control | What it does |
|---|---|
| show | What appears in the window or on the mesh: the painting, the photo, or one of the maps |
| direction field | (2D) Draws the lines the marks follow over the picture |
| mesh background, sway, STRAIGHT ON | (mesh) Background colour, a gentle side-to-side turn, and resetting the view |

**Moving the mesh:** drag to turn it, right-drag to move the light, and use the wheel to zoom.

### BRUSH

| Control | What it does |
|---|---|
| bristle stroke / palette knife | The kind of mark. Bristle strokes are long, curving ribbons that taper. Knife marks are short, flat slabs with a ridge and a torn end. |
| marks per frame | How fast it paints |
| size | How long each mark is, in pixels |
| width | Width as a share of the length. Low values make thin lines, 1 makes square dabs. |
| ragged edges | How rough the edges are |
| pointed end | (stroke) How much the end tapers |
| streaks | (knife, flat colours only) Streaks of a second colour dragged through the mark |
| leaf shapes | (knife) The share of marks pointed at both ends |
| ridge along the edge | (knife) The piled-up paint along the knife's edge |

### MOVEMENT

| Control | What it does |
|---|---|
| follow the form | How closely marks follow the shape of the face. At 1 they lie along the form, at 0 they point anywhere. |
| around the form / across it | Marks wrap around the face like contour lines, or cross it |
| field smoothing | How smooth the direction field is. Changes when you let go of the slider. |
| bend along the form | (stroke) How much a stroke curves as it goes |
| start at | Where marks land: **random**, **weighted by map** (more marks where the chosen map is light), **grid** (rows across the picture), or **mouse** (2D only; hold a mouse button down in the output window and paint by hand) |

### COLOUR

| Control | What it does |
|---|---|
| pick up from | Where the paint comes from: **photo**, **canvas (wet)** (what's already painted, so marks smear into each other), or **mix** of the two |
| carry | What the brush holds: **one colour**; **start to end** (fades from one colour to another); **two colours** (one down each side); **chunk** (a piece of the picture, smeared along the mark); **copy** (copies the picture through the mark's shape) |
| hue / saturation / brightness jitter | Random changes to each mark's colour |
| accent colour + chance | Now and then a mark is painted in this colour instead |

### APPLY

| Control | What it does |
|---|---|
| opacity | How solid each mark is |
| see-through washes | The share of marks painted thin and see-through |
| blend | How marks combine with the paint underneath: normal, multiply (darkens), screen (lightens), and so on |

## Letting the maps decide

Size, follow the form and opacity each have a **by** list underneath them. Choose a map there
and the setting changes from place to place across the picture:

- **by**: which map to use
  - **importance**: the parts that make the face recognisable (eyes, nose, mouth)
  - **curvature**: bumps and hollows
  - **depth**: near and far
  - **light**: the face lit by a made-up light
  - **photo lightness**
  - **saturation**: how strong the colour is
- **amount**: how much the map counts. At 1, the setting is at full strength where the map is
  white and drops to nothing where it's black. At 0 the map does nothing.
- **invert**: swaps the map's light and dark

For example, size by importance with invert on gives small, careful marks on the eyes and
mouth and big, loose ones everywhere else. Follow the form by importance gives marks that
hug the face in the middle and scatter at the edges.

## Keys (in the output window)

**space**: pause  **c**: clear  **s**: save  **r**: straight on (mesh)

## Tips

- Start with the defaults, press RUN, and move one slider at a time while it paints.
  New marks go on top of the old ones, so a single painting can hold several settings in
  layers.
- Try a big, loose first layer, then smaller marks by importance.
- Canvas (wet) with chunk smears the painting into itself. It gets muddy fast, which can be
  good.
- When you get something you like, press SAVE. The `.json` keeps every setting, so LOAD
  SETTINGS can bring them all back later.
- The painting is always saved at the photo's size, so it lines up with the maps and models.
