# ==============================================================================
# CardSystem.gd — 手牌管理系统 (Autoload 单例)
# ==============================================================================
# 作用：管理玩家的手牌 — 抽牌、弃牌、使用、冷却、乱码判定。
#       对应设计文档中的12张共享手牌和每关起始手牌配置。
#       包含指挥贷款、透支等机制。
# Godot 4.7.1 兼容
# ==============================================================================
extends Node

## === 卡牌状态 ===
class CardInstance:
	var card_id: String = ""
	var card_name: String = ""
	var cost: int = 1
	var cooldown: int = 0           # 剩余冷却回合
	var max_cooldown: int = 0
	var is_scrambled: bool = false  # 是否为乱码卡
	var data: Dictionary = {}       # 额外数据

	func is_usable() -> bool:
		return cooldown <= 0


## === 手牌管理 ===
var hand: Array[CardInstance] = []       # 当前手牌
var deck: Array[CardInstance] = []       # 牌库（本关可用）
var discard_pile: Array[CardInstance] = []  # 弃牌堆
const MAX_HAND_SIZE: int = 6             # 回合结束手牌上限
const STARTING_HAND_SIZE: int = 7        # 回合开始手牌数量

## === 指挥点（修复批B: cost 字段原无资源系统消费, 出牌零成本） ===
const MAX_COMMAND_POINTS: int = 5        # 每回合指挥点上限
var command_points: int = MAX_COMMAND_POINTS  # 当前可用指挥点
signal command_points_changed(points: int, max_points: int)

## === 指挥贷款 ===
var loan_available: bool = true          # 本关是否可贷款
var loan_used_this_turn: bool = false
var next_turn_card_penalty: int = 0      # 下回合手牌惩罚

## === 坐标预判buff ===
var prediction_buffs: Dictionary = {}    # "col,row" → hit_bonus

## === 牺牲冲锋buff ===
var sacrifice_buffs: Dictionary = {}    # unit_id → damage_multiplier

## === 阵地加固buff ===
var fortify_buffs: Dictionary = {}       # "col,row" → defense_bonus

## === 无线电静默buff ===
var radio_silence_active: bool = false

## === 断电debuff ===
var power_cut_units: Dictionary = {}    # unit_id → {turns: int, orig_accuracy: float}

## === 战报谎言假接触（修复批B: 原实现只有日志无效果） ===
var false_report_cells: Dictionary = {}  # "col,row" → 剩余回合数

## === 延迟卡牌效果（计划阶段标记，演绎阶段结算） ===
var pending_card_effects: Array = []     # [{card_id, card_name, target_col, target_row, data}]

## === 哪些卡牌是延迟结算的（位置相关） ===
## 修复(批B): 仅保留"演绎阶段区域伤害"类。buff 卡（坐标预判/阵地加固/
## 牺牲冲锋/断电）与区域控制卡（烟雾/布雷）改为即时生效——
## 1) buff 卡延迟到演绎末尾才写入 buff 表, 攻击计算（行动期间查询）查不到,
##    效果对当回合战斗永久丢失;
## 2) 烟雾/布雷延迟到演绎末尾施放, 本回合演绎已结束, "下回合生效"永远落空。
const DEFERRED_CARDS: Array[String] = [
	"blind_fire_barrage",    # 盲射弹幕 — 3×3范围伤害
	"call_artillery",        # 呼叫炮击 — 2×2范围伤害
]

## === 信号 ===
signal card_drawn(card: CardInstance)
signal card_used(card_id: String, target_col: int, target_row: int)
signal card_discarded(card: CardInstance)
signal card_scrambled(card: CardInstance)
signal loan_activated()


func _ready() -> void:
	print("[CardSystem] 手牌系统就绪")


## === 初始化 ===
func initialize_level(level_card_ids: Array) -> void:
	"""初始化本关卡牌库"""
	hand.clear()
	deck.clear()
	discard_pile.clear()
	pending_card_effects.clear()
	prediction_buffs.clear()
	sacrifice_buffs.clear()
	fortify_buffs.clear()
	power_cut_units.clear()
	false_report_cells.clear()
	radio_silence_active = false
	loan_available = true
	loan_used_this_turn = false
	next_turn_card_penalty = 0
	command_points = MAX_COMMAND_POINTS
	command_points_changed.emit(command_points, MAX_COMMAND_POINTS)

	# 从数据库加载卡牌
	for card_id in level_card_ids:
		var card_data = CardDatabase.get_card_data(card_id)
		if not card_data.is_empty():
			var card = CardInstance.new()
			card.card_id = card_id
			card.card_name = card_data.get("name", "")
			card.cost = card_data.get("cost", 1)
			card.max_cooldown = card_data.get("cooldown", 0)
			card.cooldown = 0
			card.data = card_data
			deck.append(card)

	# 洗牌
	_shuffle_deck()
	print("[CardSystem] 关卡初始化 — 牌库: %d 张" % deck.size())


