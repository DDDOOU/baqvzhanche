---
name: godot-map-designer
description: Design or edit tactical maps in the Godot project 战棋0.6 by translating natural-language terrain requirements into deterministic recipes and applying the project's TileSet metadata. Use for map layout, terrain painting, roads, rivers, forests, mountains, clearings, or resizing level terrain scenes.
---

# Godot Map Designer

将用户的地图描述转换为 JSON 配方，再调用项目自带生成器。用户无需提供图集坐标；生成器按 TileSet 的 `terrain_type` 自定义数据选取正确图块。

## 项目入口

- 项目根目录：在当前工作区中定位包含 `project.godot`、`tools/map_designer.gd` 和 `resources/tilesets/isometric_terrain.tres` 的 `战棋0.6` 目录。用户指定了其他项目路径时以用户路径为准。
- 一键命令：`powershell -ExecutionPolicy Bypass -File tools/design_map.ps1 -Recipe <json>`
- 保存前验证：追加 `-DryRun`
- 查询当前 TileSet 地块：`powershell -ExecutionPolicy Bypass -File tools/design_map.ps1 -ListTerrains`
- 配方示例：`tools/map_recipe.example.json`

## 工作方式

1. 先读取 [地块与指令](references/terrain-commands.md)。涉及配方字段或复杂区域时，再读取 [配方规范](references/recipe-schema.md)；涉及岸线、边缘、转角、狭道或方向图块时，必须读取 [边缘生成逻辑](references/edge-generation.md)。
2. 检查目标 `.tscn`、现有建筑、出生点和胜利点。除非用户明确要求，只重绘 `Terrain（地块）`，保留其他节点。
3. 在项目 `.codex_tmp` 下创建本次配方，先执行 `-DryRun`；检查尺寸、总格数、各地形统计和越界对象。
4. 验证通过后执行正式命令。重新加载场景并运行 Godot headless 项目检查。
5. 删除本次临时配方。用户明确要求保存设计方案时，才把配方放入 `data/maps/` 等正式目录。

地图操作按数组顺序覆盖，越靠后的操作优先。地图必须由 `base` 完整铺底，坐标为零基 `[x, y]`。尺寸变化时，必须检查建筑、出生点、单位和胜利点是否仍在边界内；生成器不会擅自移动这些玩法对象。
