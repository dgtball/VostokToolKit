extends Node
const Paths = preload("res://mods/VTK/VTKPaths.gd")
const Log = preload("res://mods/VTK/VTKLog.gd")
const SAVE_FILE := "user://MCM/vostok-toolkit/VTKsets.json"
const LEGACY_SAVE_FILE := "user://MCM/vostok-toolkit/loadouts.json"

# Одноразовый перенос loadouts.json -> VTKsets.json. Файл сетов переехал под
# префикс VTK*, как остальные сущности мода, но имя не привязано к коду, поэтому
# старые данные живут на диске и должны быть перенесены один раз.
# Копия, а не rename: если удаление старого файла не удалось, данные всё равно
# уже на месте. Выходим, если новый файл уже есть - перенос не перетирает живое.
static func migrate_save_file() -> void:
	if FileAccess.file_exists(SAVE_FILE):
		return
	_migrate_one(LEGACY_SAVE_FILE, SAVE_FILE.get_file())
	_migrate_one(LEGACY_SAVE_FILE + ".bak", SAVE_FILE.get_file() + ".bak")

static func _migrate_one(src_path: String, dst_name: String) -> void:
	if not FileAccess.file_exists(src_path):
		return
	var src = FileAccess.open(src_path, FileAccess.READ)
	if src == null:
		Log.log("[VTK] save file migration failed: cannot open " + str(src_path))
		return
	var text := src.get_as_text()
	src.close()
	var dst_path := SAVE_FILE.get_base_dir() + "/" + dst_name
	var dst = FileAccess.open(dst_path, FileAccess.WRITE)
	if dst == null:
		Log.log("[VTK] save file migration failed: cannot write " + dst_path)
		return
	dst.store_string(text)
	dst.close()
	var r := DirAccess.remove_absolute(ProjectSettings.globalize_path(src_path))
	if r != OK:
		Log.log("[VTK] save file migration: copied " + dst_name
			+ ", failed to remove " + src_path + " (code " + str(r) + ")")
		return
	Log.log("[VTK] save file migrated: " + src_path.get_file() + " -> " + dst_name)

static func _root_node() -> Node:
	var tree = Engine.get_main_loop()
	if tree is SceneTree:
		return tree.root
	return null

# ---------- meta на TraderSave ----------
# Леджер вкладов и состояние динамических сезонов живут метой на сохранении
# торговцев (user://Traders.tres - активный слот). get_meta отдаёт Variant,
# поэтому чтение фильтрует тип: чужой или битый ключ даёт пусто, а не падение.
static func trader_meta(traders, key: String) -> Dictionary:
	if traders == null:
		return {}
	var m = traders.get_meta(key, {})
	return m if typeof(m) == TYPE_DICTIONARY else {}

# Запись меты с сохранением ресурса. true только при OK: вызывающий решает,
# откатывать ли своё состояние, если сейв не записался.
static func trader_meta_write(traders, key: String, data: Dictionary) -> bool:
	if traders == null:
		return false
	traders.set_meta(key, data)
	var err := ResourceSaver.save(traders, Paths.TRADER_SAVE)
	if err != OK:
		Log.log("[VTK] trader meta save failed: " + key + " (code " + str(err) + ")")
		return false
	return true

# ---------- storage ----------

const BAK_SUFFIX := ".bak"
const TMP_SUFFIX := ".tmp"
const CORRUPT_MARK := ".corrupt-"

static func get_all() -> Array:
	var payload = _read_payload(SAVE_FILE)
	if payload != null:
		return payload as Array
	# Основной файл отсутствует или нечитаем. Если он есть - сохраняем байты
	# в сторонний .corrupt, прежде чем путь что-либо перезапишет.
	if FileAccess.file_exists(SAVE_FILE):
		_quarantine(SAVE_FILE)
	var bak_payload = _read_payload(SAVE_FILE + BAK_SUFFIX)
	if bak_payload != null:
		Log.log("[VTK] sets file unreadable; recovered from " + SAVE_FILE.get_file() + BAK_SUFFIX)
		return bak_payload as Array
	return []

