class_name PauseMenu
extends CanvasLayer

signal resume_requested
signal save_requested
signal menu_requested

const AUDIO_SETTINGS_SCRIPT = preload("res://scripts/ui/AudioSettingsPanel.gd")

var status_label: Label
var audio_settings_panel: Control


func _ready() -> void:
	layer = 90
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.46)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 360)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.075, 0.96)
	style.border_color = Color(0.75, 0.68, 0.42, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)

	var title := Label.new()
	title.text = "战斗已暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.93, 0.7))
	content.add_child(title)

	content.add_child(_make_button("继续战斗", resume_requested.emit))
	content.add_child(_make_button("保存当前进度", save_requested.emit))
	content.add_child(_make_button("设置", _show_audio_settings))
	content.add_child(_make_button("返回主菜单", menu_requested.emit))

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(0.65, 1.0, 0.7))
	content.add_child(status_label)

	audio_settings_panel = AUDIO_SETTINGS_SCRIPT.new()
	audio_settings_panel.name = "AudioSettingsPanel"
	add_child(audio_settings_panel)


func show_status(message: String) -> void:
	status_label.text = message


func _show_audio_settings() -> void:
	audio_settings_panel.show_panel()


func _make_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 44)
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.pressed.connect(callback)
	return button
