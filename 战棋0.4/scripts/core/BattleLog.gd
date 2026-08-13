# ==============================================================================
# BattleLog.gd — 战报日志系统 (Autoload 单例)
# ==============================================================================
# 作用：订阅战斗/士气信号，生成结构化战报文本，维护日志队列。
#       负责把"谁打谁、命中没、掉多少血、谁被击毁"翻译成玩家能看懂的话。
#       UI 层（BattleLogUI）订阅 log_updated 信号渲染面板。
# Godot 4.7.1 兼容
# ==============================================================================
extends Node

## === 日志数据 ===
var logs: Array[Dictionary] = []   # 每条: {text, color, turn}
const MAX_LOGS: int = 60

## === 信号 ===
signal log_updated


func _ready() -> void:
	print("[BattleLog] 战报系统就绪")
	# 订阅战斗信号 — 战斗系统不依赖战报，战报单向订阅
	CombatSystem.attack_executed.connect(_on_attack_executed)
	CombatSystem.unit_destroyed.connect(_on_unit_destroyed)
	CombatSystem.friendly_fire_occurred.connect(_on_friendly_fire)
	CombatSystem.helicopter_shot_down.connect(_on_heli_down)
	MoraleSystem.unit_broken.connect(_on_unit_broken)


## === 对外接口 ===

func add_log(text: String, color: Color = Color.WHITE) -> void:
	"""添加一条战报"""
	var entry = {
		"text": text,
		"color": color,
		"turn": TurnManager.current_turn
	}
	logs.append(entry)
	if logs.size() > MAX_LOGS:
		logs.pop_front()
	log_updated.emit()
	print("[战报] %s" % text)


func clear() -> void:
	"""清空战报（新关卡时调用）"""
	logs.clear()
	log_updated.emit()


func add_phase_log(phase_name: String) -> void:
	"""阶段切换分隔线"""
	add_log("━━━ %s ━━━" % phase_name, Color(0.6, 0.6, 0.6))


## === 信号处理 ===

func _on_attack_executed(attacker_id: int, target_col: int, target_row: int, result: Dictionary) -> void:
	var attacker = _get_unit_by_id(attacker_id)
	var a_name = "卡牌攻击" if attacker_id == -1 else ""
	var a_fac = "华约" if attacker_id == -1 else ""
	if attacker:
		a_name = _unit_display_name(attacker)
		a_fac = _faction_name(attacker.faction)
	elif attacker_id != -1:
		return  # 找不到攻击者且不是卡牌攻击，跳过

	# 未命中
	if result.get("miss", false) and not result.get("hit", false):
		var target = _get_unit_at(target_col, target_row)
		if target:
			var t_name = _unit_display_name(target)
			var t_fac = _faction_name(target.faction)
			add_log("[未命中] %s「%s」射击 %s「%s」— 偏离目标" % [a_fac, a_name, t_fac, t_name], Color.GRAY)
		else:
			add_log("[未命中] %s「%s」攻击 (%d,%d) — 落空" % [a_fac, a_name, target_col, target_row], Color.GRAY)
		return

	# 命中
	if result.get("hit", false):
		var dmg = result.get("damage", 0.0)
		var target = _get_unit_at(target_col, target_row)
		if target:
			var t_name = _unit_display_name(target)
			var t_fac = _faction_name(target.faction)
			var tag = "[命中]"
			# 误伤用黄色
			var col = Color.WHITE
			if result.get("friendly_fire", false):
				tag = "[误伤]"
				col = Color.YELLOW
			add_log("%s %s「%s」命中 %s「%s」，造成 %.0f 伤害" % [tag, a_fac, a_name, t_fac, t_name, dmg], col)
		else:
			add_log("[命中] %s「%s」命中 (%d,%d)，造成 %.0f 伤害" % [a_fac, a_name, target_col, target_row, dmg], Color.WHITE)


func _on_unit_destroyed(unit_id: int, killer_id: int) -> void:
	var victim = _get_unit_by_id(unit_id)
	if not victim:
		return
	var v_name = _unit_display_name(victim)
	var v_fac = _faction_name(victim.faction)
	# 玩家单位损失用红色醒目，敌方损失用青色
	var col = Color.RED if victim.faction == UnitBase.Faction.WARSAW_PACT else Color.CYAN

	if killer_id == -1:
		# 卡牌源击杀
		add_log("[击毁] %s「%s」被卡牌攻击摧毁！" % [v_fac, v_name], col)
		return

	var killer = _get_unit_by_id(killer_id)
	if killer:
		var k_name = _unit_display_name(killer)
		var k_fac = _faction_name(killer.faction)
		add_log("[击毁] %s「%s」被 %s「%s」击毁！" % [v_fac, v_name, k_fac, k_name], col)
		return
	add_log("[击毁] %s「%s」被摧毁！" % [v_fac, v_name], col)


func _on_friendly_fire(attacker_id: int, victim_id: int) -> void:
	var victim = _get_unit_by_id(victim_id)
	if attacker_id == -1:
		if victim:
			add_log("[误伤] 卡牌攻击击中了友军「%s」！" % _unit_display_name(victim), Color.YELLOW)
		return
	var attacker = _get_unit_by_id(attacker_id)
	if attacker and victim:
		add_log("[误伤] 「%s」击中了友军「%s」！" % [
			_unit_display_name(attacker), _unit_display_name(victim)], Color.YELLOW)


func _on_unit_broken(unit_id: int) -> void:
	var unit = _get_unit_by_id(unit_id)
	if unit:
		var col = Color.ORANGE if unit.faction == UnitBase.Faction.WARSAW_PACT else Color(1.0, 0.6, 0.3)
		add_log("[崩溃] %s「%s」士气崩溃，陷入混乱！" % [
			_faction_name(unit.faction), _unit_display_name(unit)], col)


func _on_heli_down(heli_id: int, by_unit_id: int) -> void:
	var heli = _get_unit_by_id(heli_id)
	var killer = _get_unit_by_id(by_unit_id)
	if heli and killer:
		add_log("[击落] %s「%s」被 %s「%s」击落！" % [
			_faction_name(heli.faction), _unit_display_name(heli),
			_faction_name(killer.faction), _unit_display_name(killer)], Color.CYAN)


## === 辅助 ===

func _get_unit_by_id(unit_id: int) -> UnitBase:
	"""通过ID获取单位（queue_free延迟删除，节点此时仍在树中）"""
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if unit.unit_id == unit_id:
			return unit
	return null


func _get_unit_at(col: int, row: int) -> UnitBase:
	var cell = GridManager.get_cell(col, row)
	if cell and cell.occupant_unit:
		return cell.occupant_unit
	return null


func _unit_display_name(unit: UnitBase) -> String:
	"""单位显示名：优先用 unit_name，空则用类型枚举名"""
	if unit.unit_name != null and unit.unit_name.length() > 0:
		return unit.unit_name
	return UnitBase.UnitType.keys()[unit.unit_type]


func _faction_name(faction: int) -> String:
	if faction == UnitBase.Faction.WARSAW_PACT:
		return "华约"
	return "北约"
