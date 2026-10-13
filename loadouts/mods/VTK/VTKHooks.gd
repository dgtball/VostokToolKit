extends Node
const Paths = preload("res://mods/VTK/VTKPaths.gd")
const Log = preload("res://mods/VTK/VTKLog.gd")

var _registered: bool = false
var _lib = null
var _kill_count: int = 0
var _player_hits: Dictionary = {}
var _hooks_kc: Array = []
var _hooks_notes: Array = []
var _hooks_deposits: Array = []
var _hooks_equip: Array = []
var _hooks_context: Array = []

const KC = preload("res://mods/VTK/VTKKillCounter.gd")
const Notes = preload("res://mods/VTK/VTKNotes.gd")
const VTKDeposits = preload("res://mods/VTK/VTKDeposits.gd")
const VTKData = preload("res://mods/VTK/VTKData.gd")
const EquipFlow = preload("res://mods/VTK/VTKEquip.gd")
const Loc = preload("res://mods/VTK/VTKLoc.gd")
const HIT_WINDOW_MSEC := 15000
const SEEN_DEATHS_TTL_MSEC := 600000

# Авто-экипировка: пофреймовый diff детей inventoryGrid вместо хрупких
# add-item хуков (арности их post-колбэков не восстановимы из .gdc). Интерфейс
# при загрузке мира и при возврате из сохранения создаётся заново — это видно
# по смене instance_id и включает окно оседания (ARM), чтобы стартовое
# снаряжение не разъехалось по слотам.
const EQUIP_ARM_MS := 6000
const EQUIP_BULK_LIMIT := 10
const EQUIP_OWN_WINDOW_MS := 1500
# Обход inventoryGrid - это пофреймовая работа; 100 мс незаметны для игрока и
# в разы дешевле. Оседание (ARM) и окно собственных операций заметно длиннее.
const EQUIP_POLL_MS := 100
# Игра пересоздаёт узел предмета при переносе (новый instance_id) и заводит
# новые узлы при сплите, поэтому diff по id не отличает подбор от
# перекладывания внутри инвентаря. Отличаем по количеству: подбор из мира
# УВЕЛИЧИВАЕТ суммарное количество типа (инвентарь + экипировка), а перенос/
# сплит/снятие его сохраняют. Свежий узел экипируем только если его тип подрос.
# Падение базы (перенос через промежуточный слой, пересоздание узла) фиксируем
# не сразу, а если продержалось dip-окно: так возврат предмета не читается как
# подбор, и не нужен признак itemDragged (в игре он не гаснет).
const EQUIP_DIP_MS := 500
var _equip_on: bool = true
var _pickup_pending: int = 0
var _equip_debug: bool = false
var _equip_armed_at: int = 0
var _equip_poll_at: int = 0
var _equip_iface_id: int = 0
# Суммарное количество по типу (itemData) — база дельты. Понижение откладываем:
# _equip_low[k] = [количество, время первого наблюдения].
var _equip_qty: Dictionary = {}
var _equip_low: Dictionary = {}
# Имя типа для отладочного вывода (перезаполняется каждый поллинг).
var _equip_names: Dictionary = {}
# Интерфейс живёт до выгрузки карты; путь резолвим один раз, не каждый кадр.
var _iface_cache = null

signal kill_event(ev: Dictionary)

var _last_damager: Dictionary = {}
var _seen_deaths: Dictionary = {}

var _death_is_ironman: bool = false

# The death screen ships its own "Load Game" button: live in a normal run,
# greyed out under permadeath. We borrow that button instead of stacking our own
# panel on top of it, and hand the original text/state/connections back when the
# screen goes away.
var _death_load_btn = null
var _death_load_bound = null
var _death_load_orig_text: String = ""
var _death_load_orig_disabled: bool = false
var _death_load_orig_conns: Array = []

# Death.tscn is mounted asynchronously behind Loader's FadeInLoading, so the button
# may take a few frames to appear. Give it up to DEATH_FIND_TIMEOUT_MS, then
# leave the vanilla screen alone (single warning) instead of stacking our own UI.
const DEATH_FIND_TIMEOUT_MS := 20000
var _death_find_since: int = 0
var _death_gave_up: bool = false
var _death_dump_at: int = 0
var _death_probe_at: int = 0
# Поиск сцены Death - это обращение к дереву; в живом рейде она всегда
# отсутствует. Держим результат 200 мс, чтобы не искать её каждый кадр.
const DEATH_SCENE_POLL_MS := 200
var _death_scene_at: int = 0
var _death_scene_hit: bool = false

# The death screen was never handled at all: the whole handler rode the
# controller-_physics_process hook, and Controller is a node inside /root/Map,
# so it was freed with the map and _lib._caller went invalid before the Death
# scene even mounted. Not one line of output reached the log. Poll from our own
# _process instead -- this node lives on the autoload and outlives any map.
var _gd_node = null
var _death_latched: bool = false
var _gd_missing_logged: bool = false

# Ironman respawn drops you somewhere random out of these instead of always
# Highway, so a death run can't be re-learned as one fixed route.
const IRONMAN_MAPS := ["Highway", "School", "Outpost", "Apartments"]

func _ready() -> void:
	name = "VTKHooks"
	Log.log("[VTK] Hooks node ready, RTVModLib=" + str(Engine.has_meta("RTVModLib")))

func get_kill_count() -> int:
	return _kill_count

func reset_kills() -> void:
	_kill_count = 0
	_player_hits.clear()
	_last_damager.clear()
	_seen_deaths.clear()

func _process(_delta: float) -> void:
	if not _registered:
		_try_register()
	_poll_death()

func set_equip_enabled(on: bool) -> void:
	_equip_on = on

func set_equip_debug(on: bool) -> void:
	_equip_debug = on

const GAME_DATA_RES := Paths.GAME_DATA

func _resolve_gamedata() -> Variant:
	if _gd_node != null and is_instance_valid(_gd_node):
		return _gd_node
	var direct = load(GAME_DATA_RES) if ResourceLoader.exists(GAME_DATA_RES) else null
	if direct != null:
		_gd_node = direct
		return _gd_node
	# Fall back to whatever exposes the permadeath flags.
	for c in get_tree().root.get_children():
		if "isDead" in c and "permadeath" in c:
			_gd_node = c
			Log.log("[VTK] GameData resolved by flag scan: " + str(c.name) + " (" + c.get_class() + ")")
			return _gd_node
	return null

