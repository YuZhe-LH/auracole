extends Camera3D

var is_industry_mode: bool = false

func _on_industry_area_entry() -> void:
	is_industry_mode = true


func _on_industry_area_exit() -> void:
	is_industry_mode = false


func _on_movement_backward() -> void:
	position.x-=1


func _on_movement_forward() -> void:
	position.x+=1


func _on_movement_left() -> void:
	position.z+=1


func _on_movement_right() -> void:
	position.z-=1
