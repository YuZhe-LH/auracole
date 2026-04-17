extends Control

const RATE_SUFFIX := "/分钟"
const NORMAL_SLOT_MODULATE := Color(1, 1, 1, 1)
const INACTIVE_SLOT_MODULATE := Color(0.62, 0.62, 0.62, 0.92)
const ITEM_TEXTURES := {
	"高纯金属块": preload("res://resources/texture/高纯金属块.png"),
	"高纯玄萤燃料块": preload("res://resources/texture/高纯玄萤燃料块.png"),
	"玄萤燃料块": preload("res://resources/texture/玄萤燃料块.png"),
	"玄萤矿": preload("res://resources/texture/玄萤矿.png"),
	"玄萤矿粉": preload("res://resources/texture/玄萤矿粉.png"),
	"精炼玄萤矿粉": preload("res://resources/texture/精炼玄萤矿粉.png"),
	"金属块": preload("res://resources/texture/金属块.png"),
	"金属粉末": preload("res://resources/texture/金属粉末.png"),
}

@export var inventory_data: InventoryDate:
	set(value):
		if inventory_data == value:
			return
		_disconnect_inventory_signals()
		inventory_data = value
		_connect_inventory_signals()
		if is_node_ready():
			_refresh_all_slots()

@onready var grid_container: GridContainer = $MarginContainer/ScrollContainer/GridContainer

var _slot_views: Array[Dictionary] = []


func _ready() -> void:
	_cache_slot_views()
	if inventory_data == null:
		inventory_data = _find_inventory_data_from_scene()
	else:
		_connect_inventory_signals()
	_refresh_all_slots()


func setup_inventory_data(next_inventory_data: InventoryDate) -> void:
	inventory_data = next_inventory_data


func _cache_slot_views() -> void:
	_slot_views.clear()
	for child in grid_container.get_children():
		if not child is Control:
			continue
		var slot_root := child as Control
		var item_texture := slot_root.get_node_or_null("item_texture") as TextureRect
		var name_label := slot_root.get_node_or_null("name") as Label
		var quantity_label := _find_slot_label(slot_root, "stock_room", "number")
		var curr_produce_label := slot_root.get_node_or_null("curr_produce") as Label
		var curr_consume_label := slot_root.get_node_or_null("curr_consume") as Label
		var theory_produce_label := slot_root.get_node_or_null("theory_produce") as Label
		var theory_consume_label := slot_root.get_node_or_null("theory_consume") as Label
		if item_texture == null or name_label == null or quantity_label == null:
			push_warning("Map slot is missing required UI nodes: %s" % slot_root.name)
			continue
		_slot_views.append({
			"root": slot_root,
			"item_texture": item_texture,
			"name": name_label,
			"quantity": quantity_label,
			"curr_produce": curr_produce_label,
			"curr_consume": curr_consume_label,
			"theory_produce": theory_produce_label,
			"theory_consume": theory_consume_label,
		})


func _find_slot_label(slot_root: Control, prefix: String, contains: String = "") -> Label:
	for child in slot_root.find_children("*", "Label", true, false):
		if not child is Label:
			continue
		var child_name := String(child.name)
		if not child_name.begins_with(prefix):
			continue
		if not contains.is_empty() and not child_name.contains(contains):
			continue
		return child as Label
	return null


func _connect_inventory_signals() -> void:
	if inventory_data == null:
		return
	inventory_data.bind_signals()
	if not inventory_data.inventory_data_changed.is_connected(_on_inventory_changed):
		inventory_data.inventory_data_changed.connect(_on_inventory_changed)
	if not inventory_data.slot_changed.is_connected(_on_slot_changed):
		inventory_data.slot_changed.connect(_on_slot_changed)
	if inventory_data.has_signal("slot_item_data_changed") and not inventory_data.slot_item_data_changed.is_connected(_on_slot_item_data_changed):
		inventory_data.slot_item_data_changed.connect(_on_slot_item_data_changed)


