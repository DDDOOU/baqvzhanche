extends Node

var failures: Array[String] = []


func _ready() -> void:
	var unit_type := UnitBase.UnitType.T72B_TANK
	var official := UnitDatabase.get_official_unit_stats(unit_type)
	_check(not official.is_empty(), "T-72B 官方配置存在")
	_check(UnitDatabase.get_player_editable_fields().size() == 9, "开放九项基础属性")
	_check(UnitDatabase.get_configurable_unit_types().size() == 23, "配置界面列出23种单位")

	var original_health := float(official.get("health", 0.0))
	var changed := UnitDatabase.set_player_unit_overrides(unit_type, {"health": original_health + 25.0})
	_check(changed, "玩家配置保存成功")
	_check(is_equal_approx(float(UnitDatabase.get_unit_stats(unit_type).get("health", 0.0)), original_health + 25.0), "玩家值覆盖实际属性")
	_check(is_equal_approx(float(UnitDatabase.get_official_unit_stats(unit_type).get("health", 0.0)), original_health), "官方基准未被修改")

	var reset := UnitDatabase.reset_player_unit_overrides(unit_type)
	_check(reset, "恢复默认保存成功")
	_check(is_equal_approx(float(UnitDatabase.get_unit_stats(unit_type).get("health", 0.0)), original_health), "恢复后使用官方属性")

	var screen := UnitConfigScreen.new()
	screen.menu_font = SystemFont.new()
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(screen.unit_list.item_count == 23, "界面显示全部23种单位")
	var scrollbar := screen.unit_list.get_v_scroll_bar()
	_check(scrollbar.max_value > scrollbar.page, "单位列表提供可拖动纵向滚动条")
	screen.queue_free()

	if failures.is_empty():
		print("[PLAYER UNIT CONFIG TEST] PASS (10 checks)")
		get_tree().quit(0)
	else:
		for message in failures:
			push_error("[PLAYER UNIT CONFIG TEST] %s" % message)
		print("[PLAYER UNIT CONFIG TEST] FAIL (%d)" % failures.size())
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
