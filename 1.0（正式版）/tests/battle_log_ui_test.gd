extends Node

var failures: Array[String] = []


func _ready() -> void:
	var ui := BattleLogUI.new()
	get_tree().root.add_child.call_deferred(ui)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(ui.log_label != null and ui.log_label.visible, "战报默认展开")
	_check(ui.toggle_button != null and ui.toggle_button.visible, "战报提供收起按钮")
	ui.toggle_button.pressed.emit()
	await get_tree().process_frame
	_check(ui.is_collapsed and not ui.log_label.visible, "点击后收起战报")
	_check(ui.toggle_button.visible, "收起后保留展开按钮")
	_check(ui.toggle_button.position.x + ui.toggle_button.size.x <= get_viewport().get_visible_rect().size.x,
		"展开按钮保持在屏幕右侧范围内")
	ui.toggle_button.pressed.emit()
	await get_tree().process_frame
	_check(not ui.is_collapsed and ui.log_label.visible, "再次点击展开战报")
	ui.queue_free()

	if failures.is_empty():
		print("[BATTLE LOG UI TEST] PASS (6 checks)")
		get_tree().quit(0)
	else:
		for message in failures:
			push_error("[BATTLE LOG UI TEST] %s" % message)
		print("[BATTLE LOG UI TEST] FAIL (%d)" % failures.size())
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
