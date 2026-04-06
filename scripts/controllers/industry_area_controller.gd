extends Node3D

var current_camera_position: Vector3
var current_camera_rotation: Vector3
var camera_tween: Tween
var is_top_view: bool = false

func _ready() -> void:
	current_camera_position = $TopViewCamera.get_position()
	current_camera_rotation = $TopViewCamera.get_rotation()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("set_top_view"):
		if is_top_view:
			set_third_person_view()
			is_top_view = false
		else:
			current_camera_position = $TopViewCamera.get_position()
			current_camera_rotation = $TopViewCamera.get_rotation()
			set_top_view()
			is_top_view = true

func set_top_view():
	# 如果已有动画在运行，先停止
	if camera_tween:
		camera_tween.kill()

	# 创建新的 Tween
	camera_tween = create_tween()
	camera_tween.set_parallel(true)  # 位置和旋转同时进行
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.set_trans(Tween.TRANS_CUBIC)

	# 平滑过渡位置
	camera_tween.tween_property($TopViewCamera, "position", Vector3(0, 50, 0), 0.8)
	# 平滑过渡旋转（使用弧度）
	camera_tween.tween_property($TopViewCamera, "rotation", Vector3(deg_to_rad(-90), 0, 0), 0.8)

func set_third_person_view():
	# 如果已有动画在运行，先停止
	if camera_tween:
		camera_tween.kill()

	# 创建新的 Tween
	camera_tween = create_tween()
	camera_tween.set_parallel(true)
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.set_trans(Tween.TRANS_CUBIC)

	# 平滑过渡回原位置和旋转
	camera_tween.tween_property($TopViewCamera, "position", current_camera_position, 0.8)
	camera_tween.tween_property($TopViewCamera, "rotation", current_camera_rotation, 0.8)
