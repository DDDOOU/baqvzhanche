extends CanvasLayer
## 天气视觉层（0.5.6）
## 按关卡 weather 配置显示氛围雾/雪：全屏半透明底色 + 3 团 FastNoiseLite 噪声雾缓慢漂移。
## 零外部素材（NoiseTexture2D 运行时生成）；layer=70 盖住棋盘但不挡 HUD/UI 输入。

var _puffs: Array[Sprite2D] = []
var _drift_time: float = 0.0


func setup(weather: String) -> void:
	## weather: "clear"（无） / "fog"（仅保留数值机制） / "snow"（冷雾，白色走廊）
	layer = 70
	match weather:
		"fog":
			# 晨雾仍由关卡逻辑降低视野和命中；不再用全屏视觉层遮挡棋盘。
			queue_free()
		"snow":
			_build(Color(0.86, 0.9, 0.98), 0.22)
		_:
			queue_free()


func _build(tint: Color, alpha: float) -> void:
	# 全屏底色（雾的弥漫感）
	var rect := ColorRect.new()
	rect.name = "FogBase"
	rect.color = Color(tint.r, tint.g, tint.b, alpha * 0.6)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)

	# 3 团噪声雾（低频 simplex，大尺寸低透明度，缓慢漂移）
	for i in range(3):
		var noise_tex := NoiseTexture2D.new()
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.0035 + i * 0.0012
		noise.seed = 1987 + i * 77
		noise_tex.noise = noise
		noise_tex.width = 512
		noise_tex.height = 384

		var puff := Sprite2D.new()
		puff.name = "FogPuff%d" % i
		puff.texture = noise_tex
		puff.modulate = Color(tint.r, tint.g, tint.b, alpha)
		puff.scale = Vector2(3.0 + i * 0.8, 2.6 + i * 0.6)
		puff.position = Vector2(200 + i * 260, 150 + (i % 2) * 120)
		add_child(puff)
		_puffs.append(puff)


func _process(delta: float) -> void:
	# 雾团缓慢左右漂移（sin 波，周期 20~32 秒，幅度 60~140px）
	_drift_time += delta
	for i in range(_puffs.size()):
		var puff := _puffs[i]
		if puff == null:
			continue
		var period := 20.0 + i * 6.0
		var amp := 60.0 + i * 40.0
		var base_x := 200.0 + i * 260.0
		puff.position.x = base_x + sin(_drift_time * TAU / period) * amp
		puff.position.y = 150.0 + (i % 2) * 120.0 + cos(_drift_time * TAU / (period * 1.3)) * 24.0
