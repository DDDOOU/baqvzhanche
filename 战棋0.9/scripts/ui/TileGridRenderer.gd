# ==============================================================================
# TileGridRenderer.gd — 四边形网格渲染
# ==============================================================================
# 在屏幕上绘制40×45正方形网格，含地形色、标记、高亮、坐标。
# Godot 4.7.1
# ==============================================================================
class_name TileGridRenderer
extends Node2D
const TERRAIN_TEXTURE: Texture2D = preload(
	"res://assets/terrain/isometric_tileset.png"
)

const SOURCE_TILE_SIZE: int = 32

var map_origin: Vector2 = Vector2.ZERO
const TERRAIN_ATLAS: Dictionary = {
	GridManager.TerrainType.PLAINS: Vector2i(0, 2),
	GridManager.TerrainType.FOREST: Vector2i(6, 2),
	GridManager.TerrainType.MOUNTAIN: Vector2i(8, 5),
	GridManager.TerrainType.RIVER: Vector2i(0, 9),
	GridManager.TerrainType.ROAD: Vector2i(3, 0),
	GridManager.TerrainType.RAILWAY: Vector2i(4, 0),
	GridManager.TerrainType.BRIDGE: Vector2i(5, 8),
	GridManager.TerrainType.MARSH: Vector2i(0, 4),
	GridManager.TerrainType.CITY: Vector2i(2, 1),
}

const TERRAIN_COLORS: Dictionary = {
	GridManager.TerrainType.PLAINS:   Color(0.45, 0.60, 0.35),
	GridManager.TerrainType.CITY:     Color(0.30, 0.30, 0.35),
	GridManager.TerrainType.MOUNTAIN: Color(0.40, 0.38, 0.35),
	GridManager.TerrainType.FOREST:   Color(0.15, 0.40, 0.15),
	GridManager.TerrainType.RIVER:    Color(0.20, 0.40, 0.65),
	GridManager.TerrainType.ROAD:     Color(0.55, 0.52, 0.40),
	GridManager.TerrainType.RAILWAY:  Color(0.50, 0.45, 0.35),
	GridManager.TerrainType.BRIDGE:   Color(0.55, 0.45, 0.25),
	GridManager.TerrainType.MARSH:    Color(0.25, 0.35, 0.20),
}

const MARKER_COLORS: Dictionary = {
	GridManager.CellMarker.VP_POINT:         Color(1.0, 0.55, 0.0),
	GridManager.CellMarker.WP_SPAWN:         Color(0.20, 0.50, 1.0),
	GridManager.CellMarker.NATO_SPAWN:       Color(1.0, 0.20, 0.20),
	GridManager.CellMarker.UNKNOWN_CONTACT:  Color(1.0, 0.85, 0.0),
}

const HL_MOVE: Color   = Color(0.2, 0.6, 1.0, 0.35)
const HL_ATTACK: Color = Color(1.0, 0.55, 0.05, 0.52)
const HL_BLOCKED: Color = Color(0.95, 0.08, 0.08, 0.52)
const HL_PATH: Color   = Color(0.1, 0.9, 0.3, 0.5)
const HL_HOVER_PATH: Color = Color(1.0, 1.0, 1.0, 0.42)
const HL_SELECTED: Color = Color(1.0, 1.0, 0.0, 0.6)
const HL_HOVER: Color = Color(1.0, 1.0, 1.0, 0.28)
const HL_CARD_DEFAULT: Color = Color(0.9, 0.6, 0.15, 0.42)
const PLANNED_PATH_COLOR: Color = Color(0.15, 1.0, 0.62, 0.92)
const HL_BUILDING_FRIENDLY: Color = Color(0.15, 0.55, 1.0, 0.20)
const HL_BUILDING_ENEMY: Color = Color(1.0, 0.18, 0.12, 0.22)

var camera_offset: Vector2 = Vector2.ZERO
var camera_zoom: float = 1.0
var tile_size: float = GridManager.TILE_SIZE
var highlight: Dictionary = {}
var pending_path_highlight: Dictionary = {}
var hover_path_highlight: Dictionary = {}
var card_highlight: Dictionary = {}
var building_highlight: Dictionary = {}
var planned_paths: Dictionary = {}  # unit_id → {start: Vector2i, path: Array}
var marker_cells: Dictionary = {}
var marker_cache_ready: bool = false
var hover_cell: Vector2i = Vector2i(-1, -1)
var show_coordinates: bool = true
var draw_terrain: bool = true
var source_tilemap: TileMapLayer
var source_map_origin: Vector2i = Vector2i.ZERO


