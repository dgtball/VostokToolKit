extends RefCounted

const VTKData = preload("res://mods/VTK/VTKData.gd")

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
	var fa := str(VTKData.prop(a, "file", ""))
	return fa != "" and fa == str(VTKData.prop(b, "file", ""))

# Судьба предмета, попавшего в инвентарь:
#   слот свободен (occupant == null)          -> "equip"
#   слот занят тем же стакающимся             -> "merge"
#   слот занят другим / предмет нестакающийся -> "skip"
static func decide(item_res, occupant_res) -> String:
	if item_res == null:
		return "skip"
	if occupant_res == null:
		return "equip"
	if same_item(item_res, occupant_res) and bool(VTKData.prop(item_res, "stackable", false)):
		return "merge"
	return "skip"

# Доля стака, уходящая при Split: ванильная формула (целочисленное деление
# amount / 2, см. Interface.ContextSplit).
static func split_share(amount: int) -> int:
	return int(amount / 2.0)

# Доля стака, уходящая при Take: ванильный defaultAmount предмета.
static func take_share(default_amount: int) -> int:
	return default_amount

# Свободное место в слоте: maxAmount минус занятое. -1 = лимита нет
# (нестакающийся предмет, maxAmount <= 0), место не ограничено.
static func equip_space(max_amount: int, occupied: int) -> int:
	if max_amount <= 0:
		return -1
	var s := max_amount - occupied
	return s if s > 0 else 0

# Сколько уедет из подобранного: не больше свободного места слота.
static func equip_move(picked: int, occupied: int, max_amount: int) -> int:
	var p := picked if picked > 0 else 0
	var room := equip_space(max_amount, occupied)
	if room < 0:
		return p
	return p if p < room else room
