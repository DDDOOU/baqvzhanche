extends Node

var _failures: Array[String] = []


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
	_check(main.get_children().find(main.fog_renderer) > main.get_children().find(main.unit_renderer) \
		and main.fog_renderer.z_index > main.unit_renderer.z_index,
		"战争迷雾实体层应位于单位层之上")
	_check(main.background_renderer != null and main.background_renderer.z_index < 0
		and main.background_renderer.get_theme_id() == 0
		and main.background_renderer.background_texture != null,
		"每关应有位于棋盘底层的独立战场背景")
	_check(main.command_bar != null and main.command_row != null
		and main.command_row.get_child_count() == 6,
		"指挥操作应收敛到响应式工具栏")
	_check(main.battle_log_ui != null and not main.battle_log_ui.is_expanded,
		"战报默认应收起为最新事件，优先保留战场视野")
	_check(main._is_pointer_over_button(main.battle_log_toggle_button.get_global_rect().get_center()),
		"战报按钮应被识别为HUD控件，不得被地图拖拽输入截获")
	main.battle_log_toggle_button.pressed.emit()
	await get_tree().create_timer(0.25).timeout
	_check(main.battle_log_ui.is_expanded and main.battle_log_toggle_button.text == "收起",
		"点击战报按钮应展开战报并同步按钮文字")
	main.battle_log_toggle_button.pressed.emit()
	await get_tree().create_timer(0.25).timeout
	_check(not main.battle_log_ui.is_expanded and main.battle_log_toggle_button.text == "战报",
		"再次点击战报按钮应收起战报并恢复按钮文字")
	main.battle_log_ui.set_expanded(true)
	await get_tree().create_timer(0.25).timeout
	_check(main.battle_log_ui.is_expanded, "战报应能展开完整记录")
	main.battle_log_ui.set_expanded(false)
	main._set_card_panel_open(true)
	await get_tree().create_timer(0.40).timeout
	_check(main.card_ui.is_panel_open and main.card_ui.is_panel_rendered
		and is_zero_approx(main.card_ui.panel_offset_y),
		"卡牌栏应在展开动画后进入可交互位置")
	var card_size: Vector2 = main.card_ui._get_card_size()
	var center_card_index := int(CardSystem.hand.size() / 2)
	var center_layout: Dictionary = main.card_ui._get_card_layout(center_card_index, CardSystem.hand.size(), card_size)
	var edge_layout: Dictionary = main.card_ui._get_card_layout(0, CardSystem.hand.size(), card_size)
	_check(float(center_layout.center.y) < float(edge_layout.center.y)
		and absf(float(edge_layout.rotation)) > 0.0,
		"手牌应形成中间上拱、两侧倾斜的弧线布局")
	main.card_ui.hovered_card_index = center_card_index
	main.card_ui.hover_visual_lift = CardUI.CARD_HOVER_LIFT
	var hover_layout: Dictionary = main.card_ui._get_card_layout(center_card_index, CardSystem.hand.size(), card_size)
	_check(float(hover_layout.scale) > 1.0 and float(hover_layout.center.y) < float(center_layout.center.y),
		"鼠标悬停的卡牌应上抬并放大突出显示")
	main.card_ui.hovered_card_index = -1
	main.card_ui.hover_visual_lift = 0.0
	var bottom_ui_top: float = main._get_bottom_ui_top()
	_check(main.action_hint_panel.get_global_rect().end.y <= bottom_ui_top - 7.0,
		"行动提示应位于卡牌说明栏之上，不得与卡牌底部区域重叠")
	main._set_hover_info("测试单位\n坐标 (20,29)", Vector2(
		main.get_viewport_rect().size.x * 0.5, bottom_ui_top - 4.0))
	var hover_safe_top: float = main.action_hint_panel.get_global_rect().position.y - 7.0 \
		if main.action_hint_panel.visible else bottom_ui_top - 7.0
	_check(main.hover_info_panel.get_global_rect().end.y <= hover_safe_top,
		"地图悬浮信息应避开行动提示与卡牌区域")
	main._set_hover_info("", Vector2.ZERO)
	main._set_card_panel_open(false)
	await get_tree().create_timer(0.20).timeout
	_check(not main.card_ui.visible and not main.card_ui.is_panel_rendered,
		"卡牌栏收起动画结束后应释放战场空间")
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
	var visible_initiative_cards := 0
	for button in main.initiative_bar.unit_buttons.values():
		if (button as Button).visible:
			visible_initiative_cards += 1
	_check(visible_initiative_cards <= InitiativeBar.MAX_VISIBLE_CARDS,
		"顶部行动条应仅显示一个紧凑的六格行动窗口")
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
		main.initiative_bar.set_active_unit(tank.unit_id)
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

	_check(main.briefing_panel != null, "关卡开场应显示任务简报")
	if main.briefing_panel != null:
		main._on_briefing_start_pressed()
		_check(main.briefing_panel == null, "任务简报应能关闭")

	var fogged_unit = get_tree().get_first_node_in_group("units") as UnitBase
	_check(fogged_unit != null and fogged_unit.has_meta("base_vision_range"), "雾效应保存基础视野")
	_check(FogOfWar.enabled, "第1关应启用战争迷雾")
	if fogged_unit != null:
		var friendly_cell = GridManager.get_cell(fogged_unit.grid_col, fogged_unit.grid_row)
		_check(friendly_cell != null and friendly_cell.is_visible and friendly_cell.is_explored,
			"己方单位所在格应在当前视野内且已探索")
	var distant_enemy := _get_unit_by_id(1011)
	if distant_enemy != null:
		var enemy_cell = GridManager.get_cell(distant_enemy.grid_col, distant_enemy.grid_row)
		_check(enemy_cell != null and not enemy_cell.is_visible and not enemy_cell.is_explored,
			"远端敌军所在格开局应保持未探索黑雾")
		_check(not FogOfWar.is_unit_visible(distant_enemy), "不可见敌军不应暴露给玩家")
		if enemy_cell != null:
			enemy_cell.is_explored = true
			FogOfWar.refresh()
			_check(not enemy_cell.is_visible and enemy_cell.is_explored,
				"离开视野的已探索格应保留灰雾状态")
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
		print("[SMOKE TEST] PASS (%d checks)" % 99)
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
