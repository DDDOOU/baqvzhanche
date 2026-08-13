# ==============================================================================
# UnitRenderer.gd — 单位视觉表现
# ==============================================================================
# 作用：在六边形网格上渲染单位图标/模型。
#       处理单位选中、移动动画、生命条、状态标识。
# Godot 4.7.1 兼容
# ==============================================================================
class_name UnitRenderer
extends Node2D

## === 单位图标颜色 ===
const FACTION_COLORS: Dictionary = {
	UnitBase.Faction.WARSAW_PACT: Color(0.15, 0.50, 0.85),  # 华约蓝
	UnitBase.Faction.NATO:         Color(0.85, 0.20, 0.20),  # 北约红
}

## === 单位贴图（苏式粗犷风令牌，assets/units/） ===
## 键为 UnitBase.UnitType 枚举名，值为 res:// 贴图路径。
## 九宫格视觉复核(2026-08-11, moonshot-v1-8k-vision-preview 逐张验证):
##   00/10/21 = 步兵(单兵/双人通信组/护目镜步兵)
##   01/20    = 主战坦克(01锈红=华约T-72B / 20灰绿=北约M1A1, 阵营区分)
##   02       = 履带式步战车 IFV
##   12       = 轮式步战车/APC (8x8轮式底盘)
##   11       = 侦察兵(举望远镜, 非侦察车)
##   22       = 攻击直升机 (AH-64)
## 注: 9图无火箭炮/防空专用图, BM21(轮式底盘)/SA13 借用 12 最接近。
const UNIT_ICON_PATHS: Dictionary = {
	UnitBase.UnitType.INFANTRY_SQUAD: "res://assets/units/unit_brutalist_00.png",
	UnitBase.UnitType.MOTOR_RIFLE: "res://assets/units/unit_brutalist_10.png",
	UnitBase.UnitType.T72B_TANK: "res://assets/units/unit_brutalist_01.png",
	UnitBase.UnitType.BMP2_IFV: "res://assets/units/unit_brutalist_02.png",
	UnitBase.UnitType.BM21_ROCKET: "res://assets/units/unit_brutalist_12.png",
	UnitBase.UnitType.SA13_AA: "res://assets/units/unit_brutalist_12.png",
	UnitBase.UnitType.RECON_PLATOON: "res://assets/units/unit_brutalist_11.png",
	UnitBase.UnitType.SAPPERS: "res://assets/units/unit_brutalist_10.png",
	UnitBase.UnitType.COMMAND_ELEMENT: "res://assets/units/unit_brutalist_11.png",
	UnitBase.UnitType.RESERVE: "res://assets/units/unit_brutalist_10.png",
	UnitBase.UnitType.M1A1_TANK: "res://assets/units/unit_brutalist_20.png",
	UnitBase.UnitType.M2_IFV: "res://assets/units/unit_brutalist_02.png",
	## —— 0.5.2 复核补全（关卡实际出场兵种，借用就近分类图）——
	UnitBase.UnitType.MECH_INFANTRY: "res://assets/units/unit_brutalist_21.png",
	UnitBase.UnitType.ATGM_TEAM: "res://assets/units/unit_brutalist_21.png",
	UnitBase.UnitType.NATO_ENGINEER: "res://assets/units/unit_brutalist_10.png",
	UnitBase.UnitType.NATO_RECON_SECTION: "res://assets/units/unit_brutalist_11.png",
	UnitBase.UnitType.BRDM2_RECON: "res://assets/units/unit_brutalist_12.png",
	UnitBase.UnitType.ZSU23_AA: "res://assets/units/unit_brutalist_02.png",
	UnitBase.UnitType.GVOZDIKA_ARTILLERY: "res://assets/units/unit_brutalist_02.png",
	UnitBase.UnitType.M109_ARTILLERY: "res://assets/units/unit_brutalist_02.png",
	UnitBase.UnitType.M113_APC: "res://assets/units/unit_brutalist_02.png",
	UnitBase.UnitType.M901_ITV: "res://assets/units/unit_brutalist_02.png",
	UnitBase.UnitType.AH64_HELICOPTER: "res://assets/units/unit_brutalist_22.png",
	UnitBase.UnitType.CIVILIAN_CONVOY: "res://assets/units/unit_brutalist_10.png",
	UnitBase.UnitType.UNKNOWN_CONTACT: "res://assets/units/unit_brutalist_11.png",
};