func _ready() -> void:
	map_origin = GridManager.get_iso_map_origin()
	queue_redraw()


func _draw() -> void:
	if GridManager.grid.is_empty():
		return
	if not marker_cache_ready:
		_rebuild_marker_cache()

	# 设计关卡的地形由 TileMapLayer 绘制。仅在旧的脚本地形回退模式中遍历全图。
	if draw_terrain:
		var diagonal_count := GridManager.MAP_WIDTH + GridManager.MAP_HEIGHT - 1
		for diagonal in range(diagonal_count):
			for row in range(GridManager.MAP_HEIGHT):
				var col := diagonal - row
				if GridManager.is_valid_cell(col, row):
					_draw_iso_tile(col, row, GridManager.get_cell(col, row))

	# 动态覆盖层只遍历真正需要显示的格子，不再因一次鼠标悬停扫描整张地图。
	for key_variant in building_highlight:
		var key := String(key_variant)
		var position_value := _position_from_key(key)
		if not _can_draw_overlay(position_value):
			continue
		var building_owner: int = building_highlight[key]
		var owner_color := HL_BUILDING_FRIENDLY if building_owner == UnitBase.Faction.WARSAW_PACT else HL_BUILDING_ENEMY
		_draw_iso_highlight(position_value.x, position_value.y, owner_color)
	# 移动范围与路径属于玩家的计划信息，必须跨越战争迷雾完整显示。
	# 迷雾只隐藏战场情报，不能截断蓝色范围或白/绿色规划路线。
	_draw_highlight_dictionary(highlight, Color(-1, -1, -1, -1), true)
	_draw_highlight_dictionary(pending_path_highlight, HL_PATH, true)
	_draw_highlight_dictionary(hover_path_highlight, HL_HOVER_PATH, true)
	_draw_highlight_dictionary(card_highlight)
	if _can_draw_movement_overlay(hover_cell):
		_draw_iso_highlight(hover_cell.x, hover_cell.y, HL_HOVER)
	for key_variant in marker_cells:
		var key := String(key_variant)
		var position_value := _position_from_key(key)
		var marker := int(marker_cells[key])
		# VP是已知任务目标，即使处于战争迷雾中也必须保留旗帜提示。
		if marker == GridManager.CellMarker.VP_POINT or _can_draw_overlay(position_value):
			_draw_iso_marker(position_value.x, position_value.y, marker)

	_draw_planned_paths()


func _draw_highlight_dictionary(cells: Dictionary,
		fixed_color: Color = Color(-1, -1, -1, -1), ignore_fog: bool = false) -> void:
	for key_variant in cells:
		var key := String(key_variant)
		var position_value := _position_from_key(key)
		if ignore_fog:
			if not _can_draw_movement_overlay(position_value):
				continue
		elif not _can_draw_overlay(position_value):
			continue
		var color: Color = fixed_color if fixed_color.a >= 0.0 else cells[key]
		_draw_iso_highlight(position_value.x, position_value.y, color)


func _position_from_key(key: String) -> Vector2i:
	var parts := key.split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


func _can_draw_overlay(position_value: Vector2i) -> bool:
	if not GridManager.is_valid_cell(position_value.x, position_value.y):
		return false
	return not FogOfWar.enabled or _is_cell_visible(position_value)


func _can_draw_movement_overlay(position_value: Vector2i) -> bool:
	return GridManager.is_valid_cell(position_value.x, position_value.y)


func _rebuild_marker_cache() -> void:
	marker_cells.clear()
	for row in range(GridManager.MAP_HEIGHT):
		for col in range(GridManager.MAP_WIDTH):
			var cell = GridManager.get_cell(col, row)
			if cell and cell.marker != GridManager.CellMarker.NONE:
				marker_cells["%d,%d" % [col, row]] = cell.marker
	marker_cache_ready = true


func _on_screen(rect: Rect2) -> bool:
	var vs = get_viewport_rect().size
	return rect.position.x + rect.size.x > -100 and rect.position.x < vs.x + 100 and \
		rect.position.y + rect.size.y > -100 and rect.position.y < vs.y + 100


