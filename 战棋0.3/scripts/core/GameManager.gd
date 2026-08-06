# ==============================================================================
# GameManager.gd — 游戏主状态机 (Autoload 单例)
# ==============================================================================
# 作用：管理游戏整体生命周期，协调各子系统，处理状态切换。
# Godot 4.7.1 兼容
# ==============================================================================
extends Node

## === 游戏状态枚举 ===
enum GameState {
	BOOT,           # 启动/加载
	MAIN_MENU,      # 主菜单
	CAMPAIGN_MAP,   # 战役地图（关卡选择）
	LEVEL_INTRO,    # 关卡开场叙事
	PLANNING_PHASE, # 60秒计划阶段（玩家输入）
	EXECUTION_PHASE,# 30秒沙盘演绎（结算动画）
	LEVEL_OUTRO,    # 关卡结算
	VICTORY,        # 战役胜利
	DEFEAT,         # 战役失败
	PAUSED          # 暂停
}

## === 信号定义 ===
signal state_changed(old_state: GameState, new_state: GameState)
signal level_started(level_id: int)
signal level_completed(level_id: int, result: Dictionary)
signal campaign_ended(final_result: Dictionary)

## === 当前状态 ===
var current_state: GameState = GameState.BOOT
var previous_state: GameState = GameState.BOOT
var current_level_id: int = 0

## === 计时器 ===
var planning_timer: float = 0.0      # 计划阶段倒计时
var execution_timer: float = 0.0     # 沙盘演绎倒计时
const PLANNING_DURATION: float = 60.0
const EXECUTION_DURATION: float = 30.0
var runtime_map_data: Dictionary = {}
var runtime_map_size: Vector2i = Vector2i(40, 45)
var execution_skip_requested: bool = false

## === Bug追踪与版本控制 ===
var bug_tracker: Dictionary = {}     # bug_id -> {description, status, fix_version}
var version: String = "1.0.0"
var build_number: int = 1


func _ready() -> void:
	# 初始化所有子系统
	_initialize_subsystems()
	# 设置进程优先级
	process_priority = 100
	print("[GameManager] Silent Reckoning·1987 v%s (build %d) 已启动" % [version, build_number])


func _process(delta: float) -> void:
	# 计划阶段倒计时
	if current_state == GameState.PLANNING_PHASE:
		planning_timer -= delta
		if planning_timer <= 0.0:
			_on_planning_timeout()
	# 沙盘演绎倒计时
	elif current_state == GameState.EXECUTION_PHASE:
		execution_timer -= delta
		if execution_timer <= 0.0 or (
				execution_skip_requested and TurnManager.execution_actions_finished
		):
			_finish_execution()


## === 状态切换 ===
func change_state(new_state: GameState) -> void:
	if new_state == current_state:
		return
	previous_state = current_state
	var old = current_state
	current_state = new_state
	print("[GameManager] 状态切换: %s → %s" % [GameState.keys()[old], GameState.keys()[new_state]])
	state_changed.emit(old, new_state)
	_on_state_entered(new_state)


func _on_state_entered(state: GameState) -> void:
	match state:
		GameState.PLANNING_PHASE:
			execution_skip_requested = false
			planning_timer = PLANNING_DURATION
			TurnManager.start_planning_phase()
		GameState.EXECUTION_PHASE:
			execution_skip_requested = false
			execution_timer = EXECUTION_DURATION
			TurnManager.start_execution_phase()
		GameState.LEVEL_INTRO:
			_start_level_intro()


func _on_planning_timeout() -> void:
	print("[GameManager] 计划阶段结束，进入沙盘演绎")
	_finish_planning()


func finish_planning_early() -> void:
	"""玩家主动结束计划阶段。"""
	if current_state != GameState.PLANNING_PHASE:
		return
	print("[GameManager] 玩家提前结束计划阶段")
	_finish_planning()


func _finish_planning() -> void:
	"""锁定双方命令并统一进入沙盘演绎，防止按钮和倒计时产生两套流程。"""
	if current_state != GameState.PLANNING_PHASE:
		return
	TurnManager.lock_all_orders()
	change_state(GameState.EXECUTION_PHASE)


