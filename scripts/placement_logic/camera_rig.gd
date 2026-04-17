extends Node2D
class_name CameraRig

@export var min_zoom: Vector2 = Vector2(0.5, 0.5)
@export var max_zoom: Vector2 = Vector2(3.0, 3.0)
@export var zoom_step: float = 0.15
@export var zoom_lerp_speed: float = 12.0
@export var drag_threshold: float = 6.0
@export var wasd_move_speed: float = 500.0
@export var wasd_acceleration: float = 2500.0
@export var wasd_deceleration: float = 3200.0
@export var wasd_max_speed: float = 1000.0
@export var enable_inertia: bool = true
@export_range(0.01, 0.999, 0.001) var inertia_decay: float = 0.9
@export_node_path("Node2D") var map_path: NodePath = ^"../MapManager"

@onready var camera: Camera2D = $Camera2D
@onready var map_manager: MapManager = get_node_or_null(map_path) as MapManager

var drag_enabled: bool = true

var _left_button_down: bool = false
var _is_dragging: bool = false
var _drag_consumed: bool = false
var _press_screen_position: Vector2 = Vector2.ZERO
var _drag_anchor_world: Vector2 = Vector2.ZERO
var _target_zoom: Vector2 = Vector2.ONE
var _wasd_velocity: Vector2 = Vector2.ZERO
var _wasd_input_vector: Vector2 = Vector2.ZERO
var _is_wasd_moving: bool = false


func _ready() -> void:
	camera.position = get_viewport_rect().size * 0.5
	camera.zoom = Vector2.ONE
	_target_zoom = camera.zoom
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_clamp_camera_position()


func _process(delta: float) -> void:
	var moved_by_wasd: bool = _process_wasd_movement(delta)
	var zoom_changed: bool = _process_camera_zoom(delta)
	if moved_by_wasd or zoom_changed:
		_clamp_camera_position()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
		return

	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func is_dragging() -> bool:
	return _is_dragging


func is_wasd_moving() -> bool:
	return _is_wasd_moving


func get_wasd_input_vector() -> Vector2:
	return _wasd_input_vector


func consume_drag_release() -> bool:
	if not _drag_consumed:
		return false

	_drag_consumed = false
	return true


func set_drag_enabled(enabled: bool) -> void:
	drag_enabled = enabled
	if drag_enabled:
		return

	_left_button_down = false
	_is_dragging = false
	_drag_consumed = false


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_set_target_zoom(_target_zoom + Vector2.ONE * zoom_step)
		get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_set_target_zoom(_target_zoom - Vector2.ONE * zoom_step)
		get_viewport().set_input_as_handled()
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		if not drag_enabled:
			_left_button_down = false
			return

		_left_button_down = true
		_is_dragging = false
		_drag_consumed = false
		_press_screen_position = event.position
		_drag_anchor_world = get_global_mouse_position()
		return

	_left_button_down = false
	if _is_dragging:
		get_viewport().set_input_as_handled()
	_is_dragging = false


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not drag_enabled or not _left_button_down:
		return

	if not _is_dragging and event.position.distance_to(_press_screen_position) >= drag_threshold:
		_is_dragging = true
		_drag_consumed = true

	if not _is_dragging:
		return

	_pan_to_drag_anchor()
	get_viewport().set_input_as_handled()


func _set_target_zoom(next_zoom: Vector2) -> void:
	var clamped_zoom: Vector2 = Vector2(
		clampf(next_zoom.x, min_zoom.x, max_zoom.x),
		clampf(next_zoom.y, min_zoom.y, max_zoom.y)
	)
	if clamped_zoom.is_equal_approx(_target_zoom):
		return

	_target_zoom = clamped_zoom


func _update_wasd_input_vector() -> void:
	_wasd_input_vector = Vector2(
		(1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0),
		(1.0 if Input.is_key_pressed(KEY_S) else 0.0) - (1.0 if Input.is_key_pressed(KEY_W) else 0.0)
	)


func _process_wasd_movement(delta: float) -> bool:
	_update_wasd_input_vector()

	var input_direction: Vector2 = _wasd_input_vector.normalized()
	var zoom_factor: float = maxf(camera.zoom.x, camera.zoom.y)
	var target_velocity: Vector2 = input_direction * wasd_move_speed * zoom_factor

	if input_direction.is_zero_approx():
		if enable_inertia and not _wasd_velocity.is_zero_approx():
			var frame_decay: float = pow(inertia_decay, delta * 60.0)
			_wasd_velocity *= frame_decay
			if _wasd_velocity.length() < 5.0:
				_wasd_velocity = Vector2.ZERO
		else:
			_wasd_velocity = _wasd_velocity.move_toward(Vector2.ZERO, wasd_deceleration * delta)
	else:
		_wasd_velocity = _wasd_velocity.move_toward(target_velocity, wasd_acceleration * delta)

	var max_speed: float = wasd_max_speed * zoom_factor
	if max_speed > 0.0:
		_wasd_velocity = _wasd_velocity.limit_length(max_speed)

	_is_wasd_moving = not _wasd_velocity.is_zero_approx()
	if not _is_wasd_moving:
		return false

	camera.position += _wasd_velocity * delta
	if _is_dragging:
		_drag_anchor_world = get_global_mouse_position()
	return true


func _process_camera_zoom(delta: float) -> bool:
	if camera.zoom.is_equal_approx(_target_zoom):
		return false

	var mouse_world_before_zoom: Vector2 = get_global_mouse_position()
	var zoom_weight: float = minf(1.0, zoom_lerp_speed * delta)
	var next_zoom: Vector2 = camera.zoom.lerp(_target_zoom, zoom_weight)
	if next_zoom.distance_squared_to(_target_zoom) < 0.000001:
		next_zoom = _target_zoom

	# Sample the world position under the cursor before zoom changes.
	# After updating Camera2D.zoom, sample again and move the camera by
	# the difference so the same world point stays exactly under the mouse.
	camera.zoom = next_zoom
	var mouse_world_after_zoom: Vector2 = get_global_mouse_position()
	camera.position += mouse_world_before_zoom - mouse_world_after_zoom
	return true


func _pan_to_drag_anchor() -> void:
	# Keep the exact world pixel that was clicked glued to the cursor.
	# We measure where that pixel is now, then move the camera by the difference.
	var current_mouse_world: Vector2 = get_global_mouse_position()
	var correction: Vector2 = _drag_anchor_world - current_mouse_world
	if correction.length_squared() <= 0.0001:
		return

	camera.position += correction
	_clamp_camera_position()


func _clamp_camera_position() -> void:
	if map_manager == null:
		return

	var map_size: Vector2 = map_manager.get_map_pixel_size()
	var half_view: Vector2 = get_viewport_rect().size * camera.zoom * 0.5
	var min_position: Vector2 = half_view
	var max_position: Vector2 = map_size - half_view

	if min_position.x > max_position.x:
		camera.position.x = map_size.x * 0.5
	else:
		camera.position.x = clampf(camera.position.x, min_position.x, max_position.x)

	if min_position.y > max_position.y:
		camera.position.y = map_size.y * 0.5
	else:
		camera.position.y = clampf(camera.position.y, min_position.y, max_position.y)


func _on_viewport_size_changed() -> void:
	_clamp_camera_position()
