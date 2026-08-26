# ==============================================================================
# CardUI.gd — 手牌UI面板
# ==============================================================================
# 作用：渲染手牌界面，显示卡牌名称、消耗、冷却、效果描述。
#       交互：左键选牌→点击地图目标使用 / 右键点击卡牌弃牌 / Tab开关面板。
# Godot 4.7.1 兼容
# ==============================================================================
class_name CardUI
extends Control

## === 卡牌显示尺寸 ===
const CARD_WIDTH: float = 160.0
const CARD_HEIGHT: float = 220.0
const CARD_SPACING: float = 12.0

## === 颜色配置 ===
const CARD_COLORS: Dictionary = {
	"attack":   Color(0.85, 0.30, 0.20, 0.9),   # 攻击卡 — 红色
	"defense":  Color(0.20, 0.50, 0.85, 0.9),   # 防御卡 — 蓝色
	"special":  Color(0.60, 0.30, 0.80, 0.9),   # 特殊卡 — 紫色
	"scrambled": Color(0.30, 0.30, 0.30, 0.9),  # 乱码卡 — 灰色
}

## === 状态 ===
var selected_card_index: int = -1
var is_panel_open: bool = false


func _ready() -> void:
	print("[CardUI] 手牌UI就绪")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	get_viewport().size_changed.connect(queue_redraw)


func _get_view_size() -> Vector2:
	return get_viewport_rect().size


func _get_card_size() -> Vector2:
	# 卡牌尺寸自适应窗口
	var vp = _get_view_size()
	var w = minf(CARD_WIDTH, vp.x * 0.10)
	var h = minf(CARD_HEIGHT, vp.y * 0.28)
	return Vector2(w, h)


func _get_card_spacing() -> float:
	# 卡牌间距随宽度缩放
	return minf(CARD_SPACING, _get_card_size().x * 0.08)


func _draw() -> void:
	if not is_panel_open:
		return

	var cs = _get_card_size()
	var sp = _get_card_spacing()

	# 操作说明栏（卡牌上方）
	_draw_help_bar(cs)

	var hand = CardSystem.hand
	if hand.is_empty():
		_draw_empty_hand()
		return

	var vp = _get_view_size()
	var total_width = hand.size() * (cs.x + sp) - sp
	var start_x = (vp.x - total_width) / 2.0
	var card_y = vp.y - cs.y - 20.0

	for i in range(hand.size()):
		var card = hand[i]
		var x = start_x + i * (cs.x + sp)
		_draw_card(Rect2(x, card_y, cs.x, cs.y), card, i)


func _draw_help_bar(cs: Vector2) -> void:
	# 绘制卡牌上方操作提示栏
	var vp = _get_view_size()
	var card_y = vp.y - cs.y - 20.0
	var bar_y = card_y - maxf(26.0, cs.y * 0.12)
	# 栏宽跟随视口，最大720
	var bar_w = minf(720.0, vp.x * 0.85)
	var bar_x = (vp.x - bar_w) / 2.0
	var bar_h = maxf(22.0, cs.y * 0.10)

	# 半透明背景栏
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0, 0, 0, 0.75), true)
	draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.5, 0.5, 0.6, 0.8), false, 1)

	var hand = CardSystem.hand
	var help_text = ""
	var help_color = Color(0.85, 0.85, 0.85)
	var font_size = int(maxf(10.0, cs.x * 0.075))

	# 已选中卡牌 → 提示去地图点目标
	if selected_card_index >= 0 and selected_card_index < hand.size():
		var card = hand[selected_card_index]
		help_text = "已选中《%s》：点击地图目标格使用 | 右键空白处取消" % card.card_name
		help_color = Color.YELLOW
	else:
		help_text = "左键选牌，点击地图使用；右键点卡牌弃牌；Tab 开关面板"

	draw_string(ThemeDB.fallback_font,
		Vector2(bar_x + 10, bar_y + bar_h * 0.72),
		help_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, help_color)


