class_name AssetDropEdit
extends LineEdit

## LineEdit that accepts asset drags (payload type "middot_asset") and
## replaces its text. Used for the Sound node's audio-file field.

func _can_drop_data(_at: Vector2, data) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("type") == "middot_asset"

func _drop_data(_at: Vector2, data) -> void:
	text = data["file"]
	text_changed.emit(text)
