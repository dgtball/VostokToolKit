extends Node
const Loc = preload("res://mods/VTK/VTKLoc.gd")

const GAME_DATA_RES := "res://Resources/GameData.tres"
const CONTROLLER_PATH := "/root/Map/Core/Controller"
const LOADER_PATH := "/root/Loader"
const SCENE_WAIT_FRAMES := 600
const TRAVEL_LOG := "user://loadouts_travel.log"
const TRADER_STAND_DISTANCE := 2.0
const FLOOR_PROBE_UP := 1.5
const FLOOR_PROBE_DOWN := 3.0

const MAPS := [
	"Village", "Highway", "School", "Outpost",
	"Minefield", "Bridge", "Apartments", "Terminal", "Airfield"
]

const SHELTERS := [
	"Cabin", "Attic", "Classroom", "Tent", "Bunker", "Garage"
]

const TRADERS := [
	{"name": "Generalist", "map": "Village", "pos": Vector3(44.9, 0.4, 65.4)},
	{"name": "Doctor", "map": "School", "pos": Vector3(46.0, 9.0, 49.0)},
	{"name": "Gunsmith", "map": "Outpost", "pos": Vector3(106.1, 0.21, -140.0)}
]

var game_data: Resource = null
var unlocked_only: bool = false
var _busy: bool = false
var _teleport_started_ms: int = 0
var _log_file: FileAccess = null
var _look_at: Vector3 = Vector3.ZERO
var _has_look_at: bool = false


func _ready() -> void:
	game_data = load(GAME_DATA_RES)
	process_mode = Node.PROCESS_MODE_ALWAYS


func travel_to_map(map_name: String) -> void:
	if not MAPS.has(map_name):
		_message(Loc.txt("Unknown map: ") + map_name, Color.RED)
		return
	_teleport_internal(map_name, null)


func travel_to_shelter(shelter_name: String) -> void:
	if not SHELTERS.has(shelter_name):
		_message(Loc.txt("Unknown shelter: ") + shelter_name, Color.RED)
		return
	if unlocked_only and not is_shelter_unlocked(shelter_name):
		_message(Loc.txt("Shelter not unlocked yet: ") + shelter_name, Color.RED)
		return
	_teleport_internal(shelter_name, null)


func is_shelter_unlocked(shelter_name: String) -> bool:
	var loader := _loader()
	if loader != null and loader.has_method("CheckShelterState"):
		return bool(loader.CheckShelterState(shelter_name))
	return FileAccess.file_exists("user://" + shelter_name + ".tres")


func travel_to_trader(entry: Dictionary) -> void:
	if entry == null or not entry.has("map"):
		return
	# Передаётся Callable, а не Vector3: живой трейдер появляется в дереве
	# только после смены сцены, поэтому точку обязательно считать после
	# загрузки. Callable вызывается на шаге 9 внутри _teleport_internal.
	_teleport_internal(String(entry["map"]), func(): return _trader_point(entry), String(entry.get("name", "")))


func find_trader(trader_name: String) -> Node3D:
	# Так ищет сама игра: EventSystem.ActivateTrader() берёт get_nodes_in_group("Trader"),
	# а различает трейдеров по traderData.name (Interface.UpdateTraderInfo). Поиск по имени
	# ноды и суффиксу скрипта не работает — ноды так не называются.
	for n in get_tree().get_nodes_in_group("Trader"):
		if not (n is Node3D):
			continue
		var td = n.get("traderData")
		if td != null and String(td.get("name")) == trader_name:
			return n
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return _find_trader_in(scene, trader_name)


func _find_trader_in(root: Node, trader_name: String) -> Node3D:
	for child in root.get_children():
		if child is Node3D:
			if child.name == trader_name and _is_trader(child):
				return child
			var found := _find_trader_in(child, trader_name)
			if found != null:
				return found
	return null


func _is_trader(n: Node) -> bool:
	var s = n.get("script")
	if s is Script:
		return String((s as Script).resource_path).ends_with("Trader.gd")
	return false


func set_unlocked_only(on: bool) -> void:
	unlocked_only = on


