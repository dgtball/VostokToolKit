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
const ConfigRec := preload("res://mods/VTK/VTKConfig.gd")
const SEASONS := preload("res://mods/VTK/VTKSeasons.gd")
const SEASON_DRV := preload("res://mods/VTK/VTKSeasonDriver.gd")
const HIT_WINDOW_MSEC := 15000
const SEEN_DEATHS_TTL_MSEC := 600000
const PLAYER_HITS_TTL_MSEC := 30000

var _equip_on: bool = true
var _pickup_pending: int = 0
var _equip_debug: bool = false
# Авто-экип из контейнера: запоминаем узел/ресурс/количество между pre и post.
var _xfer_node: Node = null
var _xfer_res = null
var _xfer_amount: int = 0
var _drag_node: Node = null
var _drag_res = null
var _drag_amount: int = 0
# Интерфейс живёт до выгрузки карты; путь резолвим один раз, не каждый кадр.
var _iface_cache = null

signal kill_event(ev: Dictionary)
signal travel_arrived

var _last_damager: Dictionary = {}
var _seen_deaths: Dictionary = {}

var _gd_node = null

# Динамические сезоны: драйвер сцены поднимается лениво, только если забег начат
# сезоном Dynamic (3) и настройка включена. Текущий сезон выводится из дня, а не
# хранится: стартовый offset фиксируется один раз на старте забега.
var _season_driver: Variant = null
var _dyn_enabled := false
var _dyn_start_offset := 1
var _dyn_cycle_days := 30
var _dyn_last_idx := -1

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
	if _dyn_enabled:
		_season_apply()

func set_equip_enabled(on: bool) -> void:
	_equip_on = on

func set_equip_debug(on: bool) -> void:
	_equip_debug = on

const GAME_DATA_RES := Paths.GAME_DATA

func _resolve_gamedata() -> Variant:
	if _gd_node != null and is_instance_valid(_gd_node):
		return _gd_node
	# Only the real resource: GameData.tres is a known path (Paths.GAME_DATA).
	# Scanning the tree for a node that happens to expose isDead/permadeath was a
	# guess that could latch onto an unrelated object; the typed load is exact.
	if ResourceLoader.exists(GAME_DATA_RES):
		var direct = load(GAME_DATA_RES)
		if direct != null:
			_gd_node = direct
	return _gd_node

func _try_register() -> void:
	if Engine.has_meta("RTVModLib"):
		_lib = Engine.get_meta("RTVModLib")
		if _lib.get("_is_ready"):
			_do_register()
		else:
			if not _lib.frameworks_ready.is_connected(_do_register):
				_lib.frameworks_ready.connect(_do_register)
	else:
		var mml = get_node_or_null(Paths.RTVMODLIB)
		if mml == null:
			mml = get_node_or_null(Paths.MML)
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
	_lib.hook("compiler-spawn-post", _on_compiler_spawn)
	_lib.hook("death-_ready-post", _on_death_ready)
	_lib.hook("death-_on_load_pressed", _on_death_load_pressed)
	_hooks_equip.append(_lib.hook("loader-loadcharacter-post", _on_loadcharacter_post))
	_hooks_context.append(_lib.hook("context-update-post", _on_context_update_post))
	_hooks_context.append(_lib.hook("interface-contexttake", _on_context_take_replace))
	_hooks_context.append(_lib.hook("interface-contextsplit", _on_context_split_replace))
	_hooks_equip.append(_lib.hook("pickup-interact-pre", _on_pickup_interact_pre))
	_hooks_equip.append(_lib.hook("pickup-interact-post", _on_pickup_interact_post))
	_hooks_equip.append(_lib.hook("interface-fasttransfer-pre", _on_fasttransfer_pre))
	_hooks_equip.append(_lib.hook("interface-fasttransfer-post", _on_fasttransfer_post))
	_hooks_equip.append(_lib.hook("interface-contexttransfer-pre", _on_contexttransfer_pre))
	_hooks_equip.append(_lib.hook("interface-contexttransfer-post", _on_contexttransfer_post))
	_hooks_equip.append(_lib.hook("interface-grab-pre", _on_grab_pre))
	_hooks_equip.append(_lib.hook("interface-release-post", _on_release_post))
	_registered = true
	Log.log("[VTK] Per-frame hooks registered (" + str(_hooks_kc.size() + _hooks_notes.size() + _hooks_deposits.size() + _hooks_equip.size() + _hooks_context.size() + 2) + " hooks)")

