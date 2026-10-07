extends Node
const Loc = preload("res://mods/VTK/VTKLoc.gd")

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
		print("[VTK] save file migration failed: cannot open ", src_path)
		return
	var text := src.get_as_text()
	src.close()
	var dst_path := SAVE_FILE.get_base_dir() + "/" + dst_name
	var dst = FileAccess.open(dst_path, FileAccess.WRITE)
	if dst == null:
		print("[VTK] save file migration failed: cannot write ", dst_path)
		return
	dst.store_string(text)
	dst.close()
	var r := DirAccess.remove_absolute(ProjectSettings.globalize_path(src_path))
	if r != OK:
		print("[VTK] save file migration: copied ", dst_name,
			", failed to remove ", src_path, " (code ", str(r), ")")
		return
	print("[VTK] save file migrated: ", src_path.get_file(), " -> ", dst_name)

static func _root_node() -> Node:
	var tree = Engine.get_main_loop()
	if tree is SceneTree:
		return tree.root
	return null

# ---------- storage ----------

static func get_all() -> Array:
	var file = FileAccess.open(SAVE_FILE, FileAccess.READ)
	if not file:
		return []
	var text = file.get_as_text()
	file.close()
	if text.is_empty():
		return []
	var json = JSON.new()
	if json.parse(text) != OK:
		return []
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY or not data.has("loadouts"):
		return []
	var arr = data["loadouts"]
	if typeof(arr) != TYPE_ARRAY:
		return []
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
	var file = FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify({"loadouts": loadouts}))
	file.close()

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

static func _slots_of(desc) -> Array:
	if typeof(desc) != TYPE_DICTIONARY:
		return []
	var res = load(str(desc.get("path")))
	if res == null:
		return []
	var slots = res.get("slots")
	if not (slots is Array):
		return []
	return slots

# ---------- legacy-compatible writes (used by the old panel) ----------

static func add(set_name: String, items: Array) -> void:
	var all = get_all()
	for i in range(all.size()):
		if typeof(all[i]) == TYPE_DICTIONARY and str(all[i].get("name")) == set_name:
			all[i] = _from_items(set_name, items, all[i])
			save_all(all)
			return
	all.append(_from_items(set_name, items, {}))
	save_all(all)

static func update(old: String, new_name: String, items: Array) -> void:
	var all = get_all()
	for i in range(all.size()):
		if typeof(all[i]) == TYPE_DICTIONARY and str(all[i].get("name")) == old:
			all[i] = _from_items(new_name, items, all[i])
			save_all(all)
			return

static func _from_items(set_name: String, items: Array, keep) -> Dictionary:
	var out := _norm(keep)
	out["name"] = set_name
	_split_legacy(items, out)
	return out

static func remove(name: String) -> void:
	var all = get_all()
	var kept := []
	for ld in all:
		if typeof(ld) == TYPE_DICTIONARY and str(ld.get("name")) == name:
			continue
		kept.append(ld)
	save_all(kept)

static func rename(old: String, new_name: String) -> void:
	var all = get_all()
	for i in range(all.size()):
		if typeof(all[i]) == TYPE_DICTIONARY and str(all[i].get("name")) == old:
			all[i]["name"] = new_name
			save_all(all)
			return

# ---------- item-level edits ----------

static func set_equip_item(set_name: String, slot: String, src) -> void:
	var all = get_all()
	for i in range(all.size()):
		if typeof(all[i]) != TYPE_DICTIONARY or str(all[i].get("name")) != set_name:
			continue
		var n := _norm(all[i])
		var eq: Dictionary = n["equip"]
		if src == null:
			eq.erase(slot)
		else:
			eq[slot] = _desc(src)
		n["equip"] = eq
		all[i] = n
		save_all(all)
		return

static func add_gear_item(set_name: String, src) -> void:
	var all = get_all()
	for i in range(all.size()):
		if typeof(all[i]) != TYPE_DICTIONARY or str(all[i].get("name")) != set_name:
			continue
		var n := _norm(all[i])
		var gr: Array = n["gear"]
		gr.append(_desc(src))
		n["gear"] = gr
		all[i] = n
		save_all(all)
		return

static func remove_gear_item(set_name: String, index: int) -> void:
	var all = get_all()
	for i in range(all.size()):
		if typeof(all[i]) != TYPE_DICTIONARY or str(all[i].get("name")) != set_name:
			continue
		var n := _norm(all[i])
		var gr: Array = n["gear"]
		if index < 0 or index >= gr.size():
			return
		gr.remove_at(index)
		n["gear"] = gr
		all[i] = n
		save_all(all)
		return

static func set_gear_amount(set_name: String, index: int, amount: float) -> void:
	var all = get_all()
	for i in range(all.size()):
		if typeof(all[i]) != TYPE_DICTIONARY or str(all[i].get("name")) != set_name:
			continue
		var n := _norm(all[i])
		var gr: Array = n["gear"]
		if index < 0 or index >= gr.size():
			return
		var d := _desc(gr[index])
		d["amount"] = maxf(0.0, amount)
		gr[index] = d
		n["gear"] = gr
		all[i] = n
		save_all(all)
		return

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

static func create_empty(set_name: String) -> bool:
	var all = get_all()
	for ld in all:
		if typeof(ld) == TYPE_DICTIONARY and str(ld.get("name")) == set_name:
			return false
	all.append({"name": set_name, "quick_key": 0, "equip": {}, "gear": []})
	save_all(all)
	return true

