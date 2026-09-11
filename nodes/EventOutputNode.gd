extends NodeType

## Event Output node: the compile target. Carries the event-level properties
## (bus, volume, pitch, looping). Compile starts from the wire into this node.

func type_name() -> String:
	return "event_output"

func display_name() -> String:
	return "Event Output"

func is_container() -> bool:
	return false

func connect_rules() -> Dictionary:
	return {"in": ["random_trigger", "playlist_trigger", "conditional_trigger", "sound"], "out": []}

func collect_files(data: Dictionary, files: Array) -> void:
	pass  # output carries no audio references

func create_node(data: Dictionary, node_name: String, ctx: NodeCtx) -> GraphNode:
	var node := GraphNode.new()
	node.name = node_name
	node.title = "Event Output"
	var bus_opt := OptionButton.new()
	var bus_names: Array = ["Master"]
	for b: String in ctx.main.backend.buses:
		if not bus_names.has(b):
			bus_names.append(b)
	for i in bus_names.size():
		bus_opt.add_item(bus_names[i])
		if bus_names[i] == data.get("bus", "Master"):
			bus_opt.select(i)
	bus_opt.item_selected.connect(func(idx: int) -> void: data["bus"] = bus_names[idx])
	node.add_child(bus_opt)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 100.0
	vol.value = data.get("volume", 100.0)
	vol.custom_minimum_size = Vector2(150, 0)
	vol.value_changed.connect(func(v: float) -> void: data["volume"] = v)
	node.add_child(vol)
	var loop_check := CheckBox.new()
	loop_check.text = "Loop"
	loop_check.button_pressed = data.get("looping", false)
	loop_check.toggled.connect(func(on: bool) -> void: data["looping"] = on)
	node.add_child(loop_check)
	node.set_slot(0, true, 0, Color.WHITE, false, 0, Color.WHITE)
	return node
