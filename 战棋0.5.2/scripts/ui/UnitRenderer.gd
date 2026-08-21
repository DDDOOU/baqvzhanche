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

## 四方向移动序列帧。每格32×32；行顺序：右下、左下、左上、右上；每行4帧。
## 第一版先接入T-72B用于验证完整动画链路，后续单位可按同一规格继续追加。
const ANIMATED_UNIT_SHEETS: Dictionary = {
	UnitBase.UnitType.T72B_TANK: {
		"path": "res://assets/units/animated/wp_light_tank_4dir_4f_chunky.png",
		"frame_size": Vector2i(32, 32),
		"frames_per_direction": 4,
		"direction_count": 4,
		"ground_anchor": Vector2(16.0, 28.0),
		# 与建筑层相同：原生像素按关卡场景的2×zoom显示。
		"native_world_scale": 2.0,
	},
}

## 贴图缓存（路径 → Texture2D）
var _icon_cache: Dictionary = {}

## === 状态 ===
var selected_unit: UnitBase = null
var focused_unit: UnitBase = null  # 顶部顺序条点击定位目标，不参与地图操作选择
var show_health_bars: bool = true
var show_facing_arrows: bool = true
var animating_units: Dictionary = {}  # unit_id → Tween
var animated_grid_states: Dictionary = {}  # unit_id → {from, to, progress}
var unit_animation_directions: Dictionary = {}  # unit_id → 0右下/1左下/2左上/3右上
var animated_sprite_nodes: Dictionary = {}  # unit_id → Sprite2D；与建筑使用相同渲染管线

## === 摄像机（与 TileGridRenderer 保持同步） ===
var camera_offset: Vector2 = Vector2.ZERO
var camera_zoom: float = 1.0
var tile_size: float = 64.0
var source_tilemap: TileMapLayer
var source_map_origin: Vector2i = Vector2i.ZERO
var focus_pulse_phase: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)
	print("[UnitRenderer] 单位渲染器就绪")


func _process(delta: float) -> void:
	if focused_unit == null or not is_instance_valid(focused_unit) or not focused_unit.is_alive:
		clear_focused_unit()
		return
	focus_pulse_phase = fmod(focus_pulse_phase + delta * 3.2, TAU)
	queue_redraw()


func _draw() -> void:
	# Sprite2D是保留节点；每次重绘先隐藏，本帧仍在视口内的单位会重新启用。
	for sprite_value in animated_sprite_nodes.values():
		var retained_sprite := sprite_value as Sprite2D
		if retained_sprite:
			retained_sprite.visible = false
	var viewport_size: Vector2 = get_viewport_rect().size
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if not unit.is_alive:
			continue
		var pos: Vector2 = _get_unit_screen_pos(unit)
# 视口裁剪（与 TileGridRenderer._is_on_screen 行为一致，留 60px 边距）
		if pos.x < -60 or pos.x > viewport_size.x + 60 \
		or pos.y < -60 or pos.y > viewport_size.y + 60:
			continue
		# 头像框定位提示画在单位底部，不覆盖图标、血条和地图操作选框。
		if unit == focused_unit:
			_draw_focus_ring(pos)
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
	if animated_grid_states.has(unit.unit_id):
		var state: Dictionary = animated_grid_states[unit.unit_id]
		var from_cell: Vector2i = state["from"]
		var to_cell: Vector2i = state["to"]
		var progress: float = state["progress"]
		# 每次重绘都通过当前TileMap/相机计算端点，移动视角不会产生偏移。
		return _get_grid_screen_pos(from_cell.x, from_cell.y).lerp(
			_get_grid_screen_pos(to_cell.x, to_cell.y), progress)
	return _get_grid_screen_pos(unit.grid_col, unit.grid_row)


func _get_grid_screen_pos(col: int, row: int) -> Vector2:
	if source_tilemap:
		var source_cell := Vector2i(col, row) + source_map_origin
		var exact_position := source_tilemap.to_global(source_tilemap.map_to_local(source_cell))
		exact_position.y -= 8.0 * camera_zoom
		return exact_position
	var position := GridManager.grid_to_iso(
		col,
		row
	)

	position += GridManager.get_iso_map_origin()

	position *= camera_zoom
	position += camera_offset

	# 将单位放在地块顶面
	position.y -= 8.0 * camera_zoom

	return position


