extends Control

var _enabled: bool = false
var _label: Label = null
var _kills: int = 0
var _alive_cnt: int = 0
var _nomad_cnt: int = 0
var _accum: float = 0.0
var _was_shelter: bool = false
var _iface: Node = null
var _hooks_node: Node = null
var _agents: Dictionary = {}
var _scene_ref: Node = null

func _ready() -> void:
	name = "VTKKillCounter"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_label.add_theme_font_size_override("font_size", 13)
	_label.position = Vector2(10, 10)
	_label.visible = false
	add_child(_label)
	get_tree().node_added.connect(_on_node_added)

func set_enabled(v: bool) -> void:
	_enabled = v
	_label.visible = v
	if v:
		_reseed()
	if not v:
		_kills = 0
		_alive_cnt = 0
		_nomad_cnt = 0
		_agents.clear()
		_label.text = ""

func _on_node_added(node: Node) -> void:
	call_deferred("_deferred_check", node.get_instance_id())

func _deferred_check(node_id: int) -> void:
	if not _enabled:
		return
	var n := instance_from_id(node_id)
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return
	var kind := agent_kind(n)
	if kind != "":
		_agents[node_id] = kind

# AISpawner.gd never calls add_to_group() on itself, so walking the
# "AISpawner" group always comes back empty. Match bots by the same
# signature the NVG node uses instead -- a node with an Activate() entry
# point and a `dead` flag.
static func _is_agent(n: Node) -> bool:
	return n is Node3D and n.has_method("Activate") and "dead" in n

# Vanilla keeps spawned AI under fixed pools: /root/Map/AI/E_Pool holds the
# Bandits/Guards, N_Pool the Nomads, B_Pool the Bogeyman/Punisher. Some maps also
# Classify by the agent's own script, not by the pool it sits in.
# AISpawner reparents every activated agent out of E_Pool/N_Pool into the shared
# "Enemies" node, so walking up the ancestor chain reported a live AI_Nomad as an
# enemy the moment it spawned -- which is how a Nomad ended up in the enemy tally.
# AISpawner preloads res://AI/Nomad/AI_Nomad.tscn and the hostiles from
# res://AI/Bandit, /Guard, /Military, so the script name is the stable identity.
const SCRIPT_NOMAD := "AI_Nomad"
const SCRIPTS_ENEMY := ["AI_Bandit", "AI_Guard", "AI_Military"]

# Every bot shares the same AI.gd base script, so get_script().resource_path
# only ever yields "AI" and never names the variant. The instantiated node name
# is what actually carries the identity (AI_Nomad, AI_Bandit, ...), and its
# scene owner carries it too. Test all of them and take the first that matches.
static func agent_kind(n: Node) -> String:
	if not _is_agent(n):
		return ""
	for cand in _identities(n):
		if cand.begins_with(SCRIPT_NOMAD):
			return "nomad"
		for e in SCRIPTS_ENEMY:
			if cand.begins_with(String(e)):
				return "enemy"
	# Punisher/Bogeyman (B_Pool) and anything else stay uncounted.
	return ""

# Pool instances created without a preset name come out as "@Node3D@N" and
# carry no "AI_" identity, but the faction model under them is always named
# (probe: /root/Map/AI/Enemies/@Node3D@1056/Bandit). Used by the kill feed.
const MODEL_NAMES := ["Bandit", "Guard", "Military", "Nomad", "Punisher", "Bogeyman"]

