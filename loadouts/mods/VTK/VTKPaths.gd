extends RefCounted
# Единый реестр жёстких путей внутрь игры. Все - абсолютные NodePath от корня
# дерева, поэтому резолвятся и через get_tree().root.get_node_or_null(...), и
# через любой узел. При апдейте игры правится одно место, а не шесть файлов.

const INTERFACE := "/root/Map/Core/UI/Interface"
const UI := "/root/Map/Core/UI"
const CONTROLLER := "/root/Map/Core/Controller"
const LOADER := "/root/Loader"
const SIMULATION := "/root/Simulation"
const DATABASE := "/root/Database"
const CAMERA_MANAGER := "/root/Map/Core/Camera/Manager"
const NVG := "/root/Map/Core/UI/NVG"

# Имена сейвов игры в user:// (V17).
const TRADER_SAVE := "user://Traders.tres"
const SHELTER_SAVE_FMT := "user://%s.tres"

# Ресурсы игры.
const GAME_DATA := "res://Resources/GameData.tres"
