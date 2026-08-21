# ==============================================================================
# LevelDatabase.gd — 十关完整数据库
# ==============================================================================
# 作用：定义全部10个关卡的完整数据，包括地图、单位、回合事件。
#       对应设计文档第3-14节的十个关卡。
#       在实际项目中，这些数据可以从.tres资源文件加载。
# Godot 4.7.1 兼容
# ==============================================================================
extends Node

## === 所有关卡数据 ===
var levels: Array[LevelData] = []


func _ready() -> void:
	_build_all_levels()
	print("[LevelDatabase] 已加载 %d 个关卡数据" % levels.size())


## === 关卡数据构建 ===
func _build_all_levels() -> void:
	levels.clear()
	levels.append_array([
		_build_level_01(),
		_build_level_02(),
		_build_level_03(),
		_build_level_04(),
		_build_level_05(),
		_build_level_06(),
		_build_level_07(),
		_build_level_08(),
		_build_level_09(),
		_build_level_10(),
	])
	_complete_late_level_frameworks()


func _complete_late_level_frameworks() -> void:
	"""为第3-10关补齐共用的可运行框架；独立场景可在后续直接替换美术。"""
	# 战后旁白（第3-10关，按 level_id 索引；1-2关已在各自构建函数内手写）
	var outros := {
		2: "第一轮冲击退去了。但洪水不会只涨一次，河对岸的探照灯整夜未灭。",
		3: "林地里的枪声停了，误击的伤兵被抬下火线。指挥部的电话沉默了很久。",
		4: "预备队按时抵达，像钟表一样准确。可你知道，钟表匠已经不在乎时间了。",
		5: "桥断了，反击的路也断了。敌军在河对岸重新集结，等着你用最短的桥过河。",
		6: "整个频段静默得像坟场。你赢了这一仗，却听不见任何友军的回答。",
		7: "走廊尽头的光是白的，雪也是白的。你分不清哪边是黎明，哪边是信号弹。",
		8: "轨道在炮火下泛红，像一条动脉。列车还在一趟趟开往前线，装载着你看不见的东西。",
		9: "坐标归零。地图上最后一个标记被擦掉了——这一次，没有人能再标注你的位置。",
	}
	for level in levels:
		if String(level.outro_narration).is_empty() and outros.has(level.level_id):
			level.outro_narration = outros[level.level_id]
	for level in levels:
		if level.level_id < 2:
			continue
		level.map_width = 20
		level.map_height = 12
		level.wp_spawn = [Vector2i(1, 6), Vector2i(2, 5), Vector2i(2, 7), Vector2i(2, 8)]
		level.nato_spawn = [Vector2i(17, 6), Vector2i(18, 5), Vector2i(18, 7), Vector2i(18, 8)]
		if String(level.briefing).is_empty():
			level.briefing = "战役第%d关“%s”：在电磁干扰与敌军推进中守住中央战略走廊。" % [level.level_id + 1, level.level_name]
		if String(level.primary_objective).is_empty():
			level.primary_objective = "终局控制至少2个战略VP。"
		if String(level.victory_condition).is_empty():
			level.victory_condition = "控制至少2个VP，或摧毁敌方指挥单位。"
		if String(level.failure_condition).is_empty():
			level.failure_condition = "己方指挥单位被毁、全军覆没，或终局VP不足。"
		if level.nato_units.is_empty():
			level.nato_units = _build_default_nato_force(level.level_id)


func _build_default_nato_force(level_id: int) -> Array:
	var desired_count: int = {5: 8, 6: 10, 7: 8, 8: 10, 9: 12}.get(level_id, 8)
	var slots := [
		Vector2i(16, 6), Vector2i(15, 5), Vector2i(15, 7), Vector2i(16, 5),
		Vector2i(16, 7), Vector2i(17, 5), Vector2i(17, 7), Vector2i(15, 8),
		Vector2i(16, 8), Vector2i(17, 8), Vector2i(14, 6), Vector2i(14, 8),
	]
	var types := [
		UnitBase.UnitType.M1A1_TANK, UnitBase.UnitType.M1A1_TANK,
		UnitBase.UnitType.M2_IFV, UnitBase.UnitType.MECH_INFANTRY,
		UnitBase.UnitType.M2_IFV, UnitBase.UnitType.MECH_INFANTRY,
		UnitBase.UnitType.M901_ITV, UnitBase.UnitType.M109_ARTILLERY,
		UnitBase.UnitType.M113_APC, UnitBase.UnitType.MECH_INFANTRY,
		UnitBase.UnitType.M1A1_TANK, UnitBase.UnitType.NATO_ENGINEER,
	]
	var force: Array = []
	for index in range(desired_count):
		force.append({"type": types[index], "col": slots[index].x, "row": slots[index].y})
	return force


