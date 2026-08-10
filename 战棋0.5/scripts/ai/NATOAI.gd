# ==============================================================================
# NATOAI.gd — 北约AI控制器 (Autoload 单例)
# ==============================================================================
# 作用：控制北约AI的决策和行为。实现5种AI倾向：
#       «速胜» — 快速推进，抢占VP格
#       «稳推» — 稳步推进，保持阵型
#       «火力压制» — 盲射覆盖，压制华约阵地
#       «集中突击» — 集火单一目标
#       «混乱» — 随机行动（高EMI下）
#       AI倾向根据关卡回合和EMI强度自动切换。
#       Godot 4.7.1 兼容
# ==============================================================================
extends Node

## === AI行为倾向枚举 ===
enum AIBehavior {
	SPEED_RUSH,      # 速胜：快速抢占VP
	STEADY_PUSH,     # 稳推：稳步推进
	FIRE_SUPPRESSION,# 火力压制：盲射覆盖
	CONCENTRATED,    # 集中突击：集火单目标
	CHAOS            # 混乱：随机行动
}

## === 当前状态 ===
var current_behavior: AIBehavior = AIBehavior.SPEED_RUSH
var nato_units: Array[UnitBase] = []
var known_player_positions: Array[Vector2i] = []
var priority_targets: Array[UnitBase] = []

## === 计时器 ===
var ai_think_time: float = 0.0
const MAX_THINK_TIME: float = 2.0  # AI最多思考2秒


func _ready() -> void:
	print("[NATOAI] 北约AI控制器就绪 — 初始行为: 速胜")


## === 主AI规划 ===
func plan_turn(turn: int) -> void:
	"""每回合AI规划所有单位行动"""
	var level_id = GameManager.current_level_id

	# 更新AI行为倾向
	_update_behavior(turn, level_id)

	# 清除上一回合指令并重新扫描
	nato_units.clear()
	_scan_nato_units()

	# 收集情报（在扫描单位之后）
	_gather_intel()

	print("[NATOAI] 第%d回合 AI规划 — 行为: %s, 可控单位: %d" % [
		turn, AIBehavior.keys()[current_behavior], nato_units.size()])

	# 分配指令
	match current_behavior:
		AIBehavior.SPEED_RUSH:
			_plan_speed_rush(turn)
		AIBehavior.STEADY_PUSH:
			_plan_steady_push(turn)
		AIBehavior.FIRE_SUPPRESSION:
			_plan_fire_suppression(turn)
		AIBehavior.CONCENTRATED:
			_plan_concentrated_assault(turn)
		AIBehavior.CHAOS:
			_plan_chaos(turn)


## === 行为倾向更新 ===
func _update_behavior(turn: int, level_id: int) -> void:
	"""根据关卡和回合更新AI行为倾向"""
	var old = current_behavior

	# 第1-3关: 速胜 → 稳推 → 火力压制
	if level_id <= 2:
		match level_id:
			0: current_behavior = AIBehavior.SPEED_RUSH
			1:
				if turn <= 5:
					current_behavior = AIBehavior.STEADY_PUSH
				else:
					current_behavior = AIBehavior.FIRE_SUPPRESSION
			2:
				if turn <= 3:
					current_behavior = AIBehavior.FIRE_SUPPRESSION
				else:
					current_behavior = AIBehavior.STEADY_PUSH

	# 第4-7关: 稳推/火力压制 → 稳推 → 混乱 → 稳推
	elif level_id <= 6:
		if level_id == 6:  # 第7关 EMI 100%
			if turn <= 5:
				current_behavior = AIBehavior.CHAOS
			else:
				current_behavior = AIBehavior.STEADY_PUSH
		elif EMISystem.current_intensity > 0.7:
			if randf() < 0.4:
				current_behavior = AIBehavior.CHAOS
			else:
				current_behavior = AIBehavior.STEADY_PUSH
		else:
			current_behavior = AIBehavior.FIRE_SUPPRESSION

	# 第8-10关: 稳推/火力压制 → 集中突击 → 速胜/稳推
	else:
		if level_id == 9:  # 第10关
			if turn <= 5 and EMISystem.current_intensity > 0.5:
				current_behavior = AIBehavior.CONCENTRATED
			else:
				current_behavior = AIBehavior.SPEED_RUSH
		elif level_id == 8:  # 第9关
			if turn >= 6:
				current_behavior = AIBehavior.CONCENTRATED
			else:
				current_behavior = AIBehavior.STEADY_PUSH
		else:
			current_behavior = AIBehavior.STEADY_PUSH

	# EMI高时可能切换到混乱
	if EMISystem.current_intensity >= 0.9 and randf() < 0.5:
		current_behavior = AIBehavior.CHAOS

	if old != current_behavior:
		print("[NATOAI] 行为切换: %s → %s" % [AIBehavior.keys()[old], AIBehavior.keys()[current_behavior]])