func _teleport_internal(target_map: String, final_offset: Variant, dest_label: String = "") -> void:
	if _busy:
		_message(Loc.txt("Teleport already in progress"), Color.YELLOW)
		return
	if game_data != null and bool(game_data.get("tutorial")):
		_message(Loc.txt("Teleport unavailable in the tutorial"), Color.RED)
		return
	var loader := _loader()
	if loader == null or not loader.has_method("LoadScene"):
		_message(Loc.txt("Scene loader not found"), Color.RED)
		return
	_log_reset()
	_teleport_started_ms = Time.get_ticks_msec()
	_has_look_at = false
	_busy = true
	var actual_current := _current_map_name()
	_log("teleport start -> " + target_map + " (from " + actual_current + ", offset kind=" + str(typeof(final_offset)) + ")")
	_close_interfaces()
	_save_before_transition(target_map, loader)
	if game_data != null:
		if bool(game_data.get("shelter")) and loader.has_method("SaveShelter"):
			loader.SaveShelter(actual_current)
		game_data.set("previousMap", actual_current)
		game_data.set("currentMap", target_map)
	var prev_id := 0
	var scene := get_tree().current_scene
	if scene != null:
		prev_id = scene.get_instance_id()
	loader.LoadScene(target_map)
	if not await _wait_scene_change(prev_id):
		_busy = false
		_log("FAIL scene never changed for " + target_map)
		_message(Loc.txt("Scene failed to load: ") + target_map, Color.RED)
		return
	_log("scene changed detected")
	if loader.has_method("SaveWorld"):
		loader.SaveWorld()
	if not await _await_map_ready():
		_busy = false
		var label0 := dest_label if dest_label == "" else " (" + dest_label + ")"
		_message(Loc.txt("Map ") + target_map + Loc.txt(" failed to load") + label0, Color.RED)
		_log("FAIL: map never became ready for " + target_map)
		return
	var point: Variant = _resolve_final_offset(final_offset)
	if point is Vector3:
		_log("resolved offset Vector3 " + str(point))
		_place_player(point)
	elif final_offset is Callable:
		_busy = false
		_log("FAIL trader " + dest_label + ": landing point NOT resolved (" + str(typeof(point)) + "), player left at map spawn")
		_message(Loc.txt("Trader not found: ") + dest_label + Loc.txt(" (you are on ") + target_map + ")", Color.RED)
		return
	else:
		_log("resolved offset is NOT Vector3 (" + str(typeof(point)) + "), player NOT moved")
	_busy = false
	var dest := target_map if dest_label == "" else target_map + " (" + dest_label + ")"
	_message(Loc.txt("Teleport: ") + dest, Color.GREEN)
	_log("teleport done -> " + dest)


func _save_before_transition(target_map: String, loader: Node) -> void:
	if loader == null or not loader.has_method("SaveCharacter"):
		_log("pre-transition save: Loader.SaveCharacter unavailable")
		return
	var iface := get_node_or_null("/root/Map/Core/UI/Interface")
	if iface == null:
		_log("pre-transition save: Interface missing, skipping")
		return
	var shelter := game_data != null and bool(game_data.get("shelter"))
	_log("pre-transition save: shelter=" + str(shelter) + " -> " + target_map + " (grids still live, saving BEFORE scene change)")
	loader.call("SaveCharacter")
	_log("pre-transition save: done")


func _resolve_final_offset(final_offset: Variant) -> Variant:
	if final_offset is Callable:
		var c: Callable = final_offset
		if c.is_valid():
			return c.call()
		return null
	return final_offset


func _wait_scene_change(prev_id: int) -> bool:
	for _i in range(SCENE_WAIT_FRAMES):
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and scene.get_instance_id() != prev_id:
			await get_tree().create_timer(0.1, false).timeout
			return true
	return false


func _loader() -> Node:
	return get_node_or_null(LOADER_PATH)


func _controller() -> Node3D:
	var c := get_node_or_null(CONTROLLER_PATH)
	if c is Node3D:
		return c
	return null


func _current_map_name() -> String:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path == "":
		return ""
	return scene.scene_file_path.get_file().get_basename()


func _close_interfaces() -> void:
	var parent := get_parent()
	if parent != null and is_instance_valid(parent) and parent.has_method("_set_panel_open"):
		parent.call("_set_panel_open", false)
	var ui := get_node_or_null("/root/Map/Core/UI")
	var iface := get_node_or_null("/root/Map/Core/UI/Interface")
	var gd_iface := "n/a"
	if game_data != null:
		gd_iface = str(game_data.get("interface"))
	var iface_vis := "n/a"
	if iface != null:
		iface_vis = str(iface.visible)
	_log("close_interfaces: ui_found=" + str(ui != null) + " has_ToggleInterface=" + str(ui != null and ui.has_method("ToggleInterface")) + " Interface.visible=" + iface_vis + " gameData.interface=" + gd_iface)
	if iface != null and iface.has_method("Close"):
		iface.call("Close")
		_log("close_interfaces: called Interface.Close() (deterministic)")
	elif ui != null and ui.has_method("ToggleInterface"):
		ui.call("ToggleInterface")
		_log("close_interfaces: FALLBACK blind ToggleInterface (Interface.Close unavailable)")
	else:
		_log("close_interfaces: nothing to close")
	if game_data != null:
		game_data.set("interface", false)
		game_data.set("isOccupied", false)


