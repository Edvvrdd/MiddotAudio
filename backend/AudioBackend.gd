class_name AudioBackend
extends RefCounted

## Backend: owns all authoring data and the operations on it. The frontend
## (Main.gd + node scripts) is a view/broadcaster — it calls backend mutations
## and listens to `changed` signals to re-render.
##
## Data owned here:
##   events      -> compiled event trees (written to the soundbank on export)
##   canvas      -> per-event free-canvas graphs (nodes + wires)
##   variables   -> variable registry
##   buses / bus_volumes -> mixer routing
##   project_path -> current .middot location
##
## Everything mutated through the backend emits `changed` (with a hint of what
## changed) so the frontend refreshes precisely what it shows.

signal changed(what: String)          # "canvas", "events", "variables", "buses", "project"
signal undo_stack_changed

const UNDO_LIMIT := 50

var project_path := ""
var events := {}          # compiled event trees
var canvas := {}          # per-event free-canvas graphs
var variables := {}
var buses := {}
var bus_volumes := {}

var _undo_stack: Array = []
var _redo_stack: Array = []
var _undo_enabled := false
var _volume_undo_pending := false

## ---- lifecycle -----------------------------------------------------------

func new_project() -> void:
	events = {}
	canvas = {}
	variables = {}
	buses = {}
	bus_volumes = {}
	project_path = ""
	_undo_stack.clear()
	_redo_stack.clear()
	changed.emit("project")

## ---- undo / redo (whole-state snapshots) ----------------------------------

func _snapshot() -> Dictionary:
	return {
		"events": events.duplicate(true),
		"canvas": canvas.duplicate(true),
		"variables": variables.duplicate(true),
		"buses": buses.duplicate(true),
		"bus_volumes": bus_volumes.duplicate(true),
		"selected": "",
	}

func _restore(snap: Dictionary) -> void:
	events = snap["events"]
	canvas = snap["canvas"]
	variables = snap["variables"]
	buses = snap["buses"]
	bus_volumes = snap["bus_volumes"]
	changed.emit("all")

func enable_undo() -> void:
	_undo_enabled = true
	_undo_stack.clear()
	_redo_stack.clear()
	undo_stack_changed.emit()

func push_undo() -> void:
	if not _undo_enabled:
		return
	_undo_stack.append(_snapshot())
	if _undo_stack.size() > UNDO_LIMIT:
		_undo_stack.pop_front()
	_redo_stack.clear()
	undo_stack_changed.emit()

func undo() -> void:
	if _undo_stack.is_empty():
		return
	_redo_stack.append(_snapshot())
	_restore(_undo_stack.pop_back())

func redo() -> void:
	if _redo_stack.is_empty():
		return
	_undo_stack.append(_snapshot())
	_restore(_redo_stack.pop_back())

## ---- canvas operations -----------------------------------------------------

func ensure_canvas(event_name: String) -> void:
	if not canvas.has(event_name):
		canvas[event_name] = {
			"nodes": [{"id": 0, "type": "event_output",
				"data": {"bus": "Master", "volume": 100.0, "looping": false}, "pos": Vector2(560, 20)}],
			"wires": [], "next_id": 1,
		}

func get_canvas(event_name: String) -> Dictionary:
	ensure_canvas(event_name)
	return canvas[event_name]

func place_node(event_name: String, type_name: String, pos: Vector2) -> int:
	ensure_canvas(event_name)
	push_undo()
	var c: Dictionary = canvas[event_name]
	var id: int = c["next_id"]
	c["next_id"] = id + 1
	var data: Dictionary = default_data_for(type_name)
	c["nodes"].append({"id": id, "type": type_name, "data": data, "pos": pos})
	changed.emit("canvas")
	return id

func default_data_for(type_name: String) -> Dictionary:
	match type_name:
		"sound":
			return {"audio_file": "", "volume": 100.0, "pitch": 1.0}
		"random_trigger":
			return {"random_mode": "shuffle", "pins": 1}
		"playlist_trigger":
			return {"sync": false, "playlist_loop": true, "pins": 1}
		"conditional_trigger":
			return {"mode": "playlist", "playlist_loop": true, "sync": false, "pins": 1}
		"event_output":
			return {"bus": "Master", "volume": 100.0, "looping": false}
	return {}

