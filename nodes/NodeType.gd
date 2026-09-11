class_name NodeType
extends RefCounted

## Contract every node type implements. Main (the host) asks the registry for
## types and calls these — node types never hardcode knowledge of each other
## beyond the shared data schema (the recursive trigger node in SoundBank).
##
## Node types must not reach into Main directly; use the ctx service.

func type_name() -> String:
	return ""

func display_name() -> String:
	return type_name()

## Can an event's root node be this type?
func can_be_root() -> bool:
	return false

## Does this node own children (variation/branch pins)?
func is_container() -> bool:
	return false

## Menu entries this type contributes to the event-canvas right-click menu.
## Return [] for none. Each entry: {label: String, id: int, enabled: bool}
func menu_actions(_ctx: NodeCtx) -> Array:
	return []

## Execute one of this type's menu actions.
func run_action(_id: int, _ctx: NodeCtx) -> void:
	pass

## Build the GraphNode for this node. `data` is the node's dict; `name` the
## GraphNode.name to use; `on_edit` (optional) is called when data mutates.
func create_node(_data: Dictionary, _name: String, _ctx: NodeCtx) -> GraphNode:
	return GraphNode.new()

## Connection rules: which from-node name prefixes may connect INTO this
## node's inputs, and which target prefixes this node's outputs may reach.
## "*_pin" semantics: {"in": ["Trigger", "Branch*"], "out": ["Sound*", "Sub*"]}
## Prefix with * for prefix wildcard.
func connect_rules() -> Dictionary:
	return {"in": [], "out": []}

## Recursively collect audio filenames referenced by this node's data.
func collect_files(_data: Dictionary, _files: Array) -> void:
	pass
