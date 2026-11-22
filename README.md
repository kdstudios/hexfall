# HEXFALL

A 3D geodesic hexagonal Minesweeper on alien planets, built in Flutter for Android,
iOS and Web. The planet is a mathematically correct icosphere dual (12 pentagons +
hexagons, `10n²+2` cells).

Dependencies: Flutter plus two plugins — `shared_preferences` (saves) and
`audioplayers` (sound) and `file_picker` (sound import/export). All support Android, iOS and Web.

## Play in the browser

Every push to `main` is built and published to GitHub Pages by
`.github/workflows/deploy.yml`:

**https://YOUR-USERNAME.github.io/YOUR-REPO-NAME/**

One-time setup: on GitHub open **Settings → Pages → Build and deployment → Source** and
choose **GitHub Actions**. Then open the **Actions** tab to watch the first build (about
3-5 minutes). Saves are stored in the browser (local storage), so they stay per browser and
are lost if site data is cleared.

> **Status:** the code has not been compiled on a developer machine yet; the Actions build
> is the first real compile. If it fails, open the failed run and copy the error text.

## Run it locally

You need Flutter installed (`flutter doctor` should run in a terminal).

1. Generate the platform folders once (existing files are kept):

   ```
   flutter create . --platforms=android,ios,web --project-name hexfall
   ```

   then delete the generated `test/widget_test.dart` (it refers to a default app that does not exist here).

2. Install, test and run:

   ```
   flutter pub get
   flutter test
   flutter run -d chrome --web-port=8080
   ```

   Or on a connected phone / emulator: `flutter run`.

3. Release build for the web: `flutter build web --release --base-href "/YOUR-REPO-NAME/"`.

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