## === 情报收集 ===
func _gather_intel() -> void:
	"""收集已知玩家位置"""
	known_player_positions.clear()
	priority_targets.clear()
	# 扫描华约单位
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if unit.faction == UnitBase.Faction.WARSAW_PACT and unit.is_alive:
			# 检查是否在AI可视范围内
			for nato in nato_units:
				var dist = GridManager.manhattan_distance(nato.grid_col, nato.grid_row,
					unit.grid_col, unit.grid_row)
				if dist <= nato.vision_range:
					known_player_positions.append(Vector2i(unit.grid_col, unit.grid_row))
					priority_targets.append(unit)
					break


func _scan_nato_units() -> void:
	"""扫描所有北约单位"""
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if unit.faction == UnitBase.Faction.NATO and unit.is_alive:
			nato_units.append(unit)


## === 速胜计划 ===
func _plan_speed_rush(_turn: int) -> void:
	"""速胜：所有单位全速向最近的VP格推进"""
	var vp_cells = GridManager.vp_cells
	if vp_cells.is_empty():
		print("[NATOAI] 无VP格，切换为追击最近敌人")
		_plan_hunt_enemies()
		return

	for unit in nato_units:
		# 找到最近的VP格
		var best_vp = _find_nearest_vp(unit)
		if best_vp == Vector2i(-1, -1):
			continue

		# 计算到VP的路径
		var path = TilePathfinding.find_path(unit.grid_col, unit.grid_row,
			best_vp.x, best_vp.y, unit)

		if path.is_empty():
			# 无法到达，尝试攻击范围内的敌人
			var target = CombatSystem.get_best_target_in_range(unit)
			if not target.is_empty():
				TurnManager.submit_order(unit.unit_id, {
					"type": "attack",
					"target_col": target["col"],
					"target_row": target["row"]
				}, false)
		else:
			TurnManager.submit_order(unit.unit_id, {
				"type": "move",
				"path": path
			}, false)


## === 稳推计划 ===
func _plan_steady_push(_turn: int) -> void:
	"""稳推：保持阵型推进，优先攻击范围内的敌人"""
	for unit in nato_units:
		# 先检查是否可以攻击
		var target = CombatSystem.get_best_target_in_range(unit)
		if not target.is_empty():
			TurnManager.submit_order(unit.unit_id, {
				"type": "attack",
				"target_col": target["col"],
				"target_row": target["row"]
			}, false)
			continue

		# 不能攻击则向最近的VP格移动
		var best_vp = _find_nearest_vp(unit)
		if best_vp != Vector2i(-1, -1):
			var path = TilePathfinding.find_path(unit.grid_col, unit.grid_row,
				best_vp.x, best_vp.y, unit, unit.get_effective_movement() / 2.0)
			if not path.is_empty():
				TurnManager.submit_order(unit.unit_id, {"type": "move", "path": path}, false)
			continue

		# 无VP格 → 追击最近敌人
		var nearest_enemy = _find_nearest_enemy(unit)
		if nearest_enemy:
			var path = TilePathfinding.find_path(unit.grid_col, unit.grid_row,
				nearest_enemy.grid_col, nearest_enemy.grid_row, unit)
			if not path.is_empty():
				TurnManager.submit_order(unit.unit_id, {"type": "move", "path": path}, false)


## === 火力压制计划 ===
func _plan_fire_suppression(turn: int) -> void:
	"""火力压制：对已知玩家位置进行盲射"""
	# 一半单位盲射，一半稳推
	var blind_fire_count = maxi(1, nato_units.size() / 2)
	for i in range(nato_units.size()):
		var unit = nato_units[i]
		if i < blind_fire_count:
			# 盲射已知玩家位置
			if not known_player_positions.is_empty():
				var target_pos = known_player_positions.pick_random()
				TurnManager.submit_order(unit.unit_id, {
					"type": "attack",
					"target_col": target_pos.x,
					"target_row": target_pos.y,
					"attack_type": CombatSystem.AttackType.BLIND_FIRE
				}, false)
			else:
				# 没有已知位置，随机盲射VP附近
				var vp = _find_nearest_vp(unit)
				if vp != Vector2i(-1, -1):
					var spread_col = vp.x + randi() % 5 - 2
					var spread_row = vp.y + randi() % 5 - 2
					TurnManager.submit_order(unit.unit_id, {
						"type": "attack",
						"target_col": clampi(spread_col, 0, GridManager.MAP_WIDTH - 1),
						"target_row": clampi(spread_row, 0, GridManager.MAP_HEIGHT - 1),
						"attack_type": CombatSystem.AttackType.BLIND_FIRE
					}, false)
				else:
					# 无VP无情报 → 追击最近敌人
					var nearest = _find_nearest_enemy(unit)
					if nearest:
						var path = TilePathfinding.find_path(unit.grid_col, unit.grid_row,
							nearest.grid_col, nearest.grid_row, unit)
						if not path.is_empty():
							TurnManager.submit_order(unit.unit_id, {"type": "move", "path": path}, false)
		else:
			_plan_steady_push(turn)


