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
const PANEL_HEIGHT: float = 230.0
const PANEL_MARGIN: float = 8.0
const COLLAPSED_WIDTH: float = 210.0
const COLLAPSED_HEIGHT: float = 34.0

var log_label: RichTextLabel
var is_expanded: bool = false
var layout_tween: Tween


func _ready() -> void:
	# Control 在 Node2D 父节点下：忽略鼠标，否则会拦截点击
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_layout()

	BattleLog.log_updated.connect(_on_log_updated)
	get_viewport().size_changed.connect(_layout)
	_refresh()


func _layout(animate: bool = false) -> void:
	var vp = get_viewport_rect().size
	# 默认仅展示最新战报，为地图留出完整视野；玩家可展开完整记录。
	var panel_w := get_panel_width()
	var panel_h := minf(PANEL_HEIGHT, vp.y * 0.36) if is_expanded else COLLAPSED_HEIGHT
	var panel_x = vp.x - panel_w - PANEL_MARGIN
	var panel_y = PANEL_MARGIN + 96.0

	if log_label == null:
		log_label = RichTextLabel.new()
		log_label.bbcode_enabled = true
		log_label.scroll_following = true
		log_label.selection_enabled = false
		log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		log_label.add_theme_font_size_override("normal_font_size", 14)
		log_label.add_theme_stylebox_override("normal", _make_bg_stylebox())
		add_child(log_label)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if is_expanded else TextServer.AUTOWRAP_OFF
	log_label.scroll_active = is_expanded
	log_label.scroll_following = is_expanded

	var target_position := Vector2(panel_x, panel_y)
	var target_size := Vector2(panel_w, panel_h)
	if animate and is_inside_tree():
		if layout_tween and layout_tween.is_valid():
			layout_tween.kill()
		layout_tween = create_tween().set_parallel(true)
		layout_tween.tween_property(log_label, "position", target_position, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		layout_tween.tween_property(log_label, "size", target_size, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		log_label.position = target_position
		log_label.size = target_size
	queue_redraw()
	_refresh()


func get_panel_width() -> float:
	var vp := get_viewport_rect().size
	return minf(PANEL_WIDTH, vp.x * 0.26) if is_expanded else minf(COLLAPSED_WIDTH, vp.x * 0.22)


func set_expanded(expanded: bool) -> void:
	if is_expanded == expanded:
		return
	is_expanded = expanded
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if expanded else TextServer.AUTOWRAP_OFF
	log_label.scroll_active = expanded
	log_label.scroll_following = expanded
	_layout(true)


func _make_bg_stylebox() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.68)
	sb.border_color = Color(0.45, 0.45, 0.55, 0.85)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	return sb


func _on_log_updated() -> void:
	_refresh()


func _refresh() -> void:
	if log_label == null:
		return
	if not is_expanded:
		var latest: Variant = BattleLog.logs.back() if not BattleLog.logs.is_empty() else null
		if latest == null:
			log_label.text = "[color=#d0d0d0]等待战况[/color]"
			log_label.tooltip_text = "战报：等待战况"
			return
		var latest_color: Color = latest.color
		var latest_hex: String = latest_color.to_html(false)
		var preview := str(latest.text)
		if preview.length() > 16:
			preview = preview.substr(0, 16) + "..."
		log_label.text = "[color=#%s]T%d %s[/color]" % [latest_hex, latest.turn, preview]
		log_label.tooltip_text = "T%d %s" % [latest.turn, latest.text]
		return
	log_label.tooltip_text = ""
	var bb = "[b][color=#d0d0d0]━━ 战 报 ━━[/color][/b]\n"
	for entry in BattleLog.logs:
		var hex = entry.color.to_html(false)
		bb += "[color=#%s]T%d %s[/color]\n" % [hex, entry.turn, entry.text]
	log_label.text = bb
