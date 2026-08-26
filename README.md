# Godot 战棋地图生成器

这是一个面向 Godot 4 等距战棋项目的地图设计工具。它把自然语言地图描述转换为 JSON 配方，再按 TileSet 的 `terrain_type` 元数据生成完整 `TileMapLayer` 场景。

工具支持整图填充、单格、矩形、椭圆、折线路径、多边形和确定性散布。水域会根据四邻域自动选择北、东、南、西边缘、转角、狭道、端头和深水中心图块。

## 仓库结构

```text
.
├── 战棋0.6/                              # Godot 项目
│   ├── tools/map_designer.gd             # 地图生成器
│   ├── tools/design_map.ps1              # Windows 一键入口
│   ├── tools/map_recipe.example.json     # 配方示例
│   ├── data/maps/terrain_test_10.json     # 10 地形区测试配方
│   └── scenes/levels/terrain_test_10.tscn # 已生成测试场景
└── codex-skills/godot-map-designer/      # 可安装的 Codex skill
```

## 安装指南

### 1. 安装依赖

- Windows 10/11
- Godot 4.7 或兼容的 Godot 4.x 版本
- PowerShell 5.1 或更高版本
- Git
- Codex Desktop，可选，用于自然语言生成地图配方

Steam 版 Godot 默认支持当前开发路径：

```text
D:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe
```

其他安装位置可在执行时传入 `-GodotPath`。

### 2. 克隆仓库

```powershell
git clone https://github.com/DDDOOU/baqvzhanche.git
cd baqvzhanche\战棋0.6
```

用 Godot 导入 `战棋0.6/project.godot`，等待首次资源扫描完成。

### 3. 安装 Codex 地图设计 skill

在仓库根目录执行：

```powershell
$SkillPath = Join-Path $env:USERPROFILE '.codex\skills\godot-map-designer'
New-Item -ItemType Directory -Force -Path $SkillPath
Copy-Item '.\codex-skills\godot-map-designer\*' $SkillPath -Recurse -Force
```

重新启动 Codex 后，可通过 `$godot-map-designer` 调用。

## 使用指南

### 自然语言调用

```text
$godot-map-designer 创建一张40x45地图，北部是岩石山脊，
南部生成一条3格宽河流，中间铺设公路，西侧布置森林和灌木。
```

skill 会创建 JSON 配方，先执行干跑验证，再保存 Godot 场景。

### 查询可用地形

```powershell
cd .\战棋0.6
powershell -ExecutionPolicy Bypass -File tools\design_map.ps1 -ListTerrains
```

当前游戏规则地形指令：

| 指令 | 地形 |
|---|---|
| `tile.soil` | 泥土、裸地 |
| `tile.grass` | 草地、平原 |
| `tile.road` | 道路、公路 |
| `tile.forest` | 森林、密林 |
| `tile.brush` | 灌木、花草 |
| `tile.rock` | 岩地、山地 |
| `tile.water` | 水域、河流 |

### 查询自动边缘规则

```powershell
powershell -ExecutionPolicy Bypass -File tools\design_map.ps1 -ListEdgeRules
```

地图方向使用逻辑网格坐标：`N=(0,-1)`、`E=(1,0)`、`S=(0,1)`、`W=(-1,0)`。当前格与某方向邻格不同，则边缘掩码对应位为 1：`N=1`、`E=2`、`S=4`、`W=8`。

例如水域西邻格不是水域，且其余三边仍连接水域时，生成器会选择西边缘图块 `(0,9) 浅水流纹·宽幅左摆`。

### 编写地图配方

```json
{
  "scene": "res://scenes/levels/my_map.tscn",
  "width": 40,
  "height": 45,
  "base": "tile.grass",
  "seed": 1987,
  "auto_edges": true,
  "operations": [
    { "command": "map.rect", "terrain": "tile.soil", "from": [2, 3], "to": [8, 10] },
    { "command": "map.path", "terrain": "tile.road", "points": [[0, 20], [18, 22], [39, 18]], "width": 2 },
    { "command": "map.ellipse", "terrain": "tile.forest", "center": [12, 12], "radius": [6, 4] },
    { "command": "map.scatter", "terrain": "tile.brush", "rect": [20, 5, 12, 10], "density": 0.25 }
  ]
}
```

