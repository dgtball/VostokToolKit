extends RefCounted
# Мост между MCM и модом: регистрация настроек, свёртка config.ini (секции и
# ключи свежие, Info перезаписывается, пользовательские value живут) и разбор
# конфига в типизированный VTKConfig. Узлы и тумблеры остаются в
# VTKFeatureHost - мост их только дёргает, а UI остаётся в VTKUI.

const Loc = preload("res://mods/VTK/VTKLoc.gd")
const Log = preload("res://mods/VTK/VTKLog.gd")
const ConfigRec := preload("res://mods/VTK/VTKConfig.gd")

var features: RefCounted = null
var rebuild_ui: Callable = Callable()
var set_key_ui_toggle: Callable = Callable()

func register(host: RefCounted, on_rebuild: Callable, on_key: Callable) -> void:
	features = host
	rebuild_ui = on_rebuild
	set_key_ui_toggle = on_key
	if not ResourceLoader.exists("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres"):
		features._apply_hud()
		return
	var MCM = load("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres")
	if MCM == null or not MCM.has_method("RegisterConfiguration"):
		return
	var cfg = ConfigFile.new()
	var CAT := "01. General"
	cfg.set_value("Keycode", "key_ui_toggle", {"name": "Hotkey: Toggle UI", "default": 0, "default_type": "Keycode", "value": 0, "category": CAT, "menu_pos": 0, "tooltip": "Press once to open/close the Loadouts UI."})
	cfg.set_value("Dropdown", "language", {"name": "Language", "default": Loc.DEFAULT, "value": Loc.get_lang(), "options": {"en": "English", "ru": "Русский"}, "category": CAT, "menu_pos": 1, "tooltip": "Interface language of the Loadouts window. English is the source language."})
	cfg.set_value("Bool", "auto_equip", {"name": "Auto-equip on pickup", "default": true, "value": true, "category": CAT, "menu_pos": 2, "tooltip": "When a picked-up item fits an empty equipment slot it is equipped right away. Stackables top up an already equipped stack; loading a save or starting a new game is left untouched."})
	var TP := "02. ThermalVision"
	cfg.set_value("Bool", "thermal_enabled", {"name": "Thermal vision", "default": false, "value": false, "category": TP, "menu_pos": 0, "tooltip": "Master switch for the thermal vision layer: bot heat glow, mines and the Nomad marker. Plain green NVG is unaffected while this is off."})
	cfg.set_value("Bool", "thermal_mines", {"name": "Mine highlighting", "default": true, "value": true, "category": TP, "menu_pos": 1, "tooltip": "Highlight mines while thermal vision is on."})
	cfg.set_value("Bool", "thermal_mark_nomads", {"name": "Mark friendly Nomads", "default": true, "value": true, "category": TP, "menu_pos": 2, "tooltip": "Draw a floating green marker over friendly Nomads so they are not shot by accident."})
	cfg.set_value("Bool", "thermal_winter_auto", {"name": "Winter auto-dimming", "default": true, "value": true, "category": TP, "menu_pos": 3, "tooltip": "In winter (season 2) snow blows the thermal image out; dim the world so bots stay readable."})
	cfg.set_value("Float", "thermal_winter_dim", {"name": "Winter dimming", "default": 0.55, "value": 0.55, "minRange": 0.2, "maxRange": 1.0, "step": 0.05, "category": TP, "menu_pos": 4, "tooltip": "Multiplier applied to world brightness while winter auto-dimming is active. Lower means darker snow."})
	cfg.set_value("Float", "nvg_noise", {"name": "NVG noise", "default": 4.0, "value": 4.0, "minRange": 0.0, "maxRange": 60.0, "step": 0.5, "category": TP, "menu_pos": 5, "tooltip": "Grain amount over the NVG image. Lower is cleaner. Vanilla is fixed at 10."})
	cfg.set_value("Float", "nvg_white", {"default": 1.0, "value": 1.0, "minRange": 0.05, "maxRange": 1.0, "step": 0.05, "category": TP, "menu_pos": 6, "tooltip": "Brightness of the NVG image. 1 = full brightness; lower darkens the whole overlay (helps cut shimmer in bright scenes).", "name": "NVG brightness"})
	cfg.set_value("Int", "thermal_palette", {"default": 0, "value": 0, "minRange": 0, "maxRange": 5, "step": 1, "category": TP, "menu_pos": 7, "tooltip": "0 = Classic, 1 = White Hot (grey), 2 = Black Hot (inverted grey), 3 = Amber, 4 = Forest, 5 = Ice.", "name": "World palette"})
	cfg.set_value("Float", "thermal_world", {"default": 1.70, "value": 1.70, "minRange": 1.0, "maxRange": 4.0, "step": 0.05, "category": TP, "menu_pos": 8, "tooltip": "How bright the surrounding world reads in thermal.", "name": "World brightness"})
	cfg.set_value("Int", "thermal_bot_preset", {"default": 0, "value": 0, "minRange": 0, "maxRange": 3, "step": 1, "category": TP, "menu_pos": 9, "tooltip": "0 = Amber, 1 = White, 2 = Orange, 3 = Red. Living bots glow in this colour; a corpse cools from the head down before disappearing.", "name": "Bot colour"})
	cfg.set_value("Float", "thermal_far_distance", {"default": 45.0, "value": 45.0, "minRange": 5.0, "maxRange": 300.0, "step": 5.0, "category": TP, "menu_pos": 10, "tooltip": "Bots and mines only glow within this distance; past it they read as ordinary scenery. 5 = only right beside you, 300 = the whole map.", "name": "Distance"})
	var TR := "03. Travel"
	cfg.set_value("Bool", "tp_unlocked_shelters_only", {"name": "Unlocked shelters only", "default": false, "value": false, "category": TR, "menu_pos": 0, "tooltip": "When enabled, teleporting to a locked shelter is refused."})
	var KF := "04. KillFeed"
	cfg.set_value("Bool", "kill_counter_enabled", {"name": "Kill counter", "default": true, "value": true, "category": KF, "menu_pos": 0, "tooltip": "Show the kill counter HUD line (Killed / Enemies / Nomads)."})
	cfg.set_value("Bool", "kill_feed_enabled", {"name": "Kill feed", "default": true, "value": true, "category": KF, "menu_pos": 1, "tooltip": "Show the kill feed under the counter: killer, weapon/headshot icons, victim."})
	var SN := "05. Seasons"
	cfg.set_value("Bool", "season_enabled", {"name": "Dynamic seasons", "default": true, "value": true, "category": SN, "menu_pos": 0, "tooltip": "Cycle spring, summer, autumn and winter by day during a run started with the Dynamic season in the New Game menu. Winter brings the real snow and cold; the other seasons only tint trees, grass and light."})
	cfg.set_value("Dropdown", "season_start", {"name": "Starting season", "default": "summer", "value": "summer", "options": {"spring": "Spring", "summer": "Summer", "autumn": "Autumn", "winter": "Winter", "random": "Random"}, "category": SN, "menu_pos": 1, "tooltip": "Which season a fresh Dynamic run begins with. Random picks one for each new run."})
	var DBG := "06. Debug"
	cfg.set_value("Bool", "debug_log", {"name": "Mod debug log", "default": false, "value": false, "category": DBG, "menu_pos": 0, "tooltip": "Print mod diagnostics (item resolution, hooks, teleports, saves) to the game log. Off during normal play; turn on only to troubleshoot."})
	cfg.set_value("Bool", "nvg_debug_probe", {"name": "NVG probe log", "default": false, "value": false, "category": DBG, "menu_pos": 1, "tooltip": "Write NVG/thermal probes to user://loadouts_debug.log and enable the F4 detection overlay. Leave off during normal play; turn on only to diagnose something."})
	cfg.set_value("Info", "version", version())
	cfg.set_value("Info", "author", "opencode")
	var path = "user://MCM/vostok-toolkit"
	DirAccess.make_dir_recursive_absolute(path)
	var cfile = path + "/config.ini"
	if FileAccess.file_exists(cfile):
		var existing = ConfigFile.new()
		existing.load(cfile)
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
		existing.save(cfile)
	if not FileAccess.file_exists(cfile):
		cfg.save(cfile)
	MCM.RegisterConfiguration("vostok-toolkit", "Vostok Toolkit", path, "Loadouts, ESP and teleport", Callable(self, "apply"), self)
	apply(ConfigFile.new())

