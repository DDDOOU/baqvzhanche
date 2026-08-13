# ==============================================================================
# TurnManager.gd — 回合制管理系统 (Autoload 单例)
# ==============================================================================
# 作用：管理「60秒计划 + 30秒沙盘」的回合循环，处理双方同时规划、
#       同时结算的 WEGO 系统，以及回合事件触发。
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

	# WEGO 同时结算 — 四阶段:
	# 1) 合并双方移动指令，按速度排序逐个执行（模拟同时移动）
	await _execute_all_moves_combined()

	# 2) 结算延迟卡牌效果 — 移动后根据实际位置判定伤害
	CardSystem.resolve_pending_card_effects()

	# 3) 执行显式攻击指令（AI盲射/指定攻击，基于移动后新位置判定）
	var explicit_attackers := _execute_explicit_attacks()

	# 4) 相遇自动攻击 — 移动结算后，射程内的敌对单位自动开火
	CombatSystem.resolve_encounter_attacks(explicit_attackers)

	execution_actions_finished = true
	execution_actions_completed.emit(current_turn)
	print("[TurnManager] 沙盘演绎执行完毕")


## === WEGO 阶段1: 同时移动 ===
func _execute_all_moves_combined() -> void:
	"""合并双方移动指令，按单位速度排序，逐个执行"""
	var all_move_orders: Array = []
	for uid in player_orders:
		if player_orders[uid].get("type") == "move":
			all_move_orders.append({"unit_id": uid, "path": player_orders[uid].get("path", [])})
	for uid in ai_orders:
		if ai_orders[uid].get("type") == "move":
			all_move_orders.append({"unit_id": uid, "path": ai_orders[uid].get("path", [])})

	# 按速度排序（快的先动）
	all_move_orders.sort_custom(func(a, b):
		return _get_unit_speed(a.unit_id) > _get_unit_speed(b.unit_id))

	print("[TurnManager] 同时移动: %d 个单位" % all_move_orders.size())
	for order in all_move_orders:
		await MovementSystem.execute_move(order.unit_id, order.path)


## === WEGO 阶段2: 显式攻击（AI盲射等） ===
func _execute_explicit_attacks() -> Array:
	"""执行 attack 类型指令，基于移动后的新位置判定"""
	var all_attack_orders: Array = []
	for uid in player_orders:
		if player_orders[uid].get("type") == "attack":
			all_attack_orders.append({"unit_id": uid, "order": player_orders[uid]})
	for uid in ai_orders:
		if ai_orders[uid].get("type") == "attack":
			all_attack_orders.append({"unit_id": uid, "order": ai_orders[uid]})

	for entry in all_attack_orders:
		var o = entry.order
		CombatSystem.execute_attack(
			entry.unit_id,
			o.get("target_col", 0),
			o.get("target_row", 0),
			 o.get("attack_type", CombatSystem.AttackType.DIRECT_FIRE)
		)
	var attacker_ids: Array = []
	for entry in all_attack_orders:
		attacker_ids.append(entry.unit_id)
	return attacker_ids


func _execute_orders(orders: Dictionary, is_player: bool) -> void:
	"""按优先级执行指令"""
	# 优先级：移动 → 攻击 → 特殊能力 → 手牌效果
	var ordered_units = orders.keys()
	# 按单位速度排序（更快的先动）
	ordered_units.sort_custom(func(a, b): return _get_unit_speed(a) > _get_unit_speed(b))

	for unit_id in ordered_units:
		var order = orders[unit_id]
		_execute_single_order(unit_id, order, is_player)


func _execute_single_order(unit_id: int, order: Dictionary, is_player: bool) -> void:
	"""执行单个指令"""
	match order.get("type", ""):
		"move":
			MovementSystem.execute_move(unit_id, order.get("path", []))
		"attack":
			CombatSystem.execute_attack(
				unit_id,
				order.get("target_col", 0),
				order.get("target_row", 0),
				order.get("attack_type", CombatSystem.AttackType.DIRECT_FIRE)
			)
		"use_card":
			CardSystem.execute_card(
				order.get("card_id", ""),
				order.get("target_col", 0),
				order.get("target_row", 0)
			)
		"hold":
			pass  # 原地待命
		"special":
			_execute_special_order(unit_id, order, is_player)


func _execute_special_order(unit_id: int, order: Dictionary, is_player: bool) -> void:
	"""执行特殊指令（工兵布雷/排雷/架桥等）"""
	var special = order.get("special_type", "")
	match special:
		"lay_mines":
			pass  # 工兵布雷
		"clear_mines":
			pass  # 工兵排雷
		"repair_bridge":
			pass  # 修复桥梁
		"recon":
			pass  # 侦察行动
		"resupply":
			pass  # 补给


func _get_unit_speed(unit_id: int) -> float:
	var unit = _get_unit_by_id(unit_id)
	return unit.move_speed if unit else 1.0


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

	# 4. 触发回合结束事件
	_trigger_turn_events("turn_end")

	# 5. 移除过期效果
	_cleanup_expired_effects()

	turn_resolved.emit(current_turn)
	print("[TurnManager] 第 %d 回合结算完成" % current_turn)


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
