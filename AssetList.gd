class_name AssetList
extends ItemList

## Assets browser list: drag source for asset → sound node drops.
## The list mirrors the project's Audio folder (beside the .middot file);
## add assets by dropping audio files anywhere in the app window, or into
## that folder directly (the app rescans on focus).

func _get_drag_data(_at: Vector2):
	var selected := get_selected_items()
	if selected.is_empty():
		return null
	var file := get_item_text(selected[0])
	var preview := Label.new()
	preview.text = file
	preview.position = Vector2(-40, -16)
	var wrap := Control.new()
	wrap.add_child(preview)
	set_drag_preview(wrap)
	return {"type": "middot_asset", "file": file}
