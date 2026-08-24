# BUG 待办清单（三轮审计遗留）

> 维护规则：每项含 [优先级] 文件:位置 - 问题（根因 / 建议）。修复后勾选并注明版本。
> 优先级：P0 崩溃/数据丢失（当前无未修的）｜P1 机制错误或失效｜P2 机制缺失｜P3 代码质量/平衡
> 来源：2026-08-11 三轮并行审计（0.5.7 回归 / 战斗经济 / 数据配置）+ E2E 端到端实测

## P1 机制错误或失效（批 B，建议优先）

- [x] [P1] EMISystem.gd:133-137 - **EMI 卡效果延迟一回合**：add_temp_modifier 只改 temp_modifier/duration 不重算 current_intensity（重算只在 tick_turn/set_level）→ 计划阶段用「电磁反制」本回合演绎阶段不生效。（建议：施加时调 _update_modifiers()）→ 已修（0.6.0：施加即重算+刷新+战报）
- [x] [P1] EMISystem.gd:72-75 - **EMI 临时修正时长少 1 回合**：tick_turn 开头即减 duration，「持续2回合」实际 1.x 回合。（建议：结算末尾衰减或改语义）→ 已修（0.6.0：先重算后衰减）
- [x] [P1] EMISystem.gd:151-155 + CardDatabase.gd:58-65 - **电磁反制卡方向矛盾**：卡牌执行 EMI+10%（自损）而 apply_countermeasure（降 EMI）是死代码，卡名与效果相反。（建议：定设计意图，二选一）→ 已修（0.6.0：按卡名语义降 EMI 10%，用户拍板）
- [x] [P1] CardSystem.gd:161-187 - **卡牌使用无状态门禁**：演绎阶段卡牌面板仍可用，延迟卡入 pending 但 resolve 已过 → 效果永久丢失。（建议：use_card 加 PLANNING 校验）→ 已修（0.6.0：use_card/弃牌均限 PLANNING + orders_locked）
- [x] [P1] CombatSystem.gd:88-98 - **误伤/平民惩罚在命中判定前触发**：对友军/平民开火即使落空也扣 -15/-20 士气、累计误伤/平民数。（建议：判定移到命中后，或明确"开火即事件"改文案）→ 已修（0.6.0：惩罚移到命中确认后，落空不再扣士气）
- [x] [P1] NATOAI.gd:252-269 - **AI 盲射无射程/弹药检查**：全图任意格 BLIND_FIRE，弹药可为负（execute_attack:125 无 maxi）。（建议：盲射限射程×1.5 + ammo 检查 + maxi(0)）→ 已修（0.6.0：_can_blind_fire_at 射程×1.5 + 弹药<2 转稳推/待命 + ammo maxi(0)）
- [x] [P1] NATOAI.gd:295-300 - **AI 集中突击无 LOS 校验**：隔山/隔城提交攻击 → 演绎 invalid_target 扣弹落空整回合无效。（建议：下单前 can_attack_target 预校验，不过改移动）→ 已修（0.6.0：can_attack_target 预校验，失败改移动/稳推）
- [x] [P1] LevelDatabase.gd:351-354 - **第5关预备队死数据**：wp_reserve_units（T72+步兵 turn4）无任何消费方，该关无 turn_events。（建议：补 reserve_ready 事件或删死数据）→ 已修（0.6.0：补 reserve_ready 事件 + MainScene 生成预备队单位）
- [x] [P1] LevelDatabase.gd:148 等10处 - **nato_ai_behavior 零消费**：AI 行为由 NATOAI 硬编码 level_id/turn 重算，数据声明（如第6关 SPEED_RUSH）与实际（FIRE_SUPPRESSION）不符。（建议：_update_behavior 以 DB 为基准）→ 已修（0.6.0：_update_behavior 以 DB 声明为权威，仅保留 EMI 混乱覆盖）
- [x] [P1] CardSystem.gd:317-328 - **乱码卡效果空实现**：掷骰后只 print，正/负效果分支为空。（建议：补随机 buff/debuff 池）→ 已修（0.6.0：1-3 正面/4-6 负面效果池）
- [x] [P1] CardSystem.gd:311-314 - **战报谎言卡无效果**：只有战报日志，描述"情报+1个虚假单位"未实现。（建议：实现假接触标记或暂时移出起始手牌）→ 已修（0.6.0：false_report_cells + "?" 标记绘制 + 入档）
- [x] [P1] CardDatabase.gd:85-92 - **工兵布雷描述 1×2 vs 实现单格**：lay_mines 只布 1 个雷。（建议：做 2 格或改描述）→ 已修（0.6.0：目标格+右侧格双格）
- [x] [P1] CardDatabase.gd:26 - **盲射弹幕"无差别"描述 vs 实现跳过己方**：描述可能误伤，实现 continue 跳过华约。（建议：改描述或按设计实现误伤）→ 已修（0.6.0：描述改为"可能误伤平民"）
- [x] [P1] GridManager.gd:194-201 vs CardSystem.gd:414-415 - **卡牌范围形状不一致**：曼哈顿菱形 vs 方形（3×3/4×4 描述不符）。（建议：统一为方形）→ 已修（0.6.0：get_cells_in_square，盲射/炮击/烟雾统一方形）
- [x] [P1] CardSystem.gd:361-370 - **阵地加固"不能移动"延迟路径失效**：DEFERRED 结算在移动之后，remaining_movement=0 无影响且下回合重置。（建议：改即时卡或演绎开始前检查）→ 已修（0.6.0：buff 卡全部即时生效）
- [x] [P1] CardDatabase.gd:35 - **烟雾卡时点与描述不符**：描述"下回合命中-40%"，实际本回合演绎施放、回合末清除。（建议：改文案或改时点）→ 已修（0.6.0：即时施放 duration=2，描述同步）
- [x] [P1] CardSystem.gd:656-671 - **存档缺 pending/buff 状态**：计划阶段标记的延迟卡/buff（prediction/fortify/sacrifice）读档丢失。（建议：serialize 补齐）→ 已修（0.6.0：+false_report/pending/prediction/fortify/sacrifice）
- [ ] [P1] GameManager.gd:400-412 - **存档 version 不校验**：任何结构 JSON 含 level+units 即接受，跨版本格式静默错读。（建议：校验 version + 迁移分支）

