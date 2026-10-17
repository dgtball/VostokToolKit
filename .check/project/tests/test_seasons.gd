extends SceneTree

const S = preload("res://mods/VTK/VTKSeasons.gd")

var fails := 0

func ck(cond: bool, msg: String) -> void:
	if cond:
		print("ok    ", msg)
	else:
		fails += 1
		print("FAIL  ", msg)

func _init() -> void:
	t_seasons_order()
	t_resolve_index()
	t_vanilla_season()
	t_is_winter()
	print("")
	if fails == 0:
		print("Seasons tests passed")
		quit(0)
	else:
		print("Seasons tests failed: ", fails)
		quit(1)

func t_seasons_order() -> void:
	ck(S.SEASONS == ["spring", "summer", "autumn", "winter"], "SEASONS: весна-лето-осень-зима")

func t_resolve_index() -> void:
	ck(S.resolve_index(1, 30, 0) == 0, "день 1 цикла 30 со стартом 0 - весна")
	ck(S.resolve_index(1, 30, 1) == 1, "день 1 со стартом 1 - лето")
	ck(S.resolve_index(30, 30, 0) == 0, "последний день сезона ещё в нём")
	ck(S.resolve_index(31, 30, 0) == 1, "первый день следующего сезона")
	ck(S.resolve_index(91, 30, 0) == 3, "третий переход - зима")
	ck(S.resolve_index(121, 30, 0) == 0, "второй круг заворачивается к весне")

func t_vanilla_season() -> void:
	ck(S.vanilla_season(3) == 2, "зима - ванильный сезон 2")
	ck(S.vanilla_season(0) == 1, "весна - ванильный сезон 1")
	ck(S.vanilla_season(1) == 1, "лето - ванильный сезон 1")
	ck(S.vanilla_season(2) == 1, "осень - ванильный сезон 1")

func t_is_winter() -> void:
	ck(S.is_winter(3), "индекс 3 - зима")
	ck(not S.is_winter(0), "индекс 0 - не зима")
