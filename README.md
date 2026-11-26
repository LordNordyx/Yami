# Yami

An RPG Maker XP / VX / VX Ace player for Android, built for fan games like Pokémon Essentials projects. Yami pairs the open-source **mkxp-z** RGSS engine with a modern Compose frontend, and adds a pre-launch optimizer, widescreen, shaders and automatic controller binding.

> **Status: first build, not yet compiled.** The engine patch, Ruby runtime and archive extractor are tested (see *Testing*). The Kotlin app and the Android engine build had no Android SDK/NDK available while being written, so the first CI run is their first compile. Expect a round of fixes there.

## Features

**Library**
- Import a game folder (copied), a `.zip`, a game in place (no copy, needs *All files access*), or scan a whole folder of games
- Detects XP / VX / Ace, Pokémon Essentials, title-screen covers, and Shift-JIS / CP1252 `Game.ini` titles
- Covers, grid and list views; search; sort by recent / title / added / play time; favourites; a "Continue" hero card
- Play time, last played and launch count per game
- Saves: a per-game save folder, an **automatic snapshot before every launch** (rolls back a bad save), and zip export/import
- `.nomedia` gallery hiding; RTP folders (shared by all games); MIDI SoundFont picker

**Pre-launch optimizer**
1. **Archive unpack:** `Game.rgssad` / `.rgss2a` / `.rgss3a` become loose files. Reads skip decryption, and hi-res packs and the resource index can see every file. The archive is kept as `.yami-bak` and can be restored; files the game already shipped loose are never touched.
2. **Resource index:** every file is listed once, case collisions are counted, and extension-less aliases are added. mkxp-z's `pathCache` provides case-insensitive lookup at runtime.
3. **Map streaming:** `.yami/maps.txt` lets the runtime read every map into RAM on a background thread (budget is configurable), so map transfers decode from memory.
4. **Compact tilesets (RMXP):** each map that uses an oversized tileset (taller than 4096 px or the GPU limit) gets an atlas holding only the tiles it and its events use. Identical tile sets share one atlas. Passages, priorities and terrain tags are remapped with the tiles. Originals are never modified, and any map whose source changed later automatically falls back to the original.

**Display**
- Upscaling: nearest, bilinear, bicubic (adjustable sharpness), Lanczos3, xBRZ 2–6×; fit / integer / stretch; internal resolution up to 4×; hi-res texture packs
- **Post-processing shaders** (new engine pass): CRT, LCD grid, scanlines, CAS sharpen, FXAA, vibrance, night light, Pocket, each with an intensity slider. You can import your own `.frag` files.
- **Widescreen** (experimental): *Widescreen* resizes the screen and patches the RMXP camera and Essentials' `SCREEN_WIDTH` / `SCREEN_CENTER_X`. *Panoramic* draws the map across the whole display while menus and UI stay at the original width, centred. Aspect: device, 16:10, 16:9 or 20:9.

**Speed-up:** raise frame rate, skip frames, or both; 2–8×; toggle or hold. Games can opt out with `Graphics.yami_disable_turbo!`, and `Graphics.kirin_disable_turbo!` is honoured too.

**Controls**
- **Controllers bind automatically:** Nintendo pads get the A/B swap their labels imply (detected by vendor id). Stick, d-pad hat, and triggers as keys or axes all work. Start opens the game menu, Select opens Yami's menu, and touch controls hide while a pad is in use.
- Per-layout remapping with a live input tester, autofire (never on directions), configurable deadzone and triggers
- Touch: floating analog stick, thumb-rolling between buttons, haptics, opacity; **free layout editing** in game (drag, double-tap to resize, hold to hide)

**In-game menu:** speed-up, touch controls on/off, edit/reset layout, FPS + clock + battery HUD, screenshot to `Pictures/Yami`, soft reset (F12), restart game in a fresh process, quit.

**Robustness:** the engine runs in its own `:engine` process, so a game crash never takes the library down and every launch starts from a clean native state.

