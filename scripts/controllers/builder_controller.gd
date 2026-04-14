extends Control

signal material_submitted(building_id: String, material_id: String, amount: int, total_submitted: int)
signal build_completed(building_id: String)

var building_catalog: Array[Dictionary] = [
	{
		"id": "mingju",
		"name": "民居类",
		"category": "民生建筑",
		"summary": "用于安置居民、提供基础生活空间的标准民居单元。",
		"description": "民居类建筑承担聚落扩展时最基础的人口承载功能。\n\n完成建造后可作为居民入住、生活组织和后续社区扩建的起点。",
		"build_label": "建造民居",
		"image_path": "res://resources/build_pic/Mingju.png",
		"built": false,
		"materials": [
			{"id": "ore_powder", "name": "矿石粉", "category": "基础材料", "required_amount": 2000, "submitted_amount": 0},
			{"id": "water", "name": "水", "category": "基础资源", "required_amount": 5000, "submitted_amount": 0},
			{"id": "high_purity_metal_block", "name": "高纯金属块", "category": "精炼材料", "required_amount": 2000, "submitted_amount": 0}
		]
	},
	{
		"id": "cangku",
		"name": "仓库类",
		"category": "储运建筑",
		"summary": "用于集中存放工业物资、稳定区域周转效率的仓储设施。",
		"description": "仓库类建筑负责承接大宗材料与稀有物资的集中管理。\n\n建造完成后更适合作为生产区和运输节点之间的缓冲设施。",
		"build_label": "建造仓库",
		"image_path": "res://resources/build_pic/cangku.png",
		"built": false,
		"materials": [
			{"id": "high_purity_metal_block", "name": "高纯金属块", "category": "精炼材料", "required_amount": 5000, "submitted_amount": 0},
			{"id": "rare_metal_block", "name": "稀有金属块", "category": "稀有材料", "required_amount": 1000, "submitted_amount": 0}
		]
	},
	{
		"id": "tingyuan",
		"name": "庭院类",
		"category": "景观建筑",
		"summary": "兼顾居住品质与公共活动的庭院式景观建筑。",
		"description": "庭院类建筑偏向环境塑造和区域宜居度提升。\n\n它通常用于居住区中心或连接多个功能区，提供缓冲、休憩和景观空间。",
		"build_label": "建造庭院",
		"image_path": "res://resources/build_pic/tingyuan.png",
		"built": false,
		"materials": [
			{"id": "ore_powder", "name": "矿石粉", "category": "基础材料", "required_amount": 5000, "submitted_amount": 0},
			{"id": "water", "name": "水", "category": "基础资源", "required_amount": 10000, "submitted_amount": 0},
			{"id": "high_purity_metal_block", "name": "高纯金属块", "category": "精炼材料", "required_amount": 3000, "submitted_amount": 0}
		]
	}
]

var build_target: Dictionary = {}
var _selected_building_index: int = 0
var _selected_material_index: int = -1

@onready var header_title: Label = $RootMargin/MainVBox/HeaderTitle
@onready var header_subtitle: Label = $RootMargin/MainVBox/HeaderSubtitle
@onready var building_selector_label: Label = $RootMargin/MainVBox/ContentRow/MaterialPanel/MaterialMargin/MaterialVBox/BuildingSelectorLabel
@onready var building_selector: OptionButton = $RootMargin/MainVBox/ContentRow/MaterialPanel/MaterialMargin/MaterialVBox/BuildingSelector
@onready var material_title: Label = $RootMargin/MainVBox/ContentRow/MaterialPanel/MaterialMargin/MaterialVBox/MaterialTitle
@onready var material_list: ItemList = $RootMargin/MainVBox/ContentRow/MaterialPanel/MaterialMargin/MaterialVBox/MaterialList
@onready var description_title: Label = $RootMargin/MainVBox/ContentRow/DescriptionPanel/DescriptionMargin/DescriptionVBox/DescriptionTitle
@onready var build_image: TextureRect = $RootMargin/MainVBox/ContentRow/DescriptionPanel/DescriptionMargin/DescriptionVBox/BuildImage
@onready var building_name_label: Label = $RootMargin/MainVBox/ContentRow/DescriptionPanel/DescriptionMargin/DescriptionVBox/SelectedMaterialName
@onready var building_category_label: Label = $RootMargin/MainVBox/ContentRow/DescriptionPanel/DescriptionMargin/DescriptionVBox/CategoryLabel
@onready var description_text: RichTextLabel = $RootMargin/MainVBox/ContentRow/DescriptionPanel/DescriptionMargin/DescriptionVBox/DescriptionText
@onready var submit_title: Label = $RootMargin/MainVBox/ContentRow/SubmitPanel/SubmitMargin/SubmitVBox/SubmitTitle
@onready var selected_material_label: Label = $RootMargin/MainVBox/ContentRow/SubmitPanel/SubmitMargin/SubmitVBox/SelectedMaterialLabel
@onready var requirement_label: Label = $RootMargin/MainVBox/ContentRow/SubmitPanel/SubmitMargin/SubmitVBox/RequirementLabel
@onready var progress_label: Label = $RootMargin/MainVBox/ContentRow/SubmitPanel/SubmitMargin/SubmitVBox/ProgressLabel
@onready var submit_amount: SpinBox = $RootMargin/MainVBox/ContentRow/SubmitPanel/SubmitMargin/SubmitVBox/SubmitAmount
@onready var submit_button: Button = $RootMargin/MainVBox/ContentRow/SubmitPanel/SubmitMargin/SubmitVBox/SubmitButton
@onready var build_button: Button = $RootMargin/MainVBox/ContentRow/SubmitPanel/SubmitMargin/SubmitVBox/BuildButton
@onready var status_label: Label = $RootMargin/MainVBox/ContentRow/SubmitPanel/SubmitMargin/SubmitVBox/StatusLabel
@onready var summary_label: Label = $RootMargin/MainVBox/SummaryLabel