## === 第1关·边境晨雾 ===
func _build_level_01() -> LevelData:
	var level = LevelData.new()
	level.level_id = 0
	level.level_name = "边境晨雾"
	level.act_number = 1
	level.designer_intent = "教学关：让玩家熟悉60秒计划+30秒沙盘循环、坐标输入、基础侦察、士气概念。"
	level.briefing = "1987年9月14日04:30，雾。西部军区第29摩步师前沿哨所报告：'边境出现机械化纵队，未识别。'"
	level.outro_narration = "雾散之前，边境线上的警报声终于停了。这一夜没有英雄，只有哨所里活下来的人。"

	level.max_turns = 8
	level.map_width = 40
	level.map_height = 45
	level.default_vision = 3  # 晨雾
	level.weather = "fog"
	level.weather_vision_penalty = 3
	level.emi_base_level = 0.0

	# VP格（已按场景地形修正: 原(20,20)(20,21)在水/岩上不可通行）
	level.vp_cells = [Vector2i(19, 20), Vector2i(21, 21), Vector2i(20, 22)]
	level.wp_spawn = [Vector2i(4, 5), Vector2i(5, 6), Vector2i(5, 7), Vector2i(2, 6), Vector2i(4, 8)]
	level.nato_spawn = [Vector2i(35, 21), Vector2i(34, 21), Vector2i(36, 19), Vector2i(35, 22)]
	level.wp_command_center = Vector2i(4, 5)
	level.nato_command_center = Vector2i(35, 21)

	# 华约起始手牌
	level.wp_starting_cards = CardDatabase.get_level_cards(0)

	# 华约初始单位（坐标已按场景地形修正: 原 4/5 列多处落在岩石/工事/水域）
	level.wp_units = [
		{"type": UnitBase.UnitType.COMMAND_ELEMENT, "col": 4, "row": 5, "morale": 80},  # 列夫森科
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 4},   # 步兵A
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 5, "row": 7},   # 步兵B
		{"type": UnitBase.UnitType.T72B_TANK, "col": 4, "row": 7},
		{"type": UnitBase.UnitType.BMP2_IFV, "col": 5, "row": 6},
		{"type": UnitBase.UnitType.RECON_PLATOON, "col": 2, "row": 7},
		{"type": UnitBase.UnitType.ATGM_TEAM, "col": 8, "row": 18},
		{"type": UnitBase.UnitType.BRDM2_RECON, "col": 9, "row": 19},
		{"type": UnitBase.UnitType.ZSU23_AA, "col": 5, "row": 21},
		{"type": UnitBase.UnitType.GVOZDIKA_ARTILLERY, "col": 3, "row": 22},
	]

	# 北约初始单位（坐标已按场景地形修正: 原(35,20)(35,19)(33,18)在水/工事上）
	level.nato_units = [
		{"type": UnitBase.UnitType.M1A1_TANK, "col": 35, "row": 21},
		{"type": UnitBase.UnitType.M2_IFV, "col": 34, "row": 21},
		{"type": UnitBase.UnitType.MECH_INFANTRY, "col": 35, "row": 18},
		{"type": UnitBase.UnitType.MECH_INFANTRY, "col": 35, "row": 22},
		{"type": UnitBase.UnitType.M901_ITV, "col": 33, "row": 20},
		{"type": UnitBase.UnitType.M109_ARTILLERY, "col": 37, "row": 23},
		{"type": UnitBase.UnitType.M113_APC, "col": 36, "row": 21},
		{"type": UnitBase.UnitType.NATO_RECON_SECTION, "col": 34, "row": 18},
	]

	level.nato_ai_behavior = NATOAI.AIBehavior.SPEED_RUSH

	# 地形数据（设计文档 3.3：横向公路、北部山地、南部河谷）
	level.map_data = _build_level_01_terrain()

	# 回合事件
	level.turn_events = [
		{"turn": 1, "phase": "turn_start", "id": "fog_warning", "description": "晨雾生效，视野3格"},
		{"turn": 3, "phase": "turn_start", "id": "ah64_arrives", "description": "北约AH-64进场"},
		{"turn": 4, "phase": "turn_start", "id": "fog_lifts", "description": "晨雾消散，视野恢复6格"},
		{"turn": 5, "phase": "turn_start", "id": "emi_rise", "description": "EMI强度+5%", "emi_delta": 0.05},
		{"turn": 6, "phase": "turn_start", "id": "unknown_contact_1", "description": "未知接触出现(11,J)"},
		{"turn": 7, "phase": "turn_start", "id": "artillery_ready", "description": "列夫森科下令火箭炮准备"},
	]

	# 情报
	level.intel_a = "北部山地有雾，能见度低。"
	level.intel_b = "公路两侧疑有装甲目标。"
	level.intel_c = "未识别机型/旋翼声。"
	level.hidden_intel = ["敌军具体兵种", "各单位精确生命值", "北约预备队数量"]

	# 特殊事件
	level.special_events = [
		{"id": "fog_penalty", "effect": "hit-30%", "duration": 3},
		{"id": "friendly_fire_tutorial", "trigger": "blind_fire_on_11J", "effect": "infantry_B-25%"},
	]
	level.narrative_branches = [
		{"id": "steady_defense", "condition": "no_blind_fire_before_turn4", "dialogue": "列夫森科：我们守得住。"},
		{"id": "aggressive_blind_fire", "condition": "blind_fire_before_turn3", "dialogue": "步兵班B班长：我们打到了自己人。"},
		{"id": "heli_ambush", "condition": "kill_ah64_turn3", "dialogue": "卡琳娜：旋翼声消失了。"},
	]

	level.fog_of_war = true
	return level


