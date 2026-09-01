extends Node

func _ready() -> void:
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(menu)
	for _frame in range(5):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://tests/_credits_visual_capture.png"))
	get_tree().quit(0)
