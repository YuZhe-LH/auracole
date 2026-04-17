extends Node2D
class_name GameManager

const BUILDING_SCENE: PackedScene = preload("res://scenes/placement_logic/building.tscn")
const DIRECTED_CONVEYOR_PLANNER_V2_SCRIPT: GDScript = preload("res://scripts/placement_logic/directed_conveyor_planner_v2.gd")
const CONVEYOR_DELETION_MENU_V2_SCRIPT: GDScript = preload("res://scripts/placement_logic/conveyor_deletion_menu_v2.gd")

const BAR_HEIGHT: float = 150.0
const MIN_BAR_HEIGHT: float = 110.0
const LONG_PRESS_DURATION: float = 1.0

enum BuildingAction {
	MOVE,
	DELETE,
	ROTATE
}

@onready var map_manager: MapManager = $MapManager
@onready var camera_rig: CameraRig = $CameraRig
@onready var canvas_layer: CanvasLayer = $CanvasLayer
@onready var ui_bar: UI_Bar = $CanvasLayer/UI_Bar
@onready var interaction_menu: PopupMenu = $CanvasLayer/InteractionMenu

var item_database: Dictionary = {}
var inventory: Dictionary = {}
var selected_item_id: String = ""
var is_conveyor_mode: bool = false

var _last_mouse_position: Vector2 = Vector2.ZERO
var _pressed_building: Building = null
var _pressed_duration: float = 0.0
var _context_building: Building = null
var _moving_building: Building = null
var _moving_origin_cell: Vector2i = Vector2i.ZERO
var _skip_left_release_action: bool = false
var _directed_conveyor_planner: DirectedConveyorPlannerV2 = null
var _conveyor_deletion_menu: ConveyorDeletionMenuV2 = null


