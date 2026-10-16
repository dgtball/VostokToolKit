extends RefCounted
# Единый реестр жёстких путей: игровая сцена, автолоады мода, опциональный
# фреймворк и файлы сейвов. Узловые пути - абсолютные NodePath от корня дерева,
# поэтому резолвятся и через get_tree().root.get_node_or_null(...), и через
# любой узел. При апдейте игры правится одно место, а не шесть файлов.

const INTERFACE := "/root/Map/Core/UI/Interface"
const UI := "/root/Map/Core/UI"
const CONTROLLER := "/root/Map/Core/Controller"
const LOADER := "/root/Loader"
const SIMULATION := "/root/Simulation"
const DATABASE := "/root/Database"
const CAMERA_MANAGER := "/root/Map/Core/Camera/Manager"
const NVG := "/root/Map/Core/UI/NVG"

# Свои автолоады. UI_ROOT уезжал по трём файлам литералом и был найден только
# по ссылке в аудите; HOOKS - единственная дочерняя нода, до которой доходят
# лента, счётчик и телепорт.
const UI_ROOT := "/root/VTKUI"
const HOOKS := "VTKHooks"

# Заголовочный фреймворк: RTVModLib кладёт себя в Engine.meta, без него
# хуки ищут его автолоадом - оба варианта здесь, а не в _try_register.
const RTVMODLIB := "/root/RTVModLib"
const MML := "/root/MML"

# Имя сейва трейдеров в user:// (V17).
const TRADER_SAVE := "user://Traders.tres"
# Сейв мира в user:// (V17): patch_world_difficulty правит difficulty
# задним числом, чтобы permadeath пережил любое место в hook-порядке.
const WORLD_SAVE := "user://World.tres"

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
