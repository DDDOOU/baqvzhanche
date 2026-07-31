# ==============================================================================
# MainScene.gd — 主场景
# ==============================================================================
extends Node2D

@onready var tile_grid: TileGridRenderer = $TileGridRenderer
@onready var unit_renderer: UnitRenderer = $UnitRenderer
@onready var card_ui: CardUI = $CardUI
@onready var camera: Camera2D = $Camera2D

var turn_label: Label
var morale_label: Label
var emi_label: Label
var phase_timer_label: Label
var hover_coord_label: Label
var finish_planning_button: Button
var selected_unit: UnitBase = null
var game_over_active: bool = false
var game_over_panel: CanvasLayer = null
var _last_vp_size: Vector2 = Vector2.ZERO
var level_scene_instance: Node2D
var level_terrain: TileMapLayer
var level_used_rect: Rect2i
var base_camera_offset: Vector2 = Vector2.ZERO
var base_camera_zoom: float = 1.0
var camera_pan: Vector2 = Vector2.ZERO
var camera_zoom_multiplier: float = 1.0
const CAMERA_PAN_SPEED: float = 420.0
const CAMERA_MIN_ZOOM: float = 0.45
const CAMERA_MAX_ZOOM: float = 2.0


func _ready() -> void:
	print("=".repeat(50))
	print("  Silent Reckoning·1987  静默行动·1987")
	print("=".repeat(50))

	_load_designed_level(0)
	_connect_signals()
	_setup_ui()
	_fit_camera_to_map()
	_last_vp_size = get_viewport_rect().size

	# 窗口缩放时重新计算相机，保证网格和单位始终对齐
	get_viewport().size_changed.connect(_on_viewport_resized)

	# 直接启动第1关
	GameManager.start_level(0)


## ==================== 相机 ====================

func _load_designed_level(level_id: int) -> void:
	var scene_path := "res://scenes/levels/level_%02d.tscn" % (level_id + 1)
	if not ResourceLoader.exists(scene_path):
		push_error("找不到关卡场景: %s" % scene_path)
		return
	var packed_scene := load(scene_path) as PackedScene
	level_scene_instance = packed_scene.instantiate() as Node2D
	level_scene_instance.name = "DesignedLevel"
	level_scene_instance.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(level_scene_instance)
	move_child(level_scene_instance, 0)

	for child in level_scene_instance.get_children():
		if child is TileMapLayer:
			var child_name := String(child.name).to_lower()
			if child_name.contains("terrain") or String(child.name).contains("地块"):
				level_terrain = child
				break
	if level_terrain == null:
		push_error("%s 中找不到Terrain TileMapLayer" % scene_path)
		return

	level_used_rect = level_terrain.get_used_rect()
	if level_used_rect.size.x <= 0 or level_used_rect.size.y <= 0:
		push_error("%s 的Terrain尚未绘制地块" % scene_path)
		return

	var extracted := _extract_tilemap_data()
	GameManager.set_runtime_map(extracted, level_used_rect.size)
	GridManager.MAP_WIDTH = level_used_rect.size.x
	GridManager.MAP_HEIGHT = level_used_rect.size.y
	tile_grid.use_source_tilemap(level_terrain, level_used_rect)
	unit_renderer.use_source_tilemap(level_terrain, level_used_rect)
	print("[MainScene] 使用设计关卡 %s，地图尺寸=%dx%d，原始起点=(%d,%d)" % [
		scene_path, level_used_rect.size.x, level_used_rect.size.y,
		level_used_rect.position.x, level_used_rect.position.y])


