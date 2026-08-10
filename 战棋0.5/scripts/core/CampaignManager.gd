# ==============================================================================
# CampaignManager.gd — 十关战役状态管理 (Autoload 单例)
# ==============================================================================
# 作用：追踪跨关卡的战役状态 — 累计士气、误伤、指挥贷款、击杀数。
#       管理三幕结构、战役终局判定（4种结局）。
#       每个关卡的胜负影响下一关的初始条件。
# Godot 4.7.1 兼容
# ==============================================================================
extends Node

## === 战役全局状态 ===
var campaign_morale: int = 80          # 累计士气 (0-100)
var campaign_friendly_fire: int = 0   # 累计误伤百分比 (0-100)
var campaign_loans: int = 0           # 累计指挥贷款 (0-50)
var campaign_kills: int = 0           # 累计击杀数
var current_act: int = 1              # 当前幕 (1-3)
var levels_completed: Array[int] = [] # 已完成的关卡ID
var level_results: Dictionary = {}    # level_id → result_data

## === 当前关卡参数 ===
var max_turns: int = 15

## === 关卡间传递的状态 ===
var reserve_units: Array = []         # 保留的预备队
var misha_alive: bool = true          # 米沙连是否存活
var misha_morale: int = 75            # 米沙连士气
var has_credit_loan: bool = false     # 是否透支过
var helicopter_kills: int = 0         # 累计直升机击落数
var civilian_casualties: int = 0      # 平民伤亡数

## === 信号 ===
signal morale_changed(new_value: int, delta: int)
signal friendly_fire_occurred(total: int)
signal loan_taken(amount: int, total: int)
signal act_changed(new_act: int)
signal misha_event_triggered(event_type: String)


func _ready() -> void:
	print("[CampaignManager] 战役管理器就绪 — 初始士气: %d" % campaign_morale)


## === 关卡初始化与结算 ===
func initialize_level(level_data) -> void:
	"""根据关卡数据初始化"""
	var ld = level_data
	max_turns = ld.max_turns
	print("[CampaignManager] 初始化第 %d 关: %s" % [ld.level_id, ld.level_name])


func apply_level_result(result: Dictionary) -> void:
	"""应用关卡结算结果到战役状态"""
	var level_id = result.get("level_id", 0)
	levels_completed.append(level_id)
	level_results[level_id] = result

	# 士气修正
	var morale_delta = result.get("morale_delta", 0)
	campaign_morale = clampi(campaign_morale + morale_delta, 0, 100)
	if morale_delta != 0:
		morale_changed.emit(campaign_morale, morale_delta)

	# 误伤累计
	var ff = result.get("friendly_fire_added", 0)
	campaign_friendly_fire = mini(campaign_friendly_fire + ff, 100)
	if ff > 0:
		friendly_fire_occurred.emit(campaign_friendly_fire)

	# 贷款累计
	var loan = result.get("loan_used", 0)
	campaign_loans = mini(campaign_loans + loan, 50)
	if loan > 0:
		loan_taken.emit(loan, campaign_loans)

	# 击杀累计
	campaign_kills += result.get("kills", 0)

	# 米沙状态更新
	if result.get("misha_wounded", false):
		misha_morale = maxi(0, misha_morale - 30)
		misha_event_triggered.emit("wounded")
	if result.get("misha_squad_lost", false):
		misha_alive = false
		misha_event_triggered.emit("killed")

	# 直升机击杀
	helicopter_kills += result.get("heli_kills", 0)

	# 平民伤亡
	civilian_casualties += result.get("civilian_casualties", 0)

	# 更新当前幕
	_update_act()

	print("[CampaignManager] 关卡 %d 结算完成 — 士气:%d, 误伤:%d%%, 贷款:%d, 击杀:%d" % [
		level_id, campaign_morale, campaign_friendly_fire, campaign_loans, campaign_kills
	])


func _update_act() -> void:
	var new_act = 1
	if levels_completed.size() >= 3:
		new_act = 2
	if levels_completed.size() >= 7:
		new_act = 3
	if new_act != current_act:
		current_act = new_act
		act_changed.emit(current_act)