## === 抽牌 ===
func draw_card(count: int = 1) -> void:
	"""抽牌。手牌可临时超过上限，计划阶段结束时由 trim_hand_to 处理溢出。"""
	for _i in range(count):
		# 下回合惩罚
		if next_turn_card_penalty > 0:
			next_turn_card_penalty -= 1
			continue

		if deck.is_empty():
			_reshuffle_discard()
			if deck.is_empty():
				return

		var card = deck.pop_back()
		# EMI乱码判定
		if EMISystem.should_scramble_card():
			card.is_scrambled = true
			card_scrambled.emit(card)
			print("[CardSystem] 手牌被干扰: %s 变为乱码" % card.card_name)

		hand.append(card)
		card_drawn.emit(card)


func grant_card(card_id: String) -> bool:
	"""由关卡事件直接授予一张指定卡牌。"""
	var card_data := CardDatabase.get_card_data(card_id)
	if card_data.is_empty():
		return false
	var card := CardInstance.new()
	card.card_id = card_id
	card.card_name = card_data.get("name", "")
	card.cost = card_data.get("cost", 1)
	card.max_cooldown = card_data.get("cooldown", 0)
	card.cooldown = 0
	card.data = card_data
	hand.append(card)
	card_drawn.emit(card)
	return true


func signal_card_discard_required() -> void:
	"""手牌满时提示需要弃牌"""
	print("[CardSystem] 手牌已满 (%d/%d)，需要弃牌" % [hand.size(), MAX_HAND_SIZE])


## === 使用卡牌 ===
func use_card(card_index: int, target_col: int, target_row: int) -> bool:
	"""使用手牌 — 计划阶段只标记作用范围，伤害在演绎阶段结算"""
	if card_index < 0 or card_index >= hand.size():
		return false

	# 修复(批B): 状态门禁 — 演绎阶段禁止出牌（延迟卡入 pending 但 resolve 已过,
	# 效果会永久丢失; 即时卡在演绎中结算也会破坏时序）
	if GameManager.current_state != GameManager.GameState.PLANNING_PHASE \
			or TurnManager.orders_locked:
		print("[CardSystem] 非计划阶段禁止使用卡牌")
		return false

	var card = hand[card_index]
	if not card.is_usable():
		print("[CardSystem] 卡牌冷却中: %s (%d回合)" % [card.card_name, card.cooldown])
		return false

	# 修复批B: 指挥点消耗 — cost 字段真正生效
	if card.cost > command_points:
		print("[CardSystem] 指挥点不足: %s 需%d点, 当前%d点" % [card.card_name, card.cost, command_points])
		return false

	# 乱码卡：随机效果
	if card.is_scrambled:
		_execute_scrambled_card_effect(card, target_col, target_row)
	else:
		_mark_or_execute_card(card, target_col, target_row)

	# 冷却
	if card.max_cooldown > 0:
		card.cooldown = card.max_cooldown

	# 扣指挥点
	command_points -= card.cost
	command_points_changed.emit(command_points, MAX_COMMAND_POINTS)

	card_used.emit(card.card_id, target_col, target_row)

	# 移入弃牌堆
	hand.remove_at(card_index)
	discard_pile.append(card)

	return true


func _mark_or_execute_card(card: CardInstance, target_col: int, target_row: int) -> void:
	"""判断卡牌是延迟结算还是即时生效"""
	if card.card_id in DEFERRED_CARDS:
		# 延迟类：只标记作用范围，等演绎阶段移动后结算
		pending_card_effects.append({
			"card_id": card.card_id,
			"card_name": card.card_name,
			"target_col": target_col,
			"target_row": target_row,
			"data": card.data
		})
		BattleLog.add_log("[卡牌] %s 已标记作用范围 (%d,%d) — 沙盘演绎时生效" % [card.card_name, target_col, target_row], Color(1.0, 0.8, 0.3))
		print("[CardSystem] 延迟标记: %s → (%d,%d)，待演绎阶段结算" % [card.card_name, target_col, target_row])
	else:
		# 即时类：直接生效
		_execute_card_effect(card, target_col, target_row)


