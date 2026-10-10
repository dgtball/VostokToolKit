extends RefCounted
## Interface language table for Vostok Toolkit.
##
## English is the source language and every key IS the English string, so a
## missing entry degrades to readable English instead of breaking the layout.
## Only mod chrome is translated here; item names, item types and map, shelter
## or trader labels come from the game database and are used verbatim.

const DEFAULT := "en"

const RU := {
	' (you are on ': ' (вы на карте ',
	' · Equipped: ': ' · Надето: ',
	' · In inventory: ': ' · В инвентаре: ',
	' · To catalog: ': ' · В каталог: ',
	' · Occupied slots: ': ' · Занятые слоты: ',
	' failed to load': ' не прогрузилась',
	' rnd.': ' обв.',
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
	'Create new loadout': 'Создать новый сет',
	'Deposit': 'Deposit',
	'Deposit selected items toward this task': 'Внести выбранные предметы в счёт задачи',
	'Deposited': 'Внесено',
	'Does not fit: ': 'Не подходит: ',
	'Done': 'Готово',
	'Editing: ': 'Редактирование: ',
	'Edit': 'Изменить',
	'Electronics': 'Электроника',
	'Equipment': 'Экипировка',
	'Enter a name...': 'Введите название...',
	'Empty': 'Пусто',
	'Flashlights': 'Фонари',
	'Full magazine': 'Полная обойма',
	'Furniture': 'Мебель',
	'Gear': 'Снаряжение',
	'Grenades': 'Гранаты',
	'Grips': 'Рукоятки',
	'Hotkey:': 'Клавиша:',
	'Interface language': 'Язык интерфейса',
	'Inventory': 'Инвентарь',
	'Keys': 'Ключи',
	'Kill counter': 'Счётчик убийств',
	'Knives': 'Ножи',
	'Lasers': 'ЛЦУ',
	'Loadout "': 'Сет «',
	'Loadout name required': 'Нужно название сета',
	'Magazines': 'Обоймы',
	'Map ': 'Карта ',
	'Maps': 'Карты',
	'Medical': 'Медпредметы',
	'Misc': 'Разное',
	'Muzzle': 'Дульные',
	'Name:': 'Название:',
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
	'Scene failed to load: ': 'Сцена не загрузилась: ',
	'Scene loader not found': 'Не найден загрузчик сцен',
	'Search items...': 'Поиск предметов...',
	'Select a set on the left': 'Выберите сет слева',
	'Spawn into inventory': 'В инвентарь',
	'Spawn into catalog': 'В каталог',
	'Spawned: ': 'Заспавнено: ',
	'Spawned to catalog: ': 'Заспавнено в каталог: ',
	'Sets': 'Сеты',
	'Set is empty': 'Сет пуст',
	'Settings': 'Настройки',
	'Shelter not unlocked yet: ': 'Убежище ещё не открыто: ',
	'Shelters': 'Убежища',
	'Teleport': 'Телепорт',
	'Teleport already in progress': 'Телепорт уже выполняется',
	'Teleport unavailable in the tutorial': 'Телепорт недоступен в туториале',
	'Teleport: ': 'Телепорт: ',
	'Trader not found: ': 'Не удалось найти трейдера: ',
	'Traders': 'Трейдеры',
	'Underbarrel': 'Подствольные',
	'Unknown map: ': 'Неизвестная карта: ',
	'Unknown shelter: ': 'Неизвестное убежище: ',
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
	'grid 8 columns': 'сетка 8 колонок',
	'[rounds]': '[патроны]',
	'+ Create loadout': '+ Создать сет',
	'" applied': '» применён',
	'" → to inventory: ': '» → в инвентарь: ',
	'file: ': 'файл: ',
	'in the tutorial': 'в туториале',
	'Interface': 'Интерфейс',
	'Modules': 'Модули',
	'Shows the kill counter in the interface': 'Показывает счётчик убийств в интерфейсе',
	'Switch between English and Russian': 'Переключение между английским и русским',
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

static func codes() -> PackedStringArray:
	return PackedStringArray(["en", "ru"])

static func code_label(code: String) -> String:
	return "Русский" if code == "ru" else "English"