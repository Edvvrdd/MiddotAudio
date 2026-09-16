extends Node

## Registry of authoring node types. Adding a node type = write a script under
## res://nodes/ extending NodeType, then add one register() line here.

var types := {}

func _ready() -> void:
	register(preload("res://nodes/SimpleSoundNode.gd"))
	register(preload("res://nodes/RandomTriggerNode.gd"))
	register(preload("res://nodes/PlaylistTriggerNode.gd"))
	register(preload("res://nodes/ConditionalTriggerNode.gd"))
	register(preload("res://nodes/VariableNode.gd"))
	register(preload("res://nodes/EventOutputNode.gd"))

func register(script: GDScript) -> void:
	var inst: NodeType = script.new()
	types[inst.type_name()] = script

func by_name(type_name: String) -> NodeType:
	return types.get(type_name).new() if types.has(type_name) else null

## True when the from-type may connect into the to-type. Allowed when the
## from-type's "out" rules accept the to-type, or the to-type's "in" rules
## accept the from-type.
func connection_allowed(from_type: String, to_type: String) -> bool:
	var out_rules: Array = by_name(from_type).connect_rules().get("out", []) if types.has(from_type) else []
	if out_rules.has("*") or out_rules.has(to_type):
		return true
	var in_rules: Array = by_name(to_type).connect_rules().get("in", []) if types.has(to_type) else []
	return in_rules.has("*") or in_rules.has(from_type)

## Shape-based dispatch: which type's collect_files handles this node dict?
## (SoundBank node schema, mirrored in the parser's ResolverRegistry._type_of.)
func collect_files_dispatch(node: Dictionary, files: Array) -> void:
	if node.has("branches"):
		by_name("conditional_trigger").collect_files(node, files)
	elif node.get("trigger") == "playlist":
		by_name("playlist_trigger").collect_files(node, files)
	elif node.get("trigger") == "random":
		by_name("random_trigger").collect_files(node, files)
	else:
		by_name("sound").collect_files(node, files)
