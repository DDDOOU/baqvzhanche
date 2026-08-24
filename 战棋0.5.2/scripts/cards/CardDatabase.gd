# ==============================================================================
# CardDatabase.gd — 12张共享手牌数据库
# ==============================================================================
# 作用：定义所有可用手牌的属性（名称、消耗、冷却、效果描述）。
#       对应设计文档 1.4 节「华约共享手牌」。
# Godot 4.7.1 兼容
# ==============================================================================
extends Node

## === 全部12张共享手牌 ===
const ALL_CARDS: Array[Dictionary] = [
	{
		"id": "coordinate_prediction",
		"name": "坐标预判",
		"cost": 1,
		"cooldown": 0,
		"description": "指定1个格，本回合命中该格的己方单位命中+30%。",
		"type": "buff",
		"rarity": "common"
	},
	{
		"id": "blind_fire_barrage",
		"name": "盲射弹幕",
		"cost": 2,
		"cooldown": 0,
		"description": "对3×3范围进行无差别射击，无视视野但可能误伤平民。",
		"type": "attack",
		"rarity": "common"
	},
	{
		"id": "smoke_screen",
		"name": "烟雾遮障",
		"cost": 1,
		"cooldown": 0,
		"description": "4×4范围释放烟雾，本回合及下回合敌方该范围命中-40%。",
		"type": "defense",
		"rarity": "common"
	},
	{
		"id": "call_artillery",
		"name": "呼叫炮击",
		"cost": 3,
		"cooldown": 3,
		"description": "对2×2范围进行远程炮击，3回合冷却。",
		"type": "attack",
		"rarity": "uncommon"
	},
	{
		"id": "fortify_position",
		"name": "阵地加固",
		"cost": 1,
		"cooldown": 0,
		"description": "指定1个格，本回合该格防御+50%，不能移动。",
		"type": "defense",
		"rarity": "common"
	},
	{
		"id": "emi_countermeasure",
		"name": "电磁反制",
		"cost": 2,
		"cooldown": 0,
		"description": "本回合EMI下降10%，持续2回合，保护己方电子设备。",
		"type": "special",
		"rarity": "uncommon"
	},
	{
		"id": "radio_silence",
		"name": "无线电静默",
		"cost": 1,
		"cooldown": 0,
		"description": "本回合己方单位隐蔽度+50%，但无法使用任何指令。",
		"type": "defense",
		"rarity": "common"
	},
	{
		"id": "reserve_deployment",
		"name": "预备队投入",
		"cost": 4,
		"cooldown": 3,
		"description": "立即获得1支预备队单位进场，3回合只能用1次。",
		"type": "special",
		"rarity": "rare"
	},
	{
		"id": "sapper_mines",
		"name": "工兵布雷",
		"cost": 2,
		"cooldown": 0,
		"description": "指定1×2范围，敌方单位进入即损30%。",
		"type": "defense",
		"rarity": "uncommon"
	},
	{
		"id": "sacrifice_charge",
		"name": "牺牲冲锋",
		"cost": 2,
		"cooldown": 0,
		"description": "指定1个己方单位，立即造成1.5倍伤害，自身战后-50%生命。",
		"type": "attack",
		"rarity": "uncommon"
	},
	{
		"id": "power_cut",
		"name": "断电",
		"cost": 1,
		"cooldown": 2,
		"description": "使1个敌方单位下回合电磁设备失效，2回合冷却。",
		"type": "special",
		"rarity": "uncommon"
	},
	{
		"id": "false_report",
		"name": "战报谎言",
		"cost": 1,
		"cooldown": 0,
		"description": "本回合敌方对该格的情报+1个虚假单位。",
		"type": "special",
		"rarity": "common"
	},
]

## === 每关起始手牌配置 ===
const LEVEL_STARTING_HANDS: Dictionary = {
	0: ["coordinate_prediction", "blind_fire_barrage", "smoke_screen",
		"fortify_position", "radio_silence", "call_artillery", "emi_countermeasure"],
	1: ["coordinate_prediction", "blind_fire_barrage", "fortify_position",
		"fortify_position", "sapper_mines", "call_artillery", "radio_silence",
		"emi_countermeasure"],
	2: ["coordinate_prediction", "blind_fire_barrage", "fortify_position",
		"smoke_screen", "emi_countermeasure", "power_cut"],
	3: ["coordinate_prediction", "blind_fire_barrage", "blind_fire_barrage",
		"fortify_position", "radio_silence", "false_report"],
	4: ["coordinate_prediction", "coordinate_prediction", "blind_fire_barrage",
		"fortify_position", "reserve_deployment", "emi_countermeasure",
		"sapper_mines", "sacrifice_charge"],
	5: ["coordinate_prediction", "blind_fire_barrage", "fortify_position",
		"sapper_mines", "radio_silence", "radio_silence", "emi_countermeasure",
		"sacrifice_charge"],
	6: ["coordinate_prediction", "blind_fire_barrage", "blind_fire_barrage",
		"fortify_position", "radio_silence", "emi_countermeasure", "power_cut"],
	7: ["coordinate_prediction", "coordinate_prediction", "blind_fire_barrage",
		"fortify_position", "smoke_screen", "radio_silence", "sapper_mines",
		"sacrifice_charge"],
	8: ["coordinate_prediction", "coordinate_prediction", "blind_fire_barrage",
		"fortify_position", "smoke_screen", "reserve_deployment",
		"sapper_mines", "emi_countermeasure", "sacrifice_charge"],
	9: ["coordinate_prediction", "coordinate_prediction", "blind_fire_barrage",
		"fortify_position", "reserve_deployment", "emi_countermeasure",
		"radio_silence", "sacrifice_charge", "call_artillery"],
}

## === 查询方法 ===
func get_card_data(card_id: String) -> Dictionary:
	for card in ALL_CARDS:
		if card["id"] == card_id:
			return card.duplicate()
	return {}


func get_level_cards(level_id: int) -> Array:
	if LEVEL_STARTING_HANDS.has(level_id):
		return LEVEL_STARTING_HANDS[level_id]
	return []


func get_card_count() -> int:
	return ALL_CARDS.size()
