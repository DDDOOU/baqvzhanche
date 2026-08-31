# ==============================================================================
# FogOfWar.gd — 玩家侧战争迷雾状态 (Autoload 单例)
# ==============================================================================
extends Node

signal visibility_updated

var enabled: bool = false
var viewer_faction: int = UnitBase.Faction.WARSAW_PACT


func start_level(is_enabled: bool, faction: int = UnitBase.Faction.WARSAW_PACT) -> void:
	"""重置本关的探索记录，并根据己方单位计算首帧可见区域。"""
	enabled = is_enabled
	viewer_faction = faction
	for row in GridManager.grid:
		for cell in row:
			cell.is_visible = not enabled
			cell.is_explored = not enabled
	refresh()


func refresh() -> void:
	"""以所有己方存活单位的联合 LOS 更新当前可见格，保留探索记忆。"""
	if GridManager.grid.is_empty():
		return
	if not enabled:
		for row in GridManager.grid:
			for cell in row:
				cell.is_visible = true
				cell.is_explored = true
		visibility_updated.emit()
		return

	for row in GridManager.grid:
		for cell in row:
			cell.is_visible = false

	for unit in get_tree().get_nodes_in_group("units"):
		if not (unit is UnitBase) or not unit.is_alive or unit.faction != viewer_faction:
			continue
		_reveal(Vector2i(unit.grid_col, unit.grid_row))
		for position in LineOfSight.get_visible_cells(unit):
			_reveal(position)

	visibility_updated.emit()


func is_unit_visible(unit: UnitBase) -> bool:
	if not enabled or unit == null or unit.faction == viewer_faction:
		return true
	var cell = GridManager.get_cell(unit.grid_col, unit.grid_row)
	return cell != null and cell.is_visible


func _reveal(position: Vector2i) -> void:
	var cell = GridManager.get_cell(position.x, position.y)
	if cell:
		cell.is_visible = true
		cell.is_explored = true
