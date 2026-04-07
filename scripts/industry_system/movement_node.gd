extends Node3D

signal forward
signal backward
signal left
signal right

@onready var father: Camera3D = get_parent() if get_parent() is Node3D else null

func _ready() -> void:
	assert(not father == null)

func _input(event: InputEvent) -> void:
	if event.is_action("forward"):
		emit_signal("forward")
	if event.is_action("backward"):
		emit_signal("backward")
	if event.is_action("left"):
		emit_signal("left")
	if event.is_action("right"):
		emit_signal("right")