func _ready() -> void:
	canvas_layer.layer = 10
	ui_bar.visible = true
	ui_bar.mouse_filter = Control.MOUSE_FILTER_STOP

	item_database = ItemDatabase.create()
	_init_inventory()
	_setup_conveyor_tools()
	ui_bar.setup(item_database, inventory, ItemDatabase.ITEM_ORDER)
	ui_bar.item_selected.connect(_on_item_selected)
	interaction_menu.id_pressed.connect(_on_interaction_menu_id_pressed)
	interaction_menu.hide()
	call_deferred("_layout_ui_bar")
	_sync_camera_drag_enabled()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func _process(delta: float) -> void:
	if camera_rig.is_dragging():
		_clear_pressed_building_tracking()
		return

	if _pressed_building == null:
		return
	if not is_instance_valid(_pressed_building):
		_clear_pressed_building_tracking()
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_clear_pressed_building_tracking()
		return

	_pressed_duration += delta
	if _pressed_duration >= LONG_PRESS_DURATION:
		_begin_move_mode(_pressed_building)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse and _is_pointer_over_ui(event.position):
		return

	if event is InputEventKey and event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D]:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_toggle_conveyor_mode()
			get_viewport().set_input_as_handled()
			return
		if is_conveyor_mode and event.keycode == KEY_ESCAPE:
			_directed_conveyor_planner.cancel_current_segment()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		_last_mouse_position = get_global_mouse_position()
		if camera_rig.is_dragging():
			_clear_pressed_building_tracking()
			return

		if is_conveyor_mode:
			_directed_conveyor_planner.handle_mouse_move(_last_mouse_position)
			return

		_update_active_preview(_last_mouse_position)
		return

	if event is InputEventMouseButton:
		_last_mouse_position = get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if is_conveyor_mode:
				_handle_conveyor_left_mouse(event)
				return
			if event.pressed:
				_handle_left_pressed(_last_mouse_position)
			else:
				_handle_left_released(_last_mouse_position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if is_conveyor_mode:
				interaction_menu.hide()
				if _conveyor_deletion_menu != null:
					_conveyor_deletion_menu.hide()
				_clear_pressed_building_tracking()
				return
			_handle_right_pressed(_last_mouse_position, event.position)


func _handle_left_pressed(mouse_pos: Vector2) -> void:
	interaction_menu.hide()
	if _conveyor_deletion_menu != null:
		_conveyor_deletion_menu.hide()
	_skip_left_release_action = false

	if _moving_building != null:
		return

	var clicked_building: Building = map_manager.get_building_at_world(mouse_pos)
	if clicked_building != null:
		_pressed_building = clicked_building
		_pressed_duration = 0.0
		return

	_clear_pressed_building_tracking()


func _handle_left_released(mouse_pos: Vector2) -> void:
	if camera_rig.consume_drag_release():
		_clear_pressed_building_tracking()
		_update_active_preview(mouse_pos)
		return

	if _skip_left_release_action:
		_skip_left_release_action = false
		return

	if _moving_building != null:
		_try_place_moving_building(mouse_pos)
		return

	if _pressed_building != null:
		_clear_pressed_building_tracking()
		return

	_try_place(mouse_pos)


func _handle_right_pressed(mouse_pos: Vector2, screen_pos: Vector2) -> void:
	_clear_pressed_building_tracking()
	if _conveyor_deletion_menu != null:
		_conveyor_deletion_menu.hide()

	if _moving_building != null:
		_cancel_move_mode()
		return

	var conveyor_id := map_manager.get_conveyor_id_at_world(mouse_pos)
	if conveyor_id != -1:
		interaction_menu.hide()
		_conveyor_deletion_menu.show_at_position(screen_pos, conveyor_id)
		return

	var clicked_building: Building = map_manager.get_building_at_world(mouse_pos)
	if clicked_building != null:
		_show_building_menu(clicked_building, screen_pos)
		return

	interaction_menu.hide()
	_cancel_selection()


func _layout_ui_bar() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var bar_height := clampf(viewport_size.y * 0.22, MIN_BAR_HEIGHT, BAR_HEIGHT)
	ui_bar.apply_bottom_bar_layout(bar_height)


func _init_inventory() -> void:
	inventory.clear()
	for item_id in ItemDatabase.ITEM_ORDER:
		if not item_database.has(item_id):
			continue
		var data: Dictionary = item_database[item_id]
		inventory[item_id] = int(data.get("stock", 0))


func _setup_conveyor_tools() -> void:
	_directed_conveyor_planner = DIRECTED_CONVEYOR_PLANNER_V2_SCRIPT.new() as DirectedConveyorPlannerV2
	_directed_conveyor_planner.name = "DirectedConveyorPlannerV2"
	_directed_conveyor_planner.setup(map_manager)
	_directed_conveyor_planner.conveyor_mode_changed.connect(_on_conveyor_mode_changed)
	add_child(_directed_conveyor_planner)

	_conveyor_deletion_menu = CONVEYOR_DELETION_MENU_V2_SCRIPT.new() as ConveyorDeletionMenuV2
	_conveyor_deletion_menu.name = "ConveyorDeletionMenuV2"
	_conveyor_deletion_menu.delete_conveyor.connect(_on_delete_conveyor_requested)
	canvas_layer.add_child(_conveyor_deletion_menu)


func _on_item_selected(item_id: String) -> void:
	if is_conveyor_mode:
		_exit_conveyor_mode()
	if _moving_building != null:
		_cancel_move_mode()

	selected_item_id = item_id
	ui_bar.set_selected(item_id)
	interaction_menu.hide()
	if _conveyor_deletion_menu != null:
		_conveyor_deletion_menu.hide()
	_update_preview(get_global_mouse_position())


func _cancel_selection() -> void:
	selected_item_id = ""
	ui_bar.set_selected("")
	map_manager.clear_preview()


func _handle_conveyor_left_mouse(event: InputEventMouseButton) -> void:
	interaction_menu.hide()
	if _conveyor_deletion_menu != null:
		_conveyor_deletion_menu.hide()
	_clear_pressed_building_tracking()

	if event.pressed:
		return

	if camera_rig.consume_drag_release():
		_directed_conveyor_planner.handle_mouse_move(_last_mouse_position)
		return

	_directed_conveyor_planner.handle_left_click(_last_mouse_position)


func _toggle_conveyor_mode() -> void:
	if is_conveyor_mode:
		_directed_conveyor_planner.generate_complete_conveyor()
		return

	_enter_conveyor_mode()


func _enter_conveyor_mode() -> void:
	interaction_menu.hide()
	if _conveyor_deletion_menu != null:
		_conveyor_deletion_menu.hide()
	_clear_pressed_building_tracking()
	if _moving_building != null:
		_cancel_move_mode()
	_cancel_selection()
	_directed_conveyor_planner.enter_mode()


func _exit_conveyor_mode() -> void:
	if _directed_conveyor_planner == null:
		return
	_directed_conveyor_planner.exit_mode()


func _on_conveyor_mode_changed(active: bool) -> void:
	is_conveyor_mode = active
	if active:
		map_manager.clear_preview()
		return

	map_manager.clear_directed_conveyor_preview()
	_update_active_preview(_last_mouse_position)


func _on_delete_conveyor_requested(conveyor_id: int) -> void:
	if conveyor_id == -1:
		return

	map_manager.remove_conveyor(conveyor_id)
	_update_active_preview(_last_mouse_position)


func _update_active_preview(mouse_pos: Vector2) -> void:
	if _moving_building != null:
		_update_move_preview(mouse_pos)
	else:
		_update_preview(mouse_pos)


func _update_preview(mouse_pos: Vector2) -> void:
	if selected_item_id.is_empty():
		map_manager.clear_preview()
		return
	if not item_database.has(selected_item_id):
		map_manager.clear_preview()
		return

	var item_data: Dictionary = item_database[selected_item_id]
	var grid_dimensions: Vector2i = item_data["size"]
	var top_left_cell: Vector2i = map_manager.world_to_cell(mouse_pos)
	var has_stock: bool = int(inventory.get(selected_item_id, 0)) > 0
	var can_place_here: bool = has_stock and map_manager.can_place(top_left_cell, grid_dimensions)
	map_manager.set_preview(top_left_cell, grid_dimensions, can_place_here, true)


func _try_place(mouse_pos: Vector2) -> void:
	if selected_item_id.is_empty():
		return
	if int(inventory.get(selected_item_id, 0)) <= 0:
		return
	if not item_database.has(selected_item_id):
		return

	var item_data: Dictionary = item_database[selected_item_id]
	var footprint: Vector2i = item_data["size"]
	var top_left_cell: Vector2i = map_manager.world_to_cell(mouse_pos)
	if not map_manager.can_place(top_left_cell, footprint):
		_update_preview(mouse_pos)
		return

	var building: Building = BUILDING_SCENE.instantiate() as Building
	map_manager.add_child(building)
	building.setup(selected_item_id, item_data["icon"], MapManager.CELL_SIZE, footprint)
	building.set_top_left_cell(top_left_cell)
	building.position = map_manager.cell_to_world_center(top_left_cell, footprint)

	map_manager.occupy(top_left_cell, footprint, building)
	inventory[selected_item_id] = int(inventory[selected_item_id]) - 1
	ui_bar.update_inventory(inventory)
	_update_preview(mouse_pos)


func _show_building_menu(building: Building, screen_pos: Vector2) -> void:
	_context_building = building
	interaction_menu.clear()
	interaction_menu.add_item("移动", BuildingAction.MOVE)
	interaction_menu.add_item("删除", BuildingAction.DELETE)
	interaction_menu.add_item("旋转", BuildingAction.ROTATE)
	interaction_menu.reset_size()
	interaction_menu.popup(Rect2i(Vector2i(screen_pos), Vector2i.ONE))


func _on_interaction_menu_id_pressed(action_id: int) -> void:
	interaction_menu.hide()
	if not is_instance_valid(_context_building):
		_context_building = null
		return

	var target_building: Building = _context_building
	_context_building = null

	match action_id:
		BuildingAction.MOVE:
			_begin_move_mode(target_building)
		BuildingAction.DELETE:
			_delete_building(target_building)
		BuildingAction.ROTATE:
			_rotate_building(target_building)


func _delete_building(building: Building) -> void:
	if not is_instance_valid(building):
		return

	if _moving_building == building:
		_moving_building = null
		map_manager.clear_preview()
		_sync_camera_drag_enabled()

	map_manager.free_area(building.top_left_cell, building.footprint)
	inventory[building.item_id] = int(inventory.get(building.item_id, 0)) + 1
	ui_bar.update_inventory(inventory)
	building.queue_free()
	_update_active_preview(_last_mouse_position)


func _rotate_building(building: Building) -> void:
	if not is_instance_valid(building):
		return

	var old_cell: Vector2i = building.top_left_cell
	var old_footprint: Vector2i = building.footprint
	var rotated_footprint: Vector2i = Vector2i(old_footprint.y, old_footprint.x)

	map_manager.free_area(old_cell, old_footprint)
	if not map_manager.can_place(old_cell, rotated_footprint):
		map_manager.occupy(old_cell, old_footprint, building)
		return

	building.rotate_clockwise()
	building.position = map_manager.cell_to_world_center(old_cell, building.footprint)
	map_manager.occupy(old_cell, building.footprint, building)
	_update_active_preview(_last_mouse_position)


func _begin_move_mode(building: Building) -> void:
	if not is_instance_valid(building):
		_clear_pressed_building_tracking()
		return

	_clear_pressed_building_tracking()
	interaction_menu.hide()
	if _conveyor_deletion_menu != null:
		_conveyor_deletion_menu.hide()
	_context_building = null

	if is_conveyor_mode:
		_exit_conveyor_mode()
	if _moving_building != null and _moving_building != building:
		_cancel_move_mode()
	if _moving_building == building:
		return

	selected_item_id = ""
	ui_bar.set_selected("")

	_moving_building = building
	_moving_origin_cell = building.top_left_cell
	map_manager.free_area(building.top_left_cell, building.footprint)
	building.set_drag_preview(true)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_skip_left_release_action = true
	_sync_camera_drag_enabled()
	_update_move_preview(_last_mouse_position)


func _update_move_preview(mouse_pos: Vector2) -> void:
	if _moving_building == null:
		return

	var top_left_cell: Vector2i = map_manager.world_to_cell(mouse_pos)
	var footprint: Vector2i = _moving_building.footprint
	var can_place_here: bool = map_manager.can_place(top_left_cell, footprint)

	_moving_building.position = map_manager.cell_to_world_center(top_left_cell, footprint)
	map_manager.set_preview(top_left_cell, footprint, can_place_here, true)


func _try_place_moving_building(mouse_pos: Vector2) -> void:
	if _moving_building == null:
		return

	var top_left_cell: Vector2i = map_manager.world_to_cell(mouse_pos)
	var footprint: Vector2i = _moving_building.footprint
	if not map_manager.can_place(top_left_cell, footprint):
		_update_move_preview(mouse_pos)
		return

	_moving_building.set_top_left_cell(top_left_cell)
	_moving_building.position = map_manager.cell_to_world_center(top_left_cell, footprint)
	_moving_building.set_drag_preview(false)
	map_manager.occupy(top_left_cell, footprint, _moving_building)
	_moving_building = null
	map_manager.clear_preview()
	_sync_camera_drag_enabled()


func _cancel_move_mode() -> void:
	if _moving_building == null:
		return

	_moving_building.set_top_left_cell(_moving_origin_cell)
	_moving_building.position = map_manager.cell_to_world_center(_moving_origin_cell, _moving_building.footprint)
	_moving_building.set_drag_preview(false)
	map_manager.occupy(_moving_origin_cell, _moving_building.footprint, _moving_building)
	_moving_building = null
	map_manager.clear_preview()
	_sync_camera_drag_enabled()
	_update_active_preview(_last_mouse_position)


func _clear_pressed_building_tracking() -> void:
	_pressed_building = null
	_pressed_duration = 0.0


func _sync_camera_drag_enabled() -> void:
	camera_rig.set_drag_enabled(_moving_building == null)


func _on_viewport_size_changed() -> void:
	call_deferred("_layout_ui_bar")


func _is_pointer_over_ui(screen_position: Vector2) -> bool:
	if not is_instance_valid(ui_bar):
		return false
	if not ui_bar.visible:
		return false

	return ui_bar.get_global_rect().has_point(screen_position)
