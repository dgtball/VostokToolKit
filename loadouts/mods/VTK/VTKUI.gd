extends CanvasLayer
const Loc = preload("res://mods/VTK/VTKLoc.gd")
const Draft = preload("res://mods/VTK/VTKDraft.gd")
const Picker = preload("res://mods/VTK/VTKPicker.gd")
const VTKSurface := preload("res://mods/VTK/VTKSurface.gd")

const UI_LAYER := 4095

var _db_items: Array = []
# resource_path -> Resource. Строки сетов хранят пути, а панели обвесов нужен
# сам Resource: без индекса каждая клетка искала бы его перебором всего
# списка, а раньше просто грузила с диска.
var _item_index: Dictionary = {}
# resource_path -> иконка либо null. Кеш нужен и для промахов: без него
# отсутствующий PNG искался бы заново в каждой клетке.
var _icon_cache: Dictionary = {}
var _panel: Panel = null
var _scroll: ScrollContainer = null
var _main_vbox: VBoxContainer = null

# loadouts tab
var _list_container: VBoxContainer = null
var _cards_grid: GridContainer = null
var _editor_panel: VBoxContainer = null
var _editing_name: String = ""
var _draft: Draft = null
var _name_input: LineEdit = null
# Полосы категорий строятся как VBox из заголовка и HFlow с клетками: у
# GridContainer нет растягивания на всю ширину, а полоса во всю ширину
# нужна, чтобы порядок групп читался сверху вниз.
var _shelves_box: VBoxContainer = null
var _side_slots_box: VBoxContainer = null
var _target_bar: VBoxContainer = null
var _equip_box: HBoxContainer = null
var _gear_box: HBoxContainer = null
# Открытая панель обвесов своя у каждой страницы: экран, открытый в
# Экипировке, не должен появляться в Снаряжении.
var _open_equip_att: String = ""
var _open_gear_att: String = ""
# Предмет, который только что положили в набор: его обвесы открываются сами.
var _last_placed: String = ""
# Трёхшаговый выбор предмета. Страницы строятся один раз, переключение - visible,
# поэтому _page_* и _step_btns переживают обновление содержимого.
var _page: int = 0
var _target_slot: String = ""
# Фильтры каталога шага 1: категория и её подкатегория. Для экипировки
# смотреть все предметы не нужно, поэтому отдельного пункта "Все предметы"
# здесь нет - сбрасывает строку фильтров чип "Сброс".
var _target_cat: String = ""
var _target_sub: String = ""
var _search_text: String = ""
var _gear_search: String = ""
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
var _gear_chips: VBoxContainer = null
var _gear_facet_key: String = ""
# Второй уровень фасетов шага 2: подкатегория внутри выбранной категории.
var _gear_sub_key: String = ""
# Повторный клик по активной категории сворачивает её подкатегории;
# категория при этом остаётся выбранным фильтром.
var _gear_subs_collapsed: bool = false
var _gear_facets_box: VBoxContainer = null
var _gear_grid: GridContainer = null
var _gear_grid_scroll: ScrollContainer = null
var _equip_att_box: VBoxContainer = null
var _gear_att_box: VBoxContainer = null
var _done_summary: HBoxContainer = null
var _done_equip_col: VBoxContainer = null
var _done_gear_col: VBoxContainer = null

# tabs
var _tab_btns: Array = []
var _tab_containers: Dictionary = {}
var _ui_nodes: Array = []
var _lang_btns: Array = []
var _current_tab: String = ""

# teleport tab
var _travel: Node = null
var _tp_section_btns: Array = []
var _tp_maps_box: VBoxContainer = null
var _tp_shelters_box: VBoxContainer = null
var _tp_traders_box: VBoxContainer = null
var _tp_head: Label = null
var _tp_count: Label = null
var _current_tp_section: String = "maps"

func _tp_section_label(section: String) -> String:
	match section:
		"maps":
			return Loc.txt("Maps")
		"shelters":
			return Loc.txt("Shelters")
		"traders":
			return Loc.txt("Traders")
	return ""

var game_data: Resource = null

# ui
var _gold: Color = Color("#d48a3a")

var _key_ui_toggle: int = 0
var _panel_open: bool = false
var _saved_mouse_mode: int = Input.MOUSE_MODE_CAPTURED
var _self_paused: bool = false
var _scene_ref: Node = null

func _process(_delta: float) -> void:
	var scene = get_tree().current_scene
	if scene != _scene_ref:
		_scene_ref = scene
		if _panel_open:
			_set_panel_open(false)
		return
	if visible and not get_tree().paused:
		_self_paused = true
		get_tree().paused = true
	elif not visible and get_tree().paused and _self_paused:
		_self_paused = false
		get_tree().paused = false

var _late_initialized: bool = false

func _ready() -> void:
	name = "VTKUI"
	layer = UI_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_process_input(true)
	call_deferred("_init_later")

func _migrate_mcm_dir() -> void:
	var old_dir := OS.get_user_data_dir() + "/MCM/loadouts"
	var new_dir := OS.get_user_data_dir() + "/MCM/vostok-toolkit"
	if not DirAccess.dir_exists_absolute(old_dir):
		return
	if DirAccess.dir_exists_absolute(new_dir):
		return
	var err = DirAccess.make_dir_recursive_absolute(new_dir)
	if err != OK:
		print("[VTK] MCM migration failed: could not create destination (code " + str(err) + ")")
		return
	var src := DirAccess.open(old_dir)
	if src == null:
		print("[VTK] MCM migration failed: could not open source dir")
		return
	var list_err = src.list_dir_begin()
	if list_err != OK:
		print("[VTK] MCM migration failed: could not list source dir (code " + str(list_err) + ")")
		return
	var fname := src.get_next()
	var copied := 0
	var failed := 0
	while fname != "":
		if not src.current_is_dir() and not fname.begins_with("."):
			var c_err = src.copy_absolute(old_dir + "/" + fname, new_dir + "/" + fname)
			if c_err != OK:
				failed += 1
				print("[VTK] MCM migration: failed to copy " + fname + " (code " + str(c_err) + ")")
			else:
				copied += 1
		fname = src.get_next()
	src.list_dir_end()
	if failed > 0:
		print("[VTK] MCM migration failed: " + str(failed) + " file(s) not copied")
		return
	var r_err = DirAccess.remove_absolute(old_dir)
	if r_err != OK:
		print("[VTK] MCM migration: copied " + str(copied) + " file(s), but failed to remove old dir (code " + str(r_err) + ")")
		return
	print("[VTK] MCM dir migrated: loadouts -> vostok-toolkit (" + str(copied) + " file(s))")

func _init_later() -> void:
	if _late_initialized:
		return
	_late_initialized = true
	_migrate_mcm_dir()
	# Обе миграции - до _load_items, _restore_toggles и _register_mcm: обеим
	# нужен готовый каталог MCM/vostok-toolkit.
	var LD = preload("res://mods/VTK/VTKData.gd")
	LD.migrate_save_file()
	game_data = load("res://Resources/GameData.tres")
	print("[VTK] Starting UI init")
	_load_items()
	_load_lang()
	_build_ui()
	_restore_toggles()
	var Hooks = preload("res://mods/VTK/VTKHooks.gd")
	_hooks = Hooks.new()
	add_child(_hooks)
	_register_mcm()
	print("[VTK] UI init done")

func _get_iface():
	var root = get_tree().root
	return root.get_node_or_null("Map/Core/UI/Interface")

func _is_toggle_event(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	if InputMap.has_action("key_ui_toggle") and event.is_action_pressed("key_ui_toggle"):
		return true
	if _key_ui_toggle == 0:
		return false
	return event.keycode == _key_ui_toggle or event.physical_keycode == _key_ui_toggle

func _set_panel_open(open: bool) -> void:
	_panel_open = open
	visible = open
	if open:
		_saved_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_self_paused = true
		get_tree().paused = true
		_refresh_all()
	else:
		get_tree().paused = false
		_self_paused = false
		Input.mouse_mode = _saved_mouse_mode

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _is_toggle_event(event):
			if get_tree().current_scene == null:
				return
			_set_panel_open(not visible)
			return
		if get_viewport().gui_get_focus_control() is LineEdit:
			return
		if event.keycode == KEY_7 or event.keycode == KEY_8 or event.keycode == KEY_9:
			var LD = preload("res://mods/VTK/VTKData.gd")
			var qname = LD.get_name_by_quick_key(event.keycode)
			if qname != "":
				LD.load_loadout(qname)

func _load_items() -> void:
	_db_items.clear()
	_item_index.clear()
	var db = get_node_or_null("/root/Database")
	if not db:
		return
	if not db.master:
		return
	for item in db.master.items:
		if item and item.name != "":
			_db_items.append(item)
			_item_index[item.resource_path] = item

# ============== BUILD UI ==============

# Микро-анимация из макета: scale 1.008 на ховере, 0.986 на нажатии, .14s
# cubic. Вешается на интерактивные элементы централизованно.
func _attach_motion(c: Control) -> void:
	if not is_instance_valid(c):
		return
	c.set_meta("vtk_hover", false)
	c.mouse_entered.connect(func():
		c.set_meta("vtk_hover", true)
		c.pivot_offset = c.size * 0.5
		_tween_scale(c, 1.008))
	c.mouse_exited.connect(func():
		c.set_meta("vtk_hover", false)
		_tween_scale(c, 1.0))
	if c is BaseButton:
		c.button_down.connect(func(): _tween_scale(c, 0.986))
		c.button_up.connect(func():
			var hv: bool = c.get_meta("vtk_hover")
			_tween_scale(c, 1.008 if hv else 1.0))

func _tween_scale(c: Control, target: float) -> void:
	if c.has_meta("vtk_tween"):
		var old: Tween = c.get_meta("vtk_tween")
		if old != null:
			old.kill()
	var tw := create_tween()
	tw.tween_property(c, "scale", Vector2(target, target), 0.14) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	c.set_meta("vtk_tween", tw)

func _make_tab_style() -> StyleBox:
	return VTKSurface.surface("normal", false, false, false, 14, 14, 6, 6)

func _make_tab_active_style() -> StyleBox:
	return VTKSurface.surface("normal", true, false, true, 14, 14, 6, 6)

func _make_chip_style(active: bool, hover: bool = false) -> StyleBox:
	return VTKSurface.surface("hover" if hover else "normal", active, false, false, 8, 12, 7, 7)

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_ui_nodes.append(bg)

	_panel = Panel.new()
	_panel.size = Vector2(800, 880)
	_panel.position = Vector2(60, 25)
	var panel_style := VTKSurface.panel(false, 0)
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	panel_style.shadow_size = 12
	panel_style.shadow_offset = Vector2(0, 6)
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)
	_ui_nodes.append(_panel)

	var ui_theme := Theme.new()
	ui_theme.set_stylebox("scroll", "VScrollBar", VTKSurface.panel(true, 4))
	ui_theme.set_stylebox("grabber", "VScrollBar", VTKSurface.surface("normal", true, false, false, 2, 2, 2, 2))
	ui_theme.set_stylebox("grabber_highlight", "VScrollBar", VTKSurface.surface("hover", true, false, false, 2, 2, 2, 2))
	ui_theme.set_stylebox("grabber_pressed", "VScrollBar", VTKSurface.surface("pressed", true, false, false, 2, 2, 2, 2))
	ui_theme.set_stylebox("panel", "TooltipPanel", VTKSurface.panel(false, 12))
	ui_theme.set_font_size("font_size", "TooltipLabel", 10)
	_panel.theme = ui_theme

	# КПК-хром: верхний рейл устройства. Только имя и версия: бренд-квадрат,
	# текущая вкладка и часы из макета убраны.
	var rail := HBoxContainer.new()
	rail.position = Vector2(4, 4)
	rail.size = Vector2(792, 30)
	rail.add_theme_constant_override("separation", 8)
	_panel.add_child(rail)
	_ui_nodes.append(rail)

	var name_box := VBoxContainer.new()
	name_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_box.add_theme_constant_override("separation", 0)
	rail.add_child(name_box)
	var rname := Label.new()
	rname.text = "VOSTOK TOOLKIT"
	rname.add_theme_font_size_override("font_size", 11)
	name_box.add_child(rname)
	var rver := Label.new()
	rver.text = "v" + _mod_version()
	rver.add_theme_font_size_override("font_size", 8)
	rver.add_theme_color_override("font_color", Color("#5f5347"))
	name_box.add_child(rver)

	var tab_bar = HBoxContainer.new()
	tab_bar.position = Vector2(4, 38)
	_panel.add_child(tab_bar)

	var tabs = [Loc.txt("Sets"), Loc.txt("Settings"), Loc.txt("Teleport")]
	for tname in tabs:
		var btn = Button.new()
		btn.text = tname
		btn.custom_minimum_size = Vector2(130, 30)
		btn.add_theme_font_size_override("font_size", 12)
		var tn = tname
		btn.pressed.connect(func(): _switch_tab(tn))
		_attach_motion(btn)
		tab_bar.add_child(btn)
		_tab_btns.append(btn)

	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(4, 72)
	_scroll.size = Vector2(792, 800)
	_panel.add_child(_scroll)

	_main_vbox = VBoxContainer.new()
	_main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_vbox.add_theme_constant_override("separation", 6)
	_scroll.add_child(_main_vbox)

	for tname in tabs:
		var vb = VBoxContainer.new()
		vb.name = tname
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vb.hide()
		_main_vbox.add_child(vb)
		_tab_containers[tname] = vb

	_build_loadouts_tab(_tab_containers[Loc.txt("Sets")])
	_build_settings_tab(_tab_containers[Loc.txt("Settings")])
	_build_teleport_tab(_tab_containers[Loc.txt("Teleport")])

	_switch_tab(Loc.txt("Sets"))



