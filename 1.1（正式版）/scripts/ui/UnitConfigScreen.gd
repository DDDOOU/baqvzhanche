class_name UnitConfigScreen
extends Control

signal closed

var menu_font: Font
var unit_list: ItemList
var field_editors: Dictionary = {}
var selected_unit_type: int = -1
var unit_title: Label
var unit_note: Label
var status_label: Label
var reset_all_dialog: ConfirmationDialog
var main_panel: PanelContainer
var content_split: HSplitContainer
var list_count_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 使用整个游戏视口作为布局参考，避免面板按自身最小尺寸贴在左上角。
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fit_to_viewport()
	_build_interface()
	_fill_unit_list()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_apply_responsive_layout.call_deferred()
	if unit_list.item_count > 0:
		unit_list.select(0)
		_select_item(0)


func _fit_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_apply_responsive_layout()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.02, 0.025, 0.94)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	main_panel = PanelContainer.new()
	main_panel.name = "UnitConfigWindow"
	main_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main_panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(main_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	main_panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(root_vbox)

	var header := HBoxContainer.new()
	root_vbox.add_child(header)
	var heading := Label.new()
	heading.text = "单位属性配置"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_override("font", menu_font)
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", Color(1.0, 0.86, 0.58))
	header.add_child(heading)
	var close_button := _make_button("返回主菜单", 150)
	close_button.pressed.connect(_close)
	header.add_child(close_button)

	var explanation := Label.new()
	explanation.text = "修改会保存为玩家方案，并在下一场战斗创建单位时生效。官方 Excel 基准配置不会被改写。"
	explanation.add_theme_font_override("font", menu_font)
	explanation.add_theme_font_size_override("font_size", 16)
	explanation.add_theme_color_override("font_color", Color(0.78, 0.82, 0.86))
	root_vbox.add_child(explanation)

	content_split = HSplitContainer.new()
	content_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_split.split_offset = 340
	content_split.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	root_vbox.add_child(content_split)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 270
	left.add_theme_constant_override("separation", 8)
	content_split.add_child(left)
	var list_label := Label.new()
	list_label.text = "全部单位（华约 / 北约）"
	_style_label(list_label, 18, Color.WHITE)
	left.add_child(list_label)
	list_count_label = Label.new()
	list_count_label.text = "上下滚动或拖动右侧滚动条"
	_style_label(list_count_label, 14, Color(0.68, 0.74, 0.8))
	left.add_child(list_count_label)
	unit_list = ItemList.new()
	unit_list.custom_minimum_size.y = 220
	unit_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	unit_list.auto_height = false
	unit_list.allow_reselect = true
	unit_list.tooltip_text = "共23种单位；使用鼠标滚轮、触控板或拖动右侧滚动条浏览"
	unit_list.add_theme_font_override("font", menu_font)
	unit_list.add_theme_font_size_override("font_size", 17)
	unit_list.item_selected.connect(_select_item)
	left.add_child(unit_list)
	var list_scrollbar := unit_list.get_v_scroll_bar()
	list_scrollbar.custom_minimum_size.x = 28
	list_scrollbar.tooltip_text = "拖动这里浏览其他单位"

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right_scroll.scroll_vertical_custom_step = 42.0
	content_split.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	right_scroll.add_child(right)

	unit_title = Label.new()
	_style_label(unit_title, 24, Color(1.0, 0.82, 0.45))
	right.add_child(unit_title)
	unit_note = Label.new()
	unit_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(unit_note, 15, Color(0.72, 0.76, 0.8))
	right.add_child(unit_note)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 9)
	right.add_child(grid)
	var specs := UnitDatabase.get_player_editable_fields()
	for field in specs.keys():
		var spec: Dictionary = specs[field]
		var label := Label.new()
		label.text = String(spec["label"])
		label.custom_minimum_size.x = 150
		_style_label(label, 17, Color(0.92, 0.93, 0.95))
		grid.add_child(label)
		var editor := SpinBox.new()
		editor.min_value = float(spec["min"])
		editor.max_value = float(spec["max"])
		editor.step = float(spec["step"])
		editor.custom_minimum_size = Vector2(240, 38)
		editor.allow_greater = false
		editor.allow_lesser = false
		editor.suffix = "（0–1）" if bool(spec.get("percent", false)) else ""
		grid.add_child(editor)
		field_editors[field] = editor

	var button_row := HFlowContainer.new()
	button_row.add_theme_constant_override("separation", 10)
	right.add_child(button_row)
	var save_button := _make_button("保存当前单位", 170)
	save_button.tooltip_text = "只保存与官方基准值不同的项目"
	save_button.pressed.connect(_save_selected)
	button_row.add_child(save_button)
	var reset_button := _make_button("恢复当前默认", 170)
	reset_button.pressed.connect(_reset_selected)
	button_row.add_child(reset_button)
	var reset_all_button := _make_button("全部恢复默认", 170)
	reset_all_button.pressed.connect(func() -> void: reset_all_dialog.popup_centered())
	button_row.add_child(reset_all_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(status_label, 16, Color(0.62, 0.9, 0.65))
	right.add_child(status_label)

	reset_all_dialog = ConfirmationDialog.new()
	reset_all_dialog.title = "全部恢复默认"
	reset_all_dialog.dialog_text = "确定删除全部玩家自定义单位属性吗？此操作不会修改官方 Excel。"
	reset_all_dialog.ok_button_text = "确定恢复"
	reset_all_dialog.cancel_button_text = "取消"
	reset_all_dialog.confirmed.connect(_reset_all)
	add_child(reset_all_dialog)


func _fill_unit_list() -> void:
	unit_list.clear()
	for unit_type in UnitDatabase.get_configurable_unit_types():
		var stats := UnitDatabase.get_official_unit_stats(unit_type)
		var faction := String(stats.get("faction", "未分类"))
		var marker := " *" if UnitDatabase.has_player_override(unit_type) else ""
		var index := unit_list.add_item("[%s] %s%s" % [faction, String(stats.get("name", "未知单位")), marker])
		unit_list.set_item_metadata(index, unit_type)
	if list_count_label != null:
		list_count_label.text = "共 %d 种单位｜上下滚动或拖动右侧滚动条" % unit_list.item_count


func _apply_responsive_layout() -> void:
	if main_panel == null or content_split == null:
		return
	var viewport_size := get_viewport_rect().size
	var viewport_width := viewport_size.x
	var viewport_height := viewport_size.y
	var compact := viewport_width < 1050.0 or viewport_height < 650.0
	var panel_ratio := Vector2(0.97, 0.97) if compact else Vector2(0.91, 0.93)
	var panel_size := viewport_size * panel_ratio
	# 高分辨率下保持中央窗口的阅读密度，不让配置面板无限拉伸。
	panel_size.x = minf(panel_size.x, 1180.0)
	panel_size.y = minf(panel_size.y, 680.0)
	main_panel.position = (viewport_size - panel_size) * 0.5
	main_panel.size = panel_size
	content_split.split_offset = int(clampf(viewport_width * (0.28 if compact else 0.30), 270.0, 390.0))


func _select_item(index: int) -> void:
	if index < 0 or index >= unit_list.item_count:
		return
	selected_unit_type = int(unit_list.get_item_metadata(index))
	_load_selected_values()


func _load_selected_values() -> void:
	if selected_unit_type < 0:
		return
	var effective := UnitDatabase.get_unit_stats(selected_unit_type)
	var official := UnitDatabase.get_official_unit_stats(selected_unit_type)
	unit_title.text = "%s  /  %s" % [String(effective.get("name", "未知单位")), UnitDatabase.get_unit_enum_name(selected_unit_type)]
	unit_note.text = "阵营：%s　兵种：%s　%s" % [
		String(official.get("faction", "未分类")),
		String(official.get("class", "unknown")),
		"当前使用玩家自定义值" if UnitDatabase.has_player_override(selected_unit_type) else "当前使用官方默认值"
	]
	for field in field_editors.keys():
		(field_editors[field] as SpinBox).value = float(effective.get(field, 0.0))
	status_label.text = "带 * 的单位存在玩家自定义配置。"


func _save_selected() -> void:
	if selected_unit_type < 0:
		return
	var values: Dictionary = {}
	for field in field_editors.keys():
		values[field] = (field_editors[field] as SpinBox).value
	if UnitDatabase.set_player_unit_overrides(selected_unit_type, values):
		status_label.text = "已保存。新数值会在下一场战斗创建单位时生效。"
		_refresh_list_selection()
	else:
		status_label.text = "保存失败，请检查用户目录写入权限。"


func _reset_selected() -> void:
	if selected_unit_type < 0:
		return
	if UnitDatabase.reset_player_unit_overrides(selected_unit_type):
		status_label.text = "当前单位已恢复官方默认值。"
		_refresh_list_selection()
		_load_selected_values()


func _reset_all() -> void:
	if UnitDatabase.reset_all_player_overrides():
		status_label.text = "全部单位均已恢复官方默认值。"
		_refresh_list_selection()
		_load_selected_values()


func _refresh_list_selection() -> void:
	var keep_type := selected_unit_type
	_fill_unit_list()
	for index in range(unit_list.item_count):
		if int(unit_list.get_item_metadata(index)) == keep_type:
			unit_list.select(index)
			break


func _close() -> void:
	visible = false
	closed.emit()


func _style_label(label: Label, font_size: int, color: Color) -> void:
	label.add_theme_font_override("font", menu_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)


func _make_button(text: String, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 42)
	button.add_theme_font_override("font", menu_font)
	button.add_theme_font_size_override("font_size", 17)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.075, 0.98)
	style.border_color = Color(0.56, 0.16, 0.12, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style
