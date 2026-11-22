# HEXFALL — Technical decisions, status & known gaps

## Status honesty
- Geometry algorithm and camera maths were verified numerically in a Python port
  (all 12 checks pass for n = 1,2,3,4,8,10,16,24).
- Everything else (engine, persistence, session, rendering, UI, audio) was written
  without a Flutter SDK available: **none of it has been compiled or run.** Expect a
  handful of compile errors on the first `flutter pub get && flutter test`.
- Not tested on Android, iOS or a browser. No platform is claimed as supported until run.
- Audio files were synthesised by `tools/generate_audio.py` and have never been
  listened to. Visuals, animation feel and 60 FPS are unverified.
- Not done: Android/iOS release signing, UI tests for portrait/landscape/desktop layouts,
  cross-device testing, GitHub Pages workflow file.

## Rendering approach
Software 3D pipeline feeding `Canvas.drawVertices`:
- Per frame, visible cells' corners are rotated + projected into preallocated typed
  lists, shaded per vertex (Lambert + fresnel rim + scan band), and drawn as ONE
  indexed triangle batch + two line batches (outline + glow).
- The planet is convex, so back-face culling by cell is exact; no sorting.
- Only core `dart:ui` features are used, so behaviour is the same on Android, iOS and
  Flutter Web (CanvasKit). No WebGL package, no native plugin, no extra dependencies.
- Rejected for now: GL / three.js-style Flutter packages and Flutter GPU / scene
  libraries — either platform-specific, experimental, or unverified on Web. Revisit
  only if profiling shows the CPU transform cost is a problem at n=16+ on low-end
  devices (see `lastPaintMs` in the overlay).
- Index buffers are 16-bit, so max frequency is 24 (5,762 cells, ~40k vertices); a
  test enforces this.

## Geodesic grid
- Icosahedron → each face subdivided into n² triangles → projected to the sphere →
  dual mesh (vertex = cell, triangle = cell corner).
- Shared edge vertices are de-duplicated by (edge, step) key, **never by float
  comparison**.
- CSR storage: `cellOffsets`, `cellVertexIndices` (CCW from outside),
  `neighbourIndices`. **Neighbour k lies across the edge between corner k and k+1.**
- Cells are not equal-area (linear subdivision); sizes vary slightly. Acceptable for
  gameplay; could be improved with spherical subdivision later without API changes.

## Picking
Camera ray → unit-sphere intersection → planet-space point → nearest cell centre →
exact great-circle edge test on that cell and its neighbours. Camera-independent, so
neighbour logic never depends on rotation.

## Gestures (globe_view.dart)
Raw pointer events. Tap fires only if the pointer never left the slop radius
(12 px touch / 5 px mouse) and no second pointer joined. Long-press (touch, 450 ms)
and right-click (mouse) are the secondary action. Browser context menu is disabled on
web in `main.dart`. Wheel and trackpad pinch zoom the camera distance.

## Determinism (matters for Daily Planet)
`planet_surface.dart` hashes with 32-bit-masked integer ops whose intermediate
products stay < 2^53, so results are identical on native and JS. Milestone 2's mine
RNG must follow the same rule (no 64-bit multiplies; mask every step).

## Handover for Milestone 2
- Game engine goes in `lib/core/game/`, depends only on `GeodesicGrid` (`sidesOf`,
  `neighbourIndices`, `cellOffsets`).
- Renderer already supports per-cell colour via `GlobeRenderer.cellRgb`; the
  controller's `_recolorAll()` is where tile states (hidden / revealed / flagged /
  mine) will map to colours. Replace the sandbox `toggleMarker` with real flagging and
  `select` with reveal.
- Numbers on revealed tiles are not rendered yet (need a cheap approach: pre-rendered
  glyph atlas drawn with `drawAtlas`, or text only for cells above a size threshold).

## Milestones 2–7 notes
- **Engine** (`core/game/game_engine.dart`): pure rules; flood fill is BFS marking cells
  on enqueue; chording processes every target so wrong flags still hit mines; shield
  and loss logic live in one place (`_process`). Mines come from a seeded partial
  Fisher–Yates using `SeededRandom` (xorshift32, web-safe integer maths).
- **Visual vs logical state**: the engine is always final; `GlobeController` keeps a
  delayed `shown` array so scan waves and explosions animate without ever affecting
  saves. Saving happens after every action from engine state only.