func _on_execution_timeout() -> void:
	_finish_execution()


func finish_execution_early() -> void:
	"""玩家请求跳过演绎；动作未完成时等待安全结算点。"""
	if current_state != GameState.EXECUTION_PHASE:
		return
	execution_skip_requested = true
	execution_timer = 0.0
	print("[GameManager] 玩家请求跳过沙盘演绎")
	if TurnManager.execution_actions_finished:
		_finish_execution()


func _finish_execution() -> void:
	if current_state != GameState.EXECUTION_PHASE:
		return
	# 不在单位移动或攻击动作中途强制结算。
	if not TurnManager.execution_actions_finished:
		execution_skip_requested = true
		return
	print("[GameManager] 沙盘演绎结束，回合结算")
	TurnManager.resolve_turn()

	# 1. 先检查即时胜负（指挥中心被毁/全歼）
	var instant = VictoryManager.check_victory_now()
	if instant.game_over:
		var is_win = instant.winner == UnitBase.Faction.WARSAW_PACT
		var result = {
			"completed": true,
			"victory": is_win,
			"winner_faction": instant.winner,
			"reason": instant.reason,
			"turn": TurnManager.current_turn,
			"morale_delta": 0,
			"victory_tier": "victory" if is_win else "defeat"
		}
		BattleLog.add_log("━━━ %s ━━━" % instant.reason, Color.GOLD)
		VictoryManager._trigger_game_over(instant.winner, instant.reason)
		level_completed.emit(current_level_id, result)
		_apply_level_result_and_end(result)
		return

	# 2. 检查回合末VP判定（到达max_turns时触发）
	var level_result = CampaignManager.check_level_completion(current_level_id)
	if level_result.completed:
		var winner = UnitBase.Faction.WARSAW_PACT if level_result.get("victory", false) else UnitBase.Faction.NATO
		level_result["winner_faction"] = winner
		level_result["turn"] = TurnManager.current_turn
		BattleLog.add_log("━━━ %s ━━━" % level_result.get("reason", ""), Color.GOLD)
		VictoryManager._trigger_game_over(winner, level_result.get("reason", ""))
		level_completed.emit(current_level_id, level_result)
		_apply_level_result_and_end(level_result)
	else:
		# 进入下一回合计划阶段
		TurnManager.advance_turn()
		change_state(GameState.PLANNING_PHASE)


func _apply_level_result_and_end(result: Dictionary) -> void:
	"""应用关卡结算结果并切换状态"""
	CampaignManager.apply_level_result(result)
	if current_level_id >= 9:
		var final = CampaignManager.get_final_result()
		campaign_ended.emit(final)
		if final.is_victory:
			change_state(GameState.VICTORY)
		else:
			change_state(GameState.DEFEAT)
	else:
		if result.get("victory", false):
			change_state(GameState.VICTORY)
		else:
			change_state(GameState.DEFEAT)


func start_level(level_id: int) -> void:
	current_level_id = level_id
	change_state(GameState.LEVEL_INTRO)
	level_started.emit(level_id)


func set_runtime_map(map_data: Dictionary, map_size: Vector2i) -> void:
	"""接收由关卡TileMapLayer提取的地图，替代LevelDatabase中的脚本地形。"""
	runtime_map_data = map_data
	runtime_map_size = map_size


