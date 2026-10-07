extends RefCounted
## Слоёные SVG-поверхности в золотой палитре (приём CheatMenu/FieldTheme).
## Всё кэшируется по ключу состояния; поверхности статичны и переживают
## перестройку UI (mod.tres не перегружается, кэш чистить не нужно).

const GOLD := Color("#d48a3a")
const INK := Color("#d8cdbe")
const MUTED := Color("#8a7a6a")

static var _surfaces: Dictionary = {}
static var _textures: Dictionary = {}

static func clear_cache() -> void:
	_surfaces.clear()
	_textures.clear()

static func svg_texture(svg: String) -> Texture2D:
	if _textures.has(svg):
		return _textures[svg]
	var image := Image.new()
	if image.load_svg_from_string(svg) != OK:
		return null
	var tex := ImageTexture.create_from_image(image)
	_textures[svg] = tex
	return tex

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
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#171208") if inset else Color("#1a1510")
	s.border_color = Color("#2a1f14")
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 5
	s.shadow_offset = Vector2(0, 3)
	return s

static func focus_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.TRANSPARENT
	s.border_color = GOLD
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	return s

static func style_button(button: Button, accent: bool = false, danger: bool = false,
		ml: int = 14, mr: int = 14, mt: int = 9, mb: int = 11) -> void:
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color("#efe5d4"))
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.add_theme_color_override("font_disabled_color", Color("#5f5347"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, surface(state, accent, danger, false, ml, mr, mt, mb))
	button.add_theme_stylebox_override("focus", focus_style())