## P2 机制缺失（批 C）

- [x] [P2] DamageCalculator.gd 全文件 - **伤害公式三套并存**：DamageCalculator（暴击/克制/盲射/后方加成）零调用；CombatSystem 内联公式与 take_damage armor/200 另两套口径。（建议：统一走 calculate_full_damage 或删死代码）→ 已修（0.6.0：DamageCalculator 成为唯一权威，CombatSystem 调用，take_damage 二次减伤移除）
- [x] [P2] DamageCalculator.gd:31-32 - **armor=0 除零**（接入前必修）：pen_factor 分母 armor，平民 armor=0 → INF 伤害。（建议：denom=maxf(armor,1.0)）→ 已修（0.6.0：denom=maxf(armor,1.0)）
- [x] [P2] UnitBase.gd:257-267 + CombatSystem.gd:256-262 - **侧/后判定丢失**：is_side_armor 返回 bool 无方向，后方 +50% 加成不存在，装甲 0.55/0.35 折算未生效。（建议：返回 FRONT/SIDE/REAR 枚举）→ 已修（0.6.0：get_armor_aspect 枚举，侧×1.35/后×1.50 生效）
- [x] [P2] UnitDatabase.gd:44-51 - **面杀伤未实现**：BM21(3)/GVOZDIKA(2)/M109(2) area_effect 无消费者，炮兵按直射单目标。（建议：攻击接入 execute_area_attack）→ 已修（0.6.0：area_effect_radius>0 自动转方形齐射）
- [x] [P2] CombatSystem.gd - **近战/反击（CLOSE_ASSAULT）未实现**：枚举存在无逻辑，攻击者不会受反击/死亡。（建议：贴脸判定 + 反击回调）→ 已修（0.6.0：贴脸命中后目标自动反击，is_counter 防递归）
- [x] [P2] CampaignManager.gd - **指挥单位阵亡无士气惩罚**：unit_destroyed 监听中 is_command → 同阵营 -10~15 未实现。（建议：补监听）→ 已修（0.6.0：指挥单位阵亡战役士气 -10）
- [x] [P2] CampaignManager.gd:93 - **直升机击杀统计恒 0**：result 无 heli_kills 字段，helicopter_shot_down 信号只进战报。（建议：结算统计写入 result）→ 已修（0.6.0：关卡级 _level_heli_kills 写入 result）
- [x] [P2] 弹药系统 - **无补给机制**：打完即废（T72 40 发），resupply 指令空实现。（建议：实现补给车/回合自动补充，或改每回合开火次数）→ 已修（0.6.0：回合结算自动补弹，指挥中心半径内全额其余50%）
- [x] [P2] TurnManager.gd:163-164 - **WEGO 速度排序失效**：move_speed 恒 1.0（数据库无字段）。（建议：补 speed 字段）→ 已修（0.6.0：25 单位补全 move_speed）
- [x] [P2] MovementSystem.gd:75-83 - **触雷幸存者重复处理同格**：set_grid_position/unit_step/steps_completed 二次执行。（建议：触雷分支统一 break）→ 已修（0.6.0：统一 break）
- [ ] [P2] 空中单位 - **AH-64 直升机无机制差异化**：无高度/弹药挂载/无法被地面近战等特殊规则（除防空加成）。→ 已修（0.6.0：可越河越山 + 地面近战不反击）

