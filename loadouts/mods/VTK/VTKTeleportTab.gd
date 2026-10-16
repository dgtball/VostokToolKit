extends RefCounted
## Вкладка «Телепорт»: три равные колонки-карточки (карты, убежища, торговцы)
## и строки-кнопки телепорта. Вынесена из VTKUI (батч 6e, R3).
##
## Вкладка владеет только своими боксами, всё остальное приходит извне:
## travel создаёт VTKUI через _ensure_travel (узел живёт ребёнком VTKUI),
## game_data грузит он же. Общие примитивы UI инжектируются Callable: motion
## тянет _tween_scale VTKUI, а объявить здесь вторую копию нельзя - DUP стенда
## ловит одноимённые функции в разных модулях.
##
## Имена методов сохранены от VTKUI: их держит layout_check (PRESENT на
## _make_tp_column, FUNCS по телам _build_teleport_tab и _make_tp_column),
## переименование сломало бы стенд.

const Loc = preload("res://mods/VTK/VTKLoc.gd")
const VTKSurface := preload("res://mods/VTK/VTKSurface.gd")

# Инъекция из VTKUI: _attach_row_hover и _attach_motion.
var hover: Callable = Callable()
var motion: Callable = Callable()

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
	go.add_theme_color_override("font_color", VTKSurface.GOLD if enabled else Color("#3a3226"))
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(go)

	if enabled:
		hover.call(row, func(hv: bool) -> StyleBox:
			return VTKSurface.surface("hover" if hv else "normal", false, false, false, 10, 10, 7, 7))
		motion.call(row)
		var cb := callback
		row.gui_input.connect(func(ev: InputEvent):
			var mb := ev as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				if cb.is_valid():
					cb.call())
	return row

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
	nm.add_theme_color_override("font_color", VTKSurface.GOLD)
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


func _build_teleport_tab(parent: VBoxContainer, travel: Node, game_data: Resource) -> void:
	var head := Label.new()
	head.text = Loc.txt("Teleport")
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", VTKSurface.GOLD)
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
	if travel != null and is_instance_valid(travel):
		n_maps = travel.MAPS.size()
		n_shelters = travel.SHELTERS.size()
		n_traders = travel.TRADERS.size()

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	row.add_child(_make_tp_column(_tp_section_label("maps"), n_maps, _tp_maps_box))
	row.add_child(_make_tp_column(_tp_section_label("shelters"), n_shelters, _tp_shelters_box))
	row.add_child(_make_tp_column(_tp_section_label("traders"), n_traders, _tp_traders_box))
	parent.add_child(row)

	_refresh_teleport_tab(travel, game_data)

func _refresh_teleport_tab(travel: Node, game_data: Resource) -> void:
	if travel == null or not is_instance_valid(travel):
		return
	for box in [_tp_maps_box, _tp_shelters_box, _tp_traders_box]:
		if box == null:
			continue
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	var in_tutorial: bool = game_data != null and bool(game_data.get("tutorial"))

	for m in travel.MAPS:
		var map_note := Loc.txt("in the tutorial") if in_tutorial else ""
		var mm := String(m)
		_tp_maps_box.add_child(_tp_row(String(m), map_note, not in_tutorial, func(): travel.travel_to_map(mm)))

	for s in travel.SHELTERS:
		var ss := String(s)
		if in_tutorial:
			_tp_shelters_box.add_child(_tp_row(String(s), Loc.txt("in the tutorial"), false, func(): travel.travel_to_shelter(ss)))
		else:
			_tp_shelters_box.add_child(_tp_row(String(s), "", true, func(): travel.travel_to_shelter(ss)))

	for t in travel.TRADERS:
		var entry: Dictionary = t
		var note3 := Loc.txt("in the tutorial") if in_tutorial else ""
		_tp_traders_box.add_child(_tp_row(String(entry["name"]), note3, not in_tutorial, func(): travel.travel_to_trader(entry)))
