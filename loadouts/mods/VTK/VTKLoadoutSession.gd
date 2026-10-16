extends RefCounted

# Состояние редактора сета: сам черновик документа и эфемерное состояние выбора.
# Чистая логика: ни load(), ни путей внутрь игры, поэтому тестируется headless.
# Сюда переехало то, что раньше отдельными полями текло по VTKUI: страница
# мастера, цель шага 1, фильтры и поиск каталога шага 2, открытая панель
# обвесов и предмет, положенный последним. Один владелец вместо набора полей.

const Draft := preload("res://mods/VTK/VTKDraft.gd")

# Документ, который правит редактор. null - редактор закрыт, черновика нет.
var draft: Draft = null

# Трёхшаговый выбор предмета. Страницы строятся один раз, переключение -
# visible, поэтому page переживает обновление содержимого.
var page: int = 0

# Цель шага 1: слот, в который ляжет следующий предмет. Пусто - свободный слот
# выбирает Draft.free_slot_of.
var target_slot: String = ""

# Фильтры каталога шага 1: категория и её подкатегория. Для экипировки смотреть
# все предметы не нужно, поэтому отдельного пункта "Все предметы" здесь нет -
# сбрасывает строку фильтров чип "Сброс".
var target_cat: String = ""
var target_sub: String = ""

# Живой поиск шага 1 и шага 2.
var search_text: String = ""
var gear_search: String = ""

# Фасеты каталога шага 2: выбранная категория, подкатегория внутри неё, режим
# «Только выбранные» и свёрнутость подкатегорий по повторному клику.
var gear_facet_key: String = ""
var gear_sub_key: String = ""
var gear_only_selected: bool = false
var gear_subs_collapsed: bool = false

# Какой панелью обвесов занят каждый шаг: у Экипировки и Снаряжения своя.
var open_equip_att: String = ""
var open_gear_att: String = ""

# Предмет, который только что положили: его обвесы открываются сами.
var last_placed: String = ""

# Сброс выбора между пересборками редактора: новый сет не должен начинаться с
# чужим слотом в цели, невидимым запросом в поле поиска или чужой панелью.
func reset_picker_state() -> void:
	target_slot = ""
	search_text = ""
	gear_search = ""
	gear_facet_key = ""
	gear_sub_key = ""
	gear_subs_collapsed = false
	gear_only_selected = false
	open_equip_att = ""
	open_gear_att = ""
	last_placed = ""

# Обвес открыт по текущей странице мастера: у экипировки и снаряжения свои
# поля, а ветвление по page живёт в одном месте, а не расползается по вызовам.
func attachment_target() -> String:
	return open_gear_att if page == 1 else open_equip_att

func set_attachment_target(path: String) -> void:
	if page == 1:
		open_gear_att = path
	else:
		open_equip_att = path

func toggle_attachment_target(path: String) -> void:
	if page == 1:
		open_gear_att = "" if open_gear_att == path else path
	else:
		open_equip_att = "" if open_equip_att == path else path

func clear_attachments() -> void:
	open_equip_att = ""
	open_gear_att = ""

func new_draft() -> void:
	draft = Draft.new()
	clear_attachments()

func clear_draft() -> void:
	draft = null
	clear_attachments()

func edit_draft(d) -> void:
	draft = d
	clear_attachments()
