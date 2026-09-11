# Free-Canvas Architecture (supersedes parts of NODE_ARCHITECTURE.md + nesting design)

## The shift

Before: the event dict (`_events`) was the source of truth; the graph was a
rendering of it; edits mutated data directly.

Now: **the canvas is the source of truth.** Nodes and wires live in a per-event
`_canvas` store and are freely placed — nothing is derived, nothing auto-wires,
nothing mutates on add. On **Ctrl+S** (and on Export) the canvas is **compiled**:
node paths are walked from each event's Output node and written as the recursive
trigger tree into `_events`, which `save_project` persists and the parser consumes.

## Canvas model

```
_canvas[event_name] = {
  "nodes": [ {"id": int, "type": String, "data": Dictionary, "pos": Vector2} ],
  "wires": [ {"from": id, "from_port": int, "to": id, "to_port": int} ],
  "next_id": int,
}
```

Node types (registry): `sound`, `random_trigger`, `playlist_trigger`,
`conditional_trigger`, `event_output`, `variable`.

- **Containers** (random/playlist/conditional) carry a `pins` count; children are
  whatever nodes are wired FROM their pins, in pin order. Unwired pin = skipped
  branch/variation at compile.
- **Conditional** carries `branch_conditions` (one entry per pin: `{default,
  conditions}`) — edited inline on the node; "+ add branch" = new pin + entry.
- **Event Output node** carries event-level props: bus, volume_db, pitch_scale,
  looping. Compile starts here.
- **Variable nodes** are declarations (registry-backed); no wires.

## Compile

`_compile_event(name)`: find the Output node → follow the wire into it → that
node is the root → recurse: each container's children = wired targets sorted by
output port; conditional maps pin i to `branch_conditions[i]`. Cycle-guarded
(visited set, 16 depth). **No Output, or Output with no incoming wire = loud
error** (push_error + assert in debug) per the no-silent-failures decision.

## Persistence

- `.middot` gains `"graph": _canvas` (the canvas IS the project now).
- `events` in the .middot = last compiled output (kept for the parser).
- **Migration**: old projects without `graph` are converted on load — each event
  becomes Output node + root trigger node + recursively exploded children, wired.

## What gets deleted from Main.gd

The entire derived-rendering apparatus: `_build_tree_graph`, `_render_tree_branch`,
`_render_sub_tree`, `_render_nested_node`, `_render_sound_leaf`,
`_render_variable_nodes`, `_connect_chain` (already gone), branch migration/seeding,
and the trigger-mode dropdown on events (root type = whatever wires into Output).

## Interactions after the shift

- Right-click → "Add <Type>" for every registered type (ungated, free placement)
- X button / Del → removes node + incident wires from canvas
- Wires only exist because you drew them; they live in `_canvas` and persist
- Compile errors are loud (no silent skipped events)
