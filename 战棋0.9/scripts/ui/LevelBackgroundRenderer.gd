# ==============================================================================
# LevelBackgroundRenderer.gd -- Story-specific generated scenery behind the map
# ==============================================================================
class_name LevelBackgroundRenderer
extends Node2D

const BACKGROUND_PATHS := [
	"res://assets/backgrounds/level_01_border_dawn.png",
	"res://assets/backgrounds/level_02_railway_defense.png",
	"res://assets/backgrounds/level_03_first_flood.png",
	"res://assets/backgrounds/level_04_forest_misfire.png",
	"res://assets/backgrounds/level_05_reserve_commitment.png",
	"res://assets/backgrounds/level_06_broken_bridge.png",
	"res://assets/backgrounds/level_07_blackout.png",
	"res://assets/backgrounds/level_08_white_corridor.png",
	"res://assets/backgrounds/level_09_red_track.png",
	"res://assets/backgrounds/level_10_coordinates_zero.png",
]

var level_id: int = 0
var background_texture: Texture2D
var last_viewport_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	# The board and units render above this scenery. HUD is in a CanvasLayer.
	z_index = -10
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	last_viewport_size = get_viewport_rect().size
	queue_redraw()


func configure(new_level_id: int, _tilemap: TileMapLayer, _used_rect: Rect2i) -> void:
	level_id = clampi(new_level_id, 0, BACKGROUND_PATHS.size() - 1)
	background_texture = load(BACKGROUND_PATHS[level_id]) as Texture2D
	if background_texture == null:
		push_error("找不到关卡背景: %s" % BACKGROUND_PATHS[level_id])
	queue_redraw()


func set_camera(_offset: Vector2, _zoom: float) -> void:
	# Background stays screen-filling while the map is panned or zoomed above it.
	# Camera panning does not change it; only a real window resize needs new geometry.
	var viewport_size := get_viewport_rect().size
	if viewport_size != last_viewport_size:
		last_viewport_size = viewport_size
		queue_redraw()


func get_theme_id() -> int:
	return level_id


func get_background_path() -> String:
	return BACKGROUND_PATHS[level_id]


func _draw() -> void:
	if background_texture == null:
		return
	var viewport := get_viewport_rect()
	if viewport.size.x <= 0.0 or viewport.size.y <= 0.0:
		return

	# Cover the viewport without stretching the generated 16:9 composition.
	var texture_size := background_texture.get_size()
	var scale := maxf(viewport.size.x / texture_size.x, viewport.size.y / texture_size.y)
	var display_size := texture_size * scale
	var destination := Rect2(
		viewport.get_center() - display_size * 0.5,
		display_size
	)
	draw_texture_rect(background_texture, destination, false)
