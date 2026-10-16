extends RefCounted

const Loc := preload("res://mods/VTK/VTKLoc.gd")
const Picker := preload("res://mods/VTK/VTKPicker.gd")
const VTKSurface := preload("res://mods/VTK/VTKSurface.gd")
const Items := preload("res://mods/VTK/VTKItemStore.gd")
const Draft := preload("res://mods/VTK/VTKDraft.gd")

const R_EQUIP := 1
const R_GEAR := 2
const R_DONE := 4
const R_OVERLAY := 8
const R_LIST := 16
const R_PREVIEW := 32
const R_PAGES := R_EQUIP | R_GEAR | R_DONE | R_OVERLAY

var _ui = null

var _editor_panel: VBoxContainer = null
var _name_input: LineEdit = null
# Полосы категорий строятся как VBox из заголовка и HFlow с клетками: у
# GridContainer нет растягивания на всю ширину, а полоса во всю ширину
# нужна, чтобы порядок групп читался сверху вниз.
var _shelves_box: VBoxContainer = null
var _equip_grid_box: VBoxContainer = null
var _target_bar: VBoxContainer = null
var _gear_box: HBoxContainer = null
var _search_debounce: Timer
var _gear_search_debounce: Timer
var _step_btns: Array = []
var _page_equip: Control = null
var _page_gear: Control = null
var _page_done: Control = null
var _page_label: Label = null
# Шаги стелпера собираются один раз, а _show_page переливает их состояния:
# карточка, подпись, кружок-номер, цифра в кружке и галочка пройденного шага.
var _step_labels: Array = []
var _step_circles: Array = []
var _step_numbers: Array = []
var _step_checks: Array = []
var _gear_search_field: LineEdit = null
var _gear_facets_box: VBoxContainer = null
var _gear_grid: GridContainer = null
var _gear_grid_scroll: ScrollContainer = null
# Оверлей обвесов поверх всей вкладки: панель под каталогом при узком окне
# всё равно была бы не видна. Геометрия зеркалит _scroll, тело - подложка
# для панели предмета, шапка с ✕ рисуется при сборке.
var _att_overlay: Control = null
var _att_overlay_body: VBoxContainer = null
var _done_preview: Control = null

func _init(ui) -> void:
	_ui = ui

func build(right_box: Control) -> void:
	_editor_panel = VBoxContainer.new()
	_editor_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_child(_editor_panel)
	_build_editor()
	_build_att_overlay()

func _build_att_overlay() -> void:
	# Оверлей обвесов живёт на _ui._panel и добавляется после _ui._scroll, чтобы
	# рисоваться поверх вкладки. Геометрия зеркалит _ui._scroll (якоря + отступы
	# 4/72/-4/-4): карточка центрируется MarginContainer'ом, а не фиксированным
	# размером - панель теперь на весь экран, и жёсткие 792×800 не подошли бы.
	_att_overlay = Control.new()
	_att_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_att_overlay.offset_left = 4
	_att_overlay.offset_top = 72
	_att_overlay.offset_right = -4
	_att_overlay.offset_bottom = -4
	_att_overlay.visible = false
	_att_overlay.clip_contents = true
	var dim := Panel.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0, 0, 0, 0.55)
	dim.add_theme_stylebox_override("panel", ds)
	dim.gui_input.connect(func(ev):
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_close_att_overlay()
	)
	_att_overlay.add_child(dim)

	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margins.add_theme_constant_override("margin_left", 56)
	margins.add_theme_constant_override("margin_right", 56)
	margins.add_theme_constant_override("margin_top", 24)
	margins.add_theme_constant_override("margin_bottom", 24)
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_att_overlay.add_child(margins)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", VTKSurface.panel(false, 14))
	margins.add_child(card)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	cv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(cv)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = Loc.txt("Attachments")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", _ui._gold)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	VTKSurface.style_button(close_btn, false, true)
	close_btn.pressed.connect(_close_att_overlay)
	head.add_child(close_btn)
	cv.add_child(head)

	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_att_overlay_body = VBoxContainer.new()
	_att_overlay_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_att_overlay_body)
	cv.add_child(sc)

	# «Готово» внизу оверлея: изменения применяются живьём в черновик, кнопка
	# только закрывает панель. Без неё приходилось кликать по пустой области.
	var done_row := HBoxContainer.new()
	done_row.size_flags_vertical = Control.SIZE_SHRINK_END
	var done_btn := Button.new()
	done_btn.text = Loc.txt("Done")
	done_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VTKSurface.style_button(done_btn, true, false, 14, 14, 10, 12)
	done_btn.pressed.connect(_close_att_overlay)
	done_row.add_child(done_btn)
	cv.add_child(done_row)

	_ui._panel.add_child(_att_overlay)

func _build_editor() -> void:
	for child in _editor_panel.get_children():
		_editor_panel.remove_child(child)
		child.queue_free()
	_step_btns = []
	_name_input = null
	# Переключение или закрытие черновика бросает незавершённый захват
	# и не применённый бинд: они относились к прошлому состоянию.
	_ui._rail._bind_target = ""
	_ui._rail._bind_pending = false
	_ui._rail._bind_btn = null
	_ui._rail._done_bind_btn = null
	_ui._rail._pending_qk = 0
	_done_preview = null
	_gear_search_field = null
	_gear_facets_box = null
	_gear_grid = null
	_ui._session.gear_facet_key = ""
	_gear_grid_scroll = null
	_shelves_box = null
	_equip_grid_box = null
	_gear_box = null
	_page_label = null

	var title_row = HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_theme_constant_override("separation", 4)
	var ed_title = Label.new()
	if _ui._session.draft != null and _ui._session.draft.set_name != "":
		ed_title.text = Loc.txt("Editing: ") + _ui._session.draft.set_name
	else:
		ed_title.text = Loc.txt("Create new loadout")
	ed_title.add_theme_font_size_override("font_size", 12)
	ed_title.add_theme_color_override("font_color", _ui._gold)
	ed_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(ed_title)
	_editor_panel.add_child(title_row)

	_editor_panel.add_child(_build_stepper())

	_page_equip = _build_page_equipment()
	_page_gear = _build_page_gear()
	_page_done = _build_page_done()
	_editor_panel.add_child(_page_equip)
	_editor_panel.add_child(_page_gear)
	_editor_panel.add_child(_page_done)

	_ui._session.reset_picker_state()
	_show_page(0)
	_editor_panel.visible = _ui._session.draft != null
	_ui.refresh(R_PAGES | R_PREVIEW)

# Кнопки шагов строятся один раз, переключение идёт через _show_page.
# Сообщение живёт в том же ряду: отдельная строка ради ошибки вроде
# "нужно название" дёргала бы вёрстку на каждом переходе.
func _build_stepper() -> Control:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)
	var titles := [Loc.txt("Equipment"), Loc.txt("Gear"), Loc.txt("Done")]
	_step_btns.clear()
	_step_labels.clear()
	_step_circles.clear()
	_step_numbers.clear()
	_step_checks.clear()
	for i in range(titles.size()):
		var idx := i
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.add_theme_stylebox_override("panel", _make_step_row_style(_ui._session.page == idx))
		card.gui_input.connect(func(ev):
			var mb := ev as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_show_page(idx)
		)
		_ui._attach_row_hover(card, func(hv: bool):
			return _make_step_row_style(_ui._session.page == idx, hv))
		_ui._attach_motion(card)

		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hb)

		var circle := _make_step_circle(idx + 1, _ui._session.page == idx)
		_step_circles.append(circle)
		hb.add_child(circle)
		var num := circle.get_child(0) as Label
		_step_numbers.append(num)

		var lab := Label.new()
		lab.text = titles[i]
		lab.add_theme_font_size_override("font_size", 11)
		lab.add_theme_color_override("font_color", _ui._gold if _ui._session.page == idx else VTKSurface.GREY)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_step_labels.append(lab)
		hb.add_child(lab)

		var chk := Label.new()
		chk.text = "\u2713"
		chk.add_theme_font_size_override("font_size", 10)
		chk.add_theme_color_override("font_color", _ui._gold)
		chk.visible = idx < _ui._session.page
		chk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_step_checks.append(chk)
		hb.add_child(chk)

		_step_btns.append(card)
		row.add_child(card)
	_page_label = Label.new()
	_page_label.add_theme_font_size_override("font_size", 10)
	_page_label.add_theme_color_override("font_color", _ui._gold)
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_page_label)
	return row

# Стиль карточки шага: активный - золотая рамка, как у слотов. Ховер не
# перебивает активное состояние. Вертикальные поля 9/11 совпадают со
# style_button, поэтому карточка (~38 px) растёт до высоты «Применить».
func _make_step_row_style(active: bool, hover: bool = false) -> StyleBox:
	return VTKSurface.surface("hover" if hover else "normal", active, false, active, 8, 8, 9, 11)

