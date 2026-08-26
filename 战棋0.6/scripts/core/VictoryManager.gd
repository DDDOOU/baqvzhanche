# ==============================================================================
# VictoryManager.gd — 胜利判定系统 (Autoload 单例)
# ==============================================================================
# 作用：多维度判定关卡胜负：
#   1. 指挥中心被毁 → 即时失败
#   2. 一方全歼 → 即时胜负
#   3. 回合末（max_turns）VP格控制判定 → 三档胜负
# Godot 4.7.1 兼容
# ==============================================================================
extends Node

const DEBUG_LOGS := false

## === 信号 ===
signal game_over(winner_faction: int, reason: String)
signal victory_checked(wp_alive: int, nato_alive: int)
signal vp_checked(wp_vp: int, nato_vp: int, neutral_vp: int)

## === 状态 ===
var is_game_over: bool = false
var winner_faction: int = -1
var wp_command_center_pos: Vector2i = Vector2i(-1, -1)
var nato_command_center_pos: Vector2i = Vector2i(-1, -1)
var max_turns: int = 8
var wp_initial_units: int = 0
var last_game_over_reason: String = ""   # 存储真正的胜利原因，供 UI 读取
var wp_command_unit_id: int = -1
var nato_command_unit_id: int = -1
var wp_command_destroyed: bool = false
var nato_command_destroyed: bool = false


func _ready() -> void:
	print("[VictoryManager] 胜利判定系统就绪")
	CombatSystem.unit_destroyed.connect(_on_unit_destroyed)


## === 核心接口 ===
func reset() -> void:
	"""新关卡开始时重置"""
	is_game_over = false
	winner_faction = -1
	wp_command_center_pos = Vector2i(-1, -1)
	nato_command_center_pos = Vector2i(-1, -1)
	max_turns = 8
	wp_initial_units = 0
	last_game_over_reason = ""
	wp_command_unit_id = -1
	nato_command_unit_id = -1
	wp_command_destroyed = false
	nato_command_destroyed = false


func setup_level(level_data) -> void:
	"""从关卡数据初始化胜利条件（位置和回合限制，单位数由 register_initial_units 单独设）"""
	wp_command_center_pos = level_data.wp_command_center
	nato_command_center_pos = level_data.nato_command_center
	max_turns = level_data.max_turns
	wp_initial_units = 0  # 稍后由 register_initial_units 设置
	print("[VictoryManager] 关卡设置 — 指挥中心 WP(%d,%d) NATO(%d,%d) 最大回合%d" % [
		wp_command_center_pos.x, wp_command_center_pos.y,
		nato_command_center_pos.x, nato_command_center_pos.y, max_turns])


func register_initial_units() -> void:
	"""单位创建完成后记录初始数量，并绑定双方指挥中心的开局驻守单位。"""
	wp_initial_units = _count_faction_units(UnitBase.Faction.WARSAW_PACT)
	wp_command_unit_id = _get_unit_id_at(wp_command_center_pos, UnitBase.Faction.WARSAW_PACT)
	nato_command_unit_id = _get_unit_id_at(nato_command_center_pos, UnitBase.Faction.NATO)
	print("[VictoryManager] 初始单位数: 华约 %d；指挥单位 WP=%d NATO=%d" % [
		wp_initial_units, wp_command_unit_id, nato_command_unit_id])


func check_victory_now() -> Dictionary:
	"""立即检查即时胜负条件（歼灭/指挥中心），返回结果"""
	var counts = _count_alive_units()
	var wp_alive: int = counts[UnitBase.Faction.WARSAW_PACT]
	var nato_alive: int = counts[UnitBase.Faction.NATO]

	var wp_cc_destroyed = _is_command_center_destroyed(UnitBase.Faction.WARSAW_PACT)
	var nato_cc_destroyed = _is_command_center_destroyed(UnitBase.Faction.NATO)
	if DEBUG_LOGS:
		print("[VictoryManager DEBUG] wp_alive=%d nato_alive=%d | WP_CC_destroyed=%s NATO_CC_destroyed=%s | WP_CC_pos=(%d,%d) NATO_CC_pos=(%d,%d)" % [
			wp_alive, nato_alive, wp_cc_destroyed, nato_cc_destroyed,
			wp_command_center_pos.x, wp_command_center_pos.y,
			nato_command_center_pos.x, nato_command_center_pos.y])

	var result = {
		"wp_alive": wp_alive,
		"nato_alive": nato_alive,
		"winner": -1,
		"game_over": false,
		"reason": ""
	}

	# 即时失败：指挥中心被毁
	if wp_cc_destroyed:
		result.winner = UnitBase.Faction.NATO
		result.game_over = true
		result.reason = "华约指挥中心被摧毁！"
	elif nato_cc_destroyed:
		result.winner = UnitBase.Faction.WARSAW_PACT
		result.game_over = true
		result.reason = "北约指挥中心被摧毁！"
	elif wp_alive == 0:
		result.winner = UnitBase.Faction.NATO
		result.game_over = true
		result.reason = "华约单位被全歼"
	elif nato_alive == 0:
		result.winner = UnitBase.Faction.WARSAW_PACT
		result.game_over = true
		result.reason = "北约单位被全歼"

	if result.game_over and DEBUG_LOGS:
		print("[VictoryManager DEBUG] !!! game_over 触发: winner=%s reason=%s" % [
			_faction_name(result.winner), result.reason])

	victory_checked.emit(wp_alive, nato_alive)
	return result


