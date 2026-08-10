# ==============================================================================
# TilePathfinding.gd — 四边形A*寻路算法
# ==============================================================================
# 在40×45四边形网格上用A*计算最短路径。
# 考虑地形消耗、高度差、装甲通行限制。
# Godot 4.7.1 兼容
# ==============================================================================
class_name TilePathfinding
extends RefCounted

class PathNode extends RefCounted:
	var col: int
	var row: int
	var g_cost: float
	var h_cost: float
	var parent: PathNode

	func f_cost() -> float:
		return g_cost + h_cost


## ==================== A* 寻路 ====================

static func find_path(from_col: int, from_row: int, to_col: int, to_row: int,
		unit: UnitBase = null, max_cost: float = 9999.0) -> Array:
	"""返回最短路径，不含起点"""
	if from_col == to_col and from_row == to_row:
		return []

	var end_cell = GridManager.get_cell(to_col, to_row)
	if not end_cell:
		return []

	var is_armored = _is_armored(unit)
	if not end_cell.is_passable_for(is_armored):
		return []

	var open_list: Array = []
	var closed: Dictionary = {}

	var start = PathNode.new()
	start.col = from_col
	start.row = from_row
	start.h_cost = _heuristic(from_col, from_row, to_col, to_row)
	open_list.append(start)

	while not open_list.is_empty():
		# 找 f_cost 最小的节点
		var idx = 0
		var lowest = open_list[0].f_cost()
		for i in range(1, open_list.size()):
			var f = open_list[i].f_cost()
			if f < lowest:
				lowest = f
				idx = i

		var cur: PathNode = open_list[idx]

		# 到达终点
		if cur.col == to_col and cur.row == to_row:
			return _rebuild(cur)

		open_list.remove_at(idx)
		closed["%d,%d" % [cur.col, cur.row]] = true

		# 遍历4向邻居
		for nb in GridManager.get_neighbors(cur.col, cur.row):
			var nc = nb.x
			var nr = nb.y
			var key = "%d,%d" % [nc, nr]
			if closed.has(key):
				continue

			var cell = GridManager.get_cell(nc, nr)
			if not cell or not cell.is_passable_for(is_armored):
				continue
			if cell.occupant_unit and unit and cell.occupant_unit.faction != unit.faction:
				continue

			var cost = cell.get_move_cost()
			var hdiff = GridManager.get_height_difference(cur.col, cur.row, nc, nr)
			if hdiff > 0:
				cost += hdiff * 1.0

			var tg = cur.g_cost + cost
			if tg > max_cost:
				continue

			var existing: PathNode = null
			for n in open_list:
				if n.col == nc and n.row == nr:
					existing = n
					break

			if existing:
				if tg < existing.g_cost:
					existing.g_cost = tg
					existing.parent = cur
			else:
				var nn = PathNode.new()
				nn.col = nc
				nn.row = nr
				nn.g_cost = tg
				nn.h_cost = _heuristic(nc, nr, to_col, to_row)
				nn.parent = cur
				open_list.append(nn)

	return []


## ==================== 可移动范围（Dijkstra扩散） ====================

static func get_reachable_cells(unit: UnitBase) -> Array:
	var limit = unit.get_effective_movement()
	var result: Array = []
	var cost_map: Dictionary = {}

	var sc = unit.grid_col
	var sr = unit.grid_row
	cost_map["%d,%d" % [sc, sr]] = 0.0

	var frontier: Array = [Vector2i(sc, sr)]
	var is_armored = _is_armored(unit)

	while not frontier.is_empty():
		var cur = frontier.pop_front()
		var ck = "%d,%d" % [cur.x, cur.y]
		var cc = cost_map.get(ck, 0.0)

		for nb in GridManager.get_neighbors(cur.x, cur.y):
			var nc = nb.x
			var nr = nb.y
			var key = "%d,%d" % [nc, nr]

			var cell = GridManager.get_cell(nc, nr)
			if not cell or not cell.is_passable_for(is_armored):
				continue

			# 是否被其他单位占据（己方可穿过但不停留，敌方完全阻挡扩散）
			var occ = cell.occupant_unit
			var blocked_by_unit = occ != null and occ != unit
			if blocked_by_unit and occ.faction != unit.faction:
				continue  # 敌方占用：不可通过

			var cost = cell.get_move_cost()
			var hdiff = GridManager.get_height_difference(cur.x, cur.y, nc, nr)
			if hdiff > 0:
				cost += hdiff * 1.0

			var nc_cost = cc + cost
			if nc_cost > limit:
				continue

			if not cost_map.has(key) or nc_cost < cost_map[key]:
				cost_map[key] = nc_cost
				frontier.append(Vector2i(nc, nr))
				# 只有空格（或自身所在格）才显示为可达停留格
				if not blocked_by_unit and not result.has(Vector2i(nc, nr)):
					result.append(Vector2i(nc, nr))

	return result


## ==================== 辅助 ====================

static func _heuristic(c1: int, r1: int, c2: int, r2: int) -> float:
	return float(GridManager.manhattan_distance(c1, r1, c2, r2))


static func _rebuild(end_node: PathNode) -> Array:
	var path: Array = []
	var cur = end_node
	while cur and cur.parent:
		path.push_front(Vector2i(cur.col, cur.row))
		cur = cur.parent
	return path


static func _is_armored(unit: UnitBase = null) -> bool:
	if not unit:
		return false
	return unit.unit_type in [
		UnitBase.UnitType.T72B_TANK, UnitBase.UnitType.BMP2_IFV,
		UnitBase.UnitType.M1A1_TANK, UnitBase.UnitType.M2_IFV,
		UnitBase.UnitType.BRDM2_RECON, UnitBase.UnitType.ZSU23_AA,
		UnitBase.UnitType.GVOZDIKA_ARTILLERY, UnitBase.UnitType.M901_ITV,
		UnitBase.UnitType.M109_ARTILLERY, UnitBase.UnitType.M113_APC
	]


static func is_armored(unit: UnitBase = null) -> bool:
	"""公开的装甲单位类型判断，供移动与路径验证复用。"""
	return _is_armored(unit)
