extends RefCounted
## Слоёные SVG-поверхности в золотой палитре (приём CheatMenu/FieldTheme).
## Всё кэшируется по ключу состояния; поверхности статичны и переживают
## перестройку UI (mod.tres не перегружается, кэш чистить не нужно).

const GOLD := Color("#d48a3a")
const GOLD_SOFT := Color("#e0b55a")
const INK := Color("#d8cdbe")
const MUTED := Color("#8a7a6a")
const BROWN := Color("#5f5347")
const BORDER := Color("#3a2e20")
const PANEL_BG := Color("#1a1510")
const GREY := Color("#888888")
const GREY_DIM := Color("#666666")

static var _surfaces: Dictionary = {}
static var _textures: Dictionary = {}
static var _panels: Dictionary = {}
static var _focus: StyleBoxFlat = null

static func svg_texture(svg: String) -> Texture2D:
	if _textures.has(svg):
		return _textures[svg]
	var image := Image.new()
	if image.load_svg_from_string(svg) != OK:
		return null
	var tex := ImageTexture.create_from_image(image)
	_textures[svg] = tex
	return tex

# Голая шестерёнка золотым: признак, что в слоте есть вложение. Своя SVG, а не
# символ шрифта игры: U+2699 в шрифте может отсутствовать, а мод и так рисует
# иконки из строк. Цвет подставляется в fill-rule evenodd-путь (отверстие).
static func gear_icon(size: int, color: Color) -> Texture2D:
	var hex := color.to_html(false)
	var svg := ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 24 24">' \
		+ '<path fill="#%s" fill-rule="evenodd" d="M19.14 12.94a7.5 7.5 0 0 0 0-1.88l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.49.49 0 0 0-.59-.22l-2.39.96a7.4 7.4 0 0 0-1.62-.94l-.36-2.54a.48.48 0 0 0-.48-.41h-3.84a.48.48 0 0 0-.48.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96a.48.48 0 0 0-.59.22L2.74 8.87a.49.49 0 0 0 .12.61l2.03 1.58a7.5 7.5 0 0 0 0 1.88l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.48-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32a.49.49 0 0 0-.12-.61l-2.01-1.58zM12 15.6a3.6 3.6 0 1 1 0-7.2 3.6 3.6 0 0 1 0 7.2z"/></svg>') \
		% [size, size, hex]
	return svg_texture(svg)

static func surface(state: String = "normal", accent: bool = false,
		danger: bool = false, strong: bool = false,
		ml: int = 14, mr: int = 14, mt: int = 9, mb: int = 11) -> StyleBoxTexture:
	var key := "%s/%s/%s/%s/%d/%d/%d/%d" % [state, accent, danger, strong, ml, mr, mt, mb]
	if _surfaces.has(key):
		return _surfaces[key]

	var edge := "#5a3a1a" if accent else "#3a2e20"
	var top := "#33220e" if accent else "#261f18"
	var bottom := "#241708" if accent else "#191410"
	if danger:
		top = "#40261c"
		bottom = "#2c1a14"
		edge = "#6e3d2a"
	if state == "hover":
		top = "#3f2e12" if accent else "#2c2417"
		bottom = "#241708" if accent else "#1c1711"
		edge = "#d48a3a" if accent else "#c9823a"
	elif state == "pressed":
		top = "#18130c"
		bottom = "#291c09"
		edge = "#b87a30"
	elif state == "disabled":
		top = "#1c1713"
		bottom = "#151210"
		edge = "#2e251c"

	var svg := ('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">' \
		+ '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">' \
		+ '<stop stop-color="%s"/><stop offset="1" stop-color="%s"/>' \
		+ '</linearGradient></defs>' \
		+ '<rect x="1" y="3" width="62" height="61" rx="5" fill="#0d0a07" fill-opacity=".7"/>' \
		+ '<rect x="1.5" y="1.5" width="61" height="58" rx="4" fill="url(#g)" stroke="%s"/>' \
		+ '<path d="M6 3H58" stroke="#d8cdbe" stroke-opacity=".10"/>' \
		+ '<path d="M5 57H59" stroke="#000" stroke-opacity=".5"/>' \
		+ '<rect x="4" y="5" width="56" height="50" rx="2" fill="none" stroke="#d8cdbe" stroke-opacity=".03"></rect>' \
		+ '</svg>') % [top, bottom, edge]

	var style := StyleBoxTexture.new()
	style.texture = svg_texture(svg)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 8)
	style.content_margin_left = ml
	style.content_margin_right = mr
	style.content_margin_top = mt
	style.content_margin_bottom = mb
	_surfaces[key] = style
	return style

static func panel(inset: bool = false, margin: int = 16) -> StyleBoxFlat:
	var key := "%s/%d" % [str(inset), margin]
	if _panels.has(key):
		return _panels[key]
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#171208") if inset else PANEL_BG
	s.border_color = Color("#2a1f14")
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 5
	s.shadow_offset = Vector2(0, 3)
	_panels[key] = s
	return s

# Пунктирная рамка для карточек без заливки. StyleBoxFlat штрихов не умеет, а
# узел-рамка с таким поведением удалён и держится в GONE стенда - поэтому рисуем
# штрихами через CanvasItem. dash/gap в пикселях, width - толщина линии.
static func draw_dashes(ci: CanvasItem, rect: Rect2, color: Color,
		dash: float = 4.0, gap: float = 4.0, width: float = 1.0) -> void:
	var x0 := rect.position.x + width * 0.5
	var y0 := rect.position.y + width * 0.5
	var x1 := rect.position.x + rect.size.x - width * 0.5
	var y1 := rect.position.y + rect.size.y - width * 0.5
	var x := x0
	while x < x1:
		var seg := minf(dash, x1 - x)
		ci.draw_line(Vector2(x, y0), Vector2(x + seg, y0), color, width)
		ci.draw_line(Vector2(x, y1), Vector2(x + seg, y1), color, width)
		x += dash + gap
	var y := y0
	while y < y1:
		var seg := minf(dash, y1 - y)
		ci.draw_line(Vector2(x0, y), Vector2(x0, y + seg), color, width)
		ci.draw_line(Vector2(x1, y), Vector2(x1, y + seg), color, width)
		y += dash + gap

static func focus_style() -> StyleBoxFlat:
	if _focus != null:
		return _focus
	var s := StyleBoxFlat.new()
	s.bg_color = Color.TRANSPARENT
	s.border_color = GOLD
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	_focus = s
	return s

static func style_button(button: Button, accent: bool = false, danger: bool = false,
		ml: int = 14, mr: int = 14, mt: int = 9, mb: int = 11) -> void:
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color("#efe5d4"))
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.add_theme_color_override("font_disabled_color", BROWN)
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, surface(state, accent, danger, false, ml, mr, mt, mb))
	button.add_theme_stylebox_override("focus", focus_style())