## === 第2-10关（功能框架已接入，后续继续细化剧情与美术） ===
func _build_level_02() -> LevelData:
	var level = LevelData.new()
	level.level_id = 1
	level.level_name = "铁路线防御"
	level.act_number = 1
	level.briefing = "凌晨05:20，北约装甲纵队沿铁路枢纽推进。守住仓库、铁路桥与南侧桥头堡；工兵可布雷，也能安全排除雷区。"
	level.outro_narration = "你守住了第一节车厢。但你已经听到铁轨在响——不是火车，是下一场战役的脚步声。"
	level.primary_objective = "第10回合结束时控制至少2个铁路VP。"
	level.victory_condition = "守住至少2个VP，或摧毁北约指挥单位。"
	level.failure_condition = "己方指挥单位被毁、全军覆没，或终局控制少于2个VP。"
	level.max_turns = 10
	level.emi_base_level = 0.0
	level.map_width = 20
	level.map_height = 12
	level.vp_cells = [Vector2i(9, 6), Vector2i(9, 4), Vector2i(9, 8)]  # 桥、火车站、桥头堡
	level.wp_spawn = [Vector2i(2, 6), Vector2i(2, 8), Vector2i(1, 7)]
	level.nato_spawn = [Vector2i(17, 6), Vector2i(18, 8), Vector2i(18, 5)]
	level.wp_command_center = Vector2i(2, 6)
	level.nato_command_center = Vector2i(17, 6)
	level.wp_starting_cards = CardDatabase.get_level_cards(1)
	level.nato_ai_behavior = NATOAI.AIBehavior.STEADY_PUSH

	# 华约单位
	level.wp_units = [
		{"type": UnitBase.UnitType.COMMAND_ELEMENT, "col": 2, "row": 6, "morale": 70},
		{"type": UnitBase.UnitType.T72B_TANK, "col": 3, "row": 5},
		{"type": UnitBase.UnitType.T72B_TANK, "col": 4, "row": 5},
		{"type": UnitBase.UnitType.MOTOR_RIFLE, "col": 3, "row": 8},
		{"type": UnitBase.UnitType.MOTOR_RIFLE, "col": 4, "row": 8},
		{"type": UnitBase.UnitType.SAPPERS, "col": 3, "row": 6},
		{"type": UnitBase.UnitType.BM21_ROCKET, "col": 2, "row": 8},
	]
	level.nato_units = [
		{"type": UnitBase.UnitType.M1A1_TANK, "col": 15, "row": 5},
		{"type": UnitBase.UnitType.M1A1_TANK, "col": 16, "row": 5},
		{"type": UnitBase.UnitType.M1A1_TANK, "col": 15, "row": 8},
		{"type": UnitBase.UnitType.M2_IFV, "col": 16, "row": 7},
		{"type": UnitBase.UnitType.M2_IFV, "col": 17, "row": 6},
		{"type": UnitBase.UnitType.MECH_INFANTRY, "col": 15, "row": 6},
		{"type": UnitBase.UnitType.MECH_INFANTRY, "col": 17, "row": 8},
		{"type": UnitBase.UnitType.NATO_ENGINEER, "col": 16, "row": 6},
	]
	level.nato_reserve_units = [
		{"type": UnitBase.UnitType.AH64_HELICOPTER, "turn": 8},
	]
	level.intel_a = "敌军装甲至少3个单位。"
	level.intel_b = "铁路桥两端有可疑作业（可能是排雷/架桥）。"
	level.turn_events = [
		{"turn": 1, "phase": "turn_start", "id": "loan_tutorial", "description": "指挥贷款机制教学"},
		{"turn": 4, "phase": "turn_start", "id": "nato_engineer", "description": "北约工兵开始排雷"},
		{"turn": 5, "phase": "turn_start", "id": "emi_rise_15", "description": "EMI上升至15%", "emi_target": 0.15},
		{"turn": 6, "phase": "turn_start", "id": "reserve_ready", "description": "华约预备队可投入"},
		{"turn": 8, "phase": "turn_start", "id": "ah64_arrives", "description": "北约AH-64进场"},
		{"turn": 9, "phase": "turn_start", "id": "refugee_convoy", "description": "难民车队出现(12,J)"},
	]
	return level


