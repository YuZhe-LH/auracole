# 脚本挂载在 3D 主场景根节点，用于按 B 键 打开/关闭 地图/背包UI
extends Node3D

# ====================== 常量配置 ======================
# 地图/背包场景文件路径（你自己的tscn文件）
const MAP_SCENE_PATH := "res://scenes/map.tscn"
# 按键防抖间隔（200毫秒内不能重复开关，防止连按乱套）
const MAP_TOGGLE_DEBOUNCE_MSEC := 200

# ====================== 节点引用 ======================
# 玩家节点
@onready var player: Node = $Player
# UI父容器（CanvasGroup，用于放动态生成的地图/背包）
@onready var map_parent: Node = $CanvasGroup

# ====================== 状态变量 ======================
# 保存当前生成的地图/背包实例
var map_instance: Control
# 上一次开关的时间（用于防抖）
var last_map_toggle_time_msec := -MAP_TOGGLE_DEBOUNCE_MSEC
# 保存打开地图前玩家的运行模式（用于关闭后还原）
var player_process_mode_before_map: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
# 保存打开地图前鼠标模式（捕获/显示）
var mouse_mode_before_map: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
# 标记玩家是否被地图锁定
var player_locked_by_map := false

# ====================== 输入检测 ======================
func _input(event: InputEvent) -> void:
	# 同步状态，防止异常
	_sync_map_state()

	# 只处理按键事件
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return

	# 按 B 键：开关地图/背包
	if key_event.physical_keycode == KEY_B:
		if _toggle_map():
			get_viewport().set_input_as_handled()
		return

	# 按 ESC：如果地图打开就关闭
	if event.is_action_pressed("ui_cancel") and _try_close_map():
		get_viewport().set_input_as_handled()

# ====================== 生命周期 ======================
# 节点销毁时自动关闭地图，防止内存泄漏
func _exit_tree() -> void:
	_close_map()

# ====================== 核心开关逻辑 ======================
# 切换地图：打开 ↔ 关闭
func _toggle_map() -> bool:
	if _get_map_instance() != null:
		return _try_close_map()
	if not _can_toggle_map():
		return false
	return _open_map()

# 尝试关闭地图
func _try_close_map() -> bool:
	if _get_map_instance() == null:
		_sync_map_state()
		return false
	if not _can_toggle_map():
		return false
	_close_map()
	return true

# 打开地图：动态加载 → 实例化 → 添加到场景
func _open_map() -> bool:
	if _get_map_instance() != null:
		return false
	if not is_instance_valid(map_parent):
		push_error("Map parent node is missing.")
		return false

	# 加载地图场景
	var map_scene := ResourceLoader.load(MAP_SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if map_scene == null:
		push_error("Failed to load map scene: %s" % MAP_SCENE_PATH)
		return false

	# 创建实例
	var new_map := map_scene.instantiate() as Control
	if new_map == null:
		push_error("Failed to instantiate map scene: %s" % MAP_SCENE_PATH)
		return false

	var inventory_data := _get_player_inventory_data()
	if new_map.has_method("setup_inventory_data"):
		new_map.call("setup_inventory_data", inventory_data)

	# 添加到UI容器
	map_parent.add_child(new_map)
	map_instance = new_map

	# 锁定玩家
	_lock_player_for_map()
	return true

# 关闭地图：销毁实例 → 解锁玩家
func _close_map() -> void:
	var current_map := _get_map_instance()
	if current_map != null:
		current_map.queue_free()
	map_instance = null
	_unlock_player_from_map()

# ====================== 辅助功能 ======================
# 防抖判断：是否允许开关
func _can_toggle_map() -> bool:
	var now := Time.get_ticks_msec()
	if now - last_map_toggle_time_msec < MAP_TOGGLE_DEBOUNCE_MSEC:
		return false
	last_map_toggle_time_msec = now
	return true

# 获取有效的地图实例
func _get_map_instance() -> Control:
	if is_instance_valid(map_instance) and map_instance.is_inside_tree():
		return map_instance
	map_instance = null
	return null

# 状态同步：防止地图意外消失但玩家还在锁定
func _sync_map_state() -> void:
	if _get_map_instance() == null and player_locked_by_map:
		_unlock_player_from_map()


func _get_player_inventory_data() -> InventoryDate:
	if not is_instance_valid(player):
		return null
	return player.get("inventory_data") as InventoryDate

# ====================== 玩家锁定/解锁 ======================
# 打开地图时锁定玩家：停止移动、显示鼠标
func _lock_player_for_map() -> void:
	if player_locked_by_map:
		return

	if is_instance_valid(player):
		# 如果是3D角色，清空速度
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO
		# 保存玩家原来的状态
		player_process_mode_before_map = player.process_mode
		# 禁用玩家
		player.process_mode = Node.PROCESS_MODE_DISABLED

	# 显示鼠标
	mouse_mode_before_map = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player_locked_by_map = true

# 关闭地图时恢复玩家操作和鼠标模式
func _unlock_player_from_map() -> void:
	if not player_locked_by_map:
		return

	if is_instance_valid(player):
		player.process_mode = player_process_mode_before_map
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO

	Input.mouse_mode = mouse_mode_before_map
	player_locked_by_map = false
