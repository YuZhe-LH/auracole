extends Node
class_name DirectedConveyorPlannerV2

signal conveyor_mode_changed(active: bool)
signal conveyor_generated(conveyor_id: int)

enum PlannerState {
	IDLE,
	SELECT_START_DEVICE,
	SELECT_END_DEVICE
}

const INVALID_CELL := Vector2i(-1, -1)

var map_manager: MapManager
var path_finder: ConveyorPathFinderV2
var state: PlannerState = PlannerState.IDLE

var _is_active: bool = false
var _start_building: Building = null
var _start_display_cell: Vector2i = INVALID_CELL
var _start_path_cell: Vector2i = INVALID_CELL
var _hover_target_building: Building = null
var _hover_display_cell: Vector2i = INVALID_CELL
var _hover_path_cell: Vector2i = INVALID_CELL
var _current_preview_cells: Array[Vector2i] = []


func setup(p_map_manager: MapManager) -> void:
	map_manager = p_map_manager
	path_finder = ConveyorPathFinderV2.new(map_manager)


func is_active() -> bool:
	return _is_active


func enter_mode() -> void:
	_is_active = true
	state = PlannerState.SELECT_START_DEVICE
	_reset_planning_state()
	_push_preview()
	conveyor_mode_changed.emit(true)


func exit_mode() -> void:
	_is_active = false
	state = PlannerState.IDLE
	_reset_planning_state()
	_push_preview()
	conveyor_mode_changed.emit(false)


func handle_left_click(world_pos: Vector2) -> void:
	if not _is_active or map_manager == null:
		return
	if not map_manager.is_point_inside_map(world_pos):
		return

	var clicked_cell := map_manager.world_to_cell(world_pos)
	var clicked_building := map_manager.get_building_at_position(world_pos)

	match state:
		PlannerState.SELECT_START_DEVICE:
			if clicked_building != null:
				_select_start_building(clicked_building, clicked_cell)
		PlannerState.SELECT_END_DEVICE:
			if clicked_building == null:
				return
			if clicked_building == _start_building:
				_select_start_building(clicked_building, clicked_cell)
				return

			_update_preview_to_building(clicked_building, clicked_cell)
			_finalize_current_preview()


func handle_mouse_move(world_pos: Vector2) -> void:
	if not _is_active or state != PlannerState.SELECT_END_DEVICE or map_manager == null:
		return

	if not map_manager.is_point_inside_map(world_pos):
		_clear_hover_preview()
		_push_preview()
		return

	var hovered_cell := map_manager.world_to_cell(world_pos)
	var hovered_building := map_manager.get_building_at_position(world_pos)
	if hovered_building != null and hovered_building != _start_building:
		_update_preview_to_building(hovered_building, hovered_cell)
		return
	if hovered_building == _start_building:
		_clear_hover_preview()
		_push_preview()
		return

	_update_preview_to_cell(hovered_cell)


func cancel_current_segment() -> void:
	if not _is_active:
		return

	match state:
		PlannerState.SELECT_START_DEVICE:
			exit_mode()
		PlannerState.SELECT_END_DEVICE:
			state = PlannerState.SELECT_START_DEVICE
			_reset_planning_state()
			_push_preview()


func generate_complete_conveyor() -> int:
	if not _is_active:
		return -1

	exit_mode()
	return -1


func _select_start_building(building: Building, clicked_cell: Vector2i) -> void:
	if building == null or map_manager == null:
		return

	var connection_option: Dictionary = map_manager.get_nearest_connection_option(building, clicked_cell)
	if connection_option.is_empty():
		return

	_start_building = building
	_start_display_cell = map_manager.get_nearest_building_cell(building, clicked_cell)
	_start_path_cell = connection_option["path_cell"]
	state = PlannerState.SELECT_END_DEVICE
	_clear_hover_preview()
	_push_preview()


func _update_preview_to_cell(target_cell: Vector2i) -> void:
	if _start_path_cell == INVALID_CELL or map_manager == null:
		return
	if not map_manager.is_cell_inside_map(target_cell):
		return

	_hover_target_building = null
	_hover_display_cell = target_cell
	_hover_path_cell = target_cell

	if map_manager.has_building_at_cell(target_cell):
		_current_preview_cells.clear()
		_push_preview()
		return

	_current_preview_cells = path_finder.find_path(
		_start_path_cell,
		target_cell,
		{},
		{_start_path_cell: true, target_cell: true}
	)
	_push_preview()


