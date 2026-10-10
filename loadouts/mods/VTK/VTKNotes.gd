extends RefCounted
## Логика вкладки Notes: группировка предметов задачи, признак сдачи и
## построение строк иконок. Чистая часть (без узлов) тестируется headless,
## как VTKPicker/VTKDraft: ни load(), ни путей внутрь игры.

static func group_items(items) -> Array:
	var order: Array = []
	if typeof(items) != TYPE_ARRAY:
		return order
	var index := {}
	for it in items:
		if it == null:
			continue
		var key := str(it.get("resource_path"))
		if key == "":
			key = str(it.get("name"))
		if key == "":
			key = str(it)
		if index.has(key):
			var entry: Dictionary = order[index[key]]
			entry["count"] = int(entry["count"]) + 1
		else:
			index[key] = order.size()
			order.append({"item": it, "count": 1})
	return order

static func completed_lists(traders) -> Dictionary:
	var out := {}
	if traders == null:
		return out
	for k in ["generalist", "doctor", "gunsmith", "driver", "hunter", "grandma"]:
		var names = traders.get(k)
		if typeof(names) != TYPE_ARRAY:
			continue
		var set := {}
		for n in names:
			set[str(n)] = true
		out[k] = set
	return out

static func is_completed(task_data, completed) -> bool:
	if task_data == null or typeof(completed) != TYPE_DICTIONARY:
		return false
	var trader := str(task_data.get("trader")).to_lower()
	var sets = completed.get(trader)
	if typeof(sets) != TYPE_DICTIONARY:
		return false
	return sets.has(str(task_data.get("name")))

static func find_note(notes, task_data) -> Variant:
	if typeof(notes) != TYPE_ARRAY or task_data == null:
		return null
	var want_name := str(task_data.get("name"))
	var want_trader := str(task_data.get("trader"))
	for n in notes:
		if n == null:
			continue
		if str(n.get("name")) == want_name and str(n.get("trader")) == want_trader:
			return n
	return null

static func badge_text(count: int) -> String:
	if count > 1:
		return "×" + str(count)
	return ""
