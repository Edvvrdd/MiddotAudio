class_name AppMenuBar
extends HBoxContainer

## Top application bar: File menu — new/open/save/save-as project and export.

signal new_project_requested
signal open_project_requested
signal save_requested
signal save_as_requested
signal export_requested
signal play_toggled(playing: bool)

var _transport: MenuButton
var _playing := false

func _ready() -> void:
	var file_btn := MenuButton.new()
	file_btn.text = "File"
	var menu := file_btn.get_popup()
	menu.add_item("New Project...", 0)
	menu.add_item("Open Project...", 1)
	menu.add_separator()
	menu.add_item("Save", 2)
	menu.add_item("Save As...", 3)
	menu.add_separator()
	menu.add_item("Export Soundbank... (F7)", 4)
	menu.id_pressed.connect(_on_menu_id_pressed)
	add_child(file_btn)
	_transport = MenuButton.new()
	_transport.text = "Transport"
	var tmenu := _transport.get_popup()
	tmenu.add_item("Play (F5)", 0)
	tmenu.add_item("Stop", 1)
	tmenu.id_pressed.connect(func(id: int) -> void: play_toggled.emit(id == 0))
	add_child(_transport)

## Auditioner drives the menu state (auto-revert on failure, disable current state).
func set_playing(playing: bool) -> void:
	_playing = playing
	var tmenu := _transport.get_popup()
	tmenu.set_item_disabled(0, playing)
	tmenu.set_item_disabled(1, not playing)

## F5: flip between play and stop.
func toggle_play() -> void:
	play_toggled.emit(not _playing)

func _on_menu_id_pressed(id: int) -> void:
	match id:
		0: new_project_requested.emit()
		1: open_project_requested.emit()
		2: save_requested.emit()
		3: save_as_requested.emit()
		3 + 1: export_requested.emit()