func _switch_tab(name: String) -> void:
	if _current_tab != "" and _tab_containers.has(_current_tab):
		_tab_containers[_current_tab].hide()
	_current_tab = name
	if name == Loc.txt("Teleport"):
		_refresh_teleport_tab()
	if _tab_containers.has(name):
		_tab_containers[name].show()
	for i in range(_tab_btns.size()):
		var btn = _tab_btns[i] as Button
		var is_active = btn.text == name
		if is_active:
			btn.add_theme_color_override("font_color", _gold)
			btn.add_theme_stylebox_override("normal", _make_tab_active_style())
		else:
			btn.add_theme_color_override("font_color", Color("#888"))
			btn.add_theme_stylebox_override("normal", _make_tab_style())

func _refresh_all() -> void:
	_refresh_loadout_list()
	_refresh_draft_ui()

# ============== TAB: РЎРµС‚С‹ ==============

func _build_loadouts_tab(parent: VBoxContainer) -> void:
	var list_title = Label.new()
	list_title.text = Loc.txt("Saved loadouts")
	list_title.add_theme_font_size_override("font_size", 13)
	list_title.add_theme_color_override("font_color", Color("#ddd"))
	parent.add_child(list_title)

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_list_container)

	_cards_grid = GridContainer.new()
	_cards_grid.columns = 3
	_cards_grid.add_theme_constant_override("h_separation", 6)
	_cards_grid.add_theme_constant_override("v_separation", 6)
	_cards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_child(_cards_grid)

	parent.add_child(HSeparator.new())

	_editor_panel = VBoxContainer.new()
	_editor_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_editor_panel)

	_build_editor()

func _build_editor() -> void:
	for child in _editor_panel.get_children():
		_editor_panel.remove_child(child)
		child.queue_free()
	_step_btns = []
	_name_input = null
	_done_summary = null
	_done_equip_col = null
	_done_gear_col = null
	_gear_search_field = null
	_gear_chips = null
	_gear_facets_box = null
	_gear_grid = null
	_gear_facet_key = ""
	_gear_grid_scroll = null
	_shelves_box = null
	_side_slots_box = null
	_target_bar = null
	_equip_att_box = null
	_gear_att_box = null
	_equip_box = null
	_gear_box = null
	_page_label = null

	var ed_title = Label.new()
	if _draft != null and _draft.set_name != "":
		ed_title.text = Loc.txt("Editing: ") + _draft.set_name
	else:
		ed_title.text = Loc.txt("Create new loadout")
	ed_title.add_theme_font_size_override("font_size", 12)
	ed_title.add_theme_color_override("font_color", _gold)
	_editor_panel.add_child(ed_title)

	_editor_panel.add_child(_build_stepper())

	_page_equip = _build_page_equipment()
	_page_gear = _build_page_gear()
	_page_done = _build_page_done()
	_editor_panel.add_child(_page_equip)
	_editor_panel.add_child(_page_gear)
	_editor_panel.add_child(_page_done)

	_reset_picker_state()
	_show_page(0)
	_refresh_pages()
	_editor_panel.visible = _draft != null

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
		card.add_theme_stylebox_override("panel", _make_step_row_style(_page == idx))
		card.gui_input.connect(func(ev):
			var mb := ev as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_show_page(idx)
		)
		_attach_row_hover(card, func(hv: bool):
			return _make_step_row_style(_page == idx, hv))
		_attach_motion(card)

		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hb)

		var circle := _make_step_circle(idx + 1, _page == idx)
		_step_circles.append(circle)
		hb.add_child(circle)
		var num := circle.get_child(0) as Label
		_step_numbers.append(num)

		var lab := Label.new()
		lab.text = titles[i]
		lab.add_theme_font_size_override("font_size", 11)
		lab.add_theme_color_override("font_color", _gold if _page == idx else Color("#888888"))
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_step_labels.append(lab)
		hb.add_child(lab)

		var chk := Label.new()
		chk.text = "\u2713"
		chk.add_theme_font_size_override("font_size", 10)
		chk.add_theme_color_override("font_color", _gold)
		chk.visible = idx < _page
		chk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_step_checks.append(chk)
		hb.add_child(chk)

		_step_btns.append(card)
		row.add_child(card)
	_page_label = Label.new()
	_page_label.add_theme_font_size_override("font_size", 10)
	_page_label.add_theme_color_override("font_color", _gold)
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
	s.bg_color = _gold if active else Color("#1f1913")
	s.border_color = _gold if active else Color("#3a2e20")
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
	num.add_theme_color_override("font_color", Color("#1a1206") if active else Color("#8a7a6a"))
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(num)
	return c

# Общий ховер строк со StyleBoxFlat: макит стиль по hover-флагу, активная
# строка ховер не перебивает. Строки пересобираются часто, обработчики
# умирают вместе со строкой, поэтому новые каждый раз безопасны.
func _attach_row_hover(row: Control, make_style: Callable) -> void:
	row.mouse_entered.connect(func():
		row.add_theme_stylebox_override("panel", make_style.call(true)))
	row.mouse_exited.connect(func():
		row.add_theme_stylebox_override("panel", make_style.call(false)))

func _show_page(n: int) -> void:
	_page = clampi(n, 0, 2)
	if _page_equip != null:
		_page_equip.visible = _page == 0
	if _page_gear != null:
		_page_gear.visible = _page == 1
	if _page_done != null:
		_page_done.visible = _page == 2
	for i in range(_step_btns.size()):
		var on := i == _page
		var card := _step_btns[i] as PanelContainer
		if card != null:
			card.add_theme_stylebox_override("panel", _make_step_row_style(on))
		if i < _step_labels.size():
			var lab := _step_labels[i] as Label
			if lab != null:
				lab.add_theme_color_override("font_color", _gold if on else Color("#888888"))
		if i < _step_circles.size():
			var circle := _step_circles[i] as Panel
			if circle != null:
				circle.add_theme_stylebox_override("panel", _make_step_circle_style(on))
		if i < _step_numbers.size():
			var num := _step_numbers[i] as Label
			if num != null:
				num.add_theme_color_override("font_color", Color("#1a1206") if on else Color("#8a7a6a"))
		if i < _step_checks.size():
			var chk := _step_checks[i] as Label
			if chk != null:
				chk.visible = i < _page

func _set_problem(msg: String) -> void:
	if _page_label != null:
		_page_label.text = msg

func _clear_problem() -> void:
	if _page_label != null:
		_page_label.text = ""

# Цель и поиск живут между пересборками редактора. Без сброса новый сет
# начинался бы с чужим слотом в цели и невидимым запросом в поле поиска.
func _reset_picker_state() -> void:
	_target_slot = ""
	_search_text = ""
	_gear_search = ""
	_gear_facet_key = ""
	_gear_sub_key = ""
	_gear_subs_collapsed = false
	_open_equip_att = ""
	_open_gear_att = ""
	_last_placed = ""

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

# Ширина левой колонки. В макете 216, но в игре в строке слота ещё живут
# снятие предмета и тумблер заполнения обоймы, и 216 впритык.
const SIDE_WIDTH := 232

# Сколько клеток влезает в ширину. Константа "_gear_grid.columns = 4" давала
# четыре колонки в любом окне, а HFlowContainer на шаге 1 упирался в
# собственную ширину и показывал пять клеток вместо всей области.
func _make_grid_columns(width: float) -> int:
	if width <= 0.0:
		return 1
	var cell := 96.0
	var sep := 5.0
	return maxi(1, int(floor((width + sep) / (cell + sep))))


# Каркас страницы: слева колонка выбора, справа предметы. Ширина колонки
# задаётся здесь единожды, иначе шаги разъедутся на пиксель и перестанут
# выглядеть одной сеткой.
func _page_columns(title: String, side: Control, main: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 6)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	var ps := VTKSurface.panel(true, 6)
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
	lbl.add_theme_color_override("font_color", Color("#5f5347"))
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
	var search := LineEdit.new()
	search.placeholder_text = Loc.txt("Search items...")
	search.add_theme_color_override("font_color", Color("#ffffff"))
	search.add_theme_color_override("placeholder_color", Color("#666666"))
	search.add_theme_stylebox_override("normal", VTKSurface.panel(true, 10))
	search.add_theme_stylebox_override("focus", VTKSurface.focus_style())
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(t): _set_search(t))
	v.add_child(search)

	var shelves_scroll := ScrollContainer.new()
	shelves_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shelves_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Пол, а не высота: EXPAND растягивает область на всё свободное место окна,
	# а минимум гарантирует, что полки останутся видимыми даже там, где внешний
	# контейнер игры отдаёт ровно минимальную высоту.
	shelves_scroll.custom_minimum_size = Vector2(0, 240)
	_shelves_box = VBoxContainer.new()
	_shelves_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shelves_box.add_theme_constant_override("separation", 6)
	shelves_scroll.add_child(_shelves_box)
	v.add_child(shelves_scroll)

	_equip_att_box = VBoxContainer.new()
	_equip_att_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_equip_att_box)

	_side_slots_box = VBoxContainer.new()
	_side_slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_slots_box.add_theme_constant_override("separation", 3)

	_equip_box = _page_columns(Loc.txt("Slots"), _side_slots_box, v)
	return _equip_box

func _build_page_gear() -> Control:
	var main := _page_wrap()

	# Чипы снаряжения идут первыми: это выбранное, его и правят. Поиск ниже
	# относится к каталогу, а не к этим чипам.
	_gear_chips = VBoxContainer.new()
	_gear_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gear_chips.add_theme_constant_override("separation", 2)
	main.add_child(_gear_chips)

	# Отдельное поле поиска: запрос шага 1 относится к выбору предмета в слот
	# и не должен молча фильтровать снаряжение, и наоборот.
	var search := LineEdit.new()
	search.placeholder_text = Loc.txt("Search items...")
	search.add_theme_color_override("font_color", Color("#ffffff"))
	search.add_theme_color_override("placeholder_color", Color("#666666"))
	search.add_theme_stylebox_override("normal", VTKSurface.panel(true, 10))
	search.add_theme_stylebox_override("focus", VTKSurface.focus_style())
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(t): _set_gear_search(t))
	_gear_search_field = search
	main.add_child(search)

	# Каталог всегда открыт: он и раньше был длиннее окна, поэтому кнопка
	# раскрытия только добавляла лишний клик к выбору предмета.
	_gear_grid_scroll = ScrollContainer.new()
	_gear_grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gear_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_gear_grid = GridContainer.new()
	# Колонки считаются от ширины, а не задаются константой. Пересчёт вешается
	# на resized: на первом показе ширина ещё нулевая, и без обработчика
	# получилась бы одна колонка.
	_gear_grid.columns = _make_grid_columns(_gear_grid_scroll.size.x)
	_gear_grid_scroll.resized.connect(func():
		if _gear_grid != null:
			_gear_grid.columns = _make_grid_columns(_gear_grid_scroll.size.x)
	)
	_gear_grid.add_theme_constant_override("h_separation", 5)
	_gear_grid.add_theme_constant_override("v_separation", 5)
	_gear_grid_scroll.add_child(_gear_grid)
	main.add_child(_gear_grid_scroll)

	_gear_att_box = VBoxContainer.new()
	_gear_att_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(_gear_att_box)

	_gear_facets_box = VBoxContainer.new()
	_gear_facets_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gear_facets_box.add_theme_constant_override("separation", 3)

	_gear_box = _page_columns(Loc.txt("Categories"), _gear_facets_box, main)
	return _gear_box

