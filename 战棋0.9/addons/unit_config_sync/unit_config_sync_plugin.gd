@tool
extends EditorPlugin

const MENU_NAME := "同步单位配置（Excel → JSON）"
const SYNC_SCRIPT := "res://tools/config/SyncUnitConfig.ps1"


func _enter_tree() -> void:
	add_tool_menu_item(MENU_NAME, _sync_unit_config)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_NAME)


func _sync_unit_config() -> void:
	var project_root := ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")
	var script_path := ProjectSettings.globalize_path(SYNC_SCRIPT)
	var output: Array = []
	var arguments := PackedStringArray([
		"-NoProfile",
		"-ExecutionPolicy", "Bypass",
		"-File", script_path,
		"-ProjectRoot", project_root,
	])
	var exit_code := OS.execute("powershell.exe", arguments, output, true, false)
	var message := "\n".join(output)
	if exit_code != 0:
		push_error("单位配置同步失败（退出码 %d）：\n%s" % [exit_code, message])
		return

	get_editor_interface().get_resource_filesystem().scan()
	print("[UnitConfigSync] %s" % message)
	print("[UnitConfigSync] 同步完成；重新运行游戏即可使用最新配置。")