func _execute_card_effect(card: CardInstance, target_col: int, target_row: int) -> void:
	"""执行卡牌效果"""
	match card.card_id:
		"coordinate_prediction":
			# 坐标预判：指定格命中+30%
			var key = "%d,%d" % [target_col, target_row]
			prediction_buffs[key] = 0.30
			BattleLog.add_log("[卡牌] 坐标预判: (%d,%d) 本回合命中+30%%" % [target_col, target_row], Color(0.4, 0.8, 1.0))
			print("[CardSystem] 坐标预判生效: (%d,%d) 命中+30%%" % [target_col, target_row])

		"blind_fire_barrage":
			# 盲射弹幕：对3×3范围盲射（attacker_id=-1 表示卡牌源攻击）
			CombatSystem.execute_blind_fire(-1, target_col, target_row, 3)
			BattleLog.add_log("[卡牌] 盲射弹幕覆盖 (%d,%d) 3×3范围" % [target_col, target_row], Color(1.0, 0.6, 0.3))
			print("[CardSystem] 盲射弹幕生效: (%d,%d)" % [target_col, target_row])

		"smoke_screen":
			# 烟雾遮障：4×4范围烟雾（修复批B: 原 DEFERRED 演绎末尾施放 duration=1,
			# 回合结算 tick_smoke 立刻衰减 → "下回合生效"实际从未生效。
			# 改为即时施放 duration=2: 本回合演绎 + 下回合敌方命中-40%）
			CombatSystem.apply_smoke(target_col, target_row, 2, 4)
			BattleLog.add_log("[卡牌] 烟雾遮障覆盖 (%d,%d) 4×4范围, 本回合及下回合有效" % [target_col, target_row], Color(0.6, 0.6, 0.6))
			print("[CardSystem] 烟雾遮障生效: (%d,%d) 持续2回合" % [target_col, target_row])

		"call_artillery":
			# 呼叫炮击：2×2范围炮击（attacker_id=-1 表示卡牌源攻击）
			CombatSystem.execute_area_attack(-1, target_col, target_row, 2)
			BattleLog.add_log("[卡牌] 呼叫炮击打击 (%d,%d) 2×2范围" % [target_col, target_row], Color(1.0, 0.5, 0.2))
			print("[CardSystem] 呼叫炮击生效: (%d,%d)" % [target_col, target_row])

		"fortify_position":
			# 阵地加固：指定格防御+50%
			var key = "%d,%d" % [target_col, target_row]
			fortify_buffs[key] = 0.50
			# 如果有己方单位在该格，标记不可移动
			var cell = GridManager.get_cell(target_col, target_row)
			if cell and cell.occupant_unit and cell.occupant_unit.faction == UnitBase.Faction.WARSAW_PACT:
				cell.occupant_unit.remaining_movement = 0
			BattleLog.add_log("[卡牌] 阵地加固: (%d,%d) 防御+50%%" % [target_col, target_row], Color(0.3, 0.8, 0.3))
			print("[CardSystem] 阵地加固: (%d,%d) 防御+50%%" % [target_col, target_row])

		"emi_countermeasure":
			# 电磁反制：降低EMI 10%（修复批B: 原实现 EMI+10% 自损且方向与卡名相反,
			# 用户决策按卡名语义"反制"= 保护己方电子设备, 改为降 EMI）
			EMISystem.apply_countermeasure()
			BattleLog.add_log("[卡牌] 电磁反制: EMI-10%% 持续2回合" , Color(0.8, 0.4, 1.0))
			print("[CardSystem] 电磁反制生效: EMI 降低10%")

		"radio_silence":
			# 无线电静默：己方隐蔽+50%
			radio_silence_active = true
			for unit in Engine.get_main_loop().get_nodes_in_group("units"):
				if unit.is_alive and unit.faction == UnitBase.Faction.WARSAW_PACT:
					unit.is_hidden = true
					unit.concealment_bonus += 0.50
			BattleLog.add_log("[卡牌] 无线电静默: 己方全体隐蔽+50%%" , Color(0.3, 0.8, 0.3))
			print("[CardSystem] 无线电静默生效")

		"reserve_deployment":
			# 预备队投入：在目标格生成1支预备队单位
			var cell = GridManager.get_cell(target_col, target_row)
			if cell and not cell.occupant_unit and cell.is_passable_for(false):
				var main_scene = Engine.get_main_loop().current_scene
				var unit = UnitDatabase.create_unit(UnitBase.UnitType.RESERVE,
					UnitBase.Faction.WARSAW_PACT, target_col, target_row, main_scene)
				if unit:
					BattleLog.add_log("[卡牌] 预备队投入! 「%s」已部署到 (%d,%d)" % [unit.unit_name, target_col, target_row], Color(0.2, 1.0, 0.4))
					print("[CardSystem] 预备队投入: 已部署到 (%d,%d)" % [target_col, target_row])
			else:
				BattleLog.add_log("[卡牌] 预备队投入失败: 目标格不可部署" , Color(1.0, 0.3, 0.3))
				print("[CardSystem] 预备队投入失败: 目标格被占或不可通行")

		"sapper_mines":
			# 工兵布雷（修复批B: 描述 1×2 范围, 原实现只布 1 格。
			# 布目标格 + 右侧相邻格共 2 格, 右侧越界则只布 1 格）
			var placed := 0
			for mc in [target_col, target_col + 1]:
				if not GridManager.is_valid_cell(mc, target_row):
					continue
				if not MovementSystem.mine_cells.has(Vector2i(mc, target_row)):
					MovementSystem.lay_mines(mc, target_row)
					placed += 1
			BattleLog.add_log("[卡牌] 工兵布雷: (%d,%d) 起 1×2 范围布设 %d 颗雷" % [target_col, target_row, placed], Color(0.8, 0.6, 0.2))
			print("[CardSystem] 工兵布雷生效: (%d,%d) 1×2范围 %d 颗雷" % [target_col, target_row, placed])

		"sacrifice_charge":
			# 牺牲冲锋：指定己方单位1.5倍伤害，战后-50%生命
			var cell = GridManager.get_cell(target_col, target_row)
			if cell and cell.occupant_unit and cell.occupant_unit.faction == UnitBase.Faction.WARSAW_PACT:
				var unit = cell.occupant_unit
				sacrifice_buffs[unit.unit_id] = 1.5
				# 立即扣除50%生命（战后效果提前应用）
				unit.current_health = maxf(1.0, unit.current_health * 0.5)
				BattleLog.add_log("[卡牌] 牺牲冲锋: 「%s」伤害×1.5, 生命降至50%%" % unit.unit_name, Color(1.0, 0.4, 0.2))
				print("[CardSystem] 牺牲冲锋生效: 单位%d 伤害×1.5" % unit.unit_id)
			else:
				BattleLog.add_log("[卡牌] 牺牲冲锋失败: 目标格无己方单位" , Color(1.0, 0.3, 0.3))
				print("[CardSystem] 牺牲冲锋失败: 目标格无己方单位")

		"power_cut":
			# 断电：敌方单位电磁设备失效2回合
			var cell = GridManager.get_cell(target_col, target_row)
			if cell and cell.occupant_unit and cell.occupant_unit.faction == UnitBase.Faction.NATO:
				var enemy = cell.occupant_unit
				if not power_cut_units.has(enemy.unit_id):
					power_cut_units[enemy.unit_id] = {"turns": 2, "orig_accuracy": enemy.accuracy}
					# 降低敌方命中率（到期在 tick_cooldowns 恢复）
					enemy.accuracy *= 0.5
				else:
					power_cut_units[enemy.unit_id]["turns"] = 2
				BattleLog.add_log("[卡牌] 断电: 「%s」电磁设备失效2回合" % enemy.unit_name, Color(0.8, 0.4, 1.0))
				print("[CardSystem] 断电生效: 敌方单位%d" % enemy.unit_id)
			else:
				BattleLog.add_log("[卡牌] 断电失败: 目标格无敌方单位" , Color(1.0, 0.3, 0.3))
				print("[CardSystem] 断电失败: 目标格无敌方单位")

		"false_report":
			# 战报谎言：在目标格创建虚假情报标记（修复批B: 原实现只有日志无效果。
			# 现在登记到 false_report_cells, 由 TileGridRenderer 绘制 "?" 假接触,
			# 敌方 AI 会把它当作未知接触目标, 浪费敌方行动/火力）
			var key = "%d,%d" % [target_col, target_row]
			false_report_cells[key] = 1  # 持续1回合
			BattleLog.add_log("[卡牌] 战报谎言: (%d,%d) 投放虚假情报标记" % [target_col, target_row], Color(0.8, 0.8, 0.2))
			print("[CardSystem] 战报谎言生效: (%d,%d) 假接触已投放" % [target_col, target_row])


