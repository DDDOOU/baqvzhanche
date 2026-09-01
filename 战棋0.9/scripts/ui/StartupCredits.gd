class_name StartupCredits
extends Control

signal finished

const FADE_IN_SECONDS := 0.65
const HOLD_SECONDS := 5.0
const FADE_OUT_SECONDS := 0.75

const CREDIT_ROWS: Array = [
	["窦英杰", "制作人"],
	["刘鹏辉，吴名杨，陈梓铭", "技术负责人"],
	["王宇航，梁雅皓，陈梓铭", "战斗系统程序"],
	["王震逍，刘鹏辉，窦英杰", "UI美术/程序"],
	["王震逍，梁雅皓", "剧情，文本策划"],
	["王宇航，窦英杰，黄建文", "素材修改/场景美术搭建"],
	["黄建文，吴名扬，梁雅皓", "音乐，音效，特效制作和设计"],
]

var pixel_font: SystemFont
var animation_tween: Tween
var _completed := false
var _skip_enabled_at_msec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 1000
	_build_pixel_font()
	_build_interface()
	visible = false
	modulate.a = 0.0


func _build_pixel_font() -> void:
	pixel_font = SystemFont.new()
	pixel_font.font_names = PackedStringArray([
		"Fusion Pixel 12px Monospaced zh_hans",
		"Ark Pixel 12px zh_cn",
		"Zpix",
		"SimHei",
		"Microsoft YaHei UI",
		"Noto Sans CJK SC",
	])
	pixel_font.font_weight = 900
	pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	pixel_font.hinting = TextServer.HINTING_NONE


func _build_interface() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.018, 0.022, 0.025, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "CreditsCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var frame := PanelContainer.new()
	frame.name = "CreditsFrame"
	frame.custom_minimum_size = Vector2(980, 630)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.025, 0.030, 0.032, 0.98)
	frame_style.border_color = Color(0.68, 0.11, 0.08, 0.95)
	frame_style.set_border_width_all(3)
	frame_style.set_corner_radius_all(2)
	frame_style.shadow_color = Color(0, 0, 0, 0.75)
	frame_style.shadow_size = 10
	frame_style.set_content_margin_all(28)
	frame.add_theme_stylebox_override("panel", frame_style)
	center.add_child(frame)

	var content := VBoxContainer.new()
	content.name = "CreditsContent"
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 8)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(content)

	var studio_caption := _make_label("游 戏 制 作 组", 18, Color(0.72, 0.74, 0.70))
	content.add_child(studio_caption)
	var studio_name := _make_label("八 区 战 车", 42, Color(0.95, 0.80, 0.43))
	studio_name.add_theme_color_override("font_shadow_color", Color(0.45, 0.02, 0.01, 1.0))
	studio_name.add_theme_constant_override("shadow_offset_x", 3)
	studio_name.add_theme_constant_override("shadow_offset_y", 3)
	content.add_child(studio_name)

	var separator := HSeparator.new()
	separator.custom_minimum_size.y = 12
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var separator_style := StyleBoxLine.new()
	separator_style.color = Color(0.68, 0.11, 0.08, 0.88)
	separator_style.thickness = 2
	separator.add_theme_stylebox_override("separator", separator_style)
	content.add_child(separator)

	var title := _make_label("开 发 人 员", 24, Color(0.93, 0.93, 0.86))
	content.add_child(title)

	var credits_grid := GridContainer.new()
	credits_grid.name = "CreditsGrid"
	credits_grid.columns = 2
	credits_grid.add_theme_constant_override("h_separation", 36)
	credits_grid.add_theme_constant_override("v_separation", 8)
	credits_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(credits_grid)

	for row in CREDIT_ROWS:
		var people := _make_label(String(row[0]), 18, Color(0.91, 0.91, 0.86), HORIZONTAL_ALIGNMENT_RIGHT)
		people.custom_minimum_size = Vector2(520, 30)
		people.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		credits_grid.add_child(people)
		var role := _make_label(String(row[1]), 18, Color(0.92, 0.64, 0.30), HORIZONTAL_ALIGNMENT_LEFT)
		role.custom_minimum_size = Vector2(330, 30)
		role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		credits_grid.add_child(role)

	var skip_hint := _make_label("点击或按任意键跳过", 13, Color(0.45, 0.48, 0.46))
	content.add_child(skip_hint)


func _make_label(text_value: String, font_size: int, color: Color,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", pixel_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.96))
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func play() -> void:
	if _completed:
		return
	visible = true
	modulate.a = 0.0
	_skip_enabled_at_msec = Time.get_ticks_msec() + 450
	if animation_tween and animation_tween.is_valid():
		animation_tween.kill()
	animation_tween = create_tween()
	animation_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	animation_tween.tween_property(self, "modulate:a", 1.0, FADE_IN_SECONDS)
	animation_tween.tween_interval(HOLD_SECONDS)
	animation_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_SECONDS)
	animation_tween.tween_callback(_complete)


func finish_now() -> void:
	if _completed:
		return
	if animation_tween and animation_tween.is_valid():
		animation_tween.kill()
	modulate.a = 0.0
	_complete()


func _input(event: InputEvent) -> void:
	if not visible or _completed or Time.get_ticks_msec() < _skip_enabled_at_msec:
		return
	var should_skip: bool = event is InputEventKey and event.pressed and not event.echo
	should_skip = should_skip or (event is InputEventMouseButton and event.pressed)
	if should_skip:
		get_viewport().set_input_as_handled()
		finish_now()


func _complete() -> void:
	if _completed:
		return
	_completed = true
	visible = false
	finished.emit()


func contains_credit_text(fragment: String) -> bool:
	return _tree_contains_text(self, fragment)


func _tree_contains_text(node: Node, fragment: String) -> bool:
	if node is Label and fragment in String(node.text):
		return true
	for child in node.get_children():
		if _tree_contains_text(child, fragment):
			return true
	return false