func check_turn_end_victory(current_turn: int) -> Dictionary:
	"""回合末检查VP控制 + 回合限制判定，返回三档胜负结果"""
	if current_turn < max_turns:
		return {"completed": false}

	# 到达最大回合，进行VP判定
	var vp = _count_vp_control()
	var wp_vp: int = vp.wp
	var nato_vp: int = vp.nato
	vp_checked.emit(wp_vp, nato_vp, vp.neutral)

	var wp_alive = _count_alive_units()[UnitBase.Faction.WARSAW_PACT]
	var casualties = wp_initial_units - wp_alive
	var casualty_ratio = float(casualties) / float(maxi(1, wp_initial_units))

	var result = {
		"completed": true,
		"level_id": GameManager.current_level_id,
		"wp_vp": wp_vp,
		"nato_vp": nato_vp,
		"casualties": casualties,
		"casualty_ratio": casualty_ratio,
		"morale_delta": 0,
		"victory_tier": "",
	}

	# 判定三档
	if wp_vp >= 2:
		# 守住至少2个VP → 胜利
		if wp_vp == 3 and _is_command_center_alive(UnitBase.Faction.WARSAW_PACT):
			# 全部守住 + 指挥中心完好 → 胜利
			result.victory_tier = "victory"
			result.morale_delta = 5
			result["victory"] = true
			result["reason"] = "三个战略坐标全部守住，指挥中心完好！士气+5，奖励3个行动点"
		elif casualty_ratio > 0.4:
			# 守住但伤亡较大 → 惨胜
			result.victory_tier = "pyrrhic"
			result.morale_delta = -5
			result["victory"] = true
			result["reason"] = "勉强守住%d个VP，但伤亡达%.0f%%。惨胜，士气-5" % [wp_vp, casualty_ratio * 100]
		else:
			# 正常胜利
			result.victory_tier = "victory"
			result.morale_delta = 5
			result["victory"] = true
			result["reason"] = "守住%d个战略坐标，指挥中心完好。士气+5" % wp_vp
	else:
		# VP少于2个 → 惨败
		result.victory_tier = "defeat"
		result.morale_delta = -10
		result["victory"] = false
		result["reason"] = "仅守住%d个VP格，战略坐标失守。惨败，士气-10" % wp_vp

	return result


func _on_unit_destroyed(unit_id: int, _killer_id: int) -> void:
	"""单位摧毁时即时检查"""
	if is_game_over:
		return
	if unit_id == wp_command_unit_id:
		wp_command_destroyed = true
	elif unit_id == nato_command_unit_id:
		nato_command_destroyed = true
	var result = check_victory_now()
	if result.game_over:
		_trigger_game_over(result.winner, result.reason)


func _trigger_game_over(winner: int, reason: String) -> void:
	if is_game_over:
		return
	is_game_over = true
	winner_faction = winner
	last_game_over_reason = reason
	print("[VictoryManager] 游戏结束 — %s" % reason)
	game_over.emit(winner, reason)


func finish_game(winner: int, reason: String) -> void:
	"""供游戏流程调用的正式结算接口。"""
	_trigger_game_over(winner, reason)


## === VP控制统计 ===
func _count_vp_control() -> Dictionary:
	"""统计每个VP格由哪方控制"""
	var wp_vp = 0
	var nato_vp = 0
	var neutral = 0

	for vp in GridManager.vp_cells:
		var cell = GridManager.get_cell(vp.x, vp.y)
		if not cell:
			neutral += 1
			continue
		if cell.occupant_unit and cell.occupant_unit.is_alive:
			if cell.occupant_unit.faction == UnitBase.Faction.WARSAW_PACT:
				wp_vp += 1
			elif cell.occupant_unit.faction == UnitBase.Faction.NATO:
				nato_vp += 1
			else:
				neutral += 1  # 中立单位（平民）不控制 VP
		else:
			neutral += 1

	return {"wp": wp_vp, "nato": nato_vp, "neutral": neutral}


func get_vp_control() -> Dictionary:
	"""返回当前胜利点控制统计。"""
	return _count_vp_control()


## === 指挥中心判定 ===
func _is_command_center_destroyed(faction: int) -> bool:
	"""检查开局绑定的指挥单位是否已被摧毁；移动不会解除其指挥身份。"""
	if faction == UnitBase.Faction.WARSAW_PACT:
		return wp_command_destroyed
	return nato_command_destroyed


func _is_command_center_alive(faction: int) -> bool:
	return not _is_command_center_destroyed(faction)


func _check_command_unit_alive(faction: int) -> bool:
	"""检查该阵营是否还有is_command=True的单位存活"""
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if unit.faction == faction and unit.is_alive and unit.is_command:
			return true
	return false


func _get_unit_id_at(pos: Vector2i, faction: int) -> int:
	var cell = GridManager.get_cell(pos.x, pos.y)
	if cell and cell.occupant_unit and cell.occupant_unit.faction == faction:
		return cell.occupant_unit.unit_id
	# 关卡数据未把单位正好放在标记格时，优先采用该阵营显式指挥单位。
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if unit.faction == faction and unit.is_alive and unit.is_command:
			return unit.unit_id
	return -1


## === 单位统计 ===
func _count_alive_units() -> Dictionary:
	var counts = {
		UnitBase.Faction.WARSAW_PACT: 0,
		UnitBase.Faction.NATO: 0
	}
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if unit.is_alive:
			counts[unit.faction] = counts.get(unit.faction, 0) + 1
	return counts


func _count_faction_units(faction: int) -> int:
	var count = 0
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if unit.faction == faction:
			count += 1
	return count


func _faction_name(faction: int) -> String:
	if faction == UnitBase.Faction.WARSAW_PACT:
		return "华约"
	if faction == UnitBase.Faction.NATO:
		return "北约"
	return "未知"
