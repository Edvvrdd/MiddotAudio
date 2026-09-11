extends NodeType

## Random trigger (pure or shuffle). Data: {trigger: "random", random_mode,
## sounds: [file-or-node...]}
## Menu: "Add Random Trigger" — places a new Random sub-trigger wherever the
## canvas allows it; not gated on any existing node.

func type_name() -> String:
	return "random_trigger"

func display_name() -> String:
	return "Random Trigger"

func can_be_root() -> bool:
	return true

func is_container() -> bool:
	return true

func menu_actions(_ctx: NodeCtx) -> Array:
	return [{"label": "Add Random Trigger", "id": 10, "enabled": true}]

func run_action(_id: int, ctx: NodeCtx) -> void:
	var e: Dictionary = ctx.selected_event()
	if e.is_empty():
		return
	ctx.push_undo()
	# pure append: a new empty node, no mutation of existing content, no
	# auto-wiring. User wires it and sets trigger modes themselves.
	e.get_or_add("sounds", []).append({"trigger": "random", "random_mode": "shuffle", "sounds": []})
	ctx.set_spawn_pos(ctx.spawn_pos())
	ctx.rebuild_event_deferred()

func connect_rules() -> Dictionary:
	return {"in": ["conditional_trigger"], "out": ["sound", "random_trigger", "playlist_trigger", "conditional_trigger"]}

func collect_files(data: Dictionary, files: Array) -> void:
	for child in data.get("sounds", []):
		if child is String:
			files.append(child)
		else:
			NodeTypes.collect_files_dispatch(child, files)

func create_node(data: Dictionary, node_name: String, ctx: NodeCtx) -> GraphNode:
	var sub_node := GraphNode.new()
	sub_node.name = node_name
	sub_node.title = "Random Trigger"
	var mode_opt := OptionButton.new()
	mode_opt.add_item("Random")
	mode_opt.add_item("Shuffle (no repeat until all played)")
	mode_opt.select(1 if data.get("random_mode", "random") == "shuffle" else 0)
	mode_opt.item_selected.connect(func(idx: int) -> void: data["random_mode"] = "random" if idx == 0 else "shuffle")
	sub_node.add_child(mode_opt)
	var add_pin := Button.new()
	add_pin.text = "+ add pin"
	add_pin.pressed.connect(func() -> void:
		ctx.push_undo()
		data["pins"] = data.get("pins", 1) + 1
		ctx.rebuild_deferred())
	sub_node.add_child(add_pin)
	for j in data.get("pins", 1):
		var pin := Label.new()
		pin.text = "Out %d" % (j + 1)
		sub_node.add_child(pin)
		sub_node.set_slot(sub_node.get_child_count() - 1, false, 0, Color.WHITE, true, 0, Color.WHITE)
	return sub_node

