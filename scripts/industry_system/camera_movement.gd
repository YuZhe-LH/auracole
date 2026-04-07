extends Camera3D

var is_industry_mode: bool = false

@export var wheel_height_step: float = 1.0
@export var min_height: float = 4.0
@export var max_height: float = 30.0

func _on_industry_area_entry() -> void:
	is_industry_mode = true


func _on_industry_area_exit() -> void:
	is_industry_mode = false


func _input(event: InputEvent) -> void:
	if not is_industry_mode:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_height(-wheel_height_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_height(wheel_height_step)


func _on_movement_backward() -> void:
	position.z+=1


func _on_movement_forward() -> void:
	position.z-=1


func _on_movement_left() -> void:
	position.x-=1


func _on_movement_right() -> void:
	position.x+=1


func _adjust_height(delta_height: float) -> void:
	position.y = clampf(position.y + delta_height, min_height, max_height)
