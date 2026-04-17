extends Node2D
class_name MapManager

const CONVEYOR_ARROW_V2_SCRIPT: GDScript = preload("res://scripts/placement_logic/conveyor_arrow_v2.gd")

@export var grid_rows: int = 100
@export var grid_cols: int = 100

const CELL_SIZE: int = 64
const INVALID_CELL := Vector2i(-1, -1)
const BORDER_TOP: int = 1
const BORDER_RIGHT: int = 2
const BORDER_BOTTOM: int = 4
const BORDER_LEFT: int = 8
const CONVEYOR_COLORS := {
	"conveyor_fill": Color(1.0, 1.0, 0.0, 0.7),
	"conveyor_border": Color(0.0, 1.0, 0.0, 1.0),
	"cross_fill": Color(1.0, 0.1, 0.1, 0.78),
	"cross_border": Color(0.8, 0.0, 0.0, 1.0),
	"path_preview": Color(1.0, 1.0, 0.0, 0.4),
	"cross_preview": Color(1.0, 0.15, 0.15, 0.55),
	"start": Color(0.0, 1.0, 0.0, 0.5),
	"end": Color(0.0, 0.0, 1.0, 0.5),
	"arrow_color": Color(0.0, 0.0, 0.0, 0.8),
	"border_thickness": 2.0
}

var _occupied: Dictionary = {}
var occupied_cells: Dictionary:
	get:
		return _occupied

var directed_conveyors: Dictionary = {}
var conveyor_cells: Dictionary = {}
var _next_conveyor_id: int = 1

var _preview_visible: bool = false
var _preview_cell: Vector2i = Vector2i.ZERO
var _preview_size: Vector2i = Vector2i.ONE
var _preview_valid: bool = false

var _conveyor_preview_cells: Array = []
var _conveyor_preview_lookup: Dictionary = {}
var _conveyor_start_cell: Vector2i = INVALID_CELL
var _conveyor_end_cell: Vector2i = INVALID_CELL
var _conveyor_start_visible: bool = false
var _conveyor_end_visible: bool = false
var _conveyor_path_valid: bool = true


func _ready() -> void:
	queue_redraw()


func get_map_pixel_size() -> Vector2:
	return Vector2(grid_cols * CELL_SIZE, grid_rows * CELL_SIZE)


func is_point_inside_map(world_pos: Vector2) -> bool:
	var map_size := get_map_pixel_size()
	return world_pos.x >= 0.0 and world_pos.y >= 0.0 and world_pos.x < map_size.x and world_pos.y < map_size.y


func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / CELL_SIZE), floori(world_pos.y / CELL_SIZE))


