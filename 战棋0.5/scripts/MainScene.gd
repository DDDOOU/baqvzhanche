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
var action_hint_label: Label
var victory_progress_label: RichTextLabel
var hover_info_panel: PanelContainer
var hover_info_label: Label
var finish_planning_button: Button
var card_toggle_button: Button
var pause_button: Button
var confirm_move_button: Button
var cancel_move_button: Button
var loan_button: Button
var pause_overlay: PauseMenu
var selected_unit: UnitBase = null
var pending_move_unit: UnitBase = null
var pending_move_path: Array = []
var pending_move_target: Vector2i = Vector2i(-1, -1)
var game_over_active: bool = false
var game_over_panel: CanvasLayer = null
var briefing_panel: CanvasLayer = null   # 任务简报浮窗（LEVEL_INTRO）
var tutorial: Node = null                # 教学引导（第1关新手教程）
var is_paused: bool = false
var is_card_area_flash_active: bool = false
var building_by_cell: Dictionary = {}
var building_owner_by_cell: Dictionary = {}
var _last_vp_size: Vector2 = Vector2.ZERO
var level_scene_instance: Node2D
var level_terrain: TileMapLayer
var level_used_rect: Rect2i
var base_camera_offset: Vector2 = Vector2.ZERO
var base_camera_zoom: float = 1.0
var camera_pan: Vector2 = Vector2.ZERO
var camera_zoom_multiplier: float = 1.0
var is_dragging_map: bool = false
var drag_start_mouse: Vector2 = Vector2.ZERO
var drag_start_pan: Vector2 = Vector2.ZERO
var drag_moved: bool = false
var startup_level_id: int = -1
const CAMERA_PAN_SPEED: float = 420.0
const CAMERA_MIN_ZOOM: float = 0.05
const CAMERA_MAX_ZOOM: float = 2.0
const CAMERA_ZOOM_STEP: float = 1.12
const MAP_DRAG_THRESHOLD: float = 4.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("=".repeat(50))
	print("  Silent Reckoning·1987  静默行动·1987")
	print("=".repeat(50))

	var level_id := startup_level_id if startup_level_id >= 0 else GameManager.current_level_id
	_load_designed_level(level_id)
	_connect_signals()
	_setup_ui()
	_fit_camera_to_map()
	_last_vp_size = get_viewport_rect().size

	# 窗口缩放时重新计算相机，保证网格和单位始终对齐
	get_viewport().size_changed.connect(_on_viewport_resized)

	# 直接启动指定关卡
	GameManager.start_level(level_id)


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
		push_error("%s 中找不到 Terrain TileMapLayer" % scene_path)
		return

	level_used_rect = level_terrain.get_used_rect()
	if level_used_rect.size.x <= 0 or level_used_rect.size.y <= 0:
		push_error("%s 的 Terrain 尚未绘制地块" % scene_path)
		return

	var extracted := _extract_tilemap_data()
	GameManager.set_runtime_map(extracted, level_used_rect.size)
	GridManager.MAP_WIDTH = level_used_rect.size.x
	GridManager.MAP_HEIGHT = level_used_rect.size.y
	tile_grid.use_source_tilemap(level_terrain, level_used_rect)
	tile_grid.set_building_highlights(building_owner_by_cell)
	unit_renderer.use_source_tilemap(level_terrain, level_used_rect)
	print("[MainScene] 使用设计关卡 %s，地图尺寸=%dx%d，原始起点=(%d,%d)" % [
		scene_path, level_used_rect.size.x, level_used_rect.size.y,
		level_used_rect.position.x, level_used_rect.position.y])


func _extract_tilemap_data() -> Dictionary:
	var terrain_list: Array[Dictionary] = []
	building_by_cell.clear()
	building_owner_by_cell.clear()
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

	# 建筑以左上角地图坐标为锚点，占用2×2四格。
	# 被建筑占用的格子会进入运行时地图并被标记为不可通行。
	for building in level_scene_instance.find_children("*", "Building2D", true, false):
		building.sync_grid_from_saved_position()
		var building_owner := _get_building_owner(building)
		for occupied_for_lookup: Vector2i in building.get_occupied_cells():
			var lookup_key := "%d,%d" % [occupied_for_lookup.x, occupied_for_lookup.y]
			building_by_cell[lookup_key] = building
			building_owner_by_cell[lookup_key] = building_owner
		if not building.blocks_movement:
			continue
		var blocked_cells: Array[String] = []
		for occupied: Vector2i in building.get_occupied_cells():
			for cell_data in terrain_list:
				if cell_data.col == occupied.x and cell_data.row == occupied.y:
					cell_data["passable"] = false
					cell_data["building_name"] = building.building_name
					blocked_cells.append(GridManager.grid_to_player_coordinate(occupied))
					break
		print("[MainScene] 建筑 %s 占地: %s" % [building.building_name, ", ".join(blocked_cells)])

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


func _get_building_owner(building: Building2D) -> int:
	var building_label := String(building.name).to_lower() + " " + building.building_name.to_lower()
	if building_label.contains("wp") or building_label.contains("west") or building_label.contains("southwest"):
		return UnitBase.Faction.WARSAW_PACT
	if building_label.contains("nato") or building_label.contains("east"):
		return UnitBase.Faction.NATO
	var map_mid := int(level_used_rect.size.x / 2.0)
	return UnitBase.Faction.WARSAW_PACT if building.grid_coordinate.x < map_mid else UnitBase.Faction.NATO


func _clean_terrain_name(value: Variant) -> String:
	var result := str(value).strip_edges()
	while result.begins_with("\""):
		result = result.trim_prefix("\"").strip_edges()
	while result.ends_with("\""):
		result = result.trim_suffix("\"").strip_edges()
	return result.to_lower()


func _terrain_enum_from_name(terrain_name: String) -> int:
	match terrain_name:
		"soil", "dirt", "grass", "plains":
			return GridManager.TerrainType.PLAINS
		"water", "river":
			return GridManager.TerrainType.RIVER
		"rock", "mountain":
			return GridManager.TerrainType.MOUNTAIN
		"brush", "bush", "forest":
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
	# 说明
	_fit_camera_to_map()


## ==================== 淇″彿 ====================

func _connect_signals() -> void:
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.level_started.connect(_on_level_started)
	TurnManager.planning_phase_started.connect(_on_planning_started)
	TurnManager.execution_phase_started.connect(_on_execution_started)
	TurnManager.turn_resolved.connect(_on_turn_resolved)
	TurnManager.round_event_triggered.connect(_on_round_event_triggered)
	CombatSystem.attack_executed.connect(_on_attack_executed)
	CombatSystem.unit_destroyed.connect(_on_unit_destroyed)
	MoraleSystem.unit_broken.connect(_on_unit_broken)
	EMISystem.intensity_changed.connect(_on_emi_changed)
	CardSystem.card_drawn.connect(_on_card_drawn)
	CardSystem.card_used.connect(_on_card_used)
	# 移动每步/完成都刷新单位渲染，沙盘演示时实时看到移动/攻击掉血
	MovementSystem.unit_step.connect(_on_unit_step)
	MovementSystem.unit_move_completed.connect(_on_unit_move_completed)


