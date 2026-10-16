extends RefCounted
## Каталог предметов, вынесенный из VTKUI: список валидных предметов, индекс
## resource_path -> Resource, info-словари и иконки. Состояние статическое, как у
## VTKSurface: VTKUI наполняет каталог один раз через rebuild(), а читают его все,
## кому нужен предмет по пути. load() здесь только для дисковых фолбэков - пути
## из сохранённых сетов, которых нет в индексе, и PNG рядом с предметом; дисковые
## ветки headless-тест не берёт, остальное покрыто test_items.gd.

const LD := preload("res://mods/VTK/VTKData.gd")

static var _db_items: Array = []
# resource_path -> Resource. Строки сетов хранят пути, а панелям обвесов нужен
# сам Resource: без индекса каждая клетка искала бы его перебором всего
# списка, а раньше просто грузила с диска.
static var _item_index: Dictionary = {}
# resource_path -> готовый info-словарь (info_of). Предметы неизменны в рантайме,
# поэтому считается один раз на предмет, а не на каждую клетку/обвес при пересборке.
static var _info_cache: Dictionary = {}
# resource_path -> иконка либо null. Кеш нужен и для промахов: без него
# отсутствующий PNG искался бы заново в каждой клетке.
static var _icon_cache: Dictionary = {}

# Пустой каталог без чтения базы: VTKUI зовёт clear() перед разбором Database,
# чтобы при отказе базы состояния не осталось от прошлого раза - раньше чистка
# шла первым же шагом прямо в _load_items.
static func clear() -> void:
	_db_items.clear()
	_item_index.clear()
	_info_cache.clear()

# Наполнение из db.master.items: запись без имени - не предмет каталога.
static func rebuild(items: Array) -> void:
	clear()
	for item in items:
		if item and str(item.get("name")) != "":
			_db_items.append(item)
			_item_index[item.resource_path] = item

# Список для перебора снаружи (VTKUI: сетка, фасеты, раскладка экипировки).
static func all() -> Array:
	return _db_items

# Ресурс по resource_path из сохранённого сета, null - если пути нет в индексе.
static func index_of(path: String) -> Variant:
	return _item_index.get(path)

# Сведения о предмете по пути. Пути приходят из сохранённого сета, поэтому
# за индексом идёт только загрузка - но предмет из базы берётся из индекса
# без диска.
static func item_info(path: String) -> Dictionary:
	if path == "":
		return {}
	if _item_index.has(path):
		return info_of(_item_index[path])
	return info_of(load(path))

static func info_of(res) -> Dictionary:
	if res == null:
		return {}
	var key := String(res.resource_path)
	if key != "" and _info_cache.has(key):
		return _info_cache[key]
	var compat = res.get("compatible")
	var info := {
		"resource": res,
		"name": str(res.get("name")),
		"type": str(res.get("type")),
		"cat": str(LD.prop(res, "type", "")).to_lower(),
		"subtype": str(res.get("subtype")),
		"slots": item_slots(res),
		"compatible": compat if typeof(compat) == TYPE_ARRAY else [],
		"maxAmount": res.get("maxAmount"),
		"defaultAmount": res.get("defaultAmount"),
	}
	if key != "":
		_info_cache[key] = info
	return info

# Иконка предмета. У части предметов в данных игры icon пуст, хотя PNG лежит
# рядом в Files/ под именем Icon_<имя файла>.png - так в игре
# AKS-74U_Magazine. Путь собирается относительно самого предмета, а не по
# шаблону каталога: после обновления игры фолбэк просто не срабатывает и
# остаётся пустая иконка, как раньше.
static func item_icon(res) -> Texture2D:
	if not (res is Resource):
		return null
	if "icon" in res and res["icon"]:
		return res["icon"]
	var base := str(res.resource_path)
	if not base.ends_with(".tres"):
		return null
	if _icon_cache.has(base):
		return _icon_cache[base]
	var p := base.get_base_dir() + "/Files/Icon_" + base.get_file().get_basename() + ".png"
	var tex = load(p) if ResourceLoader.exists(p) else null
	_icon_cache[base] = tex
	return tex

static func item_slots(item) -> Array:
	if item == null:
		return []
	var slots = item.get("slots")
	if typeof(slots) != TYPE_ARRAY:
		return []
	return slots

# Ресурс предмета слота для иконки. Пустой дескриптор - null.
static func cell_resource(desc: Dictionary) -> Variant:
	return item_info(str(desc.get("path", ""))).get("resource")

# Из записи группы обвесов достаётся ресурс: info_of отдаёт словарь с
# полем "resource", а плитке нужен сам ресурс - ради иконки и имени.
static func attachment_resource(a: Dictionary) -> Variant:
	return item_info(str(a.get("path", ""))).get("resource")
