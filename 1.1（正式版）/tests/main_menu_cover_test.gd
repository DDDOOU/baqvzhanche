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
	GameManager.startup_sequence_shown_this_session = false
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

	_check(menu.startup_prologue != null and menu.startup_prologue.visible,
		"每次进入游戏都应先显示启动序章")
	_check(SoundManager._current_bgm != "menu",
		"启动字幕与对白期间不应播放主菜单音乐")
	_check(not menu.start_panel.visible,
		"启动序章播放期间不得叠加主菜单按钮")
	if menu.startup_prologue != null:
		var prologue = menu.startup_prologue
		_check(is_equal_approx(prologue.BLACK_HOLD_SECONDS, 2.0),
			"首次启动序章应保持2秒黑屏静默")
		_check(not prologue._noise_player.playing and not prologue._skip_button.visible,
			"2秒黑屏期间不应播放噪声或显示界面文字")
		prologue._show_quote()
		_check(prologue._noise_player.playing and prologue._skip_button.visible,
			"字幕出现后应播放低频电流噪声并允许跳过")
		_check(prologue.contains_text("瞄准式干扰")
			and prologue.contains_text("1993年美国陆军《电子战手册》"),
			"全屏字幕应完整显示电子战手册引文与出处")
		_check(is_equal_approx(prologue.QUOTE_HOLD_SECONDS, 7.0),
			"全屏字幕完整出现后应停留7秒")
		prologue._show_dialogue()
		_check(not prologue._noise_player.playing,
			"进入开场对白后应停止字幕阶段的低频电流噪声")
		_check(prologue.get_dialogue_count() == 29,
			"“启用洪水”开场剧情应包含完整29段指挥所对话")
		_check(prologue.contains_text("西侧前沿哨连续失联"),
			"开场对话应从阿尼娅的前沿哨失联报告开始")
		_check(prologue._portrait_left.texture == CharacterPortraits.ANYA
			and prologue._portrait_left.visible,
			"“启用洪水”首句应显示阿尼娅立绘")
		prologue._advance_dialogue()
		_check(prologue._portrait_left.texture == CharacterPortraits.KARINA,
			"对白切换至卡琳娜时应同步切换立绘")
		_check(CharacterPortraits.get_portrait("列夫森科") == CharacterPortraits.LEVENSKO
			and CharacterPortraits.get_portrait("前沿班长") == CharacterPortraits.SQUAD_LEADER
			and CharacterPortraits.get_portrait("铁砧指挥官") == CharacterPortraits.ANVIL_COMMANDER,
			"五位角色应共用完整的全局立绘映射")
		prologue.finish_now()
		await get_tree().process_frame
		_check(menu.startup_prologue == null,
			"启动序章完成后应关闭独立序章层")
		_check(menu.startup_credits != null and menu.startup_credits.visible,
			"启动序章结束后应继续显示原有制作组名单")
		_check(SoundManager._current_bgm == "menu",
			"启动序章结束后应恢复原有主菜单音乐")
	if menu.startup_credits != null:
		var viewport_size := get_viewport().get_visible_rect().size
		_check(menu.startup_credits.position.distance_to(Vector2.ZERO) < 1.0
			and menu.startup_credits.size.distance_to(viewport_size) < 1.0,
			"制作组名单根界面必须像单位属性配置一样覆盖整个视口")
		var credits_grid := menu.startup_credits.get_node(
			"CreditsCenter/CreditsFrame/CreditsContent/CreditsGridCenter/CreditsGrid") as Control
		var credits_frame := menu.startup_credits.get_node(
			"CreditsCenter/CreditsFrame") as Control
		_check(credits_grid != null
			and credits_frame != null
			and absf(credits_grid.get_global_rect().get_center().x
				- credits_frame.get_global_rect().get_center().x) < 2.0,
			"制作者名单表格必须整体水平居中")
		_check(credits_frame != null
			and credits_frame.get_global_rect().get_center().distance_to(viewport_size * 0.5) < 2.0,
			"制作者名单窗口必须以整个游戏视口为中心")
		var credits_backdrop := menu.startup_credits.get_node("Backdrop") as ColorRect
		_check(credits_backdrop != null and credits_backdrop.color.a <= 0.90,
			"名单背景应提高透明度并隐约显示下方封面")
		_check(menu.startup_credits.get_fade_durations().is_equal_approx(Vector2(0.5, 1.75)),
			"名单应使用0.5秒淡入和1.75秒淡出")
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

	var returned_menu := packed.instantiate()
	add_child(returned_menu)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(returned_menu.startup_prologue == null
		and returned_menu.startup_credits == null,
		"同一程序运行内返回主菜单不应重播序章或制作组名单")
	_check(returned_menu.start_panel.visible,
		"从关卡返回主菜单应直接显示主菜单按钮")
	returned_menu.queue_free()

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
