extends Node

# Owns the NVG overlay shader, plus the thermal/mines layer that rides on it.
#
# Architecture (ported from the ThermalVision reference mod):
#   1. Our own shader REPLACES the vanilla one on the NVG ColorRect. Because
#      vanilla only ever calls set_shader_parameter("tint", ...) on that same
#      ShaderMaterial, plain green NVG keeps working untouched -- we only get
#      a "noise" uniform we can actually drive (vanilla's own shader declares
#      noise as a `const`, which is why BetterNVG's set_shader_parameter
#      calls there did nothing).
#   2. Bots, mines and the friendly Nomad marker each carry fixed emissive
#      "key" colours. Mines are painted by material_override, so the whole
#      on-screen shell IS the key pixel. A bot's key body is a DUPLICATE of its
#      real mesh (a sibling carrying VTKBot.gdshader) with the real mesh hidden,
#      because the game's own bot geometry ignores an external material_override;
#      that shader picks the key by pixel height so a corpse can cool from the
#      extremities inward. The marker is a separate small billboarded key mesh
#      over a Nomad's head.
#   3. The shader samples the screen, finds whichever key is nearest, and
#      substitutes a display color. Everything else goes through the
#      false-color thermal palette.
#
# Detection is event-driven (SceneTree.node_added) rather than a full scene
# walk, and per-entity work is only a reference swap between pre-built
# materials -- no shader or material allocation after startup.

const GAME_DATA_RES := "res://Resources/GameData.tres"
const NVG_SCRIPT_SUFFIX := "NVG.gd"
const SHADER_RES := "res://mods/VTK/VTKNVG.gdshader"
const BOT_SHADER_RES := "res://mods/VTK/VTKBot.gdshader"

const DEBUG_MINES := false
const DEBUG_LOG := "user://loadouts_debug.log"

# Friendly Nomad marker: a mesh ▼ floating over the head, shown only while
# thermal is on. It carries a real key material -- the same unshaded + emission
# setup as the mine overlay -- rather than a font glyph, because a Label3D
# renders its glyph through the font atlas and never lands on the pure key
# colour, so the screen shader would palettise it like any scenery. The key is
# green, kept clear of the magenta/cyan bot keys and only accepted under a
# tight tolerance, so ordinary green foliage cannot trip it.
const MARKER_NAME := "VTK_NomadMarker"
const MARKER_KEY := Color(0.0, 1.0, 0.0)
# World height tracks distance so the ▼ keeps a steady on-screen size; the floor
# keeps a Nomad standing right beside the player from shrinking away to nothing.
const MARKER_SCREEN_SCALE := 0.035
const MARKER_MIN_SCALE := 0.3

# Bot heat: three detector keys emitted by VTKBot.gdshader, chosen by a pixel's
# height on the body (feet warm, head cold) so a corpse reads as cooling from
# the extremities inward. A living bot emits warm everywhere; as DEATH_COOLDOWN
# passes the cold front descends from the head toward the feet. Keys are fixed
# and mutually apart (and away from MINE_KEY/MARKER_KEY); only the substitution
# colours are preset-driven.
const BOT_WARM_KEY := Color(1.0, 0.0, 1.0)
const BOT_MID_KEY := Color(1.0, 1.0, 0.0)
const BOT_COLD_KEY := Color(0.0, 0.7, 1.0)
# A body stays highlighted for DEATH_COOLDOWN seconds after death, cooling from
# the head down, then the glow hides entirely.
const DEATH_COOLDOWN := 120.0

var _dbg_f: FileAccess = null
var _dbg_summary_cd: float = 0.0

func _dbg_open() -> void:
	if _dbg_f != null:
		return
	# WRITE_READ, not READ_WRITE: READ_WRITE refuses to create a missing file,
	# WRITE_READ creates it and still does not truncate, so sessions append.
	_dbg_f = FileAccess.open(DEBUG_LOG, FileAccess.WRITE_READ)
	if _dbg_f == null:
		print("[VTKProbe] cannot open ", DEBUG_LOG, " err=", FileAccess.get_open_error())
		return
	_dbg_f.seek_end()
	_dbg("=== session start ===")


func _dbg(msg: String) -> void:
	# Central off switch. Every probe funnels through here, so gating at the
	# single choke point is what makes the MCM toggle actually quiet -- guarding
	# only the call sites would still leave _dbg_open() creating the log file.
	if not set_debug_probe:
		return
	_dbg_open()
	var line := msg
	if _dbg_f != null:
		_dbg_f.store_line(line)
		_dbg_f.flush()
	print(line)


func _dbg_map() -> String:
	if _game_data == null:
		return "?"
	return String(_game_data.get("currentMap"))
const TICK := 0.1

# Detector key for mines. Fixed by design and kept in lockstep with the
# shader's mineKey uniform and the unshaded overlay material that emits it.
const MINE_KEY := Color(0.0, 0.0, 1.0)