## ==================== HUD ====================

func _setup_ui() -> void:
	var hud = CanvasLayer.new()
	hud.layer = 10
	add_child(hud)

	var card_layer = CanvasLayer.new()
	card_layer.layer = 20
	add_child(card_layer)
	card_ui.reparent(card_layer)
	card_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_ui.offset_left = 0
	card_ui.offset_top = 0
	card_ui.offset_right = 0
	card_ui.offset_bottom = 0

	turn_label = _make_label(Vector2(10, 10), Color.WHITE, "第 1 回合")
	morale_label = _make_label(Vector2(10, 35), Color.GOLD, "士气: 昂扬 (80)")
	emi_label = _make_label(Vector2(10, 60), Color.RED, "EMI: 0%")
	phase_timer_label = _make_label(Vector2(10, 85), Color.CYAN, "")
	hover_coord_label = _make_label(Vector2(10, 110), Color(0.75, 0.9, 1.0), "")
	for lbl in [turn_label, morale_label, emi_label, phase_timer_label, hover_coord_label]:
		hud.add_child(lbl)

	action_hint_label = _make_label(Vector2(10, 272), Color(0.92, 0.9, 0.7),
		"操作：点击己方单位 → 点击蓝格移动 / 点击红色敌军攻击；Tab 使用卡牌；Enter 结束计划")
	action_hint_label.add_theme_font_size_override("font_size", 13)
	hud.add_child(action_hint_label)

	finish_planning_button = Button.new()
	finish_planning_button.position = Vector2(10, 138)
	finish_planning_button.size = Vector2(150, 36)
	finish_planning_button.text = "结束计划"
	finish_planning_button.tooltip_text = "结束计划阶段"
	finish_planning_button.visible = false
	finish_planning_button.pressed.connect(_on_phase_skip_pressed)
	hud.add_child(finish_planning_button)

	card_toggle_button = Button.new()
	card_toggle_button.position = Vector2(170, 138)
	card_toggle_button.size = Vector2(120, 36)
	card_toggle_button.tooltip_text = "展开或收起卡牌栏（Tab）"
	card_toggle_button.pressed.connect(_on_card_toggle_pressed)
	hud.add_child(card_toggle_button)
	_sync_card_toggle_button()

	pause_button = Button.new()
	pause_button.position = Vector2(300, 138)
	pause_button.size = Vector2(96, 36)
	pause_button.text = "暂停"
	pause_button.tooltip_text = "暂停/继续（P）"
	pause_button.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_button.pressed.connect(_on_pause_pressed)
	hud.add_child(pause_button)

	confirm_move_button = Button.new()
	confirm_move_button.position = Vector2(406, 138)
	confirm_move_button.size = Vector2(96, 36)
	confirm_move_button.text = "确认移动"
	confirm_move_button.visible = false
	confirm_move_button.pressed.connect(_on_confirm_move_pressed)
	hud.add_child(confirm_move_button)

	cancel_move_button = Button.new()
	cancel_move_button.position = Vector2(512, 138)
	cancel_move_button.size = Vector2(96, 36)
	cancel_move_button.text = "取消"
	cancel_move_button.visible = false
	cancel_move_button.pressed.connect(_on_cancel_move_pressed)
	hud.add_child(cancel_move_button)

	loan_button = Button.new()
	loan_button.position = Vector2(618, 138)
	loan_button.size = Vector2(142, 36)
	loan_button.text = "指挥贷款 +1牌"
	loan_button.tooltip_text = "立即抽1张牌；下回合少抽1张，战役贷款+10"
	loan_button.visible = false
	loan_button.pressed.connect(_on_loan_pressed)
	hud.add_child(loan_button)

	_create_hover_info_panel(hud)
	_create_victory_progress_panel(hud)
	_create_pause_overlay()

	var battle_log_ui = preload("res://scripts/ui/BattleLogUI.gd").new()
	hud.add_child(battle_log_ui)


func _make_label(pos: Vector2, color: Color, text: String) -> Label:
	var l = Label.new()
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	l.text = text
	return l


func _create_victory_progress_panel(hud: CanvasLayer) -> void:
	victory_progress_label = RichTextLabel.new()
	victory_progress_label.bbcode_enabled = true
	victory_progress_label.scroll_active = false
	victory_progress_label.selection_enabled = false
	victory_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	victory_progress_label.add_theme_stylebox_override("normal", _make_translucent_panel_stylebox())
	victory_progress_label.add_theme_font_size_override("normal_font_size", 12)
	hud.add_child(victory_progress_label)
	get_viewport().size_changed.connect(_layout_victory_progress_panel)
	_layout_victory_progress_panel()


func _layout_victory_progress_panel() -> void:
	if victory_progress_label == null:
		return
	var vp := get_viewport_rect().size
	var panel_w := minf(360.0, maxf(280.0, vp.x * 0.28))
	victory_progress_label.position = Vector2(10, 180)
	victory_progress_label.size = Vector2(panel_w, 86)


func _make_translucent_panel_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.78)
	sb.border_color = Color(0.45, 0.45, 0.55, 0.85)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	return sb


func _create_hover_info_panel(hud: CanvasLayer) -> void:
	hover_info_panel = PanelContainer.new()
	hover_info_panel.visible = false
	hover_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.06, 0.88)
	style.border_color = Color(0.75, 0.82, 0.9, 0.85)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	hover_info_panel.add_theme_stylebox_override("panel", style)
	hud.add_child(hover_info_panel)

	hover_info_label = Label.new()
	hover_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_info_label.add_theme_color_override("font_color", Color.WHITE)
	hover_info_label.add_theme_font_size_override("font_size", 14)
	hover_info_panel.add_child(hover_info_label)


func _create_pause_overlay() -> void:
	pause_overlay = PauseMenu.new()
	pause_overlay.resume_requested.connect(_on_pause_pressed)
	pause_overlay.save_requested.connect(_on_save_pressed)
	pause_overlay.menu_requested.connect(_return_to_main_menu)
	add_child(pause_overlay)


