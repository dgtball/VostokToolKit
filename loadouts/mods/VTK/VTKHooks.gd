extends Node

var _registered: bool = false
var _lib = null
var _kill_count: int = 0
var _player_hits: Dictionary = {}
var _hooks_kc: Array = []

var _death_restart_btn = null
var _death_is_ironman: bool = false
var _ironman_active: bool = false
var _ironman_initialized: bool = false
var _ironman_pending: bool = false

# The death screen ships its own "Load Game" button: live in a normal run,
# greyed out under permadeath. We borrow that button instead of stacking our own
# panel on top of it, and hand the original text/state/connections back when the
# screen goes away. A null button here means the fallback panel is in use.
var _death_load_btn = null
var _death_load_bound = null
var _death_load_orig_text: String = ""
var _death_load_orig_disabled: bool = false
var _death_load_orig_conns: Array = []

# Death.tscn is mounted asynchronously behind Loader's FadeInLoading, so on the
# first frames after death there is no button to borrow yet. Give the scene time
# to appear before committing to the fallback panel.
const DEATH_FIND_TIMEOUT_MS := 20000
var _death_find_since: int = 0
var _death_dump_at: int = 0
var _death_probe_at: int = 0

# The death screen was never handled at all: the whole handler rode the
# controller-_physics_process hook, and Controller is a node inside /root/Map,
# so it was freed with the map and _lib._caller went invalid before the Death
# scene even mounted. Not one line of output reached the log. Poll from our own
# _process instead -- this node lives on the autoload and outlives any map.
var _gd_node = null
var _death_latched: bool = false
var _gd_missing_logged: bool = false

# Ironman respawn drops you somewhere random out of these instead of always
# Highway, so a death run can't be re-learned as one fixed route.
const IRONMAN_MAPS := ["Highway", "School", "Outpost", "Apartments"]

# Respawn vitals. Temperature and oxygen are deliberately left at full --
# they gate survival mechanics rather than fight difficulty, and a random
# roll there just felt arbitrary. The rest roll 30..100 per death so the run
# never starts clean.
const IRONMAN_VITAL_MIN := 30.0
const IRONMAN_VITAL_MAX := 100.0

const PROBE_LOG := "user://loadouts_debug.log"
var _probe_wd: int = 0
var _probe_death: int = 0
var _probe_chain: int = 0
var _probe_hunt: int = 0
var _probe_be: int = 0
var _probe_exp: int = 0
var _probe_knife: int = 0

func _probe(msg: String) -> void:
	print("[VTK][probe] " + msg)
	var f := FileAccess.open(PROBE_LOG, FileAccess.READ_WRITE)
	if f == null and not FileAccess.file_exists(PROBE_LOG):
		f = FileAccess.open(PROBE_LOG, FileAccess.WRITE)
	if f == null:
		return
	f.seek(f.get_length())
	f.store_line(Time.get_time_string_from_system() + " [hook] " + msg)
	f.close()

func _probe_obj(o) -> String:
	if o == null:
		return "null(null)"
	if not is_instance_valid(o):
		return str(o) + "(freed)"
	var s := str(o)
	if o is Node:
		s = str(o.get_path())
	return s + "(" + str(typeof(o)) + ")"

func _probe_wp(n: Node) -> String:
	var wp := ""
	for pl in n.get_property_list():
		var pn := String(pl["name"])
		if pn.begins_with("_") or pn.contains("script"):
			continue
		var low := pn.to_lower()
		if low.contains("weapon") or low.contains("hand") or low.contains("item") \
				or low == "slotdata" or low.contains("equip"):
			var v = n.get(pn)
			wp += pn + "=" + str(v) + "(" + str(typeof(v)) + ") "
	return wp

# Охота: все узлы, имя которых совпадает с предметом Database. Показывает,
# где в дереве лежит узел оружия игрока (у AI это weapon=<RigidBody3D Glock_17>).
func _probe_weapon_hunt() -> void:
	var db = get_tree().root.get_node_or_null("Database")
	if db == null or not ("master" in db):
		_probe("HUNT no Database")
		return
	var master = db.get("master")
	if master == null or not ("items" in master):
		_probe("HUNT no items")
		return
	var names := {}
	for item in master.items:
		if item == null:
			continue
		var inm := str(item.name).strip_edges()
		if inm != "" and String(item.resource_path).contains("/Weapons/"):
			names[inm] = true
	var hits: Array = []
	var stack: Array = [get_tree().root]
	var visited := 0
	while not stack.is_empty() and hits.size() < 25 and visited < 20000:
		var n: Node = stack.pop_back()
		visited += 1
		if names.has(String(n.name)):
			hits.append(str(n.get_path()) + "(" + n.get_class() + ")")
		for c in n.get_children():
			stack.push_back(c)
	_probe("HUNT weapons_named=" + str(names.size()) + " visited=" + str(visited) + " hits=[" + " | ".join(hits) + "]")

