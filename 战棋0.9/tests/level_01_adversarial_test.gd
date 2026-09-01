extends Node

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	get_tree().create_timer(55.0).timeout.connect(_on_watchdog_timeout)
	_run.call_deferred()


func _run() -> void:
	print("[LEVEL 01 ADVERSARIAL TEST] starting")
	seed(1987)
	GameManager.tutorial_done = false
	var packed := load("res://scenes/MainScene.tscn") as PackedScene
	var main = packed.instantiate()
	main.startup_level_id = 0
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(GameManager.current_state == GameManager.GameState.LEVEL_INTRO,
		"第一关应先停留在开场叙事，不应绕过简报直接计时")
	_check(main.intro_story_layer != null, "第一关应显示战前剧情")
	for level_id in range(10):
		var level_data = LevelDatabase.get_level(level_id)
		_check(level_data != null and not level_data.core_mechanics.is_empty(),
			"每一关都必须提供开场和HUD共用的核心机制说明: %d" % (level_id + 1))
	_check(_tree_contains_text(main.intro_story_layer, "本关核心机制")
		and _tree_contains_text(main.intro_story_layer, "晨雾"),
		"第一关开场字幕必须提醒晨雾等核心机制")
	main._on_opening_story_next_pressed()
	await get_tree().process_frame
	_check(main.mission_briefing_layer != null, "战前剧情后应显示任务要求")
	_check(_tree_contains_text(main.mission_briefing_layer, "核心胜利条件")
		and _tree_contains_text(main.mission_briefing_layer, "守住3个VP格中至少2个"),
		"任务要求界面必须高亮第一关核心胜利条件")
	main._on_mission_briefing_start_pressed()
	_check(await _wait_for_state(GameManager.GameState.PLANNING_PHASE, 2.0),
		"点击开始行动后应进入计划阶段")
	_check(main.victory_progress_label != null
		and "核心胜利条件" in main.victory_progress_label.text
		and "本关机制" in main.victory_progress_label.text,
		"进入战斗后左侧文字区必须持续显示胜利条件与特殊机制")
	_check(main.victory_progress_toggle_button != null
		and main.victory_progress_toggle_button.visible,
		"左侧目标文字必须提供收起和展开按钮")
	main._on_victory_progress_toggle_pressed()
	_check(not main.victory_progress_label.visible
		and main.victory_progress_toggle_button.text == "展开目标",
		"收起目标后应保留一个可重新展开的小按钮")
	main._on_victory_progress_toggle_pressed()
	_check(main.victory_progress_label.visible,
		"再次点击后应恢复目标与特殊机制文字")
	_check(_battle_log_contains("【核心胜利条件】") and _battle_log_contains("【本关机制】"),
		"右侧战报必须保留本关目标与特殊机制供玩家回看")
	main.tile_grid._rebuild_marker_cache()
	for vp in GridManager.vp_cells:
		_check(main.tile_grid.marker_cells.get("%d,%d" % [vp.x, vp.y], -1)
			== GridManager.CellMarker.VP_POINT,
			"每个VP格都必须登记为地图旗帜标记: %s" % vp)

	var units := get_tree().get_nodes_in_group("units")
	_check(units.size() == 18, "第一关应生成18支初始单位")
	var occupied: Dictionary = {}
	for node in units:
		var unit := node as UnitBase
		var key := "%d,%d" % [unit.grid_col, unit.grid_row]
		_check(not occupied.has(key), "初始单位不应重叠在同一格: %s" % key)
		occupied[key] = true
		var cell = GridManager.get_cell(unit.grid_col, unit.grid_row)
		_check(cell != null and cell.occupant_unit == unit,
			"单位与网格占用记录必须一致: %s" % unit.unit_name)
		_check(cell != null and cell.is_passable_for(TilePathfinding.is_armored(unit)),
			"初始单位不应生成在不可通行格: %s" % unit.unit_name)

	for building in main.level_buildings:
		if not building.blocks_movement:
			continue
		for pos in building.get_occupied_cells():
			var cell = GridManager.get_cell(pos.x, pos.y)
			_check(cell != null and not cell.is_passable_for(false),
				"建筑占地必须保持不可通行: %s %s" % [building.building_name, pos])

	var mover := _get_unit(1004)
	var path: Array = []
	if mover != null:
		for target in TilePathfinding.get_reachable_cells(mover):
			path = TilePathfinding.find_path(mover.grid_col, mover.grid_row,
				target.x, target.y, mover, mover.get_effective_movement())
			if not path.is_empty():
				break
	_check(mover != null and not path.is_empty(), "玩家坦克应至少能规划到一个相邻空格")
	var expected_move_target: Vector2i = path[-1] if not path.is_empty() else Vector2i(-1, -1)
	if mover != null and not path.is_empty():
		_check(TurnManager.submit_order(mover.unit_id, {"type": "move", "path": path}, true),
			"玩家移动命令应能提交")

	var enemy := _get_unit(1011)
	var command_unit := _get_unit(1001)
	if command_unit != null:
		var smoke_key := "%d,%d" % [command_unit.grid_col, command_unit.grid_row]
		CombatSystem.smoke_cells[smoke_key] = 1
		_check(not main.unit_renderer.is_unit_visually_faded(command_unit),
			"烟雾可悬停虚化后，烟雾格中的单位模型应保持正常不透明度")
		CombatSystem.smoke_cells.erase(smoke_key)
		_check(not main.unit_renderer.is_unit_visually_faded(command_unit),
			"烟雾消散后单位仍应保持正常显示")

	if mover != null:
		var reachable_before_fog_change := TilePathfinding.get_reachable_cells(mover)
		var visibility_snapshot: Dictionary = {}
		for pos in reachable_before_fog_change:
			var move_cell = GridManager.get_cell(pos.x, pos.y)
			visibility_snapshot[pos] = move_cell.is_visible
			move_cell.is_visible = false
		var reachable_inside_fog := TilePathfinding.get_reachable_cells(mover)
		_check(_same_cell_set(reachable_before_fog_change, reachable_inside_fog),
			"玩家单位移动范围不应因地块进入战争迷雾而改变")
		if not reachable_before_fog_change.is_empty():
			_check(main.tile_grid._can_draw_movement_overlay(reachable_before_fog_change[0]),
				"迷雾中的蓝色移动范围和规划路径仍必须允许绘制")
		for pos in visibility_snapshot:
			GridManager.get_cell(pos.x, pos.y).is_visible = bool(visibility_snapshot[pos])

	if mover != null and enemy != null:
		var enemy_cell = GridManager.get_cell(enemy.grid_col, enemy.grid_row)
		var enemy_was_visible: bool = enemy_cell.is_visible
		enemy_cell.is_visible = false
		_check(not TilePathfinding.occupant_blocks_planned_movement(mover, enemy),
			"未侦察到的敌军不应提前缩小玩家的计划移动范围")
		enemy_cell.is_visible = true
		_check(TilePathfinding.occupant_blocks_planned_movement(mover, enemy),
			"已发现敌军仍应作为不可穿越的动态障碍")
		enemy_cell.is_visible = enemy_was_visible
	var prediction_index := _find_card_index("coordinate_prediction")
	_check(prediction_index >= 0 and enemy != null, "第一关起手应包含坐标预判")
	if prediction_index >= 0 and enemy != null:
		_check(CardSystem.use_card(prediction_index, enemy.grid_col, enemy.grid_row),
			"坐标预判应能标记敌军所在格")
		_check(is_equal_approx(CardSystem.get_prediction_buff(enemy.grid_col, enemy.grid_row), 0.30),
			"坐标预判必须在本次演绎开始前生效")

	var fortify_index := _find_card_index("fortify_position")
	_check(fortify_index >= 0 and command_unit != null, "第一关起手应包含阵地加固")
	if fortify_index >= 0 and command_unit != null:
		_check(CardSystem.use_card(fortify_index, command_unit.grid_col, command_unit.grid_row),
			"阵地加固应能用于己方单位所在格")
		_check(is_equal_approx(CardSystem.get_fortify_buff(command_unit.grid_col, command_unit.grid_row), 0.50),
			"阵地加固必须在本次演绎开始前提供减伤")
		_check(command_unit.remaining_movement == 0,
			"被加固单位本回合必须不能移动")

	var smoke_index := _find_card_index("smoke_screen")
	_check(smoke_index >= 0, "第一关起手应包含烟雾遮障")
	if smoke_index >= 0:
		_check(CardSystem.use_card(smoke_index, 20, 20), "烟雾遮障应能标记有效地图格")
		_check(CardSystem.pending_card_effects.size() == 1,
			"演绎前应只保留烟雾这一项延迟结算效果")

	# 额外验证同一结算时序的高风险卡：伤害加成必须先应用，生命代价必须战后结算。
	var sacrifice_health_before := command_unit.current_health if command_unit != null else 0.0
	_check(CardSystem.grant_card("sacrifice_charge"), "测试应能加入牺牲冲锋")
	var sacrifice_index := _find_card_index("sacrifice_charge")
	if sacrifice_index >= 0 and command_unit != null:
		_check(CardSystem.use_card(sacrifice_index, command_unit.grid_col, command_unit.grid_row),
			"牺牲冲锋应能指定己方单位")
		_check(is_equal_approx(CardSystem.get_sacrifice_buff(command_unit.unit_id), 1.5),
			"牺牲冲锋伤害加成必须在本次演绎前生效")
		_check(is_equal_approx(command_unit.current_health, sacrifice_health_before),
			"牺牲冲锋不得在单位行动前提前扣除生命")

	# 暂停保存发生在计划阶段时，已经使用的卡牌效果不能在读档后丢失。
	var saved_card_state = JSON.parse_string(JSON.stringify(CardSystem.serialize())) as Dictionary
	CardSystem.pending_card_effects.clear()
	CardSystem.prediction_buffs.clear()
	CardSystem.fortify_buffs.clear()
	CardSystem.sacrifice_buffs.clear()
	CardSystem.sacrifice_aftereffects.clear()
	CardSystem.deserialize(saved_card_state)
	_check(not CardSystem.hand.is_empty() and not CardSystem.hand[0].card_name.is_empty()
		and not CardSystem.hand[0].data.is_empty(),
		"读档后的卡牌必须恢复名称、费用、描述与规则数据")
	_check(CardSystem.pending_card_effects.size() == 1,
		"读档后应恢复尚未结算的烟雾标记")
	_check(enemy != null and is_equal_approx(
		CardSystem.get_prediction_buff(enemy.grid_col, enemy.grid_row), 0.30),
		"读档后应恢复坐标预判")
	_check(command_unit != null and is_equal_approx(
		CardSystem.get_fortify_buff(command_unit.grid_col, command_unit.grid_row), 0.50),
		"读档后应恢复阵地加固")
	_check(command_unit != null and is_equal_approx(
		CardSystem.get_sacrifice_buff(command_unit.unit_id), 1.5),
		"读档后应恢复牺牲冲锋")

	GameManager.finish_planning_early()
	print("[LEVEL 01 ADVERSARIAL TEST] execution started")
	_check(GameManager.current_state == GameManager.GameState.EXECUTION_PHASE,
		"提前结束计划应进入演绎阶段")
	GameManager.finish_execution_early()
	_check(GameManager.current_state == GameManager.GameState.EXECUTION_PHASE,
		"跳过演绎不得中断尚未完成的单位行动")
	_check(await _wait_for_state(GameManager.GameState.PLANNING_PHASE, 40.0),
		"第一回合演绎完成后应进入第二回合计划阶段")
	_check(TurnManager.current_turn == 2, "完整演绎后回合数应推进到2")
	if mover != null and expected_move_target.x >= 0:
		_check(Vector2i(mover.grid_col, mover.grid_row) == expected_move_target,
			"已确认的玩家移动命令必须真正执行到目标格")
	_check(TurnManager.player_orders.is_empty(), "新回合不应残留上一回合玩家命令")
	_check(CardSystem.pending_card_effects.is_empty(), "演绎完成后延迟卡牌队列应清空")
	_check(CardSystem.prediction_buffs.is_empty(), "本回合坐标预判应在结算后清除")
	_check(CardSystem.fortify_buffs.is_empty(), "本回合阵地加固应在结算后清除")
	_check(CardSystem.sacrifice_buffs.is_empty(), "牺牲冲锋伤害加成应在战后清除")
	if command_unit != null:
		_check(is_equal_approx(command_unit.current_health, sacrifice_health_before * 0.5),
			"牺牲冲锋应在单位完成行动后扣除50%当前生命")
	_check(CombatSystem.smoke_cells.size() == 16,
		"烟雾应保留到下一回合，而不是生成后立即消失")

	occupied.clear()
	for node in get_tree().get_nodes_in_group("units"):
		var unit := node as UnitBase
		if not unit.is_alive:
			continue
		var key := "%d,%d" % [unit.grid_col, unit.grid_row]
		_check(not occupied.has(key), "演绎后单位不应重叠: %s" % key)
		occupied[key] = true

	if _failures.is_empty():
		print("[LEVEL 01 ADVERSARIAL TEST] PASS (%d checks)" % _checks)
		get_tree().quit(0)
		return
	push_error("[LEVEL 01 ADVERSARIAL TEST] FAIL: %d check(s) failed\n- %s" % [
		_failures.size(), "\n- ".join(_failures)])
	get_tree().quit(1)


