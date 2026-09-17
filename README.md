# MiddotAudio (MiddotWare)

**Audio middleware made with Godot, for Godot.** Free and open source, inspired by FMOD Studio and Wwise.

MiddotWare is **not a new audio engine.** It makes the one Godot already ships easier to use: every soundbank compiles down to stock `AudioServer` buses, effects, and `AudioStreamPlayer`s. Because the target side is plain GDScript — no C++, no GDExtension, no per-platform builds — it is the only audio middleware that keeps up with Godot's development pace by construction.

- **Professional workflow, native feel.** FMOD-style events, banks, and a mixer — audio people feel at home — but every concept maps onto Godot's own objects.
- **Built for teams.** Audio lives in `.middot` projects and per-bank `.tres` files, not one shared scene. Designers work in their own files; merge conflicts shrink; audio changes stop colliding with gameplay code.

## How it works

- **This repo** = the authoring app. Define sound events on a free-canvas node graph (Sound / Random / Playlist / Conditional / Variable / Output nodes), mix buses, organize events into banks, save projects as `.middot`, and export a soundbank — a Godot `.tres` resource plus the audio files it references.
- **Target game** = the consumer. Drop in the `middot_audio` addon (one folder), and call:

```gdscript
AudioManager.play_sound("player_hurt")
```

That's the whole API. The parser (~250 lines, fully readable) handles simple/random/shuffle/playlist/conditional/sync triggers, game parameters, bus routing, and looping — using stock Godot audio only.

## Quickstart

1. Download the latest build from Releases, or open this project with **Godot 4.7** and run `control.tscn`.
2. Author: add an event, drop WAV/OGG/MP3 files onto the canvas (or the Assets tab), wire them through triggers to the Event Output node.
3. Audition in-app (**F5**) — no game launch needed.
4. **Export** (F7): pick a folder — you get `Main.tres` (one `.tres` per bank) + audio files.
5. In your game: copy the exported folder + the `addons/middot_audio/` folder, then load and play:

```gdscript
AudioManager.use_bank("res://soundbanks/Main.tres")
AudioManager.play_sound("player_hurt")
```

`use_bank()` adds banks to a persistent set (UI/Player banks at startup, level banks on loading screens — `unload_bank()` when done). `AudioManager.preload_all()` warms every referenced stream so first plays never hitch.

## Documentation

- [`docs/bank-format.md`](docs/bank-format.md) — soundbank format v3 spec (additive-only stability contract).

## The bank format is a contract

Target parsers gate on `format_version` before reading events. Changes are additive only; any unavoidable reshape is a new version with a migration note. See `docs/bank-format.md`.

## Contributing

Issues and PRs welcome. The two easiest entry points:

- **New node type** = one script under `nodes/` extending `NodeType` + one `register()` line here + one resolver + one register line in the parser's `ResolverRegistry`. That's the whole plugin contract.
- **Target parser** (`middleware-game-test` repo layout in the README of that project) — small, typed, and covered by headless tests.

## License

[MIT](LICENSE) — same as Godot.