func _poll_death() -> void:
	var gd = _resolve_gamedata()
	if gd == null and not _death_latched:
		if not _gd_missing_logged:
			_gd_missing_logged = true
			Log.log("[VTK] poll: GameData resource unavailable; death screen idle")
		return
	var is_dead := _death_latched
	var is_ironman := _death_latched
	if gd != null:
		# The game rewrites both flags the moment the Death scene mounts, so
		# neither can carry the screen on its own. Read the mode on the first
		# frame that reports it, then keep serving the screen off the mounted
		# scene until it goes away again.
		var dead_scene := _death_scene_present()
		is_dead = bool(gd.get("isDead", false)) or dead_scene
		is_ironman = bool(gd.get("permadeath", false)) or (_death_latched and dead_scene)
		if is_dead and is_ironman and not _death_latched:
			# Latch it: the flags live on the map's GameData, which is torn down
			# on death, so the next frame may have no source left to read.
			_death_latched = true
			Log.log("[VTK] poll: death+ironman latched from " + str(gd.get_class()) + " isDead=" + str(bool(gd.get("isDead", false))) + " permadeath=" + str(bool(gd.get("permadeath", false))) + " death_scene=" + str(dead_scene))
		elif not is_dead:
			# Back in a live run (or on the main menu): release the latch so a
			# missing GameData later cannot resurrect the death screen.
			_death_latched = false
			_gd_missing_logged = false
		if _death_latched:
			var pnow := Time.get_ticks_msec()
			if pnow - _death_probe_at > 1000:
				_death_probe_at = pnow
				Log.log("[VTK] poll: raw isDead=" + str(gd.get("isDead", false)) + " permadeath=" + str(gd.get("permadeath", false)) + " death_scene=" + str(dead_scene))
	_handle_death_screen(gd, is_dead, is_ironman)

func _try_register() -> void:
	if Engine.has_meta("RTVModLib"):
		_lib = Engine.get_meta("RTVModLib")
		if _lib.get("_is_ready"):
			_do_register()
		else:
			if not _lib.frameworks_ready.is_connected(_do_register):
				_lib.frameworks_ready.connect(_do_register)
	else:
		var mml = get_node_or_null("/root/RTVModLib")
		if mml == null:
			mml = get_node_or_null("/root/MML")
		if mml and mml.has_method("hook"):
			_lib = mml
			_do_register()

func _do_register() -> void:
	if _registered:
		return
	if _lib == null and Engine.has_meta("RTVModLib"):
		_lib = Engine.get_meta("RTVModLib")
	if _lib == null or not _lib.has_method("hook"):
		Log.log("[VTK] Cannot register hooks: no RTVModLib")
		return
	Log.log("[VTK] Registering hooks...")
	_lib.hook("controller-_physics_process-post", _on_controller_process)
	_hooks_kc.append(_lib.hook("ai-weapondamage-pre", _on_ai_weapon_damage))
	_hooks_kc.append(_lib.hook("ai-explosiondamage-pre", _on_ai_explosion))
	_hooks_kc.append(_lib.hook("ai-death-pre", _on_ai_death))
	_hooks_notes.append(_lib.hook("trader-completetask-post", _on_task_completed))
	_hooks_notes.append(_lib.hook("interface-initializenotes-post", _on_notes_rendered))
	_hooks_deposits.append(_lib.hook("interface-initializetasks-post", _on_tasks_rendered))
	_hooks_deposits.append(_lib.hook("interface-startinput-post", _on_tasks_startinput))
	_hooks_deposits.append(_lib.hook("task-_on_complete_pressed", _on_task_complete_pressed))
	_lib.hook("loader-newgame-post", _on_newgame_post)
	_hooks_equip.append(_lib.hook("loader-loadcharacter-post", _on_loadcharacter_post))
	_hooks_context.append(_lib.hook("context-update-post", _on_context_update_post))
	_hooks_equip.append(_lib.hook("pickup-interact-pre", _on_pickup_interact_pre))
	_hooks_equip.append(_lib.hook("pickup-interact-post", _on_pickup_interact_post))
	_registered = true
	Log.log("[VTK] Per-frame hooks registered (" + str(_hooks_kc.size() + _hooks_notes.size() + _hooks_deposits.size() + _hooks_equip.size() + _hooks_context.size() + 1) + " hooks)")

# Late Start (and any mod that saves the world from its own loader-newgame-post
# handler) writes world.difficulty from gameData.difficulty. That value is stale:
# the new-game menu passes difficulty to Loader.NewGame as an argument but never
# stores it in gameData, whose difficulty is only assigned by Loader.LoadWorld
# from a previous save. Left alone, a difficulty-3 run is persisted back as 1 and
# LoadWorld no longer restores permadeath. Sync the live value and patch the saved
# world so the chosen difficulty survives regardless of hook order.
func _on_newgame_post(difficulty, _season) -> void:
	var diff := int(difficulty)
	var gd = _resolve_gamedata()
	if gd != null:
		gd.set("difficulty", diff)
		if diff == 3:
			gd.set("permadeath", true)
	patch_world_difficulty(diff)
	Log.log("[VTK] newgame-post: difficulty=" + str(diff))

func patch_world_difficulty(diff: int) -> void:
	var path := "user://World.tres"
	if not FileAccess.file_exists(path):
		return
	var world = load(path)
	if world == null or world.get("difficulty") == null:
		return
	world.set("difficulty", diff)
	ResourceSaver.save(world, path)

func _on_loadcharacter_post() -> void:
	Log.log("[VTK] loadcharacter-post")

func _arm_equip(delay_ms: int) -> void:
	_equip_armed_at = Time.get_ticks_msec() + delay_ms

# --- Контекстное меню предмета: кнопка Delete ------------------------------
# Пост-хук Context.Update добавляет кнопку Delete, которая мгновенно удаляет
# весь стак через ванильный Interface.ContextDestroy() -- та же операция, что
# и hold-to-Destroy, но без удержания. Кнопка живёт в Panel/Margin/Buttons и
# пере-показывается после каждого Update, потому что сам ванильный Update в
# начале прячет всех детей контейнера. Показываем только для предметов в гриде
# (contextGrid != null), как и ванильный ContextDestroy; в декоре не прячем.
func _on_context_update_post(_slot_data) -> void:
	var ctx = _lib._caller if _lib else null
	if ctx == null or not is_instance_valid(ctx):
		return
	var buttons = ctx.get_node_or_null("Panel/Margin/Buttons")
	if buttons == null or not (buttons is Node):
		return
	var btn := _find_context_delete_button(buttons)
	if btn == null:
		btn = _make_context_delete_button(ctx, buttons)
	if btn == null:
		return
	var iface = _context_interface(ctx)
	btn.visible = iface != null and iface.get("contextGrid") != null

func _context_interface(ctx):
	var iface = ctx.get("interface") if ctx != null else null
	if iface == null:
		iface = _resolve_interface()
	return iface

func _find_context_delete_button(buttons) -> Button:
	var b = buttons.get_node_or_null("VTKDelete")
	return b if (b != null and b is Button) else null

