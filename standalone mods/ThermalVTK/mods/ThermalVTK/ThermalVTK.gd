extends Node
const Paths = preload("res://mods/ThermalVTK/VTKPaths.gd")

const MOD_ID := "thermal-vtk"
const MOD_NAME := "ThermalVTK"
const CONFIG_DIR := "user://MCM/thermal-vtk"
const CONFIG_FILE := "user://MCM/thermal-vtk/config.ini"
const STATE_FILE := "user://MCM/thermal-vtk/thermal_state.cfg"
const MCM_HELPERS := "res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres"

var _nvg: Node = null
var _key_thermal_toggle: int = 0
var _thermal_enabled: bool = false
var _mines_enabled: bool = true
var _mcm_thermal_seen: int = -1

func _ready() -> void:
	_register_mcm()

func _ensure_nvg() -> void:
	if _nvg != null and is_instance_valid(_nvg):
		return
	var NVG = preload("res://mods/ThermalVTK/VTKNVG.gd")
	_nvg = NVG.new()
	add_child(_nvg)

# ---------- hotkey ----------

func _unhandled_input(event: InputEvent) -> void:
	if _key_thermal_toggle == 0:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.keycode == _key_thermal_toggle or k.physical_keycode == _key_thermal_toggle:
		_toggle_thermal()
		get_viewport().set_input_as_handled()

func _toggle_thermal() -> void:
	_thermal_enabled = not _thermal_enabled
	if _nvg != null and is_instance_valid(_nvg):
		_nvg.set_thermal_enabled(_thermal_enabled)
	_notify("Thermal vision: " + ("ON" if _thermal_enabled else "OFF"),
		Color.GREEN if _thermal_enabled else Color(0.7, 0.7, 0.7))
	_save_thermal_enabled(_thermal_enabled)

# Same toast channel the toolkit uses for "Loadout ... applied".
func _notify(text: String, color: Color) -> void:
	var loader = get_node_or_null(Paths.LOADER)
	if loader != null and loader.has_method("Message"):
		loader.Message(text, color)

# Persist the hotkey choice in our own state file. MCM keeps an in-memory copy
# and rewrites its config wholesale, so writing the toggle there gets clobbered.
func _save_thermal_enabled(v: bool) -> void:
	var sf := ConfigFile.new()
	sf.set_value("state", "thermal_enabled", v)
	sf.save(STATE_FILE)

func _read_thermal_enabled() -> Variant:
	if not FileAccess.file_exists(STATE_FILE):
		return null
	var sf := ConfigFile.new()
	if sf.load(STATE_FILE) != OK:
		return null
	return bool(sf.get_value("state", "thermal_enabled", false))

# ---------- MCM ----------