# Detection targets, NOT the emitted keys. The vanilla NVG WorldEnvironment
# (glow + tonemap) desaturates the unshaded key colours toward white BEFORE the
# frame reaches our screen shader, so matching the raw keys above always misses.
# These are the measured post-NVG values for each emitted key (calibration bands,
# F8 / F9 screenshot): warm (1,0,1)->(0.94,0.69,0.94), mid (1,1,0)->(0.94,0.94,
# 0.88), cold (0,0.7,1)->(0.88,0.94,0.94), mine (0,0,1)->(0.50,0.06,0.94). The
# materials still EMIT the raw keys; only the detector compares against these.
const DET_WARM := Color(0.94, 0.69, 0.94)
const DET_MID := Color(0.94, 0.94, 0.88)
const DET_COLD := Color(0.88, 0.94, 0.94)
const DET_MINE := Color(0.50, 0.06, 0.94)
const DET_MARKER := Color(0.82, 0.96, 0.82)

# Bot glow substitution colours, per preset: [warm, mid, cold]. These never
# reach the detector -- the keys in BOT_WARM_KEY/BOT_MID_KEY/BOT_COLD_KEY are
# fixed and the display colours are driven from here, so switching a preset
# cannot shift the world palette. The three tones are the cooling readout:
# warm at the (still-warm) feet, mid partway up, cold at the head.
const BOT_PRESETS := [
	[Color(0.6, 0.48, 0.09), Color(0.55, 0.45, 0.28), Color(0.28, 0.3, 0.4)],   # Amber -> bronze -> slate
	[Color(0.6, 0.6, 0.6), Color(0.58, 0.56, 0.6), Color(0.3, 0.32, 0.38)],     # White -> warm grey -> cold grey
	[Color(0.6, 0.33, 0.09), Color(0.5, 0.34, 0.2), Color(0.26, 0.22, 0.24)],   # Orange -> dim orange -> nearly black
	[Color(0.6, 0.15, 0.09), Color(0.5, 0.22, 0.16), Color(0.28, 0.18, 0.2)],   # Red -> dim red -> barely warm
]
const BOT_PRESET_NAMES: Array[String] = ["Amber", "White", "Orange", "Red"]

# settings
var set_nvg_noise: float = 4.0
var set_nvg_white: float = 1.0
var set_thermal: bool = false
var set_mines: bool = true
var set_palette: int = 0
var set_world: float = 1.70
var set_bot_preset: int = 0
# Glow range: bots and mines only glow within this distance (MCM "Glow range").
# Past it they read as ordinary scenery, the way real optics lose a signature.
var set_far_distance: float = 45.0
# Friendly Nomads show a floating ▼ marker on top of their (warm) body glow.
var set_mark_nomads: bool = true
# In winter (gameData.season == 2) snow blows the thermal image out, so world
# visibility is scaled down by set_winter_dim. See _apply_uniforms.
var set_winter_auto: bool = true
var set_winter_dim: float = 0.55
# Off by default. Gates every probe and the F4 detection overlay; when false
# _dbg() returns immediately, so nothing is written to the log and no file is
# even opened. Turn on from MCM only when there is something to diagnose.
var set_debug_probe: bool = false

var _game_data: Resource = null
var _shader: Shader = null
var _nvg_root: Node = null
var _nvg_mat_node: Node = null
var _installed: bool = false

var _mat_mine: StandardMaterial3D = null
var _mat_marker: StandardMaterial3D = null
var _marker_mesh: Mesh = null
# Shared bot body shader; each bot gets its own ShaderMaterial instance off it,
# because "cool" and "footY" are per-bot uniforms (VTKBot.gdshader).
var _bot_shader: Shader = null

var _bots: Dictionary = {}
var _mines: Dictionary = {}
var _mine_watch: Dictionary = {}
var _dumped_bots: Dictionary = {}
var _tick_cd: float = 0.0
var _scene_ref: Node = null
var _debug_detect: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F4 and set_debug_probe:
			_debug_detect = not _debug_detect
			_apply_uniforms()
			_dbg("[probe] debugDetect=" + str(_debug_detect))


# Called by the settings layer when the MCM debug switch changes. Turning debug
# off has to actively clear the F4 overlay, otherwise the green detection mask
# would stay on screen forever with no key able to toggle it off.
func apply_debug_probe() -> void:
	if not set_debug_probe:
		_debug_detect = false
	_apply_uniforms()


func _ready() -> void:
	name = "VTKNVG"
	if ResourceLoader.exists(GAME_DATA_RES):
		_game_data = load(GAME_DATA_RES)

	if set_debug_probe:
		_dbg_open()
		_dbg("[probe] ready, gameData=" + str(_game_data != null) + " shader=" + str(ResourceLoader.exists(SHADER_RES)))

	# Shader lives in its own .gdshader file (packed by pack.ps1). load() is
	# runtime, so a missing file leaves _shader null and _try_install_shader
	# simply refuses to patch anything instead of silently breaking vanilla NVG.
	if ResourceLoader.exists(SHADER_RES):
		_shader = load(SHADER_RES) as Shader

	# Load the bot body shader. A missing file leaves _bot_shader null and bots
	# simply never get painted, rather than painting them with a broken material.
	if ResourceLoader.exists(BOT_SHADER_RES):
		_bot_shader = load(BOT_SHADER_RES) as Shader

	# Key materials emit the detector pixels. Mines and the Nomad marker use a
	# plain unshaded+emission StandardMaterial3D; bots use VTKBot.gdshader (per
	# bot), which emits warm/mid/cold by pixel height. The marker material is a
	# real key material too -- the Label3D route produced a font glyph that never
	# landed on the pure key, so it got palettised; a mesh with the same
	# unshaded+emission setup does not.
	_mat_mine = _key_material(MINE_KEY)
	_mat_marker = _key_material(MARKER_KEY)
	_mat_marker.no_depth_test = true
	_mat_marker.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat_marker.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_marker.render_priority = 10
	_marker_mesh = _make_marker_mesh()

	get_tree().node_added.connect(_on_node_added)
	# The game rewrites a bot's body material during its own update (seasonal
	# camo, damage flashes). This autoload's _process runs BEFORE the game's
	# nodes, so that write would land after ours and win the frame; re-assert the
	# paint right before the frame is drawn instead, which is after every node's
	# _process/_physics_process has run.
	RenderingServer.frame_pre_draw.connect(_frame_pre_draw)
	_scene_ref = get_tree().current_scene
	_reseed(get_tree().current_scene)


