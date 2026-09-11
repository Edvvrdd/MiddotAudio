# AGENTS.md

Guidance for AI coding agents working in this repo.

## What this is

**MiddotAudio** (product name **MiddotWare**) — a free, open-source audio middleware *authoring tool* for Godot 4.7.

The core idea: this app is **not** an audio engine. It produces a **soundbank file** (a Godot `.tres` resource, see `SoundBank.gd`) describing how a target game's audio system should be built out. The **target game** embeds a small parser/runtime that reads this soundbank and wires everything up using **native Godot audio only** (AudioStreamPlayer, buses, AudioServer). No external audio engine, no C++ modules, no GDExtension runtime side.

Mental model:

- **This repo = authoring app.** Godot editor tool with a UI (`control.tscn` / `Main.gd`) that lets a designer define sound events and export a soundbank (`.tres`) plus the audio files it references.
- **Target game = consumer.** Reads the exported soundbank, creates buses/polyphonic players/streams per its contents, and exposes a simple play API keyed by event name (e.g. `play("player_hurt")`).

## Current state

Working prototype (phase two done — see `PHASE_ONE_REPORT.md` / `PHASE_TWO_REPORT.md` for the full handoff history):

- **Backend/frontend split.** All authoring state and mutations live in `backend/AudioBackend.gd` (plain `RefCounted`): per-event free canvases (nodes + wires), compiled event trees, variable registry, buses, undo/redo. Emits `changed(what)` signals. `Main.gd` is a view/broadcaster; node scripts never touch storage — they use the `NodeCtx` service object.
- **Node types are plugins**: `nodes/NodeType.gd` contract + `nodes/NodeTypes.gd` autoload registry + one script per type (`SimpleSoundNode`, `RandomTriggerNode`, `PlaylistTriggerNode`, `ConditionalTriggerNode`, `VariableNode`, `EventOutputNode`). The Trigger node transforms itself between Playlist / Random / Conditional via `data.mode`.
- **The free canvas is the source of truth; the soundbank is compiled from it** (`backend.compile_all()` on Ctrl+S/Export; root = the node nothing feeds into; loud failures, no silent errors).
- **Project files** are JSON with a `.middot` extension, saved beside an `Audio/` folder (project-relative, outside this repo). Soundbank export is bank `.tres` + audio files flat in one folder.
- **Soundbank format v3**: `format_version: int`, `events` (name → recursive node tree: `simple`/`random`/`shuffle`/`playlist`/`conditional` with `conditions[]`), `buses` (name → parent), `bus_volumes` (0–100). Variables are set at runtime via `AudioManager.set_parameter()`.
- `SoundBank.gd` — lives at `addons/middot_audio/SoundBank.gd` **deliberately**: the same relative path as in the target game, so exported `.tres` files reference a script path that resolves in the consumer project. Changes must be **mirrored** to the target repo.
- `Themes/space-worm-theme/` — the theme; `soft_retro/` holds fonts (`Righteous`) and leftover art.

**Hygiene debt (top item since phase one):** no git repo, no `LICENSE`, no `README.md`.

## Conventions

- Godot **4.7**, GDScript, GL Compatibility renderer. Match existing style: tabs, typed GDScript where practical (`@onready var x: Type = ...`, typed params), signal handlers named `_on_<node>_<signal>`.
- Editing via the Godot editor is expected for scenes/theme; keep `.tscn`/`.tres` hand-edits minimal and consistent with Godot's output format.
- `.editorconfig`: UTF-8, LF line endings. Don't commit `.godot/`.
- Keep the soundbank format **stable and versioned** — target-game parsers depend on it. If you change the shape of `SoundBank.events` or the resource layout, that's a breaking change: document it prominently and prefer additive fields.

## Related projects

- **Target game / parser test project:** `C:\Users\edwar\Documents\middleware-game-test` ("Middleware Game test", Godot 4.7). It consumes the exported soundbank via a `middot_audio` addon and an `AudioManager` autoload. When changing the soundbank format or export logic, verify against this project — it is the integration test target for the parser.

## FMOD reference (offline docs)

The design and architecture of this app are heavily inspired by **FMOD Studio**. Offline manual: `C:\Program Files\FMOD SoundSystem\FMOD Studio 2.03.14\documentation\FMOD Studio User Manual` (HTML). Consult it often when designing UI or architecture — e.g. event browser, sound-event node graphs, banks, the `play_sound`-style API. Match FMOD's concepts where practical so the app feels familiar to FMOD users.

## Wwise reference (offline docs)

**Wwise** (Audiokinetic) is the other industry-standard audio middleware — also a design reference for this app. Compiled help: `C:\Audiokinetic\Wwise_2025.1.10.9233\Authoring\Help\WwiseHelp_en.chm`. It is a Windows CHM: to read it, decompile once with `hh.exe -decompile <out_dir> <path-to-chm>` (a decompiled copy was left at `%TEMP%\wwise_help`, 1000+ HTML pages). Use it for middleware design patterns Wwise does well — event/action model, sound object hierarchy, random/sequence containers, blend containers, buses/aux sends, SoundBank generation and layout. Cross-check FMOD and Wwise both before locking a soundbank-format decision; prefer whichever models the concept more cleanly, constrained by the stock-Godot-audio rule.

## Design constraints (don't violate these)

- Everything on the target-game side must be achievable with stock Godot audio (AudioServer, buses, AudioStreamPlayer/PolyphonicStreamPlayback). If a feature in the soundbank can't be expressed that way, cut the feature, not the constraint.
- The exported bank should be self-contained: event data + the audio files, with relative paths so it works when dropped into any project.
- Keep the authoring app dependency-free (no addons unless genuinely necessary).

## When adding features

- **New node type** = 1 script under `nodes/` extending `NodeType` + 1 `register()` line in `NodeTypes.gd` (authoring side) + 1 resolver + 1 register line in the parser's `ResolverRegistry` (target side).
- **New soundbank field** → add to `SoundBank.gd` as `@export`, surface it in the owning node's plugin script / backend defaults, and mirror it in the parser. The target parser contract is the dictionary of exported fields.
- Prefer plain Dictionaries/Resources in the bank over custom nested classes — the parser in the target game should need minimal code.
- Test exports by running the app scene (`control.tscn`) and saving a bank; open the bank in a throwaway project to confirm it loads. Headless tests: instantiate `control.tscn`, drive handlers directly, assert on backend state, self-delete the script (phase-two suites are listed in `PHASE_TWO_REPORT.md`).
