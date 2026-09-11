extends Control

var _new_event_counter := 0
var _selected := ""
var _rename_target := "asset"
var _pending_drop_pos := Vector2.INF
var _project_path := ""

## Undo/redo: snapshots of the full authoring state (events, buses, volumes).
## ponytail: whole-state snapshots, not deltas — the state is small (tens of
## events), and delta-undo across 20 mutating functions was the complex version.
const UNDO_LIMIT := 50
## Backend notifications: refresh whatever the backend says changed.
func _on_backend_changed(what: String) -> void:
	match what:
		"canvas":
			if not _mixer_view and not _variables_view:
				_build_graph()
		"events":
			_refresh_events_list()
		"variables":
			if _variables_view:
				_refresh_variables_list()
				_build_variable_graph()
		"buses":
			if _mixer_view:
				_build_bus_graph()
		"all", "project":
			if _auditioner:
				_auditioner.stop()
			_refresh_events_list()
			_refresh_assets_list()
			if _variables_view:
				_refresh_variables_list()
				_build_variable_graph()
			elif _mixer_view:
				_build_bus_graph()
			else:
				_build_graph()

## Call BEFORE any mutation that should be undoable.
func _push_undo() -> void:
	backend.push_undo()

func undo() -> void:
	backend.undo()

func redo() -> void:
	backend.redo()

@onready var file_dialog: FileDialog = $FileDialog
@onready var project_dialog: FileDialog = $ProjectDialog
@onready var events_list: ItemList = %EventsList
@onready var export_button: Button = %ExportButton
@onready var event_graph: GraphEdit = %EventGraph

var _node_ctx: NodeCtx
var _auditioner: Auditioner

var backend: AudioBackend

func _ready() -> void:
	backend = AudioBackend.new()
	backend.changed.connect(_on_backend_changed)
	backend.enable_undo()
	_node_ctx = NodeCtx.new()
	_node_ctx.main = self
	%AddEventButton.pressed.connect(_on_add_event_button_pressed)
	export_button.pressed.connect(_on_export_button_pressed)
	file_dialog.file_selected.connect(_on_file_dialog_file_selected)
	events_list.item_selected.connect(_on_events_list_item_selected)
	event_graph.connection_request.connect(_on_graph_connection_request)
	event_graph.disconnection_request.connect(_on_graph_disconnection_request)
	event_graph.asset_dropped.connect(_on_graph_asset_dropped)
	event_graph.node_selected.connect(_on_node_selected)
	event_graph.node_deselected.connect(_on_node_deselected)
	event_graph.end_node_move.connect(_save_positions)
	%EventsTabButton.pressed.connect(_on_left_tab_pressed.bind("events"))
	%AssetsTabButton.pressed.connect(_on_left_tab_pressed.bind("assets"))
	%PlaceholderTabButton.pressed.connect(_on_left_tab_pressed.bind("mixer"))
	%PlaceholderTabButton.text = "Mixer"
	%VariablesTabButton.pressed.connect(_on_left_tab_pressed.bind("variables"))
	%VariablesList.item_selected.connect(_on_variables_list_item_selected)
	%VariablesList.item_activated.connect(_on_variables_list_item_activated)
	%AddVariableButton.pressed.connect(_on_new_variable_button_pressed)
	%PlaceholderTabButton.text = "Mixer"
	project_dialog.file_selected.connect(_on_project_dialog_file_selected)
	%MenuBar.project_dialog_requested.connect(_open_project_dialog)
	_run_boot_sequence()
	%AssetsList.item_activated.connect(_on_assets_list_item_activated)
	%RenamePopup.confirmed.connect(_on_rename_popup_confirmed)
	%RenameField.text_submitted.connect(func(_t: String) -> void:
		%RenamePopup.hide()
		_on_rename_popup_confirmed()
	)
	events_list.item_activated.connect(_on_events_list_item_activated)
	%MixerList.item_selected.connect(_on_mixer_list_item_selected)
	event_graph.connection_request.connect(_on_bus_connection_request)
	event_graph.disconnection_request.connect(_on_bus_disconnection_request)
	_apply_theme_overrides()
	_auditioner = Auditioner.new()
	add_child(_auditioner)
	%AuditionButton.pressed.connect(_on_audition_pressed)
	%AuditionStopButton.pressed.connect(func() -> void: _auditioner.stop())
	var bus_menu := PopupMenu.new()
	bus_menu.name = "BusContextMenu"
	bus_menu.add_item("Add Bus", 0)
	bus_menu.id_pressed.connect(func(_id: int) -> void: _add_bus_at_cursor())
	event_graph.add_child(bus_menu)
	event_graph.gui_input.connect(_on_graph_gui_input.bind(bus_menu))
	var event_menu := PopupMenu.new()
	event_menu.name = "EventContextMenu"
	event_menu.id_pressed.connect(_on_event_menu_id_pressed.bind(event_menu))
	event_graph.add_child(event_menu)
	event_graph.gui_input.connect(_on_event_graph_gui_input.bind(event_menu))

