extends NodeType

## Playlist trigger (sequential, loops). Data: {sync, playlist_loop, pins}

func type_name() -> String:
	return "playlist_trigger"

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
	sub_node.title = "Playlist Trigger"
	var sync_check := CheckBox.new()
	sync_check.text = "Sync (play all pins together)"
	sync_check.button_pressed = data.get("sync", false)
	sync_check.toggled.connect(func(on: bool) -> void: data["sync"] = on)
	sub_node.add_child(sync_check)
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

