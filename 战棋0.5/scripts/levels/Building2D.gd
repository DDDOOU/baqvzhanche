@tool
class_name Building2D
extends Node2D

## 建筑根节点就是2×2占地的中心锚点。
## 图片只是根节点的子节点，可独立调整，不再参与占地坐标计算。

enum BuildingCategory {
	FORTIFICATION,
	INFRASTRUCTURE,
}

const FOOTPRINT_SIZE := Vector2i(2, 2)
const CATEGORY_PATHS := {
	BuildingCategory.FORTIFICATION: "res://assets/outdoor_buildings_64/fortifications/fortifications_%02d.png",
	BuildingCategory.INFRASTRUCTURE: "res://assets/outdoor_buildings_64/infrastructure/infrastructure_%02d.png",
}

@export_category("建筑素材（Building Asset）")
@export var building_category: BuildingCategory = BuildingCategory.FORTIFICATION:
	set(value):
		building_category = value
		_refresh_visual()

@export_range(1, 16, 1) var building_index: int = 1:
	set(value):
		building_index = clampi(value, 1, 16)
		_refresh_visual()

@export var building_name: String = "建筑"

@export_category("中心点与图片（Pivot & Visual）")
## 调整图片相对红色中心点的位置；红色中心点本身始终是四格中心。
@export var visual_offset: Vector2 = Vector2(0, -12):
	set(value):
		visual_offset = value
		_refresh_visual_transform()

@export var visual_scale: Vector2 = Vector2.ONE:
	set(value):
		visual_scale = value
		_refresh_visual_transform()

@export_category("地图坐标（Grid Coordinate）")
## 2×2占地的左上角；根节点位置自动落在四格共同中心。
@export var grid_coordinate: Vector2i = Vector2i.ZERO:
	set(value):
		grid_coordinate = value
		_sync_position_deferred()

@export var editor_grid_snap: bool = true

@export_category("建筑规则（Building Rules）")
@export var blocks_movement: bool = true
@export var blocks_line_of_sight: bool = true
@export_range(0, 5000, 10) var max_health: int = 500

var _last_synced_position := Vector2.INF
var _syncing_position := false


func _ready() -> void:
	_refresh_visual()
	queue_redraw()
	call_deferred("_initialize_from_saved_position")


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() or _syncing_position or not editor_grid_snap:
		return
	if _last_synced_position != Vector2.INF and not position.is_equal_approx(_last_synced_position):
		_update_grid_from_position()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	# 2×2地块的共同中心和占地外框；该红框内四格即不可通行区域。
	var points := PackedVector2Array([
		Vector2(0, -16), Vector2(32, 0),
		Vector2(0, 16), Vector2(-32, 0), Vector2(0, -16),
	])
	draw_polyline(points, Color(1.0, 0.15, 0.15, 0.9), 1.5)
	draw_circle(Vector2.ZERO, 2.5, Color(1.0, 0.9, 0.1, 1.0))


func get_occupied_cells() -> Array[Vector2i]:
	return [
		grid_coordinate,
		grid_coordinate + Vector2i(1, 0),
		grid_coordinate + Vector2i(0, 1),
		grid_coordinate + Vector2i(1, 1),
	]


func get_player_coordinate() -> String:
	return GridManager.grid_to_player_coordinate(grid_coordinate)


func _get_visual() -> Sprite2D:
	return get_node_or_null("Visual") as Sprite2D


func _refresh_visual() -> void:
	var visual := _get_visual()
	if visual == null:
		return
	var pattern: String = CATEGORY_PATHS.get(building_category, "")
	var path := pattern % building_index
	if ResourceLoader.exists(path):
		visual.texture = load(path)
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_refresh_visual_transform()


func _refresh_visual_transform() -> void:
	var visual := _get_visual()
	if visual == null:
		return
	visual.position = visual_offset
	visual.scale = visual_scale


func _sync_position_deferred() -> void:
	if is_inside_tree():
		call_deferred("_sync_position")


func _sync_position() -> void:
	var terrain := _find_terrain_layer()
	if terrain == null:
		return
	_syncing_position = true
	position = _get_anchor_position(terrain, grid_coordinate)
	_last_synced_position = position
	_syncing_position = false


func _initialize_from_saved_position() -> void:
	sync_grid_from_saved_position()


func sync_grid_from_saved_position() -> void:
	_update_grid_from_position()


func _update_grid_from_position() -> void:
	var terrain := _find_terrain_layer()
	if terrain == null:
		return
	var used_rect := terrain.get_used_rect()
	if used_rect.size.x < 2 or used_rect.size.y < 2:
		return

	var center_in_terrain: Vector2 = terrain.to_local(global_position)
	var nearby_logical := terrain.local_to_map(center_in_terrain) - used_rect.position
	var best_anchor := grid_coordinate
	var best_distance := INF
	for y in range(nearby_logical.y - 2, nearby_logical.y + 2):
		for x in range(nearby_logical.x - 2, nearby_logical.x + 2):
			var candidate := Vector2i(x, y)
			if candidate.x < 0 or candidate.y < 0:
				continue
			if candidate.x + 2 > used_rect.size.x or candidate.y + 2 > used_rect.size.y:
				continue
			var candidate_center := _get_anchor_center_in_terrain(terrain, candidate)
			var distance := center_in_terrain.distance_squared_to(candidate_center)
			if distance < best_distance:
				best_distance = distance
				best_anchor = candidate

	grid_coordinate = best_anchor
	_sync_position()


func _get_anchor_position(terrain: TileMapLayer, anchor: Vector2i) -> Vector2:
	var center := _get_anchor_center_in_terrain(terrain, anchor)
	var parent_node := get_parent() as Node2D
	if parent_node == null:
		return position
	return parent_node.to_local(terrain.to_global(center))


func _get_anchor_center_in_terrain(terrain: TileMapLayer, anchor: Vector2i) -> Vector2:
	var map_origin := terrain.get_used_rect().position
	var total := Vector2.ZERO
	for offset_y in range(2):
		for offset_x in range(2):
			total += terrain.map_to_local(map_origin + anchor + Vector2i(offset_x, offset_y))
	return total / 4.0


func _find_terrain_layer() -> TileMapLayer:
	var level_root := get_parent()
	if level_root == null:
		return null
	while level_root.get_parent():
		for child in level_root.get_children():
			if child is TileMapLayer:
				var lower_name := String(child.name).to_lower()
				if lower_name.contains("terrain") or String(child.name).contains("地块"):
					return child
		level_root = level_root.get_parent()
	return null
