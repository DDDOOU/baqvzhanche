# ==============================================================================
# UnitDatabase.gd — 华约/北约单位数据库
# ==============================================================================
# 作用：定义所有单位类型的默认属性。同时作为单位ID生成器。
#       对应设计文档 1.4 节「华约共享单位与卡牌池」。
# Godot 4.7.1 兼容
# ==============================================================================
extends Node

## === 单位ID生成器 ===
var next_unit_id: int = 1000

## === 华约单位属性表 ===
const WP_UNIT_STATS: Dictionary = {
	UnitBase.UnitType.INFANTRY_SQUAD: {
		"name": "步兵班", "health": 80, "ammo": 100,
		"attack": 25, "armor": 10, "penetration": 5,
		"accuracy": 0.75, "range": 4, "movement": 5,
		"vision": 5, "size": Vector2i(1, 1),
		"class": "infantry", "cost": 1
	},
	UnitBase.UnitType.MOTOR_RIFLE: {
		"name": "摩托化步兵", "health": 90, "ammo": 120,
		"attack": 20, "armor": 15, "penetration": 10,
		"accuracy": 0.70, "range": 5, "movement": 8,
		"vision": 5, "size": Vector2i(1, 2),
		"class": "infantry_mech", "cost": 2
	},
	UnitBase.UnitType.T72B_TANK: {
		"name": "T-72B 主战坦克", "health": 150, "ammo": 40,
		"attack": 60, "armor": 70, "penetration": 50,
		"accuracy": 0.80, "range": 7, "movement": 5,
		"vision": 4, "size": Vector2i(2, 2),
		"class": "armor", "cost": 3
	},
	UnitBase.UnitType.BMP2_IFV: {
		"name": "BMP-2 步兵战车", "health": 120, "ammo": 60,
		"attack": 40, "armor": 30, "penetration": 30,
		"accuracy": 0.75, "range": 6, "movement": 7,
		"vision": 5, "size": Vector2i(1, 2),
		"class": "ifv", "cost": 2,
		"can_transport": true, "transport_capacity": 1
	},
	UnitBase.UnitType.BM21_ROCKET: {
		"name": "BM-21 火箭炮", "health": 60, "ammo": 30,
		"attack": 50, "armor": 5, "penetration": 0,
		"accuracy": 0.40, "range": 12, "movement": 4,
		"vision": 3, "size": Vector2i(2, 1),
		"class": "artillery", "cost": 3,
		"area_effect": 3
	},
	UnitBase.UnitType.SA13_AA: {
		"name": "SA-13 防空导弹", "health": 70, "ammo": 20,
		"attack": 45, "armor": 10, "penetration": 5,
		"accuracy": 0.85, "range": 8, "movement": 5,
		"vision": 6, "size": Vector2i(1, 1),
		"class": "support", "cost": 2,
		"anti_air": true, "anti_air_bonus": 0.3
	},
	UnitBase.UnitType.RECON_PLATOON: {
		"name": "侦察连", "health": 50, "ammo": 80,
		"attack": 10, "armor": 5, "penetration": 0,
		"accuracy": 0.60, "range": 4, "movement": 8,
		"vision": 8, "recon_bonus": 2, "size": Vector2i(1, 1),
		"class": "support", "cost": 1
	},
	UnitBase.UnitType.SAPPERS: {
		"name": "工兵班", "health": 70, "ammo": 60,
		"attack": 15, "armor": 5, "penetration": 0,
		"accuracy": 0.65, "range": 3, "movement": 6,
		"vision": 5, "size": Vector2i(1, 1),
		"class": "support", "cost": 1,
		"can_lay_mines": true, "can_clear_mines": true,
		"can_repair_bridge": true, "can_destroy_bridge": true
	},
	UnitBase.UnitType.COMMAND_ELEMENT: {
		"name": "指挥组", "health": 50, "ammo": 50,
		"attack": 5, "armor": 10, "penetration": 0,
		"accuracy": 0.50, "range": 3, "movement": 4,
		"vision": 7, "size": Vector2i(1, 1),
		"class": "support", "cost": 0,
		"is_command": true, "command_radius": 5
	},
	UnitBase.UnitType.RESERVE: {
		"name": "预备队", "health": 100, "ammo": 100,
		"attack": 30, "armor": 20, "penetration": 15,
		"accuracy": 0.70, "range": 5, "movement": 6,
		"vision": 5, "size": Vector2i(1, 2),
		"class": "infantry_mech", "cost": 2
	},
	UnitBase.UnitType.ATGM_TEAM: {
		"name": "反坦克导弹组", "health": 55, "ammo": 18,
		"attack": 45, "armor": 5, "penetration": 55,
		"accuracy": 0.72, "range": 9, "movement": 4,
		"vision": 6, "size": Vector2i(1, 1),
		"class": "anti_tank", "cost": 2
	},
	UnitBase.UnitType.BRDM2_RECON: {
		"name": "BRDM-2 侦察车", "health": 65, "ammo": 70,
		"attack": 18, "armor": 12, "penetration": 8,
		"accuracy": 0.66, "range": 5, "movement": 9,
		"vision": 9, "recon_bonus": 3, "size": Vector2i(1, 1),
		"class": "recon_vehicle", "cost": 2
	},
	UnitBase.UnitType.ZSU23_AA: {
		"name": "ZSU-23-4 防空车", "health": 85, "ammo": 90,
		"attack": 36, "armor": 18, "penetration": 12,
		"accuracy": 0.78, "range": 7, "movement": 6,
		"vision": 7, "size": Vector2i(1, 1),
		"class": "air_defense", "cost": 2,
		"anti_air": true, "anti_air_bonus": 0.25
	},
	UnitBase.UnitType.GVOZDIKA_ARTILLERY: {
		"name": "2S1 自行火炮", "health": 90, "ammo": 36,
		"attack": 48, "armor": 12, "penetration": 5,
		"accuracy": 0.52, "range": 13, "movement": 5,
		"vision": 4, "size": Vector2i(2, 1),
		"class": "artillery", "cost": 3,
		"area_effect": 2
	},
}