func _update_preview_to_building(target_building: Building, hovered_cell: Vector2i) -> void:
	if _start_path_cell == INVALID_CELL or map_manager == null:
		return

	_hover_target_building = target_building
	_hover_display_cell = map_manager.get_nearest_building_cell(target_building, hovered_cell)
	_hover_path_cell = INVALID_CELL
	_current_preview_cells.clear()

	var best_preview := _find_best_preview_to_building(target_building, _hover_display_cell)
	if not best_preview.is_empty():
		_hover_display_cell = best_preview["device_cell"]
		_hover_path_cell = best_preview["path_cell"]
		_current_preview_cells = best_preview["path_cells"]

	_push_preview()


func _find_best_preview_to_building(target_building: Building, hint_cell: Vector2i) -> Dictionary:
	var best_path: Array[Vector2i] = []
	var best_device_cell := INVALID_CELL
	var best_path_cell := INVALID_CELL
	var best_length := INF
	var best_hint_distance := INF

	for option_variant in map_manager.get_building_connection_options(target_building):
		var option: Dictionary = option_variant
		var target_device_cell: Vector2i = option["device_cell"]
		var target_path_cell: Vector2i = option["path_cell"]
		var path_cells := path_finder.find_path(
			_start_path_cell,
			target_path_cell,
			{},
			{_start_path_cell: true, target_path_cell: true}
		)
		if path_cells.is_empty():
			continue

		var hint_distance := absi(target_device_cell.x - hint_cell.x) + absi(target_device_cell.y - hint_cell.y)
		if path_cells.size() < best_length:
			best_length = path_cells.size()
			best_hint_distance = hint_distance
			best_device_cell = target_device_cell
			best_path_cell = target_path_cell
			best_path = path_cells
			continue

		if path_cells.size() == best_length and hint_distance < best_hint_distance:
			best_hint_distance = hint_distance
			best_device_cell = target_device_cell
			best_path_cell = target_path_cell
			best_path = path_cells

	if best_path.is_empty():
		return {}

	return {
		"device_cell": best_device_cell,
		"path_cell": best_path_cell,
		"path_cells": best_path
	}


func _finalize_current_preview() -> int:
	if _current_preview_cells.is_empty() or map_manager == null:
		return -1

	var directed_cells := path_finder.build_directed_path(_current_preview_cells)
	if not map_manager.can_accept_directed_conveyor_path(directed_cells):
		return -1

	var conveyor_id := map_manager.add_directed_conveyor(directed_cells)
	if conveyor_id == -1:
		return -1

	_reset_planning_state()
	state = PlannerState.SELECT_START_DEVICE
	_push_preview()
	conveyor_generated.emit(conveyor_id)
	return conveyor_id


func _push_preview() -> void:
	if map_manager == null:
		return

	var directed_preview: Array = []
	var end_visible := _hover_display_cell != INVALID_CELL
	var path_valid := true
	if _hover_display_cell != INVALID_CELL and _hover_display_cell != _start_display_cell:
		path_valid = not _current_preview_cells.is_empty()

	if not _current_preview_cells.is_empty():
		var raw_preview := path_finder.build_directed_path(_current_preview_cells)
		var evaluation: Dictionary = map_manager.evaluate_directed_conveyor_path(raw_preview)
		directed_preview = evaluation.get("cells", [])
		path_valid = path_valid and bool(evaluation.get("valid", false))

	map_manager.set_directed_conveyor_preview(
		_start_display_cell,
		_start_display_cell != INVALID_CELL,
		_hover_display_cell,
		end_visible,
		directed_preview,
		path_valid
	)


func _clear_hover_preview() -> void:
	_hover_target_building = null
	_hover_display_cell = INVALID_CELL
	_hover_path_cell = INVALID_CELL
	_current_preview_cells.clear()


func _reset_planning_state() -> void:
	_start_building = null
	_start_display_cell = INVALID_CELL
	_start_path_cell = INVALID_CELL
	_clear_hover_preview()