## 贴图缓存（路径 → Texture2D）
var _icon_cache: Dictionary = {}

const UNIT_SHAPES: Dictionary = {
	"infantry": "◆",       # 菱形
	"armor": "■",          # 方块
	"artillery": "●",      # 圆
	"ifv": "▲",            # 三角
	"support": "⬢",        # 六边形
	"air": "✈",            # 飞机
	"civilian": "○",       # 空心圆
	"anti_tank": "⌁",      # 反坦克
	"air_defense": "✦",    # 防空
	"recon": "◇",          # 侦察
	"recon_vehicle": "◈",  # 侦察车
	"apc": "▰",            # 输送车
}

## === 状态 ===
var selected_unit: UnitBase = null
var show_health_bars: bool = true
var show_facing_arrows: bool = true
var animating_units: Dictionary = {}  # unit_id → tween

## === 摄像机（与 HexGridRenderer 保持同步） ===
var camera_offset: Vector2 = Vector2.ZERO
var camera_zoom: float = 1.0
var tile_size: float = 64.0
var source_tilemap: TileMapLayer
var source_map_origin: Vector2i = Vector2i.ZERO


func _ready() -> void:
	print("[UnitRenderer] 单位渲染器就绪")


func _draw() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if not unit.is_alive:
			continue
		var pos: Vector2 = _get_unit_screen_pos(unit)
		# 视口裁剪（与 HexGridRenderer._is_on_screen 行为一致，留 60px 边距）
		if pos.x < -60 or pos.x > viewport_size.x + 60 \
		or pos.y < -60 or pos.y > viewport_size.y + 60:
			continue
		_draw_unit(unit, pos)

	# 绘制选中的单位轮廓
	if selected_unit and selected_unit.is_alive:
		_draw_selection_indicator(selected_unit)


## === 摄像机同步 ===
func set_camera(pos: Vector2, zoom: float) -> void:
	camera_offset = pos
	camera_zoom = zoom
	queue_redraw()


func use_source_tilemap(tilemap: TileMapLayer, used_rect: Rect2i) -> void:
	source_tilemap = tilemap
	source_map_origin = used_rect.position
	queue_redraw()


func _get_unit_screen_pos(unit: UnitBase) -> Vector2:
	if source_tilemap:
		var source_cell := Vector2i(unit.grid_col, unit.grid_row) + source_map_origin
		var exact_position := source_tilemap.to_global(source_tilemap.map_to_local(source_cell))
		exact_position.y -= 8.0 * camera_zoom
		return exact_position
	var position := GridManager.grid_to_iso(
		unit.grid_col,
		unit.grid_row
	)

	position += GridManager.get_iso_map_origin()

	position *= camera_zoom
	position += camera_offset

	# 将单位放在地块顶面
	position.y -= 8.0 * camera_zoom

	return position


func _draw_unit(unit: UnitBase, pos: Vector2) -> void:
	"""绘制单个单位"""
	# 单位底色
	var faction_color = FACTION_COLORS.get(unit.faction, Color.GRAY)

	# 尺寸跟随格子大小缩放，避免越界：圆占格子约 78%，留出边距
	var ts: float = GridManager.ISO_TILE_WIDTH * camera_zoom
	var radius: float = GridManager.ISO_TILE_HEIGHT * camera_zoom * 0.38

	# 绘制单位图标（圆形 + 贴图令牌）
	draw_circle(pos, radius, faction_color)
	draw_circle(pos, radius, Color.WHITE, false, max(1.0, ts * 0.03))

	# 单位贴图（居中，直径约为圆的 60%，露出阵营色环）
	var icon := _get_unit_icon(unit)
	if icon != null:
		var icon_size := radius * 1.2
		var rect := Rect2(pos - Vector2(icon_size * 0.5, icon_size * 0.5), Vector2(icon_size, icon_size))
		draw_texture_rect(icon, rect, false)

	# 生命条
	if show_health_bars:
		_draw_health_bar(pos, unit, ts, radius)

	# 方向箭头
	if show_facing_arrows and unit.size_cols > 1:
		_draw_facing_arrow(pos, unit, ts)

	# 选中高亮
	if unit == selected_unit:
		draw_circle(pos, radius + max(2.0, ts * 0.06), Color.YELLOW, false, max(1.5, ts * 0.05))