func is_cell_inside_map(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_cols and cell.y < grid_rows


func cell_to_world_center(top_left_cell: Vector2i, footprint: Vector2i) -> Vector2:
	var width_cells := footprint.y
	var height_cells := footprint.x
	return Vector2(
		(top_left_cell.x + width_cells * 0.5) * CELL_SIZE,
		(top_left_cell.y + height_cells * 0.5) * CELL_SIZE
	)


func can_place(top_left_cell: Vector2i, footprint: Vector2i) -> bool:
	var width_cells := footprint.y
	var height_cells := footprint.x
	if top_left_cell.x < 0 or top_left_cell.y < 0:
		return false
	if top_left_cell.x + width_cells > grid_cols:
		return false
	if top_left_cell.y + height_cells > grid_rows:
		return false

	for row in height_cells:
		for col in width_cells:
			var cell := Vector2i(top_left_cell.x + col, top_left_cell.y + row)
			if _occupied.has(cell) or conveyor_cells.has(cell):
				return false
	return true


func occupy(top_left_cell: Vector2i, footprint: Vector2i, building: Building) -> void:
	var width_cells := footprint.y
	var height_cells := footprint.x
	for row in height_cells:
		for col in width_cells:
			var cell := Vector2i(top_left_cell.x + col, top_left_cell.y + row)
			_occupied[cell] = building
	queue_redraw()


func free_area(top_left_cell: Vector2i, footprint: Vector2i) -> void:
	var width_cells := footprint.y
	var height_cells := footprint.x
	for row in height_cells:
		for col in width_cells:
			var cell := Vector2i(top_left_cell.x + col, top_left_cell.y + row)
			_occupied.erase(cell)
	queue_redraw()


func get_building_at_cell(cell: Vector2i) -> Building:
	return _occupied.get(cell) as Building


func has_building_at_cell(cell: Vector2i) -> bool:
	return _occupied.has(cell)


func get_building_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell_variant in _occupied.keys():
		cells.append(cell_variant as Vector2i)
	return cells


func is_cell_occupied_by_building(cell: Vector2i) -> bool:
	return has_building_at_cell(cell)


func has_conveyor_at_cell(cell: Vector2i) -> bool:
	return conveyor_cells.has(cell)


func is_cross_conveyor_cell(cell: Vector2i) -> bool:
	if not conveyor_cells.has(cell):
		return false
	return bool(conveyor_cells[cell].get("is_cross", false))


func get_conveyor_id_at_cell(cell: Vector2i) -> int:
	if not conveyor_cells.has(cell):
		return -1

	var metadata: Dictionary = conveyor_cells[cell]
	var conveyor_ids: Array = metadata.get("conveyor_ids", [])
	if conveyor_ids.is_empty():
		return -1
	return int(conveyor_ids[0])


func get_conveyor_id_at_world(world_pos: Vector2) -> int:
	if not is_point_inside_map(world_pos):
		return -1
	return get_conveyor_id_at_cell(world_to_cell(world_pos))


func get_building_at_world(world_pos: Vector2) -> Building:
	if not is_point_inside_map(world_pos):
		return null
	return get_building_at_cell(world_to_cell(world_pos))


func get_building_at_position(world_pos: Vector2) -> Building:
	return get_building_at_world(world_pos)


func get_nearest_building_cell(building: Building, from_cell: Vector2i) -> Vector2i:
	if building == null:
		return INVALID_CELL

	var building_cells: Array[Vector2i] = building.get_occupied_cells()
	if building_cells.is_empty():
		return INVALID_CELL

	var nearest_cell := building_cells[0]
	var min_distance := INF
	for cell in building_cells:
		var distance := absi(cell.x - from_cell.x) + absi(cell.y - from_cell.y)
		if distance < min_distance:
			min_distance = distance
			nearest_cell = cell

	return nearest_cell


func get_building_connection_options(building: Building) -> Array:
	var options: Array = []
	if building == null:
		return options

	var seen: Dictionary = {}
	for device_cell in building.get_connection_points():
		var neighbors: Array[Vector2i] = [
			device_cell + Vector2i.UP,
			device_cell + Vector2i.RIGHT,
			device_cell + Vector2i.DOWN,
			device_cell + Vector2i.LEFT
		]
		for path_cell in neighbors:
			if not is_cell_inside_map(path_cell):
				continue
			if building.is_position_inside(path_cell):
				continue

			var occupant := get_building_at_cell(path_cell)
			if occupant != null and occupant != building:
				continue

			var key := "%d:%d:%d:%d" % [device_cell.x, device_cell.y, path_cell.x, path_cell.y]
			if seen.has(key):
				continue
			seen[key] = true
			options.append({
				"device_cell": device_cell,
				"path_cell": path_cell
			})

	return options


func get_nearest_connection_option(building: Building, from_cell: Vector2i) -> Dictionary:
	var options := get_building_connection_options(building)
	if options.is_empty():
		return {}

	var nearest_option: Dictionary = options[0]
	var min_distance := INF
	for option_variant in options:
		var option: Dictionary = option_variant
		var device_cell: Vector2i = option["device_cell"]
		var distance := absi(device_cell.x - from_cell.x) + absi(device_cell.y - from_cell.y)
		if distance < min_distance:
			min_distance = distance
			nearest_option = option

	return nearest_option


func get_building_occupied_cells() -> Array[Vector2i]:
	return get_building_cells()


func set_preview(top_left_cell: Vector2i, footprint: Vector2i, valid: bool, p_visible: bool = true) -> void:
	_preview_cell = top_left_cell
	_preview_size = footprint
	_preview_valid = valid
	_preview_visible = p_visible
	queue_redraw()


func clear_preview() -> void:
	if not _preview_visible:
		return
	_preview_visible = false
	queue_redraw()


func set_directed_conveyor_preview(
	start_cell: Vector2i,
	start_visible: bool,
	end_cell: Vector2i,
	end_visible: bool,
	directed_cells: Array,
	path_valid: bool = true
) -> void:
	_conveyor_start_cell = start_cell
	_conveyor_start_visible = start_visible
	_conveyor_end_cell = end_cell
	_conveyor_end_visible = end_visible
	_conveyor_path_valid = path_valid
	_conveyor_preview_cells = _duplicate_directed_cells(directed_cells)
	_conveyor_preview_lookup = _build_lookup_from_directed_cells(_conveyor_preview_cells)
	queue_redraw()


func clear_directed_conveyor_preview() -> void:
	_conveyor_start_visible = false
	_conveyor_end_visible = false
	_conveyor_start_cell = INVALID_CELL
	_conveyor_end_cell = INVALID_CELL
	_conveyor_path_valid = true
	_conveyor_preview_cells.clear()
	_conveyor_preview_lookup.clear()
	queue_redraw()


func evaluate_directed_conveyor_path(directed_cells: Array) -> Dictionary:
	return {
		"valid": _can_add_directed_conveyor(directed_cells),
		"cells": _resolve_directed_cells_for_display(directed_cells)
	}


func can_accept_directed_conveyor_path(directed_cells: Array) -> bool:
	return _can_add_directed_conveyor(directed_cells)


func add_directed_conveyor(directed_cells: Array) -> int:
	if directed_cells.is_empty():
		return -1
	if not _can_add_directed_conveyor(directed_cells):
		return -1

	var conveyor_id := _next_conveyor_id
	_next_conveyor_id += 1

	var stored_cells := _duplicate_directed_cells(directed_cells)
	for cell_data in stored_cells:
		cell_data["conveyor_id"] = conveyor_id

	directed_conveyors[conveyor_id] = stored_cells
	_rebuild_conveyor_cells()
	queue_redraw()
	return conveyor_id


func remove_conveyor(conveyor_id: int) -> bool:
	if not directed_conveyors.has(conveyor_id):
		return false

	directed_conveyors.erase(conveyor_id)
	_rebuild_conveyor_cells()
	queue_redraw()
	return true


func _draw() -> void:
	var map_size := get_map_pixel_size()
	draw_rect(Rect2(Vector2.ZERO, map_size), Color.WHITE, true)

	var line_color := Color.BLACK
	for col in grid_cols + 1:
		var x := float(col * CELL_SIZE)
		draw_line(Vector2(x, 0.0), Vector2(x, map_size.y), line_color, 1.0, true)

	for row in grid_rows + 1:
		var y := float(row * CELL_SIZE)
		draw_line(Vector2(0.0, y), Vector2(map_size.x, y), line_color, 1.0, true)

	for cell_variant in conveyor_cells.keys():
		var cell := cell_variant as Vector2i
		var metadata: Dictionary = conveyor_cells[cell]
		var fill_color: Color = CONVEYOR_COLORS["cross_fill"] if bool(metadata.get("is_cross", false)) else CONVEYOR_COLORS["conveyor_fill"]
		draw_conveyor_fill(cell, fill_color)

	for cell_variant in conveyor_cells.keys():
		var cell := cell_variant as Vector2i
		var metadata: Dictionary = conveyor_cells[cell]
		var border_color: Color = CONVEYOR_COLORS["cross_border"] if bool(metadata.get("is_cross", false)) else CONVEYOR_COLORS["conveyor_border"]
		draw_conveyor_border(cell, conveyor_cells, border_color)

	for cell_variant in conveyor_cells.keys():
		var cell := cell_variant as Vector2i
		var metadata: Dictionary = conveyor_cells[cell]
		if bool(metadata.get("is_cross", false)):
			continue

		var directions: Array = metadata.get("directions", [])
		if directions.is_empty():
			continue

		draw_conveyor_arrow(cell, int(directions[0]), CONVEYOR_COLORS["arrow_color"])

	for cell_data_variant in _conveyor_preview_cells:
		var cell_data: Dictionary = cell_data_variant
		var fill_color := _get_preview_fill_color(cell_data)
		draw_conveyor_fill(cell_data["position"], fill_color)

	for cell_data_variant in _conveyor_preview_cells:
		var cell_data: Dictionary = cell_data_variant
		var border_color := _get_preview_border_color(cell_data)
		draw_conveyor_border(cell_data["position"], _conveyor_preview_lookup, border_color)

	for cell_data_variant in _conveyor_preview_cells:
		var cell_data: Dictionary = cell_data_variant
		if bool(cell_data.get("is_cross", false)):
			continue

		var arrow_color: Color = CONVEYOR_COLORS["arrow_color"]
		arrow_color.a = 0.72 if _conveyor_path_valid else 0.45
		draw_conveyor_arrow(cell_data["position"], int(cell_data["arrow_direction"]), arrow_color)

	_draw_conveyor_marker(_conveyor_start_cell, _conveyor_start_visible, CONVEYOR_COLORS["start"])
	_draw_conveyor_marker(_conveyor_end_cell, _conveyor_end_visible, CONVEYOR_COLORS["end"])

	if _preview_visible:
		var width_cells := _preview_size.y
		var height_cells := _preview_size.x
		var preview_rect := Rect2(
			Vector2(_preview_cell.x * CELL_SIZE, _preview_cell.y * CELL_SIZE),
			Vector2(width_cells * CELL_SIZE, height_cells * CELL_SIZE)
		)
		var fill_color := Color(0.12, 0.85, 0.25, 0.35) if _preview_valid else Color(0.92, 0.12, 0.12, 0.35)
		var border_color := Color(0.05, 0.6, 0.2, 0.95) if _preview_valid else Color(0.8, 0.05, 0.05, 0.95)
		draw_rect(preview_rect, fill_color, true)
		draw_rect(preview_rect, border_color, false, 2.0, true)


func draw_conveyor_fill(cell: Vector2i, color: Color) -> void:
	if not is_cell_inside_map(cell):
		return
	draw_rect(_get_cell_rect(cell), color, true)


func draw_conveyor_border(cell: Vector2i, lookup: Dictionary, color: Color) -> void:
	if not lookup.has(cell):
		return

	var border_mask := _build_border_mask(cell, lookup)
	if border_mask == 0:
		return

	var rect := _get_cell_rect(cell)
	var top_left := rect.position
	var top_right := Vector2(rect.end.x, rect.position.y)
	var bottom_left := Vector2(rect.position.x, rect.end.y)
	var bottom_right := rect.end
	var thickness := float(CONVEYOR_COLORS["border_thickness"])

	if (border_mask & BORDER_TOP) != 0:
		draw_line(top_left, top_right, color, thickness, true)
	if (border_mask & BORDER_RIGHT) != 0:
		draw_line(top_right, bottom_right, color, thickness, true)
	if (border_mask & BORDER_BOTTOM) != 0:
		draw_line(bottom_left, bottom_right, color, thickness, true)
	if (border_mask & BORDER_LEFT) != 0:
		draw_line(top_left, bottom_left, color, thickness, true)


func draw_conveyor_arrow(cell: Vector2i, direction: int, color: Color) -> void:
	if not is_cell_inside_map(cell):
		return

	var world_pos: Vector2 = cell_to_world_center(cell, Vector2i.ONE)
	var polygon: PackedVector2Array = CONVEYOR_ARROW_V2_SCRIPT.get_arrow_polygon(world_pos, CELL_SIZE, direction)
	var colors: PackedColorArray = PackedColorArray()
	for _i in polygon.size():
		colors.append(color)
	draw_polygon(polygon, colors)


func _draw_conveyor_marker(cell: Vector2i, is_marker_visible: bool, color: Color) -> void:
	if not is_marker_visible or not is_cell_inside_map(cell):
		return

	var rect := _get_cell_rect(cell)
	draw_rect(rect, color, true)
	draw_rect(rect, color.darkened(0.25), false, 2.0, true)


func _get_cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(
		Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE),
		Vector2.ONE * CELL_SIZE
	)


