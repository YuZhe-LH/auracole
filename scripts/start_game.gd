extends Control

var level: PackedScene = preload("res://scenes/jing_chuan.tscn")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var level_instance: Node = level.instantiate()
		get_tree().change_scene_to_node(level_instance)