func _ready() -> void:
	_normalize_building_catalog()
	building_selector.item_selected.connect(_on_building_selected)
	material_list.item_selected.connect(_on_material_selected)
	submit_button.pressed.connect(_on_submit_pressed)
	build_button.pressed.connect(_on_build_pressed)
	submit_amount.value_changed.connect(_on_submit_amount_changed)
	_rebuild_building_selector()
	_select_building(_selected_building_index)

func set_building_catalog(catalog: Array[Dictionary]) -> void:
	building_catalog.clear()
	for building_data in catalog:
		building_catalog.append(_normalize_build_target(building_data))
	_selected_building_index = 0

	if is_node_ready():
		_rebuild_building_selector()
		_select_building(_selected_building_index)

func select_building_by_id(building_id: String) -> void:
	for index in building_catalog.size():
		if str(building_catalog[index]["id"]) == building_id:
			if is_node_ready():
				building_selector.select(index)
				_select_building(index)
			else:
				_selected_building_index = index
			return

func _normalize_building_catalog() -> void:
	var normalized_catalog: Array[Dictionary] = []
	for building_data in building_catalog:
		normalized_catalog.append(_normalize_build_target(building_data))
	building_catalog = normalized_catalog

	if building_catalog.is_empty():
		build_target = {}
		_selected_building_index = -1
		return

	_selected_building_index = clampi(_selected_building_index, 0, building_catalog.size() - 1)
	build_target = building_catalog[_selected_building_index]

func _normalize_build_target(build_data: Dictionary) -> Dictionary:
	var normalized_target: Dictionary = {
		"id": str(build_data.get("id", "unknown_building")),
		"name": str(build_data.get("name", "未命名建筑")),
		"category": str(build_data.get("category", "未分类")),
		"summary": str(build_data.get("summary", "暂无概要。")),
		"description": str(build_data.get("description", "暂无建造介绍。")),
		"build_label": str(build_data.get("build_label", "开始建造")),
		"image_path": str(build_data.get("image_path", "")),
		"built": bool(build_data.get("built", false)),
		"materials": []
	}

	var source_materials: Array = build_data.get("materials", [])
	for index in source_materials.size():
		normalized_target["materials"].append(_normalize_material_data(source_materials[index], index))

	return normalized_target

func _normalize_material_data(material_data: Dictionary, fallback_index: int) -> Dictionary:
	var required_amount: int = maxi(int(material_data.get("required_amount", 1)), 1)
	var submitted_amount: int = clampi(int(material_data.get("submitted_amount", 0)), 0, required_amount)

	return {
		"id": str(material_data.get("id", "material_%d" % fallback_index)),
		"name": str(material_data.get("name", "未命名材料")),
		"category": str(material_data.get("category", "未分类")),
		"required_amount": required_amount,
		"submitted_amount": submitted_amount
	}

func _rebuild_building_selector() -> void:
	building_selector.clear()
	for index in building_catalog.size():
		var building_data: Dictionary = building_catalog[index]
		building_selector.add_item(str(building_data["name"]), index)

	if not building_catalog.is_empty():
		building_selector.select(_selected_building_index)

func _select_building(index: int) -> void:
	if index < 0 or index >= building_catalog.size():
		build_target = {}
		_selected_building_index = -1
		_selected_material_index = -1
		_clear_building_details()
		return

	_selected_building_index = index
	build_target = building_catalog[index]
	_selected_material_index = 0 if _get_materials().size() > 0 else -1
	_refresh_building_info()
	_rebuild_material_list()

