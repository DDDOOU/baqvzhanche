# ==============================================================================
# UnitDatabase.gd — 华约/北约单位数据库
# ==============================================================================
# 作用：定义所有单位类型的默认属性。同时作为单位ID生成器。
#       对应设计文档 1.4 节「华约共享单位与卡牌池」。
# Godot 4.7.1 兼容
# ==============================================================================
extends Node

const EXTERNAL_CONFIG_PATH := "res://data/units/unit_config.json"
const PLAYER_CONFIG_PATH := "user://unit_config_overrides.json"

## 玩家可调整的基础属性。官方Excel仍是基准值，玩家只保存差异。
const PLAYER_EDITABLE_FIELDS: Dictionary = {
	"health": {"label": "生命值", "min": 10.0, "max": 500.0, "step": 5.0, "integer": true},
	"ammo": {"label": "弹药量", "min": 0.0, "max": 500.0, "step": 5.0, "integer": true},
	"attack": {"label": "攻击力", "min": 0.0, "max": 200.0, "step": 1.0, "integer": true},
	"armor": {"label": "装甲值", "min": 0.0, "max": 200.0, "step": 1.0, "integer": true},
	"penetration": {"label": "穿透力", "min": 0.0, "max": 200.0, "step": 1.0, "integer": true},
	"accuracy": {"label": "命中率", "min": 0.05, "max": 1.0, "step": 0.01, "integer": false, "percent": true},
	"range": {"label": "攻击射程", "min": 1.0, "max": 30.0, "step": 1.0, "integer": true},
	"movement": {"label": "移动力", "min": 1.0, "max": 30.0, "step": 1.0, "integer": true},
	"vision": {"label": "视野", "min": 1.0, "max": 30.0, "step": 1.0, "integer": true},
}

## === 单位ID生成器 ===
var next_unit_id: int = 1000
var _external_unit_stats: Dictionary = {}
var _external_config_loaded := false
var _player_overrides: Dictionary = {}


func _ready() -> void:
	reload_unit_config()
	load_player_overrides()


