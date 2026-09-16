class_name Auditioner
extends Node

## Audition: plays a compiled event tree in the authoring app (F5 preview).
## Honors trigger semantics (simple/random/shuffle/playlist/sync/conditional),
## event bus routing + volume, and the event's looping flag. One root voice;
## sync layers spawn extra voices.

var _p: AudioStreamPlayer
var _voices: Array = []   # extra voices spawned by sync nodes
var _audio_dir := ""
var _variables := {}
var _last_shuffle := -1
var _tree := {}
var _base_db := 0.0

func stop() -> void:
	if _p:
		_p.queue_free()
		_p = null
	for v in _voices:
		if is_instance_valid(v):
			v.queue_free()
	_voices.clear()
	_last_shuffle = -1

func play(tree: Dictionary, audio_dir: String, buses: Dictionary, bus_volumes: Dictionary, variables: Dictionary) -> void:
	stop()
	_audio_dir = audio_dir
	_variables = variables
	_tree = tree
	_setup_bus(tree.get("bus", "Master"), buses, bus_volumes)
	_p = AudioStreamPlayer.new()
	add_child(_p)
	_p.bus = tree.get("bus", "Master")
	_base_db = tree.get("volume_db", 0.0)
	_p.volume_db = _base_db
	_play_node(_p, tree, _on_tree_done)

func _on_tree_done() -> void:
	if _p == null:
		return  # stopped while playing
	if _tree.get("looping", false):
		_play_node(_p, _tree, _on_tree_done)
	else:
		stop()

## Recursively play `t` on voice `p`; `done` fires when the tree finishes.
func _play_node(p: AudioStreamPlayer, t: Dictionary, done: Callable) -> void:
	match t.get("trigger", "simple"):
		"simple":
			_play_leaf(p, t, done)
		"random":
			var kids: Array = t.get("sounds", [])
			if kids.is_empty():
				done.call()
				return
			var idx := randi() % kids.size()
			if t.get("random_mode", "random") == "shuffle" and kids.size() > 1 and idx == _last_shuffle:
				idx = (idx + 1) % kids.size()  # ponytail: avoids one repeat; Wwise-style full-cycle shuffle if it matters
			_last_shuffle = idx
			_play_node(p, kids[idx], done)
		"playlist":
			_play_seq(p, t.get("sounds", []), 0, t.get("playlist_loop", true), done)
		"sync":
			var kids: Array = t.get("sounds", [])
			if kids.is_empty():
				done.call()
				return
			var remaining := {"n": kids.size()}
			var on_one := func() -> void:
				remaining["n"] -= 1
				if remaining["n"] == 0:
					done.call()
			for i in kids.size():
				var vp: AudioStreamPlayer = p if i == 0 else _extra_voice()
				_play_node(vp, kids[i], func() -> void:
					if vp != _p:
						_voices.erase(vp)
						vp.queue_free()
					on_one.call())
		"conditional":
			var pick: Dictionary = _pick_branch(t)
			if pick.is_empty():
				push_warning("Audition: no matching branch")
				done.call()
			else:
				_play_node(p, pick, done)
		_:
			push_warning("Audition: unknown trigger '%s'" % t.get("trigger", ""))
			done.call()

func _play_seq(p: AudioStreamPlayer, sounds: Array, i: int, loop: bool, done: Callable) -> void:
	if i >= sounds.size():
		if loop and not sounds.is_empty():
			_play_seq(p, sounds, 0, true, done)  # ponytail: intentional infinite loop, Stop button is the guard
		else:
			done.call()
		return
	_play_node(p, sounds[i], func() -> void: _play_seq(p, sounds, i + 1, loop, done))

## One extra voice for sync layers; inherits the root bus. Freed by stop()
## or when its layer finishes.
func _extra_voice() -> AudioStreamPlayer:
	var vp := AudioStreamPlayer.new()
	add_child(vp)
	vp.bus = _p.bus if _p else "Master"
	_voices.append(vp)
	return vp

func _play_leaf(p: AudioStreamPlayer, t: Dictionary, done: Callable) -> void:
	var file: String = t.get("audio_file", "")
	if file.is_empty():
		done.call()
		return
	var path := _audio_dir.path_join(file)
	var stream: AudioStream = null
	match path.get_extension():
		"wav": stream = AudioStreamWAV.load_from_file(path)
		"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
		"mp3": stream = AudioStreamMP3.load_from_file(path)
	if stream == null:
		push_warning("Audition: cannot load %s" % path)
		done.call()
		return
	p.volume_db = _base_db + t.get("file_volume_db", 0.0)
	p.pitch_scale = t.get("pitch_scale", 1.0)
	p.stream = stream
	p.play()
	p.finished.connect(done, CONNECT_ONE_SHOT)

## First branch whose conditions all hold (using each variable's default value
## as the current value); falls back to the branch marked default.
func _pick_branch(t: Dictionary) -> Dictionary:
	var branches: Array = t.get("branches", [])
	var bcs: Array = t.get("branch_conditions", [])
	var fallback := -1
	for i in branches.size():
		var bc: Dictionary = bcs[i] if i < bcs.size() else {"conditions": []}
		if bc.get("default", false):
			fallback = i
		elif _conditions_ok(bc.get("conditions", [])):
			return t["branches"][i]
	if fallback != -1:
		return t["branches"][fallback]
	return {}

func _conditions_ok(conds: Array) -> bool:
	for cond: Dictionary in conds:
		var param: String = cond.get("param", "")
		var decl: Dictionary = _variables.get(param, {})
		var cur = decl.get("default", "")
		var want: String = str(cond.get("value", ""))
		var op: String = cond.get("op", "==")
		if decl.get("type", "enum") == "number" or String(cur).is_valid_float() and String(cur) != "":
			var a := float(cur)
			var b := float(want)
			match op:
				"==": if not (a == b): return false
				"!=": if not (a != b): return false
				"<": if not (a < b): return false
				"<=": if not (a <= b): return false
				">": if not (a > b): return false
				">=": if not (a >= b): return false
		else:
			match op:
				"==": if cur != want: return false
				"!=": if cur == want: return false
				_:
					push_warning("Audition: op '%s' needs a numeric variable (%s)" % [op, param])
					return false
	return true

## Create the event's bus (and its parents) in the live AudioServer, applying
## project volumes. Existing buses are left alone.
func _setup_bus(name: String, buses: Dictionary, bus_volumes: Dictionary) -> void:
	if name.is_empty() or name == "Master" or AudioServer.get_bus_index(name) != -1:
		return
	_setup_bus(buses.get(name, ""), buses, bus_volumes)  # parents before children
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, name)
	var parent: String = buses.get(name, "")
	AudioServer.set_bus_send(idx, parent if not parent.is_empty() else "Master")
	var v: float = bus_volumes.get(name, 100.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(v / 100.0, 0.0001, 1.0)))