func _draw_marker(rect: Rect2, marker: int) -> void:
	var c = MARKER_COLORS.get(marker, Color.WHITE)
	var cx = rect.position.x + rect.size.x / 2.0
	var cy = rect.position.y + rect.size.y / 2.0
	var s = rect.size.x * 0.2
	match marker:
		GridManager.CellMarker.VP_POINT:
			draw_line(Vector2(cx - s, cy), Vector2(cx + s, cy), c, 2)
			draw_line(Vector2(cx, cy - s), Vector2(cx, cy + s), c, 2)
		GridManager.CellMarker.WP_SPAWN, GridManager.CellMarker.NATO_SPAWN:
			draw_circle(Vector2(cx, cy), s, c, false, 2)
		GridManager.CellMarker.UNKNOWN_CONTACT:
			draw_string(ThemeDB.fallback_font, Vector2(cx - 6, cy + 6), "?", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, c)


func _draw_coord(tl: Vector2, ts: float, col: int, row: int) -> void:
	draw_string(ThemeDB.fallback_font, tl + Vector2(2, ts - 2),
		"(%d,%d)" % [col + 1, row + 1],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE.darkened(0.3))


## ==================== 高亮 ====================

func highlight_cells(cells: Array, color: Color) -> void:
	highlight.clear()
	for p in cells:
		highlight["%d,%d" % [p.x, p.y]] = color
	queue_redraw()


func highlight_move_range(unit: UnitBase) -> void:
	var reachable = TilePathfinding.get_reachable_cells(unit)
	highlight_cells(reachable, HL_MOVE)


func highlight_unit_actions(unit: UnitBase) -> void:
	"""蓝色显示可移动格，红色显示障碍，橙色显示可攻击敌军。"""
	highlight.clear()
	var is_armored := TilePathfinding.is_armored(unit)
	# 先标记当前移动半径内的不可通行地块，例如建筑四格占地。
	# 后绘制的敌军攻击格可覆盖障碍色，保持攻击目标优先可读。
	for p in GridManager.get_cells_in_range(
			unit.grid_col, unit.grid_row, unit.get_effective_movement()):
		var cell = GridManager.get_cell(p.x, p.y)
		if cell and not cell.is_passable_for(is_armored):
			highlight["%d,%d" % [p.x, p.y]] = HL_BLOCKED
	for p in TilePathfinding.get_reachable_cells(unit):
		highlight["%d,%d" % [p.x, p.y]] = HL_MOVE
	for candidate in get_tree().get_nodes_in_group("units"):
		if not candidate is UnitBase or not candidate.is_alive or candidate.faction == unit.faction:
			continue
		if not FogOfWar.is_unit_visible(candidate):
			continue
		if unit.can_attack_target(candidate.grid_col, candidate.grid_row):
			highlight["%d,%d" % [candidate.grid_col, candidate.grid_row]] = HL_ATTACK
	queue_redraw()


func highlight_attack_range(unit: UnitBase) -> void:
	var cells = GridManager.get_cells_in_range(unit.grid_col, unit.grid_row, unit.get_effective_range())
	var valid: Array = []
	for p in cells:
		if abs(p.x - unit.grid_col) + abs(p.y - unit.grid_row) <= unit.get_effective_range():
			valid.append(p)
	highlight_cells(valid, HL_ATTACK)


func highlight_path(path: Array) -> void:
	pending_path_highlight.clear()
	for p in path:
		pending_path_highlight["%d,%d" % [p.x, p.y]] = true
	queue_redraw()


func set_hover_move_path(path: Array) -> void:
	hover_path_highlight.clear()
	for p in path:
		hover_path_highlight["%d,%d" % [p.x, p.y]] = true
	queue_redraw()


func clear_hover_move_path() -> void:
	if hover_path_highlight.is_empty():
		return
	hover_path_highlight.clear()
	queue_redraw()


func set_planned_path(unit_id: int, start_cell: Vector2i, path: Array) -> void:
	"""保存一条已确认的玩家移动路线，直到执行完毕或进入下一回合。"""
	planned_paths[unit_id] = {
		"start": start_cell,
		"path": path.duplicate(),
	}
	queue_redraw()