func _build_level_03() -> LevelData:
	var level = LevelData.new()
	level.level_id = 2
	level.level_name = "第一轮洪水"
	level.act_number = 1
	level.max_turns = 12
	level.emi_base_level = 0.60  # 60% — 洪水第一阶段
	level.vp_cells = [Vector2i(9, 6), Vector2i(9, 5), Vector2i(9, 8)]
	level.wp_command_center = Vector2i(2, 6)
	level.nato_command_center = Vector2i(16, 6)
	level.wp_starting_cards = CardDatabase.get_level_cards(2)
	level.nato_ai_behavior = NATOAI.AIBehavior.FIRE_SUPPRESSION

	level.wp_units = [
		{"type": UnitBase.UnitType.COMMAND_ELEMENT, "col": 2, "row": 6, "morale": 65},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 5},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 7},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 3, "row": 8},
		{"type": UnitBase.UnitType.BMP2_IFV, "col": 4, "row": 6},
		{"type": UnitBase.UnitType.BM21_ROCKET, "col": 1, "row": 7},
		{"type": UnitBase.UnitType.SAPPERS, "col": 3, "row": 5},
	]
	level.nato_units = [
		{"type": UnitBase.UnitType.M1A1_TANK, "col": 15, "row": 5},
		{"type": UnitBase.UnitType.M1A1_TANK, "col": 16, "row": 7},
		{"type": UnitBase.UnitType.M2_IFV, "col": 15, "row": 7},
		{"type": UnitBase.UnitType.M2_IFV, "col": 16, "row": 6},
		{"type": UnitBase.UnitType.MECH_INFANTRY, "col": 14, "row": 5},
		{"type": UnitBase.UnitType.MECH_INFANTRY, "col": 15, "row": 6},
		{"type": UnitBase.UnitType.MECH_INFANTRY, "col": 14, "row": 8},
	]
	level.intel_a = "城市建筑群阻碍视线。"
	level.intel_b = "'洪水'第一阶段已启动，电磁强度达到60%。"
	level.turn_events = [
		{"turn": 1, "phase": "turn_start", "id": "flood_preview", "description": "EMI上升预告"},
		{"turn": 2, "phase": "turn_start", "id": "emi_surge", "description": "EMI跃升至60%"},
		{"turn": 4, "phase": "turn_start", "id": "nato_blind_fire", "description": "北约开始盲射火力覆盖"},
		{"turn": 7, "phase": "turn_start", "id": "reserve_ready", "description": "华约预备队可投入"},
		{"turn": 8, "phase": "turn_start", "id": "unknown_contacts", "description": "未知接触×2"},
	]
	return level