func _extract_tilemap_data() -> Dictionary:
	var terrain_list: Array[Dictionary] = []
	for source_cell in level_terrain.get_used_cells():
		var logical_cell: Vector2i = source_cell - level_used_rect.position
		var tile_data := level_terrain.get_cell_tile_data(source_cell)
		if tile_data == null:
			continue
		var terrain_name := _clean_terrain_name(tile_data.get_custom_data("terrain_type"))
		var terrain_type := _terrain_enum_from_name(terrain_name)
		var cell_data: Dictionary = {
			"col": logical_cell.x,
			"row": logical_cell.y,
			"terrain": terrain_type,
			"terrain_name": terrain_name,
			"height": int(tile_data.get_custom_data("height")),
			"move_cost": float(tile_data.get_custom_data("move_cost")),
			"passable": bool(tile_data.get_custom_data("passable")),
			"concealment": float(tile_data.get_custom_data("concealment")),
		}
		terrain_list.append(cell_data)

	for marker in level_scene_instance.find_children("*", "GridMarker2D", true, false):
		var pos: Vector2i = marker.grid_coordinate
		for cell_data in terrain_list:
			if cell_data.col == pos.x and cell_data.row == pos.y:
				match marker.marker_type:
					GridMarker2D.MarkerType.WP_SPAWN:
						cell_data["marker"] = GridManager.CellMarker.WP_SPAWN
					GridMarker2D.MarkerType.NATO_SPAWN:
						cell_data["marker"] = GridManager.CellMarker.NATO_SPAWN
					GridMarker2D.MarkerType.VICTORY_POINT:
						cell_data["marker"] = GridManager.CellMarker.VP_POINT
				break
	return {"terrain": terrain_list}


func _clean_terrain_name(value: Variant) -> String:
	var result := str(value).strip_edges()
	while result.begins_with("\""):
		result = result.trim_prefix("\"").strip_edges()
	while result.ends_with("\""):
		result = result.trim_suffix("\"").strip_edges()
	return result.to_lower()


func _terrain_enum_from_name(terrain_name: String) -> int:
	match terrain_name:
		"water", "river":
			return GridManager.TerrainType.RIVER
		"forest":
			return GridManager.TerrainType.FOREST
		"road":
			return GridManager.TerrainType.ROAD
		"railway":
			return GridManager.TerrainType.RAILWAY
		"bridge":
			return GridManager.TerrainType.BRIDGE
		"marsh":
			return GridManager.TerrainType.MARSH
		"city":
			return GridManager.TerrainType.CITY
		_:
			return GridManager.TerrainType.PLAINS


func _fit_camera_to_map() -> void:
	var map_w = (GridManager.MAP_WIDTH + GridManager.MAP_HEIGHT) * \
		GridManager.ISO_TILE_WIDTH * 0.5
	var map_h = (GridManager.MAP_WIDTH + GridManager.MAP_HEIGHT) * \
		GridManager.ISO_TILE_HEIGHT * 0.5 + GridManager.ISO_SPRITE_SIZE
	var vp = get_viewport_rect().size
	# 为右侧战报和底部卡牌栏预留空间
	var avail_w = maxf(320.0, vp.x - 340.0)
	var avail_h = maxf(240.0, vp.y - 260.0)
	base_camera_zoom = minf(min(avail_w / map_w, avail_h / map_h), 1.0)
	var ox = 20.0 + (avail_w - map_w * base_camera_zoom) / 2.0
	var oy = 105.0 + (avail_h - map_h * base_camera_zoom) / 2.0
	base_camera_offset = Vector2(ox, oy)
	_apply_camera_transform()
	camera.position = vp / 2.0
	camera.zoom = Vector2.ONE
	print("[MainScene] camera zoom=%.2f offset=(%.0f,%.0f) viewport=%.0fx%.0f" % [
		base_camera_zoom * camera_zoom_multiplier,
		base_camera_offset.x + camera_pan.x, base_camera_offset.y + camera_pan.y,
		vp.x, vp.y])


func _apply_camera_transform() -> void:
	var zoom := clampf(base_camera_zoom * camera_zoom_multiplier,
		CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)
	var offset := base_camera_offset + camera_pan
	tile_grid.set_camera(offset, zoom)
	unit_renderer.set_camera(offset, zoom)
	if level_scene_instance and level_terrain:
		var level_scale := 2.0 * zoom
		level_scene_instance.scale = Vector2.ONE * level_scale
		var source_origin := level_terrain.map_to_local(level_used_rect.position)
		var target_origin := GridManager.get_iso_map_origin() * zoom + offset
		level_scene_instance.position = target_origin - source_origin * level_scale


