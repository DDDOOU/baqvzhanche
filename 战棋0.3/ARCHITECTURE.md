# Silent Reckoning·1987 — 代码架构与脚本作用说明

## 工程概览

```
1.0/                                  (桌面文件夹)
├── project.godot                     # Godot 4.7.1 项目配置
├── .gitignore                        # Git版本控制忽略规则
├── README.md                         # 架构总览
├── ARCHITECTURE.md                   # 本文件 — 每个脚本的详细说明
│
├── scripts/
│   ├── MainScene.gd                  # 主场景（游戏入口）
│   │
│   ├── core/                         # 【6个全局单例】核心系统
│   │   ├── GameManager.gd            # 游戏主状态机
│   │   ├── GridManager.gd            # 六边形坐标网格
│   │   ├── TurnManager.gd            # 回合制管理
│   │   ├── CampaignManager.gd        # 战役状态追踪
│   │   ├── EMISystem.gd              # 电磁干扰
│   │   └── MoraleSystem.gd           # 士气系统
│   │
│   ├── units/                        # 单位系统
│   │   ├── UnitBase.gd               # 单位基类
│   │   ├── UnitData.gd               # 单位数据资源
│   │   └── UnitDatabase.gd           # 单位属性数据库
│   │
│   ├── combat/                       # 战斗系统
│   │   ├── CombatSystem.gd           # 战斗结算
│   │   ├── LineOfSight.gd            # 视线/视野
│   │   └── DamageCalculator.gd       # 伤害公式
│   │
│   ├── movement/                     # 移动系统
│   │   ├── HexPathfinding.gd         # A*六边形寻路
│   │   └── MovementSystem.gd         # 移动执行
│   │
│   ├── ai/                           # AI系统
│   │   ├── NATOAI.gd                 # 北约AI（5种行为）
│   │   └── AIBehaviorType.gd         # AI行为配置
│   │
│   ├── cards/                        # 手牌系统
│   │   ├── CardSystem.gd             # 手牌管理
│   │   └── CardDatabase.gd           # 12张卡牌数据
│   │
│   ├── ui/                           # UI渲染
│   │   ├── HexGridRenderer.gd        # 六边形网格渲染
│   │   ├── UnitRenderer.gd           # 单位视觉
│   │   └── CardUI.gd                 # 手牌UI面板
│   │
│   └── levels/                       # 关卡系统
│       ├── LevelData.gd              # 关卡数据结构
│       └── LevelDatabase.gd          # 10关完整数据
│
├── scenes/                           # .tscn场景文件（待创建）
├── resources/                        # .tres资源文件（待创建）
└── assets/                           # 美术/音效资源
```

---

## 每个脚本的详细作用

### 一、核心系统 (scripts/core/)

#### 1. GameManager.gd — 游戏主状态机 (Autoload)
| 项目 | 说明 |
|------|------|
| **作用** | 管理游戏整体生命周期，9种状态（BOOT→MAIN_MENU→...→VICTORY/DEFEAT） |
| **计时器** | 60秒计划阶段 + 30秒沙盘演绎的倒计时 |
| **存档** | `save_game(slot)` / `load_game(slot)` — JSON存档系统 |
| **Bug追踪** | `log_bug()` / `fix_bug()` — 内建Bug记录系统 |
| **版本控制** | `version`/`build_number` 属性，存档中包含版本号 |

#### 2. GridManager.gd — 六边形网格坐标系统 (Autoload)
| 项目 | 说明 |
|------|------|
| **坐标系统** | 三种坐标互转：Offset(col,row) ↔ Cube(q,r,s) ↔ World(x,y) |
| **六边形类型** | Flat-top hex（平边朝上） |
| **地图尺寸** | 40×45 (X:1-40, Y:1-45) |
| **9种地形** | 平原/城市/山地/密林/河流/公路/铁路/桥梁/沼泽 — 每种有move_cost/defense/concealment/height |
| **邻居查询** | `get_neighbors()` — 偶数行/奇数行偏移不同 |
| **距离计算** | `hex_distance()` — 六边形曼哈顿距离 |
| **范围查询** | `get_cells_in_range()` / `get_cells_in_ring()` |
| **高低差** | `get_height_difference()` — 影响攻击和移动 |
| **特殊标记** | VP格/华约出生点/北约出生点/未知接触 |

#### 3. TurnManager.gd — 回合制管理 (Autoload)
| 项目 | 说明 |
|------|------|
| **WEGO系统** | 双方同时规划、同时结算 |
| **指令存储** | `player_orders` / `ai_orders` — 分阵营存储 |
| **执行优先级** | 按单位速度排序执行 |
| **事件系统** | `register_turn_event()` / `_trigger_turn_events()` — 回合事件触发 |
| **回合结算** | 持续效果→士气→EMI→事件→清理 |