# Возвращает массив сетов или null, если прочитать/разобрать не удалось.
# null - это «данные негодны», в отличие от пустого массива «сетов нет».
static func _read_payload(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text = file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return null
	var json = JSON.new()
	if json.parse(text) != OK:
		return null
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY or not data.has("loadouts"):
		return null
	var arr = data["loadouts"]
	if typeof(arr) != TYPE_ARRAY:
		return null
	return arr

static func save_all(loadouts: Array) -> void:
	var real_dir = OS.get_user_data_dir() + "/MCM/vostok-toolkit"
	var d = DirAccess.open(real_dir)
	if not d:
		d = DirAccess.open(OS.get_user_data_dir())
		if d:
			d.make_dir("MCM")
			d = DirAccess.open(OS.get_user_data_dir() + "/MCM")
			if d:
				d.make_dir("vostok-toolkit")
				real_dir = OS.get_user_data_dir() + "/MCM/vostok-toolkit"
				d = DirAccess.open(real_dir)
	var payload := JSON.stringify({"loadouts": loadouts})
	# Держим предыдущую исправную версию: перед перезаписью копируем её в .bak.
	if FileAccess.file_exists(SAVE_FILE):
		var bak := SAVE_FILE + BAK_SUFFIX
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bak))
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_FILE), ProjectSettings.globalize_path(bak))
	var tmp := SAVE_FILE + TMP_SUFFIX
	var file = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		Log.log("[VTK] save_all: cannot open " + tmp)
		return
	file.store_string(payload)
	file.close()
	var err := _replace(tmp, SAVE_FILE)
	if err != OK:
		Log.log("[VTK] save_all: replace failed (code " + str(err) + ")")

# Атомарная замена: пишем в .tmp и переносим на место основного. На Windows
# rename поверх существующего файла может упасть - тогда убираем цель и повторяем.
static func _replace(from_path: String, to_path: String) -> int:
	var g_from := ProjectSettings.globalize_path(from_path)
	var g_to := ProjectSettings.globalize_path(to_path)
	var err := DirAccess.rename_absolute(g_from, g_to)
	if err == OK:
		return OK
	DirAccess.remove_absolute(g_to)
	return DirAccess.rename_absolute(g_from, g_to)

# Битый файл не затираем, а переносим в *.corrupt-<время>: байты остаются для
# разбора, а повторные get_all не плодят дубликаты - основного файла уже нет.
static func _quarantine(path: String) -> void:
	var dst := path + CORRUPT_MARK + str(int(Time.get_unix_time_from_system()))
	var g_src := ProjectSettings.globalize_path(path)
	var g_dst := ProjectSettings.globalize_path(dst)
	if DirAccess.rename_absolute(g_src, g_dst) == OK:
		Log.log("[VTK] corrupt sets file quarantined: " + dst.get_file())
		return
	if DirAccess.copy_absolute(g_src, g_dst) == OK:
		DirAccess.remove_absolute(g_src)
		Log.log("[VTK] corrupt sets file copied to " + dst.get_file())
		return
	Log.log("[VTK] corrupt sets file could not be quarantined: " + path)

static func _find(name: String) -> Variant:
	for ld in get_all():
		if typeof(ld) == TYPE_DICTIONARY and str(ld.get("name")) == name:
			return ld
	return null

static func get_set(name: String) -> Dictionary:
	var raw = _find(name)
	if raw == null:
		return {}
	return _norm(raw)

static func names() -> Array:
	var out := []
	for ld in get_all():
		if typeof(ld) == TYPE_DICTIONARY:
			out.append(str(ld.get("name")))
	return out

# ---------- schema ----------
# equip : Dictionary  slot name -> item descriptor (one item per slot by construction)
# gear  : Array       item descriptors, stackable by amount

