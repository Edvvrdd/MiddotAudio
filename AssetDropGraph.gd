class_name AssetDropGraph
extends GraphEdit

## Canvas that accepts asset drags on empty space (payload "middot_asset")
## to spawn new variation nodes.

signal asset_dropped(file: String, graph_pos: Vector2)

func _can_drop_data(_at: Vector2, data) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("type") == "middot_asset"

func _drop_data(at: Vector2, data) -> void:
	asset_dropped.emit(data["file"], at)