func _refresh_page_gear() -> void:
	_rebuild_gear_chips()
	_refresh_gear_catalog()
	_rebuild_att_box(_gear_att_box, _open_gear_att)

func _rebuild_gear_chips() -> void:
	if _gear_chips == null:
		return
	for child in _gear_chips.get_children():
		_gear_chips.remove_child(child)
		child.queue_free()
	# Панель обвесов больше не едет чипом: она живёт в _gear_att_box под
	# каталогом. Здесь только сами чипы, поэтому клик по обвесу на второй
	# странице открывает панель на текущем чипе, а не на последнем в списке.
	if _draft == null:
		return
	if _draft.gear.is_empty():
		var note := Label.new()
		note.text = Loc.txt("No gear")
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", Color("#666666"))
		_gear_chips.add_child(note)
		return
	for desc in _draft.gear:
		_gear_chips.add_child(_make_gear_chip(desc))

# Чип снаряжения: имя, счётчик, обвесы, удаление. У обоймы счётчик живёт в
# count, поэтому берём shown_count, а не amount: у обоймы amount = 0 по
# определению и показывать его - значит показать ноль вместо выбранного.
func _make_gear_chip(desc: Dictionary) -> Control:
	var path_now := str(desc.get("path", ""))
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", VTKSurface.surface("normal", false, false, false, 8, 8, 4, 4))
	_attach_motion(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	card.add_child(row)

	row.add_child(_make_dot(_gold))

	var nm := Label.new()
	nm.text = str(desc.get("name", "?"))
	nm.add_theme_font_size_override("font_size", 12)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.tooltip_text = path_now
	row.add_child(nm)

	var minus := _make_step_btn("-")
	minus.pressed.connect(func(): _bump_gear(path_now, -1.0))
	row.add_child(minus)

	var cnt := Label.new()
	cnt.text = str(Draft.shown_count(desc))
	cnt.add_theme_font_size_override("font_size", 11)
	cnt.custom_minimum_size = Vector2(22, 0)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(cnt)

	var plus := _make_step_btn("+")
	plus.pressed.connect(func(): _bump_gear(path_now, 1.0))
	row.add_child(plus)

	# Панель обвесов есть не у всего. У обоймы вместо неё тумблер заполнения,
	# и решение принимается по предмету, а не по наличию панели: у обоймы
	# есть и обвесы, и maxAmount, то есть has_panel() тут врёт.
	if _is_magazine(path_now):
		row.add_child(_make_full_mag_btn(path_now, desc))
	elif Picker.has_panel(_item_info(path_now)):
		row.add_child(_make_att_btn(desc))

	var drop := _make_step_btn("x")
	drop.tooltip_text = Loc.txt("Remove")
	drop.pressed.connect(func(): _remove_gear(path_now))
	row.add_child(drop)
	return card

# У обоймы единственный "обвес" - совместимый патрон, и он уезжает в
# slotData.nested, который игра не читает. Число патронов задаёт сам amount,
# поэтому блок обвесов обойме не нужен.
func _is_magazine(path: String) -> bool:
	var info := _item_info(path)
	return str(info.get("type")) == "Attachment" and str(info.get("subtype")) == "Magazine"

func _make_step_btn(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(24, 24)
	b.add_theme_font_size_override("font_size", 10)
	VTKSurface.style_button(b, false, false, 2, 2, 4, 4)
	return b

func _remove_gear(path: String) -> void:
	if _draft == null:
		return
	if _open_gear_att == path:
		_open_equip_att = ""
		_open_gear_att = ""
	_draft.remove_gear(path)
	_refresh_pages()

func _make_full_mag_btn(path: String, desc: Dictionary) -> Button:
	var on := Draft.is_full(desc)
	var b := Button.new()
	b.text = Loc.txt("Full magazine") if on else Loc.txt("Empty")
	b.add_theme_font_size_override("font_size", 9)
	b.add_theme_color_override("font_color", _gold if on else Color("#777777"))
	VTKSurface.style_button(b, on, false, 8, 8, 4, 4)
	b.pressed.connect(func():
		if _draft == null:
			return
		# Состояние берём с актуального descriptor'а, а не с захваченного
		# desc: после пересборки чипов он уже может быть не тем объектом.
		_draft.set_full_mag(path, not Draft.is_full(_draft.descriptor_of(path)))
		_refresh_pages()
	)
	return b

func _set_gear_search(t: String) -> void:
	_gear_search = t
	# Только каталог: пересборка страницы пересоздала бы поле поиска и выкинула
	# бы из него курсор на каждом символе.
	_refresh_gear_catalog()

# Фасеты и сетка считаются одним проходом по списку предметов: facets_of
# фильтрует и группирует его целиком, а считать дважды - значит фильтровать
# дважды.
func _refresh_gear_catalog() -> void:
	var facets: Array = []
	if _draft != null:
		facets = Picker.facets_of(_items_for_gear(), _gear_search)
	_rebuild_gear_facets(facets)
	_rebuild_gear_grid(facets)

# Фасеты левой колонки: строки категорий со счётчиками. Цифра считается по
# текущему запросу, поэтому всегда равна тому, что окажется в сетке после клика.
func _rebuild_gear_facets(facets: Array) -> void:
	if _gear_facets_box == null:
		return
	for child in _gear_facets_box.get_children():
		_gear_facets_box.remove_child(child)
		child.queue_free()
	if _draft == null:
		return
	for f in facets:
		var key := str(f.get("key", ""))
		_gear_facets_box.add_child(_make_facet_row(f, false))
		# Подкатегории - второй уровень: они идут сразу под своей категорией и
		# отступом от неё отличаются. На строке "Все предметы" их нет: список
		# занял бы полколонки и означал бы третье измерение фильтра.
		if _gear_facet_key != "" and key == _gear_facet_key and not _gear_subs_collapsed:
			for s in _gear_subfacets(f.get("items", [])):
				_gear_facets_box.add_child(_make_facet_row(s, true))

# Клик по активной строке сворачивает/разворачивает её подкатегории;
# категория продолжает фильтровать. К возврату ко «Всем предметам» ведёт
# строка «Все предметы»
func _make_facet_row(facet: Dictionary, level: bool) -> Control:
	var key := str(facet.get("key", ""))
	var active := _gear_sub_key == key if level else _gear_facet_key == key
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 23 if level else 26)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_stylebox_override("panel", _make_slot_style(active))
	_attach_row_hover(row, func(hv: bool): return _make_slot_style(active, hv))
	_attach_motion(row)
	row.gui_input.connect(func(ev): _on_facet_input(ev, key, level))
	if level:
		row.add_theme_constant_override("margin_left", 10)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hb)
	hb.add_child(_make_dot(Color("#4a4038") if level else Color("#5f5347")))

	var nm := Label.new()
	if key == "":
		nm.text = Loc.txt("All items")
	else:
		nm.text = ("> " if level else "") + Loc.txt(key if level else Picker.category_label(key))
	nm.add_theme_font_size_override("font_size", 10 if level else 11)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.add_theme_color_override("font_color", _gold if active else Color("#d8cdbe"))
	hb.add_child(nm)

	var cnt := Label.new()
	cnt.text = str(int(facet.get("count", 0)))
	cnt.add_theme_font_size_override("font_size", 10 if level else 11)
	cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cnt.add_theme_color_override("font_color", Color("#8a7a6a"))
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
	_gear_sub_key = "" if _gear_sub_key == key else key
	_refresh_gear_catalog()

# Фасет меняет только набор клеток: предметы из набора не уходят, поэтому
# открытая панель обвесов остаётся уместной.
func _set_gear_facet(key: String) -> void:
	if key != "" and key == _gear_facet_key:
		# Повторный клик по активной категории сворачивает её подкатегории.
		_gear_subs_collapsed = not _gear_subs_collapsed
	else:
		_gear_facet_key = key
		# Смена категории сбрасывает подкатегорию: иначе после "Винтовки" ->
		# "Пистолеты" остался бы фильтр "Снайперки" из прошлой ветки.
		_gear_sub_key = ""
		_gear_subs_collapsed = false
	_refresh_gear_catalog()

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
	var found := _facet_items(facets, _gear_facet_key)
	if _gear_sub_key != "":
		var only: Array = []
		for e in found:
			if str(e.get("sub", "")) == _gear_sub_key:
				only.append(e)
		found = only
	if found.is_empty():
		var note := Label.new()
		note.text = Loc.txt("Nothing fits")
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", Color("#666666"))
		_gear_grid.add_child(note)
		return
	for entry in found:
		var res = entry.get("item")
		if res == null:
			continue
		_gear_grid.add_child(_make_item_cell(res, ""))

# Шаг 2 не фильтрует по слоту: слот-цель принадлежит шагу 1, и переносить её
# сюда значило бы всюду показывать предметы только одного слота. Запрос тоже не
# применяется здесь: facets_of считает его сам, иначе фильтр был бы применён
# дважды - на входе и в счётчиках фасетов.
func _items_for_gear() -> Array:
	var out: Array = []
	for it in _db_items:
		if it == null:
			continue
		out.append(_entry(it))
	return out

