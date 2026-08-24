# ==============================================================================
# CombatSystem.gd — 战斗结算系统 (Autoload 单例)
# ==============================================================================
# 作用：处理所有战斗相关计算 — 命中判定、伤害计算、高度差修正、
#       侧后装甲判定、面杀伤、防空、误伤检测。
#       对应设计文档中的火力压制、盲射弹幕、误伤等机制。
# Godot 4.7.1 兼容
# ==============================================================================
extends Node

## === 攻击类型 ===
enum AttackType {
	DIRECT_FIRE,     # 直射（坦克主炮等）
	INDIRECT_FIRE,   # 间射（火箭炮、炮击）
	BLIND_FIRE,      # 盲射（无视野攻击）
	AREA_BOMBARDMENT,# 面轰炸
	ANTI_AIR,        # 防空
	CLOSE_ASSAULT    # 近战突击
}

## === 信号 ===
signal attack_started(attacker_id: int)
signal attack_executed(attacker_id: int, target_col: int, target_row: int, result: Dictionary)
signal unit_destroyed(unit_id: int, killer_id: int)
signal friendly_fire_occurred(attacker_id: int, victim_id: int)
signal civilian_hit(unit_id: int)
signal helicopter_shot_down(heli_id: int, by_unit_id: int)


func _ready() -> void:
	print("[CombatSystem] 战斗系统就绪")


