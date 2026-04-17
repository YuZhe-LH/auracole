extends "res://scripts/controllers/map_controller.gd"

const SLOT_SIZE := Vector2(720.0, 168.0)
const MAX_COLUMNS := 2
const COLUMN_GAP := 95
const HEADER_WIDTH := 700.0
const HEADER_HEIGHT := 32.0
const HEADER_TOP_OFFSET := 40.0
const MIN_SIDE_MARGIN := 8
const MAX_SIDE_MARGIN := 234
const MIN_TOP_MARGIN := 72
const MAX_TOP_MARGIN := 145
const MIN_BOTTOM_MARGIN := 16
const MAX_BOTTOM_MARGIN := 48

@onready var background_panel: PanelContainer = $PanelContainer
@onready var background_content: Control = $PanelContainer/Control
@onready var left_header: Label = $PanelContainer/Control/Label1
@onready var right_header: Label = $PanelContainer/Control/Label2
@onready var content_margin: MarginContainer = $MarginContainer
@onready var scroll_container: ScrollContainer = $MarginContainer/ScrollContainer


func _ready() -> void:
	_prepare_layout_nodes()
	super._ready()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	call_deferred("_apply_responsive_layout")


func _exit_tree() -> void:
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.disconnect(_on_viewport_size_changed)


func _on_viewport_size_changed() -> void:
	_apply_responsive_layout()


func _prepare_layout_nodes() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO


func _apply_responsive_layout() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var columns := _get_column_count(viewport_size.x)
	var content_width: float = float(columns) * SLOT_SIZE.x + float(max(columns - 1, 0) * COLUMN_GAP)
	var side_margin := clampi(int((viewport_size.x - content_width) * 0.5), MIN_SIDE_MARGIN, MAX_SIDE_MARGIN)
	var top_margin := clampi(int(viewport_size.y * 0.12), MIN_TOP_MARGIN, MAX_TOP_MARGIN)
	var bottom_margin := clampi(int(viewport_size.y * 0.04), MIN_BOTTOM_MARGIN, MAX_BOTTOM_MARGIN)
	var row_gap := clampi(int(viewport_size.y * 0.06), 32, 79)

	content_margin.add_theme_constant_override("margin_left", side_margin)
	content_margin.add_theme_constant_override("margin_right", side_margin)
	content_margin.add_theme_constant_override("margin_top", top_margin)
	content_margin.add_theme_constant_override("margin_bottom", bottom_margin)

	grid_container.columns = columns
	grid_container.add_theme_constant_override("h_separation", COLUMN_GAP if columns > 1 else 0)
	grid_container.add_theme_constant_override("v_separation", row_gap)
	_update_headers(side_margin, top_margin, columns)


func _get_column_count(viewport_width: float) -> int:
	for column_count in range(MAX_COLUMNS, 0, -1):
		var required_width: float = float(column_count) * SLOT_SIZE.x + float(max(column_count - 1, 0) * COLUMN_GAP + MIN_SIDE_MARGIN * 2)
		if viewport_width >= required_width:
			return column_count
	return 1


func _update_headers(side_margin: int, top_margin: int, columns: int) -> void:
	var header_y := maxf(24.0, float(top_margin) - HEADER_TOP_OFFSET)
	var centered_offset := (SLOT_SIZE.x - HEADER_WIDTH) * 0.5

	left_header.visible = true
	left_header.position = Vector2(side_margin + centered_offset, header_y)
	left_header.size = Vector2(HEADER_WIDTH, HEADER_HEIGHT)

	right_header.visible = columns > 1
	if columns > 1:
		right_header.position = Vector2(side_margin + SLOT_SIZE.x + COLUMN_GAP + centered_offset, header_y)
		right_header.size = Vector2(HEADER_WIDTH, HEADER_HEIGHT)
