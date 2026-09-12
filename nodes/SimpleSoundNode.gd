extends NodeType

## A single sound file leaf. Data: {audio_file: String}

func type_name() -> String:
	return "sound"

func display_name() -> String:
	return "Sound"

func can_be_root() -> bool:
	return true

func is_container() -> bool:
	return false

func menu_actions(_ctx: NodeCtx) -> Array:
	return []

func connect_rules() -> Dictionary:
	return {"in": ["random_trigger", "playlist_trigger", "conditional_trigger"], "out": ["event_output"]}

func collect_files(data: Dictionary, files: Array) -> void:
	if not data.get("audio_file", "").is_empty():
		files.append(data["audio_file"])

func create_node(data: Dictionary, node_name: String, ctx: NodeCtx) -> GraphNode:
	var sound: GraphNode = load("res://AssetDropNode.gd").new()
	sound.name = node_name
	sound.title = "Sound"
	var play_btn := Button.new()
	play_btn.text = "▶"
	play_btn.tooltip_text = "Preview this file"
	play_btn.pressed.connect(func() -> void: ctx.audition_file(data))
	sound.get_titlebar_hbox().add_child(play_btn)
	var file_edit: LineEdit = load("res://AssetDropEdit.gd").new()
	file_edit.text = data.get("audio_file", "")
	file_edit.text_changed.connect(func(t: String) -> void: data["audio_file"] = t)
	file_edit.custom_minimum_size = Vector2(160, 0)
	sound.add_child(file_edit)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 100.0
	vol.value = data.get("volume", 100.0)
	vol.custom_minimum_size = Vector2(120, 0)
	var vol_val := Label.new()
	vol_val.text = "%d" % int(vol.value)
	vol.value_changed.connect(func(v: float) -> void:
		data["volume"] = v
		vol_val.text = "%d" % int(v))
	sound.add_child(_slider_row("Vol", vol, vol_val))
	var pitch := HSlider.new()
	pitch.min_value = 0.1
	pitch.max_value = 4.0
	pitch.step = 0.05
	pitch.value = data.get("pitch", 1.0)
	pitch.custom_minimum_size = Vector2(120, 0)
	var pitch_val := Label.new()
	pitch_val.text = "%.2f×" % pitch.value
	pitch.value_changed.connect(func(v: float) -> void:
		data["pitch"] = v
		pitch_val.text = "%.2f×" % v)
	sound.add_child(_slider_row("Pitch", pitch, pitch_val))
	# wires attach to row 0 (the file row); slider rows carry no slots
	sound.set_slot(0, true, 0, Color.WHITE, true, 0, Color.WHITE)
	return sound

## Label + slider + live value label in one row.
static func _slider_row(label_text: String, slider: HSlider, value_label: Label) -> HBoxContainer:
	var name_label := Label.new()
	name_label.text = label_text
	var row := HBoxContainer.new()
	row.add_child(name_label)
	row.add_child(slider)
	row.add_child(value_label)
	return row