func _build_page_done() -> Control:
	var v := _page_wrap()

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	var name_lbl := Label.new()
	name_lbl.text = Loc.txt("Name:")
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_row.add_child(name_lbl)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = Loc.txt("Enter a name...")
	_name_input.add_theme_color_override("font_color", Color("#ffffff"))
	_name_input.add_theme_color_override("placeholder_color", Color("#666666"))
	_name_input.add_theme_stylebox_override("normal", VTKSurface.panel(true, 10))
	_name_input.add_theme_stylebox_override("focus", VTKSurface.focus_style())
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _draft != null:
		_name_input.text = _draft.set_name
	name_row.add_child(_name_input)
	v.add_child(name_row)

	# Две колонки, как в макете: в плоском списке не видно, где кончается один
	# раздел и начинается другой.
	_done_summary = HBoxContainer.new()
	_done_summary.add_theme_constant_override("separation", 8)
	_done_equip_col = VBoxContainer.new()
	_done_equip_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_done_equip_col.add_theme_constant_override("separation", 1)
	_done_gear_col = VBoxContainer.new()
	_done_gear_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_done_gear_col.add_theme_constant_override("separation", 1)
	_done_summary.add_child(_done_equip_col)
	_done_summary.add_child(_done_gear_col)
	v.add_child(_done_summary)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	var save_btn := Button.new()
	save_btn.text = Loc.txt("Save loadout")
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VTKSurface.style_button(save_btn, true)
	save_btn.pressed.connect(_save_loadout)
	actions.add_child(save_btn)
	var clear_btn := Button.new()
	clear_btn.text = Loc.txt("Clear")
	VTKSurface.style_button(clear_btn)
	clear_btn.pressed.connect(_clear_draft)
	actions.add_child(clear_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = Loc.txt("Cancel")
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VTKSurface.style_button(cancel_btn)
	cancel_btn.pressed.connect(_cancel_draft)
	actions.add_child(cancel_btn)
	v.add_child(actions)
	return v

# Сводка перед сохранением: что уйдёт в сет. Текстом, а не теми же блоками с
# кнопками - второй набор RND на тот же предмет открывал бы ту же панель
# обвесов дважды.
func _refresh_page_done() -> void:
	if _done_summary == null or _done_equip_col == null or _done_gear_col == null:
		return
	for col in [_done_equip_col, _done_gear_col]:
		for child in col.get_children():
			col.remove_child(child)
			child.queue_free()
	if _draft == null:
		return
	_done_equip_col.add_child(_summary_head(Loc.txt("Equipment")))
	_done_gear_col.add_child(_summary_head(Loc.txt("Gear")))
	if _draft.item_count() == 0:
		_done_equip_col.add_child(_summary_line(Loc.txt("Set is empty"), Color("#666666")))
		return
	# Слоты - из каталога, а не из сета: пустой слот в сводке не нужен, но
	# порядок должен совпадать с левой колонкой шага 1, иначе сверка глазами
	# по двум экранам не сойдётся.
	var lists: Array = []
	for k in _draft.equip.keys():
		lists.append([str(k)])
	var any_eq := false
	for slot in Picker.all_slots(lists):
		var desc = _draft.equip.get(str(slot), {})
		if typeof(desc) != TYPE_DICTIONARY or desc.is_empty():
			continue
		any_eq = true
		_done_equip_col.add_child(_summary_line(_equip_row_text(str(slot), desc)))
	for desc in _draft.gear:
		_done_gear_col.add_child(_summary_line("· " + str(desc.get("name", "?"))
			+ " x" + str(Draft.shown_count(desc)) + _gear_mag_tail(desc),
			Color("#a89a80")))
	if not any_eq:
		_done_equip_col.add_child(_summary_line(Loc.txt("Empty"), Color("#666666")))
	# Заголовок уже добавлен, поэтому пусто - это когда строк не больше одной.
	if _done_gear_col.get_child_count() <= 1:
		_done_gear_col.add_child(_summary_line(Loc.txt("Empty"), Color("#666666")))

# Строка экипировки в сводке: тег, имя, счётчик и названия надетых обвесов через
# плюс. Раньше здесь было только "rnd. N", и по такому хвосту нельзя было
# понять, какой обвес стоит - проверять набор приходилось, открывая панель.
func _equip_row_text(slot: String, desc: Dictionary) -> String:
	var line := Loc.txt(slot) + " · " + str(desc.get("name", "?"))
	var cnt := Draft.shown_count(desc)
	if cnt > 1:
		line += " x" + str(cnt)
	var names: Array = []
	var ats = desc.get("attachments")
	if typeof(ats) == TYPE_ARRAY:
		for ap in ats:
			var info := _item_info(str(ap))
			var n := str(info.get("name", ""))
			if n == "":
				n = str(ap).get_file()
			names.append(n)
	for n in names:
		line += "  + " + str(n)
	return line

# Хвост строки снаряжения: у обоймы - сколько патронов, у остальных пусто.
func _gear_mag_tail(desc: Dictionary) -> String:
	var path_now := str(desc.get("path", ""))
	if not _is_magazine(path_now):
		return ""
	if not Draft.is_full(desc):
		return "  " + Loc.txt("Empty")
	var raw = _item_info(path_now).get("maxAmount")
	var cap := int(round(float(raw if raw != null else 0.0)))
	return "  " + Loc.txt("[rounds]") + " " + str(cap)

func _summary_head(text: String) -> Label:
	var l := _summary_line(text, _gold)
	l.add_theme_font_size_override("font_size", 10)
	return l

func _summary_line(text: String, color: Color = Color("#cccccc")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", color)
	return l

# Пересборка содержимого, а не узлов: узлы страницы переживают обновление,
# иначе терялся бы фокус в поиске и позиция скролла.
func _refresh_pages() -> void:
	_refresh_page_equipment()
	_refresh_page_gear()
	_refresh_page_done()

func _refresh_page_equipment() -> void:
	_rebuild_target_bar()
	_refresh_slots()
	_rebuild_shelves()
	_rebuild_att_box(_equip_att_box, _open_equip_att)

func _refresh_slots() -> void:
	if _side_slots_box == null:
		return
	for child in _side_slots_box.get_children():
		_side_slots_box.remove_child(child)
		child.queue_free()
	if _draft == null:
		return
	# Порядок берём из Picker.all_slots, чтобы ряд был одинаковым от сета к
	# сету, а не в порядке ключей словаря. Слоты копим из всех предметов
	# каталога, а не из занятых в этом сете: иначе пустой слот был бы виден
	# только у того сета, где его уже что-то занимает.
	var lists: Array = []
	for it in _db_items:
		if it != null:
			lists.append(it.get("slots"))
	for slot in Picker.all_slots(lists):
		var s := str(slot)
		var desc = _draft.equip.get(s, {})
		if typeof(desc) != TYPE_DICTIONARY:
			desc = {}
		_side_slots_box.add_child(_make_slot_row(s, desc))

# Строка слота в левой колонке: тег, точка занятости, имя, метка обвесов и
# снятие предмета. Панель обвесов открывается кликом по строке цели и живёт в
# правой колонке, поэтому в строке нужен только маркер "у этого есть обвесы".
func _make_slot_row(slot: String, desc: Dictionary) -> Control:
	var occupied := not desc.is_empty()
	var active := _target_slot == slot
	var row: Control
	if occupied:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(0, 28)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.add_theme_stylebox_override("panel", _make_slot_style(active))
		_attach_row_hover(panel, func(hv: bool): return _make_slot_style(active, hv))
		_attach_motion(panel)
		panel.gui_input.connect(func(ev): _on_slot_row_input(ev, slot, desc))
		row = panel
	else:
		# Пустой слот - обычная приглушённая строка (пунктир в Godot удел
		# кастомного _draw, а он не переживает пересборку строки).
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(0, 28)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.add_theme_stylebox_override("panel", _make_slot_style(active, false, true))
		_attach_row_hover(box, func(hv: bool): return _make_slot_style(active, hv, true))
		_attach_motion(box)
		box.gui_input.connect(func(ev): _on_slot_row_input(ev, slot, desc))
		row = box

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hb)

	var tag := Label.new()
	tag.text = Loc.txt(slot)
	tag.add_theme_font_size_override("font_size", 9)
	tag.add_theme_color_override("font_color", Color("#8a7a6a"))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tag)

	# Точка отвечает на "есть предмет", а не на категорию. Иконок в слотах и
	# чипах нет: спрайты живут только в ячейках каталога и обвесов.
	hb.add_child(_make_dot(_gold if occupied else Color("#2a1f14")))

	var nm := Label.new()
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if occupied:
		var cnt := Draft.shown_count(desc)
		nm.text = str(desc.get("name", "?"))
		if cnt > 1:
			nm.text += " x" + str(cnt)
		nm.tooltip_text = str(desc.get("path", ""))
		nm.add_theme_color_override("font_color", Color("#d8cdbe"))
		if Picker.has_panel(_item_info(str(desc.get("path", "")))):
			var mark := Label.new()
			mark.text = "◆"
			mark.add_theme_font_size_override("font_size", 8)
			mark.add_theme_color_override("font_color", _gold)
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hb.add_child(mark)
	else:
		nm.text = Loc.txt("Empty")
		nm.add_theme_color_override("font_color", Color("#4d443a"))
	hb.add_child(nm)

	if occupied:
		var drop := _make_step_btn("x")
		drop.tooltip_text = Loc.txt("Remove")
		drop.pressed.connect(func(): _remove_slot(slot))
		hb.add_child(drop)
	return row

# Клик по строке слота: строка становится целью, а клик по текущей цели с
# предметом открывает панель обвесов. Иначе обвесы пришлось бы искать
# отдельной кнопкой, а в строке шириной 232 для неё нет места.
func _on_slot_row_input(ev: InputEvent, slot: String, desc: Dictionary) -> void:
	var mb := ev as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var path_now := str(desc.get("path", ""))
	if path_now != "" and _target_slot == slot:
		_toggle_attachment_panel(path_now)
		return
	_set_target_slot(slot)

func _make_slot_style(active: bool, hover: bool = false, empty: bool = false) -> StyleBox:
	if empty:
		return VTKSurface.surface("hover" if hover else "disabled", active, false, active, 4, 4, 2, 2)
	return VTKSurface.surface("hover" if hover else "normal", active, false, active, 4, 4, 2, 2)

# Точка-индикатор 7x7. Отдельный узел, а не символ в тексте: цвет задаётся
# стилем и не зависит от шрифта игры.
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
	const GOLD := Color("#d48a3a")
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

	# button_pressed для совместимости с прежними CheckButton в _restore_toggles.
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
			ts.border_color = Color("#3a2e20")
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

func _rebuild_target_bar() -> void:
	if _target_bar == null:
		return
	for child in _target_bar.get_children():
		_target_bar.remove_child(child)
		child.queue_free()

	var tgt := Label.new()
	tgt.text = Loc.txt(_target_slot) if _target_slot != "" else "-"
	tgt.add_theme_font_size_override("font_size", 10)
	tgt.add_theme_color_override("font_color", _gold)
	_target_bar.add_child(tgt)

	# Показываем только когда есть что фильтровать: несколько категорий -
	# чипы категорий (плюс подкатегории выбранной), одна категория с
	# несколькими подкатегориями - только подкатегории, единственный
	# экземпляр и того и другого - не показываем вовсе.
	var found := _target_filter_items()
	var cats := _target_cats(found)
	var show_subs: Array = []
	var show_line := false
	if cats.size() > 1:
		show_line = true
		if _target_cat != "":
			show_subs = _target_subs(found, _target_cat)
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
	lbl.add_theme_color_override("font_color", Color("#5f5347"))
	line.add_child(lbl)

	if cats.size() > 1:
		for c in cats:
			line.add_child(_make_filter_chip(c, _target_cat == c))
	for sub in show_subs:
		line.add_child(_make_filter_chip(sub, _target_sub == sub, true))

	var reset := Button.new()
	reset.text = Loc.txt("Reset")
	reset.add_theme_font_size_override("font_size", 9)
	reset.tooltip_text = Loc.txt("Reset")
	var any_on := _target_cat != "" or _target_sub != ""
	reset.add_theme_stylebox_override("normal", _make_chip_style(any_on))
	reset.add_theme_color_override("font_color", _gold if any_on else Color("#5f5347"))
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
	b.add_theme_stylebox_override("normal", _make_chip_style(on))
	b.add_theme_color_override("font_color", _gold if on else Color("#cccccc"))
	_attach_motion(b)
	if level:
		b.pressed.connect(func(): _set_target_sub(key))
	else:
		b.pressed.connect(func(): _set_target_cat(key))
	return b

func _set_target_cat(c: String) -> void:
	_target_cat = "" if _target_cat == c else c
	# Смена старшего уровня сбрасывает младший: иначе после "Винтовки" ->
	# "Пистолеты" остался бы фильтр "Снайперки" из прошлой ветки.
	_target_sub = ""
	_refresh_pages()

func _set_target_sub(s: String) -> void:
	_target_sub = "" if _target_sub == s else s
	_refresh_pages()

func _reset_target_filters() -> void:
	_target_cat = ""
	_target_sub = ""
	_refresh_pages()

# Записи каталога, подходящие слоту-цели и запросу, с посчитанной
# подкатегорией. Поиск применяет _items_for_target, поэтому шапка фильтров и
# сетка под ней всегда показывают один и тот же набор.
func _target_filter_items() -> Array:
	var out: Array = []
	if _draft == null:
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
	if _target_cat == "" and _target_sub == "":
		return
	var found := _target_filter_items()
	var cats := _target_cats(found)
	if _target_cat != "":
		if not cats.has(_target_cat):
			_target_cat = ""
			_target_sub = ""
		elif _target_sub != "" and not _target_subs(found, _target_cat).has(_target_sub):
			_target_sub = ""
		return
	if cats.size() == 1:
		if _target_sub != "" and not _target_subs(found, cats[0]).has(_target_sub):
			_target_sub = ""
	else:
		_target_sub = ""

func _remove_slot(slot: String) -> void:
	if _draft == null:
		return
	var path_now := str(_draft.equip.get(slot, {}).get("path", ""))
	if _open_equip_att == path_now:
		_open_equip_att = ""
		_open_gear_att = ""
	if _target_slot == slot:
		_target_slot = ""
	_draft.remove_slot(slot)
	_refresh_pages()

func _set_target_slot(slot: String) -> void:
	_target_slot = slot
	# Цель сбрасывает открытую панель обвесов: она относилась к другому
	# предмету, и оставить её висеть значило бы врать про набор.
	_open_equip_att = ""
	_open_gear_att = ""
	_last_placed = ""
	_target_cat = ""
	_target_sub = ""
	_show_page(0)
	_refresh_pages()

func _set_search(t: String) -> void:
	_search_text = t
	_validate_target_filters()
	# Перестраиваются сетка и шапка фильтров, а не вся страница: набор её
	# чипов считается из того же списка, что и сетка, поэтому запрос сужает
	# и их. Поле поиска при этом не пересоздаётся и держит курсор.
	_rebuild_shelves()
	_rebuild_target_bar()

