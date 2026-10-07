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
#   2. Bots and mines get a mesh carrying a fixed emissive "key" color. The
#      original mesh is hidden while the key mesh shows, so the only thing in
#      that screen pixel IS the key color.
#   3. The shader samples the screen, finds whichever key is nearest, and
#      substitutes a display color. Everything else goes through the
#      false-color thermal palette.
#
# Detection is event-driven (SceneTree.node_added) rather than a full scene
# walk, and per-entity work is only a reference swap between pre-built
# materials -- no shader or material allocation after startup.

const GAME_DATA_RES := "res://Resources/GameData.tres"
const NVG_SCRIPT_SUFFIX := "NVG.gd"

const DEATH_COOLDOWN := 180.0
const DEBUG_MINES := false
const DEBUG_LOG := "user://loadouts_debug.log"

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

const SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.47, 0.67, 0.51, 1.0);
uniform float noise : hint_range(0.0, 60.0, 1.0) = 4.0;
uniform float vignette : hint_range(0.0, 1.0, 0.1) = 0.1;
uniform float goggleSeparation : hint_range(0.0, 1.0, 0.1) = 0.4;
uniform float goggleSize : hint_range(0.0, 1.0, 0.1) = 0.8;
uniform float goggleAspect : hint_range(0.0, 2.0, 0.1) = 1.6;
uniform float goggleOutline : hint_range(0.0, 0.1, 0.01) = 0.05;

uniform bool thermalMode = false;
uniform float thermalDarken : hint_range(1.0, 4.0, 0.01) = 1.70;
uniform int worldPaletteMode = 0;
uniform vec3 hotKey : source_color = vec3(1.0, 0.0, 1.0);
uniform vec3 hotFarKey : source_color = vec3(0.6, 0.0, 0.6);
uniform vec3 deadKey : source_color = vec3(0.0, 0.7, 1.0);
uniform vec3 deadFarKey : source_color = vec3(0.0, 0.35, 0.5);
uniform float botHighlightOpacity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform bool debugDetect = false;
uniform vec3 mineKey : source_color = vec3(0.0, 0.0, 1.0);
uniform vec3 friendKey : source_color = vec3(0.0, 1.0, 0.0);
uniform vec3 friendFarKey : source_color = vec3(0.0, 0.6, 0.0);

// Substitution colours. Deliberately a separate group from the keys above and
// driven by BOT_PRESETS; the two must never be wired together. See the branch
// in fragment() for why.
uniform vec3 hotColor : source_color = vec3(1.0, 0.8, 0.15);
uniform vec3 hotFarColor : source_color = vec3(0.6, 0.48, 0.09);
uniform vec3 deadColor : source_color = vec3(0.45, 0.3, 0.1);
uniform vec3 deadFarColor : source_color = vec3(0.27, 0.18, 0.06);
uniform vec3 mineColor : source_color = vec3(0.7, 0.1, 0.07);
uniform vec3 friendColor : source_color = vec3(0.15, 0.95, 0.25);
uniform vec3 friendFarColor : source_color = vec3(0.09, 0.57, 0.15);

float Goggles(vec2 uv)
{
	vec2 centerUV = (uv * 2.0 - 1.0);
	centerUV.x *= goggleAspect;
	float G1Distance = length(centerUV - vec2(-goggleSeparation * goggleAspect, 0.0));
	float G2Distance = length(centerUV - vec2(goggleSeparation * goggleAspect, 0.0));
	return min(G1Distance, G2Distance);
}

