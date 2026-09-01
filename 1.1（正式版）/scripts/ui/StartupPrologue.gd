class_name StartupPrologue
extends Control

signal finished

enum Stage { BLACK, QUOTE, DIALOGUE, COMPLETE }

const BLACK_HOLD_SECONDS := 2.0
const QUOTE_HOLD_SECONDS := 7.0
const QUOTE_TEXT := "在战场电磁干扰形式选择上，本手册主张采用对某一特定频率或信道所进行的瞄准式干扰，而不主张同时干扰一个较宽频带的阻塞式干扰，因为后者对已方的电磁通讯和电子支援措施也会产生影响。"
const QUOTE_SOURCE := "——摘自1993年美国陆军《电子战手册》"
const PORTRAITS = preload("res://scripts/ui/CharacterPortraits.gd")
const DIALOGUE: Array[Dictionary] = [
	{"speaker": "阿尼娅", "text": "西侧前沿哨连续失联。最后确认坐标（4,5），时间 04:30:17。"},
	{"speaker": "卡琳娜", "text": "北约先遣营已经越过边境。他们的侦察链还完整，炮兵校射比我们快至少一个回合。"},
	{"speaker": "列夫森科", "text": "他们看得见我们。"},
	{"speaker": "卡琳娜", "text": "现在是。天基过顶、无人机中继、数字火控，全都还在工作。只要他们保持这套链路，铁路桥和通信塔撑不到天亮。"},
	{"speaker": "列夫森科", "text": "“洪水”准备到哪一步了？"},
	{"speaker": "卡琳娜", "text": "第一阶段可以立即启动。它会向战区投放宽频噪声，压垮北约的数据链和制导信号。第二阶段会伪造旧呼号和重复坐标。第三阶段会让大部分无线电只能传回最后已知位置。"},
	{"speaker": "阿尼娅", "text": "也就是说，我们自己的频道也会一起变脏。"},
	{"speaker": "卡琳娜", "text": "是。洪水不是瞄准某个频率的干扰。它是把整片频谱灌满噪声。敌人的屏幕会暗下去，我们的地图也会开始说谎。"},
	{"speaker": "列夫森科", "text": "代价。"},
	{"speaker": "卡琳娜", "text": "侦察确认延迟。炮击散布扩大。友军呼号可能重复。未知接触无法立刻识别阵营。误击概率上升。"},
	{"speaker": "阿尼娅", "text": "前沿班组请求指令。他们报告（9,6）附近有履带声，还有一辆伤员卡车卡在桥面。"},
	{"speaker": "列夫森科", "text": "北约装甲？"},
	{"speaker": "卡琳娜", "text": "可能是。也可能是我方撤回来的 BTR。干扰启动后，我不能保证第一时间分清。"},
	{"speaker": "阿尼娅", "text": "上级命令要求守住铁路桥。若桥失守，后方撤离线会断。"},
	{"speaker": "列夫森科", "text": "如果不开洪水？"},
	{"speaker": "卡琳娜", "text": "北约会继续用精确火力拆掉我们的防线。我们会输得很清楚。"},
	{"speaker": "列夫森科", "text": "如果开？"},
	{"speaker": "卡琳娜", "text": "我们可能守住。但每一道命令都要在更脏的情报里下达。"},
	{"speaker": "阿尼娅", "text": "需要确认是否启用“洪水”第一阶段。"},
	{"speaker": "列夫森科", "text": "启用。频谱压制范围覆盖前沿网格（4,5）至铁路桥（9,6）。所有单位改用最后已知坐标和目视报告。"},
	{"speaker": "卡琳娜", "text": "记录为战区级宽频阻塞。"},
	{"speaker": "列夫森科", "text": "记录为必要风险。不是免责。"},
	{"speaker": "阿尼娅", "text": "命令已发送。前线回传开始失真。"},
	{"speaker": "步兵班长", "text": "指挥部，信号很差。我们还能听见你们。请重复：如果（9,6）出现未知接触，是否开火？"},
	{"speaker": "列夫森科", "text": "未确认前不准盲射。侦察车前出，步兵班保持隐蔽，工兵准备守桥和爆破两套方案。"},
	{"speaker": "步兵班长", "text": "明白。守住坐标，先看清坐标上是谁。"},
	{"speaker": "阿尼娅", "text": "洪水第一阶段生效。干扰强度 30% 上升至 55%。"},
	{"speaker": "卡琳娜", "text": "北约链路开始掉线。我们的也一样。"},
	{"speaker": "列夫森科", "text": "那就从现在开始，每个坐标都要有人负责。"},
]

var stage: Stage = Stage.BLACK
var dialogue_index := 0
var _sequence_token := 0
var _completed := false
var _skip_enabled_at_msec := 0
var _font: SystemFont
var _quote_group: Control
var _quote_text_label: Label
var _quote_source_label: Label
var _dialogue_group: Control
var _portrait_left: TextureRect
var _portrait_right: TextureRect
var _speaker_label: Label
var _body_label: Label
var _progress_label: Label
var _next_button: Button
var _skip_button: Button
var _noise_player: AudioStreamPlayer
var _noise_playback: AudioStreamGeneratorPlayback
var _sample_cursor := 0.0
var _radio_burst_remaining := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fit_to_viewport()
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 1200
	_build_font()
	_build_interface()
	_build_noise()
	get_viewport().size_changed.connect(_fit_to_viewport)
	visible = false


