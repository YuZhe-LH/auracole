# 脚本挂载在 3D 主场景根节点，用于按 B 键 打开/关闭 地图/背包UI
extends Node3D

const CHARACTER_TOON_SHADER := preload("res://shaders/anime_character.gdshader")

# ====================== 常量配置 ======================
# 地图/背包场景文件路径（你自己的tscn文件）
const MAP_SCENE_PATH := "res://scenes/map.tscn"
const MAP_SCENE := preload("res://scenes/map.tscn")
const MAP_TOGGLE_ACTION := &"toggle_inventory"
const MAP_UI_LAYER_NAME := &"MapUiLayer"
const MAP_UI_ROOT_NAME := &"MapUiRoot"
# 按键防抖间隔（200毫秒内不能重复开关，防止连按乱套）
const MAP_TOGGLE_DEBOUNCE_MSEC := 200

# ====================== 卡通渲染配置 ======================
@export var apply_toon_to_entire_scene := true
@export_range(0.0, 1.0, 0.01) var roughness_bias := 0.12
@export_range(0.0, 1.0, 0.01) var rim_strength := 0.12
@export_range(0.0, 1.0, 0.01) var rim_tint := 0.65
@export var fallback_albedo := Color(0.82, 0.85, 0.92, 1.0)
@export var outline_color := Color(0.05, 0.06, 0.09, 1.0)
@export_range(0.0001, 0.015, 0.0005) var outline_width := 0.0009
@export var shadow_tint := Color(0.74, 0.8, 0.92, 1.0)
@export_range(0.0, 1.0, 0.01) var shadow_threshold := 0.5
@export_range(0.001, 0.2, 0.001) var shadow_softness := 0.035
@export_range(-0.2, 0.2, 0.01) var shadow_wrap := 0.04
@export var highlight_color := Color(1.0, 0.97, 0.98, 1.0)
@export_range(0.0, 1.0, 0.01) var highlight_strength := 0.05
@export_range(0.0, 1.0, 0.01) var highlight_threshold := 0.9
@export_range(0.001, 0.2, 0.001) var highlight_softness := 0.03
@export_range(0.0, 1.0, 0.01) var ambient_boost := 0.0

# ====================== 节点引用 ======================
# 玩家节点
@onready var player: Node = $Player

# UI父容器（CanvasGroup，用于放动态生成的地图/背包）
@onready var map_parent: Node = $CanvasGroup
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var directional_light: DirectionalLight3D = $DirectionalLight3D


# ====================== 状态变量 ======================
# 保存当前生成的地图/背包实例
var map_instance: Control
var map_parent: Control
# 上一次开关的时间（用于防抖）
var last_map_toggle_time_msec := -MAP_TOGGLE_DEBOUNCE_MSEC
# 保存打开地图前玩家的运行模式（用于关闭后还原）
var player_process_mode_before_map: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
# 保存打开地图前鼠标模式（捕获/显示）
var mouse_mode_before_map: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
# 标记玩家是否被地图锁定
var player_locked_by_map := false


# ====================== 初始化 ======================
func _ready() -> void:
	_ensure_map_parent()


# ====================== 输入检测 ======================
func _input(event: InputEvent) -> void:
	# 同步状态，防止异常
	_sync_map_state()

	var key_event := event as InputEventKey
	if key_event != null and key_event.echo:
		return

	# 按 B 键：开关地图/背包
	if event.is_action_pressed(MAP_TOGGLE_ACTION, true):
		if _toggle_map():
			get_viewport().set_input_as_handled()
		return

	# 按 ESC：如果地图打开就关闭
	if event.is_action_pressed("ui_cancel", true) and _try_close_map():
		get_viewport().set_input_as_handled()

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
	if _ensure_map_parent() == null:
		push_error("Map parent node is missing.")
		return false

	# 创建实例
	var new_map := MAP_SCENE.instantiate() as Control
	if new_map == null:
		push_error("Failed to instantiate map scene: %s" % MAP_SCENE_PATH)
		return false

	# 添加到UI容器
	_configure_map_instance(new_map)
	map_parent.add_child(new_map)
	map_instance = new_map

	var inventory_data := _get_player_inventory_data()
	if new_map.has_method("setup_inventory_data"):
		new_map.call_deferred("setup_inventory_data", inventory_data)

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
	if is_instance_valid(player):
		var direct_inventory := player.get("inventory_data") as InventoryDate
		if direct_inventory != null:
			return direct_inventory
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null
	var player_node := current_scene.find_child("Player", true, false)
	if player_node == null:
		return null
	return player_node.get("inventory_data") as InventoryDate


func _ensure_map_parent() -> Control:
	if is_instance_valid(map_parent) and map_parent.is_inside_tree():
		return map_parent

	var map_layer := get_node_or_null(String(MAP_UI_LAYER_NAME)) as CanvasLayer
	if map_layer == null:
		map_layer = CanvasLayer.new()
		map_layer.name = String(MAP_UI_LAYER_NAME)
		add_child(map_layer)

	var ui_root := map_layer.get_node_or_null(String(MAP_UI_ROOT_NAME)) as Control
	if ui_root == null:
		ui_root = Control.new()
		ui_root.name = String(MAP_UI_ROOT_NAME)
		ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_layer.add_child(ui_root)

	map_parent = ui_root
	return map_parent


