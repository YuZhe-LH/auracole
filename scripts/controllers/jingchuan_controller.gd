extends Node3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# TODO:Debug code for industry
	for child in get_children():
		print("Remove Child:"+child.name)
		if (child is DirectionalLight3D) or (child is WorldEnvironment):
			continue
		child.queue_free()
	var industry_scene: PackedScene = load("res://scenes/industry_area.tscn")
	var industry_instance: Node3D = industry_scene.instantiate()
	add_child(industry_instance)
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
