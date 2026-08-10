extends Node2D

enum MapTheme { URBAN, FOREST, DEFENSIVE, RIVER, BLACKOUT, SNOW, RAIL, FINAL }

const SOURCE_ID := 5
const TILE_GRASS := Vector2i(1, 2)
const TILE_SOIL := Vector2i(0, 0)
const TILE_ROAD := Vector2i(2, 1)
const TILE_BRUSH := Vector2i(0, 4)
const TILE_ROCK := Vector2i(0, 5)
const TILE_FOREST := Vector2i(9, 2)
const TILE_WATER := Vector2i(0, 10)

@export var map_size := Vector2i(20, 12)
@export var map_theme: MapTheme = MapTheme.DEFENSIVE
@export var variant_seed: int = 1987
@export var river_column: int = -1
@export var bridge_rows: Array[int] = []
@export var road_rows: Array[int] = [6]

@onready var terrain: TileMapLayer = $"Terrain（地块）"


func _ready() -> void:
	_build_map()


func _build_map() -> void:
	for row in range(map_size.y):
		for col in range(map_size.x):
			terrain.set_cell(Vector2i(col, row), SOURCE_ID, _choose_tile(col, row), 0)


func _choose_tile(col: int, row: int) -> Vector2i:
	if river_column >= 0 and col == river_column:
		return TILE_ROAD if row in bridge_rows else TILE_WATER
	if row in road_rows:
		return TILE_ROAD

	var noise := posmod(col * 17 + row * 31 + variant_seed, 29)
	match map_theme:
		MapTheme.URBAN:
			if col % 5 == 0 or row % 5 == 0:
				return TILE_ROAD
			return TILE_SOIL if noise < 11 else TILE_GRASS
		MapTheme.FOREST:
			return TILE_FOREST if noise < 15 else (TILE_BRUSH if noise < 21 else TILE_GRASS)
		MapTheme.DEFENSIVE:
			return TILE_BRUSH if noise < 6 else (TILE_SOIL if noise < 11 else TILE_GRASS)
		MapTheme.RIVER:
			return TILE_BRUSH if noise < 7 else TILE_GRASS
		MapTheme.BLACKOUT:
			return TILE_FOREST if noise < 9 else (TILE_ROCK if noise < 13 else TILE_SOIL)
		MapTheme.SNOW:
			# 当前素材库尚无雪地瓦片，以浅色岩地/土路作为可替换占位。
			return TILE_ROCK if noise < 8 else (TILE_SOIL if noise < 18 else TILE_GRASS)
		MapTheme.RAIL:
			if row in [4, 8]:
				return TILE_ROAD
			return TILE_SOIL if noise < 9 else TILE_GRASS
		MapTheme.FINAL:
			return TILE_ROCK if noise < 10 else (TILE_SOIL if noise < 22 else TILE_BRUSH)
	return TILE_GRASS