#### 4. CampaignManager.gd — 战役状态 (Autoload)
| 项目 | 说明 |
|------|------|
| **累计指标** | 士气(0-100)、误伤(0-100%)、贷款(0-50)、击杀数 |
| **三幕结构** | 自动根据已通关卡数切换 |
| **终局判定** | `get_final_result()` — 4种结局（战略胜利/惨胜/失守/坐标归零） |
| **米沙追踪** | `misha_alive` / `misha_morale` — 影响终局 |
| **跨关传递** | 预备队、直升机击杀数、平民伤亡 — 影响下一关 |

#### 5. EMISystem.gd — 电磁干扰系统 (Autoload)
| 项目 | 说明 |
|------|------|
| **10关时间线** | 0%→0%→60%→80%→80%→70%→100%→40%→30%→100%→0% |
| **第10关曲线** | 每回合动态变化：1.0→0.80→0.70→...→0.0 |
| **效果修正** | 电子设备效率-80%、侦察范围-4格、命中-50%、手牌乱码40% |
| **临时修正** | `add_temp_modifier()` — 手牌（电磁反制）影响 |
| **状态信号** | `intensity_changed` / `card_scrambled` |

#### 6. MoraleSystem.gd — 士气系统 (Autoload)
| 项目 | 说明 |
|------|------|
| **四档判定** | 昂扬(75+): 命中+10%、稳定(50-74): 无修正、动摇(25-49): 命中-10%防御-10%、崩溃(0-24): 命中-25%+溃逃 |
| **误伤惩罚** | `apply_friendly_fire_penalty()` — -15士气 |
| **平民惩罚** | `apply_civilian_casualty_penalty()` — -20士气 |
| **自然恢复** | 崩溃5%/回合、动摇10%/回合概率恢复 |
| **溃逃判定** | `check_flee()` — 崩溃20%概率溃逃 |

---

### 二、单位系统 (scripts/units/)

#### 7. UnitBase.gd — 单位基类
| 项目 | 说明 |
|------|------|
| **两个阵营** | WARSAW_PACT (华约/玩家) / NATO (北约/AI) |
| **17种单位类型** | 从步兵班到AH-64直升机 |
| **属性** | 生命、弹药、攻击力、装甲、穿透、命中率、射程、移动点数、视野 |
| **移动** | `can_move_to()` / `get_effective_movement()` / 地形通行性 |
| **攻击** | `can_attack_target()` / `get_effective_range()` / 高地+1射程 |
| **伤害** | `take_damage()` — 装甲减伤公式: damage × (1 - armor/200) |
| **侧后装甲** | `is_side_armor()` — 坦克2×2单位的方向判定 |
| **运输** | `embarked_unit` — BMP-2可搭载1个步兵班 |

#### 8. UnitData.gd — 单位数据Resource
| 项目 | 说明 |
|------|------|
| **类型** | Godot Resource (.tres) — 可在编辑器中可视化配置 |
| **装甲分区** | armor_front / armor_side / armor_rear — 三面不同 |
| **面杀伤** | area_effect_radius — BM-21火箭炮面杀伤扩散 |
| **造价** | deployment_cost — 战役资源计量 |

#### 9. UnitDatabase.gd — 单位属性数据库
| 项目 | 说明 |
|------|------|
| **华约10种** | 步兵班/摩托化步兵/T-72B/BMP-2/BM-21/SA-13/侦察连/工兵/指挥组/预备队 |
| **北约6种** | M1A1/M2/机械化步兵/AH-64/工兵 |
| **中立2种** | 平民车队/未知接触 |
| **工厂方法** | `create_unit()` — 自动分配ID、设置属性、初始化士气 |
| **ID生成** | `generate_unit_id()` — 自增唯一ID |

---

### 三、战斗系统 (scripts/combat/)

#### 10. CombatSystem.gd — 战斗结算 (Autoload)
| 项目 | 说明 |
|------|------|
| **6种攻击** | 直射/间射/盲射/面轰炸/防空/近战突击 |
| **命中公式** | 基础命中 + 高度差(每级+5%) - 距离衰减(每格-3%) - 隐蔽 - 烟雾 |
| **伤害公式** | 基础伤害 × 高度加成(+10%/级) × 侧后加成(+35%) × 穿甲加成(+20%) × 克制 |
| **盲射系统** | `execute_blind_fire()` — 3×3范围无差别射击 |
| **面杀伤** | `execute_area_attack()` — BM-21/呼叫炮击 |
| **烟雾** | `apply_smoke()` / `tick_smoke()` — 命中-40% |
| **误伤检测** | 自动检查目标是否友军/平民 |

