# HEXFALL

A 3D geodesic hexagonal Minesweeper on alien planets, built in Flutter for Android,
iOS and Web. The planet is a mathematically correct icosphere dual (12 pentagons +
hexagons, `10n²+2` cells).

Dependencies: Flutter plus two plugins — `shared_preferences` (saves) and
`audioplayers` (sound) and `file_picker` (sound import/export). All support Android, iOS and Web.

> **Status:** all code was written without a Flutter SDK available, so it has not yet
> been compiled or run on any device. See `docs/DECISIONS.md` for what is verified.

## Run it (step by step)

You need Flutter installed (`flutter doctor` should run in a terminal).

1. **Create a fresh Flutter project** (this generates the Android / iOS / web folders):

   ```
   flutter create hexfall --platforms=android,ios,web
   cd hexfall
   ```

2. **Copy this project's files over it.** From this zip, replace/copy into the new folder:
   - `lib/`  (delete the generated one first)
   - `test/` (delete the generated one first — its `widget_test.dart` refers to an app that no longer exists)
   - `pubspec.yaml`
   - `analysis_options.yaml`
   - `docs/`, `README.md`

3. **Install and test:**

   ```
   flutter pub get
   flutter test
   ```

4. **Run in the browser:**

   ```
   flutter run -d chrome --web-port=8080
   ```

   Or on a connected phone / emulator: `flutter run`.

## What's in the game

- **Play Game**: four difficulty profiles (162 / 642 / 1,002 / 2,562 tiles) plus Custom.
- **Campaign**: 4 sectors × 5 missions, data-driven (`lib/data/campaign_data.dart`).
- **Daily Planet**: one shared planet per UTC date, works offline.
- **Planet Database**, **Statistics**, **Settings** (audio, colour-blind palettes,
  reduced motion, UI scale, left-handed layout, quality, haptics).
- Shield: the first mine you hit is survived; the second ends the game. First click is
  fully random (no protection) by design.
- **Settings → Sound library**: export every sound (one by one or all as a .zip),
  replace any of them with your own .wav / .mp3, or bulk-import files named after the sounds
  (`explosion.mp3`, `music.wav`, ...). Stored on-device; limits 2.5 MB per file, 3.5 MB total.
- **Settings → Quality**: Auto lowers visual quality by itself if the frame rate stays low.
- **Settings → Geometry lab** is the Milestone 1 inspector (live geometry validation).

## Controls

| Action | Touch | Mouse / keyboard |
|---|---|---|
| Rotate | drag | left-drag |
| Zoom | pinch | wheel / trackpad pinch |
| Reveal (or chord a number) | tap in Reveal mode | left-click |
| Flag | tap in Flag mode, or long-press | right-click |
| Mode | Reveal / Flag buttons | `R` / `F` |
| Recenter / Pause | buttons | `Space` / `P` or `Esc` |

## Layout

```
lib/
  core/geometry/   geodesic grid, validator          (no Flutter dependency)
  core/game/       engine, config, medals, PRNG      (no Flutter dependency)
  core/planet/     environments, appearance, names
  data/            campaign missions, daily planet
  game/            GameSession (engine + visuals + clock + audio + saving)
  render/          camera, renderer, painter, gestures, controller, glyphs
  persistence/     key/value store, models, AppState
  services/        audio (generated assets), haptics
  ui/              screens + sci-fi widgets
  theme/           colours / lighting / outline settings
assets/audio/      original synthesised sounds (see tools/generate_audio.py)
test/              geometry, camera, engine, persistence, session tests
docs/DECISIONS.md  technical decisions, status, known gaps
```

`core/` never imports `render/` or `ui/`, so the whole game can be tested headlessly.

## Build / deploy (for later milestones)

- Android: `flutter build apk --release`
- iOS (needs a Mac + Xcode): `flutter build ios --release`
- Web: `flutter build web --release --base-href "/<repo-name>/"`, then publish
  the `build/web` folder to GitHub Pages (e.g. a `gh-pages` branch).
  
GitHub Pages: the site is served from `https://<user>.github.io/<repo-name>/`, so the
`--base-href` must match the repository name exactly (with leading and trailing slash).

Saves on the web live in the browser's local storage: they persist between visits but
disappear if the user clears site data or uses a private window.
