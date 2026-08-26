# 地块与指令

所有地块都使用稳定调用令牌。用户可直接说“用 `tile.water` 从 `[2,10]` 画到 `[30,18]`”，AI 不需要查询 atlas 坐标。

| 调用指令 | 中文别名 | 用途 | 当前运行时类型 |
|---|---|---|---|
| `tile.soil` | 土地、泥土、土壤 | 裸地、阵地、道路边缘 | 平原 |
| `tile.grass` | 草地、平原 | 默认开阔地 | 平原 |
| `tile.road` | 道路、公路 | 低移动消耗通道 | 公路 |
| `tile.forest` | 森林、密林 | 高隐蔽林区 | 密林 |
| `tile.brush` | 灌木、灌丛、花草 | 稀疏植被过渡区 | 密林 |
| `tile.rock` | 岩地、岩石、山地 | 高地和阻滞区 | 山地 |
| `tile.water` | 水域、河流 | 河道、湖泊和洼地 | 河流 |

地图形状指令：

| 调用指令 | 作用 | 核心参数 |
|---|---|---|
| `map.fill` | 全图覆盖 | `terrain` |
| `map.cell` | 单格绘制 | `at` |
| `map.rect` | 含边界矩形 | `from`, `to` |
| `map.ellipse` | 椭圆区域 | `center`, `radius` |
| `map.path` | 连续折线路径 | `points`, `width` |
| `map.polygon` | 闭合多边形区域 | `points` |
| `map.scatter` | 矩形内确定性散布 | `rect`, `density` |

道路、河流、铁路状结构优先用 `map.path`；林区、山脉优先用 `map.ellipse` 或 `map.polygon`；零散灌木用 `map.scatter`。同一 `seed` 和配方会得到完全相同的图块变体。

查询自动边缘使用的坐标和唯一名称：

```powershell
powershell -ExecutionPolicy Bypass -File tools/design_map.ps1 -ListEdgeRules
```