func _disconnect_inventory_signals() -> void:
	if inventory_data == null:
		return
	if inventory_data.inventory_data_changed.is_connected(_on_inventory_changed):
		inventory_data.inventory_data_changed.disconnect(_on_inventory_changed)
	if inventory_data.slot_changed.is_connected(_on_slot_changed):
		inventory_data.slot_changed.disconnect(_on_slot_changed)
	if inventory_data.has_signal("slot_item_data_changed") and inventory_data.slot_item_data_changed.is_connected(_on_slot_item_data_changed):
		inventory_data.slot_item_data_changed.disconnect(_on_slot_item_data_changed)


func _on_inventory_changed(_changed_inventory_data: InventoryDate) -> void:
	_refresh_all_slots()


func _on_slot_changed(slot_index: int, _slot_data: SlotData) -> void:
	if slot_index < 0:
		_refresh_all_slots()
		return
	_refresh_slot(slot_index)


func _on_slot_item_data_changed(slot_index: int, _slot_data: SlotData, _item_data: ItemData, _property_name: StringName, _value: Variant) -> void:
	if slot_index < 0:
		_refresh_all_slots()
		return
	_refresh_slot(slot_index)


func _refresh_all_slots() -> void:
	for slot_index in range(_slot_views.size()):
		_refresh_slot(slot_index)


func _refresh_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slot_views.size():
		return
	var view := _slot_views[slot_index]
	var slot_data := _get_slot_data(slot_index)
	var item_data := slot_data.item_data if slot_data != null else null
	_apply_slot_view(view, item_data)


func _get_slot_data(slot_index: int) -> SlotData:
	if inventory_data == null:
		return null
	return inventory_data.get_slot(slot_index)


func _apply_slot_view(view: Dictionary, item_data: ItemData) -> void:
	var slot_root := view["root"] as Control
	var item_texture := view["item_texture"] as TextureRect
	var name_label := view["name"] as Label
	var quantity_label := view["quantity"] as Label
	var curr_produce_label := view["curr_produce"] as Label
	var curr_consume_label := view["curr_consume"] as Label
	var theory_produce_label := view["theory_produce"] as Label
	var theory_consume_label := view["theory_consume"] as Label

	if item_data == null:
		slot_root.modulate = NORMAL_SLOT_MODULATE
		slot_root.tooltip_text = ""
		item_texture.texture = null
		name_label.text = "空"
		_set_label_text(quantity_label, "0")
		_set_label_text(curr_produce_label, _format_rate(0))
		_set_label_text(curr_consume_label, _format_rate(0))
		_set_label_text(theory_produce_label, _format_rate(0))
		_set_label_text(theory_consume_label, _format_rate(0))
		return

	slot_root.modulate = _get_slot_modulate(item_data)
	slot_root.tooltip_text = _build_slot_tooltip(item_data)
	item_texture.texture = ITEM_TEXTURES.get(item_data.name, null)
	name_label.text = item_data.name
	_set_label_text(quantity_label, str(item_data.quantity))
	_set_label_text(curr_produce_label, _format_rate(item_data.curr_produce))
	_set_label_text(curr_consume_label, _format_rate(item_data.curr_consume))
	_set_label_text(theory_produce_label, _format_rate(item_data.theory_produce))
	_set_label_text(theory_consume_label, _format_rate(item_data.theory_consume))


func _get_slot_modulate(item_data: ItemData) -> Color:
	return NORMAL_SLOT_MODULATE if item_data.status == 0 else INACTIVE_SLOT_MODULATE


func _build_slot_tooltip(item_data: ItemData) -> String:
	return "%s\n状态：%d\n库存：%d\n当前生产：%s\n当前消耗：%s\n理论生产：%s\n理论消耗：%s" % [
		item_data.name,
		item_data.status,
		item_data.quantity,
		_format_rate(item_data.curr_produce),
		_format_rate(item_data.curr_consume),
		_format_rate(item_data.theory_produce),
		_format_rate(item_data.theory_consume),
	]


func _format_rate(value: int) -> String:
	return "%d%s" % [value, RATE_SUFFIX]


func _set_label_text(target: Label, value: String) -> void:
	if target != null:
		target.text = value


func _find_inventory_data_from_scene() -> InventoryDate:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return null
	var player_node := current_scene.find_child("Player", true, false)
	if player_node == null:
		return null
	return player_node.get("inventory_data") as InventoryDate