func _on_viewport_resized() -> void:
	"""窗口缩放时重新计算相机参数，保证网格和单位始终对齐"""
	_fit_camera_to_map()


## ==================== 信号 ====================

func _connect_signals() -> void:
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.level_started.connect(_on_level_started)
	TurnManager.planning_phase_started.connect(_on_planning_started)
	TurnManager.execution_phase_started.connect(_on_execution_started)
	TurnManager.turn_resolved.connect(_on_turn_resolved)
	CombatSystem.attack_executed.connect(_on_attack_executed)
	CombatSystem.unit_destroyed.connect(_on_unit_destroyed)
	MoraleSystem.unit_broken.connect(_on_unit_broken)
	EMISystem.intensity_changed.connect(_on_emi_changed)
	CardSystem.card_drawn.connect(_on_card_drawn)
	# 移动每步/完成都刷新单位渲染（沙盘演绎时实时看到移动+攻击掉血）
	MovementSystem.unit_step.connect(_on_unit_step)
	MovementSystem.unit_move_completed.connect(_on_unit_move_completed)


## ==================== HUD ====================

func _setup_ui() -> void:
	var hud = CanvasLayer.new()
	add_child(hud)

	turn_label = _make_label(Vector2(10, 10), Color.WHITE, "第 1 回合")
	morale_label = _make_label(Vector2(10, 35), Color.GOLD, "士气: 昂扬 (80)")
	emi_label = _make_label(Vector2(10, 60), Color.RED, "EMI: 0%")
	phase_timer_label = _make_label(Vector2(10, 85), Color.CYAN, "")
	hover_coord_label = _make_label(Vector2(10, 110), Color(0.75, 0.9, 1.0), "")
	for lbl in [turn_label, morale_label, emi_label, phase_timer_label, hover_coord_label]:
		hud.add_child(lbl)

	finish_planning_button = Button.new()
	finish_planning_button.position = Vector2(10, 138)
	finish_planning_button.size = Vector2(150, 36)
	finish_planning_button.text = "提前结束计划"
	finish_planning_button.tooltip_text = "结束操作并立即进入沙盘演绎（End Planning）"
	finish_planning_button.visible = false
	finish_planning_button.pressed.connect(_on_phase_skip_pressed)
	hud.add_child(finish_planning_button)

	# 战报面板（挂到 HUD CanvasLayer）
	var battle_log_ui = preload("res://scripts/ui/BattleLogUI.gd").new()
	hud.add_child(battle_log_ui)


func _make_label(pos: Vector2, color: Color, text: String) -> Label:
	var l = Label.new()
	l.position = pos
	l.add_theme_color_override("font_color", color)
	l.text = text
	return l


func _process(delta: float) -> void:
	# 帧检测兜底：视口尺寸变化时重算相机（覆盖最大化/还原/拖拽缩放）
	var vp = get_viewport_rect().size
	if vp != _last_vp_size:
		_last_vp_size = vp
		_fit_camera_to_map()

	var move_direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		move_direction.x += 1.0
	if Input.is_key_pressed(KEY_D):
		move_direction.x -= 1.0
	if Input.is_key_pressed(KEY_W):
		move_direction.y += 1.0
	if Input.is_key_pressed(KEY_S):
		move_direction.y -= 1.0
	if move_direction != Vector2.ZERO:
		camera_pan += move_direction.normalized() * CAMERA_PAN_SPEED * delta
		_apply_camera_transform()

	if TurnManager.is_planning:
		phase_timer_label.text = "计划阶段: %.0fs" % TurnManager.get_remaining_planning_time()
		_update_hover_coordinate()
		finish_planning_button.visible = true
		finish_planning_button.disabled = false
		finish_planning_button.text = "提前结束计划"
		finish_planning_button.tooltip_text = "结束操作并立即进入沙盘演绎（End Planning）"
	elif TurnManager.is_executing:
		phase_timer_label.text = "沙盘演绎: %.0fs" % TurnManager.get_remaining_execution_time()
		hover_coord_label.text = ""
		finish_planning_button.visible = true
		finish_planning_button.disabled = false
		finish_planning_button.text = "跳过演绎"
		finish_planning_button.tooltip_text = "跳过剩余演绎等待时间（Skip Execution）"
	else:
		phase_timer_label.text = ""
		hover_coord_label.text = ""
		finish_planning_button.visible = false
	turn_label.text = "第 %d 回合 / 共 %d 回合" % [TurnManager.current_turn, CampaignManager.max_turns]
	morale_label.text = "士气: %s (%d)" % [CampaignManager.get_morale_tier_name(), CampaignManager.campaign_morale]
	emi_label.text = "EMI: %.0f%%" % (EMISystem.current_intensity * 100)