## === 攻击执行 ===
func execute_attack(attacker_id: int, target_col: int, target_row: int,
		attack_type: AttackType = AttackType.DIRECT_FIRE,
		skip_area: bool = false, skip_ammo: bool = false,
		is_counter: bool = false) -> Dictionary:
	"""执行一次攻击，返回攻击结果。attacker_id=-1 表示卡牌源攻击。
	skip_area=true 时跳过面杀伤分发（面杀伤子攻击内部调用, 防递归）。
	skip_ammo=true 时跳过弹药扣减（面杀伤子攻击, 由外层统一扣一发）。
	is_counter=true 时本次为反击（不触发对方反击, 防无限递归）。"""
	var result = {"hit": false, "damage": 0.0, "destroyed": false, "friendly_fire": false}

	var is_card_attack = (attacker_id == -1)
	var attacker: UnitBase = null

	# 卡牌源攻击：用预设数值，不需要真实攻击单位
	if is_card_attack:
		match attack_type:
			AttackType.BLIND_FIRE:
				pass  # 盲射弹幕: damage=35, acc=0.50 在下方动态取值
			AttackType.AREA_BOMBARDMENT:
				pass  # 呼叫炮击: damage=50, acc=0.60
			_:
				pass
	else:
		attacker = _get_unit_by_id(attacker_id)
		if not attacker or not attacker.is_alive:
			return result
		attack_started.emit(attacker_id)
		# 修复批B: 面杀伤接入 — 炮兵单位（BM21/GVOZDIKA/M109, area_effect_radius>0）
		# 对目标格执行范围轰炸, 而非单目标直射。范围形状与卡牌统一为方形。
		if not skip_area and attacker.area_effect_radius > 0 \
				and attack_type in [AttackType.DIRECT_FIRE, AttackType.AREA_BOMBARDMENT]:
			return _execute_area_attack_with_ammo(attacker, target_col, target_row)

	# 查找目标
	var target = _get_unit_at(target_col, target_row)
	if not target:
		# 修复: 空目标 = 开火但落空——照常扣弹药并发信号（战报记录"落空"），不再静默消失
		result["miss"] = true
		result["hit_chance"] = 0.5
		if not is_card_attack and attacker and not skip_ammo:
			attacker.current_ammo = maxi(0, attacker.current_ammo - 1)
		attack_executed.emit(attacker_id, target_col, target_row, result)
		return result
	# 直射类命令在演算时再次校验射程/视线，防止目标移动后隔图开火。
	if not is_card_attack and attack_type in [AttackType.DIRECT_FIRE, AttackType.ANTI_AIR, AttackType.CLOSE_ASSAULT]:
		if not attacker.can_attack_target(target_col, target_row):
			# 修复: 开火必消耗弹药、必有战报（目标脱离射程也算一次开火）
			result["invalid_target"] = true
			result["miss"] = true
			if not skip_ammo:
				attacker.current_ammo = maxi(0, attacker.current_ammo - 1)
			attack_executed.emit(attacker_id, target_col, target_row, result)
			return result

	# 卡牌攻击视为华约方，且只打击敌方（避免玩家手牌误伤己方）
	var attacker_faction: int
	if is_card_attack:
		attacker_faction = UnitBase.Faction.WARSAW_PACT
		if target.faction == attacker_faction:
			# 玩家卡牌不会误伤友军，直接落空
			result["miss"] = true
			return result
	else:
		attacker_faction = attacker.faction

	# 误伤检测（修复批B: 只标记, 惩罚移到命中确认后触发——落空不再扣士气）
	var is_friendly_fire: bool = target.faction == attacker_faction
	var is_civilian: bool = target.unit_type == UnitBase.UnitType.CIVILIAN_CONVOY
	if is_friendly_fire:
		result["friendly_fire"] = true
		friendly_fire_occurred.emit(attacker_id, target.unit_id)
	if is_civilian:
		civilian_hit.emit(target.unit_id)

	# 命中判定
	var hit_chance: float
	if is_card_attack:
		# 卡牌基础命中率
		match attack_type:
			AttackType.BLIND_FIRE:
				hit_chance = 0.50
			AttackType.AREA_BOMBARDMENT:
				hit_chance = 0.65
			_:
				hit_chance = 0.55
		# 目标地形隐蔽
		var tc = GridManager.get_cell(target.grid_col, target.grid_row)
		if tc:
			hit_chance -= tc.get_concealment()
		hit_chance -= _get_smoke_penalty(target.grid_col, target.grid_row)
	else:
		hit_chance = _calculate_hit_chance(attacker, target, attack_type)

	hit_chance = clampf(hit_chance, 0.02, 0.98)
	var roll = randf()
	result["hit_chance"] = hit_chance
	result["roll"] = roll
	# 扣弹药代表已经开火；未命中也必须消耗一发。
	if not is_card_attack and not skip_ammo:
		attacker.current_ammo = maxi(0, attacker.current_ammo - 1)  # 修复批B: 弹药不为负

	if roll > hit_chance:
		result["hit"] = false
		result["miss"] = true
		attack_executed.emit(attacker_id, target_col, target_row, result)
		return result

	# 伤害计算
	var base_damage: float
	if is_card_attack:
		match attack_type:
			AttackType.BLIND_FIRE:
				base_damage = 35.0
			AttackType.AREA_BOMBARDMENT:
				base_damage = 50.0
			_:
				base_damage = 30.0
		# 地形防御减伤
		var tc2 = GridManager.get_cell(target.grid_col, target.grid_row)
		if tc2:
			base_damage *= (1.0 - tc2.get_defense_bonus())
		# 阵地加固额外减伤
		var fortify = CardSystem.get_fortify_buff(target.grid_col, target.grid_row)
		if fortify > 0:
			base_damage *= (1.0 - fortify)
		# 修复批B: 卡牌伤害也走装甲减伤（原 take_damage 的 armor/200 已移除,
		# 卡牌路径需自行应用 — 用 DamageCalculator 同款公式, 无攻击方穿透）
		base_damage = DamageCalculator.calculate_base_damage(
			base_damage, target.armor_value, 0.0)
	else:
		base_damage = _calculate_damage(attacker, target, attack_type)

	result["hit"] = true
	result["damage"] = base_damage

	# 应用伤害
	target.take_damage(base_damage, attacker_id)
	# 受创掉士气（修复: 士气系统原无受创反馈, 按伤害比例扣 上限10至少1）
	MoraleSystem.modify_unit_morale(target.unit_id, -clampi(int(base_damage / 12.0), 1, 10), "受创")

	# 修复批B: 误伤/平民惩罚在命中确认后触发（落空不再扣士气）
	if not is_card_attack:
		if is_friendly_fire:
			MoraleSystem.apply_friendly_fire_penalty(attacker_id, 1.0)
		if is_civilian:
			MoraleSystem.apply_civilian_casualty_penalty(attacker_id)

	# 修复批B: 近战反击 — 直射/近战命中后, 若双方相邻（贴脸）且目标存活,
	# 目标对攻击方执行一次 CLOSE_ASSAULT 反击（is_counter 防无限递归）。
	# 空中单位不参与地面近战反击（AH-64 机制差异化）。
	if not is_card_attack and not is_counter and attacker and target.is_alive:
		var adj_dist := GridManager.manhattan_distance(
			attacker.grid_col, attacker.grid_row,
			target.grid_col, target.grid_row)
		if adj_dist == 1 and target.current_ammo > 0 \
				and target.unit_type != UnitBase.UnitType.AH64_HELICOPTER:
			execute_attack(target.unit_id, attacker.grid_col, attacker.grid_row,
				AttackType.CLOSE_ASSAULT, true, false, true)

	var was_destroyed = false
	if not target.is_alive:
		result["destroyed"] = true
		was_destroyed = true

	# 先发命中信号（战报: 命中伤害 → 再发击毁信号）
	attack_executed.emit(attacker_id, target_col, target_row, result)

	# 击毁信号放在命中之后，保证战报顺序自然
	if was_destroyed:
		unit_destroyed.emit(target.unit_id, attacker_id)
		# 直升机击杀检测
		if target.unit_type == UnitBase.UnitType.AH64_HELICOPTER:
			helicopter_shot_down.emit(target.unit_id, attacker_id)

	return result


