# poddasark

A relaxing game about restoring natural parks so their animals can thrive, building
towards balanced ecosystems of predators, prey and plants. Made in Godot 4.7.2 for PC,
releasing on itch.io.

- Design notes: `docs/brainstorms/`
- Build plan: `docs/ROADMAP.md`
- Rules for AI agents: `AGENTS.md`

## Running it

Open this folder in Godot 4.7.2 and press Play (F5).

The current build is M2: the wombat tutorial (M1), then the camera zooms out to a
bigger area with a kangaroo mob and possums, and the harmony gate.

Controls:
- **Pan:** WASD / arrow keys, or drag with the middle mouse button
- **Rotate:** drag with the right mouse button, or Q / E
- **Zoom:** mouse wheel
- **Observe an animal:** left-click it (Observe tool)
- **Tools:** the toolbar or number keys (Observe, Water, Native grasses, Burrow, Clean up,
  plus Eucalypt and Nest box in M2).
  Left-click the ground to place or clean up. Esc goes back to Observe.

All art is grey placeholder for now.

## Exporting for itch.io

In Godot: **Project > Export**. There are two presets:
- **Windows:** a single `.exe`. Zip it and upload it to itch.io as a Windows download.
- **Web (itch.io):** exports to `export/web/`. Zip the *contents* of that folder
  (with `index.html` at the top level), upload it to itch.io, and tick "This file will
  be played in the browser". The build is single-threaded, so itch's
  SharedArrayBuffer option is not needed.

The first time, Godot will ask you to download export templates (Editor > Manage
Export Templates).

## Tests

The ecosystem logic in `src/eco/` and the tutorial script are tested headless,
including a full scripted playthrough of the wombat tutorial from the real data files:

```
godot --headless --path . -s tests/run_tests.gd
```

(or `tools/godot.sh --headless --path . -s tests/run_tests.gd` on Linux, which
downloads Godot 4.7.2 on first use.)

## Balance tool

`tools/simulate.gd` runs the ecosystem forward without playing and prints how each
species is doing over time, from a plan of timed player actions:

```
tools/godot.sh --headless --path . -s tools/simulate.gd -- --plan res://tools/plans/m2_example.json
```

## Project layout

| Folder | What goes there |
|---|---|
| `src/eco/` | Ecosystem logic: needs, contentedness, populations. Plain scripts with no scene nodes, so they can be tested and balanced without playing. |
| `src/game/` | Scene scripts: camera, input, what's on screen. |
| `scenes/` | Godot scenes. |
| `data/` | Content: species, needs, parks, phase scripts. |
| `tests/` | Headless tests (`test_*.gd`). |
| `tools/` | Helper scripts. |

### Automatic upload

`tools/itch_push.sh` exports both presets and uploads them to an existing itch.io
page with butler. It needs `BUTLER_API_KEY` and `ITCH_TARGET` (`username/game-slug`)
set in the environment. The page's visibility is controlled on itch.io, so a Draft or
Restricted page stays private.