## P3 代码质量 / 平衡 / 数据

- [ ] [P3] 死代码群清理（接入或删除）：AIBehaviorType、UnitData（资源类）、GameManager._on_level_end、TurnManager._execute_orders/_execute_single_order、CardSystem.execute_card 死路径、UnitRenderer.UNIT_SHAPES、EMISystem.try_scramble_card/get_visible_cells、NATOAI.share_intel（DamageCalculator 已转正接入，MovementSystem.validate_path 已删除，EMISystem.apply_countermeasure 已激活）→ 已修（0.6.0：AIBehaviorType/UnitData 文件删除，_on_level_end/UNIT_SHAPES/try_scramble_card/get_visible_cells/share_intel 删除；execute_card 保留——TurnManager use_card 路径在用）
- [x] [P3] project.godot - **输入映射双轨**：6 个动作（camera/pause/fullscreen）运行时补建未入配置；配置的 5 个动作（ui_click_left 等）零消费；plan_cancel events 含 null 元素。→ 已修（0.6.0：代码消费配置动作 plan_confirm/plan_cancel/toggle_card_panel，运行时补建兜底，plan_cancel null 移除）
- [x] [P3] 注释乱码 - 部分文件 GBK/UTF-8 混用（CardUI.gd:6 等），统一 UTF-8。→ 已修（0.6.0：CardUI.gd 4 处 + MainScene.gd 1 处）
- [x] [P3] UnitDatabase 字段无消费者：anti_air_bonus（SA13/ZSU23，现硬编码 +0.15/×1.4）、command_radius（指挥鼓舞硬编码距离≤2）、transport_capacity（搭载流程）、can_destroy_bridge、AH64 can_cross_river/mountain。→ 已修（0.6.0：anti_air_bonus 数据化、command_radius 补给用、搭载系统、炸桥指令、直升机越地形）
- [x] [P3] 平衡 - 初始士气 70 后受创扣减上限 10 vs rally +15/回合：崩溃单位 1 回合回动摇 2 回合回稳定，受创追不上。建议 rally +10 或加条件。→ 已修（0.6.0：rally +15→+10）
- [ ] [P3] UnitBase 多格单位视觉重叠 - T72(4,7) 2×2 与步兵/碉堡占地重叠（引擎按锚点判占用无功能冲突，美术迭代错开）。
- [ ] [P3] HexPathfinding.gd:81-83 vs MovementSystem - 高度差成本不一致：寻路上坡 +1/级，执行不扣 → 执行比 UI 宽松。（已核实：TilePathfinding/MovementSystem 三处成本一致，清单引用旧 Hex 文件名）
- [ ] [P3] HexPathfinding.gd:30-36 - find_path 终点不检查占用（AI 追敌最后一步进敌占格，blocked 停在相邻格）。（已核实：TilePathfinding.find_path 已检查占用，清单引用旧 Hex 文件名）
- [ ] [P3] UnitBase.take_damage - 无 is_alive 防御（死亡后再受伤重复走 _on_death）。（已修 0.6.0：take_damage 补 is_alive 防御）
- [x] [P3] 平衡 - 初始士气 70 后受创扣减上限 10 vs rally +15/回合：崩溃单位 1 回合回动摇 2 回合回稳定，受创追不上。建议 rally +10 或加条件。→ 已修（0.6.0：rally +15→+10）
- [ ] [P3] LevelDatabase.gd:105 - 地图尺寸声明 40×45 vs 场景 45×40 残留（运行期以场景为准，DB 声明与 _build_level_01_terrain 死代码）。（已核实：DB 声明 40×45 与 level_01.tscn 一致，清单记录过时）
- [x] [P3] 第 3-10 关无 turn_events（仅第 6 关 3 条）——增援/EMI 变化/叙事密度参差（第 7 关"全频段窒息"EMI 100% 应有事件）。→ 已修（0.6.0：第3/7/8/9/10关补 radio_dialogue 剧情，第5关 reserve_ready）
- [x] [P3] EMISystem LEVEL_10_EMI_CURVE 在 tick_turn 推进 → 曲线整体滞后 1 回合（推断）。→ 已修（0.6.0：turn 索引替代 turn-1）
- [x] [P3] smoke_test 无第 1 关 VP/出生点数量断言（0.5.9 的 VP 双轨回归未被测试捕获）。→ 已修（0.6.0：补断言，49→52 checks）
- [ ] [P3] LevelData 元数据无消费方：designer_intent/hidden_intel/special_events/narrative_branches/hidden_objective（纯设计备注）。（narrative_branches 已作为剧情素材来源，其余为设计备注保留）