func _process(delta: float) -> void:
	# 帧检测兜底：视口尺寸变化时重算相机，覆盖最大化/还原/拖拽缩放
	var vp = get_viewport_rect().size
	if vp != _last_vp_size:
		_last_vp_size = vp
		_fit_camera_to_map()
	_update_hover_cell()

	if not is_paused:
		var move_direction := Vector2.ZERO
		if Input.is_action_pressed("camera_left"):
			move_direction.x += 1.0
		if Input.is_action_pressed("camera_right"):
			move_direction.x -= 1.0
		if Input.is_action_pressed("camera_up"):
			move_direction.y += 1.0
		if Input.is_action_pressed("camera_down"):
			move_direction.y -= 1.0
		if move_direction != Vector2.ZERO:
			camera_pan += move_direction.normalized() * CAMERA_PAN_SPEED * delta
			_apply_camera_transform()

	if TurnManager.is_planning:
		phase_timer_label.text = "计划阶段: %.0fs" % TurnManager.get_remaining_planning_time()
		_update_hover_coordinate()
		finish_planning_button.visible = true
		finish_planning_button.disabled = false
		finish_planning_button.text = "结束计划"
		finish_planning_button.tooltip_text = "结束计划阶段"
	elif TurnManager.is_executing:
		phase_timer_label.text = "演算阶段: %.0fs" % TurnManager.get_remaining_execution_time()
		hover_coord_label.text = ""
		finish_planning_button.visible = true
		finish_planning_button.disabled = false
		finish_planning_button.text = "跳过演算"
		finish_planning_button.tooltip_text = "跳过剩余演算等待"
	else:
		phase_timer_label.text = ""
		hover_coord_label.text = ""
		finish_planning_button.visible = false
	turn_label.text = "第%d回合 / 共%d回合" % [TurnManager.current_turn, CampaignManager.max_turns]
	morale_label.text = "士气: %s (%d)" % [CampaignManager.get_morale_tier_name(), CampaignManager.campaign_morale]
	emi_label.text = "EMI: %.0f%%" % (EMISystem.current_intensity * 100)
	_update_victory_progress()
	_sync_card_toggle_button()
	_sync_move_confirmation_buttons()


func _update_hover_coordinate() -> void:
	# 说明
	var mouse_position := get_viewport().get_mouse_position()
	if _is_pointer_over_interface(mouse_position):
		hover_coord_label.text = ""
		return
	var grid_position := tile_grid.grid_pos_at_screen(mouse_position)
	if GridManager.is_valid_cell(grid_position.x, grid_position.y):
		hover_coord_label.text = "地块坐标: %s" % \
			GridManager.grid_to_player_coordinate(grid_position)
	else:
		hover_coord_label.text = ""


func _update_hover_cell() -> void:
	var mouse_position := get_viewport().get_mouse_position()
	if _is_pointer_over_interface(mouse_position):
		tile_grid.set_hover_cell(Vector2i(-1, -1))
		tile_grid.clear_card_highlight()
		_set_hover_info("", mouse_position)
		return
	var grid_position := tile_grid.grid_pos_at_screen(mouse_position)
	tile_grid.set_hover_cell(grid_position)
	_update_hover_info(mouse_position, grid_position)
	_update_card_area_preview(grid_position)


func _update_hover_info(mouse_position: Vector2, grid_position: Vector2i) -> void:
	if not GridManager.is_valid_cell(grid_position.x, grid_position.y):
		_set_hover_info("", mouse_position)
		return
	var unit := unit_renderer.get_unit_at_position(mouse_position)
	if unit and unit.is_alive:
		var faction_name := "华约" if unit.faction == UnitBase.Faction.WARSAW_PACT else "北约"
		_set_hover_info("%s\n%s  HP %.0f/%.0f" % [
			unit.unit_name, faction_name, unit.current_health, unit.max_health], mouse_position)
		return
	var building := _get_building_at_cell(grid_position)
	if building:
		var building_owner := int(building_owner_by_cell.get(_cell_key(grid_position), UnitBase.Faction.NATO))
		var owner_name := "我方建筑" if building_owner == UnitBase.Faction.WARSAW_PACT else "敌方建筑"
		_set_hover_info("%s\n%s" % [building.building_name, owner_name], mouse_position)
		return
	_set_hover_info("", mouse_position)


func _set_hover_info(text: String, mouse_position: Vector2) -> void:
	if hover_info_panel == null or hover_info_label == null:
		return
	if text == "":
		hover_info_panel.visible = false
		return
	hover_info_label.text = text
	hover_info_panel.visible = true
	var pos := mouse_position + Vector2(18, 18)
	var vp := get_viewport_rect().size
	var estimated_size := Vector2(240, 58)
	if pos.x + estimated_size.x > vp.x:
		pos.x = maxf(8.0, mouse_position.x - estimated_size.x - 18.0)
	if pos.y + estimated_size.y > vp.y:
		pos.y = maxf(8.0, mouse_position.y - estimated_size.y - 18.0)
	hover_info_panel.position = pos


func _update_card_area_preview(grid_position: Vector2i) -> void:
	if is_card_area_flash_active:
		return
	if card_ui.selected_card_index < 0 or card_ui.selected_card_index >= CardSystem.hand.size():
		tile_grid.clear_card_highlight()
		return
	if not GridManager.is_valid_cell(grid_position.x, grid_position.y):
		tile_grid.clear_card_highlight()
		return
	var card = CardSystem.hand[card_ui.selected_card_index]
	tile_grid.set_card_highlight(_get_card_effect_cells(card.card_id, grid_position), _get_card_highlight_color(card))


func _get_card_effect_cells(card_id: String, center: Vector2i) -> Array:
	match card_id:
		"blind_fire_barrage":
			return _get_square_cells(center, 3)
		"call_artillery":
			return _get_square_cells(center, 2)
		"smoke_screen":
			return _get_square_cells(center, 4)
		_:
			return [center]


func _get_square_cells(center: Vector2i, area_size: int) -> Array:
	var cells: Array = []
	var half := int(area_size / 2.0)
	for dc in range(-half, area_size - half):
		for dr in range(-half, area_size - half):
			var cell := Vector2i(center.x + dc, center.y + dr)
			if GridManager.is_valid_cell(cell.x, cell.y):
				cells.append(cell)
	return cells


func _get_card_highlight_color(card) -> Color:
	match card.card_id:
		"blind_fire_barrage", "call_artillery", "sacrifice_charge":
			return Color(1.0, 0.28, 0.08, 0.45)
		"smoke_screen":
			return Color(0.72, 0.72, 0.72, 0.42)
		"fortify_position":
			return Color(0.15, 0.9, 0.35, 0.42)
		"sapper_mines":
			return Color(1.0, 0.78, 0.12, 0.45)
		"coordinate_prediction":
			return Color(0.25, 0.72, 1.0, 0.42)
		"power_cut", "emi_countermeasure":
			return Color(0.75, 0.35, 1.0, 0.42)
		_:
			return Color(0.95, 0.7, 0.2, 0.40)


func _flash_card_area(cells: Array, color: Color) -> void:
	is_card_area_flash_active = true
	tile_grid.set_card_highlight(cells, color.lightened(0.12))
	await get_tree().create_timer(0.85).timeout
	is_card_area_flash_active = false
	tile_grid.clear_card_highlight()


