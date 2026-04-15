# 继承自 ScrollContainer，自定义其滚动行为
extends ScrollContainer

# -------------------------- 常量定义 --------------------------
const INERTIA_DISTANCE := 15.0  # 惯性滑动的“总距离”（像素）
const INERTIA_DURATION := 0.16   # 惯性动画的“持续时间”（秒，约 60 帧）

# -------------------------- 成员变量 --------------------------
var is_dragging: bool = false      # 标记当前是否正在拖拽
var last_drag_delta: float = 0.0   # 记录最后一次拖拽的“垂直方向偏移量”（用于惯性方向/力度）
var inertia_tween: Tween = null    # 用于播放“惯性动画”的 Tween 对象

# -------------------------- 输入处理核心 --------------------------
func _input(event: InputEvent) -> void:
	# 1. 处理鼠标左键事件（按下/释放）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# 左键按下：且鼠标在容器内 → 开始拖拽
		if event.pressed and _is_mouse_inside(event.position):
			_start_drag()
			return

		# 左键释放：且正在拖拽 → 结束拖拽（触发惯性）
		if not event.pressed and is_dragging:
			_finish_drag()
			return

	# 2. 处理鼠标移动事件（仅在拖拽中生效）
	if is_dragging and event is InputEventMouseMotion:
		_drag_scroll(event.relative.y)  # 传入“垂直方向的鼠标移动量”

# 预留的 GUI 输入回调（当前未使用）
func _on_gui_input(_event: InputEvent) -> void:
	pass

# -------------------------- 拖拽状态控制 --------------------------
# 开始拖拽：初始化状态、停止惯性
func _start_drag() -> void:
	is_dragging = true
	last_drag_delta = 0.0
	_kill_inertia_tween()  # 拖拽时立即打断之前的惯性动画

# 结束拖拽：根据最后拖拽速度，启动惯性
func _finish_drag() -> void:
	is_dragging = false

	# 如果最后一次拖拽偏移量几乎为 0（没怎么动），则不触发惯性
	if is_zero_approx(last_drag_delta):
		return

	# 计算惯性目标位置：当前滚动值 + (方向 * 惯性距离)
	var target_scroll := get_v_scroll() + signf(last_drag_delta) * INERTIA_DISTANCE
	_start_inertia(target_scroll)

# -------------------------- 滚动逻辑 --------------------------
# 执行拖拽滚动：根据鼠标移动量更新滚动位置
func _drag_scroll(mouse_delta_y: float) -> void:
	if is_zero_approx(mouse_delta_y):
		return

	# 记录“反向”偏移量（鼠标向下移 → 内容向上滚，所以取负）
	last_drag_delta = -mouse_delta_y
	# 应用滚动：当前滚动值 + 偏移量
	_set_scroll_vertical(get_v_scroll() + last_drag_delta)

# 启动惯性动画：用 Tween 平滑滚动到目标位置
func _start_inertia(target_scroll: float) -> void:
	# 先把目标值“钳制”在合法滚动范围内（防止滚出界）
	var clamped_target := _clamp_scroll(target_scroll)
	# 如果目标值和当前值几乎一样，不用播动画
	if is_equal_approx(float(get_v_scroll()), clamped_target):
		return

	# 1. 先杀掉旧的 Tween（防止叠加动画）
	_kill_inertia_tween()
	# 2. 创建新 Tween 并播放动画
	inertia_tween = create_tween()
	inertia_tween.tween_method(
		Callable(self, "_set_scroll_vertical"),  # 每一帧调用的函数
		float(get_v_scroll()),                     # 动画起始值（当前滚动位置）
		clamped_target,                            # 动画结束值（目标滚动位置）
		INERTIA_DURATION                           # 动画持续时间
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	#  ↑ 动画曲线：Cubic（三次方）+ EaseOut（先快后慢，更自然的惯性手感）

# 封装“设置垂直滚动”：先钳制范围，再四舍五入为整数（ScrollContainer 滚动值为 int）
func _set_scroll_vertical(value: float) -> void:
	set_v_scroll(int(round(_clamp_scroll(value))))

# 计算“合法滚动范围”：确保滚动值在 [0, 最大可滚动距离] 之间
func _clamp_scroll(value: float) -> float:
	var v_scroll_bar := get_v_scroll_bar()
	# 最大可滚动距离 = 滚动条最大值 - 滚动条“页面大小”（可视区域高度）
	var max_scroll := maxf(0.0, v_scroll_bar.max_value - v_scroll_bar.page)
	# 把 value 钳制在 [0, max_scroll] 之间
	return clampf(value, 0.0, max_scroll)

# -------------------------- 工具函数 --------------------------
# 停止并销毁惯性 Tween（防止内存泄漏或意外动画）
func _kill_inertia_tween() -> void:
	if is_instance_valid(inertia_tween):
		inertia_tween.kill()
		inertia_tween = null

# 检查鼠标是否在容器的“全局矩形区域”内（判断是否点中自己）
func _is_mouse_inside(global_mouse_position: Vector2) -> bool:
	return get_global_rect().has_point(global_mouse_position)