func _build_level_04() -> LevelData:
	var level = LevelData.new()
	level.level_id = 3
	level.level_name = "林地误击"
	level.act_number = 2
	level.max_turns = 10
	level.emi_base_level = 0.80
	level.default_vision = 2
	level.vp_cells = [Vector2i(9, 6), Vector2i(9, 7), Vector2i(9, 8)]
	level.wp_command_center = Vector2i(4, 6)
	level.nato_command_center = Vector2i(16, 6)
	level.wp_starting_cards = CardDatabase.get_level_cards(3)
	level.nato_ai_behavior = NATOAI.AIBehavior.FIRE_SUPPRESSION

	level.wp_units = [
		{"type": UnitBase.UnitType.COMMAND_ELEMENT, "col": 4, "row": 6, "morale": 60},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 5, "row": 5},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 5, "row": 7},
		{"type": UnitBase.UnitType.T72B_TANK, "col": 4, "row": 7},
		{"type": UnitBase.UnitType.RECON_PLATOON, "col": 5, "row": 6},
		{"type": UnitBase.UnitType.BMP2_IFV, "col": 5, "row": 8},
	]
	level.nato_units = [
		{"type": UnitBase.UnitType.M1A1_TANK, "col": 15, "row": 5},
		{"type": UnitBase.UnitType.M1A1_TANK, "col": 16, "row": 8},
		{"type": UnitBase.UnitType.M2_IFV, "col": 15, "row": 7},
		{"type": UnitBase.UnitType.M2_IFV, "col": 16, "row": 6},
		{"type": UnitBase.UnitType.MECH_INFANTRY, "col": 14, "row": 6},
		{"type": UnitBase.UnitType.MECH_INFANTRY, "col": 17, "row": 6},
	]
	level.intel_a = "林区有大量未知接触，来源不明。"
	level.intel_b = "敌方机械化纵队正向林间空地推进。"
	level.intel_c = "部分友军侦察连失联。"
	level.turn_events = [
		{"turn": 1, "phase": "turn_start", "id": "forest_unknown", "description": "林区发现至少2个未知接触"},
		{"turn": 2, "phase": "turn_start", "id": "unknown_d", "description": "未知接触点(11,D)"},
		{"turn": 3, "phase": "turn_start", "id": "unknown_j", "description": "未知接触点(10,J)"},
		{"turn": 4, "phase": "turn_start", "id": "unknown_e", "description": "未知接触点(9,E)"},
		{"turn": 6, "phase": "turn_start", "id": "ah64_arrives", "description": "AH-64进场"},
	]
	return level


func _build_level_05() -> LevelData:
	var level = LevelData.new()
	level.level_id = 4
	level.level_name = "预备队投入"
	level.act_number = 2
	level.max_turns = 10
	level.emi_base_level = 0.80
	level.vp_cells = [Vector2i(9, 5), Vector2i(9, 6), Vector2i(9, 7)]
	level.wp_command_center = Vector2i(3, 6)
	level.nato_command_center = Vector2i(16, 6)
	level.wp_starting_cards = CardDatabase.get_level_cards(4)
	level.nato_ai_behavior = NATOAI.AIBehavior.STEADY_PUSH

	level.wp_units = [
		{"type": UnitBase.UnitType.COMMAND_ELEMENT, "col": 3, "row": 6, "morale": 65},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 5},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 6},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 7},
		{"type": UnitBase.UnitType.T72B_TANK, "col": 3, "row": 7},
		{"type": UnitBase.UnitType.BMP2_IFV, "col": 3, "row": 5},
		{"type": UnitBase.UnitType.BM21_ROCKET, "col": 2, "row": 6},
	]
	level.wp_reserve_units = [
		{"type": UnitBase.UnitType.T72B_TANK, "turn": 4},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "turn": 4},
	]
	level.nato_units = [
		{"type": UnitBase.UnitType.M1A1_TANK, "col": 14, "row": 5},
		{"type": UnitBase.UnitType.M1A1_TANK, "col": 15, "row": 5},
		{"type": UnitBase.UnitType.M1A1_TANK, "col": 14, "row": 7},
		{"type": UnitBase.UnitType.M2_IFV, "col": 16, "row": 6},
		{"type": UnitBase.UnitType.M2_IFV, "col": 15, "row": 7},
		{"type": UnitBase.UnitType.MECH_INFANTRY, "col": 14, "row": 6},
		{"type": UnitBase.UnitType.MECH_INFANTRY, "col": 15, "row": 6},
		{"type": UnitBase.UnitType.MECH_INFANTRY, "col": 16, "row": 7},
	]
	# 修复批B: 第5关"预备队投入"主题 — 补 turn_events 消费 wp_reserve_units 死数据,
	# 第4回合预备队就绪: 授予"预备队投入"卡 + 在华约指挥中心旁生成 T72/步兵
	level.turn_events = [
		{"turn": 4, "phase": "turn_start", "id": "reserve_ready",
			"description": "华约预备队已就绪：T-72与步兵班待命，可投入战场",
			"spawn_reserves": true},
	]
	level.intel_a = "敌方机械化纵队至少8个单位。"
	level.intel_b = "预备队可能不足，需要谨慎使用。"
	return level