## How it fits together

```
MainActivity (Compose)  ──launch──▶  PlayerActivity : SDLActivity   (:engine process)
  library, settings, import            env: SRCDIR, YAMI_CFG, YAMI_DATA_DIR
  GameOptimizer (Kotlin)               libmain.so = mkxp-z + patches
                                       preload: yami_runtime.rb (+ yami_optimizer.rb)
```

- `native/patches/0001-yami-android-postshader.patch` changes mkxp-z in four ways:
  - builds as `libmain.so` on Android
  - adds `postShader` / `postShaderIntensity` config keys and a `PostShader` pass at present time
  - honours `YAMI_DATA_DIR` (SDL's pref path ignores org/app on Android, so every game would otherwise share one save folder)
- `app/src/main/assets/yami/scripts/yami_runtime.rb` implements map streaming, the optimized-map redirect, turbo, widescreen, save redirection and graphics warm-up
- `app/src/main/assets/yami/scripts/yami_optimizer.rb` builds the compact tilesets inside the engine, then exits
- `EngineConfig.kt` merges Yami's options over the developer's own `mkxp.json`. The original is kept as `mkxp.json.original`, and the developer's preload scripts still run.

## Building

The easiest route is GitHub Actions: push the repo and `.github/workflows/build.yml` runs logic tests, then builds the engine, then assembles the APKs (artifact `yami-apk`).

Locally:
```bash
export ANDROID_NDK_HOME=/path/to/ndk/r27c
pip install "meson>=1.4"         # plus ninja, cmake, bison, autoconf, ruby
bash native/build-mkxp.sh        # → app/src/main/jniLibs/arm64-v8a/libmain.so
gradle :app:assembleDebug        # or open in Android Studio (creates the Gradle wrapper)
```
The engine build downloads mkxp-z's vendored dependencies (SDL2, Ruby 3.1, OpenAL, FluidSynth…) through meson wraps and cross-compiles them all, so the first run takes a while. CI caches the downloads.

## Writing shaders

Shaders are GLSL ES 1.00 fragment shaders. Yami supplies:

```glsl
uniform sampler2D texture;   // upscaled frame, window-sized
uniform vec2 outputSize;     // window px
uniform vec2 inputSize;      // game resolution, e.g. 640x480
uniform vec4 viewRect;       // game picture inside the window (x, y, w, h)
uniform float frameCount;
uniform float intensity;     // the user's slider, 0–2
varying vec2 v_texCoord;
```
Start the file with `// Yami post shader: Name — description` so the picker shows a nice name. A shader that fails to compile is skipped and the game runs without it.

## Testing

```bash
bash tests/run.sh
```
- Ruby runtime and optimizer, run against mkxp-z's real `RPG` module source with stand-ins for the native classes. Covers tile remapping, passage/priority/terrain consistency, event tiles, variant sharing, stale-map fallback, map cache, turbo, save redirection, and widescreen (full RMXP, full Essentials, panoramic Essentials).
- RGSS archive extractor: v1 and v3 round-trips, including non-ASCII names and empty files.

## Known limitations

- Widescreen and panoramic patch common RMXP and Essentials code paths. Custom menus with hard-coded 640 px layouts will sit left-aligned or clip.
- Compact tilesets assume tile IDs don't change at runtime. Scripts that write `$game_map.data` with original IDs, or compare `tileset_id` against constants, can misbehave. Turn off *Optimized maps* or use *Delete optimized maps* for that game.
- arm64 only. RGSS2/3 maps skip the tileset step, but everything else applies.
- MIDI needs a SoundFont (e.g. GeneralUser GS) for good sound.

## License

mkxp-z is GPLv2+. Building with `extra_shaders` (xBRZ) makes the engine GPLv3, so distributed Yami builds are GPLv3. SDL's Java glue is zlib-licensed. Yami doesn't include any games or RTP assets.