## Place a variable node. With `existing_param`, reference a declared variable
## (no new registry entry); without, generate param_N and declare it.
func add_variable_node(event_name: String, pos: Vector2, existing_param: String = "") -> String:
	push_undo()
	var name := existing_param
	if name.is_empty() or not variables.has(name):
		name = "param_%d" % (variables.size() + 1)
		while variables.has(name):
			name += "_new"
		variables[name] = {"type": "enum", "enum_values": [], "min": "", "max": "", "default": false}
	ensure_canvas(event_name)
	var c: Dictionary = canvas[event_name]
	var id: int = c["next_id"]
	c["next_id"] = id + 1
	var decl: Dictionary = variables[name]
	c["nodes"].append({"id": id, "type": "variable",
		"data": {"param": name, "type": decl.get("type", "enum"), "enum_values": decl.get("enum_values", []), "min": decl.get("min", ""), "max": decl.get("max", ""), "default": decl.get("default", false)},
		"pos": pos})
	changed.emit("all")
	return name

func add_pin(event_name: String, node_id: int) -> void:
	var n: Dictionary = node_by_id(event_name, node_id)
	if n.is_empty():
		return
	push_undo()
	n["data"]["pins"] = n["data"].get("pins", 1) + 1
	if n["type"] == "conditional_trigger":
		n["data"].get_or_add("branch_conditions", []).append({"conditions": []})
	changed.emit("canvas")

func add_branch(event_name: String, node_id: int) -> void:
	var n: Dictionary = node_by_id(event_name, node_id)
	if n.is_empty():
		return
	push_undo()
	n["data"].get_or_add("branch_conditions", []).append({"conditions": []})
	n["data"]["pins"] = n["data"].get("pins", 1) + 1
	changed.emit("canvas")

func delete_nodes(event_name: String, ids: Array) -> void:
	ensure_canvas(event_name)
	push_undo()
	var c: Dictionary = canvas[event_name]
	c["nodes"] = c["nodes"].filter(func(n): return not ids.has(n["id"]))
	c["wires"] = c["wires"].filter(func(w): return not (ids.has(w["from"]) or ids.has(w["to"])))
	changed.emit("canvas")

func connect_nodes(event_name: String, from_id: int, from_port: int, to_id: int, to_port: int) -> bool:
	ensure_canvas(event_name)
	var from_type: String = node_type(event_name, from_id)
	var to_type: String = node_type(event_name, to_id)
	if not NodeTypes.connection_allowed(from_type, to_type):
		return false
	push_undo()
	canvas[event_name]["wires"].append({"from": from_id, "from_port": from_port, "to": to_id, "to_port": to_port})
	changed.emit("canvas")
	return true

func disconnect_nodes(event_name: String, from_id: int, from_port: int, to_id: int, to_port: int) -> void:
	ensure_canvas(event_name)
	push_undo()
	canvas[event_name]["wires"] = canvas[event_name]["wires"].filter(func(w):
		return not (w["from"] == from_id and w["from_port"] == from_port and w["to"] == to_id and w["to_port"] == to_port))
	changed.emit("canvas")

func set_node_file(event_name: String, node_id: int, file: String) -> void:
	var n: Dictionary = node_by_id(event_name, node_id)
	if n.is_empty():
		return
	push_undo()
	n["data"]["audio_file"] = file
	changed.emit("canvas")

func node_by_id(event_name: String, id: int) -> Dictionary:
	ensure_canvas(event_name)
	for n in canvas[event_name]["nodes"]:
		if n["id"] == id:
			return n
	return {}

func node_type(event_name: String, id: int) -> String:
	return node_by_id(event_name, id).get("type", "")

## ---- variables --------------------------------------------------------------

func sync_declaration(cond: Dictionary, old_param: String = "") -> void:
	var param: String = cond.get("param", "")
	if not param.is_empty():
		variables[param] = {
			"type": cond.get("type", "enum"),
			"enum_values": (cond.get("enum_values", []) as Array).duplicate(),
			"min": cond.get("min", ""), "max": cond.get("max", ""),
			"default": cond.get("default", false),
		}
	if old_param != "" and old_param != param:
		variables.erase(old_param)
	for event_name: String in canvas:
		for n in canvas[event_name]["nodes"]:
			for bc in n["data"].get("branch_conditions", []):
				for c in bc.get("conditions", []):
					if old_param != "" and c.get("param", "") == old_param:
						c["param"] = param
					if c.get("param", "") == param:
						c["type"] = cond.get("type", "enum")
						c["enum_values"] = (cond.get("enum_values", []) as Array).duplicate()
						c["min"] = cond.get("min", "")
						c["max"] = cond.get("max", "")
						c["default"] = cond.get("default", false)
	changed.emit("variables")