func _execute_scrambled_card_effect(card: CardInstance, target_col: int, target_row: int) -> void:
	"""执行乱码卡效果 — 掷骰判定正/负面（修复批B: 原实现只有 print 空分支）"""
	var roll = randi() % 6  # 0-5
	if roll < 3:
		# 正面效果（1-3）
		var effects: Array[String] = [
			"accuracy",   # 随机己方单位命中+20%
			"morale",     # 随机己方单位士气+10
			"repair",     # 随机己方单位恢复30%生命
		]
		var chosen: String = effects[randi() % effects.size()]
		var unit := _get_random_wp_unit()
		if unit == null:
			BattleLog.add_log("[乱码卡] %s 触发正面效果，但场上无己方单位" % card.card_name, Color(0.8, 0.8, 0.4))
			return
		match chosen:
			"accuracy":
				unit.accuracy = minf(0.98, unit.accuracy + 0.20)
				BattleLog.add_log("[乱码卡] %s 正面效果:「%s」命中+20%%" % [card.card_name, unit.unit_name], Color(0.4, 0.9, 0.4))
			"morale":
				MoraleSystem.modify_unit_morale(unit.unit_id, 10, "scrambled_bonus")
				BattleLog.add_log("[乱码卡] %s 正面效果:「%s」士气+10" % [card.card_name, unit.unit_name], Color(0.4, 0.9, 0.4))
			"repair":
				var heal = unit.max_health * 0.30
				unit.current_health = minf(unit.max_health, unit.current_health + heal)
				BattleLog.add_log("[乱码卡] %s 正面效果:「%s」修复30%%生命" % [card.card_name, unit.unit_name], Color(0.4, 0.9, 0.4))
		print("[CardSystem] 乱码卡 '%s' 触发正面效果: %s" % [card.card_name, chosen])
	else:
		# 负面效果（4-6）
		var effects: Array[String] = [
			"damage",     # 随机己方单位损失25%生命
			"morale",     # 随机己方单位士气-10
			"reveal",     # 随机己方单位暴露（解除隐蔽）
		]
		var chosen: String = effects[randi() % effects.size()]
		var unit := _get_random_wp_unit()
		if unit == null:
			BattleLog.add_log("[乱码卡] %s 触发负面效果，但场上无己方单位" % card.card_name, Color(0.9, 0.5, 0.4))
			return
		match chosen:
			"damage":
				unit.take_damage(unit.max_health * 0.25, -1)
				BattleLog.add_log("[乱码卡] %s 负面效果:「%s」损失25%%生命" % [card.card_name, unit.unit_name], Color(0.9, 0.5, 0.4))
			"morale":
				MoraleSystem.modify_unit_morale(unit.unit_id, -10, "scrambled_penalty")
				BattleLog.add_log("[乱码卡] %s 负面效果:「%s」士气-10" % [card.card_name, unit.unit_name], Color(0.9, 0.5, 0.4))
			"reveal":
				unit.is_hidden = false
				BattleLog.add_log("[乱码卡] %s 负面效果:「%s」隐蔽被暴露" % [card.card_name, unit.unit_name], Color(0.9, 0.5, 0.4))
		print("[CardSystem] 乱码卡 '%s' 触发负面效果: %s" % [card.card_name, chosen])