## Right-click on the mixer graph: context menu with Add Bus.
func _on_graph_gui_input(event: InputEvent, menu: PopupMenu) -> void:
	if _mixer_view and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		menu.position = get_viewport().get_mouse_position()
		menu.popup()

func _on_event_graph_gui_input(event: InputEvent, menu: PopupMenu) -> void:
	if not _mixer_view and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_rebuild_event_menu(menu)
		menu.position = get_viewport().get_mouse_position()
		menu.set_meta("spawn_pos", (event_graph.get_local_mouse_position() - Vector2(150, 20)).snapped(Vector2(10, 10)))
		menu.popup()

## Context menu: node types contribute their own actions (registry), plus
## "New Variable" and existing-variable reuse entries.
## Node actions are ungated — no "set trigger mode first" ceremony.
## Context menu (fixed, curated): Trigger, Sound, Variable, Looper, Output.
func _rebuild_event_menu(menu: PopupMenu) -> void:
	menu.clear()
	var items: Array = [
		["Add Trigger", "conditional_trigger"],
		["Add Sound", "sound"],
		["Add Variable", "variable"],
		["Add Looper", "looper_placeholder"],
		["Add Output", "event_output"],
	]
	for i in items.size():
		menu.add_item(items[i][0], 1000 + i)
		menu.set_item_metadata(menu.get_item_count() - 1, {"place_type": items[i][1]})

func _on_event_menu_id_pressed(id: int, menu: PopupMenu) -> void:
	var meta = menu.get_item_metadata(_menu_index_for_id(menu, id))
	if meta is Dictionary and meta.has("place_type"):
		if meta["place_type"] == "looper_placeholder":
			return  # Looper: placeholder, does nothing for now
		_place_node(meta["place_type"])

## ponytail: PopupMenu gives no id->index lookup; ids are contiguous from 0.
func _menu_index_for_id(menu: PopupMenu, id: int) -> int:
	for i in menu.get_item_count():
		if menu.get_item_id(i) == id:
			return i
	return 0
## Node selection (Del key deletes selected canvas nodes).
func _on_node_selected(node: Node) -> void:
	if not _selected_node_names.has(String(node.name)):
		_selected_node_names.append(String(node.name))

func _on_node_deselected(node: Node) -> void:
	_selected_node_names.erase(String(node.name))

