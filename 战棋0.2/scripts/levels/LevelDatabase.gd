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


## === 第1关·边境晨雾 ===
func _build_level_01() -> LevelData:
	var level = LevelData.new()
	level.level_id = 0
	level.level_name = "边境晨雾"
	level.act_number = 1
	level.designer_intent = "教学关：让玩家熟悉60秒计划+30秒沙盘循环、坐标输入、基础侦察、士气概念。"
	level.briefing = "1987年9月14日04:30，雾。西部军区第29摩步师前沿哨所报告：'边境出现机械化纵队，未识别。'"
	level.outro_narration = "你守住了第一节车厢。但你已经听到铁轨在响。"

	level.max_turns = 8
	level.default_vision = 3  # 晨雾
	level.weather = "fog"
	level.weather_vision_penalty = 3
	level.emi_base_level = 0.0

	# VP格
	level.vp_cells = [Vector2i(9, 6), Vector2i(9, 7), Vector2i(9, 8)]  # (10,G)(10,H)(10,I)
	level.wp_spawn = [Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(4, 7), Vector2i(5, 7)]
	level.nato_spawn = [Vector2i(15, 6), Vector2i(15, 7), Vector2i(16, 6), Vector2i(16, 8)]
	level.wp_command_center = Vector2i(4, 6)  # (5,G)
	level.nato_command_center = Vector2i(15, 6)  # (16,G)

	# 华约起始手牌
	level.wp_starting_cards = CardDatabase.get_level_cards(0)

	# 华约初始单位
	level.wp_units = [
		{"type": UnitBase.UnitType.COMMAND_ELEMENT, "col": 4, "row": 6, "morale": 80},  # 列夫森科
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 5, "row": 5},   # 步兵A
		{"type": UnitBase.UnitType.INFANTRY_SQUAD, "col": 5, "row": 7},   # 步兵B
		{"type": UnitBase.UnitType.T72B_TANK, "col": 4, "row": 7},
		{"type": UnitBase.UnitType.BMP2_IFV, "col": 5, "row": 6},
		{"type": UnitBase.UnitType.RECON_PLATOON, "col": 3, "row": 6},
	]

	# 北约初始单位
	level.nato_units = [
		{"type": UnitBase.UnitType.M1A1_TANK, "col": 15, "row": 6},
		{"type": UnitBase.UnitType.M2_IFV, "col": 14, "row": 7},
		{"type": UnitBase.UnitType.MECH_INFANTRY, "col": 15, "row": 5},
		{"type": UnitBase.UnitType.MECH_INFANTRY, "col": 15, "row": 8},
	]

	level.nato_ai_behavior = NATOAI.AIBehavior.SPEED_RUSH

	# 地形数据（设计文档 3.3：横向公路、北部山地、南部河谷）
	level.map_data = _build_level_01_terrain()

	# 回合事件
	level.turn_events = [
		{"turn": 1, "phase": "turn_start", "id": "fog_warning", "description": "晨雾生效，视野3格"},
		{"turn": 3, "phase": "turn_start", "id": "ah64_arrives", "description": "北约AH-64进场"},
		{"turn": 4, "phase": "turn_start", "id": "fog_lifts", "description": "晨雾消散，视野恢复6格"},
		{"turn": 5, "phase": "turn_start", "id": "emi_rise", "description": "EMI强度+5%"},
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


## === 第2-10关（简化结构，实际使用时填充完整数据） ===
func _build_level_02() -> LevelData:
	var level = LevelData.new()
	level.level_id = 1
	level.level_name = "铁路线防御"
	level.act_number = 1
	level.max_turns = 10
	level.emi_base_level = 0.0
	level.vp_cells = [Vector2i(9, 6), Vector2i(9, 4), Vector2i(9, 8)]  # 桥、火车站、桥头堡
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
		{"turn": 5, "phase": "turn_start", "id": "emi_rise_15", "description": "EMI上升至15%"},
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
		{"type": UnitBase.UnitType.M2_IFV, "col": 16, "row": 5},
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
		{"turn": 2, "phase": "turn_start", "id": "unknown_d", "description": "未知接触?(11,D)"},
		{"turn": 3, "phase": "turn_start", "id": "unknown_j", "description": "未知接触?(10,J)"},
		{"turn": 4, "phase": "turn_start", "id": "unknown_e", "description": "未知接触?(9,E)"},
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
		{"type": UnitBase.UnitType.SAPPERS, "col": 4, "row": 5},
	]
	level.intel_a = "'洪水'第四阶段已启动，EMI 100%。"
	level.intel_b = "敌军发起最后的进攻。"
	level.intel_c = "所有积累的资源可用于本关。"
	return level


## === 第1关地形构建 ===
func _build_level_01_terrain() -> Dictionary:
	# 地图：20×15 (col:0-19, row:0-14)
	# 设计文档 3.3：横向公路 (8-12,G)、北部山地 (5-12,A-D)、南部河谷 (5-15,J-L)
	var terrain_list: Array[Dictionary] = []
	# 默认所有格为平原且可见
	for col in range(20):
		for row in range(15):
			var cell = {"col": col, "row": row, "terrain": GridManager.TerrainType.PLAINS}
			# 北部山地 ▲ (col:5-12, row:0-3 = A-D)
			if col >= 5 and col <= 12 and row <= 3:
				cell["terrain"] = GridManager.TerrainType.MOUNTAIN
				cell["height"] = 2
			# 南部河流 ~~ (col:5-15, row:9-11 = J-L)
			if col >= 5 and col <= 15 and row >= 9 and row <= 11:
				cell["terrain"] = GridManager.TerrainType.RIVER
				cell["height"] = -1
			# 横向公路 ═══ (col:8-12, row:6 = G)
			if col >= 8 and col <= 12 and row == 6:
				cell["terrain"] = GridManager.TerrainType.ROAD
			# VP格标记
			if (col == 9 and row == 6) or (col == 9 and row == 7) or (col == 9 and row == 8):
				cell["marker"] = GridManager.CellMarker.VP_POINT
			# 华约出生点标记
			if Vector2i(col, row) in [Vector2i(3,6), Vector2i(4,6), Vector2i(5,6), Vector2i(4,7), Vector2i(5,7)]:
				cell["marker"] = GridManager.CellMarker.WP_SPAWN
			terrain_list.append(cell)
	return {"terrain": terrain_list, "vp_cells": [], "wp_spawn": [], "nato_spawn": []}

## === 查询方法 ===
func get_level(level_id: int) -> LevelData:
	if level_id >= 0 and level_id < levels.size():
		return levels[level_id]
	return null


func get_level_count() -> int:
	return levels.size()