static func _norm(ld) -> Dictionary:
	var out := {"name": "", "quick_key": 0, "equip": {}, "gear": []}
	if typeof(ld) != TYPE_DICTIONARY:
		return out
	if ld.has("name"):
		out["name"] = str(ld["name"])
	if ld.has("quick_key"):
		out["quick_key"] = int(ld["quick_key"])
	if typeof(ld.get("equip")) == TYPE_DICTIONARY and typeof(ld.get("gear")) == TYPE_ARRAY:
		var eq: Dictionary = ld["equip"]
		var out_eq := {}
		for k in eq.keys():
			if typeof(eq[k]) == TYPE_DICTIONARY:
				out_eq[str(k)] = eq[k]
		out["equip"] = out_eq
		var gr: Array = ld["gear"]
		out["gear"] = gr.duplicate(true)
		return out
	if typeof(ld.get("items")) == TYPE_ARRAY:
		_split_legacy(ld["items"], out)
	return out

static func _split_legacy(items: Array, out: Dictionary) -> void:
	var out_eq := {}
	var out_gear := []
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var desc := _desc(it)
		var slot := str(it["slot"]) if it.has("slot") else ""
		if slot == "":
			slot = _preferred_slot(desc["path"])
		if slot == "":
			out_gear.append(desc)
		else:
			out_eq[slot] = desc
	out["equip"] = out_eq
	out["gear"] = out_gear

static func _desc(src) -> Dictionary:
	var d := {"path": "", "name": "", "type": "", "amount": 1.0}
	if typeof(src) != TYPE_DICTIONARY:
		return d
	if src.has("path"):
		d["path"] = str(src["path"])
	if src.has("name"):
		d["name"] = str(src["name"])
	if src.has("type"):
		d["type"] = str(src["type"])
	if src.has("amount"):
		d["amount"] = float(src["amount"])
	if src.has("attachments"):
		d["attachments"] = src["attachments"]
	return d

static func _preferred_slot(path: String) -> String:
	if path == "":
		return ""
	var res = load(path)
	if res == null:
		return ""
	var slots = res.get("slots")
	if not (slots is Array) or slots.size() == 0:
		return ""
	return str(slots[0])

# ---------- set writes ----------

static func remove(name: String) -> void:
	var all = get_all()
	var kept := []
	for ld in all:
		if typeof(ld) == TYPE_DICTIONARY and str(ld.get("name")) == name:
			continue
		kept.append(ld)
	save_all(kept)

static func replace_set(set_name: String, equip_dict: Dictionary, gear_list: Array) -> void:
	var all = get_all()
	var found := false
	for i in range(all.size()):
		if typeof(all[i]) != TYPE_DICTIONARY or str(all[i].get("name")) != set_name:
			continue
		var n := _norm(all[i])
		n["equip"] = equip_dict.duplicate(true)
		n["gear"] = gear_list.duplicate(true)
		all[i] = n
		found = true
		break
	if not found:
		all.append({
			"name": set_name,
			"quick_key": 0,
			"equip": equip_dict.duplicate(true),
			"gear": gear_list.duplicate(true),
		})
	save_all(all)

# ---------- hotkeys ----------

static func set_quick_key(name: String, keycode: int) -> void:
	var all = get_all()
	for i in range(all.size()):
		if typeof(all[i]) == TYPE_DICTIONARY and str(all[i].get("name")) == name:
			all[i]["quick_key"] = keycode
			save_all(all)
			return

# Одна клавиша - один сет: перед назначением чужой бинд на этом коде
# снимается, иначе get_name_by_quick_key отдала бы первого попавшегося.
static func set_quick_key_unique(name: String, keycode: int) -> void:
	var all = get_all()
	var found := false
	for i in range(all.size()):
		if typeof(all[i]) != TYPE_DICTIONARY:
			continue
		var nm := str(all[i].get("name"))
		if nm == name:
			all[i]["quick_key"] = keycode
			found = true
		elif keycode != 0 and int(all[i].get("quick_key", 0)) == keycode:
			all[i]["quick_key"] = 0
	if found:
		save_all(all)

