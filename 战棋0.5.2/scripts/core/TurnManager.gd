# ==============================================================================
# TurnManager.gd — 回合制管理系统 (Autoload 单例)
# ==============================================================================
# 作用：管理「60秒计划 + 30秒沙盘」的回合循环。双方同时规划，
#       演绎阶段按敌我统一先手队列逐个完成移动/攻击，并触发回合事件。
# Godot 4.7.1 兼容
# ==============================================================================
extends Node

## === 信号 ===
signal planning_phase_started(turn: int)
signal execution_phase_started(turn: int)
signal execution_actions_completed(turn: int)
signal turn_resolved(turn: int)
signal round_event_triggered(event_id: String, data: Dictionary)
signal order_submitted(unit_id: int, order: Dictionary)
signal unit_action_started(unit_id: int, order_index: int, total_units: int)
signal unit_action_completed(unit_id: int, order_index: int, total_units: int)

## === 当前状态 ===
var current_turn: int = 1
var is_planning: bool = false
var is_executing: bool = false
var execution_actions_finished: bool = false

## === 指令存储 ===
# 每个回合，双方指令存储在字典中
# orders[unit_id] = {type, target_col, target_row, card_used, ...}
var player_orders: Dictionary = {}    # 华约（玩家）指令
var ai_orders: Dictionary = {}        # 北约（AI）指令
var orders_locked: bool = false

## === 事件系统 ===
var turn_events: Dictionary = {}  # turn_number → Array[event_data]
var processed_events: Array[String] = []

## === 回合限制 ===
var max_turns: int = 15  # 默认最大回合数，由关卡覆盖


func _ready() -> void:
	print("[TurnManager] 回合管理系统就绪")


func reset_for_level(level_max_turns: int) -> void:
	"""开始或重开关卡时清除所有上一局的临时状态。"""
	current_turn = 1
	max_turns = maxi(1, level_max_turns)
	is_planning = false
	is_executing = false
	execution_actions_finished = false
	orders_locked = false
	player_orders.clear()
	ai_orders.clear()
	turn_events.clear()
	processed_events.clear()
	print("[TurnManager] 关卡状态已重置，最大回合=%d" % max_turns)


## === 计划阶段 ===
func start_planning_phase() -> void:
	is_planning = true
	is_executing = false
	execution_actions_finished = false
	orders_locked = false
	player_orders.clear()
	ai_orders.clear()
	_reset_unit_movement()

	print("[TurnManager] === 第 %d 回合 计划阶段开始 ===" % current_turn)
	planning_phase_started.emit(current_turn)

	# 回合开始：手牌多弃少补到7张
	CardSystem.adjust_hand_to(CardSystem.STARTING_HAND_SIZE)

	# 修复批B: 每回合补充指挥点（不结转, 用不完作废）
	CardSystem.command_points = CardSystem.MAX_COMMAND_POINTS
	CardSystem.command_points_changed.emit(CardSystem.command_points, CardSystem.MAX_COMMAND_POINTS)

	# AI 开始规划（异步，不阻塞玩家）
	NATOAI.plan_turn(current_turn)

	# 触发本回合开始事件
	_trigger_turn_events("turn_start")


func _reset_unit_movement() -> void:
	"""每个计划阶段统一恢复单位移动点，避免依赖特定场景的 UI 信号回调。"""
	for node in Engine.get_main_loop().get_nodes_in_group("units"):
		if node is UnitBase and node.is_alive:
			node.reset_movement_for_turn()


func lock_all_orders() -> void:
	"""计划时间到，锁定所有指令"""
	orders_locked = true
	# 计划阶段结束：手牌超过6张则自动弃到6张
	CardSystem.trim_hand_to(CardSystem.MAX_HAND_SIZE)
	print("[TurnManager] 所有指令已锁定，手牌已调整至≤%d张" % CardSystem.MAX_HAND_SIZE)


