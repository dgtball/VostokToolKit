extends RefCounted
## Чистые решения выбора предметов: слоты, фильтры, полосы категорий, группы
## обвесов. Ни load(), ни путей внутрь игры - поэтому файл тестируется headless,
## как VTKDraft. Всё, что знает про ресурсы, приходит снаружи готовыми данными.

# Порядок слотов в списке выбора. Это предпочтение, а не жёсткий список: слот
# из данных, которого здесь нет, не теряется, а дописывается в конец. И наоборот -
# предпочтительного слота, которого в игре нет, в списке не появляется, так что
# после обновления игры пустых строк не прибавится.
const SLOT_ORDER := ["Primary", "Secondary", "Melee", "Body", "Head",
	"Backpack", "Pouches", "Grenade_1", "Grenade_2", "Flashlight", "Radio"]

# Полосы категорий: порядок полок и подписи в одной таблице. Ключ -
# str(item.type).to_lower() после CATEGORY_ALIASES, подпись - что видит игрок.
# Раньше порядок жил здесь, а подписи в VTKUI.gd как CATEGORY_LABELS, и они
# разъезжались: одну и ту же категорию приходилось вписывать в оба места.
# Категория из данных, которой здесь нет, не теряется: встаёт в конец по
# алфавиту и подписывается через category_label() - обновление игры не даёт
# строчной подписи.
const CATEGORIES := [
	["weapon", "Weapons"],
	["armor", "Armor"],
	["@grenade", "Grenades"],
	["ammo", "Ammo"],
	["attachment", "Attachments"],
	["medical", "Medical"],
	["consumable", "Consumables"],
	["clothing", "Clothing"],
	["electronics", "Electronics"],
	["key", "Keys"],
	["knife", "Knives"],
	["literature", "Books"],
	["misc", "Misc"],
]

static var _art_cache: Dictionary = {}

