extends CanvasLayer
const Paths = preload("res://mods/VTK/VTKPaths.gd")
const Log = preload("res://mods/VTK/VTKLog.gd")
const Loc = preload("res://mods/VTK/VTKLoc.gd")
const Draft = preload("res://mods/VTK/VTKDraft.gd")
const Picker = preload("res://mods/VTK/VTKPicker.gd")
const VTKSurface := preload("res://mods/VTK/VTKSurface.gd")
const LD := preload("res://mods/VTK/VTKData.gd")

const UI_LAYER := 4095

var _db_items: Array = []
# resource_path -> Resource. Строки сетов хранят пути, а панели обвесов нужен
# сам Resource: без индекса каждая клетка искала бы его перебором всего
# списка, а раньше просто грузила с диска.
var _item_index: Dictionary = {}
var _equip_cells: Array = []
var _equip_cols := 6
var _equip_rows := 8
var _equip_styles: Dictionary = {}
var _inven_bg_style: StyleBoxFlat
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
# Ширина рейла сетов. Панель на весь экран, поэтому рейл можно не жать:
# карточкам хватает воздуха, а редактор справа всё равно забирает большую
# часть ширины.
const RAIL_WIDTH := 280
var _rail_box: VBoxContainer = null
var _right_box: VBoxContainer = null
var _preview_box: VBoxContainer = null
var _editing_name: String = ""
# Активная карточка рейла: её состав показывает превью справа.
var _selected_set: String = ""
# Захват клавиши для хоткея: _bind_target - имя сохранённого сета (превью),
# _bind_pending - бинд для ещё не сохранённого черновика (страница Готово),
# _pending_qk применится в _save_loadout после replace_set.
var _bind_target: String = ""
var _bind_pending: bool = false
var _bind_btn: Button = null
# Кнопка хоткея на странице Готово: её непустое состояние показываем текстом
# «Назначить клавишу», а не «?». В остальных местах кнопка хоткея - превью сета.
var _done_bind_btn: Button = null
var _pending_qk: int = 0
var _draft: Draft = null
var _name_input: LineEdit = null
# Полосы категорий строятся как VBox из заголовка и HFlow с клетками: у
# GridContainer нет растягивания на всю ширину, а полоса во всю ширину
# нужна, чтобы порядок групп читался сверху вниз.
var _shelves_box: VBoxContainer = null
var _equip_grid_box: VBoxContainer = null
var _target_bar: VBoxContainer = null
var _gear_box: HBoxContainer = null
# Какой панелью обвесов занят каждый шаг: путь своя у Экипировки и
# Снаряжения, оверлей рендерит панель по текущей странице.
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
var _search_debounce: Timer
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
# Пунктирная строка «Только выбранные» в колонке категорий: в сетке
# остаются только предметы, уже лежащие в сете.
var _gear_only_selected: bool = false
var _gear_facet_key: String = ""
# Второй уровень фасетов шага 2: подкатегория внутри выбранной категории.
var _gear_sub_key: String = ""
# Повторный клик по активной категории сворачивает её подкатегории;
# категория при этом остаётся выбранным фильтром.
var _gear_subs_collapsed: bool = false
var _gear_facets_box: VBoxContainer = null
var _gear_grid: GridContainer = null
var _gear_grid_scroll: ScrollContainer = null
# Оверлей обвесов поверх всей вкладки: панель под каталогом при узком окне
# всё равно была бы не видна. Геометрия зеркалит _scroll, тело - подложка
# для панели предмета, шапка с ✕ рисуется при сборке.
var _att_overlay: Control = null
var _att_overlay_body: VBoxContainer = null
var _done_preview: Control = null

# tabs
var _tab_btns: Array = []
var _tab_containers: Dictionary = {}
var _ui_nodes: Array = []
var _current_tab: String = ""

# teleport tab
var _travel: Node = null
var _tp_maps_box: VBoxContainer = null
var _tp_shelters_box: VBoxContainer = null
var _tp_traders_box: VBoxContainer = null

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
var _gold: Color = VTKSurface.GOLD

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
		Log.log("[VTK] MCM migration failed: could not create destination (code " + str(err) + ")")
		return
	var src := DirAccess.open(old_dir)
	if src == null:
		Log.log("[VTK] MCM migration failed: could not open source dir")
		return
	var list_err = src.list_dir_begin()
	if list_err != OK:
		Log.log("[VTK] MCM migration failed: could not list source dir (code " + str(list_err) + ")")
		return
	var fname := src.get_next()
	var copied := 0
	var failed := 0
	while fname != "":
		if not src.current_is_dir() and not fname.begins_with("."):
			var c_err = src.copy_absolute(old_dir + "/" + fname, new_dir + "/" + fname)
			if c_err != OK:
				failed += 1
				Log.log("[VTK] MCM migration: failed to copy " + fname + " (code " + str(c_err) + ")")
			else:
				copied += 1
		fname = src.get_next()
	src.list_dir_end()
	if failed > 0:
		Log.log("[VTK] MCM migration failed: " + str(failed) + " file(s) not copied")
		return
	var r_err = DirAccess.remove_absolute(old_dir)
	if r_err != OK:
		Log.log("[VTK] MCM migration: copied " + str(copied) + " file(s), but failed to remove old dir (code " + str(r_err) + ")")
		return
	Log.log("[VTK] MCM dir migrated: loadouts -> vostok-toolkit (" + str(copied) + " file(s))")

func _init_later() -> void:
	if _late_initialized:
		return
	_late_initialized = true
	_migrate_mcm_dir()
	# Обе миграции - до _load_items и _register_mcm: обеим нужен готовый
	# каталог MCM/vostok-toolkit.
	LD.migrate_save_file()
	game_data = load(Paths.GAME_DATA)
	Log.log("[VTK] Starting UI init")
	_load_items()
	_load_lang()
	_build_ui()
	var Hooks = preload("res://mods/VTK/VTKHooks.gd")
	_hooks = Hooks.new()
	add_child(_hooks)
	_register_mcm()
	Log.log("[VTK] UI init done")

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
		refresh(RefreshScope.PAGES | RefreshScope.LIST | RefreshScope.PREVIEW)
	else:
		get_tree().paused = false
		_self_paused = false
		Input.mouse_mode = _saved_mouse_mode

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Захват идёт первым: Esc и клавиша панели во время захвата
		# отменяют его, а не закрывают панель.
		if _bind_target != "" or _bind_pending:
			_handle_bind_key(event)
			return
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			if visible:
				_set_panel_open(false)
			return
		if _is_toggle_event(event):
			if get_tree().current_scene == null:
				return
			_set_panel_open(not visible)
			return
		if get_viewport().gui_get_focus_control() is LineEdit:
			return
		var kc := int(event.physical_keycode)
		if kc == 0:
			kc = int(event.keycode)
		var qname = LD.get_name_by_quick_key(kc)
		if qname == "" and kc != int(event.keycode):
			qname = LD.get_name_by_quick_key(int(event.keycode))
		if qname != "":
			LD.load_loadout(qname)

func _handle_bind_key(event: InputEventKey) -> void:
	if event.keycode == KEY_ESCAPE:
		_end_bind()
		return
	if _is_toggle_event(event):
		_end_bind()
		return
	var kc := int(event.physical_keycode)
	if kc == 0:
		kc = int(event.keycode)
	if kc == 0:
		return
	if _bind_target != "":
		# Клавиша, занятая другим сетом, забирается: чужой бинд снимается.
		LD.set_quick_key_unique(_bind_target, kc)
		_bind_target = ""
		_bind_btn = null
		refresh(RefreshScope.LIST | RefreshScope.PREVIEW)
	else:
		# Черновик ещё не в файле - бинд копится до сохранения.
		_pending_qk = kc
		_bind_pending = false
		_apply_qk_btn(_bind_btn, kc)
		_bind_btn = null