# A single downward-pointing triangle reads as ▼. Billboarded via the material,
# so the exact winding does not matter (cull is disabled anyway).
func _make_marker_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(Vector3(-0.5, 0.4, 0.0))
	st.add_vertex(Vector3(0.5, 0.4, 0.0))
	st.add_vertex(Vector3(0.0, -0.5, 0.0))
	return st.commit()


# node_added only ever reports nodes created after we connected, so anything
# already in the scene when this node comes up has to be swept manually.
func _reseed(scene: Node) -> void:
	if scene == null:
		return
	if set_debug_probe:
		_dbg("[probe] scan scene=" + str(scene.get_path()) + " name=" + str(scene.name) + " children=" + str(scene.get_child_count()))
	_scan_node(scene)


func _scan_node(n: Node) -> void:
	if n == null:
		return
	var s = n.get_script()
	var path: String = "" if s == null else String(s.resource_path)
	if path.ends_with(NVG_SCRIPT_SUFFIX) and _nvg_root == null:
		_nvg_root = n
		_try_install_shader()
	elif path.ends_with("Mine.gd"):
		_register_mine(n)
	elif path.ends_with("Trader.gd"):
		_log_trader(n)
	elif _is_bot(n):
		_register_bot(n)
	for c in n.get_children():
		_scan_node(c)


func _key_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.0
	return m


# Repaint an existing key material. Must mirror _key_material exactly, otherwise
# the emitted pixel stops matching the shader key and the category disappears.
func _key_set(m: StandardMaterial3D, c: Color) -> void:
	if m == null:
		return
	m.albedo_color = c
	m.emission = c


func _on_node_added(node: Node) -> void:
	call_deferred("_deferred_check", node.get_instance_id())


func _deferred_check(node_id: int) -> void:
	var n := instance_from_id(node_id)
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return
	var s = n.get_script()
	var path: String = "" if s == null else String(s.resource_path)

	if path.ends_with(NVG_SCRIPT_SUFFIX):
		_nvg_root = n
		_try_install_shader()
		return
	if path.ends_with("Mine.gd"):
		_register_mine(n)
		return
	if path.ends_with("Trader.gd"):
		_log_trader(n)
		return
	if _is_bot(n):
		_register_bot(n)


# AI.gd extends Node3D, not CharacterBody3D. Signature: has Activate(), exposes
# a "dead" flag and an exported MeshInstance3D "mesh". Trader.gd also has
# Activate() but no "dead", so it stays out of the bot set.
func _is_bot(n: Node) -> bool:
	return n is Node3D and n.has_method("Activate") and "dead" in n and "mesh" in n


# The shader lives on a ColorRect under the NVG node's "Overlay" child. Vanilla
# captures exactly that ShaderMaterial in its own _ready() and only ever calls
# set_shader_parameter("tint", ...) on it -- so swapping .shader here keeps
# plain NVG working while giving us a drivable "noise" uniform.
func _try_install_shader() -> void:
	# /root/Map is rebuilt on every map change, which frees the NVG node we
	# patched and spawns a fresh one carrying the vanilla shader. So this must
	# re-run every tick and re-patch by inspection, never latch on a flag.
	if _shader == null:
		_installed = false
		return
	if _nvg_root == null or not is_instance_valid(_nvg_root):
		_nvg_root = get_node_or_null("/root/Map/Core/UI/NVG")
	if _nvg_root == null or not is_instance_valid(_nvg_root):
		_installed = false
		return
	var overlay = _nvg_root.get_node_or_null("Overlay")
	if overlay == null or overlay.get_child_count() == 0:
		_installed = false
		return
	var target = overlay.get_child(0)
	if not ("material" in target):
		_installed = false
		return
	var mat = target.get("material")
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader == _shader:
		_nvg_mat_node = target
		_installed = true
		return
	if mat == null or not (mat is ShaderMaterial):
		if set_debug_probe and _installed:
			_dbg("[probe] install lost: material is " + str(mat))
		_installed = false
		return
	mat.shader = _shader
	_nvg_mat_node = target
	_installed = true
	if set_debug_probe:
		_dbg("[probe] shader INSTALLED on " + str(target.get_path()))
	_apply_uniforms()


