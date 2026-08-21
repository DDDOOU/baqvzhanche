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

## === 装甲面枚举（攻击方向） ===
enum ArmorAspect {
	FRONT,  # 正面 — 全额装甲
	SIDE,   # 侧面 — 装甲×0.55, 伤害×1.35
	REAR    # 后方 — 装甲×0.35, 伤害×1.50
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


## 行动顺序统一比较规则：配置表先手值高者优先，其次移动速度，最后用ID保证稳定顺序。
static func acts_before(a: UnitBase, b: UnitBase) -> bool:
	if a.initiative != b.initiative:
		return a.initiative > b.initiative
	if not is_equal_approx(a.move_speed, b.move_speed):
		return a.move_speed > b.move_speed
	return a.unit_id < b.unit_id

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

## 行动点与演绎先手（由Excel同步配置加载；战斗流程将在后续版本正式消费）
@export var base_action_points: int = 1
@export var can_store_action_points: bool = false
@export var max_stored_action_points: int = 0
@export_range(1, 5, 1) var initiative: int = 3
@export var action_order: String = "移动→攻击"
@export var can_attack_after_move: bool = true
@export var can_move_after_attack: bool = false
@export var requires_stationary_attack: bool = false
@export var reaction_action_type: String = "无"
@export var special_action_replaces_attack: bool = false
var remaining_action_points: int = 0
var stored_action_points: int = 0

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
@export var transport_capacity: int = 0
@export var anti_air_bonus: float = 0.0
@export var area_effect_radius: int = 0
@export var can_destroy_bridge: bool = false
@export var can_cross_river: bool = false
@export var can_cross_mountain: bool = false
@export var command_radius: int = 0
var embarked_unit: UnitBase = null             # 搭载的单位（BMP-2 修复批B: transport 字段消费）

## === 搭载 ===
func mount_passenger(unit: UnitBase) -> bool:
	"""步兵搭载进载具。修复批B: transport_capacity 字段消费（原为死字段）。"""
	if not can_transport or transport_capacity <= 0 or embarked_unit != null:
		return false
	if unit == null or not unit.is_alive or unit.faction != faction:
		return false
	if unit.unit_type in [UnitType.INFANTRY_SQUAD, UnitType.MOTOR_RIFLE, UnitType.MECH_INFANTRY]:
		embarked_unit = unit
		unit.visible = false
		var cell = GridManager.get_cell(unit.grid_col, unit.grid_row)
		if cell and cell.occupant_unit == unit:
			cell.occupant_unit = null
		return true
	return false


func unmount_passenger() -> UnitBase:
	"""卸载步兵到载具相邻空位。"""
	if embarked_unit == null:
		return null
	var passenger := embarked_unit
	embarked_unit = null
	passenger.visible = true
	for nb in GridManager.get_neighbors(grid_col, grid_row):
		var cell = GridManager.get_cell(nb.x, nb.y)
		if cell and cell.is_passable_for(false) and cell.occupant_unit == null:
			passenger.set_grid_position(nb.x, nb.y)
			return passenger
	passenger.set_grid_position(grid_col, grid_row)
	return passenger

## 单位特性文本；先作为数据层字段，后续战斗逻辑按枚举/字段实现具体效果。
@export var trait_name: String = ""
@export var trait_trigger: String = ""
@export var trait_effect: String = ""
@export var trait_limit: String = ""
@export var config_status: String = ""

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
	_init_from_type()
	reset_movement_for_turn()
	reset_action_points_for_turn()


func _init_from_type() -> void:
	"""根据单位类型设置默认属性"""
	var stats = UnitDatabase.get_unit_stats(unit_type)
	if not stats.is_empty():
		apply_config_stats(stats, true)

