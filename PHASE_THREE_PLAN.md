# MiddotWare — Phase Three Plan (for review)

Proposed scope and ordering. Nothing here starts until you approve; comments welcome inline.

## Goal

Turn the phase-two prototype into a project someone else can open and use: hygiene first, audition (hear sounds without launching the game) as the flagship feature, then the two deferred structural items (permanent tests, multi-bank).

## Work items, in order

### 1. Hygiene (overdue since phase one — do first, ~1 session)

- `git init` + `.gitignore` already exists; commit the current state as baseline before any further changes.
- `LICENSE` (MIT — it's advertised as free/open-source; confirm choice).
- `README.md`: what the tool is, two-repo model, how to open/export, link to the target-game test project.

### 2. Audition playback in the authoring app (flagship)

FMOD/Wwise never make you launch the game to hear a sound. Stock Godot only:

- Per-canvas "audition" play button (and/or F5): compiles the selected event in memory and plays it with `AudioStreamPlayer`s in the authoring app, honoring trigger mode (random/shuffle/playlist order/loop) and bus routing via real `AudioServer` buses + volume.
- Optional: double-click a Sound node to play just that file.
- No soundbank-format changes required. No parser-side changes.

### 3. Permanent headless tests (was: throwaway scripts)

- One committed test runner script + suite files (`BACKEND`, `CANVAS`, `MIG`, `MODES`, `POS`, `TRIG`, `SMOKE`) — same assert-and-self-delete pattern, but checked in and runnable on demand: `godot --headless --path . --script tests/run.gd`.
- Parser-side: same treatment in `middleware-game-test` (`REG`, `NEST`, `NOFAIL`, `V2_REGRESS`).
- Rationale: phase three adds audition + format-adjacent features; regressions need a re-runnable net, not session-flavored scripts.

### 4. Looper semantics (schema slot reserved)

- Implement loop-region playback: Looper node loops its input N times or until a stop condition.
- Soundbank: additive field on the compiled tree (e.g. `"loop": {count, ...}` inside the node dict) — bump nothing; v3 stays v3 if the parser treats unknown fields as ignore-with-warning, otherwise v4. Decide after checking the parser's unknown-field behavior.
- Parser resolver side mirrored.

### 5. Bus mute/solo + effects (small, additive)

- Mute/solo toggles on mixer bus nodes → `AudioServer.set_bus_mute/solo`; export format additive (`bus_mutes`/`bus_solos` or extend `bus_volumes` shape — pick one, document it).
- Bus effects (reverb etc.) → Godot bus effect slots; additive `bus_effects` field only if stock Godot can express the chosen effect list (per design constraints).

### 6. Multi-bank / project organization (deferred from phase one — decide now or cut)

- Bank-per-category export, event grouping. Largest remaining structural item; touches backend data model, compile, and project serialization.
- Recommendation: do it **after** audition ships and only if mixer/events browsing actually hurts at current event counts. YAGNI until the single-bank model demonstrably pinches.

## Explicitly deferred (do not re-litigate)

- **Profiler** (`AUDIO_PROFILER_DESIGN.md`) — after the feature set settles; backend split makes the pipeline cleaner when we get there.
- OS drag-drop import (replaced by Audio-folder scan), 3D/spatialization, music sequencing, session recording.

## Soundbank format policy

All phase-three changes additive on v3. Any unavoidable shape change = v4 with a migration note in `SoundBank.gd` and a parser-side version gate; never break v3 readers silently.

## Suggested phase-three done criteria

- Repo in git with LICENSE/README; headless suites committed and green on both sides; audition working end-to-end against the target project; Looper either real or removed from the menu.