func _get_materials() -> Array[Dictionary]:
	var materials: Array[Dictionary] = []
	for material_data in build_target.get("materials", []):
		materials.append(material_data)
	return materials

func _refresh_building_info() -> void:
	header_title.text = "建造提交界面"
	header_subtitle.text = "选择建筑类别，提交全部材料后即可完成建造。"
	building_selector_label.text = "建造类别"
	material_title.text = "所需材料"
	description_title.text = "建造目标"
	submit_title.text = "材料提交与建造"
	building_name_label.text = str(build_target["name"])
	building_category_label.text = "建筑类型：%s    编号：%s" % [
		str(build_target["category"]),
		str(build_target["id"])
	]
	description_text.text = "%s\n\n%s" % [
		str(build_target["summary"]),
		str(build_target["description"])
	]
	_refresh_build_image()

func _refresh_build_image() -> void:
	var image_path: String = str(build_target.get("image_path", ""))
	if image_path.is_empty():
		build_image.texture = null
		return

	build_image.texture = load(image_path) as Texture2D

func _clear_building_details() -> void:
	building_name_label.text = "未配置建筑"
	building_category_label.text = "建筑类型：未配置"
	description_text.text = "请先配置可建造的建筑条目。"
	build_image.texture = null
	_clear_selected_material_details()
	summary_label.text = "没有可建造的目标。"
	status_label.text = "当前没有建造目标。"
	status_label.modulate = Color(0.35, 0.35, 0.35)
	build_button.disabled = true
	build_button.text = "无法建造"

func _rebuild_material_list() -> void:
	material_list.clear()

	var materials: Array[Dictionary] = _get_materials()
	for material_data in materials:
		material_list.add_item(_format_material_list_text(material_data))

	if materials.is_empty():
		_selected_material_index = -1
		_clear_selected_material_details()
		_update_summary()
		_update_build_button()
		_update_default_status()
		return

	_selected_material_index = clampi(_selected_material_index, 0, materials.size() - 1)
	material_list.select(_selected_material_index)
	_refresh_selected_material()
	_update_summary()
	_update_build_button()
	_update_default_status()

func _format_material_list_text(material_data: Dictionary) -> String:
	return "%s  %d/%d" % [
		str(material_data["name"]),
		int(material_data["submitted_amount"]),
		int(material_data["required_amount"])
	]

func _refresh_selected_material() -> void:
	var materials: Array[Dictionary] = _get_materials()
	if _selected_material_index < 0 or _selected_material_index >= materials.size():
		_clear_selected_material_details()
		return

	var material_data: Dictionary = materials[_selected_material_index]
	var required_amount: int = int(material_data["required_amount"])
	var submitted_amount: int = int(material_data["submitted_amount"])
	var remaining_amount: int = maxi(required_amount - submitted_amount, 0)

	selected_material_label.text = "当前材料：%s" % str(material_data["name"])
	requirement_label.text = "需求数量：%d" % required_amount
	progress_label.text = "提交进度：%d / %d    分类：%s" % [
		submitted_amount,
		required_amount,
		str(material_data["category"])
	]

	submit_amount.max_value = max(1.0, float(remaining_amount))
	if remaining_amount > 0:
		submit_amount.value = min(max(submit_amount.value, 1.0), float(remaining_amount))
	else:
		submit_amount.value = 1.0

	submit_button.disabled = bool(build_target["built"]) or remaining_amount <= 0
	submit_button.text = "提交材料" if remaining_amount > 0 else "材料已齐"
	material_list.set_item_text(_selected_material_index, _format_material_list_text(material_data))

func _clear_selected_material_details() -> void:
	selected_material_label.text = "当前材料：未选择"
	requirement_label.text = "需求数量：0"
	progress_label.text = "提交进度：0 / 0"
	submit_amount.max_value = 1.0
	submit_amount.value = 1.0
	submit_button.disabled = true
	submit_button.text = "提交材料"

