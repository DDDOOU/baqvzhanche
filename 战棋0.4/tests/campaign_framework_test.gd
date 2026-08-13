extends Node

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for level_id in range(2, 10):
		var path := "res://scenes/levels/level_%02d.tscn" % (level_id + 1)
		_check(ResourceLoader.exists(path), "第%d关应存在场景文件" % (level_id + 1))
		var scene := (load(path) as PackedScene).instantiate()
		get_tree().root.add_child(scene)
		var terrain := scene.get_node_or_null("Terrain（地块）") as TileMapLayer
		_check(terrain != null and terrain.get_used_rect().size == Vector2i(20, 12), "第%d关应生成20×12地形" % (level_id + 1))
		var level = LevelDatabase.get_level(level_id)
		_check(level.wp_units.size() > 0 and level.nato_units.size() > 0, "第%d关双方都应有初始单位" % (level_id + 1))
		_check(level.wp_spawn.size() > 0 and level.nato_spawn.size() > 0, "第%d关双方都应有增援点" % (level_id + 1))
		_check(_has_unit_at(level.wp_units, level.wp_command_center), "第%d关华约指挥坐标应有单位" % (level_id + 1))
		_check(_has_unit_at(level.nato_units, level.nato_command_center), "第%d关北约指挥坐标应有单位" % (level_id + 1))
		_check(_unit_positions_valid_and_unique(level), "第%d关单位坐标应有效且不重叠" % (level_id + 1))
		scene.free()

	# 用最终关完整启动，覆盖地图提取、单位生成、EMI、AI与胜负绑定。
	var main := (load("res://scenes/MainScene.tscn") as PackedScene).instantiate()
	main.startup_level_id = 9
	get_tree().root.add_child(main)
	await get_tree().create_timer(3.5).timeout
	# 0.5.3 起 LEVEL_INTRO 等待玩家点击"开始行动"——测试模拟确认进入计划阶段
	GameManager.confirm_intro()
	await get_tree().create_timer(0.3).timeout
	_check(GameManager.current_level_id == 9, "应完整启动第10关")
	_check(GridManager.MAP_WIDTH == 20 and GridManager.MAP_HEIGHT == 12, "第10关运行时地图尺寸应正确")
	_check(get_tree().get_nodes_in_group("units").size() == 25, "第10关应生成13支华约与12支北约单位")
	_check(is_equal_approx(EMISystem.current_intensity, 1.0), "第10关应从100% EMI开始")
	_check(VictoryManager.wp_command_unit_id >= 0 and VictoryManager.nato_command_unit_id >= 0, "第10关双方指挥单位应绑定")

	if _failures.is_empty():
		print("[CAMPAIGN FRAMEWORK TEST] PASS (%d checks)" % _checks)
		get_tree().quit(0)
		return
	push_error("[CAMPAIGN FRAMEWORK TEST] FAIL: %d check(s) failed\n- %s" % [_failures.size(), "\n- ".join(_failures)])
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _has_unit_at(configs: Array, pos: Vector2i) -> bool:
	for cfg in configs:
		if Vector2i(int(cfg.col), int(cfg.row)) == pos:
			return true
	return false


func _unit_positions_valid_and_unique(level) -> bool:
	var occupied := {}
	for cfg in level.wp_units + level.nato_units:
		var pos := Vector2i(int(cfg.col), int(cfg.row))
		if pos.x < 0 or pos.y < 0 or pos.x >= level.map_width or pos.y >= level.map_height:
			return false
		var key := "%d,%d" % [pos.x, pos.y]
		if occupied.has(key):
			return false
		occupied[key] = true
	return true