func animate_unit_step(unit_id: int, from_cell: Vector2i, to_cell: Vector2i,
		duration: float) -> void:
	"""让自绘单位图标在两个格子中心之间平滑移动。"""
	if animating_units.has(unit_id):
		var old_tween: Tween = animating_units[unit_id]
		if old_tween and old_tween.is_valid():
			old_tween.kill()
	var direction_row := _direction_row_from_step(to_cell - from_cell)
	unit_animation_directions[unit_id] = direction_row
	animated_grid_states[unit_id] = {
		"from": from_cell,
		"to": to_cell,
		"progress": 0.0,
		"direction_row": direction_row,
	}
	var tween := create_tween()
	animating_units[unit_id] = tween
	tween.tween_method(func(progress: float) -> void:
		if animated_grid_states.has(unit_id):
			animated_grid_states[unit_id]["progress"] = progress
		queue_redraw(), 0.0, 1.0, maxf(0.01, duration))
	tween.finished.connect(func() -> void:
		animated_grid_states.erase(unit_id)
		animating_units.erase(unit_id)
		queue_redraw())


func get_unit_screen_position(unit: UnitBase) -> Vector2:
	"""公开单位的屏幕位置，供建筑遮挡检测等界面功能复用。"""
	return _get_unit_screen_pos(unit)


func _draw_unit(unit: UnitBase, pos: Vector2) -> void:
	"""绘制单个单位"""
	# 单位底色
	var faction_color = FACTION_COLORS.get(unit.faction, Color.GRAY)

	# 尺寸跟随格子大小缩放，避免越界：圆占格子约 78%，留出边距
	var ts: float = GridManager.ISO_TILE_WIDTH * camera_zoom
	var radius: float = GridManager.ISO_TILE_HEIGHT * camera_zoom * 0.38

	var animation_config: Dictionary = ANIMATED_UNIT_SHEETS.get(unit.unit_type, {})
	if not animation_config.is_empty():
		_sync_animated_unit_sprite(unit, pos, animation_config)
	else:
		# 尚未制作序列帧的单位继续使用圆形贴图令牌。
		draw_circle(pos, radius, faction_color)
		draw_circle(pos, radius, Color.WHITE, false, max(1.0, ts * 0.03))
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


func _sync_animated_unit_sprite(unit: UnitBase, pos: Vector2, config: Dictionary) -> void:
	"""使用与建筑层相同的Sprite2D变换显示序列帧，避免目标矩形重采样。"""
	var path := String(config.get("path", ""))
	var texture := _load_cached_texture(path)
	if texture == null:
		return
	var sprite := animated_sprite_nodes.get(unit.unit_id) as Sprite2D
	if sprite == null or not is_instance_valid(sprite):
		sprite = Sprite2D.new()
		sprite.name = "AnimatedUnit_%d" % unit.unit_id
		sprite.centered = false
		sprite.region_enabled = true
		sprite.region_filter_clip_enabled = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# 单位模型先绘制，选中环、生命条和方向箭头保持在模型上层。
		sprite.show_behind_parent = true
		add_child(sprite)
		animated_sprite_nodes[unit.unit_id] = sprite
	sprite.texture = texture
	var frame_size: Vector2i = config.get("frame_size", Vector2i(32, 32))
	var frame_coords := get_animation_frame_coords(unit)
	sprite.region_rect = Rect2(
		Vector2(frame_coords.x * frame_size.x, frame_coords.y * frame_size.y),
		Vector2(frame_size))
	var ground_anchor: Vector2 = config.get("ground_anchor", Vector2(32.0, 56.0))
	# 使用32px原生帧并采用与建筑层一致的2×zoom缩放。最终世界尺寸仍为64px，
	# Sprite2D直接应用变换，不再把源图压入四舍五入后的目标矩形。
	var visual_zoom := get_animated_visual_zoom()
	var native_world_scale := float(config.get("native_world_scale", 1.0))
	var sprite_scale := visual_zoom * native_world_scale
	# UnitRenderer的逻辑位置已比地块中心上移8px；把履带接地点放回地块顶面。
	var ground_point := pos + Vector2(0.0, 8.0 * camera_zoom)
	sprite.position = ground_point - ground_anchor * sprite_scale
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.visible = true


