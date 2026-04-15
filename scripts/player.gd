## 第三人称控制器，负责角色移动、镜头环绕和导入动作播放。
extends CharacterBody3D

@export var inventory_data:InventoryDate
# —————————————————— 常量定义 ——————————————————
# 导入动画里用于标记伪根父骨骼的名称（日语："全ての親"，意为"所有父级"）。
# 用于后续禁用该骨骼的动画轨道，避免根运动破坏角色移动逻辑。
const ROOT_PARENT_BONE_TOKEN := "\u5168\u3066\u306e\u89aa"  

# —————————————————— 移动参数（可在检查器调整） ——————————————————
@export var move_speed: float = 6.5          # 角色在水平面上的最大移动速度。
@export var acceleration: float = 18.0       # 有输入时，速度逼近目标值的加速度。
@export var deceleration: float = 22.0       # 松开输入后，速度衰减的减速度。
@export var rotation_speed: float = 10.0     # 可见模型朝移动方向转身的平滑速度。

# —————————————————— 鼠标视角与相机参数 ——————————————————
@export var mouse_sensitivity: float = 0.0035    # 鼠标每像素对应的镜头旋转灵敏度（弧度）。
@export var min_pitch_degrees: float = -35.0     # 镜头可下压的最小俯仰角（度）。
@export var max_pitch_degrees: float = 45.0      # 镜头可上抬的最大俯仰角（度）。
@export var model_yaw_offset_degrees: float = 180.0  # 修正导入模型初始朝向的偏航角。
@export var camera_pivot_height: float = 1.45    # 肩后镜头旋转枢轴的高度偏移。
@export var camera_distance: float = 4.2          # 默认镜头距离。
@export var min_camera_distance: float = 1.0      # 允许的最近镜头距离。
@export var max_camera_distance: float = 6.0      # 允许的最远镜头距离。
@export var camera_zoom_step: float = 0.35        # 鼠标滚轮每一档的缩放距离变化量。

# —————————————————— 节点引用缓存（自动获取） ——————————————————
@onready var visual_root: Node3D = $kanami                    # 可见角色模型的根节点。
@onready var camera_yaw: Node3D = $CameraYaw                  # 控制相机水平旋转（偏航）的节点。
@onready var camera_pitch: Node3D = $CameraYaw/CameraPitch    # 控制相机垂直旋转（俯仰）的节点。
@onready var spring_arm: SpringArm3D = $CameraYaw/CameraPitch/SpringArm3D  # 弹簧臂（处理相机碰撞）。

# —————————————————— 运行时状态 ——————————————————
var gravity_strength: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)  # 从项目设置读取重力。
var animation_player: AnimationPlayer          # 用于播放导入动画的播放器。
var locomotion_animation: StringName = &""    # 选中的移动（跑步/待机）动画名称。
var run_animation_active := false              # 标记当前是否正在播放跑步动画。


## 初始化：鼠标捕获、相机默认值、模型与动画设置。
func _ready() -> void:
	floor_snap_length = 0.4  # 地面吸附长度：帮助角色在下坡/台阶时更好地贴地。
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # 游戏开始时捕获鼠标（隐藏并锁定）。
	camera_pitch.position.y = camera_pivot_height  # 设置相机枢轴的高度。
	_apply_camera_distance(camera_distance)        # 应用初始相机距离。
	spring_arm.add_excluded_object(get_rid())      # 让弹簧臂忽略角色自身的碰撞体（避免相机被自己挡住）。
	_setup_model()                                  # 初始化模型朝向和动画。
	camera_pitch.rotation.x = deg_to_rad(-12.0)   # 设置相机初始俯仰角（稍微向下看）。


## 处理输入：鼠标捕获、滚轮缩放、第三人称视角环绕。
func _unhandled_input(event: InputEvent) -> void:
	# 按 ESC 键显示鼠标。
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	# 点击左键重新捕获鼠标。
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	# 鼠标滚轮缩放相机距离。
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_camera_distance(camera_distance - camera_zoom_step)  # 滚轮上推：拉近
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_camera_distance(camera_distance + camera_zoom_step)  # 滚轮下拉：拉远
			return

	# 鼠标移动时旋转视角（仅在鼠标捕获状态下）。
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw.rotate_y(-event.relative.x * mouse_sensitivity)  # 水平旋转（偏航）。
		# 垂直旋转（俯仰），并限制角度范围。
		camera_pitch.rotation.x = clamp(
			camera_pitch.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)


## 物理帧更新：应用重力、处理移动、同步动画。
func _physics_process(delta: float) -> void:
	# 1. 应用重力
	if not is_on_floor():
		velocity.y -= gravity_strength * delta  # 在空中时，垂直速度持续下降。
	else:
		velocity.y = 0.0  # 在地面上时，垂直速度清零。

	# 2. 计算移动方向与速度
	var input_vector := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var move_direction := _get_camera_relative_direction(input_vector)  # 获取相对于相机的移动方向。
	var target_horizontal_velocity := move_direction * move_speed        # 目标水平速度。
	var current_horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)  # 当前水平速度（忽略Y轴）。
	var blend_rate := acceleration if move_direction != Vector3.ZERO else deceleration  # 根据是否有输入选择加/减速率。

	# 平滑过渡当前速度到目标速度
	current_horizontal_velocity = current_horizontal_velocity.move_toward(target_horizontal_velocity, blend_rate * delta)
	velocity.x = current_horizontal_velocity.x
	velocity.z = current_horizontal_velocity.z

	# 3. 执行移动
	move_and_slide()  # Godot 专门的角色移动函数，自动处理碰撞和滑动。

	# 4. 让角色模型朝向移动方向
	if move_direction != Vector3.ZERO:
		_rotate_visual_towards(move_direction, delta)

	# 5. 更新动画状态
	_update_animation(current_horizontal_velocity.length())


