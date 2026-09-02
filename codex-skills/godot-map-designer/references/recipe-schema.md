# 地图配方规范

```json
{
  "scene": "res://scenes/levels/level_01.tscn",
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

顶层字段：

- `scene`：目标关卡场景。存在时保留非地形节点；不存在时创建含地形层的新场景。
- `width`、`height`：正整数地图尺寸。
- `base`：完整铺底地块，默认 `tile.grass`。
- `seed`：控制图块变体和散布，默认 `1987`。
- `auto_edges`：根据四邻域自动选择边缘、转角和内部图块，默认 `true`。
- `operations`：按顺序执行，后项覆盖前项。

操作字段：

- 坐标统一为零基 `[x, y]`。
- `map.rect` 的 `from`、`to` 都包含在区域内。
- `map.path.width` 是格数，最小为 1。
- `map.ellipse.radius` 为 `[横半径, 纵半径]`。
- `map.polygon.points` 至少 3 点。
- `map.scatter.rect` 为 `[x, y, width, height]`，`density` 范围为 0 到 1。

设计约束：

- 先放大面积地貌，再画道路、河道等线性结构，最后放局部地块。
- 对战地图必须检查双方出生区间距、可通行连通性、胜利点可达性以及建筑占地。
- `tile.water` 和 `tile.rock` 可能限制装甲单位通行，不要无意中封死唯一通路。
- 当前 TileSet 没有独立桥梁、铁路、城市和沼泽图块；不要把这些运行时概念伪装成已有地块。需要时先扩展 TileSet 元数据。
- 方位图块必须遵循 [边缘生成逻辑](edge-generation.md)，不得在边缘随机选择中心纹理。
