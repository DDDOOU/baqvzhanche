# ==============================================================================
# LineOfSight.gd — 四边形网格视线计算 (Autoload 单例)
# ==============================================================================
extends Node

enum BlockType { NONE, TERRAIN, FOREST, HEIGHT, SMOKE }

class LOSResult extends RefCounted:
	var has_los: bool
	var block_type: int

	func _init() -> void:
		has_los = true
		block_type = BlockType.NONE


func _ready() -> void:
	print("[LineOfSight] 四边形视线系统就绪")


func has_line_of_sight(from_col: int, from_row: int, to_col: int, to_row: int,
		ignore_smoke: bool = false) -> bool:
	return check_los(from_col, from_row, to_col, to_row, ignore_smoke).has_los


func check_los(from_col: int, from_row: int, to_col: int, to_row: int,
		ignore_smoke: bool = false) -> LOSResult:
	if from_col == to_col and from_row == to_row:
		return LOSResult.new()

	var from_cell = GridManager.get_cell(from_col, from_row)
	var to_cell = GridManager.get_cell(to_col, to_row)
	if not from_cell or not to_cell:
		var r2 = LOSResult.new()
		r2.has_los = false
		return r2

	var line = _bresenham_line(from_col, from_row, to_col, to_row)
	for i in range(1, line.size() - 1):
		var p: Vector2i = line[i]
		var cell = GridManager.get_cell(p.x, p.y)
		if not cell:
			continue
		if cell.terrain == GridManager.TerrainType.MOUNTAIN:
			return _block(BlockType.TERRAIN)
		if cell.terrain == GridManager.TerrainType.CITY and i > 1:
			return _block(BlockType.TERRAIN)
		var fh = from_cell.get_effective_height()
		var th = to_cell.get_effective_height()
		var mh = cell.get_effective_height()
		if mh > fh and mh > th:
			return _block(BlockType.HEIGHT)
		if not ignore_smoke and CombatSystem.smoke_cells.has("%d,%d" % [p.x, p.y]):
			return _block(BlockType.SMOKE)

	return LOSResult.new()


func _block(t: int) -> LOSResult:
	var r = LOSResult.new()
	r.has_los = false
	r.block_type = t
	return r


func _bresenham_line(x0: int, y0: int, x1: int, y1: int) -> Array:
	var points: Array = []
	var dx = abs(x1 - x0)
	var dy = abs(y1 - y0)
	var sx = 1 if x0 < x1 else -1
	var sy = 1 if y0 < y1 else -1
	var err = dx - dy
	var x = x0
	var y = y0
	while true:
		points.append(Vector2i(x, y))
		if x == x1 and y == y1:
			break
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
	return points


func get_visible_cells(unit: UnitBase, ignore_emi: bool = false) -> Array:
	var base_range = unit.vision_range + unit.recon_bonus
	if not ignore_emi:
		base_range = EMISystem.apply_recon_range_modifier(base_range)
	var visible: Array = []
	var candidates = GridManager.get_cells_in_range(unit.grid_col, unit.grid_row, base_range)
	for p in candidates:
		if check_los(unit.grid_col, unit.grid_row, p.x, p.y).has_los:
			visible.append(p)
	return visible