func _get_random_wp_unit() -> UnitBase:
	"""随机获取一个存活的华约单位（乱码卡效果目标）"""
	var units: Array[UnitBase] = []
	for node in Engine.get_main_loop().get_nodes_in_group("units"):
		if node is UnitBase and node.is_alive and node.faction == UnitBase.Faction.WARSAW_PACT:
			units.append(node)
	if units.is_empty():
		return null
	return units[randi() % units.size()]


## === 沙盘演绎阶段：结算延迟卡牌效果 ===
func resolve_pending_card_effects() -> void:
	"""移动结算后调用 — 检查标记范围内是否有单位，有的才造成伤害/效果"""
	if pending_card_effects.is_empty():
		return

	print("[CardSystem] 结算 %d 个延迟卡牌效果" % pending_card_effects.size())

	for entry in pending_card_effects:
		var cid: String = entry.card_id
		var cname: String = entry.card_name
		var tc: int = entry.target_col
		var tr: int = entry.target_row

		match cid:
			"blind_fire_barrage":
				# 盲射弹幕：对3×3范围（中心tc,tr 周围）内的敌方单位造成伤害
				var hits = _resolve_area_damage(tc, tr, 3, 35, 0.50, cname)
				BattleLog.add_log("[卡牌结算] 盲射弹幕 → %d 个目标受创" % hits, Color(1.0, 0.6, 0.3))

			"call_artillery":
				# 呼叫炮击：对2×2范围造成伤害
				var hits = _resolve_area_damage(tc, tr, 2, 50, 0.65, cname)
				BattleLog.add_log("[卡牌结算] 呼叫炮击 → %d 个目标受创" % hits, Color(1.0, 0.5, 0.2))

			"coordinate_prediction":
				# 坐标预判：标记格如果有单位，本回合命中+30%
				var key = "%d,%d" % [tc, tr]
				prediction_buffs[key] = 0.30
				BattleLog.add_log("[卡牌结算] 坐标预判: (%d,%d) 命中+30%%" % [tc, tr], Color(0.4, 0.8, 1.0))

			"fortify_position":
				# 阵地加固：标记格如果有己方单位，防御+50%
				var cell = GridManager.get_cell(tc, tr)
				if cell and cell.occupant_unit and cell.occupant_unit.faction == UnitBase.Faction.WARSAW_PACT:
					var key = "%d,%d" % [tc, tr]
					fortify_buffs[key] = 0.50
					cell.occupant_unit.remaining_movement = 0
					BattleLog.add_log("[卡牌结算] 阵地加固: 「%s」防御+50%%" % cell.occupant_unit.unit_name, Color(0.3, 0.8, 0.3))
				else:
					BattleLog.add_log("[卡牌结算] 阵地加固: (%d,%d) 无己方单位，效果未生效" % [tc, tr], Color(0.6, 0.6, 0.6))

			"sacrifice_charge":
				# 牺牲冲锋：标记格如果有己方单位，伤害×1.5，生命-50%
				var cell = GridManager.get_cell(tc, tr)
				if cell and cell.occupant_unit and cell.occupant_unit.faction == UnitBase.Faction.WARSAW_PACT:
					var unit = cell.occupant_unit
					sacrifice_buffs[unit.unit_id] = 1.5
					unit.current_health = maxf(1.0, unit.current_health * 0.5)
					BattleLog.add_log("[卡牌结算] 牺牲冲锋: 「%s」伤害×1.5, 生命降至50%%" % unit.unit_name, Color(1.0, 0.4, 0.2))
				else:
					BattleLog.add_log("[卡牌结算] 牺牲冲锋: (%d,%d) 无己方单位，效果未生效" % [tc, tr], Color(0.6, 0.6, 0.6))

			"power_cut":
				# 断电：标记格如果有敌方单位，电磁设备失效2回合
				var cell = GridManager.get_cell(tc, tr)
				if cell and cell.occupant_unit and cell.occupant_unit.faction == UnitBase.Faction.NATO:
					var enemy = cell.occupant_unit
					if not power_cut_units.has(enemy.unit_id):
						# 修复: 首次记录原始命中率; 重复施放只重置时长, 否则恢复的是减半值→永久-50%
						power_cut_units[enemy.unit_id] = {"turns": 2, "orig_accuracy": enemy.accuracy}
						enemy.accuracy *= 0.5
					else:
						power_cut_units[enemy.unit_id]["turns"] = 2
					BattleLog.add_log("[卡牌结算] 断电: 「%s」电磁设备失效2回合" % enemy.unit_name, Color(0.8, 0.4, 1.0))
				else:
					BattleLog.add_log("[卡牌结算] 断电: (%d,%d) 无敌方单位，效果未生效" % [tc, tr], Color(0.6, 0.6, 0.6))

			"smoke_screen":
				# 烟雾遮障：在标记区域施放烟雾
				CombatSystem.apply_smoke(tc, tr, 1, 4)
				BattleLog.add_log("[卡牌结算] 烟雾遮障: (%d,%d) 4×4范围" % [tc, tr], Color(0.6, 0.6, 0.6))

			"sapper_mines":
				# 工兵布雷：在标记格布设地雷（修复批B: 描述 1×2 范围, 原实现只布 1 格。
				# 现在布目标格 + 右侧相邻格共 2 格, 若右侧越界则只布 1 格）
				var placed := 0
				for mc in [tc, tc + 1]:
					if not GridManager.is_valid_cell(mc, tr):
						continue
					var mkey = "%d,%d" % [mc, tr]
					if not MovementSystem.mine_cells.has(Vector2i(mc, tr)):
						MovementSystem.lay_mines(mc, tr)
						placed += 1
				BattleLog.add_log("[卡牌结算] 工兵布雷: (%d,%d) 起 1×2 范围布设 %d 颗雷" % [tc, tr, placed], Color(0.8, 0.6, 0.2))

	# 结算完毕，清空待处理列表
	pending_card_effects.clear()