func remove_planned_path(unit_id: int) -> void:
	if planned_paths.erase(unit_id):
		queue_redraw()


func clear_planned_paths() -> void:
	if planned_paths.is_empty():
		return
	planned_paths.clear()
	queue_redraw()


func _draw_planned_paths() -> void:
	for unit_id in planned_paths:
		var route: Dictionary = planned_paths[unit_id]
		var path: Array = route.get("path", [])
		if path.is_empty():
			continue
		var previous: Vector2i = route.get("start", path[0])
		var previous_center := _get_iso_screen_center(previous.x, previous.y)
		for step_variant in path:
			var step: Vector2i = step_variant
			var center := _get_iso_screen_center(step.x, step.y)
			draw_line(previous_center, center, PLANNED_PATH_COLOR,
				4.0, true)
			draw_circle(center, 4.5, PLANNED_PATH_COLOR)
			previous_center = center
		# 终点使用较大的圆环，区别于尚未确认的绿色格子高亮。
		draw_circle(previous_center, 8.0,
			PLANNED_PATH_COLOR, false, 2.5)


func clear_highlights() -> void:
	highlight.clear()
	pending_path_highlight.clear()
	hover_path_highlight.clear()
	queue_redraw()


func set_card_highlight(cells: Array, color: Color = HL_CARD_DEFAULT) -> void:
	card_highlight.clear()
	for p in cells:
		card_highlight["%d,%d" % [p.x, p.y]] = color
	queue_redraw()


func clear_card_highlight() -> void:
	if card_highlight.is_empty():
		return
	card_highlight.clear()
	queue_redraw()


func set_building_highlights(cells_by_owner: Dictionary) -> void:
	building_highlight = cells_by_owner.duplicate()
	queue_redraw()


func set_hover_cell(cell: Vector2i) -> void:
	if hover_cell == cell:
		return
	hover_cell = cell
	queue_redraw()


## ==================== 点击检测 ====================

func grid_pos_at_screen(screen_pos: Vector2) -> Vector2i:
	"""屏幕坐标 → 等距地图格坐标"""
	if source_tilemap:
		var source_cell := source_tilemap.local_to_map(source_tilemap.to_local(screen_pos))
		var logical_cell := source_cell - source_map_origin
		if GridManager.is_valid_cell(logical_cell.x, logical_cell.y):
			return logical_cell
		return Vector2i(-1, -1)
	var local_position := screen_pos - camera_offset
	local_position /= camera_zoom
	local_position -= map_origin
	var grid_position := GridManager.iso_to_grid(local_position)
	if GridManager.is_valid_cell(grid_position.x, grid_position.y):
		return grid_position
	return Vector2i(-1, -1)


func _get_iso_screen_center(col: int, row: int) -> Vector2:
	return GridManager.grid_to_iso(col, row) + map_origin


func use_source_tilemap(tilemap: TileMapLayer, used_rect: Rect2i) -> void:
	source_tilemap = tilemap
	source_map_origin = used_rect.position
	map_origin = GridManager.get_iso_map_origin()
	marker_cells.clear()
	marker_cache_ready = false
	draw_terrain = false
	queue_redraw()


func _draw_iso_highlight(col: int, row: int, color: Color) -> void:
	var center := _get_iso_screen_center(col, row)
	var half_width := GridManager.ISO_TILE_WIDTH * 0.5
	var half_height := GridManager.ISO_TILE_HEIGHT * 0.5
	var points := PackedVector2Array([
		center + Vector2(0, -half_height),
		center + Vector2(half_width, 0),
		center + Vector2(0, half_height),
		center + Vector2(-half_width, 0),
	])
	draw_colored_polygon(points, color)
	draw_polyline(PackedVector2Array([
		points[0], points[1], points[2], points[3], points[0]
	]), color.lightened(0.35), 2.0)


