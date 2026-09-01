extends Node

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(1987)
	var packed := load("res://scenes/MainScene.tscn") as PackedScene
	var main = packed.instantiate()
	get_tree().root.add_child(main)
	# 初始演绎会让18个行动槽各展示至少0.5秒，等待其完整进入计划阶段。
	await get_tree().create_timer(12.0).timeout
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
	var light_tank_sheet := load("res://assets/units/animated/wp_light_tank_target_4dir_4f.png") as Texture2D
	_check(light_tank_sheet != null and light_tank_sheet.get_size() == Vector2(128, 128),
		"轻型坦克应使用与建筑层像素密度一致的128×128原生母版")
	var light_tank_attack_sheet := load("res://assets/units/animated/wp_light_tank_attack_4dir_4f.png") as Texture2D
	_check(light_tank_attack_sheet != null and light_tank_attack_sheet.get_size() == Vector2(128, 128),
		"轻型坦克攻击图集应为四方向乘四帧的128×128图集")
	var muzzle_flash_sheet := load("res://assets/effects/tank_muzzle_flash_4f.png") as Texture2D
	_check(muzzle_flash_sheet != null and muzzle_flash_sheet.get_size() == Vector2(128, 32),
		"炮口火光应为横向四帧的128×32图集")
	_check(main.unit_renderer.animated_unit_sheets.size() == UnitBase.UnitType.size(),
		"全部25种单位类型都应加载独立的128×128动作图集")
	for unit_type in UnitBase.UnitType.values():
		var animation_config: Dictionary = main.unit_renderer.animated_unit_sheets.get(unit_type, {})
		var move_sheet := load(String(animation_config.get("path", ""))) as Texture2D
		var attack_sheet := load(String(animation_config.get("attack_path", ""))) as Texture2D
		var effect_sheet := load(String(animation_config.get("muzzle_flash_path", ""))) as Texture2D
		_check(move_sheet != null and move_sheet.get_size() == Vector2(128, 128)
			and attack_sheet != null and attack_sheet.get_size() == Vector2(128, 128)
			and effect_sheet != null and effect_sheet.get_size() == Vector2(128, 32),
			"单位类型%d的移动、攻击和复用特效尺寸应严格正确" % unit_type)
	_check(main.unit_renderer._direction_row_from_step(Vector2i(1, 0)) == 0
		and main.unit_renderer._direction_row_from_step(Vector2i(0, 1)) == 1
		and main.unit_renderer._direction_row_from_step(Vector2i(-1, 0)) == 2
		and main.unit_renderer._direction_row_from_step(Vector2i(0, -1)) == 3,
		"坦克序列帧应正确映射地图四方向")
	_check(main.unit_renderer.get_animation_frame_coords(tank) == Vector2i.ZERO,
		"坦克停止移动时应显示当前方向的待机首帧")
	main.unit_renderer.animated_grid_states[tank.unit_id] = {
		"progress": 0.62, "direction_row": 1,
	}
	_check(main.unit_renderer.get_animation_frame_coords(tank) == Vector2i(2, 1),
		"坦克移动时应按进度播放对应方向的四帧动画")
	main.unit_renderer.animated_grid_states.erase(tank.unit_id)
	var saved_renderer_zoom: float = main.unit_renderer.camera_zoom
	main.unit_renderer.camera_zoom = 0.5
	_check(is_equal_approx(main.unit_renderer.get_animated_visual_zoom(), 0.5),
		"坦克模型应与地图使用同一摄像机缩放比例")
	main.unit_renderer.camera_zoom = saved_renderer_zoom
	_check(tank != null and tank.initiative == int(UnitDatabase.get_unit_stats(UnitBase.UnitType.T72B_TANK).get("initiative", -1)),
		"单位实例的先手值应来自Excel同步配置")
	_check(main.initiative_bar != null and main.initiative_bar.get_ordered_unit_ids().size() == 18,
		"顶部行动顺序条应显示敌我18支初始单位")
	main._on_unit_action_started(tank.unit_id, 0, 18)
	_check(main.unit_renderer.acting_unit == tank,
		"当前行动单位应在地图渲染器中获得独立高亮")
	main._on_unit_action_completed(tank.unit_id, 0, 18)
	_check(main.unit_renderer.acting_unit == null,
		"行动完成后应清除地图行动高亮")
	var initiative_is_sorted := true
	var initiative_ids: Array[int] = main.initiative_bar.get_ordered_unit_ids()
	_check(initiative_ids == turn_manager.get_current_action_order_ids(),
		"顶部显示顺序应与TurnManager实际行动队列完全一致")
	for index in range(1, initiative_ids.size()):
		var previous_unit := _get_unit_by_id(initiative_ids[index - 1])
		var current_unit := _get_unit_by_id(initiative_ids[index])
		if previous_unit == null or current_unit == null or UnitBase.acts_before(current_unit, previous_unit):
			initiative_is_sorted = false
			break
	_check(initiative_is_sorted, "行动顺序条应按先制、速度、单位ID稳定排序")
	var faction_transitions := 0
	for index in range(1, initiative_ids.size()):
		if _get_unit_by_id(initiative_ids[index - 1]).faction != _get_unit_by_id(initiative_ids[index]).faction:
			faction_transitions += 1
	_check(faction_transitions >= 2, "敌我单位应在同一先手队列中交错排列")
	if tank != null:
		var previous_pan: Vector2 = main.camera_pan
		var tank_button := main.initiative_bar.unit_buttons.get(tank.unit_id) as Button
		var pointer_event := InputEventMouseButton.new()
		pointer_event.button_index = MOUSE_BUTTON_LEFT
		pointer_event.pressed = true
		pointer_event.position = tank_button.get_global_rect().get_center()
		main.is_dragging_map = false
		main._input(pointer_event)
		_check(not main.is_dragging_map, "头像框点击不应被地图拖拽输入吞掉")
		tank_button.pressed.emit()
		var viewport_size: Vector2 = main.get_viewport_rect().size
		var expected_focus := Vector2(
			maxf(160.0, (viewport_size.x - 340.0) * 0.5),
			110.0 + maxf(220.0, viewport_size.y - 360.0) * 0.5)
		_check(main.unit_renderer.get_unit_screen_position(tank).distance_to(expected_focus) < 1.0,
			"点击行动顺序卡片后应把摄像机定位到对应单位")
		_check(main.unit_renderer.focused_unit == tank and main.unit_renderer.is_processing(),
			"点击行动顺序卡片后应为对应单位开启呼吸定位环")
		main.camera_pan = previous_pan
		main._apply_camera_transform()
		main.initiative_bar.set_unit_acting(tank.unit_id)
		_check(String(main.initiative_bar.action_states.get(tank.unit_id, "")) == "acting",
			"单位行动中头像框应进入金色脉冲状态")
		main.initiative_bar.set_unit_completed(tank.unit_id, false)
		_check(String(main.initiative_bar.action_states.get(tank.unit_id, "")) == "completed",
			"单位行动完毕头像框应进入勾选变暗状态")
		main.initiative_bar.reset_action_states()
	var executed_action_ids: Array[int] = []
	var capture_action: Callable = func(unit_id: int, _index: int, _total: int) -> void:
		executed_action_ids.append(unit_id)
	turn_manager.unit_action_started.connect(capture_action)
	turn_manager.player_orders.clear()
	turn_manager.ai_orders.clear()
	await turn_manager.start_execution_phase()
	turn_manager.unit_action_started.disconnect(capture_action)
	_check(executed_action_ids == initiative_ids,
		"演算阶段应严格按照敌我统一先手队列逐个执行")
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

	# 第1关使用“开场对白 → 战前剧情 → 任务要求”；第2关沿用两段式开场。
	_check(main.opening_dialogue_layer != null, "第1关应先显示开场对白")
	if main.opening_dialogue_layer != null:
		var opening_dialogue_count: int = LevelDatabase.get_level(0).opening_dialogue.size()
		for _entry_index in range(opening_dialogue_count):
			main._on_opening_dialogue_next_pressed()
		_check(main.opening_dialogue_layer == null, "开场对白应能进入战前剧情")
	_check(main.intro_story_layer != null, "开场对白后应显示战前剧情")
	if main.intro_story_layer != null:
		main._on_opening_story_next_pressed()
		_check(main.intro_story_layer == null, "战前剧情应能进入下一步")
		_check(main.mission_briefing_layer != null, "战前剧情后应显示任务要求")
	if main.mission_briefing_layer != null:
		# 这里只验证界面关闭；不调用开始行动，避免自动回合计时器与后续手动系统测试竞争。
		main._close_mission_briefing_dialog()
		main._set_gameplay_ui_visible(true)
		_check(main.mission_briefing_layer == null, "任务要求应能关闭")

	_check(main.card_effect_renderer.effect_configs.size() == 12,
		"应加载12套正式卡牌地图特效配置")
	_check(main._get_card_effect_cells("call_artillery", Vector2i(5, 5)).size() == 4,
		"呼叫炮击预览应覆盖2×2四格")
	_check(main._get_card_effect_cells("blind_fire_barrage", Vector2i(5, 5)).size() == 9,
		"盲射弹幕预览应覆盖3×3九格")
	_check(main._get_card_effect_cells("smoke_screen", Vector2i(5, 5)).size() == 16,
		"烟雾遮障预览应覆盖4×4十六格")
	_check(main._get_card_effect_cells("sapper_mines", Vector2i(5, 5)).size() == 2,
		"工兵布雷预览应覆盖1×2两格")
	CombatSystem.smoke_cells.clear()
	CombatSystem.apply_smoke(5, 5, 1, 4)
	_check(CombatSystem.smoke_cells.size() == 16, "烟雾数值效果应与4×4动画范围一致")
	CombatSystem.smoke_cells.clear()
	MovementSystem.mine_cells.clear()
	CardSystem._lay_mines_1x2(5, 5)
	_check(MovementSystem.mine_cells.size() == 2, "工兵布雷数值效果应覆盖1×2两格")
	MovementSystem.mine_cells.clear()
	var effect_count_before: int = main.card_effect_renderer.active_effects.size()
	CardSystem.card_effect_resolved.emit("call_artillery", 5, 5)
	_check(main.card_effect_renderer.active_effects.size() == effect_count_before + 1,
		"卡牌结算信号应触发地图特效")
	main.card_effect_renderer.clear_all()
	_check(SoundManager.CARD_EFFECT_SFX.get("call_artillery", "") == "explosion",
		"炮击卡牌应映射爆炸音效")
	_check(SoundManager.CARD_EFFECT_SFX.get("smoke_screen", "") == "card_smoke",
		"烟雾卡牌应映射持续喷放音效")
	CombatSystem.apply_smoke(5, 5, 1, 4)
	_check(main.card_effect_renderer.play_card_effect("smoke_screen", 5, 5),
		"烟雾特效应能直接播放并保持")
	if not main.card_effect_renderer.active_effects.is_empty():
		var hover_effect: Dictionary = main.card_effect_renderer.active_effects[-1]
		var hover_sprite := hover_effect.get("sprite") as Sprite2D
		_check(hover_sprite != null and main.card_effect_renderer._is_screen_point_over_effect(
			hover_effect, hover_sprite.position), "烟雾应能识别鼠标悬停区域")
		main.card_effect_renderer._update_hover_fade_for_point(
			hover_effect, hover_sprite.position, 1.0)
		_check(hover_sprite.self_modulate.a <= 0.19,
			"鼠标悬停烟雾时应明显变淡以看清下方单位")
		main.card_effect_renderer._update_hover_fade_for_point(
			hover_effect, hover_sprite.position + Vector2(5000, 5000), 1.0)
		_check(hover_sprite.self_modulate.a >= 0.99,
			"鼠标移出烟雾后应恢复正常显示")
	main.card_effect_renderer.clear_all()
	CombatSystem.smoke_cells.clear()
	var smoke_effect_state := {
		"config": {"area_width": 4, "area_height": 4},
		"target": Vector2i(5, 5),
	}
	CombatSystem.apply_smoke(5, 5, 1, 4)
	_check(main.card_effect_renderer._persistent_state_exists(smoke_effect_state, "smoke"),
		"烟雾数值存在时应保留烟雾特效")
	CombatSystem.smoke_cells.clear()
	_check(not main.card_effect_renderer._persistent_state_exists(smoke_effect_state, "smoke"),
		"烟雾数值结束后应移除烟雾特效")
	MovementSystem.mine_cells = [Vector2i(4, 5), Vector2i(5, 5)]
	var mine_effect_state := {
		"config": {"area_width": 2, "area_height": 1},
		"target": Vector2i(5, 5),
	}
	_check(main.card_effect_renderer._persistent_state_exists(mine_effect_state, "mines"),
		"雷区仍存在时应保留布雷特效")
	MovementSystem.mine_cells.clear()

	var fogged_unit = get_tree().get_first_node_in_group("units") as UnitBase
	_check(fogged_unit != null and fogged_unit.has_meta("base_vision_range"), "雾效应保存基础视野")
	if fogged_unit != null:
		var base_vision := int(fogged_unit.get_meta("base_vision_range"))
		fogged_unit.vision_range = maxi(1, base_vision - 3)
		var saved_turn := TurnManager.current_turn
		var saved_processed := TurnManager.processed_events.duplicate()
		TurnManager.current_turn = 4
		TurnManager.processed_events.clear()
		TurnManager._trigger_turn_events("turn_start")
		_check(fogged_unit.vision_range == base_vision,
			"第4回合开始事件必须通过真实事件链恢复晨雾视野惩罚")
		_check("fog_lifts" in TurnManager.processed_events,
			"第4回合晨雾消散事件必须被正式触发并登记")
		TurnManager.current_turn = saved_turn
		TurnManager.processed_events = saved_processed

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
	var attack_capture := {"count": 0}
	var capture_attack: Callable = func(attacker_id: int, _target_col: int, _target_row: int, _result: Dictionary):
		if attacker_id == attacker.unit_id:
			attack_capture.count += 1
	CombatSystem.attack_executed.connect(capture_attack)
	await turn_manager._execute_unit_action(attacker)
	CombatSystem.attack_executed.disconnect(capture_attack)
	_check(attack_capture.count == 1, "显式攻击命令在单位行动中应只结算一次")
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
		print("[SMOKE TEST] PASS (%d checks)" % _checks)
		get_tree().quit(0)
		return

	push_error("[SMOKE TEST] FAIL: %d check(s) failed\n- %s" % [
		_failures.size(), "\n- ".join(_failures)])
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(message)


func _get_unit_by_id(unit_id: int) -> UnitBase:
	for unit in get_tree().get_nodes_in_group("units"):
		if unit is UnitBase and unit.unit_id == unit_id:
			return unit
	return null