func submit_order(unit_id: int, order: Dictionary, is_player: bool = true) -> bool:
	"""提交一个单位的指令"""
	if orders_locked:
		print("[TurnManager] 指令已锁定，无法提交")
		return false

	# 无线电静默期间己方无法使用任何指令（卡牌代价, 修复批B: 描述实现）
	if is_player and CardSystem.radio_silence_active:
		print("[TurnManager] 无线电静默中，己方无法下达指令")
		return false

	# 命令必须拥有独立数据。UI随后会清理待确认路径，如果保存同一个Array引用，
	# 玩家订单的path会被一起清空；AI不经过UI清理，所以此前只有敌军能移动。
	var stored_order := order.duplicate(true)
	if is_player:
		player_orders[unit_id] = stored_order
	else:
		ai_orders[unit_id] = stored_order

	order_submitted.emit(unit_id, stored_order)
	return true


func remove_order(unit_id: int, is_player: bool = true) -> void:
	if is_player:
		player_orders.erase(unit_id)
	else:
		ai_orders.erase(unit_id)


## === 沙盘演绎 ===
func start_execution_phase() -> void:
	is_planning = false
	is_executing = true
	execution_actions_finished = false

	print("[TurnManager] === 第 %d 回合 沙盘演绎开始 ===" % current_turn)
	execution_phase_started.emit(current_turn)

	# 恐慌判定（修复: 溃逃机制原未接入战斗）— 动摇/崩溃单位掷骰, 溃逃则本回合命令作废
	var flee_units: Array[int] = []
	for uid in player_orders.keys():
		if MoraleSystem.check_flee(uid):
			flee_units.append(uid)
	for uid in ai_orders.keys():
		if MoraleSystem.check_flee(uid):
			flee_units.append(uid)
	for uid in flee_units:
		player_orders.erase(uid)
		ai_orders.erase(uid)
		if BattleLog:
			BattleLog.add_log("[恐慌] 单位 %d 陷入恐慌, 本回合命令作废!" % uid, Color(1.0, 0.6, 0.3))

	# 双方共用一条行动队列。顺序直接读取单位实例的 initiative（来自Excel先手值），
	# 因此敌我行动可以在同一回合内自然交错，而不是先结算完整一方。
	var action_queue := get_current_action_order()
	var order_names: Array[String] = []
	for unit in action_queue:
		order_names.append("%s[%d]" % [unit.unit_name, unit.initiative])
	print("[TurnManager] 本回合先手队列: %s" % " → ".join(order_names))

	for order_index in range(action_queue.size()):
		var unit: UnitBase = action_queue[order_index]
		# 高先手单位可能已经击毁后续单位；死亡单位不再获得行动机会。
		if unit == null or not unit.is_alive:
			continue
		unit_action_started.emit(unit.unit_id, order_index, action_queue.size())
		await _execute_unit_action(unit)
		unit_action_completed.emit(unit.unit_id, order_index, action_queue.size())

	# 延迟卡牌仍在本回合所有单位完成行动后统一结算。
	CardSystem.resolve_pending_card_effects()

	execution_actions_finished = true
	execution_actions_completed.emit(current_turn)
	print("[TurnManager] 沙盘演绎执行完毕")


func get_current_action_order() -> Array[UnitBase]:
	"""返回敌我共用行动队列；这是顶部顺序条与实际演算的唯一排序来源。"""
	var units: Array[UnitBase] = []
	for node in Engine.get_main_loop().get_nodes_in_group("units"):
		if node is UnitBase and node.is_alive and node.faction != UnitBase.Faction.NEUTRAL:
			units.append(node)
	units.sort_custom(UnitBase.acts_before)
	return units


func get_current_action_order_ids() -> Array[int]:
	var result: Array[int] = []
	for unit in get_current_action_order():
		result.append(unit.unit_id)
	return result


func _execute_unit_action(unit: UnitBase) -> void:
	"""执行队列中的单个单位：指令动作完成后，若允许则进行一次自动接敌。"""
	var orders := player_orders if unit.faction == UnitBase.Faction.WARSAW_PACT else ai_orders
	var order: Dictionary = orders.get(unit.unit_id, {"type": "hold"}) as Dictionary
	var order_type := String(order.get("type", "hold"))
	var used_explicit_attack := false
	var moved_this_action := false

	match order_type:
		"move":
			moved_this_action = true
			await MovementSystem.execute_move(unit.unit_id, order.get("path", []))
		"attack":
			used_explicit_attack = true
			CombatSystem.execute_attack(
				unit.unit_id,
				int(order.get("target_col", 0)),
				int(order.get("target_row", 0)),
				int(order.get("attack_type", CombatSystem.AttackType.DIRECT_FIRE)))
		"use_card":
			CardSystem.execute_card(
				String(order.get("card_id", "")),
				int(order.get("target_col", 0)),
				int(order.get("target_row", 0)))
		"special":
			_execute_special_order(unit.unit_id, order,
				unit.faction == UnitBase.Faction.WARSAW_PACT)
		"hold":
			pass

	# 没有显式攻击的单位仍沿用相遇自动开火；移动后攻击受兵种配置限制。
	var may_auto_attack := unit.is_alive and not used_explicit_attack
	if moved_this_action and (unit.requires_stationary_attack or not unit.can_attack_after_move):
		may_auto_attack = false
	if may_auto_attack:
		CombatSystem.resolve_unit_encounter_attacks(unit)