func _apply_uniforms() -> void:
	# The key materials are what actually emit the detector's key pixels on
	# screen. They are pinned to the key constants and deliberately NOT to
	# BOT_PRESETS: the substitution colour is free, the key is not.
	#
	# Kept ahead of the _installed check on purpose -- if this were gated on the
	# shader being live, the two sides could desync during startup.
	_key_set(_mat_mine, MINE_KEY)
	_key_set(_mat_marker, MARKER_KEY)
	if not _installed or _nvg_mat_node == null or not is_instance_valid(_nvg_mat_node):
		return
	var nvg_mat = _nvg_mat_node.get("material")
	if nvg_mat == null or not (nvg_mat is ShaderMaterial):
		return
	nvg_mat.set_shader_parameter("noise", set_nvg_noise)
	nvg_mat.set_shader_parameter("thermalMode", set_thermal and _nvg_active())
	# Winter snow reads near-white, so the whole frame pins to the top of the
	# palette and everything vanishes. Scaling the world darkening down pulls
	# the snow back into the readable mid-range.
	var darken := set_world
	if _is_winter():
		darken *= set_winter_dim
	nvg_mat.set_shader_parameter("thermalDarken", darken)
	nvg_mat.set_shader_parameter("worldPaletteMode", set_palette)
	nvg_mat.set_shader_parameter("debugDetect", _debug_detect)
	nvg_mat.set_shader_parameter("markNomads", set_mark_nomads)
	nvg_mat.set_shader_parameter("nvgWhite", set_nvg_white)
	nvg_mat.set_shader_parameter("warmKey", DET_WARM)
	nvg_mat.set_shader_parameter("midKey", DET_MID)
	nvg_mat.set_shader_parameter("coldKey", DET_COLD)
	nvg_mat.set_shader_parameter("mineKey", DET_MINE)
	nvg_mat.set_shader_parameter("markerKey", DET_MARKER)
	var p: Array = BOT_PRESETS[clampi(set_bot_preset, 0, BOT_PRESETS.size() - 1)]
	nvg_mat.set_shader_parameter("warmColor", p[0])
	nvg_mat.set_shader_parameter("midColor", p[1])
	nvg_mat.set_shader_parameter("coldColor", p[2])


# gameData.season == 2 is winter (default 1). Gated on the setting so the
# dimming is a no-op when the player turns it off.
func _is_winter() -> bool:
	return set_winter_auto and _game_data != null and int(_game_data.get("season")) == 2


func _nvg_active() -> bool:
	if _game_data == null or not _game_data.has_method("get"):
		return false
	return bool(_game_data.get("NVG"))


func _process(delta: float) -> void:
	_try_install_shader()
	if get_tree().current_scene != _scene_ref:
		_scene_ref = get_tree().current_scene
		_bots.clear()
		_mines.clear()
		_mine_watch.clear()
		_reseed(_scene_ref)
		_tick_cd = 0.0
	var on := set_thermal and _nvg_active()

	# Key paint tracks NVG state every frame, not every TICK: the tick gate below
	# runs the world scan, but if painting waited for it, a quick NVG toggle left
	# bots a frame behind on the flash of raw key pixels.
	for id in _bots.keys():
		_update_bot(id, on)
	for id in _mines.keys():
		_update_mine(id, on)

	if _tick_cd > 0.0:
		_tick_cd -= delta
		return
	_tick_cd = TICK

	_apply_uniforms()

	_retry_mines()

	if set_debug_probe:
		_dbg_summary_cd -= delta
		if _dbg_summary_cd <= 0.0:
			_dbg_summary_cd = 3.0
			var nvg_mat = _nvg_mat_node.get("material") if _nvg_mat_node != null and is_instance_valid(_nvg_mat_node) else null
			var tm := "n/a"
			if nvg_mat is ShaderMaterial:
				tm = str((nvg_mat as ShaderMaterial).get_shader_parameter("thermalMode"))
			_dbg("[sum] map=%s | installed=%s | set_thermal=%s | set_mines=%s | nvg_active=%s | shaderThermalMode=%s | palette=%s | far=%s | opacity=%s | preset=%s | bots=%d | friendly=%d | mines=%d | watch=%d | botShader=%s | player=%s" % [
				_dbg_map(), str(_installed), str(set_thermal), str(set_mines), str(_nvg_active()), tm,
				str(set_palette), str(set_far_distance), str(set_bot_preset),
				_bots.size(), _count_friendly(),
				_mines.size(), _mine_watch.size(), str(_bot_shader != null), str(_player_pos())])
			_mine_report()
			_bot_report()
			_probe_pixels()


func _cdist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2.0) + pow(a.g - b.g, 2.0) + pow(a.b - b.b, 2.0))

