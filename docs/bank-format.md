# Soundbank format v3

A soundbank is a Godot `Resource` (script: `addons/middot_audio/SoundBank.gd`,
same relative path in the authoring app and the target game) saved as a
`.tres` file next to the audio files it references.

**Stability contract:** target parsers gate on `format_version` before reading
`events`. Changes are additive only — new optional fields, never re-shaped
ones. A shape change means v4 with a version gate and migration notes.

## Resource fields

| Field | Type | Meaning |
| --- | --- | --- |
| `format_version` | `int` | `3` |
| `events` | `Dictionary` | event name (`String`) → compiled node tree (below) |
| `buses` | `Dictionary` | bus name → parent bus name (`""` = routes nowhere, typically Master-only projects omit this) |
| `bus_volumes` | `Dictionary` | bus name → linear volume `0..100` (absent = unchanged) |

The game's `AudioManager` applies buses additively on bank load: creates
missing buses, routes sends, sets volumes. It never removes or re-parents
existing buses, so the runtime tree only grows and gameplay code can rely on
buses staying valid.

## Compiled event tree

Each event is a recursive node dictionary. Every node may have any of the
documented keys; unknown keys are ignored by the parser (forward-compatible).

Common keys:

| Key | Meaning |
| --- | --- |
| `trigger` | node type: `"simple"`, `"random"`, `"playlist"`, `"conditional"`, `"sync"` |
| `audio_file` | file name, relative to the bank's folder |
| `bus` | target bus name (unknown bus → plays on Master with a warning) |
| `volume_db` | event volume in dB |
| `pitch_scale` | event pitch multiplier |
| `looping` | `true` → the event restarts when finished |
| `file_volume_db` | per-file volume offset, additive with `volume_db` |
| `pitch_scale` (leaf) | per-file pitch, replaces event pitch |

### trigger: `"simple"`

One file plays. Keys: `audio_file`, plus per-file `file_volume_db` / `pitch_scale`.

### trigger: `"random"`

```gdscript
{ "trigger": "random", "random_mode": "random" | "shuffle", "sounds": [ ... ] }
```

- `random`: pick one child at random.
- `shuffle`: pick without repetition until all played, then reshuffle.
- Each child: a plain file (string or `{audio_file: ...}`), or a nested node
  (any trigger type; nesting is recursive).
- Parser detail: when all children are plain files, the parser builds a stock
  `AudioStreamRandomizer` (`PLAYBACK_RANDOM` / `PLAYBACK_RANDOM_NO_REPEATS`).
  Nested children fall back to resolver-side picking.

### trigger: `"playlist"`

```gdscript
{ "trigger": "playlist", "playlist_loop": true, "sounds": [ ... ] }
```

Plays children in order; advances the cursor on each trigger; `playlist_loop`
wraps at the end. Children may be files or nested nodes.

### trigger: `"sync"`

All `sounds[]` play simultaneously, one voice each (music layers, stings).
Children may be files or nested nodes.

### trigger: `"conditional"`

```gdscript
{ "trigger": "conditional", "branches": [ <node>, ... ],
  "branch_conditions": [ {"conditions": [ {"param": "hp", "op": "<", "value": "30", "type": "int"} ]}, ... ] }
```

Branches are evaluated in order; the first whose `conditions` all pass plays
(AND semantics). `op` ∈ `== != < <= > >=`. Comparisons respect `type`
(`enum`/`int`/`float`/`bool`); the game sets parameters before playing via
`AudioManager.set_parameter("hp", 25)`. A branch with empty `conditions`
matches always (use as the default branch). An event-level `conditions` array
(no `branches`) gates the whole event the same way.