func _begin_bind(target: String, btn: Button) -> void:
	_bind_target = target
	_bind_pending = false
	_bind_btn = btn
	if btn != null:
		btn.text = Loc.txt("Press a key…")
		btn.add_theme_color_override("font_color", VTKSurface.GREY_DIM)

func _begin_bind_pending(btn: Button) -> void:
	_bind_target = ""
	_bind_pending = true
	_bind_btn = btn
	if btn != null:
		btn.text = Loc.txt("Press a key…")
		btn.add_theme_color_override("font_color", VTKSurface.GREY_DIM)

func _end_bind() -> void:
	var btn := _bind_btn
	var qk := _display_qk()
	if _bind_target != "":
		var pack: Dictionary = LD.get_set(_bind_target)
		qk = int(pack.get("quick_key", 0)) if not pack.is_empty() else 0
	_bind_target = ""
	_bind_pending = false
	_bind_btn = null
	_apply_qk_btn(btn, qk)

# Текст и цвет кнопки хоткея по её состоянию: назначенная клавиша - золотым,
# неназначенная на странице Готово - подписью «Назначить клавишу», в остальных
# местах - прежним «?». Одна точка правды для сборки, захвата клавиши и отмены,
# иначе после смены кнопки где-то остаётся старый текст.
func _apply_qk_btn(btn: Button, qk: int) -> void:
	if btn == null:
		return
	if qk > 0:
		btn.text = _keycode_to_string(qk)
		btn.add_theme_color_override("font_color", _gold)
		VTKSurface.style_button(btn, true)
	elif btn == _done_bind_btn:
		btn.text = Loc.txt("Assign key")
		btn.add_theme_color_override("font_color", Color("#c8bfae"))
		VTKSurface.style_button(btn)
	else:
		btn.text = "?"
		btn.add_theme_color_override("font_color", Color("#444"))
		VTKSurface.style_button(btn)

func _load_items() -> void:
	_db_items.clear()
	_item_index.clear()
	var db = get_node_or_null(Paths.DATABASE)
	if not db:
		return
	if not db.master:
		return
	for item in db.master.items:
		if item and item.name != "":
			_db_items.append(item)
			_item_index[item.resource_path] = item
	_build_equip_layout()

# Раскладка экипировки одна на сессию: набор слотов берётся из всего каталога,
# а каталог меняется только в _load_items. Считаем один раз, а не в каждой
# пересборке сетки/превью.
func _build_equip_layout() -> void:
	var lists: Array = []
	for it in _db_items:
		if it != null:
			lists.append(it.get("slots"))
	var layout := Picker.equip_layout(Picker.all_slots(lists))
	_equip_cells = layout.get("cells", [])
	_equip_cols = int(layout.get("cols", 6))
	_equip_rows = int(layout.get("rows", 8))

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
	# На весь вьюпорт: мастер-деталь (рейл сетов + редактор) тогда тянется
	# по всей ширине окна, и фокус-кнопка ⛶ больше не нужна.
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel_style := VTKSurface.panel(false, 0).duplicate(true)
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

	# КПК-хром: верхний рейл устройства: плашка «V», имя и версия в одну строку.
	# Только имя и версия: бренд-квадрат,
	# текущая вкладка и часы из макета убраны.
	# Отступ сверху не 4, а 24: счётчик убийств - отдельный CanvasLayer слоем
	# 9999 поверх панели, его Label стоит в (10,10), и при верхе 4 имя
	# «VOSTOK TOOLKIT» уходило под счётчик. Рейл и вкладки сдвинуты на ту же
	# величину, чтобы не наехать друг на друга.
	var rail := HBoxContainer.new()
	rail.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rail.offset_left = 4
	rail.offset_top = 24
	rail.offset_right = -4
	rail.offset_bottom = 54
	rail.add_theme_constant_override("separation", 8)
	_panel.add_child(rail)
	_ui_nodes.append(rail)

	var brand := Panel.new()
	brand.custom_minimum_size = Vector2(30, 30)
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bs := StyleBoxFlat.new()
	bs.bg_color = VTKSurface.GOLD
	bs.corner_radius_all = 8
	brand.add_theme_stylebox_override("panel", bs)
	rail.add_child(brand)
	var bv := Label.new()
	bv.text = "V"
	bv.add_theme_font_size_override("font_size", 15)
	bv.add_theme_color_override("font_color", Color("#0e0b08"))
	bv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand.add_child(bv)

	var rname := Label.new()
	rname.text = "VOSTOK TOOLKIT"
	rname.add_theme_font_size_override("font_size", 14)
	rname.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rail.add_child(rname)

	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(fill)

	var rver := Label.new()
	rver.text = "v" + _mod_version()
	rver.add_theme_font_size_override("font_size", 10)
	rver.add_theme_color_override("font_color", VTKSurface.BROWN)
	rver.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rail.add_child(rver)

	# Полоса под рейлом (макет .rail border-bottom): 1px на всю ширину
	# рабочей области (как рейл и вкладки, врезка 4px).
	var rail_sep := ColorRect.new()
	rail_sep.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rail_sep.offset_left = 4
	rail_sep.offset_top = 56
	rail_sep.offset_right = -4
	rail_sep.offset_bottom = 57
	rail_sep.color = Color("#2a2419")
	rail_sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(rail_sep)

	var tab_bar = HBoxContainer.new()
	tab_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tab_bar.offset_left = 4
	tab_bar.offset_top = 58
	tab_bar.offset_right = -4
	tab_bar.offset_bottom = 88
	_panel.add_child(tab_bar)

	var tabs = [Loc.txt("Sets"), Loc.txt("Teleport")]
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
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 4
	_scroll.offset_top = 92
	_scroll.offset_right = -4
	_scroll.offset_bottom = -4
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
	_build_teleport_tab(_tab_containers[Loc.txt("Teleport")])

	_switch_tab(Loc.txt("Sets"))



func _switch_tab(name: String) -> void:
	if _current_tab != "" and _tab_containers.has(_current_tab):
		_tab_containers[_current_tab].hide()
	# Оверлей живёт на _panel, а не в контейнере таба, поэтому прячется сам:
	# при уходе с «Сетов» - скрыть, при возврате - вернуть открытую панель.
	if _att_overlay != null:
		if _current_tab == Loc.txt("Sets") and name != Loc.txt("Sets"):
			_att_overlay.visible = false
	_current_tab = name
	if name == Loc.txt("Teleport"):
		_refresh_teleport_tab()
	if _tab_containers.has(name):
		_tab_containers[name].show()
	if name == Loc.txt("Sets"):
		refresh(RefreshScope.OVERLAY)
	for i in range(_tab_btns.size()):
		var btn = _tab_btns[i] as Button
		var is_active = btn.text == name
		if is_active:
			btn.add_theme_color_override("font_color", _gold)
			btn.add_theme_stylebox_override("normal", _make_tab_active_style())
		else:
			btn.add_theme_color_override("font_color", VTKSurface.GREY)
			btn.add_theme_stylebox_override("normal", _make_tab_style())

# Колонка управления превью/Done: шапка + вертикальный стек кнопок.
# Принимает готовые кнопки (стиль и текст задаёт вызывающий), раскладывает
# их столбиком по центру высоты колонки. Панель тянется по вертикали.
func _make_control_column(title: String, buttons: Array) -> Control:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 6)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 9)
	head.add_theme_color_override("font_color", _gold)
	head.add_theme_constant_override("letter_spacing", 1)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(head)
	var stack := VBoxContainer.new()
	stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.add_theme_constant_override("separation", 4)
	for btn in buttons:
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.add_child(btn)
	panel.add_child(stack)
	return panel

# Общий билдер превью сета: три колонки - экипировка, инвентарь, управление.
# Им же собрана страница Done, чтобы состав везде выглядел одинаково. fill=false
# на странице Done: там превью идёт по содержимому, а строка полей сразу под ним,
# а не прижата к низу на всё окно. controls=null - колонки управления нет.
func _build_set_preview(eq: Dictionary, gear: Array, fill := true, controls: Control = null) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL if fill else Control.SIZE_SHRINK_BEGIN
	row.add_child(_make_equip_preview(eq))
	row.add_child(_make_inventory_panel(gear))
	if controls != null:
		row.add_child(controls)
	return row

