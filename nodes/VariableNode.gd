extends NodeType

## Variable declaration node. Data: the condition dict it edits
## {param, type, enum_values, min, max, default}. Registered so the graph can
## render variables anywhere; the Variables tab hosts them.

func type_name() -> String:
	return "variable"

func connect_rules() -> Dictionary:
	return {"in": [], "out": []}

func create_node(data: Dictionary, node_name: String, _ctx: NodeCtx) -> GraphNode:
	var var_node := GraphNode.new()
	var_node.name = node_name
	var_node.title = "Variable: %s" % data.get("param", "?")
	var param_edit := LineEdit.new()
	param_edit.text = data.get("param", "")
	param_edit.placeholder_text = "variable name"
	var sync_from: String = data.get("param", "")
	param_edit.text_changed.connect(func(t: String) -> void:
		data["param"] = t
		var_node.title = "Variable: %s" % t
		_ctx.sync_declaration(data, sync_from)
		sync_from = t)
	param_edit.custom_minimum_size = Vector2(150, 0)
	var_node.add_child(param_edit)
	var type_opt := OptionButton.new()
	for type_name: String in ["enum", "int", "float", "bool"]:
		type_opt.add_item(type_name)
	var vtype: String = data.get("type", "enum")
	type_opt.select(maxi(["enum", "int", "float", "bool"].find(vtype), 0))
	var_node.add_child(type_opt)

	# enum panel: one editable slot per value, + to add, right-click to delete
	var enum_panel := VBoxContainer.new()
	for j in data.get("enum_values", []).size():
		enum_panel.add_child(_make_enum_slot(data, j, _ctx))
	var add_btn := Button.new()
	add_btn.text = "+ add value"
	add_btn.pressed.connect(func() -> void:
		_ctx.push_undo()
		data.get_or_add("enum_values", []).append("")
		_ctx.sync_declaration(data)
		_ctx.rebuild_deferred())
	enum_panel.add_child(add_btn)

	# int/float panel: min + max
	var range_panel := HBoxContainer.new()
	for spec: Array in [["min", "min"], ["max", "max"]]:
		var lbl := Label.new()
		lbl.text = spec[1]
		range_panel.add_child(lbl)
		var num_edit := LineEdit.new()
		num_edit.text = str(data.get(spec[0], ""))
		num_edit.placeholder_text = spec[1]
		num_edit.text_changed.connect(func(t: String) -> void:
			data[spec[0]] = t
			_ctx.sync_declaration(data))
		num_edit.custom_minimum_size = Vector2(60, 0)
		range_panel.add_child(num_edit)

	# bool panel: default value picker
	var bool_panel := HBoxContainer.new()
	var blbl := Label.new()
	blbl.text = "default"
	bool_panel.add_child(blbl)
	var bool_opt := OptionButton.new()
	bool_opt.add_item("false")
	bool_opt.add_item("true")
	bool_opt.select(1 if data.get("default", false) else 0)
	bool_opt.item_selected.connect(func(idx: int) -> void:
		data["default"] = idx == 1
		_ctx.sync_declaration(data))
	bool_panel.add_child(bool_opt)

	for panel: Control in [enum_panel, range_panel, bool_panel]:
		var_node.add_child(panel)
		panel.visible = false
	var panels: Array = [enum_panel, range_panel, bool_panel]
	# 4 types, 3 panels: int and float share the range panel
	var panel_of_type: Array = [0, 1, 1, 2]
	panels[panel_of_type[type_opt.selected]].visible = true
	type_opt.item_selected.connect(func(idx: int) -> void:
		data["type"] = ["enum", "int", "float", "bool"][idx]
		for p: int in panels.size():
			panels[p].visible = p == panel_of_type[idx]
		_ctx.sync_declaration(data))
	return var_node

## One editable enum value slot; right-click deletes it from the list.
func _make_enum_slot(data: Dictionary, j: int, ctx: NodeCtx) -> Control:
	var row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.text = data["enum_values"][j]
	edit.context_menu_enabled = false  # right-click deletes instead
	edit.text_changed.connect(func(t: String) -> void:
		data["enum_values"][j] = t
		ctx.sync_declaration(data))
	edit.custom_minimum_size = Vector2(150, 0)
	edit.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			ctx.push_undo()
			data["enum_values"].remove_at(j)
			ctx.sync_declaration(data)
			ctx.rebuild_deferred())
	row.add_child(edit)
	return row
