# ==============================================================================
# FogOfWar.gd — 玩家侧战争迷雾状态 (Autoload 单例)
# ==============================================================================
extends Node

signal visibility_updated

var enabled: bool = false
var viewer_faction: int = UnitBase.Faction.WARSAW_PACT
var _visibility_by_unit: Dictionary = {}
var _visibility_counts: Dictionary = {}


func start_level(is_enabled: bool, faction: int = UnitBase.Faction.WARSAW_PACT) -> void:
	"""重置本关的探索记录，并根据己方单位计算首帧可见区域。"""
	enabled = is_enabled
	viewer_faction = faction
	_visibility_by_unit.clear()
	_visibility_counts.clear()
	for row in GridManager.grid:
		for cell in row:
			cell.is_visible = not enabled
			cell.is_explored = not enabled
	refresh()


func refresh() -> void:
	"""以所有己方存活单位的联合 LOS 更新当前可见格，保留探索记忆。"""
	if GridManager.grid.is_empty():
		return
	_visibility_by_unit.clear()
	_visibility_counts.clear()
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
		var visible_cells := _collect_unit_visibility(unit)
		_visibility_by_unit[unit.unit_id] = visible_cells
		for position in visible_cells:
			_visibility_counts[position] = int(_visibility_counts.get(position, 0)) + 1
			_reveal(position)

	visibility_updated.emit()


func refresh_unit(unit: UnitBase) -> bool:
	"""单位跨格后只更新它自己的视野差集；返回迷雾显示是否实际改变。"""
	if not enabled or GridManager.grid.is_empty() or unit == null:
		return false
	var unit_id: int = unit.unit_id
	var previous: Dictionary = _visibility_by_unit.get(unit_id, {})
	if not unit.is_alive or unit.faction != viewer_faction:
		if previous.is_empty():
			return false
		var removed_visibility := false
		for position in previous:
			removed_visibility = _decrement_visibility(position) or removed_visibility
		_visibility_by_unit.erase(unit_id)
		if removed_visibility:
			visibility_updated.emit()
		return removed_visibility

	var current := _collect_unit_visibility(unit)
	var visibility_changed := false
	for position in previous:
		if not current.has(position):
			visibility_changed = _decrement_visibility(position) or visibility_changed
	for position in current:
		if previous.has(position):
			continue
		var old_count := int(_visibility_counts.get(position, 0))
		_visibility_counts[position] = old_count + 1
		if old_count == 0:
			_reveal(position)
			visibility_changed = true
	_visibility_by_unit[unit_id] = current
	if visibility_changed:
		visibility_updated.emit()
	return visibility_changed


func is_unit_visible(unit: UnitBase) -> bool:
	if not enabled or unit == null or unit.faction == viewer_faction:
		return true
	var cell = GridManager.get_cell(unit.grid_col, unit.grid_row)
	return cell != null and cell.is_visible


func _collect_unit_visibility(unit: UnitBase) -> Dictionary:
	var result: Dictionary = {}
	result[Vector2i(unit.grid_col, unit.grid_row)] = true
	for position in LineOfSight.get_visible_cells(unit):
		result[position] = true
	return result


func _decrement_visibility(position: Vector2i) -> bool:
	var count := int(_visibility_counts.get(position, 0)) - 1
	if count > 0:
		_visibility_counts[position] = count
		return false
	_visibility_counts.erase(position)
	var cell = GridManager.get_cell(position.x, position.y)
	if cell and cell.is_visible:
		cell.is_visible = false
		return true
	return false


func _reveal(position: Vector2i) -> void:
	var cell = GridManager.get_cell(position.x, position.y)
	if cell:
		cell.is_visible = true
		cell.is_explored = true