func _process(delta: float) -> void:
	if not visible or _noise_playback == null:
		return
	_radio_burst_remaining = maxf(_radio_burst_remaining - delta, 0.0)
	var frames := _noise_playback.get_frames_available()
	var mix_rate := 22050.0
	for frame_index in range(frames):
		var time := _sample_cursor / mix_rate
		var sample := sin(TAU * 50.0 * time) * 0.018
		sample += sin(TAU * 100.0 * time) * 0.006
		if _radio_burst_remaining > 0.0:
			sample += randf_range(-0.11, 0.11)
		_noise_playback.push_frame(Vector2(sample, sample))
		_sample_cursor += 1.0


func _fit_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	queue_redraw()


func _build_font() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Arial"
	])
	_font.font_weight = 600


func _build_interface() -> void:
	var blackout := ColorRect.new()
	blackout.name = "BlackBackdrop"
	blackout.color = Color(0.005, 0.006, 0.006, 1.0)
	blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blackout.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(blackout)

	_build_quote_screen()
	_build_dialogue_screen()
	_build_skip_button()


func _build_quote_screen() -> void:
	_quote_group = Control.new()
	_quote_group.name = "QuoteScreen"
	_quote_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quote_group.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_quote_group)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quote_group.add_child(center)

	var text_column := VBoxContainer.new()
	text_column.custom_minimum_size = Vector2(1040, 0)
	text_column.add_theme_constant_override("separation", 34)
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(text_column)

	_quote_text_label = _make_label(QUOTE_TEXT, 28, Color(0.96, 0.96, 0.94), HORIZONTAL_ALIGNMENT_LEFT)
	_quote_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quote_text_label.custom_minimum_size = Vector2(1040, 210)
	_quote_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_quote_text_label.add_theme_constant_override("line_spacing", 12)
	text_column.add_child(_quote_text_label)

	_quote_source_label = _make_label(QUOTE_SOURCE, 20, Color(0.72, 0.74, 0.70), HORIZONTAL_ALIGNMENT_RIGHT)
	_quote_source_label.modulate.a = 0.0
	text_column.add_child(_quote_source_label)
	_quote_group.visible = false


func _build_dialogue_screen() -> void:
	_dialogue_group = Control.new()
	_dialogue_group.name = "DialogueScreen"
	_dialogue_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_group.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dialogue_group)

	_portrait_left = PORTRAITS.create_slot("PortraitLeft")
	_portrait_left.anchor_left = 0.04
	_portrait_left.anchor_top = 0.10
	_portrait_left.anchor_right = 0.32
	_portrait_left.anchor_bottom = 0.72
	_dialogue_group.add_child(_portrait_left)

	_portrait_right = PORTRAITS.create_slot("PortraitRight")
	_portrait_right.anchor_left = 0.68
	_portrait_right.anchor_top = 0.10
	_portrait_right.anchor_right = 0.96
	_portrait_right.anchor_bottom = 0.72
	_dialogue_group.add_child(_portrait_right)

	var dialogue_center := CenterContainer.new()
	dialogue_center.name = "DialogueBottomCenter"
	dialogue_center.anchor_left = 0.0
	dialogue_center.anchor_top = 1.0
	dialogue_center.anchor_right = 1.0
	dialogue_center.anchor_bottom = 1.0
	dialogue_center.offset_top = -238.0
	dialogue_center.offset_bottom = -20.0
	_dialogue_group.add_child(dialogue_center)

	var dialogue_panel := Panel.new()
	dialogue_panel.name = "DialoguePanel"
	dialogue_panel.custom_minimum_size = Vector2(1100, 204)
	dialogue_panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.24, 0.25, 0.25, 0.40), Color(0.76, 0.78, 0.74, 0.42), 1))
	dialogue_center.add_child(dialogue_panel)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 30
	content.offset_top = 18
	content.offset_right = -30
	content.offset_bottom = -14
	content.add_theme_constant_override("separation", 7)
	dialogue_panel.add_child(content)

	_speaker_label = _make_label("", 20, Color(0.96, 0.80, 0.42), HORIZONTAL_ALIGNMENT_LEFT)
	content.add_child(_speaker_label)
	_body_label = _make_label("", 19, Color(0.97, 0.97, 0.95), HORIZONTAL_ALIGNMENT_LEFT)
	_body_label.custom_minimum_size = Vector2(0, 86)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(_body_label)

	var actions := HBoxContainer.new()
	content.add_child(actions)
	_progress_label = _make_label("", 13, Color(0.64, 0.66, 0.63), HORIZONTAL_ALIGNMENT_LEFT)
	_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_progress_label)
	_next_button = Button.new()
	_next_button.name = "ContinueButton"
	_next_button.text = "继续"
	_next_button.custom_minimum_size = Vector2(170, 40)
	_next_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_next_button.add_theme_font_override("font", _font)
	_next_button.add_theme_font_size_override("font_size", 17)
	_next_button.pressed.connect(_advance_dialogue)
	actions.add_child(_next_button)
	_dialogue_group.visible = false