# Reads the real framebuffer back and reports the composited pixel at a few
# bots. Because substitution happens on the GPU, the sample is the OUTPUT: a
# colour close to a preset display colour means the detector fired (SUB); the
# raw-key distance only tells us about pixels it missed. Samples at head height,
# which is the first zone to cool.
func _probe_pixels() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	var tex := vp.get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null:
		return
	var w := img.get_width()
	var h := img.get_height()
	var nvg_mat = _nvg_mat_node.get("material") if _nvg_mat_node != null and is_instance_valid(_nvg_mat_node) else null
	var tint := "n/a"
	if nvg_mat is ShaderMaterial:
		tint = str((nvg_mat as ShaderMaterial).get_shader_parameter("tint"))
	_dbg("[px] world=%s tint=%s screen=%dx%d" % [str(set_world), tint, w, h])
	# Robot keys are the raw detector colours; once substitution has happened the
	# output no longer matches them (it is a preset colour), so the raw distance
	# is only meaningful for a pixel the detector MISSED. The DISP distance is
	# the useful one: close to a substitution colour means the detector fired.
	var rkeys := {
		"warm": BOT_WARM_KEY,
		"mid": BOT_MID_KEY,
		"cold": BOT_COLD_KEY,
		"mine": MINE_KEY,
		"marker": MARKER_KEY,
	}
	var p: Array = BOT_PRESETS[clampi(set_bot_preset, 0, BOT_PRESETS.size() - 1)]
	var g: float = 0.88
	var disp := {
		"warm": p[0] * g,
		"mid": p[1] * g,
		"cold": p[2] * g,
		"mine": Color(0.7, 0.1, 0.07),
		"marker": Color(0.2, 1.0, 0.2),
	}
	var done := 0
	# Pool bots sit parked at y=100/110/120, far outside the camera, so every
	# one of them fails the screen-bounds test and the loop used to report
	# nothing at all. Tally the skips so an empty probe is explainable.
	var skip_noview := 0
	var skip_unpainted := 0
	var skip_bounds := 0
	for id in _bots.keys():
		var e = _bots.get(id)
		if e == null:
			continue
		var node = e["node"]
		if not is_instance_valid(node):
			continue
		# Same active gate the counter uses: only roamers are worth sampling.
		if "active" in node and not bool(node.get("active")):
			skip_noview += 1
			continue
		if not bool(e.get("painted")):
			skip_unpainted += 1
			continue
		if not bool(e.get("painted")):
			skip_unpainted += 1
			continue
		var sp := cam.unproject_position(node.global_position + Vector3(0.0, 1.0, 0.0))
		if sp.x < 1.0 or sp.y < 1.0 or sp.x >= float(w - 1) or sp.y >= float(h - 1):
			skip_bounds += 1
			continue
		var c := img.get_pixelv(sp)
		var line := "[px] %s friendly=%s rgb=(%.2f,%.2f,%.2f) lum=%.2f " % [
			str(node.name), str(e["friendly"]), c.r, c.g, c.b,
			(0.299 * c.r + 0.587 * c.g + 0.114 * c.b)]
		var best := 999.0
		for k in rkeys.keys():
			var d := _cdist(c, rkeys[k])
			line += "%s=%.2f " % [String(k), d]
			if d < best:
				best = d
		var bestDisp := 999.0
		for k in disp.keys():
			bestDisp = minf(bestDisp, _cdist(c, disp[k]))
		_dbg(line + "MIN=%.2f %s DISP=%.2f %s" % [
			best, ("MATCH" if best < 0.4 else "NO-MATCH"),
			bestDisp, ("SUB" if bestDisp < 0.12 else "RAW")])
		done += 1
	if done == 0:
		_dbg("[px] no sampleable bot: inactive=%d unpainted=%d off_screen=%d of %d" % [
			skip_noview, skip_unpainted, skip_bounds, _bots.size()])


func _count_friendly() -> int:
	var n := 0
	for id in _bots.keys():
		if _bots[id]["friendly"]:
			n += 1
	return n


func _log_trader(node: Node) -> void:
	if not set_debug_probe:
		return
	var td = node.get("traderData")
	var nm := "?"
	if td != null:
		nm = String(td.get("name"))
	_dbg("[trader] %s | map=%s | pos=%s | data=%s | active=%s" % [
		node.get_path(), _dbg_map(), str(node.global_position), nm, str(node.is_inside_tree())])


func _bot_report() -> void:
	for id in _bots.keys():
		var e = _bots.get(id)
		if e == null:
			continue
		var node = e.get("node")
		if node == null or not is_instance_valid(node):
			continue
		if not _dumped_bots.has(id):
			_dumped_bots[id] = true
			_dump_bot_tree(node, 0)
		var meshes: Array = e.get("meshes")
		var painted := 0
		var vis := 0
		var parts: Array = []
		for m in meshes:
			if not is_instance_valid(m):
				continue
			var g := m as GeometryInstance3D
			if g.material_override != null:
				painted += 1
			if g.visible:
				vis += 1
			if parts.size() < 12:
				parts.append("%s(%s v=%s)" % [String(g.name), str(g.get_aabb().size), str(g.visible)])
		if meshes.size() > 12:
			parts.append("...+%d" % (meshes.size() - 12))
		_dbg("[bots] %s | nvg=%s | meshes=%d painted=%d vis=%d | nodeMesh=%s | shader=%s | %s" % [
			node.name, str(set_thermal and _nvg_active()),
			meshes.size(), painted, vis,
			str(node.get("mesh") != null), str(_bot_shader != null),
			", ".join(parts)])
		# The body is the largest swept mesh. Its visibility-range window tells us
		# whether the game range-fades the painted skin out up close, revealing an
		# unpainted proxy (the distance-dependent "key only at the edges").
		var body: GeometryInstance3D = null
		var best_vol := -1.0
		for m in meshes:
			if not is_instance_valid(m):
				continue
			var gb := m as GeometryInstance3D
			var sz := gb.get_aabb().size
			var vol := sz.x * sz.y * sz.z
			if vol > best_vol:
				best_vol = vol
				body = gb
		if body != null:
			var surfs := 0
			if body is MeshInstance3D:
				surfs = (body as MeshInstance3D).get_surface_override_material_count()
			_dbg("[bot:body] %s mesh=%s aabb=%s vis=%s visrange=[%s..%s] fade=%s layers=%s ovr=%s surfs=%d" % [
				node.name, String(body.name), str(body.get_aabb().size), str(body.visible),
				str(body.visibility_range_begin), str(body.visibility_range_end),
				str(body.visibility_range_fade_mode), str(body.layers),
				str(body.material_override != null), surfs])
		var marker := node.get_node_or_null(MARKER_NAME) as MeshInstance3D
		_dbg("[bot:marker] %s friendly=%s markNomads=%s has=%s vis=%s pos=%s scale=%s" % [
			node.name, str(e["friendly"]), str(set_mark_nomads), str(marker != null),
			str(marker.visible) if marker != null else "n/a",
			str(marker.global_position) if marker != null else "n/a",
			str(marker.scale) if marker != null else "n/a"])


