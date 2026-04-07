extends GridMap

const PREVIEW_COLOR := Color(0.24, 0.58, 1.0, 0.32)
const PREVIEW_EMISSION := Color(0.24, 0.58, 1.0)
const PREVIEW_HEIGHT := 0.04
const PREVIEW_MARGIN := 0.08
const PREVIEW_Y_OFFSET := 0.01

@export var snap_size_in_cells: Vector2i = Vector2i.ONE

var is_industry_mode: bool = false
var preview_mesh_instance: MeshInstance3D


func _ready() -> void:
	set_snap_size(snap_size_in_cells)
	preview_mesh_instance = _create_preview_mesh_instance()
	add_child(preview_mesh_instance)
	_set_preview_visible(false)
	set_process(false)


func _process(_delta: float) -> void:
	if not is_industry_mode:
		return

	_update_hover_preview()

func _on_industry_area_entry() -> void:
	is_industry_mode = true
	set_process(true)


func _on_industry_area_exit() -> void:
	is_industry_mode = false
	_set_preview_visible(false)
	set_process(false)


func _update_hover_preview() -> void:
	var grid_cell: Variant = get_mouse_grid_cell()
	if grid_cell == null:
		_set_preview_visible(false)
		return

	preview_mesh_instance.position = _get_preview_local_position(grid_cell)
	_set_preview_visible(true)


func get_mouse_grid_cell() -> Variant:
	var world_position: Variant = get_mouse_world_position()
	if world_position == null:
		return null

	return local_to_snapped_map(to_local(world_position))


func _get_preview_local_position(grid_cell: Vector3i) -> Vector3:
	var preview_position := map_to_local(grid_cell)
	preview_position.x += float(snap_size_in_cells.x - 1) * cell_size.x * 0.5
	preview_position.y = float(grid_cell.y) * cell_size.y + PREVIEW_Y_OFFSET + PREVIEW_HEIGHT * 0.5
	preview_position.z += float(snap_size_in_cells.y - 1) * cell_size.z * 0.5
	return preview_position


func _create_preview_mesh_instance() -> MeshInstance3D:
	var preview := MeshInstance3D.new()
	preview.name = "PlacementPreview"

	var preview_mesh := BoxMesh.new()
	preview_mesh.size = _get_preview_mesh_size()
	preview.mesh = preview_mesh

	var preview_material := StandardMaterial3D.new()
	preview_material.albedo_color = PREVIEW_COLOR
	preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	preview_material.disable_receive_shadows = true
	preview_material.emission_enabled = true
	preview_material.emission = PREVIEW_EMISSION
	preview_material.emission_energy_multiplier = 0.4
	preview.material_override = preview_material

	return preview


func set_snap_size(value: Vector2i) -> void:
	snap_size_in_cells = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
	if preview_mesh_instance == null:
		return

	var preview_mesh := preview_mesh_instance.mesh as BoxMesh
	if preview_mesh != null:
		preview_mesh.size = _get_preview_mesh_size()


func _get_preview_mesh_size() -> Vector3:
	return Vector3(
		maxf(cell_size.x * float(maxi(snap_size_in_cells.x, 1)) - PREVIEW_MARGIN, 0.05),
		PREVIEW_HEIGHT,
		maxf(cell_size.z * float(maxi(snap_size_in_cells.y, 1)) - PREVIEW_MARGIN, 0.05)
	)


func _set_preview_visible(is_visible: bool) -> void:
	if preview_mesh_instance != null:
		preview_mesh_instance.visible = is_visible

func get_mouse_world_position() -> Variant:
	var current_camera := get_viewport().get_camera_3d()
	if current_camera == null:
		return null

	var ground := get_parent().get_node_or_null("Ground") as CollisionObject3D
	if ground == null:
		return null

	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = current_camera.project_ray_origin(mouse_position)
	var ray_direction: Vector3 = current_camera.project_ray_normal(mouse_position)
	var ray_length: float = maxf(current_camera.far, 1000.0)
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * ray_length)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = _get_ray_exclude_rids(ground)

	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null

	if hit.get("collider") != ground:
		return null

	return hit.get("position")


func _get_ray_exclude_rids(target_ground: CollisionObject3D) -> Array[RID]:
	var exclude_rids: Array[RID] = []
	_collect_exclude_rids(get_parent(), target_ground, exclude_rids)
	return exclude_rids


func _collect_exclude_rids(node: Node, target_ground: CollisionObject3D, exclude_rids: Array[RID]) -> void:
	if node is CollisionObject3D and node != target_ground:
		exclude_rids.append((node as CollisionObject3D).get_rid())

	for child: Node in node.get_children():
		_collect_exclude_rids(child, target_ground, exclude_rids)


func local_to_snapped_map(local_position: Vector3) -> Vector3i:
	var map_cell := local_to_map(local_position)
	map_cell.x = _snap_axis_to_footprint(map_cell.x, maxi(snap_size_in_cells.x, 1))
	map_cell.y = 0
	map_cell.z = _snap_axis_to_footprint(map_cell.z, maxi(snap_size_in_cells.y, 1))
	return map_cell


func _snap_axis_to_footprint(cell_index: int, footprint: int) -> int:
	return floori(float(cell_index) / float(footprint)) * footprint