func _register_mcm() -> void:
	_ensure_nvg()
	if not ResourceLoader.exists(MCM_HELPERS):
		_apply_defaults()
		return
	var MCM = load(MCM_HELPERS)
	if MCM == null or not MCM.has_method("RegisterConfiguration"):
		_apply_defaults()
		return
	var cfg = ConfigFile.new()
	var CAT := "01. ThermalVision"
	cfg.set_value("Keycode", "key_thermal_toggle", {"name": "Hotkey: Toggle thermal vision", "default": 0, "default_type": "Keycode", "value": 0, "category": CAT, "menu_pos": 0, "tooltip": "Press in game to turn the thermal layer on and off."})
	cfg.set_value("Float", "nvg_noise", {"name": "NVG noise", "default": 4.0, "value": 4.0, "minRange": 0.0, "maxRange": 60.0, "step": 0.5, "category": CAT, "menu_pos": 1, "tooltip": "Grain amount over the NVG image. Lower is cleaner. Vanilla is fixed at 10."})
	cfg.set_value("Float", "nvg_white", {"name": "NVG brightness", "default": 1.0, "value": 1.0, "minRange": 0.05, "maxRange": 1.0, "step": 0.05, "category": CAT, "menu_pos": 2, "tooltip": "Brightness of the NVG image. 1 = full brightness; lower darkens the whole overlay."})
	cfg.set_value("Bool", "thermal_enabled", {"name": "Thermal vision", "default": false, "value": false, "category": CAT, "menu_pos": 3, "tooltip": "Master switch for the thermal vision layer: bot heat glow, mines and the Nomad marker. Plain green NVG is unaffected while this is off."})
	cfg.set_value("Bool", "thermal_mines", {"name": "Mine highlighting", "default": true, "value": true, "category": CAT, "menu_pos": 4, "tooltip": "Highlight mines while thermal vision is on."})
	cfg.set_value("Bool", "thermal_mark_nomads", {"name": "Mark friendly Nomads", "default": true, "value": true, "category": CAT, "menu_pos": 5, "tooltip": "Draw a floating green marker over friendly Nomads so they are not shot by accident."})
	cfg.set_value("Bool", "thermal_winter_auto", {"name": "Winter auto-dimming", "default": true, "value": true, "category": CAT, "menu_pos": 6, "tooltip": "In winter (season 2) snow blows the thermal image out; dim the world so bots stay readable."})
	cfg.set_value("Float", "thermal_winter_dim", {"name": "Winter dimming", "default": 0.55, "value": 0.55, "minRange": 0.2, "maxRange": 1.0, "step": 0.05, "category": CAT, "menu_pos": 7, "tooltip": "Multiplier applied to world brightness while winter auto-dimming is active. Lower means darker snow."})
	cfg.set_value("Int", "thermal_palette", {"default": 0, "value": 0, "minRange": 0, "maxRange": 5, "step": 1, "category": CAT, "menu_pos": 8, "tooltip": "0 = Classic, 1 = White Hot (grey), 2 = Black Hot (inverted grey), 3 = Amber, 4 = Forest, 5 = Ice.", "name": "World palette"})
	cfg.set_value("Float", "thermal_world", {"default": 1.70, "value": 1.70, "minRange": 1.0, "maxRange": 4.0, "step": 0.05, "category": CAT, "menu_pos": 9, "tooltip": "How bright the surrounding world reads in thermal.", "name": "World brightness"})
	cfg.set_value("Int", "thermal_bot_preset", {"default": 0, "value": 0, "minRange": 0, "maxRange": 3, "step": 1, "category": CAT, "menu_pos": 10, "tooltip": "0 = Amber, 1 = White, 2 = Orange, 3 = Red. Living bots glow in this colour; a corpse cools from the head down before disappearing.", "name": "Bot colour"})
	cfg.set_value("Float", "thermal_far_distance", {"default": 45.0, "value": 45.0, "minRange": 5.0, "maxRange": 300.0, "step": 5.0, "category": CAT, "menu_pos": 11, "tooltip": "Bots and mines only glow within this distance; past it they read as ordinary scenery. 5 = only right beside you, 300 = the whole map.", "name": "Distance"})
	cfg.set_value("Info", "version", _mod_version())
	cfg.set_value("Info", "author", "opencode")
	DirAccess.make_dir_recursive_absolute(CONFIG_DIR)
	_sync_config(cfg)
	MCM.RegisterConfiguration(MOD_ID, MOD_NAME, CONFIG_DIR, "NVG thermal overlay: bot, mine and Nomad highlighting", _mcm_apply, self)
	_mcm_apply(ConfigFile.new())