func _build_border_mask(cell: Vector2i, lookup: Dictionary) -> int:
	var border_mask := 0

	if not lookup.has(cell + Vector2i.UP):
		border_mask |= BORDER_TOP
	if not lookup.has(cell + Vector2i.RIGHT):
		border_mask |= BORDER_RIGHT
	if not lookup.has(cell + Vector2i.DOWN):
		border_mask |= BORDER_BOTTOM
	if not lookup.has(cell + Vector2i.LEFT):
		border_mask |= BORDER_LEFT

	return border_mask


func _can_add_directed_conveyor(directed_cells: Array) -> bool:
	if directed_cells.is_empty():
		return false

	var seen: Dictionary = {}
	for cell_data_variant in directed_cells:
		var cell_data: Dictionary = cell_data_variant
		if not cell_data.has("position"):
			return false

		var cell: Vector2i = cell_data["position"]
		if not is_cell_inside_map(cell):
			return false
		if seen.has(cell):
			return false
		if _occupied.has(cell):
			return false

		seen[cell] = true

	if _creates_wide_conveyor_area(directed_cells):
		return false

	return true


func _resolve_directed_cells_for_display(directed_cells: Array) -> Array:
	var resolved: Array = []
	for cell_data_variant in directed_cells:
		var cell_data: Dictionary = cell_data_variant
		var cell_copy: Dictionary = cell_data.duplicate(true)
		var cell: Vector2i = cell_copy["position"]
		cell_copy["is_cross"] = _is_preview_cross_cell(cell)
		resolved.append(cell_copy)
	return resolved


