extends Node
## 音效管理（0.5.5）
## 预加载 assets/audio/ 全部程序合成 wav，8 个 AudioStreamPlayer 循环复用播放。
## 用法：SoundManager.play("explosion") / SoundManager.play("tank_fire", -6.0)

const SFX := {
	"ui_click": "res://assets/audio/ui_click.wav",
	"unit_select": "res://assets/audio/unit_select.wav",
	"move_order": "res://assets/audio/move_order.wav",
	"gunshot": "res://assets/audio/gunshot.wav",
	"tank_fire": "res://assets/audio/tank_fire.wav",
	"hit": "res://assets/audio/hit.wav",
	"explosion": "res://assets/audio/explosion.wav",
	"morale_break": "res://assets/audio/morale_break.wav",
	"round_plan": "res://assets/audio/round_plan.wav",
	"round_exec": "res://assets/audio/round_exec.wav",
	"card_use": "res://assets/audio/card_use.wav",
	"loan_coin": "res://assets/audio/loan_coin.wav",
	"victory": "res://assets/audio/victory.wav",
	"defeat": "res://assets/audio/defeat.wav",
}

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0


func _ready() -> void:
	for i in range(8):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer%d" % i
		player.finished.connect(_on_player_finished.bind(player))
		add_child(player)
		_pool.append(player)


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


func _on_player_finished(player: AudioStreamPlayer) -> void:
	## 播放完释放流引用，避免资源在退出时仍被 AudioStreamPlayer 持有
	player.stream = null


func _exit_tree() -> void:
	## 退出时释放音频流引用，避免 Godot 报 resources still in use
	for p in _pool:
		p.stop()
		p.stream = null
	_streams.clear()