## === 命中计算 ===
func _calculate_hit_chance(attacker: UnitBase, target: UnitBase,
		attack_type: AttackType) -> float:
	"""综合命中率计算"""
	var chance = attacker.get_effective_accuracy()

	# === 攻击方修正 ===
	var attacker_cell = GridManager.get_cell(attacker.grid_col, attacker.grid_row)
	var target_cell = GridManager.get_cell(target.grid_col, target.grid_row)

	# 高度差优势：每高1级 +5%命中
	var height_diff = 0
	if attacker_cell and target_cell:
		height_diff = attacker_cell.get_effective_height() - target_cell.get_effective_height()
		chance += height_diff * 0.05  # 攻击方在高处时获得命中加成

	# 距离修正：超过基础射程的一半，每格-3%
	var dist = GridManager.manhattan_distance(attacker.grid_col, attacker.grid_row,
		target.grid_col, target.grid_row)
	var effective_range = attacker.get_effective_range()
	if dist > effective_range / 2.0:
		chance -= (dist - effective_range / 2.0) * 0.03

	# === 目标方修正 ===
	# 地形隐蔽
	if target_cell:
		chance -= target_cell.get_concealment()

	# 单位隐蔽状态
	if target.is_hidden:
		chance -= 0.20

	# 目标士气影响防御（defense_bonus 为负=防御下降→更易命中, 故用 -=）
	chance -= MoraleSystem.get_defense_modifier(target.unit_id)

	# === 攻击类型修正 ===
	match attack_type:
		AttackType.BLIND_FIRE:
			chance *= 0.60  # 盲射 -40%
		AttackType.INDIRECT_FIRE:
			chance *= 0.80  # 间射 -20%
		AttackType.ANTI_AIR:
			if target.unit_type == UnitBase.UnitType.AH64_HELICOPTER:
				if attacker.is_anti_air:
					# 修复批B: 防空命中加成用数据字段 anti_air_bonus（原硬编码 +0.15）
					chance += attacker.anti_air_bonus

	# === 坐标预判效果 ===
	# 由 CardSystem 在攻击前施加临时命中 buff
	var prediction_buff = CardSystem.get_prediction_buff(target.grid_col, target.grid_row)
	chance += prediction_buff

	# === 牺牲冲锋效果 ===
	# 由 CardSystem 施加的伤害 buff 不影响命中率，但在 _calculate_damage 中生效

	# === 烟雾效果 ===
	var smoke_penalty = _get_smoke_penalty(target.grid_col, target.grid_row)
	chance -= smoke_penalty

	return clampf(chance, 0.02, 0.98)