func _get_building_at_cell(cell: Vector2i) -> Building2D:
	return building_by_cell.get(_cell_key(cell), null) as Building2D


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _update_victory_progress() -> void:
	if victory_progress_label == null:
		return
	var vp = VictoryManager.get_vp_control()
	var counts := _count_alive_units_local()
	var vp_total := GridManager.vp_cells.size()
	victory_progress_label.text = "[font_size=12][color=#e8e4bf][b]胜利条件[/b][/color]  第%d回合结束守住至少2个VP\n[color=#d8d8d8]进度[/color]  第%d/%d回合   VP 我方%d/%d 敌方%d 中立%d\n[color=#d8d8d8]单位[/color]  我方%d 敌方%d    [color=#6ab7ff]蓝[/color]=我方建筑 [color=#ff766c]红[/color]=敌方建筑[/font_size]" % [
		VictoryManager.max_turns, TurnManager.current_turn, VictoryManager.max_turns,
		vp.wp, vp_total, vp.nato, vp.neutral,
		counts.wp, counts.nato]


func _count_alive_units_local() -> Dictionary:
	var counts := {"wp": 0, "nato": 0}
	for unit in get_tree().get_nodes_in_group("units"):
		if not unit.is_alive:
			continue
		if unit.faction == UnitBase.Faction.WARSAW_PACT:
			counts.wp += 1
		elif unit.faction == UnitBase.Faction.NATO:
			counts.nato += 1
	return counts


func _on_phase_skip_pressed() -> void:
	if is_paused:
		return
	finish_planning_button.disabled = true
	if GameManager.current_state == GameManager.GameState.PLANNING_PHASE:
		GameManager.finish_planning_early()
	elif GameManager.current_state == GameManager.GameState.EXECUTION_PHASE:
		GameManager.finish_execution_early()


func _on_card_toggle_pressed() -> void:
	if is_paused:
		return
	_set_card_panel_open(not card_ui.is_panel_open)


func _on_loan_pressed() -> void:
	if is_paused or GameManager.current_state != GameManager.GameState.PLANNING_PHASE:
		return
	if CardSystem.activate_loan():
		SoundManager.play("loan_coin", -3.0)
		BattleLog.add_log("指挥贷款启用：立即抽1张牌，下回合手牌-1。", Color(1.0, 0.82, 0.35))
		_set_action_hint("贷款已使用：本回合多1张牌，下回合将少抽1张。")
	_sync_loan_button()


func _sync_loan_button() -> void:
	if loan_button == null or not loan_button.visible:
		return
	loan_button.disabled = is_paused or not CardSystem.loan_available or GameManager.current_state != GameManager.GameState.PLANNING_PHASE
	loan_button.text = "贷款已使用" if not CardSystem.loan_available else "指挥贷款 +1牌"


func _set_card_panel_open(open: bool) -> void:
	card_ui.is_panel_open = open
	card_ui.visible = open
	if not open:
		card_ui.selected_card_index = -1
	card_ui.queue_redraw()
	_sync_card_toggle_button()


func _sync_card_toggle_button() -> void:
	if card_toggle_button == null:
		return
	card_toggle_button.text = "收起卡牌" if card_ui.is_panel_open else "展开卡牌"


## ==================== 关卡加载 ====================

func _on_level_started(level_id: int) -> void:
	print("[MainScene] 开始第 %d 关" % (level_id + 1))
	# 清空战报，记录关卡开始
	BattleLog.clear()
	BattleLog.add_log("第 %d 关开始" % (level_id + 1), Color(0.8, 0.8, 0.8))
	var ld = LevelDatabase.get_level(level_id)
	loan_button.visible = level_id == 1
	_sync_loan_button()

	# 天气视觉（雾/雪），按关卡 weather 配置
	var weather_layer = (load("res://scripts/ui/WeatherLayer.gd") as GDScript).new()
	weather_layer.name = "WeatherLayer"
	add_child(weather_layer)
	weather_layer.setup(ld.weather)

	# 教学引导：仅第 1 关且本次运行内未完成时启用
	if level_id == 0 and not GameManager.tutorial_done and tutorial == null:
		var tut = (load("res://scripts/ui/TutorialManager.gd") as GDScript).new()
		tut.name = "TutorialManager"
		add_child(tut)
		tut.setup()
		tutorial = tut

	if not String(ld.briefing).is_empty():
		BattleLog.add_log("任务简报：%s" % ld.briefing, Color(0.85, 0.88, 1.0))
	if not String(ld.intel_a).is_empty():
		BattleLog.add_log("情报：%s" % ld.intel_a, Color(0.65, 0.82, 1.0))

	# 刷新网格渲染
	tile_grid.show_coordinates = true
	tile_grid.queue_redraw()

	# 生成单位（移动力取自 UnitDatabase 配置，不覆盖）
	for cfg in ld.wp_units:
		UnitDatabase.create_unit(cfg["type"], UnitBase.Faction.WARSAW_PACT, cfg["col"], cfg["row"], self)
	for cfg in ld.nato_units:
		UnitDatabase.create_unit(cfg["type"], UnitBase.Faction.NATO, cfg["col"], cfg["row"], self)

	_apply_level_start_effects(ld)

	# 手牌和事件
	CardSystem.initialize_level(ld.wp_starting_cards)
	# 起手多弃少补到7张并打开手牌面板
	CardSystem.adjust_hand_to(CardSystem.STARTING_HAND_SIZE)
	_set_card_panel_open(true)
	print("[MainScene] 起手调整至%d张，按 Tab 切换手牌面板" % CardSystem.STARTING_HAND_SIZE)
	for evt in ld.turn_events:
		TurnManager.register_turn_event(evt["turn"], evt)
	# 读取存档时以保存的动态单位和系统状态覆盖关卡初始值。
	if not GameManager.apply_pending_save(self):
		VictoryManager.register_initial_units()

	unit_renderer.queue_redraw()


func _apply_level_start_effects(level_data) -> void:
	"""把关卡天气等数据真正应用到单位，而不只停留在数据库描述中。"""
	var vision_penalty: int = maxi(0, level_data.weather_vision_penalty)
	for unit in get_tree().get_nodes_in_group("units"):
		unit.set_meta("base_vision_range", unit.vision_range)
		if level_data.weather != "clear" and vision_penalty > 0:
			unit.vision_range = maxi(1, unit.vision_range - vision_penalty)
	if level_data.weather == "fog":
		BattleLog.add_log("晨雾笼罩战场：全体视野降低%d格" % vision_penalty, Color(0.7, 0.8, 0.9))
	elif level_data.weather == "snow":
		BattleLog.add_log("大雪覆盖战场：全体视野降低%d格，车辆辙印更易暴露。" % vision_penalty, Color(0.8, 0.9, 1.0))


