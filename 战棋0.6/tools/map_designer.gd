extends SceneTree

const DEFAULT_TILESET_PATH := "res://resources/tilesets/isometric_terrain.tres"
const TERRAIN_LAYER_HINTS := ["terrain", "地块"]
const EDGE_ROLE_BY_MASK := {
	0: "center",
	1: "edge_n",
	2: "edge_e",
	3: "corner_ne",
	4: "edge_s",
	5: "channel_ew",
	6: "corner_se",
	7: "cap_w",
	8: "edge_w",
	9: "corner_nw",
	10: "channel_ns",
	11: "cap_s",
	12: "corner_sw",
	13: "cap_e",
	14: "cap_n",
	15: "isolated",
}
const EDGE_AWARE_TILES := {
	"water": {
		"center": [
			{"coords": Vector2i(7, 8), "name": "深水波纹·稀疏亮点"},
			{"coords": Vector2i(8, 8), "name": "深水波纹·双层暗纹"},
			{"coords": Vector2i(7, 9), "name": "深水涟漪·碎亮点"},
			{"coords": Vector2i(8, 9), "name": "深水涟漪·环状暗纹"},
		],
		"edge_n": [{"coords": Vector2i(0, 8), "name": "浅水波纹·北缘长波"}],
		"edge_e": [{"coords": Vector2i(1, 9), "name": "浅水流纹·窄幅右摆"}],
		"edge_s": [{"coords": Vector2i(1, 8), "name": "浅水波纹·南缘长波"}],
		"edge_w": [{"coords": Vector2i(0, 9), "name": "浅水流纹·宽幅左摆"}],
		"corner_ne": [{"coords": Vector2i(3, 8), "name": "浅水波纹·东北双层回旋"}],
		"corner_se": [{"coords": Vector2i(3, 9), "name": "浅水涟漪·东南双圈"}],
		"corner_sw": [{"coords": Vector2i(2, 9), "name": "浅水涟漪·西南单圈"}],
		"corner_nw": [{"coords": Vector2i(2, 8), "name": "浅水波纹·西北中央圆波"}],
		"channel_ew": [{"coords": Vector2i(4, 8), "name": "中水波纹·东西狭道"}],
		"channel_ns": [{"coords": Vector2i(5, 8), "name": "中水波纹·南北狭道"}],
		"cap_n": [{"coords": Vector2i(4, 9), "name": "中水涟漪·北向端头"}],
		"cap_e": [{"coords": Vector2i(5, 9), "name": "中水涟漪·东向端头"}],
		"cap_s": [{"coords": Vector2i(4, 8), "name": "中水波纹·南向端头"}],
		"cap_w": [{"coords": Vector2i(5, 8), "name": "中水波纹·西向端头"}],
		"isolated": [{"coords": Vector2i(2, 8), "name": "浅水波纹·孤立水洼"}],
	},
}

