# 单位配置系统使用说明

本文档供《Silent Reckoning·1987》后续开发者使用，说明如何修改官方单位数据、生成游戏配置，以及处理玩家自定义配置。

## 1. 配置文件位置

| 用途 | 文件位置 | 是否手动修改 |
|---|---|---|
| 官方单位属性设计表 | `config/source/unit_config.xlsx` | 是 |
| 游戏运行时单位数据 | `data/units/unit_config.json` | 否，由工具生成 |
| 文件夹一键同步工具 | `更新单位配置_Excel转JSON.cmd` | 否，双击运行 |
| Excel转换脚本 | `tools/config/SyncUnitConfig.ps1` | 一般不修改 |
| 单位配置加载逻辑 | `scripts/units/UnitDatabase.gd` | 扩展系统时修改 |
| 玩家配置界面 | `scripts/ui/UnitConfigScreen.gd` | 调整界面时修改 |

不要直接修改 `unit_config.json`。再次同步 Excel 时，手动修改的 JSON 内容会被覆盖。

## 2. 不打开 Godot 的推荐修改流程

1. 打开 `config/source/unit_config.xlsx`。
2. 修改需要调整的单位属性。
3. 保存并关闭 Excel。
4. 双击项目根目录的 `更新单位配置_Excel转JSON.cmd`。
5. 等待更新窗口完成。
6. 出现以下信息代表同步成功：

```text
UNIT_CONFIG_SYNC_OK units=23
[SUCCESS] Unit configuration has been updated.
```

7. 工具将自动更新 `data/units/unit_config.json`。
8. 运行游戏并进入关卡验证数值。

运行同步工具需要 Windows 版 Microsoft Excel。同步前应保存并关闭工作簿。

## 3. 在 Godot 内同步

在 Godot 编辑器顶部选择：

```text
项目（Project）
└─ 工具（Tools）
   └─ 同步单位配置（Excel → JSON）
```

完成后，在“输出（Output）”面板确认出现：

```text
UNIT_CONFIG_SYNC_OK units=23
```

如果菜单中没有该选项：

1. 打开“项目 → 项目设置（Project Settings）”。
2. 进入“插件（Plugins）”。
3. 找到“单位配置同步”。
4. 将插件状态设为“启用（Enabled）”。
5. 如果已经启用，可以先禁用再重新启用。

插件文件位于 `addons/unit_config_sync/`。

## 4. Excel 修改规则

可以直接修改单位的生命、攻击、装甲、射程、移动力、视野、行动点、先制值和特性等属性。

请遵守以下规则：

- 不要删除或重命名工作表“单位属性配置”。
- 不要修改表头文字。
- 不要改变前四行的表格结构。
- 不要重复填写相同的 `enum_id`。
- 命中率应填写为 `0–1` 之间的小数，例如 `0.75`。
- 单位尺寸必须使用大于零的整数。
- `enum_id` 必须与 `UnitBase.gd` 中的 `UnitType` 枚举完全一致。

同步工具会检查单位数量、重复枚举、生命值、命中率、先制值和占地尺寸。检查失败时不会覆盖现有的可用 JSON。

## 5. 配置加载优先级

游戏使用以下优先级加载单位属性：

```text
代码内置默认值
	↓
Excel 生成的官方 JSON
	↓
玩家自定义差异（最高优先级）
	↓
游戏最终使用的单位属性
```

因此，开发者修改 Excel 后如果游戏数值没有变化，应先在主菜单进入“单位属性配置”，点击“全部恢复默认”。玩家保存过的同名属性会覆盖官方 Excel 数值。

玩家配置存放在：

```text
user://unit_config_overrides.json
```

它位于 Godot 的用户数据目录，不会修改项目中的 Excel 或 JSON。

## 6. 玩家单位属性配置界面

主菜单的“单位属性配置”目前允许玩家调整：

- 生命值
- 弹药量
- 攻击力
- 装甲值
- 穿透力
- 命中率
- 攻击射程
- 移动力
- 视野

带 `*` 的单位存在玩家自定义数值。界面支持恢复当前单位和全部恢复默认。

玩家可编辑字段及安全上下限定义在：

```text
scripts/units/UnitDatabase.gd
```

搜索 `PLAYER_EDITABLE_FIELDS` 即可修改显示名称、最小值、最大值和增减步长。配置界面会自动根据该字典生成输入框。

## 7. 增加全新单位

增加单位不能只在 Excel 中新增一行，需要同步完成以下工作：

1. 在 `scripts/units/UnitBase.gd` 的 `UnitType` 中增加枚举。
2. 在 Excel 中新增单位行。
3. 将 Excel 的 `enum_id` 设置为与枚举完全相同的名称。
4. 填写阵营、显示名称、兵种类别和全部基础属性。
5. 运行 Excel → JSON 同步工具。
6. 在对应关卡数据中添加出生位置。
7. 添加单位图标、地图显示或移动动画。
8. 运行配置测试与关卡测试。

如果只是修改现有单位数值，不需要修改 GDScript。

## 8. 生效时机

- 官方 JSON 在游戏启动时读取。
- 玩家修改在保存后立即写入用户配置文件。
- 新数值会在下一场战斗创建单位时生效。
- 已经进入战场并创建的单位不会自动刷新。
- 修改配置后应退出当前战斗并重新进入关卡。

## 9. 自动测试

主要测试文件：

```text
tests/unit_config_test.tscn
tests/player_unit_config_test.tscn
tests/smoke_test.tscn
```

配置系统的正常结果应包含：

```text
[UNIT CONFIG TEST] PASS
[PLAYER UNIT CONFIG TEST] PASS
[SMOKE TEST] PASS
```

如果本机配置了 Godot 控制台版本，可以运行：

```powershell
python tools/run_tests.py
```

## 10. 常见问题

### 双击更新工具后失败

检查以下内容：

- Microsoft Excel 是否已安装。
- `unit_config.xlsx` 是否已经保存并关闭。
- 工作表和表头是否被重命名。
- Excel 中是否存在重复或无效的 `enum_id`。
- 项目路径和同步脚本是否仍然存在。

### Excel 已修改，但游戏还是旧数值

依次检查：

1. 同步窗口是否显示成功。
2. `data/units/unit_config.json` 的修改时间是否更新。
3. 是否停止并重新运行了游戏。
4. 是否存在玩家自定义覆盖值。
5. 在游戏配置界面点击“全部恢复默认”后重新进入关卡。

### JSON 缺失或损坏

游戏会退回 GDScript 中的内置默认值，不会因为 JSON 缺失而无法启动。重新运行同步工具即可生成 JSON。

## 11. 推荐提交内容

开发者调整官方数值并提交版本时，至少应同时提交：

```text
config/source/unit_config.xlsx
data/units/unit_config.json
```

如果修改了可编辑字段、加载逻辑或界面，还需要提交对应的 GDScript 和测试文件。不要提交个人的 `user://unit_config_overrides.json`。
