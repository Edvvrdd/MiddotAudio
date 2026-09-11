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
	play_btn.pressed.connect(func() -> void: ctx.audition_file(data.get("audio_file", "")))
	sound.get_titlebar_hbox().add_child(play_btn)
	var file_edit: LineEdit = load("res://AssetDropEdit.gd").new()
	file_edit.text = data.get("audio_file", "")
	file_edit.text_changed.connect(func(t: String) -> void: data["audio_file"] = t)
	file_edit.custom_minimum_size = Vector2(160, 0)
	sound.add_child(file_edit)
	sound.set_slot(0, true, 0, Color.WHITE, false, 0, Color.WHITE)
	return sound