func _ready() -> void:
	name = "VTKHooks"
	print("[VTK] Hooks node ready, RTVModLib=" + str(Engine.has_meta("RTVModLib")))

func get_kill_count() -> int:
	return _kill_count

func reset_kills() -> void:
	_kill_count = 0
	_player_hits.clear()

func _process(_delta: float) -> void:
	if not _registered:
		_try_register()
	_poll_death()

const GAME_DATA_RES := "res://Resources/GameData.tres"

func _resolve_gamedata() -> Variant:
	if _gd_node != null and is_instance_valid(_gd_node):
		return _gd_node
	var direct = load(GAME_DATA_RES) if ResourceLoader.exists(GAME_DATA_RES) else null
	if direct != null:
		_gd_node = direct
		return _gd_node
	# Fall back to whatever exposes the permadeath flags.
	for c in get_tree().root.get_children():
		if "isDead" in c and "permadeath" in c:
			_gd_node = c
			print("[VTK] GameData resolved by flag scan: " + str(c.name) + " (" + c.get_class() + ")")
			return _gd_node
	return null

func _poll_death() -> void:
	var gd = _resolve_gamedata()
	if gd == null and not _death_latched:
		if not _gd_missing_logged:
			_gd_missing_logged = true
			print("[VTK] poll: GameData resource unavailable; death screen idle")
		return
	var is_dead := _death_latched
	var is_ironman := _death_latched
	if gd != null:
		# LoadScene runs a full New Game, which rebuilds GameData from defaults
		# and drops permadeath again. Re-assert it every frame until it sticks,
		# otherwise the second death arrives as DEATH: Standard and the whole
		# Death screen goes untouched.
		if _ironman_pending:
			if not bool(gd.get("permadeath", false)) or bool(gd.get("isDead", false)):
				gd.set("permadeath", true)
				gd.set("shelter", false)
				gd.set("isDead", false)
				print("[VTK] re-asserted ironman after restart (permadeath was dropped)")
			else:
				_ironman_pending = false
				_ironman_initialized = true
				print("[VTK] ironman re-applied and holding")
		# The game rewrites both flags the moment the Death scene mounts, so
		# neither can carry the screen on its own. Read the mode on the first
		# frame that reports it, then keep serving the screen off the mounted
		# scene until it goes away again.
		var dead_scene := _death_scene_root() != null
		is_dead = bool(gd.get("isDead", false)) or dead_scene
		is_ironman = bool(gd.get("permadeath", false)) or (_death_latched and dead_scene)
		if is_dead and is_ironman and not _death_latched:
			# Latch it: the flags live on the map's GameData, which is torn down
			# on death, so the next frame may have no source left to read.
			_death_latched = true
			print("[VTK] poll: death+ironman latched from " + str(gd.get_class()) + " isDead=" + str(bool(gd.get("isDead", false))) + " permadeath=" + str(bool(gd.get("permadeath", false))) + " death_scene=" + str(dead_scene))
		elif not is_dead:
			# Back in a live run (or on the main menu): release the latch so a
			# missing GameData later cannot resurrect the death screen.
			_death_latched = false
			_gd_missing_logged = false
		if _death_latched:
			var pnow := Time.get_ticks_msec()
			if pnow - _death_probe_at > 1000:
				_death_probe_at = pnow
				print("[VTK] poll: raw isDead=" + str(gd.get("isDead", false)) + " permadeath=" + str(gd.get("permadeath", false)) + " death_scene=" + str(dead_scene))
	_handle_death_screen(gd, is_dead, is_ironman)

func _try_register() -> void:
	if Engine.has_meta("RTVModLib"):
		_lib = Engine.get_meta("RTVModLib")
		if _lib.get("_is_ready"):
			_do_register()
		else:
			if not _lib.frameworks_ready.is_connected(_do_register):
				_lib.frameworks_ready.connect(_do_register)
	else:
		var mml = get_node_or_null("/root/RTVModLib")
		if mml == null:
			mml = get_node_or_null("/root/MML")
		if mml and mml.has_method("hook"):
			_lib = mml
			_do_register()