func _configure_map_instance(new_map: Control) -> void:
	new_map.name = "MapView"
	new_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	new_map.mouse_filter = Control.MOUSE_FILTER_STOP

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


# ====================== 卡通渲染应用 ======================
func _apply_tps_demo_render_style() -> void:
	_setup_environment()
	_setup_directional_light()
	_apply_toon_materials(player if not apply_toon_to_entire_scene else self)


func _setup_environment() -> void:
	if world_environment == null or world_environment.environment == null:
		return

	var environment := world_environment.environment
	environment.ambient_light_color = Color(0.62, 0.73, 0.9, 1.0)
	environment.ambient_light_energy = 0.12
	environment.ambient_light_sky_contribution = 0.15
	environment.background_energy_multiplier = 0.35
	environment.background_intensity = 0.7
	environment.tonemap_exposure = 0.78
	environment.tonemap_white = 1.0
	environment.ssr_enabled = true
	environment.ssao_enabled = false
	environment.ssil_enabled = true
	environment.sdfgi_enabled = false
	environment.volumetric_fog_enabled = false
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_strength = 0.65
	environment.glow_mix = 0.04
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 2.4
	environment.glow_hdr_scale = 1.0
	environment.glow_hdr_luminance_cap = 12.0


func _setup_directional_light() -> void:
	if directional_light == null:
		return

	directional_light.light_energy = 0.42
	directional_light.light_indirect_energy = 0.12
	directional_light.shadow_enabled = true
	directional_light.rotation = Vector3(-1.3089969, 0.5183628, 0.0)


func _apply_toon_materials(root_node: Node) -> void:
	if root_node is MeshInstance3D:
		_toonize_mesh(root_node as MeshInstance3D)

	for child in root_node.get_children():
		_apply_toon_materials(child)


func _toonize_mesh(mesh_instance: MeshInstance3D) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return

	for surface_index in range(mesh.get_surface_count()):
		var source_material := mesh_instance.get_active_material(surface_index)
		var toon_material: Material
		if _is_character_mesh(mesh_instance):
			toon_material = _build_character_material(source_material)
		else:
			toon_material = _build_toon_material(source_material)
		if toon_material != null:
			mesh_instance.set_surface_override_material(surface_index, toon_material)

	if _is_character_mesh(mesh_instance):
		mesh_instance.material_overlay = _build_outline_material()


func _build_toon_material(source_material: Material) -> BaseMaterial3D:
	var toon_material: BaseMaterial3D

	if source_material is BaseMaterial3D:
		toon_material = (source_material as BaseMaterial3D).duplicate(true) as BaseMaterial3D
	else:
		var fallback_material := StandardMaterial3D.new()
		fallback_material.albedo_color = fallback_albedo
		toon_material = fallback_material

	toon_material.set_local_to_scene(true)
	toon_material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	toon_material.specular_mode = BaseMaterial3D.SPECULAR_TOON
	toon_material.roughness = clamp(toon_material.roughness + roughness_bias, 0.0, 1.0)
	toon_material.metallic = 0.0
	toon_material.rim_enabled = true
	toon_material.rim = max(toon_material.rim, rim_strength)
	toon_material.rim_tint = max(toon_material.rim_tint, rim_tint)
	return toon_material


func _build_outline_material() -> BaseMaterial3D:
	var outline_material := StandardMaterial3D.new()
	outline_material.set_local_to_scene(true)
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.albedo_color = outline_color
	outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
	outline_material.set_grow_enabled(true)
	outline_material.set_grow(outline_width)
	outline_material.set_flag(BaseMaterial3D.FLAG_DISABLE_FOG, true)
	outline_material.no_depth_test = false
	return outline_material


func _is_character_mesh(mesh_instance: MeshInstance3D) -> bool:
	return player != null and player.is_ancestor_of(mesh_instance)


func _build_character_material(source_material: Material) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CHARACTER_TOON_SHADER
	material.set_local_to_scene(true)
	material.set_shader_parameter("base_color", fallback_albedo)
	material.set_shader_parameter("shadow_color", shadow_tint)
	material.set_shader_parameter("shadow_threshold", shadow_threshold)
	material.set_shader_parameter("shadow_softness", shadow_softness)
	material.set_shader_parameter("shadow_wrap", shadow_wrap)
	material.set_shader_parameter("highlight_color", highlight_color)
	material.set_shader_parameter("highlight_strength", highlight_strength)
	material.set_shader_parameter("highlight_threshold", highlight_threshold)
	material.set_shader_parameter("highlight_softness", highlight_softness)
	material.set_shader_parameter("rim_strength", rim_strength)
	material.set_shader_parameter("rim_threshold", 0.72)
	material.set_shader_parameter("rim_softness", 0.08)
	material.set_shader_parameter("ambient_boost", ambient_boost)

	if source_material is BaseMaterial3D:
		var base_material := source_material as BaseMaterial3D
		material.set_shader_parameter("base_color", base_material.albedo_color)
		material.set_shader_parameter("use_texture", base_material.albedo_texture != null)
		material.set_shader_parameter("albedo_texture", base_material.albedo_texture)
		material.set_shader_parameter("alpha_cutoff", max(base_material.alpha_scissor_threshold, 0.1))
	else:
		material.set_shader_parameter("use_texture", false)
		material.set_shader_parameter("alpha_cutoff", 0.1)

	return material
