extends PopupMenu
class_name ConveyorDeletionMenuV2

signal delete_conveyor(conveyor_id: int)

const DELETE_ITEM_ID := 0

var target_conveyor_id: int = -1


func _ready() -> void:
	add_item("Delete Conveyor", DELETE_ITEM_ID)
	id_pressed.connect(_on_id_pressed)


func show_at_position(screen_position: Vector2, conveyor_id: int) -> void:
	target_conveyor_id = conveyor_id
	reset_size()
	popup(Rect2i(Vector2i(screen_position), Vector2i.ONE))


func _on_id_pressed(item_id: int) -> void:
	if item_id != DELETE_ITEM_ID:
		return
	if target_conveyor_id == -1:
		return

	delete_conveyor.emit(target_conveyor_id)
	target_conveyor_id = -1
	hide()