# Запись каталога для обоих шагов: предмет и его группа. Группу вычисляет
# Picker, а не строка type здесь: иначе шаг 1 и шаг 2 разошлись бы группами,
# и граната с Grenade_1 попала бы в другое место, чем её полка.
func _entry(it) -> Dictionary:
	return {
		"item": it,
		"cat": Picker.category_of(it.get("slots"), it.get("type")),
		"sub": Picker.subcategory_of(str(it.resource_path), it.get("type")),
	}

# Предметы под текущую цель и запрос. Цель - это фильтр по слотам, а не
# обязательство: клик по предмету без цели сам выбирает свободный слот.
func _items_for_target() -> Array:
	var out: Array = []
	for it in _db_items:
		if it == null:
			continue
		if not Picker.matches_search(str(it.get("name")), _search_text):
			continue
		if _target_slot != "" and not Picker.matches_slot(it.get("slots"), _target_slot):
			continue
		var e := _entry(it)
		if not Picker.category_allowed(str(e.get("cat", "")), _target_slot):
			continue
		out.append(e)
	return out

func _rebuild_shelves() -> void:
	if _shelves_box == null:
		return
	for child in _shelves_box.get_children():
		_shelves_box.remove_child(child)
		child.queue_free()
	var found := _target_filter_items()
	if _target_cat != "":
		var only: Array = []
		for e in found:
			if str(e.get("cat", "")) == _target_cat:
				only.append(e)
		found = only
	if _target_sub != "":
		var only_sub: Array = []
		for e in found:
			if str(e.get("sub", "")) == _target_sub:
				only_sub.append(e)
		found = only_sub
	if found.is_empty():
		var note := Label.new()
		note.text = Loc.txt("Nothing fits")
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", Color("#666666"))
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
	head.add_theme_color_override("font_color", Color("#d8cdbe"))
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

# Сведения о предмете по пути. Пути приходят из сохранённого сета, поэтому
# за индексом идёт только загрузка - но предмет из базы берётся из индекса
# без диска.
func _item_info(path: String) -> Dictionary:
	if path == "":
		return {}
	if _item_index.has(path):
		return _info_of(_item_index[path])
	return _info_of(load(path))

func _info_of(res) -> Dictionary:
	if res == null:
		return {}
	var compat = res.get("compatible")
	return {
		"resource": res,
		"name": str(res.get("name")),
		"type": str(res.get("type")),
		"cat": str(res.get("type", "")).to_lower(),
		"subtype": str(res.get("subtype")),
		"slots": _item_slots(res),
		"compatible": compat if typeof(compat) == TYPE_ARRAY else [],
		"maxAmount": res.get("maxAmount"),
	}

func _refresh_loadout_list() -> void:
	for child in _list_container.get_children():
		_list_container.remove_child(child)
		child.queue_free()
	_cards_grid = GridContainer.new()
	_cards_grid.columns = 3
	_cards_grid.add_theme_constant_override("h_separation", 6)
	_cards_grid.add_theme_constant_override("v_separation", 6)
	_cards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_child(_cards_grid)

	var LD = preload("res://mods/VTK/VTKData.gd")
	var loadouts = LD.get_all()
	if loadouts.is_empty():
		var empty = Label.new()
		empty.text = Loc.txt("No saved loadouts")
		empty.add_theme_color_override("font_color", Color("#666"))
		_list_container.add_child(empty)
		var debug = Label.new()
		debug.text = Loc.txt("file: ") + str(OS.get_user_data_dir()) + "/MCM/vostok-toolkit/VTKsets.json"
		debug.add_theme_font_size_override("font_size", 8)
		debug.add_theme_color_override("font_color", Color("#444"))
		_list_container.add_child(debug)
		_list_container.add_child(_make_create_btn())
		return

	for ld in loadouts:
		if typeof(ld) != TYPE_DICTIONARY:
			continue
		var nm := str(ld.get("name", ""))
		var pack: Dictionary = LD.get_set(nm)

		var card = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(200, 0)
		card.add_theme_stylebox_override("panel", VTKSurface.surface("normal", false, false, false, 12, 12, 11, 11))

		var box = VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 7)
		card.add_child(box)

		var top = HBoxContainer.new()
		top.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var titles = VBoxContainer.new()
		titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_lbl = Label.new()
		name_lbl.text = nm
		name_lbl.add_theme_font_size_override("font_size", 13)
		titles.add_child(name_lbl)
		var eq_d: Dictionary = pack.get("equip", {})
		var gr_a: Array = pack.get("gear", [])
		var meta = Label.new()
		meta.text = str(eq_d.size() + gr_a.size()) + Loc.txt(" items · ") + str(eq_d.size()) + Loc.txt(" in equipment")
		meta.add_theme_font_size_override("font_size", 10)
		meta.add_theme_color_override("font_color", Color("#666"))
		titles.add_child(meta)
		top.add_child(titles)

		var qk = int(ld.get("quick_key", 0))
		var qk_btn = Button.new()
		qk_btn.custom_minimum_size = Vector2(22, 20)
		qk_btn.add_theme_font_size_override("font_size", 9)
		if qk > 0:
			qk_btn.text = _keycode_to_string(qk)
			qk_btn.add_theme_color_override("font_color", _gold)
		else:
			qk_btn.text = "?"
			qk_btn.add_theme_color_override("font_color", Color("#444"))
		VTKSurface.style_button(qk_btn, qk > 0)
		qk_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		qk_btn.pressed.connect(func(): _cycle_quick_key_789(nm))
		top.add_child(qk_btn)
		box.add_child(top)

		var chips = HBoxContainer.new()
		chips.add_theme_constant_override("separation", 3)
		var shown := 0
		for slot in eq_d.keys():
			if shown >= 4:
				var more = Label.new()
				more.text = "+" + str(eq_d.size() - 4)
				more.add_theme_font_size_override("font_size", 8)
				more.add_theme_color_override("font_color", _gold)
				chips.add_child(more)
				break
			var ch = Label.new()
			ch.text = Loc.txt(str(slot))
			ch.add_theme_font_size_override("font_size", 8)
			ch.add_theme_color_override("font_color", Color("#8a7a60"))
			chips.add_child(ch)
			shown += 1
		box.add_child(chips)

		var foot = HBoxContainer.new()
		foot.add_theme_constant_override("separation", 4)
		var apply_btn = Button.new()
		apply_btn.text = Loc.txt("Apply")
		apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		VTKSurface.style_button(apply_btn, true)
		apply_btn.pressed.connect(func(): LD.load_loadout(nm))
		foot.add_child(apply_btn)
		var edit_btn = Button.new()
		edit_btn.text = Loc.txt("Edit")
		VTKSurface.style_button(edit_btn)
		edit_btn.pressed.connect(func(): _edit_loadout(nm))
		foot.add_child(edit_btn)
		var del_btn = Button.new()
		del_btn.text = "✕"
		VTKSurface.style_button(del_btn, false, true)
		del_btn.pressed.connect(func(): _delete_loadout(nm))
		foot.add_child(del_btn)
		box.add_child(foot)

		_cards_grid.add_child(card)

	_list_container.add_child(_make_create_btn())

func _make_create_btn() -> Button:
	var ghost = Button.new()
	ghost.text = Loc.txt("+ Create loadout")
	VTKSurface.style_button(ghost, true)
	ghost.pressed.connect(_start_new_draft)
	return ghost

# Плоский список заменён тремя страницами. Имя оставлено, потому что на него
# завязаны _bump_gear, _toggle_attachment_panel и _clear_draft; по смыслу это
# теперь "перерисовать то, что сейчас видно".
func _refresh_draft_ui() -> void:
	_refresh_pages()

func _make_att_btn(desc) -> Button:
	var path_now := str(desc.get("path", ""))
	var atts = desc.get("attachments") if desc.has("attachments") else []
	var b := Button.new()
	b.text = Loc.txt(" rnd.") + str(atts.size()) + " "
	b.custom_minimum_size = Vector2(0, 18)
	b.add_theme_font_size_override("font_size", 8)
	if atts.size() > 0:
		b.add_theme_color_override("font_color", _gold)
	VTKSurface.style_button(b, true)
	b.pressed.connect(func(): _toggle_attachment_panel(path_now))
	return b

func _bump_gear(path: String, delta: float) -> void:
	if _draft == null:
		return
	_draft.set_gear_amount(path, _draft.amount_of(path) + delta)
	_refresh_draft_ui()

func _toggle_attachment_panel(path: String) -> void:
	if _page == 1:
		_open_gear_att = "" if _open_gear_att == path else path
	else:
		_open_equip_att = "" if _open_equip_att == path else path
	_refresh_draft_ui()

# Иконка предмета. У части предметов в данных игры icon пуст, хотя PNG лежит
# рядом в Files/ под именем Icon_<имя файла>.png - так в игре
# AKS-74U_Magazine. Путь собирается относительно самого предмета, а не по
# шаблону каталога: после обновления игры фолбэк просто не срабатывает и
# остаётся пустая иконка, как раньше.
func _item_icon(res) -> Texture2D:
	if not (res is Resource):
		return null
	if "icon" in res and res["icon"]:
		return res["icon"]
	var base := str(res.resource_path)
	if not base.ends_with(".tres"):
		return null
	if _icon_cache.has(base):
		return _icon_cache[base]
	var p := base.get_base_dir() + "/Files/Icon_" + base.get_file().get_basename() + ".png"
	var tex = load(p) if ResourceLoader.exists(p) else null
	_icon_cache[base] = tex
	return tex

func _make_item_cell(item, forced_slot = null) -> Control:
	var cell = Panel.new()
	cell.custom_minimum_size = Vector2(96, 132)
	# Без SIZE_EXPAND_FILL: HFlowContainer растягивает такие клетки на всю
	# ширину полосы, пока предметов мало (stretch в flow_container.cpp).
	cell.mouse_filter = Control.MOUSE_FILTER_STOP

	var normal_style := VTKSurface.surface("normal")
	var hover_style := VTKSurface.surface("hover")
	var in_set_style := VTKSurface.surface("normal", true, false, true)

	cell.add_theme_stylebox_override("panel", normal_style)
	_attach_motion(cell)

	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(center)
	# Panel - не контейнер: без пресета center остаётся нулевым прямоугольником
	# в левом верхнем углу, и иконка центрируется относительно угла клетки.
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	var tex = TextureRect.new()
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.custom_minimum_size = Vector2(84, 48)
	var icon := _item_icon(item)
	if icon:
		tex.texture = Picker.item_art(icon)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(tex)

	var name_lbl = Label.new()
	name_lbl.text = item.name
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.add_theme_color_override("font_color", Color("#aaa"))
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_lbl.max_lines_visible = 2
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	var path_now: String = item.resource_path
	var already := _draft != null and _draft.has_path(path_now)
	if already:
		var cur_slot := _draft.equip_slot_of(path_now)
		if cur_slot == "":
			var n := int(_draft.amount_of(path_now))
			if n > 1:
				var cnt = Label.new()
				cnt.text = "×" + str(n)
				cnt.add_theme_font_size_override("font_size", 8)
				cnt.add_theme_color_override("font_color", _gold)
				cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
				vbox.add_child(cnt)
		cell.add_theme_stylebox_override("panel", in_set_style)

	cell.tooltip_text = item.name

	var it = item
	# Шаг 2 зовёт клетку с пустой целью явно, иначе цель шага 1 переехала бы
	# на шаг 2 вместе с клеткой.
	var slot := _target_slot if forced_slot == null else str(forced_slot)
	cell.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_place_into(it, slot)
	)
	cell.mouse_entered.connect(func():
		var base_style := in_set_style if already else hover_style
		cell.add_theme_stylebox_override("panel", base_style)
	)
	cell.mouse_exited.connect(func():
		cell.add_theme_stylebox_override("panel", normal_style)
	)
	return cell

func _item_slots(item) -> Array:
	if item == null:
		return []
	var slots = item.get("slots")
	if typeof(slots) != TYPE_ARRAY:
		return []
	return slots

# Клик по предмету. Цель решает всё: при явной цели предмет вытесняет то, что
# стояло в этом слоте, при пустой занимает первый свободный слот сам, а если
# слотов нет - уходит в снаряжение.
func _place_item(item) -> void:
	_place_into(item, _target_slot)

