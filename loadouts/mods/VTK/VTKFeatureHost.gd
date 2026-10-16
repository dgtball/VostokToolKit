extends RefCounted
## Хост фич: владеет ленивыми узлами (хуки, NVG, телепорт, HUD) и их тумблерами.
## Вынесен из VTKUI (батч 6e, R4a).
##
## Родитель приходит в _init и обязан быть VTKUI: дети создаются через
## _root.add_child, потому что три места ищут узел хуков по имени
## /root/VTKUI/VTKHooks (VTKTravel, VTKFeed, VTKKillCounter). get_node_or_null
## вернёт null молча - хуки, фид и счётчик просто перестанут работать, без
## ошибки в логе.
##
## Имена методов сохранены от VTKUI: их держит layout_check (PRESENT на
## func _apply_hud( и func _ensure_hud().

const Hooks := preload("res://mods/VTK/VTKHooks.gd")
const NVG := preload("res://mods/VTK/VTKNVG.gd")
const Travel := preload("res://mods/VTK/VTKTravel.gd")
const KillCounter := preload("res://mods/VTK/VTKKillCounter.gd")
const Feed := preload("res://mods/VTK/VTKFeed.gd")
const ConfigRec := preload("res://mods/VTK/VTKConfig.gd")

var _root: Node = null

var _hooks: Node = null
var _nvg_node: Node = null
var _travel: Node = null
var _kc_node: Control = null
var _feed_node = null
var _hud_canvas = null

var _kc_mcm: bool = true
var _feed_mcm: bool = true
var _thermal_active: bool = false
var _mines_active: bool = true

func _init(root: Node) -> void:
	_root = root

func _ensure_hooks() -> void:
	if _hooks != null and is_instance_valid(_hooks):
		return
	_hooks = Hooks.new()
	_root.add_child(_hooks)

func nvg() -> Node:
	_ensure_nvg()
	if _nvg_node == null or not is_instance_valid(_nvg_node):
		return null
	return _nvg_node

func travel() -> Node:
	_ensure_travel()
	if _travel == null or not is_instance_valid(_travel):
		return null
	return _travel

func set_equip(enabled: bool, debug_probe: bool) -> void:
	if _hooks == null or not is_instance_valid(_hooks):
		return
	_hooks.set_equip_enabled(enabled)
	_hooks.set_equip_debug(debug_probe)

func set_hud(counter: bool, feed: bool) -> void:
	_kc_mcm = counter
	_feed_mcm = feed
	_apply_hud()

func set_travel_unlocked(only: bool) -> void:
	var t := travel()
	if t != null:
		t.set_unlocked_only(only)

func set_thermal(thermal: bool, mines: bool) -> void:
	_thermal_active = thermal
	_mines_active = mines
	_apply_nvg_settings()

# Применение всего разобранного MCM-конфига разом. Порядок прежний:
# HUD -> автоэкип -> телепорт -> пропсы NVG -> термал. Если NVG ещё не
# поднялся, пропсы и термал пропускаются - как и раньше.
func apply_config(c: ConfigRec) -> void:
	set_hud(c.kill_counter_enabled, c.kill_feed_enabled)
	set_equip(c.auto_equip, c.nvg_debug_probe)
	set_travel_unlocked(c.tp_unlocked_shelters_only)
	var nvg_node: Node = nvg()
	if nvg_node == null:
		return
	nvg_node.set_nvg_noise = c.nvg_noise
	nvg_node.set_nvg_white = c.nvg_white
	nvg_node.set_palette = c.thermal_palette
	nvg_node.set_world = c.thermal_world
	nvg_node.set_debug_probe = c.nvg_debug_probe
	nvg_node.set_mark_nomads = c.thermal_mark_nomads
	nvg_node.set_winter_auto = c.thermal_winter_auto
	nvg_node.set_winter_dim = c.thermal_winter_dim
	nvg_node.set_bot_preset = c.thermal_bot_preset
	nvg_node.set_far_distance = c.thermal_far_distance
	nvg_node.apply_debug_probe()
	set_thermal(c.thermal_enabled, c.thermal_mines)

func _ensure_nvg() -> void:
	if _nvg_node != null and is_instance_valid(_nvg_node):
		return
	_nvg_node = NVG.new()
	_root.add_child(_nvg_node)

func _ensure_travel() -> void:
	if _travel != null and is_instance_valid(_travel):
		return
	_travel = Travel.new()
	_root.add_child(_travel)

# Единая точка применения обоих HUD-виджетов. Зовётся из apply_config и из
# VTKMCMBridge.register, когда MCM не установлен: состояние приходит из MCM,
# отдельного UI-тумблера больше нет.
func _apply_hud() -> void:
	_set_counter_enabled(_kc_mcm)
	_set_feed_enabled(_feed_mcm)

func _set_counter_enabled(v: bool) -> void:
	if v:
		_ensure_hud()
		_kc_node.set_enabled(true)
	elif _kc_node != null and is_instance_valid(_kc_node):
		_kc_node.set_enabled(false)

func _set_feed_enabled(v: bool) -> void:
	if v:
		_ensure_hud()
		_feed_node.set_enabled(true)
	elif _feed_node != null and is_instance_valid(_feed_node):
		_feed_node.set_enabled(false)

# Один CanvasLayer на оба виджета; лениво, пока хотя бы один не включён.
func _ensure_hud() -> void:
	if _kc_node != null and is_instance_valid(_kc_node) \
			and _feed_node != null and is_instance_valid(_feed_node):
		return
	var tree := _root.get_tree()
	if tree == null:
		return
	if _hud_canvas == null or not is_instance_valid(_hud_canvas):
		_hud_canvas = CanvasLayer.new()
		_hud_canvas.name = "VTKKC_Canvas"
		_hud_canvas.layer = 9999
		tree.root.add_child(_hud_canvas)
	if _kc_node == null or not is_instance_valid(_kc_node):
		_kc_node = KillCounter.new()
		_hud_canvas.add_child(_kc_node)
	if _feed_node == null or not is_instance_valid(_feed_node):
		_feed_node = Feed.new()
		_hud_canvas.add_child(_feed_node)

func _apply_nvg_settings() -> void:
	_ensure_nvg()
	if _nvg_node != null and is_instance_valid(_nvg_node):
		_nvg_node.set_mines_enabled(_mines_active)
		_nvg_node.set_thermal_enabled(_thermal_active)
