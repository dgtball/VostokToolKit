extends RefCounted
# Hard paths into the game used by ThermalVTK. Absolute NodePaths from the tree
# root, so they resolve through get_node_or_null(...) from any node. Fix here on
# a game update, not in each file.

const LOADER := "/root/Loader"
const NVG := "/root/Map/Core/UI/NVG"
const GAME_DATA := "res://Resources/GameData.tres"
