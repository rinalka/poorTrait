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
| masses: blobs, roundness, join, smooth edges, number of colours | How the photo is cut into the masses. See MASSES below. |

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
| show | What appears in the window or on the mesh: the painting, the photo, the masses, or one of the maps |
| direction field | (2D) Draws the lines the marks follow over the picture |
| mesh background, sway, STRAIGHT ON | (mesh) Background colour, a gentle side-to-side turn, and resetting the view |
| light on | (mesh) Turns the light on or off. With it off, the model shows its picture's true colours with no shading, which helps when judging the masses' colours. The **l** key does the same. |

**Moving the mesh:** drag to turn it, right-drag to move the light, and use the wheel to zoom.

### BRUSH

| Control | What it does |
|---|---|
| bristle stroke / palette knife | The kind of mark. Bristle strokes are long, curving ribbons that taper. Knife marks are short, flat slabs with a ridge and a torn end. |
| marks per frame | How fast it paints. 0 turns the brushes off, for example to paint only splatters. |
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

### ABSTRACTION

These controls decide how much of the face the marks may break up. They use the importance map,
which records how much each part of the picture matters for recognising the face.

| Control | What it does |
|---|---|
| on | Switches ABSTRACTION off: nothing is protected, and marks and splatters go anywhere. The other controls show once it's on. |
| abstraction | At 0, everything that matters is protected and marks stay off the face. At 1, marks go anywhere. In between, the less important parts go first. |
| anchors | The most important few spots (eyes, nostrils, mouth) are always protected, however high the abstraction is. Raise it to keep more of them. |
| protected parts get | **no marks**: whatever is underneath (the masses or the photo) stays readable. **careful marks**: small marks that follow the form, in the photo's exact colours, which repair the features as the painting goes on. |
| careful mark size | (careful marks) How big the careful marks are, compared with the others |
| show protected parts | (2D) Shows the protected parts in red |

### COLOUR

| Control | What it does |
|---|---|
| pick up from | Where the paint comes from: **photo**, **canvas (wet)** (what's already painted, so marks smear into each other), a **mix** of the two, or the **masses** (their palette, so the palette sliders below change the marks' colours too) |
| carry | What the brush holds: **one colour**; **start to end** (fades from one colour to another); **two colours** (one down each side); **chunk** (a piece of the picture, smeared along the mark); **copy** (copies the picture through the mark's shape) |
| hue / saturation / brightness jitter | Random changes to each mark's colour |
| accent colour + chance | Now and then a mark is painted in this colour instead |

### APPLY

| Control | What it does |
|---|---|
| opacity | How solid each mark is |
| see-through washes | The share of marks painted thin and see-through |
| blend | How marks combine with the paint underneath: normal, multiply (darkens), screen (lightens), and so on |

### MASSES

The masses are the photo cut into large patches, each painted one of a few colours. They are
the painting's large colour regions.

How the photo is cut up is part of SETUP, so it stays fixed for a whole run. The masses are
worked out in the background when you pick a picture, and again whenever one of SETUP's masses
sliders changes (once you let go of the slider). They take a few seconds. The status line at the
bottom of the panel shows their progress. If you press RUN before they're ready, the panel says
"waiting for the masses" and the run starts once they are.

In SETUP:

| Control | What it does |
|---|---|
| blobs | How many small patches the photo is cut into first |
| roundness | Low values give patches that follow the photo's edges, high values give rounder, more even patches |
| join similar neighbours | Joins touching patches that are close in colour. Higher values give fewer, bigger masses. |
| smooth edges | Rounds off the jagged edges between masses |
| number of colours | How many colours the masses are painted with (2–32) |

In MASSES (these can change during a run):

| Control | What it does |
|---|---|
| start the canvas with | What the canvas holds at RUN and CLEAR: the **plain** canvas colour, the **masses**, or the **photo**. Starting with the masses and then breaking them up with marks is the idea behind ABSTRACTION. |
| LAY ON NOW + opacity | Lays the masses over the painting as it is now, as see-through as the opacity slider says |
| textured paint, NEW TEXTURE | Gives each colour a mottled, streaky texture instead of flat colour. NEW TEXTURE picks different textures. |
| palette hue / saturation / brightness | Shift the hue and scale the saturation and brightness of every colour in the palette at once. They change instantly. |

### SPLATTER

Splatters are a separate mark system, painted alongside the brushes. Each splatter is a
cluster: usually a big splat in the middle, with drops scattered round it. Most drops land near
the middle and a few fly far. Most are tiny, a few are big, and the big ones have little satellite
droplets. Some clusters fling long, thin trails outwards that end in a drop.

Clusters are placed by MOVEMENT's "start at", like brush marks, so "mouse" lets you splatter by
hand. They respect ABSTRACTION: no drop lands on a protected part.

| Control | What it does |
|---|---|
| splatter | Turns splatters on. The other controls show once it's on. |
| clusters per frame | How often. Below 1 means not every frame: 0.3 is about 3 frames in 10. |
| drops per cluster | How many drops are scattered round each splat |
| size | The size of the biggest splat |
| how many big drops | At 0 nearly every drop is tiny. Higher values give more big drops. |
| spread | How far the drops scatter |
| flung trails | How many clusters throw long, thin trails, and how many |
| opacity | How solid the drops are |
| colour | **picked up** (as COLOUR's "pick up from" says, where the cluster lands) or the **accent colour** |
| contrast with the photo | Pushes the colour away from the photo's lightness where it lands: light drops on dark parts, dark drops on light parts |
| colour variation | How much each drop's colour varies from the cluster's |

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

**space**: pause  **c**: clear  **s**: save  **r**: straight on (mesh)  **l**: light on/off (mesh)

## Tips

- Start with the defaults, press RUN, and move one slider at a time while it paints.
  New marks go on top of the old ones, so a single painting can hold several settings in
  layers.
- Start the canvas with the masses, keep abstraction around 0.5 with careful marks on, and
  let it paint. The face stays readable while everything around it breaks up.
- Try a big, loose first layer, then smaller marks by importance.
- Canvas (wet) with chunk smears the painting into itself. It gets muddy fast, which can be
  good.
- When you get something you like, press SAVE. The `.json` keeps every setting, so LOAD
  SETTINGS can bring them all back later.
- The painting is always saved at the photo's size, so it lines up with the maps and models.
