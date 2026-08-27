# ==============================================================================
# FogOfWarRenderer.gd — 覆盖战场实体的战争迷雾渲染层
# ==============================================================================
class_name FogOfWarRenderer
extends Node2D

var camera_offset: Vector2 = Vector2.ZERO
var camera_zoom: float = 1.0
var source_tilemap: TileMapLayer
var source_map_origin: Vector2i = Vector2i.ZERO


func _ready() -> void:
	# 保持在单位和建筑之上；HUD 使用 CanvasLayer，因此不会被遮挡。
	z_index = 10
	queue_redraw()


func set_camera(offset: Vector2, zoom: float) -> void:
	camera_offset = offset
	camera_zoom = zoom
	queue_redraw()


func use_source_tilemap(tilemap: TileMapLayer, used_rect: Rect2i) -> void:
	source_tilemap = tilemap
	source_map_origin = used_rect.position
	queue_redraw()


func _draw() -> void:
	if not FogOfWar.enabled or GridManager.grid.is_empty():
		return

	var diagonal_count := GridManager.MAP_WIDTH + GridManager.MAP_HEIGHT - 1
	for diagonal in range(diagonal_count):
		for row in range(GridManager.MAP_HEIGHT):
			var col := diagonal - row
			if not GridManager.is_valid_cell(col, row):
				continue
			var cell = GridManager.get_cell(col, row)
			if cell == null or cell.is_visible:
				continue
			_draw_fog_cell(col, row, cell.is_explored)


func _draw_fog_cell(col: int, row: int, explored: bool) -> void:
	var center := _get_iso_screen_center(col, row)
	var half_width := GridManager.ISO_TILE_WIDTH * camera_zoom * 0.5
	var half_height := GridManager.ISO_TILE_HEIGHT * camera_zoom * 0.5
	var points := PackedVector2Array([
		center + Vector2(0, -half_height),
		center + Vector2(half_width, 0),
		center + Vector2(0, half_height),
		center + Vector2(-half_width, 0),
	])
	# 底雾保留地形轮廓，叠加的云团打散方格边界；敌军仍由可见性系统直接隐藏。
	# 连续底雾填满相邻格之间的空隙，云团只负责提供像素化层次。
	var veil := Color(0.58, 0.63, 0.71, 0.14) if explored else Color(0.38, 0.46, 0.57, 0.34)
	draw_colored_polygon(points, veil)

	var cloud_color := Color(0.90, 0.93, 0.98, 0.12) if explored else Color(0.84, 0.89, 0.97, 0.26)
	# 云块以地图世界尺寸定义，缩放时和地块保持固定比例。
	var pixel_size := 9.0 * camera_zoom
	for index in range(5):
		var cloud_center := center + _cloud_offset(col, row, index, half_width, half_height)
		var size_scale := 0.82 + _cloud_value(col, row, index + 7) * 0.30
		_draw_pixel_cloud(cloud_center, pixel_size * size_scale, cloud_color, col, row, index)


func _draw_pixel_cloud(center: Vector2, block_size: float, color: Color,
		col: int, row: int, cloud_index: int) -> void:
	# 阶梯状像素块构成云团，保留像素地形的视觉语言。
	const PIXEL_CLOUD: Array[Vector2i] = [
		Vector2i(0, -2), Vector2i(-1, -2), Vector2i(1, -2),
		Vector2i(-2, -1), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(2, -1),
		Vector2i(-3, 0), Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(-2, 1), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(-1, 2), Vector2i(0, 2), Vector2i(1, 2),
	]
	for offset in PIXEL_CLOUD:
		var jitter_seed := cloud_index * 97 + offset.x * 11 + offset.y * 17
		var jitter := 0.74 + _cloud_value(col, row, jitter_seed) * 0.26
		var block_color := Color(color.r, color.g, color.b, color.a * jitter)
		var block_center := center + Vector2(offset) * block_size
		draw_rect(Rect2(block_center - Vector2.ONE * block_size * 0.5, Vector2.ONE * block_size), block_color)


func _cloud_offset(col: int, row: int, index: int, half_width: float, half_height: float) -> Vector2:
	return Vector2(
		(_cloud_value(col, row, index) - 0.5) * half_width * 0.80,
		(_cloud_value(col, row, index + 3) - 0.5) * half_height * 1.10)


func _cloud_value(col: int, row: int, seed_offset: int) -> float:
	var seed := float(col * 127 + row * 311 + seed_offset * 719)
	return 0.5 + 0.5 * sin(seed * 0.017 + sin(seed * 0.071))


func _get_iso_screen_center(col: int, row: int) -> Vector2:
	if source_tilemap:
		var source_cell := Vector2i(col, row) + source_map_origin
		return source_tilemap.to_global(source_tilemap.map_to_local(source_cell))
	var center := GridManager.grid_to_iso(col, row) + GridManager.get_iso_map_origin()
	return center * camera_zoom + camera_offset