# Клик по предмету. Слот-цель решает всё: при явной цели предмет вытесняет то,
# что стояло в этом слоте, при пустой занимает первый свободный слот сам, а если
# слотов нет - уходит в снаряжение.
func _place_into(item, slot: String) -> void:
	if _draft == null or item == null:
		return
	var path := str(item.resource_path)
	if path == "":
		return
	var res = _item_index.get(path)
	if res == null:
		res = load(path)
	if res == null:
		return
	# Запоминаем предмет до расчёта количества: если предмет не влезет в слот,
	# _after_place не зовётся, и без этого строка ушла бы в следующий клик и
	# открыла панель не того предмета.
	_last_placed = path
	var t := str(res.get("type"))
	var amt := 1.0
	if t != "Weapon" and t != "Ammo":
		var max_am = res.get("maxAmount")
		if max_am != null and float(max_am) > 1.0:
			amt = float(max_am)
	var counted := t == "Attachment" and str(res.get("subtype")) == "Magazine"
	var slots = _item_slots(res)
	var item_name := str(res.get("name"))
	if slot != "":
		# add_to_slot отказывает, не тронув набор, если предмет не подходит
		# слоту. Отказ - это не вытеснение, поэтому сообщаем и выходим, а не
		# падаем в add(): иначе предмет молча уехал бы в другое место мимо
		# выбранной цели.
		if _draft.add_to_slot(path, item_name, slots, amt, t, slot, counted) != "":
			_after_place()
			return
		if not Picker.matches_slot(slots, slot):
			_set_problem(Loc.txt("Does not fit: ") + Loc.txt(slot))
			return
	_draft.add(path, item_name, slots, amt, t, counted)
	_after_place()

func _after_place() -> void:
	_clear_problem()
	# Клик по предмету открывает его обвесы: иначе до них надо было
	# добираться через кнопку в строке слота, о чём мало кто догадывался.
	# У обоймы панели нет - там тумблер заполнения, открывать нечего.
	if _last_placed != "" and not _is_magazine(_last_placed) \
			and Picker.has_panel(_item_info(_last_placed)):
		if _page == 1:
			_open_gear_att = _last_placed
		else:
			_open_equip_att = _last_placed
	_last_placed = ""
	_refresh_pages()

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
	var res = _item_index.get(path)
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
	var info := _item_info(str(desc.get("path", "")))
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

# Панель обвесов живёт в правой колонке под каталогом, а не рядом со строкой
# слота: после переноса слотов в боковую колонку она оказалась бы среди строк.
# Своя панель у каждой страницы: экран, открытый в Экипировке, не должен
# появляться и в Снаряжении. Каждая страница рендерит только своё состояние.
func _rebuild_att_box(host: VBoxContainer, path: String) -> void:
	if host == null:
		return
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()
	if path == "":
		return
	var panel := _build_att_panel(path)
	if panel != null:
		host.add_child(panel)

# Панель одного предмета. Возвращает null, если панели нет: кнопка RND тогда
# не показывается вовсе, и незачем создавать пустой блок.
func _build_att_panel(path: String) -> Control:
	if _draft == null:
		return null
	var desc := _draft.descriptor_of(path)
	if desc.is_empty():
		return null
	if _is_magazine(path):
		return _build_mag_panel(path, desc)
	if not Picker.has_panel(_item_info(path)):
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

	var head := Label.new()
	head.text = Loc.txt("Attachments")
	head.add_theme_font_size_override("font_size", 10)
	head.add_theme_color_override("font_color", Color("#6a5a4a"))
	vb.add_child(head)
	# Имя предмета отдельной строкой: панель стоит под каталогом, и без неё
	# не видно, чьи это обвесы.
	var owner_lbl := Label.new()
	owner_lbl.text = str(desc.get("name", "?"))
	owner_lbl.add_theme_font_size_override("font_size", 11)
	owner_lbl.add_theme_color_override("font_color", _gold)
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
			flow.add_child(_make_att_cell(path, grp, _attachment_resource(a)))
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
	var on := _draft != null and _draft.has_attachment(owner_path, str(att_res.resource_path))

	var normal := VTKSurface.surface("normal")
	var hover := VTKSurface.surface("hover")
	var picked := VTKSurface.surface("normal", true, false, true)

	cell.add_theme_stylebox_override("panel", picked if on else normal)
	_attach_motion(cell)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(center)
	# Panel - не контейнер: без пресета center остаётся нулевым прямоугольником
	# в левом верхнем углу, и иконка центрируется относительно угла клетки.
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	var tex = TextureRect.new()
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.custom_minimum_size = Vector2(84, 48)
	var icon := _item_icon(att_res)
	if icon:
		tex.texture = Picker.item_art(icon)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(tex)

	var nm = Label.new()
	nm.text = str(att_res.name)
	nm.add_theme_font_size_override("font_size", 9)
	nm.add_theme_color_override("font_color", _gold if on else Color("#aaa"))
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	nm.max_lines_visible = 2
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(nm)

	cell.tooltip_text = str(att_res.name) + "\n" + str(att_res.resource_path)
	cell.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if _draft == null:
				return
			_draft.toggle_attachment(owner_path, str(att_res.resource_path), grp, _att_group_of)
			# Панель остаётся открытой: подбор обвесов идёт списком, и закрывать
			# её после каждого клика значило бы кликать дважды на каждый обвес.
			_refresh_pages()
	)
	cell.mouse_entered.connect(func():
		if not on:
			cell.add_theme_stylebox_override("panel", hover))
	cell.mouse_exited.connect(func():
		cell.add_theme_stylebox_override("panel", picked if on else normal))
	return cell

# Из записи группы обвесов достаётся ресурс: _item_info отдаёт словарь с
# полем "resource", а плитке нужен сам ресурс - ради иконки и имени.
func _attachment_resource(a: Dictionary):
	return _item_info(str(a.get("path", ""))).get("resource")

# У обоймы единственный "обвес" - совместимый патрон, и он уезжает в
# slotData.nested, который игра не читает. Число патронов задаёт сам amount
# обоймы, поэтому вместо списка обвесов показываем тумблер заполнения.
func _build_mag_panel(path: String, desc: Dictionary) -> Control:
	var info := _item_info(path)
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
		if _draft == null:
			return
		_draft.set_full_mag(path, is_on)
		_refresh_pages()
	)
	row.add_child(b)

	var cut_label := Label.new()
	cut_label.text = Loc.txt("Full magazine")
	cut_label.add_theme_font_size_override("font_size", 10)
	cut_label.add_theme_color_override("font_color", _gold if on else Color("#bbb"))
	cut_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cut_label)

	var cap_lbl := Label.new()
	cap_lbl.text = Loc.txt("[rounds]") + " " + str(cap)
	cap_lbl.add_theme_font_size_override("font_size", 9)
	cap_lbl.add_theme_color_override("font_color", Color("#666666"))
	row.add_child(cap_lbl)
	return panel

# ============== TAB: Настройки ==============

var _kc_node: Control = null
var _hooks: Node = null
var _nvg_node: Node = null
var _kc_active: bool = false
var _kc_mcm: bool = true
var _feed_mcm: bool = true
var _hud_canvas = null
var _feed_node = null
var _thermal_active: bool = false
var _mines_active: bool = true
var _kc_btn: Node = null
var _thermal_btn: Node = null
var _mines_btn: Node = null

const TOGGLE_CFG := "user://MCM/vostok-toolkit/ui_toggles.json"

func _save_toggles() -> void:
	var data = {"kc": _kc_active, "mine": _mines_active, "thermal": _thermal_active, "lang": Loc.get_lang()}
	var d = DirAccess.open(OS.get_user_data_dir() + "/MCM/vostok-toolkit")
	if not d:
		d = DirAccess.open(OS.get_user_data_dir())
		if d:
			d.make_dir("MCM")
			d = DirAccess.open(OS.get_user_data_dir() + "/MCM")
			if d:
				d.make_dir("vostok-toolkit")
				d = DirAccess.open(OS.get_user_data_dir() + "/MCM/vostok-toolkit")
	var f = FileAccess.open(TOGGLE_CFG, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func _load_lang() -> void:
	Loc.set_lang(Loc.DEFAULT)
	var f = FileAccess.open(TOGGLE_CFG, FileAccess.READ)
	if not f:
		print("[VTK] lang: no ", TOGGLE_CFG, ", using ", Loc.DEFAULT)
		return
	var txt = f.get_as_text()
	f.close()
	if txt.is_empty():
		return
	var j = JSON.new()
	if j.parse(txt) != OK:
		return
	Loc.set_lang(str(j.data.get("lang", Loc.DEFAULT)))
	print("[VTK] lang restored: ", Loc.get_lang())

func _clear_ui() -> void:
	for n in _ui_nodes:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_ui_nodes.clear()
	_tab_btns.clear()
	_tab_containers.clear()
	_scroll = null
	_panel = null

func _restore_toggles() -> void:
	var f = FileAccess.open(TOGGLE_CFG, FileAccess.READ)
	if not f:
		return
	var txt = f.get_as_text()
	f.close()
	if txt.is_empty():
		return
	var j = JSON.new()
	if j.parse(txt) != OK:
		return
	var d = j.data
	_kc_active = bool(d.get("kc", false))
	_mines_active = bool(d.get("mine", true))
	_thermal_active = bool(d.get("thermal", false))
	if _kc_btn:
		_kc_btn.button_pressed = _kc_active
	if _mines_btn:
		_mines_btn.button_pressed = _mines_active
		_mines_toggle(_mines_active)
	if _thermal_btn:
		_thermal_btn.button_pressed = _thermal_active
		_thermal_toggle(_thermal_active)

func _build_settings_tab(parent: VBoxContainer) -> void:
	_lang_btns.clear()

	parent.add_child(HSeparator.new())

	_make_settings_header(parent, Loc.txt("Interface"))
	_make_lang_row(parent)

	_make_settings_header(parent, Loc.txt("Modules"))
	_kc_btn = _make_toggle_row(parent, Loc.txt("Kill counter"), Loc.txt("Shows the kill counter in the interface"), _kc_toggle)
	_mines_btn = _make_toggle_row(parent, Loc.txt("Mine highlighting (in thermal)"), Loc.txt("Mines are highlighted in thermal vision mode"), _mines_toggle)
	_thermal_btn = _make_toggle_row(parent, Loc.txt("Thermal vision"), Loc.txt("Turns on the thermal vision mode"), _thermal_toggle)

func _make_settings_header(parent: VBoxContainer, text: String) -> void:
	var h := Label.new()
	h.text = text.to_upper()
	h.add_theme_font_size_override("font_size", 9)
	h.add_theme_color_override("font_color", Color("#5f5347"))
	h.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	h.add_theme_constant_override("shadow_offset_x", 1)
	h.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(h)

func _make_lang_row(parent: VBoxContainer) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 1)
	row.add_child(box)
	var lbl = Label.new()
	lbl.text = Loc.txt("Interface language")
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#d8cdbe"))
	box.add_child(lbl)
	var sub := Label.new()
	sub.text = Loc.txt("Switch between English and Russian")
	sub.add_theme_font_size_override("font_size", 8)
	sub.add_theme_color_override("font_color", Color("#5f5347"))
	box.add_child(sub)

	_lang_btns.clear()
	var codes := Loc.codes()
	var seg_panel := PanelContainer.new()
	seg_panel.add_theme_stylebox_override("panel", VTKSurface.panel(true, 4))
	seg_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(seg_panel)
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 0)
	seg_panel.add_child(seg)
	for c in codes:
		var b := Button.new()
		b.text = Loc.code_label(c)
		b.toggle_mode = true
		b.button_pressed = (c == Loc.get_lang())
		b.custom_minimum_size = Vector2(64, 30)
		b.add_theme_font_size_override("font_size", 11)
		var seg_btn := _make_seg_btn_style(c == Loc.get_lang())
		b.add_theme_stylebox_override("normal", seg_btn)
		var seg_btn_hover := _make_seg_btn_style(true)
		b.add_theme_stylebox_override("hover", seg_btn_hover)
		var seg_btn_pressed := _make_seg_btn_style(true)
		b.add_theme_stylebox_override("pressed", seg_btn_pressed)
		b.add_theme_color_override("font_color", _gold if c == Loc.get_lang() else Color("#8a7a6a"))
		_attach_motion(b)
		b.pressed.connect(_on_lang_button.bind(c))
		seg.add_child(b)
		_lang_btns.append(b)
	return row

func _make_seg_btn_style(active: bool) -> StyleBox:
	return VTKSurface.surface("normal", active, false, false, 8, 8, 4, 4)