## === 贴图加载 ===
func _get_unit_icon(unit: UnitBase) -> Texture2D:
	var path: String = UNIT_ICON_PATHS.get(unit.unit_type, "")
	if path.is_empty():
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	var tex: Texture2D = load(path)
	if tex != null:
		_icon_cache[path] = tex
	return tex


func _draw_health_bar(pos: Vector2, unit: UnitBase, ts: float, radius: float) -> void:
	"""绘制单位生命条"""
	var bar_width = ts * 0.72
	var bar_height = max(3.0, ts * 0.07)
	# 紧贴圆下方，留小间距
	var bar_y_offset = radius + max(3.0, ts * 0.08)
	var health_ratio = unit.current_health / unit.max_health

	var bg_rect = Rect2(pos.x - bar_width/2, pos.y + bar_y_offset, bar_width, bar_height)
	draw_rect(bg_rect, Color.BLACK, true)

	if health_ratio > 0.5:
		draw_rect(Rect2(pos.x - bar_width/2, pos.y + bar_y_offset,
			bar_width * health_ratio, bar_height), Color.GREEN, true)
	elif health_ratio > 0.25:
		draw_rect(Rect2(pos.x - bar_width/2, pos.y + bar_y_offset,
			bar_width * health_ratio, bar_height), Color.ORANGE, true)
	else:
		draw_rect(Rect2(pos.x - bar_width/2, pos.y + bar_y_offset,
			bar_width * health_ratio, bar_height), Color.RED, true)

	# 士气标记
	var morale_tier = MoraleSystem.get_unit_morale_tier(unit.unit_id)
	var morale_colors = [Color.RED, Color.ORANGE, Color.WHITE, Color.GOLD]
	var morale_color = morale_colors[morale_tier]
	draw_circle(pos + Vector2(0, bar_y_offset + bar_height + max(3.0, ts * 0.06)),
		max(2.0, ts * 0.06), morale_color)


func _draw_facing_arrow(pos: Vector2, unit: UnitBase, ts: float) -> void:
	"""绘制单位朝向箭头"""
	var arrow_len = ts * 0.32
	var tip = pos + Vector2(cos(unit.facing_angle), sin(unit.facing_angle)) * arrow_len
	draw_line(pos, tip, Color.WHITE, max(1.5, ts * 0.04))
	# 箭头尖端
	var head = max(3.0, ts * 0.09)
	var left = tip + Vector2(cos(unit.facing_angle + PI * 0.75),
		sin(unit.facing_angle + PI * 0.75)) * head
	var right = tip + Vector2(cos(unit.facing_angle - PI * 0.75),
		sin(unit.facing_angle - PI * 0.75)) * head
	draw_line(tip, left, Color.WHITE, max(1.0, ts * 0.025))
	draw_line(tip, right, Color.WHITE, max(1.0, ts * 0.025))


func _draw_selection_indicator(unit: UnitBase) -> void:
	"""绘制选中指示器"""
	var pos = _get_unit_screen_pos(unit)
	var half_width := GridManager.ISO_TILE_WIDTH * camera_zoom * 0.43
	var half_height := GridManager.ISO_TILE_HEIGHT * camera_zoom * 0.43
	var points := PackedVector2Array([
		pos + Vector2(0, -half_height),
		pos + Vector2(half_width, 0),
		pos + Vector2(0, half_height),
		pos + Vector2(-half_width, 0),
		pos + Vector2(0, -half_height),
	])
	draw_polyline(points, Color.YELLOW, maxf(1.5, 2.0 * camera_zoom))


## === 交互 ===
func select_unit(unit: UnitBase) -> void:
	selected_unit = unit
	queue_redraw()


func deselect_unit() -> void:
	selected_unit = null
	queue_redraw()


func get_unit_at_position(screen_pos: Vector2) -> UnitBase:
	"""查找指定屏幕位置的单位"""
	var hit_radius := GridManager.ISO_TILE_HEIGHT * camera_zoom * 0.5
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		var unit_pos = _get_unit_screen_pos(unit)
		if screen_pos.distance_to(unit_pos) < hit_radius:
			return unit
	return null