func _draw_iso_marker(col: int, row: int, marker: int) -> void:
	var center := _get_iso_screen_center(col, row)
	var color: Color = MARKER_COLORS.get(marker, Color.WHITE)
	var radius := GridManager.ISO_TILE_HEIGHT * 0.18
	match marker:
		GridManager.CellMarker.VP_POINT:
			color = _get_vp_marker_color(col, row)
			var half_width := GridManager.ISO_TILE_WIDTH * 0.5
			var half_height := GridManager.ISO_TILE_HEIGHT * 0.5
			var tile_points := PackedVector2Array([
				center + Vector2(0, -half_height),
				center + Vector2(half_width, 0),
				center + Vector2(0, half_height),
				center + Vector2(-half_width, 0),
				center + Vector2(0, -half_height),
			])
			var tile_fill := PackedVector2Array([tile_points[0], tile_points[1], tile_points[2], tile_points[3]])
			draw_colored_polygon(tile_fill, Color(color.r, color.g, color.b, 0.20))
			draw_polyline(tile_points, Color(0.04, 0.04, 0.04, 0.95), 5.0)
			draw_polyline(tile_points, color, 3.0)

			# 程序化像素旗帜：旗杆落在VP格中心，旗面颜色随当前控制方变化。
			var pole_bottom := center + Vector2(0, 2)
			var pole_top := center + Vector2(0, -34)
			draw_line(pole_bottom, pole_top, Color(0.04, 0.04, 0.04), 5.0)
			draw_line(pole_bottom, pole_top, Color(0.82, 0.82, 0.72), 2.5)
			var flag := PackedVector2Array([
				pole_top + Vector2(1, 1),
				pole_top + Vector2(22, 1),
				pole_top + Vector2(17, 7),
				pole_top + Vector2(22, 13),
				pole_top + Vector2(1, 13),
			])
			draw_colored_polygon(flag, color)
			draw_polyline(PackedVector2Array([flag[0], flag[1], flag[2], flag[3], flag[4], flag[0]]),
				Color(0.04, 0.04, 0.04, 0.95), 2.0)
			draw_string(ThemeDB.fallback_font, center + Vector2(-10, 13), "VP",
				HORIZONTAL_ALIGNMENT_CENTER, 20, 12, Color(0.05, 0.05, 0.05))
			draw_string(ThemeDB.fallback_font, center + Vector2(-10, 12), "VP",
				HORIZONTAL_ALIGNMENT_CENTER, 20, 12, Color.WHITE)
		GridManager.CellMarker.WP_SPAWN, GridManager.CellMarker.NATO_SPAWN:
			draw_circle(center, radius, color, false, 2.0)
		GridManager.CellMarker.UNKNOWN_CONTACT:
			draw_string(ThemeDB.fallback_font, center + Vector2(-4, 5), "?",
				HORIZONTAL_ALIGNMENT_CENTER, -1, 12, color)


func _get_vp_marker_color(col: int, row: int) -> Color:
	var cell = GridManager.get_cell(col, row)
	if cell != null and cell.occupant_unit != null and cell.occupant_unit.is_alive:
		if cell.occupant_unit.faction == UnitBase.Faction.WARSAW_PACT:
			return Color(0.20, 0.62, 1.0)
		if cell.occupant_unit.faction == UnitBase.Faction.NATO:
			return Color(1.0, 0.24, 0.18)
	return Color(1.0, 0.67, 0.08)


func _is_cell_visible(position: Vector2i) -> bool:
	var cell = GridManager.get_cell(position.x, position.y)
	return cell != null and cell.is_visible

func _draw_iso_tile(col: int, row: int, cell) -> void:
	var atlas_position: Vector2i = TERRAIN_ATLAS.get(
		cell.terrain,
		Vector2i(0, 2)
	)

	var source_rect := Rect2(
		atlas_position.x * SOURCE_TILE_SIZE,
		atlas_position.y * SOURCE_TILE_SIZE,
		SOURCE_TILE_SIZE,
		SOURCE_TILE_SIZE
	)

	var center := _get_iso_screen_center(col, row)

	var display_size := Vector2(64, 64)

	var destination_rect := Rect2(
		center - display_size * 0.5,
		display_size
	)

	draw_texture_rect_region(
		TERRAIN_TEXTURE,
		destination_rect,
		source_rect
	)
func set_camera(off: Vector2, zoom: float) -> void:
	if camera_offset.is_equal_approx(off) and is_equal_approx(camera_zoom, zoom):
		return
	camera_offset = off
	camera_zoom = zoom
	tile_size = GridManager.TILE_SIZE
	# 高亮与路径保持地图世界坐标；平移缩放整层即可，避免镜头移动时遍历全部格子。
	position = off
	scale = Vector2.ONE * zoom
