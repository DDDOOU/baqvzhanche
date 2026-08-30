class_name StoryDialog
extends CanvasLayer
## 剧情对话框
## 用于关卡中插入人物对白 / 旁白。非阻塞：不暂停游戏，也不拦截战场输入。
## 多条对白按队列依次显示，点击“继续”关闭当前并显示下一条。

var _queue: Array[Dictionary] = []
var _showing: bool = false
var _panel: Panel
var _speaker_label: Label
var _body_label: Label


func _ready() -> void:
	layer = 86
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_panel()


func _build_panel() -> void:
	var root := Control.new()
	root.name = "StoryDialogRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = Panel.new()
	_panel.name = "StoryDialogPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -430
	_panel.offset_right = 430
	_panel.offset_top = 112
	_panel.offset_bottom = 252
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.06, 0.94)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.82, 0.76, 0.52, 0.95)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.name = "StoryDialogContent"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 18
	vbox.offset_right = -18
	vbox.offset_top = 12
	vbox.offset_bottom = -12
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 18)
	_speaker_label.add_theme_color_override("font_color", Color(0.95, 0.84, 0.58))
	vbox.add_child(_speaker_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_label.add_theme_font_size_override("font_size", 16)
	_body_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	vbox.add_child(_body_label)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(button_row)

	var close_btn := Button.new()
	close_btn.text = "继续"
	close_btn.custom_minimum_size = Vector2(96, 32)
	close_btn.pressed.connect(_on_close_pressed)
	button_row.add_child(close_btn)


func is_pointer_over(pos: Vector2) -> bool:
	if _panel == null or not visible:
		return false
	return _panel.get_global_rect().has_point(pos)


func queue_dialog(speaker: String, text: String) -> void:
	if String(text).is_empty():
		return
	_queue.append({"speaker": String(speaker), "text": String(text)})
	_show_next()


func _show_next() -> void:
	if _showing or _queue.is_empty():
		return
	var item: Dictionary = _queue.pop_front()
	_showing = true
	_speaker_label.text = String(item.get("speaker", "无线电"))
	_body_label.text = String(item.get("text", ""))
	visible = true


func close_current() -> void:
	"""键盘/外部关闭当前对话框，随后自动显示队列中的下一条。"""
	_on_close_pressed()


func _on_close_pressed() -> void:
	visible = false
	_showing = false
	_show_next()
