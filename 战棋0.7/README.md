# Silent Reckoning·1987 静默行动·1987

单位配置的完整开发者操作流程参见：[单位配置_README.md](单位配置_README.md)。

## 单位配置同步

单位属性的设计源文件位于 `res://config/source/unit_config.xlsx`。

修改Excel并保存后，在Godot顶部菜单选择“项目/Project → 工具/Tools → 同步单位配置（Excel → JSON）”。工具会生成 `res://data/units/unit_config.json`。游戏启动时，`UnitDatabase.gd`优先读取该JSON；如果文件缺失或格式错误，则回退到代码内置属性，不会阻止游戏启动。

不启动 Godot 时，也可以在项目根目录双击 `更新单位配置_Excel转JSON.cmd` 完成相同操作。运行前请保存并关闭 Excel，窗口显示“成功”后即可关闭。

Excel目前包含华约与北约23种单位，中立单位仍使用代码默认值。同步依赖Windows版Microsoft Excel；同步工具只创建并关闭自己的后台Excel进程，不会关闭用户已经打开的Excel或Godot。

## 玩家单位属性配置

- 主菜单选择“单位属性配置”，可调整双方单位的生命、弹药、攻击、装甲、穿透、命中率、射程、移动力和视野。
- 玩家修改以差异形式保存在 `user://unit_config_overrides.json`，不会改写项目内的 Excel 或官方 JSON。
- 修改在下一场战斗创建单位时生效；界面支持恢复当前单位默认值和全部恢复默认值。
- 属性输入设有安全范围，官方 Excel 始终作为可恢复的基准配置。

## 当前可玩内容

- 当前十关均可从关卡选择进入，并可在胜利后连续进入下一关；第1、2关已有专用场景，第3至第10关使用可替换的功能地图框架。
- 第1、2关开局采用两段式剧情弹窗：先显示「战前简报」剧情对话框，再显示「任务要求」提示框；显示期间会隐藏战斗UI，点击「下一步」/「开始行动」推进。第3至第10关仍使用传统任务简报面板。
- 第1关胜利结算显示旁白：「你守住了第一节车厢。但你已经听到铁轨在响。」第2关剧情已按《铁路线防御》大纲补齐开场、结算旁白、情报与分支对白。
- 核心循环：计划阶段给每支单位下达移动或指定攻击命令，并使用战术卡牌；演算阶段统一结算移动、攻击与自动接敌。
- 顶部行动顺序条与实际演绎共用敌我统一队列，按“配置表先手值 → 移动速度 → 单位ID”从左到右排列，因此同一回合内双方可交错行动；点击文字头像框可将镜头定位到对应单位。行动中显示金色脉冲，行动完成后勾选并变暗。
- 操作：左键选择己方单位；点击蓝格规划移动，点击红色敌军指定攻击；右键取消或弃牌，Enter 确认/结束计划，Tab 展开/收起卡牌，P 暂停，F11 全屏。
- 存档：游戏中按 P 暂停后可保存；主菜单“继续游戏”读取最近存档。
- 胜利：第8回合结束控制至少2个VP，或摧毁敌方指挥单位；己方指挥单位被毁或全军覆没则失败。

## 运行与导出

1. 使用 Godot 4.7 或兼容的 Godot 4.x 版本导入本目录的 `project.godot`。
2. 首次打开后等待资源导入完成，按 F6/F5 启动并完整进行一局。
3. 安装 Windows 导出模板后，选择“项目 → 导出 → Windows Desktop”。默认输出为 `builds/Silent_Reckoning_1987.exe`。

开发回归测试建议通过包装脚本执行；它会同时拦截 Godot 可能未反映到退出码中的脚本错误：

```powershell
python tools/run_tests.py
```

第3至第10关已具备独立20×12功能地图、双方部署、AI、EMI、卡牌、存档和胜负闭环；城市、密林、雪地、铁路及终局废墟目前使用占位地形，后续可直接替换TileMap与建筑素材。

## Godot 4.7.1 工程架构设计文档

---

## 一、项目总体架构

