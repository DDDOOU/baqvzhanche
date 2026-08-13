extends Node

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(1987)
	var packed := load("res://scenes/MainScene.tscn") as PackedScene
	var main = packed.instantiate()
	get_tree().root.add_child(main)
	await get_tree().create_timer(3.5).timeout
	var turn_manager = get_node("/root/TurnManager")
	var victory_manager = get_node("/root/VictoryManager")
	var emi_system = get_node("/root/EMISystem")

	_check(turn_manager.current_turn == 1, "新关卡应从第1回合开始")
	_check(turn_manager.max_turns == 8, "第一关最大回合应为8")
	_check(victory_manager.wp_command_unit_id >= 0, "应绑定华约指挥单位")
	_check(victory_manager.nato_command_unit_id >= 0, "应绑定北约指挥单位")
	_check(GridManager.MAP_WIDTH == 40 and GridManager.MAP_HEIGHT == 45, "第一关地图应为40×45")
	_check(get_tree().get_nodes_in_group("units").size() == 18, "第一关应生成18支初始单位")
	_check(GridManager.get_neighbors(0, 0).size() == 2, "地图角落应只有两个四方向邻格")
	_check(GridManager.manhattan_distance(1, 2, 4, 6) == 7, "四方向曼哈顿距离应正确")
	var tank := _get_unit_by_id(1004)
	_check(tank != null and TilePathfinding.is_armored(tank), "坦克应按装甲单位寻路")
	if tank != null:
		tank.remaining_movement = 0
		turn_manager.start_planning_phase()
		_check(tank.remaining_movement == tank.get_effective_movement(), "每回合计划阶段开始应恢复有效移动点")
		var reachable_cells := TilePathfinding.get_reachable_cells(tank)
		var move_target: Vector2i = reachable_cells[0] if not reachable_cells.is_empty() \
			else Vector2i(-1, -1)
		var movement_path: Array = []
		if move_target.x >= 0:
			movement_path = TilePathfinding.find_path(
				tank.grid_col, tank.grid_row, move_target.x, move_target.y,
				tank, tank.get_effective_movement())
		_check(not movement_path.is_empty(), "单位应能规划到相邻空地")
		if not movement_path.is_empty():
			var start_position := Vector2i(tank.grid_col, tank.grid_row)
			var submitted_test_path := movement_path.duplicate()
			_check(turn_manager.submit_order(tank.unit_id,
				{"type": "move", "path": submitted_test_path}, true),
				"玩家移动命令应能提交")
			submitted_test_path.clear()
			_check(not turn_manager.player_orders[tank.unit_id].path.is_empty(),
				"清理UI待确认路径不应清空已提交的玩家命令")
			var movement_result: Dictionary = await MovementSystem.execute_move(
				tank.unit_id, movement_path)
			_check(movement_result.success and Vector2i(tank.grid_col, tank.grid_row) == move_target,
				"执行移动后单位逻辑坐标应更新到目标格")
			tank.set_grid_position(start_position.x, start_position.y)

	_check(main.briefing_panel != null, "关卡开场应显示任务简报")
	if main.briefing_panel != null:
		main._on_briefing_start_pressed()
		_check(main.briefing_panel == null, "任务简报应能关闭")

	var fogged_unit = get_tree().get_first_node_in_group("units") as UnitBase
	_check(fogged_unit != null and fogged_unit.has_meta("base_vision_range"), "雾效应保存基础视野")
	if fogged_unit != null:
		main._on_round_event_triggered("fog_lifts", {"description": "测试：雾散"})
		_check(fogged_unit.vision_range == int(fogged_unit.get_meta("base_vision_range")), "雾散应恢复视野")

	var before_units := get_tree().get_nodes_in_group("units").size()
	main._on_round_event_triggered("ah64_arrives", {"description": "测试：增援"})
	_check(get_tree().get_nodes_in_group("units").size() == before_units + 1, "AH-64事件应生成一支增援")

	main._on_round_event_triggered("emi_rise", {"description": "测试：EMI", "emi_delta": 0.05})
	_check(is_equal_approx(emi_system.current_intensity, 0.05), "EMI事件应立即增加5%")

	# 玩家显式攻击命令必须真正结算，且无论命中与否只消耗一发弹药。
	var attacker := _get_unit_by_id(1004)
	var target := _get_unit_by_id(1012)
	target.set_grid_position(4, 8)
	_check(attacker.can_attack_target(target.grid_col, target.grid_row), "相邻敌军应可被直接攻击")
	var ammo_before := attacker.current_ammo
	_check(turn_manager.submit_order(attacker.unit_id, {
		"type": "attack", "target_col": target.grid_col, "target_row": target.grid_row,
		"attack_type": CombatSystem.AttackType.DIRECT_FIRE}, true), "计划阶段应接受玩家攻击命令")
	var explicit_attackers: Array = turn_manager._execute_explicit_attacks()
	_check(attacker.unit_id in explicit_attackers, "显式攻击单位应从随后自动接敌中排除")
	_check(attacker.current_ammo == ammo_before - 1, "直接攻击无论命中与否都应消耗一发弹药")

	# 存档必须恢复战场单位和回合，而不只是战役外围数据。
	var saved_unit := get_tree().get_first_node_in_group("units") as UnitBase
	var saved_unit_id := saved_unit.unit_id
	saved_unit.current_health = 42.0
	turn_manager.current_turn = 3
	GameManager.save_game(99)
	_check(GameManager.has_save(99), "测试存档应写入成功")
	saved_unit.current_health = 7.0
	turn_manager.current_turn = 1
	_check(GameManager.load_game(99), "测试存档应能读取")
	_check(GameManager.apply_pending_save(main), "测试存档应能应用到当前战场")
	var restored_unit := _get_unit_by_id(saved_unit_id)
	_check(restored_unit != null and is_equal_approx(restored_unit.current_health, 42.0), "读取后应恢复单位生命值")
	_check(turn_manager.current_turn == 3, "读取后应恢复当前回合")
	var morale_keys_are_int := true
	for stored_id in MoraleSystem.unit_morale.keys():
		if not stored_id is int:
			morale_keys_are_int = false
			break
	_check(morale_keys_are_int, "读取存档后士气字典的单位ID应恢复为整数")
	# 回归检查：此前存档读取后在回合结算时会把String ID传给整数接口并报错。
	MoraleSystem.tick_turn(turn_manager.current_turn)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_99.json"))

	turn_manager.current_turn = 7
	turn_manager.register_turn_event(7, {"id": "stale", "phase": "turn_start"})
	turn_manager.reset_for_level(8)
	_check(turn_manager.current_turn == 1, "重置后应回到第1回合")
	_check(turn_manager.turn_events.is_empty(), "重置后不应保留旧事件")

	victory_manager.wp_command_destroyed = true
	var result: Dictionary = victory_manager.check_victory_now()
	_check(result.game_over and result.winner == UnitBase.Faction.NATO, "华约指挥单位被毁应立即判负")

	if _failures.is_empty():
		print("[SMOKE TEST] PASS (%d checks)" % 33)
		get_tree().quit(0)
		return

	push_error("[SMOKE TEST] FAIL: %d check(s) failed\n- %s" % [
		_failures.size(), "\n- ".join(_failures)])
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)


func _get_unit_by_id(unit_id: int) -> UnitBase:
	for unit in get_tree().get_nodes_in_group("units"):
		if unit is UnitBase and unit.unit_id == unit_id:
			return unit
	return null