func _make_context_delete_button(ctx, buttons) -> Button:
	var btn := Button.new()
	btn.name = "VTKDelete"
	btn.text = "Delete"
	btn.add_theme_font_size_override("font_size", _sibling_button_font_size(buttons))
	btn.pressed.connect(_on_context_delete_pressed.bind(ctx))
	buttons.add_child(btn)
	return btn

# Ванильные кнопки несут персональный theme_override_font_sizes/font_size (12),
# а не общий для темы Button; новый Button унаследовал бы дефолт темы (16).
# Берём размер у соседа-ванилы, пропуская наши VTK*-кнопки, и не привязываемся
# к жёсткому числу, если игра его сменит.
func _sibling_button_font_size(buttons) -> int:
	for child in buttons.get_children():
		if child is Button and not str(child.name).begins_with("VTK"):
			return child.get_theme_font_size("font_size")
	return 12

func _on_context_delete_pressed(ctx) -> void:
	var iface = _context_interface(ctx)
	if iface == null or not is_instance_valid(iface):
		return
	if iface.get("visible") != true:
		return
	if iface.get("contextGrid") == null or iface.get("contextItem") == null:
		return
	iface.call("ContextDestroy")

func _resolve_interface() -> Node:
	if _iface_cache != null and is_instance_valid(_iface_cache):
		return _iface_cache
	var root = get_tree().root
	if root == null:
		return null
	_iface_cache = root.get_node_or_null(Paths.INTERFACE)
	return _iface_cache

# База дельты: рост фиксируем сразу (подбор), падение — только если продержалось
# EQUIP_DIP_MS. Это гасит промежуточные кадры переноса/пересоздания узла, когда
# предмет на миг не виден ни инвентарю, ни экипировке.
func _update_equip_qty(now_qty: Dictionary, t: int) -> void:
	for k in _equip_qty.keys():
		if not now_qty.has(k):
			now_qty[k] = 0
	for k in now_qty.keys():
		var cur := int(now_qty.get(k, 0))
		var base := int(_equip_qty.get(k, 0))
		if cur >= base:
			_equip_qty[k] = cur
			_equip_low.erase(k)
			continue
		var low = _equip_low.get(k)
		if low == null or int(low[0]) != cur:
			_equip_low[k] = [cur, t]
		elif t - int(low[1]) >= EQUIP_DIP_MS:
			_equip_qty[k] = cur
			_equip_low.erase(k)
			Log.log("[VTK] equip: dip confirmed '" + _type_name(k) + "' -> " + str(cur))

# Тип предмета как ключ состояния: ресурс-предмет игры общий (Database), поэтому
# instance_id стабилен для одного и того же предмета; словари и прочие значения
# хешируются по содержимому (см. headless-тест).
func _item_type_key(res) -> int:
	if res == null:
		return 0
	if res is Object:
		if not is_instance_valid(res):
			return 0
		return res.get_instance_id()
	return hash(res)

# Количество одного предмета: стакающиеся хранят реальное число, нестакающиеся
# игра пишет с amount = 0 — считаем такой узел за единицу.
func _node_qty(node) -> int:
	var sd = node.get("slotData")
	if sd == null:
		return 0
	var amt := int(sd.get("amount"))
	return amt if amt > 0 else 1

func _add_node_qty(out: Dictionary, node) -> void:
	var sd = node.get("slotData")
	if sd == null:
		return
	var r = sd.get("itemData")
	if r == null:
		return
	var k := _item_type_key(r)
	out[k] = int(out.get(k, 0)) + _node_qty(node)
	_equip_names[k] = str(r.get("name"))

func _type_name(k) -> String:
	return str(_equip_names.get(k, k))

func _collect_equip_qty(node, out: Dictionary, depth: int) -> void:
	if node == null or not is_instance_valid(node) or depth > 3:
		return
	for c in node.get_children():
		if is_instance_valid(c):
			_add_node_qty(out, c)
			_collect_equip_qty(c, out, depth + 1)

# Авто-экип по событию подбора: Pickup.Interact удалил узел, значит предмет
# лёг в инвентарь. Переносим в слот ровно подобранное количество (не больше
# свободного места), отложенное в инвентаре не трогаем.
func _on_pickup_interact_pre() -> void:
	_pickup_pending = 0
	if not _equip_on or _lib == null:
		return
	var p = _lib._caller
	if p == null or not is_instance_valid(p):
		return
	var sd = p.get("slotData")
	if sd == null:
		return
	var res = sd.get("itemData")
	if res == null or not EquipFlow.is_equipment(res):
		return
	var amt := int(sd.get("amount"))
	_pickup_pending = amt if amt > 0 else 1

func _on_pickup_interact_post() -> void:
	var picked := _pickup_pending
	_pickup_pending = 0
	if not _equip_on or picked <= 0 or _lib == null:
		return
	var p = _lib._caller
	# Подбор удался только если ванильный Interact вызвал queue_free.
	if p == null or not is_instance_valid(p) or not p.is_queued_for_deletion():
		return
	var sd = p.get("slotData")
	if sd == null:
		return
	var res = sd.get("itemData")
	if res == null or not EquipFlow.is_equipment(res):
		return
	var iface = p.get("interface")
	if iface == null or not is_instance_valid(iface):
		iface = _resolve_interface()
	if iface == null or not is_instance_valid(iface):
		return
	var ig = iface.get("inventoryGrid")
	if ig == null or not is_instance_valid(ig):
		return
	_equip_picked(iface, ig, res, picked)

func _equip_picked(iface, ig, res, picked: int) -> void:
	if picked <= 0:
		return
	var equip_root = iface.get("equipment")
	if equip_root == null or not is_instance_valid(equip_root):
		return
	var node = _find_inventory_node(ig, res)
	if node == null:
		return
	var free_sl = VTKData._find_free_slot(equip_root, EquipFlow.wanted_slots(res), 0)
	if free_sl != null:
		_equip_move(iface, ig, node, free_sl, picked)
		return
	var occ_sl = VTKData._find_occupied_slot(equip_root, res, 0)
	if occ_sl == null:
		Log.log("[VTK] equip: skip '" + str(res.get("name")) + "' (no free/occupied slot)")
		return
	var occ = VTKData._slot_item(occ_sl)
	if occ == null:
		return
	var occ_sd = occ.get("slotData")
	if occ_sd == null:
		return
	if EquipFlow.decide(res, occ_sd.get("itemData")) != "merge":
		Log.log("[VTK] equip: skip '" + str(res.get("name")) + "' (no merge)")
		return
	_merge_picked(iface, ig, node, occ, occ_sd, res, picked)