func _build_level_06() -> LevelData:
	var level = LevelData.new()
	level.level_id = 5
	level.level_name = "断桥反击"
	level.act_number = 2
	level.max_turns = 12
	level.emi_base_level = 0.70
	level.vp_cells = [Vector2i(9, 6), Vector2i(9, 8)]  # 桥梁、桥头堡
	level.wp_command_center = Vector2i(3, 6)
	level.nato_command_center = Vector2i(16, 6)
	level.wp_starting_cards = CardDatabase.get_level_cards(5)
	level.nato_ai_behavior = NATOAI.AIBehavior.SPEED_RUSH

	level.wp_units = [
		{"type": UnitBase.UnitType.COMMAND_ELEMENT, "col": 3, "row": 6, "morale": 45},  # 动摇
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 6},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 8},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 3, "row": 8},
		{"type": UnitBase.UnitType.T72B_TANK, "col": 4, "row": 7},
		{"type": UnitBase.UnitType.SAPPERS, "col": 5, "row": 6},
		{"type": UnitBase.UnitType.BMP2_IFV, "col": 3, "row": 7},
	]
	level.intel_a = "桥上有1辆载伤员的卡车。"
	level.intel_b = "敌军工兵已开始作业，可能准备架桥。"
	level.turn_events = [
		{"turn": 3, "phase": "turn_start", "id": "bridge_decision", "description": "玩家需决定炸桥还是先救人"},
		{"turn": 4, "phase": "turn_start", "id": "nato_pontoon", "description": "北约工兵开始架设浮桥"},
		{"turn": 8, "phase": "turn_start", "id": "ah64_arrives", "description": "AH-64进场"},
	]
	return level


func _build_level_07() -> LevelData:
	var level = LevelData.new()
	level.level_id = 6
	level.level_name = "全频段窒息"
	level.act_number = 2
	level.max_turns = 15
	level.emi_base_level = 1.0  # 100%
	level.default_vision = 1
	level.vp_cells = [Vector2i(9, 5), Vector2i(9, 7), Vector2i(9, 8)]
	level.wp_command_center = Vector2i(2, 6)
	level.nato_command_center = Vector2i(16, 6)
	level.wp_starting_cards = CardDatabase.get_level_cards(6)
	level.nato_ai_behavior = NATOAI.AIBehavior.CHAOS

	level.wp_units = [
		{"type": UnitBase.UnitType.COMMAND_ELEMENT, "col": 2, "row": 6, "morale": 50},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 5},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 6},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 7},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 8},
		{"type": UnitBase.UnitType.T72B_TANK, "col": 3, "row": 8},
		{"type": UnitBase.UnitType.BMP2_IFV, "col": 3, "row": 5},
		{"type": UnitBase.UnitType.BMP2_IFV, "col": 3, "row": 7},
		{"type": UnitBase.UnitType.SAPPERS, "col": 3, "row": 6},
	]
	level.intel_a = "所有电子设备失效，只能依靠目视与地图。"
	level.intel_b = "敌方至少仍有10个战斗单位。"
	level.intel_c = "友军步兵班位置需要玩家自行记忆。"
	return level