地图指令：

| 指令 | 作用 | 参数 |
|---|---|---|
| `map.fill` | 全图覆盖 | `terrain` |
| `map.cell` | 单格绘制 | `at` |
| `map.rect` | 矩形区域 | `from`, `to` |
| `map.ellipse` | 椭圆区域 | `center`, `radius` |
| `map.path` | 连续折线路径 | `points`, `width` |
| `map.polygon` | 闭合多边形 | `points` |
| `map.scatter` | 矩形内散布 | `rect`, `density` |

坐标均为零基 `[x, y]`。操作按数组顺序覆盖，后面的操作优先。

### 验证和生成

先执行干跑，不写入场景：

```powershell
powershell -ExecutionPolicy Bypass -File tools\design_map.ps1 `
  -Recipe tools\map_recipe.example.json -DryRun
```

确认地形统计和边缘规则后正式生成：

```powershell
powershell -ExecutionPolicy Bypass -File tools\design_map.ps1 `
  -Recipe tools\map_recipe.example.json
```

使用非默认 Godot 路径：

```powershell
powershell -ExecutionPolicy Bypass -File tools\design_map.ps1 `
  -Recipe tools\map_recipe.example.json `
  -GodotPath 'C:\Godot\Godot_v4.7-stable_win64.exe'
```

### 10 地形区测试地图

```powershell
powershell -ExecutionPolicy Bypass -File tools\design_map.ps1 `
  -Recipe data\maps\terrain_test_10.json
