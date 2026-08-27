class_name InitiativeBar
extends PanelContainer

signal unit_focus_requested(unit_id: int)

const ALLY_COLOR := Color(0.08, 0.35, 0.68, 0.96)
const ENEMY_COLOR := Color(0.68, 0.12, 0.12, 0.96)
const ACTIVE_BORDER := Color(1.0, 0.83, 0.28, 1.0)
const MAX_VISIBLE_CARDS := 6

var card_row: HBoxContainer
var order_label: Label
var previous_button: Button
var next_button: Button
var unit_buttons: Dictionary = {}
var ordered_unit_ids: Array[int] = []
var active_unit_id: int = -1
var action_states: Dictionary = {}
var action_tweens: Dictionary = {}
var visible_start_index: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _make_panel_style())
	_build_interface()


func _build_interface() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 3)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	margin.add_child(column)

	order_label = Label.new()
	order_label.text = "行动顺序"
	order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_label.add_theme_font_size_override("font_size", 12)
	order_label.add_theme_color_override("font_color", Color(0.94, 0.91, 0.8))
	column.add_child(order_label)

	var queue_row := HBoxContainer.new()
	queue_row.alignment = BoxContainer.ALIGNMENT_CENTER
	queue_row.add_theme_constant_override("separation", 4)
	queue_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(queue_row)

	previous_button = _make_navigation_button("‹", "查看前面的行动单位")
	previous_button.pressed.connect(_show_previous_window)
	queue_row.add_child(previous_button)

	card_row = HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 5)
	queue_row.add_child(card_row)

	next_button = _make_navigation_button("›", "查看后续行动单位")
	next_button.pressed.connect(_show_next_window)
	queue_row.add_child(next_button)


func refresh_units() -> void:
	if card_row == null:
		return
	_stop_all_tweens()
	for child in card_row.get_children():
		child.queue_free()
	unit_buttons.clear()
	ordered_unit_ids.clear()

	# 直接使用TurnManager的正式行动队列，保证显示顺序与实际执行完全一致。
	var units: Array[UnitBase] = TurnManager.get_current_action_order()

	for index in range(units.size()):
		var unit := units[index]
		ordered_unit_ids.append(unit.unit_id)
		var card := _make_unit_card(unit, index + 1)
		card_row.add_child(card)
		unit_buttons[unit.unit_id] = card
	visible_start_index = clampi(visible_start_index, 0, maxi(0, units.size() - MAX_VISIBLE_CARDS))
	_update_card_window()
	set_active_unit(active_unit_id)


func get_ordered_unit_ids() -> Array[int]:
	return ordered_unit_ids.duplicate()


func set_active_unit(unit_id: int) -> void:
	active_unit_id = unit_id
	var active_index := ordered_unit_ids.find(unit_id)
	if active_index >= 0 and (active_index < visible_start_index \
			or active_index >= visible_start_index + MAX_VISIBLE_CARDS):
		visible_start_index = clampi(active_index - int(MAX_VISIBLE_CARDS / 2),
			0, maxi(0, ordered_unit_ids.size() - MAX_VISIBLE_CARDS))
	_update_card_window()
	for id in unit_buttons.keys():
		_apply_button_visual(int(id))


func _make_navigation_button(glyph: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = glyph
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(24, 42)
	button.add_theme_font_size_override("font_size", 22)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _make_card_style(Color(0.12, 0.14, 0.18, 0.9), Color(0.40, 0.44, 0.50, 0.9), 1))
	button.add_theme_stylebox_override("hover", _make_card_style(Color(0.19, 0.23, 0.29, 0.96), Color(0.80, 0.84, 0.88, 1.0), 1))
	return button


func _show_previous_window() -> void:
	visible_start_index = maxi(0, visible_start_index - MAX_VISIBLE_CARDS)
	_update_card_window()


func _show_next_window() -> void:
	visible_start_index = mini(maxi(0, ordered_unit_ids.size() - MAX_VISIBLE_CARDS),
		visible_start_index + MAX_VISIBLE_CARDS)
	_update_card_window()


func _update_card_window() -> void:
	var total := ordered_unit_ids.size()
	if total == 0:
		order_label.text = "行动顺序"
		return
	var max_start := maxi(0, total - MAX_VISIBLE_CARDS)
	visible_start_index = clampi(visible_start_index, 0, max_start)
	var end_index := mini(total, visible_start_index + MAX_VISIBLE_CARDS)
	for index in range(total):
		var unit_id := ordered_unit_ids[index]
		var button := unit_buttons.get(unit_id) as Button
		if button:
			button.visible = index >= visible_start_index and index < end_index
	if previous_button:
		previous_button.disabled = visible_start_index <= 0
	if next_button:
		next_button.disabled = end_index >= total
	order_label.text = "行动 %d-%d / %d" % [visible_start_index + 1, end_index, total]


func reset_action_states() -> void:
	_stop_all_tweens()
	action_states.clear()
	active_unit_id = -1
	for unit_id in unit_buttons.keys():
		_apply_button_visual(int(unit_id))


func set_unit_acting(unit_id: int) -> void:
	if not unit_buttons.has(unit_id):
		return
	var state_changed := String(action_states.get(unit_id, "pending")) != "acting"
	action_states[unit_id] = "acting"
	set_active_unit(unit_id)
	if state_changed:
		SoundManager.play("initiative_active", -9.0)