func delete_variable(name: String) -> void:
	push_undo()
	variables.erase(name)
	# purge EVERY usage: condition references AND variable nodes themselves
	# (previously nodes were left orphaned, pointing at a deleted declaration)
	for event_name: String in canvas:
		var c: Dictionary = canvas[event_name]
		var dead: Array = []
		for n in c["nodes"]:
			if n["type"] == "variable" and n["data"].get("param", "") == name:
				dead.append(n["id"])
			else:
				for bc in n["data"].get("branch_conditions", []):
					bc["conditions"] = (bc.get("conditions", []) as Array).filter(func(c):
						return c.get("param", "") != name)
		c["nodes"] = c["nodes"].filter(func(n): return not dead.has(n["id"]))
		c["wires"] = c["wires"].filter(func(w): return not (dead.has(w["from"]) or dead.has(w["to"])))
	changed.emit("all")

## ---- events (list-level) ----------------------------------------------------

func create_event(event_name: String) -> void:
	push_undo()
	ensure_canvas(event_name)
	events[event_name] = {}
	changed.emit("events")

func delete_event(event_name: String) -> void:
	push_undo()
	canvas.erase(event_name)
	events.erase(event_name)
	changed.emit("all")

func rename_event(old_name: String, new_name: String) -> bool:
	if not events.has(old_name) or new_name.is_empty() or new_name == old_name:
		return false
	push_undo()
	events[new_name] = events[old_name]
	events.erase(old_name)
	canvas[new_name] = canvas[old_name]
	canvas.erase(old_name)
	changed.emit("events")
	return true

## ---- compile ---------------------------------------------------------------

## Compile every canvas into `events`. Events that fail compile loudly and are
## skipped. Returns the compiled dict.
func compile_all() -> Dictionary:
	var compiled := {}
	for event_name: String in canvas:
		var tree: Dictionary = compile_event(event_name)
		if not tree.is_empty():
			compiled[event_name] = tree
	events = compiled
	changed.emit("events")
	return events

func compile_event(event_name: String) -> Dictionary:
	var c: Dictionary = get_canvas(event_name)
	var out: Dictionary = {}
	for n in c["nodes"]:
		if n["type"] == "event_output":
			out = n
			break
	if out.is_empty():
		push_error("Compile: event '%s' has no Event Output node -- skipped" % event_name)
		return {}
	# Root = the node that nothing feeds into (no wire targets it). The Output
	# node carries event props only. Sounds wired straight into Output are
	# absorbed: one is a simple event, several are rejected (route them through
	# a Trigger node -- Output plays nothing by itself).
	var targeted := {}
	var out_sounds: Array = []  # ids of sound nodes wired directly into Output
	for w in c["wires"]:
		if w["to"] != out["id"]:
			targeted[w["to"]] = true
		elif node_type(event_name, w["from"]) == "sound":
			out_sounds.append(w["from"])
	var roots: Array = []
	for n in c["nodes"]:
		if n["type"] in ["event_output", "variable"] or targeted.has(n["id"]):
			continue
		if n["type"] == "sound" and out_sounds.has(n["id"]):
			continue  # absorbed into Output, never a root
		roots.append(n["id"])
	if roots.is_empty() and out_sounds.size() == 1:
		roots.append(out_sounds[0])  # single sound -> simple event
	if roots.is_empty():
		if out_sounds.size() > 1:
			push_error("Compile: event '%s' has %d sounds wired straight into Output -- route them through a Trigger node (Playlist/Random)" % [event_name, out_sounds.size()])
			assert(false, "Compile: multiple sounds into Output")
			return {}
		push_error("Compile: event '%s' has no root node (wire your triggers together) -- skipped" % event_name)
		assert(false, "Compile: no root trigger found")
		return {}
	if roots.size() > 1:
		push_error("Compile: event '%s' has %d unparented roots -- connect them or delete extras" % [event_name, roots.size()])
		assert(false, "Compile: multiple roots")
		return {}
	var visited := {}
	var tree: Dictionary = _compile_node(roots[0], c, event_name, visited, 0, out["id"])
	if tree.is_empty():
		return {}
	var vol: float = out["data"].get("volume", 100.0)
	tree["volume_db"] = linear_to_db(clampf(vol / 100.0, 0.0001, 1.0))
	tree["bus"] = out["data"].get("bus", "Master")
	tree["looping"] = out["data"].get("looping", false)
	return tree

