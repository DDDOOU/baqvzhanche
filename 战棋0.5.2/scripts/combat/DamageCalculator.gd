# ==============================================================================
# DamageCalculator.gd — 伤害公式与修正
# ==============================================================================
# 作用：集中所有伤害计算逻辑，包括基础公式、各种修正因子。
#       独立模块，便于调整游戏平衡。
# Godot 4.7.1 兼容
# ==============================================================================
class_name DamageCalculator
extends RefCounted

## === 伤害类型 ===
enum DamageType {
	KINETIC,       # 动能（炮弹）
	EXPLOSIVE,     # 爆炸（火箭炮、炮击）
	INCENDIARY,    # 燃烧
	EMP            # 电磁脉冲
}

## === 基础伤害公式 ===
static func calculate_base_damage(attack_power: float, armor: float,
		penetration: float) -> float:
	"""
	基础伤害公式：
	damage = attack_power * (1 - armor_reduction) * penetration_factor
	"""
	# 修复批B: armor=0（平民/无装甲单位）时分母除零 → INF 伤害
	var denom := maxf(armor, 1.0)

	# 装甲减伤：装甲值 / (装甲值 + 50)
	var armor_reduction = armor / (armor + 50.0)

	# 穿透系数
	var pen_factor = 1.0
	if penetration > armor:
		pen_factor = 1.0 + (penetration - armor) / denom * 0.3  # 击穿加成

	var damage = attack_power * (1.0 - armor_reduction) * pen_factor
	return maxf(1.0, damage)


## === 高度差伤害修正 ===
static func height_damage_modifier(height_diff: int) -> float:
	"""
	高度差对伤害的影响
	height_diff > 0: 攻击方在高处 → 伤害增加
	height_diff < 0: 攻击方在低处 → 伤害减少
	"""
	if height_diff > 0:
		return 1.0 + height_diff * 0.10  # 每级+10%
	else:
		return 1.0 + height_diff * 0.05  # 每级-5%（惩罚较小）


## === 侧后装甲伤害修正 ===
static func flank_damage_modifier(is_side: bool, is_rear: bool) -> float:
	"""侧面和后方攻击的伤害加成"""
	if is_rear:
		return 1.50   # 后方 +50%
	elif is_side:
		return 1.35   # 侧面 +35%
	return 1.0


## === 面杀伤衰减 ===
static func area_damage_falloff(center_dist: int, max_radius: int) -> float:
	"""
	面杀伤随距离衰减
	中心: 100%, 半径边缘: 40%
	"""
	if center_dist == 0:
		return 1.0
	if center_dist >= max_radius:
		return 0.0
	var ratio = 1.0 - float(center_dist) / float(max_radius)
	return clampf(ratio, 0.4, 1.0)


## === 盲射伤害修正 ===
static func blind_fire_damage_modifier() -> float:
	"""盲射伤害随机修正：0.5~1.2"""
	return randf_range(0.5, 1.2)


## === 暴击判定 ===
static func check_critical_hit(accuracy: float, height_advantage: bool) -> bool:
	"""暴击判定：命中极高 + 高度优势"""
	var crit_chance = maxf(0.0, accuracy - 0.85) * 0.5  # 超过85%命中时，溢出部分50%成为暴击率
	if height_advantage:
		crit_chance += 0.10
	return randf() < crit_chance


static func critical_damage_multiplier() -> float:
	"""暴击伤害：1.5~2.0倍"""
	return randf_range(1.5, 2.0)


## === 单位克制关系 ===
static func get_counter_bonus(attacker_type: UnitBase.UnitType,
		target_type: UnitBase.UnitType) -> float:
	"""单位克制关系修正"""
	# SA-13 vs AH-64
	if attacker_type == UnitBase.UnitType.SA13_AA and target_type == UnitBase.UnitType.AH64_HELICOPTER:
		return 1.50
	if attacker_type == UnitBase.UnitType.ZSU23_AA and target_type == UnitBase.UnitType.AH64_HELICOPTER:
		return 1.35
	if attacker_type in [UnitBase.UnitType.ATGM_TEAM, UnitBase.UnitType.M901_ITV] and target_type in [
			UnitBase.UnitType.T72B_TANK, UnitBase.UnitType.M1A1_TANK,
			UnitBase.UnitType.BMP2_IFV, UnitBase.UnitType.M2_IFV,
			UnitBase.UnitType.M113_APC]:
		return 1.45
	# T-72B vs M1A1 (均衡)
	if attacker_type == UnitBase.UnitType.T72B_TANK and target_type == UnitBase.UnitType.M1A1_TANK:
		return 1.0
	# BMP-2 vs 步兵
	if attacker_type == UnitBase.UnitType.BMP2_IFV and target_type in [
		UnitBase.UnitType.INFANTRY_SQUAD, UnitBase.UnitType.MECH_INFANTRY,
		UnitBase.UnitType.NATO_RECON_SECTION]:
		return 1.25
	# 步兵 vs 坦克（贴脸）
	if attacker_type == UnitBase.UnitType.INFANTRY_SQUAD and target_type == UnitBase.UnitType.M1A1_TANK:
		return 1.40  # 步兵近距离反装甲
	return 1.0


## === 综合伤害计算 ===
static func calculate_full_damage(attacker: UnitBase, target: UnitBase,
		attack_type: int, height_diff: int,
		armor_aspect: int = UnitBase.ArmorAspect.FRONT) -> Dictionary:
	"""
	完整的伤害计算流程，返回详细结果。
	修复批B: is_side/is_rear bool 改为 ArmorAspect 枚举（FRONT/SIDE/REAR）,
	后方+50%加成与装甲 0.55/0.35 折算真正生效。
	注意: 不引用 CombatSystem（避免循环依赖）— 面杀伤/防空等修正由调用方叠加。
	"""
	var result = {"base": 0.0, "after_armor": 0.0, "final": 0.0,
		"crit": false, "breakdown": []}

	# 1. 基础伤害
	result["base"] = attacker.get_effective_damage()

	# 2. 装甲减伤（按攻击面折算: 正面全额 / 侧面0.55 / 后方0.35）
	var armor = target.armor_value
	var is_side: bool = armor_aspect == UnitBase.ArmorAspect.SIDE
	var is_rear: bool = armor_aspect == UnitBase.ArmorAspect.REAR
	if is_side:
		armor *= 0.55  # 侧面装甲
	elif is_rear:
		armor *= 0.35  # 后面装甲

	result["after_armor"] = calculate_base_damage(
		result["base"], armor, attacker.penetration)
	result["breakdown"].append("装甲减伤: %.0f → %.0f" % [result["base"], result["after_armor"]])

	# 3. 高度修正
	var height_mult = height_damage_modifier(height_diff)
	result["after_armor"] *= height_mult
	if height_diff != 0:
		result["breakdown"].append("高度差(%+d): ×%.2f" % [height_diff, height_mult])

	# 4. 侧/后修正（只对装甲单位生效）
	var flank_mult := 1.0
	if target.unit_type in [UnitBase.UnitType.T72B_TANK, UnitBase.UnitType.M1A1_TANK]:
		flank_mult = flank_damage_modifier(is_side, is_rear)
		result["after_armor"] *= flank_mult
		if is_side or is_rear:
			result["breakdown"].append("侧/后装甲: ×%.2f" % flank_mult)

	# 5. 克制
	var counter = get_counter_bonus(attacker.unit_type, target.unit_type)
	if counter != 1.0:
		result["after_armor"] *= counter
		result["breakdown"].append("克制: ×%.2f" % counter)

	result["final"] = maxf(1.0, result["after_armor"])
	return result