# Превью выбранного сета в правой колонке. Схлопывается при открытом
# черновике: правая колонка принадлежит редактору.
func _refresh_preview() -> void:
	if _preview_box == null:
		return
	for child in _preview_box.get_children():
		_preview_box.remove_child(child)
		child.queue_free()
	_preview_box.visible = _draft == null
	if _draft != null:
		return
	var pack: Dictionary = {}
	if _selected_set != "":
		pack = LD.get_set(_selected_set)
	if pack.is_empty():
		_selected_set = ""
		var ph := Label.new()
		ph.text = Loc.txt("Select a set on the left")
		ph.add_theme_font_size_override("font_size", 11)
		ph.add_theme_color_override("font_color", VTKSurface.GREY_DIM)
		_preview_box.add_child(ph)
		return

	var eq_d: Dictionary = pack.get("equip", {})
	var gr_a: Array = pack.get("gear", [])
	var qk := int(pack.get("quick_key", 0))

	var card_head := VBoxContainer.new()
	card_head.add_theme_constant_override("separation", 2)
	var nm := Label.new()
	nm.text = str(pack.get("name", _selected_set))
	nm.add_theme_font_size_override("font_size", 14)
	nm.add_theme_color_override("font_color", VTKSurface.INK)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_head.add_child(nm)
	_preview_box.add_child(card_head)

	# Разделитель под именем сета (макет .card head border-bottom).
	var head_sep := ColorRect.new()
	head_sep.custom_minimum_size = Vector2(0, 1)
	head_sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_sep.color = Color("#2a2419")
	head_sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_box.add_child(head_sep)

	var apply_btn := Button.new()
	apply_btn.text = Loc.txt("Apply")
	VTKSurface.style_button(apply_btn, true)
	apply_btn.pressed.connect(func(): LD.load_loadout(_selected_set))
	var edit_btn := Button.new()
	edit_btn.text = Loc.txt("Edit")
	VTKSurface.style_button(edit_btn)
	edit_btn.pressed.connect(func(): _edit_loadout(_selected_set))
	var qk_btn := Button.new()
	if qk > 0:
		qk_btn.text = _keycode_to_string(qk)
		qk_btn.add_theme_color_override("font_color", _gold)
	else:
		qk_btn.text = "?"
		qk_btn.add_theme_color_override("font_color", Color("#444"))
	VTKSurface.style_button(qk_btn, qk > 0)
	qk_btn.pressed.connect(func(): _begin_bind(_selected_set, qk_btn))
	var del_btn := Button.new()
	del_btn.text = Loc.txt("Delete")
	VTKSurface.style_button(del_btn, false, true)
	del_btn.pressed.connect(func(): _delete_loadout(_selected_set))

	_preview_box.add_child(_build_set_preview(
		eq_d, gr_a, true,
		_make_control_column(Loc.txt("Controls").to_upper(), [apply_btn, edit_btn, qk_btn, del_btn])))

# ============== TAB: Сеты ==============

func _build_loadouts_tab(parent: VBoxContainer) -> void:
	# Рейл и правая колонка - ряд через HBox: сам parent вертикальный (таб),
	# и без ряда обе колонки легли бы друг под другом.
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	# Рейл - та же подложка, что у колонок телепорта/снаряжения: inset-панель
	# с видимым только правым бордюром-разделителем. Без неё список сетов
	# висел бы на общей подложке таба и не читался как отдельная зона.
	var rail_panel := PanelContainer.new()
	rail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rp := VTKSurface.panel(true, 6).duplicate(true)
	rp.border_width_left = 0
	rp.border_width_top = 0
	rp.border_width_bottom = 0
	rp.shadow_color = Color(0, 0, 0, 0)
	rail_panel.add_theme_stylebox_override("panel", rp)
	row.add_child(rail_panel)

	_rail_box = VBoxContainer.new()
	_rail_box.custom_minimum_size = Vector2(RAIL_WIDTH, 0)
	_rail_box.add_theme_constant_override("separation", 6)
	rail_panel.add_child(_rail_box)

	var list_title = Label.new()
	list_title.text = Loc.txt("Saved loadouts")
	list_title.add_theme_font_size_override("font_size", 13)
	list_title.add_theme_color_override("font_color", Color("#ddd"))
	_rail_box.add_child(list_title)

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rail_box.add_child(_list_container)

	_cards_grid = GridContainer.new()
	_cards_grid.columns = 1
	_cards_grid.add_theme_constant_override("h_separation", 6)
	_cards_grid.add_theme_constant_override("v_separation", 6)
	_cards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_child(_cards_grid)

	_right_box = VBoxContainer.new()
	_right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_box.add_theme_constant_override("separation", 6)
	row.add_child(_right_box)

	_preview_box = VBoxContainer.new()
	_preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_box.add_child(_preview_box)

	# Редактор тянется по вертикали, иначе страницы не добирают высоту
	# таба: счётчики EXPAND форсировали только _page_wrap, а сам
	# _editor_panel оставался с флагом по умолчанию.
	_editor_panel = VBoxContainer.new()
	_editor_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_box.add_child(_editor_panel)

	_build_editor()
	refresh(RefreshScope.PREVIEW)

	# Оверлей обвесов живёт на _panel и добавляется после _scroll, чтобы
	# рисоваться поверх вкладки. Геометрия зеркалит _scroll (якоря + отступы
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
	title.add_theme_color_override("font_color", _gold)
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

	_panel.add_child(_att_overlay)

func _build_editor() -> void:
	for child in _editor_panel.get_children():
		_editor_panel.remove_child(child)
		child.queue_free()
	_step_btns = []
	_name_input = null
	# Переключение или закрытие черновика бросает незавершённый захват
	# и не применённый бинд: они относились к прошлому состоянию.
	_bind_target = ""
	_bind_pending = false
	_bind_btn = null
	_done_bind_btn = null
	_pending_qk = 0
	_done_preview = null
	_gear_search_field = null
	_gear_facets_box = null
	_gear_grid = null
	_gear_facet_key = ""
	_gear_grid_scroll = null
	_shelves_box = null
	_equip_grid_box = null
	_gear_box = null
	_page_label = null

	var title_row = HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_theme_constant_override("separation", 4)
	var ed_title = Label.new()
	if _draft != null and _draft.set_name != "":
		ed_title.text = Loc.txt("Editing: ") + _draft.set_name
	else:
		ed_title.text = Loc.txt("Create new loadout")
	ed_title.add_theme_font_size_override("font_size", 12)
	ed_title.add_theme_color_override("font_color", _gold)
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

	_reset_picker_state()
	_show_page(0)
	_editor_panel.visible = _draft != null
	refresh(RefreshScope.PAGES | RefreshScope.PREVIEW)

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
		lab.add_theme_color_override("font_color", _gold if _page == idx else VTKSurface.GREY)
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
	num.add_theme_color_override("font_color", Color("#1a1206") if active else VTKSurface.MUTED)
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
				lab.add_theme_color_override("font_color", _gold if on else VTKSurface.GREY)
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
				chk.visible = i < _page
	# При смене шага оверлей перерисовывается по пути новой страницы:
	# чужая панель закрывается, своя - открывается.
	refresh(RefreshScope.OVERLAY)

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
	_gear_only_selected = false
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
	search.add_theme_color_override("placeholder_color", VTKSurface.GREY_DIM)
	search.add_theme_stylebox_override("normal", VTKSurface.panel(true, 10))
	search.add_theme_stylebox_override("focus", VTKSurface.focus_style())
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(t): _set_search(t))
	if _search_debounce != null and is_instance_valid(_search_debounce):
		_search_debounce.queue_free()
	_search_debounce = Timer.new()
	_search_debounce.one_shot = true
	_search_debounce.wait_time = 0.12
	_search_debounce.timeout.connect(_apply_search)
	add_child(_search_debounce)
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
	var search := LineEdit.new()
	search.placeholder_text = Loc.txt("Search items...")
	search.add_theme_color_override("font_color", Color("#ffffff"))
	search.add_theme_color_override("placeholder_color", VTKSurface.GREY_DIM)
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
	var info := _item_info(path)
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
	if _draft == null:
		return
	if _open_gear_att == path:
		_open_equip_att = ""
		_open_gear_att = ""
	_draft.remove_gear(path)
	refresh(RefreshScope.PAGES)

