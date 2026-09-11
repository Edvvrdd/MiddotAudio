class_name AppMenuBar
extends HBoxContainer

## Top application bar: File menu with project open/save-as and export.

signal project_dialog_requested
signal export_requested

func _ready() -> void:
	var file_btn := MenuButton.new()
	file_btn.text = "File"
	var menu := file_btn.get_popup()
	menu.add_item("New / Open Project...", 0)
	menu.add_item("Save As...", 1)
	menu.add_separator()
	menu.add_item("Export Soundbank...", 2)
	menu.id_pressed.connect(_on_menu_id_pressed)
	add_child(file_btn)

func _on_menu_id_pressed(id: int) -> void:
	if id == 2:
		export_requested.emit()
	else:
		project_dialog_requested.emit()