func _draw_card(rect: Rect2, card, index: int) -> void:
	# 绘制单张卡牌
	var bg_color = CARD_COLORS.get(card.data.get("type", "special"), Color.GRAY)
	if card.is_scrambled:
		bg_color = CARD_COLORS["scrambled"]

	# 内部字号、间距随卡片尺寸缩放
	var title_font = int(maxf(10.0, rect.size.x * 0.08))
	var desc_font = int(maxf(8.0, rect.size.x * 0.06))
	var cost_font = int(maxf(9.0, rect.size.x * 0.07))

	# 选中高亮
	if index == selected_card_index:
		draw_rect(rect.grow(3), Color.YELLOW, false, 2.0)

	# 卡牌背景
	draw_rect(rect, bg_color, true)
	draw_rect(rect, Color.WHITE.darkened(0.3), false, 1.0)

	# 卡面贴图（AI 美术素材 — 立绘铺满整卡, 文字遮罩叠加）
	var art_tex := _get_card_art(card)
	if art_tex != null:
		var tex_size := art_tex.get_size()
		if tex_size.x > 0 and tex_size.y > 0:
			# cover 模式: 立绘铺满整张卡片, 溢出部分居中裁剪
			var scale := maxf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
			var draw_size := tex_size * scale
			var draw_pos := rect.position + (rect.size - draw_size) * 0.5
			var src_rect := Rect2(Vector2.ZERO, tex_size)
			var dst_rect := Rect2(draw_pos, draw_size)
			var overlap := dst_rect.intersection(rect)
			if overlap.size.x > 0 and overlap.size.y > 0:
				var src_offset := (overlap.position - dst_rect.position) / draw_size
				var src_size := overlap.size / draw_size
				var src_region := Rect2(
					src_rect.position + src_rect.size * src_offset,
					src_rect.size * src_size)
				draw_texture_rect_region(art_tex, overlap, src_region, Color.WHITE)
		# 顶部遮罩条（保证名称可读）
		var top_bar := Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.20))
		draw_rect(top_bar, Color(0.0, 0.0, 0.0, 0.45), true)
		# 底部遮罩条（保证描述可读）
		var bot_bar := Rect2(
			rect.position + Vector2(0, rect.size.y * 0.70),
			Vector2(rect.size.x, rect.size.y * 0.30))
		draw_rect(bot_bar, Color(0.0, 0.0, 0.0, 0.55), true)
	# 卡牌名称
	draw_string(ThemeDB.fallback_font,
		rect.position + Vector2(rect.size.x * 0.06, rect.size.y * 0.12),
		card.card_name, HORIZONTAL_ALIGNMENT_LEFT, -1, title_font, Color.WHITE)

	# 消耗
	draw_string(ThemeDB.fallback_font,
		rect.position + Vector2(rect.size.x * 0.78, rect.size.y * 0.10),
		"费用%d" % card.cost, HORIZONTAL_ALIGNMENT_RIGHT, -1, cost_font, Color.YELLOW)

	# 分隔线
	var line_y = rect.position.y + rect.size.y * 0.18
	draw_line(Vector2(rect.position.x + rect.size.x * 0.06, line_y),
		Vector2(rect.position.x + rect.size.x * 0.94, line_y),
		Color.WHITE.darkened(0.5), 1.0)

	# 效果描述（底部遮罩条内）
	var desc_rect := Rect2(
		rect.position + Vector2(rect.size.x * 0.06, rect.size.y * 0.74),
		Vector2(rect.size.x * 0.88, rect.size.y * 0.22)
	)
	_draw_wrapped_text(desc_rect, str(card.data.get("description", "")),
		desc_font, Color.WHITE.darkened(0.2))

	# 冷却标记
	if card.cooldown > 0:
		draw_string(ThemeDB.fallback_font,
			rect.position + Vector2(rect.size.x * 0.06, rect.size.y - rect.size.y * 0.08),
			"冷却: %d回合" % card.cooldown,
			HORIZONTAL_ALIGNMENT_LEFT, -1, desc_font, Color.RED)

	# 弃牌提示（右下角，玩家自主弃牌入口）
	draw_string(ThemeDB.fallback_font,
		rect.position + Vector2(rect.size.x - rect.size.x * 0.05, rect.size.y - rect.size.y * 0.04),
		"右键弃牌", HORIZONTAL_ALIGNMENT_RIGHT, -1, desc_font,
		Color(0.7, 0.7, 0.7))

	# 乱码标记
	if card.is_scrambled:
		draw_string(ThemeDB.fallback_font,
			rect.position + Vector2(rect.size.x / 2, rect.size.y / 2),
			"?", HORIZONTAL_ALIGNMENT_CENTER, -1, rect.size.x * 0.3,
			Color.YELLOW.darkened(0.5))