func _message(text: String, color: Color) -> void:
	var loader := _loader()
	if loader != null and loader.has_method("Message"):
		loader.call("Message", text, color)
		return
	print("[VTK] " + text)


func _log_reset() -> void:
	if _log_file != null:
		_log_file.close()
		_log_file = null
	if FileAccess.file_exists(TRAVEL_LOG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TRAVEL_LOG))


func _log(msg: String) -> void:
	if _log_file == null:
		_log_file = FileAccess.open(TRAVEL_LOG, FileAccess.READ_WRITE)
		if _log_file == null:
			_log_file = FileAccess.open(TRAVEL_LOG, FileAccess.WRITE)
		if _log_file == null:
			print("[VTK] " + msg)
			return
	_log_file.seek_end()
	var elapsed := 0
	if _teleport_started_ms > 0:
		elapsed = Time.get_ticks_msec() - _teleport_started_ms
	_log_file.store_line("[" + Time.get_datetime_string_from_system() + " | +" + str(elapsed) + "ms] " + msg)
	_log_file.flush()
	print("[VTK] " + msg)


func _trader_point(entry: Dictionary) -> Vector3:
	var fallback := Vector3.ZERO
	if entry.has("pos"):
		var raw = entry["pos"]
		if raw is Vector3:
			fallback = raw
	var trader_name := String(entry.get("name", ""))
	var node := find_trader(trader_name)
	var anchor: Vector3 = fallback
	if node != null:
		anchor = node.global_position
		_log("trader " + trader_name + ": node at " + str(anchor))
		_log("trader " + trader_name + ": tree " + _dump_subtree(node, 0))
	else:
		_log("trader " + trader_name + ": node NOT found by name+Trader.gd, using hardcoded fallback " + str(fallback))
	var ctrl := _controller()
	_log("trader " + trader_name + ": controller " + ("present at " + str(ctrl.global_position) if ctrl != null else "NULL"))
	var facing := _node_forward(node)
	_log("trader " + trader_name + ": facing " + str(facing) + " rot=" + (str((node as Node3D).global_rotation) if node is Node3D else "n/a"))
	_look_at = anchor
	_has_look_at = true
	var ctrl2 := _controller()
	if ctrl2 == null:
		var raw2 := anchor + facing * TRADER_STAND_DISTANCE
		_log("trader " + trader_name + ": controller NULL, cannot place near trader, using raw probe " + str(raw2))
		return raw2
	var space := ctrl2.get_world_3d().direct_space_state
	var exclude: Array = [ctrl2.get_rid()]
	if node != null:
		_collect_rids(node, exclude)
	var ref_floor := _ray_floor(space, exclude, anchor)
	_log("trader " + trader_name + ": floor under trader y=" + str(ref_floor) + " (anchor y=" + str(anchor.y) + ")")
	var stand_dir := -facing
	_log("trader " + trader_name + ": stand dir " + str(stand_dir))
	for dist in [TRADER_STAND_DISTANCE, 2.5, 3.0, 1.5]:
		var cand: Vector3 = anchor + stand_dir * float(dist)
		var hit := _ray_floor_hit(space, exclude, cand)
		if not hit.is_empty():
			var hp: Vector3 = hit["position"]
			_log("trader " + trader_name + ": STAND " + str(hp) + " at dist " + str(dist) + " dir " + str(stand_dir))
			return hp
	for step in range(12):
		var ang := TAU * float(step) / 12.0
		var cand2: Vector3 = anchor + Vector3(cos(ang), 0.0, sin(ang)) * TRADER_STAND_DISTANCE
		var hit2 := _ray_floor_hit(space, exclude, cand2)
		if not hit2.is_empty():
			var hp2: Vector3 = hit2["position"]
			_log("trader " + trader_name + ": STAND ring " + str(hp2) + " step " + str(step))
			return hp2
	var map_name := String(entry.get("map", ""))
	_log("no floor near " + trader_name + " on " + map_name + "; using trader altitude " + str(anchor))
	return anchor + stand_dir * TRADER_STAND_DISTANCE