- **Numbers/flags/mines** are drawn from cached `ui.Paragraph`s and vector paths for
  visible tiles larger than 5 px, not as widgets.
- **Destruction animation** is a radial shock pulse (tiles pushed out and settling),
  followed by the results panel, so the planet can still be inspected afterwards.
- **Daily Planet**: seed = hash of `hexfall-daily-v1-YYYY-MM-DD` (UTC). Changing the
  algorithm requires bumping `DailyPlanet.generationVersion`.
- **Persistence**: one JSON value per key via `shared_preferences`; each write replaces
  a whole value (no partial files). Corrupt data is ignored rather than crashing.
- **Reduced motion**: no shake, flashes dimmed, no staggered scans, no idle spin,
  no scan line, no camera tween on reveals.
- **Medal gold time target**: 0.5 s per tile (`MedalRules.goldSecondsPerCell`).
- Custom games are limited to n = 3–20 and 4–30% mines.

## Hidden vs revealed look (user feedback round 1)
Hidden tiles are raised (+1.4% radius), bright light-blue hologram with bright outlines.
Revealed tiles are sunken (-1%), dark (zero-tiles darkest), with dimmed outlines, so numbers
stand out. Differences are luminance + depth + outline brightness, not just hue.

## Touch hold menu
Touch, stylus and left mouse button. Hold ~320 ms on a tile without moving past the slop (12 px) -> menu opens
above (Reveal, or Chord on a number) and below (Flag / Unflag). Drag up/down past 55% of the
menu distance and release to confirm; release in the middle cancels. Moving before the delay
rotates as normal; a second finger cancels the menu. Mouse: drag still rotates immediately, click reveals, right-click flags; holding the
left button still for ~320 ms also opens the menu.

## Performance round (user feedback: high quality was slow, low was fine)
- Outlines are now soft triangle ribbons (centre opaque, edges fade) drawn in chunked
  `drawVertices` batches instead of thousands of wide round-capped strokes. Glow is a
  second, wider, fainter ribbon layer (High quality only).
- Numbers / flags / mines come from a sprite atlas (built once with `Picture.toImage`) and
  are drawn in ONE `drawRawAtlas` call; vector fallback is used until the atlas is ready.
- Backdrop, planet base (halo + rings + body) and rim are recorded once as `ui.Picture`s and
  replayed each frame (re-recorded only when size / zoom / atmosphere colour changes).
- Auto quality: below 42 fps for 2 s steps High -> Medium -> Low; never steps back up.
- Not yet profiled on a device: please compare fps at 2,562 tiles.

## Reveal pulse
Revealing tiles launches a bright ring that sweeps across the sphere from the revealed tile
(geodesic angle from the origin), lifts tiles it passes over, and revealed tiles pop upward
and flash brighter / longer. Disabled in reduced-motion mode.

## Concept-art polish
Hex-framed glowing digits, hologram flags on hex platforms, spiked glowing mines (atlas
sprites); outlines turn gold toward the limb; hologram projector rings under the globe;
ringed gas giant + extra nebulae in the backdrop; chamfered panel/button frames; HUD with
TIME / MINES LEFT / CLEARED / SHIELD readout panels; flat SURFACE MAP panel (wide screens).

## Sound import / export
`SoundLibrary` keeps user replacements (base64 JSON per slot in the key/value store, so it
works on web too). Playback uses `BytesSource`; if a custom file fails to play the default is
used. `file_picker` is pinned to 8.x because its API changes between major versions.
Zip export uses a small built-in ZIP writer (stored, no compression), checked against a
reference unzipper in a Python port.

## ConceptArt.jpg pass 2 (user feedback: hex frames misaligned, not like the concept)
- Removed the hex frame baked into number sprites (it could never match a tile's projected
  orientation). The tile's own outline is now the frame: scanned tiles glow in their number's
  colour (1 cyan, 2 green, 3 red ...), hidden tiles have a faint steel outline, flags blue,
  mines red; outlines turn gold toward the limb.
- Hidden tiles are dark gunmetal with a pillowed (bright centre, dark edge) shading; scanned
  tiles are near-black, so glowing numbers and outlines carry the look as in the concept.