## === 集中突击计划 ===
func _plan_concentrated_assault(_turn: int) -> void:
	"""集中突击：全部集火优先级最高的目标（通常是华约指挥中心或T-72）"""
	var primary_target = _find_primary_target()
	if not primary_target:
		_plan_steady_push(_turn)
		return

	# 所有单位集火同一目标
	for unit in nato_units:
		var dist = GridManager.manhattan_distance(unit.grid_col, unit.grid_row,
			primary_target.grid_col, primary_target.grid_row)
		if dist <= unit.get_effective_range():
			TurnManager.submit_order(unit.unit_id, {
				"type": "attack",
				"target_col": primary_target.grid_col,
				"target_row": primary_target.grid_row
			}, false)
		else:
			# 向目标移动
			var path = TilePathfinding.find_path(unit.grid_col, unit.grid_row,
				primary_target.grid_col, primary_target.grid_row, unit)
			if not path.is_empty():
				TurnManager.submit_order(unit.unit_id, {"type": "move", "path": path}, false)


## === 混乱计划 ===
func _plan_chaos(_turn: int) -> void:
	"""混乱：随机行动（高EMI下）"""
	for unit in nato_units:
		var roll = randf()
		if roll < 0.4:
			# 40%: 随机移动
			var rand_col = clampi(unit.grid_col + randi() % 5 - 2, 0, GridManager.MAP_WIDTH - 1)
			var rand_row = clampi(unit.grid_row + randi() % 5 - 2, 0, GridManager.MAP_HEIGHT - 1)
			var path = TilePathfinding.find_path(unit.grid_col, unit.grid_row,
				rand_col, rand_row, unit, unit.get_effective_movement() / 2.0)
			if not path.is_empty():
				TurnManager.submit_order(unit.unit_id, {"type": "move", "path": path}, false)
		elif roll < 0.7:
			# 30%: 随机攻击未知位置
			var blind_col = clampi(unit.grid_col + randi() % 8 - 4, 0, GridManager.MAP_WIDTH - 1)
			var blind_row = clampi(unit.grid_row + randi() % 8 - 4, 0, GridManager.MAP_HEIGHT - 1)
			TurnManager.submit_order(unit.unit_id, {
				"type": "attack", "target_col": blind_col, "target_row": blind_row,
				"attack_type": CombatSystem.AttackType.BLIND_FIRE
			}, false)
		else:
			# 30%: 原地待命
			TurnManager.submit_order(unit.unit_id, {"type": "hold"}, false)


## === 辅助方法 ===
func _find_nearest_vp(unit: UnitBase) -> Vector2i:
	"""找到离单位最近的VP格"""
	var best = Vector2i(-1, -1)
	var best_dist = 9999
	for vp in GridManager.vp_cells:
		var dist = GridManager.manhattan_distance(unit.grid_col, unit.grid_row, vp.x, vp.y)
		if dist < best_dist:
			best_dist = dist
			best = vp
	return best


func _find_primary_target() -> UnitBase:
	"""找到集中突击的优先目标"""
	# 1. 华约指挥中心
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if unit.faction == UnitBase.Faction.WARSAW_PACT and unit.is_alive:
			if unit.is_command and unit.current_health > 0:
				return unit

	# 2. T-72B坦克（高威胁）
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if unit.faction == UnitBase.Faction.WARSAW_PACT and unit.is_alive:
			if unit.unit_type == UnitBase.UnitType.T72B_TANK:
				return unit

	# 3. 任何可见的华约单位
	if not priority_targets.is_empty():
		return priority_targets[0]

	return null


func _find_nearest_enemy(unit: UnitBase) -> UnitBase:
	"""找到离单位最近的华约单位"""
	var best: UnitBase = null
	var best_dist: int = 9999
	for enemy in Engine.get_main_loop().get_nodes_in_group("units"):
		if enemy.faction == UnitBase.Faction.WARSAW_PACT and enemy.is_alive:
			var dist = GridManager.manhattan_distance(unit.grid_col, unit.grid_row,
				enemy.grid_col, enemy.grid_row)
			if dist < best_dist:
				best_dist = dist
				best = enemy
	return best


func _plan_hunt_enemies() -> void:
	"""无VP格时的兜底计划：所有单位追击最近的华约单位"""
	for unit in nato_units:
		# 先检查射程内是否有可攻击目标
		var target = CombatSystem.get_best_target_in_range(unit)
		if not target.is_empty():
			TurnManager.submit_order(unit.unit_id, {
				"type": "attack",
				"target_col": target["col"],
				"target_row": target["row"]
			}, false)
			continue
		# 否则追击最近敌人
		var nearest = _find_nearest_enemy(unit)
		if nearest:
			var path = TilePathfinding.find_path(unit.grid_col, unit.grid_row,
				nearest.grid_col, nearest.grid_row, unit)
			if not path.is_empty():
				TurnManager.submit_order(unit.unit_id, {"type": "move", "path": path}, false)


## === 情报共享 ===
func share_intel(unit: UnitBase, visible_area: Array[Vector2i]) -> void:
	"""AI单位侦察到的信息"""
	for pos in visible_area:
		if not known_player_positions.has(pos):
			known_player_positions.append(pos)