func _execute_special_order(unit_id: int, order: Dictionary, is_player: bool) -> void:
	"""执行特殊指令（工兵布雷/排雷/架桥/炸桥等）"""
	var special = order.get("special_type", "")
	var unit := _get_unit_by_id(unit_id)
	if unit == null or not unit.is_alive:
		return
	var tc := int(order.get("target_col", unit.grid_col))
	var tr := int(order.get("target_row", unit.grid_row))
	match special:
		"lay_mines":
			# 修复批B: 工兵布雷实装（can_lay_mines 校验）
			if unit.can_lay_mines:
				MovementSystem.lay_mines(tc, tr)
				BattleLog.add_log("[工兵] %s 在 (%d,%d) 布设地雷" % [unit.unit_name, tc + 1, tr + 1], Color(0.8, 0.6, 0.2))
		"clear_mines":
			# 修复批B: 工兵排雷实装 — 清除目标格地雷
			if unit.can_clear_mines:
				var mine_pos := Vector2i(tc, tr)
				if mine_pos in MovementSystem.mine_cells:
					MovementSystem.mine_cells.erase(mine_pos)
					BattleLog.add_log("[工兵] %s 排除了 (%d,%d) 的地雷" % [unit.unit_name, tc + 1, tr + 1], Color(0.55, 0.9, 0.55))
		"repair_bridge":
			# 修复批B: 工兵架桥实装 — 恢复被炸毁的桥梁格
			if unit.can_repair_bridge:
				var cell = GridManager.get_cell(tc, tr)
				if cell and cell.is_destroyed and cell.terrain == GridManager.TerrainType.BRIDGE:
					cell.is_destroyed = false
					BattleLog.add_log("[工兵] %s 修复了桥梁 (%d,%d)" % [unit.unit_name, tc + 1, tr + 1], Color(0.55, 0.9, 0.55))
		"destroy_bridge":
			# 修复批B: 工兵炸桥实装 — can_destroy_bridge 单位摧毁桥梁格（不可通行）
			if unit.can_destroy_bridge:
				var cell = GridManager.get_cell(tc, tr)
				if cell and not cell.is_destroyed and cell.terrain == GridManager.TerrainType.BRIDGE:
					cell.is_destroyed = true
					BattleLog.add_log("[工兵] %s 炸毁了桥梁 (%d,%d) — 敌军无法通过" % [unit.unit_name, tc + 1, tr + 1], Color(1.0, 0.5, 0.2))
		"recon":
			pass  # 侦察行动
		"resupply":
			pass  # 补给（回合结算自动补弹已覆盖）
		"mount":
			# 修复批B: 步兵搭载（can_transport/transport_capacity 字段消费）
			var carrier := _get_unit_by_id(int(order.get("target_unit_id", -1)))
			if carrier:
				if carrier.mount_passenger(unit):
					BattleLog.add_log("[搭载] %s 进入 %s" % [unit.unit_name, carrier.unit_name], Color(0.6, 0.9, 0.6))
				else:
					BattleLog.add_log("[搭载] 失败：%s 无法搭载 %s" % [carrier.unit_name, unit.unit_name], Color(0.9, 0.5, 0.4))
		"unmount":
			var disembarked := unit.unmount_passenger()
			if disembarked:
				BattleLog.add_log("[卸载] %s 离开载具" % disembarked.unit_name, Color(0.6, 0.9, 0.6))


func _get_unit_by_id(unit_id: int) -> UnitBase:
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if unit.unit_id == unit_id:
			return unit
	return null