	# 初始化士气
	MoraleSystem.init_unit_morale(unit_id, 70)  # 默认70: 避免开局全员ELATED(阈值75)


func apply_config_stats(stats: Dictionary, reset_runtime_values: bool = false) -> void:
	"""把UnitDatabase配置统一应用到实例，避免工厂与_ready出现两套字段。"""
	max_health = float(stats.get("health", 100))
	max_ammo = int(stats.get("ammo", 100))
	attack_power = float(stats.get("attack", 30))
	armor_value = float(stats.get("armor", 20))
	penetration = float(stats.get("penetration", 10))
	accuracy = float(stats.get("accuracy", 0.7))
	attack_range = int(stats.get("range", 5))
	attacks_per_turn = int(stats.get("max_attacks_per_turn", 1))
	movement_points = int(stats.get("movement", 6))
	move_speed = float(stats.get("move_speed", 1.0))
	vision_range = int(stats.get("vision", 6))
	recon_bonus = int(stats.get("recon_bonus", 0))

	can_lay_mines = bool(stats.get("can_lay_mines", false))
	can_clear_mines = bool(stats.get("can_clear_mines", false))
	can_repair_bridge = bool(stats.get("can_repair_bridge", false))
	can_destroy_bridge = bool(stats.get("can_destroy_bridge", false))
	can_transport = bool(stats.get("can_transport", false))
	transport_capacity = int(stats.get("transport_capacity", 0))
	is_anti_air = bool(stats.get("anti_air", false))
	anti_air_bonus = float(stats.get("anti_air_bonus", 0.0))
	area_effect_radius = int(stats.get("area_effect", 0))
	is_command = bool(stats.get("is_command", false))
	command_radius = int(stats.get("command_radius", 0))
	can_cross_river = bool(stats.get("can_cross_river", false))
	can_cross_mountain = bool(stats.get("can_cross_mountain", false))

	base_action_points = int(stats.get("base_action_points", 1))
	can_store_action_points = bool(stats.get("can_store_action_points", false))
	max_stored_action_points = int(stats.get("max_stored_action_points", 0))
	initiative = clampi(int(stats.get("initiative", 3)), 1, 5)
	action_order = String(stats.get("action_order", "移动→攻击"))
	can_attack_after_move = bool(stats.get("can_attack_after_move", true))
	can_move_after_attack = bool(stats.get("can_move_after_attack", false))
	requires_stationary_attack = bool(stats.get("requires_stationary_attack", false))
	reaction_action_type = String(stats.get("reaction_action_type", "无"))
	special_action_replaces_attack = bool(stats.get("special_action_replaces_attack", false))
	trait_name = String(stats.get("trait_name", ""))
	trait_trigger = String(stats.get("trait_trigger", ""))
	trait_effect = String(stats.get("trait_effect", ""))
	trait_limit = String(stats.get("trait_limit", ""))
	config_status = String(stats.get("config_status", ""))

