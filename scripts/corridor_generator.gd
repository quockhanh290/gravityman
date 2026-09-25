class_name CorridorGenerator
extends Node2D

signal pad_requested(position: Vector2, direction: Vector2, difficulty: float, risky: bool)

@export_category("Corridor")
@export var corridor_width := 330.0
@export var min_segment_length := 440.0
@export var max_segment_length := 680.0
@export var min_angle := 13.0
@export var max_angle := 34.0
@export var max_bend_delta := 58.0
@export var difficulty_narrowing_rate := 0.045
@export_category("Progression")
@export var bend_difficulty_growth := 0.018
@export var corridor_width_reduction := 4.0

var points: Array[Vector2] = []
var widths: Array[float] = []
var segment_angles: Array[float] = []
var generated_pads: Dictionary = {}
var rng := RandomNumberGenerator.new()
var debug_draw := false

func _ready() -> void:
	rng.seed = 73571

func reset() -> void:
	points = [Vector2(0, 360), Vector2(0, -360)]
	widths = [corridor_width, corridor_width]
	segment_angles = [0.0]
	generated_pads.clear()
	_generate_until(-5200.0, 0.0)
	queue_redraw()

func ensure_ahead(world_y: float, difficulty: float) -> void:
	_generate_until(world_y - 4300.0, difficulty)

func _generate_until(target_y: float, difficulty: float) -> void:
	while points.back().y > target_y:
		var index := points.size() - 1
		var sign_value := -1.0 if index % 2 == 0 else 1.0
		var angle_limit := minf(max_angle + difficulty * bend_difficulty_growth, 43.0)
		var angle_deg := sign_value * rng.randf_range(min_angle, angle_limit)
		var previous_angle: float = segment_angles.back()
		angle_deg = clampf(angle_deg, previous_angle - max_bend_delta, previous_angle + max_bend_delta)
		var length_scale := clampf(1.0 - difficulty * 0.0015, 0.7, 1.0)
		var length := rng.randf_range(min_segment_length, max_segment_length) * length_scale
		var direction := Vector2(sin(deg_to_rad(angle_deg)), -cos(deg_to_rad(angle_deg)))
		var next_point: Vector2 = points.back() + direction * length
		var new_width := maxf(205.0, corridor_width - difficulty * difficulty_narrowing_rate - index * corridor_width_reduction * 0.08)
		points.append(next_point)
		widths.append(new_width)
		segment_angles.append(angle_deg)

		# Pads follow the racing line. Sharper apexes favor center recovery; some
		# ordinary pads offset toward a wall for optional risk/reward.
		if index >= 2:
			var t := 0.73 if absf(angle_deg - previous_angle) > 30.0 else rng.randf_range(0.48, 0.72)
			var base_position: Vector2 = points[index].lerp(next_point, t)
			var normal := Vector2(-direction.y, direction.x)
			var risky := rng.randf() < 0.24 and absf(angle_deg - previous_angle) < 38.0
			var offset := normal * (new_width * 0.24 * (-1.0 if rng.randf() < 0.5 else 1.0)) if risky else Vector2.ZERO
			pad_requested.emit(base_position + offset, direction, difficulty, risky)
	queue_redraw()

func sample(position_value: Vector2) -> Dictionary:
	var best_distance := INF
	var result := {}
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var t := clampf((position_value - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var center := a + ab * t
		var distance := position_value.distance_squared_to(center)
		if distance < best_distance:
			best_distance = distance
			var direction := ab.normalized()
			var normal := Vector2(-direction.y, direction.x)
			result = {
				"center": center,
				"direction": direction,
				"normal": normal,
				"signed_distance": (position_value - center).dot(normal),
				"width": lerpf(widths[i], widths[i + 1], t),
				"angle": segment_angles[i],
				"segment": i,
			}
	return result

func _draw() -> void:
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var direction := (b - a).normalized()
		var normal := Vector2(-direction.y, direction.x)
		var half_a := widths[i] * 0.5
		var half_b := widths[i + 1] * 0.5
		var left_a := a - normal * half_a
		var left_b := b - normal * half_b
		var right_a := a + normal * half_a
		var right_b := b + normal * half_b
		var wall_depth := 170.0
		draw_colored_polygon(PackedVector2Array([left_a, left_b, left_b - normal * wall_depth, left_a - normal * wall_depth]), Color("162445"))
		draw_colored_polygon(PackedVector2Array([right_a, right_b, right_b + normal * wall_depth, right_a + normal * wall_depth]), Color("162445"))
		draw_line(left_a, left_b, Color("55d9ee"), 8.0, true)
		draw_line(right_a, right_b, Color("55d9ee"), 8.0, true)
		if debug_draw:
			draw_line(a, b, Color(1.0, 0.85, 0.2, 0.65), 2.0, true)
			draw_line(left_a + normal * 22.0, left_b + normal * 22.0, Color(1, 0.35, 0.5, 0.5), 2.0, true)
			draw_line(right_a - normal * 22.0, right_b - normal * 22.0, Color(1, 0.35, 0.5, 0.5), 2.0, true)