static func get_name_by_quick_key(keycode: int) -> String:
	if keycode == 0:
		return ""
	for ld in get_all():
		if typeof(ld) != TYPE_DICTIONARY:
			continue
		var k = int(ld.get("quick_key")) if ld.has("quick_key") else 0
		if k == keycode:
			return str(ld.get("name"))
	return ""

# ---------- actions ----------

static func load_loadout(name: String) -> void:
	apply_loadout(name, true)

static func apply_loadout(name: String, equip: bool) -> void:
	var pack = get_set(name)
	if pack.is_empty():
		return
	var root = _root_node()
	if not root:
		return
	var interface = root.get_node_or_null(Paths.INTERFACE)
	if not interface:
		Log.log("[VTK] apply_loadout: no Interface node")
		return
	var loader = root.get_node_or_null(Paths.LOADER)
	if loader == null:
		# Ниже всё защищено null-проверками, так что промах раньше означал
		# молчаливое отсутствие сообщений об успехе - теперь один след.
		Log.warn_once(Paths.LOADER, "apply_loadout: Loader node missing")
	var ig = interface.get("inventoryGrid")
	if ig == null or not is_instance_valid(ig):
		Log.log("[VTK] apply_loadout: no inventoryGrid")
		return

	var will_equip := equip and interface.has_method("Equip")
	if equip and not will_equip:
		Log.log("[VTK] interface.Equip unavailable, inventory only")
	var equip_root = interface.get("equipment") if will_equip else null
	if will_equip and (equip_root == null or not is_instance_valid(equip_root)):
		will_equip = false
		equip_root = null

	var fitted := 0
	var skipped := 0

	if will_equip:
		var eq: Dictionary = pack["equip"]
		for slot_name in eq.keys():
			var desc: Dictionary = eq[slot_name]
			var sd = _build_slot_data(desc)
			if sd == null:
				continue
			if _equip_sd(interface, ig, equip_root, sd, str(slot_name)):
				fitted += 1
			else:
				skipped += 1
				Log.log("[VTK] slot busy or missing: " + str(desc.get("name")) + " -> " + str(slot_name))

	var cat_grid = interface.get("catalogGrid")
	var cat_before := _grid_count(cat_grid)
	var gear: Array = pack["gear"]
	for desc in gear:
		if typeof(desc) != TYPE_DICTIONARY:
			continue
		_insert_desc(interface, ig, desc)
	var to_catalog := _grid_count(cat_grid) - cat_before

	if loader and loader.has_method("SaveCharacter"):
		loader.SaveCharacter()
	if interface.has_method("UpdateStats"):
		interface.UpdateStats(true)
	if will_equip and interface.has_method("PlayEquip"):
		interface.PlayEquip()

	var grid_count := 0
	for child in ig.get_children():
		if is_instance_valid(child) and child.get("slotData") != null:
			grid_count += 1

	Log.log("[VTK] apply '" + name + "' equip=" + str(equip)
		+ " fitted=" + str(fitted) + " skipped=" + str(skipped)
		+ " grid=" + str(grid_count) + " catalog=" + str(to_catalog)
		+ " reset=skipped saved=1")

	if not equip:
		var inv_msg := 'Loadout "' + name + '" → to inventory: ' + str(grid_count)
		if to_catalog > 0:
			inv_msg += ' · To catalog: ' + str(to_catalog)
		_notify(loader, inv_msg, Color.GREEN)
		return

	var msg := 'Loadout "' + name + '" applied'
	if fitted > 0:
		msg += ' · Equipped: ' + str(fitted)
	if skipped > 0:
		msg += ' · Occupied slots: ' + str(skipped)
	if grid_count > 0:
		msg += ' · In inventory: ' + str(grid_count)
	if to_catalog > 0:
		msg += ' · To catalog: ' + str(to_catalog)
	_notify(loader, msg, Color.GREEN)