func _update_hover_coordinate() -> void:
	"""计划阶段在左上角显示鼠标所在的地图坐标"""
	var mouse_position := get_viewport().get_mouse_position()
	var grid_position := tile_grid.grid_pos_at_screen(mouse_position)
	if GridManager.is_valid_cell(grid_position.x, grid_position.y):
		hover_coord_label.text = "地块坐标: %s" % \
			GridManager.grid_to_player_coordinate(grid_position)
	else:
		hover_coord_label.text = ""


func _on_phase_skip_pressed() -> void:
	finish_planning_button.disabled = true
	if GameManager.current_state == GameManager.GameState.PLANNING_PHASE:
		GameManager.finish_planning_early()
	elif GameManager.current_state == GameManager.GameState.EXECUTION_PHASE:
		GameManager.finish_execution_early()


## ==================== 关卡加载 ====================

func _on_level_started(level_id: int) -> void:
	print("[MainScene] 开始第 %d 关" % (level_id + 1))
	# 清空战报，记录关卡开始
	BattleLog.clear()
	BattleLog.add_log("第 %d 关 开始" % (level_id + 1), Color(0.8, 0.8, 0.8))
	var ld = LevelDatabase.get_level(level_id)

	# 刷新网格渲染
	tile_grid.show_coordinates = true
	tile_grid.queue_redraw()

	# 生成单位
	for cfg in ld.wp_units:
		var u = UnitDatabase.create_unit(cfg["type"], UnitBase.Faction.WARSAW_PACT, cfg["col"], cfg["row"], self)
		u.movement_points = 10
		u.remaining_movement = 10
	for cfg in ld.nato_units:
		var u = UnitDatabase.create_unit(cfg["type"], UnitBase.Faction.NATO, cfg["col"], cfg["row"], self)
		u.movement_points = 8
		u.remaining_movement = 8

	# 单位创建完毕后注册初始数量（用于伤亡率计算）
	VictoryManager.register_initial_units()

	# 手牌和事件
	CardSystem.initialize_level(ld.wp_starting_cards)
	# 起手多弃少补到7张并打开手牌面板
	CardSystem.adjust_hand_to(CardSystem.STARTING_HAND_SIZE)
	card_ui.is_panel_open = true
	card_ui.visible = true
	card_ui.queue_redraw()
	print("[MainScene] 起手调整至%d张 — 按 Tab 切换手牌面板" % CardSystem.STARTING_HAND_SIZE)
	for evt in ld.turn_events:
		TurnManager.register_turn_event(evt["turn"], evt)

	unit_renderer.queue_redraw()


## ==================== 输入 ====================

func _unhandled_input(event: InputEvent) -> void:
	if game_over_active:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_zoom_multiplier = minf(camera_zoom_multiplier * 1.12, 3.0)
			_apply_camera_transform()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_zoom_multiplier = maxf(camera_zoom_multiplier / 1.12, 0.3)
			_apply_camera_transform()
			return
	if not (event is InputEventMouseButton and event.pressed):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		_on_left_click(event.position)

	if event.button_index == MOUSE_BUTTON_RIGHT:
		_on_right_click(event.position)