func _do_register() -> void:
	if _registered:
		return
	if _lib == null and Engine.has_meta("RTVModLib"):
		_lib = Engine.get_meta("RTVModLib")
	if _lib == null or not _lib.has_method("hook"):
		print("[VTK] Cannot register hooks: no RTVModLib")
		return
	print("[VTK] Registering hooks...")
	_lib.hook("controller-_physics_process-post", _on_controller_process)
	_hooks_kc.append(_lib.hook("ai-weapondamage-pre", _on_ai_weapon_damage))
	_hooks_kc.append(_lib.hook("ai-death-pre", _on_ai_death))
	_lib.hook("weaponrig-bloodeffect-post", _on_probe_bloodeffect)
	_lib.hook("ai-explosiondamage-pre", _on_probe_explosion)
	_lib.hook("kniferig-hitcheck-post", _on_probe_knife)
	_registered = true
	print("[VTK] Per-frame hooks registered (" + str(_hooks_kc.size() + 1) + " hooks)")

func _on_probe_bloodeffect(hitCollider, _hit_point, _hit_normal) -> void:
	if _probe_be >= 15:
		return
	_probe_be += 1
	var rig = _lib._caller if _lib else null
	var rig_s := "null"
	var wfile := ""
	if rig != null and is_instance_valid(rig):
		rig_s = str(rig.get_path()) + " cls=" + rig.get_class()
		if "data" in rig and rig.data != null:
			var d = rig.data
			wfile = " file=" + str(d.get("file") if "file" in d else "?") + " cls=" + d.get_class()
	_probe("BE rig=[%s]%s target=[%s]" % [rig_s, wfile, _probe_obj(hitCollider)])

func _on_probe_explosion(_direction, id) -> void:
	if _probe_exp >= 10:
		return
	_probe_exp += 1
	var ai = _lib._caller if _lib else null
	var ai_s := "null"
	if ai != null and is_instance_valid(ai):
		ai_s = str(ai.get_path())
	var grp := false
	if id != null and is_instance_valid(id) and id is Node:
		grp = id.is_in_group("Player")
	_probe("EXP caller=[%s] direction=%s id=[%s] grpP=%s" % [ai_s, str(_direction), _probe_obj(id), str(grp)])

func _on_probe_knife() -> void:
	if _probe_knife >= 5:
		return
	_probe_knife += 1
	var kn = _lib._caller if _lib else null
	var s := "null"
	if kn != null and is_instance_valid(kn):
		s = str(kn.get_path())
		if "data" in kn and kn.data != null:
			s += " file=" + str(kn.data.get("file") if "file" in kn.data else "?")
	_probe("KNIFE " + s)

func _on_ai_weapon_damage(_hitbox, _damage, _vector, id) -> void:
	if _probe_wd < 40:
		_probe_wd += 1
		var ai = _lib._caller if _lib else null
		var caller_s := "null"
		var wprops := ""
		if ai != null and is_instance_valid(ai):
			caller_s = str(ai.get_path()) + " cls=" + ai.get_class()
			for p in ["weapon", "currentWeapon", "weaponName", "equippedWeapon", "activeWeapon", "slotData"]:
				if p in ai:
					wprops += p + "=" + str(ai.get(p)) + "(" + str(typeof(ai.get(p))) + ") "
		_probe("WD hitbox=%s damage=%s vector=%s id=[%s] caller=[%s] callerW=[%s]" % [
			str(_hitbox), str(_damage), str(_vector), _probe_obj(id), caller_s, wprops])
		if _probe_wd == 1:
			var gd = _resolve_gamedata()
			var gds := "gd=null"
			if gd != null:
				gds = "gd=" + str(gd.get_class()) + " | "
				for p in ["currentWeaponName", "currentWeapon", "weaponName", "weapon", "equippedWeapon"]:
					if p in gd:
						gds += p + "=" + str(gd.get(p)) + "(" + str(typeof(gd.get(p))) + ") "
				if "playerVector" in gd:
					gds += "playerVector=" + str(gd.get("playerVector")) + " "
			var pl = get_tree().get_first_node_in_group("Player")
			var pls := " player=null"
			if pl != null:
				pls = " player=" + str(pl.get_path()) + " | "
				for p in ["weapon", "currentWeapon", "activeWeapon", "weaponName", "equippedWeapon", "slotData", "hands", "itemInHands"]:
					if p in pl:
						pls += p + "=" + str(pl.get(p)) + "(" + str(typeof(pl.get(p))) + ") "
			_probe("GD " + gds + pls)
	if id != null and is_instance_valid(id) and id is Node:
		if _probe_chain < 10:
			_probe_chain += 1
			var parts: Array = []
			var n: Node = id
			var depth := 0
			while n != null and depth < 8:
				parts.append(str(n.get_path()) + " {" + _probe_wp(n) + "}")
				n = n.get_parent()
				depth += 1
			_probe("CHAIN grpP=" + str(id.is_in_group("Player")) + " " + " >> ".join(parts))
		if id.is_in_group("Player") and _probe_hunt < 2:
			_probe_hunt += 1
			_probe_weapon_hunt()
	if id == null or not is_instance_valid(id):
		return
	if not id.is_in_group("Player"):
		return
	var ai = _lib._caller if _lib else null
	if ai == null or not is_instance_valid(ai):
		return
	_player_hits[ai.get_instance_id()] = Time.get_ticks_msec()

