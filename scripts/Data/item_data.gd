extends Resource
class_name ItemData

signal data_changed(item_data: ItemData, property_name: StringName, value: Variant)

@export var name: String:
	set(value):
		if name == value:
			return
		name = value
		_emit_data_changed(&"name", value)

@export var quantity: int = 0:
	set(value):
		if quantity == value:
			return
		quantity = value
		_emit_data_changed(&"quantity", value)

@export var status: int = 0:
	set(value):
		if status == value:
			return
		status = value
		_emit_data_changed(&"status", value)

@export var curr_produce: int = 0:
	set(value):
		if curr_produce == value:
			return
		curr_produce = value
		_emit_data_changed(&"curr_produce", value)

@export var curr_consume: int = 0:
	set(value):
		if curr_consume == value:
			return
		curr_consume = value
		_emit_data_changed(&"curr_consume", value)

@export var theory_produce: int = 0:
	set(value):
		if theory_produce == value:
			return
		theory_produce = value
		_emit_data_changed(&"theory_produce", value)

@export var theory_consume: int = 0:
	set(value):
		if theory_consume == value:
			return
		theory_consume = value
		_emit_data_changed(&"theory_consume", value)


func notify_data_changed(property_name: StringName = &"") -> void:
	var value: Variant = null
	if not String(property_name).is_empty():
		value = get(String(property_name))
	emit_signal("data_changed", self, property_name, value)


func _emit_data_changed(property_name: StringName, value: Variant) -> void:
	emit_changed()
	emit_signal("data_changed", self, property_name, value)
