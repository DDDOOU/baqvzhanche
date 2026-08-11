# ==============================================================================
# UnitBase.gd — 单位基类
# ==============================================================================
# 作用：所有战斗单位的基础类，包含生命、弹药、士气、移动点数、攻击属性、
#       以及华约/北约所有单位类型的通用接口。
# Godot 4.7.1 兼容 — 作为 Node2D 子节点挂载到场景
# ==============================================================================
class_name UnitBase
extends Node2D

## === 阵营枚举 ===
enum Faction {
	WARSAW_PACT,  # 华约（玩家）
	NATO,         # 北约（AI敌方）
	NEUTRAL       # 中立（平民车队/未知接触）
}

## === 单位类型 ===
enum UnitType {
	INFANTRY_SQUAD,       # 步兵班
	MOTOR_RIFLE,          # 摩托化步兵
	T72B_TANK,            # T-72B 主战坦克
	BMP2_IFV,             # BMP-2 步兵战车
	BM21_ROCKET,          # BM-21 火箭炮
	SA13_AA,              # SA-13 防空导弹
	RECON_PLATOON,        # 侦察连
	SAPPERS,              # 工兵班
	COMMAND_ELEMENT,      # 指挥组
	RESERVE,              # 预备队
	M1A1_TANK,            # M1A1 坦克（北约）
	M2_IFV,               # M2 步战车（北约）
	MECH_INFANTRY,        # 机械化步兵（北约）
	AH64_HELICOPTER,      # AH-64 直升机（北约）
	NATO_ENGINEER,        # 北约工兵
	CIVILIAN_CONVOY,      # 平民车队（中立）
	UNKNOWN_CONTACT,      # 未知接触
	ATGM_TEAM,            # 反坦克导弹组
	BRDM2_RECON,          # BRDM-2 侦察车
	ZSU23_AA,             # ZSU-23-4 防空车
	GVOZDIKA_ARTILLERY,   # 2S1 自行火炮
	M901_ITV,             # M901 反坦克导弹车
	M109_ARTILLERY,       # M109 自行火炮
	M113_APC,             # M113 装甲输送车
	NATO_RECON_SECTION    # 北约侦察分队
}

## === 核心属性 ===
@export var unit_id: int = 0
@export var unit_name: String = ""
@export var faction: Faction = Faction.WARSAW_PACT
@export var unit_type: UnitType = UnitType.INFANTRY_SQUAD

## 网格位置
var grid_col: int = 0
var grid_row: int = 0

## 生命与状态
@export var max_health: float = 100.0
var current_health: float = 100.0
@export var max_ammo: int = 100
var current_ammo: int = 100
var is_alive: bool = true
var is_suppressed: bool = false

## 战斗属性
@export var attack_power: float = 30.0       # 基础攻击力
@export var armor_value: float = 20.0         # 装甲值
@export var penetration: float = 10.0         # 穿透力
@export var accuracy: float = 0.70            # 基础命中率 (0-1)
@export var attack_range: int = 5             # 基础攻击射程（格数）
@export var attacks_per_turn: int = 1         # 每回合攻击次数

## 移动属性
@export var movement_points: int = 6          # 每回合移动点数
@export var move_speed: float = 1.0           # 移动速度倍率
var remaining_movement: int = 0

## 视野与侦察
@export var vision_range: int = 6             # 基础视野（格数）
@export var recon_bonus: int = 0              # 侦察加成（侦察连+2）

## 特殊能力标记
@export var can_lay_mines: bool = false       # 可布雷
@export var can_clear_mines: bool = false      # 可排雷
@export var can_repair_bridge: bool = false    # 可架桥
@export var can_transport: bool = false        # 可运输步兵
@export var is_anti_air: bool = false          # 可防空
@export var is_command: bool = false           # 是指挥单位
var embarked_unit = null                       # 搭载的单位（BMP-2）

## 尺寸（占格数）
@export var size_cols: int = 1                 # 横向占格
@export var size_rows: int = 1                 # 纵向占格

