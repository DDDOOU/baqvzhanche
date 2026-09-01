extends Node

var checks := 0
var failures: Array[String] = []


func _ready() -> void:
	var packed := load("res://scenes/MainMenu.tscn") as PackedScene
	_check(packed != null, "主菜单场景应可加载")
	if packed == null:
		_finish()
		return

	var menu := packed.instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame

	var foreground := menu.cover_background as TextureRect
	_check(foreground != null, "应创建单一封面层")
	_check(menu.get_node_or_null("CoverBackdrop") == null,
		"主菜单不应再叠加暗化封面副本")
	if foreground != null:
		_assert_layout(menu, foreground, Vector2(1280, 720))
		_assert_layout(menu, foreground, Vector2(1024, 768))
		_assert_layout(menu, foreground, Vector2(1920, 720))

	_check(menu.startup_credits != null and menu.startup_credits.visible,
		"Godot启动画面后应先显示制作组名单")
	_check(not menu.start_panel.visible,
		"制作组名单播放期间不得叠加主菜单按钮")
	if menu.startup_credits != null:
		_check(menu.startup_credits.contains_credit_text("八 区 战 车"),
			"制作组名单应显示八区战车")
		_check(menu.startup_credits.contains_credit_text("窦英杰"),
			"制作组名单应包含制作人")
		_check(menu.startup_credits.contains_credit_text("音乐，音效，特效制作和设计"),
			"制作组名单应包含完整岗位信息")
		menu.startup_credits.finish_now()
		await get_tree().process_frame
		_check(menu.startup_credits == null and menu.start_panel.visible,
			"名单结束后应自动进入现有主菜单")

	menu.queue_free()
	await get_tree().process_frame
	_finish()


func _assert_layout(menu: Control, foreground: TextureRect, viewport_size: Vector2) -> void:
	menu._apply_cover_layout(viewport_size)
	var epsilon := 0.6
	_check(foreground.position.distance_to(Vector2.ZERO) <= epsilon,
		"封面必须从窗口左上角开始显示")
	_check(foreground.size.distance_to(viewport_size) <= epsilon,
		"封面尺寸必须与整个窗口完全一致")
	_check(foreground.position.x + foreground.size.x >= viewport_size.x - epsilon,
		"封面必须铺满窗口右侧")
	_check(foreground.position.y + foreground.size.y >= viewport_size.y - epsilon,
		"封面必须铺满窗口底部")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("[MAIN MENU COVER TEST] PASS (%d checks)" % checks)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("[MAIN MENU COVER TEST] FAIL: %s" % failure)
	get_tree().quit(1)