```
战棋0.5/
├── project.godot                    # Godot 项目配置文件
├── README.md                        # 本文件 — 架构总览
├── scripts/                         # 所有 GDScript 脚本
│   ├── core/                        # 游戏流程、网格、回合、战役等核心服务
│   │   ├── GameManager.gd           # 游戏主状态机
│   │   ├── GridManager.gd           # 四方向等距方格坐标系统
│   │   ├── TurnManager.gd           # 回合制管理（计划+沙盘）
│   │   ├── CampaignManager.gd       # 十关战役状态追踪
│   │   ├── EMISystem.gd             # 全频带阻塞干扰系统
│   │   └── MoraleSystem.gd          # 士气系统（昂扬→崩溃）
│   ├── units/                       # 单位系统
│   │   ├── UnitBase.gd              # 单位基类（所有战斗单位）
│   │   ├── UnitData.gd              # 单位数据资源类
│   │   └── UnitDatabase.gd          # 华约/北约单位数据库
│   ├── combat/                      # 战斗系统
│   │   ├── CombatSystem.gd          # 战斗结算（命中/伤害）
│   │   ├── LineOfSight.gd           # 视野/可视性计算
│   │   └── DamageCalculator.gd      # 伤害公式与修正
│   ├── movement/                    # 移动系统
│   │   ├── TilePathfinding.gd       # TilePathfinding 类（四方向A*）
│   │   └── MovementSystem.gd        # 移动范围与路径执行
│   ├── ai/                          # AI系统
│   │   ├── NATOAI.gd                # 北约AI控制器（5种倾向）
│   │   └── AIBehaviorType.gd        # AI行为枚举与配置
│   ├── cards/                       # 手牌系统
│   │   ├── CardSystem.gd            # 手牌管理（抽牌/弃牌/使用）
│   │   └── CardDatabase.gd          # 12张共享手牌定义
│   ├── ui/                          # 用户界面
│   │   ├── TileGridRenderer.gd      # 四边形等距网格渲染
│   │   ├── UnitRenderer.gd          # 单位视觉表现
│   │   └── CardUI.gd                # 手牌UI面板
│   └── levels/                      # 关卡系统
│       ├── LevelData.gd             # 关卡数据结构
│       └── LevelDatabase.gd         # 十关完整数据
├── scenes/                          # Godot场景文件（.tscn）
├── resources/                       # 资源文件（.tres）
└── assets/                          # 美术/音效资源
```

## 二、核心系统说明

### 2.1 四方向等距方格 (GridManager)
- 坐标系：关卡逻辑方格坐标 + TileMap 等距世界坐标
- 地图尺寸：40×45 (X:1-40, Y:1-45)
- 邻接规则：上、下、左、右四方向；距离使用曼哈顿距离
- 每个格子包含：地形类型、高度、控制方、可见性

### 2.2 回合制 (TurnManager)
- 每回合 = 60秒计划阶段 + 30秒沙盘演绎
- 双方同时规划、同时结算
- 回合计数器 + 事件触发器

### 2.3 EMI干扰 (EMISystem)
- 干扰强度 0%-100%
- 影响：电子设备效率、侦察范围、手牌可用性
- 10关时间线：0→60→80→80→70→100→40→30→100→0

### 2.4 AI系统 (NATOAI)
- 5种行为倾向：速胜/稳推/火力压制/集中突击/混乱
- 根据EMI强度和关卡进度切换
- 基于效用评估的决策树

## 三、版本控制建议
```
Git 仓库结构：
├── .gitignore          # 忽略.import/, .godot/, 用户数据
├── main               # 主开发分支
├── feature/combat     # 战斗功能分支
├── feature/ai         # AI功能分支
└── releases/v1.0      # 发布标签
```

## 四、Godot 4.7.1 关键API说明
- 所有脚本使用 GDScript 2.0 语法
- `class_name` 用于全局类型注册
- `@export` 用于编辑器可配置属性
- `Signal` 用于系统间解耦通信
- Autoload 管理跨场景服务；新增系统前应优先评估能否使用普通节点或资源，避免继续扩大全局状态
