# ==============================================================================
# GridManager.gd — 四边形网格坐标系统 (Autoload 单例)
# ==============================================================================
# 作用：管理40×45正方形网格地图，坐标(col,row)→世界坐标(x,y)。
#       含地形属性、邻居查询、距离计算、通行性判定。
# Godot 4.7.1 兼容
# ==============================================================================
extends Node

## === 地图常量 ===
var MAP_WIDTH: int = 40
var MAP_HEIGHT: int = 45
const TILE_SIZE: float = 64.0     # 正方形边长（像素）
## === 等距2.5D显示参数 ===
const ISO_TILE_WIDTH: float = 64.0
const ISO_TILE_HEIGHT: float = 32.0
const ISO_SPRITE_SIZE: float = 64.0

## === 地形类型 ===
enum TerrainType {
	PLAINS, MOUNTAIN, FOREST, RIVER, ROAD, RAILWAY, BRIDGE, MARSH, CITY
}

## === 地形属性 ===
const TERRAIN_PROPERTIES: Dictionary = {
	TerrainType.PLAINS:   {"move_cost": 1.0, "defense": 0.0,  "height": 0, "concealment": 0.0, "name": "平原"},
	TerrainType.CITY:     {"move_cost": 1.0, "defense": 0.5,  "height": 1, "concealment": 0.3, "name": "城市"},
	TerrainType.MOUNTAIN: {"move_cost": 3.0, "defense": 0.3,  "height": 3, "concealment": 0.2, "name": "山地"},
	TerrainType.FOREST:   {"move_cost": 2.0, "defense": 0.2,  "height": 0, "concealment": 0.5, "name": "密林"},
	TerrainType.RIVER:    {"move_cost": 4.0, "defense": 0.0,  "height": -1, "concealment": 0.0, "name": "河流"},
	TerrainType.ROAD:     {"move_cost": 0.5, "defense": 0.0,  "height": 0, "concealment": 0.0, "name": "公路"},
	TerrainType.RAILWAY:  {"move_cost": 0.5, "defense": 0.0,  "height": 0, "concealment": 0.0, "name": "铁路"},
	TerrainType.BRIDGE:   {"move_cost": 0.5, "defense": 0.0,  "height": 1, "concealment": 0.0, "name": "桥梁"},
	TerrainType.MARSH:    {"move_cost": 3.0, "defense": 0.0,  "height": -1, "concealment": 0.1, "name": "沼泽"},
}

## === 特殊标记 ===
enum CellMarker { NONE, VP_POINT, WP_SPAWN, NATO_SPAWN, UNKNOWN_CONTACT }

## === 网格单元 ===
class TileCell:
	var col: int = 0
	var row: int = 0
	var terrain: int = TerrainType.PLAINS
	var height: int = 0
	var marker: int = CellMarker.NONE
	var is_visible: bool = true
	var is_explored: bool = false
	var control_faction: int = 0
	var occupant_unit = null
	var is_destroyed: bool = false   # 桥梁被炸毁
	var terrain_name: String = "plains"
	var custom_move_cost: float = -1.0
	var custom_passable: int = -1
	var custom_concealment: float = -1.0

	func get_effective_height() -> int:
		return height + TERRAIN_PROPERTIES[terrain]["height"]

	func get_move_cost() -> float:
		if custom_move_cost >= 0.0:
			return custom_move_cost
		return TERRAIN_PROPERTIES[terrain]["move_cost"]

	func get_defense_bonus() -> float:
		return TERRAIN_PROPERTIES[terrain]["defense"]

	func get_concealment() -> float:
		if custom_concealment >= 0.0:
			return custom_concealment
		return TERRAIN_PROPERTIES[terrain]["concealment"]

	func is_passable_for(is_armored: bool) -> bool:
		if is_destroyed:
			return false
		if custom_passable >= 0:
			return custom_passable == 1
		if terrain == TerrainType.RIVER and is_armored:
			return false
		if terrain == TerrainType.MOUNTAIN and is_armored:
			return false
		return true


## === 主数据 ===
var grid: Array = []              # grid[row][col] → TileCell
var vp_cells: Array = []
var spawn_wp: Array = []
var spawn_nato: Array = []

## === 4向邻居偏移 ===
const FOUR_DIRS: Array = [
	Vector2i(0, -1),   # 上
	Vector2i(1, 0),    # 右
	Vector2i(0, 1),    # 下
	Vector2i(-1, 0),   # 左
]


## ==================== 初始化 ====================

func initialize_map(map_data: Dictionary = {}, map_width: int = MAP_WIDTH,
		map_height: int = MAP_HEIGHT) -> void:
	MAP_WIDTH = maxi(1, map_width)
	MAP_HEIGHT = maxi(1, map_height)
	grid.clear()
	vp_cells.clear()
	spawn_wp.clear()
	spawn_nato.clear()

	for row in range(MAP_HEIGHT):
		var row_arr: Array = []
		for col in range(MAP_WIDTH):
			var cell = TileCell.new()
			cell.col = col
			cell.row = row
			row_arr.append(cell)
		grid.append(row_arr)

	if not map_data.is_empty():
		_apply_map_data(map_data)
	print("[GridManager] 四边形地图初始化: %d×%d" % [MAP_WIDTH, MAP_HEIGHT])