func reload_unit_config() -> bool:
	"""重新读取由Excel同步工具生成的JSON；失败时继续使用代码内置数据。"""
	_external_unit_stats.clear()
	_external_config_loaded = false
	if not FileAccess.file_exists(EXTERNAL_CONFIG_PATH):
		push_warning("[UnitDatabase] 外部单位配置不存在，使用代码默认值：%s" % EXTERNAL_CONFIG_PATH)
		return false

	var file := FileAccess.open(EXTERNAL_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("[UnitDatabase] 无法读取外部单位配置，使用代码默认值")
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("[UnitDatabase] 外部单位配置JSON格式无效，使用代码默认值")
		return false
	var payload := parsed as Dictionary
	var raw_units: Dictionary = payload.get("units", {}) as Dictionary
	for enum_key in raw_units.keys():
		var enum_name := String(enum_key)
		if not UnitBase.UnitType.has(enum_name):
			push_warning("[UnitDatabase] 配置中存在未知单位枚举：%s" % enum_name)
			continue
		var raw_stats: Dictionary = raw_units[enum_key] as Dictionary
		var stats := raw_stats.duplicate(true)
		stats["size"] = Vector2i(
			int(raw_stats.get("size_cols", 1)),
			int(raw_stats.get("size_rows", 1)))
		_external_unit_stats[int(UnitBase.UnitType[enum_name])] = stats

	_external_config_loaded = not _external_unit_stats.is_empty()
	if _external_config_loaded:
		print("[UnitDatabase] 已加载Excel同步配置：%d种单位" % _external_unit_stats.size())
	else:
		push_warning("[UnitDatabase] 外部配置没有有效单位，使用代码默认值")
	return _external_config_loaded


func is_external_config_loaded() -> bool:
	return _external_config_loaded


func get_external_config_count() -> int:
	return _external_unit_stats.size()


func load_player_overrides() -> bool:
	_player_overrides.clear()
	if not FileAccess.file_exists(PLAYER_CONFIG_PATH):
		return true
	var file := FileAccess.open(PLAYER_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("[UnitDatabase] 无法读取玩家单位配置")
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("[UnitDatabase] 玩家单位配置格式无效，已忽略")
		return false
	var raw_overrides: Dictionary = (parsed as Dictionary).get("overrides", {}) as Dictionary
	for enum_key in raw_overrides.keys():
		var enum_name := String(enum_key)
		if not UnitBase.UnitType.has(enum_name):
			continue
		var unit_type := int(UnitBase.UnitType[enum_name])
		var sanitized := _sanitize_player_values(raw_overrides[enum_key] as Dictionary)
		if not sanitized.is_empty():
			_player_overrides[unit_type] = sanitized
	print("[UnitDatabase] 已加载玩家单位配置：%d种单位" % _player_overrides.size())
	return true


func save_player_overrides() -> bool:
	var serialized: Dictionary = {}
	for unit_type in _player_overrides.keys():
		serialized[get_unit_enum_name(int(unit_type))] = (_player_overrides[unit_type] as Dictionary).duplicate(true)
	var payload := {
		"schema_version": 1,
		"overrides": serialized,
	}
	var file := FileAccess.open(PLAYER_CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[UnitDatabase] 无法保存玩家单位配置")
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	return true


func set_player_unit_overrides(unit_type: UnitBase.UnitType, values: Dictionary) -> bool:
	var base := get_official_unit_stats(unit_type)
	if base.is_empty():
		return false
	var sanitized := _sanitize_player_values(values)
	var differences: Dictionary = {}
	for field in sanitized.keys():
		var spec: Dictionary = PLAYER_EDITABLE_FIELDS[field]
		var current_value: Variant = sanitized[field]
		var base_value: Variant = base.get(field, current_value)
		var differs := absf(float(current_value) - float(base_value)) > (0.0001 if not bool(spec.get("integer", false)) else 0.0)
		if differs:
			differences[field] = current_value
	if differences.is_empty():
		_player_overrides.erase(unit_type)
	else:
		_player_overrides[unit_type] = differences
	return save_player_overrides()


func reset_player_unit_overrides(unit_type: UnitBase.UnitType) -> bool:
	_player_overrides.erase(unit_type)
	return save_player_overrides()


func reset_all_player_overrides() -> bool:
	_player_overrides.clear()
	return save_player_overrides()


func has_player_override(unit_type: UnitBase.UnitType) -> bool:
	return unit_type in _player_overrides


func get_player_editable_fields() -> Dictionary:
	return PLAYER_EDITABLE_FIELDS.duplicate(true)


func get_configurable_unit_types() -> Array[int]:
	var result: Array[int] = []
	for unit_type in _external_unit_stats.keys():
		result.append(int(unit_type))
	result.sort_custom(func(a: int, b: int) -> bool:
		var a_stats := get_official_unit_stats(a)
		var b_stats := get_official_unit_stats(b)
		var a_faction := String(a_stats.get("faction", ""))
		var b_faction := String(b_stats.get("faction", ""))
		if a_faction == b_faction:
			return String(a_stats.get("name", "")) < String(b_stats.get("name", ""))
		return a_faction < b_faction
	)
	return result


func get_unit_enum_name(unit_type: UnitBase.UnitType) -> String:
	var keys := UnitBase.UnitType.keys()
	if unit_type < 0 or unit_type >= keys.size():
		return "UNKNOWN"
	return String(keys[unit_type])


func _sanitize_player_values(values: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field in PLAYER_EDITABLE_FIELDS.keys():
		if not values.has(field):
			continue
		var spec: Dictionary = PLAYER_EDITABLE_FIELDS[field]
		var value := clampf(float(values[field]), float(spec["min"]), float(spec["max"]))
		result[field] = int(round(value)) if bool(spec.get("integer", false)) else value
	return result

## === 华约单位属性表 ===
const WP_UNIT_STATS: Dictionary = {
	UnitBase.UnitType.INFANTRY_SQUAD: {
		"name": "步兵班", "health": 80, "ammo": 100,
		"attack": 25, "armor": 10, "penetration": 5,
		"accuracy": 0.75, "range": 4, "movement": 5,
		"vision": 5, "size": Vector2i(1, 1),
		"class": "infantry", "cost": 1,
		"move_speed": 0.8,
	},
	UnitBase.UnitType.MOTOR_RIFLE: {
		"name": "摩托化步兵", "health": 90, "ammo": 120,
		"attack": 20, "armor": 15, "penetration": 10,
		"accuracy": 0.70, "range": 5, "movement": 8,
		"vision": 5, "size": Vector2i(1, 2),
		"class": "infantry_mech", "cost": 2,
		"move_speed": 1.1,
	},
	UnitBase.UnitType.T72B_TANK: {
		"name": "T-72B 主战坦克", "health": 150, "ammo": 40,
		"attack": 60, "armor": 70, "penetration": 50,
		"accuracy": 0.80, "range": 7, "movement": 5,
		"vision": 4, "size": Vector2i(2, 2),
		"class": "armor", "cost": 3,
		"move_speed": 1.0,
	},
	UnitBase.UnitType.BMP2_IFV: {
		"name": "BMP-2 步兵战车", "health": 120, "ammo": 60,
		"attack": 40, "armor": 30, "penetration": 30,
		"accuracy": 0.75, "range": 6, "movement": 7,
		"vision": 5, "size": Vector2i(1, 2),
		"class": "ifv", "cost": 2,
		"can_transport": true, "transport_capacity": 1,
		"move_speed": 1.1,
	},
	UnitBase.UnitType.BM21_ROCKET: {
		"name": "BM-21 火箭炮", "health": 60, "ammo": 30,
		"attack": 50, "armor": 5, "penetration": 0,
		"accuracy": 0.40, "range": 12, "movement": 4,
		"vision": 3, "size": Vector2i(2, 1),
		"class": "artillery", "cost": 3,
		"area_effect": 3,
		"move_speed": 0.9,
	},
	UnitBase.UnitType.SA13_AA: {
		"name": "SA-13 防空导弹", "health": 70, "ammo": 20,
		"attack": 45, "armor": 10, "penetration": 5,
		"accuracy": 0.85, "range": 8, "movement": 5,
		"vision": 6, "size": Vector2i(1, 1),
		"class": "support", "cost": 2,
		"anti_air": true, "anti_air_bonus": 0.3,
		"move_speed": 1.0,
	},
	UnitBase.UnitType.RECON_PLATOON: {
		"name": "侦察连", "health": 50, "ammo": 80,
		"attack": 10, "armor": 5, "penetration": 0,
		"accuracy": 0.60, "range": 4, "movement": 8,
		"vision": 8, "recon_bonus": 2, "size": Vector2i(1, 1),
		"class": "support", "cost": 1,
		"move_speed": 1.0,
	},
	UnitBase.UnitType.SAPPERS: {
		"name": "工兵班", "health": 70, "ammo": 60,
		"attack": 15, "armor": 5, "penetration": 0,
		"accuracy": 0.65, "range": 3, "movement": 6,
		"vision": 5, "size": Vector2i(1, 1),
		"class": "support", "cost": 1,
		"can_lay_mines": true, "can_clear_mines": true,
		"can_repair_bridge": true, "can_destroy_bridge": true,
		"move_speed": 0.8,
	},
	UnitBase.UnitType.COMMAND_ELEMENT: {
		"name": "指挥组", "health": 50, "ammo": 50,
		"attack": 5, "armor": 10, "penetration": 0,
		"accuracy": 0.50, "range": 3, "movement": 4,
		"vision": 7, "size": Vector2i(1, 1),
		"class": "support", "cost": 0,
		"is_command": true, "command_radius": 5,
		"move_speed": 0.8,
	},
	UnitBase.UnitType.RESERVE: {
		"name": "预备队", "health": 100, "ammo": 100,
		"attack": 30, "armor": 20, "penetration": 15,
		"accuracy": 0.70, "range": 5, "movement": 6,
		"vision": 5, "size": Vector2i(1, 2),
		"class": "infantry_mech", "cost": 2,
		"move_speed": 1.0,
	},
	UnitBase.UnitType.ATGM_TEAM: {
		"name": "反坦克导弹组", "health": 55, "ammo": 18,
		"attack": 45, "armor": 5, "penetration": 55,
		"accuracy": 0.72, "range": 9, "movement": 4,
		"vision": 6, "size": Vector2i(1, 1),
		"class": "anti_tank", "cost": 2,
		"move_speed": 0.7,
	},
	UnitBase.UnitType.BRDM2_RECON: {
		"name": "BRDM-2 侦察车", "health": 65, "ammo": 70,
		"attack": 18, "armor": 12, "penetration": 8,
		"accuracy": 0.66, "range": 5, "movement": 9,
		"vision": 9, "recon_bonus": 3, "size": Vector2i(1, 1),
		"class": "recon_vehicle", "cost": 2,
		"move_speed": 1.3,
	},
	UnitBase.UnitType.ZSU23_AA: {
		"name": "ZSU-23-4 防空车", "health": 85, "ammo": 90,
		"attack": 36, "armor": 18, "penetration": 12,
		"accuracy": 0.78, "range": 7, "movement": 6,
		"vision": 7, "size": Vector2i(1, 1),
		"class": "air_defense", "cost": 2,
		"anti_air": true, "anti_air_bonus": 0.25,
		"move_speed": 1.1,
	},
	UnitBase.UnitType.GVOZDIKA_ARTILLERY: {
		"name": "2S1 自行火炮", "health": 90, "ammo": 36,
		"attack": 48, "armor": 12, "penetration": 5,
		"accuracy": 0.52, "range": 13, "movement": 5,
		"vision": 4, "size": Vector2i(2, 1),
		"class": "artillery", "cost": 3,
		"area_effect": 2,
		"move_speed": 0.9,
	},
}

## === 北约单位属性表 ===
const NATO_UNIT_STATS: Dictionary = {
	UnitBase.UnitType.M1A1_TANK: {
		"name": "M1A1 主战坦克", "health": 160, "ammo": 45,
		"attack": 65, "armor": 75, "penetration": 55,
		"accuracy": 0.82, "range": 8, "movement": 6,
		"vision": 5, "size": Vector2i(2, 2),
		"class": "armor", "cost": 3,
		"move_speed": 1.0,
	},
	UnitBase.UnitType.M2_IFV: {
		"name": "M2 Bradley 步战车", "health": 125, "ammo": 65,
		"attack": 42, "armor": 32, "penetration": 35,
		"accuracy": 0.78, "range": 6, "movement": 7,
		"vision": 5, "size": Vector2i(1, 2),
		"class": "ifv", "cost": 2,
		"can_transport": true, "transport_capacity": 1,
		"move_speed": 1.1,
	},
	UnitBase.UnitType.MECH_INFANTRY: {
		"name": "机械化步兵", "health": 85, "ammo": 110,
		"attack": 28, "armor": 20, "penetration": 12,
		"accuracy": 0.73, "range": 5, "movement": 6,
		"vision": 5, "size": Vector2i(1, 1),
		"class": "infantry_mech", "cost": 1,
		"move_speed": 0.8,
	},
	UnitBase.UnitType.AH64_HELICOPTER: {
		"name": "AH-64 阿帕奇", "health": 100, "ammo": 30,
		"attack": 55, "armor": 15, "penetration": 40,
		"accuracy": 0.85, "range": 10, "movement": 12,
		"vision": 8, "size": Vector2i(1, 1),
		"class": "air", "cost": 4,
		"can_cross_river": true, "can_cross_mountain": true,
		"move_speed": 1.6,
	},
	UnitBase.UnitType.NATO_ENGINEER: {
		"name": "北约工兵", "health": 70, "ammo": 60,
		"attack": 12, "armor": 8, "penetration": 0,
		"accuracy": 0.60, "range": 3, "movement": 6,
		"vision": 5, "size": Vector2i(1, 1),
		"class": "support", "cost": 1,
		"can_lay_mines": true, "can_clear_mines": true,
		"move_speed": 0.8,
	},
	UnitBase.UnitType.M901_ITV: {
		"name": "M901 反坦克导弹车", "health": 80, "ammo": 16,
		"attack": 52, "armor": 18, "penetration": 60,
		"accuracy": 0.74, "range": 10, "movement": 6,
		"vision": 6, "size": Vector2i(1, 1),
		"class": "anti_tank", "cost": 3,
		"move_speed": 1.2,
	},
	UnitBase.UnitType.M109_ARTILLERY: {
		"name": "M109 自行火炮", "health": 95, "ammo": 34,
		"attack": 52, "armor": 14, "penetration": 5,
		"accuracy": 0.54, "range": 14, "movement": 5,
		"vision": 4, "size": Vector2i(2, 1),
		"class": "artillery", "cost": 3,
		"area_effect": 2,
		"move_speed": 0.9,
	},
	UnitBase.UnitType.M113_APC: {
		"name": "M113 装甲输送车", "health": 100, "ammo": 80,
		"attack": 24, "armor": 22, "penetration": 8,
		"accuracy": 0.68, "range": 5, "movement": 7,
		"vision": 5, "size": Vector2i(1, 2),
		"class": "apc", "cost": 2,
		"can_transport": true, "transport_capacity": 1,
		"move_speed": 1.2,
	},
	UnitBase.UnitType.NATO_RECON_SECTION: {
		"name": "北约侦察分队", "health": 60, "ammo": 80,
		"attack": 16, "armor": 6, "penetration": 3,
		"accuracy": 0.68, "range": 5, "movement": 7,
		"vision": 9, "recon_bonus": 3, "size": Vector2i(1, 1),
		"class": "recon", "cost": 2,
		"move_speed": 1.0,
	},
}

## === 中立单位 ===
const NEUTRAL_UNIT_STATS: Dictionary = {
	UnitBase.UnitType.CIVILIAN_CONVOY: {
		"name": "平民车队", "health": 30, "ammo": 0,
		"attack": 0, "armor": 0, "penetration": 0,
		"accuracy": 0.0, "range": 0, "movement": 4,
		"vision": 3, "size": Vector2i(1, 1),
		"class": "civilian", "cost": 0,
		"move_speed": 0.6,
	},
	UnitBase.UnitType.UNKNOWN_CONTACT: {
		"name": "未知接触", "health": 50, "ammo": 50,
		"attack": 10, "armor": 10, "penetration": 5,
		"accuracy": 0.50, "range": 4, "movement": 5,
		"vision": 4, "size": Vector2i(1, 1),
		"class": "unknown", "cost": 0,
		"move_speed": 1.0,
	},
}


## === 查询方法 ===
func get_unit_stats(unit_type: UnitBase.UnitType) -> Dictionary:
	"""获取实际生效属性：官方基准值叠加玩家保存的差异。"""
	var stats := get_official_unit_stats(unit_type)
	if stats.is_empty():
		return {}
	if unit_type in _player_overrides:
		for field in (_player_overrides[unit_type] as Dictionary).keys():
			stats[field] = _player_overrides[unit_type][field]
	return stats


func get_official_unit_stats(unit_type: UnitBase.UnitType) -> Dictionary:
	"""获取不含玩家修改的官方基准属性。"""
	if unit_type in _external_unit_stats:
		return (_external_unit_stats[unit_type] as Dictionary).duplicate(true)
	if unit_type in WP_UNIT_STATS:
		return (WP_UNIT_STATS[unit_type] as Dictionary).duplicate(true)
	if unit_type in NATO_UNIT_STATS:
		return (NATO_UNIT_STATS[unit_type] as Dictionary).duplicate(true)
	if unit_type in NEUTRAL_UNIT_STATS:
		return (NEUTRAL_UNIT_STATS[unit_type] as Dictionary).duplicate(true)
	return {}


func get_unit_name(unit_type: UnitBase.UnitType) -> String:
	return get_unit_stats(unit_type).get("name", "未知单位")


func get_unit_class(unit_type: UnitBase.UnitType) -> String:
	return get_unit_stats(unit_type).get("class", "unknown")


func generate_unit_id() -> int:
	"""生成唯一单位ID"""
	next_unit_id += 1
	return next_unit_id


func reset_for_level() -> void:
	"""保证重开后单位ID可预测，且不携带上一局计数。"""
	next_unit_id = 1000


func create_unit(unit_type: UnitBase.UnitType, faction: UnitBase.Faction,
		col: int, row: int, parent_node: Node, initial_morale: int = 70) -> UnitBase:
	"""工厂方法：创建一个单位实例（initial_morale: 关卡数据可指定, 默认70避免开局全员ELATED）"""
	var unit = UnitBase.new()
	unit.unit_id = generate_unit_id()
	unit.unit_type = unit_type
	unit.faction = faction
	unit.unit_name = get_unit_name(unit_type)

	var stats = get_unit_stats(unit_type)
	unit.apply_config_stats(stats, true)

	unit.set_grid_position(col, row)

	if parent_node:
		parent_node.add_child(unit)

	# 初始化士气
	MoraleSystem.init_unit_morale(unit.unit_id, initial_morale)

	print("[UnitDatabase] 创建单位: %s (ID=%d) at (%d,%d)" % [unit.unit_name, unit.unit_id, col, row])
	return unit


func restore_unit(data: Dictionary, parent_node: Node) -> UnitBase:
	"""从存档创建并恢复一个单位，同时维护后续ID不重复。"""
	var unit := create_unit(
		int(data.get("unit_type", UnitBase.UnitType.INFANTRY_SQUAD)),
		int(data.get("faction", UnitBase.Faction.WARSAW_PACT)),
		int(data.get("grid_col", 0)),
		int(data.get("grid_row", 0)),
		parent_node,
		int(data.get("morale", 70)))
	unit.restore(data)
	next_unit_id = maxi(next_unit_id, unit.unit_id)
	return unit