## === 伤害计算 ===
func _calculate_damage(attacker: UnitBase, target: UnitBase,
		attack_type: AttackType) -> float:
	"""伤害公式 — 统一走 DamageCalculator（修复批B: 原三套口径并存）"""
	var height_diff = 0
	var attacker_cell = GridManager.get_cell(attacker.grid_col, attacker.grid_row)
	var target_cell = GridManager.get_cell(target.grid_col, target.grid_row)
	if attacker_cell and target_cell:
		height_diff = attacker_cell.get_effective_height() - target_cell.get_effective_height()

	# 攻击面（FRONT/SIDE/REAR）— 侧/后加成与装甲折算在 DamageCalculator 内统一处理
	var armor_aspect := target.get_armor_aspect(attacker.grid_col, attacker.grid_row)

	var calc := DamageCalculator.calculate_full_damage(attacker, target, attack_type, height_diff, armor_aspect)
	var base_damage: float = calc["final"]

	# 面杀伤扩散（调用方叠加, DamageCalculator 不引用 CombatSystem 防循环依赖）
	if attack_type == AttackType.AREA_BOMBARDMENT:
		base_damage *= 0.75  # 面杀伤单目标伤害降低

	# 防空对直升机
	if attacker.is_anti_air and target.unit_type == UnitBase.UnitType.AH64_HELICOPTER:
		base_damage *= 1.40  # SA-13 对直升机+40%

	# 地形防御
	if target_cell:
		base_damage *= (1.0 - target_cell.get_defense_bonus())

	# 阵地加固：额外减伤
	var fortify = CardSystem.get_fortify_buff(target.grid_col, target.grid_row)
	if fortify > 0:
		base_damage *= (1.0 - fortify)

	# 牺牲冲锋：1.5倍伤害
	var sacrifice_mult = CardSystem.get_sacrifice_buff(attacker.unit_id)
	if sacrifice_mult > 1.0:
		base_damage *= sacrifice_mult

	return maxf(5.0, base_damage)


## === 烟雾效果 ===
var smoke_cells: Dictionary = {}  # {cell_key: remaining_turns}


func serialize() -> Dictionary:
	var smokes: Array = []
	for key in smoke_cells:
		smokes.append({"pos": key, "turns": smoke_cells[key]})
	return {"smoke": smokes}


func deserialize(data: Dictionary) -> void:
	smoke_cells.clear()
	for s in data.get("smoke", []):
		smoke_cells[s["pos"]] = s["turns"]

func _get_smoke_penalty(col: int, row: int) -> float:
	var key = "%d,%d" % [col, row]
	if smoke_cells.has(key) and smoke_cells[key] > 0:
		return 0.40  # 烟雾中命中-40%
	return 0.0


func apply_smoke(col: int, row: int, duration: int = 1, radius: int = 4) -> void:
	"""施加烟雾效果（「烟雾遮障」手牌）— 修复批B: 统一为方形范围（原为曼哈顿菱形, 与 4×4 描述不符）"""
	var cells = GridManager.get_cells_in_square(col, row, radius)
	for c in cells:
		var key = "%d,%d" % [c.x, c.y]
		smoke_cells[key] = duration
	print("[CombatSystem] 烟雾覆盖 %d 个格子, 持续 %d 回合" % [cells.size(), duration])


func tick_smoke() -> void:
	"""每回合烟雾衰减"""
	var expired = []
	for key in smoke_cells.keys():
		smoke_cells[key] -= 1
		if smoke_cells[key] <= 0:
			expired.append(key)
	for key in expired:
		smoke_cells.erase(key)


## === 面杀伤 ===
func _execute_area_attack_with_ammo(attacker: UnitBase, center_col: int, center_row: int) -> Dictionary:
	"""炮兵面杀伤: 对 area_effect_radius 方形范围内所有敌方单位各执行一次攻击,
	消耗一发弹药, 返回首个命中结果（战报/信号在子攻击中逐条发出）。
	修复批B: 接入 area_effect_radius 字段（原炮兵按直射单目标打）。"""
	if attacker.current_ammo <= 0:
		return {"hit": false, "damage": 0.0, "destroyed": false, "out_of_ammo": true}

	var cells := GridManager.get_cells_in_square(center_col, center_row, attacker.area_effect_radius)
	var first_result := {"hit": false, "damage": 0.0, "destroyed": false, "area": true}
	var hit_any := false
	for c in cells:
		var target = _get_unit_at(c.x, c.y)
		if target == null or target.unit_id == attacker.unit_id:
			continue
		if target.faction == attacker.faction:
			continue  # 面杀伤不打己方（与卡牌路径一致）
		var sub := execute_attack(attacker.unit_id, c.x, c.y, AttackType.AREA_BOMBARDMENT, true, true)
		if not hit_any:
			first_result = sub
			hit_any = true
	attacker.current_ammo = maxi(0, attacker.current_ammo - 1)
	first_result["area"] = true
	return first_result