func _is_preview_cross_cell(cell: Vector2i) -> bool:
	return conveyor_cells.has(cell)


func _creates_wide_conveyor_area(directed_cells: Array) -> bool:
	var occupied_lookup: Dictionary = {}
	for cell_variant in conveyor_cells.keys():
		occupied_lookup[cell_variant as Vector2i] = true

	for cell_data_variant in directed_cells:
		var cell_data: Dictionary = cell_data_variant
		occupied_lookup[cell_data["position"]] = true

	for cell_data_variant in directed_cells:
		var cell_data: Dictionary = cell_data_variant
		var cell: Vector2i = cell_data["position"]
		var top_left_candidates: Array[Vector2i] = [
			cell,
			cell + Vector2i.LEFT,
			cell + Vector2i.UP,
			cell + Vector2i(-1, -1)
		]
		for top_left in top_left_candidates:
			if _is_full_two_by_two(top_left, occupied_lookup):
				return true

	return false


func _is_full_two_by_two(top_left: Vector2i, occupied_lookup: Dictionary) -> bool:
	var cells: Array[Vector2i] = [
		top_left,
		top_left + Vector2i.RIGHT,
		top_left + Vector2i.DOWN,
		top_left + Vector2i.RIGHT + Vector2i.DOWN
	]
	for cell in cells:
		if not is_cell_inside_map(cell):
			return false
		if not occupied_lookup.has(cell):
			return false
	return true