func _build_level_08() -> LevelData:
	var level = LevelData.new()
	level.level_id = 7
	level.level_name = "白色走廊"
	level.act_number = 3
	level.max_turns = 12
	level.emi_base_level = 0.40
	level.weather = "snow"
	level.weather_vision_penalty = 1
	level.vp_cells = [Vector2i(9, 6), Vector2i(9, 7), Vector2i(9, 8)]
	level.wp_command_center = Vector2i(3, 6)
	level.nato_command_center = Vector2i(16, 6)
	level.wp_starting_cards = CardDatabase.get_level_cards(7)
	level.nato_ai_behavior = NATOAI.AIBehavior.STEADY_PUSH

	level.wp_units = [
		{"type": UnitBase.UnitType.COMMAND_ELEMENT, "col": 3, "row": 6, "morale": 60},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 5},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 7},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 8},
		{"type": UnitBase.UnitType.T72B_TANK, "col": 3, "row": 5},
		{"type": UnitBase.UnitType.T72B_TANK, "col": 3, "row": 8},
		{"type": UnitBase.UnitType.BMP2_IFV, "col": 3, "row": 7},
		{"type": UnitBase.UnitType.BM21_ROCKET, "col": 2, "row": 6},
	]
	level.intel_a = "大雪覆盖战场，视野受限。"
	level.intel_b = "敌方侦察部分恢复，可能提前发现己方位置。"
	level.intel_c = "雪地车辆辙印会暴露阵地位置。"
	return level


func _build_level_09() -> LevelData:
	var level = LevelData.new()
	level.level_id = 8
	level.level_name = "红色轨道"
	level.act_number = 3
	level.max_turns = 12
	level.emi_base_level = 0.30
	level.vp_cells = [Vector2i(9, 5), Vector2i(9, 6), Vector2i(9, 8)]
	level.wp_command_center = Vector2i(4, 6)
	level.nato_command_center = Vector2i(16, 6)
	level.wp_starting_cards = CardDatabase.get_level_cards(8)
	level.nato_ai_behavior = NATOAI.AIBehavior.CONCENTRATED

	level.wp_units = [
		{"type": UnitBase.UnitType.COMMAND_ELEMENT, "col": 4, "row": 6, "morale": 65},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 5, "row": 5},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 5, "row": 6},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 5, "row": 7},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 5, "row": 8},
		{"type": UnitBase.UnitType.T72B_TANK, "col": 4, "row": 7},
		{"type": UnitBase.UnitType.T72B_TANK, "col": 4, "row": 5},
		{"type": UnitBase.UnitType.BMP2_IFV, "col": 3, "row": 5},
		{"type": UnitBase.UnitType.BMP2_IFV, "col": 3, "row": 8},
		{"type": UnitBase.UnitType.BM21_ROCKET, "col": 2, "row": 7},
	]
	level.intel_a = "敌军可能利用铁路进行快速机动。"
	level.intel_b = "敌军至少10个战斗单位。"
	level.intel_c = "指挥中心位置是敌军首要目标。"
	return level


func _build_level_10() -> LevelData:
	var level = LevelData.new()
	level.level_id = 9
	level.level_name = "坐标归零"
	level.act_number = 3
	level.max_turns = 10
	level.emi_base_level = 1.0  # 从100%开始
	level.vp_cells = [Vector2i(9, 6), Vector2i(9, 5), Vector2i(9, 8)]
	level.wp_command_center = Vector2i(3, 6)
	level.nato_command_center = Vector2i(16, 6)
	level.wp_starting_cards = CardDatabase.get_level_cards(9)
	level.nato_ai_behavior = NATOAI.AIBehavior.SPEED_RUSH

	level.wp_units = [
		{"type": UnitBase.UnitType.COMMAND_ELEMENT, "col": 3, "row": 6, "morale": 65},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 4},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 5, "row": 5},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 5, "row": 6},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 5, "row": 7},
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 4, "row": 8},
		{"type": UnitBase.UnitType.T72B_TANK, "col": 3, "row": 5},
		{"type": UnitBase.UnitType.T72B_TANK, "col": 3, "row": 7},
		{"type": UnitBase.UnitType.T72B_TANK, "col": 3, "row": 8},
		{"type": UnitBase.UnitType.BMP2_IFV, "col": 2, "row": 6},
		{"type": UnitBase.UnitType.BMP2_IFV, "col": 4, "row": 6},
		{"type": UnitBase.UnitType.BM21_ROCKET, "col": 1, "row": 6},
		{"type": UnitBase.UnitType.SAPPERS, "col": 2, "row": 5},
	]
	level.intel_a = "'洪水'第四阶段已启动，EMI 100%。"
	level.intel_b = "敌军发起最后的进攻。"
	level.intel_c = "所有积累的资源可用于本关。"
	return level


