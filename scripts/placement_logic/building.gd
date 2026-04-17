extends Node2D
class_name Building

static var _next_device_id: int = 1

@onready var cover: Polygon2D = $Cover
@onready var sprite: Sprite2D = $Sprite2D

const DEFAULT_Z_INDEX: int = 10
const DRAG_Z_INDEX: int = 30
const DRAG_PREVIEW_MODULATE := Color(1.0, 1.0, 1.0, 0.72)

var item_id: String = ""
var device_id: int = -1
var top_left_cell: Vector2i = Vector2i.ZERO
var footprint: Vector2i = Vector2i.ONE # rows, cols
var cell_size_px: int = 0
var rotation_steps: int = 0


func _ready() -> void:
	if device_id == -1:
		device_id = _next_device_id
		_next_device_id += 1
	add_to_group("buildings")


func setup(p_item_id: String, texture: Texture2D, cell_size: int, p_footprint: Vector2i) -> void:
	item_id = p_item_id
	cell_size_px = cell_size
	z_index = DEFAULT_Z_INDEX
	sprite.texture = texture
	set_footprint(p_footprint)


func set_top_left_cell(p_top_left_cell: Vector2i) -> void:
	top_left_cell = p_top_left_cell


func set_footprint(p_footprint: Vector2i) -> void:
	footprint = p_footprint
	_refresh_visual()


func rotate_clockwise() -> void:
	rotation_steps = posmod(rotation_steps + 1, 4)
	footprint = Vector2i(footprint.y, footprint.x)
	_refresh_visual()


func set_drag_preview(active: bool) -> void:
	modulate = DRAG_PREVIEW_MODULATE if active else Color.WHITE
	z_index = DRAG_Z_INDEX if active else DEFAULT_Z_INDEX


func is_position_inside(cell: Vector2i) -> bool:
	for occupied_cell in get_occupied_cells():
		if occupied_cell == cell:
			return true
	return false


func get_occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for row in footprint.x:
		for col in footprint.y:
			cells.append(Vector2i(top_left_cell.x + col, top_left_cell.y + row))
	return cells


func get_connection_points() -> Array[Vector2i]:
	var connection_points: Array[Vector2i] = []
	for cell in get_occupied_cells():
		if is_edge_cell(cell):
			connection_points.append(cell)
	return connection_points


func is_edge_cell(cell: Vector2i) -> bool:
	if not is_position_inside(cell):
		return false

	var neighbors: Array[Vector2i] = [
		cell + Vector2i.UP,
		cell + Vector2i.RIGHT,
		cell + Vector2i.DOWN,
		cell + Vector2i.LEFT
	]
	for neighbor in neighbors:
		if not is_position_inside(neighbor):
			return true

	return false


func _refresh_visual() -> void:
	if cell_size_px <= 0:
		return
	var pixel_size := Vector2(footprint.y * cell_size_px, footprint.x * cell_size_px)
	var half := pixel_size * 0.5
	cover.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	])
	cover.color = Color.WHITE

	sprite.centered = true
	sprite.rotation = rotation_steps * PI * 0.5
	if sprite.texture != null:
		var tex_size := sprite.texture.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			if rotation_steps % 2 == 0:
				sprite.scale = Vector2(pixel_size.x / tex_size.x, pixel_size.y / tex_size.y)
			else:
				sprite.scale = Vector2(pixel_size.y / tex_size.x, pixel_size.x / tex_size.y)