func _on_lang_button(code: String) -> void:
	var cur := Loc.get_lang()
	print("[VTK] lang button pressed code=", code, " current=", cur)
	if code == cur:
		return
	Loc.set_lang(code)
	_save_toggles()
	print("[VTK] lang now=", Loc.get_lang(), ", rebuilding UI")
	_clear_ui()
	_build_ui()
	_restore_toggles()

func _make_toggle_row(parent: VBoxContainer, label_text: String, hint_text: String, callback: Callable) -> Node:
	var set_row := PanelContainer.new()
	set_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_row.add_theme_stylebox_override("panel", VTKSurface.surface("normal", false, false, false, 10, 10, 7, 7))
	parent.add_child(set_row)
	_attach_row_hover(set_row, func(hv: bool) -> StyleBox:
		return VTKSurface.surface("hover" if hv else "normal", false, false, false, 10, 10, 7, 7))

	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	set_row.add_child(row)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 1)
	row.add_child(box)
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#d8cdbe"))
	box.add_child(lbl)
	var sub = Label.new()
	sub.text = hint_text
	sub.add_theme_font_size_override("font_size", 8)
	sub.add_theme_color_override("font_color", Color("#5f5347"))
	box.add_child(sub)

	var sw := ToggleSwitch.new()
	sw.set_on(false)
	sw.toggled.connect(callback)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sw)
	return sw

# UI-тумблер из вкладки «Настройки»: пишет в json (legacy) и в MCM, затем
# применяет через общий путь. _save_toggles после _apply_hud, чтобы json
# получил уже обновлённый _kc_active, а не предыдущее значение.
func _kc_toggle(on: bool) -> void:
	_kc_mcm = on
	_save_mcm_bool("kill_counter_enabled", on)
	_apply_hud()
	_save_toggles()

# Единая точка применения обоих HUD-виджетов. Зовётся из _mcm_apply и из
# UI-тумблера; файлы не трогает — запись в MCM делает только _kc_toggle.
func _apply_hud() -> void:
	_kc_active = _kc_mcm
	if _kc_btn != null and is_instance_valid(_kc_btn):
		_kc_btn.button_pressed = _kc_mcm
	_set_counter_enabled(_kc_mcm)
	_set_feed_enabled(_feed_mcm)

func _set_counter_enabled(v: bool) -> void:
	if v:
		_ensure_hud()
		_kc_node.set_enabled(true)
	elif _kc_node != null and is_instance_valid(_kc_node):
		_kc_node.set_enabled(false)

func _set_feed_enabled(v: bool) -> void:
	if v:
		_ensure_hud()
		_feed_node.set_enabled(true)
	elif _feed_node != null and is_instance_valid(_feed_node):
		_feed_node.set_enabled(false)

# Один CanvasLayer на оба виджета; лениво, пока хотя бы один не включён.
func _ensure_hud() -> void:
	if _kc_node != null and is_instance_valid(_kc_node) \
			and _feed_node != null and is_instance_valid(_feed_node):
		return
	if _hud_canvas == null or not is_instance_valid(_hud_canvas):
		_hud_canvas = CanvasLayer.new()
		_hud_canvas.name = "VTKKC_Canvas"
		_hud_canvas.layer = 9999
		get_tree().root.add_child(_hud_canvas)
	if _kc_node == null or not is_instance_valid(_kc_node):
		var KC = preload("res://mods/VTK/VTKKillCounter.gd")
		_kc_node = KC.new()
		_hud_canvas.add_child(_kc_node)
	if _feed_node == null or not is_instance_valid(_feed_node):
		var Feed = preload("res://mods/VTK/VTKFeed.gd")
		_feed_node = Feed.new()
		_hud_canvas.add_child(_feed_node)

# Перезапись значения Bool-ключа в config.ini, чтобы меню MCM показывало
# то же, что переключил пользователь в настройках мода.
func _save_mcm_bool(key: String, v: bool) -> void:
	var cfile := "user://MCM/vostok-toolkit/config.ini"
	if not FileAccess.file_exists(cfile):
		return
	var cf := ConfigFile.new()
	if cf.load(cfile) != OK:
		return
	if not cf.has_section_key("Bool", key):
		return
	var d = cf.get_value("Bool", key, {})
	if typeof(d) != TYPE_DICTIONARY:
		return
	d["value"] = v
	cf.set_value("Bool", key, d)
	cf.save(cfile)

func _mines_toggle(on: bool) -> void:
	_mines_active = on
	_save_toggles()
	_ensure_nvg()
	if _nvg_node != null and is_instance_valid(_nvg_node):
		_nvg_node.set_mines_enabled(on)

func _thermal_toggle(on: bool) -> void:
	_thermal_active = on
	_save_toggles()
	_ensure_nvg()
	if _nvg_node != null and is_instance_valid(_nvg_node):
		_nvg_node.set_thermal_enabled(on)

# поэтому состояние кладём прямо в него и перечитываем на каждом Apply.

func _ensure_nvg() -> void:
	if _nvg_node != null and is_instance_valid(_nvg_node):
		return
	var NVG = preload("res://mods/VTK/VTKNVG.gd")
	_nvg_node = NVG.new()
	add_child(_nvg_node)

func _ensure_travel() -> void:
	if _travel != null and is_instance_valid(_travel):
		return
	var T := preload("res://mods/VTK/VTKTravel.gd")
	_travel = T.new()
	add_child(_travel)

func _apply_nvg_settings() -> void:
	_ensure_nvg()
	if _nvg_node != null and is_instance_valid(_nvg_node):
		_nvg_node.set_mines_enabled(_mines_active)
		_nvg_node.set_thermal_enabled(_thermal_active)

# ============== SAVE / LOAD / DELETE ==============

func _start_new_draft() -> void:
	_draft = Draft.new()
	_open_equip_att = ""
	_open_gear_att = ""
	_editing_name = ""
	_build_editor()

func _cancel_draft() -> void:
	_draft = null
	_open_equip_att = ""
	_open_gear_att = ""
	_editing_name = ""
	_build_editor()
	_refresh_loadout_list()

func _clear_draft() -> void:
	if _draft == null:
		return
	_draft.clear()
	# Цель и поиск относятся к прежнему содержимому, поэтому чистим их тоже.
	_reset_picker_state()
	_refresh_draft_ui()

func _save_loadout() -> void:
	if _draft == null:
		return
	if _name_input != null:
		_draft.set_name = _name_input.text.strip_edges()
	var name_new := _draft.set_name.strip_edges()
	# Отказы сообщаем в том же ряду, где живут шаги: раньше пустой ввод и
	# пустой сет просто ничего не делали, и пользователь не понимал, почему
	# кнопка молчит.
	if name_new == "":
		_set_problem(Loc.txt("Loadout name required"))
		return
	if _draft.item_count() == 0:
		_set_problem(Loc.txt("Set is empty"))
		return
	var LD = preload("res://mods/VTK/VTKData.gd")
	var all = LD.get_all()
	for ld in all:
		if str(ld.get("name")) == name_new and name_new != _editing_name:
			_set_problem(Loc.txt("Name already taken!"))
			if _name_input != null:
				_name_input.text = ""
				_name_input.placeholder_text = Loc.txt("Name already taken!")
			return
	var kept_key := 0
	if _editing_name != "" and _editing_name != name_new:
		for ld in all:
			if str(ld.get("name")) == _editing_name:
				kept_key = int(ld.get("quick_key", 0))
				break
		LD.remove(_editing_name)
	LD.replace_set(name_new, _draft.equip, _draft.gear)
	if kept_key != 0:
		LD.set_quick_key(name_new, kept_key)
	_draft.set_name = name_new
	_editing_name = name_new
	_clear_problem()
	_refresh_loadout_list()

func _load_loadout(name: String) -> void:
	var LD = preload("res://mods/VTK/VTKData.gd")
	LD.load_loadout(name)

func _edit_loadout(name: String) -> void:
	var LD = preload("res://mods/VTK/VTKData.gd")
	var raw = LD.get_set(name)
	if raw.is_empty():
		return
	var d = Draft.new()
	d.load_from(raw)
	_draft = d
	_editing_name = name
	_open_equip_att = ""
	_open_gear_att = ""
	_build_editor()

func _delete_loadout(name: String) -> void:
	var LD = preload("res://mods/VTK/VTKData.gd")
	LD.remove(name)
	if _editing_name == name:
		_cancel_draft()
	else:
		_refresh_loadout_list()

func _cycle_quick_key_789(name: String) -> void:
	var LD = preload("res://mods/VTK/VTKData.gd")
	var all = LD.get_all()
	var current = 0
	for ld in all:
		if ld["name"] == name:
			current = ld.get("quick_key") if ld.has("quick_key") else 0
			break
	var taken = {}
	for ld in all:
		if ld["name"] != name:
			var k = ld.get("quick_key") if ld.has("quick_key") else 0
			if k > 0:
				taken[k] = true
	var keys = [KEY_7, KEY_8, KEY_9]
	var next = 0
	if current > 0:
		for i in range(keys.size()):
			if keys[i] == current:
				next = keys[(i + 1) % keys.size()]
				break
		if next == 0 or next == current:
			next = 0
	else:
		for k in keys:
			if not taken.has(k):
				next = k
				break
	LD.set_quick_key(name, next)
	_refresh_loadout_list()

static func _keycode_to_string(kc: int) -> String:
	if kc == KEY_7: return "7"
	if kc == KEY_8: return "8"
	if kc == KEY_9: return "9"
	return "?"

func _register_mcm() -> void:
	if not ResourceLoader.exists("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres"):
		_kc_mcm = _kc_active
		_apply_hud()
		return
	var MCM = load("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres")
	if MCM == null or not MCM.has_method("RegisterConfiguration"):
		return
	var cfg = ConfigFile.new()
	var CAT := "01. General"
	cfg.set_value("Keycode", "key_ui_toggle", {"name": "Hotkey: Toggle UI", "default": 0, "default_type": "Keycode", "value": 0, "category": CAT, "menu_pos": 0, "tooltip": "Press once to open/close the Loadouts UI."})
	cfg.set_value("Bool", "nvg_debug_probe", {"name": "Debug logging", "default": false, "value": false, "category": CAT, "menu_pos": 1, "tooltip": "Writes probes to user://loadouts_debug.log and enables the F4 detection overlay. Leave off during normal play; turn on only to diagnose something."})
	var TP := "02. ThermalVision"
	cfg.set_value("Float", "nvg_noise", {"name": "NVG noise", "default": 4.0, "value": 4.0, "minRange": 0.0, "maxRange": 60.0, "step": 0.5, "category": TP, "menu_pos": 0, "tooltip": "Grain amount over the NVG image. Lower is cleaner. Vanilla is fixed at 10."})
	cfg.set_value("Float", "nvg_white", {"default": 1.0, "value": 1.0, "minRange": 0.05, "maxRange": 1.0, "step": 0.05, "category": TP, "menu_pos": 1, "tooltip": "Tonemap white point while NVG is on. Pull down to darken the image and cut the shimmer.", "name": "NVG white point"})
	cfg.set_value("Int", "thermal_palette", {"default": 0, "value": 0, "minRange": 0, "maxRange": 5, "step": 1, "category": TP, "menu_pos": 2, "tooltip": "0 = Classic, 1 = White Hot (grey), 2 = Black Hot (inverted grey), 3 = Amber, 4 = Forest, 5 = Ice.", "name": "World palette"})
	cfg.set_value("Float", "thermal_world", {"default": 1.70, "value": 1.70, "minRange": 1.0, "maxRange": 4.0, "step": 0.05, "category": TP, "menu_pos": 3, "tooltip": "How bright the surrounding world reads in thermal.", "name": "World brightness"})
	cfg.set_value("Int", "thermal_bot_preset", {"default": 0, "value": 0, "minRange": 0, "maxRange": 3, "step": 1, "category": TP, "menu_pos": 4, "tooltip": "0 = Orange, 1 = Red, 2 = White, 3 = Cyan.", "name": "Bot colour"})
	cfg.set_value("Float", "thermal_far_distance", {"default": 45.0, "value": 45.0, "minRange": 5.0, "maxRange": 300.0, "step": 5.0, "category": TP, "menu_pos": 5, "tooltip": "Beyond this distance a bot switches to the dimmer marker, the same way real thermal optics lose contrast with range.", "name": "Dim distance"})
	cfg.set_value("Float", "thermal_bot_opacity", {"default": 0.0, "value": 0.0, "minRange": 0.0, "maxRange": 1.0, "step": 0.05, "category": TP, "menu_pos": 6, "tooltip": "0 = a bot is drawn in the thermal palette colour for its own heat signature, so it can never introduce an off-palette hue. 1 = flat colour from the Bot colour preset. Cosmetic only; detection is unaffected, so it is safe to change mid-game.", "name": "Bot marker opacity"})
	var TR := "03. Travel"
	cfg.set_value("Bool", "tp_unlocked_shelters_only", {"name": "Unlocked shelters only", "default": false, "value": false, "category": TR, "menu_pos": 0, "tooltip": "When enabled, teleporting to a locked shelter is refused."})
	var KF := "04. KillFeed"
	cfg.set_value("Bool", "kill_counter_enabled", {"name": "Kill counter", "default": true, "value": true, "category": KF, "menu_pos": 0, "tooltip": "Show the kill counter HUD line (Killed / Enemies / Nomads)."})
	cfg.set_value("Bool", "kill_feed_enabled", {"name": "Kill feed", "default": true, "value": true, "category": KF, "menu_pos": 1, "tooltip": "Show the kill feed under the counter: killer, weapon/headshot icons, victim."})
	cfg.set_value("Info", "version", _mod_version())
	cfg.set_value("Info", "author", "opencode")
	var path = "user://MCM/vostok-toolkit"
	DirAccess.make_dir_recursive_absolute(path)
	var cfile = path + "/config.ini"
	if FileAccess.file_exists(cfile):
		var existing = ConfigFile.new()
		existing.load(cfile)
		var stale_sections := []
		for s in existing.get_sections():
			if s != "Info" and not cfg.has_section(s):
				stale_sections.append(s)
		for s in stale_sections:
			existing.erase_section(s)
		for s in cfg.get_sections():
			var stale_keys: Array = []
			if existing.has_section(s):
				for k in existing.get_section_keys(s):
					if not cfg.has_section_key(s, k):
						stale_keys.append(k)
			for k in stale_keys:
				existing.erase_section_key(s, k)
		for s in cfg.get_sections():
			for k in cfg.get_section_keys(s):
				if s == "Info":
					existing.set_value(s, k, cfg.get_value(s, k, {}))
					continue
				if not existing.has_section_key(s, k):
					existing.set_value(s, k, cfg.get_value(s, k, {}))
					continue
				var old_v = existing.get_value(s, k, {})
				var new_v = cfg.get_value(s, k, {})
				if typeof(old_v) == TYPE_DICTIONARY and typeof(new_v) == TYPE_DICTIONARY:
					var merged = new_v.duplicate()
					merged["value"] = old_v.get("value", new_v.get("value"))
					existing.set_value(s, k, merged)
		existing.save(cfile)
	if not FileAccess.file_exists(cfile):
		cfg.save(cfile)
	MCM.RegisterConfiguration("vostok-toolkit", "Vostok Toolkit", path, "Loadouts, ESP and teleport", _mcm_apply, self)
	_mcm_apply(ConfigFile.new())