var _terrain_tiles: Dictionary = {}
var _atlas_tiles: Dictionary = {}
var _terrain_field: Dictionary = {}
var _resolved_variant_counts: Dictionary = {}
var _width := 0
var _height := 0
var _seed := 1987
var _auto_edges := true
var _terrain_layer: TileMapLayer


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var options := _parse_arguments(OS.get_cmdline_user_args())
	var tileset_path: String = options.get("tileset", DEFAULT_TILESET_PATH)
	var tile_set := load(tileset_path) as TileSet
	if tile_set == null:
		_fail("无法加载 TileSet: %s" % tileset_path)
		return

	_index_terrain_tiles(tile_set)
	if options.has("list-terrains"):
		_print_terrain_catalog()
		quit(0)
		return
	if options.has("list-edge-rules"):
		_print_edge_rules()
		quit(0)
		return

	var recipe_path: String = options.get("recipe", "")
	if recipe_path.is_empty():
		_fail("缺少 --recipe=<配方 JSON 路径>")
		return
	var recipe := _load_recipe(recipe_path)
	if recipe.is_empty():
		return

	_width = int(recipe.get("width", 0))
	_height = int(recipe.get("height", 0))
	_seed = int(recipe.get("seed", 1987))
	_auto_edges = bool(recipe.get("auto_edges", true))
	if _width <= 0 or _height <= 0:
		_fail("width 和 height 必须是正整数")
		return

	var target_scene: String = recipe.get("scene", "")
	if not target_scene.begins_with("res://") or not target_scene.ends_with(".tscn"):
		_fail("scene 必须是 res:// 开头的 .tscn 路径")
		return

	var root := _load_or_create_scene(target_scene, tile_set)
	if root == null:
		return
	_terrain_layer = _find_terrain_layer(root)
	if _terrain_layer == null:
		_fail("场景中找不到 Terrain/地块 TileMapLayer")
		root.queue_free()
		return
	_terrain_layer.tile_set = tile_set
	_terrain_layer.clear()
	_terrain_field.clear()
	_resolved_variant_counts.clear()

	var base_terrain := _normalize_terrain(String(recipe.get("base", "tile.grass")))
	if not _require_terrain(base_terrain):
		root.queue_free()
		return
	_fill(base_terrain)

	var operations: Array = recipe.get("operations", [])
	for index in range(operations.size()):
		var operation = operations[index]
		if not operation is Dictionary:
			_fail("operations[%d] 必须是对象" % index)
			root.queue_free()
			return
		if not _apply_operation(operation, index):
			root.queue_free()
			return

	_resolve_tiles()
	if not _validate_complete_map():
		root.queue_free()
		return
	_print_summary(target_scene)

	if options.has("dry-run"):
		print("[MapDesigner] dry-run 验证通过，未写入场景")
		root.queue_free()
		quit(0)
		return

	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		_fail("场景打包失败，错误码: %d" % pack_error)
		root.queue_free()
		return
	var save_error := ResourceSaver.save(packed, target_scene)
	root.queue_free()
	if save_error != OK:
		_fail("场景保存失败，错误码: %d" % save_error)
		return
	print("[MapDesigner] 已保存: %s" % target_scene)
	quit(0)


func _parse_arguments(args: PackedStringArray) -> Dictionary:
	var result := {}
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var body := arg.substr(2)
		var separator := body.find("=")
		if separator < 0:
			result[body] = true
		else:
			result[body.substr(0, separator)] = body.substr(separator + 1)
	return result


