# ==============================================================================
# CardEffectRenderer.gd — 卡牌地图特效渲染器
# ==============================================================================
# 播放透明四帧像素序列帧。特效锚点始终由实际 TileMap 计算，因此玩家在
# 演绎阶段移动或缩放视角时，动画仍会贴在原目标地块上。
# ==============================================================================
class_name CardEffectRenderer
extends Node2D

const CONFIG_PATH := "res://assets/effects/card_effects/card_effects.json"

var source_tilemap: TileMapLayer
var source_map_origin := Vector2i.ZERO
var camera_offset := Vector2.ZERO
var camera_zoom := 1.0
var effect_configs: Dictionary = {}
var active_effects: Array[Dictionary] = []
var texture_cache: Dictionary = {}


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 50
	_load_configs()
	set_process(false)


func _load_configs() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("[CardEffectRenderer] 找不到配置: %s" % CONFIG_PATH)
		return
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		effect_configs = parsed
	else:
		push_warning("[CardEffectRenderer] 卡牌特效配置格式错误")


func use_source_tilemap(tilemap: TileMapLayer, used_rect: Rect2i) -> void:
	source_tilemap = tilemap
	source_map_origin = used_rect.position


func set_camera(pos: Vector2, zoom: float) -> void:
	camera_offset = pos
	camera_zoom = zoom
	_update_effect_transforms()


func play_card_effect(card_id: String, target_col: int, target_row: int) -> bool:
	if not effect_configs.has(card_id):
		return false
	var config: Dictionary = effect_configs[card_id]
	var texture_path := String(config.get("texture", ""))
	var texture := _load_texture(texture_path)
	if texture == null:
		push_warning("[CardEffectRenderer] 无法加载特效: %s" % texture_path)
		return false

	var frame_width := int(config.get("frame_width", 64))
	var frame_height := int(config.get("frame_height", 64))
	var sprite := Sprite2D.new()
	sprite.name = "CardFX_%s" % card_id
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, frame_width, frame_height)
	sprite.centered = true
	sprite.z_index = 50
	add_child(sprite)

	active_effects.append({
		"sprite": sprite,
		"config": config,
		"target": Vector2i(target_col, target_row),
		"elapsed": 0.0,
		"frame": -1,
		"holding": false,
	})
	_update_one_effect(active_effects[-1])
	set_process(true)
	return true


func _process(delta: float) -> void:
	for index in range(active_effects.size() - 1, -1, -1):
		var effect: Dictionary = active_effects[index]
		var config: Dictionary = effect["config"]
		var frames := maxi(1, int(config.get("frames", 4)))
		var fps := maxf(1.0, float(config.get("fps", 7.0)))
		effect["elapsed"] = float(effect["elapsed"]) + delta
		var frame := mini(frames - 1, int(floor(float(effect["elapsed"]) * fps)))
		if frame != int(effect["frame"]):
			effect["frame"] = frame
			var sprite := effect["sprite"] as Sprite2D
			var frame_width := int(config.get("frame_width", 64))
			var frame_height := int(config.get("frame_height", 64))
			sprite.region_rect = Rect2(frame * frame_width, 0, frame_width, frame_height)
			_update_one_effect(effect)
		_update_hover_fade(effect, delta)
		if float(effect["elapsed"]) >= float(frames) / fps:
			var persistence := String(config.get("persistence", ""))
			if not persistence.is_empty() and _persistent_state_exists(effect, persistence):
				effect["holding"] = true
				continue
			var expired_sprite := effect["sprite"] as Sprite2D
			expired_sprite.queue_free()
			active_effects.remove_at(index)
	if active_effects.is_empty():
		set_process(false)


func _update_hover_fade(effect: Dictionary, delta: float) -> void:
	_update_hover_fade_for_point(effect, get_viewport().get_mouse_position(), delta)