# compact = true: поля 2/2 вместо 8/8 и шрифт 8 - для рядов клетки шага 2,
# где на всю ширину 96px приходится ещё и счётчик.
func _make_full_mag_btn(path: String, desc: Dictionary, compact := false) -> Button:
	var on := Draft.is_full(desc)
	var b := Button.new()
	b.text = Loc.txt("Full magazine") if on else Loc.txt("Empty")
	b.add_theme_font_size_override("font_size", 8 if compact else 9)
	b.add_theme_color_override("font_color", _gold if on else Color("#777777"))
	if compact:
		VTKSurface.style_button(b, on, false, 2, 2, 2, 2)
	else:
		VTKSurface.style_button(b, on, false, 8, 8, 4, 4)
	b.pressed.connect(func():
		if _draft == null:
			return
		# Состояние берём с актуального descriptor'а, а не с захваченного
		# desc: после пересборки клеток он уже может быть не тем объектом.
		_draft.set_full_mag(path, not Draft.is_full(_draft.descriptor_of(path)))
		refresh(RefreshScope.PAGES)
	)
	return b

func _set_gear_search(t: String) -> void:
	_gear_search = t
	# Только каталог: пересборка страницы пересоздала бы поле поиска и выкинула
	# бы из него курсор на каждом символе.
	refresh(RefreshScope.GEAR)

# Фасеты и сетка считаются одним проходом по списку предметов: facets_of
# фильтрует и группирует его целиком, а считать дважды - значит фильтровать
# дважды.
func _refresh_gear_catalog() -> void:
	var facets: Array = []
	if _draft != null:
		facets = Picker.facets_of(_items_for_gear(), _gear_search)
	_rebuild_gear_facets(facets)
	_rebuild_gear_grid(facets)

# Пунктирная строка «Только выбранные» в колонке фасетов. Как CreateCard:
# штрих рисуется в _draw, Loc передаётся текстом. Внутреннему классу недоступен
# _gold внешнего скрипта, поэтому цвет дублируется константой.
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
		st.bg_color = Color("#1a1510")
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
	# Пунктирная строка «Только выбранные» - в конце списка категорий.
	_gear_facets_box.add_child(ChosenRow.new(_gear_only_selected,
		Loc.txt("Only selected"), func():
			_gear_only_selected = not _gear_only_selected
			refresh(RefreshScope.GEAR)))

# Клик по активной строке сворачивает/разворачивает её подкатегории;
# категория продолжает фильтровать. К возврату ко «Всем предметам» ведёт
# строка «Все предметы»
func _make_facet_row(facet: Dictionary, level: bool) -> Control:
	var key := str(facet.get("key", ""))
	var active := _gear_sub_key == key if level else _gear_facet_key == key
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 28 if level else 31)
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
	hb.add_child(_make_dot(Color("#4a4038") if level else VTKSurface.BROWN))

	var nm := Label.new()
	if key == "":
		nm.text = Loc.txt("All items")
	else:
		nm.text = ("> " if level else "") + Loc.txt(key if level else Picker.category_label(key))
	nm.add_theme_font_size_override("font_size", 10 if level else 11)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.add_theme_color_override("font_color", _gold if active else VTKSurface.INK)
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
	_gear_sub_key = "" if _gear_sub_key == key else key
	refresh(RefreshScope.GEAR)

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
	refresh(RefreshScope.GEAR)

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
	if _gear_only_selected and _draft != null:
		var picked: Array = []
		for e in found:
			var res_it = e.get("item")
			if res_it != null and _draft.has_path(str(res_it.resource_path)):
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
		_gear_grid.add_child(_make_item_cell(res, "", true))

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

	# Карточка трёх колонок состава; имя сета и кнопка хоткея живут в столбце
	# «Управление», как в превью. Узлы создаются один раз и перевешиваются в
	# столбец при каждой пересборке (_refresh_page_done), чтобы не терять текст.
	_name_input = LineEdit.new()
	_name_input.placeholder_text = Loc.txt("Enter a name...")
	_name_input.add_theme_color_override("font_color", Color("#ffffff"))
	_name_input.add_theme_color_override("placeholder_color", VTKSurface.GREY_DIM)
	_name_input.add_theme_stylebox_override("normal", VTKSurface.panel(true, 10))
	_name_input.add_theme_stylebox_override("focus", VTKSurface.focus_style())
	if _draft != null:
		_name_input.text = _draft.set_name

	# Хоткей назначается до сохранения: для нового сета бинд копится в
	# _pending_qk и применяется в _save_loadout.
	_bind_btn = Button.new()
	_done_bind_btn = _bind_btn
	_bind_btn.custom_minimum_size = Vector2(120, 0)
	_bind_btn.add_theme_font_size_override("font_size", 10)
	_apply_qk_btn(_bind_btn, _display_qk())
	_bind_btn.pressed.connect(func(): _begin_bind_pending(_bind_btn))

	_done_preview = _build_set_preview({}, [], false,
		_make_control_column(Loc.txt("Controls").to_upper(), []))
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
	if _done_bind_btn != null and _done_bind_btn.get_parent() != null:
		_done_bind_btn.get_parent().remove_child(_done_bind_btn)
	for child in _done_preview.get_children():
		_done_preview.remove_child(child)
		child.queue_free()
	var save_btn := Button.new()
	save_btn.text = Loc.txt("Save loadout")
	VTKSurface.style_button(save_btn, true)
	save_btn.pressed.connect(_save_loadout)
	var cancel_btn := Button.new()
	cancel_btn.text = Loc.txt("Cancel")
	VTKSurface.style_button(cancel_btn)
	cancel_btn.pressed.connect(_cancel_draft)
	_done_preview.add_child(_build_set_preview(
		_draft.equip if _draft else {},
		_draft.gear if _draft else [],
		false,
		_make_control_column(Loc.txt("Controls").to_upper(),
			[_name_input, _done_bind_btn, save_btn, cancel_btn])))

# Единый вход перерисовки: область задаётся битмаской RefreshScope. Шаг «±»
# не пересобирает экипировку, закрытие обвесов - каталог.
class RefreshScope:
	const EQUIP := 1
	const GEAR := 2
	const DONE := 4
	const OVERLAY := 8
	const LIST := 16
	const PREVIEW := 32
	const PAGES := EQUIP | GEAR | DONE | OVERLAY

func refresh(scope: int) -> void:
	if scope & RefreshScope.EQUIP:
		_refresh_page_equipment()
	if scope & RefreshScope.GEAR:
		_refresh_gear_catalog()
	if scope & RefreshScope.DONE:
		_refresh_page_done()
	if scope & RefreshScope.OVERLAY:
		_refresh_att_overlay()
	if scope & RefreshScope.LIST:
		_refresh_loadout_list()
	if scope & RefreshScope.PREVIEW:
		_refresh_preview()

func _refresh_page_equipment() -> void:
	_rebuild_target_bar()
	_refresh_slots()
	_rebuild_shelves()

func _refresh_slots() -> void:
	if _equip_grid_box == null:
		return
	for child in _equip_grid_box.get_children():
		_equip_grid_box.remove_child(child)
		child.queue_free()
	if _draft == null:
		return
	if _equip_cells.is_empty():
		_build_equip_layout()
	if _equip_cells.is_empty():
		return
	_equip_grid_box.add_child(_make_equip_grid(_equip_cells, _equip_cols, _equip_rows))

