# Assets 资源文件夹

将以下类型的素材放入此文件夹：

## 地形贴图 (textures/)
```
assets/textures/terrain/
├── plains.png           # 平原
├── city.png             # 城市/永备工事
├── mountain.png         # 山地
├── forest.png           # 密林/反斜面
├── river.png            # 河流/沼泽
├── road.png             # 公路
├── railway.png          # 铁路
├── bridge.png           # 桥梁
└── marsh.png            # 沼泽
```

## 单位图标 (icons/)
```
assets/icons/
├── wp_infantry.png      # 华约步兵班
├── wp_t72b.png          # T-72B 坦克
├── wp_bmp2.png          # BMP-2 步战车
├── wp_bm21.png          # BM-21 火箭炮
├── wp_sa13.png          # SA-13 防空
├── nato_m1a1.png        # M1A1 坦克
├── nato_m2.png          # M2 Bradley
├── nato_ah64.png        # AH-64 阿帕奇
└── civilian.png         # 平民
```

## 音效 (audio/)
```
assets/audio/
├── sfx/
│   ├── tank_fire.wav    # 坦克开火
│   ├── artillery.wav    # 炮击
│   ├── explosion.wav    # 爆炸
│   ├── helicopter.wav   # 直升机旋翼声
│   ├── mine_explode.wav # 地雷引爆
│   └── radio_static.wav # 电磁干扰噪声
└── music/
	├── menu_theme.ogg   # 菜单主题
	├── battle_01.ogg    # 战斗音乐1
	└── victory.ogg      # 胜利音乐
```

## 字体 (fonts/)
```
assets/fonts/
└── tactical.ttf         # 战术风格字体（可选）
```

---

注意：
- Godot 4.x 推荐使用 `.png` (贴图) 和 `.ogg`/`.wav` (音频) 格式
- 所有素材放入后，在 Godot 编辑器中会自动导入
- 贴图建议分辨率: 128×128 (地形) / 64×64 (单位图标)
