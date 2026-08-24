# Silent Reckoning·1987 工程架构

> 当前版本：0.6.0（build 7）。本文以实际运行代码为准；早期"六边形网格"设计已被四方向等距方格替代，相关脚本文件名已统一为 `Tile`。

## 运行边界

- Godot 4.7.1，主入口为 `scenes/MainMenu.tscn`。
- 十关全部可玩：第 1 关手绘地形（`level_01.tscn`，40×45），第 2 关 `Level02Builder.gd` 铁路防御，第 3～10 关由 `ProceduralLevelBuilder.gd` 程序化生成（8 种主题：洪水/森林/防御/断桥/停电/雪原/铁路/决战，含河流、桥梁、道路参数）。
- 回合循环为计划阶段（60s）、统一演算（30s）、回合结算；即时胜负由指挥单位和全歼条件触发，第八回合再结算 VP。
- 主开发目录为 `战棋0.5.2/`（0.5 起为正式主线；`战棋/`、`战棋0.1`~`战棋0.5` 为历史版本，仅供回溯）。

## 目录职责

```text
战棋0.5.2/
├── project.godot
├── export_presets.cfg
├── scenes/
│   ├── MainMenu.tscn
│   ├── MainScene.tscn
│   ├── buildings/      建筑预制体（基础设施/工事）
│   └── levels/level_01~10.tscn
├── scripts/
│   ├── core/       游戏状态、回合、战役、网格、胜负、EMI、日志
│   ├── units/      单位数据、单位实例和单位工厂（UnitBase/UnitDatabase）
│   ├── movement/   四方向 A*、可达范围和移动执行、雷区
│   ├── combat/     视线、命中、伤害结算（DamageCalculator 为唯一公式权威）
│   ├── cards/      卡牌定义、牌库、指挥点与效果执行
│   ├── ai/         北约规划逻辑（行为数据驱动）
│   ├── levels/     关卡数据、程序化地形、建筑和编辑标记
│   └── ui/         菜单、卡牌、战报、简报、无线电对话、地图与单位渲染
├── resources/      LevelData 和 TileSet 资源
├── assets/         运行时美术资源及素材源图
├── tests/          无头冒烟测试（6 套，含卡牌专项）
└── tools/          素材处理与测试入口
```

## 关键流程

1. `MainMenu` 只展示实际存在 `.tscn` 的关卡，可读取存档槽。
2. `MainScene` 加载关卡场景，从 TileMap 提取地形、出生点、VP 和建筑占地。
3. `GameManager.start_level()` 重置跨场景单例并初始化网格。
4. `MainScene._on_level_started()` 生成单位、应用天气、准备手牌、挂载无线电对话 UI 并注册事件。
5. `TurnManager` 驱动计划和演算；`CombatSystem`、`MovementSystem`、`NATOAI` 执行动作；回合结算做弹药补给（指挥中心半径内全额、其余半额）。
6. `VictoryManager` 提供即时胜负和 VP 统计的公共接口；`CampaignManager` 累计战役士气/误伤/贷款/击杀（含直升机击杀与指挥单位阵亡惩罚）。

## 网格约定

- `GridManager` 使用四方向邻接和曼哈顿距离。
- `TilePathfinding.gd` 实现四方向 A*（规划/高亮/执行三处高度差成本一致：上坡 +1/级）。
- `TileGridRenderer.gd` 负责渲染等距四边形 TileMap，并绘制卡牌范围/战报谎言假接触标记。
- 逻辑坐标以关卡 `used_rect` 左上角归一化，显示坐标可由 `GridManager.grid_to_player_coordinate()` 转换。

## 战斗系统（0.6.0 统一口径）

- 伤害公式唯一权威：`DamageCalculator.calculate_full_damage()`。包含基础公式（装甲减伤 `armor/(armor+50)`、穿透击穿加成）、高度差修正、侧/后装甲（`ArmorAspect` FRONT/SIDE/REAR：侧面装甲×0.55 伤害×1.35，后方×0.35 伤害×1.50）、面杀伤 ×0.75、克制加成。`take_damage` 只做纯扣血（原 armor/200 二次减伤已移除）。
- 炮兵面杀伤：`area_effect_radius>0` 的单位（BM21/GVOZDIKA/M109）直射自动转为方形范围齐射，一次攻击消耗一发弹药。
- 近战反击：直射命中后若双方相邻，目标对攻击方执行一次 CLOSE_ASSAULT 反击（`is_counter` 防递归）。
- 卡牌伤害（盲射/炮击）同样走 DamageCalculator 装甲减伤，与直射统一。

## 卡牌与指挥点（0.6.0 实装）

- 12 张共享手牌定义于 `CardDatabase`；每关起始手牌按 `LEVEL_STARTING_HANDS` 配置。
- **指挥点**：每回合 5 点（`MAX_COMMAND_POINTS`），出牌消耗对应 cost，不结转；`CardUI` 帮助栏实时显示。
- 出牌限定 PLANNING_PHASE（use_card 与弃牌均有状态门禁）。
- buff 卡（坐标预判/阵地加固/牺牲冲锋/断电）出牌即时写入 buff 表；伤害/区域卡（盲射/炮击）演绎阶段结算；烟雾即时施放持续 2 回合。
- 乱码卡掷骰 1-3 正面 / 4-6 负面效果池；战报谎言生成假接触标记（地图 "?"）；无线电静默期间己方无法下令。

## AI（0.6.0 数据驱动）

- 行为倾向以 `LevelData.nato_ai_behavior` 为唯一权威，`behavior_switches` 支持按回合演进（如第2关第6回合后转火力压制）。
- EMI≥90% 时有 50% 概率切混乱（动态覆盖层）。
- 盲射限射程×1.5 且弹药≥2；集中突击下单前 `can_attack_target` 预校验（含视线）。

## 存档

- 默认槽位为 `user://save_0.json`；结构版本 `SAVE_VERSION=2` 严格校验，不兼容存档拒绝加载。
- 保存战役、EMI、士气、卡牌（含指挥点/假接触/pending/buff）、雷区、烟雾、回合和所有存活单位的动态状态。
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

测试脚本要求出现全部 PASS 标记（UNIT CONFIG 6 / PLAYER 10 / SMOKE 49 / CARD SYSTEM 17 / LEVEL 02 14 / CAMPAIGN 61 = 157 checks），同时拒绝 `SCRIPT ERROR` 和测试失败标记。Windows 发布使用 `export_presets.cfg`；由于项目存在脚本动态加载资源，发布包导出全部运行时资源，并明确排除 `tests/`、`tools/`、文档和大尺寸素材源图。