func _on_ai_death(_direction, _force) -> void:
	if _probe_death < 40:
		_probe_death += 1
		var ai = _lib._caller if _lib else null
		var caller_s := "null"
		if ai != null and is_instance_valid(ai):
			caller_s = str(ai.get_path()) + " cls=" + ai.get_class() + " dead=" + str(ai.get("dead") if "dead" in ai else "?")
		var pv = null
		var gd = _resolve_gamedata()
		if gd != null and "playerVector" in gd:
			pv = gd.get("playerVector")
		var dot := -2.0
		if _direction is Vector3 and pv is Vector3:
			var a := (_direction as Vector3).normalized()
			var b := (pv as Vector3).normalized()
			if a != Vector3.ZERO and b != Vector3.ZERO:
				dot = a.dot(b)
		_probe("DEATH caller=[%s] direction=%s force=%s(%s) playerVector=%s dot=%.4f" % [
			caller_s, str(_direction), str(_force), str(typeof(_force)), str(pv), dot])
	var ai = _lib._caller if _lib else null
	if ai == null or not is_instance_valid(ai):
		return
	var iid = ai.get_instance_id()
	var now = Time.get_ticks_msec()
	if _player_hits.has(iid) and now - int(_player_hits[iid]) < 15000:
		_kill_count += 1
	_player_hits.erase(iid)

func _on_controller_process(_delta: float) -> void:
	var controller = _lib._caller if _lib else null
	if not is_instance_valid(controller):
		return
	var gd = _resolve_gamedata()
	if gd == null:
		return
	if bool(gd.get("tutorial")):
		return
	if _ironman_active and not _ironman_initialized and not bool(gd.get("isDead", false)):
		gd.set("permadeath", true)
		_ironman_initialized = true
		print("[VTK] Applied ironman mode after restart")
	var now = Time.get_ticks_msec()
	var stale: Array = []
	for iid in _player_hits:
		if now - int(_player_hits[iid]) > 30000:
			stale.append(iid)
	for s in stale:
		_player_hits.erase(s)

func _handle_death_screen(gd, is_dead: bool, is_ironman: bool) -> void:
	if not is_dead or not is_ironman:
		if _death_restart_btn != null and is_instance_valid(_death_restart_btn):
			_death_restart_btn.queue_free()
			_death_restart_btn = null
		_restore_load_button()
		_death_find_since = 0
		_death_is_ironman = false
		if not is_ironman and not _ironman_pending:
			_ironman_active = false
			_ironman_initialized = false
		return

	if _death_restart_btn != null and is_instance_valid(_death_restart_btn):
		return

	if _death_load_btn != null and is_instance_valid(_death_load_btn):
		return

	_death_is_ironman = is_ironman
	var now := Time.get_ticks_msec()
	if _death_find_since == 0:
		_death_find_since = now
		print("[VTK] death screen tracking started @" + str(now))

	# Only ever touch the Death scene. Walking the root re-found a dozen
	# unrelated buttons ("Continue to Main Menu", JCM, the Settings tree) and
	# buried the real one under hundreds of MCM lines.
	var root := _death_scene_root()
	if root == null:
		return

	var load_btn := _find_load_button(root)
	if load_btn != null:
		_repurpose_load_button(load_btn, gd, root)
		return

	var waited := now - _death_find_since
	if waited < DEATH_FIND_TIMEOUT_MS:
		_dump_death_tree(root, waited, now)
		return
	print("[VTK] No 'Load Game' button after " + str(waited) + "ms, using fallback panel")
	_build_fallback_panel(gd, root)

