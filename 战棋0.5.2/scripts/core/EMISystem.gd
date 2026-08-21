# ==============================================================================
# EMISystem.gd — 全频带阻塞干扰系统 (Autoload 单例)
# ==============================================================================
# 作用：管理电磁干扰(EMI)强度，影响电子设备效率、侦察范围、手牌可用性。
#       EMI时间线覆盖10关，从0%到100%再到0%。
#       在Godot 4.7.1中负责所有EMI相关的修正计算。
# ==============================================================================
extends Node

## === EMI状态 ===
var current_intensity: float = 0.0      # 当前强度 (0.0 - 1.0)
var base_intensity: float = 0.0         # 基础强度（由关卡决定）
var temp_modifier: float = 0.0          # 临时修正（手牌效果）
var temp_modifier_duration: int = 0     # 临时修正剩余回合

## === EMI 10关时间线 ===
const EMI_TIMELINE: Array[float] = [
	0.0,    # 第01关: 0%
	0.0,    # 第02关: 0%
	0.60,   # 第03关: 60% — 「洪水」第一阶段
	0.80,   # 第04关: 80%
	0.80,   # 第05关: 80%
	0.70,   # 第06关: 70%（回落）
	1.00,   # 第07关: 100% — 「洪水」第三阶段
	0.40,   # 第08关: 40%
	0.30,   # 第09关: 30%
	1.0,    # 第10关: 动态变化（100%→0%）
]

## === 第10关特殊EMI曲线 ===
const LEVEL_10_EMI_CURVE: Array[float] = [1.0, 0.80, 0.70, 0.60, 0.40, 0.0, 0.0, 0.0, 0.0, 0.0]

## === 效果修正系数 ===
var electronics_efficiency: float = 1.0     # 电子设备效率
var recon_range_modifier: float = 0.0       # 侦察范围修正
var hit_penalty: float = 0.0               # 命中惩罚
var card_scramble_chance: float = 0.0       # 手牌变为乱码的概率

## === 信号 ===
signal intensity_changed(new_intensity: float, old_intensity: float)
signal card_scrambled(card_id: String)
signal electronics_disrupted(severity: float)


func _ready() -> void:
	print("[EMISystem] 电磁干扰系统就绪")
	_update_modifiers()


func set_level(level_id: int) -> void:
	"""根据关卡ID设置EMI基础强度"""
	if level_id >= 0 and level_id < EMI_TIMELINE.size():
		base_intensity = EMI_TIMELINE[level_id]
	else:
		base_intensity = 0.0
	temp_modifier = 0.0
	temp_modifier_duration = 0
	current_intensity = base_intensity
	_update_modifiers()
	print("[EMISystem] 第%d关 EMI基础强度: %.0f%%" % [level_id + 1, base_intensity * 100])


func tick_turn(turn: int) -> void:
	"""每回合更新EMI状态"""
	# 第10关特殊处理：根据回合动态变化
	var level_id = GameManager.current_level_id
	if level_id == 9:  # 第10关 (0-indexed)
		if turn - 1 < LEVEL_10_EMI_CURVE.size():
			base_intensity = LEVEL_10_EMI_CURVE[turn - 1]

	# 先重算当前强度（临时修正在本回合演绎中仍生效），再在末尾衰减。
	# 修复: 原实现在 tick_turn 开头就减 duration, "持续2回合"实际只有1.x回合生效。
	_apply_temp_modifier_to_intensity()

	# 临时修正衰减（移到重算之后, 用卡当回合 + 后续 duration 回合均生效）
	if temp_modifier_duration > 0:
		temp_modifier_duration -= 1
		if temp_modifier_duration == 0:
			temp_modifier = 0.0
			_apply_temp_modifier_to_intensity()


func _apply_temp_modifier_to_intensity() -> void:
	"""按 base + temp 重算 current_intensity 并刷新修正系数"""
	var old = current_intensity
	current_intensity = clampf(base_intensity + temp_modifier, 0.0, 1.0)
	_update_modifiers()
	if abs(current_intensity - old) > 0.01:
		intensity_changed.emit(current_intensity, old)


