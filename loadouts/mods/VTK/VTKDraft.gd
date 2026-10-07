extends RefCounted

# Черновик сета. Чистая логика: ни load(), ни путей внутрь игры.
# Слоты приходят снаружи уже вычитанными из ресурса предмета — поэтому черновик
# тестируется headless, без копии игры.

var set_name: String = ""
var equip: Dictionary = {}
var gear: Array = []

func _init(p_name: String = "", p_equip: Dictionary = {}, p_gear: Array = []) -> void:
	set_name = p_name
	equip = p_equip.duplicate(true)
	gear = p_gear.duplicate(true)

static func slot_of(slots) -> String:
	if typeof(slots) != TYPE_ARRAY or slots.size() == 0:
		return ""
	return str(slots[0])

# Первый свободный слот из списка. Grenade_1, Grenade_2 и прочие кратные
# слоты занимаются по очереди, поэтому две гранаты в одном сете возможны.
func free_slot_of(slots) -> String:
	if typeof(slots) != TYPE_ARRAY:
		return ""
	for s in slots:
		var n := str(s)
		if n != "" and not equip.has(n):
			return n
	return ""

static func slot_label(slots) -> String:
	if typeof(slots) != TYPE_ARRAY:
		return ""
	var names := []
	for s in slots:
		names.append(str(s))
	return ", ".join(names)

static func _desc(path: String, item_name: String, amount: float, type_name: String) -> Dictionary:
	return {"name": item_name, "path": path, "amount": amount, "type": type_name}

# counted = true для обойм. Обойма в игре stackable = false, а её amount — это
# количество патронов внутри. Поэтому в сете обоймы считаются штуками в
# отдельном ключе "count", а amount с момента применения сета считается из
# ресурса (maxAmount) и зависит от переключателя full mag.
func add(path: String, item_name: String, slots, amount: float, type_name: String, counted: bool = false) -> String:
	var amt := maxf(0.0, amount)
	var slot := free_slot_of(slots)
	if slot != "":
		equip[slot] = _desc(path, item_name, amt, type_name)
		return slot
	var idx := gear_index_of(path)
	if idx >= 0:
		if gear[idx].has("count"):
			gear[idx]["count"] = int(gear[idx].get("count", 1)) + 1
		else:
			gear[idx]["amount"] = float(gear[idx].get("amount", 1.0)) + 1.0
		return ""
	var d := _desc(path, item_name, amt, type_name)
	if counted:
		d["count"] = 1
		d["amount"] = 0.0
		d["full_mag"] = true
	gear.append(d)
	return ""

# Положить предмет в конкретный слот. Занятый слот вытесняется: содержимое
# уходит из сета целиком, потому что оружие или броня в снаряжении бессмысленны,
# а молчаливый перенос пугает сильнее явного удаления.
# "" означает "слот непригоден" - вызывающий код откатывается на add().
func add_to_slot(path: String, item_name: String, slots, amount: float,
		type_name: String, slot: String, counted: bool = false) -> String:
	# У обоймы счётчик в count, а в слоре descriptor живёт с amount. Слотов у
	# обоймы нет, так что ветка недостижима, но подстраховка стоит одну строку.
	if counted:
		return ""
	if slot == "" or typeof(slots) != TYPE_ARRAY:
		return ""
	var fits := false
	for s in slots:
		if str(s) == slot:
			fits = true
			break
	if not fits:
		return ""
	# Присваивание по ключу и есть вытеснение: старый descriptor заменяется целиком,
	# вместе со своими обвесами. Erase не нужен, а проверка слота выше гарантирует,
	# что отказ ничего не тронул.
	equip[slot] = _desc(path, item_name, maxf(0.0, amount), type_name)
	return slot

func equip_slot_of(path: String) -> String:
	for k in equip.keys():
		if typeof(equip[k]) == TYPE_DICTIONARY and str(equip[k].get("path")) == path:
			return str(k)
	return ""

func _equip_desc(path: String) -> Dictionary:
	for k in equip.keys():
		if typeof(equip[k]) == TYPE_DICTIONARY and str(equip[k].get("path")) == path:
			return equip[k]
	return {}

func gear_index_of(path: String) -> int:
	for i in range(gear.size()):
		if typeof(gear[i]) == TYPE_DICTIONARY and str(gear[i].get("path")) == path:
			return i
	return -1

func has_path(path: String) -> bool:
	if equip_slot_of(path) != "":
		return true
	return gear_index_of(path) >= 0

func amount_of(path: String) -> float:
	return float(shown_count(descriptor_of(path)))