## === 北约单位属性表 ===
const NATO_UNIT_STATS: Dictionary = {
	UnitBase.UnitType.M1A1_TANK: {
		"name": "M1A1 主战坦克", "health": 160, "ammo": 45,
		"attack": 65, "armor": 75, "penetration": 55,
		"accuracy": 0.82, "range": 8, "movement": 6,
		"vision": 5, "size": Vector2i(2, 2),
		"class": "armor", "cost": 3
	},
	UnitBase.UnitType.M2_IFV: {
		"name": "M2 Bradley 步战车", "health": 125, "ammo": 65,
		"attack": 42, "armor": 32, "penetration": 35,
		"accuracy": 0.78, "range": 6, "movement": 7,
		"vision": 5, "size": Vector2i(1, 2),
		"class": "ifv", "cost": 2,
		"can_transport": true, "transport_capacity": 1
	},
	UnitBase.UnitType.MECH_INFANTRY: {
		"name": "机械化步兵", "health": 85, "ammo": 110,
		"attack": 28, "armor": 20, "penetration": 12,
		"accuracy": 0.73, "range": 5, "movement": 6,
		"vision": 5, "size": Vector2i(1, 1),
		"class": "infantry_mech", "cost": 1
	},
	UnitBase.UnitType.AH64_HELICOPTER: {
		"name": "AH-64 阿帕奇", "health": 100, "ammo": 30,
		"attack": 55, "armor": 15, "penetration": 40,
		"accuracy": 0.85, "range": 10, "movement": 12,
		"vision": 8, "size": Vector2i(1, 1),
		"class": "air", "cost": 4,
		"can_cross_river": true, "can_cross_mountain": true
	},
	UnitBase.UnitType.NATO_ENGINEER: {
		"name": "北约工兵", "health": 70, "ammo": 60,
		"attack": 12, "armor": 8, "penetration": 0,
		"accuracy": 0.60, "range": 3, "movement": 6,
		"vision": 5, "size": Vector2i(1, 1),
		"class": "support", "cost": 1,
		"can_lay_mines": true, "can_clear_mines": true
	},
	UnitBase.UnitType.M901_ITV: {
		"name": "M901 反坦克导弹车", "health": 80, "ammo": 16,
		"attack": 52, "armor": 18, "penetration": 60,
		"accuracy": 0.74, "range": 10, "movement": 6,
		"vision": 6, "size": Vector2i(1, 1),
		"class": "anti_tank", "cost": 3
	},
	UnitBase.UnitType.M109_ARTILLERY: {
		"name": "M109 自行火炮", "health": 95, "ammo": 34,
		"attack": 52, "armor": 14, "penetration": 5,
		"accuracy": 0.54, "range": 14, "movement": 5,
		"vision": 4, "size": Vector2i(2, 1),
		"class": "artillery", "cost": 3,
		"area_effect": 2
	},
	UnitBase.UnitType.M113_APC: {
		"name": "M113 装甲输送车", "health": 100, "ammo": 80,
		"attack": 24, "armor": 22, "penetration": 8,
		"accuracy": 0.68, "range": 5, "movement": 7,
		"vision": 5, "size": Vector2i(1, 2),
		"class": "apc", "cost": 2,
		"can_transport": true, "transport_capacity": 1
	},
	UnitBase.UnitType.NATO_RECON_SECTION: {
		"name": "北约侦察分队", "health": 60, "ammo": 80,
		"attack": 16, "armor": 6, "penetration": 3,
		"accuracy": 0.68, "range": 5, "movement": 7,
		"vision": 9, "recon_bonus": 3, "size": Vector2i(1, 1),
		"class": "recon", "cost": 2
	},
}

