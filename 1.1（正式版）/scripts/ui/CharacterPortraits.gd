class_name CharacterPortraits
extends RefCounted

const ANYA: Texture2D = preload("res://assets/portraits/anya.png")
const KARINA: Texture2D = preload("res://assets/portraits/karina.png")
const LEVENSKO: Texture2D = preload("res://assets/portraits/levensko.png")
const SQUAD_LEADER: Texture2D = preload("res://assets/portraits/squad_leader.png")
const ANVIL_COMMANDER: Texture2D = preload("res://assets/portraits/anvil_commander.png")


static func create_slot(slot_name: String) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.name = slot_name
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.visible = false
	return portrait


static func show_speaker(left: TextureRect, right: TextureRect,
		speaker: String, dialogue: String = "") -> void:
	var portrait := get_portrait(speaker, dialogue)
	var show_right := is_nato_speaker(speaker, dialogue)
	left.texture = portrait if portrait != null and not show_right else null
	right.texture = portrait if portrait != null and show_right else null
	left.visible = left.texture != null
	right.visible = right.texture != null
	_fade_in(left)
	_fade_in(right)


static func get_portrait(speaker: String, dialogue: String = "") -> Texture2D:
	var identity := _identity_text(speaker, dialogue)
	if "阿尼娅" in identity or "anya" in identity:
		return ANYA
	if "卡琳娜" in identity or "karina" in identity:
		return KARINA
	if "列夫森科" in identity or "levensko" in identity:
		return LEVENSKO
	if ("步兵班长" in identity or "前沿班长" in identity
			or "班长" in identity or "squadleader" in identity):
		return SQUAD_LEADER
	if ("铁砧指挥官" in identity or "北约指挥官" in identity
			or "anvilcommander" in identity):
		return ANVIL_COMMANDER
	return null


static func is_nato_speaker(speaker: String, dialogue: String = "") -> bool:
	var identity := _identity_text(speaker, dialogue)
	return ("铁砧指挥官" in identity or "北约指挥官" in identity
		or "anvilcommander" in identity)


static func _identity_text(speaker: String, dialogue: String) -> String:
	return (speaker + " " + dialogue).to_lower().replace("_", "").replace(" ", "")


static func _fade_in(portrait: TextureRect) -> void:
	if not portrait.visible:
		return
	portrait.modulate.a = 0.0
	var tween := portrait.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(portrait, "modulate:a", 1.0, 0.14)
