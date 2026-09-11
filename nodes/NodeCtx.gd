class_name NodeCtx
extends RefCounted

## Service object handed to node types so they never touch Main directly.
## Reads Main state LIVE (never caches references — _load_project replaces
## the _events/_variables dicts on open).

var main: Control                    # host (Main.gd); last-resort escape hatch
var selected: String                 # currently selected event name

func _sync() -> void:
	selected = main._selected

func events() -> Dictionary:
	return main.backend.events

func variables() -> Dictionary:
	return main.backend.variables

func push_undo() -> void:
	main._push_undo()

func rebuild_deferred() -> void:
	main._rebuild_current_view()

func rebuild_event_deferred() -> void:
	main._build_graph.call_deferred()

func spawn_pos() -> Vector2:
	return main.event_graph.get_meta("spawn_pos", Vector2.INF)

func set_spawn_pos(p: Vector2) -> void:
	main.event_graph.set_meta("spawn_pos", p)

func sync_declaration(cond: Dictionary, old_param: String = "") -> void:
	main._sync_declaration(cond, old_param)

func select_event(name: String) -> void:
	main._selected = name
	main._build_graph()

func selected_event() -> Dictionary:
	_sync()
	return main.backend.events.get(selected, {})
