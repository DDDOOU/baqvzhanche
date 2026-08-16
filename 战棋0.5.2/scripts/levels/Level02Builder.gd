extends Node2D

const MAP_SIZE := Vector2i(20, 12)
const SOURCE_ID := 5
const TILE_GRASS := Vector2i(1, 2)
const TILE_SOIL := Vector2i(0, 0)
const TILE_ROAD := Vector2i(2, 1)
const TILE_BRUSH := Vector2i(0, 4)
const TILE_FOREST := Vector2i(9, 2)
const TILE_WATER := Vector2i(0, 10)

@onready var terrain: TileMapLayer = $"Terrain（地块）"


func _ready() -> void:
	_build_railway_battlefield()
	# 场景中的建筑以逻辑格保存；地形生成后再同步其等距坐标。
	for building in find_children("*", "Building2D", true, false):
		building.call("_sync_position")


func _build_railway_battlefield() -> void:
	for row in range(MAP_SIZE.y):
		for col in range(MAP_SIZE.x):
			var atlas := TILE_GRASS
			# 东西向铁路与军用道路。
			if row == 4 or row == 6:
				atlas = TILE_ROAD
			elif (col + row * 3) % 11 == 0:
				atlas = TILE_SOIL
			elif row in [0, 1, 10, 11] and (col + row) % 3 == 0:
				atlas = TILE_FOREST
			elif (col * 2 + row) % 13 == 0:
				atlas = TILE_BRUSH

			# 南北向河道；三个VP正好是铁路桥、车站渡口和桥头堡。
			if col == 9 and row not in [4, 6, 8]:
				atlas = TILE_WATER
			elif col == 9 and row in [4, 6, 8]:
				atlas = TILE_ROAD
			terrain.set_cell(Vector2i(col, row), SOURCE_ID, atlas, 0)
