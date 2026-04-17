extends RefCounted
class_name ConveyorPathFinderV2


enum ArrowDirection {
	RIGHT = 0,
	DOWN = 90,
	LEFT = 180,
	UP = 270
}


class AStarNode:
	extends RefCounted

	var cell: Vector2i
	var g_cost: int
	var h_cost: int
	var parent: AStarNode
	var move_direction: Vector2i

	func _init(
		p_cell: Vector2i,
		p_g_cost: int = 0,
		p_h_cost: int = 0,
		p_parent: AStarNode = null,
		p_move_direction: Vector2i = Vector2i.ZERO
	) -> void:
		cell = p_cell
		g_cost = p_g_cost
		h_cost = p_h_cost
		parent = p_parent
		move_direction = p_move_direction

	func get_f_cost() -> int:
		return g_cost + h_cost


var map_manager: MapManager


func _init(p_map_manager: MapManager = null) -> void:
	map_manager = p_map_manager


func set_map_manager(p_map_manager: MapManager) -> void:
	map_manager = p_map_manager


func find_path(
	start_cell: Vector2i,
	goal_cell: Vector2i,
	additional_blocked: Dictionary = {},
	allow_cells: Dictionary = {}
) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	if map_manager == null:
		return empty_path
	if not map_manager.is_cell_inside_map(start_cell):
		return empty_path
	if not map_manager.is_cell_inside_map(goal_cell):
		return empty_path
	if _is_hard_blocked(start_cell, additional_blocked, allow_cells):
		return empty_path
	if _is_hard_blocked(goal_cell, additional_blocked, allow_cells):
		return empty_path
	if start_cell == goal_cell:
		return [start_cell]

	var open_nodes: Dictionary = {}
	var closed_states: Dictionary = {}
	var start_node := AStarNode.new(
		start_cell,
		0,
		manhattan_distance(start_cell, goal_cell),
		null,
		Vector2i.ZERO
	)
	open_nodes[_get_state_key(start_cell, Vector2i.ZERO)] = start_node

	while not open_nodes.is_empty():
		var current_node: AStarNode = _get_lowest_cost_node(open_nodes)
		var current_key := _get_state_key(current_node.cell, current_node.move_direction)
		open_nodes.erase(current_key)
		closed_states[current_key] = true

		if current_node.cell == goal_cell:
			var path_cells := retrace_path(current_node)
			var directed_path := build_directed_path(path_cells)
			if map_manager.can_accept_directed_conveyor_path(directed_path):
				return path_cells
			continue

		for neighbor in get_neighbors(current_node.cell):
			var move_direction := neighbor - current_node.cell
			var neighbor_key := _get_state_key(neighbor, move_direction)
			if closed_states.has(neighbor_key):
				continue
			if _is_hard_blocked(neighbor, additional_blocked, allow_cells):
				continue

			var tentative_g_cost := current_node.g_cost + 1
			var existing_node: AStarNode = open_nodes.get(neighbor_key) as AStarNode
			if existing_node == null or tentative_g_cost < existing_node.g_cost:
				open_nodes[neighbor_key] = AStarNode.new(
					neighbor,
					tentative_g_cost,
					manhattan_distance(neighbor, goal_cell),
					current_node,
					move_direction
				)

	return empty_path


func find_directed_path(
	start_cell: Vector2i,
	goal_cell: Vector2i,
	additional_blocked: Dictionary = {},
	allow_cells: Dictionary = {},
	segment_index: int = 0
) -> Array:
	var path_cells := find_path(start_cell, goal_cell, additional_blocked, allow_cells)
	return build_directed_path(path_cells, segment_index)


func build_directed_path(path_cells: Array[Vector2i], segment_index: int = 0) -> Array:
	var directed_cells: Array = []
	if path_cells.is_empty():
		return directed_cells

	for i in path_cells.size():
		var cell := path_cells[i]
		var flow_direction := Vector2i.RIGHT
		if i < path_cells.size() - 1:
			flow_direction = path_cells[i + 1] - cell
		elif i > 0:
			flow_direction = cell - path_cells[i - 1]

		directed_cells.append({
			"position": cell,
			"arrow_direction": vector_to_arrow_direction(flow_direction),
			"flow_direction": flow_direction,
			"segment_index": segment_index
		})

	return directed_cells


func vector_to_arrow_direction(vec: Vector2i) -> int:
	if vec == Vector2i.UP:
		return ArrowDirection.UP
	if vec == Vector2i.RIGHT:
		return ArrowDirection.RIGHT
	if vec == Vector2i.DOWN:
		return ArrowDirection.DOWN
	if vec == Vector2i.LEFT:
		return ArrowDirection.LEFT
	return ArrowDirection.RIGHT


func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func get_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions: Array[Vector2i] = [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN
	]

	for direction in directions:
		var next_cell := cell + direction
		if map_manager != null and map_manager.is_cell_inside_map(next_cell):
			neighbors.append(next_cell)

	return neighbors


func retrace_path(end_node: AStarNode) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current: AStarNode = end_node
	while current != null:
		path.append(current.cell)
		current = current.parent

	path.reverse()
	return path


func _get_lowest_cost_node(open_nodes: Dictionary) -> AStarNode:
	var best_node: AStarNode = null
	for candidate in open_nodes.values():
		var node := candidate as AStarNode
		if best_node == null:
			best_node = node
			continue

		var node_f_cost := node.get_f_cost()
		var best_f_cost := best_node.get_f_cost()
		if node_f_cost < best_f_cost:
			best_node = node
			continue
		if node_f_cost == best_f_cost and node.h_cost < best_node.h_cost:
			best_node = node

	return best_node


func _is_hard_blocked(cell: Vector2i, additional_blocked: Dictionary, allow_cells: Dictionary) -> bool:
	if allow_cells.has(cell):
		return false
	if map_manager == null:
		return true
	if map_manager.has_building_at_cell(cell):
		return true
	if additional_blocked.has(cell):
		return true
	return false


func _get_state_key(cell: Vector2i, move_direction: Vector2i) -> String:
	return "%d:%d:%d:%d" % [cell.x, cell.y, move_direction.x, move_direction.y]