func set_unit_completed(unit_id: int, play_sound: bool = true) -> void:
	if not unit_buttons.has(unit_id):
		return
	var was_completed := String(action_states.get(unit_id, "pending")) == "completed"
	action_states[unit_id] = "completed"
	if active_unit_id == unit_id:
		active_unit_id = -1
	_apply_button_visual(unit_id)
	var button := unit_buttons[unit_id] as Button
	button.modulate = Color.WHITE
	var tween := create_tween()
	tween.tween_property(button, "modulate", Color(0.48, 0.48, 0.52, 0.82), 0.22)
	action_tweens[unit_id] = tween
	if play_sound and not was_completed:
		SoundManager.play("initiative_complete", -12.0)


func complete_remaining_units() -> void:
	for unit_id in ordered_unit_ids:
		if String(action_states.get(unit_id, "pending")) != "completed":
			set_unit_completed(unit_id, false)


func contains_screen_point(screen_position: Vector2) -> bool:
	return visible and get_global_rect().has_point(screen_position)


func _make_unit_card(unit: UnitBase, order_number: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(84, 42)
	button.text = "%02d　先手%d\n%s" % [order_number, unit.initiative, _short_name(unit.unit_name)]
	button.set_meta("base_text", button.text)
	button.clip_text = true
	button.tooltip_text = "%s\n阵营：%s　配置表先手值：%d　速度：%.1f\n点击定位到该单位" % [
		unit.unit_name,
		"华约" if unit.faction == UnitBase.Faction.WARSAW_PACT else "北约",
		unit.initiative,
		unit.move_speed,
	]
	button.add_theme_font_size_override("font_size", 12)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(func() -> void:
		set_active_unit(unit.unit_id)
		_animate_card_selection(unit.unit_id)
		SoundManager.play("initiative_focus", -9.0)
		unit_focus_requested.emit(unit.unit_id)
	)
	_apply_card_style(button, unit.faction, unit.unit_id == active_unit_id)
	return button


func _apply_button_visual(unit_id: int) -> void:
	if not unit_buttons.has(unit_id):
		return
	_stop_tween(unit_id)
	var button := unit_buttons[unit_id] as Button
	var unit := _get_unit_by_id(unit_id)
	if unit == null:
		return
	var state := String(action_states.get(unit_id, "pending"))
	var base_text := String(button.get_meta("base_text", button.text))
	button.text = ("✓ " + base_text) if state == "completed" else base_text
	button.scale = Vector2.ONE
	button.rotation = 0.0
	button.modulate = Color(0.48, 0.48, 0.52, 0.82) if state == "completed" else Color.WHITE
	_apply_card_style(button, unit.faction, unit_id == active_unit_id or state == "acting")
	if state == "acting":
		_start_acting_pulse(unit_id)


func _animate_card_selection(unit_id: int) -> void:
	if not unit_buttons.has(unit_id):
		return
	_stop_tween(unit_id)
	var button := unit_buttons[unit_id] as Button
	button.pivot_offset = button.size * 0.5
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2(1.12, 1.12), 0.08).set_trans(Tween.TRANS_BACK)
	tween.tween_property(button, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_QUAD)
	if String(action_states.get(unit_id, "pending")) == "acting":
		tween.tween_callback(_start_acting_pulse.bind(unit_id))
	action_tweens[unit_id] = tween


func _start_acting_pulse(unit_id: int) -> void:
	if not unit_buttons.has(unit_id) or String(action_states.get(unit_id, "pending")) != "acting":
		return
	_stop_tween(unit_id)
	var button := unit_buttons[unit_id] as Button
	button.pivot_offset = button.size * 0.5
	var tween := create_tween().set_loops()
	tween.tween_property(button, "scale", Vector2(1.07, 1.07), 0.32).set_trans(Tween.TRANS_SINE)
	tween.tween_property(button, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_SINE)
	action_tweens[unit_id] = tween


func _stop_tween(unit_id: int) -> void:
	if action_tweens.has(unit_id):
		var tween := action_tweens[unit_id] as Tween
		if tween != null and tween.is_valid():
			tween.kill()
		action_tweens.erase(unit_id)


func _stop_all_tweens() -> void:
	for unit_id in action_tweens.keys().duplicate():
		_stop_tween(int(unit_id))


func _apply_card_style(button: Button, faction: int, active: bool) -> void:
	var fill := ALLY_COLOR if faction == UnitBase.Faction.WARSAW_PACT else ENEMY_COLOR
	var border := ACTIVE_BORDER if active else fill.lightened(0.32)
	button.add_theme_stylebox_override("normal", _make_card_style(fill, border, 3 if active else 1))
	button.add_theme_stylebox_override("hover", _make_card_style(fill.lightened(0.12), Color.WHITE, 2))
	button.add_theme_stylebox_override("pressed", _make_card_style(fill.darkened(0.12), ACTIVE_BORDER, 3))
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)


func _make_card_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.04, 0.05, 0.84)
	style.border_color = Color(0.46, 0.49, 0.53, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style


func _short_name(full_name: String) -> String:
	return full_name if full_name.length() <= 9 else full_name.substr(0, 8) + "…"


func _get_unit_by_id(unit_id: int) -> UnitBase:
	for node in get_tree().get_nodes_in_group("units"):
		if node is UnitBase and node.unit_id == unit_id:
			return node
	return null
