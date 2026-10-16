extends RefCounted
const Surface = preload("res://mods/VTK/VTKSurface.gd")
## Логика вкладки Notes: группировка предметов задачи, признак сдачи,
## построение строк иконок и прогресса вкладов (вариант A). Чистая часть
## (без узлов сцены и без путей внутрь игры) тестируется headless, как
## VTKPicker/VTKDraft: ни load(), ни res:// внутрь игры.

const ICON_CELL := 52.0
const ART_INSET := 6.0

const COL_GOLD_HI := Color(0.878, 0.710, 0.353)   # e0b55a
const COL_GOLD_DIM := Color(0.541, 0.478, 0.416)  # 8a7a6a
const COL_TRACK := Color(0.141, 0.110, 0.071)     # 241c12
const COL_CHIP_BG := Color(0.055, 0.043, 0.031)   # 0e0b08
const COL_CELL_DONE := Color(0.094, 0.141, 0.059) # 18240f
const COL_GREEN := Color(0.549, 0.851, 0.549)     # 8cd98c
const COL_GREEN_DIM := Color(0.306, 0.478, 0.306) # 4e7a4e
const COL_PARTIAL := Color(0.420, 0.306, 0.141)   # 6b4e24
const COL_BORDER := Surface.BORDER
const COL_INK := Color(0.847, 0.804, 0.745)       # d8cdbe

## Ключ группировки: у предмета из БД стабильно есть resource_path; фолбэк —
## имя, затем str(). Notes и покрытие вкладов считают группы одинаково.
static func item_key(item) -> String:
	if item == null:
		return ""
	var key := str(item.get("resource_path"))
	if key == "":
		key = str(item.get("name"))
	if key == "":
		key = str(item)
	return key

static func group_items(items) -> Array:
	var order: Array = []
	if typeof(items) != TYPE_ARRAY:
		return order
	var index := {}
	for it in items:
		if it == null:
			continue
		var key := item_key(it)
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

# --- вариант A: прогресс вкладов -------------------------------------------
# cov_map: { item_key: {"got": int, "need": int} }. Отсутствие ключа = 0/N.

static func progress_totals(entries: Array, cov_map) -> Vector2i:
	var got := 0
	var need := 0
	for e in entries:
		var k := item_key(e.get("item"))
		var g := 0
		var n := int(e.get("count", 1))
		if typeof(cov_map) == TYPE_DICTIONARY:
			var c = cov_map.get(k)
			if typeof(c) == TYPE_DICTIONARY:
				n = int(c.get("need", n))
				g = int(c.get("got", 0))
				if g > n:
					g = n
		got += g
		need += n
	return Vector2i(got, need)

static func build_progress(entries: Array, cov_map) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var totals := progress_totals(entries, cov_map)
	var got := int(totals.x)
	var need := int(totals.y)
	var pct := 0
	if need > 0:
		pct = int(round(float(got) / float(need) * 100.0))
	var line := HBoxContainer.new()
	var left := Label.new()
	left.text = "Deposited " + str(got) + " / " + str(need)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_font_size_override("font_size", 11)
	left.add_theme_color_override("font_color", COL_GOLD_DIM)
	var right := Label.new()
	right.text = str(pct) + "%"
	right.add_theme_font_size_override("font_size", 11)
	right.add_theme_color_override("font_color", COL_GOLD_DIM)
	line.add_child(left)
	line.add_child(right)
	box.add_child(line)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = float(pct)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 4)
	var fill := COL_GREEN if (need > 0 and got >= need) else COL_GOLD_HI
	bar.add_theme_stylebox_override("background", _flat(COL_TRACK, 3))
	bar.add_theme_stylebox_override("fill", _flat(fill, 3))
	box.add_child(bar)
	return box

static func build_progress_row(entries: Array, cov_map) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	for e in entries:
		var k := item_key(e.get("item"))
		var need := int(e.get("count", 1))
		var got := 0
		if typeof(cov_map) == TYPE_DICTIONARY:
			var c = cov_map.get(k)
			if typeof(c) == TYPE_DICTIONARY:
				need = int(c.get("need", need))
				got = int(c.get("got", 0))
				if got > need:
					got = need
		row.add_child(_make_progress_cell(e.get("item"), got, need))
	return row