## === 终局判定 ===
func get_final_result() -> Dictionary:
	"""根据四项累计指标判定战役结局"""
	var is_victory = false
	var ending_type = ""
	var description = ""

	if not misha_alive or campaign_loans > 50:
		# 坐标归零：无人归来
		ending_type = "zero_coordinates"
		is_victory = true  # 军事胜利，但...
		description = "华约赢得军事胜利，但失去所有预备队与士气基础。地图上的坐标全部归零，没有人记得回家的路。"
	elif campaign_morale < 40 or campaign_friendly_fire > 30:
		# 失守：清晰的失败
		ending_type = "clear_defeat"
		is_victory = false
		description = "华约指挥中心被摧毁，铁幕崩溃。列夫森科上校阵亡，战役结束。"
	elif campaign_morale >= 60 and campaign_friendly_fire <= 10:
		# 战略胜利：铁幕仍在
		ending_type = "strategic_victory"
		is_victory = true
		description = "「洪水」第四阶段成功。北约指挥中心被摧毁，敌军残部撤退。华约收复失地，铁幕仍在。"
	else:
		# 惨胜：洪水之后
		ending_type = "pyrrhic_victory"
		is_victory = true
		description = "战役胜利，但伤亡惨重。米沙连幸存，但战役中失去30%的友军。"

	return {
		"is_victory": is_victory,
		"ending_type": ending_type,
		"description": description,
		"final_morale": campaign_morale,
		"final_friendly_fire": campaign_friendly_fire,
		"final_loans": campaign_loans,
		"final_kills": campaign_kills,
		"misha_survived": misha_alive
	}


## === 查询接口 ===
func get_morale_tier() -> int:
	"""返回士气档位: 0=崩溃, 1=动摇, 2=稳定, 3=昂扬"""
	if campaign_morale >= 75: return 3
	if campaign_morale >= 50: return 2
	if campaign_morale >= 25: return 1
	return 0


func get_morale_tier_name() -> String:
	match get_morale_tier():
		3: return "昂扬"
		2: return "稳定"
		1: return "动摇"
		_: return "崩溃"


func check_level_completion(level_id: int) -> Dictionary:
	"""检查关卡是否达到完成条件 — 委托给 VictoryManager 检查VP和回合数"""
	var turn_result = VictoryManager.check_turn_end_victory(TurnManager.current_turn)
	if turn_result.completed:
		# 关卡结束，补充战役数据
		turn_result["level_id"] = level_id
		turn_result["kills"] = _count_kills_this_level()
		return turn_result
	return {"completed": false, "level_id": level_id}


func _count_kills_this_level() -> int:
	"""统计本关击杀数"""
	var nato_dead = 0
	for unit in Engine.get_main_loop().get_nodes_in_group("units"):
		if unit.faction == UnitBase.Faction.NATO and not unit.is_alive:
			nato_dead += 1
	return nato_dead


## === 序列化 ===
func serialize() -> Dictionary:
	return {
		"campaign_morale": campaign_morale,
		"campaign_friendly_fire": campaign_friendly_fire,
		"campaign_loans": campaign_loans,
		"campaign_kills": campaign_kills,
		"current_act": current_act,
		"levels_completed": levels_completed,
		"level_results": level_results,
		"reserve_units": reserve_units,
		"misha_alive": misha_alive,
		"misha_morale": misha_morale,
		"has_credit_loan": has_credit_loan,
		"helicopter_kills": helicopter_kills,
		"civilian_casualties": civilian_casualties
	}


func deserialize(data: Dictionary) -> void:
	campaign_morale = data.get("campaign_morale", 80)
	campaign_friendly_fire = data.get("campaign_friendly_fire", 0)
	campaign_loans = data.get("campaign_loans", 0)
	campaign_kills = data.get("campaign_kills", 0)
	current_act = data.get("current_act", 1)
	levels_completed.clear()
	for level_id in data.get("levels_completed", []):
		levels_completed.append(int(level_id))
	level_results.clear()
	for level_id in data.get("level_results", {}):
		level_results[int(level_id)] = data["level_results"][level_id]
	reserve_units = data.get("reserve_units", []).duplicate(true)
	misha_alive = data.get("misha_alive", true)
	misha_morale = data.get("misha_morale", 75)
	has_credit_loan = data.get("has_credit_loan", false)
	helicopter_kills = data.get("helicopter_kills", 0)
	civilian_casualties = data.get("civilian_casualties", 0)