# Узел инвентаря того же предмета с наибольшим количеством (после подбора игра
# могла доложить подобранное в уже лежащий стек).
func _find_inventory_node(ig, res) -> Node:
	if ig == null or not is_instance_valid(ig):
		return null
	var best: Node = null
	var best_amt := -1
	for c in ig.get_children():
		if not is_instance_valid(c):
			continue
		var sd = c.get("slotData")
		if sd == null:
			continue
		if not EquipFlow.same_item(res, sd.get("itemData")):
			continue
		var amt := int(sd.get("amount"))
		if amt > best_amt:
			best_amt = amt
			best = c
	return best

func _equip_move(iface, ig, node, sl, picked: int) -> void:
	var sd = node.get("slotData")
	if sd == null:
		return
	var res = sd.get("itemData")
	var moved := EquipFlow.equip_move(picked, 0, int(res.get("maxAmount", 0)))
	if moved <= 0:
		return
	var amt := int(sd.get("amount"))
	var have := amt if amt > 0 else 1
	if moved >= have:
		_do_equip_move(iface, ig, node, sl)
		return
	# Часть узла: в слот уезжает moved, остаток возвращаем в инвентарь на
	# освободившуюся (после переноса) клетку.
	var leftover := have - moved
	sd.set("amount", moved)
	if node.has_method("UpdateDetails"):
		node.UpdateDetails()
	_do_equip_move(iface, ig, node, sl)
	var new_sd = SlotData.new()
	new_sd.itemData = res
	new_sd.amount = leftover
	if not iface.AutoStack(new_sd, ig):
		iface.Create(new_sd, ig, true)

func _do_equip_move(iface, ig, node, sl) -> void:
	if ig != null and ig.has_method("Pick"):
		ig.Pick(node)
	if iface.has_method("Equip"):
		iface.Equip(node, sl)
	if iface.has_method("PlayEquip"):
		iface.PlayEquip()
	if iface.has_method("UpdateStats"):
		iface.UpdateStats(true)
	Log.log("[VTK] equip: moved item -> " + str(sl.name))

func _merge_picked(iface, ig, node, occ, occ_sd, res, picked: int) -> void:
	var occ_amt := int(occ_sd.get("amount"))
	var moved := EquipFlow.equip_move(picked, occ_amt, int(res.get("maxAmount", 0)))
	if moved <= 0:
		return
	occ_sd.set("amount", VTKData._whole(float(occ_amt) + float(moved)))
	var sd = node.get("slotData")
	var amt := int(sd.get("amount"))
	var have := amt if amt > 0 else 1
	var leftover := have - moved
	if leftover <= 0:
		if ig != null and ig.has_method("Pick"):
			ig.Pick(node)
		node.queue_free()
	else:
		sd.set("amount", leftover)
		if node.has_method("UpdateDetails"):
			node.UpdateDetails()
	if occ.has_method("UpdateDetails"):
		occ.UpdateDetails()
	if iface.has_method("UpdateStats"):
		iface.UpdateStats(true)
	Log.log("[VTK] equip: merged " + str(moved) + " into stack (left " + str(leftover) + ")")

func _on_ai_weapon_damage(_hitbox, _damage, _vector, id) -> void:
	var victim_ai = _lib._caller if _lib else null
	if victim_ai != null and is_instance_valid(victim_ai) and victim_ai is Node:
		var rec := {
			"t": Time.get_ticks_msec(),
			"hitbox": str(_hitbox),
			"player": false,
			"attacker": null,
			"weapon": "",
		}
		if id != null and is_instance_valid(id) and id is Node:
			if id.is_in_group("Player"):
				rec["player"] = true
				rec["weapon"] = _player_weapon_name()
			else:
				# Игра отдаёт атакующего как ID-маркер, а не агента:
				# kind/display/weapon живут на агенте-предке.
				var atk := _agent_root(id)
				rec["attacker"] = atk
				rec["weapon"] = _weapon_name_of(atk)
		_last_damager[victim_ai.get_instance_id()] = rec
	if id == null or not is_instance_valid(id):
		return
	if not id.is_in_group("Player"):
		return
	var ai = _lib._caller if _lib else null
	if ai == null or not is_instance_valid(ai):
		return
	_player_hits[ai.get_instance_id()] = Time.get_ticks_msec()

# Гранаты и взрывы идут мимо ai-weapondamage (probe Task 1, п.4):
# ai-explosiondamage(_direction, id), caller=жертва, id=Area бросившего
# (grpP=true). Без записи здесь взрывной килл не попадает ни в счётчик
# (_player_hits), ни в ленту (_last_damager).
func _on_ai_explosion(_direction, id) -> void:
	var victim_ai = _lib._caller if _lib else null
	if victim_ai == null or not is_instance_valid(victim_ai) or not (victim_ai is Node):
		return
	var rec := {
		"t": Time.get_ticks_msec(),
		"hitbox": "",
		"player": false,
		"attacker": null,
		"weapon": "",
		"grenade": true,
	}
	if id != null and is_instance_valid(id) and id is Node:
		if id.is_in_group("Player"):
			rec["player"] = true
			_player_hits[victim_ai.get_instance_id()] = Time.get_ticks_msec()
		else:
			rec["attacker"] = _agent_root(id)
	_last_damager[victim_ai.get_instance_id()] = rec

func _on_ai_death(_direction, _force) -> void:
	var ai = _lib._caller if _lib else null
	if ai == null or not is_instance_valid(ai):
		return
	var iid = ai.get_instance_id()
	var now = Time.get_ticks_msec()
	if _player_hits.has(iid) and now - int(_player_hits[iid]) < 15000:
		_kill_count += 1
	_player_hits.erase(iid)
	_emit_kill_event(_direction)

func _emit_kill_event(direction) -> void:
	var ai = _lib._caller if _lib else null
	if ai == null or not is_instance_valid(ai) or not (ai is Node):
		return
	var iid = ai.get_instance_id()
	if _seen_deaths.has(iid):
		return
	_seen_deaths[iid] = Time.get_ticks_msec()
	var now := Time.get_ticks_msec()
	var killer_kind := ""
	var killer_name := ""
	var weapon := ""
	var headshot := false
	var grenade := false
	var rec = _last_damager.get(iid, null)
	if rec != null and now - int(rec["t"]) <= HIT_WINDOW_MSEC:
		weapon = str(rec["weapon"])
		headshot = str(rec["hitbox"]).to_lower() == "head"
		if bool(rec["player"]):
			killer_kind = "player"
			killer_name = "Player"
		else:
			var atk = rec.get("attacker")
			if atk != null and is_instance_valid(atk) and atk is Node:
				killer_kind = KC.agent_kind(atk)
				if killer_kind == "":
					killer_kind = "enemy"
				killer_name = KC.agent_display_name(atk)
		grenade = bool(rec.get("grenade", false)) or _is_grenade(weapon)
	if killer_kind == "" and _direction_is_player(direction):
		killer_kind = "player"
		killer_name = "Player"
		weapon = _player_weapon_name()
		grenade = _is_grenade(weapon)
	if killer_kind == "":
		_last_damager.erase(iid)
		return
	kill_event.emit({
		"killer_kind": killer_kind,
		"killer_name": killer_name,
		"victim_kind": KC.agent_kind(ai),
		"victim_name": KC.agent_display_name(ai),
		"weapon": weapon,
		"headshot": headshot,
		"grenade": grenade,
		"t": now,
	})
	_last_damager.erase(iid)