func _make_step_circle_style(active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _ui._gold if active else Color("#1f1913")
	s.border_color = _ui._gold if active else VTKSurface.BORDER
	s.border_width_all = 1
	s.corner_radius_all = 9
	return s

# Кружок с номером шага, как в макете: заполнен золотом у активного шага,
# тёмный с рамкой у остальных. Цифра ложится на весь кружок и центрируется
# выравниванием, чтобы не зависеть от шрифта игры.
func _make_step_circle(n: int, active: bool) -> Panel:
	var c := Panel.new()
	c.custom_minimum_size = Vector2(18, 18)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_theme_stylebox_override("panel", _make_step_circle_style(active))
	var num := Label.new()
	num.text = str(n)
	num.add_theme_font_size_override("font_size", 10)
	num.add_theme_color_override("font_color", Color("#1a1206") if active else VTKSurface.MUTED)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(num)
	return c

func _show_page(n: int) -> void:
	_ui._session.page = clampi(n, 0, 2)
	if _page_equip != null:
		_page_equip.visible = _ui._session.page == 0
	if _page_gear != null:
		_page_gear.visible = _ui._session.page == 1
	if _page_done != null:
		_page_done.visible = _ui._session.page == 2
	for i in range(_step_btns.size()):
		var on: bool = i == _ui._session.page
		var card := _step_btns[i] as PanelContainer
		if card != null:
			card.add_theme_stylebox_override("panel", _make_step_row_style(on))
		if i < _step_labels.size():
			var lab := _step_labels[i] as Label
			if lab != null:
				lab.add_theme_color_override("font_color", _ui._gold if on else VTKSurface.GREY)
		if i < _step_circles.size():
			var circle := _step_circles[i] as Panel
			if circle != null:
				circle.add_theme_stylebox_override("panel", _make_step_circle_style(on))
		if i < _step_numbers.size():
			var num := _step_numbers[i] as Label
			if num != null:
				num.add_theme_color_override("font_color", Color("#1a1206") if on else VTKSurface.MUTED)
		if i < _step_checks.size():
			var chk := _step_checks[i] as Label
			if chk != null:
				chk.visible = i < _ui._session.page
	# При смене шага оверлей перерисовывается по пути новой страницы:
	# чужая панель закрывается, своя - открывается.
	_ui.refresh(R_OVERLAY)

func _set_problem(msg: String) -> void:
	if _page_label != null:
		_page_label.text = msg

func _clear_problem() -> void:
	if _page_label != null:
		_page_label.text = ""


# У ScrollContainer минимальная высота 0: содержимое скроллится, а сам он
# место не занимает. Высоту area получает только от custom_minimum_size либо
# от вертикального SIZE_EXPAND_FILL, который обязан дойти по всей цепочке
# контейнеров до _editor_panel. Без этого полки с предметами схлопывались в
# ноль, и сетка не рисовалась вовсе.
func _page_wrap() -> VBoxContainer:
	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	return v

# Ширина левой колонки по умолчанию (шаг 2 «Снаряжение» и «Точки»). Шаг 1
# «Экипировка» идёт под колонку 447 (EQ_COL_W): укладка 6×8 шире 232.
const SIDE_WIDTH := 232

# Размеры сетки экипировки (вариант E): фиксированная сетка 6 колонок × 8 рядов,
# клетка EQ_CELL, зазор EQ_GAP. Колонка экипировки - 447: 6·70 + 5·3 = 435 плюс
# поля панели 12. Метрики (клетка 70, зазор 3) совпадают с инвентарём, поэтому
# превью ровное по низу. Раскладка слотов живёт в Picker.EQUIP_GRID;
# здесь только геометрия. Прежних высот оружия/тела/мелочи больше нет - все клетки
# одного размера, разный только размах (2×6, 2×2, 1×1).
const EQ_COL_W := 447
const EQ_CELL := 70
const EQ_GAP := 3
# Стена инвентаря: чипы 1×1, клетка 70px для читаемости иконок, всегда 8×8.
# Метрики совпадают с экипировкой (70/3) и отступом 6px: ряды колонок ровные.
const INVEN_CELL := 70
const INVEN_COLS := 8
const INVEN_ROWS := 8
const INVEN_GAP := 3

# Сколько клеток влезает в ширину. Константа "_gear_grid.columns = 4" давала
# четыре колонки в любом окне, а HFlowContainer на шаге 1 упирался в
# собственную ширину и показывал пять клеток вместо всей области.
# Ширина клетки + зазор задаётся здесь, а не в _make_item_cell: расчёт колонок
# обязан знать тот же размер, что и вёрстка, иначе сетка переполняется и
# снизу появляется горизонтальная прокрутка.
const GEAR_CELL_W := 128.0
const GEAR_CELL_SEP := 6.0

func _make_grid_columns(width: float) -> int:
	if width <= 0.0:
		return 1
	return maxi(1, int(floor((width + GEAR_CELL_SEP) / (GEAR_CELL_W + GEAR_CELL_SEP))))


# Каркас страницы: слева колонка выбора, справа предметы. Ширина колонки
# задаётся единожды (по умолчанию SIDE_WIDTH): у экипировки она шире - 375,
# чтобы встала укладка 6×8.
func _page_columns(title: String, side: Control, main: Control, width := SIDE_WIDTH) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 6)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	var ps := VTKSurface.panel(true, 6).duplicate(true)
	ps.border_width_left = 0
	ps.border_width_top = 0
	ps.border_width_bottom = 0
	ps.shadow_color = Color(0, 0, 0, 0)
	panel.add_theme_stylebox_override("panel", ps)

	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", VTKSurface.BROWN)
	sv.add_child(lbl)
	sv.add_child(side)
	panel.add_child(sv)
	h.add_child(panel)

	var mv := VBoxContainer.new()
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mv.add_theme_constant_override("separation", 4)
	mv.add_child(main)
	h.add_child(mv)
	return h

func _make_search_field(on_change: Callable) -> LineEdit:
	var search := LineEdit.new()
	search.placeholder_text = Loc.txt("Search items...")
	search.add_theme_color_override("font_color", Color("#ffffff"))
	search.add_theme_color_override("placeholder_color", VTKSurface.GREY_DIM)
	search.add_theme_stylebox_override("normal", VTKSurface.panel(true, 10))
	search.add_theme_stylebox_override("focus", VTKSurface.focus_style())
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(on_change)
	return search

func _build_page_equipment() -> Control:
	var v := _page_wrap()

	# Шапка цели: чем заполнен слот-цель и сброс на "все предметы". Список
	# занятых слотов чипами больше не нужен - левая колонка и есть этот список.
	_target_bar = VBoxContainer.new()
	_target_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_bar.add_theme_constant_override("separation", 2)
	v.add_child(_target_bar)

	# Поиск живёт над сеткой и обновляет её на лету. text_changed, а не
	# gui_input: у LineEdit gui_input при потере фокуса Godot обрывает, и
	# вторая вкладка с первого раза роняла бы редактор.
	var search := _make_search_field(func(t): _set_search(t))
	if _search_debounce != null and is_instance_valid(_search_debounce):
		_search_debounce.queue_free()
	_search_debounce = Timer.new()
	_search_debounce.one_shot = true
	_search_debounce.wait_time = 0.12
	_search_debounce.timeout.connect(_apply_search)
	_ui.add_child(_search_debounce)
	v.add_child(search)

	var shelves_scroll := ScrollContainer.new()
	shelves_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelves_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Только вертикальная прокрутка: горизонтальную отключаем явно, иначе
	# полка упирается в собственную ширину и появляется лишняя полоса снизу.
	# Пол по высоте гарантирует, что полки останутся видимыми даже там, где
	# внешний контейнер игры отдаёт ровно минимальную высоту.
	shelves_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shelves_scroll.custom_minimum_size = Vector2(0, 240)
	_shelves_box = VBoxContainer.new()
	_shelves_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shelves_box.add_theme_constant_override("separation", 6)
	shelves_scroll.add_child(_shelves_box)
	v.add_child(shelves_scroll)

	# Левая колонка шага 1 - укладка экипировки (вариант E): фиксированная
	# сетка 6×8 с стволами в рост. Колонка шире прочих - 330.
	_equip_grid_box = VBoxContainer.new()
	_equip_grid_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equip_grid_box.add_theme_constant_override("separation", 6)
	return _page_columns(Loc.txt("Equipment"), _equip_grid_box, v, EQ_COL_W)

func _build_page_gear() -> Control:
	var main := _page_wrap()

	# Отдельное поле поиска: запрос шага 1 относится к выбору предмета в слот
	# и не должен молча фильтровать снаряжение, и наоборот.
	var search := _make_search_field(func(t): _set_gear_search(t))
	_gear_search_field = search
	main.add_child(search)
	# Тот же дебаунс, что у шага 1: без него каталог пересобирался на каждый символ.
	if _gear_search_debounce != null and is_instance_valid(_gear_search_debounce):
		_gear_search_debounce.queue_free()
	_gear_search_debounce = Timer.new()
	_gear_search_debounce.one_shot = true
	_gear_search_debounce.wait_time = 0.12
	_gear_search_debounce.timeout.connect(_apply_gear_search)
	_ui.add_child(_gear_search_debounce)

	# Каталог всегда открыт: он и раньше был длиннее окна, поэтому кнопка
	# раскрытия только добавляла лишний клик к выбору предмета.
	_gear_grid_scroll = ScrollContainer.new()
	_gear_grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gear_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Колонки считаются от ширины (см. _make_grid_columns), поэтому клеткам
	# незачем прокручиваться вбок - пусть переносятся на новую строку.
	_gear_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_gear_grid = GridContainer.new()
	# Колонки считаются от ширины, а не задаются константой. Пересчёт вешается
	# на resized: на первом показе ширина ещё нулевая, и без обработчика
	# получилась бы одна колонка.
	_gear_grid.columns = _make_grid_columns(_gear_grid_scroll.size.x)
	_gear_grid_scroll.resized.connect(func():
		if _gear_grid != null:
			_gear_grid.columns = _make_grid_columns(_gear_grid_scroll.size.x)
	)
	_gear_grid.add_theme_constant_override("h_separation", int(GEAR_CELL_SEP))
	_gear_grid.add_theme_constant_override("v_separation", int(GEAR_CELL_SEP))
	_gear_grid_scroll.add_child(_gear_grid)
	main.add_child(_gear_grid_scroll)

	_gear_facets_box = VBoxContainer.new()
	_gear_facets_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gear_facets_box.add_theme_constant_override("separation", 3)

	_gear_box = _page_columns(Loc.txt("Categories"), _gear_facets_box, main)
	return _gear_box

# У обоймы единственный "обвес" - совместимый патрон, и он уезжает в
# slotData.nested, который игра не читает. Число патронов задаёт сам amount,
# поэтому блок обвесов обойме не нужен.
func _is_magazine(path: String) -> bool:
	var info = _ui._item_info(path)
	return str(info.get("type")) == "Attachment" and str(info.get("subtype")) == "Magazine"

# Кнопка обвеса нужна только там, где есть что вешать: непустой compatible.
# У патронов maxAmount = 300 (вместимость стака), поэтому maxAmount в проверке
# не участвует - иначе патроны получали бы кнопку обвеса без обвесов.
func _att_panel_needed(info: Dictionary) -> bool:
	return Picker.att_panel_needed(info)

# Микро-кнопка: крестик чипа слота и ряды управления клеткой снаряжения.
# Дефолт 15×16/font 8 - слот-строка; клетка шага 2 передаёт размер крупнее,
# потому что «− n +» там основное управление, а не служебная мелочь.
func _make_mini_btn(label: String, size := Vector2(15, 16), font := 8) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", font)
	VTKSurface.style_button(b, false, false, 1, 1, 2, 2)
	return b

func _remove_gear(path: String) -> void:
	if _ui._session.draft == null:
		return
	if _ui._session.open_gear_att == path:
		_ui._session.open_equip_att = ""
		_ui._session.open_gear_att = ""
	_ui._session.draft.remove_gear(path)
	_ui.refresh(R_PAGES)

# Единый вид кнопок Full: включено - заливка и золотая точка, выключено -
# серый контур без точки. Точка - символ в тексте, а не отдельный узел:
# Button не контейнер, позиционировать детей вручную здесь хрупко. dot=false
# у патронов: состояние уже видно числом в строке A, а точка удлиняла текст и
# вылезала за клетку.
func _style_full_btn(b: Button, on: bool, label: String, dot := true) -> void:
	b.text = ("● " if on and dot else "") + label
	b.custom_minimum_size = Vector2(0, 22)
	VTKSurface.style_button(b, on, false, 8, 8, 4, 4)
	b.add_theme_color_override("font_color", _ui._gold if on else VTKSurface.GREY_DIM)