- HUD: notched TIME / MINES LEFT / CLEARED / SHIELD panels centred along the top edge, back
  ("<<") button + planet name top-left, corner-bracket surface map top-right, transport-style
  control strip bottom-centre (bottom-left when left-handed).
- Known gaps vs concept: tile thickness / metal plating at the limb, drifting ships and
  particles, second (bottom-right) mini map, left-side duplicate readouts.

## V05 — textured tile plates (concept-art pass)
- Source: `ConceptTile.png`. `tools/build_tiles.py <sheet>` rebuilds everything in
  `assets/tiles/` and the flat previews in `tiles/` (contact_sheet.png shows all states).
- **Plates** (`tile_plates.png`, 4x4 atlas of 256 px hexes) are mapped onto each cell
  corner-by-corner with `drawVertices` + `ImageShader` (modulate by per-vertex lighting),
  so frames always match cell outlines. Pentagons map their 5 corners onto the hex border.
  A second additive pass (`BlendMode.plus`) carries rim light, scan band, flashes and the
  reveal pulse. Digits 5-8, the blank (0) plate and the red wrong-flag plate are derived
  from the sheet (hue shifts + a flat recess fill).
- **Glyphs stay upright**: digits and the flag are drawn from `glyph_digits.png` /
  `glyph_flag.png` through the existing glyph atlas (digit colours still follow the
  colour-blind palettes). Mine / exploded tiles are full plates (no glyph needed).
- Digits 1-8 are redrawn as strokes in one consistent neon style (the sheet only has 1-4).
- Fallback: if the PNGs fail to load, or outside a game (menus, lab), the old flat-colour
  mesh is used, so nothing regresses. Number 3 is now amber and 5 red-orange to match the sheet.
- Not compiled or run here (no Flutter SDK in this environment) — please run
  `flutter pub get && flutter test` and report any errors.

## V06 — pentagons, planet identity, chain detonation
- **Pentagon plates**: `tools/source/ConceptTilePentagon.png` (hidden + clean recess) is
  recoloured for every state (rows 4-7 of `tile_plates.png`, index + `TileAtlas.pentagonOffset`).
  Mine / exploded pentagons paste the hex mine art into the pentagon recess. Pentagon cells map
  their 5 corners to the 5 pentagon corners (apex up).
- **Planet identity**: hidden plates are multiplied by the cell's terrain colour (strength 0.78,
  brightness follows terrain brightness), so oceans / ice / lava / forests show through the
  metal; scanned plates keep neon frames plus a faint additive terrain haze. Atmosphere colour
  also tints plate frames, hidden-tile outlines, the planet's dark body and the nebulae.
- **Chain detonation**: on the fatal mine every other mine goes off in order of great-circle
  distance from it (60% wave front, 40% rank order, +jitter), 1.4-2.6 s total, rumble builds
  (`GlobeController.shakeAmplitude`) then a final shockwave. Results panel on a loss is
  delayed to 4.6 s; nine staggered explosion sounds play. Reduced motion: instant, no shake.

## V07/V08 — colour strength, depth effects
- Colour strength is two global settings: hidden tiles 1.00, scanned tiles 0.60 (defaults,
  Settings -> Planet look, with Reset). The in-game TINT button edits the same two values live.
- Depth effects (each has a Settings switch, all default on, medium quality and up):
  1. **Tile thickness** - quads from each raised tile's top edge down to the planet body, only
     where they face the camera and only for cells within ~35 degrees of the limb.
  2. **Edge highlights** - soft light/dark ribbons on tile edges facing / away from the sun.
  3. **Plate relief** - `tile_plates_relief.png`, same atlas with baked local contrast, raised
     rim and inner groove (orientation independent). Swapped in via a second ImageShader.
- Normal maps rejected: Flutter fragment shaders cannot take per-vertex UVs through
  `drawVertices`, so per-pixel lighting would need one draw per tile.

## V09 — pop-in fixes
- Glyph size now uses the **mean** corner distance (was corner 0, which depends on each cell's
  arbitrary corner order, so neighbours shrank at different rates) and shrinks smoothly to
  nothing between facing 0.66 and 0.26 (was a hard cut at 0.32).
- Wall thickness fades in smoothly between facing 0.86 and 0.64 (was an on/off switch at 0.82);
  walls are drawn **before** the tile mesh so neighbouring tops cover them instead of leaving
  dark slabs; edge glints fade between facing 0.12 and 0.45.