func _on_round_event_triggered(event_id: String, data: Dictionary) -> void:
	var description := String(data.get("description", event_id))
	BattleLog.add_log("事件：%s" % description, Color(1.0, 0.78, 0.3))
	match event_id:
		"fog_warning":
			pass # 初始雾效已在单位生成后应用。
		"fog_lifts":
			_restore_unit_vision()
		"ah64_arrives":
			_spawn_reinforcement(UnitBase.UnitType.AH64_HELICOPTER, UnitBase.Faction.NATO)
		"loan_tutorial":
			_set_action_hint("第2关机制：可用“指挥贷款”立即多抽1张牌，但下回合少抽1张。")
			_sync_loan_button()
		"nato_engineer":
			BattleLog.add_log("北约工兵开始清理通往铁路桥的雷区；工兵进入雷区不会受损。", Color(1.0, 0.58, 0.28))
		"emi_rise_15":
			var target_intensity := float(data.get("emi_target", 0.15))
			EMISystem.change_base_intensity(target_intensity - EMISystem.base_intensity)
		"reserve_ready":
			if CardSystem.grant_card("reserve_deployment"):
				BattleLog.add_log("华约预备队已就绪：“预备队投入”加入手牌。", Color(0.3, 1.0, 0.45))
		"refugee_convoy":
			_spawn_unit_near(UnitBase.UnitType.CIVILIAN_CONVOY, UnitBase.Faction.NEUTRAL, Vector2i(11, 9))
		"flood_preview":
			_set_action_hint("“洪水”干扰即将启动：高EMI会降低命中、侦察并扰乱卡牌。")
		"emi_surge":
			EMISystem.change_base_intensity(0.60 - EMISystem.base_intensity)
		"nato_blind_fire":
			BattleLog.add_log("北约转入盲射压制，中央走廊将成为高风险区域。", Color(1.0, 0.52, 0.3))
		"unknown_contacts":
			_spawn_unit_near(UnitBase.UnitType.UNKNOWN_CONTACT, UnitBase.Faction.NEUTRAL, Vector2i(10, 5))
			_spawn_unit_near(UnitBase.UnitType.UNKNOWN_CONTACT, UnitBase.Faction.NEUTRAL, Vector2i(10, 8))
		"forest_unknown":
			_spawn_unit_near(UnitBase.UnitType.UNKNOWN_CONTACT, UnitBase.Faction.NEUTRAL, Vector2i(10, 3))
			_spawn_unit_near(UnitBase.UnitType.UNKNOWN_CONTACT, UnitBase.Faction.NEUTRAL, Vector2i(9, 9))
		"unknown_d":
			_spawn_unit_near(UnitBase.UnitType.UNKNOWN_CONTACT, UnitBase.Faction.NEUTRAL, Vector2i(10, 3))
		"unknown_j":
			_spawn_unit_near(UnitBase.UnitType.UNKNOWN_CONTACT, UnitBase.Faction.NEUTRAL, Vector2i(9, 9))
		"unknown_e":
			_spawn_unit_near(UnitBase.UnitType.UNKNOWN_CONTACT, UnitBase.Faction.NEUTRAL, Vector2i(8, 4))
		"bridge_decision":
			CardSystem.grant_card("sapper_mines")
			_set_action_hint("断桥抉择：可用工兵布雷拖延敌军；桥梁取舍将在后续美术/剧情版扩展。")
		"nato_pontoon":
			_spawn_reinforcement(UnitBase.UnitType.NATO_ENGINEER, UnitBase.Faction.NATO)
		"emi_rise":
			EMISystem.change_base_intensity(float(data.get("emi_delta", 0.05)))
		"unknown_contact_1":
			_spawn_unit_near(UnitBase.UnitType.UNKNOWN_CONTACT, UnitBase.Faction.NEUTRAL, Vector2i(10, 9))
		"artillery_ready":
			CardSystem.draw_card(1)
		_:
			if event_id.begins_with("emi_rise"):
				EMISystem.change_base_intensity(float(data.get("emi_delta", 0.05)))
	unit_renderer.queue_redraw()
	tile_grid.queue_redraw()


func _restore_unit_vision() -> void:
	for unit in get_tree().get_nodes_in_group("units"):
		if unit.has_meta("base_vision_range"):
			unit.vision_range = int(unit.get_meta("base_vision_range"))
	BattleLog.add_log("晨雾消散：单位视野恢复", Color(0.65, 0.9, 1.0))


func _spawn_reinforcement(unit_type: int, faction: int) -> UnitBase:
	var spawn_cells: Array = GridManager.spawn_nato if faction == UnitBase.Faction.NATO else GridManager.spawn_wp
	for spawn in spawn_cells:
		var unit := _spawn_unit_near(unit_type, faction, spawn)
		if unit:
			return unit
	BattleLog.add_log("增援抵达失败：没有可用出生点", Color(1.0, 0.35, 0.35))
	return null


func _spawn_unit_near(unit_type: int, faction: int, preferred: Vector2i) -> UnitBase:
	var candidates: Array[Vector2i] = [preferred]
	for cell in GridManager.get_neighbors(preferred.x, preferred.y):
		candidates.append(Vector2i(cell.x, cell.y))
	for pos in candidates:
		var grid_cell = GridManager.get_cell(pos.x, pos.y)
		if grid_cell == null or not grid_cell.is_passable_for(false) or grid_cell.occupant_unit:
			continue
		var unit := UnitDatabase.create_unit(unit_type, faction, pos.x, pos.y, self)
		unit.set_meta("base_vision_range", unit.vision_range)
		var ld = LevelDatabase.get_level(GameManager.current_level_id)
		if ld and ld.weather == "fog" and TurnManager.current_turn < 4:
			unit.vision_range = maxi(1, unit.vision_range - maxi(0, ld.weather_vision_penalty))
		BattleLog.add_log("增援抵达：%s (%s)" % [unit.unit_name, GridManager.grid_to_player_coordinate(pos)], Color(1.0, 0.75, 0.25))
		return unit
	return null


## ==================== 输入 ====================