# The real Death scene, so the search never walks the whole Interface tree.
# A dump taken over the root for four seconds showed only UI/MCM nodes and no
# scene nodes at all, which is what the missing button actually looked like.
func _death_scene_root() -> Node:
	var cs = get_tree().current_scene
	if cs != null and cs.name == "Death":
		return cs
	return get_tree().root.get_node_or_null("Death")

func _find_load_button(root: Node) -> BaseButton:
	var best: BaseButton = null
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is BaseButton:
			var b := n as BaseButton
			var t := String(b.text).strip_edges().to_lower()
			if t == "load game":
				return b
			if best == null and b.visible and not b.disabled and (t.begins_with("load") or t == "continue"):
				best = b
		for c in n.get_children():
			stack.push_back(c)
	return best

func _dump_death_tree(root: Node, waited: int, now: int) -> void:
	if now - _death_dump_at < 1000:
		return
	_death_dump_at = now
	var lines: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is BaseButton:
			var b := n as BaseButton
			var bt := String(b.text).strip_edges()
			lines.append("[VTK]   " + b.get_class() + " path='" + str(b.get_path()) + "' name='" + str(b.name) + "' text='" + bt + "' tip='" + str(b.tooltip_text) + "' vis=" + str(b.visible) + " dis=" + str(b.disabled) + " focus=" + str(b.focus_mode) + " conns=" + str(b.pressed.get_connections().size()))
		elif n is Control:
			var c := n as Control
			var txt := ""
			if "text" in c:
				txt = String(c.get("text"))
			elif c is RichTextLabel:
				txt = String((c as RichTextLabel).get_parsed_text())
			if txt.strip_edges() != "":
				lines.append("[VTK]   " + c.get_class() + " path='" + str(c.get_path()) + "' text='" + txt + "' vis=" + str(c.visible))
		for ch in n.get_children():
			stack.push_back(ch)
	print("[VTK] death tree @" + str(waited) + "ms:\n" + "\n".join(lines))

func _repurpose_load_button(btn: BaseButton, gd, root) -> void:
	_death_load_btn = btn
	_death_load_orig_text = btn.text
	_death_load_orig_disabled = btn.disabled
	_death_load_orig_conns = []
	for c in btn.pressed.get_connections():
		var cb = c["callable"]
		_death_load_orig_conns.append(cb)
		btn.pressed.disconnect(cb)
	_death_load_bound = _on_restart_pressed.bind(gd, root)
	btn.pressed.connect(_death_load_bound)
	btn.text = "Restart"
	btn.disabled = false
	print("[VTK] Death 'Load Game' button repurposed to Restart")

func _restore_load_button() -> void:
	if _death_load_btn == null:
		return
	if not is_instance_valid(_death_load_btn):
		_death_load_btn = null
		return
	var btn := _death_load_btn as Button
	if _death_load_bound != null and btn.pressed.is_connected(_death_load_bound):
		btn.pressed.disconnect(_death_load_bound)
	btn.text = _death_load_orig_text
	btn.disabled = _death_load_orig_disabled
	for cb in _death_load_orig_conns:
		if not btn.pressed.is_connected(cb):
			btn.pressed.connect(cb)
	_death_load_btn = null
	_death_load_bound = null
	_death_load_orig_conns = []

func _build_fallback_panel(gd, root) -> void:
	# root is the Death scene node, which is not a Control and has no .size.
	# Size the panel off the viewport instead.
	var vp := get_viewport()
	var vs := vp.get_visible_rect().size if vp != null else Vector2(1920.0, 1080.0)
	var cl = CanvasLayer.new()
	cl.layer = 128
	cl.name = "VTKRestartOverlay"
	root.add_child(cl)

	var panel = Panel.new()
	panel.size = Vector2(300, 220)
	panel.position = Vector2(
		vs.x / 2.0 - 150.0,
		vs.y / 2.0 - 110.0
	)
	cl.add_child(panel)

	var btn_restart = Button.new()
	btn_restart.text = "Restart"
	btn_restart.size = Vector2(260, 50)
	btn_restart.position = Vector2(20, 20)
	panel.add_child(btn_restart)
	btn_restart.pressed.connect(_on_restart_pressed.bind(gd, root))

	var btn_menu = Button.new()
	btn_menu.text = "Main Menu"
	btn_menu.size = Vector2(260, 50)
	btn_menu.position = Vector2(20, 85)
	panel.add_child(btn_menu)
	btn_menu.pressed.connect(_on_menu_pressed)

	var btn_quit = Button.new()
	btn_quit.text = "Quit"
	btn_quit.size = Vector2(260, 50)
	btn_quit.position = Vector2(20, 150)
	panel.add_child(btn_quit)
	btn_quit.pressed.connect(_on_quit_pressed)

	_death_restart_btn = cl
	print("[VTK] Death overlay created (ironman)")

