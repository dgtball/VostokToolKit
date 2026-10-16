extends RefCounted
# Типизированный срез MCM-конфига: 19 ключей. Дефолты полей - это же, что
# лежит в регистрационных записях VTKMCMBridge (там плюс name/tooltip/menu_pos,
# их в рекорд не тянем). Разбор - read(), он держит прежнюю семантику
# _mcm_key_val: приоритет d["value"] внутри словаря, иначе примитив, иначе
# дефолт.

const Loc = preload("res://mods/VTK/VTKLoc.gd")

var key_ui_toggle: int = 0
var language: String = Loc.DEFAULT
var auto_equip: bool = true
var debug_log: bool = false
var nvg_debug_probe: bool = false
var tp_unlocked_shelters_only: bool = false
var kill_counter_enabled: bool = true
var kill_feed_enabled: bool = true
var thermal_enabled: bool = false
var thermal_mines: bool = true
var thermal_mark_nomads: bool = true
var thermal_winter_auto: bool = true
var thermal_winter_dim: float = 0.55
var thermal_palette: int = 0
var thermal_world: float = 1.70
var thermal_bot_preset: int = 0
var thermal_far_distance: float = 45.0
var nvg_noise: float = 4.0
var nvg_white: float = 1.0


func read(cfg: ConfigFile) -> void:
	key_ui_toggle = int(_val(cfg, "Keycode", "key_ui_toggle", key_ui_toggle))
	language = str(_val(cfg, "Dropdown", "language", Loc.get_lang()))
	auto_equip = bool(_val(cfg, "Bool", "auto_equip", auto_equip))
	debug_log = bool(_val(cfg, "Bool", "debug_log", debug_log))
	nvg_debug_probe = bool(_val(cfg, "Bool", "nvg_debug_probe", nvg_debug_probe))
	tp_unlocked_shelters_only = bool(_val(cfg, "Bool", "tp_unlocked_shelters_only", tp_unlocked_shelters_only))
	kill_counter_enabled = bool(_val(cfg, "Bool", "kill_counter_enabled", kill_counter_enabled))
	kill_feed_enabled = bool(_val(cfg, "Bool", "kill_feed_enabled", kill_feed_enabled))
	thermal_enabled = bool(_val(cfg, "Bool", "thermal_enabled", thermal_enabled))
	thermal_mines = bool(_val(cfg, "Bool", "thermal_mines", thermal_mines))
	thermal_mark_nomads = bool(_val(cfg, "Bool", "thermal_mark_nomads", thermal_mark_nomads))
	thermal_winter_auto = bool(_val(cfg, "Bool", "thermal_winter_auto", thermal_winter_auto))
	thermal_winter_dim = float(_val(cfg, "Float", "thermal_winter_dim", thermal_winter_dim))
	thermal_palette = int(_val(cfg, "Int", "thermal_palette", thermal_palette))
	thermal_world = float(_val(cfg, "Float", "thermal_world", thermal_world))
	thermal_bot_preset = int(_val(cfg, "Int", "thermal_bot_preset", thermal_bot_preset))
	thermal_far_distance = float(_val(cfg, "Float", "thermal_far_distance", thermal_far_distance))
	nvg_noise = float(_val(cfg, "Float", "nvg_noise", nvg_noise))
	nvg_white = float(_val(cfg, "Float", "nvg_white", nvg_white))


static func _val(cfg: ConfigFile, section: String, key: String, fallback: Variant) -> Variant:
	if not cfg.has_section_key(section, key):
		return fallback
	var d = cfg.get_value(section, key, {})
	if typeof(d) == TYPE_DICTIONARY and d.has("value"):
		return d["value"]
	return d if typeof(d) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT] else fallback