func _load_recipe(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("找不到配方文件: %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_fail("配方必须是合法的 JSON 对象: %s" % path)
		return {}
	return parsed


func _index_terrain_tiles(tile_set: TileSet) -> void:
	_terrain_tiles.clear()
	_atlas_tiles.clear()
	for source_index in range(tile_set.get_source_count()):
		var source_id: int = tile_set.get_source_id(source_index)
		var source := tile_set.get_source(source_id)
		if not source is TileSetAtlasSource:
			continue
		var atlas_source := source as TileSetAtlasSource
		for tile_index in range(atlas_source.get_tiles_count()):
			var atlas_coords: Vector2i = atlas_source.get_tile_id(tile_index)
			var tile_data: TileData = atlas_source.get_tile_data(atlas_coords, 0)
			if tile_data == null:
				continue
			var terrain := _normalize_terrain(String(tile_data.get_custom_data("terrain_type")))
			var tile_entry := {
				"source_id": source_id,
				"atlas_coords": atlas_coords,
				"alternative": 0,
				"terrain": terrain,
			}
			_atlas_tiles[_atlas_key(atlas_coords)] = tile_entry
			if terrain.is_empty():
				continue
			if not _terrain_tiles.has(terrain):
				_terrain_tiles[terrain] = []
			_terrain_tiles[terrain].append(tile_entry)


func _print_terrain_catalog() -> void:
	var names := _terrain_tiles.keys()
	names.sort()
	print("[MapDesigner] 可用地块指令:")
	for terrain in names:
		print("  tile.%s (%d variants)" % [terrain, _terrain_tiles[terrain].size()])


func _print_edge_rules() -> void:
	print("[MapDesigner] 自动边缘规则（地图方向 N/E/S/W）:")
	for terrain in EDGE_AWARE_TILES:
		print("  tile.%s:" % terrain)
		var rules: Dictionary = EDGE_AWARE_TILES[terrain]
		for role in EDGE_ROLE_BY_MASK.values():
			if not rules.has(role):
				continue
			for rule: Dictionary in rules[role]:
				var coords: Vector2i = rule.coords
				print("    %s -> (%d,%d) %s" % [role, coords.x, coords.y, rule.name])


func _load_or_create_scene(scene_path: String, tile_set: TileSet) -> Node2D:
	if ResourceLoader.exists(scene_path):
		var packed := load(scene_path) as PackedScene
		if packed == null:
			_fail("无法加载场景: %s" % scene_path)
			return null
		var instance := packed.instantiate() as Node2D
		if instance == null:
			_fail("地图场景根节点必须是 Node2D: %s" % scene_path)
		return instance

	var root := Node2D.new()
	root.name = scene_path.get_file().get_basename().to_pascal_case()
	var layer := TileMapLayer.new()
	layer.name = "Terrain（地块）"
	layer.tile_set = tile_set
	layer.y_sort_enabled = true
	layer.y_sort_origin = 8
	root.add_child(layer)
	layer.owner = root
	return root


func _find_terrain_layer(root: Node) -> TileMapLayer:
	for node in root.find_children("*", "TileMapLayer", true, false):
		var normalized_name := String(node.name).to_lower()
		for hint in TERRAIN_LAYER_HINTS:
			if normalized_name.contains(hint):
				return node as TileMapLayer
	return null


func _apply_operation(operation: Dictionary, index: int) -> bool:
	var command := String(operation.get("command", operation.get("op", ""))).to_lower()
	if command.begins_with("map."):
		command = command.substr(4)
	var terrain := _normalize_terrain(String(operation.get("terrain", "")))
	if command != "fill" and not _require_terrain(terrain):
		return false

	match command:
		"fill":
			if not _require_terrain(terrain):
				return false
			_fill(terrain)
		"cell":
			_paint(_vector2i(operation.get("at", []), "operations[%d].at" % index), terrain)
		"rect":
			_paint_rect(
				_vector2i(operation.get("from", []), "operations[%d].from" % index),
				_vector2i(operation.get("to", []), "operations[%d].to" % index), terrain)
		"ellipse":
			_paint_ellipse(
				_vector2i(operation.get("center", []), "operations[%d].center" % index),
				_vector2i(operation.get("radius", []), "operations[%d].radius" % index), terrain)
		"path":
			var points := _point_array(operation.get("points", []), "operations[%d].points" % index)
			if points.size() < 2:
				_fail("operations[%d].points 至少需要两个坐标" % index)
				return false
			_paint_path(points, maxi(1, int(operation.get("width", 1))), terrain)
		"polygon":
			var points := _point_array(operation.get("points", []), "operations[%d].points" % index)
			if points.size() < 3:
				_fail("operations[%d].points 至少需要三个坐标" % index)
				return false
			_paint_polygon(points, terrain)
		"scatter":
			var region: Array = operation.get("rect", [])
			if region.size() != 4:
				_fail("operations[%d].rect 必须是 [x, y, width, height]" % index)
				return false
			_paint_scatter(Rect2i(int(region[0]), int(region[1]), int(region[2]), int(region[3])),
				clampf(float(operation.get("density", 0.2)), 0.0, 1.0), terrain, index)
		_:
			_fail("未知地图指令: %s" % command)
			return false
	return true


func _fill(terrain: String) -> void:
	for y in range(_height):
		for x in range(_width):
			_paint(Vector2i(x, y), terrain)


func _paint(cell: Vector2i, terrain: String) -> void:
	if not _inside(cell):
		return
	_terrain_field[cell] = terrain


func _paint_rect(from: Vector2i, to: Vector2i, terrain: String) -> void:
	var min_x := mini(from.x, to.x)
	var max_x := maxi(from.x, to.x)
	var min_y := mini(from.y, to.y)
	var max_y := maxi(from.y, to.y)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			_paint(Vector2i(x, y), terrain)


func _paint_ellipse(center: Vector2i, radius: Vector2i, terrain: String) -> void:
	var rx := maxi(1, abs(radius.x))
	var ry := maxi(1, abs(radius.y))
	for y in range(center.y - ry, center.y + ry + 1):
		for x in range(center.x - rx, center.x + rx + 1):
			var dx := float(x - center.x) / float(rx)
			var dy := float(y - center.y) / float(ry)
			if dx * dx + dy * dy <= 1.0:
				_paint(Vector2i(x, y), terrain)


func _paint_path(points: Array[Vector2i], width: int, terrain: String) -> void:
	for index in range(points.size() - 1):
		for cell in _line_cells(points[index], points[index + 1]):
			_stamp(cell, width, terrain)


func _line_cells(start: Vector2i, finish: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x := start.x
	var y := start.y
	var dx: int = absi(finish.x - start.x)
	var sx: int = 1 if start.x < finish.x else -1
	var dy: int = -absi(finish.y - start.y)
	var sy: int = 1 if start.y < finish.y else -1
	var error: int = dx + dy
	while true:
		result.append(Vector2i(x, y))
		if x == finish.x and y == finish.y:
			break
		var doubled: int = 2 * error
		if doubled >= dy:
			error += dy
			x += sx
		if doubled <= dx:
			error += dx
			y += sy
	return result


func _stamp(center: Vector2i, width: int, terrain: String) -> void:
	var lower := -int(floor(float(width - 1) / 2.0))
	var upper := lower + width
	for offset_y in range(lower, upper):
		for offset_x in range(lower, upper):
			_paint(center + Vector2i(offset_x, offset_y), terrain)


func _paint_polygon(points: Array[Vector2i], terrain: String) -> void:
	var min_x := points[0].x
	var max_x := points[0].x
	var min_y := points[0].y
	var max_y := points[0].y
	for point in points:
		min_x = mini(min_x, point.x)
		max_x = maxi(max_x, point.x)
		min_y = mini(min_y, point.y)
		max_y = maxi(max_y, point.y)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), PackedVector2Array(points)):
				_paint(Vector2i(x, y), terrain)


func _paint_scatter(region: Rect2i, density: float, terrain: String, salt: int) -> void:
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var cell := Vector2i(x, y)
			var sample := float(_stable_hash(cell, "scatter-%d" % salt) % 10000) / 10000.0
			if sample < density:
				_paint(cell, terrain)


func _resolve_tiles() -> void:
	_terrain_layer.clear()
	for y in range(_height):
		for x in range(_width):
			var cell := Vector2i(x, y)
			var terrain := String(_terrain_field.get(cell, ""))
			var variant := _select_variant(cell, terrain)
			if variant.is_empty():
				continue
			_terrain_layer.set_cell(cell, variant.source_id, variant.atlas_coords, variant.alternative)


func _select_variant(cell: Vector2i, terrain: String) -> Dictionary:
	if _auto_edges and EDGE_AWARE_TILES.has(terrain):
		var role := _edge_role(cell, terrain)
		var rules: Dictionary = EDGE_AWARE_TILES[terrain]
		var candidates: Array = rules.get(role, rules.get("center", []))
		if not candidates.is_empty():
			var rule: Dictionary = candidates[_variant_index(cell, "%s-%s" % [terrain, role], candidates.size())]
			var atlas_coords: Vector2i = rule.coords
			var exact_variant: Dictionary = _atlas_tiles.get(_atlas_key(atlas_coords), {})
			if not exact_variant.is_empty() and exact_variant.terrain == terrain:
				var variant_name := String(rule.name)
				_resolved_variant_counts[variant_name] = int(_resolved_variant_counts.get(variant_name, 0)) + 1
				return exact_variant

	var variants: Array = _terrain_tiles.get(terrain, [])
	if variants.is_empty():
		return {}
	return variants[_variant_index(cell, terrain, variants.size())]


func _edge_role(cell: Vector2i, terrain: String) -> String:
	var mask := 0
	if not _same_terrain(cell + Vector2i.UP, terrain):
		mask |= 1
	if not _same_terrain(cell + Vector2i.RIGHT, terrain):
		mask |= 2
	if not _same_terrain(cell + Vector2i.DOWN, terrain):
		mask |= 4
	if not _same_terrain(cell + Vector2i.LEFT, terrain):
		mask |= 8
	return String(EDGE_ROLE_BY_MASK.get(mask, "center"))


func _same_terrain(cell: Vector2i, terrain: String) -> bool:
	return _inside(cell) and String(_terrain_field.get(cell, "")) == terrain


func _atlas_key(coords: Vector2i) -> String:
	return "%d,%d" % [coords.x, coords.y]


func _validate_complete_map() -> bool:
	for y in range(_height):
		for x in range(_width):
			if _terrain_layer.get_cell_source_id(Vector2i(x, y)) < 0:
				_fail("地图存在未填充格: (%d,%d)" % [x, y])
				return false
	var used := _terrain_layer.get_used_rect()
	if used != Rect2i(0, 0, _width, _height):
		_fail("地图边界异常，期望 %dx%d，实际 %s" % [_width, _height, used])
		return false
	return true


func _print_summary(scene_path: String) -> void:
	var counts := {}
	for cell in _terrain_layer.get_used_cells():
		var data := _terrain_layer.get_cell_tile_data(cell)
		var terrain := _normalize_terrain(String(data.get_custom_data("terrain_type")))
		counts[terrain] = int(counts.get(terrain, 0)) + 1
	var names := counts.keys()
	names.sort()
	print("[MapDesigner] %s | %dx%d | %d cells" % [scene_path, _width, _height, _width * _height])
	for terrain in names:
		print("  tile.%s: %d" % [terrain, counts[terrain]])
	if not _resolved_variant_counts.is_empty():
		print("[MapDesigner] 自动边缘图块:")
		var variant_names := _resolved_variant_counts.keys()
		variant_names.sort()
		for variant_name in variant_names:
			print("  %s: %d" % [variant_name, _resolved_variant_counts[variant_name]])


func _normalize_terrain(value: String) -> String:
	var key := value.strip_edges().to_lower().replace("\"", "").replace("tile.", "").strip_edges()
	var aliases := {
		"土地": "soil", "泥土": "soil", "土壤": "soil", "dirt": "soil",
		"草地": "grass", "平原": "grass", "plains": "grass",
		"道路": "road", "公路": "road",
		"森林": "forest", "密林": "forest", "woods": "forest",
		"灌木": "brush", "灌丛": "brush", "花草": "brush", "bush": "brush",
		"岩地": "rock", "岩石": "rock", "山地": "rock", "mountain": "rock",
		"水域": "water", "河流": "water", "river": "water",
	}
	return aliases.get(key, key)


func _require_terrain(terrain: String) -> bool:
	if terrain.is_empty() or not _terrain_tiles.has(terrain):
		_fail("未知或不可用的地块: %s。请运行 --list-terrains 查看可用指令" % terrain)
		return false
	return true


func _vector2i(value, label: String) -> Vector2i:
	if not value is Array or value.size() != 2:
		_fail("%s 必须是 [x, y]" % label)
		return Vector2i.ZERO
	return Vector2i(int(value[0]), int(value[1]))


func _point_array(value, label: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not value is Array:
		_fail("%s 必须是坐标数组" % label)
		return result
	for index in range(value.size()):
		result.append(_vector2i(value[index], "%s[%d]" % [label, index]))
	return result


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < _width and cell.y >= 0 and cell.y < _height


func _variant_index(cell: Vector2i, terrain: String, count: int) -> int:
	return _stable_hash(cell, terrain) % count


func _stable_hash(cell: Vector2i, salt: String) -> int:
	var value := int(cell.x) * 73856093 ^ int(cell.y) * 19349663 ^ _seed * 83492791 ^ hash(salt)
	return absi(value) & 0x7fffffff


func _fail(message: String) -> void:
	push_error("[MapDesigner] %s" % message)
	quit(1)