func _wipe_saves_for_restart() -> void:
	var ldr = get_node_or_null("/root/Loader")
	if ldr != null and ldr.has_method("FormatSave"):
		print("[VTK] Restart: wiping saves via Loader.FormatSave()")
		ldr.call("FormatSave")
		return
	var dir = DirAccess.open("user://")
	if dir == null:
		print("[VTK] Restart: ERROR cannot open user://")
		return
	var names: Array = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres") and f != "Validator.tres" and f != "Preferences.tres":
			names.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	for n in names:
		var path := "user://" + String(n)
		if dir.remove(path) == OK:
			print("[VTK] Restart: removed " + String(n))
		else:
			print("[VTK] Restart: FAILED to remove " + String(n))


func _on_restart_pressed(gd, root) -> void:
	print("[VTK] Restart: starting new game...")
	_ironman_active = _death_is_ironman
	_ironman_pending = _death_is_ironman
	_death_latched = false
	_gd_node = null
	if _death_restart_btn != null and is_instance_valid(_death_restart_btn):
		_death_restart_btn.queue_free()
		_death_restart_btn = null
	_death_load_btn = null
	_death_load_bound = null
	_death_load_orig_conns = []
	if gd == null:
		print("[VTK] Restart: no GameData, aborting")
		return
	gd.set("isDead", false)
	var hp := 100.0
	var st := 100.0
	var en := 100.0
	var hy := 100.0
	var me := 100.0
	if _death_is_ironman:
		hp = randf_range(IRONMAN_VITAL_MIN, IRONMAN_VITAL_MAX)
		st = randf_range(IRONMAN_VITAL_MIN, IRONMAN_VITAL_MAX)
		en = randf_range(IRONMAN_VITAL_MIN, IRONMAN_VITAL_MAX)
		hy = randf_range(IRONMAN_VITAL_MIN, IRONMAN_VITAL_MAX)
		me = randf_range(IRONMAN_VITAL_MIN, IRONMAN_VITAL_MAX)
	gd.health = hp
	gd.armStamina = st
	gd.bodyStamina = st
	gd.energy = en
	gd.hydration = hy
	gd.mental = me
	gd.temperature = 100.0
	gd.oxygen = 100.0
	gd.set("bleeding", false)
	gd.set("fracture", false)
	gd.set("rupture", false)
	gd.set("burn", false)
	gd.set("frostbite", false)
	gd.set("insanity", false)
	gd.set("dehydration", false)
	gd.set("headshot", false)
	gd.set("poisoning", false)
	gd.set("tutorial", false)
	gd.set("previousMap", "")
	var start_map = "Cabin"
	if _death_is_ironman:
		start_map = IRONMAN_MAPS[randi() % IRONMAN_MAPS.size()]
		gd.set("shelter", false)
		gd.set("permadeath", true)
		gd.set("difficulty", 3)
	else:
		gd.set("shelter", true)
		gd.set("permadeath", false)
	gd.set("currentMap", start_map)
	_wipe_saves_for_restart()
	var ldr = get_node_or_null("/root/Loader")
	if ldr != null:
		ldr.LoadScene(start_map)
		print("[VTK] Restart: loading " + start_map + " ironman=" + str(_death_is_ironman))
	else:
		print("[VTK] Restart: ERROR - Loader not found")

func _on_menu_pressed() -> void:
	print("[VTK] Menu: loading Menu scene...")
	_ironman_active = false
	_ironman_initialized = false
	_ironman_pending = false
	if _death_restart_btn != null and is_instance_valid(_death_restart_btn):
		_death_restart_btn.queue_free()
		_death_restart_btn = null
	var l = get_node_or_null("/root/Loader")
	if l != null:
		l.LoadScene("Menu")

func _on_quit_pressed() -> void:
	print("[VTK] Quit: exiting game...")
	get_tree().quit()