func _resolve_area_damage(center_col: int, center_row: int, area_size: int,
		base_damage: float, hit_chance: float, source_name: String) -> int:
	"""对指定范围内的敌方单位造成伤害，返回命中数"""
	var half := int(area_size / 2.0)   # 修复: GDScript4 中 / 恒为浮点除, 必须显式取整, 否则 3x3 实际覆盖 2x2
	var hits = 0

	for dc in range(-half, area_size - half):
		for dr in range(-half, area_size - half):
			var c = center_col + dc
			var r = center_row + dr
			if not GridManager.is_valid_cell(c, r):
				continue
			var cell = GridManager.get_cell(c, r)
			if not cell or not cell.occupant_unit:
				continue
			var target = cell.occupant_unit
			if not target.is_alive:
				continue
			if target.faction == UnitBase.Faction.WARSAW_PACT:
				continue  # 卡牌不攻击己方

			# 命中判定
			if randf() <= hit_chance:
				# 地形防御减伤
				var dmg = base_damage * (1.0 - cell.get_defense_bonus())
				# 阵地加固减伤
				dmg *= (1.0 - get_fortify_buff(c, r))
				# 修复批B: 卡牌范围伤害也走装甲减伤（与直射统一, take_damage 已移除 armor/200）
				dmg = DamageCalculator.calculate_base_damage(dmg, target.armor_value, 0.0)
				# 修复: 卡牌范围攻击误伤中立平民→惩罚攻击方（与直射路径一致, 扣平民自己士气无效）
				if target.faction == UnitBase.Faction.NEUTRAL \
						and target.unit_type == UnitBase.UnitType.CIVILIAN_CONVOY:
					MoraleSystem.apply_civilian_casualty_penalty(-1)
				target.take_damage(dmg, -1)

				var was_destroyed = false
				if not target.is_alive:
					was_destroyed = true

				CombatSystem.attack_executed.emit(-1, c, r, {
					"hit": true, "damage": dmg, "destroyed": was_destroyed, "card_sourced": true
				})
				BattleLog.add_log("[卡牌结算] %s 命中「%s」造成 %.0f 伤害" % [source_name, target.unit_name, dmg], Color(1.0, 0.6, 0.3))

				if was_destroyed:
					CombatSystem.unit_destroyed.emit(target.unit_id, -1)

				hits += 1
			else:
				BattleLog.add_log("[卡牌结算] %s 射向 (%d,%d) — 偏离目标" % [source_name, c, r], Color(0.6, 0.6, 0.6))

	return hits


func execute_card(card_id: String, target_col: int, target_row: int) -> void:
	"""由TurnManager在执行阶段调用 — 执行卡牌效果"""
	for card_data in CardDatabase.ALL_CARDS:
		if card_data["id"] == card_id:
			var card = CardInstance.new()
			card.card_id = card_id
			card.card_name = card_data["name"]
			card.data = card_data
			_execute_card_effect(card, target_col, target_row)
			break


## === 指挥贷款 ===
func activate_loan() -> bool:
	"""激活指挥贷款 — 透支下回合1张手牌"""
	if not loan_available:
		print("[CardSystem] 本关贷款已使用")
		return false
	if loan_used_this_turn:
		print("[CardSystem] 本回合已贷款")
		return false

	loan_used_this_turn = true
	loan_available = false
	CampaignManager.add_loan(10)
	loan_activated.emit()

	# 先立即抽一张牌，再登记下回合惩罚；否则惩罚会错误吞掉本次贷款收益。
	draw_card()
	next_turn_card_penalty += 1
	print("[CardSystem] 指挥贷款激活 — 下回合手牌-1, 累计贷款: %d" % CampaignManager.campaign_loans)
	return true