	var sz: Vector2i = stats.get("size", Vector2i(1, 1))
	size_cols = sz.x
	size_rows = sz.y
	if reset_runtime_values:
		current_health = max_health
		current_ammo = max_ammo
		remaining_action_points = base_action_points + stored_action_points


func reset_action_points_for_turn() -> void:
	remaining_action_points = maxi(0, base_action_points + stored_action_points)
	stored_action_points = 0


## === 移动 ===
func reset_movement_for_turn() -> void:
	"""恢复本回合的有效移动点，包含士气和当前地形修正。"""
	remaining_movement = get_effective_movement()


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
	# 修复批B: 搭载的步兵随载具同步移动
	if embarked_unit != null and embarked_unit.is_alive:
		embarked_unit.set_grid_position(col, row)


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
	if not cell.is_passable_for(is_armored, self):
		return false
	# 检查是否有敌方单位占据
	if cell.occupant_unit and cell.occupant_unit.faction != faction:
		return false
	return true


func get_effective_movement() -> int:
	"""获取修正后的移动点数（MP 单位, 供寻路预算与执行重置统一使用）
	修复: 原实现按当前格地形折算成"格数"再被寻路当成本预算双重计费——
	公路 UI 高估 4 倍、山地 UI 0 格不可移动"""
	var mp = movement_points
	mp += MoraleSystem.get_move_modifier(unit_id)
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
	var cell = GridManager.get_cell(grid_col, grid_row)
	if cell:
		r += cell.get_attack_range_modifier()
	return maxi(1, r)


func get_effective_vision_range() -> int:
	"""获取当前地块高度修正后的基础视野；EMI由视线系统继续结算。"""
	var result := vision_range + recon_bonus
	var cell = GridManager.get_cell(grid_col, grid_row)
	if cell:
		result += cell.get_vision_modifier()
	return maxi(1, result)


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


## === 补给 ===
func resupply(ratio: float = 1.0) -> void:
	"""补充弹药。ratio=1.0 全额补给（指挥中心范围）, 0.5 半额（回合自动补给）。
	修复批B: 原无补给机制, 单位弹药打完即废。"""
	if not is_alive or max_ammo <= 0:
		return
	if ratio >= 1.0:
		current_ammo = max_ammo
	else:
		current_ammo = mini(max_ammo, current_ammo + maxi(1, int(max_ammo * ratio)))


## === 伤害处理 ===
func take_damage(amount: float, source_unit_id: int = -1) -> void:
	"""受到伤害 — 修复批B: 移除 armor/200 二次减伤（装甲已在 DamageCalculator
	统一处理, 原实现造成双重减伤）。补 is_alive 防御: 死亡后不再重复处理。"""
	if not is_alive:
		return
	current_health = maxf(0.0, current_health - amount)

	print("[Unit %d] 受到 %.1f 伤害, 剩余生命: %.1f" % [unit_id, amount, current_health])

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
	"""判断攻击是否来自侧后（用于装甲薄弱判定, 兼容旧调用）"""
	return get_armor_aspect(col, row) != ArmorAspect.FRONT


func get_armor_aspect(col: int, row: int) -> int:
	"""攻击方向装甲面: FRONT/SIDE/REAR（修复批B: 原 bool 无法区分侧/后,
	后方+50%加成与装甲 0.55/0.35 折算从未生效）"""
	if unit_type in [UnitType.T72B_TANK, UnitType.M1A1_TANK]:
		# 2×2坦克单位：判断攻击方向
		var dx = col - grid_col
		var dy = row - grid_row
		if dx == 0 and dy == 0:
			return ArmorAspect.FRONT
		var angle = atan2(dy, dx)
		# 与正面朝向的夹角（0~PI）
		var off := fposmod(angle - facing_angle, TAU)
		off = minf(off, TAU - off)
		if off <= PI / 6.0:
			return ArmorAspect.FRONT    # ±30° 正面
		if off <= PI / 2.0 + PI / 6.0:
			return ArmorAspect.SIDE     # 30°~120° 侧面
		return ArmorAspect.REAR         # >120° 后方
	return ArmorAspect.FRONT


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
		"remaining_action_points": remaining_action_points,
		"stored_action_points": stored_action_points,
		"vision_range": vision_range,
		"base_vision_range": int(get_meta("base_vision_range", vision_range)),
		"is_suppressed": is_suppressed,
		"is_hidden": is_hidden,
		"concealment_bonus": concealment_bonus,
		"current_order": current_order,
		"morale": MoraleSystem.get_unit_morale(unit_id)
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
	remaining_action_points = int(data.get("remaining_action_points", base_action_points))
	stored_action_points = int(data.get("stored_action_points", 0))
	vision_range = int(data.get("vision_range", vision_range))
	set_meta("base_vision_range", int(data.get("base_vision_range", vision_range)))
	is_suppressed = bool(data.get("is_suppressed", false))
	is_hidden = bool(data.get("is_hidden", false))
	concealment_bonus = float(data.get("concealment_bonus", 0.0))
	current_order = data.get("current_order", {}) as Dictionary
	set_grid_position(int(data.get("grid_col", grid_col)), int(data.get("grid_row", grid_row)))