## 方向（影响正面装甲判定）
@export var facing_angle: float = 0.0          # 正面朝向（弧度）

## 隐蔽状态
var is_hidden: bool = false
var concealment_bonus: float = 0.0

## 当前指令
var current_order: Dictionary = {}


## === 初始化 ===
func _ready() -> void:
	add_to_group("units")
	remaining_movement = movement_points
	_init_from_type()


func _init_from_type() -> void:
	"""根据单位类型设置默认属性"""
	var stats = UnitDatabase.get_unit_stats(unit_type)
	if not stats.is_empty():
		max_health = stats.get("health", 100)
		current_health = max_health
		max_ammo = stats.get("ammo", 100)
		current_ammo = max_ammo
		attack_power = stats.get("attack", 30)
		armor_value = stats.get("armor", 20)
		penetration = stats.get("penetration", 10)
		movement_points = stats.get("movement", 6)
		vision_range = stats.get("vision", 6)
		recon_bonus = stats.get("recon_bonus", 0)
		attack_range = stats.get("range", 5)
		accuracy = stats.get("accuracy", 0.7)
		can_lay_mines = stats.get("can_lay_mines", false)
		can_clear_mines = stats.get("can_clear_mines", false)
		can_repair_bridge = stats.get("can_repair_bridge", false)
		can_transport = stats.get("can_transport", false)
		is_anti_air = stats.get("anti_air", false)
		is_command = stats.get("is_command", false)
		var sz = stats.get("size", Vector2i(1, 1))
		size_cols = sz.x
		size_rows = sz.y

	# 初始化士气
	MoraleSystem.init_unit_morale(unit_id, 75)


## === 移动 ===
func set_grid_position(col: int, row: int) -> void:
	"""设置网格位置并更新世界坐标，同时维护格子的占用单位"""
	# 先释放旧格子占用
	var old_cell = GridManager.get_cell(grid_col, grid_row)
	if old_cell and old_cell.occupant_unit == self:
		old_cell.occupant_unit = null
	# 再占用新格子
	grid_col = col
	grid_row = row
	var new_cell = GridManager.get_cell(col, row)
	if new_cell:
		new_cell.occupant_unit = self
	var world_pos = GridManager.grid_to_world(col, row)
	position = world_pos


func can_move_to(col: int, row: int) -> bool:
	"""检查是否可以移动到目标格"""
	var cell = GridManager.get_cell(col, row)
	if not cell:
		return false
	# 检查地形通行性
	var is_armored = (unit_type in [
		UnitType.T72B_TANK, UnitType.BMP2_IFV, UnitType.M1A1_TANK, UnitType.M2_IFV,
		UnitType.BRDM2_RECON, UnitType.ZSU23_AA, UnitType.GVOZDIKA_ARTILLERY,
		UnitType.M901_ITV, UnitType.M109_ARTILLERY, UnitType.M113_APC,
	])
	if not cell.is_passable_for(is_armored):
		return false
	# 检查是否有敌方单位占据
	if cell.occupant_unit and cell.occupant_unit.faction != faction:
		return false
	return true


func get_effective_movement() -> int:
	"""获取修正后的移动点数"""
	var mp = movement_points
	# 士气修正
	mp += MoraleSystem.get_move_modifier(unit_id)
	# 地形修正（当前格子）
	var cell = GridManager.get_cell(grid_col, grid_row)
	if cell:
		mp = int(float(mp) / cell.get_move_cost())
	return maxi(1, mp)


## === 攻击 ===
func can_attack_target(target_col: int, target_row: int) -> bool:
	"""检查是否可以攻击目标"""
	if current_ammo <= 0:
		return false
	var dist = GridManager.manhattan_distance(grid_col, grid_row, target_col, target_row)
	if dist > get_effective_range():
		return false
	# 检查视线
	if not LineOfSight.has_line_of_sight(grid_col, grid_row, target_col, target_row):
		return false
	return true


func get_effective_range() -> int:
	"""获取修正后的攻击射程"""
	var r = attack_range
	# EMI修正
	var cell = GridManager.get_cell(grid_col, grid_row)
	if cell:
		# 高地+1射程
		if cell.get_effective_height() >= 2:
			r += 1
	return r


