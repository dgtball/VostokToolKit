extends Control

# Лента убийств. Чистая логика (цвета, сегменты, вытеснение, fade) — static,
# чтобы тестировалась headless; рендер и игровые пути — только в экземпляре.

const GREEN := Color(0.55, 0.85, 0.55)
const RED := Color(1, 0.45, 0.45)
const GREY := Color(0.75, 0.75, 0.75)
const HS_GOLD := Color(1, 0.84, 0.41)

const MAX_ROWS := 5
const FEED_DURATION := 5.0
const FADE_TIME := 0.6
const FEED_TOP_OFFSET := 72.0
const FONT_SIZE := 15
const ROW_HEIGHT := 20.0
const ICON_SIZE := 14.0

static func kind_color(kind: String) -> Color:
	if kind == "player" or kind == "nomad":
		return GREEN
	return RED

static func segments(ev: Dictionary) -> Array:
	var out: Array = []
	out.append({"text": str(ev.get("killer_name", "")), "color": kind_color(str(ev.get("killer_kind", "")))})
	if bool(ev.get("grenade", false)):
		out.append({"icon": "grenade"})
	else:
		if str(ev.get("weapon", "")) != "":
			out.append({"icon": "weapon"})
		if bool(ev.get("headshot", false)):
			out.append({"icon": "hs"})
	out.append({"text": str(ev.get("victim_name", "")), "color": kind_color(str(ev.get("victim_kind", "")))})
	return out

static func alpha_at(age: float) -> float:
	if age <= FEED_DURATION:
		return 1.0
	var f := (age - FEED_DURATION) / FADE_TIME
	if f >= 1.0:
		return 0.0
	return 1.0 - f

static func push_entry(entries: Array, entry: Dictionary, max_rows: int) -> Array:
	entries.insert(0, entry)
	var dropped: Array = []
	while entries.size() > max_rows:
		dropped.append(entries.pop_back())
	return dropped

const Surface = preload("res://mods/VTK/VTKSurface.gd")
const Picker = preload("res://mods/VTK/VTKPicker.gd")

const GRENADE_SVG := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"32\"><ellipse cx=\"16\" cy=\"20\" rx=\"9\" ry=\"10\" fill=\"#6f7a5a\" stroke=\"#3d4433\" stroke-width=\"2\"/><rect x=\"13\" y=\"6\" width=\"6\" height=\"5\" rx=\"1\" fill=\"#8a8f7a\" stroke=\"#3d4433\" stroke-width=\"1.5\"/><path d=\"M19 8 q7 1 7 7\" fill=\"none\" stroke=\"#c9c2b2\" stroke-width=\"2\"/><path d=\"M26 15 l0 4\" fill=\"none\" stroke=\"#c9c2b2\" stroke-width=\"2\"/></svg>"
# Перекрестие HS — из утверждённого макета (killfeed-mockup.html), цвет = HS_GOLD.
const HS_SVG := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"32\"><circle cx=\"16\" cy=\"16\" r=\"11\" fill=\"none\" stroke=\"#FFD669\" stroke-width=\"2.5\"/><circle cx=\"16\" cy=\"16\" r=\"3.5\" fill=\"#FFD669\"/><path d=\"M16 1v7M16 24v7M1 16h7M24 16h7\" fill=\"none\" stroke=\"#FFD669\" stroke-width=\"2.5\"/></svg>"

var _enabled: bool = false
var _rows: Array = []
var _vbox: VBoxContainer = null
var _scene_ref: Node = null
var _was_shelter: bool = false
var _hooks: Node = null

func _ready() -> void:
	name = "VTKFeed"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	position = Vector2(10, 10 + FEED_TOP_OFFSET)
	_vbox = VBoxContainer.new()
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_theme_constant_override("separation", 2) # зазор подложек по макету
	add_child(_vbox)
	_connect_hooks()

func _connect_hooks() -> void:
	if _hooks != null and is_instance_valid(_hooks):
		return
	var p = get_node_or_null("/root/VTKUI")
	if p == null:
		return
	var h = p.get_node_or_null("VTKHooks")
	if h != null and h.has_signal("kill_event"):
		_hooks = h
		h.connect("kill_event", _on_kill_event)

func set_enabled(v: bool) -> void:
	_enabled = v
	visible = v
	if v:
		_connect_hooks()
	else:
		clear()

func clear() -> void:
	for e in _rows:
		var n = e.get("node")
		if n != null and is_instance_valid(n):
			n.queue_free()
	_rows.clear()