# Разовое действие патронов: выставить полный стак. Горит, когда уже полный.
# Подпись - только "Full": число патронов стоит в строке A, а «●» и «· 300»
# удлиняли кнопку и вылезали за клетку.
func _make_full_ammo_btn(path: String, _desc: Dictionary) -> Button:
	var cap := _gear_cap(path)
	var on: bool = cap > 0.0 and _ui._session.draft != null and _ui._session.draft.amount_of(path) >= cap
	var b := Button.new()
	_style_full_btn(b, on, Loc.txt("Full"), false)
	b.pressed.connect(func():
		if _ui._session.draft == null or cap <= 0.0:
			return
		_ui._session.draft.set_gear_amount(path, cap)
		_ui.refresh(R_PAGES)
	)
	return b

# У обоймы тумблер переехал в строку B и стал крупным: прежний зажатый
# компакт-вид (шрифт 8, поля 2/2) почти не отличал включено от выключено.
func _make_full_mag_btn(path: String, desc: Dictionary) -> Button:
	var on := Draft.is_full(desc)
	var b := Button.new()
	_style_full_btn(b, on, Loc.txt("Full mag") if on else Loc.txt("Empty mag"))
	b.pressed.connect(func():
		if _ui._session.draft == null:
			return
		# Состояние берём с актуального descriptor'а, а не с захваченного
		# desc: после пересборки клеток он уже может быть не тем объектом.
		_ui._session.draft.set_full_mag(path, not Draft.is_full(_ui._session.draft.descriptor_of(path)))
		_ui.refresh(R_PAGES)
	)
	return b

# Строка B клетки снаряжения: одно действие по типу предмета, либо null.
func _make_gear_action_row(path: String, desc: Dictionary) -> Control:
	if _is_magazine(path):
		return _make_full_mag_btn(path, desc)
	if str(_ui._item_info(path).get("type")) == "Ammo":
		return _make_full_ammo_btn(path, desc)
	return null

# Число в строке A, по центру между «−» и «+». Голый Control детей не
# раскладывает - число липло к левому верхнему углу; CenterContainer держит
# его посередине. Ввод точного значения убран: поле наезжало на «+».
func _make_gear_count(cnt: int) -> Control:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(30, 28)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lbl := Label.new()
	lbl.text = str(cnt)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", _ui._gold)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lbl)
	return holder

func _set_gear_search(t: String) -> void:
	_ui._session.gear_search = t
	# Дебаунс, как у шага 1: пересборка каталога идёт не на каждый символ.
	if _gear_search_debounce != null:
		_gear_search_debounce.start()

func _apply_gear_search() -> void:
	# Только каталог: пересборка страницы пересоздала бы поле поиска и выкинула
	# бы из него курсор на каждом символе.
	_ui.refresh(R_GEAR)

# Фасеты и сетка считаются одним проходом по списку предметов: facets_of
# фильтрует и группирует его целиком, а считать дважды - значит фильтровать
# дважды.
func _refresh_gear_catalog() -> void:
	var facets: Array = []
	if _ui._session.draft != null:
		facets = Picker.facets_of(_items_for_gear(), _ui._session.gear_search)
	_rebuild_gear_facets(facets)
	_rebuild_gear_grid(facets)

# Пунктирная строка «Только выбранные» в колонке фасетов. Как CreateCard:
# штрих рисуется в _draw, Loc передаётся текстом. Внутреннему классу недоступен
# _ui._gold внешнего скрипта, поэтому цвет дублируется константой.
class ChosenRow extends PanelContainer:
	const S := preload("res://mods/VTK/VTKSurface.gd")
	const GOLD := VTKSurface.GOLD_SOFT

	var _on := false
	var _action: Callable

	func _init(on: bool, label: String, action: Callable) -> void:
		_on = on
		_action = action
		custom_minimum_size = Vector2(0, 26)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		var st := StyleBoxFlat.new()
		st.bg_color = VTKSurface.PANEL_BG
		st.corner_radius_all = 4
		add_theme_stylebox_override("panel", st)
		var l := Label.new()
		l.text = ("✓ " if _on else "") + label
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", GOLD if _on else VTKSurface.MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		gui_input.connect(func(ev):
			var mb := ev as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_action.call()
		)

	func _draw() -> void:
		S.draw_dashes(self, Rect2(Vector2(2, 2), size - Vector2(4, 4)), VTKSurface.BROWN)

# Фасеты левой колонки: строки категорий со счётчиками. Цифра считается по
# текущему запросу, поэтому всегда равна тому, что окажется в сетке после клика.
func _rebuild_gear_facets(facets: Array) -> void:
	if _gear_facets_box == null:
		return
	for child in _gear_facets_box.get_children():
		_gear_facets_box.remove_child(child)
		child.queue_free()
	if _ui._session.draft == null:
		return
	for f in facets:
		var key := str(f.get("key", ""))
		_gear_facets_box.add_child(_make_facet_row(f, false))
		# Подкатегории - второй уровень: они идут сразу под своей категорией и
		# отступом от неё отличаются. На строке "Все предметы" их нет: список
		# занял бы полколонки и означал бы третье измерение фильтра.
		if _ui._session.gear_facet_key != "" and key == _ui._session.gear_facet_key and not _ui._session.gear_subs_collapsed:
			for s in _gear_subfacets(f.get("items", [])):
				_gear_facets_box.add_child(_make_facet_row(s, true))
	# Пунктирная строка «Только выбранные» - в конце списка категорий.
	_gear_facets_box.add_child(ChosenRow.new(_ui._session.gear_only_selected,
		Loc.txt("Only selected"), func():
			_ui._session.gear_only_selected = not _ui._session.gear_only_selected
			_ui.refresh(R_GEAR)))

# Клик по активной строке сворачивает/разворачивает её подкатегории;
# категория продолжает фильтровать. К возврату ко «Всем предметам» ведёт
# строка «Все предметы»
func _make_facet_row(facet: Dictionary, level: bool) -> Control:
	var key := str(facet.get("key", ""))
	var active: bool = _ui._session.gear_sub_key == key if level else _ui._session.gear_facet_key == key
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 28 if level else 31)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_stylebox_override("panel", _make_slot_style(active))
	_ui._attach_row_hover(row, func(hv: bool): return _make_slot_style(active, hv))
	_ui._attach_motion(row)
	row.gui_input.connect(func(ev): _on_facet_input(ev, key, level))
	if level:
		row.add_theme_constant_override("margin_left", 10)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hb)
	hb.add_child(_make_dot(Color("#4a4038") if level else VTKSurface.BROWN))

	var nm := Label.new()
	if key == "":
		nm.text = Loc.txt("All items")
	else:
		nm.text = ("> " if level else "") + Loc.txt(key if level else Picker.category_label(key))
	nm.add_theme_font_size_override("font_size", 10 if level else 11)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.add_theme_color_override("font_color", _ui._gold if active else VTKSurface.INK)
	hb.add_child(nm)

	var cnt := Label.new()
	cnt.text = str(int(facet.get("count", 0)))
	cnt.add_theme_font_size_override("font_size", 10 if level else 11)
	cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cnt.add_theme_color_override("font_color", VTKSurface.MUTED)
	hb.add_child(cnt)
	return row

func _on_facet_input(ev: InputEvent, key: String, level: bool) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if level:
		_set_gear_sub(key)
	else:
		_set_gear_facet(key)

# Подкатегории набора как строки фасетов, в порядке Picker.order_subcategories.
# Счётчик - это число предметов подкатегории в текущем наборе, то есть ровно
# то, что окажется в сетке после клика.
func _gear_subfacets(items) -> Array:
	var buckets := {}
	for e in items:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var s := str(e.get("sub", ""))
		if s == "":
			continue
		if not buckets.has(s):
			buckets[s] = []
		buckets[s].append(e)
	var out: Array = []
	for s in Picker.order_subcategories(buckets.keys()):
		out.append({"key": s, "items": buckets[s], "count": buckets[s].size()})
	return out

func _set_gear_sub(key: String) -> void:
	_ui._session.gear_sub_key = "" if _ui._session.gear_sub_key == key else key
	_ui.refresh(R_GEAR)

# Фасет меняет только набор клеток: предметы из набора не уходят, поэтому
# открытая панель обвесов остаётся уместной.
func _set_gear_facet(key: String) -> void:
	if key != "" and key == _ui._session.gear_facet_key:
		# Повторный клик по активной категории сворачивает её подкатегории.
		_ui._session.gear_subs_collapsed = not _ui._session.gear_subs_collapsed
	else:
		_ui._session.gear_facet_key = key
		# Смена категории сбрасывает подкатегорию: иначе после "Винтовки" ->
		# "Пистолеты" остался бы фильтр "Снайперки" из прошлой ветки.
		_ui._session.gear_sub_key = ""
		_ui._session.gear_subs_collapsed = false
	_ui.refresh(R_GEAR)

func _facet_items(facets: Array, key: String) -> Array:
	for f in facets:
		if str(f.get("key", "")) == key:
			return f.get("items", [])
	return []

# Плоская сетка вместо полок: категорию уже называет подсвеченная строка слева,
# а второй заголовок над теми же предметами только путает. Клетка уходит с
# пустым слотом - слот-цель принадлежит шагу 1.
func _rebuild_gear_grid(facets: Array) -> void:
	if _gear_grid == null:
		return
	for child in _gear_grid.get_children():
		_gear_grid.remove_child(child)
		child.queue_free()
	var found := _facet_items(facets, _ui._session.gear_facet_key)
	if _ui._session.gear_sub_key != "":
		var only: Array = []
		for e in found:
			if str(e.get("sub", "")) == _ui._session.gear_sub_key:
				only.append(e)
		found = only
	if _ui._session.gear_only_selected and _ui._session.draft != null:
		var picked: Array = []
		for e in found:
			var res_it = e.get("item")
			if res_it != null and _ui._session.draft.gear_index_of(str(res_it.resource_path)) >= 0:
				picked.append(e)
		found = picked
	if found.is_empty():
		var note := Label.new()
		note.text = Loc.txt("Nothing fits")
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", VTKSurface.GREY_DIM)
		_gear_grid.add_child(note)
		return
	for entry in found:
		var res = entry.get("item")
		if res == null:
			continue
		_gear_grid.add_child(_make_item_cell(res, "", true, true))

# Шаг 2 не фильтрует по слоту: слот-цель принадлежит шагу 1, и переносить её
# сюда значило бы всюду показывать предметы только одного слота. Запрос тоже не
# применяется здесь: facets_of считает его сам, иначе фильтр был бы применён
# дважды - на входе и в счётчиках фасетов.
func _items_for_gear() -> Array:
	var out: Array = []
	for it in Items.all():
		if it == null:
			continue
		out.append(_entry(it))
	return out

