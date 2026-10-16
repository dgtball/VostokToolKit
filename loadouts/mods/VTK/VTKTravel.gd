extends Node
const Paths = preload("res://mods/VTK/VTKPaths.gd")
const Log = preload("res://mods/VTK/VTKLog.gd")
const GAME_DATA_RES := Paths.GAME_DATA
const CONTROLLER_PATH := Paths.CONTROLLER
const LOADER_PATH := Paths.LOADER
const SCENE_WAIT_FRAMES := 600
# Верхние границы ожиданий телепорта: кадры на вход/выход из кэширования карты
# и паузы после смены сцены. Ждём по флагу game_data.isCaching, а не по событию
# загрузчика; лимиты не дают зависнуть, если флаг не придёт.
const CACHE_ENTER_WAIT_FRAMES := 180
const CACHE_DRAIN_WAIT_FRAMES := 1800
const SCENE_SETTLE_SEC := 0.1
const MAP_SETTLE_SEC := 0.35
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
var _look_at: Vector3 = Vector3.ZERO
var _has_look_at: bool = false


func _ready() -> void:
	game_data = load(GAME_DATA_RES)
	process_mode = Node.PROCESS_MODE_ALWAYS


func travel_to_map(map_name: String) -> void:
	if not MAPS.has(map_name):
		_message("Unknown map: " + map_name, Color.RED)
		return
	_teleport_internal(map_name, null)


func travel_to_shelter(shelter_name: String) -> void:
	if not SHELTERS.has(shelter_name):
		_message("Unknown shelter: " + shelter_name, Color.RED)
		return
	if unlocked_only and not is_shelter_unlocked(shelter_name):
		_message("Shelter not unlocked yet: " + shelter_name, Color.RED)
		return
	_teleport_internal(shelter_name, null)


func is_shelter_unlocked(shelter_name: String) -> bool:
	var loader := _loader()
	if loader != null and loader.has_method("CheckShelterState"):
		return bool(loader.CheckShelterState(shelter_name))
	return false


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
		_message("Teleport already in progress", Color.YELLOW)
		return
	if game_data != null and bool(game_data.get("tutorial")):
		_message("Teleport unavailable in the tutorial", Color.RED)
		return
	var loader := _loader()
	if loader == null or not loader.has_method("LoadScene"):
		_message("Scene loader not found", Color.RED)
		return
	_has_look_at = false
	_busy = true
	var actual_current := _current_map_name()
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
	var hooks := _hooks()
	var wait_hook := hooks != null and hooks.has_signal("travel_arrived")
	var arrived_flag := [false]
	var cb := func(): arrived_flag[0] = true
	if wait_hook:
		hooks.connect("travel_arrived", cb)
	loader.LoadScene(target_map)
	if not await _wait_scene_change(prev_id):
		if wait_hook:
			hooks.disconnect("travel_arrived", cb)
		_busy = false
		_message("Scene failed to load: " + target_map, Color.RED)
		return
	var arrived := true
	if wait_hook:
		var guard := 0
		while not arrived_flag[0] and guard < SCENE_WAIT_FRAMES:
			await get_tree().process_frame
			guard += 1
		hooks.disconnect("travel_arrived", cb)
		if arrived_flag[0]:
			arrived = is_inside_tree()
		else:
			arrived = await _await_map_ready()
	else:
		arrived = await _await_map_ready()
	if not arrived:
		_busy = false
		var label0 := dest_label if dest_label == "" else " (" + dest_label + ")"
		_message("Map " + target_map + " failed to load" + label0, Color.RED)
		return
	if loader.has_method("SaveWorld"):
		loader.SaveWorld()
	var point: Variant = _resolve_final_offset(final_offset)
	if point is Vector3:
		_place_player(point)
	elif final_offset is Callable:
		_busy = false
		_message("Trader not found: " + dest_label + " (you are on " + target_map + ")", Color.RED)
		return
	_busy = false
	var dest := target_map if dest_label == "" else target_map + " (" + dest_label + ")"
	_message("Teleport: " + dest, Color.GREEN)


func _hooks() -> Node:
	var ui := get_node_or_null(Paths.UI_ROOT)
	if ui == null:
		# Телепорт без хуков работает, но теряет авто-экип и синхронизацию
		# сейвов. Раньше промах гасил обе функции без следа.
		Log.warn_once(Paths.UI_ROOT, "travel: VTKUI autoload missing")
		return null
	var h := ui.get_node_or_null(Paths.HOOKS)
	if h == null:
		Log.warn_once(Paths.UI_ROOT + "/" + Paths.HOOKS, "travel: VTKHooks missing")
	return h


