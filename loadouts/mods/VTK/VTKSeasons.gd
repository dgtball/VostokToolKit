extends RefCounted
## Чистая логика динамических сезонов: цикл по дням, отображение на ванильные сезоны.
## Ни load(), ни путей внутрь игры: на вход обычные числа,
## поэтому модуль покрыт headless-тестом test_seasons.gd.

const SEASONS := ["spring", "summer", "autumn", "winter"]

static func resolve_index(day: int, cycle_days: int, start_offset: int) -> int:
	var cycle := cycle_days
	if cycle < 1:
		cycle = 1
	var block := (day - 1) / cycle
	return posmod(block + start_offset, SEASONS.size())

static func vanilla_season(index: int) -> int:
	return 2 if index == 3 else 1

static func is_winter(index: int) -> bool:
	return index == 3