static func _make_progress_cell(item, got: int, need: int) -> Control:
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(ICON_CELL, ICON_CELL)
	cell.tooltip_text = str(item.get("name")) if item != null else ""
	var done := need > 0 and got >= need
	var partial := got > 0 and not done
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(1)
	sb.bg_color = COL_CELL_DONE if done else COL_CHIP_BG
	sb.border_color = COL_GREEN_DIM if done else (COL_PARTIAL if partial else COL_BORDER)
	cell.add_theme_stylebox_override("panel", sb)
	_add_art(cell, item, 0.55 if partial else 1.0)
	if done:
		var tick := Label.new()
		tick.text = "✓"
		tick.add_theme_font_size_override("font_size", 12)
		tick.add_theme_color_override("font_color", COL_GREEN)
		tick.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		tick.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		tick.anchor_right = 0.5
		tick.anchor_bottom = 0.5
		cell.add_child(tick)
	var chip := Label.new()
	chip.text = str(got) + " / " + str(need)
	chip.add_theme_font_size_override("font_size", 11)
	chip.add_theme_color_override("font_color", COL_GREEN if done else COL_INK)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chip.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	chip.anchor_left = 0.15
	chip.anchor_top = 0.55
	chip.anchor_right = 1.0
	chip.anchor_bottom = 1.0
	cell.add_child(chip)
	return cell

static func _flat(col: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	return sb

# --- строка иконок без прогресса (награда) ----------------------------------

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
	_add_art(cell, item, 1.0)
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

static func _add_art(parent: Control, item, alpha: float) -> void:
	var icon = item.get("icon") if item != null else null
	if icon is Texture2D:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = ART_INSET
		tr.offset_top = ART_INSET
		tr.offset_right = -ART_INSET
		tr.offset_bottom = -ART_INSET
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.modulate.a = alpha
		parent.add_child(tr)
	else:
		var fallback := Label.new()
		fallback.text = str(item.get("name")) if item != null else ""
		fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		fallback.offset_left = 4
		fallback.offset_top = 4
		fallback.offset_right = -4
		fallback.offset_bottom = -4
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fallback.add_theme_font_size_override("font_size", 9)
		fallback.modulate.a = alpha
		parent.add_child(fallback)

# --- сборка карточки заметки ------------------------------------------------

static func augment_note(card, cov_map := {}) -> void:
	if card == null:
		return
	_remove_blocks(card)
	var task_data = card.get("taskData")
	if task_data == null:
		return
	_apply_deliver(card, task_data, cov_map)
	_apply_section(card.get("outputItems"), card.get("outputGrid"), task_data.get("receive"))

## Снимает ранее вставленные блоки, чтобы повторный augment_note (live-refresh
## после вклада) заменял прогресс, а не наслаивал его.
static func _remove_blocks(card) -> void:
	if card == null or not (card is Node):
		return
	for nm in ["VTKNoteDeliver", "VTKNoteReward"]:
		var n = card.find_child(nm, true, false)
		while n != null:
			var p = n.get_parent()
			if p != null:
				p.remove_child(n)
			n.queue_free()
			n = card.find_child(nm, true, false)

static func _apply_deliver(card, task_data, cov_map) -> void:
	var items_label = card.get("inputItems")
	var section = items_label.get_parent() if (items_label != null and items_label is Node) else null
	if section == null:
		return
	var container = section.get_parent()
	if container == null:
		return
	if items_label != null and items_label is Node:
		items_label.visible = false
	var grid = card.get("inputGrid")
	if grid != null and grid is Node:
		grid.visible = false
	var entries := group_items(task_data.get("deliver"))
	if entries.is_empty():
		return
	var block := VBoxContainer.new()
	block.name = "VTKNoteDeliver"
	block.add_theme_constant_override("separation", 4)
	block.add_child(build_progress(entries, cov_map))
	block.add_child(build_progress_row(entries, cov_map))
	container.add_child(block)
	container.move_child(block, section.get_index() + 1)

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
	row.name = "VTKNoteReward"
	container.add_child(row)
	container.move_child(row, section.get_index() + 1)