# Compiler.Spawn() - точный момент готовности карты: контроллер уже расставлен
# ванилой (Compiler.gd:205-220). Телепорт ждёт именно это, а не крутит кадры.
func _on_compiler_spawn() -> void:
	if _dyn_enabled:
		_season_apply()
	travel_arrived.emit()

# Late Start (and any mod that saves the world from its own loader-newgame-post
# handler) writes world.difficulty from gameData.difficulty. That value is stale:
# the new-game menu passes difficulty to Loader.NewGame as an argument but never
# stores it in gameData, whose difficulty is only assigned by Loader.LoadWorld
# from a previous save. Left alone, a difficulty-3 run is persisted back as 1 and
# LoadWorld no longer restores permadeath. Sync the live value and patch the saved
# world so the chosen difficulty survives regardless of hook order.
func _on_newgame_post(difficulty, season) -> void:
	var diff := int(difficulty)
	var gd = _resolve_gamedata()
	if gd != null:
		gd.set("difficulty", diff)
		if diff == 3:
			gd.set("permadeath", true)
	patch_world_difficulty(diff)
	_season_new_run(int(season))
	Log.log("[VTK] newgame-post: difficulty=" + str(diff) + " season=" + str(int(season)))

func patch_world_difficulty(diff: int) -> void:
	var path := Paths.WORLD_SAVE
	if not FileAccess.file_exists(path):
		return
	var world = load(path)
	if world == null or world.get("difficulty") == null:
		return
	world.set("difficulty", diff)
	ResourceSaver.save(world, path)

func _on_loadcharacter_post() -> void:
	Log.log("[VTK] loadcharacter-post")
	_season_resume()

# --- Динамические сезоны ----------------------------------------------------
# Идут только в забеге, начатом сезоном Dynamic (Menu передаёт season=3 в
# Loader.NewGame). NewGame пересоздаёт Traders.tres, поэтому мета vtk_season
# пишется на свежий файл сразу после старта и хранит только стартовые
# параметры (случайный стартовый сезон фиксируется один раз). Текущий сезон
# всегда выводится из Simulation.day, отдельно его хранить не нужно.
const SEASON_META := "vtk_season"
const MCM_CONFIG := "user://MCM/vostok-toolkit/config.ini"
const DYNAMIC_SEASON := 3

func _season_new_run(season: int) -> void:
	_dyn_last_idx = -1
	_dyn_enabled = false
	if season != DYNAMIC_SEASON:
		return
	var cfg := _season_config()
	if not cfg.season_enabled:
		Log.log("[VTK] dynamic seasons: disabled by config")
		return
	_dyn_start_offset = _season_offset_of(str(cfg.season_start))
	_dyn_cycle_days = 30
	_dyn_enabled = true
	_season_meta_write({
		"dynamic": true,
		"start_offset": _dyn_start_offset,
		"cycle_days": _dyn_cycle_days,
	})
	_season_apply()
	Log.log("[VTK] dynamic seasons: start_offset=" + str(_dyn_start_offset))

# Загрузка сейва: хук newgame-post не звался, параметры забега берём из меты.
# Пустая мета (чужой слот без динамики) состояние текущей сессии не трогает.
func _season_resume() -> void:
	var m := _season_meta()
	if m.is_empty():
		return
	if not bool(m.get("dynamic", false)):
		_dyn_enabled = false
		_dyn_last_idx = -1
		return
	_dyn_start_offset = clampi(int(m.get("start_offset", _dyn_start_offset)), 0, SEASONS.SEASONS.size() - 1)
	_dyn_cycle_days = maxi(1, int(m.get("cycle_days", _dyn_cycle_days)))
	_dyn_enabled = true
	_dyn_last_idx = -1
	_season_apply()