# Стиль клетки сетки экипировки: непрозрачная заливка, слот читается как слот, а
# не как ряд фоновых ячеек 1×1. Занятая клетка чуть теплее и с цветом рамки
# предмета, пустая - тёмная с едва заметной рамкой. Активная цель - золото.
func _equip_cell_style(active: bool, hover: bool = false, occupied: bool = false) -> StyleBoxFlat:
	var key := (1 if active else 0) | (2 if hover else 0) | (4 if occupied else 0)
	if _equip_styles.has(key):
		return _equip_styles[key]
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#241d13") if occupied else Color("#1e1a15")
	if active:
		s.bg_color = Color("#2c2417")
	s.set_border_width_all(1)
	s.corner_radius_all = 6
	if active:
		s.border_color = _gold
	elif hover:
		s.border_color = Color("#c9823a")
	elif occupied:
		s.border_color = Color("#8a6a30")
	else:
		s.border_color = Color("#4a443a")
	_equip_styles[key] = s
	return s

# Нужно ли разворачивать иконку предмета в этом слоте. Стволы в Primary/Secondary
# лежат вдоль горизонтали, а слот вытянут по вертикали, поэтому их иконку крутим
# дулом вверх. Пистолеты компактны и читаются как есть - их не трогаем. Правило
# здесь, а не в Picker: ему нужен ресурс слота, а Picker держится чистой логикой.
func _rotates_icon(slot: String, desc: Dictionary) -> bool:
	if slot != "Primary" and slot != "Secondary":
		return false
	var res: Variant = _cell_resource(desc)
	if res == null:
		return false
	var path := str(res.get("resource_path"))
	return Picker.subcategory_of(path, res.get("type")) != "Pistols"

# Клетка слота в укладке: w×h ячеек, занятая показывает иконку предмета, пустая
# (или без иконки) - имя слота. Клик - прежний _on_slot_row_input: выбор цели,
# второй клик по занятой цели открывает панель обвесов.
func _make_equip_cell(slot: String, w: int, h: int, desc: Dictionary = {}, interactive := true) -> Control:
	var src: Dictionary = desc
	if src.is_empty() and interactive:
		if _draft != null:
			var raw = _draft.equip.get(slot)
			if typeof(raw) == TYPE_DICTIONARY:
				src = raw
	var occupied := not src.is_empty()
	var active := interactive and _target_slot == slot
	var box := Panel.new()
	box.custom_minimum_size = Vector2(w * EQ_CELL + (w - 1) * EQ_GAP, h * EQ_CELL + (h - 1) * EQ_GAP)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.clip_contents = true
	box.tooltip_text = str(src.get("name", Loc.txt(slot))) if occupied else Loc.txt(slot)
	box.add_theme_stylebox_override("panel", _equip_cell_style(active, false, occupied))
	if interactive:
		_attach_row_hover(box, func(hv: bool): return _equip_cell_style(active, hv, occupied))
		box.gui_input.connect(func(ev): _on_slot_row_input(ev, slot, src))

	var tex := _item_icon(_cell_resource(src)) if occupied else null
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(center)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = Picker.item_art(tex, _rotates_icon(slot, src))
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

	var dot := _make_dot(_gold if occupied else Color("#2a1f14"))
	box.add_child(dot)
	dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	dot.offset_left = -10
	dot.offset_top = 3
	dot.offset_right = -3
	dot.offset_bottom = 10

	if interactive and occupied:
		var drop := _make_mini_btn("✕", Vector2(16, 16), 8)
		drop.tooltip_text = Loc.txt("Remove")
		drop.add_theme_color_override("font_color", Color("#e05a4a"))
		drop.pressed.connect(func(): _remove_slot(slot))
		box.add_child(drop)
		drop.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		drop.offset_left = 2
		drop.offset_top = 2
		drop.offset_right = 18
		drop.offset_bottom = 18
		# Бейдж количества обвесов на оружии (вариант 2)
		if slot == "Primary" or slot == "Secondary":
			var atts = src.get("attachments")
			var ac := 0
			if typeof(atts) == TYPE_ARRAY:
				ac = atts.size()
			if ac > 0:
				var badge := Label.new()
				badge.text = str(ac)
				badge.add_theme_font_size_override("font_size", 9)
				badge.add_theme_color_override("font_color", Color("#0e0b08"))
				var bsb := StyleBoxFlat.new()
				bsb.bg_color = _gold
				bsb.corner_radius_top_right = 8
				bsb.corner_radius_top_left = 8
				bsb.corner_radius_bottom_right = 8
				bsb.corner_radius_bottom_left = 8
				bsb.content_margin_left = 4
				bsb.content_margin_right = 4
				bsb.content_margin_top = 0
				bsb.content_margin_bottom = 0
				badge.add_theme_stylebox_override("normal", bsb)
				badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
				badge.offset_left = -4
				badge.offset_top = 2
				badge.offset_right = -4
				badge.offset_bottom = 16
				box.add_child(badge)
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
	head.add_theme_color_override("font_color", _gold)
	head.add_theme_constant_override("letter_spacing", 1)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(head)
	# Слоты берём из каталога, как в редакторе (_refresh_slots): превью повторяет
	# укладку целиком, включая пустые клетки, даже если сет занял лишь часть
	# слотов.
	if _equip_cells.is_empty():
		_build_equip_layout()
	var cells: Array = _equip_cells
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
		pad.add_child(_make_equip_grid(cells, _equip_cols, _equip_rows, eq, false))
		panel.add_child(pad)
	return panel

func _wall_item(desc: Dictionary) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(INVEN_CELL, INVEN_CELL)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.tooltip_text = str(desc.get("name", "?"))
	var tex := _item_icon(_cell_resource(desc))
	if tex != null:
		var img := _art_texture_rect(tex, Vector2.ZERO)
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.add_child(img)
		var qty := Draft.shown_count(desc)
		if qty > 1:
			var q := Label.new()
			q.text = "×" + str(qty)
			q.add_theme_font_size_override("font_size", 9)
			q.add_theme_color_override("font_color", _gold)
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
	if _inven_bg_style == null:
		_inven_bg_style = StyleBoxFlat.new()
		_inven_bg_style.bg_color = Color("#14110c")
		_inven_bg_style.corner_radius_all = 3
	for i in range(rows * INVEN_COLS):
		var gc := Panel.new()
		gc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		gc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gc.add_theme_stylebox_override("panel", _inven_bg_style)
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
	ttl.add_theme_color_override("font_color", _gold)
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

# Ресурс предмета слота для иконки. Пустой дескриптор - null.
func _cell_resource(desc: Dictionary) -> Variant:
	return _item_info(str(desc.get("path", ""))).get("resource")

# Клик по строке слота: строка становится целью, а клик по текущей цели с
# предметом открывает панель обвесов. Иначе обвесы пришлось бы искать
# отдельной кнопкой, а в колонке для неё нет места.
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
	lbl.add_theme_color_override("font_color", VTKSurface.BROWN)
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
	reset.add_theme_color_override("font_color", _gold if any_on else VTKSurface.BROWN)
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
	refresh(RefreshScope.EQUIP)

func _set_target_sub(s: String) -> void:
	_target_sub = "" if _target_sub == s else s
	refresh(RefreshScope.EQUIP)

func _reset_target_filters() -> void:
	_target_cat = ""
	_target_sub = ""
	refresh(RefreshScope.EQUIP)

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
	refresh(RefreshScope.PAGES)

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
	refresh(RefreshScope.PAGES)

# Живой поиск с дебаунсом: пересборка идёт не на каждый символ, а через
# короткую паузу. Поле поиска не пересоздаётся и держит курсор.
func _set_search(t: String) -> void:
	_search_text = t
	if _search_debounce != null:
		_search_debounce.start()

func _apply_search() -> void:
	_validate_target_filters()
	refresh(RefreshScope.EQUIP)

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

