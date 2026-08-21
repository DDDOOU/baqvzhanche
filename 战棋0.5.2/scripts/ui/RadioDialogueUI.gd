# ==============================================================================
# RadioDialogueUI.gd — 无线电对话浮窗（UI/交互最后缺口）
# ==============================================================================
# 作用：显示剧情/事件驱动的无线电对话（指挥官喊话、情报通报、剧情旁白）。
#       底部浮窗 + 打字机效果 + 点击/按键跳过 + 自动消失。
# 接入方式：MainScene 实例化并持有，关卡事件/回合节点调用 show_dialogue()。
# Godot 4.7.1 兼容 — 挂载模式参考 TutorialManager（CanvasLayer layer=85）
# ==============================================================================
class_name RadioDialogueUI
extends CanvasLayer

const PANEL_HEIGHT: float = 110.0
const CHAR_INTERVAL: float = 0.028   # 打字机每字符间隔（秒）
const AUTO_DISMISS_SECONDS: float = 6.0

var _panel: Panel = null
var _speaker_label: Label = null
var _text_label: Label = null
var _typewriter_timer: float = 0.0
var _full_text: String = ""
var _visible_chars: int = 0
var _auto_dismiss: float = 0.0
var _dismissing: bool = false


func _ready() -> void:
	layer = 85
	_build_panel()
	hide_dialogue()


func _build_panel() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_top = -PANEL_HEIGHT - 12.0
	_panel.offset_bottom = -8.0
	_panel.offset_left = 24.0
	_panel.offset_right = -24.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.93)
	style.border_width_top = 2
	style.border_color = Color(0.75, 0.72, 0.5, 0.9)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	_panel.add_theme_stylebox_override("panel", style)
	# 面板不拦截鼠标 — 点击由 MainScene._input 转发给 skip_or_dismiss
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.set_deferred("offset_left", 18)
	vbox.set_deferred("offset_right", -18)
	vbox.set_deferred("offset_top", 8)
	vbox.set_deferred("offset_bottom", -8)
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 14)
	_speaker_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.5))
	_speaker_label.text = "无线电"
	vbox.add_child(_speaker_label)

	_text_label = Label.new()
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_size_override("font_size", 16)
	_text_label.add_theme_color_override("font_color", Color(0.93, 0.93, 0.93))
	vbox.add_child(_text_label)


## === 对外接口 ===
func show_dialogue(speaker: String, text: String, auto_dismiss_seconds: float = AUTO_DISMISS_SECONDS) -> void:
	"""显示一条无线电对话（打字机效果）。重复调用会直接切换内容。"""
	_speaker_label.text = "无线电 · %s" % speaker
	_full_text = text
	_visible_chars = 0
	_typewriter_timer = 0.0
	_auto_dismiss = auto_dismiss_seconds
	_dismissing = false
	_panel.visible = true
	_apply_visible_text()
	print("[RadioDialogue] %s: %s" % [speaker, text])


func hide_dialogue() -> void:
	_panel.visible = false
	_dismissing = true


func is_showing() -> bool:
	return _panel.visible


func _apply_visible_text() -> void:
	_text_label.text = _full_text.substr(0, _visible_chars)


func _process(delta: float) -> void:
	if not _panel.visible:
		return

	# 打字机推进
	if _visible_chars < _full_text.length():
		_typewriter_timer += delta
		var steps := int(_typewriter_timer / CHAR_INTERVAL)
		if steps > 0:
			_visible_chars = mini(_full_text.length(), _visible_chars + steps)
			_typewriter_timer = 0.0
			_apply_visible_text()

	# 全文显示后开始自动消失倒计时（点击由 MainScene 转发跳过）
	if _visible_chars >= _full_text.length() and not _dismissing:
		_auto_dismiss -= delta
		if _auto_dismiss <= 0.0:
			hide_dialogue()


func skip_or_dismiss() -> void:
	"""点击/按键：打字中则立即显全文, 已完整则关闭。"""
	if not _panel.visible:
		return
	if _visible_chars < _full_text.length():
		_visible_chars = _full_text.length()
		_apply_visible_text()
		_auto_dismiss = AUTO_DISMISS_SECONDS
	else:
		hide_dialogue()