func _season_apply() -> void:
	if not _dyn_enabled:
		return
	if _season_driver == null:
		_season_driver = SEASON_DRV.new()
	var idx := SEASONS.resolve_index(_season_day(), _dyn_cycle_days, _dyn_start_offset)
	if idx == _dyn_last_idx:
		return
	_season_driver.set_season(idx, true)
	# Мир может быть ещё не поднят (start до Compiler.Spawn) - драйвер молча
	# пропустит; тогда отметку не ставим и повторим на compiler-spawn-post.
	if int(_season_driver._last_index) != idx:
		return
	_dyn_last_idx = idx
	Log.log("[VTK] season -> " + str(SEASONS.SEASONS[idx]))

func _season_day() -> int:
	var sim = get_node_or_null(Paths.SIMULATION)
	if sim != null:
		var d = sim.get("day")
		if d != null:
			return int(d)
	return 1

func _season_offset_of(choice: String) -> int:
	var key := choice.strip_edges().to_lower()
	if key == "random":
		return randi() % SEASONS.SEASONS.size()
	var i := SEASONS.SEASONS.find(key)
	return i if i >= 0 else 1

func _season_config() -> ConfigRec:
	var c: ConfigRec = ConfigRec.new()
	var cf := ConfigFile.new()
	if cf.load(MCM_CONFIG) == OK:
		c.read(cf)
	return c

func _season_meta() -> Dictionary:
	return VTKData.trader_meta(_traders(), SEASON_META)

func _season_meta_write(data: Dictionary) -> void:
	VTKData.trader_meta_write(_traders(), SEASON_META, data)

# --- Контекстное меню предмета: Destroy вне декора --------------------------
# Удаление в игре — ванильная кнопка Destroy в Context (Panel/Margin/Buttons/
# Destroy) с удержанием: Context._physics_process -> DestroyProgress копит
# Progress, при >=100 зовёт Interface.ContextDestroy(). Но ванила показывает её
# только в режиме декора (gameData.decor). Для предмета в гриде мод показывает
# ту же кнопку вне декора и переименовывает в "Delete" — отдельной кнопки мод
# не держит, вся логика удержания/прогресса/удаления остаётся ванильной.
# Пост-хук нужен потому, что ванильный Update в начале прячет всех детей
# контейнера, а Progress сбрасываем, чтобы открытие меню не начиналось с
# накопленного прошлого значения.
func _on_context_update_post(_slot_data) -> void:
	var ctx = _lib._caller if _lib else null
	if ctx == null or not is_instance_valid(ctx):
		return
	var destroy_btn = ctx.get_node_or_null("Panel/Margin/Buttons/Destroy")
	if destroy_btn == null or not (destroy_btn is Button):
		return
	destroy_btn.text = "Delete"
	var iface = _context_interface(ctx)
	if iface == null or not is_instance_valid(iface):
		return
	if iface.get("contextGrid") == null or iface.get("contextItem") == null:
		return
	destroy_btn.show()
	var progress = destroy_btn.get_node_or_null("Progress")
	if progress != null and progress is ProgressBar:
		progress.value = 0.0

func _context_interface(ctx):
	var iface = ctx.get("interface") if ctx != null else null
	if iface == null:
		iface = _resolve_interface()
	return iface

# Ванильные кнопки несут персональный theme_override_font_sizes/font_size (12),
# а не общий для темы Button; новый Button унаследовал бы дефолт темы (16).
# Берём размер у соседа-ванилы, пропуская наши VTK*-кнопки, и не привязываемся
# к жёсткому числу, если игра его сменит.
func _sibling_button_font_size(buttons) -> int:
	for child in buttons.get_children():
		if child is Button and not str(child.name).begins_with("VTK"):
			return child.get_theme_font_size("font_size")
	return 12

# --- Take/Split из слота экипировки ----------------------------------------
# Ванильные ContextTake/ContextSplit требуют contextGrid != null и в слоте
# молча выходят: кнопки в меню есть, эффекта нет. Если предмет лежит в слоте,
# сами возвращаем долю стака в инвентарь (AutoStack/Create) и пропускаем
# ванильное тело; для предметов в гриде не вмешиваемся (contextGrid != null).
func _on_context_take_replace() -> void:
	_context_slot_share(true)

func _on_context_split_replace() -> void:
	_context_slot_share(false)