## 将二维输入转换为相对于相机朝向的世界空间水平移动方向。
func _get_camera_relative_direction(input_vector: Vector2) -> Vector3:
	if input_vector.is_zero_approx():
		return Vector3.ZERO  # 没有输入时返回零向量。

	# 获取相机的前方向和右方向（注意：Godot 中相机默认看向 -Z 方向）。
	var forward := -camera_yaw.global_basis.z
	var right := camera_yaw.global_basis.x
	
	# 只保留水平方向（Y轴归零），防止上下坡时方向倾斜。
	forward.y = 0.0
	right.y = 0.0
	
	# 归一化，确保方向向量长度为 1。
	forward = forward.normalized()
	right = right.normalized()

	# 合成最终移动方向：右方向 * 输入X + 前方向 * 输入Y。
	return (right * input_vector.x + forward * input_vector.y).normalized()


## 限制并应用相机距离到弹簧臂。
func _apply_camera_distance(next_distance: float) -> void:
	camera_distance = clamp(next_distance, min_camera_distance, max_camera_distance)  # 限制在最小/最大距离之间。
	spring_arm.spring_length = camera_distance  # 更新弹簧臂长度。


## 让可见角色模型平滑地转向目标移动方向。
func _rotate_visual_towards(move_direction: Vector3, delta: float) -> void:
	# 1. 计算目标朝向：看向移动方向，并应用模型初始偏航修正。
	var target_basis := Basis.looking_at(move_direction, Vector3.UP) * _get_model_yaw_offset_basis()
	
	# 2. 使用四元数进行球面线性插值（Slerp），实现平滑旋转。
	var current_rotation := visual_root.basis.get_rotation_quaternion()
	var target_rotation := target_basis.get_rotation_quaternion()
	
	# 3. 应用旋转
	visual_root.basis = Basis(current_rotation.slerp(target_rotation, min(rotation_speed * delta, 1.0)))


## 初始化模型：查找动画播放器、处理导入的动画数据。
func _setup_model() -> void:
	# 1. 应用模型初始朝向修正
	visual_root.basis = _get_model_yaw_offset_basis()
	
	# 2. 递归查找模型中的 AnimationPlayer
	animation_player = _find_animation_player(visual_root)
	if animation_player == null:
		push_warning("No AnimationPlayer found in kanami.gltf.")
		return

	# 3. 禁用伪根骨骼的动画轨道（防止根运动破坏代码控制的移动）
	_disable_root_parent_tracks()

	# 4. 自动选择一个移动动画
	locomotion_animation = _pick_locomotion_animation(animation_player.get_animation_list())
	if String(locomotion_animation).is_empty():
		push_warning("No locomotion animation found in kanami.gltf.")
		return

	# 5. 设置动画为循环播放
	var animation := animation_player.get_animation(locomotion_animation)
	if animation != null:
		animation.set_loop_mode(Animation.LOOP_LINEAR)

	# 6. 初始化为待机姿态
	_set_idle_pose()


## 递归在节点树中查找 AnimationPlayer。
func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer

	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found

	return null


## 从动画列表中优先选择包含 "run" 或 "bone" 的动画作为移动动画。
func _pick_locomotion_animation(animation_names: PackedStringArray) -> StringName:
	for animation_name in animation_names:
		var lowered := String(animation_name).to_lower()
		if lowered.contains("run") or lowered.contains("bone"):
			return animation_name

	if animation_names.is_empty():
		return &""

	return animation_names[0]  # 没找到的话，回退到第一个动画。


## 构建用于修正模型初始朝向的旋转 Basis。
func _get_model_yaw_offset_basis() -> Basis:
	return Basis.from_euler(Vector3(0.0, deg_to_rad(model_yaw_offset_degrees), 0.0))


## 禁用驱动伪根节点的动画轨道，避免模型被动画拖走。
func _disable_root_parent_tracks() -> void:
	for animation_name in animation_player.get_animation_list():
		var animation := animation_player.get_animation(animation_name)
		if animation == null:
			continue

		# 遍历该动画的所有轨道
		for track_idx in range(animation.get_track_count()):
			var track_path := String(animation.track_get_path(track_idx))
			# 如果轨道路径包含伪根骨骼名称，则禁用该轨道
			if track_path.contains(ROOT_PARENT_BONE_TOKEN):
				animation.track_set_enabled(track_idx, false)


## 根据移动速度播放/暂停动画，并调整播放速度。
func _update_animation(horizontal_speed: float) -> void:
	if animation_player == null or String(locomotion_animation).is_empty():
		return

	# 速度大于阈值：播放跑步动画
	if horizontal_speed > 0.15:
		if not run_animation_active:
			animation_player.play(locomotion_animation, 0.15)  # 0.15 秒的淡入时间
			run_animation_active = true

		# 根据实际速度微调动画播放速度（走得越快，动画播得越快）
		animation_player.speed_scale = clamp(horizontal_speed / move_speed, 0.85, 1.15)
		return

	# 速度低于阈值：切回待机姿态
	if run_animation_active:
		_set_idle_pose()


## 将动画暂停在第一帧，作为待机姿态。
func _set_idle_pose() -> void:
	animation_player.play(locomotion_animation)
	animation_player.seek(0.0, true)  # 强制跳到第 0 秒
	animation_player.pause()
	run_animation_active = false