static func agent_display_name(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return "NPC"
	if "boss" in n and bool(n.get("boss")):
		return "Punisher"
	for cand in _identities(n):
		var s := String(cand)
		if s.begins_with("AI_"):
			return s.substr(3)
	for c in n.get_children():
		var cn := String(c.name)
		if cn in MODEL_NAMES:
			return cn
	var kind := agent_kind(n)
	if kind == "nomad":
		return "Nomad"
	return "NPC"

static func _identities(n: Node) -> Array:
	var out: Array = []
	var s = n.get_script()
	if s != null:
		var path := String(s.resource_path)
		if path != "":
			var b := path.get_file().get_basename()
			if b != "" and b != "AI":
				out.append(b)
	var nm := String(n.name)
	if nm != "":
		out.append(nm)
	var o = n.owner
	if o != null:
		var on := String(o.name)
		if on != "":
			out.append(on)
	return out

func _reseed() -> void:
	_agents.clear()
	_scene_ref = get_tree().current_scene
	if _scene_ref == null:
		return
	_scan(_scene_ref)

func _scan(n: Node) -> void:
	var kind := agent_kind(n)
	if kind != "":
		_agents[n.get_instance_id()] = kind
	for c in n.get_children():
		_scan(c)

func _get_iface() -> Node:
	if _iface != null and is_instance_valid(_iface):
		return _iface
	var root = get_tree().root
	_iface = root.get_node_or_null("Map/Core/UI/Interface")
	return _iface

func _get_hooks() -> Node:
	if _hooks_node != null and is_instance_valid(_hooks_node):
		return _hooks_node
	var parent = get_node_or_null("/root/VTKUI")
	if parent != null:
		_hooks_node = parent.get_node_or_null("VTKHooks")
	return _hooks_node

func _reset_counters() -> void:
	_kills = 0
	_alive_cnt = 0
	_nomad_cnt = 0
	var hooks = _get_hooks()
	if hooks != null and is_instance_valid(hooks) and hooks.has_method("reset_kills"):
		hooks.reset_kills()

func _process(delta: float) -> void:
	if not _enabled:
		return
	var iface = _get_iface()
	var in_shelter = false
	if iface != null:
		var gd = iface.get("gameData")
		if gd != null:
			in_shelter = bool(gd.get("shelter"))
	# A map change is signalled by the current_scene pointer moving to a new
	# node. Entering a shelter also needs a reset, but the two can coincide
	# (teleport straight into a shelter), so check the map change first and let
	# the shelter branch below still run to label the HUD.
	var map_changed := get_tree().current_scene != _scene_ref
	if map_changed:
		_reset_counters()
	if in_shelter and not _was_shelter:
		_reset_counters()
		_label.text = "Shelter"
	_was_shelter = in_shelter
	if in_shelter:
		return
	_accum += delta
	if _accum < 0.5:
		return
	_accum = 0.0
	# A map change wipes every bot; re-walk the fresh scene or the count
	# would keep reading nodes that no longer exist.
	if map_changed:
		_reseed()
	_tick()

func _tick() -> void:
	var hooks = _get_hooks()
	if hooks != null and is_instance_valid(hooks) and hooks.has_method("get_kill_count"):
		_kills = hooks.get_kill_count()
	_alive_cnt = 0
	_nomad_cnt = 0
	var stale: Array = []
	for iid in _agents.keys():
		var a = instance_from_id(iid)
		if a == null or not is_instance_valid(a):
			stale.append(iid)
			continue
		# AI.gd keeps a pool of pre-built bots parked off-map with active=false
		# (CreatePools calls Deactivate on each), and only flips it true in
		# Activate(). So counting the pool membership alone reported ~15 bots on
		# a map whose live cap is 3-5. Gate on `active` so the HUD shows bots
		# actually roaming, and keep counting `dead` separately so a corpse that
		# has not been cleaned up yet stops counting too.
		if bool(a.get("dead")):
			continue
		if not ("active" in a) or not bool(a.get("active")):
			continue
		if _agents[iid] == "nomad":
			_nomad_cnt += 1
		else:
			_alive_cnt += 1
	for iid in stale:
		_agents.erase(iid)
	_label.text = _fmt()

func _fmt() -> String:
	return "Killed: " + str(_kills) + "   Enemies: " + str(_alive_cnt) + "   Nomads: " + str(_nomad_cnt)
