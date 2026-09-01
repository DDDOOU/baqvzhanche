# ==============================================================================
# FogOfWarRenderer.gd — 覆盖战场实体的战争迷雾渲染层
# ==============================================================================
class_name FogOfWarRenderer
extends Node2D

const FOG_TEXTURE: Texture2D = preload("res://assets/effects/fog/pixel_fog_tile.png")

var camera_offset: Vector2 = Vector2.ZERO
var camera_zoom: float = 1.0
var source_tilemap: TileMapLayer
var source_map_origin: Vector2i = Vector2i.ZERO


func _ready() -> void:
	# 保持在单位和建筑之上；HUD 使用 CanvasLayer，因此不会被遮挡。
	z_index = 10
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func set_camera(offset: Vector2, zoom: float) -> void:
	if camera_offset.is_equal_approx(offset) and is_equal_approx(camera_zoom, zoom):
		return
	camera_offset = offset
	camera_zoom = zoom
	# 迷雾绘制命令保存在地图世界坐标中；镜头移动只变换整层，不重建所有格子。
	position = offset
	scale = Vector2.ONE * zoom


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
	var center := _get_iso_world_center(col, row)
	var half_width := GridManager.ISO_TILE_WIDTH * 0.5
	var half_height := GridManager.ISO_TILE_HEIGHT * 0.5
	var fog_size := Vector2(
		GridManager.ISO_TILE_WIDTH * 1.55,
		GridManager.ISO_TILE_HEIGHT * 2.10
	)
	var points := PackedVector2Array([
		center + Vector2(0, -half_height),
		center + Vector2(half_width, 0),
		center + Vector2(0, half_height),
		center + Vector2(-half_width, 0),
	])
	# 底雾保留地形轮廓；每格只叠加一次纹理，替代原先 115 次像素块绘制。
	var veil := Color(0.58, 0.63, 0.71, 0.14) if explored else Color(0.38, 0.46, 0.57, 0.34)
	draw_colored_polygon(points, veil)
	var jitter := Vector2(
		float((col * 17 + row * 11) % 9 - 4),
		float((col * 7 + row * 19) % 7 - 3)
	)
	var fog_rect := Rect2(center + jitter - fog_size * 0.5, fog_size)
	var texture_tint := Color(0.82, 0.88, 0.94, 0.48) if explored else Color(0.69, 0.78, 0.88, 0.78)
	draw_texture_rect(FOG_TEXTURE, fog_rect, false, texture_tint)


func _get_iso_world_center(col: int, row: int) -> Vector2:
	return GridManager.grid_to_iso(col, row) + GridManager.get_iso_map_origin()