# Имя оружия игрока: свойства GameData, затем оружие в руках у игрока.
# Список и порядок — из probe-вывода (Task 1, п.3); лишние свойства просто
# не найдутся и вернут "".
func _player_weapon_name() -> String:
	var gd = _resolve_gamedata()
	if gd != null:
		for p in ["currentWeaponName", "weaponName", "currentWeapon", "weapon", "equippedWeapon"]:
			if p in gd:
				var s := _weapon_str(gd.get(p))
				if s != "":
					return s
	var pl = get_tree().get_first_node_in_group("Player")
	if pl != null:
		for p in ["currentWeapon", "activeWeapon", "weapon", "weaponName", "equippedWeapon"]:
			if p in pl:
				var s := _weapon_str(pl.get(p))
				if s != "":
					return s
	return _rig_weapon_name()

# Ни GameData, ни узел игрока не несут имени оружия (probe, Task 1): настоящее
# оружие — WeaponRig под Camera/Manager, у него data.file (AKM, M4A1...).
func _rig_weapon_name() -> String:
	var mgr = get_tree().root.get_node_or_null(Paths.CAMERA_MANAGER)
	if mgr == null:
		return ""
	var first := ""
	for c in mgr.get_children():
		if c == null or not ("data" in c):
			continue
		var d = c.get("data")
		if d == null or not (d is Dictionary or d is Object) or not ("file" in d):
			continue
		var f := str(d.get("file")).strip_edges()
		if f == "":
			continue
		if "/" in f:
			f = f.get_file().get_basename()
		# Если ригов несколько, видимый — текущее оружие.
		if "visible" in c and c.visible:
			return f
		if first == "":
			first = f
	return first

# Атакующий приходит как ID-маркер (/root/Map/Core/Camera/ID, .../Identifier/ID):
# на нём нет ни Activate/dead, ни weapon, ни script-имени модели. Поднимаемся
# по родителям к ближайшему агенту; если агента нет — исходный узел.
func _agent_root(n: Node) -> Node:
	var cur := n
	for _i in 12:
		if KC._is_agent(cur):
			return cur
		var p := cur.get_parent()
		if p == null:
			break
		cur = p
	return n

func _weapon_name_of(n: Node) -> String:
	for p in ["currentWeaponName", "weaponName", "currentWeapon", "weapon", "equippedWeapon", "activeWeapon"]:
		if p in n:
			var s := _weapon_str(n.get(p))
			if s != "":
				return s
	return ""

# Значение свойства может быть строкой, именем или ресурсом предмета.
func _weapon_str(v) -> String:
	if v is String or v is StringName:
		return str(v).strip_edges()
	if v is Object and is_instance_valid(v) and "name" in v:
		return str(v.get("name")).strip_edges()
	return ""

# Граната: имя оружия — это предмет из папки Grenades (принадлежность по
# resource_path, как подкатегории в Picker).
func _is_grenade(weapon: String) -> bool:
	if weapon == "":
		return false
	var db = get_tree().root.get_node_or_null(Paths.DATABASE)
	if db == null or not ("master" in db):
		return false
	var master = db.get("master")
	if master == null or not ("items" in master):
		return false
	for item in master.items:
		if item == null:
			continue
		if str(item.name).strip_edges() != weapon:
			continue
		return String(item.resource_path).contains("/Grenades/")
	return false

func _direction_is_player(direction) -> bool:
	if not (direction is Vector3):
		return false
	var gd = _resolve_gamedata()
	if gd == null or not ("playerVector" in gd):
		return false
	var pv = gd.get("playerVector")
	if not (pv is Vector3):
		return false
	var a := (direction as Vector3).normalized()
	var b := (pv as Vector3).normalized()
	if a == Vector3.ZERO or b == Vector3.ZERO:
		return false
	return a.dot(b) > 0.985

func _on_controller_process(_delta: float) -> void:
	var controller = _lib._caller if _lib else null
	if not is_instance_valid(controller):
		return
	var now = Time.get_ticks_msec()
	var stale: Array = []
	for iid in _player_hits:
		if now - int(_player_hits[iid]) > 30000:
			stale.append(iid)
	for s in stale:
		_player_hits.erase(s)
	var stale_seen: Array = []
	for iid in _seen_deaths:
		if now - int(_seen_deaths[iid]) > SEEN_DEATHS_TTL_MSEC:
			stale_seen.append(iid)
	for s in stale_seen:
		_seen_deaths.erase(s)
	var stale_dmg: Array = []
	for iid in _last_damager:
		if now - int(_last_damager[iid]["t"]) > HIT_WINDOW_MSEC:
			stale_dmg.append(iid)
	for s in stale_dmg:
		_last_damager.erase(s)

# Сдача задачи во вкладке торговца: убираем её заметку из Notes сразу.
# Notes в этот момент закрыт, поэтому чистим только данные (Loader).
func _on_task_completed(task_data) -> void:
	if task_data == null:
		return
	_clear_ledger_key(task_data)
	var ldr = get_node_or_null(Paths.LOADER)
	if ldr == null or not ldr.has_method("LoadTaskNotes") or not ldr.has_method("SaveTaskNotes"):
		return
	var inst = Notes.find_note(ldr.call("LoadTaskNotes"), task_data)
	if inst != null:
		ldr.call("SaveTaskNotes", inst, false)

# Отрисовка вкладки Notes: сданные заметки убираем, у остальных меняем текст
# списка предметов на ряд иконок. Страховка для задач, сданных в обход
# Trader.CompleteTask, и заметок из сессий до установки мода.
func _on_notes_rendered(_result) -> void:
	var iface = _lib._caller if _lib else null
	if iface == null or not is_instance_valid(iface):
		return
	var list = iface.get("notesList")
	if list == null or not (list is Node):
		return
	var ldr = get_node_or_null(Paths.LOADER)
	var traders = null
	if FileAccess.file_exists(Paths.TRADER_SAVE):
		traders = load(Paths.TRADER_SAVE)
	var completed = Notes.completed_lists(traders)
	var notes = []
	if ldr != null and ldr.has_method("LoadTaskNotes"):
		notes = ldr.call("LoadTaskNotes")
	for card in list.get_children():
		if card == null or not is_instance_valid(card) or card.is_queued_for_deletion():
			continue
		var task_data = card.get("taskData")
		if task_data == null:
			continue
		if Notes.is_completed(task_data, completed):
			var note = Notes.find_note(notes, task_data)
			if note != null and ldr != null and ldr.has_method("SaveTaskNotes"):
				ldr.call("SaveTaskNotes", note, false)
			continue
		Notes.augment_note(card, _notes_cov_map(task_data))

