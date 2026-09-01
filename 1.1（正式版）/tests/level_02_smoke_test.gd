extends Node

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(1988)
	var packed := load("res://scenes/MainScene.tscn") as PackedScene
	var main = packed.instantiate()
	main.startup_level_id = 1
	get_tree().root.add_child(main)
	await get_tree().create_timer(3.5).timeout
	# 0.5.3 起 LEVEL_INTRO 等待玩家点击"开始行动"——测试模拟确认进入计划阶段
	GameManager.confirm_intro()
	await get_tree().create_timer(0.3).timeout

	_check(GridManager.MAP_WIDTH == 20 and GridManager.MAP_HEIGHT == 12, "第2关地图应为20×12")
	_check(TurnManager.max_turns == 10, "第2关应在第10回合结算")
	_check(get_tree().get_nodes_in_group("units").size() == 15, "第2关应生成15支初始单位")
	_check(GridManager.vp_cells.size() == 3, "第2关应有3个铁路VP")
	_check(Vector2i(9, 4) in GridManager.vp_cells and Vector2i(9, 8) in GridManager.vp_cells, "车站与桥头堡应登记为VP")
	_check(not GridManager.spawn_wp.is_empty() and not GridManager.spawn_nato.is_empty(), "双方增援点应可用")
	_check(main.loan_button.visible and CardSystem.loan_available, "第2关应开放指挥贷款")

	var hand_before := CardSystem.hand.size()
	var points_before := CardSystem.command_points
	main._on_loan_pressed()
	_check(not CardSystem.loan_available and CardSystem.hand.size() == hand_before,
		"指挥贷款不应改变手牌数量")
	_check(CardSystem.command_points == points_before + CardSystem.LOAN_COMMAND_POINTS,
		"指挥贷款应立即增加2指挥点")
	CardSystem.reset_command_points_for_turn()
	_check(CardSystem.command_points == CardSystem.MAX_COMMAND_POINTS - CardSystem.LOAN_COMMAND_POINTS,
		"贷款后的下一回合应偿还2指挥点")
	CardSystem.command_points = CardSystem.MAX_COMMAND_POINTS
	CardSystem.grant_card("reserve_deployment")
	var invalid_card_index := CardSystem.hand.size() - 1
	var invalid_points_before := CardSystem.command_points
	var invalid_hand_before := CardSystem.hand.size()
	_check(not CardSystem.use_card(invalid_card_index, 2, 6),
		"预备队投入不应允许部署到已占用地块")
	_check(CardSystem.command_points == invalid_points_before and CardSystem.hand.size() == invalid_hand_before,
		"非法目标不应消耗指挥点或卡牌")

	main._on_round_event_triggered("reserve_ready", {"description": "测试预备队"})
	_check(_hand_has_card("reserve_deployment"), "预备队事件应授予预备队投入卡")
	main._on_round_event_triggered("emi_rise_15", {"description": "测试EMI", "emi_target": 0.15})
	_check(is_equal_approx(EMISystem.base_intensity, 0.15), "第5回合EMI应升至15%")

	var sapper := _get_unit(func(unit): return unit.faction == UnitBase.Faction.WARSAW_PACT and unit.can_clear_mines)
	var sapper_health := sapper.current_health
	MovementSystem.lay_mines(4, 6)
	await MovementSystem.execute_move(sapper.unit_id, [Vector2i(4, 6)])
	_check(is_equal_approx(sapper.current_health, sapper_health), "工兵排雷不应受到伤害")
	_check(Vector2i(4, 6) not in MovementSystem.mine_cells, "工兵经过后雷区应被清除")

	var command := _get_unit(func(unit): return unit.faction == UnitBase.Faction.WARSAW_PACT and unit.is_command)
	var command_health := command.current_health
	MovementSystem.lay_mines(2, 7)
	await MovementSystem.execute_move(command.unit_id, [Vector2i(2, 7)])
	_check(command.current_health < command_health and command.grid_col == 2 and command.grid_row == 7, "普通单位触雷应受损并停在雷区")

	var count_before := get_tree().get_nodes_in_group("units").size()
	main._on_round_event_triggered("refugee_convoy", {"description": "测试难民车队"})
	_check(get_tree().get_nodes_in_group("units").size() == count_before + 1, "难民车队事件应生成平民单位")

	if _failures.is_empty():
		print("[LEVEL 02 TEST] PASS (%d checks)" % _checks)
		get_tree().quit(0)
		return
	push_error("[LEVEL 02 TEST] FAIL: %d check(s) failed\n- %s" % [_failures.size(), "\n- ".join(_failures)])
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _hand_has_card(card_id: String) -> bool:
	for card in CardSystem.hand:
		if card.card_id == card_id:
			return true
	return false


func _get_unit(predicate: Callable) -> UnitBase:
	for unit in get_tree().get_nodes_in_group("units"):
		if unit is UnitBase and predicate.call(unit):
			return unit
	return null
