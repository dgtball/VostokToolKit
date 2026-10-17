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
	t_resolve_bounds()
	t_start_offset_for()
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
	ck(S.resolve_index(331, 30, 3) == 2, "offset 3 сдвигает второй круг к осени")

func t_resolve_bounds() -> void:
	ck(S.resolve_index(5, 0, 0) == 0, "цикл 0 клампится к 1, деления на ноль нет")
	ck(S.resolve_index(1, -5, 0) == 0, "отрицательный цикл клампится к 1")
	ck(S.resolve_index(1, 30, 7) == 3, "offset вне диапазона сворачивается по модулю")
	ck(S.resolve_index(31, 30, -1) == 0, "отрицательный offset сворачивается по модулю")

func t_start_offset_for() -> void:
	ck(S.start_offset_for("spring") == 0, "spring - offset 0")
	ck(S.start_offset_for("summer") == 1, "summer - offset 1")
	ck(S.start_offset_for("autumn") == 2, "autumn - offset 2")
	ck(S.start_offset_for("winter") == 3, "winter - offset 3")
	ck(S.start_offset_for("SUMMER") == 1, "регистр не важен")
	ck(S.start_offset_for(" Winter ") == 3, "пробелы обрезаются")
	ck(S.start_offset_for("banana") == S.DEFAULT_START_OFFSET, "неизвестное имя - дефолт")
	ck(S.start_offset_for("") == S.DEFAULT_START_OFFSET, "пустая строка - дефолт")
	var rnd_ok := true
	for _i in range(32):
		var v := S.start_offset_for("random")
		if v < 0 or v >= S.SEASONS.size():
			rnd_ok = false
	ck(rnd_ok, "random всегда даёт валидный offset")

func t_vanilla_season() -> void:
	ck(S.vanilla_season(3) == 2, "зима - ванильный сезон 2")
	ck(S.vanilla_season(0) == 1, "весна - ванильный сезон 1")
	ck(S.vanilla_season(1) == 1, "лето - ванильный сезон 1")
	ck(S.vanilla_season(2) == 1, "осень - ванильный сезон 1")

func t_is_winter() -> void:
	ck(S.is_winter(3), "индекс 3 - зима")
	ck(not S.is_winter(0), "индекс 0 - не зима")
