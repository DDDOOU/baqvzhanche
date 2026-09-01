extends Control

const MAIN_SCENE: PackedScene = preload("res://scenes/MainScene.tscn")
const COVER_TEXTURE: Texture2D = preload("res://封面图.png")
const UNIT_CONFIG_SCREEN_SCRIPT = preload("res://scripts/ui/UnitConfigScreen.gd")
const AUDIO_SETTINGS_SCRIPT = preload("res://scripts/ui/AudioSettingsPanel.gd")
const STARTUP_CREDITS_SCRIPT = preload("res://scripts/ui/StartupCredits.gd")

var start_panel: VBoxContainer
var level_panel: VBoxContainer
var level_grid: GridContainer
var menu_font: SystemFont
var cover_background: TextureRect
var unit_config_screen: UnitConfigScreen
var audio_settings_panel: Control
var startup_credits: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_font()
	_build_background()
	_build_start_panel()
	_build_level_panel()
	_build_unit_config_screen()
	_build_audio_settings_panel()
	_show_start_panel()
	_build_startup_credits()
	SoundManager.play_bgm("menu")
	get_viewport().size_changed.connect(_fit_cover_background)
	_fit_cover_background.call_deferred()
	startup_credits.play.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("toggle_fullscreen") or (event.alt_pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]):
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()


func _build_font() -> void:
	menu_font = SystemFont.new()
	menu_font.font_names = PackedStringArray([
		"Microsoft YaHei UI",
		"Microsoft YaHei",
		"Noto Sans CJK SC",
		"Arial"
	])
	menu_font.font_weight = 700


func _build_background() -> void:
	# 使用单一封面直接铺满窗口，不再叠加暗化副本或补边层。
	# 原图为4:3、游戏窗口为16:9，因此按窗口尺寸拉伸，保证画面内容完整且无裁切。
	cover_background = TextureRect.new()
	cover_background.name = "CoverBackground"
	cover_background.texture = COVER_TEXTURE
	cover_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover_background.stretch_mode = TextureRect.STRETCH_SCALE
	cover_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_background.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(cover_background)

	var shade := ColorRect.new()
	shade.name = "ReadabilityShade"
	shade.color = Color(0.0, 0.0, 0.0, 0.18)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

func _fit_cover_background() -> void:
	if cover_background == null or COVER_TEXTURE == null:
		return

	var viewport_size := get_viewport_rect().size
	_apply_cover_layout(viewport_size)


func _apply_cover_layout(viewport_size: Vector2) -> void:
	if cover_background == null or COVER_TEXTURE == null:
		return
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	cover_background.position = Vector2.ZERO
	cover_background.size = viewport_size


func _build_start_panel() -> void:
	start_panel = VBoxContainer.new()
	start_panel.name = "StartPanel"
	start_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	start_panel.add_theme_constant_override("separation", 14)
	_anchor_menu_panel(start_panel, 0.38, 0.96, 360)
	add_child(start_panel)

	var start_button := _make_menu_button("开始游戏")
	start_button.pressed.connect(func() -> void:
		_start_level(0)
	)
	start_panel.add_child(start_button)

	var continue_button := _make_menu_button("继续游戏")
	continue_button.disabled = not GameManager.has_save(0)
	continue_button.tooltip_text = "读取最近存档" if not continue_button.disabled else "尚无可读取的存档"
	continue_button.pressed.connect(_continue_game)
	start_panel.add_child(continue_button)

	var select_button := _make_menu_button("关卡选择")
	select_button.pressed.connect(_show_level_panel)
	start_panel.add_child(select_button)

	var config_button := _make_menu_button("单位属性配置")
	config_button.tooltip_text = "调整玩家允许自定义的单位基础属性"
	config_button.pressed.connect(_show_unit_config_screen)
	start_panel.add_child(config_button)

	var settings_button := _make_menu_button("设置")
	settings_button.tooltip_text = "调整背景音乐与战斗音效音量"
	settings_button.pressed.connect(_show_audio_settings)
	start_panel.add_child(settings_button)

	var quit_button := _make_menu_button("退出游戏")
	quit_button.pressed.connect(func() -> void:
		get_tree().quit()
	)
	start_panel.add_child(quit_button)


func _build_unit_config_screen() -> void:
	unit_config_screen = UNIT_CONFIG_SCREEN_SCRIPT.new()
	unit_config_screen.name = "UnitConfigScreen"
	unit_config_screen.menu_font = menu_font
	unit_config_screen.visible = false
	unit_config_screen.closed.connect(_show_start_panel)
	add_child(unit_config_screen)


func _build_audio_settings_panel() -> void:
	audio_settings_panel = AUDIO_SETTINGS_SCRIPT.new()
	audio_settings_panel.name = "AudioSettingsPanel"
	audio_settings_panel.menu_font = menu_font
	audio_settings_panel.closed.connect(_show_start_panel)
	add_child(audio_settings_panel)


