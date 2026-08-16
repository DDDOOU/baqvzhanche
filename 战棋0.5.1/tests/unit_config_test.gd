extends Node


func _ready() -> void:
	var failures: Array[String] = []
	if not UnitDatabase.is_external_config_loaded():
		failures.append("external unit config should be loaded")
	if UnitDatabase.get_external_config_count() != 23:
		failures.append("external unit config should contain 23 units")
	var tank := UnitDatabase.get_unit_stats(UnitBase.UnitType.T72B_TANK)
	if int(tank.get("health", 0)) != 150:
		failures.append("T-72B health should come from JSON")
	if int(tank.get("initiative", 0)) != 3:
		failures.append("T-72B initiative should be 3")
	if String(tank.get("trait_name", "")) != "装甲突击":
		failures.append("T-72B trait should be loaded")
	var apache := UnitDatabase.get_unit_stats(UnitBase.UnitType.AH64_HELICOPTER)
	if not bool(apache.get("can_move_after_attack", false)):
		failures.append("AH-64 should be able to move after attacking")

	if failures.is_empty():
		print("[UNIT CONFIG TEST] PASS (6 checks)")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error("[UNIT CONFIG TEST] %s" % failure)
		get_tree().quit(1)