# Кроп непрозрачной области иконки: AtlasTexture на оригинальном ресурсе, файлы
# игры не трогает. used_rect расширен на 3 пикселя и обрезан по границе текстуры,
# filter_clip убирает размытие по краю. Кэш по instance_id: иконки приходят из
# одного набора ресурсов и переживают перестроение UI.
static func item_art(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var key := texture.get_instance_id()
	if _art_cache.has(key):
		return _art_cache[key]
	var image := texture.get_image()
	if image == null:
		return texture
	if image.is_compressed():
		image.decompress()
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return texture
	var rect := Rect2(used).grow(3.0).intersection(Rect2(Vector2.ZERO, texture.get_size()))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return texture
	var art := AtlasTexture.new()
	art.atlas = texture
	art.region = rect
	art.filter_clip = true
	_art_cache[key] = art
	return art

# Ключи категорий в порядке полок.
static func category_keys() -> Array:
	var out: Array = []
	for entry in CATEGORIES:
		out.append(str(entry[0]))
	return out

# Подпись полки по ключу категории. Неизвестный ключ не возвращается сырым:
# capitalize() даёт "Furniture", а не "furniture". Вызывать только для
# категории, не для подкатегории: у подкатегорий ключ уже в игровом регистре
# и в нём бывает "&" и "SMG", которые capitalize() поломал бы.
static func category_label(key: String) -> String:
	for entry in CATEGORIES:
		if str(entry[0]) == key:
			return str(entry[1])
	return key.capitalize()

# Сводка типов, которые в данных игры не совпадают с группой, в которую их
# ждёт игрок. Одна и та же еда приходит и как "Consumable", и как
# "Consumables", у Sticks - " Misc" с ведущим пробелом, и отдельные типы
# дробят полки на пустые подписи: рыба уходит в еду, разгрузка в броню,
# подсумок, шлем и рюкзак в одежду, удочка с гитарой сходятся в "Разное", а
# type "Grenade" без гранатного слота давал вторую полку рядом с @grenade.
# Отдельными полками стояли Instruments, Lore и Backpacks - подпись каждой
# приходилось держать в двух таблицах разом.
# Подкатегории при этом не трогаются - их считает subcategory_of по пути.
const CATEGORY_ALIASES := {
	"consumables": "consumable",
	"fish": "consumable",
	"rig": "armor",
	"belt pouch": "clothing",
	"helmet": "clothing",
	"backpack": "clothing",
	"fishing": "misc",
	"instrument": "misc",
	"lore": "misc",
	"grenade": "@grenade",
}

# Порядок подкатегорий - как заголовки "-- X --" в JCMDatabase.gd, минус
# FURNITURE: там res://Assets, это не предметы для сета.
const SUBCATEGORY_ORDER := ["Assault Rifles", "Sniper Rifles", "Shotguns",
	"Pistols", "SMGs",
	"Handgun & SMG Mags", "Rifle & Sniper Mags",
	"Pistol & SMG Calibers", "Rifle Calibers", "Shotgun Shells",
	"First Aid", "Medication", "Utility",
	"Helmets", "Armor Plates", "Rigs & Vests", "Backpacks",
	"Belts", "Hats", "Torso", "Pants", "Boots & Hands",
	"Weapon Parts", "Scopes", "Suppressors", "Lasers",
	"Hydration", "Canned Goods", "Snacks & Ingredients", "Cooked Meals",
	"Vices", "Fish", "Garbage",
	"Utilities & Tools", "Music", "Fishing", "Lore"]

# Имя папки -> подкатегория. Ключ - третий сегмент пути
# ("res://Items/Weapons/AKM/AKM.tres" -> "AKM"), потому что второй сегмент
# повторяется: "Weapons" в JCM встречается семь раз. Пути в игру здесь не
# хранятся - только имена папок, поэтому апдейт игры таблицу не ломает.
const SUB_FOLDERS := {
	# Оружие
	"AK-12": "Assault Rifles", "AKM": "Assault Rifles",
	"AKS-74U": "Assault Rifles", "HK416": "Assault Rifles",
	"KAR-21": "Assault Rifles", "M4A1": "Assault Rifles",
	"MK18": "Assault Rifles", "RK-62": "Assault Rifles",
	"RK-95": "Assault Rifles",
	"M28": "Sniper Rifles", "M78": "Sniper Rifles", "Mosin": "Sniper Rifles",
	"SVD": "Sniper Rifles", "VSS": "Sniper Rifles",
	"Remington_870": "Shotguns",
	"Colt_1911": "Pistols", "Glock_17": "Pistols", "HP-DA": "Pistols",
	"Makarov": "Pistols", "P320": "Pistols",
	"Jatimatic": "SMGs", "KP-31": "SMGs", "MP5": "SMGs", "MP5K": "SMGs",
	"MP5SD": "SMGs", "MP7": "SMGs",
	# Боеприпасы
	"Ammo_45ACP": "Pistol & SMG Calibers", "Ammo_46x30": "Pistol & SMG Calibers",
	"Ammo_9x18": "Pistol & SMG Calibers", "Ammo_9x19": "Pistol & SMG Calibers",
	"Ammo_9x39": "Pistol & SMG Calibers",
	"Ammo_223": "Rifle Calibers", "Ammo_308": "Rifle Calibers",
	"Ammo_545x39": "Rifle Calibers", "Ammo_762x39": "Rifle Calibers",
	"Ammo_762x54R": "Rifle Calibers", "Ammo_12x70": "Shotgun Shells",
	# Медицина
	"AFAK": "First Aid", "Bandage": "First Aid",
	"Bandage_Improvised": "First Aid", "IFAK": "First Aid",
	"Medkit": "First Aid", "Splint": "First Aid",
	"Splint_Improvised": "First Aid", "Tourniquet": "First Aid",
	"Tourniquet_Improvised": "First Aid",
	"Antibiotics": "Medication", "Cold_Medicine": "Medication",
	"Melatonin": "Utility", "Painkillers": "Medication",
	"Antiseptic": "Utility", "Balm": "Utility",
	"Deodorant": "Utility", "Gum": "Utility",
	"Lotion": "Utility", "Saline": "Utility",
	"Thermal_Blanket": "Utility",
	"Tissues": "Utility", "Wipes": "Utility",
	# Снаряжение
	"Helmet_Police": "Helmets", "SSh-39": "Helmets",
	"LVPC": "Rigs & Vests", "K19": "Rigs & Vests",
	"Vest_Fishing": "Rigs & Vests",
	"Backpack_Jaeger": "Backpacks", "Backpack_Kantamus": "Backpacks",
	"Backpack_Nomad": "Backpacks", "Backpack_Patrol": "Backpacks",
	"Duffel_Retro": "Backpacks",
	"Kukkaro": "Belts",
	"Beanie_Flame": "Hats", "Cap_M62": "Hats", "Hat_Foil": "Hats",
	"Hat_Mosquito": "Hats", "Hat_Sauna": "Hats",
	"Fleece_Tactical_Brown": "Torso", "Fleece_Tactical_Green": "Torso",
	"Hoodie_Border_Zone": "Torso", "Hoodie_Gray": "Torso",
	"Jacket_M62": "Torso", "Jacket_Santa": "Torso",
	"Jacket_Winter_Blue": "Torso", "Jacket_Winter_Red": "Torso",
	"Windbreaker_Black": "Torso", "Windbreaker_Green": "Torso",
	"Jeans_Black": "Pants", "Pants_Hiking": "Pants",
	"Boots_Combat": "Boots & Hands", "Gloves_Leather": "Boots & Hands",
	"Gloves_Work": "Boots & Hands",
	# Обвесы. Три подкатегории по данным игры: subtype Optic даёт Scopes,
	# Laser - Lasers, Muzzle - глушители.
	"ACOG": "Scopes", "EXPS": "Scopes", "HMR": "Scopes", "Kobra": "Scopes",
	"Leopard": "Scopes", "MRO": "Scopes", "Micro": "Scopes",
	"POSP": "Scopes", "PRO": "Scopes", "PU": "Scopes", "RMR": "Scopes",
	"SRO": "Scopes", "Vudu": "Scopes",
	"OZ5": "Lasers", "ANPEQ": "Lasers",
	"Hybrid": "Suppressors", "Monster": "Suppressors", "Navy": "Suppressors",
	"PBS": "Suppressors", "PTN": "Suppressors", "Rider": "Suppressors",
	"Salvo": "Suppressors", "Thor": "Suppressors", "SOCOM": "Suppressors",
	# Еда
	"Energy_Drink": "Hydration", "Juice_Orange": "Hydration",
	"Juice_Pear": "Hydration", "Juice_Raspberry": "Hydration",
	"Soda_Lemon": "Hydration", "Water_Bottle": "Hydration",
	"Canned_Meat": "Canned Goods", "Canned_Meatballs": "Canned Goods",
	"Canned_Pea_Soup": "Canned Goods", "Canned_Peaches": "Canned Goods",
	"Canned_Peas": "Canned Goods",
	"Canned_Pear": "Canned Goods",
	"Canned_Pineapple": "Canned Goods", "Canned_Tomatoes": "Canned Goods",
	"Canned_Tuna": "Canned Goods", "Cat_Food": "Canned Goods",
	"Chocolate_War": "Snacks & Ingredients", "Coffee": "Snacks & Ingredients",
	"Crackers": "Snacks & Ingredients", "Energy_Powder": "Snacks & Ingredients",
	"Field_Ration": "Cooked Meals", "Jam": "Snacks & Ingredients",
	"Mustard": "Snacks & Ingredients", "Peanuts": "Snacks & Ingredients",
	"Potato": "Snacks & Ingredients", "Salty_Liquorice": "Snacks & Ingredients",
	"Sugar": "Snacks & Ingredients", "Yeast": "Snacks & Ingredients",
	"Coffee_Brewed": "Cooked Meals", "Cooked_Fish_Soup": "Cooked Meals",
	"Cooked_Meatballs": "Cooked Meals", "Cooked_Pea_Soup": "Cooked Meals",
	"Cooked_Tomato_Soup": "Cooked Meals", "Kompot": "Cooked Meals",
	"Beer": "Vices", "Cigarettes": "Vices", "Cigars": "Vices", "Kilju": "Vices",
	"Snus": "Vices",
	"Bream": "Fish", "Perch": "Fish", "Pike": "Fish", "Roach": "Fish",
	# Пустая тара: не расходник, а мусор.
	"Can_Empty": "Garbage", "Soda_Empty": "Garbage",
	# Разное. Ключи, книги, ножи, электроника и гранаты здесь не значатся: их
	# убирает NO_SUB_FOLDERS по верхней папке пути.
	"Aluminum_Foil": "Utilities & Tools", "Duct_Tape": "Utilities & Tools",
	"Happy_Stove": "Utilities & Tools", "Jerry_Can": "Utilities & Tools",
	"Lumber": "Utilities & Tools", "Matches": "Utilities & Tools",
	"Mess_Kit": "Utilities & Tools", "Nails": "Utilities & Tools",
	"Oil_Filter": "Utilities & Tools", "Sticks": "Utilities & Tools",
	"Toolbox": "Utilities & Tools", "Water_Lock": "Utilities & Tools",
	"Weapon_Repair_Kit": "Utilities & Tools",
	"Blanket": "Utilities & Tools", "Board_Game": "Utilities & Tools",
	"Bucket": "Utilities & Tools", "Coffee_Filter": "Utilities & Tools",
	"Map": "Utilities & Tools", "Map_Tactical": "Utilities & Tools",
	"Mattress": "Utilities & Tools", "Pillow": "Utilities & Tools",
	"Rags": "Utilities & Tools", "Sleeping_Bag": "Utilities & Tools",
	"Toilet_Paper": "Utilities & Tools",
	"Fishing_Rod": "Fishing", "Tackle_Box": "Fishing",
	"Guitar": "Music", "Harmonica": "Music",
	"Cat": "Lore", "Oil_Sample": "Lore", "Patient_Report": "Lore",
	# Бронеплиты: папки нет, путь трёхсегментный, ключ - имя файла.
	"Armor_Plate_II": "Armor Plates", "Armor_Plate_IIIA": "Armor Plates",
	"Armor_Plate_III": "Armor Plates", "Armor_Plate_III+": "Armor Plates",
	"Armor_Plate_IV": "Armor Plates",
	"Backpack_Bag": "Backpacks", "Potato_Box": "Canned Goods",
}

# Верхние папки, у которых подкатегория не считается: подписи там либо
# дублируют категорию (Books, Knives, Electronics, Grenades - единственная
# подкатегория в своей полке), либо дробят её на чипы, которые игрок просил
# убрать (Keys). Проверяется верхняя папка пути, а не список имён предметов:
# их много и они меняются с апдейтами игры.
const NO_SUB_FOLDERS := ["Keys", "Books", "Knives", "Electronics", "Grenades"]

# Папки, чей магазин относится к пистолетам и ПП. Остальные стволы дают
# Rifle & Sniper Mags. Список нужен потому, что папка у магазина та же, что
# у ствола: у Makarov она одна на Pistols и на Handgun & SMG Mags.
const MAG_FOLDERS := ["Makarov", "Colt_1911", "Glock_17", "P320", "HP-DA",
	"MP5", "MP5SD", "MP7", "Jatimatic", "KP-31", "MP5K"]

# Суффикс имени файла, по которым предмет опознаётся как магазин или часть
# ствола, раньше разбора папки. Без этого KAR-21_Barrel попал бы в
# Assault Rifles, а Makarov_Magazine - в Pistols.
const MAG_SUFFIXES := ["_Magazine", "_Mag", "_Drum"]
const WEAPON_PART_SUFFIXES := ["_Barrel", "_Muzzle", "_Grip"]


# Все слоты, встречающиеся у предметов, в предпочтительном порядке.
# На вход - список списков слотов, как их отдаёт item.slots.
static func all_slots(slot_lists) -> Array:
	var found := {}
	for s in slot_lists:
		if typeof(s) != TYPE_ARRAY:
			continue
		for one in s:
			# str(null) даёт "<null>", поэтому мусорный элемент отсекаем
			# сравнением, а не строкой: иначе в списке появился бы слот-призрак.
			if one == null:
				continue
			var n := str(one)
			if n != "":
				found[n] = true
	var out: Array = []
	for s in SLOT_ORDER:
		if found.has(s):
			out.append(s)
			found.erase(s)
	var rest := found.keys()
	rest.sort()
	for s in rest:
		out.append(str(s))
	return out

# Подходит ли предмет под выбранный слот-цель. Пустая цель - фильтр выключен,
# подходит всё. Строка вместо массива слотами не считается.
static func matches_slot(slots, slot: String) -> bool:
	if slot == "":
		return true
	if typeof(slots) != TYPE_ARRAY:
		return false
	for s in slots:
		if str(s) == slot:
			return true
	return false

# Группа предмета для полок и фасетов. Слоты важнее type: граната лежит в
# Grenade_1/2, а её type в данных игры не grenade, и группа "Гранаты" по одному
# type не набралась бы. Виртуальный ключ начинается с @, чтобы не совпасть с
# типом из данных. Ни слотов ни type - предмет вне групп, не показываем.
const CATEGORY_GRENADE := "@grenade"
const GRENADE_SLOTS := ["Grenade_1", "Grenade_2"]

static func category_of(slots, type) -> String:
	for gs in GRENADE_SLOTS:
		if matches_slot(slots, str(gs)):
			return CATEGORY_GRENADE
	if type == null:
		return ""
	var c := str(type).strip_edges().to_lower()
	return str(CATEGORY_ALIASES.get(c, c))

# Совпадение по имени без учёта регистра, подстрокой. Запрос из пробелов
# считается пустым, чтобы пробел вокруг слова его не отключал.
# Подкатегория предмета по его resource_path. Порядок правил важен:
# сначала суффикс имени файла, потом верхняя папка без подкатегории, потом
# папка предмета. Суффикс - потому что у KAR-21 и Makarov папка одна на два
# разных смысла. Папка предмета - третий сегмент пути, а у трёхсегментного
# (Armor_Plate_II.tres, Key_Attic.tres) её нет вовсе, и роль папки играет
# имя файла.
static func subcategory_of(path: String, type) -> String:
	if path == "" or type == null or str(type) == "":
		return ""
	# У мебели папка лежит в res://Assets и подпись из неё ничего не значит:
	# в фильтрах подкатегория не показывается, а в сет мебель не попадает.
	if str(type).strip_edges().to_lower() == "furniture":
		return ""
	var leaf := path.get_file()
	if leaf.get_extension() == "":
		return ""
	var stem := leaf.get_basename()
	for suf in WEAPON_PART_SUFFIXES:
		if stem.ends_with(suf):
			return "Weapon Parts"
	# res://Items/<папка>/<файл> - три сегмента после res://,
	# res://Items/<папка>/<ствол>/<файл> - четыре.
	var segs := path.trim_prefix("res://").split("/")
	var folder := ""
	if segs.size() >= 4:
		folder = segs[2]
	elif segs.size() == 3:
		folder = stem
	if folder == "":
		return ""
	if segs.size() >= 3 and NO_SUB_FOLDERS.has(segs[1]):
		return ""
	for suf in MAG_SUFFIXES:
		if stem.ends_with(suf):
			return "Handgun & SMG Mags" if MAG_FOLDERS.has(folder) else "Rifle & Sniper Mags"
	if SUB_FOLDERS.has(folder):
		return str(SUB_FOLDERS[folder])
	return folder

# Подкатегории в порядке таблицы, остальные - после них по алфавиту. Пустая
# строка отбрасывается: неопознанная папка не должна превращаться в чип.
static func order_subcategories(names) -> Array:
	var seen := {}
	for n in names:
		if str(n) != "":
			seen[str(n)] = true
	var out: Array = []
	for s in SUBCATEGORY_ORDER:
		if seen.has(s):
			out.append(s)
			seen.erase(s)
	var rest := seen.keys()
	rest.sort()
	for s in rest:
		out.append(str(s))
	return out

static func matches_search(item_name: String, query: String) -> bool:
	var q := query.strip_edges().to_lower()
	if q == "":
		return true
	return str(item_name).to_lower().find(q) >= 0

# Слоты, которые в игре занимает только оружие. Удилище, гитара и губная
# гармошка формально помечены слотами Primary/Secondary (тип Fishing и
# Instrument), поэтому без этого правила в фильтре шага 1 к Weapons
# доезжали лишние чипы, а предмет не относился к снаряжению.
const WEAPON_SLOTS := ["Primary", "Secondary"]

# Единственная категория, которую эти слоты предлагают. Пустая категория -
# предмет вне таксономии: он и раньше не попадал ни на какую полку, но из
# списка не выбрасывается, чтобы чип не стал единственным фильтром в пустоту.
static func category_allowed(cat: String, slot: String) -> bool:
	if not WEAPON_SLOTS.has(slot):
		return true
	return cat == "" or cat == "weapon"

# Полосы категорий в порядке CATEGORIES, пустые пропускаются.
# Элемент полосы: {"cat": String, "items": Array}. Элемент предмета:
# {"item": Resource, "cat": String} - cat это str(item.type).to_lower().
static func shelves_of(items) -> Array:
	var buckets: Dictionary = {}
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var c := str(it.get("cat", ""))
		if c == "":
			continue
		if not buckets.has(c):
			buckets[c] = []
		buckets[c].append(it)
	var out: Array = []
	for c in category_keys():
		if buckets.has(c):
			out.append({"cat": c, "items": buckets[c]})
			buckets.erase(c)
	var rest := buckets.keys()
	rest.sort()
	for c in rest:
		out.append({"cat": str(c), "items": buckets[c]})
	return out

# Фасеты левой колонки шага 2: строка "Все" первой, затем по строке на
# категорию. Пустые под текущим запросом выпадают - иначе фасет вёл бы в
# пустую сетку. На вход - записи _entry: нужен name для поиска и cat для
# группировки. Счётчик строки равен числу её элементов, поэтому клик по фасету
# всегда открывает ровно то, что показано цифрой.
static func facets_of(items, query) -> Array:
	var all: Array = []
	var buckets: Dictionary = {}
	for e in items:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if not matches_search(str(e.get("name", "")), query):
			continue
		var c := str(e.get("cat", ""))
		if c == "":
			continue
		all.append(e)
		if not buckets.has(c):
			buckets[c] = []
		buckets[c].append(e)
	var out: Array = [{"key": "", "items": all, "count": all.size()}]
	for c in category_keys():
		if buckets.has(c):
			out.append({"key": c, "items": buckets[c], "count": buckets[c].size()})
			buckets.erase(c)
	var rest := buckets.keys()
	rest.sort()
	for c in rest:
		out.append({"key": str(c), "items": buckets[c], "count": (buckets[c] as Array).size()})
	return out

# Есть ли что показать в панели предмета: обвесы или тумблер заполнения обоймы.
# Единая проверка для клетки, строки слота, чипа и самой панели - иначе метка
# и содержимое панели могут разойтись. На вход - {"compatible": ..., "maxAmount": ...}.
static func has_panel(info) -> bool:
	if typeof(info) != TYPE_DICTIONARY:
		return false
	var compat = info.get("compatible")
	if compat is Array and compat.size() > 0:
		return true
	var max_a = info.get("maxAmount")
	return max_a != null and float(max_a) > 0.0

# Обвесы, сгруппированные по их собственному subtype: оптику нельзя надеть
# вместе с оптикой, а дуло с дулом. Элемент группы: {"grp": String, "items": Array},
# элемент обвеса: {"path": String, "name": String, "subtype": String}.
static func group_attachments(attachments) -> Array:
	var groups: Array = []
	var index := {}
	for a in attachments:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var path := str(a.get("path", ""))
		if path == "":
			continue
		var grp := "Other"
		if a.get("subtype") != null:
			grp = str(a.get("subtype"))
		if grp == "":
			grp = "Other"
		if not index.has(grp):
			index[grp] = groups.size()
			groups.append({"grp": grp, "items": []})
		groups[index[grp]]["items"].append(
			{"path": path, "name": str(a.get("name", "?")), "subtype": grp})
	return groups