func _on_left_click(screen_pos: Vector2) -> void:
	# 卡牌面板
	if card_ui.is_panel_open:
		var ci = card_ui.get_card_at_pos(screen_pos)
		if ci >= 0:
			card_ui.select_card(ci)
			return

	# 地图点击 → 格坐标
	var gp = tile_grid.grid_pos_at_screen(screen_pos)
	if not GridManager.is_valid_cell(gp.x, gp.y):
		return

	# 如果有选中卡牌 → 使用卡牌
	if card_ui.selected_card_index >= 0:
		card_ui.use_selected_card(gp.x, gp.y)
		return

	var clicked_unit = _get_unit_at(gp.x, gp.y)

	# 1) 点中己方单位 → 选中并显示移动范围
	if clicked_unit and clicked_unit.faction == UnitBase.Faction.WARSAW_PACT:
		selected_unit = clicked_unit
		tile_grid.highlight_move_range(clicked_unit)
		unit_renderer.select_unit(clicked_unit)
		print("[MainScene] 选中 %s at (%d,%d) 移动=%d 射程=%d" % [
			clicked_unit.unit_name, gp.x, gp.y,
			clicked_unit.get_effective_movement(), clicked_unit.get_effective_range()])
		return

	# 2) 已选中己方单位 → WEGO: 计划阶段只下移动指令，攻击在沙盘演绎自动判定
	#    点击任何格（含敌方所在格）都尝试寻路；移动时因占用检测会停在敌方前一格
	if selected_unit and selected_unit.is_alive:
		var path = TilePathfinding.find_path(selected_unit.grid_col, selected_unit.grid_row,
			gp.x, gp.y, selected_unit, selected_unit.get_effective_movement())
		if not path.is_empty():
			tile_grid.highlight_path(path)
			TurnManager.submit_order(selected_unit.unit_id, {"type": "move", "path": path}, true)
			print("[MainScene] 提交移动指令: %s → (%d,%d) 路径%d格" % [
				selected_unit.unit_name, gp.x, gp.y, path.size()])
		else:
			print("[MainScene] 无法到达 (%d,%d)" % [gp.x, gp.y])
		selected_unit = null
		unit_renderer.deselect_unit()
		# 保留路径高亮，1秒后清除
		await get_tree().create_timer(1.0).timeout
		tile_grid.clear_highlights()


func _on_right_click(pos: Vector2) -> void:
	# 右键点卡牌 → 弃牌（玩家自主弃牌入口）
	if card_ui.is_panel_open and card_ui.discard_card_at_pos(pos):
		return
	# 否则取消所有选择
	selected_unit = null
	tile_grid.clear_highlights()
	unit_renderer.deselect_unit()
	card_ui.selected_card_index = -1
	card_ui.queue_redraw()


func _get_unit_at(col: int, row: int) -> UnitBase:
	for u in get_tree().get_nodes_in_group("units"):
		if u.grid_col == col and u.grid_row == row:
			return u
	return null


## ==================== 状态回调 ====================

func _on_state_changed(_old: int, new: int) -> void:
	match new:
		GameManager.GameState.PLANNING_PHASE:
			print("[MainScene] <<< 计划阶段 >>> 请下达移动/攻击指令")
			game_over_active = false
		GameManager.GameState.EXECUTION_PHASE:
			print("[MainScene] >>> 沙盘演绎 <<<")
		GameManager.GameState.VICTORY:
			_show_game_over_panel(UnitBase.Faction.WARSAW_PACT, _get_game_over_reason())
		GameManager.GameState.DEFEAT:
			_show_game_over_panel(UnitBase.Faction.NATO, _get_game_over_reason())

func _on_planning_started(turn: int) -> void:
	print("[MainScene] 第%d回合计划开始" % turn)
	BattleLog.add_phase_log("第%d回合 · 计划阶段" % turn)
	# 重置所有单位移动点数
	for u in get_tree().get_nodes_in_group("units"):
		if u.is_alive:
			u.remaining_movement = u.movement_points

func _on_execution_started(turn: int) -> void:
	print("[MainScene] 第%d回合沙盘开始" % turn)
	BattleLog.add_phase_log("第%d回合 · 沙盘演绎" % turn)

func _on_turn_resolved(turn: int) -> void:
	print("[MainScene] 第%d回合结算" % turn)

func _on_attack_executed(_aid: int, _tc: int, _tr: int, result: Dictionary) -> void:
	if result.get("hit"):
		print("[MainScene] 命中! 伤害: %.1f" % result.get("damage", 0.0))
	unit_renderer.queue_redraw()