## === 面杀伤（卡牌源） ===
func execute_area_attack(attacker_id: int, center_col: int, center_row: int,
		radius: int) -> Array[Dictionary]:
	"""对区域进行面杀伤（BM-21、呼叫炮击）— 修复批B: 统一方形范围"""
	var results: Array[Dictionary] = []
	var cells = GridManager.get_cells_in_square(center_col, center_row, radius)
	for c in cells:
		var target = _get_unit_at(c.x, c.y)
		if target and target.unit_id != attacker_id:
			var result = execute_attack(attacker_id, c.x, c.y, AttackType.AREA_BOMBARDMENT)
			results.append(result)
	return results


## === 盲射（Blind Fire） ===
func execute_blind_fire(attacker_id: int, center_col: int, center_row: int,
		spread: int = 3) -> Array[Dictionary]:
	"""盲射：对3×3范围进行无差别射击 — 可能误伤（修复批B: 统一方形范围）"""
	var results: Array[Dictionary] = []
	var cells = GridManager.get_cells_in_square(center_col, center_row, spread)
	for c in cells:
		var target = _get_unit_at(c.x, c.y)
		if target and target.unit_id != attacker_id:
			var result = execute_attack(attacker_id, c.x, c.y, AttackType.BLIND_FIRE)
			results.append(result)
	return results


## === 辅助方法 ===
func _get_unit_by_id(unit_id: int) -> UnitBase:
	"""通过ID获取单位"""
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if unit.unit_id == unit_id:
			return unit
	return null


func _get_unit_at(col: int, row: int) -> UnitBase:
	"""获取指定格上的单位"""
	var cell = GridManager.get_cell(col, row)
	if cell and cell.occupant_unit:
		return cell.occupant_unit
	return null


func get_best_target_in_range(unit: UnitBase) -> Dictionary:
	"""为AI找到射程内最优目标"""
	var best_target = null
	var best_score = -INF
	for col in range(GridManager.MAP_WIDTH):
		for row in range(GridManager.MAP_HEIGHT):
			if not unit.can_attack_target(col, row):
				continue
			var target = _get_unit_at(col, row)
			if target and target.faction != unit.faction and target.faction != UnitBase.Faction.NEUTRAL:
				# 评分：优先高价值、低血量目标
				var score = target.attack_power * 2.0 - target.current_health * 0.5
				if target.unit_type == UnitBase.UnitType.AH64_HELICOPTER and unit.is_anti_air:
					score += 100  # 防空优先直升机
				if score > best_score:
					best_score = score
					best_target = {"col": col, "row": row, "unit": target}

	if best_target:
		return best_target
	return {}


## === WEGO 相遇自动攻击 ===
func resolve_unit_encounter_attacks(attacker: UnitBase) -> int:
	"""为行动队列中的单个单位结算自动接敌，返回实际开火次数。"""
	if attacker == null or not attacker.is_alive:
		return 0
	var attack_count := 0
	var attacks_left := attacker.attacks_per_turn
	while attacks_left > 0 and attacker.is_alive:
		var target := get_best_target_in_range(attacker)
		if target.is_empty():
			break
		var target_unit: UnitBase = target.unit
		if target_unit == null or not target_unit.is_alive:
			break
		if target_unit.faction == attacker.faction or target_unit.faction == UnitBase.Faction.NEUTRAL:
			break
		execute_attack(attacker.unit_id, target_unit.grid_col, target_unit.grid_row,
			AttackType.DIRECT_FIRE)
		attack_count += 1
		attacks_left -= 1
	return attack_count


func resolve_encounter_attacks(excluded_unit_ids: Array = []) -> void:
	"""沙盘演绎阶段移动结算后调用。
	遍历所有存活单位，检查射程内是否有敌方单位（相遇），
	有则自动开火。按速度排序模拟同时交火。
	每个单位按 attacks_per_turn 多次攻击。"""
	var combatants: Array = []
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if unit.is_alive and unit.unit_id not in excluded_unit_ids:
			combatants.append(unit)

	# 与顶部行动顺序条一致：配置表先手值优先，其次速度，最后按单位ID稳定排序。
	combatants.sort_custom(UnitBase.acts_before)

	var attack_count := 0
	for attacker in combatants:
		attack_count += resolve_unit_encounter_attacks(attacker)

	if attack_count > 0:
		print("[CombatSystem] 相遇自动攻击: %d 次交火" % attack_count)
	else:
		print("[CombatSystem] 本回合无相遇交火")
