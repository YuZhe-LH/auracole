extends RefCounted
class_name ConveyorArrowV2


static func get_arrow_polygon(center: Vector2, cell_size: float, direction_degrees: int) -> PackedVector2Array:
	var arrow_length := cell_size * 0.34
	var tail_half_width := cell_size * 0.08
	var base_points := PackedVector2Array([
		Vector2(-arrow_length * 0.5, -tail_half_width),
		Vector2(arrow_length * 0.1, -tail_half_width),
		Vector2(arrow_length * 0.1, -tail_half_width * 1.9),
		Vector2(arrow_length * 0.5, 0.0),
		Vector2(arrow_length * 0.1, tail_half_width * 1.9),
		Vector2(arrow_length * 0.1, tail_half_width),
		Vector2(-arrow_length * 0.5, tail_half_width)
	])
	var rotation_radians := deg_to_rad(float(direction_degrees))
	var rotated_points := PackedVector2Array()

	for point in base_points:
		rotated_points.append(center + point.rotated(rotation_radians))

	return rotated_points
