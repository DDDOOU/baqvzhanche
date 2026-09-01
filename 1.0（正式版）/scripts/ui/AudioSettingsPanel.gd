class_name AudioSettingsPanel
extends Control

signal closed

var menu_font: Font
var bgm_slider: HSlider
var sfx_slider: HSlider
var bgm_value_label: Label
var sfx_value_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 该控件有时直接挂在 CanvasLayer（暂停菜单）下。CanvasLayer 不是
	# Control，PRESET_FULL_RECT 无法从它取得尺寸，因此必须显式使用视口大小。
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	z_index = 200
	_build_interface()
	visible = false


func _fit_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func show_panel() -> void:
	bgm_slider.set_value_no_signal(SoundManager.get_bgm_volume() * 100.0)
	sfx_slider.set_value_no_signal(SoundManager.get_sfx_volume() * 100.0)
	_update_value_labels()
	visible = true
	bgm_slider.grab_focus()


func close_panel() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.005, 0.01, 0.015, 0.74)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.name = "ViewportCenter"
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.name = "SettingsWindow"
	panel.custom_minimum_size = Vector2(540, 350)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 18)
	panel.add_child(content)

	var title := _make_label("音频设置 / AUDIO", 28, Color(1.0, 0.91, 0.64))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	var subtitle := _make_label("调整战术频道与战场环境的声音比例", 14, Color(0.62, 0.72, 0.78))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)

	var divider := HSeparator.new()
	divider.add_theme_constant_override("separation", 4)
	content.add_child(divider)

	var bgm_row := _make_volume_row("背景音乐  BGM")
	bgm_slider = bgm_row.slider
	bgm_value_label = bgm_row.value_label
	content.add_child(bgm_row.row)

	var sfx_row := _make_volume_row("战斗音效  SFX")
	sfx_slider = sfx_row.slider
	sfx_value_label = sfx_row.value_label
	content.add_child(sfx_row.row)

	bgm_slider.value_changed.connect(func(value: float) -> void:
		SoundManager.set_bgm_volume(value / 100.0)
		_update_value_labels())
	sfx_slider.value_changed.connect(func(value: float) -> void:
		SoundManager.set_sfx_volume(value / 100.0)
		SoundManager.play("ui_click", -8.0)
		_update_value_labels())

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 14)
	content.add_child(button_row)

	var reset_button := _make_button("恢复默认", 150)
	reset_button.pressed.connect(func() -> void:
		SoundManager.set_bgm_volume(SoundManager.DEFAULT_BGM_VOLUME)
		SoundManager.set_sfx_volume(SoundManager.DEFAULT_SFX_VOLUME)
		show_panel())
	button_row.add_child(reset_button)

	var close_button := _make_button("保存并返回", 180)
	close_button.pressed.connect(close_panel)
	button_row.add_child(close_button)

	bgm_slider.set_value_no_signal(SoundManager.get_bgm_volume() * 100.0)
	sfx_slider.set_value_no_signal(SoundManager.get_sfx_volume() * 100.0)
	_update_value_labels()


func _make_volume_row(label_text: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(470, 52)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)

	var label := _make_label(label_text, 17, Color(0.88, 0.91, 0.89))
	label.custom_minimum_size = Vector2(150, 36)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(230, 36)
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.tick_count = 11
	slider.ticks_on_borders = true
	slider.add_theme_icon_override("grabber", _make_slider_grabber(Color(0.94, 0.71, 0.22)))
	slider.add_theme_icon_override("grabber_highlight", _make_slider_grabber(Color(1.0, 0.88, 0.48)))
	slider.add_theme_stylebox_override("slider", _slider_track(Color(0.08, 0.14, 0.17)))
	slider.add_theme_stylebox_override("grabber_area", _slider_track(Color(0.24, 0.62, 0.72)))
	row.add_child(slider)

	var value_label := _make_label("100%", 16, Color(0.42, 0.84, 0.91))
	value_label.custom_minimum_size = Vector2(58, 36)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)
	return {"row": row, "slider": slider, "value_label": value_label}


func _update_value_labels() -> void:
	if bgm_value_label:
		bgm_value_label.text = "%d%%" % int(round(bgm_slider.value))
	if sfx_value_label:
		sfx_value_label.text = "%d%%" % int(round(sfx_slider.value))


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if menu_font:
		label.add_theme_font_override("font", menu_font)
	return label


func _make_button(text: String, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 44)
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 16)
	if menu_font:
		button.add_theme_font_override("font", menu_font)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.055, 0.08, 0.09), Color(0.47, 0.57, 0.57)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.13, 0.07, 0.055), Color(0.94, 0.43, 0.25)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.20, 0.06, 0.04), Color(1.0, 0.75, 0.34)))
	return button


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.052, 0.985)
	style.border_color = Color(0.73, 0.58, 0.28, 0.96)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(30)
	return style


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	return style


func _slider_track(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


func _make_slider_grabber(color: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([color.lightened(0.18), color])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 16
	texture.height = 24
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(1.0, 1.0)
	return texture