func _draw_wrapped_text(bounds: Rect2, text: String, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var line_height := maxf(font_size + 3.0, font.get_height(font_size) + 2.0)
	var max_lines := int(floor(bounds.size.y / line_height))
	if max_lines <= 0:
		return
	var lines := _wrap_text_to_width(text, bounds.size.x, font_size)
	for i in range(mini(lines.size(), max_lines)):
		var line := lines[i]
		if i == max_lines - 1 and lines.size() > max_lines:
			line = _fit_text_to_width(line + "...", bounds.size.x, font_size)
		draw_string(font, bounds.position + Vector2(0, line_height * (i + 1)),
			line, HORIZONTAL_ALIGNMENT_LEFT, bounds.size.x, font_size, color)


func _wrap_text_to_width(text: String, max_width: float, font_size: int) -> Array[String]:
	var font := ThemeDB.fallback_font
	var lines: Array[String] = []
	var current := ""
	for i in range(text.length()):
		var ch := text.substr(i, 1)
		if ch == "\n":
			lines.append(current)
			current = ""
			continue
		var candidate := current + ch
		if current != "" and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
			lines.append(current)
			current = ch.strip_edges() if ch == " " else ch
		else:
			current = candidate
	if current != "":
		lines.append(current)
	return lines


func _fit_text_to_width(text: String, max_width: float, font_size: int) -> String:
	var font := ThemeDB.fallback_font
	var result := text
	while result.length() > 0 and font.get_string_size(result, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		result = result.substr(0, result.length() - 1)
	return result


func _draw_empty_hand() -> void:
	# 手牌为空时的提示
	var vp = _get_view_size()
	draw_string(ThemeDB.fallback_font,
		Vector2(vp.x / 2, vp.y - 30),
		"手牌已空，下回合自动抽牌",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.GRAY)


## === 卡面贴图缓存 ===
var _card_art_cache: Dictionary = {}  # card_id → Texture2D

func _get_card_art(card) -> Texture2D:
	"""按卡牌 id 加载 AI 生成卡面; 乱码卡用专用碎裂图; 缺失时返回 null 回退纯色。"""
	var art_id := "scrambled" if card.is_scrambled else String(card.data.get("id", ""))
	if art_id.is_empty():
		return null
	if _card_art_cache.has(art_id):
		return _card_art_cache[art_id]
	var tex := load("res://assets/cards/%s.png" % art_id) as Texture2D
	_card_art_cache[art_id] = tex
	return tex


## === 交互 ===
func toggle_panel() -> void:
	is_panel_open = not is_panel_open
	visible = is_panel_open
	if is_panel_open:
		selected_card_index = -1
	queue_redraw()


func get_card_at_pos(mouse_pos: Vector2) -> int:
	# 返回鼠标下的卡牌索引
	if not is_panel_open:
		return -1

	var hand = CardSystem.hand
	var vp = _get_view_size()
	var cs = _get_card_size()
	var sp = _get_card_spacing()
	var total_width = hand.size() * (cs.x + sp) - sp
	var start_x = (vp.x - total_width) / 2.0
	var card_y = vp.y - cs.y - 20.0

	for i in range(hand.size()):
		var x = start_x + i * (cs.x + sp)
		var rect = Rect2(x, card_y, cs.x, cs.y)
		if rect.has_point(mouse_pos):
			return i
	return -1


func select_card(index: int) -> void:
	selected_card_index = index
	queue_redraw()


func use_selected_card(target_col: int, target_row: int) -> bool:
	# 使用选中的卡牌
	if selected_card_index < 0:
		return false
	var success = CardSystem.use_card(selected_card_index, target_col, target_row)
	if success:
		selected_card_index = -1
		queue_redraw()
	return success


func discard_card_at_pos(mouse_pos: Vector2) -> bool:
	# 右键点击卡牌弃牌，返回是否成功
	if not is_panel_open:
		return false
	var idx = get_card_at_pos(mouse_pos)
	if idx < 0:
		return false
	# 弃牌前记录名称用于战报
	var card_name = CardSystem.hand[idx].card_name
	CardSystem.discard_card(idx)
	# 调整选中索引：弃的是选中卡牌则清空，弃的在选中之前则前移
	if idx == selected_card_index:
		selected_card_index = -1
	elif idx < selected_card_index:
		selected_card_index -= 1
	BattleLog.add_log("弃牌: 「%s」已弃置" % card_name, Color(0.6, 0.6, 0.6))
	print("[CardUI] 弃牌: %s" % card_name)
	queue_redraw()
	return true