# Что показывать в поле количества. У обойм это "count" — число обойм,
# у всего остального "amount". UI обязан читать через эту функцию, иначе
# обойма показывает свой служебный amount 0 вместо выбранного количества.
static func shown_count(desc) -> int:
	if typeof(desc) != TYPE_DICTIONARY or desc.is_empty():
		return 0
	if desc.has("count"):
		return int(desc.get("count", 1))
	return int(round(float(desc.get("amount", 1.0))))

# Заполненная ли обойма. Хранится на самом descriptor'е, потому что у каждой
# обоймы в сете своё состояние. Отсутствие ключа = включено (по умолчанию ВКЛ).
static func is_full(desc) -> bool:
	if typeof(desc) != TYPE_DICTIONARY:
		return true
	return bool(desc.get("full_mag", true))

func set_full_mag(path: String, on: bool) -> void:
	var d := descriptor_of(path)
	if not d.is_empty():
		d["full_mag"] = on

func descriptor_of(path: String) -> Dictionary:
	var d := _equip_desc(path)
	if not d.is_empty():
		return d
	var idx := gear_index_of(path)
	if idx >= 0:
		return gear[idx]
	return {}

func set_attachments(path: String, atts: Array) -> void:
	var d := descriptor_of(path)
	if not d.is_empty():
		d["attachments"] = atts.duplicate(true)

# Обвес одиночный по группе: два прицела на стволе невалидны, поэтому выбор
# другого выбрасывает прежнего из той же группы, а повторный клик снимает.
# grp_of - Callable "путь обвеса -> группа", потому что черновик не грузит
# ресурсы. Пустой итог удаляет ключ, а не оставляет пустой массив.
func toggle_attachment(owner_path: String, att_path: String, grp: String,
		grp_of: Callable) -> void:
	var d := descriptor_of(owner_path)
	if d.is_empty() or att_path == "":
		return
	var atts: Array = []
	if typeof(d.get("attachments")) == TYPE_ARRAY:
		atts = d["attachments"]
	if atts.find(att_path) >= 0:
		atts.erase(att_path)
		# Ключ убирается только когда список опустел. Без проверки снятие одного
		# прицела стирало бы дуло и цевьё, выбранные раньше.
		if atts.is_empty():
			d.erase("attachments")
		return
	# Группа, заявленная вызывающим, сверяется с настоящей: опечатка в разметке
	# панели иначе молча вычистила бы чужую группу обвесов.
	var real_grp := grp
	if grp_of.is_valid():
		real_grp = str(grp_of.call(att_path))
	if real_grp == "":
		real_grp = grp
	var keep: Array = []
	for p in atts:
		if not grp_of.is_valid() or str(grp_of.call(str(p))) != real_grp:
			keep.append(p)
	keep.append(att_path)
	d["attachments"] = keep

# Выбран ли конкретный обвес у предмета. Спрашивается плиткой для каждого
# обвеса панели, поэтому ответ должен быть про этот обвес, а не про "первый в
# списке": у ствола одновременно стоят прицел, коллиматор и дуло, и золотым
# должен быть каждый выбор. Пустой путь - это не обвес, а совпадение с мусором
# в списке.
func has_attachment(owner_path: String, att_path: String) -> bool:
	if att_path == "":
		return false
	var d := descriptor_of(owner_path)
	var ats = d.get("attachments")
	if typeof(ats) != TYPE_ARRAY:
		return false
	return ats.has(att_path)

func remove_slot(slot: String) -> void:
	equip.erase(slot)

func remove_gear(path: String) -> void:
	var idx := gear_index_of(path)
	if idx >= 0:
		gear.remove_at(idx)

func set_gear_amount(path: String, amount: float) -> void:
	if amount <= 0.0:
		remove_gear(path)
		return
	var idx := gear_index_of(path)
	if idx < 0:
		return
	if gear[idx].has("count"):
		gear[idx]["count"] = max(1, int(round(amount)))
		return
	gear[idx]["amount"] = amount

func clear() -> void:
	equip.clear()
	gear.clear()

func is_empty() -> bool:
	return equip.is_empty() and gear.is_empty()

func equip_count() -> int:
	return equip.size()

func item_count() -> int:
	return equip.size() + gear.size()

func to_saved() -> Dictionary:
	return {"equip": equip.duplicate(true), "gear": gear.duplicate(true)}

func load_from(ld) -> void:
	if typeof(ld) != TYPE_DICTIONARY:
		return
	set_name = str(ld.get("name", ""))
	var eq = ld.get("equip")
	equip = eq.duplicate(true) if typeof(eq) == TYPE_DICTIONARY else {}
	var gr = ld.get("gear")
	gear = gr.duplicate(true) if typeof(gr) == TYPE_ARRAY else []