func _dump_bot_tree(n: Node, depth: int) -> void:
	var pad := ""
	var i := 0
	while i < depth:
		pad += "  "
		i += 1
	var extra := ""
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		var surf := 0
		var ovr_surf := 0
		if g is MeshInstance3D:
			var mi := g as MeshInstance3D
			surf = mi.get_surface_override_material_count()
			for s in surf:
				if mi.get_surface_override_material(s) != null:
					ovr_surf += 1
		extra = " aabb=%s vis=%s layers=%s ovr=%s ovl=%s ovrSurf=%d/%d" % [
			str(g.get_aabb().size), str(g.visible), str(g.layers),
			str(g.material_override != null), str(g.material_overlay != null),
			ovr_surf, surf]
	_dbg("[tree] %s%s:%s%s" % [pad, String(n.name), n.get_class(), extra])
	for c in n.get_children():
		_dump_bot_tree(c, depth + 1)


func _register_bot(node: Node) -> void:
	var id := node.get_instance_id()
	if _bots.has(id):
		return
	# The bot's visual (variant skin, LODs, gear) is assembled by AI.Initialize()
	# at runtime as a whole subtree, and the exported node.mesh is only ONE inner
	# piece of it -- duplicating that single mesh highlighted just the sliver that
	# pokes past the real skin, so the body read as scenery. Instead we paint the
	# bot's own geometry directly, exactly like mines: sweep every
	# GeometryInstance3D under the node and override its material. The sweep is
	# (re)done lazily in _update_bot, because the subtree does not exist yet at
	# registration and AI.Initialize() can rewire it later.
	_bots[id] = {
		"node": node,
		"meshes": [],
		"mat": null,
		"painted": false,
		"paint": null,
		"probed": false,
		"friendly": _is_friendly(node),
		"death": 0.0,
		"recorded": false,
	}
	if set_debug_probe:
		_dbg("[bot] %s tracked pos=%s" % [node.get_path(), str(node.global_position)])


# Sweeps the bot's whole visual subtree and returns its geometry nodes. The
# exported node.mesh is only an inner piece of the rig -- the visible skin is
# separate LOD/gear meshes -- so painting that one node (or a duplicate of it)
# left the real body as scenery with just a key sliver at the silhouette. This
# is the same route mines already take.
func _sweep_bot_meshes(node: Node) -> Array:
	var all: Array = []
	_collect_meshes(node, all)
	var out: Array = []
	for m in all:
		# Skip the friendly ▼ we add ourselves; it carries its own key material.
		if is_instance_valid(m) and String(m.name) != MARKER_NAME:
			out.append(m)
	return out


func _is_friendly(node: Node) -> bool:
	# Faction comes from the AIData variant picked in AI.Initialize(), so this is
	# recomputed every tick (the variant can be null at registration time). Falls
	# back to the pooled node name, since AISpawner names them AI_Nomad, AI_Nomad_2.
	var v = node.get("variant")
	if v != null and v.get("faction") != null:
		return int(v.get("faction")) == 0
	return String(node.name).contains("Nomad")


