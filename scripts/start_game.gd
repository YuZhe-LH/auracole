extends Control

var level: PackedScene = preload("res://scenes/jing_chuan.tscn")

func _ready() -> void:
	Dialogic.timeline_ended.connect(_on_dialog_ended)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for child in get_children():
			child.queue_free()
		if Dialogic.current_timeline == null:
			Dialogic.start("res://story/begin.dtl")
			get_viewport().set_input_as_handled()
		
		#

func _on_dialog_ended():
	var level_instance: Node = level.instantiate()
	get_tree().change_scene_to_node(level_instance)
