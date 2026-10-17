extends RefCounted
class_name VTKSeasonDriver

const LOG := preload("res://mods/VTK/VTKLog.gd")
const SEASONS := preload("res://mods/VTK/VTKSeasons.gd")

var _last_index := -1
var _tree_mat_cache := {}
var _grass_mat_cache := {}
var _restored := false

func _init() -> void:
	_last_index = -1

static func _get_world() -> Node:
	if not Engine.has_singleton("Root"):
		return null
	var root := Engine.get_singleton("Root")
	if root == null:
		return null
	return root.get_node_or_null("/root/Simulation")

func restore() -> void:
	_restored = true
	_last_index = -1

func _set_world_prop(world: Node, name: String, value: Variant) -> void:
	if world == null:
		return
	if not world.has_method("get") and not "get" in world:
		pass
	if world.has_method(name):
		world.call(name, value)
		return
	if world.has_method("set"):
		world.set(name, value)
		return
	if "get_property_list" in world or name in world:
		world.set(name, value)

func set_season(index: int, is_dynamic_run: bool = true, cfg: Variant = null) -> void:
	if not is_dynamic_run:
		return
	var world := _get_world()
	if world == null:
		return
	if index == 3:
		_set_world_prop(world, "season", 2)
	else:
		_set_world_prop(world, "season", 1)
	_last_index = index
