# Nested Trigger Graphs — Design Proposal

Status: PROPOSAL — awaiting review, not implemented. This is the big one: it restructures the soundbank event model.

References: Wwise ch. 22 (containers nest freely — the footstep example is literally "Switch Container grouping Random Containers, so a different sound plays each step on the same surface"); FMOD ch. 20 (Multi Instrument: "its playlist can contain nearly any kind of instrument... and other multi instruments" — arbitrary recursion); FMOD instrument trigger conditions (probability/parameter/event on ANY instrument). Godot side unchanged: pick-at-trigger-time stays pure GDScript; no native container object needed for one-shots.

## 1. The concept

Today an event is: one trigger mode → flat list of sound files. The nesting feature generalizes this to a **tree**: any trigger can contain other triggers as its variations, to arbitrary depth.

The canonical example (Wwise's own footstep walkthrough):

```
footstep (Conditional: surface == ?)
├─ branch "grass" → Random trigger → [grass1.wav, grass2.wav, grass3.wav]
├─ branch "stone" → Random trigger → [stone1.wav, stone2.wav]
└─ branch "wood"  → Single → wood.wav
```

Evaluating `play_sound("footstep")`: conditional picks a branch by parameters, the branch's own trigger logic (random/shuffle/playlist/…) picks the actual file. Every existing trigger type becomes a node that can live at any depth.

## 2. Format: one node type, recursive by construction (v3)

The lazy-but-correct trick: **an event's `trigger` field keeps its meaning, but `sounds` may contain either a filename OR a nested trigger object.** One rule, applied recursively:

```
node := { trigger: "simple",  audio_file, ... }                      # leaf
      | { trigger: "random",    random_mode, sounds: [node...], ... } # branch: file or nested
      | { trigger: "playlist",  playlist_loop, sounds: [node...], ... }
      | { trigger: "conditional", conditions: [{param,op,value}...], branches: [node...] }
```

- **additive in practice**: today's `sounds: Array[String]` becomes `sounds: Array[String | node]`; a v2 parser reading a nested node just fails to `load()` a dict-as-path with a warning (already the parser's failure mode for missing files). Conditions stay index-parallel for conditional nodes.
- Conditional nodes use a **`branches` list** (one child per condition) instead of reusing `sounds`, so a conditional node's children are always sub-triggers, never bare files — cleaner semantics, and per-branch conditions stay parallel to branches.
- **Variables**: existing `_variables` registry slots in unchanged — conditions at any depth reference the same project-wide variables.
- `format_version` bumps to 3 in the authoring app's export; the parser accepts 2–3.

Explicitly rejected alternatives: separate `branches` event entries with IDs (broke locality, complicate export), or a generic "node graph" serialization (massively overbuilt — trees suffice; Wwise and FMOD both model this as trees/ordered lists, not free graphs).

## 3. Parser (`_pick_audio` becomes `_resolve_node`)

```gdscript
func _resolve_node(node: Dictionary, event_name: StringName) -> String:
    match node.get("trigger", "simple"):
        "simple":      return node["audio_file"]
        "random":      pick/shuffle among _eligible children, recurse
        "playlist":    cursor over children, recurse
        "conditional": first branch whose conditions all pass → recurse into it
```

- Shuffle pools keyed by `(event_name, node_path)` so nested shuffles don't share state; playlist cursors likewise.
- A conditional node with **no eligible branch → play nothing + warn** (existing convention).
- Recursion depth is naturally bounded by authoring UI sanity (we won't need a hard cap for v1; add depth limiter at 16 as a guard).

## 4. Authoring UI: the event graph becomes a tree

- **Conditional Trigger node gains one output pin per branch** (like the current random variation pins) — condition rows stay on the node.
- **Branch output pins connect to child trigger nodes** (Random/Playlist/Conditional/Sound). Child sub-trigger nodes are the same node type as the root, just placed to the right.
- Sound nodes remain the only leaves; a branch pin left unconnected = empty branch.
- Right-click menu gains "Add Random Trigger", "Add Playlist Trigger" as placeable nodes. Connection rules generalize: any Trigger-node output → any Trigger/Sound input, type-checked (no file into a trigger, no trigger into Output).
- **Variables tab untouched.** Conditions still reference the registry; depth doesn't affect them.

## 5. What stays compatible

- Export walks the tree; leaf audio files still export flat (same as today).
- `format_version: 3` on export; target parser updated in lockstep (it's ours).
- **Simple events are byte-identical** — single-mode keeps `audio_file` at top level, so v2 banks load without migration. Random/playlist events gain the option of nested children but flat string lists remain valid.

## 6. Implementation order

1. Format + parser `_resolve_node` recursion (works on hand-authored banks first)
2. UI: conditional branch pins + placeable sub-trigger nodes + generalized connection rules
3. Drop/undo/rebuild generalization for the tree
4. Round-trip tests: nested random-under-conditional, shuffle pool independence, deep chains (3 levels), branch-miss behavior
5. Export + middleware-game-test verification

## 7. Deferred (don't build now)

- Blend/crossfade layers (`AudioStreamInteractive`'s job, music later)
- RTPC automation on nested nodes
- Free-form graph cycles (DAGs) — trees cover the use cases; loops make evaluation ambiguous
- Conditions on random/playlist nodes (only conditional nodes branch) — additive later if needed

## 8. Decisions

1. **Branch selection: first-match-wins** top-to-bottom (overlapping conditions resolve by order, FMOD logic-marker style), with an optional "default" flag on one branch as catch-all. **No eligible branch is a LOUD failure, not silence**: the parser `push_error`s with the event name, path, and parameters, and `assert(false, ...)` halts the game when running from the editor (debug builds). The user explicitly rejected silent no-ops — missing branches are authoring bugs and must surface immediately. In exported release builds asserts are stripped, so it degrades to a loud red error in the log.
2. **Nesting allowed anywhere** a child can exist (random-under-random etc.) — same recursion.
3. **Depth cap: 16** levels, parser-side guard against pathological authoring.

## 9. Performance note (reviewed)

Nesting adds only trigger-time decision-tree traversal: per level a handful of Dictionary lookups and comparisons (microseconds), once per `play_sound()`. Exactly ONE leaf file plays per call — nesting never stacks voices, so mixer load, per-frame cost, and memory are unchanged vs today. The dominant cost on the play path remains the stream `load()` that already happens for every play (first-play disk I/O); preloading streams as samples is the lever for that if it ever shows up, independent of nesting.
