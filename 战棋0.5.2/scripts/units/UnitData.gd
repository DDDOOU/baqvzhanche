# ==============================================================================
# UnitData.gd — 单位数据资源类
# ==============================================================================
# 作用：定义单个单位类型的可配置数据容器。
#       可在Godot编辑器中作为 Resource (.tres) 文件管理。
# Godot 4.7.1 兼容
# ==============================================================================
class_name UnitData
extends Resource

## === 基本信息 ===
@export var unit_type_id: int = 0
@export var display_name: String = ""
@export var faction: int = 0          # 0=华约, 1=北约, 2=中立
@export var unit_class: String = ""   # "infantry", "armor", "artillery", "support", "air"

## === 网格尺寸 ===
@export var size_cols: int = 1
@export var size_rows: int = 1

## === 战斗属性 ===
@export var max_health: float = 100.0
@export var max_ammo: int = 100
@export var attack_power: float = 30.0
@export var armor_front: float = 50.0    # 正面装甲
@export var armor_side: float = 25.0     # 侧面装甲
@export var armor_rear: float = 15.0     # 后部装甲
@export var penetration: float = 10.0    # 穿甲值
@export var accuracy: float = 0.70       # 基础命中率

## === 射程与攻击 ===
@export var min_range: int = 1           # 最小射程
@export var max_range: int = 5           # 最大射程
@export var attacks_per_turn: int = 1
@export var damage_type: String = "kinetic"  # "kinetic", "explosive", "incendiary", "emp"
@export var area_effect_radius: int = 0  # 面杀伤范围 (0=单目标)

## === 移动属性 ===
@export var movement_points: int = 6
@export var move_speed: float = 1.0
@export var can_cross_river: bool = false
@export var can_cross_mountain: bool = false

## === 视野与侦察 ===
@export var vision_range: int = 6
@export var recon_bonus: int = 0         # 侦察附加视野

## === 特殊能力 ===
@export var can_lay_mines: bool = false
@export var can_clear_mines: bool = false
@export var can_repair_bridge: bool = false
@export var can_destroy_bridge: bool = false
@export var can_transport_infantry: bool = false
@export var transport_capacity: int = 0
@export var is_anti_air: bool = false
@export var anti_air_bonus: float = 0.0
@export var is_command: bool = false
@export var command_radius: int = 0

## === 造价（用于战役资源计量） ===
@export var deployment_cost: int = 1
@export var rarity: int = 0              # 0=常见, 1=稀有, 2=唯一

## === 帮助函数 ===
func get_armor_for_angle(attack_angle_diff: float) -> float:
	"""根据攻击角度返回对应的装甲值"""
	if attack_angle_diff < PI / 4.0:
		return armor_front
	elif attack_angle_diff < 3.0 * PI / 4.0:
		return armor_side
	else:
		return armor_rear