func _context_slot_share(is_take: bool) -> void:
	var iface = _lib._caller if _lib else null
	if iface == null or not is_instance_valid(iface):
		return
	if iface.get("contextGrid") != null:
		return
	var item = iface.get("contextItem")
	var slot = iface.get("contextSlot")
	if item == null or slot == null or not is_instance_valid(item):
		return
	var sd = item.get("slotData")
	if sd == null:
		return
	var res = sd.get("itemData")
	if res == null:
		return
	var amount := int(sd.get("amount"))
	var share := EquipFlow.take_share(int(res.get("defaultAmount"))) if is_take else EquipFlow.split_share(amount)
	if share <= 0 or share > amount:
		return
	sd.set("amount", amount - share)
	if item.has_method("UpdateDetails"):
		item.UpdateDetails()
	var new_sd = SlotData.new()
	new_sd.itemData = res
	new_sd.amount = share
	var ig = iface.get("inventoryGrid")
	if ig != null and is_instance_valid(ig):
		if not iface.AutoStack(new_sd, ig):
			iface.Create(new_sd, ig, true)
	if iface.has_method("HideContext"):
		iface.HideContext()
	if iface.has_method("Reset"):
		iface.Reset()
	if iface.has_method("PlayStack"):
		iface.PlayStack()
	if _lib != null:
		_lib.skip_super()

func _resolve_interface() -> Node:
	if _iface_cache != null and is_instance_valid(_iface_cache):
		return _iface_cache
	var root = get_tree().root
	if root == null:
		return null
	_iface_cache = root.get_node_or_null(Paths.INTERFACE)
	return _iface_cache

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

# --- Авто-экип из контейнера ------------------------------------------------
# Двойной клик (FastTransfer), контекстное Transfer (ContextTransfer) и
# перетаскивание (Grab/Release) переносят предмет из открытого контейнера в
# инвентарь. Ловим успешный перенос и уводим предмет в слот, как при подборе с
# земли. Источник — только контейнер (его грид назван "Container"), торговец не
# задет. Успех: узел либо слился в стек (queue_free), либо переехал в
# inventoryGrid; иначе предмет остался в контейнере и трогать нечего.

func _xfer_arm(grid, item) -> void:
	_xfer_node = null
	_xfer_res = null
	_xfer_amount = 0
	if not _equip_on or grid == null or item == null:
		return
	if not is_instance_valid(grid) or not is_instance_valid(item):
		return
	var parent = grid.get_parent()
	if parent == null or str(parent.name) != "Container":
		return
	var sd = item.get("slotData")
	if sd == null:
		return
	var res = sd.get("itemData")
	if res == null or not EquipFlow.is_equipment(res):
		return
	var amt := int(sd.get("amount"))
	_xfer_node = item
	_xfer_res = res
	_xfer_amount = amt if amt > 0 else 1

func _xfer_post() -> void:
	var node = _xfer_node
	var res = _xfer_res
	var picked := _xfer_amount
	_xfer_node = null
	_xfer_res = null
	_xfer_amount = 0
	if not _equip_on or node == null or res == null or picked <= 0 or _lib == null:
		return
	if not is_instance_valid(node):
		return
	var iface = _lib._caller
	if iface == null or not is_instance_valid(iface):
		return
	var ig = iface.get("inventoryGrid")
	if ig == null or not is_instance_valid(ig):
		return
	if not node.is_queued_for_deletion() and node.get_parent() != ig:
		return
	_equip_picked(iface, ig, res, picked)

func _iface_caller() -> Variant:
	var iface = _lib._caller if _lib else null
	if iface == null or not is_instance_valid(iface):
		return null
	return iface

func _on_fasttransfer_pre() -> void:
	var iface = _iface_caller()
	if iface == null:
		return
	_xfer_arm(iface.get("hoverGrid"), iface.get("hoverItem"))

func _on_fasttransfer_post() -> void:
	_xfer_post()

func _on_contexttransfer_pre() -> void:
	var iface = _iface_caller()
	if iface == null:
		return
	_xfer_arm(iface.get("contextGrid"), iface.get("contextItem"))

func _on_contexttransfer_post() -> void:
	_xfer_post()

