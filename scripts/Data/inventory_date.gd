# 继承自 Resource，说明这是一个数据资源类，用于存储数据
# 定义类名为 InventoryDate
extends Resource
class_name InventoryDate

# --- 信号定义区 ---
# 当背包整体数据发生变化时发射，传递自身作为参数
signal inventory_data_changed(inventory_data: InventoryDate)
# 当某一个插槽的数据发生变化时发射，传递插槽索引和插槽数据
signal slot_changed(slot_index: int, slot_data: SlotData)
# 当某一个插槽内的物品属性发生变化时发射，传递详细信息
signal slot_item_data_changed(slot_index: int, slot_data: SlotData, item_data: ItemData, property_name: StringName, value: Variant)

# --- 核心数据区 ---
# 定义一个导出数组，用于存储所有的插槽数据 (SlotData)
# 注意：变量名为 solt_date
@export var solt_date: Array[SlotData] = []:
	# 设置器 (Setter)：当 solt_date 被赋值时自动执行
	set(value):
		# 1. 先断开旧数组中所有信号连接（防止内存泄漏或逻辑错误）
		_disconnect_slot_signals()
		# 2. 真正赋值给内部变量
		solt_date = value
		# 3. 连接新数组中所有信号
		_connect_slot_signals()
		# 4. 通知 Godot 引擎该资源已发生变化（用于编辑器刷新）
		emit_changed()
		# 5. 发射自定义信号，通知监听者背包数据变了
		emit_signal("inventory_data_changed", self)

# --- 公有方法 ---
# 提供给外部调用的手动绑定信号接口
func bind_signals() -> void:
	_connect_slot_signals()

# 获取指定索引的插槽数据，带越界检查
func get_slot(slot_index: int) -> SlotData:
	# 如果索引越界，返回空
	if slot_index < 0 or slot_index >= solt_date.size():
		return null
	# 返回对应插槽数据
	return solt_date[slot_index]

# --- 内部私有方法 ---
# 连接所有插槽的信号
func _connect_slot_signals() -> void:
	# 遍历数组中的每一个 slot_data
	for slot_data in solt_date:
		# 跳过空元素
		if slot_data == null:
			continue
		# 1. 让插槽自己先绑定好它内部的信号
		slot_data.bind_signals()
		# 2. 连接“插槽本身变化”的信号
		if not slot_data.slot_data_changed.is_connected(_on_slot_changed):
			slot_data.slot_data_changed.connect(_on_slot_changed)
		# 3. 连接“插槽内物品属性变化”的信号
		if not slot_data.item_data_changed.is_connected(_on_slot_item_data_changed):
			slot_data.item_data_changed.connect(_on_slot_item_data_changed)

# 断开所有插槽的信号（与上面的操作正好相反）
func _disconnect_slot_signals() -> void:
	for slot_data in solt_date:
		if slot_data == null:
			continue
		# 断开“插槽本身变化”的信号
		if slot_data.slot_data_changed.is_connected(_on_slot_changed):
			slot_data.slot_data_changed.disconnect(_on_slot_changed)
		# 断开“插槽内物品属性变化”的信号
		if slot_data.item_data_changed.is_connected(_on_slot_item_data_changed):
			slot_data.item_data_changed.disconnect(_on_slot_item_data_changed)

# --- 信号响应函数 ---
# 当收到“插槽数据变化”信号时调用
func _on_slot_changed(changed_slot_data: SlotData) -> void:
	# 在数组中查找是哪个插槽的索引
	var slot_index := solt_date.find(changed_slot_data)
	# 转发信号：告诉外部具体是哪个索引变了
	emit_signal("slot_changed", slot_index, changed_slot_data)
	emit_changed()
	# 同时也认为背包整体数据发生了变化
	emit_signal("inventory_data_changed", self)

# 当收到“物品属性变化”信号时调用
func _on_slot_item_data_changed(changed_slot_data: SlotData, item_data: ItemData, property_name: StringName, value: Variant) -> void:
	# 查找插槽索引
	var slot_index := solt_date.find(changed_slot_data)
	# 转发信号：把所有详细信息都传出去
	emit_signal("slot_item_data_changed", slot_index, changed_slot_data, item_data, property_name, value)