func _build_skip_button() -> void:
	_skip_button = Button.new()
	_skip_button.name = "SkipButton"
	_skip_button.text = "跳过序章"
	_skip_button.anchor_left = 1.0
	_skip_button.anchor_top = 0.0
	_skip_button.anchor_right = 1.0
	_skip_button.anchor_bottom = 0.0
	_skip_button.offset_left = -154
	_skip_button.offset_top = 24
	_skip_button.offset_right = -24
	_skip_button.offset_bottom = 62
	_skip_button.add_theme_font_override("font", _font)
	_skip_button.add_theme_font_size_override("font_size", 15)
	_skip_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_skip_button.pressed.connect(finish_now)
	add_child(_skip_button)


func _build_noise() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.35
	_noise_player = AudioStreamPlayer.new()
	_noise_player.name = "ElectricalNoise"
	_noise_player.stream = stream
	_noise_player.bus = "SFX"
	_noise_player.volume_db = -9.0
	add_child(_noise_player)


func play() -> void:
	if _completed:
		return
	visible = true
	stage = Stage.BLACK
	dialogue_index = 0
	_quote_group.visible = false
	_dialogue_group.visible = false
	_skip_button.visible = false
	_skip_enabled_at_msec = Time.get_ticks_msec() + 450
	_sequence_token += 1
	_run_sequence(_sequence_token)


func _run_sequence(token: int) -> void:
	await get_tree().create_timer(BLACK_HOLD_SECONDS, true, false, true).timeout
	if token != _sequence_token or _completed:
		return
	_show_quote()
	await get_tree().create_timer(0.85, true, false, true).timeout
	if token != _sequence_token or _completed:
		return
	_quote_source_label.modulate.a = 1.0
	_radio_burst_remaining = 0.34
	await get_tree().create_timer(QUOTE_HOLD_SECONDS, true, false, true).timeout
	if token != _sequence_token or _completed:
		return
	_show_dialogue()


func _show_quote() -> void:
	stage = Stage.QUOTE
	_quote_group.visible = true
	_dialogue_group.visible = false
	_skip_button.visible = true
	_start_noise()
	_quote_text_label.modulate.a = 0.0
	_quote_source_label.modulate.a = 0.0
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_quote_text_label, "modulate:a", 1.0, 0.55)


func _show_dialogue() -> void:
	stage = Stage.DIALOGUE
	_quote_group.visible = false
	_dialogue_group.visible = true
	_stop_noise()
	dialogue_index = 0
	_render_dialogue()


func _render_dialogue() -> void:
	var entry := DIALOGUE[dialogue_index]
	_speaker_label.text = String(entry.speaker)
	_body_label.text = String(entry.text)
	PORTRAITS.show_speaker(_portrait_left, _portrait_right,
		String(entry.speaker), String(entry.text))
	_progress_label.text = "%02d / %02d" % [dialogue_index + 1, DIALOGUE.size()]
	_next_button.text = "进入游戏" if dialogue_index == DIALOGUE.size() - 1 else "继续"


func _advance_dialogue() -> void:
	if stage != Stage.DIALOGUE or _completed:
		return
	if dialogue_index + 1 >= DIALOGUE.size():
		finish_now()
		return
	dialogue_index += 1
	_render_dialogue()
	SoundManager.play("ui_click", -8.0)


func _input(event: InputEvent) -> void:
	if not visible or _completed:
		return
	if Time.get_ticks_msec() < _skip_enabled_at_msec:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			finish_now()
		elif stage == Stage.DIALOGUE and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			get_viewport().set_input_as_handled()
			_advance_dialogue()


func finish_now() -> void:
	if _completed:
		return
	_completed = true
	stage = Stage.COMPLETE
	_sequence_token += 1
	visible = false
	_stop_noise()
	finished.emit()


func _start_noise() -> void:
	if _noise_player == null or _noise_player.playing:
		return
	_noise_player.play()
	_noise_playback = _noise_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _stop_noise() -> void:
	if _noise_player != null:
		_noise_player.stop()
	_noise_playback = null


func contains_text(fragment: String) -> bool:
	return _tree_contains_text(self, fragment)


func get_dialogue_count() -> int:
	return DIALOGUE.size()


func _make_label(text_value: String, font_size: int, color: Color,
		alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = alignment
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.88))
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel_style(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 7
	return style


func _tree_contains_text(node: Node, fragment: String) -> bool:
	if node is Label and fragment in String(node.text):
		return true
	for child in node.get_children():
		if _tree_contains_text(child, fragment):
			return true
	return false
