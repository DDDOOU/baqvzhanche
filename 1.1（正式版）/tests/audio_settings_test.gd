extends Node

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var old_bgm := SoundManager.get_bgm_volume()
	var old_sfx := SoundManager.get_sfx_volume()
	GameManager.startup_sequence_shown_this_session = false
	var packed := load("res://scenes/MainMenu.tscn") as PackedScene
	var menu = packed.instantiate()
	get_tree().root.add_child(menu)
	await get_tree().process_frame
	if menu.startup_prologue != null:
		menu.startup_prologue.finish_now()
		await get_tree().process_frame

	_check(FileAccess.file_exists("res://assets/audio/bgm/menu_shortwave_unknown_threat.mp3"),
		"主菜单BGM文件应存在")
	_check(FileAccess.file_exists("res://assets/audio/bgm/level_radar_pulse_unrest.mp3"),
		"关卡BGM文件应存在")
	_check(SoundManager._current_bgm == "menu" and SoundManager._bgm_player.stream != null,
		"主菜单应自动播放短波主题BGM")
	_check(menu.audio_settings_panel != null, "主菜单应包含设置面板")
	menu._show_audio_settings()
	_check(menu.audio_settings_panel.visible, "主菜单设置按钮应能打开设置面板")
	_check(menu.audio_settings_panel.bgm_slider != null and menu.audio_settings_panel.sfx_slider != null,
		"设置面板应提供BGM与音效滑块")

	SoundManager.set_bgm_volume(0.31, false)
	SoundManager.set_sfx_volume(0.67, false)
	_check(is_equal_approx(SoundManager.get_bgm_volume(), 0.31), "BGM音量应可独立调整")
	_check(is_equal_approx(SoundManager.get_sfx_volume(), 0.67), "音效音量应可独立调整")

	var pause_menu = preload("res://scripts/ui/PauseMenu.gd").new()
	get_tree().root.add_child(pause_menu)
	pause_menu.visible = true
	await get_tree().process_frame
	_check(pause_menu.audio_settings_panel != null, "暂停菜单应包含设置入口")
	pause_menu.audio_settings_panel.show_panel()
	await get_tree().process_frame
	var settings_window := pause_menu.audio_settings_panel.get_node("ViewportCenter/SettingsWindow") as Control
	var viewport_center := get_viewport().get_visible_rect().size * 0.5
	_check(settings_window != null and settings_window.get_global_rect().get_center().distance_to(viewport_center) < 2.0,
		"暂停菜单中的设置窗口应以整个游戏视口为中心")

	SoundManager.play_bgm("level")
	await get_tree().create_timer(0.8).timeout
	_check(SoundManager._current_bgm == "level" and SoundManager._bgm_player.stream != null,
		"进入关卡时应切换为雷达脉冲BGM")

	SoundManager.set_bgm_volume(old_bgm, false)
	SoundManager.set_sfx_volume(old_sfx, false)
	menu.queue_free()
	pause_menu.queue_free()
	await get_tree().process_frame

	if _failures.is_empty():
		print("[AUDIO SETTINGS TEST] PASS (%d checks)" % _checks)
		get_tree().quit(0)
		return
	push_error("[AUDIO SETTINGS TEST] FAIL: %d check(s) failed\n- %s" % [
		_failures.size(), "\n- ".join(_failures)])
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