func _ray_floor_hit(space: PhysicsDirectSpaceState3D, exclude: Array, point: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(point + Vector3(0.0, FLOOR_PROBE_UP, 0.0), point + Vector3(0.0, -FLOOR_PROBE_DOWN, 0.0))
	q.exclude = exclude
	return space.intersect_ray(q)


func _ray_floor(space: PhysicsDirectSpaceState3D, exclude: Array, point: Vector3) -> float:
	var h := _ray_floor_hit(space, exclude, point)
	if h.is_empty():
		return point.y
	return float((h["position"] as Vector3).y)


func _collect_rids(node: Node, out: Array) -> void:
	for ch in node.get_children():
		if ch is CollisionObject3D:
			out.append((ch as CollisionObject3D).get_rid())
		else:
			_collect_rids(ch, out)


func _dump_subtree(node: Node, depth: int) -> String:
	if depth > 3:
		return ""
	var out := ""
	for ch in node.get_children():
		var pos := ""
		if ch is Node3D:
			pos = "@" + str((ch as Node3D).global_position)
		out += ch.name + "(" + ch.get_class() + pos + ")"
		if ch is Node3D:
			out += "[" + _dump_subtree(ch, depth + 1) + "]"
		out += " "
	return out.strip_edges()


func _node_forward(node: Node) -> Vector3:
	var fwd := Vector3(0.0, 0.0, -1.0)
	if node is Node3D:
		var b: Basis = (node as Node3D).global_transform.basis
		fwd = -b.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(0.0, 0.0, -1.0)
	return fwd.normalized()


func _await_map_ready() -> bool:
	if not is_inside_tree():
		return false
	var guard := 0
	while guard < 180 and game_data != null and not bool(game_data.get("isCaching")):
		await get_tree().process_frame
		guard += 1
	guard = 0
	while guard < 1800 and game_data != null and bool(game_data.get("isCaching")):
		await get_tree().process_frame
		guard += 1
	var caching := game_data != null and bool(game_data.get("isCaching"))
	_log("map ready: isCaching=" + str(caching) + " after " + str(guard) + " cached frames")
	if caching:
		return false
	await get_tree().create_timer(0.35, true, false, true).timeout
	return is_inside_tree()


func _place_player(target: Vector3) -> void:
	var ctrl := _controller()
	if ctrl == null:
		_log("place_player: controller NULL, player NOT moved (target was " + str(target) + ")")
		return
	ctrl.global_position = target
	ctrl.set("velocity", Vector3.ZERO)
	if game_data != null:
		game_data.set("playerVector", Vector3.ZERO)
	_log("place_player: moved controller to " + str(target) + ", readback=" + str(ctrl.global_position))
	if _has_look_at:
		_face_trader(ctrl, _look_at)
	_monitor_placement(target, ctrl)


# Spawn() leaves controller.global_rotation.y at randf_range(0, 360) and the
# view camera is a descendant of the controller, so the player ends up staring
# in a random direction. The camera inherits controller yaw plus the head's
# own mouse-look yaw, so both have to be dealt with.
func _face_trader(ctrl: Node3D, trader_pos: Vector3) -> void:
	var d := trader_pos - ctrl.global_position
	d.y = 0.0
	if d.length() < 0.01:
		_log("face: trader too close, yaw untouched")
		return
	var yaw := atan2(-d.x, -d.z)
	var r := ctrl.global_rotation
	ctrl.global_rotation = Vector3(r.x, yaw, r.z)
	var head = ctrl.get("head")
	var zeroed := false
	if head is Node3D:
		(head as Node3D).rotation.y = 0.0
		zeroed = true
	_log("face: yaw=" + str(yaw) + " to " + str(trader_pos) + ", head_yaw_zeroed=" + str(zeroed))


func _monitor_placement(target: Vector3, ctrl: Node) -> void:
	for step in [0.1, 0.35, 1.0, 3.0]:
		await get_tree().create_timer(step, true, false, true).timeout
		if not is_instance_valid(ctrl):
			_log("monitor: controller became invalid")
			return
		var now: Vector3 = ctrl.global_position
		var drift := now - target
		var vel = ctrl.get("velocity")
		_log("monitor +" + str(step) + "s: pos=" + str(now) + " drift=" + str(drift) + " vel=" + str(vel))
		if drift.length() > 0.5:
			_log("monitor +" + str(step) + "s: DRIFTED from target, something else owns position")
			return
