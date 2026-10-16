extends RefCounted
## Interface language table for Vostok Toolkit.
##
## English is the source language and every key IS the English string, so a
## missing entry degrades to readable English instead of breaking the layout.
## Only mod chrome is translated here; item names, item types and map, shelter
## or trader labels come from the game database and are used verbatim.

const DEFAULT := "en"

const RU := {
	'Armor': 'Броня',
	'Armor plates': 'Бронеплиты',
	'Ammo': 'Патроны',
	'All items': 'Все предметы',
	'Apply': 'Применить',
	'Assign key': 'Назначить клавишу',
	'Attachments': 'Обвесы',
	'Books': 'Книги',
	'Cancel': 'Отмена',
	'Categories': 'Категории',
	'Chest rig': 'Нагрудник',
	'Clothing': 'Одежда',
	'Consumables': 'Еда',
	'Controls': 'Управление',
	'Create new loadout': 'Создать новый сет',
	'Delete': 'Удалить',
	'Does not fit: ': 'Не подходит: ',
	'Done': 'Готово',
	'Editing: ': 'Редактирование: ',
	'Edit': 'Изменить',
	'Electronics': 'Электроника',
	'Equipment': 'Экипировка',
	'Enter a name...': 'Введите название...',
	'Flashlights': 'Фонари',
	'Full': 'Полный',
	'Empty mag': 'Пустая',
	'Full magazine': 'Полная обойма',
	'Full mag': 'Полная',
	'Furniture': 'Мебель',
	'Gear': 'Снаряжение',
	'Grenades': 'Гранаты',
	'Grips': 'Рукоятки',
	'Inventory': 'Инвентарь',
	'Keys': 'Ключи',
	'Knives': 'Ножи',
	'Lasers': 'ЛЦУ',
	'Loadout name required': 'Нужно название сета',
	'Magazines': 'Обоймы',
	'Maps': 'Карты',
	'Medical': 'Медпредметы',
	'Misc': 'Разное',
	'Muzzle': 'Дульные',
	'Name already taken!': 'Имя уже занято!',
	'No saved loadouts': 'Нет сохранённых сетов',
	'Nothing fits': 'Ничего не подходит',
	'Optics': 'Оптика',
	'Only selected': 'Только выбранные',
	'Press a key…': 'Нажмите клавишу…',
	'Pouches': 'Подсумки',
	# Слоты набора: ключи идут из VTKPicker.SLOT_ORDER, отображаются только,
	# данные игры (item.slots) остаются английскими.
	'Primary': 'Основное',
	'Secondary': 'Дополнительное',
	'Knife': 'Нож',
	'Grenade_1': 'Граната 1',
	'Grenade_2': 'Граната 2',
	'Backpack': 'Рюкзак',
	'Rig': 'Разгрузка',
	'Helmet': 'Каска',
	'Head': 'Шапка',
	'Legs': 'Штаны',
	'Belt': 'Подсумок',
	'Feet': 'Обувь',
	'Hands': 'Перчатки',
	'Light': 'Фонарик',
	'Time': 'Часы',
	'Map': 'Карта',
	'NVG': 'ПНВ',
	'Player': 'Плеер',
	'Matches': 'Спички',
	'Remove': 'Убрать',
	'Save loadout': 'Сохранить сет',
	'Saved loadouts': 'Сохранённые сеты',
	'Search items...': 'Поиск предметов...',
	'Select a set on the left': 'Выберите сет слева',
	'Sets': 'Сеты',
	'Set is empty': 'Сет пуст',
	'Shelters': 'Убежища',
	'Teleport': 'Телепорт',
	'Traders': 'Трейдеры',
	'Underbarrel': 'Подствольные',
	'Filter': 'Фильтр',
	'Reset': 'Сброс',
	# Подкатегории предметов: ключ идёт из VTKPicker.SUBCATEGORY_ORDER, поэтому
	# порядок здесь повторяет его, чтобы ключ и заголовок строки фильтров
	# читались вместе. Grenades, Books, Knives и Electronics выше: подписи
	# полок категорий, только приходят они не литералом, а через
	# Picker.category_label() из VTKPicker.CATEGORIES. Lasers выше: подпись
	# группы обвесов из VTKUI.ATT_GROUP_LABELS, перевод один и тот же.
	# По тексту кода их не найти, поэтому keycheck читает таблицу отдельно.
	'Assault Rifles': 'Винтовки',
	'Sniper Rifles': 'Снайперки',
	'Shotguns': 'Дробовики',
	'Pistols': 'Пистолеты',
	'SMGs': 'ПП',
	'Handgun & SMG Mags': 'Обоймы пистолетов и ПП',
	'Rifle & Sniper Mags': 'Обоймы для винтовок',
	'Pistol & SMG Calibers': 'Патроны для пистолетов и ПП',
	'Rifle Calibers': 'Патроны для винтовок',
	'Shotgun Shells': 'Дробь',
	'First Aid': 'Первая помощь',
	'Medication': 'Лекарства',
	'Utility': 'Мелочи',
	'Helmets': 'Шлемы',
	'Armor Plates': 'Бронеплиты',
	'Rigs & Vests': 'Бронежилеты',
	'Backpacks': 'Рюкзаки',
	'Belts': 'Подсумки',
	'Hats': 'Шапки',
	'Torso': 'Торс',
	'Pants': 'Брюки',
	'Boots & Hands': 'Обувь и перчатки',
	'Weapon Parts': 'Детали оружия',
	'Scopes': 'Прицелы',
	'Suppressors': 'Глушители',
	'Hydration': 'Питьё',
	'Canned Goods': 'Консервы',
	'Snacks & Ingredients': 'Перекусы и продукты',
	'Cooked Meals': 'Готовые блюда',
	'Vices': 'Алкоголь и табак',
	'Fish': 'Рыба',
	'Garbage': 'Мусор',
	'Utilities & Tools': 'Хозтовары и инструменты',
	'Music': 'Музыка',
	'Fishing': 'Рыбалка',
	'Lore': 'Лор',
	'Storage & Cabinets': 'Хранение',
	'Seating & Beds': 'Сиденья и кровати',
	'Tables & Shelving': 'Столы и полки',
	'Appliances & Electronics': 'Техника',
	'Decor': 'Декор',
	'Weapons': 'Оружие',
	' in equipment': ' в экипировке',
	' items · ': ' предметов · ',
	'[rounds]': '[патроны]',
	'+ Create loadout': '+ Создать сет',
	'file: ': 'файл: ',
	'in the tutorial': 'в туториале',
}

static var _lang := DEFAULT

static func set_lang(code: String) -> void:
	if code == "en" or code == "ru":
		_lang = code

static func get_lang() -> String:
	return _lang

static func txt(text: String) -> String:
	if _lang == "ru":
		return RU.get(text, text)
	return text