func _update_modifiers() -> void:
	"""根据当前EMI强度更新所有修正系数"""
	# 电子设备效率：随EMI线性下降
	electronics_efficiency = clampf(1.0 - current_intensity * 0.8, 0.1, 1.0)

	# 侦察范围修正：按比例减少视野格数
	recon_range_modifier = -roundi(current_intensity * 4)  # 最多-4格

	# 命中惩罚
	hit_penalty = current_intensity * 0.5  # 最多-50%命中

	# 手牌乱码概率
	card_scramble_chance = current_intensity * 0.4  # 最多40%概率


## === 效果查询 ===
func apply_recon_range_modifier(base_range: int) -> int:
	"""对侦察范围应用EMI修正"""
	return maxi(1, int(base_range + recon_range_modifier))


func apply_hit_modifier(base_hit: float) -> float:
	"""对命中率应用EMI修正"""
	return clampf(base_hit - hit_penalty, 0.05, 1.0)


func apply_electronics_modifier(base_efficiency: float) -> float:
	"""对电子设备效率应用修正"""
	return base_efficiency * electronics_efficiency


func should_scramble_card() -> bool:
	"""判定手中的一张牌是否变为乱码"""
	return randf() < card_scramble_chance


## === 手牌干扰 ===
func try_scramble_card() -> String:
	"""尝试将一张手牌变为乱码，返回被干扰的卡牌ID"""
	if randf() < card_scramble_chance:
		var card_id = CardSystem.get_random_card_id()
		if not card_id.is_empty():
			card_scrambled.emit(card_id)
			return card_id
	return ""


## === 临时修正（手牌效果） ===
func add_temp_modifier(amount: float, duration: int) -> void:
	"""添加临时EMI修正（如「电磁反制」卡±10%）并立即生效。

	修复: 原实现只改 temp_modifier/duration 不重算 current_intensity,
	导致计划阶段用卡后本回合演绎阶段 EMI 无变化（效果延迟一回合）。
	"""
	temp_modifier = clampf(temp_modifier + amount, -1.0, 1.0)
	temp_modifier_duration = maxi(temp_modifier_duration, duration)
	_apply_temp_modifier_to_intensity()
	BattleLog.add_log("[EMI] 临时修正 %+.0f%%, 持续 %d 回合 (当前 %.0f%%)" % [amount * 100, duration, current_intensity * 100], Color(0.8, 0.5, 1.0))
	print("[EMISystem] 临时修正 %+.0f%%, 持续 %d 回合, 当前强度 %.0f%%" % [amount * 100, duration, current_intensity * 100])


func change_base_intensity(delta: float) -> void:
	"""关卡事件永久改变本关的基础干扰强度，并立即刷新效果。"""
	var old := current_intensity
	base_intensity = clampf(base_intensity + delta, 0.0, 1.0)
	current_intensity = clampf(base_intensity + temp_modifier, 0.0, 1.0)
	_update_modifiers()
	if not is_equal_approx(old, current_intensity):
		intensity_changed.emit(current_intensity, old)
	print("[EMISystem] 基础强度变化 %+.0f%%，当前 %.0f%%" % [delta * 100.0, current_intensity * 100.0])


func apply_countermeasure() -> void:
	"""电磁反制：降低EMI（「电磁反制」手牌效果）— 与卡名/描述一致"""
	add_temp_modifier(-0.10, 2)  # 降低10%，持续2回合


## === 序列化 ===
func serialize() -> Dictionary:
	return {
		"current_intensity": current_intensity,
		"base_intensity": base_intensity,
		"temp_modifier": temp_modifier,
		"temp_modifier_duration": temp_modifier_duration
	}


func deserialize(data: Dictionary) -> void:
	current_intensity = data.get("current_intensity", 0.0)
	base_intensity = data.get("base_intensity", 0.0)
	temp_modifier = data.get("temp_modifier", 0.0)
	temp_modifier_duration = data.get("temp_modifier_duration", 0)
	_update_modifiers()