func _compile_node(id: int, c: Dictionary, event_name: String, visited: Dictionary, depth: int, out_id: int) -> Dictionary:
	if depth > 16:
		push_error("Compile: event '%s' nesting deeper than 16" % event_name)
		assert(false, "Compile: runaway nesting")
		return {}
	if visited.has(id):
		push_error("Compile: event '%s' has a cycle at node %d" % [event_name, id])
		assert(false, "Compile: cycle in trigger graph")
		return {}
	visited[id] = true
	var node: Dictionary = node_by_id(event_name, id)
	if node.is_empty():
		return {}
	match node["type"]:
		"sound":
			var t := {"trigger": "simple", "audio_file": node["data"].get("audio_file", "")}
			var vol: float = node["data"].get("volume", 100.0)
			if not is_equal_approx(vol, 100.0):
				t["file_volume_db"] = linear_to_db(clampf(vol / 100.0, 0.0001, 1.0))
			var pitch: float = node["data"].get("pitch", 1.0)
			if not is_equal_approx(pitch, 1.0):
				t["pitch_scale"] = pitch
			return t
		"random_trigger":
			return {"trigger": "random", "random_mode": node["data"].get("random_mode", "random"),
				"sounds": _compile_children(node, c, event_name, visited, depth, out_id)}
		"playlist_trigger":
			if node["data"].get("sync", false):
				return {"trigger": "sync", "sounds": _compile_children(node, c, event_name, visited, depth, out_id)}
			return {"trigger": "playlist", "playlist_loop": node["data"].get("playlist_loop", true),
				"sounds": _compile_children(node, c, event_name, visited, depth, out_id)}
		"conditional_trigger":
			var out_wires: Array = c["wires"].filter(func(w): return w["from"] == id)
			out_wires.sort_custom(func(a, b): return a["from_port"] < b["from_port"])
			# Trigger node transforms by its own mode selection
			var tmode: String = node["data"].get("mode", "playlist")
			if tmode in ["playlist", "random"]:
				var sounds: Array = []
				for w in out_wires:
					if w["to"] == out_id:
						continue  # wire into Output is decorative
					var s: Dictionary = _compile_node(w["to"], c, event_name, visited, depth + 1, out_id)
					if not s.is_empty():
						sounds.append(s)
				if tmode == "playlist":
					if node["data"].get("sync", false):
						return {"trigger": "sync", "sounds": sounds}
					return {"trigger": "playlist", "playlist_loop": node["data"].get("playlist_loop", true), "sounds": sounds}
				return {"trigger": "random", "random_mode": node["data"].get("random_mode", "random"), "sounds": sounds}
			var bcs: Array = node["data"].get("branch_conditions", [])
			var branches: Array = []
			var out_bcs: Array = []
			for w in out_wires:
				if w["to"] == out_id:
					continue  # wire into Output is decorative, not tree content
				var bc: Dictionary = bcs[w["from_port"]] if w["from_port"] < bcs.size() else {"conditions": []}
				var child: Dictionary = _compile_node(w["to"], c, event_name, visited, depth + 1, out_id)
				if child.is_empty():
					return {}
				branches.append(child)
				out_bcs.append(bc)
			return {"trigger": "conditional", "branches": branches, "branch_conditions": out_bcs}
	push_error("Compile: event '%s' node type '%s' cannot play audio" % [event_name, node["type"]])
	return {}