func _input(event: InputEvent) -> void:
	if game_over_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key_input(event)
		return
	if is_paused:
		return

	if event is InputEventMouseMotion:
		if is_dragging_map:
			var drag_delta: Vector2 = event.position - drag_start_mouse
			drag_moved = drag_moved or drag_delta.length() >= MAP_DRAG_THRESHOLD
			camera_pan = drag_start_pan + drag_delta
			_apply_camera_transform()
			get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseButton):
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _is_pointer_over_button(event.position):
				return
			if _is_pointer_over_card_panel(event.position):
				_on_left_click(event.position)
				get_viewport().set_input_as_handled()
				return
			is_dragging_map = true
			drag_start_mouse = event.position
			drag_start_pan = camera_pan
			drag_moved = false
			get_viewport().set_input_as_handled()
		else:
			if not is_dragging_map:
				return
			is_dragging_map = false
			if not drag_moved:
				_on_left_click(event.position)
			get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _is_pointer_over_button(event.position):
			return
		_on_right_click(event.position)
		get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		if not _is_pointer_over_interface(event.position):
			_zoom_camera_at(event.position, CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		if not _is_pointer_over_interface(event.position):
			_zoom_camera_at(event.position, 1.0 / CAMERA_ZOOM_STEP)
			get_viewport().set_input_as_handled()
		return


func _zoom_camera_at(screen_pos: Vector2, factor: float) -> void:
	var old_zoom := clampf(base_camera_zoom * camera_zoom_multiplier,
		CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)
	var old_offset := base_camera_offset + camera_pan
	var world_under_mouse := (screen_pos - old_offset) / old_zoom
	var safe_base_zoom := maxf(base_camera_zoom, 0.001)
	camera_zoom_multiplier = clampf(camera_zoom_multiplier * factor,
		CAMERA_MIN_ZOOM / safe_base_zoom, CAMERA_MAX_ZOOM / safe_base_zoom)
	var new_zoom := clampf(base_camera_zoom * camera_zoom_multiplier,
		CAMERA_MIN_ZOOM, CAMERA_MAX_ZOOM)
	if is_equal_approx(old_zoom, new_zoom):
		return
	var new_offset := screen_pos - world_under_mouse * new_zoom
	camera_pan = new_offset - base_camera_offset
	_apply_camera_transform()


func _on_pause_pressed() -> void:
	_set_game_paused(not is_paused)


func _on_save_pressed() -> void:
	GameManager.save_game(0)
	BattleLog.add_log("进度已保存", Color(0.65, 1.0, 0.7))
	if pause_overlay:
		pause_overlay.show_status("保存成功")


func _return_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _set_game_paused(paused: bool) -> void:
	is_paused = paused
	get_tree().paused = paused
	if pause_overlay:
		pause_overlay.visible = paused
	if pause_button:
		pause_button.text = "继续" if paused else "暂停"
	is_dragging_map = false
	_sync_move_confirmation_buttons()
	_sync_loan_button()


func _sync_move_confirmation_buttons() -> void:
	var can_order := GameManager.current_state == GameManager.GameState.PLANNING_PHASE and not TurnManager.orders_locked
	var has_pending := can_order and pending_move_unit != null and not pending_move_path.is_empty()
	if confirm_move_button:
		confirm_move_button.visible = has_pending
		confirm_move_button.disabled = is_paused
	if cancel_move_button:
		cancel_move_button.visible = has_pending
		cancel_move_button.disabled = is_paused
	if finish_planning_button:
		finish_planning_button.disabled = is_paused or finish_planning_button.disabled
	if card_toggle_button:
		card_toggle_button.disabled = is_paused


func _on_confirm_move_pressed() -> void:
	if is_paused or pending_move_unit == null or pending_move_path.is_empty():
		return
	# 修复: 计划已锁定/已进入演算时提交无效, 直接放弃并清空, 避免静默吞指令
	if GameManager.current_state != GameManager.GameState.PLANNING_PHASE or TurnManager.orders_locked:
		_clear_pending_move(true)
		selected_unit = null
		unit_renderer.deselect_unit()
		return
	TurnManager.submit_order(pending_move_unit.unit_id, {"type": "move", "path": pending_move_path}, true)
	print("[MainScene] 确认移动: %s -> (%d,%d)，路径%d格" % [
		pending_move_unit.unit_name, pending_move_target.x, pending_move_target.y, pending_move_path.size()])
	_clear_pending_move(false)
	selected_unit = null
	unit_renderer.deselect_unit()
	SoundManager.play("move_order", -6.0)
	if tutorial:
		tutorial.notify("order_submitted")
	await get_tree().create_timer(1.0).timeout
	tile_grid.clear_highlights()


func _on_cancel_move_pressed() -> void:
	_cancel_pending_move()


func _cancel_pending_move() -> void:
	_clear_pending_move(true)
	selected_unit = null
	unit_renderer.deselect_unit()
	tile_grid.clear_highlights()


func _clear_pending_move(clear_path_now: bool) -> void:
	pending_move_unit = null
	pending_move_path.clear()
	pending_move_target = Vector2i(-1, -1)
	if clear_path_now:
		tile_grid.clear_highlights()
	_sync_move_confirmation_buttons()


func _handle_key_input(event: InputEventKey) -> void:
	if event.is_action_pressed("toggle_fullscreen") or (event.alt_pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause_game"):
		_set_game_paused(not is_paused)
		get_viewport().set_input_as_handled()
		return
	if is_paused:
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_TAB:
			_set_card_panel_open(not card_ui.is_panel_open)
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if pending_move_unit:
				_cancel_pending_move()
			selected_unit = null
			tile_grid.clear_highlights()
			unit_renderer.deselect_unit()
			card_ui.selected_card_index = -1
			card_ui.queue_redraw()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if pending_move_unit:
				_on_confirm_move_pressed()
				get_viewport().set_input_as_handled()
			elif GameManager.current_state == GameManager.GameState.PLANNING_PHASE:
				_on_phase_skip_pressed()
				get_viewport().set_input_as_handled()
			elif GameManager.current_state == GameManager.GameState.EXECUTION_PHASE:
				_on_phase_skip_pressed()
				get_viewport().set_input_as_handled()


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _is_pointer_over_button(pos: Vector2) -> bool:
	for button in [finish_planning_button, card_toggle_button, pause_button, confirm_move_button, cancel_move_button, loan_button]:
		if button and button.visible and button.get_global_rect().has_point(pos):
			return true
	return false


func _is_pointer_over_card_panel(pos: Vector2) -> bool:
	if card_ui == null or not card_ui.is_panel_open:
		return false
	var vp := get_viewport_rect().size
	var card_height := minf(CardUI.CARD_HEIGHT, vp.y * 0.28)
	var help_height := maxf(26.0, card_height * 0.12)
	var panel_top := vp.y - card_height - 20.0 - help_height - 8.0
	return pos.y >= panel_top


func _is_pointer_over_interface(pos: Vector2) -> bool:
	return _is_pointer_over_button(pos) or _is_pointer_over_card_panel(pos)


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

	# 如果有选中卡牌 → 使用卡牌（索引需在界内：贷款惩罚/弃牌可能使手牌少于选中索引）
	if card_ui.selected_card_index >= 0 and card_ui.selected_card_index < CardSystem.hand.size():
		var card = CardSystem.hand[card_ui.selected_card_index]
		var cells := _get_card_effect_cells(card.card_id, gp)
		var color := _get_card_highlight_color(card)
		if card_ui.use_selected_card(gp.x, gp.y):
			_flash_card_area(cells, color)
		return

	var clicked_unit = _get_unit_at(gp.x, gp.y)

	# 1) 点中己方单位 → 选中并显示移动与攻击目标
	if clicked_unit and clicked_unit.faction == UnitBase.Faction.WARSAW_PACT:
		_clear_pending_move(true)
		selected_unit = clicked_unit
		tile_grid.highlight_unit_actions(clicked_unit)
		unit_renderer.select_unit(clicked_unit)
		_set_action_hint("%s：点击蓝格规划移动；点击红色敌军下达攻击命令。" % clicked_unit.unit_name)
		print("[MainScene] 已选中单位")
		if tutorial:
			tutorial.notify("unit_selected")
		SoundManager.play("unit_select", -6.0)
		return

	# 2) 点击射程与视线内的敌军 → 下达显式攻击指令。
	if selected_unit and selected_unit.is_alive and clicked_unit and clicked_unit.faction != selected_unit.faction:
		if selected_unit.can_attack_target(clicked_unit.grid_col, clicked_unit.grid_row):
			TurnManager.submit_order(selected_unit.unit_id, {
				"type": "attack",
				"target_col": clicked_unit.grid_col,
				"target_row": clicked_unit.grid_row,
				"attack_type": CombatSystem.AttackType.DIRECT_FIRE,
			}, true)
			BattleLog.add_log("已下令：%s 攻击 %s" % [selected_unit.unit_name, clicked_unit.unit_name], Color(1.0, 0.72, 0.45))
			_set_action_hint("攻击命令已记录；可继续给其他单位下令，或结束计划。")
			selected_unit = null
			unit_renderer.deselect_unit()
			tile_grid.clear_highlights()
			_clear_pending_move(false)   # 修复: 攻击提交后清掉残留的移动规划, 防止旧路径覆盖攻击指令
			if tutorial:
				tutorial.notify("order_submitted")
			SoundManager.play("tank_fire", -4.0)
			return
		_set_action_hint("目标不在射程或视线被阻挡；请先移动接近。")
		return

	# 3) 点击空格 → 规划移动路径。
	if selected_unit and selected_unit.is_alive:
		var path = TilePathfinding.find_path(selected_unit.grid_col, selected_unit.grid_row,
			gp.x, gp.y, selected_unit, selected_unit.get_effective_movement())
		if not path.is_empty():
			pending_move_unit = selected_unit
			pending_move_path = path
			pending_move_target = gp
			tile_grid.highlight_path(path)
			_sync_move_confirmation_buttons()
			_set_action_hint("路径已规划：点击“确认移动”或按 Enter 提交，右键取消。")
			print("[MainScene] 待确认移动: %s -> (%d,%d) 路径%d格" % [
				selected_unit.unit_name, gp.x, gp.y, path.size()])
			if pending_move_unit:
				return
			tile_grid.highlight_path(path)
			TurnManager.submit_order(selected_unit.unit_id, {"type": "move", "path": path}, true)
			print("[MainScene] 提交移动指令: %s -> (%d,%d) 路径%d格" % [
				selected_unit.unit_name, gp.x, gp.y, path.size()])
		else:
			print("[MainScene] 无法到达 (%d,%d)" % [gp.x, gp.y])
			_set_action_hint("该格无法到达，请选择蓝色高亮格。")
		selected_unit = null
		unit_renderer.deselect_unit()
		# 保留路径高亮，2秒后清除
		await get_tree().create_timer(1.0).timeout
		tile_grid.clear_highlights()


func _on_right_click(pos: Vector2) -> void:
	# 右键点击卡牌 → 弃牌（玩家自主弃牌入口）
	if card_ui.is_panel_open and card_ui.discard_card_at_pos(pos):
		return
	if pending_move_unit:
		_cancel_pending_move()
		return
	# 鍚﹀垯鍙栨秷鎵€鏈夐€夋嫨
	selected_unit = null
	tile_grid.clear_highlights()
	tile_grid.clear_card_highlight()
	unit_renderer.deselect_unit()
	card_ui.selected_card_index = -1
	card_ui.queue_redraw()


func _get_unit_at(col: int, row: int) -> UnitBase:
	for u in get_tree().get_nodes_in_group("units"):
		if u.grid_col == col and u.grid_row == row:
			return u
	return null


func _set_action_hint(message: String) -> void:
	if action_hint_label:
		action_hint_label.text = message


## ==================== 状态回调 ====================

func _on_state_changed(_old: int, new: int) -> void:
	match new:
		GameManager.GameState.LEVEL_INTRO:
			_show_briefing_panel()
		GameManager.GameState.PLANNING_PHASE:
			print("[MainScene] <<< 计划阶段 >>> 请下达移动/攻击指令")
			game_over_active = false
		GameManager.GameState.EXECUTION_PHASE:
			print("[MainScene] >>> 演算阶段 <<<")
			if tutorial:
				tutorial.notify("execution")
		GameManager.GameState.VICTORY:
			SoundManager.play("victory")
			_show_game_over_panel(UnitBase.Faction.WARSAW_PACT, _get_game_over_reason())
		GameManager.GameState.DEFEAT:
			SoundManager.play("defeat")
			_show_game_over_panel(UnitBase.Faction.NATO, _get_game_over_reason())

func _on_planning_started(turn: int) -> void:
	print("[MainScene] 第%d回合计划开始" % turn)
	SoundManager.play("round_plan", -4.0)
	BattleLog.add_phase_log("第%d回合 · 计划阶段" % turn)
	_set_action_hint("选择己方单位下达命令。蓝格可移动，红色敌军可直接攻击。")
	_sync_loan_button()
	# 重置越界的卡牌选中索引（贷款惩罚/弃牌后手牌可能变少）
	if card_ui.selected_card_index >= CardSystem.hand.size():
		card_ui.selected_card_index = -1
		card_ui.queue_redraw()
	# 指挥鼓舞（修复: rally 原未接入）— 指挥组每回合鼓舞士气偏低(≤60)的相邻己方单位
	for u in get_tree().get_nodes_in_group("units"):
		if not (u.is_alive and u.is_command and u.faction == UnitBase.Faction.WARSAW_PACT):
			continue
		for v in get_tree().get_nodes_in_group("units"):
			if not (v.is_alive and v.faction == UnitBase.Faction.WARSAW_PACT and v != u):
				continue
			if absi(v.grid_col - u.grid_col) + absi(v.grid_row - u.grid_row) <= 2 \
					and MoraleSystem.get_unit_morale(v.unit_id) <= 60:
				MoraleSystem.apply_rally(v.unit_id)
	# 教学引导推进（第1回合开始 / 第2回合完成）
	if tutorial:
		if turn == 1:
			tutorial.notify("planning_r1")
		elif turn == 2:
			tutorial.notify("planning_r2")
	# 重置所有单位移动点数
	for u in get_tree().get_nodes_in_group("units"):
		if u.is_alive:
			u.remaining_movement = u.movement_points

func _on_execution_started(turn: int) -> void:
	print("[MainScene] 第%d回合演算开始" % turn)
	SoundManager.play("round_exec", -4.0)
	BattleLog.add_phase_log("第%d回合 · 演算阶段" % turn)
	_sync_loan_button()

func _on_turn_resolved(turn: int) -> void:
	print("[MainScene] 第%d回合结算" % turn)

func _on_attack_executed(_aid: int, _tc: int, _tr: int, result: Dictionary) -> void:
	SoundManager.play("gunshot", -4.0)
	if result.get("hit"):
		print("[MainScene] 命中! 伤害: %.1f" % result.get("damage", 0.0))
		SoundManager.play("hit", -2.0)
	unit_renderer.queue_redraw()

func _on_unit_destroyed(uid: int, _kid: int) -> void:
	print("[MainScene] 单位%d被摧毁" % uid)
	SoundManager.play("explosion", -2.0)
	unit_renderer.queue_redraw()

func _on_unit_broken(uid: int) -> void:
	print("[MainScene] 单位%d士气崩溃!" % uid)
	SoundManager.play("morale_break", -3.0)

func _on_card_used(_card_id: String, _tc: int, _tr: int) -> void:
	SoundManager.play("card_use", -4.0)

func _on_emi_changed(new_val: float, _old: float) -> void:
	print("[MainScene] EMI: %.0f%%" % (new_val * 100))

func _on_card_drawn(card) -> void:
	print("[MainScene] 抽到: %s" % card.card_name)


func _show_briefing_panel() -> void:
	"""任务简报浮窗：关卡开场显示任务目标与情报，点击'开始行动'进入计划阶段。"""
	if briefing_panel:
		return
	var level_data = LevelDatabase.get_level(GameManager.current_level_id)
	if level_data == null:
		GameManager.confirm_intro()
		return

	var layer = CanvasLayer.new()
	layer.layer = 90
	layer.name = "BriefingLayer"
	add_child(layer)
	briefing_panel = layer

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(660, 480)
	panel.self_modulate = Color(0.08, 0.08, 0.1, 0.92)
	center.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.11, 0.96)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.8, 0.75, 0.5)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.set_deferred("offset_left", 36)
	vbox.set_deferred("offset_right", -36)
	vbox.set_deferred("offset_top", 28)
	vbox.set_deferred("offset_bottom", -24)
	panel.add_child(vbox)

	# 标题
	var title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	title.text = "任务简报 — 第%d关《%s》" % [level_data.level_id + 1, level_data.level_name]
	vbox.add_child(title)

	# 简报正文
	var briefing = Label.new()
	briefing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	briefing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing.add_theme_font_size_override("font_size", 17)
	briefing.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	briefing.text = level_data.briefing
	vbox.add_child(briefing)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# 目标 / 条件 / 情报
	var info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	var info_text := "主任务：%s\n胜利：%s\n失败：%s\n回合限制：%d 回合" % [
		level_data.primary_objective, level_data.victory_condition,
		level_data.failure_condition, level_data.max_turns]
	if not String(level_data.intel_a).is_empty():
		info_text += "\n情报：%s" % level_data.intel_a
	info.text = info_text
	vbox.add_child(info)

	# 开始按钮
	var start_btn = Button.new()
	start_btn.text = "开始行动"
	start_btn.custom_minimum_size = Vector2(180, 52)
	start_btn.pressed.connect(_on_briefing_start_pressed)
	vbox.add_child(start_btn)


