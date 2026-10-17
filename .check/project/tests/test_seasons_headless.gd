extends SceneTree

# Заглушка-бегун: грузит сам тест и запускает его. Сам тест наследует SceneTree и
# прогоняется в _init, поэтому достаточно инстанцировать скрипт.
func _init() -> void:
	load("res://tests/test_seasons.gd").new()
	quit(0)
