# ==============================================================================
# MovementSystem.gd — 移动执行系统 (Autoload 单例)
# ==============================================================================
# 逐格执行移动路径、扣除移动点数、触雷/辙印检测。
# Godot 4.7.1 兼容
# ==============================================================================
extends Node

signal unit_move_started(unit_id: int, path: Array)
signal unit_move_completed(unit_id: int, final_col: int, final_row: int)
signal unit_step(unit_id: int, col: int, row: int)
signal mine_triggered(unit_id: int, col: int, row: int)
signal mine_cleared(unit_id: int, col: int, row: int)

const BASE_MOVE_SPEED: float = 0.3


func _ready() -> void:
	print("[MovementSystem] 移动系统就绪")


func execute_move(unit_id: int, path: Array) -> Dictionary:
	var result = {"success": false, "final_col": 0, "final_row": 0,
		"steps_completed": 0, "mines_hit": false, "blocked": false}

	var unit = _get_unit_by_id(unit_id)
	if not unit or not unit.is_alive:
		return result
	if path.is_empty():
		result["final_col"] = unit.grid_col
		result["final_row"] = unit.grid_row
		return result

	unit_move_started.emit(unit_id, path)

	var remaining_mp: float = float(unit.remaining_movement)
	var is_armored = TilePathfinding.is_armored(unit)

	for i in range(path.size()):
		var step = path[i]
		var col: int = step.x
		var row: int = step.y

		var cell = GridManager.get_cell(col, row)
		if not cell:
			result["blocked"] = true
			break
		# 格子已被其他单位占据 → 停下，绝不重叠
		if cell.occupant_unit and cell.occupant_unit != unit:
			result["blocked"] = true
			break
		var move_cost = cell.get_move_cost()
		if remaining_mp < move_cost:
			result["blocked"] = true
			break

		remaining_mp -= move_cost

		if _check_mines(col, row):
			var mine_pos := Vector2i(col, row)
			mine_cells.erase(mine_pos)
			if unit.can_clear_mines:
				mine_cleared.emit(unit_id, col, row)
				BattleLog.add_log("[工兵] %s 安全排除 (%d,%d) 雷区" % [unit.unit_name, col + 1, row + 1], Color(0.55, 0.9, 0.55))
			else:
				result["mines_hit"] = true
				unit.set_grid_position(col, row)
				result["steps_completed"] += 1
				result["final_col"] = col
				result["final_row"] = row
				mine_triggered.emit(unit_id, col, row)
				unit.take_damage(unit.max_health * 0.30, -1)
				BattleLog.add_log("[触雷] %s 损失30%%生命并停止移动" % unit.unit_name, Color(1.0, 0.35, 0.25))
				if not unit.is_alive:
					CombatSystem.unit_destroyed.emit(unit.unit_id, -1)
				remaining_mp = 0.0
				break

		var prev_col: int = unit.grid_col
		var prev_row: int = unit.grid_row
		unit.set_grid_position(col, row)
		# 移动后更新朝向（面向箭头与侧后装甲判定共用）
		if col != prev_col or row != prev_row:
			unit.facing_angle = atan2(float(row - prev_row), float(col - prev_col))
		unit_step.emit(unit_id, col, row)
		result["steps_completed"] += 1
		result["final_col"] = col
		result["final_row"] = row

		if GameManager.current_state == GameManager.GameState.EXECUTION_PHASE:
			await _animate_step(unit, col, row)

	unit.remaining_movement = int(remaining_mp)
	result["success"] = true
	unit_move_completed.emit(unit_id, result["final_col"], result["final_row"])
	_check_trail_exposure(unit)
	return result


func _animate_step(unit: UnitBase, col: int, row: int) -> void:
	var target = GridManager.grid_to_world(col, row)
	var tween = unit.create_tween()
	tween.tween_property(unit, "position", target, BASE_MOVE_SPEED)
	await unit.get_tree().create_timer(BASE_MOVE_SPEED).timeout


func validate_path(unit_id: int, path: Array) -> bool:
	var unit = _get_unit_by_id(unit_id)
	if not unit:
		return false
	if path.is_empty():
		return true

	var cc = unit.grid_col
	var cr = unit.grid_row
	var total = 0.0
	var is_armored = TilePathfinding.is_armored(unit)

	for step in path:
		var dist = GridManager.manhattan_distance(cc, cr, step.x, step.y)
		if dist != 1:
			return false
		var cell = GridManager.get_cell(step.x, step.y)
		if not cell or not cell.is_passable_for(is_armored):
			return false
		total += cell.get_move_cost()
		cc = step.x
		cr = step.y

	return total <= unit.get_effective_movement()


## ==================== 雷区 ====================

var mine_cells: Array = []


func serialize() -> Dictionary:
	return {"mines": mine_cells.map(func(p): return [p.x, p.y])}


func deserialize(data: Dictionary) -> void:
	mine_cells.clear()
	for m in data.get("mines", []):
		mine_cells.append(Vector2i(m[0], m[1]))


func reset_for_level() -> void:
	mine_cells.clear()

func lay_mines(col: int, row: int) -> void:
	var pos := Vector2i(col, row)
	if pos not in mine_cells:
		mine_cells.append(pos)


func _check_mines(col: int, row: int) -> bool:
	for m in mine_cells:
		if m.x == col and m.y == row:
			return true
	return false


## ==================== 辙印暴露 ====================

func _check_trail_exposure(unit: UnitBase) -> void:
	var cell = GridManager.get_cell(unit.grid_col, unit.grid_row)
	if cell and cell.terrain in [GridManager.TerrainType.PLAINS]:
		if EMISystem.current_intensity < 0.5:
			unit.is_hidden = false


## ==================== 工具 ====================

func _get_unit_by_id(unit_id: int) -> UnitBase:
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if unit.unit_id == unit_id:
			return unit
	return null


func execute_all_moves(orders: Dictionary) -> void:
	var sorted = orders.keys()
	sorted.sort_custom(func(a, b):
		var ua = _get_unit_by_id(a)
		var ub = _get_unit_by_id(b)
		return (ua.move_speed if ua else 1.0) > (ub.move_speed if ub else 1.0))
	for uid in sorted:
		var order = orders[uid]
		if order.get("type") == "move":
			execute_move(uid, order.get("path", []))