func _save_before_transition(target_map: String, loader: Node) -> void:
	if loader == null or not loader.has_method("SaveCharacter"):
		return
	var iface := get_node_or_null(Paths.INTERFACE)
	if iface == null:
		return
	loader.call("SaveCharacter")
	# Мир (Simulation.*) сохраняем ДО смены сцены: Compiler.Spawn при загрузке
	# карты зовёт Loader.LoadWorld(), а тот восстанавливает user://World.tres.
	# Без этой записи телепорт откатывал время к последнему сохранению мира
	# (обычный переход так делает сам — SAVE: World перед LoadScene).
	if loader.has_method("SaveWorld"):
		loader.call("SaveWorld")


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
			await get_tree().create_timer(SCENE_SETTLE_SEC, false).timeout
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
	# Свою панель ищем по реестру, а не через get_parent(): контракт - публичный
	# set_panel_open на автолоаде, а не приватный метод, до которого едут через
	# того, кого сейчас случайно повесили на ноду.
	var mod_ui := get_node_or_null(Paths.UI_ROOT)
	if mod_ui != null and is_instance_valid(mod_ui) and mod_ui.has_method("set_panel_open"):
		mod_ui.call("set_panel_open", false)
	var ui := get_node_or_null(Paths.UI)
	var iface := get_node_or_null(Paths.INTERFACE)
	if iface != null and iface.has_method("Close"):
		iface.call("Close")
	elif ui != null and ui.has_method("ToggleInterface"):
		ui.call("ToggleInterface")
	# Клик по кнопке телепорта обрабатывается в том же кадре, что и ванильный
	# Interface._physics_process, где ввод читается ДО обновления hover
	# (блок ввода Interface.gd:290-322 стоит раньше вызова Hover() :346).
	# С ещё живыми hoverItem/hoverGrid ваниль зовёт Grab() (:317) -> Pick/
	# Unequip наведённого предмета ровно при смене сцены; HideAllUI() (:587)
	# чистит только панели и hover не трогает. Зануляем hover здесь, пока
	# клик ещё "свежий" и Hover() его не перетёр.
	if iface != null:
		iface.set("hoverItem", null)
		iface.set("hoverGrid", null)
		iface.set("hoverSlot", null)
		iface.set("canUnequip", false)
	if game_data != null:
		game_data.set("interface", false)


func _message(text: String, color: Color) -> void:
	var loader := _loader()
	if loader != null and loader.has_method("Message"):
		loader.call("Message", text, color)
		return
	Log.log("[VTK] " + text)


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
	var facing := _node_forward(node)
	_look_at = anchor
	_has_look_at = true
	var ctrl2 := _controller()
	if ctrl2 == null:
		var raw2 := anchor + facing * TRADER_STAND_DISTANCE
		return raw2
	var space := ctrl2.get_world_3d().direct_space_state
	var exclude: Array = [ctrl2.get_rid()]
	if node != null:
		_collect_rids(node, exclude)
	var stand_dir := -facing
	for dist in [TRADER_STAND_DISTANCE, 2.5, 3.0, 1.5]:
		var cand: Vector3 = anchor + stand_dir * float(dist)
		var hit := _ray_floor_hit(space, exclude, cand)
		if not hit.is_empty():
			var hp: Vector3 = hit["position"]
			return hp
	for step in range(12):
		var ang := TAU * float(step) / 12.0
		var cand2: Vector3 = anchor + Vector3(cos(ang), 0.0, sin(ang)) * TRADER_STAND_DISTANCE
		var hit2 := _ray_floor_hit(space, exclude, cand2)
		if not hit2.is_empty():
			var hp2: Vector3 = hit2["position"]
			return hp2
	return anchor + stand_dir * TRADER_STAND_DISTANCE


func _ray_floor_hit(space: PhysicsDirectSpaceState3D, exclude: Array, point: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(point + Vector3(0.0, FLOOR_PROBE_UP, 0.0), point + Vector3(0.0, -FLOOR_PROBE_DOWN, 0.0))
	q.exclude = exclude
	return space.intersect_ray(q)


func _collect_rids(node: Node, out: Array) -> void:
	for ch in node.get_children():
		if ch is CollisionObject3D:
			out.append((ch as CollisionObject3D).get_rid())
		else:
			_collect_rids(ch, out)


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
	while guard < CACHE_ENTER_WAIT_FRAMES and game_data != null and not bool(game_data.get("isCaching")):
		await get_tree().process_frame
		guard += 1
	guard = 0
	while guard < CACHE_DRAIN_WAIT_FRAMES and game_data != null and bool(game_data.get("isCaching")):
		await get_tree().process_frame
		guard += 1
	var caching := game_data != null and bool(game_data.get("isCaching"))
	if caching:
		return false
	await get_tree().create_timer(MAP_SETTLE_SEC, true, false, true).timeout
	return is_inside_tree()


func _place_player(target: Vector3) -> void:
	var ctrl := _controller()
	if ctrl == null:
		return
	ctrl.global_position = target
	ctrl.set("velocity", Vector3.ZERO)
	if _has_look_at:
		_face_trader(ctrl, _look_at)


# Spawn() leaves controller.global_rotation.y at randf_range(0, 360) and the
# view camera is a descendant of the controller, so the player ends up staring
# in a random direction. The camera inherits controller yaw plus the head's
# own mouse-look yaw, so both have to be dealt with.
func _face_trader(ctrl: Node3D, trader_pos: Vector3) -> void:
	var d := trader_pos - ctrl.global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	var yaw := atan2(-d.x, -d.z)
	var r := ctrl.global_rotation
	ctrl.global_rotation = Vector3(r.x, yaw, r.z)
	var head = ctrl.get("head")
	if head is Node3D:
		(head as Node3D).rotation.y = 0.0

