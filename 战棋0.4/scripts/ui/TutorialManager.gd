extends Node
## 教学引导（第 1 关新手教程）
## 底部提示条分步引导核心操作闭环：选中单位 → 移动/攻击 → 结束计划 → 观看演绎。
## 事件驱动：MainScene 在关键动作后调用 notify()，满足条件才推进；乱序操作自动跳过中间提示。
## 完成或跳过 → GameManager.tutorial_done = true（本次运行内不再重复引导）。

signal tutorial_finished

enum Step { NONE, SELECT_UNIT, MOVE_OR_ATTACK, SUBMIT_ORDERS, WATCH_EXECUTION, DONE }

const STEP_TEXTS := {
	Step.SELECT_UNIT: "第1步/4  欢迎，指挥官。点击任意蓝色（华约）单位选中它。",
	Step.MOVE_OR_ATTACK: "第2步/4  蓝色格=可移动：点击蓝格规划路径，再点『确认移动』。点击红色敌军可直接下达攻击命令。",
	Step.SUBMIT_ORDERS: "第3步/4  继续给其他单位下令（移动/攻击/卡牌）。全部下令后点击『结束计划』进入沙盘演绎。",
	Step.WATCH_EXECUTION: "第4步/4  沙盘演绎——双方同时行动，点击『跳过』可加速观看。",
}

var _current_step: Step = Step.NONE
var _layer: CanvasLayer = null
var _label: Label = null


func setup() -> void:
	## 构建底部提示条（初始隐藏，首次推进时显示）
	_layer = CanvasLayer.new()
	_layer.layer = 85
	_layer.name = "TutorialLayer"
	add_child(_layer)

	var panel = Panel.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = -96
	panel.offset_bottom = -16
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.13, 0.92)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.85, 0.8, 0.55, 0.9)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", style)
	_layer.add_child(panel)

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.8))
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_left = 14
	_label.offset_right = -90
	_label.offset_top = 6
	_label.offset_bottom = -6
	panel.add_child(_label)

	var skip_btn = Button.new()
	skip_btn.text = "跳过教学"
	skip_btn.anchor_left = 1.0
	skip_btn.anchor_right = 1.0
	skip_btn.anchor_top = 1.0
	skip_btn.anchor_bottom = 1.0
	skip_btn.offset_left = -82
	skip_btn.offset_right = -10
	skip_btn.offset_top = -30
	skip_btn.offset_bottom = -8
	skip_btn.pressed.connect(_finish)
	panel.add_child(skip_btn)
	_layer.visible = false  # 初始隐藏整层；_advance 时显示


func notify(event: String) -> void:
	## 事件驱动推进：MainScene 在关键动作后调用
	if _current_step == Step.DONE:
		return
	match event:
		"planning_r1":
			if _current_step == Step.NONE:
				_advance(Step.SELECT_UNIT)
		"unit_selected":
			if _current_step == Step.SELECT_UNIT:
				_advance(Step.MOVE_OR_ATTACK)
		"order_submitted":
			if _current_step == Step.MOVE_OR_ATTACK:
				_advance(Step.SUBMIT_ORDERS)
		"execution":
			if _current_step == Step.SUBMIT_ORDERS:
				_advance(Step.WATCH_EXECUTION)
		"planning_r2":
			if _current_step == Step.WATCH_EXECUTION:
				_finish()


func is_active() -> bool:
	return _current_step != Step.NONE and _current_step != Step.DONE


func _advance(step: Step) -> void:
	_current_step = step
	if _layer == null:
		return
	_layer.visible = true
	if _label:
		_label.text = STEP_TEXTS.get(step, "")


func _finish() -> void:
	_current_step = Step.DONE
	if _layer:
		_layer.visible = false
	GameManager.tutorial_done = true
	tutorial_finished.emit()