## === 回合处理 ===
func tick_cooldowns() -> void:
	"""每回合更新冷却"""
	for card in deck:
		if card.cooldown > 0:
			card.cooldown -= 1
	for card in hand:
		if card.cooldown > 0:
			card.cooldown -= 1
	for card in discard_pile:
		if card.cooldown > 0:
			card.cooldown -= 1

	# 清理已结算的延迟效果（resolve_pending_card_effects 已清空，这里是安全兜底）
	pending_card_effects.clear()

	# 清除过期buff — 坐标预判只持续1回合
	var expired_keys = []
	for key in prediction_buffs.keys():
		expired_keys.append(key)
	for key in expired_keys:
		prediction_buffs.erase(key)

	# 牺牲冲锋只持续1回合
	sacrifice_buffs.clear()

	# 阵地加固只持续1回合
	fortify_buffs.clear()

	# 无线电静默重置
	if radio_silence_active:
		radio_silence_active = false
		for unit in Engine.get_main_loop().get_nodes_in_group("units"):
			if unit.is_alive and unit.faction == UnitBase.Faction.WARSAW_PACT:
				unit.is_hidden = false
				unit.concealment_bonus = maxf(0.0, unit.concealment_bonus - 0.50)

	# 断电倒计时（到期恢复命中率）
	var expired_pc = []
	for uid in power_cut_units.keys():
		var entry: Dictionary = power_cut_units[uid]
		entry["turns"] -= 1
		if entry["turns"] <= 0:
			expired_pc.append(uid)
	for uid in expired_pc:
		var entry: Dictionary = power_cut_units[uid]
		var unit: UnitBase = null
		for u in Engine.get_main_loop().get_nodes_in_group("units"):
			if u.unit_id == uid:
				unit = u
				break
		if unit and unit.is_alive and entry.has("orig_accuracy"):
			unit.accuracy = entry["orig_accuracy"]  # 修复: 断电 debuff 到期必须恢复命中率
		power_cut_units.erase(uid)

	# 战报谎言假接触衰减（持续1回合, 回合末清除）
	var expired_fr = []
	for key in false_report_cells.keys():
		false_report_cells[key] = int(false_report_cells[key]) - 1
		if false_report_cells[key] <= 0:
			expired_fr.append(key)
	for key in expired_fr:
		false_report_cells.erase(key)

	# 重置贷款
	loan_used_this_turn = false

	# 烟雾衰减
	CombatSystem.tick_smoke()


func get_prediction_buff(col: int, row: int) -> float:
	"""查询坐标预判buff"""
	var key = "%d,%d" % [col, row]
	return prediction_buffs.get(key, 0.0)


func get_sacrifice_buff(unit_id: int) -> float:
	"""查询牺牲冲锋伤害倍率（>1.0 表示有buff）"""
	return sacrifice_buffs.get(unit_id, 1.0)


func get_fortify_buff(col: int, row: int) -> float:
	"""查询阵地加固防御加成"""
	var key = "%d,%d" % [col, row]
	return fortify_buffs.get(key, 0.0)


func is_unit_power_cut(unit_id: int) -> bool:
	"""查询单位是否被断电"""
	if not power_cut_units.has(unit_id):
		return false
	return power_cut_units[unit_id]["turns"] > 0


func has_false_report(col: int, row: int) -> bool:
	"""查询目标格是否有战报谎言假接触标记"""
	var key = "%d,%d" % [col, row]
	return false_report_cells.has(key) and int(false_report_cells[key]) > 0


func discard_card(card_index: int) -> void:
	"""弃牌"""
	if card_index >= 0 and card_index < hand.size():
		var card = hand[card_index]
		hand.remove_at(card_index)
		discard_pile.append(card)
		card_discarded.emit(card)
		BattleLog.add_log("[弃牌] %s 已弃置" % card.card_name, Color(0.7, 0.7, 0.7))


## === 手牌数量管理 ===
func refill_hand_to(target_size: int) -> void:
	"""补充手牌到指定数量（不足则抽牌补满）"""
	var needed = target_size - hand.size()
	if needed > 0:
		draw_card(needed)
		print("[CardSystem] 补充手牌: 抽 %d 张 (当前 %d/%d)" % [needed, hand.size(), target_size])


func trim_hand_to(target_size: int) -> void:
	"""手牌超出上限时自动弃牌到指定数量"""
	var excess = hand.size() - target_size
	while excess > 0 and not hand.is_empty():
		var card = hand.pop_back()
		discard_pile.append(card)
		card_discarded.emit(card)
		BattleLog.add_log("[自动弃牌] %s 已弃置 (手牌超上限)" % card.card_name, Color(0.9, 0.7, 0.3))
		excess -= 1
	if excess > 0:
		print("[CardSystem] 自动弃牌 %d 张到上限 %d" % [hand.size() + excess, target_size])