#### 11. LineOfSight.gd — 视线系统
| 项目 | 说明 |
|------|------|
| **射线追踪** | 六边形Bresenham算法 `_hex_line()` — 立方体坐标线性插值 |
| **5种阻挡** | 山地(完全)/密林(70%)/高度/城市(80%)/烟雾(完全) |
| **可视范围** | `get_visible_cells()` — 结合EMI、地形、单位视野 |
| **高地加成** | 高度3→+2视野, 高度2→+1视野 |
| **迷雾** | LOS结果包含visibility字段(0-1) |

#### 12. DamageCalculator.gd — 伤害公式
| 项目 | 说明 |
|------|------|
| **基础公式** | `damage = attack_power × (1 - armor/(armor+50)) × penetration_factor` |
| **击穿加成** | 穿透>装甲时，额外+30% |
| **暴击** | 命中>85%时溢出部分×50%为暴击率，伤害1.5-2.0倍 |
| **克制表** | SA-13 vs AH-64: +50%、步兵vs坦克: +40%、BMP-2 vs步兵: +25% |
| **衰减** | 面杀伤随距离衰减至40% |

---

### 四、移动系统 (scripts/movement/)

#### 13. HexPathfinding.gd — A*六边形寻路
| 项目 | 说明 |
|------|------|
| **算法** | 标准A*+六边形曼哈顿启发式 |
| **代价** | 地形移动消耗 + 高度差上坡惩罚 |
| **通行性** | 装甲不可过河流/山地 |
| **部分路径** | 超出移动范围时返回最近路径 |
| **可移动范围** | Dijkstra扩散算法 `get_reachable_cells()` |
| **最大代价** | max_cost参数限制（如稳推AI只走半步） |

#### 14. MovementSystem.gd — 移动执行 (Autoload)
| 项目 | 说明 |
|------|------|
| **逐格移动** | `execute_move()` — 扣移动点、检测雷区、更新位置 |
| **路径验证** | `validate_path()` — 检查相邻性+通行性+消耗 |
| **雷区** | `lay_mines()` / `clear_mines()` / 触雷减速1回合 |
| **辙印** | 雪地移动后暴露位置（第8关机制） |
| **动画** | `_animate_step()` — Tween移动动画 |

---

### 五、AI系统 (scripts/ai/)

#### 15. NATOAI.gd — 北约AI (Autoload)
| 项目 | 说明 |
|------|------|
| **5种行为** | 速胜(抢VP)→稳推(保持阵型)→火力压制(盲射)→集中突击(集火)→混乱(随机) |
| **自动切换** | 根据关卡ID、回合数、EMI强度自动切换 |
| **情报收集** | `_gather_intel()` — 扫描可视范围内的玩家单位 |
| **优先目标** | 指挥中心 > T-72B坦克 > 任何可见华约单位 |
| **每回合规划** | `plan_turn()` → 行为调度 → 提交AI指令到TurnManager |

#### 16. AIBehaviorType.gd — AI行为配置
| 项目 | 说明 |
|------|------|
| **行为参数** | aggressiveness/risk_tolerance/vp_priority/use_blind_fire/focus_fire |
| **效用评估** | `evaluate_action_score()` — 攻击/占点/近敌/待命/撤退评分 |
| **难度调节** | easy: -15%命中, hard: +10%命中+侧翼意识 |

---

### 六、手牌系统 (scripts/cards/)

#### 17. CardSystem.gd — 手牌管理 (Autoload)
| 项目 | 说明 |
|------|------|
| **12张卡牌** | 坐标预判/盲射弹幕/烟雾遮障/呼叫炮击/阵地加固/电磁反制/无线电静默/预备队投入/工兵布雷/牺牲冲锋/断电/战报谎言 |
| **手牌上限** | 6张，每回合自动抽1张 |
| **冷却** | 呼叫炮击3回合、预备队投入3回合、断电2回合 |
| **指挥贷款** | `activate_loan()` — 透支1张，下回合-1 |
| **乱码** | EMI干扰下手牌随机变为乱码卡(掷骰:1-3正面/4-6负面) |
| **坐标预判Buff** | 指定格本回合+30%命中 |

#### 18. CardDatabase.gd — 卡牌数据
| 项目 | 说明 |
|------|------|
| **全部12张** | 完整属性：id/name/cost/cooldown/description/type/rarity |
| **10关配置** | `LEVEL_STARTING_HANDS` — 每关起始手牌ID列表 |

---

### 七、UI系统 (scripts/ui/)

#### 19. HexGridRenderer.gd — 网格渲染
| 项目 | 说明 |
|------|------|
| **绘制方式** | Godot `_draw()` + `draw_polygon()` / `draw_polyline()` |
| **9种地形色** | 草绿/深灰/灰棕/深绿/蓝/土黄/棕灰/棕色/暗绿 |
| **4种标记** | VP格(橙色十字)/出生点(蓝/红圆圈)/未知接触(黄色问号) |
| **高亮** | 可移动(蓝色)/可攻击(红色)/选中(黄色)/路径(绿色) |
| **坐标显示** | 缩放>0.4时显示"X,Y"标签 |
| **战争迷雾** | 未探索格黑色覆盖，已探索但不可见格暗化 |
| **点击检测** | `get_cell_at_screen_pos()` — 屏幕坐标→六边形格 |

