# MiddotWare — Phase One Report

End of phase one: from empty repo to a working audio middleware authoring tool with a tested runtime. This is the handoff doc for the next session.

## What the product is

A free, open-source **audio middleware authoring tool** for Godot 4.7, FMOD/Wwise-inspired. It does NOT play audio in games. It authors a **soundbank** that a target game consumes via the small `middot_audio` addon, using stock Godot audio only (AudioServer, buses, AudioStreamPlayer). Two repos:

- **This repo** (`middot-audio`): the authoring app, exports to `Desktop\MiddotWare\MiddotWare.exe`
- **`C:\Users\edwar\Documents\middleware-game-test`**: target-game test project with the `middot_audio` parser addon + `AudioManager` autoload + main menu

## What works today (all verified headless)

- **Boot sequence**: forced project dialog before any editing. SAVE_FILE mode — type a new name to create, or select an existing `.middot`. New projects write to disk immediately.
- **Project files**: JSON with `.middot` extension, saved beside an `Audio/` folder. `File > Save As...` re-points the project. Export always saves the project first.
- **Assets**: Audio folder beside the project is the source of truth; app scans it (auto-rescan on window focus) and lists `.wav/.ogg/.mp3`. F2/double-click renames on disk with follow-through to all referencing events.
- **Events panel**: add events, F2-rename, select to edit. State starts empty.
- **Node graph editor** (always visible, right pane): Trigger → Sound → Output chain per event.
  - Trigger modes: **Simple**, **Random** (pure or shuffle — every variation plays once before repeats, Wwise semantics), **Playlist** (pin order, loops by default)
  - Random/Playlist: one output pin per variation; drop assets on the canvas to append variations (node spawns at drop point); drop on a Sound node replaces its file
- **Mixer tab**: lists the project bank; clicking shows a **bus-routing graph** (right-click → Add Bus). Master input-only, child buses output-right, one input pin per incoming child. Volume sliders per bus (0–100). Buses renameable (double-click node title; routing/volume/events all follow).
- **Export**: writes the bank `.tres` + all referenced audio files flat beside it. Bank format v2 (below).
- **Undo/redo**: Ctrl+Z / Ctrl+Shift+Z. Snapshot-based (whole state, 50 deep). Covers: event add/rename, trigger mode changes, variation add, bus add/rename/re-route, bus volume (one entry per drag gesture). Not undoable: project load/save, audio file ops.
- **Theme**: space-worm base + runtime overrides (dark `#0d0f16`, cyan/magenta/amber accents, rounded corners).

## Soundbank format (v2) — the parser contract, keep additive

```gdscript
SoundBank (Resource):
  format_version: int = 2
  events: Dictionary  # name -> {
                      #   trigger: "simple"|"random"|"playlist",
                      #   audio_file: String,          # simple mode
                      #   sounds: Array[String],       # random/playlist variations, pin order
                      #   random_mode: "random"|"shuffle",  # random only
                      #   playlist_loop: bool,         # playlist only (parser currently always loops)
                      #   bus: String, volume_db, pitch_scale, looping }
  buses: Dictionary   # bus name -> parent bus name
  bus_volumes: Dictionary  # bus name -> linear 0-100
```

Export layout: `bank.tres` + all audio files **flat in one folder**; `audio_file` values are bare filenames resolved relative to the bank.

## Target parser (middleware-game-test)

`AudioManager` autoload: `use_bank(path)` (validates v2, applies buses + volumes), `play_sound(event)` / `play(bank, event)`. Handles simple/random/shuffle/playlist picking via `_pick_audio()`, applies buses via `_apply_buses()` (additive-only). Warnings instead of crashes on missing events/files.

**Known gaps in parser:** `playlist_loop=false` not honored (always loops); no live-update hooks.

## Key architecture facts (don't re-litigate)

- **One source of truth**: `_events`, `_buses`, `_bus_volumes` Dictionaries in `Main.gd`. Every UI handler mutates them; `_build_graph()`/`_build_bus_graph()` re-render from data. Wiring is never stored.
- **Graph rebuilds are deferred** (`call_deferred`) when triggered from signals of nodes being freed (drops).
- **SoundBank.gd lives at `addons/middot_audio/SoundBank.gd` in BOTH repos** — same relative path so exported `.tres` script refs resolve. Changes must be mirrored.
- **`GraphEdit` internals**: never clear non-`GraphElement` children (kills `connections_layer`). Slot convention: left=in, right=out; `set_slot(row, left_enable, ...)` — getting this wrong snaps connection lines to node corners. One slot row per incoming edge on shared nodes.
- **Theme**: space-worm base theme (image-based .tres at `Themes/space-worm-theme/`, paths rewritten) + imperative StyleBoxFlat overrides in `_apply_theme_overrides()` in Main.gd. Replace with a full .tres reskin only if it grows past ~100 lines.
- **FileDialog gotcha**: `ResourceSaver` refuses unknown extensions; project files are JSON under `.middot`.
- Headless test pattern: instantiate `control.tscn`, drive handlers directly (`_on_*`, `_add_bus_at_cursor`), assert on state, self-delete script. See git-less history — tests were inline and cleaned up each time.

## Deferred by decision (do not re-litigate without cause)

- **Profiler** — design exists in `AUDIO_PROFILER_DESIGN.md` (debugger-plugin P1, TCP P2, live-update P3). Waiting until feature set stabilizes to avoid maintaining two systems.
- **OS drag-drop import** — removed; Audio-folder scan + focus rescan replaced it.
- 3D/spatialization, music sequencing, session recording.

## Next moves (ranked, from the FMOD/Wwise gap analysis)

1. **Multiple banks / project organization** — the data model change that unblocks the mixer tab becoming real, bank-per-category export, and the eventual refactor of state out of `Main.gd`. Biggest structural item; do before more features pile onto single-bank assumptions.
2. **Mute/solo on bus nodes** — tiny; `AudioServer.set_bus_mute/solo`; format stays additive.
3. **Audition (preview playback) in the graph** — play a Sound node's file in the authoring app; FMOD/Wwise never make you launch the game to hear a sound.
4. **Bus effects exposure** (reverb etc. — Godot bus effect slots; additive format change).
5. **Switch/parameter-driven variation** (Wwise Switch Container analog) — design Trigger node to leave room; needs format addition.
6. Only after 1–2: consider extracting authoring state from `Main.gd` into a model class — undo already forces discipline; multi-bank makes it necessary.

## Repo state

- Working tree: `Main.gd` (~740 lines, the whole app), 5 small helper classes, `control.tscn`, `AppMenuBar.gd`, theme at `Themes/space-worm-theme/`, sounds in `Audio/` (project-relative), `AUDIO_PROFILER_DESIGN.md`, `AGENTS.md` (FMOD/Wwise doc paths — consult before design work).
- Export preset "Windows Desktop" → `Desktop\MiddotWare\`. Rebuild: `godot --headless --path . --export-release "Windows Desktop" "$USERPROFILE/Desktop/MiddotWare/MiddotWare.exe"`
- **Still no git repo** — this was flagged in phase one's first review and remains the top hygiene item. `LICENSE` + `README.md` also still missing.
