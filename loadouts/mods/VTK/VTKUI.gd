extends CanvasLayer
const Paths = preload("res://mods/VTK/VTKPaths.gd")
const Log = preload("res://mods/VTK/VTKLog.gd")
const Loc = preload("res://mods/VTK/VTKLoc.gd")
const Draft = preload("res://mods/VTK/VTKDraft.gd")
const Picker = preload("res://mods/VTK/VTKPicker.gd")
const VTKSurface := preload("res://mods/VTK/VTKSurface.gd")
const LD := preload("res://mods/VTK/VTKData.gd")
const Items := preload("res://mods/VTK/VTKItemStore.gd")
const TeleportTab := preload("res://mods/VTK/VTKTeleportTab.gd")
const Features := preload("res://mods/VTK/VTKFeatureHost.gd")
const MCMBridge := preload("res://mods/VTK/VTKMCMBridge.gd")
const SetsRail := preload("res://mods/VTK/VTKSetsRail.gd")
const Session := preload("res://mods/VTK/VTKLoadoutSession.gd")
const Editor := preload("res://mods/VTK/VTKEditor.gd")

const UI_LAYER := 4095

# New Game locks the Dynamic season behind an early-access gate (the Select
# button ships disabled with the text "Locked"). The menu scene is rebuilt on
# every visit, so the button is polled and unlocked instead of touched once.
const MENU_POLL := 0.4
const MENU_DYNAMIC_SELECT := "Modes/Season/Dynamic/Select"

# Каталог предметов (список, индекс resource_path, кеши info и иконок) живёт в
# VTKItemStore: сюда он попадает через _load_items, а читается отсюда Items.*.
var _equip_cells: Array = []
var _equip_cols := 6
var _equip_rows := 8
var _equip_styles: Dictionary = {}
var _inven_bg_style: StyleBoxFlat
var _panel: Panel = null
var _scroll: ScrollContainer = null
var _main_vbox: VBoxContainer = null

# loadouts tab: рейл, выбор сета, хоткей и превью живут в VTKSetsRail,
# редактор черновика - в VTKEditor.
var _rail: RefCounted = null
var _session: RefCounted = null
var _editor: RefCounted = null

# tabs
var _tab_btns: Array = []
var _tab_containers: Dictionary = {}
var _ui_nodes: Array = []
var _current_tab: String = ""

# teleport tab
var _tp_tab: RefCounted = null

var game_data: Resource = null

# ui
var _gold: Color = VTKSurface.GOLD

var _key_ui_toggle: int = 0
var _panel_open: bool = false
var _saved_mouse_mode: int = Input.MOUSE_MODE_CAPTURED
var _self_paused: bool = false
var _scene_ref: Node = null
var _menu_poll := 0.0

func _process(delta: float) -> void:
	_menu_poll += delta
	if _menu_poll >= MENU_POLL:
		_menu_poll = 0.0
		_unlock_dynamic_menu()
	var scene = get_tree().current_scene
	if scene != _scene_ref:
		_scene_ref = scene
		if _panel_open:
			set_panel_open(false)
		return
	if visible and not get_tree().paused:
		_self_paused = true
		get_tree().paused = true
	elif not visible and get_tree().paused and _self_paused:
		_self_paused = false
		get_tree().paused = false

# Меню игры - не наш узел, поэтому путь берётся у current_scene и глушится
# get_node_or_null: вне меню узла нет, ветка молча выходит.
func _unlock_dynamic_menu() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	var sel := scene.get_node_or_null(MENU_DYNAMIC_SELECT) as Button
	if sel == null:
		return
	if sel.disabled:
		sel.disabled = false
	if sel.text == "Locked":
		sel.text = "Select"

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
	# Обе миграции - до _load_items и регистрации в MCM: обеим нужен готовый
	# каталог MCM/vostok-toolkit.
	LD.migrate_save_file()
	game_data = load(Paths.GAME_DATA)
	Log.log("[VTK] Starting UI init")
	_load_items()
	_mcm = MCMBridge.new()
	_mcm.load_lang()
	# Хост до _build_ui: вкладка телепорта берёт у него узел travel.
	_features = Features.new(self)
	# Рейл до _build_ui: вкладка «Сеты» строится его builders.
	_rail = SetsRail.new(self)
	_rail.refresh_rail = Callable(self, "_refresh_rail")
	_session = Session.new()
	_editor = Editor.new(self)
	_build_ui()
	_features._ensure_hooks()
	_mcm.register(_features, Callable(self, "_rebuild_ui"), Callable(self, "_set_key_ui_toggle"))
	Log.log("[VTK] UI init done")

func _set_key_ui_toggle(v: int) -> void:
	_key_ui_toggle = v

