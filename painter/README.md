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

Work down SETUP 1 to 5 (each box's square turns from red to green when it's done), then press **RUN**.

## The control panel

The panel has four columns:

1. **SETUP 1–4**: the photo, 2D or a mesh, the large colour masses the painting can start
   from, and what the canvas starts with.
2. **The tools**: what does the drawing. These are BRUSH, PALETTE KNIFE, SPLATTER, LINES,
   FRAGMENTS, PENCIL and SCRAPE. Only one tool paints at a time.
3. **MOVEMENT, COLOUR, APPLY**: how a tool moves and where it lands, where its colour comes from,
   and how solid it is. These belong to **the tool that's on in column 2**: every tool has its
   own set.
4. **ABSTRACTION, LAYERS, SHADOW BOX, IMPASTO**: where the face may be broken up, the four
   layers, the layers floating apart with light and shadow between them, and thick paint
   catching the light.

Along the bottom of the window are **VIEW** (what you're looking at) and **CAMERA**, under
column 1, and **RUN**, under column 2.

**Choosing a tool:** click the box beside a tool's name (or the name itself). The box is **red**
when the tool is off and **green** when it's on. Switching a tool on switches the one that was
on off, so only one tool paints at a time. The tool that's on gets a dark frame and its box
opens to show its shape settings, and columns 3 and 4 switch to its settings. Their headings
show which tool that is, for example "MOVEMENT - splatter". The other tools keep their settings
while they're off. If you switch every tool off, nothing paints, and columns 3 and 4 keep
showing the last tool's settings under a grey cover.

Controls that don't apply to your current choices are hidden. For example, the map settings
under "start at" only appear when "weighted by map" is chosen.

## Column 1

### SETUP 1 to 5

The setup is five boxes, done in order. Click a box to set it up. Each has a square before its
title: red until it's done, then green. SETUP 1 to 3 stay fixed for a whole run, so they're locked
while a run is going (except the palette sliders in SETUP 3). Press STOP to change them. SETUP 4
and 5 can change during a run: the backdrop changes straight away, and the start is used at the
next CLEAR.

| Box | What it does |
|---|---|
| SETUP 1  SOURCE | Click it for a list of the photos, and pick one. Its name shows under the title. |
| SETUP 2  TARGET | Click it to choose **2D canvas**, **mesh: just the person** (a 3D model of the face) or **mesh: whole photo** (the whole picture as a relief). For 2D canvas, the canvas colour wheel appears under it: the colour the painting starts on. |
| SETUP 3  MASSES | Click it to open the masses' sliders (below). The output window shows the masses as they are now, with the light off so their colours are true. When they look right, click the box's title: the sliders close, the view goes back to what it was, and the box turns green. |
| SETUP 4  BACKDROP | What the canvas sits on: the bottom of the whole stack, under the canvas. Choose **none** (plain white), **canvas weave**, **paper** or a collage of **newspaper** cuttings (more to come). It shows wherever the canvas is see-through (its **transparency** in LAYERS) or hidden (VIEW's LAYERS). **strength** fades it towards white. **shows through the paint** lets it come through everything above it too, the way a coarse canvas's weave does; with IMPASTO on, a weave or paper also gets bumps that catch the light. It changes straight away. |
| SETUP 5  START | What the canvas, under the four layers, holds at RUN and CLEAR: the **plain** canvas colour, the **masses**, or the **photo**. Starting with the masses and then breaking them up with marks is the idea behind ABSTRACTION. The choices are always showing; the box is done once you click one. Once it's done, and until the first RUN on this picture, the output window shows what the painting will start on: the backdrop with the canvas over it, following any changes to SETUP 4 and 5, the canvas colour and the LAYERS settings. After a run the painting stays on screen instead. |

Picking a new photo turns SETUP 3 back from green, because the new photo has new masses to look
at.

**The masses** are the photo cut into large patches, each painted one of a few colours. They are
the painting's large colour regions. They're worked out in the background when you pick a photo,
and again whenever one of the first five sliders changes (once you let go of it). They take a few
seconds, and the box shows their progress. If you press RUN before they're ready, the panel says
"waiting for the masses" and the run starts once they are.

| Control | What it does |
|---|---|
| blobs | How many small patches the photo is cut into first |
| roundness | Low values give patches that follow the photo's edges, high values give rounder, more even patches |
| join similar neighbours | Joins touching patches that are close in colour. Higher values give fewer, bigger masses. |
| smooth edges | Rounds off the jagged edges between masses |
| number of colours | How many colours the masses are painted with (2–32) |
| palette hue / saturation / brightness | Shift the hue and scale the saturation and brightness of every colour in the palette at once. They change instantly, and can be changed during a run. |

## Along the bottom

### VIEW

VIEW has two lists side by side, always open.

| List | What it does |
|---|---|
| MAPS | **none** shows the painting. Or show one of the maps in its place: the photo, normal, importance, curvature, depth, light, or the masses. **While a map is showing, nothing paints:** a run pauses, and RUN and CARRY ON are greyed out until you choose **none** again. |
| LAYERS | The stack, top first, like Photoshop's layers panel, with the **canvas** (what SETUP 5 started it with) and under it the **backdrop** (SETUP 4) always at the bottom: those two can't be moved. Tick boxes show and hide the layers and the canvas; the backdrop is always on. **^** and **v** move a layer up or down the stack. A layer takes its paint and its settings with it, and the tools that paint on "layer 2" keep painting on layer 2 wherever it is. SAVE keeps the order, and LOAD SETTINGS puts it back. |

### CAMERA

| Control | What it does |
|---|---|
| direction field over the picture | (2D) Draws the lines the marks follow |
| direction field smoothing | How smooth the direction field is, for every tool. Changes when you let go of the slider. |
| mesh background, sway, STRAIGHT ON | (mesh) Background colour, a gentle side-to-side turn, and resetting the view |
| light on | (mesh) Turns the light on or off. With it off, the model shows its picture's true colours with no shading. The **l** key does the same. |

**Moving the mesh:** drag to turn it, right-drag to move the light, and use the wheel to zoom.

### RUN

RUN sits beside VIEW, level with its top.

| Button | What it does |
|---|---|
| RUN / STOP | Start a new painting (green **RUN**), or end the run (red **STOP**). The painting stays on screen after STOP. |
| PAUSE / CARRY ON | Freeze the painting. You can still turn the mesh. Green **PAUSE** while it's painting, orange **CARRY ON** while it's paused. |
| STEP | While paused, paints one step: one frame's worth of marks, as the tool's settings say (for example 20 knife marks at "marks per frame" 20). Change a setting, press STEP, look. The **n** key in the output window does the same. |
| painting speed | Slows the painting down so you can follow it: from **full speed** (a step every frame, about 60 a second) down to one step every 2 seconds. Only the painting slows, so the window and the panel stay smooth. Each step still paints the tool's marks per frame, so for the slowest pace set that low too. |
| CLEAR | Reset the canvas and every layer, and keep painting |
| SAVE | Save the painting, the backdrop, the canvas and each layer (as see-through PNGs you can stack in Photoshop), the paint's height (IMPASTO), and every setting, to `painter/saved/`. For a mesh it also saves the view as you see it. |
| LOAD SETTINGS | Load the settings from a saved `.json` |
| NUDGE + how far | Shift every live setting, for every tool, by a random amount. "how far" sets how big the change is. Good for when you're stuck. |
| PRINT | Save what the output window shows now, at the photo's size, to `painter/saved/` as `...-print.png`. That's whatever VIEW shows (the painting or a map), the mesh as you've turned it, and the direction field or protected parts if they're showing. |

## Column 2: the tools

Each tool has a red / green on-off box (see "Choosing a tool" above). The settings below are the
ones that open in the tool's box while it's on. How fast a tool works is set in its box:
marks, clusters, lines or fragments **per frame**. Below 1 means not every frame: 0.3 is about 3
frames in 10.

All the tools respect ABSTRACTION: they stay off protected parts. Brush and palette knife can
make careful marks there instead.

### BRUSH

Long, curving bristle strokes that taper.

| Control | What it does |
|---|---|
| marks per frame | How fast it paints |
| size | How long each mark is, in pixels. It has a "by" row, see "Letting the maps decide". |
| width | Width as a share of the length. Low values make thin lines, 1 makes square dabs. |
| ragged edges | How rough the edges are |
| pointed end | How much the end tapers |
| bend along the form | How much a stroke curves to follow the form as it goes |

### PALETTE KNIFE

Short, flat slabs of paint with a ridge along one edge and a torn end.

| Control | What it does |
|---|---|
| marks per frame, size, width, ragged edges | As for BRUSH |
| streaks of a second colour | Streaks dragged through the mark. Only for flat colours, so hidden when COLOUR's carry is chunk or copy. |
| leaf shapes | The share of marks pointed at both ends |
| ridge along the edge | The piled-up paint along the knife's edge |

### SPLATTER

Each splatter is a cluster: usually a big splat in the middle, with drops scattered round it.
Most drops land near the middle and a few fly far. Most are tiny, a few are big, and the big ones
have little satellite droplets. Some clusters fling long, thin trails outwards that end in a drop.

| Control | What it does |
|---|---|
| clusters per frame | How often |
| drops per cluster | How many drops are scattered round each splat |
| size | The size of the biggest splat |
| how many big drops | At 0 nearly every drop is tiny. Higher values give more big drops. |
| scatter | How far the drops scatter |
| flung trails | How many clusters throw long, thin trails, and how many |
| drop colour variation | How much each drop's colour varies from the cluster's |

### LINES

Fine lines that wander like a pen drawn loosely across the picture. Each line curves one way and
then another, and its width changes along it like pen pressure, thin at both ends.

| Control | What it does |
|---|---|
| lines per frame | How often |
| length, width | How long and how thick the lines are |
| wander | How much a line curves about. At 0 lines go nearly straight. |
| broken | How often a line skips, leaving gaps |

For lines, MOVEMENT's "follow the form" is the share of lines pulled along the form, like
contour lines. The rest ignore it.

### FRAGMENTS

Tiny dots, dashes, triangles and shards, for surface complexity.

| Control | What it does |
|---|---|
| fragments per frame | How many |
| size | The size of the biggest ones. Most are smaller. |
| clumping | The share that land near the one before, so they gather in little drifts instead of spreading evenly |
| dots, dashes, triangles, shards | Which kinds to make |

For fragments, MOVEMENT's "follow the form" is the share turned along the form.

### PENCIL

Lines that grow a little every frame, as if someone were sketching with a coloured pencil. A few
pencils are on the paper at once. Each moves on until its line is long enough, then lifts, and
(with more than one pass) goes down again close to where that line began and goes over it again,
a little off, like the searching, repeated lines of a sketch.

| Control | What it does |
|---|---|
| trace the edges / flow from the map / wander | How the pencil steers. **Trace the edges**: it walks along the edge of the dark parts of the map, where the map crosses **level**, the way you'd draw round a shape. **Flow from the map**: postContemp's continuous flow. The map's value where the pencil is gives a direction (dark 0 degrees, light all the way round), and the pencil keeps turning towards it, making swirls. **Wander**: postContemp's random walk, a new direction now and then, pulled along the form as much as MOVEMENT's "follow the form" says. |
| map | The map it follows. **light** (the default) outlines the shading. **photo lightness** follows the photo's own light and dark. |
| follow the light parts | Turns the map over, so the pencil traces the light parts instead |
| level | Where the edge is: the pencil traces the line where the map is this light. Low values outline only the darkest parts. Hatching also uses it: it only goes where the map is darker than this. |
| how tightly it steers | (trace and flow) Low values let the line drift off the edge and come back, like a loose hand. High values trace it closely. |
| turn the flow | (flow) Turns every direction by this many degrees |
| pencils at once | How many lines are being drawn at the same time |
| speed | How far each pencil moves in a frame |
| line length | How long a line gets before the pencil lifts |
| passes over each line | How many times the pencil goes over each line |
| wobble | The unsteadiness of the hand |
| width | How thick the line is |
| pressure changes | How much the hand presses harder and lighter along a line |
| paper grain | How much the paper's tooth breaks up the line. The grain stays in place, so lines that go over the same spot catch the same grain. |
| hatching | Groups of short parallel strokes in the parts darker than **level**: closer together, longer and more of them where it's darker. Off at 0. |
| hatching angle | Which way the hatching goes |

Each line is one colour, picked up where it starts (COLOUR). COLOUR's "contrast with the photo"
makes the lines darker or lighter than what's under them, so they show. To use one pencil colour
for every line, set the accent chance to 1 and choose the accent colour. A pencil lifts over
protected parts (ABSTRACTION).

### SCRAPE

Takes paint off instead of putting it on. Each scrape removes paint from every layer above its
"scrape down to" layer, so what's on that layer (or under it) shows through: an
earlier stage of the painting or, scraping down to the **canvas**, what it started with (the
masses, the photo or the bare canvas colour).

| Control | What it does |
|---|---|
| knife scrape / scratches | **Knife scrape**: a broad palette-knife mark that leaves streaks of paint behind where it didn't quite catch. **Scratches**: short, thin, wandering lines scored through. |
| scrapes per frame | How often |
| length, width | Their size. Scratches are much thinner than the width says. |
| ragged edges | How rough a knife scrape's edges are |
| how much comes off | At 1 a scrape takes nearly everything. Lower values leave more behind. |
| scrape down to | What scraping reveals: the **canvas** (every layer is scraped) or a layer (every layer above it in the stack is scraped). |

Scrape has MOVEMENT settings but no COLOUR or APPLY.

## Column 3: the chosen tool's movement, colour and opacity

### MOVEMENT

| Control | What it does |
|---|---|
| follow the form | How closely marks follow the shape of the face. At 1 they lie along the form, at 0 they point anywhere. Splatter has no direction, so it doesn't have this. Brush and knife have a "by" row for it. |
| around the form / across it | Marks wrap around the face like contour lines, or cross it |
| start at | Where marks land: **random**, **weighted by map** (more marks where the chosen map is light), **grid** (rows across the picture), or **mouse** (2D only; hold a mouse button down in the output window and paint by hand) |

### COLOUR

| Control | What it does |
|---|---|
| pick up from | Where the paint comes from: **photo**, **canvas (wet)** (what's already painted, so marks smear into each other), a **mix** of the two, or the **masses** (their palette, so the SETUP 3 palette sliders change the tool's colours too) |
| carry | (brush and knife) What the brush holds: **one colour**; **start to end** (fades from one colour to another); **two colours** (one down each side); **chunk** (a piece of the picture, smeared along the mark); **copy** (copies the picture through the mark's shape) |
| contrast with the photo | (splatter, lines, fragments) Pushes the colour away from the photo's lightness where it lands: light marks on dark parts, dark marks on light parts |
| hue / saturation / brightness jitter | Random changes to each mark's colour |
| accent chance | How often a mark is painted in the accent colour instead. At 1, every mark is. |
| accent colour | The accent colour, shared by all the tools |

### APPLY

| Control | What it does |
|---|---|
| paints on layer | Which layer the tool paints on. By default brush and knife are on 2, lines and fragments on 3, and splatter and pencil on 4. |
| opacity | How solid each mark is. It has a "by" row. |
| see-through washes | The share of marks painted thin and see-through |
| blend | How marks combine with the paint already on their layer: normal, multiply (darkens), screen (lightens), and so on |
| thickness  (impasto) | How thick the tool's paint is, for IMPASTO's light. By default the knife is thickest (0.8), then the brush (0.5), splatter (0.4), fragments (0.25) and lines (0.1); the pencil is 0 (flat). Washes and see-through marks come out thinner. |

The blend works against what's already on the same layer. On an empty layer, modes like multiply
have nothing to work against, so use the layer's own blend in LAYERS instead.

## Column 4

### ABSTRACTION

These controls decide how much of the face the tools may break up. They use the importance map,
which records how much each part of the picture matters for recognising the face. ABSTRACTION is
shared by all the tools.

| Control | What it does |
|---|---|
| on | Switches ABSTRACTION off: nothing is protected, and every tool goes anywhere. The other controls show once it's on. |
| abstraction | At 0, everything that matters is protected and marks stay off the face. At 1, marks go anywhere. In between, the less important parts go first. |
| anchors | The most important few spots (eyes, nostrils, mouth) are always protected, however high the abstraction is. Raise it to keep more of them. |
| protected parts get | **no marks**: whatever is underneath (the masses or the photo) stays readable. **careful marks**: the brush and knife paint small marks that follow the form, in the photo's exact colours, which repair the features as the painting goes on. The other tools always stay off protected parts. |
| careful mark size | (careful marks) How big the careful marks are, compared with the others |
| show protected parts | (2D) Shows the protected parts in red |

### LAYERS

The painting is four see-through layers, one on top of another, on the canvas, which sits on the
backdrop. The canvas is the canvas colour with the masses or the photo on it (see SETUP 5), and
it's never painted on. The backdrop (SETUP 4) is under it and shows where the canvas is made
see-through. From the bottom: backdrop, canvas, layers 1 to 4 (the layers' order can change; the
backdrop and canvas stay at the bottom). The layers start empty, and layer 1 is at the bottom until you change the order in VIEW's
LAYERS list. What you see, and what the mesh wears,
is all of them combined. Which ones show is set in VIEW's LAYERS menu.

| Control | What it does |
|---|---|
| a row for each layer | **List**: how it combines with the layers under it (normal, multiply, screen, add, lightest). **CLEAR**: empties that layer. |
| transparency | Under each layer's row. At 0 the layer is as solid as its paint; at 1 it's invisible. |
| impasto | Beside transparency: how much IMPASTO's light catches this layer's paint. 1 = as thick as the tools painted it, 0 = flat. |
| canvas transparency | The last row. At 0 the canvas is solid; towards 1 the backdrop shows through it. |

Layers 1 and 3 and the canvas have a darker band behind them, so the rows are easy to tell apart.

Which layer each tool paints on is in its APPLY, and what SCRAPE scrapes down to is in its box in column 2.

Hiding, making see-through or recombining a layer changes the painting immediately, including what's already
painted on it. The main CLEAR button (in RUN) puts the canvas back to its start and empties every
layer.

### SHADOW BOX

Makes the layers look as if they float apart, like cut paper in a shadow box, lit from one side.
Each layer casts a soft shadow on everything under it in the stack, and its edges that face the
light catch the light. Where an upper layer has no paint you see down to the layers under it, lit,
with shadow along the edges of the paint above. It changes what you see straight away, including
what's already painted, and the mesh wears it too. The canvas casts no shadow.

| Control | What it does |
|---|---|
| on | Switches the shadow box on. The other controls show once it's on. |
| light from | Which side the light comes from, in degrees: 0 = right, 90 = above, 180 = left, 270 = below. The default 135 is the upper left, so shadows fall to the lower right. |
| light height | How high the light is. Low light (10) makes long shadows, high light (80) short ones. |
| shadow darkness | How dark the shadows are |
| shadow softness | How blurred the shadows' edges are. They get softer the further a layer floats above what's under it. |
| lit edges | How bright the edges facing the light are |
| gap above the layers under it | One slider per layer, in pixels: how far it floats above the stack under it. 0 = flat on it (no shadow). Bigger gaps make longer, softer shadows. The gap belongs to the layer, so it moves with it when you change the order. |

### IMPASTO

Thick paint catching a raking light. Every mark a tool paints adds to its layer's height, as
thick as the tool's **thickness** in APPLY says. A knife mark becomes a slab with steep edges, and
lighter paint stands a little higher than dark. A new mark flattens the paint under it a little,
so the height doesn't pile up for ever. The light brightens the edges that face it and shades the
ones that face away, with a little shine.

SCRAPE takes the height off with the paint, CLEAR on a layer flattens it, and hiding a layer or
making it see-through takes its height away too. Each layer's **impasto** slider in LAYERS turns
its relief up or down: at 0 its paint lies flat, so you can have a thick knife layer over a
smooth one. The light is applied to the finished picture, so
the canvas, the mesh, wet paint and a saved painting all have it. SAVE also writes the height as
`...-height.png` (white = thick).

| Control | What it does |
|---|---|
| on | Switches the light on. Paint records its thickness either way, so switching on later shows everything already painted. |
| relief | How deep the paint looks |
| light from | Which side the light comes from, in degrees, as for SHADOW BOX: 0 = right, 90 = above, 180 = left. It's a separate light, so set both the same if you use both. |
| light height | How high the light is: low light (10) rakes across the paint and shows every ridge; high light (80) flattens it. |
| shine | How much the steepest lit edges glint |

## Letting the maps decide

Some settings have a **by** row underneath them: size (brush and knife), follow the form (brush
and knife) and opacity (every tool except scrape). Choose a map there and the setting changes
from place to place across the picture:

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

**space**: pause  **n**: one step (while paused)  **c**: clear  **s**: save  **r**: straight on (mesh)  **l**: light on/off (mesh)

## Tips

- Start with the defaults, press RUN, and move one slider at a time while it paints. Turn the
  painting speed down to watch what each change does.
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