func _build_page_done() -> Control:
	var v := _page_wrap()

	# Карточка трёх колонок состава; имя сета и кнопка хоткея живут в столбце
	# «Управление», как в превью. Узлы создаются один раз и перевешиваются в
	# столбец при каждой пересборке (_refresh_page_done), чтобы не терять текст.
	_name_input = LineEdit.new()
	_name_input.placeholder_text = Loc.txt("Enter a name...")
	_name_input.add_theme_color_override("font_color", Color("#ffffff"))
	_name_input.add_theme_color_override("placeholder_color", VTKSurface.GREY_DIM)
	_name_input.add_theme_stylebox_override("normal", VTKSurface.panel(true, 10))
	_name_input.add_theme_stylebox_override("focus", VTKSurface.focus_style())
	if _ui._session.draft != null:
		_name_input.text = _ui._session.draft.set_name

	# Хоткей назначается до сохранения: для нового сета бинд копится в
	# _pending_qk и применяется в _ui._save_loadout.
	_ui._rail._bind_btn = Button.new()
	_ui._rail._done_bind_btn = _ui._rail._bind_btn
	_ui._rail._bind_btn.custom_minimum_size = Vector2(120, 0)
	_ui._rail._apply_qk_btn(_ui._rail._bind_btn, _ui._rail._display_qk())
	_ui._rail._bind_btn.pressed.connect(func(): _ui._rail._begin_bind("", _ui._rail._done_bind_btn, true))

	_done_preview = _ui._rail._build_set_preview({}, [], false,
		_ui._rail._make_control_column(Loc.txt("Controls").to_upper(), []))
	v.add_child(_done_preview)
	return v

# Сводка перед сохранением: что уйдёт в сет. Пересобирается целиком тем же
# билдером, что и превью сета, - вторая раскладка не нужна.
func _refresh_page_done() -> void:
	if _done_preview == null:
		return
	# Поле имени и кнопка хоткея переживают пересборку: отцепить от старого
	# столбца, иначе queue_free унёс бы их вместе с ним (текст и фокус).
	if _name_input != null and _name_input.get_parent() != null:
		_name_input.get_parent().remove_child(_name_input)
	if _ui._rail._done_bind_btn != null and _ui._rail._done_bind_btn.get_parent() != null:
		_ui._rail._done_bind_btn.get_parent().remove_child(_ui._rail._done_bind_btn)
	for child in _done_preview.get_children():
		_done_preview.remove_child(child)
		child.queue_free()
	var save_btn := Button.new()
	save_btn.text = Loc.txt("Save loadout")
	VTKSurface.style_button(save_btn, true)
	save_btn.pressed.connect(_ui._save_loadout)
	var cancel_btn := Button.new()
	cancel_btn.text = Loc.txt("Cancel")
	VTKSurface.style_button(cancel_btn)
	cancel_btn.pressed.connect(_ui._cancel_draft)
	_done_preview.add_child(_ui._rail._build_set_preview(
		_ui._session.draft.equip if _ui._session.draft else {},
		_ui._session.draft.gear if _ui._session.draft else [],
		false,
		_ui._rail._make_control_column(Loc.txt("Controls").to_upper(),
			[_name_input, _ui._rail._done_bind_btn, save_btn, cancel_btn])))

func _refresh_page_equipment() -> void:
	# Один обход каталога на пересборку: и шапка фильтров, и полки берут один
	# и тот же набор, а _target_filter_items проходит весь каталог целиком.
	var found := _target_filter_items()
	_rebuild_target_bar(found)
	_refresh_slots()
	_rebuild_shelves(found)

func _refresh_slots() -> void:
	if _equip_grid_box == null:
		return
	for child in _equip_grid_box.get_children():
		_equip_grid_box.remove_child(child)
		child.queue_free()
	if _ui._session.draft == null:
		return
	if _ui._equip_cells.is_empty():
		_ui._build_equip_layout()
	if _ui._equip_cells.is_empty():
		return
	_equip_grid_box.add_child(_make_equip_grid(_ui._equip_cells, _ui._equip_cols, _ui._equip_rows))

# Стиль клетки сетки экипировки: непрозрачная заливка, слот читается как слот, а
# не как ряд фоновых ячеек 1×1. Занятая клетка чуть теплее и с цветом рамки
# предмета, пустая - тёмная с едва заметной рамкой. Активная цель - золото.
func _equip_cell_style(active: bool, hover: bool = false, occupied: bool = false) -> StyleBoxFlat:
	var key := (1 if active else 0) | (2 if hover else 0) | (4 if occupied else 0)
	if _ui._equip_styles.has(key):
		return _ui._equip_styles[key]
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#241d13") if occupied else Color("#1e1a15")
	if active:
		s.bg_color = Color("#2c2417")
	s.set_border_width_all(1)
	s.corner_radius_all = 6
	if active:
		s.border_color = _ui._gold
	elif hover:
		s.border_color = Color("#c9823a")
	elif occupied:
		s.border_color = Color("#8a6a30")
	else:
		s.border_color = Color("#4a443a")
	_ui._equip_styles[key] = s
	return s

# Нужно ли разворачивать иконку предмета в этом слоте. Стволы в Primary/Secondary
# лежат вдоль горизонтали, а слот вытянут по вертикали, поэтому их иконку крутим
# дулом вверх. Пистолеты компактны и читаются как есть - их не трогаем. Правило
# здесь, а не в Picker: ему нужен ресурс слота, а Picker держится чистой логикой.
func _rotates_icon(slot: String, desc: Dictionary) -> bool:
	if slot != "Primary" and slot != "Secondary":
		return false
	var res: Variant = Items.cell_resource(desc)
	if res == null:
		return false
	var path := str(res.get("resource_path"))
	return Picker.subcategory_of(path, res.get("type")) != "Pistols"

# Есть ли в слоте вложения (плита рига, обвесы оружия). Пустой ключ и не-массив
# считаются отсутствием.
func _has_attachments(src: Dictionary) -> bool:
	var a = src.get("attachments")
	return typeof(a) == TYPE_ARRAY and (a as Array).size() > 0

# Имена `file` навешанных обвесов и их классы: по file прячем/показываем детей
# сцены tetris, по классам Picker.composite_pack выбирает позу.
func _composite_meta(src: Dictionary) -> Dictionary:
	var files: Array = []
	var classes: Array = []
	var ats = src.get("attachments")
	if typeof(ats) == TYPE_ARRAY:
		for p in ats:
			var r = _ui._item_info(str(p)).get("resource")
			if r == null:
				continue
			files.append(str(r.get("file")))
			var cls := Picker.attachment_class(r.get("subtype"))
			if cls != "" and not classes.has(cls):
				classes.append(cls)
	return {"files": files, "classes": classes}

# Оружие рисуется своей сценой tetris: база + спрайты обвесов, как в экране
# персонажа игры. Прячем всех детей, показываем навешанные, поза - из пакета.
# Возвращает false, если композита нет (не оружие/нет tetris) - тогда рисуется
# прежняя иконка. Смещение пакета в 64-пространстве, при повороте разворачиваем
# его тем же -90°, что и узел, чтобы оси совпали с ванильными.
func _render_composite(box: Panel, res, src: Dictionary, w: int, h: int, rotated: bool) -> bool:
	var scene = res.get("tetris")
	if scene == null:
		return false
	var node: Node2D = scene.instantiate()
	var meta := _composite_meta(src)
	for ch in node.get_children():
		ch.visible = meta["files"].has(str(ch.name))
	var pack := Picker.composite_pack(res, meta["classes"])
	var base = res.get("size")
	if not (base is Vector2) or base.x <= 0.0 or base.y <= 0.0:
		base = Vector2(1, 1)
	var cell := Vector2(w * EQ_CELL + (w - 1) * EQ_GAP, h * EQ_CELL + (h - 1) * EQ_GAP)
	var place := Picker.composite_placement(base, cell, 8.0, pack, rotated)
	node.scale = Vector2(place["scale"], place["scale"])
	node.rotation_degrees = -90.0 if rotated else 0.0
	node.position = place["position"]
	box.add_child(node)
	return true

# Размер глифа присутствия по клетке: max(w,h) >= 6 -> L, 4..5 -> M, 2 -> S, 1 -> XS.
# Реально встречаются S (риг 2×2) и XS (NVG/Player 1×1); L/M - фолбэк, если
# композит оружия почему-то не сработал.
func _glyph_size(w: int, h: int) -> int:
	var m := maxi(w, h)
	if m >= 6:
		return 16
	if m >= 4:
		return 14
	if m == 2:
		return 13
	return 11

# Размер крестика и шрифт по клетке: L 26/14, M/S 22/12, XS 18/10.
func _x_size(w: int, h: int) -> Dictionary:
	var m := maxi(w, h)
	if m >= 6:
		return {"box": 26, "font": 14}
	if m == 1:
		return {"box": 18, "font": 10}
	return {"box": 22, "font": 12}

# Клетка слота в укладке: w×h ячеек, занятая показывает иконку предмета, пустая
# (или без иконки) - имя слота. Клик - прежний _on_slot_row_input: выбор цели,
# второй клик по занятой цели открывает панель обвесов.
func _make_equip_cell(slot: String, w: int, h: int, desc: Dictionary = {}, interactive := true) -> Control:
	var src: Dictionary = desc
	if src.is_empty() and interactive:
		if _ui._session.draft != null:
			var raw = _ui._session.draft.equip.get(slot)
			if typeof(raw) == TYPE_DICTIONARY:
				src = raw
	var occupied := not src.is_empty()
	var active: bool = interactive and _ui._session.target_slot == slot
	var box := Panel.new()
	box.custom_minimum_size = Vector2(w * EQ_CELL + (w - 1) * EQ_GAP, h * EQ_CELL + (h - 1) * EQ_GAP)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.clip_contents = true
	box.tooltip_text = str(src.get("name", Loc.txt(slot))) if occupied else Loc.txt(slot)
	box.add_theme_stylebox_override("panel", _equip_cell_style(active, false, occupied))
	if interactive:
		_ui._attach_row_hover(box, func(hv: bool): return _equip_cell_style(active, hv, occupied))
		box.gui_input.connect(func(ev): _on_slot_row_input(ev, slot, src))

	# Variant: `Items.cell_resource` отдаёт Variant, а `:=` на нём - предупреждение,
	# которое стенд считает ошибкой парсинга.
	var res: Variant = Items.cell_resource(src) if occupied else null
	var rotated := occupied and _rotates_icon(slot, src)
	var composited := false
	if occupied and res != null and res.get("tetris") != null and str(res.get("type")) == "Weapon":
		composited = _render_composite(box, res, src, w, h, rotated)

	if not composited:
		var tex = _ui._item_icon(res) if occupied else null
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(center)
		if tex != null:
			var icon := TextureRect.new()
			icon.texture = Picker.item_art(tex, rotated)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			var sq := maxi(16, mini(w * EQ_CELL, h * EQ_CELL) - 16)
			icon.custom_minimum_size = Vector2(sq, sq)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			center.add_child(icon)
		else:
			var lb := Label.new()
			lb.text = Loc.txt(slot)
			lb.add_theme_font_size_override("font_size", 9)
			lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lb.add_theme_color_override("font_color", VTKSurface.INK if occupied else VTKSurface.BROWN)
			lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			center.add_child(lb)

	# Признак вложения там, где композита нет (риг с плитой, NVG/Player). Оружию
	# не нужен: обвесы видны на модели.
	if not composited and _has_attachments(src):
		var gsz := _glyph_size(w, h)
		var gear := TextureRect.new()
		gear.texture = VTKSurface.gear_icon(gsz, _ui._gold)
		gear.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gear.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gear.custom_minimum_size = Vector2(gsz, gsz)
		gear.size = Vector2(gsz, gsz)
		gear.position = Vector2(5, 4)
		gear.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(gear)

	if interactive and occupied:
		var xs := _x_size(w, h)
		var drop := _make_mini_btn("✕", Vector2(xs["box"], xs["box"]), xs["font"])
		drop.tooltip_text = Loc.txt("Remove")
		drop.add_theme_color_override("font_color", Color("#e05a4a"))
		drop.pressed.connect(func(): _remove_slot(slot))
		box.add_child(drop)
		drop.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		drop.offset_left = -(int(xs["box"]) + 4)
		drop.offset_top = 4
		drop.offset_right = -4
		drop.offset_bottom = int(xs["box"]) + 4
	return box