# ---------- internals ----------

# Вставить один gear-дескриптор столько раз, сколько задано count (обоймы)
# или amount (обычное снаряжение). Общая точка для apply_loadout и кнопки
# «В инвентарь». Нестекуемое с amount=N разбивается на N копий по 1 — игра
# не умеет показывать 5 банок в одном слоте; стекуемое (аммо) остаётся
# одной стопкой с amount=N. Возвращает число созданных узлов.
static func _insert_desc(interface, ig, desc: Dictionary) -> int:
	var placed := 0
	var n := _instances(desc)
	var one := desc
	if n > 1 and not desc.has("count"):
		one = desc.duplicate()
		one["amount"] = 1.0
	# Каталог постройки: мебель игра показывает не в рюкзаке, а в строительном
	# каталоге (interface.catalogGrid), как это делает JCM. Берём ссылку один
	# раз до цикла; без Interface (headless-тест) остаётся null.
	var catalog = null
	if interface != null and is_instance_valid(interface):
		catalog = interface.get("catalogGrid")
	for i in range(n):
		var gsd = _build_slot_data(one)
		if gsd == null:
			break
		if catalog != null and _is_furniture(gsd.get("itemData")):
			interface.Create(gsd, catalog, false)
		else:
			_insert(interface, ig, gsd)
		placed += 1
	return placed

# Мебель нельзя выдавать в рюкзак: игровое Interface.Create для неё зовётся с
# строительным каталогом, а не с inventoryGrid.
static func _is_furniture(res) -> bool:
	if res == null:
		return false
	return str(res.get("type")).strip_edges().to_lower() == "furniture"

# Число слотов сетки - для отчёта "сколько ушло в каталог". null-безопасно:
# без игрового дерева сетки нет, должно вернуться 0, а не упасть.
static func _grid_count(grid) -> int:
	if grid == null or not is_instance_valid(grid):
		return 0
	var n := 0
	for c in grid.get_children():
		if is_instance_valid(c) and c.get("slotData") != null:
			n += 1
	return n

static func _is_magazine(res) -> bool:
	return res != null and str(res.get("type")) == "Attachment" and str(res.get("subtype")) == "Magazine"

# Полная обойма = maxAmount ресурса обоймы (у Makarov_Magazine это 8, ровно
# magazineSize пистолета). JCM делает так же: newSlotData.amount = maxAmount.
# Выключенный тумблер даёт пустую обойму — amount 0.
static func _mag_unit(res, full: bool) -> int:
	if not full:
		return 0
	var m = res.get("maxAmount")
	if m != null and float(m) > 0.0:
		return int(round(float(m)))
	var d = res.get("defaultAmount")
	if d != null and float(d) > 0.0:
		return int(round(float(d)))
	return 0

# Свойство игрового объекта с фолбэком. Object.get() принимает ровно один
# аргумент: get(name, default) на Resource падает в debug (в release лишний
# аргумент молча игнорируется). Фолбэк применяем сами; Dictionary тоже годится.
static func prop(obj, name: String, default = null) -> Variant:
	if obj == null:
		return default
	var v = obj.get(name)
	return default if v == null else v

# Сколько отдельных SlotData создавать из одного descriptor'а. Обоймы
# считаются в count; у обычного снаряжения amount = число копий, но только
# для нестекуемых предметов — стекуемое (аммо, maxAmount > 1) это одна
# стопка с amount = N, поэтому ей нужен один SlotData. Ресурс не загрузился
# — считаем нестекуемым: копий столько, сколько amount, каждая по 1.
static func _instances(desc: Dictionary) -> int:
	if desc.has("count"):
		return clampi(int(desc.get("count", 1)), 0, 32)
	var amt := int(round(float(desc.get("amount", 1.0))))
	if amt <= 1:
		return 1
	var path := str(desc.get("path", ""))
	if path != "":
		var res = load(path)
		if res != null and bool(res.get("stackable")):
			return 1
	return clampi(amt, 1, 32)