# Перетаскивание: запоминаем предмет, взятый именно из контейнера, и после
# отпускания проверяем, где он оказался. Drop в мир освобождает узел, поэтому
# здесь нельзя опираться на is_queued_for_deletion — только на родителя.
func _on_grab_pre() -> void:
	_drag_node = null
	_drag_res = null
	_drag_amount = 0
	var iface = _iface_caller()
	if iface == null or not _equip_on:
		return
	var grid = iface.get("hoverGrid")
	var item = iface.get("hoverItem")
	if grid == null or item == null:
		return
	if not is_instance_valid(grid) or not is_instance_valid(item):
		return
	var parent = grid.get_parent()
	if parent == null or str(parent.name) != "Container":
		return
	var sd = item.get("slotData")
	if sd == null:
		return
	var res = sd.get("itemData")
	if res == null or not EquipFlow.is_equipment(res):
		return
	var amt := int(sd.get("amount"))
	_drag_node = item
	_drag_res = res
	_drag_amount = amt if amt > 0 else 1

func _on_release_post() -> void:
	var node = _drag_node
	var res = _drag_res
	var picked := _drag_amount
	_drag_node = null
	_drag_res = null
	_drag_amount = 0
	if not _equip_on or node == null or res == null or picked <= 0:
		return
	if not is_instance_valid(node):
		return
	var iface = _iface_caller()
	if iface == null:
		return
	var ig = iface.get("inventoryGrid")
	if ig == null or not is_instance_valid(ig):
		return
	if node.get_parent() != ig:
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
	var moved := EquipFlow.equip_move(picked, 0, int(VTKData.prop(res, "maxAmount", 0)))
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
	var moved := EquipFlow.equip_move(picked, occ_amt, int(VTKData.prop(res, "maxAmount", 0)))
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
				rec["weapon"] = _rig_weapon_name()
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
		weapon = _rig_weapon_name()
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
	if n != null and is_instance_valid(n) and "weaponData" in n:
		var wd = n.get("weaponData")
		if wd != null and "name" in wd:
			var s := str(wd.get("name")).strip_edges()
			if s != "":
				return s
	for p in ["currentWeaponName", "weaponName", "currentWeapon", "weapon", "equippedWeapon", "activeWeapon"]:
		if p in n:
			var s2 := _weapon_str(n.get(p))
			if s2 != "":
				return s2
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
	if _player_hits.is_empty() and _seen_deaths.is_empty() and _last_damager.is_empty():
		return
	var now = Time.get_ticks_msec()
	var stale: Array = []
	for iid in _player_hits:
		if now - int(_player_hits[iid]) > PLAYER_HITS_TTL_MSEC:
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

const DEPOSITS_META := "vtk_deposits"

func _traders() -> Variant:
	if not FileAccess.file_exists(Paths.TRADER_SAVE):
		return null
	return load(Paths.TRADER_SAVE)

func _ledger() -> Dictionary:
	var traders = _traders()
	if traders == null:
		return {}
	var m = traders.get_meta(DEPOSITS_META, {})
	return m if typeof(m) == TYPE_DICTIONARY else {}

func _ledger_set(data: Dictionary) -> bool:
	var traders = _traders()
	if traders == null:
		return false
	traders.set_meta(DEPOSITS_META, data)
	var err := ResourceSaver.save(traders, Paths.TRADER_SAVE)
	if err != OK:
		Log.log("[VTK] deposit ledger save failed (code " + str(err) + ")")
		return false
	return true

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

# GC леджера вкладов: сносим ключи задач, чей ресурс больше не существует
# (задачу переименовал или удалил апдейт игры). Ключи-фолбэки (name::trader)
# не трогаем — их не с чем сверить. Пишем в сейв только при изменениях.
func _gc_ledger() -> void:
	var ledger := _ledger()
	if ledger.is_empty():
		return
	var pruned := VTKDeposits.prune_missing(ledger, Callable(self, "_resource_exists"))
	if pruned.size() != ledger.size():
		_ledger_set(pruned)

func _resource_exists(path: String) -> bool:
	return ResourceLoader.exists(path)

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
				amount = int(VTKData.prop(sd, "amount", 1))
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
	_gc_ledger()
	_render_all_tasks(iface)

