extends RefCounted
# Единый реестр жёстких путей внутрь игры. Все - абсолютные NodePath от корня
# дерева, поэтому резолвятся и через get_tree().root.get_node_or_null(...), и
# через любой узел. При апдейте игры правится одно место, а не шесть файлов.

const INTERFACE := "/root/Map/Core/UI/Interface"
const UI := "/root/Map/Core/UI"
const CONTROLLER := "/root/Map/Core/Controller"
const LOADER := "/root/Loader"
const SIMULATION := "/root/Simulation"
const DATABASE := "/root/Database"
const CAMERA_MANAGER := "/root/Map/Core/Camera/Manager"
const NVG := "/root/Map/Core/UI/NVG"

# Имя сейва трейдеров в user:// (V17).
const TRADER_SAVE := "user://Traders.tres"

# Ресурсы игры.
const GAME_DATA := "res://Resources/GameData.tres"
# Тема HUD: единственный источник игрового шрифта (Lora). Проектного дефолта в
# игре нет (gui/theme/custom пуст), поэтому наши надписи на автолоаде вне дерева
# игры его не наследуют — тянем ресурс темы и берём default_font.
const THEME := "res://UI/Themes/Theme.tres"

static var _hud_font: Font = null

static func hud_font() -> Font:
	if _hud_font != null:
		return _hud_font
	if ResourceLoader.exists(THEME):
		var t = load(THEME)
		if t is Theme:
			_hud_font = t.default_font
	return _hud_font
