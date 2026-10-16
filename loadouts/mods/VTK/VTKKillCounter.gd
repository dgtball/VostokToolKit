extends Control
const Paths = preload("res://mods/VTK/VTKPaths.gd")
const Log = preload("res://mods/VTK/VTKLog.gd")

var _enabled: bool = false
var _label: Label = null
var _panel: PanelContainer = null
var _kills: int = 0
var _alive_cnt: int = 0
var _nomad_cnt: int = 0
var _accum: float = 0.0
var _was_shelter: bool = false
var _iface: Node = null
var _hooks_node: Node = null
var _agents: Dictionary = {}
var _pending: Array[int] = []
var _scene_ref: Node = null

func _ready() -> void:
	name = "VTKKillCounter"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Подложка: без неё светлый HUD на солнце съедает надпись. Тот же приём,
	# что у строки ленты (VTKFeed): чёрный 0.45 + узкие поля.
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = Vector2(10, 10)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	_panel.add_theme_stylebox_override("panel", sb)
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	_label.add_theme_font_size_override("font_size", 13)
	var hud := Paths.hud_font()
	if hud != null:
		_label.add_theme_font_override("font", hud)
	_panel.add_child(_label)
	_panel.visible = false
	add_child(_panel)
	get_tree().node_added.connect(_on_node_added)

func set_enabled(v: bool) -> void:
	_enabled = v
	_panel.visible = v
	if v:
		_reseed()
	if not v:
		_kills = 0
		_alive_cnt = 0
		_nomad_cnt = 0
		_agents.clear()
		_label.text = ""

func _on_node_added(node: Node) -> void:
	# Батчим: загрузчик за кадр добавляет целые поддеревья, и call_deferred на
	# каждый узел — это отдельный instance_from_id + agent_kind lookup. Копим
	# id, разбираем одним проходом раз за кадр в начале своего _process.
	_pending.append(node.get_instance_id())

func _drain_pending() -> void:
	if _pending.is_empty():
		return
	for id in _pending:
		_deferred_check(id)
	_pending.clear()

func _deferred_check(node_id: int) -> void:
	if not _enabled:
		return
	var n := instance_from_id(node_id)
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return
	var kind := agent_kind(n)
	if kind != "":
		_agents[node_id] = kind

# Игровой агент AI.gd несёт @export identifier+var variant: AIData (AI.gd:20/60),
# а не только Activate/dead. variant - устойчивый маркер агента и источник
# фракции/имени, в отличие от duck-typing по методам и разбора имён узлов.
static func _is_agent(n: Node) -> bool:
	return n is Node3D and "variant" in n

# AIData.Faction (headless probe): Nomad 0, Bandit 1, Guard 2, Military 3, Boss 4.
const FACTION_NOMAD := 0
const FACTION_BOSS := 4

static func agent_kind(n: Node) -> String:
	if not _is_agent(n):
		return ""
	var v = n.get("variant")
	if v == null:
		return ""
	var f := int(v.get("faction"))
	if f == FACTION_NOMAD:
		return "nomad"
	if f == FACTION_BOSS:
		return ""
	return "enemy"

static func agent_display_name(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return "NPC"
	var v = n.get("variant")
	if v == null:
		return "NPC"
	var s := str(v.get("name")).strip_edges()
	if s != "":
		return s
	return "NPC"

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
	_iface = root.get_node_or_null(Paths.INTERFACE)
	return _iface

func _get_hooks() -> Node:
	if _hooks_node != null and is_instance_valid(_hooks_node):
		return _hooks_node
	var parent = get_node_or_null(Paths.UI_ROOT)
	if parent == null:
		# Промах раньше молча останавливал счётчик: флаг оставался включённым,
		# узел жил, но считал ноль. Один след на путь.
		Log.warn_once(Paths.UI_ROOT, "kill counter: VTKUI autoload missing")
		return _hooks_node
	_hooks_node = parent.get_node_or_null(Paths.HOOKS)
	if _hooks_node == null:
		Log.warn_once(Paths.UI_ROOT + "/" + Paths.HOOKS, "kill counter: VTKHooks missing")
	return _hooks_node

func _reset_counters() -> void:
	_kills = 0
	_alive_cnt = 0
	_nomad_cnt = 0
	var hooks = _get_hooks()
	if hooks != null and is_instance_valid(hooks) and hooks.has_method("reset_kills"):
		hooks.reset_kills()

func _is_shelter() -> bool:
	var iface = _get_iface()
	if iface == null:
		return false
	var gd = iface.get("gameData")
	if gd == null:
		return false
	return bool(gd.get("shelter"))

func _process(delta: float) -> void:
	_drain_pending()
	if not _enabled:
		return
	# Смена сцены дешёвая и должна сбрасывать счётчик сразу; чтение
	# gameData.shelter - только на тике (0.5 с), HUD и так обновляется там же.
	var map_changed := get_tree().current_scene != _scene_ref
	if map_changed:
		_reset_counters()
	_accum += delta
	if _accum < 0.5:
		return
	_accum = 0.0
	var in_shelter := _is_shelter()
	if in_shelter and not _was_shelter:
		_reset_counters()
		_label.text = "Shelter"
	_was_shelter = in_shelter
	if in_shelter:
		return
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