func _on_briefing_start_pressed() -> void:
	"""点击开始行动：关闭简报浮窗并立即进入计划阶段。"""
	_close_briefing_panel()
	GameManager.confirm_intro()


func _close_briefing_panel() -> void:
	if briefing_panel:
		briefing_panel.queue_free()
		briefing_panel = null


func _get_game_over_reason() -> String:
	# 优先使用胜利管理器记录的正式结算原因。
	if VictoryManager.last_game_over_reason != "":
		return VictoryManager.last_game_over_reason
	return "战斗结束"


func _show_game_over_panel(winner_faction: int, reason: String) -> void:
	# 结束游戏后解除暂停，避免结算界面无法交互。
	get_tree().paused = false
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

	# 结算原因
	var reason_label = Label.new()
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_label.add_theme_font_size_override("font_size", 20)
	reason_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	reason_label.text = reason
	vbox.add_child(reason_label)

	# 战后旁白
	var level_data = LevelDatabase.get_level(GameManager.current_level_id)
	if level_data != null and not String(level_data.outro_narration).is_empty():
		var outro = Label.new()
		outro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		outro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		outro.add_theme_font_size_override("font_size", 16)
		outro.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
		outro.text = "—— %s ——" % level_data.outro_narration
		vbox.add_child(outro)

	# 统计 — 含VP控制信息
	var vp = VictoryManager.get_vp_control()
	var stats = Label.new()
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 18)
	stats.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	stats.text = "第%d / %d 回合\n华约控制VP: %d    北约控制VP: %d\n华约剩余单位: %d    北约剩余单位: %d" % [
		TurnManager.current_turn, VictoryManager.max_turns, vp.wp, vp.nato, wp_alive, nato_alive]
	vbox.add_child(stats)

	# 操作按钮
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(hbox)

	var next_level_path := "res://scenes/levels/level_%02d.tscn" % (GameManager.current_level_id + 2)
	if winner_faction == UnitBase.Faction.WARSAW_PACT and ResourceLoader.exists(next_level_path):
		var next_btn = Button.new()
		next_btn.text = "进入下一关"
		next_btn.custom_minimum_size = Vector2(140, 48)
		next_btn.pressed.connect(_on_next_level_pressed)
		hbox.add_child(next_btn)

	var restart_btn = Button.new()
	restart_btn.text = "重新开始"
	restart_btn.custom_minimum_size = Vector2(140, 48)
	restart_btn.pressed.connect(_on_restart_pressed)
	hbox.add_child(restart_btn)

	var quit_btn = Button.new()
	quit_btn.text = "返回主菜单"
	quit_btn.custom_minimum_size = Vector2(140, 48)
	quit_btn.pressed.connect(_on_quit_pressed)
	hbox.add_child(quit_btn)

	game_over_panel = layer
	BattleLog.add_log("游戏结束: %s" % ("华约胜利" if winner_faction == UnitBase.Faction.WARSAW_PACT else "北约胜利"), Color.GOLD)