const TRADERS_RES := Paths.TRADER_SAVE
const DEPOSITS_META := "vtk_deposits"

func _traders() -> Variant:
	if not FileAccess.file_exists(Paths.TRADER_SAVE):
		return null
	return load(Paths.TRADER_SAVE)

func _ledger() -> Dictionary:
	var traders = _traders()
	if traders == null:
		return {}
	var m = traders.get_meta("vtk_deposits", {})
	return m if typeof(m) == TYPE_DICTIONARY else {}

func _ledger_set(data: Dictionary) -> void:
	var traders = _traders()
	if traders == null:
		return
	traders.set_meta("vtk_deposits", data)
	ResourceSaver.save(traders, Paths.TRADER_SAVE)

func _key_of(task_data) -> String:
	return VTKDeposits.task_key(str(task_data.get("resource_path")), str(task_data.get("name")), str(task_data.get("trader")))

func _clear_ledger_key(task_data) -> void:
	if task_data == null:
		return
	var key := _key_of(task_data)
	var ledger := _ledger()
	if not ledger.has(key):
		return
	_ledger_set(VTKDeposits.clear_task(ledger, key))

func _live_children(grid) -> Array:
	var out: Array = []
	if grid == null or not (grid is Node):
		return out
	for c in grid.get_children():
		if c != null and is_instance_valid(c) and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _slots_from_grid(grid) -> Array:
	var entries: Array = []
	for cell in _live_children(grid):
		var file := ""
		var nm := ""
		var amount := 1
		if cell != null and is_instance_valid(cell):
			var sd = cell.get("slotData")
			if sd != null:
				var item = sd.get("itemData")
				if item != null:
					file = str(item.get("file"))
					nm = str(item.get("name"))
				amount = int(sd.get("amount", 1))
		entries.append({"file": file, "name": nm, "amount": amount})
	return VTKDeposits.normalize_slots(entries)

func _card_covered(card) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	var task_data = card.get("taskData")
	var grid = card.get("inputGrid")
	if task_data == null or grid == null or not (grid is Node):
		return false
	var slots := _slots_from_grid(grid)
	if slots.is_empty():
		return false
	var key := _key_of(task_data)
	return VTKDeposits.is_covered(VTKDeposits.coverage(_ledger(), key, slots))

# Покрытие для Notes: карточка заметки не строит ячейки inputGrid, поэтому
# берём deliver напрямую и сопоставляем с леджером по индексу (порядок deliver
# = порядок ячеек в Tasks). Считаем need так же, как Task.Initialize.
func _notes_cov_map(task_data) -> Dictionary:
	var out := {}
	if task_data == null:
		return out
	var deliver = task_data.get("deliver")
	if typeof(deliver) != TYPE_ARRAY:
		return out
	var task: Dictionary = {}
	var ledger := _ledger()
	var key := _key_of(task_data)
	if typeof(ledger.get(key)) == TYPE_DICTIONARY:
		task = ledger[key]
	for i in range(deliver.size()):
		var item = deliver[i]
		var req := 1
		if item != null:
			var da := int(item.get("defaultAmount"))
			if da >= 1 and str(item.get("subtype")) != "Magazine":
				req = da
		var dep := int(task.get(i, 0))
		if dep > req:
			dep = req
		var k := Notes.item_key(item)
		if not out.has(k):
			out[k] = {"got": 0, "need": 0}
		out[k]["need"] = int(out[k]["need"]) + req
		out[k]["got"] = int(out[k]["got"]) + dep
	return out

# Notes-панель можно держать открытой рядом с задачами: после вклада
# перерисовываем её карточку, иначе она остаётся со старым прогрессом до
# повторного открытия вкладки.
func _refresh_notes_for(iface, task_data) -> void:
	if iface == null or not is_instance_valid(iface) or task_data == null:
		return
	var list = iface.get("notesList")
	if list == null or not (list is Node):
		return
	var key := _key_of(task_data)
	var cov := _notes_cov_map(task_data)
	for card in list.get_children():
		if card == null or not is_instance_valid(card) or card.is_queued_for_deletion():
			continue
		var td = card.get("taskData")
		if td != null and _key_of(td) == key:
			Notes.augment_note(card, cov)

func _on_tasks_rendered() -> void:
	var iface = _lib._caller if _lib else null
	if iface == null or not is_instance_valid(iface):
		return
	_render_all_tasks(iface)

func _on_tasks_startinput(_target) -> void:
	var iface = _lib._caller if _lib else null
	if iface == null or not is_instance_valid(iface):
		return
	_render_all_tasks(iface)

func _render_all_tasks(iface) -> void:
	var list = iface.get("taskList")
	if list == null or not (list is Node):
		return
	for card in _live_children(list):
		_render_task_card(iface, card)

func _card_completed(card) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	var task_data = card.get("taskData")
	if task_data == null:
		return false
	return Notes.is_completed(task_data, Notes.completed_lists(_traders()))

func _render_task_card(iface, card) -> void:
	if card == null or not is_instance_valid(card):
		return
	var grid = card.get("inputGrid")
	var task_data = card.get("taskData")
	if grid == null or not (grid is Node) or task_data == null:
		return
	var btn := _find_deposit_button(card)
	if _card_completed(card):
		_clear_badges(grid)
		if btn != null:
			btn.queue_free()
		return
	var cells := _live_children(grid)
	var slots := _slots_from_grid(grid)
	if slots.is_empty():
		return
	var key := _key_of(task_data)
	var cov := VTKDeposits.coverage(_ledger(), key, slots)
	for s in cov["slots"]:
		_paint_cell(cells, s)
	if btn == null:
		btn = _make_deposit_button(card)
	if btn != null:
		btn.disabled = iface.get("inputTarget") != card or VTKDeposits.is_covered(cov)
	var cbtn = card.get_node_or_null("Margin/Elements/Buttons/Complete")
	if cbtn != null and cbtn is Button and VTKDeposits.is_covered(cov):
		cbtn.disabled = false

func _find_deposit_button(card) -> Button:
	var buttons = card.get_node_or_null("Margin/Elements/Buttons")
	if buttons == null or not (buttons is Node):
		return null
	var b = buttons.get_node_or_null("VTKDepositButton")
	return b if (b != null and b is Button) else null