static func _build_slot_data(item_data):
	if typeof(item_data) != TYPE_DICTIONARY:
		return null
	var path = str(item_data.get("path"))
	if path == "":
		return null
	var res = load(path)
	if not res:
		Log.log("[VTK] _build_slot_data: can't load " + path)
		return null
	var amount = float(item_data.get("amount")) if item_data.has("amount") else 1.0
	var slotData = SlotData.new()
	slotData.itemData = res
	var is_mag: bool = item_data.has("count") and _is_magazine(res)
	if is_mag:
		slotData.amount = _mag_unit(res, bool(item_data.get("full_mag", true)))
	elif str(res.get("type")) == "Weapon":
		var mag = res.get("magazineSize")
		var maxAm = res.get("maxAmount")
		slotData.amount = _whole(mag if mag != null else (maxAm if maxAm != null else amount))
		slotData.chamber = true
	else:
		slotData.amount = _whole(amount)

	var attachments = item_data.get("attachments") if item_data.has("attachments") else []
	if is_mag:
		# Обойма: слот «обвесы» отдан под тумблер заполнения, поэтому
		# вложенные патроны сюда не попадают. Игра их всё равно не читает —
		# amount обоймы целиком задаёт maxAmount.
		attachments = []
	if attachments is Array and attachments.size() > 0:
		var arr = _nested_array(slotData)
		for att_path in attachments:
			var att_res = load(str(att_path))
			if att_res != null:
				arr.append(att_res)
	elif str(res.get("type")) == "Weapon":
		var compat = res.get("compatible")
		if compat is Array:
			for cd in compat:
				if cd != null and str(cd.get("subtype")) == "Magazine":
					_nested_array(slotData).append(cd)
					break
	return slotData

# Игра выводит amount как есть, поэтому спавненные 116.0 патронов показывались
# игроку как "116.0", хотя разрядка обоймы в игре даёт "116".
# Целые значения отдаём int'ом. Дробные (например 0.5) сохраняем float'ом:
# обрезать их нельзя, иначе предмет выродится в amount <= 0 и исчезнет.
static func _whole(v) -> Variant:
	var f := float(v)
	if is_equal_approx(f, round(f)):
		return int(round(f))
	return f

static func _nested_array(slotData) -> Array:
	var arr = slotData.get("nested")
	if typeof(arr) != TYPE_ARRAY:
		arr = []
		slotData.set("nested", arr)
	return arr

static func _insert(interface, ig, slotData) -> Node:
	var before := {}
	if ig != null and is_instance_valid(ig):
		for child in ig.get_children():
			if is_instance_valid(child):
				before[child.get_instance_id()] = true
	# Обоймы не проходят через AutoStack: у них stackable = false, и стекер
	# либо съедает слот, либо теряет amount. JCM для обойм зовёт Create напрямую.
	if _is_magazine(slotData.get("itemData")):
		interface.Create(slotData, ig, true)
	elif interface.has_method("AutoStack"):
		if not interface.AutoStack(slotData, ig):
			interface.Create(slotData, ig, true)
	else:
		interface.Create(slotData, ig, true)
	if ig == null or not is_instance_valid(ig):
		return null
	for child in ig.get_children():
		if is_instance_valid(child) and not before.has(child.get_instance_id()):
			return child
	return _find_node_for_sd(ig, slotData)

static func _find_node_for_sd(ig, sd) -> Node:
	if ig == null or not is_instance_valid(ig) or sd == null:
		return null
	for child in ig.get_children():
		if is_instance_valid(child) and child.get("slotData") == sd:
			return child
	var res = sd.get("itemData")
	if res == null:
		return null
	for child in ig.get_children():
		if not is_instance_valid(child):
			continue
		var csd = child.get("slotData")
		if csd != null and csd.get("itemData") == res:
			return child
	return null