#### 20. UnitRenderer.gd — 单位渲染
| 项目 | 说明 |
|------|------|
| **阵营色** | 华约蓝/北约红 |
| **生命条** | 绿(>50%)/橙(25-50%)/红(<25%) |
| **士气点** | 金/白/橙/红色小圆点 |
| **方向箭头** | 2×2坦克单位的正面朝向 |
| **选中** | 黄色虚线框+外发光 |

#### 21. CardUI.gd — 手牌UI
| 项目 | 说明 |
|------|------|
| **卡牌尺寸** | 160×220px，排列在屏幕底部 |
| **颜色分类** | 攻击(红)/防御(蓝)/特殊(紫)/乱码(灰) |
| **交互** | 点击选中→点击地图使用 / Tab切换面板 |
| **显示** | 名称、消耗(✚)、效果描述、冷却回合、乱码标记(?) |

---

### 八、关卡系统 (scripts/levels/)

#### 22. LevelData.gd — 关卡数据Resource
| 项目 | 说明 |
|------|------|
| **11个字段** | 对应设计文档的「章节定位→特殊事件」 |
| **完整数据** | 地图、VP格、出生点、单位配置、手牌、回合事件、情报、分支 |
| **编辑器可用** | `@export` 全部字段可在Godot资源面板配置 |

#### 23. LevelDatabase.gd — 10关数据
| 项目 | 说明 |
|------|------|
| **第1关** | 边境晨雾 — 教学关，晨雾3回合，AH-64进场 |
| **第2关** | 铁路线防御 — 桥梁控制，指挥贷款 |
| **第3关** | 第一轮洪水 — EMI 60%，乱码手牌，火力压制 |
| **第4关** | 林地误击 — 未知接触×3，误伤惩罚 |
| **第5关** | 预备队投入 — 长线规划 |
| **第6关** | 断桥反击 — 米沙救援，炸桥决策 |
| **第7关** | 全频段窒息 — EMI 100%，完全信息真空 |
| **第8关** | 白色走廊 — 大雪，辙印暴露 |
| **第9关** | 红色轨道 — 集中突击，装甲列车 |
| **第10关** | 坐标归零 — 终局，EMI 100%→0% |

---

## 九、版本控制策略

### Git分支策略
```
main              → 稳定版本
develop           → 开发主线
feature/combat    → 战斗系统开发
feature/ai        → AI系统开发
feature/ui        → UI系统开发
bugfix/*          → Bug修复
releases/v1.0     → 发布标签
```

### .gitignore 配置
- 忽略 `.godot/` (Godot编辑器缓存)
- 忽略 `*.import` (导入资源缓存)
- 忽略 `export/` (导出构建)
- 忽略 `user://` (用户存档数据)

### 存档系统
- 格式：JSON
- 位置：`user://save_{slot}.json`
- 包含：版本号、关卡、回合、战役状态、EMI、士气、手牌

---

## 十、Bug追踪框架

GameManager 内建了Bug追踪系统：

```gdscript
# 记录Bug
GameManager.log_bug("BUG-001", "A*寻路在山地地形陷入死循环")

# 修复Bug
GameManager.fix_bug("BUG-001")
# → 自动记录修复版本号
```

Bug记录包含：描述、状态(open/fixed)、发现版本、修复版本、时间戳。

---

## 十一、Godot 4.7.1 关键API使用

| API | 用途 |
|-----|------|
| `@export` | 编辑器可配置属性（UnitData, LevelData） |
| `Signal` | 系统间解耦通信（所有Autoload） |
| `class_name` | 全局类型注册（UnitBase, HexPathfinding等） |
| `FileAccess` | 存档读写（GameManager） |
| `Resource` | 数据容器（UnitData, LevelData） |
| `_draw()` | 自定义渲染（HexGridRenderer, UnitRenderer） |
| `Tween` | 移动动画（MovementSystem） |
| `get_tree().get_nodes_in_group()` | 单位查询 |
| `Engine.get_main_loop()` | 跨场景访问Autoload |

---

## 十二、下一步实现建议

1. **在 Godot 4.7.1 中新建项目**，将 `project.godot` 放入项目根目录
2. **创建 MainScene.tscn**，挂载 `MainScene.gd`
3. **配置 Autoload**（project.godot中已配置好10个单例）
4. **创建场景节点**：HexGridRenderer、UnitRenderer、CardUI、Camera2D
5. **导入资源**：地形贴图、单位图标、音效
6. **运行调试**：从第1关开始逐关测试
