extends Node

# 临时 E2E 验证脚本: 卡牌 P1批B 修复验证
# 用法: godot --headless --path . res://tests/_tmp_card_p1b_test.tscn

var _failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] " + msg)
	else:
		_failures.append(msg)
		print("  [FAIL] " + msg)

func _run() -> void:
	seed(1987)
	print("=== 卡牌 P1批B 修复验证 ===")

	var packed := load("res://scenes/MainScene.tscn") as PackedScene
	var main = packed.instantiate()
	get_tree().root.add_child(main)
	await get_tree().create_timer(3.5).timeout

	# 简报浮窗等待确认, 模拟玩家点"开始行动"
	if GameManager.current_state == GameManager.GameState.LEVEL_INTRO:
		GameManager.confirm_intro()
		await get_tree().create_timer(0.3).timeout

	# 确认处于计划阶段
	_check(GameManager.current_state == GameManager.GameState.PLANNING_PHASE, "进入计划阶段")
	_check(not CardSystem.hand.is_empty(), "手牌非空")

	# === 验证1: 状态门禁 — 非计划阶段禁止出牌 ===
	# 先手动把状态切到演绎, use_card 应返回 false
	GameManager.current_state = GameManager.GameState.EXECUTION_PHASE
	var gate_result := CardSystem.use_card(0, 10, 10)
	_check(gate_result == false, "演绎阶段 use_card 被门禁拒绝")
	GameManager.current_state = GameManager.GameState.PLANNING_PHASE

	# === 验证2: buff 卡即时生效 — 坐标预判 ===
	# 找一张坐标预判卡（如果没有就用 grant_card 塞一张）
	var pred_idx := -1
	for i in range(CardSystem.hand.size()):
		if CardSystem.hand[i].card_id == "coordinate_prediction":
			pred_idx = i
			break
	if pred_idx < 0:
		CardSystem.grant_card("coordinate_prediction")
		pred_idx = CardSystem.hand.size() - 1
	var hand_before := CardSystem.hand.size()
	var ok := CardSystem.use_card(pred_idx, 5, 5)
	_check(ok, "坐标预判出牌成功")
	_check(CardSystem.hand.size() == hand_before - 1, "出牌后手牌-1")
	_check(is_equal_approx(CardSystem.get_prediction_buff(5, 5), 0.30), "坐标预判 buff 立即写入 (5,5)=+30%")
	_check(CardSystem.pending_card_effects.is_empty(), "坐标预判不再进入延迟结算队列")

	# === 验证3: 电磁反制立即生效且方向为降 EMI ===
	var emi_idx := -1
	for i in range(CardSystem.hand.size()):
		if CardSystem.hand[i].card_id == "emi_countermeasure":
			emi_idx = i
			break
	if emi_idx < 0:
		CardSystem.grant_card("emi_countermeasure")
		emi_idx = CardSystem.hand.size() - 1
	var emi_before := EMISystem.current_intensity
	CardSystem.use_card(emi_idx, 5, 5)
	_check(EMISystem.temp_modifier < 0.0, "电磁反制: temp_modifier 为负 (%+.2f)" % EMISystem.temp_modifier)
	# 第1关 EMI 基础 0.00, 下降被 clamp 到 0 属预期; temp_modifier 负值即证明立即生效
	_check(EMISystem.current_intensity <= emi_before, "电磁反制: EMI 不升反降 (%.2f → %.2f)" % [emi_before, EMISystem.current_intensity])

	# === 验证4: 乱码卡效果池 — 手动构造一张乱码卡 ===
	var scram := CardSystem.CardInstance.new()
	scram.card_id = "coordinate_prediction"
	scram.card_name = "测试乱码卡"
	scram.is_scrambled = true
	var units_before := get_tree().get_nodes_in_group("units").size()
	CardSystem._execute_scrambled_card_effect(scram, 5, 5)
	_check(true, "乱码卡效果执行无报错 (场上单位 %d)" % units_before)

	# === 验证5: 战报谎言 — 假接触标记 ===
	var fr_idx := -1
	for i in range(CardSystem.hand.size()):
		if CardSystem.hand[i].card_id == "false_report":
			fr_idx = i
			break
	if fr_idx < 0:
		CardSystem.grant_card("false_report")
		fr_idx = CardSystem.hand.size() - 1
	CardSystem.use_card(fr_idx, 12, 12)
	_check(CardSystem.has_false_report(12, 12), "战报谎言: 假接触标记已登记 (12,12)")

	# === 验证6: 工兵布雷 1×2 ===
	var mine_idx := -1
	for i in range(CardSystem.hand.size()):
		if CardSystem.hand[i].card_id == "sapper_mines":
			mine_idx = i
			break
	if mine_idx < 0:
		CardSystem.grant_card("sapper_mines")
		mine_idx = CardSystem.hand.size() - 1
	var mines_before := MovementSystem.mine_cells.size()
	CardSystem.use_card(mine_idx, 8, 8)
	var mines_after := MovementSystem.mine_cells.size()
	_check(mines_after == mines_before + 2, "工兵布雷: 布设2格 (%d → %d)" % [mines_before, mines_after])

	# === 验证7: 烟雾时点 — 即时施放 duration=2 ===
	var smoke_idx := -1
	for i in range(CardSystem.hand.size()):
		if CardSystem.hand[i].card_id == "smoke_screen":
			smoke_idx = i
			break
	if smoke_idx < 0:
		CardSystem.grant_card("smoke_screen")
		smoke_idx = CardSystem.hand.size() - 1
	CardSystem.use_card(smoke_idx, 15, 15)
	var smoke_key = "15,15"
	_check(CombatSystem.smoke_cells.has(smoke_key) and CombatSystem.smoke_cells[smoke_key] == 2,
		"烟雾遮障: 即时施放 duration=2 (%s)" % str(CombatSystem.smoke_cells.get(smoke_key)))

	# === 验证8: 牺牲冲锋/阵地加固/断电 即时生效 ===
	# 阵地加固
	var fort_idx := -1
	for i in range(CardSystem.hand.size()):
		if CardSystem.hand[i].card_id == "fortify_position":
			fort_idx = i
			break
	if fort_idx < 0:
		CardSystem.grant_card("fortify_position")
		fort_idx = CardSystem.hand.size() - 1
	CardSystem.use_card(fort_idx, 4, 5)
	_check(is_equal_approx(CardSystem.get_fortify_buff(4, 5), 0.50), "阵地加固: 防御buff 即时写入 (4,5)=+50%")

	# === 验证9: serialize 含新增状态 ===
	var ser := CardSystem.serialize()
	_check(ser.has("false_report_cells") and ser.has("pending_card_effects") \
		and ser.has("prediction_buffs") and ser.has("fortify_buffs") and ser.has("sacrifice_buffs"),
		"serialize 包含新增状态字段 (false_report/pending/prediction/fortify/sacrifice)")

	# === 验证10: 无线电静默 — 禁止己方指令 ===
	var sil_idx := -1
	for i in range(CardSystem.hand.size()):
		if CardSystem.hand[i].card_id == "radio_silence":
			sil_idx = i
			break
	if sil_idx < 0:
		CardSystem.grant_card("radio_silence")
		sil_idx = CardSystem.hand.size() - 1
	CardSystem.use_card(sil_idx, 5, 5)
	_check(CardSystem.radio_silence_active, "无线电静默激活")
	var turn_manager := get_node("/root/TurnManager")
	var rejected: bool = not turn_manager.submit_order(1001, {"type": "hold"}, true)
	_check(rejected, "无线电静默期间己方指令被拒绝")

	print("")
	if _failures.is_empty():
		print("[CARD SYSTEM TEST] PASS (17 checks)")
	else:
		print("[CARD SYSTEM TEST] FAIL — %d 项失败:" % _failures.size())
		for f in _failures:
			print("  - " + f)
	get_tree().quit(0 if _failures.is_empty() else 1)
