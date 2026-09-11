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

func all() -> Array:
	var out: Array = []
	for t: String in types:
		out.append(by_name(t))
	return out

func by_name(type_name: String) -> NodeType:
	return types.get(type_name).new() if types.has(type_name) else null

## All menu actions across registered types, for the event-canvas context menu.
func menu_actions(ctx: NodeCtx) -> Array:
	var out: Array = []
	for t: String in types:
		out.append_array(by_name(t).menu_actions(ctx))
	return out

## True when `from_name` may connect into `to_name`. Node names carry their
## type as prefix (e.g. "Trigger", "Branch0", "Sub0_1", "Sound2", "Variable1").
## True when `from_name` may connect into `to_name` (node names carry their
## type as prefix, e.g. "Trigger", "Branch0", "Sub0_1", "Sound2", "Variable1").
## A connection is allowed when the TARGET type's "in" rules match the FROM
## node's name ("in" = who may connect into me).
## Connection validation by TYPE KEY (canvas nodes carry their type; names are
## just "N<id>"). Allowed when the from-type's "out" rules accept the to-type,
## or the to-type's "in" rules accept the from-type.
func connection_allowed(from_type: String, to_type: String) -> bool:
	var out_rules: Array = by_name(from_type).connect_rules().get("out", []) if types.has(from_type) else []
	if out_rules.has("*") or out_rules.has(to_type):
		return true
	var in_rules: Array = by_name(to_type).connect_rules().get("in", []) if types.has(to_type) else []
	return in_rules.has("*") or in_rules.has(from_type)

func _matches_any_out(from_name: String) -> bool:
	for t: String in types:
		for rule in by_name(t).connect_rules().get("out", []):
			if _wildcard(rule, from_name):
				return true
	return false

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

func _wildcard(pattern: String, name: String) -> bool:
	if pattern == "*":
		return true
	if pattern.ends_with("*"):
		return name.begins_with(pattern.trim_suffix("*"))
	return name == pattern

## Strip trailing digits/underscores: "Sub0_1" -> "Sub", "Branch12" -> "Branch".
func _type_prefix(node_name: String) -> String:
	var i := node_name.length()
	while i > 0 and (node_name[i - 1].is_valid_int() or node_name[i - 1] == "_"):
		i -= 1
	return node_name.substr(0, i)
