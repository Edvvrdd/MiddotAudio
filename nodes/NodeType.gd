class_name NodeType
extends RefCounted

## Contract every node type implements. Main (the host) asks the registry for
## types and calls these — node types never hardcode knowledge of each other
## beyond the shared data schema (the recursive trigger node in SoundBank).
##
## Node types must not reach into Main directly; use the ctx service.

func type_name() -> String:
	return ""

## Build the GraphNode for this node. `data` is the node's dict; `name` the
## GraphNode.name to use.
func create_node(_data: Dictionary, _name: String, _ctx: NodeCtx) -> GraphNode:
	return GraphNode.new()

## Connection rules by TYPE KEY: which node types may connect INTO this
## node's inputs ("in"), and which target types this node's outputs may reach
## ("out"). "*" accepts anything.
func connect_rules() -> Dictionary:
	return {"in": [], "out": []}

## Recursively collect audio filenames referenced by this node's data.
func collect_files(_data: Dictionary, _files: Array) -> void:
	pass