func _apply_map_data(data: Dictionary) -> void:
	for cell_data in data.get("terrain", []):
		var cell = get_cell(cell_data.col, cell_data.row)
		if cell:
			cell.terrain = cell_data.terrain
			cell.height = cell_data.get("height", 0)
			cell.marker = cell_data.get("marker", CellMarker.NONE)
			cell.terrain_name = cell_data.get("terrain_name", "plains")
			cell.custom_move_cost = cell_data.get("move_cost", -1.0)
			if cell_data.has("passable"):
				cell.custom_passable = 1 if cell_data["passable"] else 0
			cell.custom_concealment = cell_data.get("concealment", -1.0)
			cell.is_visible = true
			cell.is_explored = true
			# 根据 marker 填充特殊格数组
			match cell.marker:
				CellMarker.VP_POINT:
					vp_cells.append(Vector2i(cell.col, cell.row))
				CellMarker.WP_SPAWN:
					spawn_wp.append(Vector2i(cell.col, cell.row))
				CellMarker.NATO_SPAWN:
					spawn_nato.append(Vector2i(cell.col, cell.row))


## ==================== 坐标转换 ====================

static func grid_to_world(col: int, row: int, tile_size: float = 64.0) -> Vector2:
	"""格坐标→世界坐标(格子中心)"""
	return Vector2(col * tile_size + tile_size / 2.0, row * tile_size + tile_size / 2.0)


static func world_to_grid(world_pos: Vector2, tile_size: float = 64.0) -> Vector2i:
	"""世界坐标→格坐标"""
	return Vector2i(int(world_pos.x / tile_size), int(world_pos.y / tile_size))


## ==================== 格子访问 ====================

func get_cell(col: int, row: int) -> TileCell:
	if not is_valid_cell(col, row):
		return null
	return grid[row][col]


func is_valid_cell(col: int, row: int) -> bool:
	return col >= 0 and col < MAP_WIDTH and row >= 0 and row < MAP_HEIGHT


## ==================== 邻居查询 ====================

func get_neighbors(col: int, row: int) -> Array:
	var result: Array = []
	for d in FOUR_DIRS:
		var nc = col + d.x
		var nr = row + d.y
		if is_valid_cell(nc, nr):
			result.append(Vector2i(nc, nr))
	return result


## ==================== 距离计算 ====================

func manhattan_distance(col1: int, row1: int, col2: int, row2: int) -> int:
	"""曼哈顿距离（4向移动）"""
	return abs(col1 - col2) + abs(row1 - row2)


## ==================== 范围查询 ====================

func get_cells_in_range(center_col: int, center_row: int, range_val: int) -> Array:
	"""获取曼哈顿距离 ≤ range_val 的所有格"""
	var result: Array = []
	for col in range(MAP_WIDTH):
		for row in range(MAP_HEIGHT):
			if manhattan_distance(center_col, center_row, col, row) <= range_val:
				result.append(Vector2i(col, row))
	return result


## ==================== 高低差 ====================

func get_height_difference(col1: int, row1: int, col2: int, row2: int) -> int:
	var c1 = get_cell(col1, row1)
	var c2 = get_cell(col2, row2)
	if not c1 or not c2:
		return 0
	return c2.get_effective_height() - c1.get_effective_height()
## ==================== 等距坐标转换 ====================

static func grid_to_iso(col: int, row: int) -> Vector2:
	"""地图坐标转等距屏幕坐标"""
	return Vector2(
		(col - row) * ISO_TILE_WIDTH * 0.5,
		(col + row) * ISO_TILE_HEIGHT * 0.5
	)


func get_iso_map_origin() -> Vector2:
	"""等距地图本地原点；地图、单位和点击检测必须共用此值"""
	return Vector2(MAP_HEIGHT * ISO_TILE_WIDTH * 0.5, 40.0)


static func grid_to_player_coordinate(grid_position: Vector2i) -> String:
	"""内部0基准地图坐标转玩家1基准纯数字坐标，例如(5,6)→(6,7)。"""
	return "(%d,%d)" % [grid_position.x + 1, grid_position.y + 1]


static func iso_to_grid(local_pos: Vector2) -> Vector2i:
	"""等距屏幕坐标转地图坐标"""
	var col_value := (
		local_pos.x / ISO_TILE_WIDTH +
		local_pos.y / ISO_TILE_HEIGHT
	)

	var row_value := (
		local_pos.y / ISO_TILE_HEIGHT -
		local_pos.x / ISO_TILE_WIDTH
	)

	return Vector2i(
		roundi(col_value),
		roundi(row_value)
	)
