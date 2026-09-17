extends Node

## Headless test runner: `godot --headless --path . res://tests/run_tests.tscn`
## Exit code 0 = all green, 1 = failure. Autoloads are up (NodeTypes etc.),
## so backend + node plugins are exercisable for real.

var _failures: Array = []
var _count := 0

func _ready() -> void:
	_test_compile_simple()
	_test_compile_looping()
	_test_compile_cycle_fails_loud()
	_test_banks_membership()
	_test_position_roundtrip()
	_test_legacy_migration()
	print("---")
	if _failures.is_empty():
		print("ALL %d TESTS PASSED" % _count)
		get_tree().quit(0)
	else:
		for f in _failures:
			print("FAIL: " + f)
		print("%d/%d TESTS FAILED" % [_failures.size(), _count])
		get_tree().quit(1)

func _check(cond: bool, label: String) -> void:
	_count += 1
	if not cond:
		_failures.append(label)
		print("  FAIL: " + label)

func _backend() -> AudioBackend:
	return AudioBackend.new()

## ensure_canvas already creates the Output node; tests wire into it.
func _out_id(be: AudioBackend, ev: String) -> int:
	for n in be.get_canvas(ev)["nodes"]:
		if n["type"] == "event_output":
			return n["id"]
	return -1

## Sound → Output compiles to a simple tree with the file.
func _test_compile_simple() -> void:
	var be := _backend()
	be.create_event("ev")
	var snd := be.place_node("ev", "sound", Vector2.ZERO)
	be.set_node_file("ev", snd, "footstep.wav")
	be.connect_nodes("ev", snd, 0, _out_id(be, "ev"), 0)
	var tree: Dictionary = be.compile_event("ev")
	_check(tree.get("trigger", "") == "simple", "simple: trigger")
	_check(tree.get("audio_file", "") == "footstep.wav", "simple: file")

## Output Loop flag reaches the compiled tree.
func _test_compile_looping() -> void:
	var be := _backend()
	be.create_event("ev")
	var snd := be.place_node("ev", "sound", Vector2.ZERO)
	be.set_node_file("ev", snd, "footstep.wav")
	be.connect_nodes("ev", snd, 0, _out_id(be, "ev"), 0)
	var out_data: Dictionary = be.node_by_id("ev", _out_id(be, "ev"))
	out_data["data"]["looping"] = true
	_check(be.compile_event("ev").get("looping", false) == true, "looping: reaches tree")

## A wire cycle fails loudly (empty tree), doesn't hang.
func _test_compile_cycle_fails_loud() -> void:
	var be := _backend()
	be.create_event("ev")
	var r1 := be.place_node("ev", "random_trigger", Vector2.ZERO)
	var r2 := be.place_node("ev", "random_trigger", Vector2.ZERO)
	be.connect_nodes("ev", r1, 0, r2, 0)
	be.connect_nodes("ev", r2, 0, r1, 0)   # cycle r1 -> r2 -> r1
	_check(be.compile_event("ev").is_empty(), "cycle: compiles empty (loud error logged)")

## Banks: membership, rename propagation, delete cleanup.
func _test_banks_membership() -> void:
	var be := _backend()
	be.add_bank("Music")
	be.create_event("ev_main")            # default bank
	be.create_event("ev_music", "Music")
	_check(be.banks["Main"].has("ev_main"), "banks: default membership")
	_check(be.banks["Music"].has("ev_music"), "banks: explicit membership")
	be.rename_event("ev_music", "track1")
	_check(be.banks["Music"].has("track1") and not be.banks["Music"].has("ev_music"),
		"banks: rename propagates")
	be.delete_event("track1")
	_check(not be.banks["Music"].has("track1"), "banks: delete cleans up")

## Node positions survive to_dict -> JSON -> from_dict (the Vector2 flattening bug).
func _test_position_roundtrip() -> void:
	var be := _backend()
	be.create_event("ev")
	be.place_node("ev", "sound", Vector2(123, 456))
	var s: String = JSON.stringify(be.to_dict())
	be.from_dict(JSON.parse_string(s))
	var snd: Dictionary = be.get_canvas("ev")["nodes"].filter(func(n): return n["type"] == "sound")[0]
	_check(snd["pos"] is Vector2 and snd["pos"] == Vector2(123, 456), "pos: JSON roundtrip")

## Pre-canvas (format v1) projects migrate into canvases.
func _test_legacy_migration() -> void:
	var be := _backend()
	be.from_dict({
		"format_version": 2,
		"graph": {},
		"events": {"legacy": {"trigger": "simple", "audio_file": "old.wav",
			"bus": "Master", "volume_db": 0.0}},
		"buses": {}, "bus_volumes": {}, "variables": {},
	})
	_check(be.canvas.has("legacy"), "migration: canvas created")
	var snds: Array = be.get_canvas("legacy")["nodes"].filter(func(n): return n["type"] == "sound")
	_check(snds.size() == 1 and snds[0]["data"]["audio_file"] == "old.wav", "migration: node data")