## === 第1关地形构建 ===
func _build_level_01_terrain() -> Dictionary:
	# 地图：40×45 (col:0-39, row:0-44)
	# 设计文档 3.3：横向公路、北部山地、南部河谷；扩展后保留中部VP走廊。
	var terrain_list: Array[Dictionary] = []
	# 默认所有格为平原且可见
	for col in range(40):
		for row in range(45):
			var terrain_type := GridManager.TerrainType.PLAINS
			var terrain_name := "grass"
			var height := 0
			var move_cost := 1.0
			var passable := true
			var concealment := 0.1
			var south_center := 33 + roundi(sin(float(col) * 0.45) * 1.4)
			var branch_center := 27 - roundi(float(col - 22) * 0.45)
			var is_river: bool = (
				(col >= 4 and col <= 35 and abs(row - south_center) <= 2) or
				(col >= 20 and col <= 31 and abs(row - branch_center) <= 1)
			)
			var is_road: bool = (
				(row == 20 and col >= 4 and col <= 36) or
				(col == 20 and row >= 16 and row <= 30) or
				(col >= 6 and col <= 15 and row == 7)
			)
			var is_mountain: bool = (
				(col >= 5 and col <= 29 and row >= 0 and row <= 8) or
				(col >= 28 and col <= 37 and row >= 10 and row <= 17 and (col + row) % 3 != 0)
			)
			var is_forest: bool = (
				_is_level_01_ellipse_cell(col, row, 9, 15, 6, 4) or
				_is_level_01_ellipse_cell(col, row, 26, 25, 6, 5) or
				_is_level_01_ellipse_cell(col, row, 12, 39, 8, 4)
			)
			var is_brush: bool = (
				(_is_level_01_ellipse_cell(col, row, 16, 24, 7, 3) and (col + row) % 2 == 0) or
				_is_level_01_ellipse_cell(col, row, 32, 39, 5, 3)
			)
			if is_river:
				terrain_type = GridManager.TerrainType.RIVER
				terrain_name = "water"
				height = -1
				move_cost = 4.0
				passable = false
				concealment = 0.0
			elif is_road:
				terrain_type = GridManager.TerrainType.ROAD
				terrain_name = "road"
				move_cost = 0.5
				concealment = 0.0
			elif is_mountain:
				terrain_type = GridManager.TerrainType.MOUNTAIN
				terrain_name = "rock"
				height = 2
				move_cost = 3.0
				concealment = 0.15
			elif is_forest:
				terrain_type = GridManager.TerrainType.FOREST
				terrain_name = "forest"
				move_cost = 2.0
				concealment = 0.45
			elif is_brush:
				terrain_type = GridManager.TerrainType.FOREST
				terrain_name = "brush"
				move_cost = 1.5
				concealment = 0.25
			elif (col + row * 2) % 11 == 0:
				terrain_name = "soil"
				concealment = 0.0

			var cell = {
				"col": col,
				"row": row,
				"terrain": terrain_type,
				"terrain_name": terrain_name,
				"height": height,
				"move_cost": move_cost,
				"passable": passable,
				"concealment": concealment,
			}
			# VP格标记
			if (col == 20 and row == 20) or (col == 20 and row == 21) or (col == 20 and row == 22):
				cell["marker"] = GridManager.CellMarker.VP_POINT
			# 华约出生点标记
			if Vector2i(col, row) in [Vector2i(3,6), Vector2i(4,6), Vector2i(5,6), Vector2i(4,7), Vector2i(5,7)]:
				cell["marker"] = GridManager.CellMarker.WP_SPAWN
			# 北约出生点标记
			if Vector2i(col, row) in [Vector2i(35,20), Vector2i(35,21), Vector2i(36,20), Vector2i(36,22)]:
				cell["marker"] = GridManager.CellMarker.NATO_SPAWN
			terrain_list.append(cell)
	return {"terrain": terrain_list, "vp_cells": [], "wp_spawn": [], "nato_spawn": []}


func _is_level_01_ellipse_cell(col: int, row: int, cx: int, cy: int, rx: int, ry: int) -> bool:
	var nx := float(col - cx) / float(rx)
	var ny := float(row - cy) / float(ry)
	return nx * nx + ny * ny <= 1.0

## === 查询方法 ===
func get_level(level_id: int) -> LevelData:
	if level_id >= 0 and level_id < levels.size():
		return levels[level_id]
	return null


func get_level_count() -> int:
	return levels.size()