func _make_deposit_button(card) -> Button:
	var buttons = card.get_node_or_null("Margin/Elements/Buttons")
	if buttons == null or not (buttons is Node):
		return null
	var btn := Button.new()
	btn.name = "VTKDepositButton"
	btn.text = Loc.txt("Deposit")
	btn.tooltip_text = Loc.txt("Deposit selected items toward this task")
	btn.add_theme_font_size_override("font_size", _sibling_button_font_size(buttons))
	btn.pressed.connect(_on_deposit_pressed.bind(card))
	buttons.add_child(btn)
	_balance_buttons(buttons)
	return btn

# Ванильное Input/Complete живут в GridContainer(columns=3) и за счёт
# content-based столбцов имеют разную ширину. Растягиваем все кнопки задачи до
# общего минимума — три столбца становятся равными.
func _balance_buttons(buttons) -> void:
	if buttons == null or not (buttons is Node):
		return
	var maxw := 0.0
	var maxh := 0.0
	for c in buttons.get_children():
		if c is Control:
			var m: Vector2 = (c as Control).get_combined_minimum_size()
			maxw = max(maxw, m.x)
			maxh = max(maxh, m.y)
	if maxw <= 0.0:
		return
	for c in buttons.get_children():
		if c is Control:
			(c as Control).custom_minimum_size = Vector2(maxw, maxh)

func _paint_cell(cells: Array, s) -> void:
	var idx := int(s["index"])
	if idx < 0 or idx >= cells.size():
		return
	var cell = cells[idx]
	if cell == null or not is_instance_valid(cell):
		return
	var satisfied := bool(s["satisfied"])
	var amount_lbl = cell.get_node_or_null("Details/Amount")
	if amount_lbl != null and amount_lbl is Node:
		amount_lbl.visible = not satisfied
	var badge = cell.get_node_or_null("VTKDepositBadge")
	if not satisfied:
		if badge != null:
			badge.queue_free()
		return
	if badge == null or not (badge is Label):
		badge = Label.new()
		badge.name = "VTKDepositBadge"
		badge.anchor_left = 0.0
		badge.anchor_top = 0.5
		badge.anchor_right = 1.0
		badge.anchor_bottom = 1.0
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		badge.add_theme_font_size_override("font_size", 11)
		cell.add_child(badge)
	badge.text = "✓"
	if cell.has_method("State"):
		cell.call("State", "Selected")

func _clear_badges(grid) -> void:
	for cell in _live_children(grid):
		if cell == null or not is_instance_valid(cell):
			continue
		var badge = cell.get_node_or_null("VTKDepositBadge")
		if badge != null:
			badge.queue_free()

func _selected_stacks(iface) -> Array:
	var out: Array = []
	var grid = iface.get("inventoryGrid")
	if grid == null or not (grid is Node):
		return out
	for cell in grid.get_children():
		if cell == null or not is_instance_valid(cell):
			continue
		if not bool(cell.get("selected")):
			continue
		var sd = cell.get("slotData")
		if sd == null:
			continue
		var item = sd.get("itemData")
		if item == null:
			continue
		# Нестакающиеся предметы игра хранит с amount = 0: Task.Initialize
		# проставляет amount только при defaultAmount != 0, поэтому почти все
		# сдаваемые предметы лежат в инвентаре нулём. Для вклада такая ячейка —
		# ровно один предмет, иначе apply() пропустит её как пустую.
		var amt := int(sd.get("amount", 0))
		if amt < 1:
			amt = 1
		out.append({
			"file": str(item.get("file")),
			"name": str(item.get("name")),
			"amount": amt,
			"ref": cell,
		})
	return out

func _consume(take: Array) -> void:
	for t in take:
		if t == null or typeof(t) != TYPE_DICTIONARY:
			continue
		var node = t.get("ref")
		var amt := int(t.get("amount", 0))
		if node == null or not is_instance_valid(node) or amt <= 0:
			continue
		var sd = node.get("slotData")
		if sd == null:
			continue
		var left := int(sd.get("amount", 0)) - amt
		if left <= 0:
			var grid = node.get_parent()
			if grid != null and grid.has_method("Pick"):
				grid.Pick(node)
			node.queue_free()
		else:
			sd.set("amount", left)
			node.call("UpdateDetails")
			node.call("State", "Static")

func _on_deposit_pressed(card) -> void:
	if card == null or not is_instance_valid(card):
		return
	var iface = card.get("interface")
	if iface == null or not is_instance_valid(iface):
		return
	if iface.get("inputTarget") != card:
		return
	var task_data = card.get("taskData")
	var grid = card.get("inputGrid")
	if task_data == null or grid == null or not (grid is Node):
		return
	var slots := _slots_from_grid(grid)
	if slots.is_empty():
		return
	var offered := _selected_stacks(iface)
	if offered.is_empty():
		return
	var key := _key_of(task_data)
	var res := VTKDeposits.apply(_ledger(), key, slots, offered)
	var take: Array = res.get("take", [])
	if take.is_empty():
		return
	_consume(take)
	_ledger_set(res.get("ledger", {}))
	_render_task_card(iface, card)
	_refresh_notes_for(iface, task_data)
	if card.has_method("CanComplete"):
		card.CanComplete()

func _on_task_complete_pressed() -> void:
	var card = _lib._caller if _lib else null
	if card == null or not is_instance_valid(card) or not _card_covered(card):
		return
	var iface = card.get("interface")
	var trader = iface.get("trader") if iface != null else null
	var task_data = card.get("taskData") if card != null else null
	if iface == null or trader == null or task_data == null:
		return
	if card.has_method("Completed"):
		card.Completed()
	if trader.has_method("CompleteTask"):
		trader.call("CompleteTask", task_data)
	if iface.has_method("UpdateTraderInfo"):
		iface.call("UpdateTraderInfo")
	# Награды — ванильным GetOutputItems, который читает inputTarget.outputGrid.
	var prev_target = iface.get("inputTarget")
	var prev_inputting = iface.get("isInputting")
	iface.set("inputTarget", card)
	iface.set("isInputting", true)
	if iface.has_method("GetOutputItems"):
		iface.call("GetOutputItems")
	iface.set("inputTarget", prev_target)
	iface.set("isInputting", prev_inputting)
	if iface.has_method("ResetInput"):
		iface.call("ResetInput")
	if _lib != null:
		_lib.skip_super()
	_render_task_card(iface, card)