func _on_graph_connection_request(from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	backend.connect_nodes(_selected, _id_from_name(String(from)), from_port, _id_from_name(String(to)), to_port)

func _on_graph_disconnection_request(from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	backend.disconnect_nodes(_selected, _id_from_name(String(from)), from_port, _id_from_name(String(to)), to_port)

## Dropping an asset on empty canvas places a Sound node with that file.
func _on_graph_asset_dropped(file: String, at: Vector2) -> void:
	if _selected.is_empty():
		return
	backend.place_node(_selected, "sound", at + event_graph.scroll_offset)
	var c: Dictionary = backend.get_canvas(_selected)
	# newest node gets the dropped file
	var newest: int = c["nodes"][-1]["id"]
	backend.set_node_file(_selected, newest, file)

## Propagate a variable's declaration (delegates to backend).
func _sync_declaration(cond: Dictionary, old_param: String = "") -> void:
	backend.sync_declaration(cond, old_param)

## Variables tab: Del removes the variable from the registry AND every canvas
## condition using it.
func _delete_selected_variable() -> void:
	if _selected_variable.is_empty():
		return
	backend.delete_variable(_selected_variable)
	_selected_variable = ""

func _refresh_mixer_list() -> void:
	%MixerList.clear()
	%MixerList.add_item(_project_path.get_file() if not _project_path.is_empty() else "Project Soundbank")

## Theme overrides layered on the space-worm theme: darker background,
## cyan/magenta/amber accents, rounded corners. ponytail: imperatively
## applied because the space-worm .tres is image-based; swap to a full
## .tres reskin if this grows beyond ~100 lines.
const ACCENT := Color("00e5ff")
const ACCENT2 := Color("ff3fa4")
const ACCENT3 := Color("ffb020")
const BG_PANEL := Color("161924")
const BG_CONTROL := Color("20242f")
const FG_TEXT := Color("e8ecf1")

func _flat_style(bg: Color, border: Color, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = border
	return sb

func _apply_theme_overrides() -> void:
	var root_bg := StyleBoxFlat.new()
	root_bg.bg_color = Color("0d0f16")
	root_bg.set_corner_radius_all(0)

	var panel_sb := _flat_style(BG_PANEL, Color("2a2f42"), 10)
	panel_sb.set_content_margin_all(6)

	var btn := _flat_style(BG_CONTROL, Color("3a4159"))
	btn.content_margin_left = 12.0
	btn.content_margin_right = 12.0
	btn.content_margin_top = 6.0
	btn.content_margin_bottom = 6.0

	var btn_hover := _flat_style(Color("2c3247"), ACCENT)
	btn_hover.content_margin_left = 12.0
	btn_hover.content_margin_right = 12.0
	btn_hover.content_margin_top = 6.0
	btn_hover.content_margin_bottom = 6.0

	var btn_pressed := _flat_style(ACCENT.darkened(0.6), ACCENT)
	btn_pressed.content_margin_left = 12.0
	btn_pressed.content_margin_right = 12.0
	btn_pressed.content_margin_top = 6.0
	btn_pressed.content_margin_bottom = 6.0

	for b: Button in find_children("*", "Button", true, false):
		b.add_theme_stylebox_override("normal", btn)
		b.add_theme_stylebox_override("hover", btn_hover)
		b.add_theme_stylebox_override("pressed", btn_pressed)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", FG_TEXT)
		b.add_theme_color_override("font_hover_color", ACCENT)
		b.add_theme_color_override("font_pressed_color", Color("0d0f16"))
	for l: Label in find_children("*", "Label", true, false):
		l.add_theme_color_override("font_color", FG_TEXT)
	for il: ItemList in find_children("*", "ItemList", true, false):
		var list_sb := _flat_style(BG_PANEL, Color("2a2f42"), 10)
		il.add_theme_stylebox_override("panel", list_sb)
		il.add_theme_color_override("font_color", FG_TEXT)
		il.add_theme_color_override("font_hover_color", ACCENT)
		il.add_theme_color_override("font_selected_color", ACCENT2)
		var cursb := StyleBoxFlat.new()
		cursb.bg_color = Color("2c3247")
		cursb.set_corner_radius_all(6)
		il.add_theme_stylebox_override("selected_focus", cursb)
		il.add_theme_stylebox_override("selected", cursb)
	for ge: GraphEdit in find_children("*", "GraphEdit", true, false):
		var grid_sb := _flat_style(Color("0d0f16"), Color("2a2f42"), 10)
		ge.add_theme_stylebox_override("panel", grid_sb)
	for le: LineEdit in find_children("*", "LineEdit", true, false):
		le.add_theme_color_override("font_color", FG_TEXT)
		le.add_theme_color_override("caret_color", ACCENT)
		var lesb := _flat_style(BG_CONTROL, Color("3a4159"), 6)
		le.add_theme_stylebox_override("normal", lesb)
		le.add_theme_color_override("font_color", FG_TEXT)
	for ob: OptionButton in find_children("*", "OptionButton", true, false):
		ob.add_theme_stylebox_override("normal", btn)
		ob.add_theme_stylebox_override("hover", btn_hover)
		ob.add_theme_color_override("font_color", FG_TEXT)
	var grab_sb := _flat_style(ACCENT3, ACCENT3, 6)
	for sl: HSlider in find_children("*", "HSlider", true, false):
		sl.add_theme_stylebox_override("slider", _flat_style(Color("2a2f42"), Color("3a4159"), 4))
		sl.add_theme_stylebox_override("grabber_area", grab_sb)
		sl.add_theme_stylebox_override("grabber_area_highlight", grab_sb)

## Boot sequence: the app refuses to edit until a project exists.
## The dialog is in SAVE_FILE mode: type a NEW filename to create a project,
## or select an existing .middot to open it.
func _run_boot_sequence() -> void:
	project_dialog.title = "New project (type a name) or open existing (.middot)"
	_open_project_dialog()

func _open_project_dialog() -> void:
	project_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	project_dialog.filters = ["*.middot"]
	project_dialog.current_file = _project_path.get_file() if not _project_path.is_empty() else "new_project.middot"
	project_dialog.popup_centered()

## File > Save As: re-opens the project dialog; picking a path re-points the
## project and saves immediately.
func _on_save_as_pressed() -> void:
	_open_project_dialog()

func _on_project_dialog_file_selected(path: String) -> void:
	if not path.ends_with(".middot"):
		path += ".middot"
	_project_path = path
	if FileAccess.file_exists(path):
		_load_project(path)
	_refresh_events_list()
	_refresh_assets_list()
	_refresh_mixer_list()
	backend.enable_undo()
	save_project()  # new projects are written immediately; existing get re-persisted

## Project save/load: JSON under a .middot extension (ResourceSaver only
## accepts known extensions like .tres, so raw JSON is the lazy path).
## FMOD-style project file, self-contained next to its audio.
func save_project() -> void:
	if _project_path.is_empty():
		return
	var data: Dictionary = backend.to_dict()
	var f := FileAccess.open(_project_path, FileAccess.WRITE)
	if f == null:
		push_error("Project save failed: cannot open ", _project_path)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("Project saved: ", _project_path)

func _load_project(path: String) -> void:
	var parsed = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("format_version") != 2:
		push_error("Invalid or unsupported project file: ", path)
		return
	backend.from_dict(parsed)




## The project's Audio folder lives beside the .middot file.
func _audio_dir() -> String:
	return _project_path.get_base_dir().path_join("Audio")

## Clicking the bank: the right pane becomes the bus-routing graph.
func _on_mixer_list_item_selected(_index: int) -> void:
	_mixer_view = true
	_build_bus_graph()

## Toggle the left panel contents: mutually exclusive tab-style buttons.
func _on_left_tab_pressed(tab: String) -> void:
	%EventsTabButton.button_pressed = tab == "events"
	%AssetsTabButton.button_pressed = tab == "assets"
	%PlaceholderTabButton.button_pressed = tab == "mixer"
	%VariablesTabButton.button_pressed = tab == "variables"
	%EventsPanel.visible = tab == "events"
	%AssetsPanel.visible = tab == "assets"
	%MixerPanel.visible = tab == "mixer"
	%VariablesPanel.visible = tab == "variables"
	_mixer_view = tab == "mixer"
	_variables_view = tab == "variables"
	if _mixer_view:
		_build_bus_graph()
	elif _variables_view:
		_refresh_variables_list()
		_build_variable_graph()
	else:
		# no event selected yet: show placeholder, not an empty canvas
		if not _selected.is_empty():
			_build_graph()
		else:
			for c in event_graph.get_children():
				if c is GraphElement:
					event_graph.remove_child(c)
					c.free()








## Rebuild whichever graph the user is looking at (deferred-safe: call this
## from signal handlers that fire from nodes being freed).
func _rebuild_current_view() -> void:
	if _mixer_view:
		_build_bus_graph()
	elif _variables_view:
		_refresh_variables_list()
		_build_variable_graph()
	else:
		_build_graph()

## Variables tab: the graph shows ONLY the selected variable's node.
## Route file collection through the node-type registry by shape.
func _collect_files_typed(node: Dictionary, files: Array) -> void:
	var type_name: String = "sound"
	if node.has("branches"):
		type_name = "conditional_trigger"
	elif node.get("trigger") == "playlist":
		type_name = "playlist_trigger"
	elif node.get("trigger") == "random":
		type_name = "random_trigger"
	var t: NodeType = NodeTypes.by_name(type_name)
	if t:
		t.collect_files(node, files)

func _build_variable_graph() -> void:
	for c in event_graph.get_children():
		if c is GraphElement:
			event_graph.remove_child(c)
			c.free()
	if _selected_variable.is_empty() or backend.variables.is_empty():
		return
	var cond := _find_variable(_selected_variable)
	if cond.is_empty():
		return
	var var_node: GraphNode = NodeTypes.by_name("variable").create_node(cond, "Variable0", _node_ctx)
	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.tooltip_text = "Delete variable"
	x_btn.pressed.connect(_on_node_close.bind(var_node))
	var_node.get_titlebar_hbox().add_child(x_btn)
	var_node.position_offset = Vector2(20, 20)
	event_graph.add_child(var_node)

## First condition matching a param name, anywhere in the project; falls back
## to the registry declaration when the variable has no usages.
func _find_variable(param: String) -> Dictionary:
	var decl: Dictionary = backend.variables.get(param, {})
	if not decl.is_empty():
		return {"param": param, "type": decl.get("type", "enum"), "enum_values": decl.get("enum_values", []), "min": decl.get("min", ""), "max": decl.get("max", ""), "default": decl.get("default", false), "op": "==", "value": ""}
	return {}

## The Variables tab list: one entry per registered variable + its type.
func _refresh_variables_list() -> void:
	%VariablesList.clear()
	for param: String in backend.variables:
		%VariablesList.add_item("%s  (%s)" % [param, backend.variables[param].get("type", "enum")])
		if param == _selected_variable:
			%VariablesList.select(%VariablesList.item_count - 1)

func _on_variables_list_item_selected(index: int) -> void:
	_selected_variable = %VariablesList.get_item_text(index).split("  ")[0]
	_build_variable_graph()

func _on_variables_list_item_activated(_index: int) -> void:
	# F2/double-click: reuse the events-tab rename popup for the variable
	_open_rename_popup("variable")

func _on_new_variable_button_pressed() -> void:
	if _project_path.is_empty():
		return
	_selected_variable = backend.add_variable_node(_selected, Vector2(20, 20))

## Bus routing state lives in the backend (buses, bus_volumes); variables and
## canvases likewise — Main only renders and broadcasts.
var _mixer_view := false
var _variables_view := false
var _selected_variable := ""  # param name of the variable shown in Variables tab

## Rescan the Audio folder whenever the window regains focus — covers files
## added/removed in Explorer while the app runs.
func _notification(what: int) -> void:
	if not is_inside_tree():
		return
	if not _project_path.is_empty():
		match what:
			NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
				_refresh_assets_list()

## Scan the project's Audio folder (beside the .middot file) for audio files
## and mirror it into the assets list. Single source of truth = the folder.
func _refresh_assets_list() -> void:
	%AssetsList.clear()
	if _project_path.is_empty():
		return
	var audio_dir: String = _project_path.get_base_dir().path_join("Audio")
	DirAccess.make_dir_recursive_absolute(audio_dir)
	var dir := DirAccess.open(audio_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while not f.is_empty():
		if not dir.current_is_dir() and f.get_extension() in ["wav", "ogg", "mp3"]:
			%AssetsList.add_item(f)
		f = dir.get_next()
	dir.list_dir_end()

## F2 or double-click on a list: open rename popup pre-filled with current name.
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_DELETE and not _mixer_view:
		if _variables_view:
			_delete_selected_variable()
		else:
			_delete_selected_nodes()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_S and event.ctrl_pressed:
		save_project()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_Z and event.ctrl_pressed:
		if event.shift_pressed:
			redo()
		else:
			undo()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F5:
		_on_audition_pressed()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		if %AssetsPanel.visible and not %AssetsList.get_selected_items().is_empty():
			_open_rename_popup("asset")
		elif %EventsPanel.visible and not events_list.get_selected_items().is_empty():
			_open_rename_popup("event")

## Audition (F5): play the selected event's compiled tree in-app.
func _on_audition_pressed() -> void:
	if _mixer_view or _variables_view:
		return
	if _selected.is_empty():
		push_warning("Audition: select an event first")
		return
	var tree: Dictionary = backend.compile_event(_selected)
	if tree.is_empty():
		push_warning("Audition: event '%s' does not compile (see errors)" % _selected)
		return
	_auditioner.play(tree, _audio_dir(), backend.buses, backend.bus_volumes, backend.variables)

func _on_assets_list_item_activated(_index: int) -> void:
	_open_rename_popup("asset")

## Preview one file (Sound node ▶ button) with the event's bus/volume and
## the node's own volume/pitch.
func _audition_file(node_data: Dictionary) -> void:
	var file: String = node_data.get("audio_file", "")
	if file.is_empty() or _selected.is_empty():
		return
	var bus := "Master"
	var vol := 100.0
	for n in backend.get_canvas(_selected)["nodes"]:
		if n["type"] == "event_output":
			bus = n["data"].get("bus", "Master")
			vol = n["data"].get("volume", 100.0)
			break
	var tree := {"trigger": "simple", "audio_file": file, "bus": bus,
		"volume_db": linear_to_db(clampf(vol / 100.0, 0.0001, 1.0)), "looping": false}
	var node_vol: float = node_data.get("volume", 100.0)
	if not is_equal_approx(node_vol, 100.0):
		tree["file_volume_db"] = linear_to_db(clampf(node_vol / 100.0, 0.0001, 1.0))
	var node_pitch: float = node_data.get("pitch", 1.0)
	if not is_equal_approx(node_pitch, 1.0):
		tree["pitch_scale"] = node_pitch
	_auditioner.play(tree, _audio_dir(), backend.buses, backend.bus_volumes, backend.variables)

func _on_events_list_item_activated(_index: int) -> void:
	_open_rename_popup("event")

## One shared rename popup; _rename_target picks which list/state it acts on.
func _open_rename_popup(target: String) -> void:
	_rename_target = target
	var list: ItemList = %AssetsList if target == "asset" else events_list
	if target == "variable":
		list = %VariablesList
	var old_name: String = list.get_item_text(list.get_selected_items()[0])
	if target == "variable":
		old_name = old_name.split("  ")[0]
	%RenamePopup.title = "Rename %s" % old_name
	%RenameField.text = old_name
	%RenameField.select_all()
	%RenamePopup.popup_centered()
	%RenameField.grab_focus()

func _on_rename_popup_confirmed() -> void:
	var list: ItemList = %AssetsList if _rename_target == "asset" else events_list
	if _rename_target == "variable":
		list = %VariablesList
	var sel: Array = list.get_selected_items()
	if sel.is_empty():
		return
	var idx: int = sel[0]
	var old_name: String = list.get_item_text(idx)
	if _rename_target == "variable":
		old_name = old_name.split("  ")[0]
	var new_name: String = %RenameField.text.strip_edges()
	if new_name.is_empty() or new_name == old_name:
		return
	if _rename_target == "variable":
		backend.push_undo()
		# rename every condition with this param, everywhere
		var cond := _find_variable(old_name)
		if not cond.is_empty():
			cond["param"] = new_name
			_sync_declaration(cond, old_name)
			_selected_variable = new_name
			_refresh_variables_list()
			_build_variable_graph()
		return
	if _rename_target == "event":
		backend.push_undo()
	if _rename_target == "asset":
		if new_name.get_extension().is_empty():
			new_name += "." + old_name.get_extension()
		if new_name.get_extension() != old_name.get_extension():
			push_warning("Keep the same extension: ", old_name.get_extension())
			return
		var rename_err := DirAccess.rename_absolute(_audio_dir().path_join(old_name), _audio_dir().path_join(new_name))
		if rename_err != OK:
			push_error("Rename failed: error code %d" % rename_err)
			return
		# Keep every event pointing at the renamed file.
		for e_props: Dictionary in backend.events.values():
			if e_props.get("audio_file", "") == old_name:
				e_props["audio_file"] = new_name
		_refresh_assets_list()
		if not _selected.is_empty():
			_build_graph()
	else:
		if not backend.rename_event(old_name, new_name):
			push_warning("Event '%s' already exists" % new_name)
			return
		if _selected == old_name:
			_selected = new_name
		_refresh_events_list()
	_refresh_assets_list()
	if not _selected.is_empty():
		_build_graph()

func _refresh_events_list() -> void:
	var selected: Array = events_list.get_selected_items()
	events_list.clear()
	for event_name: String in backend.events:
		events_list.add_item(event_name)
	for i: int in selected:
		if i < events_list.item_count:
			events_list.select(i)

func _on_add_event_button_pressed() -> void:
	_new_event_counter += 1
	var name := "new_event_%d" % _new_event_counter
	while backend.events.has(name):
		_new_event_counter += 1
		name = "new_event_%d" % _new_event_counter
	backend.create_event(name)
	_refresh_events_list()

func _on_events_list_item_selected(index: int) -> void:
	_auditioner.stop()
	_selected = events_list.get_item_text(index)
	_build_graph()

## ============ Free canvas ============
## The graph is a free canvas: nodes are placed freely, wired manually, and
## nothing is derived or auto-connected. Ctrl+S compiles node paths into the
## event tree (_events) which save_project persists and the parser consumes.
## See FREE_CANVAS_ARCHITECTURE.md.

var _node_names: Array = []
var _selected_node_names: Array = []


func _place_node(type_name: String) -> void:
	if _selected.is_empty():
		return
	var spawn: Vector2 = event_graph.get_meta("spawn_pos", Vector2(200, 100))
	if type_name == "variable":
		backend.add_variable_node(_selected, spawn)
	else:
		backend.place_node(_selected, type_name, spawn)



func _build_graph() -> void:
	if _mixer_view:
		_build_bus_graph()
		return
	_save_positions()
	for c in event_graph.get_children():
		if c is GraphElement:
			event_graph.remove_child(c)
			c.free()
	_node_names.clear()
	if _selected.is_empty():
		return
	backend.ensure_canvas(_selected)
	var canvas: Dictionary = backend.get_canvas(_selected)
	for n in canvas["nodes"]:
		var t: NodeType = NodeTypes.by_name(n["type"])
		if t == null:
			continue
		var gn: GraphNode = t.create_node(n["data"], "N%d" % n["id"], _node_ctx)
		gn.position_offset = n["pos"]
		var x_btn := Button.new()
		x_btn.text = "X"
		x_btn.tooltip_text = "Delete node"
		x_btn.pressed.connect(_on_node_close.bind(gn))
		gn.get_titlebar_hbox().add_child(x_btn)
		event_graph.add_child(gn)
		_node_names.append(String(gn.name))
	for w in canvas["wires"]:
		var from_ok: bool = _node_names.has("N%d" % w["from"])
		var to_ok: bool = _node_names.has("N%d" % w["to"])
		if from_ok and to_ok:
			event_graph.connect_node("N%d" % w["from"], w["from_port"], "N%d" % w["to"], w["to_port"])

func _on_node_close(node: Node) -> void:
	if _variables_view:
		backend.delete_variable(_selected_variable)
		_selected_variable = ""
		return
	backend.delete_nodes(_selected, [_id_from_name(String(node.name))])

func _delete_canvas_node(id: int) -> void:
	backend.delete_nodes(_selected, [id])

## Persist live node positions into the canvas (called on drag end and before
## rebuilds) so nodes never teleport when the graph re-renders.
func _save_positions() -> void:
	if not backend.canvas.has(_selected):
		return
	for c in event_graph.get_children():
		if c is GraphElement and String(c.name).begins_with("N"):
			var n: Dictionary = backend.node_by_id(_selected, _id_from_name(String(c.name)))
			if not n.is_empty():
				n["pos"] = c.position_offset

func _id_from_name(node_name: String) -> int:
	if not node_name.begins_with("N"):
		return -1
	return int(node_name.substr(1))

func _delete_selected_nodes() -> void:
	if _selected_node_names.is_empty() or _selected.is_empty():
		return
	var ids: Array = _selected_node_names.map(func(n): return _id_from_name(n))
	backend.delete_nodes(_selected, ids)
	_selected_node_names.clear()

## ============ Compile: canvas -> event tree (Ctrl+S / Export) ============


## One node per bus, one pin per child-parent edge. Master at the root.
func _build_bus_graph() -> void:
	for c in event_graph.get_children():
		if c is GraphElement:
			event_graph.remove_child(c)
			c.free()
	# Master is implicit (always exists) — add it if no child references a missing bus
	var all_buses := backend.buses.duplicate()
	if not all_buses.has("Master"):
		all_buses["Master"] = ""
	for parent: String in all_buses.values():
		if not parent.is_empty() and not all_buses.has(parent):
			all_buses[parent] = ""
	for bus_name: String in all_buses:
		var node := GraphNode.new()
		node.name = bus_name
		node.title = bus_name
		var vol := HSlider.new()
		vol.min_value = 0.0
		vol.max_value = 100.0
		vol.value = backend.bus_volumes.get(bus_name, 100.0)
		vol.custom_minimum_size = Vector2(160, 0)
		vol.value_changed.connect(_on_bus_volume_changed.bind(bus_name))
		node.add_child(vol)
		# rename: double-click title → inline rename field (not for Master)
		if bus_name != "Master":
			var title_lbl := Label.new()
			title_lbl.text = "double-click title to rename"
			title_lbl.add_theme_font_size_override("font_size", 9)
			var rename_edit := LineEdit.new()
			rename_edit.text = bus_name
			rename_edit.visible = false
			rename_edit.text_submitted.connect(func(t: String) -> void:
				_rename_bus(bus_name, t)
			)
			node.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.pressed and ev.double_click and bus_name != "Master":
					rename_edit.visible = true
					rename_edit.grab_focus()
					rename_edit.select_all()
			)
			node.add_child(title_lbl)
			node.add_child(rename_edit)
		# One slot row per incoming child (so each connection gets its own pin),
		# min 1 row. Output (right) only on row 0, only for non-Master buses.
		var incoming: int = all_buses.values().count(bus_name)
		var rows: int = maxi(incoming, 1)
		for row in rows:
			node.add_child(HSeparator.new())
			var enable_left: bool = row < incoming
			var enable_right: bool = row == 0 and bus_name != "Master"
			node.set_slot(row, enable_left, 0, Color.WHITE, enable_right, 0, Color.WHITE)
		# children at x=40 (stacked vertically), Master at the right — data flows left to right
		var pos_x: float = 300.0 if bus_name == "Master" else 40.0
		var pos_y: float = 40.0 if bus_name == "Master" else 40.0 + 130.0 * all_buses.keys().filter(
			func(b: String) -> bool: return all_buses[b] != "" and b != "Master").find(bus_name)
		node.position_offset = Vector2(pos_x, pos_y)
		event_graph.add_child(node)
	for bus_name: String in all_buses:
		var parent: String = all_buses[bus_name]
		if parent != "" and event_graph.get_node_or_null(NodePath(parent)) != null:
			event_graph.connect_node(bus_name, 0, parent, _child_slot(parent, bus_name))

## Slot index on the parent's enabled output slots for this child bus.
func _child_slot(parent: String, child: String) -> int:
	var idx := 0
	for b: String in backend.buses:
		if b != parent and backend.buses[b] == parent:
			if b == child:
				break
			idx += 1
	return idx

## New bus routed to Master, uniquely named Bus1, Bus2, ...
func _add_bus_at_cursor() -> void:
	var n := 1
	var name := "Bus%d" % n
	while backend.buses.has(name) or name == "Master":
		n += 1
		name = "Bus%d" % n
	backend.push_undo()
	backend.buses[name] = "Master"
	_build_bus_graph()

## F2 on a selected mixer-list entry, or rename via the bus node's title.
## Renaming a bus updates routing keys, bus volumes, and every event using it.
func _rename_bus(old_name: String, new_name: String) -> void:
	backend.push_undo()
	new_name = new_name.strip_edges()
	if new_name.is_empty() or new_name == old_name or new_name == "Master":
		return
	if backend.buses.has(new_name):
		push_warning("Bus '%s' already exists" % new_name)
		return
	# rebuild dict preserving order
	var new_buses := {}
	for b: String in backend.buses:
		var parent: String = backend.buses[b]
		if parent == old_name:
			parent = new_name
		new_buses[new_name if b == old_name else b] = parent
	backend.buses = new_buses
	if backend.bus_volumes.has(old_name):
		backend.bus_volumes[new_name] = backend.bus_volumes[old_name]
		backend.bus_volumes.erase(old_name)
	for e_props: Dictionary in backend.events.values():
		if e_props.get("bus", "") == old_name:
			e_props["bus"] = new_name
	_build_bus_graph()

## Bus routing edges: any child bus into its declared parent only.
var _volume_undo_pending := false

func _on_bus_volume_changed(value: float, bus_name: String) -> void:
	if not _volume_undo_pending:
		_volume_undo_pending = true
		backend.push_undo()
		# one undo entry per drag gesture: cleared next frame after release
		_clear_volume_pending.call_deferred()
	backend.bus_volumes[bus_name] = value

func _clear_volume_pending() -> void:
	_volume_undo_pending = false
func _on_bus_connection_request(from: StringName, from_port: int, to: StringName, to_port: int) -> void:
	backend.push_undo()
	if to == "Master" or backend.buses.has(String(to)):
		backend.buses[String(from)] = String(to)
		_build_bus_graph()

func _on_bus_disconnection_request(from: StringName, _from_port: int, to: StringName, _to_port: int) -> void:
	if String(from) != "Master":
		backend.push_undo()
		backend.buses[String(from)] = ""
		_build_bus_graph()

func _on_export_button_pressed() -> void:
	save_project()  # durability first: authoring state always persists on export
	file_dialog.popup_centered()

func _on_file_dialog_file_selected(path: String) -> void:
	if not path.ends_with(".tres"):
		path += ".tres"

	backend.compile_all()
	var dir := path.get_base_dir()
	var bank: Resource = load("res://addons/middot_audio/SoundBank.gd").new()
	for event_props: Dictionary in backend.events.values():
		var files: Array = []
		_collect_files_typed(event_props, files)
		for audio_file: String in files:
			if audio_file.is_empty():
				continue
			var source := _audio_dir().path_join(audio_file)
			if not FileAccess.file_exists(source):
				push_error("Missing audio file for event: ", source)
				return
			var copy_err := DirAccess.copy_absolute(source, dir.path_join(audio_file))
			if copy_err != OK:
				push_error("Failed to copy %s: error code %d" % [audio_file, copy_err])
				return

	bank.events = backend.events.duplicate(true)
	bank.buses = backend.buses.duplicate(true)
	bank.bus_volumes = backend.bus_volumes.duplicate(true)

	var err := ResourceSaver.save(bank, path)
	if err == OK:
		print("Soundbank saved: ", path)
	else:
		push_error("Failed to save resource. Godot Error Code: ", err)