func get_animated_visual_zoom() -> float:
	return camera_zoom


func get_animation_frame_coords(unit: UnitBase) -> Vector2i:
	"""返回当前序列帧坐标，供渲染与自动测试共用。"""
	var direction_row := int(unit_animation_directions.get(unit.unit_id, 0))
	var frame_index := 0
	if animated_grid_states.has(unit.unit_id):
		var state: Dictionary = animated_grid_states[unit.unit_id]
		direction_row = int(state.get("direction_row", direction_row))
		var progress := clampf(float(state.get("progress", 0.0)), 0.0, 0.9999)
		frame_index = mini(3, int(floor(progress * 4.0)))
	return Vector2i(frame_index, direction_row)


func _direction_row_from_step(step: Vector2i) -> int:
	if step.x > 0:
		return 0  # 地图列+1：屏幕右下
	if step.y > 0:
		return 1  # 地图行+1：屏幕左下
	if step.x < 0:
		return 2  # 地图列-1：屏幕左上
	if step.y < 0:
		return 3  # 地图行-1：屏幕右上
	return 0


## === 贴图加载 ===
func _get_unit_icon(unit: UnitBase) -> Texture2D:
	var path: String = UNIT_ICON_PATHS.get(unit.unit_type, "")
	return _load_cached_texture(path)


func _load_cached_texture(path: String) -> Texture2D:
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


func _draw_focus_ring(unit_pos: Vector2) -> void:
	"""绘制顶部头像框定位产生的2.5D呼吸底圈。"""
	var pulse := (sin(focus_pulse_phase) + 1.0) * 0.5
	var scale_factor := lerpf(0.92, 1.10, pulse)
	var center := unit_pos + Vector2(0.0, 8.0 * camera_zoom)
	var radius_x := GridManager.ISO_TILE_WIDTH * camera_zoom * 0.48 * scale_factor
	var radius_y := GridManager.ISO_TILE_HEIGHT * camera_zoom * 0.30 * scale_factor
	var ring_points := PackedVector2Array()
	for index in range(49):
		var angle := TAU * float(index) / 48.0
		ring_points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	# 宽而透明的外层负责呼吸光晕，细实线保证缩放后仍清楚可见。
	var glow_alpha := lerpf(0.22, 0.48, pulse)
	draw_polyline(ring_points, Color(1.0, 0.78, 0.12, glow_alpha),
		maxf(4.0, 7.0 * camera_zoom), true)
	draw_polyline(ring_points, Color(1.0, 0.94, 0.30, lerpf(0.72, 1.0, pulse)),
		maxf(1.5, 2.2 * camera_zoom), true)


## === 交互 ===
func select_unit(unit: UnitBase) -> void:
	selected_unit = unit
	queue_redraw()


func deselect_unit() -> void:
	selected_unit = null
	queue_redraw()


func focus_unit(unit: UnitBase) -> void:
	"""显示顶部顺序条定位用的呼吸环；不会改变地图操作选中单位。"""
	focused_unit = unit
	focus_pulse_phase = 0.0
	set_process(focused_unit != null)
	queue_redraw()


func clear_focused_unit() -> void:
	focused_unit = null
	focus_pulse_phase = 0.0
	set_process(false)
	queue_redraw()


func get_unit_at_position(screen_pos: Vector2) -> UnitBase:
	"""查找指定屏幕位置的单位"""
	var hit_radius := GridManager.ISO_TILE_HEIGHT * camera_zoom * 0.5
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		var unit_pos = _get_unit_screen_pos(unit)
		if screen_pos.distance_to(unit_pos) < hit_radius:
			return unit
	return null
