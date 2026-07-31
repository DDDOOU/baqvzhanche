# ==============================================================================
# HexGridRenderer.gd — 四边形网格渲染
# ==============================================================================
# 在屏幕上绘制20×15正方形网格，含地形色、标记、高亮、坐标。
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
const HL_ATTACK: Color = Color(1.0, 0.3, 0.1, 0.35)
const HL_PATH: Color   = Color(0.1, 0.9, 0.3, 0.5)
const HL_SELECTED: Color = Color(1.0, 1.0, 0.0, 0.6)

var camera_offset: Vector2 = Vector2.ZERO
var camera_zoom: float = 1.0
var tile_size: float = GridManager.TILE_SIZE
var highlight: Dictionary = {}
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

	var diagonal_count := (
		GridManager.MAP_WIDTH +
		GridManager.MAP_HEIGHT - 1
	)

	for diagonal in range(diagonal_count):
		for row in range(GridManager.MAP_HEIGHT):
			var col := diagonal - row

			if not GridManager.is_valid_cell(col, row):
				continue

			var cell = GridManager.get_cell(col, row)
			if draw_terrain:
				_draw_iso_tile(col, row, cell)
			var key := "%d,%d" % [col, row]
			if highlight.has(key):
				_draw_iso_highlight(col, row, highlight[key])
			if cell.marker != GridManager.CellMarker.NONE:
				_draw_iso_marker(col, row, cell.marker)


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


func highlight_attack_range(unit: UnitBase) -> void:
	var cells = GridManager.get_cells_in_range(unit.grid_col, unit.grid_row, unit.get_effective_range())
	var valid: Array = []
	for p in cells:
		if abs(p.x - unit.grid_col) + abs(p.y - unit.grid_row) <= unit.get_effective_range():
			valid.append(p)
	highlight_cells(valid, HL_ATTACK)


func highlight_path(path: Array) -> void:
	for p in path:
		highlight["%d,%d" % [p.x, p.y]] = HL_PATH
	queue_redraw()


func clear_highlights() -> void:
	highlight.clear()
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
	if source_tilemap:
		var source_cell := Vector2i(col, row) + source_map_origin
		return source_tilemap.to_global(source_tilemap.map_to_local(source_cell))
	var center := GridManager.grid_to_iso(col, row) + map_origin
	return center * camera_zoom + camera_offset


func use_source_tilemap(tilemap: TileMapLayer, used_rect: Rect2i) -> void:
	source_tilemap = tilemap
	source_map_origin = used_rect.position
	draw_terrain = false
	queue_redraw()


func _draw_iso_highlight(col: int, row: int, color: Color) -> void:
	var center := _get_iso_screen_center(col, row)
	var half_width := GridManager.ISO_TILE_WIDTH * camera_zoom * 0.5
	var half_height := GridManager.ISO_TILE_HEIGHT * camera_zoom * 0.5
	var points := PackedVector2Array([
		center + Vector2(0, -half_height),
		center + Vector2(half_width, 0),
		center + Vector2(0, half_height),
		center + Vector2(-half_width, 0),
	])
	draw_colored_polygon(points, color)
	draw_polyline(PackedVector2Array([
		points[0], points[1], points[2], points[3], points[0]
	]), color.lightened(0.35), maxf(1.0, 2.0 * camera_zoom))


func _draw_iso_marker(col: int, row: int, marker: int) -> void:
	var center := _get_iso_screen_center(col, row)
	var color: Color = MARKER_COLORS.get(marker, Color.WHITE)
	var radius := maxf(3.0, GridManager.ISO_TILE_HEIGHT * camera_zoom * 0.18)
	match marker:
		GridManager.CellMarker.VP_POINT:
			draw_circle(center, radius, color, false, maxf(1.0, 2.0 * camera_zoom))
			draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), color, 1.0)
			draw_line(center - Vector2(0, radius), center + Vector2(0, radius), color, 1.0)
		GridManager.CellMarker.WP_SPAWN, GridManager.CellMarker.NATO_SPAWN:
			draw_circle(center, radius, color, false, maxf(1.0, 2.0 * camera_zoom))
		GridManager.CellMarker.UNKNOWN_CONTACT:
			draw_string(ThemeDB.fallback_font, center + Vector2(-4, 5), "?",
				HORIZONTAL_ALIGNMENT_CENTER, -1, 12, color)

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

	var display_size := Vector2(64, 64) * camera_zoom

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
	camera_offset = off
	camera_zoom = zoom
	tile_size = GridManager.TILE_SIZE
	queue_redraw()