static func item_count(name: String) -> int:
	var p = get_set(name)
	if p.is_empty():
		return 0
	var eq: Dictionary = p["equip"]
	var gr: Array = p["gear"]
	return eq.size() + gr.size()

static func flat_items(ld) -> Array:
	var n := _norm(ld)
	var out := []
	var eq: Dictionary = n["equip"]
	for k in eq.keys():
		var d := _desc(eq[k])
		d["slot"] = str(k)
		out.append(d)
	var gr: Array = n["gear"]
	for g in gr:
		out.append(_desc(g))
	return out

# ---------- hotkeys ----------

static func set_quick_key(name: String, keycode: int) -> void:
	var all = get_all()
	for i in range(all.size()):
		if typeof(all[i]) == TYPE_DICTIONARY and str(all[i].get("name")) == name:
			all[i]["quick_key"] = keycode
			save_all(all)
			return

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

static func spawn_loadout(name: String) -> void:
	apply_loadout(name, false)

static func apply_loadout(name: String, equip: bool) -> void:
	var pack = get_set(name)
	if pack.is_empty():
		return
	var root = _root_node()
	if not root:
		return
	var interface = root.get_node_or_null("Map/Core/UI/Interface")
	if not interface:
		print("[VTK] apply_loadout: no Interface node")
		return
	var loader = root.get_node_or_null("Loader")
	var ig = interface.get("inventoryGrid")
	if ig == null or not is_instance_valid(ig):
		print("[VTK] apply_loadout: no inventoryGrid")
		return

	var will_equip := equip and interface.has_method("Equip")
	if equip and not will_equip:
		print("[VTK] interface.Equip unavailable, inventory only")
	var equip_root = interface.get("equipment") if will_equip else null
	if will_equip and (equip_root == null or not is_instance_valid(equip_root)):
		will_equip = false
		equip_root = null

	var own := []
	var fitted := 0
	var skipped := 0

	if will_equip:
		var eq: Dictionary = pack["equip"]
		for slot_name in eq.keys():
			var desc: Dictionary = eq[slot_name]
			var sd = _build_slot_data(desc)
			if sd == null:
				continue
			var node := _insert(interface, ig, sd)
			own.append(sd)
			var used := _equip_into(interface, ig, equip_root, sd, str(slot_name), node)
			if used == "":
				skipped += 1
				print("[VTK] slot busy or missing: " + str(desc.get("name")) + " -> " + str(slot_name))
			else:
				fitted += 1

	var gear: Array = pack["gear"]
	for desc in gear:
		if typeof(desc) != TYPE_DICTIONARY:
			continue
		for i in range(_instances(desc)):
			var gsd = _build_slot_data(desc)
			if gsd == null:
				break
			_insert(interface, ig, gsd)
			own.append(gsd)

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

	print("[VTK] apply '" + name + "' equip=" + str(equip)
		+ " fitted=" + str(fitted) + " skipped=" + str(skipped)
		+ " grid=" + str(grid_count) + " reset=skipped saved=1")

	if not equip:
		_notify(loader, Loc.txt("Loadout \"") + name + Loc.txt("\" → to inventory: ") + str(grid_count), Color.GREEN)
		return

	var msg := Loc.txt("Loadout \"") + name + Loc.txt("\" applied")
	if fitted > 0:
		msg += Loc.txt(" \u00b7 Equipped: ") + str(fitted)
	if skipped > 0:
		msg += Loc.txt(" \u00b7 Occupied slots: ") + str(skipped)
	if grid_count > 0:
		msg += Loc.txt(" \u00b7 In inventory: ") + str(grid_count)
	_notify(loader, msg, Color.GREEN)

# ---------- internals ----------

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

# Сколько отдельных предметов создавать из одного descriptor'а.
static func _instances(desc: Dictionary) -> int:
	if not desc.has("count"):
		return 1
	return clampi(int(desc.get("count", 1)), 0, 32)

static func _build_slot_data(item_data):
	if typeof(item_data) != TYPE_DICTIONARY:
		return null
	var path = str(item_data.get("path"))
	if path == "":
		return null
	var res = load(path)
	if not res:
		print("[VTK] _build_slot_data: can't load " + path)
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

static func _find_free_slot(node, wanted: Dictionary, depth: int) -> Node:
	if node == null or not is_instance_valid(node) or depth > 3:
		return null
	for sl in node.get_children():
		if is_instance_valid(sl) and wanted.has(str(sl.name).to_lower()) and _slot_is_free(sl):
			return sl
	if depth >= 3:
		return null
	for sl in node.get_children():
		if is_instance_valid(sl):
			var r = _find_free_slot(sl, wanted, depth + 1)
			if r != null:
				return r
	return null

static func _equip_into(interface, ig, equip_root, sd, preferred: String, node) -> String:
	if equip_root == null or not is_instance_valid(equip_root):
		return ""
	var res = sd.get("itemData")
	if res == null:
		return ""
	var slots = res.get("slots")
	if not (slots is Array) or slots.size() == 0:
		return ""
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
	if node == null:
		node = _find_node_for_sd(ig, sd)
	if node == null:
		print("[VTK] _equip_into: no grid node for " + str(res.get("name")))
		return ""
	var sl = _find_free_slot(equip_root, wanted, 0)
	if sl == null:
		return ""
	if ig.has_method("Pick"):
		ig.Pick(node)
	interface.Equip(node, sl)
	return str(sl.name)

static func _notify(loader, text: String, color: Color) -> void:
	if loader and loader.has_method("Message"):
		loader.Message(text, color)
