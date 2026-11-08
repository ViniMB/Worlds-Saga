# Worlds Saga

A pixel-art RPG across many Earths, where the language of the world is English. Built in **Godot 4.3**.
Split out from the "My English" app: the app keeps teaching; this project is the game.

## Play
1. Install Godot 4.3 (standard build) from godotengine.org.
2. Open Godot → Import → choose this folder's `project.godot` → Run (F5).

Controls: ←/→ or tap the ground to walk on the map; walk to a `!` and press Space/E (or tap it) to play a chapter.
Space, Enter or a click advances the dialogue. Portuguese subtitles and voices can be turned on/off on the title screen.

## First slice: London Fog
The whole first world (30 chapters, 3 roads) runs end to end: cutscenes, dialogue with choices, exploring places,
pairs, sorting, ordering, reading, the Tube maze, the bill at the café, rune spells, the Corrector's testimony,
the chase battles, relics and ranks. Wrong answers cost a courage heart; at zero, a friend helps and they refill.

## Layout
- `scripts/game.gd` — global state (autoload `Game`): world data, save file, settings, voices, the shared look.
- `scripts/main.gd` — title → map → chapter. `--autotest` plays every chapter; `--shots` saves screenshots.
- `scripts/hub.gd` — the side-scrolling world map.
- `scripts/chapter.gd` — plays one chapter; one coroutine per step kind.
- `scripts/art.gd` — animated backgrounds and character sheets.
- `data/worlds/<world>.json` — the world's story and steps (exported from the original game).
- `assets/` — backgrounds (8-frame sheets), characters (32×32 cells), relics, emotes, fonts, voices.
- `tools/` — exporters that turn a world of the original game into data and art for this project.

## Bringing a world over
From a checkout of the original game at `/home/claude/my-english`:
```
cd /home/claude/my-english
npx esbuild ../worlds-saga/tools/dump-world.ts --bundle --platform=node --format=cjs --outfile=/tmp/dump.cjs --define:import.meta.env={} --alias:WORLD=$PWD/src/worlds/<world>/index.ts
node /tmp/dump.cjs > ../worlds-saga/data/worlds/<world>.json
npx esbuild ../worlds-saga/tools/render-entry.ts --bundle --format=iife --outfile=/tmp/render-<world>.js --define:import.meta.env={} --alias:WORLD=$PWD/src/worlds/<world>/index.ts
node ../worlds-saga/tools/render-world.cjs <world> ../worlds-saga/assets
```

## Checks
```
godot --headless --path . -- --autotest      # plays every chapter with correct answers
```

## Voices
The London voices are placeholders (Kokoro, from the original app). The plan is to record every line with
ElevenLabs once each world's RPG script is final: a sheet of lines (id, character, emotion, text), a Voice Design
prompt per character, and a script that generates the audio through the API in the format `game.gd` reads.

## Credits
Emotes: Kenney (CC0). Fonts: Pixelify Sans and Silkscreen (SIL Open Font License). Pixel art drawn in code.