# Пунктирная карточка «+ Создать сет». StyleBoxFlat штрихов не умеет, а
# штатный компонент рамки убран из вёрстки, поэтому рамка рисуется вручную.
# Loc во внутреннем классе недоступен - текст приходит аргументом.
class CreateCard extends Panel:
	const S := preload("res://mods/VTK/VTKSurface.gd")

	var _action: Callable

	func _init(action: Callable, label: String) -> void:
		_action = action
		custom_minimum_size = Vector2(0, 46)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var st := StyleBoxFlat.new()
		st.bg_color = Color("#141009")
		st.corner_radius_all = 4
		add_theme_stylebox_override("panel", st)
		var l := Label.new()
		l.text = label
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", VTKSurface.MUTED)
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
		S.draw_dashes(self,
			Rect2(Vector2(2, 2), size - Vector2(4, 4)), VTKSurface.BROWN)

func _refresh_loadout_list() -> void:
	for child in _list_container.get_children():
		_list_container.remove_child(child)
		child.queue_free()
	_cards_grid = GridContainer.new()
	_cards_grid.columns = 1
	_cards_grid.add_theme_constant_override("h_separation", 6)
	_cards_grid.add_theme_constant_override("v_separation", 6)
	_cards_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_child(_cards_grid)

	var loadouts = LD.get_all()
	if loadouts.is_empty():
		var empty = Label.new()
		empty.text = Loc.txt("No saved loadouts")
		empty.add_theme_color_override("font_color", VTKSurface.GREY_DIM)
		_list_container.add_child(empty)
		var debug = Label.new()
		debug.text = Loc.txt("file: ") + str(OS.get_user_data_dir()) + "/MCM/vostok-toolkit/VTKsets.json"
		debug.add_theme_font_size_override("font_size", 8)
		debug.add_theme_color_override("font_color", Color("#444"))
		_list_container.add_child(debug)
		_list_container.add_child(CreateCard.new(_start_new_draft, Loc.txt("+ Create loadout")))
		return

	for ld in loadouts:
		if typeof(ld) != TYPE_DICTIONARY:
			continue
		var nm := str(ld.get("name", ""))
		var pack: Dictionary = LD.get_set(nm)
		var active := nm == _selected_set

		# Карточка только выбирает: Apply/Edit/клавиша живут в превью справа,
		# иначе в рейле шириной 236 четыре кнопки не помещаются.
		var card = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.add_theme_stylebox_override("panel", VTKSurface.surface("normal", active, false, active, 12, 12, 11, 11))
		_attach_row_hover(card, func(hv: bool):
			return VTKSurface.surface("hover" if hv else "normal", active, false, active, 12, 12, 11, 11))
		_attach_motion(card)
		card.gui_input.connect(func(ev):
			var mb := ev as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_select_set(nm)
		)

		var box = VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 4)
		card.add_child(box)

		var top = HBoxContainer.new()
		top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_lbl = Label.new()
		name_lbl.text = nm
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(name_lbl)
		var qk := int(ld.get("quick_key", 0))
		if qk > 0:
			var kb = Label.new()
			kb.text = _keycode_to_string(qk)
			kb.add_theme_font_size_override("font_size", 9)
			kb.add_theme_color_override("font_color", _gold)
			kb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			top.add_child(kb)
		box.add_child(top)

		var eq_d: Dictionary = pack.get("equip", {})
		var gr_a: Array = pack.get("gear", [])
		var meta = Label.new()
		meta.text = str(eq_d.size() + gr_a.size()) + Loc.txt(" items · ") + str(eq_d.size()) + Loc.txt(" in equipment")
		meta.add_theme_font_size_override("font_size", 10)
		meta.add_theme_color_override("font_color", VTKSurface.GREY_DIM)
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(meta)

		_cards_grid.add_child(card)

	_list_container.add_child(CreateCard.new(_start_new_draft, Loc.txt("+ Create loadout")))

func _select_set(nm: String) -> void:
	_selected_set = nm
	# Клик по сету при открытом редакторе закрывает черновик и открывает
	# превью: правки не сохранённого черновика теряются, без диалога.
	if _draft != null:
		_cancel_draft()
	else:
		refresh(RefreshScope.LIST | RefreshScope.PREVIEW)

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
	refresh(RefreshScope.GEAR | RefreshScope.DONE)

func _toggle_attachment_panel(path: String) -> void:
	if _page == 1:
		_open_gear_att = "" if _open_gear_att == path else path
	else:
		_open_equip_att = "" if _open_equip_att == path else path
	refresh(RefreshScope.OVERLAY)

# Оверлей рендерит панель текущей страницы: путь своя у Экипировки и
# Снаряжения; при пустом пути или закрытом черновике прячется.
func _refresh_att_overlay() -> void:
	if _att_overlay == null or _att_overlay_body == null:
		return
	for child in _att_overlay_body.get_children():
		_att_overlay_body.remove_child(child)
		child.queue_free()
	var path := _open_gear_att if _page == 1 else _open_equip_att
	if _draft == null or path == "":
		_att_overlay.visible = false
		return
	var panel := _build_att_panel(path)
	if panel == null:
		_att_overlay.visible = false
		return
	_att_overlay_body.add_child(panel)
	_att_overlay.visible = true

func _close_att_overlay() -> void:
	_open_equip_att = ""
	_open_gear_att = ""
	refresh(RefreshScope.OVERLAY)

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

func _make_item_cell(item, forced_slot = null, gear := false) -> Control:
	var path_now: String = item.resource_path
	var gi := _draft.gear_index_of(path_now) if (gear and _draft != null) else -1
	var cell = Panel.new()
	# Клетка снаряжения выше и шире: под именем два ряда - счётчик с
	# обвесами и крупные «− n +»; ✕ живёт в углу. Каталог шага 1 остаётся
	# ниже - там под именем только счётчик.
	# Ширина берётся из GEAR_CELL_W: расчёт колонок обязан совпадать с
	# вёрсткой, иначе сетка переполняется и появляется прокрутка.
	cell.custom_minimum_size = Vector2(GEAR_CELL_W, 176 if gi >= 0 else (168 if gear else 152))
	# Без SIZE_EXPAND_FILL: HFlowContainer растягивает такие клетки на всю
	# ширину полосы, пока предметов мало (stretch в flow_container.cpp).
	cell.mouse_filter = Control.MOUSE_FILTER_STOP

	var normal_style := VTKSurface.surface("normal")
	var hover_style := VTKSurface.surface("hover")
	var in_set_style := VTKSurface.surface("normal", true, false, true)

	cell.add_theme_stylebox_override("panel", normal_style)

	var vbox := _icon_stack(cell, _item_icon(item), Vector2(GEAR_CELL_W - 32, 56),
		str(item.name), 9, Color("#aaa"), 2)

	var already := _draft != null and _draft.has_path(path_now)
	if already and not gear:
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

	if gear and _draft != null and gi >= 0:
		cell.add_theme_stylebox_override("panel", in_set_style)
		var desc_g: Dictionary = _draft.gear[gi]
		var cnt_g := Draft.shown_count(desc_g)

		# Ряд А: счётчик и обвесы. У обоймы - тумблер полной обоймы,
		# у остальных с панелью - кнопка rnd (открывает панель обвесов).
		var crow := HBoxContainer.new()
		crow.add_theme_constant_override("separation", 3)
		crow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var xl := Label.new()
		xl.text = "×" + str(cnt_g)
		xl.add_theme_font_size_override("font_size", 8)
		xl.add_theme_color_override("font_color", _gold)
		xl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		xl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		xl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crow.add_child(xl)
		if _is_magazine(path_now):
			var mag_btn := _make_full_mag_btn(path_now, desc_g, true)
			crow.add_child(mag_btn)
		elif _att_panel_needed(_item_info(path_now)):
			crow.add_child(_make_att_btn(desc_g))
		vbox.add_child(crow)

		# Ряд Б: минус, счётчик, плюс. Основное управление клетки, поэтому
		# крупнее прежних микро-кнопок 15×16.
		var brow := HBoxContainer.new()
		brow.add_theme_constant_override("separation", 4)
		brow.alignment = BoxContainer.ALIGNMENT_CENTER
		brow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var minus := _make_mini_btn("−", Vector2(28, 28), 15)
		minus.pressed.connect(func(): _bump_gear(path_now, -1.0))
		brow.add_child(minus)
		var cl := Label.new()
		cl.text = str(cnt_g)
		cl.add_theme_font_size_override("font_size", 13)
		cl.custom_minimum_size = Vector2(30, 0)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		brow.add_child(cl)
		var plus := _make_mini_btn("+", Vector2(28, 28), 15)
		plus.pressed.connect(func(): _bump_gear(path_now, 1.0))
		brow.add_child(plus)
		vbox.add_child(brow)

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
	# тем же _place_into (Draft.add).
	var slot := _target_slot if forced_slot == null else str(forced_slot)
	cell.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_place_into(it, slot)
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
			and _att_panel_needed(_item_info(_last_placed)):
		if _page == 1:
			_open_gear_att = _last_placed
		else:
			_open_equip_att = _last_placed
	_last_placed = ""
	refresh(RefreshScope.PAGES)

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
	if not _att_panel_needed(_item_info(path)):
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
	var picked := VTKSurface.surface("normal", true, false, false)

	cell.add_theme_stylebox_override("panel", picked if on else normal)
	_attach_motion(cell)

	_icon_stack(cell, _item_icon(att_res), Vector2(84, 48),
		str(att_res.name), 9, _gold if on else Color("#aaa"), 2)

	cell.tooltip_text = str(att_res.name) + "\n" + str(att_res.resource_path)
	cell.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if _draft == null:
				return
			_draft.toggle_attachment(owner_path, str(att_res.resource_path), grp, _att_group_of)
			# Панель остаётся открытой: подбор обвесов идёт списком, и закрывать
			# её после каждого клика значило бы кликать дважды на каждый обвес.
			refresh(RefreshScope.PAGES)
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
		refresh(RefreshScope.PAGES)
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
	cap_lbl.add_theme_color_override("font_color", VTKSurface.GREY_DIM)
	row.add_child(cap_lbl)
	return panel

