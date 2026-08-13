# Silent Reckoning·1987 工程架构

> 当前版本：0.3.2。本文以实际运行代码为准；早期“六边形网格”设计已被四方向等距方格替代。部分旧文件名仍保留 `Hex`，仅为避免一次性破坏 Godot UID 和引用。

## 运行边界

- Godot 4.7.1，主入口为 `scenes/MainMenu.tscn`。
- 当前正式可玩内容为第一关“边境晨雾”。第 2～10 关只有 `LevelDatabase` 数据草案，菜单不会展示没有场景的关卡。
- 第一关地图由 `scenes/levels/level_01.tscn` 的 `Terrain` TileMapLayer 提取，逻辑尺寸为 40×45。
- 回合循环为计划阶段、统一演算、回合结算；即时胜负由指挥单位和全歼条件触发，第八回合再结算 VP。

## 目录职责

```text
战棋0.3/
├── project.godot
├── export_presets.cfg
├── scenes/
│   ├── MainMenu.tscn
│   ├── MainScene.tscn
│   └── levels/level_01.tscn
├── scripts/
│   ├── core/       游戏状态、回合、战役、网格、胜负、日志
│   ├── units/      单位数据、单位实例和单位工厂
│   ├── movement/   四方向 A*、可达范围和移动执行
│   ├── combat/     视线、命中和伤害结算
│   ├── cards/      卡牌定义、牌库和效果执行
│   ├── ai/         北约规划逻辑
│   ├── levels/     关卡数据、建筑和编辑标记
│   └── ui/         菜单、卡牌、战报、地图与单位渲染
├── resources/      LevelData 和 TileSet 资源
├── assets/         运行时美术资源及素材源图
├── tests/          无头冒烟测试
└── tools/          素材处理与测试入口
```

## 关键流程

1. `MainMenu` 只展示实际存在 `.tscn` 的关卡。
2. `MainScene` 加载关卡场景，从 TileMap 提取地形、出生点、VP 和建筑占地。
3. `GameManager.start_level()` 重置跨场景单例并初始化网格。
4. `MainScene._on_level_started()` 生成单位、应用天气、准备手牌并注册事件。
5. `TurnManager` 驱动计划和演算；`CombatSystem`、`MovementSystem`、`NATOAI` 执行动作。
6. `VictoryManager` 提供即时胜负和 VP 统计的公共接口。

## 网格约定

- `GridManager` 使用四方向邻接和曼哈顿距离。
- `TilePathfinding` 是四方向 A*；源文件暂仍叫 `HexPathfinding.gd`。
- `HexGridRenderer.gd` 也是历史文件名，实际渲染等距四边形 TileMap。
- 逻辑坐标以关卡 `used_rect` 左上角归一化，显示坐标可由 `GridManager.grid_to_player_coordinate()` 转换。

## 存档

- 默认槽位为 `user://save_0.json`。
- 保存战役、EMI、士气、卡牌、回合和所有存活单位的动态状态。
- 主菜单读取存档后先建立关卡和网格，再由 `GameManager.apply_pending_save()` 恢复单位，避免恢复数据被关卡初始化覆盖。
- 新增存档字段时应保留默认值，并为旧版本数据提供兼容分支。

## 模块边界

- 外部模块不得调用以下划线开头的私有方法；胜负统计使用 `VictoryManager.get_vp_control()`，结束游戏使用 `finish_game()`。
- 新输入通过 `InputMap` 动作访问。默认动作由 `GameManager` 补齐，后续可接入键位设置界面。
- 新关卡内容优先使用 `.tres`/`.tscn` 数据，不继续扩大 `MainScene.gd` 和 `LevelDatabase.gd` 中的硬编码。
- `MainScene.gd` 仍承担较多协调职责；后续重构顺序为 HUD、输入/相机、关卡事件，且每次拆分后运行完整测试。

## 验证与发布

```powershell
python tools/run_tests.py
```

测试脚本要求出现 `[SMOKE TEST] PASS`，同时拒绝 `SCRIPT ERROR` 和测试失败标记。Windows 发布使用 `export_presets.cfg`；由于项目存在脚本动态加载资源，发布包导出全部运行时资源，并明确排除 `tests/`、`tools/`、文档和大尺寸素材源图。
