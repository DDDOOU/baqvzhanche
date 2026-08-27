# ==============================================================================
# BattleLogUI.gd — 战报面板 UI
# ==============================================================================
# 作用：订阅 BattleLog.log_updated 信号，在画面右侧渲染半透明战报面板。
#       显示最近战报（命中/伤害/击毁/误伤/崩溃），带回合前缀和颜色区分。
# Godot 4.7.1 兼容
# ==============================================================================
class_name BattleLogUI
extends Control

const PANEL_WIDTH: float = 320.0
const PANEL_HEIGHT: float = 260.0
const PANEL_MARGIN: float = 8.0

var log_label: RichTextLabel


func _ready() -> void:
	# PASS：让命中测试能进入子树，使 log_label 收到滚轮事件；
	# 自身无 size 不会被命中，点击事件穿透给战场，不影响选单位。
	mouse_filter = Control.MOUSE_FILTER_PASS

	_layout()

	BattleLog.log_updated.connect(_on_log_updated)
	get_viewport().size_changed.connect(_layout)
	_refresh()


func _layout() -> void:
	var vp = get_viewport_rect().size
	# 面板尺寸自适应窗口：宽取视口 26%（最大 320），高取视口 40%（最大 260）
	var panel_w = minf(PANEL_WIDTH, vp.x * 0.26)
	var panel_h = minf(PANEL_HEIGHT, vp.y * 0.40)
	var panel_x = vp.x - panel_w - PANEL_MARGIN
	var panel_y = PANEL_MARGIN + 100.0

	if log_label == null:
		log_label = RichTextLabel.new()
		log_label.bbcode_enabled = true
		log_label.scroll_following = true
		log_label.selection_enabled = false
		# PASS：接收滚轮事件以支持上下滚动，同时不吞掉点击（仍可穿透给战场）
		log_label.mouse_filter = Control.MOUSE_FILTER_PASS
		log_label.add_theme_font_size_override("normal_font_size", 15)
		log_label.add_theme_stylebox_override("normal", _make_bg_stylebox())
		add_child(log_label)

	log_label.position = Vector2(panel_x, panel_y)
	log_label.size = Vector2(panel_w, panel_h)
	queue_redraw()


func _make_bg_stylebox() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.78)
	sb.border_color = Color(0.45, 0.45, 0.55, 0.85)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	return sb


func _on_log_updated() -> void:
	_refresh()


func _refresh() -> void:
	var bb = "[b][color=#d0d0d0]━━ 战 报 ━━[/color][/b]\n"
	for entry in BattleLog.logs:
		var hex = entry.color.to_html(false)
		bb += "[color=#%s]T%d %s[/color]\n" % [hex, entry.turn, entry.text]
	log_label.text = bb


## 供 MainScene 查询：鼠标是否落在战报面板上（用于让滚轮事件交给战报而非缩放地图）
func is_pointer_over_log(pos: Vector2) -> bool:
	if log_label == null or not log_label.visible:
		return false
	return log_label.get_global_rect().has_point(pos)