# Укладка экипировки (вариант E): клетки слотов ложатся по координатам из
# Picker.equip_layout, фоновая сетка cols×rows не рисуется - слоты и есть сетка.
# Отдельных секций оружия/тела/мелочи и силуэта нет: положение слота задаёт
# раскладка. Шаг сетки (EQ_CELL + EQ_GAP) держит клетки на одной линии.
func _make_equip_grid(cells: Array, cols: int, rows: int, eq: Dictionary = {}, interactive := true) -> Control:
	var gw := cols * EQ_CELL + (cols - 1) * EQ_GAP
	var gh := rows * EQ_CELL + (rows - 1) * EQ_GAP
	var zone := Control.new()
	zone.custom_minimum_size = Vector2(gw, gh)
	zone.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for row in cells:
		if row.size() < 5:
			continue
		var slot := str(row[0])
		var w := int(row[3])
		var h := int(row[4])
		var box := _make_equip_cell(slot, w, h, eq.get(slot, {}), interactive)
		box.position = Vector2(int(row[1]) * (EQ_CELL + EQ_GAP), int(row[2]) * (EQ_CELL + EQ_GAP))
		box.size = Vector2(w * EQ_CELL + (w - 1) * EQ_GAP, h * EQ_CELL + (h - 1) * EQ_GAP)
		zone.add_child(box)
	return zone

# Превью сета: та же укладка, что во вкладке, но некликабельная и с занятыми
# клетками из сета. Колонка фиксирована (EQ_COL_W), остаток строки забирает
# стена инвентаря.
func _make_equip_preview(eq: Dictionary) -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(EQ_COL_W, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 6)
	panel.add_theme_stylebox_override("panel", VTKSurface.panel(true, 6))
	var head := Label.new()
	head.text = Loc.txt("Equipment").to_upper()
	head.add_theme_font_size_override("font_size", 9)
	head.add_theme_color_override("font_color", _ui._gold)
	head.add_theme_constant_override("letter_spacing", 1)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(head)
	# Слоты берём из каталога, как в редакторе (_refresh_slots): превью повторяет
	# укладку целиком, включая пустые клетки, даже если сет занял лишь часть
	# слотов.
	if _ui._equip_cells.is_empty():
		_ui._build_equip_layout()
	var cells: Array = _ui._equip_cells
	if cells.is_empty():
		var ph := Label.new()
		ph.text = Loc.txt("Set is empty")
		ph.add_theme_font_size_override("font_size", 11)
		ph.add_theme_color_override("font_color", VTKSurface.GREY_DIM)
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(ph)
	else:
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 6)
		pad.add_theme_constant_override("margin_top", 6)
		pad.add_theme_constant_override("margin_right", 6)
		pad.add_theme_constant_override("margin_bottom", 6)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(_make_equip_grid(cells, _ui._equip_cols, _ui._equip_rows, eq, false))
		panel.add_child(pad)
	return panel

func _wall_item(desc: Dictionary) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(INVEN_CELL, INVEN_CELL)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.tooltip_text = str(desc.get("name", "?"))
	var tex = _ui._item_icon(Items.cell_resource(desc))
	if tex != null:
		var img := _art_texture_rect(tex, Vector2.ZERO)
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.add_child(img)
		var qty := Draft.shown_count(desc)
		if qty > 1:
			var q := Label.new()
			q.text = "×" + str(qty)
			q.add_theme_font_size_override("font_size", 9)
			q.add_theme_color_override("font_color", _ui._gold)
			q.mouse_filter = Control.MOUSE_FILTER_IGNORE
			q.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			q.offset_left = -24
			q.offset_top = -18
			q.offset_right = -2
			q.offset_bottom = -2
			box.add_child(q)
	return box

# Стена инвентаря: чипы 1×1, 8 колонок, минимум 8 рядов - поле всегда квадрат
# 581×581 (при ≤64 стеках). Не растягивается по ширине: блок превью прижат
# влево, остаток строки - справа. Пиксельные координаты, посчитанные один
# раз, не пережили бы ресайз окна, поэтому предметы держатся якорями -
# долями от ширины/высоты стены.
func _make_inventory_wall(gear: Array) -> Control:
	var n := 0
	for desc in gear:
		if typeof(desc) == TYPE_DICTIONARY:
			n += 1
	var rows := maxi(INVEN_ROWS, int(ceil(n / float(INVEN_COLS))))
	var wall := Control.new()
	wall.custom_minimum_size = Vector2(INVEN_COLS * INVEN_CELL + (INVEN_COLS - 1) * INVEN_GAP,
		rows * INVEN_CELL + (rows - 1) * INVEN_GAP)
	wall.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	wall.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wall.clip_contents = true
	var bg := GridContainer.new()
	bg.columns = INVEN_COLS
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_constant_override("h_separation", INVEN_GAP)
	bg.add_theme_constant_override("v_separation", INVEN_GAP)
	if _ui._inven_bg_style == null:
		_ui._inven_bg_style = StyleBoxFlat.new()
		_ui._inven_bg_style.bg_color = Color("#14110c")
		_ui._inven_bg_style.corner_radius_all = 3
	for i in range(rows * INVEN_COLS):
		var gc := Panel.new()
		gc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		gc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gc.add_theme_stylebox_override("panel", _ui._inven_bg_style)
		bg.add_child(gc)
	wall.add_child(bg)
	var idx := 0
	for desc in gear:
		if typeof(desc) != TYPE_DICTIONARY:
			continue
		var item := _wall_item(desc)
		var col := idx % INVEN_COLS
		var row := int(idx / INVEN_COLS)
		item.anchor_left = float(col) / float(INVEN_COLS)
		item.anchor_right = float(col + 1) / float(INVEN_COLS)
		item.anchor_top = float(row) / float(rows)
		item.anchor_bottom = float(row + 1) / float(rows)
		item.offset_left = 0.0
		item.offset_top = 0.0
		item.offset_right = 0.0
		item.offset_bottom = 0.0
		wall.add_child(item)
		idx += 1
	return wall

func _make_inventory_panel(gear: Array) -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(INVEN_COLS * INVEN_CELL + (INVEN_COLS - 1) * INVEN_GAP + 12, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	var ttl := Label.new()
	ttl.text = Loc.txt("Inventory").to_upper()
	ttl.add_theme_font_size_override("font_size", 9)
	ttl.add_theme_color_override("font_color", _ui._gold)
	ttl.add_theme_constant_override("letter_spacing", 1)
	ttl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(ttl)
	panel.add_child(head)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wall := _make_inventory_wall(gear)
	pad.add_child(wall)
	panel.add_child(pad)
	return panel

# Клик по строке слота: строка становится целью, а клик по текущей цели с
# предметом открывает панель обвесов. Иначе обвесы пришлось бы искать
# отдельной кнопкой, а в колонке для неё нет места.
func _on_slot_row_input(ev: InputEvent, slot: String, desc: Dictionary) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var path_now := str(desc.get("path", ""))
	if path_now != "" and _ui._session.target_slot == slot:
		_toggle_attachment_panel(path_now)
		return
	_set_target_slot(slot)

func _make_slot_style(active: bool, hover: bool = false, empty: bool = false) -> StyleBox:
	if empty:
		return VTKSurface.surface("hover" if hover else "disabled", active, false, active, 4, 4, 2, 2)
	return VTKSurface.surface("hover" if hover else "normal", active, false, active, 4, 4, 2, 2)

# Точка-индикатор 7x7. Отдельный узел, а не символ в тексте: цвет задаётся
func _make_dot(color: Color) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(7, 7)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_all = 2
	p.add_theme_stylebox_override("panel", s)
	return p

# Золотой свитч из макета: капсула 34x18 с ползунком. CheckButton так не
# рисуется, поэтому свой Control с двумя панелями и сигналом toggled.
class ToggleSwitch:
	extends Control
	signal toggled(value: bool)
	const GOLD := VTKSurface.GOLD
	var _on := false
	var _track: Panel = null
	var _knob: Panel = null

	func _ready() -> void:
		custom_minimum_size = Vector2(34, 18)
		_track = Panel.new()
		_track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_track)
		_knob = Panel.new()
		_knob.custom_minimum_size = Vector2(12, 12)
		_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_knob.position = Vector2(2, 3)
		add_child(_knob)
		_refresh(false)

	func set_on(v: bool, emit := false) -> void:
		if _on == v:
			return
		_on = v
		_refresh(true)
		if emit:
			toggled.emit(v)

	# button_pressed для совместимости с CheckButton-вызовами.
	var button_pressed: bool:
		get:
			return _on
		set(v):
			set_on(v, false)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			set_on(not _on, true)

	func _refresh(animate: bool) -> void:
		if _track == null:
			return
		var ts := StyleBoxFlat.new()
		if _on:
			ts.bg_color = Color("#2a1a0a")
			ts.border_color = GOLD
		else:
			ts.bg_color = Color("#241b12")
			ts.border_color = VTKSurface.BORDER
		ts.border_width_all = 1
		ts.corner_radius_all = 9
		_track.add_theme_stylebox_override("panel", ts)
		var ks := StyleBoxFlat.new()
		ks.bg_color = GOLD if _on else Color("#6b5a46")
		ks.corner_radius_all = 6
		ks.shadow_color = Color(0, 0, 0, 0.4)
		ks.shadow_size = 2
		ks.shadow_offset = Vector2(0, 1)
		_knob.add_theme_stylebox_override("panel", ks)
		var target := Vector2(18, 3) if _on else Vector2(2, 3)
		if animate:
			var tw := create_tween()
			tw.tween_property(_knob, "position", target, 0.15) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			_knob.position = target

