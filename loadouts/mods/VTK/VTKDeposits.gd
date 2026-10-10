extends RefCounted
## Чистая логика частичной сдачи заданий торговцу (PartialTasks).
## Ни load(), ни путей внутрь игры: на вход обычные словари/массивы,
## поэтому модуль покрыт headless-тестом test_deposits.gd.

static func task_key(path: String, name: String, trader: String) -> String:
	var p := str(path).strip_edges()
	if p != "":
		return p
	return str(name) + "::" + str(trader)

static func normalize_slots(entries) -> Array:
	var out: Array = []
	if typeof(entries) != TYPE_ARRAY:
		return out
	for i in range(entries.size()):
		var e = entries[i]
		var file := ""
		var nm := ""
		var amount := 1
		if e != null and typeof(e) == TYPE_DICTIONARY:
			file = str(e.get("file", ""))
			if file == "":
				file = str(e.get("name", ""))
			nm = str(e.get("name", ""))
			amount = int(e.get("amount", 1))
		if amount < 1:
			amount = 1
		out.append({"index": i, "file": file, "name": nm, "required": amount})
	return out

static func coverage(ledger: Dictionary, key: String, slots: Array) -> Dictionary:
	var task: Dictionary = {}
	if typeof(ledger) == TYPE_DICTIONARY and typeof(ledger.get(key)) == TYPE_DICTIONARY:
		task = ledger[key]
	var per: Array = []
	var all := true
	for s in slots:
		var idx := int(s["index"])
		var req := int(s["required"])
		var dep := int(task.get(idx, 0))
		if dep > req:
			dep = req
		var satisfied := dep >= req
		if not satisfied:
			all = false
		per.append({
			"index": idx,
			"file": str(s["file"]),
			"name": str(s["name"]),
			"required": req,
			"deposited": dep,
			"remaining": req - dep,
			"satisfied": satisfied,
		})
	return {"slots": per, "all_satisfied": all}

static func apply(ledger: Dictionary, key: String, slots: Array, offered: Array) -> Dictionary:
	var out := _copy_ledger(ledger)
	var task: Dictionary = _dup_task(out.get(key, {}))
	var remaining := {}
	for s in slots:
		var idx := int(s["index"])
		remaining[idx] = max(0, int(s["required"]) - int(task.get(idx, 0)))
	var take: Array = []
	if typeof(offered) == TYPE_ARRAY:
		for o in offered:
			if o == null or typeof(o) != TYPE_DICTIONARY:
				continue
			var file := str(o.get("file"))
			var amt := int(o.get("amount", 0))
			if file == "" or amt <= 0:
				continue
			var used := 0
			for s in slots:
				if used >= amt:
					break
				if str(s["file"]) != file:
					continue
				var idx := int(s["index"])
				var rem := int(remaining.get(idx, 0))
				if rem <= 0:
					continue
				var give: int = min(rem, amt - used)
				remaining[idx] = rem - give
				task[idx] = int(task.get(idx, 0)) + give
				used += give
			if used > 0:
				take.append({"ref": o.get("ref"), "amount": used})
	if task.is_empty():
		out.erase(key)
	else:
		out[key] = task
	return {"ledger": out, "take": take}

static func clear_task(ledger: Dictionary, key: String) -> Dictionary:
	var out := _copy_ledger(ledger)
	out.erase(key)
	return out

static func badge_text(deposited: int, required: int) -> String:
	return str(deposited) + " / " + str(required)

static func is_covered(coverage: Dictionary) -> bool:
	return bool(coverage.get("all_satisfied", false))

static func _copy_ledger(ledger) -> Dictionary:
	var out := {}
	if typeof(ledger) != TYPE_DICTIONARY:
		return out
	for k in ledger:
		out[k] = _dup_task(ledger[k])
	return out

static func _dup_task(task) -> Dictionary:
	var out := {}
	if typeof(task) != TYPE_DICTIONARY:
		return out
	for k in task:
		out[k] = int(task[k])
	return out