vec3 ThermalPalette(float t)
{
	t = clamp(t, 0.0, 1.0);
	vec3 c0;
	vec3 c1;
	vec3 c2;
	vec3 c3;
	vec3 c4;
	if (worldPaletteMode == 1) {
		c0 = vec3(0.0, 0.0, 0.0);
		c1 = vec3(0.25, 0.25, 0.25);
		c2 = vec3(0.5, 0.5, 0.5);
		c3 = vec3(0.75, 0.75, 0.75);
		c4 = vec3(1.0, 1.0, 1.0);
	} else if (worldPaletteMode == 2) {
		t = pow(t, 0.4);
		c0 = vec3(0.7, 0.7, 0.7);
		c1 = vec3(0.55, 0.55, 0.55);
		c2 = vec3(0.4, 0.4, 0.4);
		c3 = vec3(0.2, 0.2, 0.2);
		c4 = vec3(0.0, 0.0, 0.0);
	} else if (worldPaletteMode == 3) {
		c0 = vec3(0.02, 0.01, 0.0);
		c1 = vec3(0.25, 0.12, 0.02);
		c2 = vec3(0.55, 0.30, 0.05);
		c3 = vec3(0.80, 0.58, 0.18);
		c4 = vec3(1.0, 0.92, 0.70);
	} else if (worldPaletteMode == 4) {
		c0 = vec3(0.0, 0.02, 0.02);
		c1 = vec3(0.05, 0.18, 0.12);
		c2 = vec3(0.10, 0.38, 0.22);
		c3 = vec3(0.35, 0.62, 0.30);
		c4 = vec3(0.80, 0.95, 0.65);
	} else if (worldPaletteMode == 5) {
		c0 = vec3(0.0, 0.01, 0.04);
		c1 = vec3(0.05, 0.12, 0.35);
		c2 = vec3(0.10, 0.30, 0.60);
		c3 = vec3(0.40, 0.65, 0.85);
		c4 = vec3(0.85, 0.95, 1.0);
	} else {
		c0 = vec3(0.0, 0.0, 0.03);
		c1 = vec3(0.30, 0.12, 0.45);
		c2 = vec3(0.55, 0.0, 0.08);
		c3 = vec3(0.9, 0.65, 0.0);
		c4 = vec3(1.0, 1.0, 0.8);
	}
	vec3 color = mix(c0, c1, smoothstep(0.0, 0.25, t));
	color = mix(color, c2, smoothstep(0.25, 0.5, t));
	color = mix(color, c3, smoothstep(0.5, 0.75, t));
	color = mix(color, c4, smoothstep(0.75, 1.0, t));
	return color;
}