## === 中立单位 ===
const NEUTRAL_UNIT_STATS: Dictionary = {
	UnitBase.UnitType.CIVILIAN_CONVOY: {
		"name": "平民车队", "health": 30, "ammo": 0,
		"attack": 0, "armor": 0, "penetration": 0,
		"accuracy": 0.0, "range": 0, "movement": 4,
		"vision": 3, "size": Vector2i(1, 1),
		"class": "civilian", "cost": 0
	},
	UnitBase.UnitType.UNKNOWN_CONTACT: {
		"name": "未知接触", "health": 50, "ammo": 50,
		"attack": 10, "armor": 10, "penetration": 5,
		"accuracy": 0.50, "range": 4, "movement": 5,
		"vision": 4, "size": Vector2i(1, 1),
		"class": "unknown", "cost": 0
	},
}


## === 查询方法 ===
func get_unit_stats(unit_type: UnitBase.UnitType) -> Dictionary:
	"""获取单位类型的属性"""
	if unit_type in WP_UNIT_STATS:
		return WP_UNIT_STATS[unit_type]
	if unit_type in NATO_UNIT_STATS:
		return NATO_UNIT_STATS[unit_type]
	if unit_type in NEUTRAL_UNIT_STATS:
		return NEUTRAL_UNIT_STATS[unit_type]
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
		col: int, row: int, parent_node: Node) -> UnitBase:
	"""工厂方法：创建一个单位实例"""
	var unit = UnitBase.new()
	unit.unit_id = generate_unit_id()
	unit.unit_type = unit_type
	unit.faction = faction
	unit.unit_name = get_unit_name(unit_type)

	var stats = get_unit_stats(unit_type)
	unit.max_health = stats.get("health", 100)
	unit.current_health = unit.max_health
	unit.max_ammo = stats.get("ammo", 100)
	unit.current_ammo = unit.max_ammo
	unit.attack_power = stats.get("attack", 30)
	unit.armor_value = stats.get("armor", 20)
	unit.penetration = stats.get("penetration", 10)
	unit.accuracy = stats.get("accuracy", 0.7)
	unit.attack_range = stats.get("range", 5)
	unit.movement_points = stats.get("movement", 6)
	unit.vision_range = stats.get("vision", 5)
	unit.recon_bonus = stats.get("recon_bonus", 0)

	# 特殊能力
	unit.can_lay_mines = stats.get("can_lay_mines", false)
	unit.can_clear_mines = stats.get("can_clear_mines", false)
	unit.can_repair_bridge = stats.get("can_repair_bridge", false)
	unit.can_transport = stats.get("can_transport", false)
	unit.is_anti_air = stats.get("anti_air", false)
	unit.is_command = stats.get("is_command", false)

	# 尺寸
	var sz = stats.get("size", Vector2i(1, 1))
	unit.size_cols = sz.x
	unit.size_rows = sz.y

	unit.set_grid_position(col, row)

	if parent_node:
		parent_node.add_child(unit)

	# 初始化士气
	MoraleSystem.init_unit_morale(unit.unit_id, 75)

	print("[UnitDatabase] 创建单位: %s (ID=%d) at (%d,%d)" % [unit.unit_name, unit.unit_id, col, row])
	return unit


func restore_unit(data: Dictionary, parent_node: Node) -> UnitBase:
	"""从存档创建并恢复一个单位，同时维护后续ID不重复。"""
	var unit := create_unit(
		int(data.get("unit_type", UnitBase.UnitType.INFANTRY_SQUAD)),
		int(data.get("faction", UnitBase.Faction.WARSAW_PACT)),
		int(data.get("grid_col", 0)),
		int(data.get("grid_row", 0)),
		parent_node)
	unit.restore(data)
	next_unit_id = maxi(next_unit_id, unit.unit_id)
	# 修复: create_unit 用新生成的 unit_id 初始化了士气, restore 覆盖 unit_id 后
	# MoraleSystem 键失配 → 读档全体士气归零(BROKEN)。按存档值重新初始化。
	MoraleSystem.init_unit_morale(unit.unit_id, int(data.get("morale", 75)))
	return unit
