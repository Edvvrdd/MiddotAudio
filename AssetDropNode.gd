class_name AssetDropNode
extends GraphNode

## Graph node that accepts asset drags anywhere on it (payload "middot_asset").

signal asset_dropped(file: String)

func _can_drop_data(_at: Vector2, data) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("type") == "middot_asset"

func _drop_data(_at: Vector2, data) -> void:
	asset_dropped.emit(data["file"])
