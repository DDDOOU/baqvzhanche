# Silent Reckoning·1987 静默行动·1987

## Godot 4.7.1 工程架构设计文档

---

## 一、项目总体架构

```
1.0/
├── project.godot                    # Godot 项目配置文件
├── README.md                        # 本文件 — 架构总览
├── scripts/                         # 所有 GDScript 脚本
│   ├── core/                        # 核心系统（6个全局单例）
│   │   ├── GameManager.gd           # 游戏主状态机
│   │   ├── GridManager.gd           # 六边形网格坐标系统
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
│   │   ├── HexPathfinding.gd        # 六边形A*寻路
│   │   └── MovementSystem.gd        # 移动范围与路径执行
│   ├── ai/                          # AI系统
│   │   ├── NATOAI.gd                # 北约AI控制器（5种倾向）
│   │   └── AIBehaviorType.gd        # AI行为枚举与配置
│   ├── cards/                       # 手牌系统
│   │   ├── CardSystem.gd            # 手牌管理（抽牌/弃牌/使用）
│   │   └── CardDatabase.gd          # 12张共享手牌定义
│   ├── ui/                          # 用户界面
│   │   ├── HexGridRenderer.gd       # 六边形网格渲染
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

### 2.1 六边形网格 (GridManager)
- 坐标系：偏移坐标(Offset) + 立方体坐标(Cube)双系统
- 地图尺寸：40×45 (X:1-40, Y:1-45)
- 六边形平边朝向（Flat-top hex）
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
- Autoload 单例模式管理6个核心系统
