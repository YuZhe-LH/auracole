extends Resource
class_name SlotData

signal slot_data_changed(slot_data: SlotData)
signal item_data_changed(slot_data: SlotData, item_data: ItemData, property_name: StringName, value: Variant)

@export var item_data: ItemData:
	set(value):
		if item_data == value:
			return
		_disconnect_item_data_signal()
		item_data = value
		_connect_item_data_signal()
		emit_changed()
		emit_signal("slot_data_changed", self)
		emit_signal("item_data_changed", self, item_data, &"item_data", item_data)


func bind_signals() -> void:
	_connect_item_data_signal()


func _connect_item_data_signal() -> void:
	if item_data == null:
		return
	if not item_data.data_changed.is_connected(_on_item_data_changed):
		item_data.data_changed.connect(_on_item_data_changed)


func _disconnect_item_data_signal() -> void:
	if item_data == null:
		return
	if item_data.data_changed.is_connected(_on_item_data_changed):
		item_data.data_changed.disconnect(_on_item_data_changed)


func _on_item_data_changed(changed_item_data: ItemData, property_name: StringName, value: Variant) -> void:
	emit_changed()
	emit_signal("slot_data_changed", self)
	emit_signal("item_data_changed", self, changed_item_data, property_name, value)