func _update_hover_fade_for_point(effect: Dictionary, screen_point: Vector2, delta: float) -> void:
	var config: Dictionary = effect.get("config", {})
	if String(config.get("persistence", "")) != "smoke":
		return
	var sprite := effect.get("sprite") as Sprite2D
	if sprite == null:
		return
	var hovered := _is_screen_point_over_effect(effect, screen_point)
	var target_alpha := 0.18 if hovered else 1.0
	var next_alpha := move_toward(sprite.self_modulate.a, target_alpha, delta * 6.0)
	sprite.self_modulate = Color(1.0, 1.0, 1.0, next_alpha)
	effect["hovered"] = hovered


func _is_screen_point_over_effect(effect: Dictionary, screen_point: Vector2) -> bool:
	var sprite := effect.get("sprite") as Sprite2D
	if sprite == null:
		return false
	var config: Dictionary = effect.get("config", {})
	var frame_size := Vector2(
		float(config.get("frame_width", 64)),
		float(config.get("frame_height", 64))) * camera_zoom
	return Rect2(sprite.position - frame_size * 0.5, frame_size).has_point(screen_point)


func _update_effect_transforms() -> void:
	for effect in active_effects:
		_update_one_effect(effect)


func _update_one_effect(effect: Dictionary) -> void:
	var sprite := effect["sprite"] as Sprite2D
	if sprite == null:
		return
	var config: Dictionary = effect["config"]
	var target: Vector2i = effect["target"]
	var frame_height := float(config.get("frame_height", 64))
	var ground_ratio := float(config.get("ground_ratio", 0.9))
	var ground_position := _get_area_screen_center(
		target,
		int(config.get("area_width", 1)),
		int(config.get("area_height", 1)))
	sprite.position = ground_position + Vector2(0.0,
		(0.5 - ground_ratio) * frame_height * camera_zoom)
	sprite.scale = Vector2.ONE * camera_zoom


func _get_area_screen_center(target: Vector2i, area_width: int, area_height: int) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	var start_x := -int(area_width / 2.0)
	var start_y := -int(area_height / 2.0)
	for offset_x in range(start_x, start_x + area_width):
		for offset_y in range(start_y, start_y + area_height):
			var cell := target + Vector2i(offset_x, offset_y)
			if not GridManager.is_valid_cell(cell.x, cell.y):
				continue
			total += _get_cell_screen_position(cell)
			count += 1
	if count == 0:
		return _get_cell_screen_position(target)
	return total / float(count)


func _get_cell_screen_position(cell: Vector2i) -> Vector2:
	if source_tilemap:
		var source_cell := cell + source_map_origin
		return source_tilemap.to_global(source_tilemap.map_to_local(source_cell))
	var fallback := GridManager.grid_to_iso(cell.x, cell.y) + GridManager.get_iso_map_origin()
	return fallback * camera_zoom + camera_offset


func _persistent_state_exists(effect: Dictionary, persistence: String) -> bool:
	var config: Dictionary = effect["config"]
	var target: Vector2i = effect["target"]
	var area_width := int(config.get("area_width", 1))
	var area_height := int(config.get("area_height", 1))
	var start_x := -int(area_width / 2.0)
	var start_y := -int(area_height / 2.0)
	for offset_x in range(start_x, start_x + area_width):
		for offset_y in range(start_y, start_y + area_height):
			var cell := target + Vector2i(offset_x, offset_y)
			match persistence:
				"smoke":
					if CombatSystem.smoke_cells.get("%d,%d" % [cell.x, cell.y], 0) > 0:
						return true
				"mines":
					if cell in MovementSystem.mine_cells:
						return true
	return false


func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if texture_cache.has(path):
		return texture_cache[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	else:
		# 新增PNG可能尚未被正在运行的编辑器写入.import；直接从源图创建
		# ImageTexture，保证首次运行和自动测试也能立刻播放，不要求重启Godot。
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	texture_cache[path] = texture
	return texture


func clear_all() -> void:
	for effect in active_effects:
		var sprite := effect.get("sprite") as Sprite2D
		if sprite:
			sprite.queue_free()
	active_effects.clear()
	set_process(false)
