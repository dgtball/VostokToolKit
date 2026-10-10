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

const ICON_CELL := 52.0

static func build_icon_row(entries: Array) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	for e in entries:
		row.add_child(_make_cell(e.get("item"), int(e.get("count", 1))))
	return row

static func _make_cell(item, count: int) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(ICON_CELL, ICON_CELL)
	cell.tooltip_text = str(item.get("name"))
	var icon = item.get("icon")
	if icon is Texture2D:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(tr)
	else:
		var fallback := Label.new()
		fallback.text = str(item.get("name"))
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fallback.add_theme_font_size_override("font_size", 9)
		cell.add_child(fallback)
	var badge := badge_text(count)
	if badge != "":
		var lbl := Label.new()
		lbl.text = badge
		lbl.anchor_left = 0.55
		lbl.anchor_top = 0.55
		lbl.anchor_right = 1.0
		lbl.anchor_bottom = 1.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		lbl.add_theme_font_size_override("font_size", 11)
		cell.add_child(lbl)
	return cell

static func augment_note(card) -> void:
	if card == null:
		return
	var task_data = card.get("taskData")
	if task_data == null:
		return
	_apply_section(card.get("inputItems"), card.get("inputGrid"), task_data.get("deliver"))
	_apply_section(card.get("outputItems"), card.get("outputGrid"), task_data.get("receive"))

static func _apply_section(items_label, grid, items) -> void:
	var section = items_label.get_parent() if (items_label != null and items_label is Node) else null
	if section == null:
		return
	var container = section.get_parent()
	if container == null:
		return
	if items_label != null and items_label is Node:
		items_label.visible = false
	if grid != null and grid is Node:
		grid.visible = false
	var entries := group_items(items)
	if entries.is_empty():
		return
	var row := build_icon_row(entries)
	container.add_child(row)
	container.move_child(row, section.get_index() + 1)