func _compile_children(node: Dictionary, c: Dictionary, event_name: String, visited: Dictionary, depth: int, out_id: int) -> Array:
	var out_wires: Array = c["wires"].filter(func(w): return w["from"] == node["id"] and w["to"] != out_id)
	out_wires.sort_custom(func(a, b): return a["from_port"] < b["from_port"])
	var children: Array = []
	for w in out_wires:
		var child: Dictionary = _compile_node(w["to"], c, event_name, visited, depth + 1, out_id)
		if not child.is_empty():
			children.append(child)
	return children

## ---- persistence ------------------------------------------------------------

## Legacy projects (pre-canvas): synthesize a canvas from each event's tree.
func migrate_legacy() -> void:
	for event_name: String in events:
		if canvas.has(event_name):
			continue
		var nodes: Array = []
		var wires: Array = []
		var next_id: Array = [0]
		var ev: Dictionary = events[event_name]
		var out_id: int = next_id[0]
		next_id[0] += 1
		nodes.append({"id": out_id, "type": "event_output",
			"data": {"bus": ev.get("bus", "Master"), "volume": 100.0, "looping": ev.get("looping", false)},
			"pos": Vector2(700, 20)})
		var root_id: int = _migrate_node(ev, nodes, wires, next_id, Vector2(20, 20))
		if root_id >= 0:
			wires.append({"from": root_id, "from_port": 0, "to": out_id, "to_port": 0})
		canvas[event_name] = {"nodes": nodes, "wires": wires, "next_id": next_id[0]}
	changed.emit("canvas")

func _migrate_node(ev: Dictionary, nodes: Array, wires: Array, next_id: Array, pos: Vector2) -> int:
	var id: int = next_id[0]
	next_id[0] += 1
	var trigger: String = ev.get("trigger", "simple")
	var type_name: String = "sound"
	var data: Dictionary = {"audio_file": ev.get("audio_file", "")}
	var children: Array = []
	if trigger == "conditional":
		type_name = "conditional_trigger"
		data = {"branch_conditions": ev.get("branch_conditions", ev.get("conditions", []).map(
			func(c): return {"default": true, "conditions": [c]}))}
		children = ev.get("branches", [])
	elif trigger == "playlist":
		type_name = "playlist_trigger"
		data = {"playlist_loop": ev.get("playlist_loop", true), "pins": maxi(ev.get("sounds", []).size(), 1)}
		children = ev.get("sounds", [])
	elif trigger == "random":
		type_name = "random_trigger"
		data = {"random_mode": ev.get("random_mode", "random"), "pins": maxi(ev.get("sounds", []).size(), 1)}
		children = ev.get("sounds", [])
	nodes.append({"id": id, "type": type_name, "data": data, "pos": pos})
	for k in children.size():
		var cid: int = _migrate_child(children[k], nodes, wires, next_id, pos + Vector2(260, 130 * k))
		if cid >= 0:
			wires.append({"from": id, "from_port": k, "to": cid, "to_port": 0})
	return id

func _migrate_child(child, nodes: Array, wires: Array, next_id: Array, pos: Vector2) -> int:
	if child is String:
		var id: int = next_id[0]
		next_id[0] += 1
		nodes.append({"id": id, "type": "sound", "data": {"audio_file": child}, "pos": pos})
		return id
	return _migrate_node(child, nodes, wires, next_id, pos)

## Serialize/deserialize the whole project state (used by the frontend's
## save/load file dialogs).
func to_dict() -> Dictionary:
	compile_all()
	return {
		"format_version": 2,
		"graph": canvas,
		"events": events,
		"buses": buses,
		"bus_volumes": bus_volumes,
		"variables": variables,
	}

func from_dict(data: Dictionary) -> void:
	buses = data.get("buses", {})
	bus_volumes = data.get("bus_volumes", {})
	variables = data.get("variables", {})
	canvas = data.get("graph", {})
	# JSON turns ints into floats on load; coerce all ids back to int or every
	# id comparison (delete_nodes' Array.has, wires, next_id) silently fails
	for ev: String in canvas:
		var c: Dictionary = canvas[ev]
		for n in c["nodes"]:
			n["id"] = int(n["id"])
		for w in c["wires"]:
			w["from"] = int(w["from"])
			w["to"] = int(w["to"])
		c["next_id"] = int(c.get("next_id", 0))
	events = data.get("events", {})
	if canvas.is_empty():
		migrate_legacy()
	changed.emit("project")