func _on_kill_event(ev: Dictionary) -> void:
	if not _enabled or _was_shelter:
		return
	_add_row(ev)

func _add_row(ev: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size.y = ROW_HEIGHT
	for seg in segments(ev):
		if seg.has("text"):
			var lbl := Label.new()
			lbl.text = str(seg["text"])
			lbl.add_theme_font_size_override("font_size", FONT_SIZE)
			lbl.add_theme_color_override("font_color", seg["color"])
			row.add_child(lbl)
		else:
			_add_icon(row, str(seg["icon"]), ev)
	# Подложка по макету: слегка затемнённый StyleBoxFlat, padding 6px по горизонтали.
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.add_child(row)
	_vbox.add_child(panel)
	var dropped: Array = push_entry(_rows, {"node": panel, "age": 0.0}, MAX_ROWS)
	for old in dropped:
		var n = old.get("node")
		if n != null and is_instance_valid(n):
			n.queue_free()

func _add_icon(row: HBoxContainer, icon: String, ev: Dictionary) -> void:
	if icon == "weapon":
		var w := str(ev.get("weapon", ""))
		var tex := _weapon_texture(w)
		if tex != null:
			_add_tex(row, tex, 2.0)
			return
		# Иконка не найдена (имя не сошлось с Database) — имя текстом, иначе
		# сегмент оружия исчезнет и строка снова будет без оружия.
		if w != "":
			var wl := Label.new()
			wl.text = w
			wl.add_theme_font_size_override("font_size", FONT_SIZE)
			wl.add_theme_color_override("font_color", GREY)
			row.add_child(wl)
		return
	if icon == "grenade":
		_add_tex(row, Surface.svg_texture(GRENADE_SVG))
		return
	if icon == "hs":
		var tex := _hs_texture()
		if tex != null:
			_add_tex(row, tex)
			return
		# Иконки нет (файл не попал в пак) — текстовый фолбэк как у KillFeedMod.
		var lbl := Label.new()
		lbl.text = "HS"
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", HS_GOLD)
		row.add_child(lbl)

func _add_tex(row: HBoxContainer, tex: Texture2D, width_mul: float = 1.0) -> void:
	if tex == null:
		return
	var iv := TextureRect.new()
	iv.texture = tex
	iv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	iv.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	iv.custom_minimum_size = Vector2(ICON_SIZE * width_mul, ICON_SIZE)
	iv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(iv)

func _hs_texture() -> Texture2D:
	return Surface.svg_texture(HS_SVG)

# Оружие: имя из события -> предмет Database -> иконка предмета (как в сетах).
# item_art кропит прозрачные поля, иначе иконка оружия едва видна в строке 15px.
func _weapon_texture(weapon: String) -> Texture2D:
	if weapon == "":
		return null
	var db = get_tree().root.get_node_or_null("Database")
	if db == null or not ("master" in db):
		return null
	var master = db.get("master")
	if master == null or not ("items" in master):
		return null
	for item in master.items:
		if item == null:
			continue
		if str(item.name).strip_edges() != weapon:
			continue
		var ui = get_node_or_null("/root/VTKUI")
		var icon = null
		if ui != null and ui.has_method("_item_icon"):
			icon = ui.call("_item_icon", item)
		if icon is Texture2D:
			return Picker.item_art(icon)
		if "icon" in item and item["icon"] is Texture2D:
			return Picker.item_art(item["icon"])
	return null

func _process(delta: float) -> void:
	if not _enabled:
		return
	# Смена карты и шелтер чистят ленту теми же признаками, что и счётчик.
	var cs = get_tree().current_scene
	if cs != _scene_ref:
		_scene_ref = cs
		clear()
	var in_shelter := false
	var iface = get_tree().root.get_node_or_null("Map/Core/UI/Interface")
	if iface != null and "gameData" in iface:
		var gd = iface.get("gameData")
		if gd != null:
			in_shelter = bool(gd.get("shelter"))
	if in_shelter and not _was_shelter:
		clear()
	_was_shelter = in_shelter
	if in_shelter:
		return
	for e in _rows:
		e["age"] = float(e["age"]) + delta
	var i := 0
	while i < _rows.size():
		var e = _rows[i]
		var a := alpha_at(float(e["age"]))
		var n = e.get("node")
		if n != null and is_instance_valid(n):
			n.modulate.a = a
		if a <= 0.0:
			if n != null and is_instance_valid(n):
				n.queue_free()
			_rows.remove_at(i)
			continue
		i += 1
