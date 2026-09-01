extends Node
## 音效管理（0.5.5）
## 加载项目音效与 Kenney CC0 UI 音效，8 个 AudioStreamPlayer 循环复用播放。
## 用法：SoundManager.play("explosion") / SoundManager.play("tank_fire", -6.0)

const SFX := {
	"ui_click": "res://assets/audio/ui_click.wav",
	"unit_select": "res://assets/audio/kenney_ui/unit_select.ogg",
	"initiative_focus": "res://assets/audio/kenney_ui/initiative_focus.ogg",
	"initiative_active": "res://assets/audio/kenney_ui/initiative_active.ogg",
	"initiative_complete": "res://assets/audio/kenney_ui/initiative_complete.ogg",
	"move_order": "res://assets/audio/move_order.wav",
	"gunshot": "res://assets/audio/gunshot.wav",
	"tank_fire": "res://assets/audio/tank_fire.wav",
	"hit": "res://assets/audio/hit.wav",
	"explosion": "res://assets/audio/explosion.wav",
	"morale_break": "res://assets/audio/morale_break.wav",
	"round_plan": "res://assets/audio/round_plan.wav",
	"round_exec": "res://assets/audio/round_exec.wav",
	"card_use": "res://assets/audio/card_use.wav",
	"card_smoke": "res://assets/audio/card_effects/card_smoke.wav",
	"card_electronic": "res://assets/audio/card_effects/card_electronic.wav",
	"card_deploy": "res://assets/audio/card_effects/card_deploy.wav",
	"card_mines": "res://assets/audio/card_effects/card_mines.wav",
	"card_fortify": "res://assets/audio/card_effects/card_fortify.wav",
	"loan_coin": "res://assets/audio/loan_coin.wav",
	"victory": "res://assets/audio/victory.wav",
	"defeat": "res://assets/audio/defeat.wav",
}

const BGM_TRACKS := {
	"menu": "res://assets/audio/bgm/menu_shortwave_unknown_threat.mp3",
	"level": "res://assets/audio/bgm/level_radar_pulse_unrest.mp3",
}
const SETTINGS_PATH := "user://audio_settings.cfg"
const DEFAULT_BGM_VOLUME := 0.72
const DEFAULT_SFX_VOLUME := 0.82

const CARD_EFFECT_SFX := {
	"call_artillery": "explosion",
	"blind_fire_barrage": "explosion",
	"smoke_screen": "card_smoke",
	"sapper_mines": "card_mines",
	"coordinate_prediction": "card_electronic",
	"emi_countermeasure": "card_electronic",
	"power_cut": "card_electronic",
	"radio_silence": "card_electronic",
	"false_report": "card_electronic",
	"reserve_deployment": "card_deploy",
	"fortify_position": "card_fortify",
	"sacrifice_charge": "morale_break",
}

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0
var _bgm_player: AudioStreamPlayer
var _bgm_tween: Tween
var _current_bgm := ""
var _bgm_volume := DEFAULT_BGM_VOLUME
var _sfx_volume := DEFAULT_SFX_VOLUME

signal audio_settings_changed(bgm_volume: float, sfx_volume: float)


func _ready() -> void:
	_ensure_bus("BGM")
	_ensure_bus("SFX")
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMPlayer"
	_bgm_player.bus = "BGM"
	add_child(_bgm_player)
	for i in range(8):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer%d" % i
		player.bus = "SFX"
		player.finished.connect(_on_player_finished.bind(player))
		add_child(player)
		_pool.append(player)
	_load_audio_settings()


func play(sfx_name: String, volume_db: float = 0.0) -> void:
	## 从池中取一个播放器播放指定音效（同音快速连发自动复用）；流按需加载并缓存
	if not SFX.has(sfx_name):
		return
	if not _streams.has(sfx_name):
		var stream: AudioStream = load(SFX[sfx_name])
		if stream == null:
			return
		_streams[sfx_name] = stream
	var player := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	player.stream = _streams[sfx_name]
	player.volume_db = volume_db
	player.play()