static func _slot_is_free(sl) -> bool:
	for c in sl.get_children():
		if is_instance_valid(c) and c.get("slotData") != null:
			return false
	return true

# Слот оборудования несёт скрипт Slot.gd со свойством hint. Проверяется именно
# свойство, а не класс: оверлей Equipment/Hints состоит из Label'ов с теми же
# именами (Primary, Helmet, ...), и без этой проверки занятый слот подменялся
# подписью из Hints — предмет «экипировался» в Label вместо отказа и ухода в
# инвентарь: визуальный призрак и повторный сет, посчитанный как fitted.
static func _is_equip_slot(n) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	for p in n.get_property_list():
		if str(p.get("name")) == "hint":
			return true
	return false

static func _find_free_slot(node, wanted: Dictionary, depth: int) -> Node:
	if node == null or not is_instance_valid(node) or depth > 3:
		return null
	for sl in node.get_children():
		if is_instance_valid(sl) and _is_equip_slot(sl) and wanted.has(str(sl.name).to_lower()) and _slot_is_free(sl):
			return sl
	if depth >= 3:
		return null
	for sl in node.get_children():
		if is_instance_valid(sl):
			var r = _find_free_slot(sl, wanted, depth + 1)
			if r != null:
				return r
	return null

# Занятый слот, в котором лежит ровно тот же itemData. Нужен авто-экипировке:
# свободных слотов нет, но экипированный стак совпадает — туда можно доложить.
static func _find_occupied_slot(node, item_res, depth: int) -> Node:
	if node == null or not is_instance_valid(node) or depth > 3 or item_res == null:
		return null
	for sl in node.get_children():
		if is_instance_valid(sl) and _is_equip_slot(sl) and not _slot_is_free(sl):
			for c in sl.get_children():
				if is_instance_valid(c):
					var csd = c.get("slotData")
					if csd != null and csd.get("itemData") == item_res:
						return sl
	for sl in node.get_children():
		if is_instance_valid(sl):
			var r = _find_occupied_slot(sl, item_res, depth + 1)
			if r != null:
				return r
	return null

static func _slot_item(sl) -> Node:
	if sl == null or not is_instance_valid(sl):
		return null
	for c in sl.get_children():
		if is_instance_valid(c) and c.get("slotData") != null:
			return c
	return null

# Вставить предмет в слот экипировки и вернуть true при успехе. Свободный слот
# ищется ДО interface.Create: иначе на занятом слоте предмет успевал лечь в
# inventoryGrid и оставался там — повторный Apply каждого предмета плодил дубль
# и переполнял сетку (иконки-призраки поверх HUD). Занятый или отсутствующий
# слот теперь пропускается, не создавая узла.
static func _equip_sd(interface, ig, equip_root, sd, preferred: String) -> bool:
	if equip_root == null or not is_instance_valid(equip_root):
		return false
	var res = sd.get("itemData")
	if res == null:
		return false
	var slots = res.get("slots")
	if not (slots is Array) or slots.size() == 0:
		return false
	var order := []
	if preferred != "" and slots.has(preferred):
		order.append(preferred)
	for s in slots:
		var n = str(s)
		if not order.has(n):
			order.append(n)
	var wanted := {}
	for n in order:
		wanted[str(n).to_lower()] = true
	var sl = _find_free_slot(equip_root, wanted, 0)
	if sl == null:
		return false
	var node := _insert(interface, ig, sd)
	if node == null:
		Log.log("[VTK] _equip_sd: no grid node for " + str(res.get("name")))
		return false
	if ig.has_method("Pick"):
		ig.Pick(node)
	interface.Equip(node, sl)
	return true

static func _notify(loader, text: String, color: Color) -> void:
	if loader and loader.has_method("Message"):
		loader.Message(text, color)
