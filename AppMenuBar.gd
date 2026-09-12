class_name AppMenuBar
extends HBoxContainer

## Top application bar: File menu — new/open/save/save-as project and export.

signal new_project_requested
signal open_project_requested
signal save_requested
signal save_as_requested
signal export_requested

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
	menu.add_item("Export Soundbank...", 4)
	menu.id_pressed.connect(_on_menu_id_pressed)
	add_child(file_btn)

func _on_menu_id_pressed(id: int) -> void:
	match id:
		0: new_project_requested.emit()
		1: open_project_requested.emit()
		2: save_requested.emit()
		3: save_as_requested.emit()
		3 + 1: export_requested.emit()