func _handle_death_screen(gd, is_dead: bool, is_ironman: bool) -> void:
	if not is_dead or not is_ironman:
		_restore_load_button()
		_death_find_since = 0
		_death_gave_up = false
		_death_is_ironman = false
		return

	if _death_load_btn != null and is_instance_valid(_death_load_btn):
		return

	_death_is_ironman = is_ironman
	var now := Time.get_ticks_msec()
	if _death_find_since == 0:
		_death_find_since = now
		Log.log("[VTK] death screen tracking started @" + str(now))

	# Only ever touch the Death scene. Walking the root re-found a dozen
	# unrelated buttons ("Continue to Main Menu", JCM, the Settings tree) and
	# buried the real one under hundreds of MCM lines.
	var root := _death_scene_root()
	if root == null:
		return

	var load_btn := _find_load_button(root)
	if load_btn != null:
		_repurpose_load_button(load_btn, gd, root)
		return

	if _death_gave_up:
		return

	var waited := now - _death_find_since
	if waited >= DEATH_FIND_TIMEOUT_MS:
		_death_gave_up = true
		Log.log("[VTK] No 'Load Game' button after " + str(waited) + "ms; leaving vanilla death screen")
		return
	_dump_death_tree(root, waited, now)

# The real Death scene, so the search never walks the whole Interface tree.
# A dump taken over the root for four seconds showed only UI/MCM nodes and no
# scene nodes at all, which is what the missing button actually looked like.
func _death_scene_root() -> Node:
	var cs = get_tree().current_scene
	if cs != null and cs.name == "Death":
		return cs
	return get_tree().root.get_node_or_null("Death")

func _death_scene_present() -> bool:
	var now := Time.get_ticks_msec()
	if now - _death_scene_at >= DEATH_SCENE_POLL_MS:
		_death_scene_at = now
		_death_scene_hit = _death_scene_root() != null
	return _death_scene_hit

func _find_load_button(root: Node) -> BaseButton:
	var best: BaseButton = null
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is BaseButton:
			var b := n as BaseButton
			var t := String(b.text).strip_edges().to_lower()
			if t == "load game":
				return b
			if best == null and b.visible and not b.disabled and (t.begins_with("load") or t == "continue"):
				best = b
		for c in n.get_children():
			stack.push_back(c)
	return best

func _dump_death_tree(root: Node, waited: int, now: int) -> void:
	if now - _death_dump_at < 1000:
		return
	_death_dump_at = now
	var lines: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is BaseButton:
			var b := n as BaseButton
			var bt := String(b.text).strip_edges()
			lines.append("[VTK]   " + b.get_class() + " path='" + str(b.get_path()) + "' name='" + str(b.name) + "' text='" + bt + "' tip='" + str(b.tooltip_text) + "' vis=" + str(b.visible) + " dis=" + str(b.disabled) + " focus=" + str(b.focus_mode) + " conns=" + str(b.pressed.get_connections().size()))
		elif n is Control:
			var c := n as Control
			var txt := ""
			if "text" in c:
				txt = String(c.get("text"))
			elif c is RichTextLabel:
				txt = String((c as RichTextLabel).get_parsed_text())
			if txt.strip_edges() != "":
				lines.append("[VTK]   " + c.get_class() + " path='" + str(c.get_path()) + "' text='" + txt + "' vis=" + str(c.visible))
		for ch in n.get_children():
			stack.push_back(ch)
	Log.log("[VTK] death tree @" + str(waited) + "ms:\n" + "\n".join(lines))

func _repurpose_load_button(btn: BaseButton, gd, root) -> void:
	_death_load_btn = btn
	_death_load_orig_text = btn.text
	_death_load_orig_disabled = btn.disabled
	_death_load_orig_conns = []
	for c in btn.pressed.get_connections():
		var cb = c["callable"]
		_death_load_orig_conns.append(cb)
		btn.pressed.disconnect(cb)
	_death_load_bound = _on_restart_pressed.bind(gd, root)
	btn.pressed.connect(_death_load_bound)
	btn.text = "Restart"
	btn.disabled = false
	Log.log("[VTK] Death 'Load Game' button repurposed to Restart")

func _restore_load_button() -> void:
	if _death_load_btn == null:
		return
	if not is_instance_valid(_death_load_btn):
		_death_load_btn = null
		return
	var btn := _death_load_btn as Button
	if _death_load_bound != null and btn.pressed.is_connected(_death_load_bound):
		btn.pressed.disconnect(_death_load_bound)
	btn.text = _death_load_orig_text
	btn.disabled = _death_load_orig_disabled
	for cb in _death_load_orig_conns:
		if not btn.pressed.is_connected(cb):
			btn.pressed.connect(cb)
	_death_load_btn = null
	_death_load_bound = null
	_death_load_orig_conns = []

func _resolve_start_season() -> int:
	var sim = get_node_or_null(Paths.SIMULATION)
	if sim != null:
		var s = sim.get("season")
		if s != null:
			return int(s)
	return 1

func _wipe_saves_for_restart() -> void:
	var ldr = get_node_or_null(Paths.LOADER)
	if ldr != null and ldr.has_method("FormatSave"):
		Log.log("[VTK] Restart: wiping saves via Loader.FormatSave()")
		ldr.call("FormatSave")
		return
	var dir = DirAccess.open("user://")
	if dir == null:
		Log.log("[VTK] Restart: ERROR cannot open user://")
		return
	var names: Array = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres") and f != "Validator.tres" and f != "Preferences.tres":
			names.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	for n in names:
		var path := "user://" + String(n)
		if dir.remove(path) == OK:
			Log.log("[VTK] Restart: removed " + String(n))
		else:
			Log.log("[VTK] Restart: FAILED to remove " + String(n))


func _on_restart_pressed(gd, root) -> void:
	Log.log("[VTK] Restart: starting new game...")
	_death_latched = false
	_gd_node = null
	_death_load_btn = null
	_death_load_bound = null
	_death_load_orig_conns = []
	_death_gave_up = false
	if gd == null:
		Log.log("[VTK] Restart: no GameData, aborting")
		return
	gd.set("isDead", false)
	gd.set("previousMap", "")
	var start_map = "Cabin"
	if _death_is_ironman:
		start_map = IRONMAN_MAPS[randi() % IRONMAN_MAPS.size()]
		gd.set("shelter", false)
		gd.set("permadeath", true)
		gd.set("difficulty", 3)
	else:
		gd.set("shelter", true)
		gd.set("permadeath", false)
	gd.set("currentMap", start_map)
	var ldr = get_node_or_null(Paths.LOADER)
	if ldr == null:
		Log.log("[VTK] Restart: ERROR - Loader not found")
		return
	var difficulty := 1
	if _death_is_ironman:
		difficulty = 3
	elif gd.get("difficulty") != null:
		difficulty = int(gd.get("difficulty"))
	if ldr.has_method("NewGame"):
		ldr.call("NewGame", difficulty, _resolve_start_season())
	else:
		_wipe_saves_for_restart()
	ldr.LoadScene(start_map)
	Log.log("[VTK] Restart: loading " + start_map + " ironman=" + str(_death_is_ironman))