# ============== HUD / LANGUAGE ==============

var _kc_node: Control = null
var _hooks: Node = null
var _nvg_node: Node = null
var _kc_mcm: bool = true
var _feed_mcm: bool = true
var _hud_canvas = null
var _feed_node = null
var _thermal_active: bool = false
var _mines_active: bool = true

func _load_lang() -> void:
	Loc.set_lang(Loc.DEFAULT)
	var cf := ConfigFile.new()
	if cf.load("user://MCM/vostok-toolkit/config.ini") != OK:
		return
	var d = cf.get_value("Dropdown", "language", {})
	if typeof(d) == TYPE_DICTIONARY:
		Loc.set_lang(str(d.get("value", Loc.DEFAULT)))

func _clear_ui() -> void:
	for n in _ui_nodes:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_ui_nodes.clear()
	_tab_btns.clear()
	_tab_containers.clear()
	_scroll = null
	_panel = null

# Пересборка UI на месте после смены языка. Активную вкладку восстанавливаем
# по позиции: _current_tab хранит локализованную строку, а после перевода
# имена вкладок меняются и по имени прежний ключ не находится.
func _rebuild_ui() -> void:
	var idx := -1
	for i in range(_tab_btns.size()):
		if (_tab_btns[i] as Button).text == _current_tab:
			idx = i
			break
	_clear_ui()
	_build_ui()
	if idx >= 0 and idx < _tab_btns.size():
		_switch_tab((_tab_btns[idx] as Button).text)

# Единая точка применения обоих HUD-виджетов. Зовётся только из _mcm_apply:
# состояние приходит из MCM, отдельного UI-тумблера больше нет.
func _apply_hud() -> void:
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
	refresh(RefreshScope.LIST | RefreshScope.PREVIEW)

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
	if _pending_qk != 0:
		LD.set_quick_key_unique(name_new, _pending_qk)
		_pending_qk = 0
		_apply_qk_btn(_bind_btn, int(LD.get_set(name_new).get("quick_key", 0)))
	_draft.set_name = name_new
	_editing_name = name_new
	_clear_problem()
	refresh(RefreshScope.LIST | RefreshScope.PREVIEW)

func _edit_loadout(name: String) -> void:
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
	LD.remove(name)
	if _editing_name == name:
		_cancel_draft()
	else:
		refresh(RefreshScope.LIST | RefreshScope.PREVIEW)

# Бинд, который показывает кнопка на странице Готово: нажатый в захвате,
# если он есть, иначе сохранённый у редактируемого сета.
func _display_qk() -> int:
	if _pending_qk > 0:
		return _pending_qk
	if _editing_name != "":
		var pack: Dictionary = LD.get_set(_editing_name)
		if not pack.is_empty():
			return int(pack.get("quick_key", 0))
	return 0

static func _keycode_to_string(kc: int) -> String:
	if kc <= 0:
		return "?"
	return OS.get_keycode_string(kc)