func version() -> String:
	# Единственный источник версии - version.txt, который пишет pack.ps1.
	# res://mod.txt не читаем: он общий для всех модов и в заголовке может
	# оказаться чужая версия.
	var vf = FileAccess.open("res://mods/VTK/version.txt", FileAccess.READ)
	if vf == null:
		return "unknown"
	var v := vf.get_as_text().strip_edges()
	vf.close()
	return v if v != "" else "unknown"

func load_lang() -> void:
	Loc.set_lang(Loc.DEFAULT)
	var cf := ConfigFile.new()
	if cf.load("user://MCM/vostok-toolkit/config.ini") != OK:
		return
	var d = cf.get_value("Dropdown", "language", {})
	if typeof(d) == TYPE_DICTIONARY:
		Loc.set_lang(str(d.get("value", Loc.DEFAULT)))

func apply(cfg: ConfigFile) -> void:
	var cpath = "user://MCM/vostok-toolkit/config.ini"
	if cfg.get_sections().is_empty() and FileAccess.file_exists(cpath):
		cfg.load(cpath)
	var c: ConfigRec = ConfigRec.new()
	c.read(cfg)
	var want: String = c.language
	if want != Loc.get_lang():
		Loc.set_lang(want)
		if Loc.get_lang() == want and rebuild_ui.is_valid():
			rebuild_ui.call()
	if set_key_ui_toggle.is_valid():
		set_key_ui_toggle.call(c.key_ui_toggle)
	Log.enabled = c.debug_log
	if features != null:
		features.apply_config(c)