func _update_bot(id: int, thermal_on: bool) -> void:
	var e = _bots.get(id)
	if e == null:
		return
	var node = e["node"]
	if not is_instance_valid(node):
		_bots.erase(id)
		return

	var friendly := _is_friendly(node)
	e["friendly"] = friendly

	# Death clock: death_time is latched on the frame the bot dies, and a body
	# stays highlighted DEATH_COOLDOWN seconds while it cools. The cooling front
	# (VTKBot.gdshader) is driven by cool = secs / DEATH_COOLDOWN; at the end the
	# glow hides. Mirror of the reference mod's death_time/death_time_recorded.
	var dead: bool = bool(node.get("dead"))
	var secs := -1.0
	var now := float(Time.get_ticks_msec()) / 1000.0
	if dead:
		if not e["recorded"]:
			e["recorded"] = true
			e["death"] = now
		secs = now - float(e["death"])
	else:
		e["recorded"] = false

	# A friendly Nomad gets a floating ▼ on top of its body glow, but only inside
	# the same glow range as the body -- otherwise it reads through the whole map.
	var mark_dist := _player_pos().distance_to(node.global_position)
	var mark := thermal_on and set_mark_nomads and friendly and not dead \
		and mark_dist <= maxf(set_far_distance, 1.0)
	_update_nomad_marker(node, mark)

	# Re-collect the bot's geometry every frame. It does not exist at
	# registration, AI.Initialize() can swap the variant, and the game adds,
	# removes or range-fades LOD/body meshes as the player closes in. A stale-ref
	# check alone missed meshes ADDED later (the old refs stay valid), which left
	# the close-range body unpainted while only a key sliver poked past it. A
	# fresh sweep is cheap -- a few dozen nodes per bot, once a frame.
	var fresh: Array = _sweep_bot_meshes(node)
	if set_debug_probe:
		var before := {}
		for m in e["meshes"]:
			if is_instance_valid(m):
				before[m.get_instance_id()] = true
		for m in fresh:
			if not before.has(m.get_instance_id()):
				var g := m as GeometryInstance3D
				_dbg("[bot:new] %s mesh=%s class=%s aabb=%s visrange=[%s..%s] fade=%s vis=%s" % [
					node.name, String(g.name), g.get_class(), str(g.get_aabb().size),
					str(g.visibility_range_begin), str(g.visibility_range_end),
					str(g.visibility_range_fade_mode), str(g.visible)])
	e["meshes"] = fresh

	# Per-bot body material off the shared shader: "cool" and "footY" are
	# per-bot uniforms. cool = secs / DEATH_COOLDOWN drives the cooling front
	# (VTKBot.gdshader) from just above the head down past the feet.
	var bmat: ShaderMaterial = e.get("mat")
	if bmat == null and _bot_shader != null:
		bmat = ShaderMaterial.new()
		bmat.shader = _bot_shader
		bmat.set_shader_parameter("warmKey", BOT_WARM_KEY)
		bmat.set_shader_parameter("midKey", BOT_MID_KEY)
		bmat.set_shader_parameter("coldKey", BOT_COLD_KEY)
		e["mat"] = bmat
	if bmat != null:
		var cool := 0.0 if not dead else clampf(secs / DEATH_COOLDOWN, 0.0, 1.0)
		bmat.set_shader_parameter("cool", cool)
		bmat.set_shader_parameter("footY", node.global_position.y)

	# A body only glows inside the glow range and while it still has heat left;
	# past either bound the override is cleared and the real skin shows through.
	var dist := _player_pos().distance_to(node.global_position)
	var show := thermal_on and bmat != null and dist <= maxf(set_far_distance, 1.0) and (not dead or secs < DEATH_COOLDOWN)
	e["painted"] = show
	var paint = bmat if show else null
	e["paint"] = paint
	for m in e["meshes"]:
		if is_instance_valid(m):
			(m as GeometryInstance3D).material_override = paint


# Last write before the frame is drawn, after every node has processed. Re-assert
# the body paint so a game-side material write (see _ready) cannot outlast ours,
# and report the first time we catch one, so a silent overwrite becomes visible
# in the probe log.
func _frame_pre_draw() -> void:
	for id in _bots.keys():
		var e = _bots.get(id)
		if e == null:
			continue
		var node = e.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var paint = e.get("paint")
		for m in e.get("meshes", []):
			if not is_instance_valid(m):
				continue
			var g := m as GeometryInstance3D
			if g.material_override == paint:
				continue
			if set_debug_probe and not e.get("probed", false):
				_dbg("[bot:clobber] %s mesh=%s was=%s now=%s" % [
					node.name, String(g.name), str(paint),
					(g.material_override.get_class() if g.material_override != null else "null")])
				e["probed"] = true
			g.material_override = paint


# Lazily builds the marker on the bot itself (looked up by name, not via the
# bookkeeping dict) so a dropped-and-recreated entry can never orphan the mesh.
# The ▼ is a real key mesh, billboarded and depth-test-free, so the screen
# shader substitutes it to markerColor instead of palettising it.
func _update_nomad_marker(node: Node, show_marker: bool) -> void:
	var marker := node.get_node_or_null(MARKER_NAME) as MeshInstance3D
	if not show_marker:
		if marker != null:
			marker.visible = false
		return
	if marker == null:
		marker = MeshInstance3D.new()
		marker.name = MARKER_NAME
		marker.mesh = _marker_mesh
		marker.material_override = _mat_marker
		marker.position = Vector3(0.0, 2.2, 0.0)
		node.add_child(marker)
	# Scale with distance so the ▼ keeps a steady on-screen size, with a floor so
	# a Nomad standing right beside the player does not shrink away.
	var dist := _player_pos().distance_to(node.global_position)
	marker.scale = Vector3.ONE * maxf(dist * MARKER_SCREEN_SCALE, MARKER_MIN_SCALE)
	marker.visible = true


func _player_pos() -> Vector3:
	if _game_data != null:
		var p = _game_data.get("playerPosition")
		if p != null:
			return p
	return Vector3.ZERO