# Merge the freshly declared keys into the on-disk config by KEY: drop sections
# and keys that no longer exist in code, add new ones, but never overwrite a
# user's saved "value". Info is always rewritten.
func _sync_config(cfg: ConfigFile) -> void:
	var existing := ConfigFile.new()
	if FileAccess.file_exists(CONFIG_FILE):
		existing.load(CONFIG_FILE)
		var stale_sections := []
		for s in existing.get_sections():
			if s != "Info" and not cfg.has_section(s):
				stale_sections.append(s)
		for s in stale_sections:
			existing.erase_section(s)
		for s in cfg.get_sections():
			var stale_keys: Array = []
			if existing.has_section(s):
				for k in existing.get_section_keys(s):
					if not cfg.has_section_key(s, k):
						stale_keys.append(k)
			for k in stale_keys:
				existing.erase_section_key(s, k)
		for s in cfg.get_sections():
			for k in cfg.get_section_keys(s):
				if s == "Info":
					existing.set_value(s, k, cfg.get_value(s, k, {}))
					continue
				if not existing.has_section_key(s, k):
					existing.set_value(s, k, cfg.get_value(s, k, {}))
					continue
				var old_v = existing.get_value(s, k, {})
				var new_v = cfg.get_value(s, k, {})
				if typeof(old_v) == TYPE_DICTIONARY and typeof(new_v) == TYPE_DICTIONARY:
					var merged = new_v.duplicate()
					merged["value"] = old_v.get("value", new_v.get("value"))
					existing.set_value(s, k, merged)
		existing.save(CONFIG_FILE)
	if not FileAccess.file_exists(CONFIG_FILE):
		cfg.save(CONFIG_FILE)

func _mcm_key_val(cfg: ConfigFile, section: String, key: String, fallback):
	if not cfg.has_section_key(section, key):
		return fallback
	var d = cfg.get_value(section, key, {})
	if typeof(d) == TYPE_DICTIONARY and d.has("value"):
		return d["value"]
	return d if typeof(d) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT] else fallback

func _mcm_apply(cfg: ConfigFile) -> void:
	if cfg.get_sections().is_empty() and FileAccess.file_exists(CONFIG_FILE):
		cfg.load(CONFIG_FILE)
	_ensure_nvg()
	if _nvg == null or not is_instance_valid(_nvg):
		return
	_key_thermal_toggle = int(_mcm_key_val(cfg, "Keycode", "key_thermal_toggle", 0))
	var mcm_thermal := bool(_mcm_key_val(cfg, "Bool", "thermal_enabled", false))
	var mcm_i: int = 1 if mcm_thermal else 0
	var saved = _read_thermal_enabled()
	if _mcm_thermal_seen < 0:
		_thermal_enabled = saved if saved != null else mcm_thermal
	elif saved != null and mcm_i == _mcm_thermal_seen:
		_thermal_enabled = saved
	else:
		_thermal_enabled = mcm_thermal
		_save_thermal_enabled(_thermal_enabled)
	_mcm_thermal_seen = mcm_i
	_mines_enabled = bool(_mcm_key_val(cfg, "Bool", "thermal_mines", true))
	_nvg.set_nvg_noise = float(_mcm_key_val(cfg, "Float", "nvg_noise", 4.0))
	_nvg.set_nvg_white = float(_mcm_key_val(cfg, "Float", "nvg_white", 1.0))
	_nvg.set_palette = int(_mcm_key_val(cfg, "Int", "thermal_palette", 0))
	_nvg.set_world = float(_mcm_key_val(cfg, "Float", "thermal_world", 1.70))
	_nvg.set_mark_nomads = bool(_mcm_key_val(cfg, "Bool", "thermal_mark_nomads", true))
	_nvg.set_winter_auto = bool(_mcm_key_val(cfg, "Bool", "thermal_winter_auto", true))
	_nvg.set_winter_dim = float(_mcm_key_val(cfg, "Float", "thermal_winter_dim", 0.55))
	_nvg.set_bot_preset = int(_mcm_key_val(cfg, "Int", "thermal_bot_preset", 0))
	_nvg.set_far_distance = float(_mcm_key_val(cfg, "Float", "thermal_far_distance", 45.0))
	_nvg.set_thermal_enabled(_thermal_enabled)
	_nvg.set_mines_enabled(_mines_enabled)

func _apply_defaults() -> void:
	var saved = _read_thermal_enabled()
	if saved != null:
		_thermal_enabled = saved
	if _nvg != null and is_instance_valid(_nvg):
		_nvg.set_thermal_enabled(_thermal_enabled)
		_nvg.set_mines_enabled(_mines_enabled)

func _mod_version() -> String:
	var vf = FileAccess.open("res://mods/ThermalVTK/version.txt", FileAccess.READ)
	if vf == null:
		return "unknown"
	var v := vf.get_as_text().strip_edges()
	vf.close()
	return v if v != "" else "unknown"