## === 回合结算 ===
func resolve_turn() -> void:
	"""回合结束后结算所有效果"""
	print("[TurnManager] --- 第 %d 回合结算 ---" % current_turn)

	# 1. 结算持续效果（烟雾、EMI脉冲等）
	CardSystem.tick_cooldowns()

	# 2. 更新士气
	MoraleSystem.tick_turn(current_turn)

	# 3. 更新EMI
	EMISystem.tick_turn(current_turn)

	# 4. 弹药补给（修复批B: 原无补给机制, 单位打完即废。
	# 指挥中心 command_radius 范围内单位全额补弹, 其余单位恢复 50%）
	_apply_ammo_resupply()

	# 5. 触发回合结束事件
	_trigger_turn_events("turn_end")

	# 6. 移除过期效果
	_cleanup_expired_effects()

	turn_resolved.emit(current_turn)
	print("[TurnManager] 第 %d 回合结算完成" % current_turn)


func _apply_ammo_resupply() -> void:
	"""回合结束弹药补给: 指挥中心半径内全额, 其余半额。"""
	var wp_cmd: UnitBase = null
	var nato_cmd: UnitBase = null
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if not unit.is_alive:
			continue
		if unit.is_command:
			if unit.faction == UnitBase.Faction.WARSAW_PACT:
				wp_cmd = unit
			elif unit.faction == UnitBase.Faction.NATO:
				nato_cmd = unit

	var resupplied := 0
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if not unit.is_alive or unit.faction == UnitBase.Faction.NEUTRAL:
			continue
		if unit.current_ammo >= unit.max_ammo:
			continue
		var in_command_radius := false
		var cmd: UnitBase = wp_cmd if unit.faction == UnitBase.Faction.WARSAW_PACT else nato_cmd
		if cmd and GridManager.manhattan_distance(unit.grid_col, unit.grid_row,
				cmd.grid_col, cmd.grid_row) <= maxi(2, cmd.command_radius):
			in_command_radius = true
		unit.resupply(1.0 if in_command_radius else 0.5)
		resupplied += 1
	if resupplied > 0:
		print("[TurnManager] 弹药补给: %d 个单位 (指挥中心范围内全额)" % resupplied)


func advance_turn() -> void:
	"""进入下一回合"""
	current_turn += 1
	processed_events.clear()
	print("[TurnManager] → 进入第 %d 回合" % current_turn)

	# 检查是否达到最大回合
	if current_turn > max_turns:
		print("[TurnManager] 达到最大回合数限制")


func _cleanup_expired_effects() -> void:
	"""清理过期效果"""
	pass  # 遍历所有活跃效果，移除已到期的


## === 事件系统 ===
func register_turn_event(turn: int, event_data: Dictionary) -> void:
	"""注册回合事件"""
	if not turn_events.has(turn):
		turn_events[turn] = []
	turn_events[turn].append(event_data)


func _trigger_turn_events(phase: String) -> void:
	"""触发当前回合的特定阶段事件"""
	if not turn_events.has(current_turn):
		return

	for event in turn_events[current_turn]:
		var event_id = event.get("id", "")
		if event_id in processed_events:
			continue
		if event.get("phase", "") == phase:
			round_event_triggered.emit(event_id, event)
			processed_events.append(event_id)
			print("[TurnManager] 触发事件: %s" % event_id)


## === 查询 ===
func get_remaining_planning_time() -> float:
	return GameManager.planning_timer


func get_remaining_execution_time() -> float:
	return GameManager.execution_timer


func get_turn_progress() -> float:
	"""返回当前回合的进度百分比"""
	return float(current_turn) / float(max_turns)


## === 序列化 ===
func serialize() -> Dictionary:
	return {
		"current_turn": current_turn,
		"max_turns": max_turns,
		"orders_locked": orders_locked,
		"processed_events": processed_events  # 修复: 事件状态入档, 防止读档后当前回合事件重复触发
	}


func deserialize(data: Dictionary) -> void:
	current_turn = maxi(1, int(data.get("current_turn", 1)))
	max_turns = maxi(1, int(data.get("max_turns", 15)))   # 修复: clamp 防除零
	orders_locked = bool(data.get("orders_locked", false))
	processed_events.clear()
	for e in data.get("processed_events", []):
		processed_events.append(String(e))