func _build_startup_credits() -> void:
	startup_credits = STARTUP_CREDITS_SCRIPT.new()
	startup_credits.name = "StartupCredits"
	startup_credits.finished.connect(_on_startup_credits_finished)
	add_child(startup_credits)
	# 制作组名单播放期间不显示主菜单按钮，避免文字重叠和误触。
	start_panel.visible = false
	level_panel.visible = false


func _on_startup_credits_finished() -> void:
	if startup_credits != null:
		startup_credits.queue_free()
		startup_credits = null
	_show_start_panel()


func _build_level_panel() -> void:
	level_panel = VBoxContainer.new()
	level_panel.name = "LevelPanel"
	level_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	level_panel.add_theme_constant_override("separation", 12)
	_anchor_menu_panel(level_panel, 0.58, 0.93, 560)
	add_child(level_panel)

	var title := Label.new()
	title.text = "关卡选择"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", menu_font)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	level_panel.add_child(title)

	level_grid = GridContainer.new()
	level_grid.name = "LevelGrid"
	level_grid.columns = 2
	level_grid.add_theme_constant_override("h_separation", 12)
	level_grid.add_theme_constant_override("v_separation", 10)
	level_panel.add_child(level_grid)
	_fill_level_buttons()

	var back_button := _make_menu_button("返回", 260)
	back_button.pressed.connect(_show_start_panel)
	level_panel.add_child(back_button)


func _fill_level_buttons() -> void:
	var level_count: int = max(LevelDatabase.get_level_count(), 1)
	var has_available_level := false

	for level_id in range(level_count):
		var scene_path := "res://scenes/levels/level_%02d.tscn" % (level_id + 1)
		if not ResourceLoader.exists(scene_path):
			continue

		has_available_level = true
		var level_name := "第%d关" % (level_id + 1)
		var level_data = LevelDatabase.get_level(level_id)
		if level_data != null and not String(level_data.level_name).is_empty():
			level_name = "第%d关  %s" % [level_id + 1, level_data.level_name]

		var selected_level_id := level_id
		var level_button := _make_menu_button(level_name, 260)
		level_button.pressed.connect(func() -> void:
			_start_level(selected_level_id)
		)
		level_grid.add_child(level_button)

	if not has_available_level:
		var disabled_button := _make_menu_button("暂无可用关卡", 260)
		disabled_button.disabled = true
		level_grid.add_child(disabled_button)


func _make_menu_button(text: String, width: float = 320.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 54)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", menu_font)
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.55))
	button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	button.add_theme_constant_override("outline_size", 3)
	button.add_theme_stylebox_override("normal", _make_button_style(Color(0.04, 0.04, 0.04, 0.62), Color(0.72, 0.12, 0.12, 0.88)))
	button.add_theme_stylebox_override("hover", _make_button_style(Color(0.16, 0.03, 0.03, 0.78), Color(0.95, 0.24, 0.18, 1.0)))
	button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.3, 0.04, 0.03, 0.85), Color(1.0, 0.32, 0.22, 1.0)))
	button.add_theme_stylebox_override("focus", _make_button_style(Color(0.12, 0.02, 0.02, 0.78), Color(1.0, 0.86, 0.55, 1.0)))
	button.add_theme_stylebox_override("disabled", _make_button_style(Color(0.04, 0.04, 0.04, 0.42), Color(0.5, 0.5, 0.5, 0.5)))
	return button


func _make_button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _anchor_menu_panel(panel: Control, top: float, bottom: float, width: float) -> void:
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = top
	panel.anchor_bottom = bottom
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = 0
	panel.offset_bottom = 0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH


func _show_start_panel() -> void:
	start_panel.visible = true
	level_panel.visible = false
	if unit_config_screen != null:
		unit_config_screen.visible = false
	if audio_settings_panel != null:
		audio_settings_panel.visible = false


func _show_level_panel() -> void:
	start_panel.visible = false
	level_panel.visible = true
	if unit_config_screen != null:
		unit_config_screen.visible = false
	if audio_settings_panel != null:
		audio_settings_panel.visible = false


func _show_unit_config_screen() -> void:
	start_panel.visible = false
	level_panel.visible = false
	unit_config_screen.visible = true
	if audio_settings_panel != null:
		audio_settings_panel.visible = false


func _show_audio_settings() -> void:
	start_panel.visible = false
	level_panel.visible = false
	if unit_config_screen != null:
		unit_config_screen.visible = false
	audio_settings_panel.show_panel()


func _start_level(level_id: int) -> void:
	var next_scene := MAIN_SCENE.instantiate()
	next_scene.startup_level_id = level_id
	var root := get_tree().root
	var current := get_tree().current_scene
	root.add_child(next_scene)
	get_tree().current_scene = next_scene
	if current != null:
		current.queue_free()


func _continue_game() -> void:
	if GameManager.load_game(0):
		_start_level(GameManager.get_pending_level_id())


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
