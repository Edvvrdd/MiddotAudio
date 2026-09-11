# MiddotWare — Phase Two Report

End of phase two: from a working single-trigger tool to a **backend/frontend architecture with a free-canvas graph editor, a three-mode transformable trigger, project-wide variables, and a compiled soundbank pipeline**. Handoff doc for the next session.

## What the product is

A free, open-source **audio middleware authoring tool** for Godot 4.7, FMOD/Wwise-inspired. Two repos:

- **This repo** (`middot-audio`): the authoring app → `Desktop\MiddotWare\MiddotWare.exe`
- **`C:\Users\edwar\Documents\middleware-game-test`**: target-game test project with the `middot_audio` parser addon + `AudioManager` autoload

## Architecture (the big change this phase)

**Backend/frontend split.** All authoring state and mutations live in **`backend/AudioBackend.gd`** (plain `RefCounted`): canvas (per-event nodes + wires), compiled events, variable registry, buses, project path, undo/redo stacks (whole-state snapshots, 50 deep), compile, migration, serialization (`to_dict`/`from_dict`). Emits `changed(what)` signals.

**Frontend** (`Main.gd` ~1000 lines + `nodes/*.gd`) is a view/broadcaster: every gesture is one backend call; re-rendering happens from `changed` signals. `NodeCtx` is the service object node scripts use (push_undo, rebuild, sync_declaration, spawn_pos) — node scripts never touch storage.

**Node types are plugins**: `nodes/NodeType.gd` contract + `NodeTypes.gd` autoload registry + per-type scripts (`SimpleSoundNode`, `RandomTriggerNode`, `PlaylistTriggerNode`, `ConditionalTriggerNode`, `VariableNode`, `EventOutputNode`). Adding a node type = 1 script + 1 register line (authoring) + 1 resolver + 1 register line (parser). Connection rules are per-type declarations validated by the registry.

**Parser mirrors the pattern**: `middleware-game-test/addons/middot_audio/nodes/` has `ResolverRegistry` + Simple/Random/Playlist/Conditional resolvers; `AudioManager._resolve_node` delegates. Same v3 recursive node schema on both sides.

## The free canvas (source of truth)

**The graph is a free canvas — the soundbank is compiled from it.**

- Per-event canvas: `{nodes: [{id, type, data, pos}], wires: [{from, from_port, to, to_port}], next_id}` stored in `_canvas`, persisted in the `.middot` as `"graph"`
- **Right-click menu (curated): Add Trigger / Add Sound / Add Variable / Add Looper / Add Output.** Placing is ungated and never mutates existing content; Looper is a menu placeholder that does nothing yet
- **No auto-connections.** Wires exist only because the user drew them; validated by per-type connection rules (type-key based). Wires + node positions persist across rebuilds (`end_node_move` writes positions back; rebuilds snapshot/restore wires) and across save/load
- **X button on every node titlebar** deletes it (root Trigger/Output have none). Del key also works via selection
- **Event Output node** carries event props (bus, volume, looping) and is the compile target

## The Trigger node (transforms itself)

One Trigger node with an **in-node type dropdown: Playlist / Random / Conditional** (default Playlist — one entry ≈ basic trigger):

- Playlist → Loop checkbox + "+ add pin"
- Random → Random/Shuffle picker + "+ add pin"
- Conditional → branch rows (default flag, op, variable, value) + "+ add branch"

Mode is data (`data.mode`); switching re-renders the body; compile maps mode → soundbank schema (`playlist`/`random`/`conditional`).

## Compile (canvas → soundbank)

On **Ctrl+S** (and Export): `backend.compile_all()` walks each canvas — **root = the node nothing feeds into** (Output node carries props only; wires into Output are ignored as decorative) — following output pins in order, recursing through children. Cycle-guarded (16 depth).

**Loud failures** (per explicit decision — the user hates silent errors): no Output node, no root, multiple roots, no-match conditional branch, cycles → `push_error` + `assert` (halts debug builds from the editor; red error in release logs).

## Variables (registry + free nodes)

Variables are declared once and **tracked project-wide forever** until manually deleted (X in Variables tab purges registry + every usage). Declared via the Variables tab or event canvas; renames/edits sync everywhere; branch conditions reference them by name at runtime (`AudioManager.set_parameter(...)`).

## Project file (.middot, JSON)

```gdscript
{format_version: 2,
 graph: _canvas,          # free canvas per event (NEW this phase)
 events: _events,         # last compiled trees (parser contract, additive v3)
 buses: {}, bus_volumes: {}, variables: {}}
```

**Legacy projects without `graph` migrate on load**: each event becomes Output + root trigger + recursively exploded children, pre-wired.

## Key facts / gotchas (learned the hard way)

- **GraphEdit slot ports are numbered per side** (input-capable rows only), not per child row. Connecting to a nonexistent port corrupts the connection cache → silent segfault in exported builds.
- **Never free a node mid-signal-emission** (e.g. rebuilding the graph inside a child widget's `item_selected`). Always `_build_graph.call_deferred()` — immediate free = use-after-free crash with no error output.
- **GraphEdit's deselect signal is `node_deselected`**, and it has `begin_node_move`/`end_node_move` for drag lifecycle; `get_titlebar_hbox()` is the supported way to add title-bar controls (no `show_close` in 4.7).
- **Backend owns state — nothing may cache dict references across loads** (`_load_project` replaces them; NodeCtx reads live via Main).
- Compile root rule: node that nothing feeds into; wires into Output are decorative.

## Deferred / known gaps

- **Looper**: menu placeholder only; schema slot reserved (loop-region playback)
- **Wires are session+canvas state**, not compiled into the bank — fine, but a copied project loses nothing since canvas persists in the .middot
- **No phase-1 features removed**: undo/redo (now backend-side), drag-drop import via Audio folder, asset rename follow-through, mixer bus routing — all intact
- **Still no git repo, no LICENSE, no README** — flagged since phase one, still the top hygiene item

## Verified test coverage (headless, all passing at phase end)

`BACKEND_OK` (state ops, wiring validation, compile, undo/redo of variables), `CANVAS_OK` (place/wire/compile/roundtrip), `MIG_OK` (legacy migration), `MODES_OK` (3-mode trigger transform + compile per mode), `POS_OK` (position persistence), `TRIG_OK` (curated menu, mode switch, output-wire ignored), `SMOKE_OK`, parser-side `REG_OK`/`NEST_OK`/`NOFAIL_OK`/`V2_REGRESS_OK`.

## Suggested next moves

1. **git init + LICENSE + README** (overdue since phase one)
2. **Parser-side registry tests** as permanent files (current tests are throwaway scripts)
3. **Looper real semantics** (loop-region playback, schema slot reserved)
4. **Audition playback** in the authoring app (F5-style preview without launching the target game)
5. Revisit the profiler design (`AUDIO_PROFILER_DESIGN.md`) once features settle — backend split makes the canvas→stats pipeline cleaner now