void fragment()
{
	vec4 pixelColor = texture(screen_texture, SCREEN_UV);
	float goggleMask = smoothstep(goggleSize + vignette, goggleSize, Goggles(UV));
	float goggleRim = abs(Goggles(UV) - goggleSize);
	float goggleOutlines = 1.0 - smoothstep(0.0, goggleOutline, goggleRim);
	float x = (SCREEN_UV.x + 1.0) * (SCREEN_UV.y + 1.0) * (TIME * 10.0);
	vec4 noiseEffect = vec4(mod((mod(x, 13.0)) * (mod(x, 123.0)), 0.01) - 0.005) * noise;

	vec4 color;
	if (thermalMode) {
		float dHot = distance(pixelColor.rgb, hotKey);
		float dHotFar = distance(pixelColor.rgb, hotFarKey);
		float dDead = distance(pixelColor.rgb, deadKey);
		float dDeadFar = distance(pixelColor.rgb, deadFarKey);
		float dMine = distance(pixelColor.rgb, mineKey);
		float dFriend = distance(pixelColor.rgb, friendKey);
		float dFriendFar = distance(pixelColor.rgb, friendFarKey);
		float minD = min(min(dHot, dHotFar), min(dDead, dDeadFar));
		minD = min(minD, dMine);
		minD = min(minD, min(dFriend, dFriendFar));

		// The framebuffer can be read back after shading, but never before it,
		// so a CPU-side probe can only ever see the already-tinted result and
		// can never confirm a match. Let the shader report on itself instead:
		// green where the detector fires, black where it misses. Godot rejects
		// `return` in a fragment processor, so the normal path is nested.
		if (debugDetect) {
			color = vec4(minD < 0.4 ? vec3(0.0, 1.0, 0.0) : vec3(0.0), pixelColor.a);
		} else {
			float rawLuminance = dot(pixelColor.rgb, vec3(0.299, 0.587, 0.114));
			float luminance = clamp(rawLuminance * thermalDarken, 0.0, 1.0);
			vec3 backgroundColor = ThermalPalette(luminance) * 0.7;

if (minD < 0.4) {
			// Substitution only. The keys above are the DETECTOR and stay fixed
			// regardless of what the player picks for bot colour.
			//
			// There is no feedback loop to defend against here: the bot overlay
			// is a real 3D mesh whose material_override is reassigned every
			// tick, so the key is repainted into the frame before this pass
			// samples it. (Proven by emission_energy_multiplier having no
			// visible effect on those materials -- the matched pixel's original
			// brightness is discarded, not fed forward.)
			//
			// So the output colour does NOT need to be the key. Wiring the
			// preset to the keys instead only changes which ordinary scenery
			// happens to land inside the 0.4 tolerance, and that reads as the
			// entire palette shifting when you switch colour.
			//
			// botHighlightOpacity blends toward backgroundColor rather than
			// toward black, so a translucent bot still reads as heat instead
			// of punching a hole in the picture. Mines stay solid regardless:
			// they are a UI marker, not a heat signature.
			vec3 marker;
			if (minD == dMine) {
				marker = mineColor;
			} else if (minD == dFriend) {
				marker = mix(backgroundColor, friendColor, botHighlightOpacity);
			} else if (minD == dFriendFar) {
				marker = mix(backgroundColor, friendFarColor, botHighlightOpacity);
			} else if (minD == dHot) {
				marker = mix(backgroundColor, hotColor, botHighlightOpacity);
			} else if (minD == dHotFar) {
				marker = mix(backgroundColor, hotFarColor, botHighlightOpacity);
			} else if (minD == dDead) {
				marker = mix(backgroundColor, deadColor, botHighlightOpacity);
			} else {
				marker = mix(backgroundColor, deadFarColor, botHighlightOpacity);
			}
				color = vec4(marker, pixelColor.a);
			} else {
				color = vec4(backgroundColor, pixelColor.a);
			}
		}
	} else {
		color = pixelColor * tint;
	}
	color += noiseEffect;
	color.rgb *= (1.0 + goggleOutlines);
	COLOR = mix(vec4(0.0, 0.0, 0.0, 1.0), color, goggleMask);
}
"""

const BOT_PRESETS := [
	# [hot, hotFar, dead, deadFar] -- SUBSTITUTION colours only.
	# These never reach the detector; the keys live in THERMAL_KEYS below.
	# Keeping the two apart is what makes switching preset provably incapable
	# of shifting the palette, which is the whole point.
	[Color(1.0, 0.8, 0.15), Color(0.6, 0.48, 0.09), Color(0.45, 0.3, 0.1), Color(0.27, 0.18, 0.06)],
	[Color(1.0, 0.2, 0.1), Color(0.6, 0.12, 0.06), Color(0.5, 0.1, 0.05), Color(0.3, 0.06, 0.03)],
	[Color(1.0, 1.0, 1.0), Color(0.6, 0.6, 0.6), Color(0.5, 0.5, 0.5), Color(0.3, 0.3, 0.3)],
	[Color(0.2, 0.9, 1.0), Color(0.12, 0.54, 0.6), Color(0.1, 0.4, 0.45), Color(0.06, 0.24, 0.27)],
]

# The detector's keys: [hot, hotFar, dead, deadFar, mine, friend, friendFar].
# Fixed by design -- NOT a setting, NOT preset-driven. These values have to stay
# in lockstep with the shader uniforms of the same name and with the unshaded
# overlay materials below, because the shader matches this exact triple in the
# frame and the 3D overlay is what emits it.
#
# Tolerance is distance < 0.4, so every pair here must stay further apart than
# that and all seven must stay clear of ordinary scenery. A single-hue ramp
# cannot manage that once the colours get dim -- 0.5 steps fall under 0.4 -- so
# near/far alternate hue instead of merely fading. hotKey stays off pure white,
# which is the most common blown-out highlight in any normally lit scene.
const THERMAL_KEYS := [
	Color(1.0, 0.0, 1.0),
	Color(0.6, 0.0, 0.6),
	Color(0.0, 0.7, 1.0),
	Color(0.0, 0.35, 0.5),
	Color(0.0, 0.0, 1.0),
	Color(0.0, 1.0, 0.0),
	Color(0.0, 0.6, 0.0),
]

# settings
var set_nvg_noise: float = 4.0
var set_nvg_white: float = 1.0
var set_thermal: bool = false
var set_mines: bool = true
var set_palette: int = 0
var set_world: float = 1.70
# 0.0 is the intended default and is not a "disabled" state: a matched bot is
# then drawn in the thermal palette colour for its own heat signature, which
# keeps every bot pixel on-palette by construction. Verified in game -- bots read
# clearly at 0.0. Raise it only to force a flat preset hue over that.
var set_bot_opacity: float = 0.0
var set_bot_preset: int = 0
var set_far_distance: float = 45.0
# Off by default. Gates every probe and the F4 detection overlay; when false
# _dbg() returns immediately, so nothing is written to the log and no file is
# even opened. Turn on from MCM only when there is something to diagnose.
var set_debug_probe: bool = false

var _game_data: Resource = null
var _shader: Shader = null
var _nvg_root: Node = null
var _nvg_mat_node: Node = null
var _installed: bool = false

var _mat_hot: StandardMaterial3D = null
var _mat_hot_far: StandardMaterial3D = null
var _mat_dead: StandardMaterial3D = null
var _mat_dead_far: StandardMaterial3D = null
var _mat_mine: StandardMaterial3D = null
var _mat_friend: StandardMaterial3D = null
var _mat_friend_far: StandardMaterial3D = null

var _bots: Dictionary = {}
var _mines: Dictionary = {}
var _mine_watch: Dictionary = {}
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
		_dbg("[probe] ready, gameData=" + str(_game_data != null) + " shader_len=" + str(SHADER_CODE.length()))

	_shader = Shader.new()
	_shader.code = SHADER_CODE

	# Seeded from THERMAL_KEYS rather than re-typing the values: these seven are the
	# detector's keys, so the shader uniforms and these materials must never
	# drift apart. Mine and friend are fixed, not part of BOT_PRESETS.
	var k: Array = THERMAL_KEYS
	_mat_hot = _key_material(k[0])
	_mat_hot_far = _key_material(k[1])
	_mat_dead = _key_material(k[2])
	_mat_dead_far = _key_material(k[3])
	_mat_mine = _key_material(k[4])
	_mat_friend = _key_material(k[5])
	_mat_friend_far = _key_material(k[6])

	get_tree().node_added.connect(_on_node_added)
	_scene_ref = get_tree().current_scene
	_reseed(get_tree().current_scene)


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
	# screen. They are pinned to THERMAL_KEYS and deliberately NOT to
	# BOT_PRESETS: the substitution colour is free, the key is not.
	#
	# Kept ahead of the _installed check on purpose -- if this were gated on the
	# shader being live, the two sides could desync during startup.
	var k: Array = THERMAL_KEYS
	_key_set(_mat_hot, k[0])
	_key_set(_mat_hot_far, k[1])
	_key_set(_mat_dead, k[2])
	_key_set(_mat_dead_far, k[3])
	if not _installed or _nvg_mat_node == null or not is_instance_valid(_nvg_mat_node):
		return
	var nvg_mat = _nvg_mat_node.get("material")
	if nvg_mat == null or not (nvg_mat is ShaderMaterial):
		return
	nvg_mat.set_shader_parameter("noise", set_nvg_noise)
	nvg_mat.set_shader_parameter("thermalMode", set_thermal and _nvg_active())
	nvg_mat.set_shader_parameter("thermalDarken", set_world)
	nvg_mat.set_shader_parameter("worldPaletteMode", set_palette)
	nvg_mat.set_shader_parameter("botHighlightOpacity", set_bot_opacity)
	nvg_mat.set_shader_parameter("debugDetect", _debug_detect)
	nvg_mat.set_shader_parameter("hotKey", k[0])
	nvg_mat.set_shader_parameter("hotFarKey", k[1])
	nvg_mat.set_shader_parameter("deadKey", k[2])
	nvg_mat.set_shader_parameter("deadFarKey", k[3])
	nvg_mat.set_shader_parameter("mineKey", k[4])
	nvg_mat.set_shader_parameter("friendKey", k[5])
	nvg_mat.set_shader_parameter("friendFarKey", k[6])
	var p: Array = BOT_PRESETS[clampi(set_bot_preset, 0, BOT_PRESETS.size() - 1)]
	nvg_mat.set_shader_parameter("hotColor", p[0])
	nvg_mat.set_shader_parameter("hotFarColor", p[1])
	nvg_mat.set_shader_parameter("deadColor", p[2])
	nvg_mat.set_shader_parameter("deadFarColor", p[3])


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
	if _tick_cd > 0.0:
		_tick_cd -= delta
		return
	_tick_cd = TICK

	var on := set_thermal and _nvg_active()

	_apply_env()

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
			_dbg("[sum] map=%s | installed=%s | set_thermal=%s | set_mines=%s | nvg_active=%s | shaderThermalMode=%s | palette=%s | far=%s | bots=%d | friendly=%d | mines=%d | watch=%d | player=%s" % [
				_dbg_map(), str(_installed), str(set_thermal), str(set_mines), str(_nvg_active()), tm,
				str(set_palette), str(set_far_distance), _bots.size(), _count_friendly(),
				_mines.size(), _mine_watch.size(), str(_player_pos())])
			_mine_report()
			_probe_pixels()

	for id in _bots.keys():
		_update_bot(id, on)
	for id in _mines.keys():
		_update_mine(id, on)


func _cdist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2.0) + pow(a.g - b.g, 2.0) + pow(a.b - b.b, 2.0))

# Reads the real framebuffer back and reports what the shader actually sees at a
# few bots. The key match is a screen-space distance test with a 0.4 cutoff, so
# "the ESP washed out" is only decidable from measured pixels -- reasoning about
# the material setup alone kept guessing wrong. Logs the distance to every key so
# a miss shows up as minD >= 0.4 instead of a vague white flood.
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
	_dbg("[px] botOpacity=%s world=%s tint=%s screen=%dx%d" % [
		str(set_bot_opacity), str(set_world), tint, w, h])
	var keys := {
		"hot": Color(1.0, 0.0, 1.0),
		"hotFar": Color(0.6, 0.0, 0.6),
		"dead": Color(0.0, 0.7, 1.0),
		"mine": Color(0.0, 0.0, 1.0),
		"friend": Color(0.0, 1.0, 0.0),
		"friendFar": Color(0.0, 0.6, 0.0),
	}
	var done := 0
	# Pool bots sit parked at y=100/110/120, far outside the camera, so every
	# one of them fails the screen-bounds test and the loop used to report
	# nothing at all. Tally the skips so an empty probe is explainable.
	var skip_noview := 0
	var skip_overlay := 0
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
		if not (bool(e["overlay"]) if "overlay" in e else false):
			skip_overlay += 1
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
		for k in keys.keys():
			var d := _cdist(c, keys[k])
			line += "%s=%.2f " % [String(k), d]
			if d < best:
				best = d
		_dbg(line + "MIN=%.2f %s" % [best, ("MATCH" if best < 0.4 else "NO-MATCH")])
		done += 1
	if done == 0:
		_dbg("[px] no sampleable bot: inactive=%d no_overlay=%d off_screen=%d of %d" % [
			skip_noview, skip_overlay, skip_bounds, _bots.size()])


func _count_friendly() -> int:
	var n := 0
	for id in _bots.keys():
		if _bots[id]["friendly"]:
			n += 1
	return n


func _apply_env() -> void:
	if set_nvg_white <= 0.0 or not _nvg_active():
		return
	var env := _env()
	if env != null:
		env.tonemap_white = set_nvg_white


func _env() -> Environment:
	var world = get_node_or_null("/root/Map/World")
	if world == null:
		return null
	var we = world.get("environment")
	if we == null:
		return null
	return we.get("environment")


func _log_trader(node: Node) -> void:
	if not set_debug_probe:
		return
	var td = node.get("traderData")
	var nm := "?"
	if td != null:
		nm = String(td.get("name"))
	_dbg("[trader] %s | map=%s | pos=%s | data=%s | active=%s" % [
		node.get_path(), _dbg_map(), str(node.global_position), nm, str(node.is_inside_tree())])


func _register_bot(node: Node) -> void:
	var id := node.get_instance_id()
	if _bots.has(id):
		return
	var mesh = node.get("mesh")
	if mesh == null or not (mesh is MeshInstance3D):
		if set_debug_probe:
			_dbg("[bot] REJECT mesh=%s (%s) at %s" % [str(mesh), ("null" if mesh == null else mesh.get_class()), node.get_path()])
		return
	var overlay: MeshInstance3D = mesh.duplicate()
	overlay.visible = false
	mesh.get_parent().add_child(overlay)
	overlay.transform = mesh.transform
	_bots[id] = {"node": node, "mesh": mesh, "overlay": overlay, "death": 0.0, "recorded": false, "friendly": _is_friendly(node)}
	if set_debug_probe:
		_dbg("[bot] ok %s mesh=%s pos=%s" % [node.get_path(), mesh.get_path(), str(node.global_position)])


func _is_friendly(node: Node) -> bool:
	# AISpawner instantiates res://AI/Nomad/AI_Nomad.tscn, so the pooled nodes are
	# named AI_Nomad, AI_Nomad_2, ... Green key keeps them from being shot.
	return String(node.name).contains("Nomad")


func _update_bot(id: int, thermal_on: bool) -> void:
	var e = _bots.get(id)
	if e == null:
		return
	var node = e["node"]
	var mesh = e["mesh"]
	var overlay = e["overlay"]
	if not is_instance_valid(node) or not is_instance_valid(mesh) or not is_instance_valid(overlay):
		_bots.erase(id)
		return

	var dead: bool = bool(node.get("dead"))
	var secs := -1.0
	var now := float(Time.get_ticks_msec()) / 1000.0
	if dead:
		if not e["recorded"]:
			e["recorded"] = true
			e["death"] = now
		secs = now - float(e["death"])

	var show := thermal_on and (not dead or secs < DEATH_COOLDOWN)
	if not dead:
		e["recorded"] = false

	var far := _player_pos().distance_to(node.global_position) > maxf(set_far_distance, 1.0)
	var m: StandardMaterial3D
	var friendly: bool = e["friendly"]
	if dead:
		m = _mat_dead_far if far else _mat_dead
	elif friendly:
		m = _mat_friend_far if far else _mat_friend
	else:
		m = _mat_hot_far if far else _mat_hot

	overlay.material_override = m
	overlay.visible = show
	mesh.visible = not show


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
	var show := thermal_on and set_mines
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