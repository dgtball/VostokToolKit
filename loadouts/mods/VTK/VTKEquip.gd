extends RefCounted

# Логика авто-экипировки: что делать с предметом, попавшим в инвентарь, и
# арифметика докладывания в уже экипированный стек. Ни load(), ни путей внутрь
# игры: item_res/occupant_res приходят как Resource или Dictionary, читаются
# через get(), поэтому покрыто headless-тестом test_equip.gd.

static func slot_names(item_res) -> Array:
	var out: Array = []
	if item_res == null:
		return out
	var slots = item_res.get("slots")
	if slots is Array:
		for s in slots:
			var n := str(s)
			if n != "" and not out.has(n):
				out.append(n)
	return out

static func is_equipment(item_res) -> bool:
	return not slot_names(item_res).is_empty()

# Множество имён слотов в нижнем регистре — формат, который ждёт
# VTKData._find_free_slot (сравнивает с to_lower имени слота).
static func wanted_slots(item_res) -> Dictionary:
	var wanted := {}
	for n in slot_names(item_res):
		wanted[str(n).to_lower()] = true
	return wanted

# Тот же самый предмет: сначала тождество ресурса, иначе совпадение file.
static func same_item(a, b) -> bool:
	if a == null or b == null:
		return false
	if a == b:
		return true
	var fa := str(a.get("file", ""))
	return fa != "" and fa == str(b.get("file", ""))

# Судьба предмета, попавшего в инвентарь:
#   слот свободен (occupant == null)          -> "equip"
#   слот занят тем же стакающимся             -> "merge"
#   слот занят другим / предмет нестакающийся -> "skip"
static func decide(item_res, occupant_res) -> String:
	if item_res == null:
		return "skip"
	if occupant_res == null:
		return "equip"
	if same_item(item_res, occupant_res) and bool(item_res.get("stackable", false)):
		return "merge"
	return "skip"

# Сколько (amount) из входящего стека уедет в экипированный:
# {"moved": float, "leftover": float}. moved не больше свободного места
# (max_amount - occupant); остаток остаётся в инвентаре. Нет ёмкости
# (max_amount <= 0) — не переносим ничего, предмет остаётся целым.
static func merge_amounts(incoming, occupant, max_amount) -> Dictionary:
	var inc := float(incoming)
	var occ := float(occupant)
	var cap := float(max_amount)
	if cap <= 0.0:
		cap = occ
	var room := cap - occ
	if room < 0.0:
		room = 0.0
	var moved := inc if inc < room else room
	if moved < 0.0:
		moved = 0.0
	return {"moved": moved, "leftover": inc - moved}
