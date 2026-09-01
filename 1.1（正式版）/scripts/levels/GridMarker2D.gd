@tool
class_name GridMarker2D
extends Marker2D

## 关卡标记类型。关卡逻辑只读取类型和地图坐标，不读取像素位置。
enum MarkerType {
	WP_SPAWN,
	NATO_SPAWN,
	VICTORY_POINT,
	WP_COMMAND_CENTER,
	NATO_COMMAND_CENTER,
}

@export_category("地图坐标（Grid Coordinate）")
@export var grid_coordinate: Vector2i = Vector2i.ZERO:
	set(value):
		grid_coordinate = value
		_sync_position_deferred()

@export var marker_type: MarkerType = MarkerType.WP_SPAWN


func _ready() -> void:
	_sync_position_deferred()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var terrain := _find_terrain_layer()
	if terrain == null:
		return
	var map_cell := grid_coordinate + terrain.get_used_rect().position
	var expected_global := terrain.to_global(terrain.map_to_local(map_cell))
	if not global_position.is_equal_approx(expected_global):
		global_position = expected_global


func get_player_coordinate() -> String:
	"""地图内部(0,0)显示为玩家坐标(1,1)。"""
	return GridManager.grid_to_player_coordinate(grid_coordinate)


func _sync_position_deferred() -> void:
	if not is_inside_tree():
		return
	call_deferred("_sync_position")


func _sync_position() -> void:
	var terrain := _find_terrain_layer()
	if terrain == null:
		push_warning("%s 找不到同一关卡下的Terrain TileMapLayer" % name)
		return
	var map_cell := grid_coordinate + terrain.get_used_rect().position
	global_position = terrain.to_global(terrain.map_to_local(map_cell))


func _find_terrain_layer() -> TileMapLayer:
	var level_root := get_parent()
	if level_root:
		level_root = level_root.get_parent()
	if level_root == null:
		return null
	for child in level_root.get_children():
		if child is TileMapLayer:
			var lower_name := String(child.name).to_lower()
			if lower_name.contains("terrain") or String(child.name).contains("地块"):
				return child
	return null
