# ==============================================================================
# AIBehaviorType.gd — AI行为枚举与配置
# ==============================================================================
class_name AIBehaviorType
extends RefCounted

class BehaviorConfig extends RefCounted:
	var name: String = ""
	var aggressiveness: float = 0.5
	var risk_tolerance: float = 0.5
	var vp_priority: float = 0.5
	var use_blind_fire: bool = false
	var maintain_formation: bool = false
	var focus_fire: bool = false
	var retreat_threshold: float = 0.25


static func get_behavior_config(behavior: int) -> BehaviorConfig:
	var cfg = BehaviorConfig.new()
	match behavior:
		0:
			cfg.name = "速胜"
			cfg.aggressiveness = 0.9
			cfg.risk_tolerance = 0.8
			cfg.vp_priority = 0.9
			cfg.retreat_threshold = 0.15
		1:
			cfg.name = "稳推"
			cfg.aggressiveness = 0.5
			cfg.risk_tolerance = 0.3
			cfg.vp_priority = 0.6
			cfg.maintain_formation = true
			cfg.retreat_threshold = 0.30
		2:
			cfg.name = "火力压制"
			cfg.aggressiveness = 0.7
			cfg.risk_tolerance = 0.6
			cfg.use_blind_fire = true
			cfg.vp_priority = 0.4
			cfg.retreat_threshold = 0.20
		3:
			cfg.name = "集中突击"
			cfg.aggressiveness = 0.95
			cfg.risk_tolerance = 0.9
			cfg.focus_fire = true
			cfg.vp_priority = 0.3
			cfg.retreat_threshold = 0.10
		_:
			cfg.name = "混乱"
			cfg.aggressiveness = 0.3
			cfg.risk_tolerance = 0.2
			cfg.vp_priority = 0.2
			cfg.retreat_threshold = 0.50
	return cfg


static func evaluate_action_score(unit: UnitBase, action: Dictionary,
		known_enemies: Array[Vector2i]) -> float:
	var score = 0.0
	var config = get_behavior_config(NATOAI.current_behavior)
	match action.get("type"):
		"attack":
			var td = action.get("dist", 999)
			var tv = action.get("target_value", 0)
			score = tv * 3.0 - td * 0.5
			if config.focus_fire:
				score *= 1.5
		"move_to_vp":
			score = config.vp_priority * 5.0
		"move_to_enemy":
			score = config.aggressiveness * 3.0
		"hold":
			score = 1.0 - config.aggressiveness
		"retreat":
			var hr = unit.current_health / unit.max_health
			if hr < config.retreat_threshold:
				score = (1.0 - hr) * 5.0
	return score


static func get_difficulty_modifier(difficulty: String = "normal") -> Dictionary:
	match difficulty:
		"easy":
			return {"accuracy_penalty": -0.15, "planning_delay": 1.0, "avoid_flanking": true}
		"hard":
			return {"accuracy_bonus": 0.10, "planning_delay": 0.0, "flanking_aware": true}
		_:
			return {"accuracy_penalty": 0.0, "planning_delay": 0.0, "flanking_aware": false}