func _rebuild_conveyor_cells() -> void:
	conveyor_cells.clear()

	for conveyor_id_variant in directed_conveyors.keys():
		var conveyor_id := int(conveyor_id_variant)
		var path_cells: Array = directed_conveyors[conveyor_id]
		for cell_data_variant in path_cells:
			var cell_data: Dictionary = cell_data_variant
			if not cell_data.has("position") or not cell_data.has("arrow_direction"):
				continue

			var cell: Vector2i = cell_data["position"]
			var direction: int = int(cell_data["arrow_direction"])
			var metadata: Dictionary = conveyor_cells.get(cell, {
				"position": cell,
				"conveyor_ids": [],
				"directions": [],
				"is_cross": false
			})

			var conveyor_ids: Array = metadata["conveyor_ids"]
			if not conveyor_ids.has(conveyor_id):
				conveyor_ids.append(conveyor_id)

			var directions: Array = metadata["directions"]
			if not directions.has(direction):
				directions.append(direction)

			metadata["is_cross"] = conveyor_ids.size() > 1
			conveyor_cells[cell] = metadata

	for cell_variant in conveyor_cells.keys():
		var cell := cell_variant as Vector2i
		var metadata: Dictionary = conveyor_cells[cell]
		var conveyor_ids: Array = metadata.get("conveyor_ids", [])
		metadata["is_cross"] = conveyor_ids.size() > 1
		conveyor_cells[cell] = metadata


func _get_preview_fill_color(cell_data: Dictionary) -> Color:
	if not _conveyor_path_valid:
		return Color(1.0, 0.2, 0.2, 0.35)
	if bool(cell_data.get("is_cross", false)):
		return CONVEYOR_COLORS["cross_preview"]
	return CONVEYOR_COLORS["path_preview"]


func _get_preview_border_color(cell_data: Dictionary) -> Color:
	if not _conveyor_path_valid:
		return Color(0.85, 0.1, 0.1, 0.65)
	if bool(cell_data.get("is_cross", false)):
		return CONVEYOR_COLORS["cross_border"]

	var border_color: Color = CONVEYOR_COLORS["conveyor_border"]
	border_color.a = 0.85
	return border_color


func _duplicate_directed_cells(directed_cells: Array) -> Array:
	var duplicated: Array = []
	for cell_data_variant in directed_cells:
		var cell_data: Dictionary = cell_data_variant
		duplicated.append(cell_data.duplicate(true))
	return duplicated


func _build_lookup_from_directed_cells(directed_cells: Array) -> Dictionary:
	var lookup: Dictionary = {}
	for cell_data_variant in directed_cells:
		var cell_data: Dictionary = cell_data_variant
		lookup[cell_data["position"]] = true
	return lookup