func _register_mcm() -> void:
	if not ResourceLoader.exists("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres"):
		_apply_hud()
		return
	var MCM = load("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres")
	if MCM == null or not MCM.has_method("RegisterConfiguration"):
		return
	var cfg = ConfigFile.new()
	var CAT := "01. General"
	cfg.set_value("Keycode", "key_ui_toggle", {"name": "Hotkey: Toggle UI", "default": 0, "default_type": "Keycode", "value": 0, "category": CAT, "menu_pos": 0, "tooltip": "Press once to open/close the Loadouts UI."})
	cfg.set_value("Dropdown", "language", {"name": "Language", "default": Loc.DEFAULT, "value": Loc.get_lang(), "options": {"en": "English", "ru": "Русский"}, "category": CAT, "menu_pos": 1, "tooltip": "Interface language of the Loadouts window. English is the source language."})
	cfg.set_value("Bool", "auto_equip", {"name": "Auto-equip on pickup", "default": true, "value": true, "category": CAT, "menu_pos": 2, "tooltip": "When a picked-up item fits an empty equipment slot it is equipped right away. Stackables top up an already equipped stack; loading a save or starting a new game is left untouched."})
	var TP := "02. ThermalVision"
	cfg.set_value("Bool", "thermal_enabled", {"name": "Thermal vision", "default": false, "value": false, "category": TP, "menu_pos": 0, "tooltip": "Master switch for the thermal vision layer: bot heat glow, mines and the Nomad marker. Plain green NVG is unaffected while this is off."})
	cfg.set_value("Bool", "thermal_mines", {"name": "Mine highlighting", "default": true, "value": true, "category": TP, "menu_pos": 1, "tooltip": "Highlight mines while thermal vision is on."})
	cfg.set_value("Bool", "thermal_mark_nomads", {"name": "Mark friendly Nomads", "default": true, "value": true, "category": TP, "menu_pos": 2, "tooltip": "Draw a floating green marker over friendly Nomads so they are not shot by accident."})
	cfg.set_value("Bool", "thermal_winter_auto", {"name": "Winter auto-dimming", "default": true, "value": true, "category": TP, "menu_pos": 3, "tooltip": "In winter (season 2) snow blows the thermal image out; dim the world so bots stay readable."})
	cfg.set_value("Float", "thermal_winter_dim", {"name": "Winter dimming", "default": 0.55, "value": 0.55, "minRange": 0.2, "maxRange": 1.0, "step": 0.05, "category": TP, "menu_pos": 4, "tooltip": "Multiplier applied to world brightness while winter auto-dimming is active. Lower means darker snow."})
	cfg.set_value("Float", "nvg_noise", {"name": "NVG noise", "default": 4.0, "value": 4.0, "minRange": 0.0, "maxRange": 60.0, "step": 0.5, "category": TP, "menu_pos": 5, "tooltip": "Grain amount over the NVG image. Lower is cleaner. Vanilla is fixed at 10."})
	cfg.set_value("Float", "nvg_white", {"default": 1.0, "value": 1.0, "minRange": 0.05, "maxRange": 1.0, "step": 0.05, "category": TP, "menu_pos": 6, "tooltip": "Brightness of the NVG image. 1 = full brightness; lower darkens the whole overlay (helps cut shimmer in bright scenes).", "name": "NVG brightness"})
	cfg.set_value("Int", "thermal_palette", {"default": 0, "value": 0, "minRange": 0, "maxRange": 5, "step": 1, "category": TP, "menu_pos": 7, "tooltip": "0 = Classic, 1 = White Hot (grey), 2 = Black Hot (inverted grey), 3 = Amber, 4 = Forest, 5 = Ice.", "name": "World palette"})
	cfg.set_value("Float", "thermal_world", {"default": 1.70, "value": 1.70, "minRange": 1.0, "maxRange": 4.0, "step": 0.05, "category": TP, "menu_pos": 8, "tooltip": "How bright the surrounding world reads in thermal.", "name": "World brightness"})
	cfg.set_value("Int", "thermal_bot_preset", {"default": 0, "value": 0, "minRange": 0, "maxRange": 3, "step": 1, "category": TP, "menu_pos": 9, "tooltip": "0 = Amber, 1 = White, 2 = Orange, 3 = Red. Living bots glow in this colour; a corpse cools from the head down before disappearing.", "name": "Bot colour"})
	cfg.set_value("Float", "thermal_far_distance", {"default": 45.0, "value": 45.0, "minRange": 5.0, "maxRange": 300.0, "step": 5.0, "category": TP, "menu_pos": 10, "tooltip": "Bots and mines only glow within this distance; past it they read as ordinary scenery. 5 = only right beside you, 300 = the whole map.", "name": "Distance"})
	var TR := "03. Travel"
	cfg.set_value("Bool", "tp_unlocked_shelters_only", {"name": "Unlocked shelters only", "default": false, "value": false, "category": TR, "menu_pos": 0, "tooltip": "When enabled, teleporting to a locked shelter is refused."})
	var KF := "04. KillFeed"
	cfg.set_value("Bool", "kill_counter_enabled", {"name": "Kill counter", "default": true, "value": true, "category": KF, "menu_pos": 0, "tooltip": "Show the kill counter HUD line (Killed / Enemies / Nomads)."})
	cfg.set_value("Bool", "kill_feed_enabled", {"name": "Kill feed", "default": true, "value": true, "category": KF, "menu_pos": 1, "tooltip": "Show the kill feed under the counter: killer, weapon/headshot icons, victim."})
	var DBG := "05. Debug"
	cfg.set_value("Bool", "debug_log", {"name": "Mod debug log", "default": false, "value": false, "category": DBG, "menu_pos": 0, "tooltip": "Print mod diagnostics (item resolution, hooks, teleports, saves) to the game log. Off during normal play; turn on only to troubleshoot."})
	cfg.set_value("Bool", "nvg_debug_probe", {"name": "NVG probe log", "default": false, "value": false, "category": DBG, "menu_pos": 1, "tooltip": "Write NVG/thermal probes to user://loadouts_debug.log and enable the F4 detection overlay. Leave off during normal play; turn on only to diagnose something."})
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
	# Единственный источник версии - version.txt, который пишет pack.ps1.
	# res://mod.txt не читаем: он общий для всех модов и в заголовке может
	# оказаться чужая версия.
	var vf = FileAccess.open("res://mods/VTK/version.txt", FileAccess.READ)
	if vf == null:
		return "unknown"
	var v := vf.get_as_text().strip_edges()
	vf.close()
	return v if v != "" else "unknown"

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
	var want := str(_mcm_key_val(cfg, "Dropdown", "language", Loc.get_lang()))
	if want != Loc.get_lang():
		Loc.set_lang(want)
		if Loc.get_lang() == want:
			_rebuild_ui()
	_key_ui_toggle = int(_mcm_key_val(cfg, "Keycode", "key_ui_toggle", 0))
	Log.enabled = bool(_mcm_key_val(cfg, "Bool", "debug_log", false))
	_kc_mcm = bool(_mcm_key_val(cfg, "Bool", "kill_counter_enabled", true))
	_feed_mcm = bool(_mcm_key_val(cfg, "Bool", "kill_feed_enabled", true))
	_apply_hud()
	if _hooks != null and is_instance_valid(_hooks):
		_hooks.set_equip_enabled(bool(_mcm_key_val(cfg, "Bool", "auto_equip", true)))
		_hooks.set_equip_debug(bool(_mcm_key_val(cfg, "Bool", "nvg_debug_probe", false)))
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
	_nvg_node.set_debug_probe = bool(_mcm_key_val(cfg, "Bool", "nvg_debug_probe", false))
	_nvg_node.set_mark_nomads = bool(_mcm_key_val(cfg, "Bool", "thermal_mark_nomads", true))
	_nvg_node.set_winter_auto = bool(_mcm_key_val(cfg, "Bool", "thermal_winter_auto", true))
	_nvg_node.set_winter_dim = float(_mcm_key_val(cfg, "Float", "thermal_winter_dim", 0.55))
	_nvg_node.set_bot_preset = int(_mcm_key_val(cfg, "Int", "thermal_bot_preset", 0))
	_nvg_node.set_far_distance = float(_mcm_key_val(cfg, "Float", "thermal_far_distance", 45.0))
	_nvg_node.apply_debug_probe()
	# Mines/thermal moved out of the Settings tab into MCM; read them here.
	_thermal_active = bool(_mcm_key_val(cfg, "Bool", "thermal_enabled", false))
	_mines_active = bool(_mcm_key_val(cfg, "Bool", "thermal_mines", true))
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
	nm.add_theme_color_override("font_color", VTKSurface.INK if enabled else Color("#4d443a"))
	hb.add_child(nm)

	if note != "":
		var nt := Label.new()
		nt.text = note
		nt.add_theme_font_size_override("font_size", 9)
		nt.add_theme_color_override("font_color", VTKSurface.BROWN)
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

func _make_tp_column(title: String, count: int, box: VBoxContainer) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", VTKSurface.surface("normal", false, false, false, 10, 10, 7, 7))

	var col := VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)

	var nm := Label.new()
	nm.text = title.to_upper()
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.add_theme_font_size_override("font_size", 11)
	nm.add_theme_color_override("font_color", _gold)
	head.add_child(nm)

	var cnt := Label.new()
	cnt.text = str(count)
	cnt.add_theme_font_size_override("font_size", 9)
	cnt.add_theme_color_override("font_color", VTKSurface.BROWN)
	cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(cnt)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	col.add_child(scroll)
	return card


func _build_teleport_tab(parent: VBoxContainer) -> void:
	_ensure_travel()

	var head := Label.new()
	head.text = Loc.txt("Teleport")
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", _gold)
	parent.add_child(head)

	_tp_maps_box = VBoxContainer.new()
	_tp_maps_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tp_maps_box.add_theme_constant_override("separation", 4)
	_tp_shelters_box = VBoxContainer.new()
	_tp_shelters_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tp_shelters_box.add_theme_constant_override("separation", 4)
	_tp_traders_box = VBoxContainer.new()
	_tp_traders_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tp_traders_box.add_theme_constant_override("separation", 4)

	var n_maps := 0
	var n_shelters := 0
	var n_traders := 0
	if _travel != null and is_instance_valid(_travel):
		n_maps = _travel.MAPS.size()
		n_shelters = _travel.SHELTERS.size()
		n_traders = _travel.TRADERS.size()

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	row.add_child(_make_tp_column(_tp_section_label("maps"), n_maps, _tp_maps_box))
	row.add_child(_make_tp_column(_tp_section_label("shelters"), n_shelters, _tp_shelters_box))
	row.add_child(_make_tp_column(_tp_section_label("traders"), n_traders, _tp_traders_box))
	parent.add_child(row)

	_refresh_teleport_tab()