func adjust_hand_to(target_size: int) -> void:
	"""多弃少补：手牌多于目标则弃到目标，少于目标则抽到目标"""
	if hand.size() > target_size:
		trim_hand_to(target_size)
	elif hand.size() < target_size:
		refill_hand_to(target_size)
	print("[CardSystem] 手牌调整至 %d 张 (当前 %d)" % [target_size, hand.size()])


func get_random_card_id() -> String:
	"""获取随机卡牌ID（用于乱码判定）"""
	if not hand.is_empty():
		return hand.pick_random().card_id
	return ""


## === 洗牌 ===
func _shuffle_deck() -> void:
	"""Fisher-Yates洗牌"""
	var n = deck.size()
	for i in range(n - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = deck[i]
		deck[i] = deck[j]
		deck[j] = temp


func _reshuffle_discard() -> void:
	"""将弃牌堆洗回牌库"""
	if discard_pile.is_empty():
		return
	print("[CardSystem] 弃牌堆洗回牌库 (%d 张)" % discard_pile.size())
	deck.append_array(discard_pile)
	discard_pile.clear()
	_shuffle_deck()


## === 序列化 ===
func serialize() -> Dictionary:
	return {
		"hand": _cards_to_state(hand),
		"deck": _cards_to_state(deck),
		"discard": _cards_to_state(discard_pile),
		"loan_available": loan_available,
		"next_turn_penalty": next_turn_card_penalty,
		"command_points": command_points,
		"radio_silence_active": radio_silence_active,
		"power_cut_units": power_cut_units,
		"false_report_cells": false_report_cells,
		"pending_card_effects": pending_card_effects,
		"prediction_buffs": prediction_buffs,
		"fortify_buffs": fortify_buffs,
		"sacrifice_buffs": sacrifice_buffs,
	}


func deserialize(data: Dictionary) -> void:
	# 修复: 空/缺失存档数据不覆盖已抽手牌（旧档无 cards 字段时跳过）
	if data.is_empty():
		return
	hand.clear()
	deck.clear()
	discard_pile.clear()
	loan_available = data.get("loan_available", true)
	next_turn_card_penalty = data.get("next_turn_penalty", 0)
	command_points = int(data.get("command_points", MAX_COMMAND_POINTS))
	# 修复: 无线电静默/断电状态入档, 否则读档后 concealment_bonus 永久残留
	radio_silence_active = bool(data.get("radio_silence_active", false))
	power_cut_units = data.get("power_cut_units", {}).duplicate(true)
	# 修复(批B): 战报谎言/延迟卡/buff 状态入档, 计划阶段用卡后读档不丢效果
	false_report_cells = data.get("false_report_cells", {}).duplicate(true)
	pending_card_effects = data.get("pending_card_effects", []).duplicate(true)
	prediction_buffs = data.get("prediction_buffs", {}).duplicate(true)
	fortify_buffs = data.get("fortify_buffs", {}).duplicate(true)
	sacrifice_buffs = data.get("sacrifice_buffs", {}).duplicate(true)
	# 修复: 必须重建卡牌对象, 否则读档后手牌/牌库为空, 卡牌系统整体失效
	hand = _cards_from_state(data.get("hand", []))
	deck = _cards_from_state(data.get("deck", []))
	discard_pile = _cards_from_state(data.get("discard", []))
	# 兼容旧存档（仅 id 列表）
	if hand.is_empty() and deck.is_empty() and data.has("hand_ids"):
		hand = _cards_from_ids(data.get("hand_ids", []))
		deck = _cards_from_ids(data.get("deck_ids", []))
		discard_pile = _cards_from_ids(data.get("discard_ids", []))
	print("[CardSystem] 反序列化完成 — 手牌%d/牌库%d/弃牌%d" % [hand.size(), deck.size(), discard_pile.size()])


func _cards_to_state(list: Array[CardInstance]) -> Array:
	var out: Array = []
	for c in list:
		out.append({"id": c.card_id, "cd": c.cooldown, "scrambled": c.is_scrambled})
	return out


func _cards_from_state(states: Array) -> Array[CardInstance]:
	var out: Array[CardInstance] = []
	for s in states:
		var c := CardInstance.new()
		if s is Dictionary:
			c.card_id = s.get("id", "")
			c.cooldown = int(s.get("cd", 0))
			c.is_scrambled = s.get("scrambled", false)
		else:
			# 兼容旧格式（元素为纯 id 字符串）
			c.card_id = String(s)
		_fill_card_info(c)   # 修复: 回填 name/cost/max_cooldown/data, 否则读档后卡牌空白
		out.append(c)
	return out


func _cards_from_ids(ids: Array) -> Array[CardInstance]:
	var out: Array[CardInstance] = []
	for id in ids:
		var c := CardInstance.new()
		c.card_id = id
		_fill_card_info(c)
		out.append(c)
	return out


func _fill_card_info(card: CardInstance) -> void:
	"""按 card_id 从数据库回填卡牌展示与规则字段"""
	var data: Dictionary = CardDatabase.get_card_data(card.card_id)
	if data.is_empty():
		return
	card.card_name = data.get("name", card.card_id)
	card.cost = int(data.get("cost", 1))
	card.max_cooldown = int(data.get("cooldown", 0))
	card.data = data