func play_card_effect(card_id: String) -> void:
	"""在卡牌实际结算时播放对应环境音，而不是在选牌时提前播放。"""
	var sfx_name := String(CARD_EFFECT_SFX.get(card_id, "card_use"))
	var volume_db := -2.0 if sfx_name == "explosion" else -5.0
	play(sfx_name, volume_db)


func play_bgm(track_id: String) -> void:
	"""切换并循环播放主菜单或关卡BGM；重复请求同一曲目不会重头播放。"""
	if not BGM_TRACKS.has(track_id):
		return
	if _current_bgm == track_id and _bgm_player.playing:
		return
	var path := String(BGM_TRACKS[track_id])
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	elif FileAccess.file_exists(path):
		# 新复制的MP3可能尚未被编辑器生成.import；首次启动直接从磁盘读取。
		stream = AudioStreamMP3.load_from_file(ProjectSettings.globalize_path(path))
	if stream == null:
		push_warning("[SoundManager] 无法加载BGM: %s" % path)
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	if _bgm_tween and _bgm_tween.is_valid():
		_bgm_tween.kill()
	if _bgm_player.playing:
		_bgm_tween = create_tween()
		_bgm_tween.tween_property(_bgm_player, "volume_db", -24.0, 0.28)
		_bgm_tween.tween_callback(_start_bgm.bind(track_id, stream))
	else:
		_start_bgm(track_id, stream)


func _start_bgm(track_id: String, stream: AudioStream) -> void:
	_current_bgm = track_id
	_bgm_player.stream = stream
	_bgm_player.volume_db = -24.0
	_bgm_player.play()
	_bgm_tween = create_tween()
	_bgm_tween.tween_property(_bgm_player, "volume_db", 0.0, 0.45)


func set_bgm_volume(value: float, save: bool = true) -> void:
	_bgm_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume("BGM", _bgm_volume)
	if save:
		_save_audio_settings()
	audio_settings_changed.emit(_bgm_volume, _sfx_volume)


func set_sfx_volume(value: float, save: bool = true) -> void:
	_sfx_volume = clampf(value, 0.0, 1.0)
	_apply_bus_volume("SFX", _sfx_volume)
	if save:
		_save_audio_settings()
	audio_settings_changed.emit(_bgm_volume, _sfx_volume)


func get_bgm_volume() -> float:
	return _bgm_volume


func get_sfx_volume() -> float:
	return _sfx_volume


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


func _apply_bus_volume(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, value <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))


func _load_audio_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		_bgm_volume = clampf(float(config.get_value("audio", "bgm_volume", DEFAULT_BGM_VOLUME)), 0.0, 1.0)
		_sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", DEFAULT_SFX_VOLUME)), 0.0, 1.0)
	set_bgm_volume(_bgm_volume, false)
	set_sfx_volume(_sfx_volume, false)


func _save_audio_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "bgm_volume", _bgm_volume)
	config.set_value("audio", "sfx_volume", _sfx_volume)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("[SoundManager] 音频设置保存失败: %s" % error_string(error))


func _on_player_finished(player: AudioStreamPlayer) -> void:
	## 播放完释放流引用，避免资源在退出时仍被 AudioStreamPlayer 持有
	player.stream = null


func _exit_tree() -> void:
	if _bgm_tween and _bgm_tween.is_valid():
		_bgm_tween.kill()
	if _bgm_player:
		_bgm_player.stop()
		_bgm_player.stream = null
	for p in _pool:
		p.stop()
		p.stream = null
	_streams.clear()


func stop_all() -> void:
	## 停止所有播放并清空流缓存（场景退出/测试结束时调用,
	## 避免 AudioServer 持有已播放流导致退出时报资源未释放）
	for p in _pool:
		p.stop()
		p.stream = null
	_streams.clear()