func get_effective_accuracy() -> float:
	"""获取所有修正后的命中率"""
	var acc = accuracy
	# 士气修正
	acc += MoraleSystem.get_hit_modifier(unit_id)
	# EMI修正
	acc = EMISystem.apply_hit_modifier(acc)
	# 高度差优势
	# (在攻击时由CombatSystem添加)
	return clampf(acc, 0.05, 0.95)


func get_effective_damage() -> float:
	"""获取修正后的伤害"""
	var dmg = attack_power
	return dmg


## === 伤害处理 ===
func take_damage(amount: float, source_unit_id: int = -1) -> void:
	"""受到伤害"""
	var actual_damage = amount * (1.0 - armor_value / 200.0)  # 装甲减伤
	current_health = maxf(0.0, current_health - actual_damage)

	print("[Unit %d] 受到 %.1f 伤害 (原始: %.1f), 剩余生命: %.1f" % [unit_id, actual_damage, amount, current_health])

	if current_health <= 0:
		_on_death(source_unit_id)


func _on_death(_killer_id: int) -> void:
	"""单位死亡"""
	is_alive = false
	print("[Unit %d] %s 已被摧毁" % [unit_id, unit_name])
	# 清除网格占用
	var cell = GridManager.get_cell(grid_col, grid_row)
	if cell:
		cell.occupant_unit = null
	queue_free()


func is_side_armor(col: int, row: int) -> bool:
	"""判断攻击是否来自侧后（用于装甲薄弱判定）"""
	if unit_type in [UnitType.T72B_TANK, UnitType.M1A1_TANK]:
		# 2×2坦克单位：判断攻击方向
		var dx = col - grid_col
		var dy = row - grid_row
		if dx == 0 and dy == 0:
			return false
		var angle = atan2(dy, dx)
		# 与正面朝向的夹角（0~PI），修复: 原公式 abs(fposmod(angle-facing,TAU)-PI)
		# 度量的是"与正后方的夹角"，正面攻击反而被判为侧面。
		var off := fposmod(angle - facing_angle, TAU)
		off = minf(off, TAU - off)
		return off > PI / 3.0  # 超过60度偏移视为侧后
	return false


## === 序列化 ===
func serialize() -> Dictionary:
	return {
		"unit_id": unit_id,
		"unit_name": unit_name,
		"faction": faction,
		"unit_type": unit_type,
		"grid_col": grid_col,
		"grid_row": grid_row,
		"current_health": current_health,
		"current_ammo": current_ammo,
		"facing_angle": facing_angle,
		"is_alive": is_alive,
		"remaining_movement": remaining_movement,
		"vision_range": vision_range,
		"base_vision_range": int(get_meta("base_vision_range", vision_range)),
		"is_suppressed": is_suppressed,
		"is_hidden": is_hidden,
		"concealment_bonus": concealment_bonus,
		"current_order": current_order
	}


func restore(data: Dictionary) -> void:
	"""在工厂创建默认单位后恢复一局中的动态状态。"""
	unit_id = int(data.get("unit_id", unit_id))
	unit_name = String(data.get("unit_name", unit_name))
	current_health = float(data.get("current_health", max_health))
	current_ammo = int(data.get("current_ammo", max_ammo))
	facing_angle = float(data.get("facing_angle", 0.0))
	is_alive = bool(data.get("is_alive", true))
	remaining_movement = int(data.get("remaining_movement", movement_points))
	vision_range = int(data.get("vision_range", vision_range))
	set_meta("base_vision_range", int(data.get("base_vision_range", vision_range)))
	is_suppressed = bool(data.get("is_suppressed", false))
	is_hidden = bool(data.get("is_hidden", false))
	concealment_bonus = float(data.get("concealment_bonus", 0.0))
	current_order = data.get("current_order", {}) as Dictionary
	set_grid_position(int(data.get("grid_col", grid_col)), int(data.get("grid_row", grid_row)))