func _mod_version() -> String:
	var vf = FileAccess.open("res://mods/VTK/version.txt", FileAccess.READ)
	if vf != null:
		var v := vf.get_as_text().strip_edges()
		vf.close()
		if v != "":
			return v
	# Фолбэк для ручной укладки без pack.ps1: res://mod.txt разделяется всеми
	# модами в рантайме и может оказаться чужим (в заголовке чужая версия).
	var f = FileAccess.open("res://mod.txt", FileAccess.READ)
	if f == null:
		return "unknown"
	var text = f.get_as_text()
	f.close()
	var at = text.find("version=")
	if at < 0:
		return "unknown"
	var open_q = text.find("\"", at)
	if open_q < 0:
		return "unknown"
	var close_q = text.find("\"", open_q + 1)
	if close_q < 0:
		return "unknown"
	return text.substr(open_q + 1, close_q - open_q - 1)

func _mcm_key_val(cfg: ConfigFile, section: String, key: String, fallback):
	if not cfg.has_section_key(section, key):
		return fallback
	var d = cfg.get_value(section, key, {})
	if typeof(d) == TYPE_DICTIONARY and d.has("value"):
		return d["value"]
	return d if typeof(d) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT] else fallback

func _mcm_apply(cfg: ConfigFile) -> void:
	var cpath = "user://MCM/vostok-toolkit/config.ini"
	if cfg.get_sections().is_empty() and FileAccess.file_exists(cpath):
		cfg.load(cpath)
	_key_ui_toggle = int(_mcm_key_val(cfg, "Keycode", "key_ui_toggle", 0))
	_kc_mcm = bool(_mcm_key_val(cfg, "Bool", "kill_counter_enabled", true))
	_feed_mcm = bool(_mcm_key_val(cfg, "Bool", "kill_feed_enabled", true))
	_apply_hud()
	_ensure_travel()
	if _travel != null and is_instance_valid(_travel):
		var tp_unlocked = bool(_mcm_key_val(cfg, "Bool", "tp_unlocked_shelters_only", false))
		_travel.set_unlocked_only(tp_unlocked)
	_ensure_nvg()
	if _nvg_node == null or not is_instance_valid(_nvg_node):
		return
	_nvg_node.set_nvg_noise = float(_mcm_key_val(cfg, "Float", "nvg_noise", 4.0))
	_nvg_node.set_nvg_white = float(_mcm_key_val(cfg, "Float", "nvg_white", 1.0))
	_nvg_node.set_palette = int(_mcm_key_val(cfg, "Int", "thermal_palette", 0))
	_nvg_node.set_world = float(_mcm_key_val(cfg, "Float", "thermal_world", 1.70))
	_nvg_node.set_bot_preset = int(_mcm_key_val(cfg, "Int", "thermal_bot_preset", 0))
	_nvg_node.set_far_distance = float(_mcm_key_val(cfg, "Float", "thermal_far_distance", 45.0))
	_nvg_node.set_bot_opacity = float(_mcm_key_val(cfg, "Float", "thermal_bot_opacity", 0.0))
	_nvg_node.set_debug_probe = bool(_mcm_key_val(cfg, "Bool", "nvg_debug_probe", false))
	_nvg_node.apply_debug_probe()
	_apply_nvg_settings()

func _tp_row(title: String, note: String, enabled: bool, callback: Callable) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_stylebox_override("panel", VTKSurface.surface("normal", false, false, false, 10, 10, 7, 7))

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	row.add_child(hb)

	var nm := Label.new()
	nm.text = title
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", Color("#d8cdbe") if enabled else Color("#4d443a"))
	hb.add_child(nm)

	if note != "":
		var nt := Label.new()
		nt.text = note
		nt.add_theme_font_size_override("font_size", 9)
		nt.add_theme_color_override("font_color", Color("#5f5347"))
		nt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(nt)

	var go := Label.new()
	go.text = "▸" if enabled else "•"
	go.add_theme_font_size_override("font_size", 12)
	go.add_theme_color_override("font_color", _gold if enabled else Color("#3a3226"))
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(go)

	if enabled:
		_attach_row_hover(row, func(hv: bool) -> StyleBox:
			return VTKSurface.surface("hover" if hv else "normal", false, false, false, 10, 10, 7, 7))
		_attach_motion(row)
		var cb := callback
		row.gui_input.connect(func(ev: InputEvent):
			var mb := ev as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				if cb.is_valid():
					cb.call())
	return row


func _refresh_teleport_tab() -> void:
	_ensure_travel()
	if _travel == null or not is_instance_valid(_travel):
		return
	for box in [_tp_maps_box, _tp_shelters_box, _tp_traders_box]:
		if box == null:
			continue
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	var in_tutorial: bool = game_data != null and bool(game_data.get("tutorial"))

	for m in _travel.MAPS:
		var map_note := Loc.txt("in the tutorial") if in_tutorial else ""
		var mm := String(m)
		_tp_maps_box.add_child(_tp_row(String(m), map_note, not in_tutorial, func(): _travel.travel_to_map(mm)))

	for s in _travel.SHELTERS:
		var ss := String(s)
		if in_tutorial:
			_tp_shelters_box.add_child(_tp_row(String(s), Loc.txt("in the tutorial"), false, func(): _travel.travel_to_shelter(ss)))
		else:
			_tp_shelters_box.add_child(_tp_row(String(s), "", true, func(): _travel.travel_to_shelter(ss)))

	for t in _travel.TRADERS:
		var entry: Dictionary = t
		var note3 := Loc.txt("in the tutorial") if in_tutorial else ""
		_tp_traders_box.add_child(_tp_row(String(entry["name"]), note3, not in_tutorial, func(): _travel.travel_to_trader(entry)))

	if _tp_head != null:
		_tp_head.text = _tp_section_label(_current_tp_section)
	if _tp_count != null:
		var n := 0
		match _current_tp_section:
			"maps":
				n = _travel.MAPS.size()
			"shelters":
				n = _travel.SHELTERS.size()
			"traders":
				n = _travel.TRADERS.size()
		_tp_count.text = str(n)


func _tp_switch(section: String) -> void:
	_current_tp_section = section
	_tp_maps_box.visible = section == "maps"
	_tp_shelters_box.visible = section == "shelters"
	_tp_traders_box.visible = section == "traders"
	for entry in _tp_section_btns:
		var is_active: bool = entry["key"] == section
		var btn: PanelContainer = entry["btn"]
		btn.add_theme_stylebox_override("panel", _make_tp_section_style(is_active))
		var ind: Panel = entry["ind"]
		if ind != null:
			var ind_s := StyleBoxFlat.new()
			ind_s.bg_color = _gold if is_active else Color("#3a2e20")
			ind_s.corner_radius_all = 1
			ind.add_theme_stylebox_override("panel", ind_s)
	_refresh_teleport_tab()


func _make_tp_section_style(active: bool) -> StyleBox:
	return VTKSurface.surface("normal", active, false, false, 10, 10, 7, 7)


func _make_tp_section_row(key: String, label: String) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_stylebox_override("panel", _make_tp_section_style(false))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	row.add_child(hb)

	var indicator := Panel.new()
	indicator.custom_minimum_size = Vector2(3, 0)
	indicator.size_flags_vertical = Control.SIZE_EXPAND_FILL
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ind_s := StyleBoxFlat.new()
	ind_s.bg_color = Color("#3a2e20")
	ind_s.corner_radius_all = 1
	indicator.add_theme_stylebox_override("panel", ind_s)
	hb.add_child(indicator)

	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#d8cdbe"))
	hb.add_child(lbl)

	var k := key
	row.set_meta("vtk_key", key)
	_attach_motion(row)
	row.gui_input.connect(func(ev: InputEvent):
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_tp_switch(str(row.get_meta("vtk_key"))))
	return row


func _build_teleport_tab(parent: VBoxContainer) -> void:
	_ensure_travel()

	var head := Label.new()
	head.text = Loc.txt("Teleport")
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", _gold)
	parent.add_child(head)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)

	_tp_maps_box = VBoxContainer.new()
	_tp_maps_box.add_theme_constant_override("separation", 4)
	_tp_shelters_box = VBoxContainer.new()
	_tp_shelters_box.add_theme_constant_override("separation", 4)
	_tp_traders_box = VBoxContainer.new()
	_tp_traders_box.add_theme_constant_override("separation", 4)

	var main := VBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 6)

	var main_head := HBoxContainer.new()
	main_head.add_theme_constant_override("separation", 8)
	main.add_child(main_head)
	_tp_head = Label.new()
	_tp_head.add_theme_font_size_override("font_size", 11)
	_tp_head.add_theme_color_override("font_color", _gold)
	_tp_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_head.add_child(_tp_head)
	_tp_count = Label.new()
	_tp_count.add_theme_font_size_override("font_size", 9)
	_tp_count.add_theme_color_override("font_color", Color("#5f5347"))
	_tp_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	main_head.add_child(_tp_count)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 260)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	list.add_child(_tp_maps_box)
	list.add_child(_tp_shelters_box)
	list.add_child(_tp_traders_box)
	main.add_child(scroll)

	var defs := [["maps", Loc.txt("Maps")], ["shelters", Loc.txt("Shelters")], ["traders", Loc.txt("Traders")]]
	for d in defs:
		var row: Control = _make_tp_section_row(d[0], d[1])
		side.add_child(row)
		_tp_section_btns.append({"key": d[0], "btn": row, "ind": row.get_child(0).get_child(0)})

	parent.add_child(_page_columns(Loc.txt("Points"), side, main))
	_tp_switch("maps")