func _rebuild_target_bar(found: Array) -> void:
	if _target_bar == null:
		return
	for child in _target_bar.get_children():
		_target_bar.remove_child(child)
		child.queue_free()

	var tgt := Label.new()
	tgt.text = Loc.txt(_ui._session.target_slot) if _ui._session.target_slot != "" else "-"
	tgt.add_theme_font_size_override("font_size", 10)
	tgt.add_theme_color_override("font_color", _ui._gold)
	_target_bar.add_child(tgt)

	# Показываем только когда есть что фильтровать: несколько категорий -
	# чипы категорий (плюс подкатегории выбранной), одна категория с
	# несколькими подкатегориями - только подкатегории, единственный
	# экземпляр и того и другого - не показываем вовсе.
	var cats := _target_cats(found)
	var show_subs: Array = []
	var show_line := false
	if cats.size() > 1:
		show_line = true
		if _ui._session.target_cat != "":
			show_subs = _target_subs(found, _ui._session.target_cat)
	elif cats.size() == 1:
		show_subs = _target_subs(found, cats[0])
		show_line = show_subs.size() > 1
	if not show_line:
		return

	var line := HFlowContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_constant_override("h_separation", 4)
	line.add_theme_constant_override("v_separation", 2)

	var lbl := Label.new()
	lbl.text = Loc.txt("Filter") + ":"
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", VTKSurface.BROWN)
	line.add_child(lbl)

	if cats.size() > 1:
		for c in cats:
			line.add_child(_make_filter_chip(c, _ui._session.target_cat == c))
	for sub in show_subs:
		line.add_child(_make_filter_chip(sub, _ui._session.target_sub == sub, true))

	var reset := Button.new()
	reset.text = Loc.txt("Reset")
	reset.add_theme_font_size_override("font_size", 9)
	reset.tooltip_text = Loc.txt("Reset")
	var any_on: bool = _ui._session.target_cat != "" or _ui._session.target_sub != ""
	reset.add_theme_stylebox_override("normal", _ui._make_chip_style(any_on))
	reset.add_theme_color_override("font_color", _ui._gold if any_on else VTKSurface.BROWN)
	reset.pressed.connect(_reset_target_filters)
	line.add_child(reset)

	_target_bar.add_child(line)

# Чип фильтра. level = true означает подкатегорию: она не снимает старший
# уровень, а меняет только себя.
func _make_filter_chip(key: String, on: bool, level: bool = false) -> Button:
	var b := Button.new()
	var name_txt := key if level else Picker.category_label(key)
	b.text = ("> " if level else "") + Loc.txt(name_txt)
	b.add_theme_font_size_override("font_size", 9)
	b.tooltip_text = name_txt
	b.add_theme_stylebox_override("normal", _ui._make_chip_style(on))
	b.add_theme_color_override("font_color", _ui._gold if on else Color("#cccccc"))
	_ui._attach_motion(b)
	if level:
		b.pressed.connect(func(): _set_target_sub(key))
	else:
		b.pressed.connect(func(): _set_target_cat(key))
	return b

func _set_target_cat(c: String) -> void:
	_ui._session.target_cat = "" if _ui._session.target_cat == c else c
	# Смена старшего уровня сбрасывает младший: иначе после "Винтовки" ->
	# "Пистолеты" остался бы фильтр "Снайперки" из прошлой ветки.
	_ui._session.target_sub = ""
	_ui.refresh(R_EQUIP)

func _set_target_sub(s: String) -> void:
	_ui._session.target_sub = "" if _ui._session.target_sub == s else s
	_ui.refresh(R_EQUIP)

func _reset_target_filters() -> void:
	_ui._session.target_cat = ""
	_ui._session.target_sub = ""
	_ui.refresh(R_EQUIP)

# Записи каталога, подходящие слоту-цели и запросу, с посчитанной
# подкатегорией. Поиск применяет _items_for_target, поэтому шапка фильтров и
# сетка под ней всегда показывают один и тот же набор.
func _target_filter_items() -> Array:
	var out: Array = []
	if _ui._session.draft == null:
		return out
	for e in _items_for_target():
		var it = e.get("item")
		if it == null:
			continue
		out.append({
			"item": it,
			"name": str(it.get("name", "")),
			"cat": str(e.get("cat", "")),
			"sub": str(e.get("sub", "")),
		})
	return out

# Уникальные категории найденного списка в порядке чипов: сначала известный
# порядок Picker.category_keys(), затем остальные по алфавиту - строка
# фильтров и валидация должны считать набор одинаково.
func _target_cats(found: Array) -> Array:
	var known := Picker.category_keys()
	var out: Array = []
	for c in known:
		for e in found:
			if str(e.get("cat", "")) == c and not out.has(c):
				out.append(c)
	var extra: Array = []
	for e in found:
		var c := str(e.get("cat", ""))
		if c != "" and not known.has(c) and not extra.has(c):
			extra.append(c)
	extra.sort()
	out.append_array(extra)
	return out

# Подкатегории одной категории из найденного списка, в общем порядке
# Picker.order_subcategories, чтобы чипы не прыгали между перестройками.
func _target_subs(found: Array, cat: String) -> Array:
	var seen: Array = []
	for e in found:
		if str(e.get("cat", "")) == cat:
			var s := str(e.get("sub", ""))
			if s != "" and not seen.has(s):
				seen.append(s)
	return Picker.order_subcategories(seen)

# Смена запроса меняет набор найденного: под категорию или подкатегорию
# могло остаться одно или ноль предметов, и фильтр без чипов молча пускал бы
# пустую сетку. Сбрасываем только то, чего больше нет в данных.
func _validate_target_filters() -> void:
	if _ui._session.target_cat == "" and _ui._session.target_sub == "":
		return
	var found := _target_filter_items()
	var cats := _target_cats(found)
	if _ui._session.target_cat != "":
		if not cats.has(_ui._session.target_cat):
			_ui._session.target_cat = ""
			_ui._session.target_sub = ""
		elif _ui._session.target_sub != "" and not _target_subs(found, _ui._session.target_cat).has(_ui._session.target_sub):
			_ui._session.target_sub = ""
		return
	if cats.size() == 1:
		if _ui._session.target_sub != "" and not _target_subs(found, cats[0]).has(_ui._session.target_sub):
			_ui._session.target_sub = ""
	else:
		_ui._session.target_sub = ""

func _remove_slot(slot: String) -> void:
	if _ui._session.draft == null:
		return
	var path_now := str(_ui._session.draft.equip.get(slot, {}).get("path", ""))
	if _ui._session.open_equip_att == path_now:
		_ui._session.open_equip_att = ""
		_ui._session.open_gear_att = ""
	if _ui._session.target_slot == slot:
		_ui._session.target_slot = ""
	_ui._session.draft.remove_slot(slot)
	_ui.refresh(R_PAGES)

func _set_target_slot(slot: String) -> void:
	_ui._session.target_slot = slot
	# Цель сбрасывает открытую панель обвесов: она относилась к другому
	# предмету, и оставить её висеть значило бы врать про набор.
	_ui._session.open_equip_att = ""
	_ui._session.open_gear_att = ""
	_ui._session.last_placed = ""
	_ui._session.target_cat = ""
	_ui._session.target_sub = ""
	_show_page(0)
	_ui.refresh(R_PAGES)

# Живой поиск с дебаунсом: пересборка идёт не на каждый символ, а через
# короткую паузу. Поле поиска не пересоздаётся и держит курсор.
func _set_search(t: String) -> void:
	_ui._session.search_text = t
	if _search_debounce != null:
		_search_debounce.start()

func _apply_search() -> void:
	_validate_target_filters()
	_ui.refresh(R_EQUIP)

# Запись каталога для обоих шагов: предмет и его группа. Группу вычисляет
# Picker, а не строка type здесь: иначе шаг 1 и шаг 2 разошлись бы группами,
# и граната с Grenade_1 попала бы в другое место, чем её полка.
func _entry(it) -> Dictionary:
	return {
		"item": it,
		"name": str(it.get("name", "")),
		"cat": Picker.category_of(it.get("slots"), it.get("type")),
		"sub": Picker.subcategory_of(str(it.resource_path), it.get("type")),
	}

# Предметы под текущую цель и запрос. Цель - это фильтр по слотам, а не
# обязательство: клик по предмету без цели сам выбирает свободный слот.
func _items_for_target() -> Array:
	var out: Array = []
	for it in Items.all():
		if it == null:
			continue
		if not Picker.matches_search(str(it.get("name")), _ui._session.search_text):
			continue
		if _ui._session.target_slot != "" and not Picker.matches_slot(it.get("slots"), _ui._session.target_slot):
			continue
		var e := _entry(it)
		if not Picker.category_allowed(str(e.get("cat", "")), _ui._session.target_slot):
			continue
		out.append(e)
	return out

func _rebuild_shelves(found: Array) -> void:
	if _shelves_box == null:
		return
	for child in _shelves_box.get_children():
		_shelves_box.remove_child(child)
		child.queue_free()
	if _ui._session.target_cat != "":
		var only: Array = []
		for e in found:
			if str(e.get("cat", "")) == _ui._session.target_cat:
				only.append(e)
		found = only
	if _ui._session.target_sub != "":
		var only_sub: Array = []
		for e in found:
			if str(e.get("sub", "")) == _ui._session.target_sub:
				only_sub.append(e)
		found = only_sub
	if found.is_empty():
		var note := Label.new()
		note.text = Loc.txt("Nothing fits")
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", VTKSurface.GREY_DIM)
		_shelves_box.add_child(note)
		return
	for shelf in Picker.shelves_of(found):
		_shelves_box.add_child(_make_shelf(shelf))

# Полоса категории: заголовок и клетки в потоке. Заголовок остаётся на месте
# при переносе, поэтому группа читается даже когда клеток много.
func _make_shelf(shelf: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)

	var cat := str(shelf.get("cat", ""))
	var head := Label.new()
	head.text = Loc.txt(Picker.category_label(cat))
	head.add_theme_font_size_override("font_size", 10)
	# Заголовок полки нейтральный: цвет по категории вынуждал бы держать
	# палитру ради одной строки текста, а на шаге 2 категорию и так называет
	# подсвеченная строка фасета.
	head.add_theme_color_override("font_color", VTKSurface.INK)
	box.add_child(head)

	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	for entry in shelf.get("items", []):
		var res = entry.get("item")
		if res == null:
			continue
		flow.add_child(_make_item_cell(res))
	box.add_child(flow)
	return box