func _register_mine(node: Node) -> void:
	var id := node.get_instance_id()
	if _mines.has(id):
		return
	# The visual usually lives under an exported "mine" Node3D, but not every
	# mine has one -- fall back to the node itself so those still get picked up.
	# The exported "mine" points at the INNER detail (the tiny orange piece that
	# pops out on detonation), NOT the visible shell: a mine node holds LOD0/LOD1
	# (the shell you actually see) plus Mine (interior) plus Area. Sweeping from
	# the exported property alone highlighted only the interior, so the shell
	# stayed invisible while still being the thing you want spotted. So we always
	# sweep the whole mine node: that covers the shell LODs and the interior, and
	# the Area3D is skipped automatically because it isn't geometry.
	var _inner = node.get("mine")
	var visual: Node = node
	if set_debug_probe:
		_dbg("[mine] %s | mine_prop=%s (%s) | sweep=whole_node | children=%d" % [
			node.get_path(), str(_inner), ("null" if _inner == null else _inner.get_class()),
			node.get_child_count()])
	var meshes: Array = []
	_collect_meshes(visual, meshes)
	if set_debug_probe:
		_dbg("[mine] %s | collected %d geometry nodes: %s" % [node.get_path(), meshes.size(), str(_mesh_paths(meshes))])
		var _sizes: Array = []
		for m in meshes:
			if is_instance_valid(m):
				_sizes.append("%s(aabb=%s)" % [m.name, str((m as GeometryInstance3D).get_aabb().size)])
		_dbg("[mine] %s | shell+interior sizes: %s" % [node.get_path(), str(_sizes)])
	if meshes.is_empty():
		# A freshly spawned mine can still be building its visual (own _ready, a
		# timer, an async load), so an empty sweep is not proof there is nothing
		# to paint. Park it and retry on later ticks instead of dropping it.
		_mine_watch[id] = node
		if DEBUG_MINES:
			print("[VTKNVG] mine without mesh yet: %s" % node.get_path())
		return
	_mine_watch.erase(id)
	_mines[id] = {"node": node, "meshes": meshes}
	if DEBUG_MINES:
		print("[VTKNVG] mine registered: %s meshes=%d" % [node.get_path(), meshes.size()])


func _describe(n: Variant) -> String:
	if n == null or not is_instance_valid(n):
		return "<null>"
	var root := n as Node
	var out: Array = [str(root.name) + ":" + root.get_class()]
	for c in root.get_children():
		var extra := ""
		if c is GeometryInstance3D:
			extra = "(vis=%s,ovr=%s)" % [str((c as GeometryInstance3D).visible), str((c as GeometryInstance3D).material_override != null)]
		out.append(str(c.name) + ":" + c.get_class() + extra)
	return "[" + ", ".join(out) + "]"


func _mesh_paths(meshes: Array) -> Array:
	var out: Array = []
	for m in meshes:
		out.append(String(m.get_path()))
		if out.size() >= 8:
			break
	return out


func _retry_mines() -> void:
	if _mine_watch.is_empty():
		return
	for id in _mine_watch.keys():
		var n = _mine_watch[id]
		if not is_instance_valid(n):
			_mine_watch.erase(id)
			continue
		_register_mine(n)


func _collect_meshes(node: Node, out: Array) -> void:
	# GeometryInstance3D rather than MeshInstance3D: some visuals are MultiMesh
	# or CSG, and material_override lives on the base class.
	if node is GeometryInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)


func _update_mine(id: int, thermal_on: bool) -> void:
	var e = _mines.get(id)
	if e == null:
		return
	if not is_instance_valid(e["node"]):
		_mines.erase(id)
		return
	# Mines obey the same glow range as bots: past it they read as scenery.
	var node = e["node"]
	var dist := _player_pos().distance_to(node.global_position)
	var show := thermal_on and set_mines and dist <= maxf(set_far_distance, 1.0)
	for mesh in e["meshes"]:
		if is_instance_valid(mesh):
			mesh.material_override = _mat_mine if show else null


func _mine_report() -> void:
	if not set_debug_probe or _mines.is_empty():
		return
	var pp := _player_pos()
	var best: Array = []
	for id in _mines.keys():
		var e = _mines[id]
		if not is_instance_valid(e["node"]):
			continue
		var d: float = pp.distance_to((e["node"] as Node3D).global_position)
		best.append([d, id])
	best.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(3, best.size()):
		var e = _mines[best[k][1]]
		var node = e["node"]
		_dbg("[mine:full] %s | dist=%.1f | prop=%s | subtree=%s" % [
			node.get_path(), best[k][0], _describe(node), _describe(node.get("mine"))])
		for m in e["meshes"]:
			_dbg("[mine:mesh] %s | ours=%s | visible=%s | pos=%s | aabb=%s | layers=%d" % [
				m.get_path(), str(m.material_override == _mat_mine), str(m.visible),
				str(m.global_position), str(m.get_aabb()), m.layers])


func set_thermal_enabled(on: bool) -> void:
	set_thermal = on
	_apply_uniforms()
	_tick_cd = 0.0


func set_mines_enabled(on: bool) -> void:
	set_mines = on
	_tick_cd = 0.0