class_name NodeCtx
extends RefCounted

## Service object handed to node types so they never touch Main directly.

var main: Control                    # host (Main.gd); last-resort escape hatch

func push_undo() -> void:
	main._push_undo()

func rebuild_deferred() -> void:
	main._rebuild_current_view.call_deferred()  # actually deferred: callers fire from node signals

func sync_declaration(cond: Dictionary, old_param: String = "") -> void:
	main._sync_declaration(cond, old_param)

## Play a single file (Sound node preview) with the event's bus/volume.
func audition_file(node_data: Dictionary) -> void:
	main._audition_file(node_data)