func _on_watchdog_timeout() -> void:
	push_error("[LEVEL 01 ADVERSARIAL TEST] FAIL: watchdog timeout")
	get_tree().quit(2)


func _wait_for_state(expected: int, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if GameManager.current_state == expected:
			return true
		await get_tree().process_frame
	return GameManager.current_state == expected


func _find_card_index(card_id: String) -> int:
	for index in range(CardSystem.hand.size()):
		if CardSystem.hand[index].card_id == card_id:
			return index
	return -1


func _get_unit(unit_id: int) -> UnitBase:
	for node in get_tree().get_nodes_in_group("units"):
		if node is UnitBase and node.unit_id == unit_id:
			return node
	return null


func _tree_contains_text(root: Node, needle: String) -> bool:
	if root == null:
		return false
	if root is Label or root is RichTextLabel or root is Button:
		if needle in String(root.text):
			return true
	for child in root.get_children():
		if _tree_contains_text(child, needle):
			return true
	return false


func _battle_log_contains(needle: String) -> bool:
	for entry in BattleLog.logs:
		if needle in String(entry.get("text", "")):
			return true
	return false


func _same_cell_set(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	var right_set: Dictionary = {}
	for position in right:
		right_set[position] = true
	for position in left:
		if not right_set.has(position):
			return false
	return true


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