func _make_att_btn(desc) -> Button:
	var path_now := str(desc.get("path", ""))
	var atts = desc.get("attachments") if desc.has("attachments") else []
	var b := Button.new()
	b.icon = VTKSurface.gear_icon(18, _ui._gold if atts.size() > 0 else VTKSurface.GREY)
	b.expand_icon = true
	b.custom_minimum_size = Vector2(20, 20)
	VTKSurface.style_button(b, true, false, 2, 2, 2, 2)
	b.pressed.connect(func(): _toggle_attachment_panel(path_now))
	return b

# Шаг «−/+» и потолок клетки снаряжения. Патроны шагают стаком калибра и
# упираются во вместимость; обоймы - по штуке до 99; прочее - по одному до
# maxAmount, если он задан. Знание о ресурсе живёт здесь, в Draft не идёт.
func _gear_step(path: String) -> float:
	var info = _ui._item_info(path)
	if str(info.get("type")) == "Ammo":
		var da = info.get("defaultAmount")
		if da != null and float(da) >= 1.0:
			return float(da)
	return 1.0

func _gear_cap(path: String) -> float:
	if _is_magazine(path):
		return 99.0
	var ma = _ui._item_info(path).get("maxAmount")
	if ma != null and float(ma) > 1.0:
		return float(ma)
	return 0.0

# dir - направление шага (+1 / -1), не сырая дельта: шаг, потолок и пол зависят
# от ресурса, поэтому считаются здесь, а не в вызывающем коде. У патронов пол 0:
# «−» на последней коробке убирает патроны из набора, как ✕.
func _bump_gear(path: String, dir: float) -> void:
	if _ui._session.draft == null:
		return
	var floor := 0.0 if str(_ui._item_info(path).get("type")) == "Ammo" else 1.0
	_ui._session.draft.bump_amount(path, dir, _gear_step(path), _gear_cap(path), floor)
	_ui.refresh(R_GEAR | R_DONE)

func _toggle_attachment_panel(path: String) -> void:
	_ui._session.toggle_attachment_target(path)
	_ui.refresh(R_OVERLAY)

# Оверлей рендерит панель текущей страницы: путь своя у Экипировки и
# Снаряжения; при пустом пути или закрытом черновике прячется.
func _refresh_att_overlay() -> void:
	if _att_overlay == null or _att_overlay_body == null:
		return
	for child in _att_overlay_body.get_children():
		_att_overlay_body.remove_child(child)
		child.queue_free()
	var path: String = _ui._session.attachment_target()
	if _ui._session.draft == null or path == "":
		_att_overlay.visible = false
		return
	var panel := _build_att_panel(path)
	if panel == null:
		_att_overlay.visible = false
		return
	_att_overlay_body.add_child(panel)
	_att_overlay.visible = true

func _close_att_overlay() -> void:
	_ui._session.clear_attachments()
	_ui.refresh(R_OVERLAY)

# Иконка предмета: кроп прозрачных полей через Picker.item_art и режим
# сохранения пропорций. Общая для клеток шага 1/2 и чипа инвентаря.
func _art_texture_rect(art: Texture2D, min_size: Vector2) -> TextureRect:
	var tex := TextureRect.new()
	tex.texture = Picker.item_art(art)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.custom_minimum_size = min_size
	tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tex

# Иконка над подписью, по центру клетки: CenterContainer на всю клетку, VBox,
# TextureRect и подпись. Возвращает VBox, чтобы клетка дописала свои ряды.
func _icon_stack(host: Control, art: Texture2D, icon_min: Vector2, name_text: String,
		name_size: int, name_color: Color, name_lines: int) -> VBoxContainer:
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)
	var tex := _art_texture_rect(art, icon_min)
	vbox.add_child(tex)
	var name_lbl := Label.new()
	name_lbl.text = name_text
	name_lbl.add_theme_font_size_override("font_size", name_size)
	name_lbl.add_theme_color_override("font_color", name_color)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_lbl.max_lines_visible = name_lines
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)
	return vbox

func _make_item_cell(item, forced_slot = null, gear := false, force_gear := false) -> Control:
	var path_now: String = item.resource_path
	var gi: int = _ui._session.draft.gear_index_of(path_now) if (gear and _ui._session.draft != null) else -1
	var cell = Panel.new()
	# Клетка снаряжения выше и шире: под именем два ряда - шаговый «− n +»
	# и контекстная кнопка (Full/обойма/обвес); ✕ живёт в углу. Каталог
	# шага 1 остаётся ниже - там под именем только счётчик.
	# Ширина берётся из GEAR_CELL_W: расчёт колонок обязан совпадать с
	# вёрсткой, иначе сетка переполняется и появляется прокрутка.
	cell.custom_minimum_size = Vector2(GEAR_CELL_W, 200 if gi >= 0 else (168 if gear else 152))
	# Без SIZE_EXPAND_FILL: HFlowContainer растягивает такие клетки на всю
	# ширину полосы, пока предметов мало (stretch в flow_container.cpp).
	cell.mouse_filter = Control.MOUSE_FILTER_STOP

	var normal_style := VTKSurface.surface("normal")
	var hover_style := VTKSurface.surface("hover")
	var in_set_style := VTKSurface.surface("normal", true, false, true)

	cell.add_theme_stylebox_override("panel", normal_style)

	var vbox := _icon_stack(cell, _ui._item_icon(item), Vector2(GEAR_CELL_W - 32, 56),
		str(item.name), 9, Color("#aaa"), 2)

	var already: bool = _ui._session.draft != null and _ui._session.draft.has_path(path_now)
	if already and not gear:
		var cur_slot: String = _ui._session.draft.equip_slot_of(path_now)
		if cur_slot == "":
			var n := int(_ui._session.draft.amount_of(path_now))
			if n > 1:
				var cnt = Label.new()
				cnt.text = "×" + str(n)
				cnt.add_theme_font_size_override("font_size", 8)
				cnt.add_theme_color_override("font_color", _ui._gold)
				cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
				vbox.add_child(cnt)
		cell.add_theme_stylebox_override("panel", in_set_style)

	if gear and _ui._session.draft != null and gi >= 0:
		cell.add_theme_stylebox_override("panel", in_set_style)
		var desc_g: Dictionary = _ui._session.draft.gear[gi]
		var cnt_g := Draft.shown_count(desc_g)

		# Строка A: шаг «− n +». Дубль ×N убран - число живёт здесь само.
		var row_a := HBoxContainer.new()
		row_a.add_theme_constant_override("separation", 4)
		row_a.alignment = BoxContainer.ALIGNMENT_CENTER
		row_a.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var minus := _make_mini_btn("−", Vector2(28, 28), 15)
		minus.pressed.connect(func(): _bump_gear(path_now, -1.0))
		row_a.add_child(minus)
		row_a.add_child(_make_gear_count(cnt_g))
		var plus := _make_mini_btn("+", Vector2(28, 28), 15)
		plus.pressed.connect(func(): _bump_gear(path_now, 1.0))
		row_a.add_child(plus)
		vbox.add_child(row_a)

		# Строка B: одно контекстное действие предмета, если оно есть.
		# Патроны - разовый Full, обоймы - тумблер Full magazine/Empty.
		# Обвесы больше не здесь: шестерёнка уехала в угол клетки.
		var row_b := _make_gear_action_row(path_now, desc_g)
		if row_b != null:
			vbox.add_child(row_b)

		# Обвесы: шестерёнка в левом верхнем углу, зеркально ✕ справа.
		# Прежняя текстовая «обв.N» занимала строку B и больше не нужна.
		if _att_panel_needed(_ui._item_info(path_now)):
			var gear_btn := _make_att_btn(desc_g)
			cell.add_child(gear_btn)
			gear_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			gear_btn.offset_left = 2
			gear_btn.offset_top = 2
			gear_btn.offset_right = 22
			gear_btn.offset_bottom = 22

		# Удаление - крестик в правом верхнем углу клетки, красный: это
		# уничтожение набора, его не должно быть рядом с «В инвентарь».
		# Panel - не контейнер, якоря работают; кнопка добавляется после
		# center и рисуется поверх, клики на себя забирает она.
		var drop := _make_mini_btn("✕", Vector2(20, 20), 11)
		VTKSurface.style_button(drop, false, true, 2, 2, 2, 2)
		drop.add_theme_color_override("font_color", Color("#e05a4a"))
		drop.tooltip_text = Loc.txt("Remove")
		drop.pressed.connect(func(): _remove_gear(path_now))
		cell.add_child(drop)
		drop.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		drop.offset_left = -22
		drop.offset_top = 2
		drop.offset_right = -2
		drop.offset_bottom = 22

	cell.tooltip_text = item.name

	var it = item
	# Шаг 2 зовёт клетку с пустой целью явно, иначе цель шага 1 переехала бы
	# на шаг 2 вместе с клеткой. Клик по пустой gear-клетке добавляет предмет
	# тем же _place_into (Draft.add_gear).
	var slot: String = _ui._session.target_slot if forced_slot == null else str(forced_slot)
	cell.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_place_into(it, slot, force_gear)
	)
	# Рамка набора обязана переживать курсор: при выходе возвращаем ту же
	# рамку, что стояла до наведения. Прежний общий normal_style гасил её,
	# и клетка выглядела выбранной ровно до первого наведения.
	cell.mouse_entered.connect(func():
		var base_style := in_set_style if already else hover_style
		cell.add_theme_stylebox_override("panel", base_style)
	)
	cell.mouse_exited.connect(func():
		var base_style := in_set_style if already else normal_style
		cell.add_theme_stylebox_override("panel", base_style)
	)
	return cell

