extends Control
class_name UI_Bar

signal item_selected(item_id: String)

@onready var panel: PanelContainer = $Panel
@onready var scroll: ScrollContainer = $Panel/Scroll
@onready var item_list: HBoxContainer = $Panel/Scroll/ItemList

var _item_db: Dictionary = {}
var _inventory: Dictionary = {}
var _stock_labels: Dictionary = {}
var _buttons: Dictionary = {}
var _selected_item_id: String = ""
var _ordered_ids: Array[String] = []


func _ready() -> void:
	_apply_style()
	_configure_layout()
	if not _ordered_ids.is_empty():
		_rebuild_buttons(_ordered_ids)


func setup(item_db: Dictionary, inventory: Dictionary, ordered_ids: Array[String]) -> void:
	_item_db = item_db
	_inventory = inventory
	_ordered_ids = ordered_ids.duplicate()
	if not is_node_ready():
		return

	_rebuild_buttons(_ordered_ids)


func apply_bottom_bar_layout(bar_height: float) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 0.0
	offset_top = -bar_height
	offset_right = 0.0
	offset_bottom = 0.0
	custom_minimum_size = Vector2(0.0, bar_height)
	size = Vector2(get_viewport_rect().size.x, bar_height)


func update_inventory(inventory: Dictionary) -> void:
	_inventory = inventory
	for item_id in _stock_labels.keys():
		var stock_label: Label = _stock_labels[item_id]
		stock_label.text = "库存: %d" % int(_inventory.get(item_id, 0))


func set_selected(item_id: String) -> void:
	_selected_item_id = item_id
	for id in _buttons.keys():
		var button: Button = _buttons[id]
		button.button_pressed = (id == _selected_item_id)


func _apply_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.content_margin_left = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", panel_style)

	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	item_list.add_theme_constant_override("separation", 12)


func _configure_layout() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)

	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _rebuild_buttons(ordered_ids: Array[String]) -> void:
	for child in item_list.get_children():
		child.queue_free()

	_stock_labels.clear()
	_buttons.clear()

	for item_id in ordered_ids:
		if not _item_db.has(item_id):
			continue
		var data: Dictionary = _item_db[item_id]
		var button := _build_item_button(item_id, data)
		item_list.add_child(button)

	item_list.queue_sort()
	update_minimum_size()


func _build_item_button(item_id: String, data: Dictionary) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(230, 108)
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_on_item_button_pressed.bind(item_id))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 8)
	button.add_child(row)

	var icon := TextureRect.new()
	icon.texture = data["icon"]
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(72, 72)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name_label := Label.new()
	name_label.text = str(data["name"])
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_color_override("font_color", Color.WHITE)
	info.add_child(name_label)

	var stock_label := Label.new()
	stock_label.text = "库存: %d" % int(_inventory.get(item_id, 0))
	stock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stock_label.add_theme_color_override("font_color", Color.WHITE)
	info.add_child(stock_label)

	var item_size: Vector2i = data["size"]
	var spec_label := Label.new()
	spec_label.text = "规格: %d行 x %d列" % [item_size.x, item_size.y]
	spec_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spec_label.add_theme_color_override("font_color", Color.WHITE)
	info.add_child(spec_label)

	_stock_labels[item_id] = stock_label
	_buttons[item_id] = button
	return button


func _on_item_button_pressed(item_id: String) -> void:
	set_selected(item_id)
	item_selected.emit(item_id)
