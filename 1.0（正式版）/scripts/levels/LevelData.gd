# ==============================================================================
# LevelData.gd — 关卡数据结构
# ==============================================================================
# 作用：定义单个关卡的全部数据 — 地图、单位配置、手牌、回合事件。
#       可在Godot编辑器中作为Resource (.tres) 管理。
# Godot 4.7.1 兼容
# ==============================================================================
class_name LevelData
extends Resource

## === 基本信息 ===
@export var level_id: int = 0
@export var level_name: String = ""
@export var act_number: int = 1            # 所属幕 (1-3)
@export var designer_intent: String = ""   # 设计师意图

## === 剧情 ===
@export_multiline var briefing: String = ""       # 开战前战报
@export_multiline var outro_narration: String = "" # 战后结算旁白

## === 地图 ===
@export var map_width: int = 40
@export var map_height: int = 45
@export var map_data: Dictionary = {}       # 地形数据
@export var vp_cells: Array = []  # 关键战略坐标
@export var wp_spawn: Array = []  # 华约出生点
@export var nato_spawn: Array = [] # 北约出生点
@export var wp_command_center: Vector2i = Vector2i.ZERO
@export var nato_command_center: Vector2i = Vector2i.ZERO

## === 目标 ===
@export_multiline var primary_objective: String = ""
@export_multiline var hidden_objective: String = ""
@export_multiline var failure_condition: String = ""
@export_multiline var victory_condition: String = ""
@export var core_mechanics: Array = [] # 开场与战斗HUD共用的本关核心机制说明

## === 华约配置 ===
@export var wp_starting_cards: Array = []  # 起始手牌ID列表
@export var wp_units: Array = []        # 初始单位配置
@export var wp_reserve_units: Array = [] # 预备队配置

## === 北约配置 ===
@export var nato_units: Array = []       # 初始单位配置
@export var nato_ai_behavior: int = 0                 # AI初始倾向
@export var nato_reserve_units: Array = [] # 预备队

## === 环境设置 ===
@export var emi_base_level: float = 0.0              # EMI基础水平
@export var max_turns: int = 15
@export var weather: String = "clear"                 # "clear", "fog", "snow", "rain"
@export var fog_of_war: bool = true
@export var default_vision: int = 6
@export var weather_vision_penalty: int = 0

## === 回合事件 ===
@export var turn_events: Array = []  # [{turn, event_id, data}]

## === 已知情报 ===
@export_multiline var intel_a: String = ""
@export_multiline var intel_b: String = ""
@export_multiline var intel_c: String = ""
@export var hidden_intel: Array = []     # 玩家不知道的情报

## === 特殊事件 ===
@export var special_events: Array = []
@export var narrative_branches: Array = []

## === 辅助方法 ===
func get_summary() -> String:
	return "第%d关: %s [第%d幕]" % [level_id + 1, level_name, act_number]


func get_unit_count(faction: int) -> int:
	"""获取某一阵营的初始单位数量"""
	var count = 0
	if faction == UnitBase.Faction.WARSAW_PACT:
		count = wp_units.size()
	else:
		count = nato_units.size()
	return count
