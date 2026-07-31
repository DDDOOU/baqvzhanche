# ==============================================================================
# MoraleSystem.gd — 士气系统 (Autoload 单例)
# ==============================================================================
# 作用：管理单位士气和战役士气，包含四档判定（昂扬/稳定/动摇/崩溃）。
#       士气影响命中率、防御力、移动速度，并触发特殊事件。
#       支持误伤惩罚、平民伤亡、剧情事件等修正来源。
# Godot 4.7.1 兼容
# ==============================================================================
extends Node

## === 士气档位 ===
enum MoraleTier {
	ELATED,     # 昂扬 (75+): 命中+10%, 移动+1
	STEADY,     # 稳定 (50-74): 无修正
	SHAKEN,     # 动摇 (25-49): 命中-10%, 防御-10%
	BROKEN      # 崩溃 (0-24): 命中-25%, 防御-25%, 可能溃逃
}

## === 士气修正表 ===
const MORALE_MODIFIERS: Dictionary = {
	MoraleTier.ELATED:  {"hit_bonus": 0.10, "defense_bonus": 0.05, "move_bonus": 1, "flee_chance": 0.0},
	MoraleTier.STEADY:  {"hit_bonus": 0.00, "defense_bonus": 0.00, "move_bonus": 0, "flee_chance": 0.0},
	MoraleTier.SHAKEN:  {"hit_bonus": -0.10, "defense_bonus": -0.10, "move_bonus": 0, "flee_chance": 0.05},
	MoraleTier.BROKEN:  {"hit_bonus": -0.25, "defense_bonus": -0.25, "move_bonus": -1, "flee_chance": 0.20},
}

## === 单位士气追踪 ===
# unit_id → {value: int, history: Array}
var unit_morale: Dictionary = {}

## === 信号 ===
signal unit_morale_changed(unit_id: int, new_value: int, tier: MoraleTier)
signal unit_broken(unit_id: int)
signal unit_rallied(unit_id: int)
signal morale_event_triggered(event_type: String, data: Dictionary)


func _ready() -> void:
	print("[MoraleSystem] 士气系统就绪")


## === 单位士气 ===
func init_unit_morale(unit_id: int, initial_value: int = 75) -> void:
	unit_morale[unit_id] = {
		"value": clampi(initial_value, 0, 100),
		"history": [initial_value]
	}


func get_unit_morale(unit_id: int) -> int:
	if unit_morale.has(unit_id):
		return unit_morale[unit_id]["value"]
	return 0


func get_unit_morale_tier(unit_id: int) -> MoraleTier:
	var value = get_unit_morale(unit_id)
	return _value_to_tier(value)


func _value_to_tier(value: int) -> MoraleTier:
	if value >= 75: return MoraleTier.ELATED
	if value >= 50: return MoraleTier.STEADY
	if value >= 25: return MoraleTier.SHAKEN
	return MoraleTier.BROKEN


func modify_unit_morale(unit_id: int, delta: int, reason: String = "") -> void:
	"""修改单位士气值"""
	if not unit_morale.has(unit_id):
		return

	var old_tier = get_unit_morale_tier(unit_id)
	var old_value = unit_morale[unit_id]["value"]
	var new_value = clampi(old_value + delta, 0, 100)

	unit_morale[unit_id]["value"] = new_value
	unit_morale[unit_id]["history"].append(new_value)

	var new_tier = _value_to_tier(new_value)
	unit_morale_changed.emit(unit_id, new_value, new_tier)

	# 档位变化检测
	if new_tier != old_tier:
		if new_tier == MoraleTier.BROKEN:
			unit_broken.emit(unit_id)
			print("[MoraleSystem] 单位 %d 士气崩溃！" % unit_id)
		elif old_tier == MoraleTier.BROKEN and new_tier >= MoraleTier.SHAKEN:
			unit_rallied.emit(unit_id)
			print("[MoraleSystem] 单位 %d 恢复斗志" % unit_id)

	print("[MoraleSystem] 单位 %d 士气 %d→%d (%s) [%s]" % [unit_id, old_value, new_value, MoraleTier.keys()[new_tier], reason])


## === 士气修正应用 ===
func get_hit_modifier(unit_id: int) -> float:
	var tier = get_unit_morale_tier(unit_id)
	return MORALE_MODIFIERS[tier]["hit_bonus"]


func get_defense_modifier(unit_id: int) -> float:
	var tier = get_unit_morale_tier(unit_id)
	return MORALE_MODIFIERS[tier]["defense_bonus"]


func get_move_modifier(unit_id: int) -> int:
	var tier = get_unit_morale_tier(unit_id)
	return MORALE_MODIFIERS[tier]["move_bonus"]


func get_flee_chance(unit_id: int) -> float:
	var tier = get_unit_morale_tier(unit_id)
	return MORALE_MODIFIERS[tier]["flee_chance"]


func check_flee(unit_id: int) -> bool:
	"""判定单位是否溃逃"""
	return randf() < get_flee_chance(unit_id)


## === 事件触发的士气变化 ===
func apply_friendly_fire_penalty(unit_id: int, severity: float) -> void:
	"""误伤惩罚 — 设计文档中的关键机制"""
	var penalty = -roundi(15 * severity)  # 最高-15
	modify_unit_morale(unit_id, penalty, "friendly_fire")
	CampaignManager.campaign_friendly_fire = mini(
		CampaignManager.campaign_friendly_fire + roundi(severity * 10), 100
	)


func apply_civilian_casualty_penalty(unit_id: int) -> void:
	"""平民伤亡惩罚 — 严重士气打击"""
	modify_unit_morale(unit_id, -20, "civilian_casualty")
	CampaignManager.civilian_casualties += 1
	morale_event_triggered.emit("civilian_casualty", {"unit_id": unit_id})


func apply_victory_bonus(unit_id: int) -> void:
	"""胜利士气奖励"""
	modify_unit_morale(unit_id, 10, "victory")


func apply_rally(unit_id: int) -> void:
	"""指挥官鼓舞效果"""
	modify_unit_morale(unit_id, 15, "rally")


## === 每回合士气自然变化 ===
func tick_turn(_turn: int) -> void:
	"""每回合士气微调"""
	for unit_id in unit_morale.keys():
		var tier = get_unit_morale_tier(unit_id)
		match tier:
			MoraleTier.BROKEN:
				# 崩溃单位有小概率自然恢复
				if randf() < 0.05:
					modify_unit_morale(unit_id, 5, "natural_recovery")
			MoraleTier.SHAKEN:
				# 动摇单位有较小概率恢复
				if randf() < 0.10:
					modify_unit_morale(unit_id, 3, "natural_recovery")


## === 序列化 ===
func serialize() -> Dictionary:
	return {"unit_morale": unit_morale.duplicate(true)}


func deserialize(data: Dictionary) -> void:
	unit_morale = data.get("unit_morale", {}).duplicate(true)