## 功能缺口（产品向）

- [ ] [P3] 第 3-10 关主题地形（当前程序化占位 20×12 平地，缺河流/山地/雪地主题 + 标记）。
- [ ] [P3] 无线电对话（UI/交互最后缺口：战报/简报/旁白已覆盖）。
- [ ] [P3] ARCHITECTURE.md 文档滞后（停在 0.3.2，实际 0.5.9）。
- [ ] [P3] 第二套皮肤（01_写实军事风/01_单位精灵表.png）。

## 已闭环（历史，勿重复报）

- 0.5.7 批1/批2/批3（21 项）：教学条/盲射 3×3/士气符号/侧后角度/卡牌索引/pending 冲突/确认按钮/移动力覆盖/换关信号/空目标扣弹/NEUTRAL 派系/AI 压制/半程寻路/断电恢复/intro 泄漏/贷款封顶/重打回滚/双路径结算/卡牌重建/雷区烟雾入档/士气接入/击杀实时累计
- 0.5.8（18 项）：第 1 关地形坐标根治/换关死锁/pending 残留/读档士气键失配/卡牌回填/即时胜负 kills/invalid_target 扣弹/触雷停止/rally 去重/AI 过滤 NEUTRAL/卡牌误伤平民/读档事件不重复/空存档防护/遭遇战 continue
- 0.5.9 批A（10 项）：VP/出生点唯一化/读档士气顺序/卡牌类型防护/平民惩罚对象/移动预算统一/士气修正生效/morale 透传/初始士气 70/power_cut 去重/静默入档/换关 SceneTreeTimer
- 0.6.0 卡牌批B（10 项）：EMI 卡立即生效/EMI 时长语义/电磁反制方向（降 EMI）/卡牌状态门禁/乱码卡效果池/战报谎言假接触/布雷 1×2/范围方形统一/阵地加固即时化/烟雾时点修正/存档补 pending+buff/无线电静默指令门禁
- 0.6.0 批B 剩余（6 项）：AI 盲射射程/弹药/AI 集中突击 LOS 预校验/误伤惩罚移到命中后/存档 version 校验/第5关预备队死数据/nato_ai_behavior 以 DB 为权威
- 0.6.0 战斗系统（10 项 P2+）：伤害公式统一/侧后装甲枚举/面杀伤接入/近战反击/弹药补给/指挥阵亡惩罚+直升机统计/触雷幸存者/速度排序/行为演进/指挥点资源系统
- 0.6.0 体验完善（5 项）：无线电对话 UI/输入映射统一/ARCHITECTURE 重写/validate_path 删除/第3-10关主题地形核查确认