# Перерисовка рейла и превью одним заходом: этим Callable VTKSetsRail
# обновляет список сетов и превью после выбора/бинда.
func _refresh_rail() -> void:
	refresh(RefreshScope.LIST | RefreshScope.PREVIEW)

func _is_toggle_event(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	if InputMap.has_action("key_ui_toggle") and event.is_action_pressed("key_ui_toggle"):
		return true
	if _key_ui_toggle == 0:
		return false
	return event.keycode == _key_ui_toggle or event.physical_keycode == _key_ui_toggle

func set_panel_open(open: bool) -> void:
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
	if _rail == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# Захват идёт первым: Esc и клавиша панели во время захвата
		# отменяют его, а не закрывают панель.
		if _rail._bind_target != "" or _rail._bind_pending:
			_rail._handle_bind_key(event)
			return
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			if visible:
				set_panel_open(false)
			return
		if _is_toggle_event(event):
			if get_tree().current_scene == null:
				return
			set_panel_open(not visible)
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

func _load_items() -> void:
	# Чистка до чтения базы: при отказе Database каталог остаётся пустым, как и
	# раньше, когда эти три строки жили здесь.
	Items.clear()
	var db = get_node_or_null(Paths.DATABASE)
	if not db:
		Log.warn_once(Paths.DATABASE, "item catalog: Database node missing")
		return
	if not db.master:
		Log.warn_once(Paths.DATABASE + "/master", "item catalog: Database.master missing")
		return
	Items.rebuild(db.master.items)
	_build_equip_layout()

# Раскладка экипировки одна на сессию: набор слотов берётся из всего каталога,
# а каталог меняется только в _load_items. Считаем один раз, а не в каждой
# пересборке сетки/превью.
func _build_equip_layout() -> void:
	var lists: Array = []
	for it in Items.all():
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
	# Один Tween на клетку: пока он жив (ещё доворачивает предыдущий hover),
	# перезапускаем его вместо свежего create_tween. Готовый или убитый заводим заново.
	var tw: Tween = null
	if c.has_meta("vtk_tween"):
		var old: Tween = c.get_meta("vtk_tween")
		if old != null and old.is_valid():
			old.stop()
			tw = old
		elif old != null:
			old.kill()
	if tw == null:
		tw = create_tween()
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
	# Отступ сверху не 4, а 34: счётчик убийств - отдельный CanvasLayer слоем
	# 9999 поверх панели, его Label стоит в (10,10) шрифтом 13 и опускается до
	# y≈28, и при меньшем верхе имя «VOSTOK TOOLKIT» уходило под счётчик.
	# Рейл и вкладки сдвинуты на ту же величину, чтобы не наехать друг на друга.
	var rail := HBoxContainer.new()
	rail.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rail.offset_left = 4
	rail.offset_top = 34
	rail.offset_right = -4
	rail.offset_bottom = 64
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
	rver.text = "v" + _mcm.version()
	rver.add_theme_font_size_override("font_size", 10)
	rver.add_theme_color_override("font_color", VTKSurface.BROWN)
	rver.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rail.add_child(rver)

	# Полоса под рейлом (макет .rail border-bottom): 1px на всю ширину
	# рабочей области (как рейл и вкладки, врезка 4px).
	var rail_sep := ColorRect.new()
	rail_sep.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rail_sep.offset_left = 4
	rail_sep.offset_top = 66
	rail_sep.offset_right = -4
	rail_sep.offset_bottom = 67
	rail_sep.color = Color("#2a2419")
	rail_sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(rail_sep)

	var tab_bar = HBoxContainer.new()
	tab_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tab_bar.offset_left = 4
	tab_bar.offset_top = 68
	tab_bar.offset_right = -4
	tab_bar.offset_bottom = 98
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
	_scroll.offset_top = 102
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

	_build_sets_pane()
	_features._ensure_travel()
	_tp_tab = TeleportTab.new()
	_tp_tab.hover = Callable(self, "_attach_row_hover")
	_tp_tab.motion = Callable(self, "_attach_motion")
	_tp_tab._build_teleport_tab(_tab_containers[Loc.txt("Teleport")], _features.travel(), game_data)

	_switch_tab(Loc.txt("Sets"))



func _switch_tab(name: String) -> void:
	if _current_tab != "" and _tab_containers.has(_current_tab):
		_tab_containers[_current_tab].hide()
	# Оверлей живёт на _panel, а не в контейнере таба, поэтому прячется сам:
	# при уходе с «Сетов» - скрыть, при возврате - вернуть открытую панель.
	if _editor._att_overlay != null:
		if _current_tab == Loc.txt("Sets") and name != Loc.txt("Sets"):
			_editor._att_overlay.visible = false
	_current_tab = name
	if name == Loc.txt("Teleport"):
		_features._ensure_travel()
		if _tp_tab != null:
			_tp_tab._refresh_teleport_tab(_features.travel(), game_data)
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

# ============== TAB: Сеты ==============

func _build_sets_pane() -> void:
	_rail._build_loadouts_tab(_tab_containers[Loc.txt("Sets")])
	_editor.build(_rail._right_box)
	_rail._refresh_preview()

# Общий ховер строк со StyleBoxFlat: макит стиль по hover-флагу, активная
# строка ховер не перебивает. Строки пересобираются часто, обработчики
# умирают вместе со строкой, поэтому новые каждый раз безопасны.
func _attach_row_hover(row: Control, make_style: Callable) -> void:
	row.mouse_entered.connect(func():
		row.add_theme_stylebox_override("panel", make_style.call(true)))
	row.mouse_exited.connect(func():
		row.add_theme_stylebox_override("panel", make_style.call(false)))

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
		_editor._refresh_page_equipment()
	if scope & RefreshScope.GEAR:
		_editor._refresh_gear_catalog()
	if scope & RefreshScope.DONE:
		_editor._refresh_page_done()
	if scope & RefreshScope.OVERLAY:
		_editor._refresh_att_overlay()
	if scope & RefreshScope.LIST:
		_rail._refresh_loadout_list()
	if scope & RefreshScope.PREVIEW:
		_rail._refresh_preview()

# Сведения о предмете по пути - тонкий форвардер на VTKItemStore: сам каталог,
# кеши и дисковая ветка живут там, а здесь имя держит ~15 внутренних вызовов.
func _item_info(path: String) -> Dictionary:
	return Items.item_info(path)

# Иконка предмета - форвардер на VTKItemStore. VTKFeed ходит сюда же через
# ui.call("_item_icon", item), поэтому имя на VTKUI обязано остаться.
func _item_icon(res) -> Texture2D:
	return Items.item_icon(res)

# ============== FEATURES / MCM ==============

var _features: RefCounted = null
var _mcm: RefCounted = null

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

# ============== SAVE / LOAD / DELETE ==============

func _start_new_draft() -> void:
	_session.new_draft()
	_rail._editing_name = ""
	_editor._build_editor()

func _cancel_draft() -> void:
	_session.clear_draft()
	_rail._editing_name = ""
	_editor._build_editor()
	refresh(RefreshScope.LIST | RefreshScope.PREVIEW)

func _save_loadout() -> void:
	if _session.draft == null:
		return
	if _editor._name_input != null:
		_session.draft.set_name = _editor._name_input.text.strip_edges()
	var name_new: String = _session.draft.set_name.strip_edges()
	# Отказы сообщаем в том же ряду, где живут шаги: раньше пустой ввод и
	# пустой сет просто ничего не делали, и пользователь не понимал, почему
	# кнопка молчит.
	if name_new == "":
		_editor._set_problem(Loc.txt("Loadout name required"))
		return
	if _session.draft.item_count() == 0:
		_editor._set_problem(Loc.txt("Set is empty"))
		return
	var all = LD.get_all()
	for ld in all:
		if str(ld.get("name")) == name_new and name_new != _rail._editing_name:
			_editor._set_problem(Loc.txt("Name already taken!"))
			if _editor._name_input != null:
				_editor._name_input.text = ""
				_editor._name_input.placeholder_text = Loc.txt("Name already taken!")
			return
	var kept_key := 0
	if _rail._editing_name != "" and _rail._editing_name != name_new:
		for ld in all:
			if str(ld.get("name")) == _rail._editing_name:
				kept_key = int(ld.get("quick_key", 0))
				break
		LD.remove(_rail._editing_name)
	LD.replace_set(name_new, _session.draft.equip, _session.draft.gear)
	if kept_key != 0:
		LD.set_quick_key(name_new, kept_key)
	if _rail._pending_qk != 0:
		LD.set_quick_key_unique(name_new, _rail._pending_qk)
		_rail._pending_qk = 0
		_rail._apply_qk_btn(_rail._bind_btn, int(LD.get_set(name_new).get("quick_key", 0)))
	_session.draft.set_name = name_new
	_rail._editing_name = name_new
	_editor._clear_problem()
	refresh(RefreshScope.LIST | RefreshScope.PREVIEW)

func _edit_loadout(name: String) -> void:
	var raw = LD.get_set(name)
	if raw.is_empty():
		return
	var d = Draft.new()
	d.load_from(raw)
	_session.edit_draft(d)
	_rail._editing_name = name
	_editor._build_editor()

func _delete_loadout(name: String) -> void:
	LD.remove(name)
	if _rail._editing_name == name:
		_cancel_draft()
	else:
		refresh(RefreshScope.LIST | RefreshScope.PREVIEW)
