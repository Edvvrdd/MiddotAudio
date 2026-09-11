# Architecture: Node Types as Plugins

## Current structure: backend/frontend split (implemented)

- **backend/AudioBackend.gd** — owns ALL authoring state (canvas, events, variables, buses) and every mutation: place/delete/connect, compile, undo stacks, migration, serialization (to_dict/from_dict). Emits  signals.
- **Frontend** (Main.gd + nodes/*.gd) — renders from backend state; every user gesture calls a backend method and re-renders from the  signal. Node scripts read data dicts, never touch storage.
- Undo/redo lives entirely in the backend (whole-state snapshots, 50 deep) — granular stacks are now trivial because every mutation funnels through one object.
- Ctrl+S / Export:  compiles canvases into event trees, persists, and the parser consumes the compiled events.

---

# Original design notes (historical)

## The problem you named

Every new node type's entry points are welded into `Main.gd`:

- The trigger **mode dropdown** is the gate for everything (branches need conditional first)
- `_build_graph()` / `_build_nested_graph()` hand-render every node type inline
- The right-click menu, connection rules, undo, export — all hardcode node knowledge
- Cost so far: `Main.gd` is 1360 lines, and each feature touched 6+ of its functions

## The target shape

**A node type = one self-registering script.** `Main.gd` becomes a shell that asks
the registry what exists. Concretely, three moving parts:

### 1. `NodeTypes.gd` — the registry (autoload)

```gdscript
# Each node type registers itself at ready:
#   NodeTypes.register("conditional_trigger", preload("res://nodes/ConditionalTriggerNode.gd"))
var types := {}          # name -> script (extends NodeTypeDef)
func register(type_name: String, script: GDScript) -> void: ...
func all() -> Array: ...
func by_name(n: String) -> GDScript: ...
```

### 2. `NodeType.gd` — the contract every node type implements

```gdscript
extends RefCounted
# What the node declares about itself:
func type_name() -> String: ...            # "conditional_trigger"
func display_name() -> String: ...         # "Conditional Trigger" (menu label)
func can_be_root() -> bool: ...            # event root vs sub-node only
func is_container() -> bool: ...           # has children pins (random/conditional)
func create_node(data, ctx) -> GraphNode: ...   # build the GraphNode UI
func menu_actions(ctx) -> Array: ...       # [{label, id, enabled}] for right-click
func run_action(id, ctx) -> void: ...      # execute a menu action
func connect_rules() -> Dictionary: ...    # {accepts_from: ["*"], outputs_to: ["*"]}
func collect_files(data, files) -> void: ...    # export walk
func resolve(data, ctx) -> String: ...     # parser-side pick (mirrored in addon)
```

`ctx` is a small service object the host passes in: `{push_undo, rebuild_deferred,
events, variables, selected, spawn_pos, sync_declaration, audio_dir}`. Node types
never touch Main directly — they call ctx.

### 3. `Main.gd` shrinks to host code

- `_build_graph` → asks the event's root node type to `create_node`, then asks each
  container node to render its children via the same mechanism (recursion comes free)
- Right-click menu → union of every type's `menu_actions`
- Connection validation → table-driven from `connect_rules()`
- Export → walks nodes via `collect_files`
- No `if trigger == "conditional"` anywhere in Main

## What this buys immediately

- **Add Variable / Add Branch / New Trigger** become menu actions offered by their
  owning node type — no gating on "trigger must be Conditional first". A branch
  action appears wherever a container can receive one; variables work anywhere.
- New node types (e.g. a future Blend trigger, Weighted Random, Sequence) become:
  drop one script in `nodes/`, register it, done. Zero edits to Main.gd.
- The nested-graph renderer generalizes: `_render_sub_trigger`/_render_branch
  collapse into "ask each node to render itself and its children".

## Status: IMPLEMENTED (this refactor)

- nodes/ contains NodeType contract, NodeTypes registry (autoload), NodeCtx, and 5 types
- Main.gd: menus, connection validation, file collection, and rendering delegate to the registry; zero  conditionals remain in Main
- Parser mirrored: addons/middot_audio/nodes/ has ResolverRegistry + Simple/Random/Playlist/Conditional resolvers
- Adding a node type now: 1 script in nodes/ + 1 register line (authoring) + 1 resolver + 1 register line (parser)
- Connection rules are per-type declarations; ctx service (push_undo, rebuild, sync_declaration, spawn_pos) keeps node scripts decoupled from Main

## Original migration plan (historical)

1. Extract `VariableNode`, `ConditionalTriggerNode`, `RandomTriggerNode`,
   `PlaylistTriggerNode`, `SimpleSoundNode` into `nodes/*.gd`, Main delegates
2. Introduce `NodeTypes.gd` registry + ctx; menus/actions/rules become data-driven
3. Connection rules + `_assert_edges` table-driven
4. Parser: the addon mirrors the same registry pattern (its match statement maps
   to per-type `resolve()` scripts — keeps target-side equally extensible)
5. Re-test: full headless suite (undo, variables, branches, nested, export roundtrip)

## Not doing

- No per-node .tscn scenes — nodes are built in code (they already are)
- No plugin loader/scan-dirs — a simple preload list in the registry; the "plugins"
  live in the repo, not drop-in addons (that's a much later need)
- Not touching the soundbank format — this is authoring-side structure only;
  the bank's recursive node schema already supports arbitrary new trigger types