func _start_level_intro() -> void:
	# 加载关卡数据并初始化
	var level_data = LevelDatabase.get_level(current_level_id)
	if runtime_map_data.is_empty():
		GridManager.initialize_map(level_data.map_data, level_data.map_width, level_data.map_height)
	else:
		GridManager.initialize_map(runtime_map_data, runtime_map_size.x, runtime_map_size.y)
	# 确保VP格从关卡数据复制到GridManager（地形marker可能未覆盖所有关卡）
	for vp in level_data.vp_cells:
		if not GridManager.vp_cells.has(vp):
			GridManager.vp_cells.append(vp)
	for wp in level_data.wp_spawn:
		if not GridManager.spawn_wp.has(wp):
			GridManager.spawn_wp.append(wp)
	for ns in level_data.nato_spawn:
		if not GridManager.spawn_nato.has(ns):
			GridManager.spawn_nato.append(ns)
	CampaignManager.initialize_level(level_data)
	EMISystem.set_level(current_level_id)
	# 初始化胜利判定（VP格、指挥中心、回合限制）
	VictoryManager.setup_level(level_data)
	# 短暂展示后进入计划阶段
	await get_tree().create_timer(3.0).timeout
	change_state(GameState.PLANNING_PHASE)


func _on_level_end(result: Dictionary) -> void:
	# 更新战役状态
	CampaignManager.apply_level_result(result)
	# 检查是否最后一关
	if current_level_id >= 9:  # 第10关（索引9）
		var final = CampaignManager.get_final_result()
		campaign_ended.emit(final)
		if final.is_victory:
			change_state(GameState.VICTORY)
		else:
			change_state(GameState.DEFEAT)
	else:
		change_state(GameState.CAMPAIGN_MAP)


func _initialize_subsystems() -> void:
	# 确保所有 autoload 已就绪（Godot按名称顺序加载）
	VictoryManager.game_over.connect(_on_game_over)
	print("[GameManager] 子系统初始化完成")


func _on_game_over(winner_faction: int, reason: String) -> void:
	"""任意一方被全歼时触发"""
	if current_state in [GameState.VICTORY, GameState.DEFEAT]:
		return

	var is_player_victory = (winner_faction == UnitBase.Faction.WARSAW_PACT)
	var result = {
		"completed": true,
		"victory": is_player_victory,
		"winner_faction": winner_faction,
		"reason": reason,
		"turn": TurnManager.current_turn
	}

	level_completed.emit(current_level_id, result)
	print("[GameManager] 关卡结束 — %s" % reason)

	if is_player_victory:
		change_state(GameState.VICTORY)
	else:
		change_state(GameState.DEFEAT)


## === Bug追踪工具 ===
func log_bug(bug_id: String, description: String) -> void:
	bug_tracker[bug_id] = {
		"description": description,
		"status": "open",
		"found_version": version,
		"timestamp": Time.get_datetime_string_from_system()
	}
	print("[BUG-TRACKER] 新Bug记录: %s — %s" % [bug_id, description])


func fix_bug(bug_id: String) -> void:
	if bug_tracker.has(bug_id):
		bug_tracker[bug_id]["status"] = "fixed"
		bug_tracker[bug_id]["fix_version"] = version
		print("[BUG-TRACKER] Bug已修复: %s" % bug_id)


## === 版本控制接口 ===
func get_version_string() -> String:
	return "v%s (build %d)" % [version, build_number]


func save_game(slot: int) -> void:
	var save_data = {
		"version": version,
		"build": build_number,
		"level": current_level_id,
		"turn": TurnManager.current_turn,
		"campaign": CampaignManager.serialize(),
		"emi": EMISystem.serialize(),
		"morale": MoraleSystem.serialize(),
		"cards": CardSystem.serialize(),
		"timestamp": Time.get_datetime_string_from_system()
	}
	var file = FileAccess.open("user://save_%d.json" % slot, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		print("[GameManager] 存档已保存到槽位 %d" % slot)


func load_game(slot: int) -> bool:
	var file = FileAccess.open("user://save_%d.json" % slot, FileAccess.READ)
	if not file:
		print("[GameManager] 存档槽位 %d 为空" % slot)
		return false
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data:
		CampaignManager.deserialize(data.get("campaign", {}))
		EMISystem.deserialize(data.get("emi", {}))
		MoraleSystem.deserialize(data.get("morale", {}))
		CardSystem.deserialize(data.get("cards", {}))
		# 恢复关卡
		start_level(data.get("level", 0))
		print("[GameManager] 存档已从槽位 %d 加载" % slot)
		return true
	return false
