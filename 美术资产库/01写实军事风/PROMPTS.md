# AI生成美术资产 — 提示词记录

日期: 2026-07-30
API: micuapi.ai → gpt-image-2 (low/medium quality)
输出: D:/Project_code/baqvzhanche/美术资产库/AI生成_v1/

---

## 1. 单位图标 Sprite Sheet
文件: units_spritesheet.png (1024×1024, medium)

A clean pixel-art style sprite sheet for a military wargame. 3 columns x 3 rows of unit icons, each cell exactly 64x64 pixels, clearly separated by thin white grid lines on dark background.
TOP ROW (red/暖色调 - Warsaw Pact): infantry soldier with rifle, T-72 main battle tank top-down view, BMP-2 infantry fighting vehicle.
MIDDLE ROW (red/暖色调 - Warsaw Pact): command squad with radio backpack, reconnaissance scout with binoculars, motorized infantry in truck/APC.
BOTTOM ROW (blue/冷色调 - NATO): M1 Abrams tank top-down view, NATO infantry soldier, AH-64 Apache attack helicopter.
Style: simple pixel art, flat shading, clear silhouettes at small size, minimalist military aesthetic. Each icon fills its 64x64 cell. No text labels.

---

## 2. 卡牌面图 (7张, 1024×1536, low)

### 2.1 坐标预判
card_coordinate_prediction.png
Military strategy card art, portrait aspect 2:3. Dark tactical map with red glowing crosshair overlay, trajectory prediction lines, radar sweep effect. Cold War aesthetic, green radar screen background, minimalist military UI style. Atmospheric. Large empty space at bottom for card text.

### 2.2 盲射弹幕
card_blind_fire.png
Military strategy card art, portrait aspect 2:3. Multiple artillery shell trajectories arcing through thick fog and smoke, orange muzzle flashes, distant explosions. Silhouette of artillery on ridge line. Moody atmospheric, dark gray fog, cinematic Cold War military aesthetic. Space at bottom for card text.

### 2.3 烟雾遮障
card_smoke_screen.png
Military strategy card art, portrait aspect 2:3. Thick rolling white smoke clouds covering a battlefield, partially obscuring tank silhouettes. Single searchlight beam cutting through haze. Atmospheric, moody, olive green and gray palette, Cold War military. Space at bottom for card text.

### 2.4 阵地加固
card_fortify.png
Military strategy card art, portrait 2:3. Soldiers digging trenches and building sandbag fortifications at night, dim lantern light, barbed wire silhouettes. Cold War defensive position, dark earthy tones, atmospheric moonlight. Space at bottom for card text.

### 2.5 无线电静默
card_radio_silence.png
Military strategy card art, portrait 2:3. An old military radio set in a dark bunker, static noise visualized as abstract waves, a hand reaching to turn it off. Dark cramped interior, single desk lamp lighting, Cold War tension. Space at bottom for card text.

### 2.6 呼叫炮击
card_artillery_strike.png
Military strategy card art, portrait 2:3. A soldier with radio handset calling coordinates, dramatic explosion in distance through window/bunker slit. Orange and yellow blast, smoke column rising. Cold War battlefield atmosphere, dramatic contrast. Space at bottom for card text.

### 2.7 电磁反制
card_emi_counter.png
Military strategy card art, portrait 2:3. Abstract electronic warfare visualization — a radar screen going haywire with interference patterns, radio waves being jammed, static noise visual effect. Blue and purple neon-like waves on dark tech background. Cyber-electronic military aesthetic. Space at bottom for card text.

---

## 3. 地形标记 (4个, 1024×1024, low)

### 3.1 VP胜利点
marker_vp.png
Simple game icon on transparent/black background. A golden-yellow diamond shape with a small star inside, like a victory point marker for a strategy game. Clean geometric, minimal, 256x256. No text.

### 3.2 华约出生点
marker_wp_spawn.png
Simple game icon on transparent/black background. A red square with a white upward arrow inside, like a Warsaw Pact spawn point marker. Clean geometric military icon, 256x256. No text.

### 3.3 NATO出生点
marker_nato_spawn.png
Simple game icon on transparent/black background. A blue square with a white upward arrow inside, like a NATO spawn point marker. Clean geometric military icon, 256x256. No text.

### 3.4 未知接触
marker_unknown.png
Simple game icon on transparent/black background. A gray circle with a white question mark '?' inside, like an unknown contact marker for a strategy game. Clean geometric, 256x256. No text.

---

## 4. 结算背景 (2张, 1536×1024, low)

### 4.1 胜利
bg_victory.png
Cinematic Cold War military victory screen background, landscape. Soviet tanks rolling through a liberated checkpoint at dawn, soldiers raising a flag, warm golden sunrise light, hopeful triumphant atmosphere. No text or UI elements. Widescreen cinematic.

### 4.2 失败
bg_defeat.png
Cinematic Cold War military defeat screen background, landscape. Abandoned checkpoint in mist, destroyed tank wreckage smoking, single helmet on rifle stuck in ground, grim gray overcast sky, somber atmosphere. No text or UI elements. Widescreen cinematic.

---

## 已知问题 / 待改进

- [ ] 单位 sprite sheet 可能需要自行切片成 9 个独立文件
- [ ] 地形标记背景非透明，需在 Godot 里处理或用 SVG 重新做
- [ ] 卡牌图片尺寸偏大(1024×1536)，Godot 内需缩放
- [ ] 部分卡牌面图底部预留的文字区域不够明显