```

测试地图为 `36×28`、1008 格，包含开阔草原、裸土地、密林、花草地、稀疏灌丛、岩石山脊、独立岩丘、深水湖泊、浅水河流和碎石公路。

## 地块与名称对照表

Atlas 坐标格式为 `(X,Y)`，每格尺寸为 `32×32`。视觉名称保持唯一；运行时指令来自 TileSet 的 `terrain_type`。`未定义` 图块没有可用的游戏规则元数据，不应由地图生成器自动放置。

| Atlas 坐标 | 唯一视觉名称 | 运行时指令 |
|---|---|---|
| `(0,0)` | 泥土·左侧暗斑 | `tile.soil` |
| `(1,0)` | 泥土·右缘碎砾 | `tile.soil` |
| `(2,0)` | 泥土·中央浅斑 | `tile.soil` |
| `(3,0)` | 泥土·深褐平面 | `tile.soil` |
| `(4,0)` | 泥土·浅黄平面 | `tile.soil` |
| `(5,0)` | 泥土·右上亮斑 | `tile.soil` |
| `(6,0)` | 泥土·中央点状纹 | `tile.soil` |
| `(7,0)` | 泥土·环形车辙 | `tile.soil` |
| `(8,0)` | 泥土·右侧颗粒 | `tile.soil` |
| `(9,0)` | 泥土·宽浅色面 | `tile.soil` |
| `(10,0)` | 泥土·窄浅色面 | `tile.soil` |
| `(0,1)` | 碎石路·横向巨石 | `tile.road` |
| `(1,1)` | 碎石路·斜向石板 | `tile.road` |
| `(2,1)` | 碎石路·圆石拼接 | `tile.road` |
| `(3,1)` | 砂砾路·浅色细石 | `tile.road` |
| `(4,1)` | 车辙路·三道平行纹 | `tile.road` |
| `(5,1)` | 碎石路·破裂岩片 | `tile.road` |
| `(6,1)` | 干裂土·双龟裂 | `tile.soil` |
| `(7,1)` | 干裂土·中央裂缝 | `tile.soil` |
| `(8,1)` | 裸土苗圃·左侧双芽 | `tile.soil` |
| `(9,1)` | 裸土苗圃·两株幼苗 | `tile.soil` |
| `(10,1)` | 裸土·深褐平整 | `tile.soil` |
| `(0,2)` | 草坪·平滑短草 | `tile.grass` |
| `(1,2)` | 草坪·顶部尖草 | `tile.grass` |
| `(2,2)` | 草坪·前缘细草 | `tile.grass` |
| `(3,2)` | 耕地·裸土斜垄 | `tile.grass` |
| `(4,2)` | 耕地·覆草斜垄 | `tile.grass` |
| `(5,2)` | 苔草地·细叶覆盖 | `tile.forest` |
| `(6,2)` | 苔草地·宽叶覆盖 | `tile.forest` |
| `(7,2)` | 密林·浅绿阔叶冠 | `tile.forest` |
| `(8,2)` | 密林·中绿交叠冠 | `tile.forest` |
| `(9,2)` | 密林·尖叶高冠 | `tile.forest` |
| `(10,2)` | 密林·圆叶高冠 | `tile.forest` |
| `(0,3)` | 灌丛·浅绿密叶 | `tile.grass` |
| `(1,3)` | 灌丛·高枝新叶 | `tile.grass` |
| `(2,3)` | 灌丛·深绿宽叶 | `tile.grass` |
| `(3,3)` | 高草丛·直立细叶 | `tile.grass` |
| `(4,3)` | 草甸·左侧高草边 | `tile.forest` |
| `(5,3)` | 草甸·中央高草边 | `tile.forest` |
| `(6,3)` | 草甸·右侧高草边 | `tile.grass` |
| `(7,3)` | 深绿草坪·裸土底边 | `tile.grass` |
| `(8,3)` | 花圃·橙黄红花簇 | 未定义 |
| `(9,3)` | 花圃·红黄小花束 | 未定义 |
| `(10,3)` | 深绿灌木·尖叶团 | 未定义 |
| `(0,4)` | 紫花丛·高穗 | `tile.brush` |
| `(1,4)` | 圆叶灌木·低矮 | `tile.brush` |
| `(2,4)` | 红黄野花丛·带叶 | `tile.brush` |
| `(3,4)` | 红黄花瓣·零散 | `tile.brush` |
| `(4,4)` | 倒木·完整树干 | 未定义 |
| `(5,4)` | 枯枝·交叉堆 | 未定义 |
| `(6,4)` | 倒木·断裂树干 | 未定义 |
| `(7,4)` | 倒木·苔藓覆盖 | 未定义 |
| `(8,4)` | 枯树桩·直立 | 未定义 |
| `(9,4)` | 褐色独石·圆顶 | 未定义 |
| `(10,4)` | 褐色叠石·双层 | 未定义 |
| `(0,5)` | 褐岩柱·左斜层叠 | `tile.rock` |
| `(1,5)` | 褐岩柱·双峰并立 | `tile.rock` |
| `(2,5)` | 褐岩柱·宽顶方台 | `tile.rock` |
| `(3,5)` | 褐岩柱·细腰孤柱 | `tile.rock` |
| `(4,5)` | 褐岩柱·三层叠台 | `tile.rock` |
| `(5,5)` | 褐岩柱·右斜高台 | `tile.rock` |
| `(6,5)` | 灰岩台·碎石铺顶 | `tile.rock` |
| `(7,5)` | 灰岩台·双岩拼接 | `tile.rock` |
| `(8,5)` | 灰岩台·宽阔平顶 | `tile.rock` |
| `(9,5)` | 灰岩峰·高耸尖柱 | `tile.rock` |
| `(10,5)` | 灰岩块·圆顶巨石 | `tile.rock` |
| `(0,6)` | 陆地灰岩·单体尖峰 | `tile.rock` |
| `(1,6)` | 陆地灰岩·双体碎峰 | `tile.rock` |
| `(2,6)` | 水边灰岩·碎石平台 | `tile.rock` |
| `(3,6)` | 水边灰岩·平顶平台 | `tile.rock` |
| `(4,6)` | 水边灰岩·双岩平台 | `tile.rock` |
| `(5,6)` | 水边灰岩·乱石平台 | `tile.rock` |
| `(6,6)` | 水中灰岩·高耸石柱 | `tile.rock` |
| `(7,6)` | 水中灰岩·倾斜尖峰 | `tile.rock` |
| `(8,6)` | 水中灰岩·层叠圆峰 | 未定义 |
| `(9,6)` | 水中灰岩·低矮圆礁 | 未定义 |
| `(10,6)` | 水中灰岩·小型尖礁 | 未定义 |
| `(0,7)` | 深水灰岩·双岩礁 | 未定义 |
| `(1,7)` | 深水灰岩·乱石礁 | 未定义 |
| `(2,7)` | 深水灰岩·高尖石柱 | 未定义 |
| `(3,7)` | 深水灰岩·倾斜石峰 | 未定义 |
| `(4,7)` | 深水灰岩·层叠圆石 | 未定义 |
| `(5,7)` | 水花粒子·横向双点 | 未定义 |
| `(6,7)` | 水花粒子·紧凑三点 | 未定义 |
| `(7,7)` | 水花粒子·竖向散点 | 未定义 |
| `(8,7)` | 水花粒子·斜向散点 | 未定义 |
| `(9,7)` | 透明占位·A | 未定义 |
| `(10,7)` | 透明占位·B | 未定义 |
| `(0,8)` | 浅水波纹·北缘长波 | `tile.water` |
| `(1,8)` | 浅水波纹·南缘长波 | `tile.water` |
| `(2,8)` | 浅水波纹·西北中央圆波 | `tile.water` |
| `(3,8)` | 浅水波纹·东北双层回旋 | `tile.water` |
| `(4,8)` | 中水波纹·东西狭道 | `tile.water` |
| `(5,8)` | 中水波纹·南北狭道 | `tile.water` |
| `(6,8)` | 深水静面·纯暗蓝 | 未定义 |
| `(7,8)` | 深水波纹·稀疏亮点 | `tile.water` |
| `(8,8)` | 深水波纹·双层暗纹 | `tile.water` |
| `(9,8)` | 透明水域占位·A | `tile.water` |
| `(10,8)` | 透明水域占位·B | `tile.water` |
| `(0,9)` | 浅水流纹·宽幅左摆 | `tile.water` |
| `(1,9)` | 浅水流纹·窄幅右摆 | `tile.water` |
| `(2,9)` | 浅水涟漪·西南单圈 | `tile.water` |
| `(3,9)` | 浅水涟漪·东南双圈 | `tile.water` |
| `(4,9)` | 中水涟漪·北向端头 | `tile.water` |
| `(5,9)` | 中水涟漪·东向端头 | `tile.water` |
| `(6,9)` | 深水静面·靛蓝 | 未定义 |
| `(7,9)` | 深水涟漪·碎亮点 | `tile.water` |
| `(8,9)` | 深水涟漪·环状暗纹 | `tile.water` |
| `(9,9)` | 透明水域占位·C | `tile.water` |
| `(10,9)` | 透明水域占位·D | `tile.water` |
| `(0,10)` | 冰面·左下厚边 | `tile.water` |
| `(1,10)` | 冰面·右上亮边 | `tile.water` |
| `(2,10)` | 冰面·上缘尖角 | `tile.water` |
| `(3,10)` | 冰面·左下延伸边 | `tile.water` |
| `(4,10)` | 冰面·右下延伸边 | `tile.water` |
| `(5,10)` | 冰面·中央亮脊 | `tile.water` |
| `(6,10)` | 冰面·右侧内凹 | `tile.water` |
| `(7,10)` | 冰面·平整亮面 | `tile.water` |
| `(8,10)` | 冰面·右上缺口 | `tile.water` |
| `(9,10)` | 冰面·双层亮边 | `tile.water` |
| `(10,10)` | 浮冰·碎片群 | `tile.water` |
