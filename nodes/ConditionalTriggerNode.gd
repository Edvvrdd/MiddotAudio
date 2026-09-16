extends NodeType

## Trigger node — transforms based on its own type selection (dropdown inside
## the node): Conditional (branch rows + conditions) or Looper (loop + pins).
## Data: {mode: "conditional"|"looper", branch_conditions: [...],
##        playlist_loop: bool, pins: int}
## Compile (backend): mode looper -> playlist schema, conditional -> branches.

const ACCENT3 := Color("e8b84b")

func type_name() -> String:
	return "conditional_trigger"

func connect_rules() -> Dictionary:
	return {"in": [], "out": ["sound", "random_trigger", "playlist_trigger", "conditional_trigger"]}

func collect_files(data: Dictionary, files: Array) -> void:
	for child in data.get("branches", []):
		if child is String:
			files.append(child)
		else:
			NodeTypes.collect_files_dispatch(child, files)

func create_node(data: Dictionary, node_name: String, ctx: NodeCtx) -> GraphNode:
	var node := GraphNode.new()
	node.name = node_name
	node.title = "Trigger"
	var mode: String = data.get("mode", "conditional")

	# type selection inside the node — transforms the body on change
	var type_opt := OptionButton.new()
	for mode_name: String in ["Playlist", "Random", "Conditional"]:
		type_opt.add_item(mode_name)
	type_opt.select(maxi(["playlist", "random", "conditional"].find(mode), 0))
	type_opt.item_selected.connect(func(idx: int) -> void:
		data["mode"] = ["playlist", "random", "conditional"][idx]
		ctx.rebuild_deferred())
	node.add_child(type_opt)

	if mode in ["playlist", "random"]:
		# Playlist body: sync toggle + pins. Random body: shuffle picker + pins.
		if mode == "playlist":
			var sync_check := CheckBox.new()
			sync_check.text = "Sync (play all pins together)"
			sync_check.button_pressed = data.get("sync", false)
			sync_check.toggled.connect(func(on: bool) -> void: data["sync"] = on)
			node.add_child(sync_check)
		else:
			var mode_opt := OptionButton.new()
			mode_opt.add_item("Random")
			mode_opt.add_item("Shuffle (no repeat until all played)")
			mode_opt.select(1 if data.get("random_mode", "random") == "shuffle" else 0)
			mode_opt.item_selected.connect(func(idx: int) -> void: data["random_mode"] = "random" if idx == 0 else "shuffle")
			node.add_child(mode_opt)
		var add_pin := Button.new()
		add_pin.text = "+ add pin"
		add_pin.pressed.connect(func() -> void:
			ctx.push_undo()
			data["pins"] = data.get("pins", 1) + 1
			ctx.rebuild_deferred())
		node.add_child(add_pin)
		for j in data.get("pins", 1):
			var pin := Label.new()
			pin.text = "Out %d" % (j + 1)
			node.add_child(pin)
			node.set_slot(node.get_child_count() - 1, false, 0, Color.WHITE, true, 0, Color.WHITE)
	else:
		# Conditional body: one condition row per branch + add branch
		var bcs: Array = data.get_or_add("branch_conditions", [])
		for i in bcs.size():
			var bc: Dictionary = bcs[i]
			var row := HBoxContainer.new()
			var def_check := CheckBox.new()
			def_check.text = "default"
			def_check.button_pressed = bc.get("default", false)
			def_check.toggled.connect(func(on: bool) -> void: bc["default"] = on)
			row.add_child(def_check)
			var conds: Array = bc.get_or_add("conditions", [])
			if conds.is_empty():
				conds.append({"param": "", "type": "enum", "enum_values": [], "min": "", "max": "", "default": false, "op": "==", "value": ""})
			var cond: Dictionary = conds[0]
			var op_opt := OptionButton.new()
			for op: String in ["==", "!=", "<", "<=", ">", ">="]:
				op_opt.add_item(op)
			op_opt.select(maxi(["==", "!=", "<", "<=", ">", ">="].find(cond.get("op", "==")), 0))
			op_opt.item_selected.connect(func(idx: int) -> void:
				cond["op"] = ["==", "!=", "<", "<=", ">", ">="][idx]
				ctx.sync_declaration(cond))
			row.add_child(op_opt)
			var param_edit := LineEdit.new()
			param_edit.text = cond.get("param", "")
			param_edit.placeholder_text = "variable"
			param_edit.text_changed.connect(func(t: String) -> void:
				cond["param"] = t
				ctx.sync_declaration(cond))
			param_edit.custom_minimum_size = Vector2(90, 0)
			row.add_child(param_edit)
			var val_edit := LineEdit.new()
			val_edit.text = str(cond.get("value", ""))
			val_edit.placeholder_text = "value"
			val_edit.text_changed.connect(func(t: String) -> void:
				cond["value"] = t
				ctx.sync_declaration(cond))
			val_edit.custom_minimum_size = Vector2(60, 0)
			row.add_child(val_edit)
			node.add_child(row)
			node.set_slot(node.get_child_count() - 1, false, 0, Color.WHITE, true, 0, ACCENT3)
		var add_branch := Button.new()
		add_branch.text = "+ add branch"
		add_branch.pressed.connect(func() -> void:
			ctx.push_undo()
			data.get_or_add("branch_conditions", []).append({"conditions": []})
			ctx.rebuild_deferred())
		node.add_child(add_branch)
	return node
