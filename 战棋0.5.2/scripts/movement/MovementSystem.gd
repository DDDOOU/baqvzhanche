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
signal unit_step_animation_requested(unit_id: int, from_col: int, from_row: int,
	to_col: int, to_row: int, duration: float)
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
			print("[MovementSystem] %s 移动中止：目标格不存在 (%d,%d)" % [unit.unit_name, col, row])
			break
		if not cell.is_passable_for(is_armored, unit):
			result["blocked"] = true
			print("[MovementSystem] %s 移动中止：地块不可通行 (%d,%d)" % [unit.unit_name, col, row])
			break
		# 格子已被其他单位占据 → 停下，绝不重叠
		if cell.occupant_unit and cell.occupant_unit != unit:
			result["blocked"] = true
			print("[MovementSystem] %s 移动中止：%s 占据 (%d,%d)" % [
				unit.unit_name, cell.occupant_unit.unit_name, col, row])
			break
		var move_cost: float = cell.get_move_cost()
		var height_diff := GridManager.get_height_difference(
			unit.grid_col, unit.grid_row, col, row)
		if height_diff > 0:
			move_cost += float(height_diff)
		if remaining_mp < move_cost:
			result["blocked"] = true
			print("[MovementSystem] %s 移动中止：移动点不足，需要%.1f，剩余%.1f" % [
				unit.unit_name, move_cost, remaining_mp])
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
				# 修复: 触雷后无论死活都停止移动（原仅死亡分支 break, 幸存者继续走完与战报矛盾）
				remaining_mp = 0.0
				if not unit.is_alive:
					CombatSystem.unit_destroyed.emit(unit.unit_id, -1)
				# 修复批B: 触雷分支统一 break — 幸存者不再落入下方常规移动
				# 重复执行 set_grid_position/unit_step/steps_completed（同格二次处理）
				break

		var prev_col: int = unit.grid_col
		var prev_row: int = unit.grid_row
		if GameManager.current_state == GameManager.GameState.EXECUTION_PHASE:
			# UnitRenderer 是自绘节点，必须单独接收格子间的视觉插值请求。
			unit_step_animation_requested.emit(
				unit_id, prev_col, prev_row, col, row, BASE_MOVE_SPEED)
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
	# 逻辑位置已经更新；实际图标动画由 UnitRenderer 响应
	# unit_step_animation_requested 完成。这里保留等待，维持逐格演绎节奏。
	await unit.get_tree().create_timer(BASE_MOVE_SPEED).timeout


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