func _update_default_status() -> void:
	if build_target.is_empty():
		return

	if bool(build_target["built"]):
		status_label.text = "%s 已建造完成。" % str(build_target["name"])
		status_label.modulate = Color(0.15, 0.45, 0.2)
		return

	if _is_ready_to_build():
		status_label.text = "全部材料已提交完成，可以直接点击建造。"
		status_label.modulate = Color(0.15, 0.45, 0.2)
		return

	var materials: Array[Dictionary] = _get_materials()
	if materials.is_empty():
		status_label.text = "当前目标没有配置材料，可直接建造。"
		status_label.modulate = Color(0.35, 0.35, 0.35)
		return

	if _selected_material_index < 0 or _selected_material_index >= materials.size():
		status_label.text = "请先选择一种材料。"
		status_label.modulate = Color(0.35, 0.35, 0.35)
		return

	var material_data: Dictionary = materials[_selected_material_index]
	var remaining_amount: int = maxi(
		int(material_data["required_amount"]) - int(material_data["submitted_amount"]),
		0
	)

	if remaining_amount <= 0:
		status_label.text = "该材料已满足要求，请继续完成其他材料。"
		status_label.modulate = Color(0.35, 0.35, 0.35)
		return

	status_label.text = "当前还需 %d %s。" % [remaining_amount, str(material_data["name"])]
	status_label.modulate = Color(0.35, 0.35, 0.35)

func _update_summary() -> void:
	var materials: Array[Dictionary] = _get_materials()
	if materials.is_empty():
		summary_label.text = "当前建筑未配置材料。"
		return

	var total_required: int = 0
	var total_submitted: int = 0
	var completed_materials: int = 0

	for material_data in materials:
		var required_amount: int = int(material_data["required_amount"])
		var submitted_amount: int = int(material_data["submitted_amount"])
		total_required += required_amount
		total_submitted += submitted_amount
		if submitted_amount >= required_amount:
			completed_materials += 1

	var build_state: String = "已建造" if bool(build_target["built"]) else "未建造"
	summary_label.text = "%s    总进度：%d / %d    已完成材料：%d / %d    状态：%s" % [
		str(build_target["name"]),
		total_submitted,
		total_required,
		completed_materials,
		materials.size(),
		build_state
	]

func _update_build_button() -> void:
	if build_target.is_empty():
		build_button.disabled = true
		build_button.text = "无法建造"
		return

	if bool(build_target["built"]):
		build_button.disabled = true
		build_button.text = "已建造"
		return

	if _is_ready_to_build():
		build_button.disabled = false
		build_button.text = str(build_target["build_label"])
		return

	build_button.disabled = true
	build_button.text = "材料未齐"

func _is_ready_to_build() -> bool:
	if build_target.is_empty() or bool(build_target["built"]):
		return false

	for material_data in _get_materials():
		if int(material_data["submitted_amount"]) < int(material_data["required_amount"]):
			return false

	return true

func _submit_selected_material(amount: int) -> void:
	if build_target.is_empty() or bool(build_target["built"]):
		_update_default_status()
		return

	var materials: Array[Dictionary] = _get_materials()
	if _selected_material_index < 0 or _selected_material_index >= materials.size():
		return

	var material_data: Dictionary = materials[_selected_material_index]
	var required_amount: int = int(material_data["required_amount"])
	var submitted_amount: int = int(material_data["submitted_amount"])
	var remaining_amount: int = maxi(required_amount - submitted_amount, 0)

	if remaining_amount <= 0:
		_update_default_status()
		return

	var actual_submit_amount: int = clampi(amount, 1, remaining_amount)
	material_data["submitted_amount"] = submitted_amount + actual_submit_amount
	materials[_selected_material_index] = material_data
	build_target["materials"] = materials
	building_catalog[_selected_building_index] = build_target

	_refresh_selected_material()
	_update_summary()
	_update_build_button()

	if _is_ready_to_build():
		status_label.text = "最后一批材料已提交，现可开始建造。"
		status_label.modulate = Color(0.15, 0.45, 0.2)
	else:
		status_label.text = "已向 %s 提交 %d %s。" % [
			str(build_target["name"]),
			actual_submit_amount,
			str(material_data["name"])
		]
		status_label.modulate = Color(0.15, 0.45, 0.2)

	material_submitted.emit(
		str(build_target["id"]),
		str(material_data["id"]),
		actual_submit_amount,
		int(material_data["submitted_amount"])
	)

func _build_current_target() -> void:
	if not _is_ready_to_build():
		_update_default_status()
		return

	build_target["built"] = true
	building_catalog[_selected_building_index] = build_target
	_refresh_selected_material()
	_update_summary()
	_update_build_button()
	status_label.text = "%s 建造完成。" % str(build_target["name"])
	status_label.modulate = Color(0.15, 0.45, 0.2)
	build_completed.emit(str(build_target["id"]))

func _on_building_selected(index: int) -> void:
	_select_building(index)

func _on_material_selected(index: int) -> void:
	_selected_material_index = index
	_refresh_selected_material()
	_update_default_status()

func _on_submit_pressed() -> void:
	_submit_selected_material(int(submit_amount.value))

func _on_build_pressed() -> void:
	_build_current_target()

func _on_submit_amount_changed(_value: float) -> void:
	if submit_button.disabled:
		return
	_update_default_status()