func _on_restart_pressed() -> void:
	# 说明
	if game_over_panel:
		game_over_panel.queue_free()
		game_over_panel = null
	game_over_active = false
	VictoryManager.reset()
	# 重载整个主场景，干净地重新开始
	get_tree().reload_current_scene()


func _on_next_level_pressed() -> void:
	var next_level_id := GameManager.current_level_id + 1
	# 修复: 先移出并释放旧场景再启动新场景——旧场景残留的 level_started 连接
	# 会响应新场景启动信号, 导致单位双倍生成、register_initial_units 计数翻倍
	get_tree().root.remove_child(self)
	queue_free()
	await get_tree().create_timer(0.1).timeout
	var packed := load("res://scenes/MainScene.tscn") as PackedScene
	var next_scene = packed.instantiate()
	next_scene.startup_level_id = next_level_id
	var root := get_tree().root
	root.add_child(next_scene)
	get_tree().current_scene = next_scene


func _on_quit_pressed() -> void:
	_return_to_main_menu()


func _on_unit_step(_uid: int, _col: int, _row: int) -> void:
	# 沙盘演示：单位每走一格刷新画面
	unit_renderer.queue_redraw()
	tile_grid.queue_redraw()


func _on_unit_move_completed(_uid: int, _col: int, _row: int) -> void:
	unit_renderer.queue_redraw()