# Клик по предмету. Слот-цель решает всё: при явной цели предмет вытесняет то,
# что стояло в этом слоте, при пустой занимает первый свободный слот сам, а если
# слотов нет - уходит в снаряжение. force_gear (шаг 2) кладёт предмет сразу в
# снаряжение через Draft.add_gear, минуя свободный слот экипировки.
func _place_into(item, slot: String, force_gear := false) -> void:
	if _ui._session.draft == null or item == null:
		return
	var path := str(item.resource_path)
	if path == "":
		return
	var res = Items.index_of(path)
	if res == null:
		res = load(path)
	if res == null:
		return
	# Запоминаем предмет до расчёта количества: если предмет не влезет в слот,
	# _after_place не зовётся, и без этого строка ушла бы в следующий клик и
	# открыла панель не того предмета.
	_ui._session.last_placed = path
	var t := str(res.get("type"))
	# Патроны в снаряжение попадают коробкой (defaultAmount) и той же коробкой
	# шагают: клик и «+/−» в одном масштабе, потолок - maxAmount. Прочие
	# стакаемые по-прежнему берут maxAmount; оружие - 1.
	var amt := 1.0
	var step := 0.0
	var cap := 0.0
	if t == "Ammo":
		var da = res.get("defaultAmount")
		if da != null and float(da) >= 1.0:
			amt = float(da)
			step = float(da)
		var ma = res.get("maxAmount")
		if ma != null and float(ma) > 1.0:
			cap = float(ma)
	elif t != "Weapon":
		var max_am = res.get("maxAmount")
		if max_am != null and float(max_am) > 1.0:
			amt = float(max_am)
	var counted := t == "Attachment" and str(res.get("subtype")) == "Magazine"
	var slots = Items.item_slots(res)
	var item_name := str(res.get("name"))
	# Шаг 2 («Снаряжение»): слот не выбирается, предмет идёт в снаряжение и
	# не занимает свободный слот экипировки.
	if force_gear:
		_ui._session.draft.add_gear(path, item_name, amt, t, counted, step, cap)
		_after_place()
		return
	if slot != "":
		# add_to_slot отказывает, не тронув набор, если предмет не подходит
		# слоту. Отказ - это не вытеснение, поэтому сообщаем и выходим, а не
		# падаем в add(): иначе предмет молча уехал бы в другое место мимо
		# выбранной цели.
		if _ui._session.draft.add_to_slot(path, item_name, slots, amt, t, slot, counted) != "":
			_after_place()
			return
		if not Picker.matches_slot(slots, slot):
			_set_problem(Loc.txt("Does not fit: ") + Loc.txt(slot))
			return
	_ui._session.draft.add(path, item_name, slots, amt, t, counted, step, cap)
	_after_place()

func _after_place() -> void:
	_clear_problem()
	# Клик по предмету открывает его обвесы: иначе до них надо было
	# добираться через кнопку в строке слота, о чём мало кто догадывался.
	# У обоймы панели нет - там тумблер заполнения, открывать нечего.
	if _ui._session.last_placed != "" and not _is_magazine(_ui._session.last_placed) \
			and _att_panel_needed(_ui._item_info(_ui._session.last_placed)):
		_ui._session.set_attachment_target(_ui._session.last_placed)
	_ui._session.last_placed = ""
	_ui.refresh(R_PAGES)

# У обоймы единственный "обвес" — совместимый патрон, и он уезжает в
# slotData.nested, который игра не читает: количество патронов в обойме целиком
# задаётся её amount. Поэтому блок обвесов у обоймы отдан под тумблер
# заполнения: ВКЛ = maxAmount патронов, ВЫКЛ = пустая обойма.
# Панель обвесов и панель обоймы больше не строятся как CheckButton-списки с
# независимыми галочками: выбор одиночный по группе, и переключение делает
# черновик, а не лямбда, которая правит словарь на месте. Старые
# _build_magazine_panel, _build_attachment_panel и _connect_att_cb удалены
# вместе с этими правилами; ниже только две панели, которые им на смену.

# Имя группы обвесов. Словарь, а не Loc.txt(grp): subtype из данных приходит в
# игровом регистре и не совпадает ни с одним ключом локализации, так что
# проверка Loc.RU.has(grp) молча показывала бы английский текст.
const ATT_GROUP_LABELS := {
	"Magazine": "Magazines",
	"Muzzle": "Muzzle",
	"Sight": "Optics",
	"Optic": "Optics",
	"Scope": "Optics",
	"Grip": "Grips",
	"Underbarrel": "Underbarrel",
	"Stock": "Attachments",
	"Laser": "Lasers",
	"Light": "Flashlights",
	"Plate": "Armor plates",
	"Pouch": "Pouches",
	"Rig": "Chest rig",
	"Armor": "Armor",
}

func _att_group_label(grp: String) -> String:
	# Group_unknown показываем как есть: пустой заголовок хуже честного
	# английского слова, а данные из обновления игры мы заранее не знаем.
	return Loc.txt(str(ATT_GROUP_LABELS.get(grp, grp)))

# Группа обвеса по его пути. Черновик не грузит ресурсы, поэтому проверку
# группы делаем здесь, а в toggle_attachment() передаём её Callable'ом.
func _att_group_of(path: String) -> String:
	var res = Items.index_of(path)
	if res == null:
		res = load(path)
	if res == null:
		return "Other"
	var sub = res.get("subtype")
	if sub == null or str(sub) == "":
		return "Other"
	return str(sub)

# Совместимые обвесы предмета, разложенные по группам. На вход - descriptor
# из черновика, на выход - элементы Picker.group_attachments(): путь, имя,
# группа. compatible берётся из уже загруженного ресурса.
func _att_entries(desc: Dictionary) -> Array:
	var info = _ui._item_info(str(desc.get("path", "")))
	var compat = info.get("compatible")
	if typeof(compat) != TYPE_ARRAY:
		return []
	var saved = desc.get("attachments")
	var ats: Array = saved if typeof(saved) == TYPE_ARRAY else []
	var out: Array = []
	for cd in compat:
		if cd == null:
			continue
		var cd_path := str(cd.resource_path) if cd is Resource else ""
		if cd_path == "":
			continue
		var sub = "Other"
		if cd.get("subtype") != null and str(cd.get("subtype")) != "":
			sub = str(cd.get("subtype"))
		out.append({"path": cd_path, "name": str(cd.get("name", "?")), "subtype": sub})
	# Выбранные обвесы здесь не помечаются: плитка спрашивает Draft сама,
	# has_attachment'ом по своему пути. Помечать флагом значило бы держать
	# второе место, где живёт состояние выбора.
	return Picker.group_attachments(out)

# Панель одного предмета. Возвращает null, если панели нет: кнопка RND тогда
# не показывается вовсе, и незачем создавать пустой блок.
func _build_att_panel(path: String) -> Control:
	if _ui._session.draft == null:
		return null
	var desc: Dictionary = _ui._session.draft.descriptor_of(path)
	if desc.is_empty():
		return null
	if _is_magazine(path):
		return _build_mag_panel(path, desc)
	if not _att_panel_needed(_ui._item_info(path)):
		return null

	var groups := _att_entries(desc)
	if groups.is_empty():
		return null
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", VTKSurface.panel(true, 10))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)

	# Имя предмета первой строкой: заголовок «Attachments» рисует шапка
	# оверлея, а чьи это обвесы - вопрос отдельный.
	var owner_lbl := Label.new()
	owner_lbl.text = str(desc.get("name", "?"))
	owner_lbl.add_theme_font_size_override("font_size", 11)
	owner_lbl.add_theme_color_override("font_color", _ui._gold)
	owner_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(owner_lbl)

	for g in groups:
		var grp := str(g.get("grp", "Other"))
		var sect := Label.new()
		sect.text = _att_group_label(grp)
		sect.add_theme_font_size_override("font_size", 9)
		sect.add_theme_color_override("font_color", Color("#6a5a4a"))
		sect.add_theme_constant_override("margin_left", 4)
		vb.add_child(sect)
		# Плитки переносятся сами, а обвесов у ствола бывает под двадцать,
		# поэтому ряд не задаётся числом.
		var flow := HFlowContainer.new()
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 2)
		flow.add_theme_constant_override("margin_left", 8)
		for a in g.get("items", []):
			flow.add_child(_make_att_cell(path, grp, Items.attachment_resource(a)))
		vb.add_child(flow)
	return panel

# Обвес как плитка, тем же кодом, что и предмет в каталоге. Раньше был чип, и
# состояние "выбран" не читалось: Godot рисует hover и pressed из темы, они
# перебивали normal, поэтому после клика не оставалось ничего. У плитки все
# четыре стиля заданы явно.
func _make_att_cell(owner_path: String, grp: String, att_res) -> Control:
	if att_res == null:
		return Control.new()
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(96, 132)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP

	# Принадлежность, а не "первый в списке": дуло, коллиматор и лазер стоят
	# одновременно, и золотым должен быть каждый из них.
	var on: bool = _ui._session.draft != null and _ui._session.draft.has_attachment(owner_path, str(att_res.resource_path))

	var normal := VTKSurface.surface("normal")
	var hover := VTKSurface.surface("hover")
	var picked := VTKSurface.surface("normal", true, false, false)

	cell.add_theme_stylebox_override("panel", picked if on else normal)
	_ui._attach_motion(cell)

	_icon_stack(cell, _ui._item_icon(att_res), Vector2(84, 48),
		str(att_res.name), 9, _ui._gold if on else Color("#aaa"), 2)

	cell.tooltip_text = str(att_res.name) + "\n" + str(att_res.resource_path)
	cell.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if _ui._session.draft == null:
				return
			_ui._session.draft.toggle_attachment(owner_path, str(att_res.resource_path), grp, _att_group_of)
			# Панель остаётся открытой: подбор обвесов идёт списком, и закрывать
			# её после каждого клика значило бы кликать дважды на каждый обвес.
			_ui.refresh(R_PAGES)
	)
	cell.mouse_entered.connect(func():
		if not on:
			cell.add_theme_stylebox_override("panel", hover))
	cell.mouse_exited.connect(func():
		cell.add_theme_stylebox_override("panel", picked if on else normal))
	return cell

# У обоймы единственный "обвес" - совместимый патрон, и он уезжает в
# slotData.nested, который игра не читает. Число патронов задаёт сам amount
# обоймы, поэтому вместо списка обвесов показываем тумблер заполнения.
func _build_mag_panel(path: String, desc: Dictionary) -> Control:
	var info = _ui._item_info(path)
	var cap := int(round(float(info.get("maxAmount") if info.get("maxAmount") != null else 0.0)))
	var on := Draft.is_full(desc)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", VTKSurface.panel(true, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_theme_constant_override("margin_left", 8)
	panel.add_child(row)

	var b := ToggleSwitch.new()
	b.button_pressed = on
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.toggled.connect(func(is_on: bool):
		if _ui._session.draft == null:
			return
		_ui._session.draft.set_full_mag(path, is_on)
		_ui.refresh(R_PAGES)
	)
	row.add_child(b)

	var cut_label := Label.new()
	cut_label.text = Loc.txt("Full magazine")
	cut_label.add_theme_font_size_override("font_size", 10)
	cut_label.add_theme_color_override("font_color", _ui._gold if on else Color("#bbb"))
	cut_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cut_label)

	var cap_lbl := Label.new()
	cap_lbl.text = Loc.txt("[rounds]") + " " + str(cap)
	cap_lbl.add_theme_font_size_override("font_size", 9)
	cap_lbl.add_theme_color_override("font_color", VTKSurface.GREY_DIM)
	row.add_child(cap_lbl)
	return panel