func _on_unit_destroyed(uid: int, _kid: int) -> void:
	print("[MainScene] 单位%d被摧毁" % uid)
	unit_renderer.queue_redraw()

func _on_unit_broken(uid: int) -> void:
	print("[MainScene] 单位%d士气崩溃!" % uid)

func _on_emi_changed(new_val: float, _old: float) -> void:
	print("[MainScene] EMI: %.0f%%" % (new_val * 100))

func _on_card_drawn(card) -> void:
	print("[MainScene] 抽到: %s" % card.card_name)


func _get_game_over_reason() -> String:
	"""从 VictoryManager 读取真正的胜利原因"""
	if VictoryManager.last_game_over_reason != "":
		return VictoryManager.last_game_over_reason
	return "战斗结束"


func _show_game_over_panel(winner_faction: int, reason: String) -> void:
	"""显示游戏结束面板"""
	if game_over_panel:
		return
	game_over_active = true

	var counts = VictoryManager.check_victory_now()
	var wp_alive: int = counts.wp_alive
	var nato_alive: int = counts.nato_alive

	var layer = CanvasLayer.new()
	layer.layer = 100
	layer.name = "GameOverLayer"
	add_child(layer)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(520, 320)
	panel.self_modulate = Color(0.08, 0.08, 0.1, 0.92)
	center.add_child(panel)

	# 面板边框（用Line2D或简单背景）
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.8, 0.75, 0.5) if winner_faction == UnitBase.Faction.WARSAW_PACT else Color(0.6, 0.65, 0.75)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 16)
	vbox.set_deferred("offset_left", 30)
	vbox.set_deferred("offset_right", -30)
	vbox.set_deferred("offset_top", 30)
	vbox.set_deferred("offset_bottom", -30)
	panel.add_child(vbox)

	# 标题
	var title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	if winner_faction == UnitBase.Faction.WARSAW_PACT:
		title.text = "华约胜利"
		title.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25))
	else:
		title.text = "北约胜利"
		title.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	vbox.add_child(title)

	# 原因
	var reason_label = Label.new()
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_label.add_theme_font_size_override("font_size", 20)
	reason_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	reason_label.text = reason
	vbox.add_child(reason_label)

	# 统计 — 含VP控制信息
	var vp = VictoryManager._count_vp_control()
	var stats = Label.new()
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 18)
	stats.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	stats.text = "第 %d / %d 回合\n华约控制VP: %d    北约控制VP: %d\n华约剩余单位: %d    北约剩余单位: %d" % [
		TurnManager.current_turn, VictoryManager.max_turns, vp.wp, vp.nato, wp_alive, nato_alive]
	vbox.add_child(stats)

	# 按钮
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(hbox)

	var restart_btn = Button.new()
	restart_btn.text = "重新开始"
	restart_btn.custom_minimum_size = Vector2(140, 48)
	restart_btn.pressed.connect(_on_restart_pressed)
	hbox.add_child(restart_btn)

	var quit_btn = Button.new()
	quit_btn.text = "退出游戏"
	quit_btn.custom_minimum_size = Vector2(140, 48)
	quit_btn.pressed.connect(_on_quit_pressed)
	hbox.add_child(quit_btn)

	game_over_panel = layer
	BattleLog.add_log("━━━ 游戏结束 — %s ━━━" % ("华约胜利" if winner_faction == UnitBase.Faction.WARSAW_PACT else "北约胜利"), Color.GOLD)


func _on_restart_pressed() -> void:
	"""重新开始当前关卡"""
	if game_over_panel:
		game_over_panel.queue_free()
		game_over_panel = null
	game_over_active = false
	VictoryManager.reset()
	# 重载整个主场景，干净地重新开始
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	"""退出游戏"""
	get_tree().quit()


func _on_unit_step(_uid: int, _col: int, _row: int) -> void:
	# 沙盘演绎: 单位每走一格刷新画面
	unit_renderer.queue_redraw()
	tile_grid.queue_redraw()


func _on_unit_move_completed(_uid: int, _col: int, _row: int) -> void:
	unit_renderer.queue_redraw()