func _on_tasks_startinput(_target) -> void:
	_on_tasks_rendered()

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
	btn.text = "Deposit"
	btn.tooltip_text = "Deposit selected items toward this task"
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
		var amt := int(VTKData.prop(sd, "amount", 0))
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
		var left := int(VTKData.prop(sd, "amount", 0)) - amt
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
	# Леджер сохраняется до списания: если персист не удался, commit отдаёт
	# пустой take и предметы остаются у игрока, а вклад не фиксируется.
	var committed := VTKDeposits.commit(_ledger(), key, slots, offered, Callable(self, "_ledger_set"))
	if not bool(committed.get("ok", false)):
		return
	var take: Array = committed.get("take", [])
	if take.is_empty():
		return
	_consume(take)
	_render_task_card(iface, card)
	_refresh_notes_for(iface, task_data)
	if card.has_method("CanComplete"):
		card.CanComplete()

func _on_task_complete_pressed() -> void:
	var card = _lib._caller if _lib else null
	if card == null or not is_instance_valid(card) or not _card_covered(card):
		return
	var iface = card.get("interface")
	if iface == null or not is_instance_valid(iface):
		return
	var task_data = card.get("taskData")
	if task_data == null:
		return
	# Ванильный путь завершения задачи: StartInput ставит inputTarget=card,
	# Complete сам делает CompleteTask/UpdateTraderInfo/DestroyInputItems/
	# GetOutputItems/ResetInput. Вклад уже списал предметы, поэтому удалять
	# нечего и повторного CompleteTask нет.
	if iface.has_method("StartInput"):
		iface.call("StartInput", card)
	if card.has_method("Completed"):
		card.Completed()
	if iface.has_method("Complete"):
		iface.call("Complete", task_data)
	if _lib != null:
		_lib.skip_super()
	_render_task_card(iface, card)

func _on_death_ready() -> void:
	var death = _lib._caller if _lib else null
	if death == null:
		return
	var pd = death.get_node_or_null("Main/Permadeath")
	if pd == null:
		Log.log("[VTK] death: Main/Permadeath not found; leaving vanilla death screen")
		return
	if not pd.visible:
		return
	var btn = death.get_node_or_null("Main/Buttons/Load")
	if btn == null:
		Log.log("[VTK] death: Main/Buttons/Load not found; leaving vanilla death screen")
		return
	btn.text = "Restart"
	btn.disabled = false

func _on_death_load_pressed() -> void:
	var death = _lib._caller if _lib else null
	if death == null:
		return
	var pd = death.get_node_or_null("Main/Permadeath")
	if pd == null:
		Log.log("[VTK] death: Main/Permadeath not found; vanilla Load runs")
		return
	if not pd.visible:
		return
	_lib.skip_super()
	var blocker = death.get_node_or_null("Blocker")
	if blocker != null:
		blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	if death.has_method("PlayClick"):
		death.PlayClick()
	_on_restart_pressed(VTKData.prop(death, "gameData", null), death, true)

func _resolve_start_season() -> int:
	var sim = get_node_or_null(Paths.SIMULATION)
	if sim != null:
		var s = sim.get("season")
		if s != null:
			return int(s)
	return 1

func _on_restart_pressed(gd, root, ironman: bool) -> void:
	Log.log("[VTK] Restart: starting new game...")
	_gd_node = null
	if gd == null:
		Log.log("[VTK] Restart: no GameData, aborting")
		return
	gd.set("isDead", false)
	gd.set("previousMap", "")
	var start_map = "Cabin"
	if ironman:
		start_map = IRONMAN_MAPS[randi() % IRONMAN_MAPS.size()]
		gd.set("difficulty", 3)
	gd.set("currentMap", start_map)
	var ldr = get_node_or_null(Paths.LOADER)
	if ldr == null:
		Log.log("[VTK] Restart: ERROR - Loader not found")
		return
	var difficulty := 1
	if ironman:
		difficulty = 3
	elif gd.get("difficulty") != null:
		difficulty = int(gd.get("difficulty"))
	ldr.call("NewGame", difficulty, _resolve_start_season())
	ldr.LoadScene(start_map)
	Log.log("[VTK] Restart: loading " + start_map + " ironman=" + str(ironman))
