class_name CorridorGenerator
extends Node2D

signal pad_requested(position: Vector2, direction: Vector2, difficulty: float, risky: bool)

@export_category("Corridor")
@export var corridor_width := 330.0
@export var min_segment_length := 440.0
@export var max_segment_length := 680.0
@export var min_angle := 13.0
@export var max_angle := 34.0
@export var max_bend_delta := 48.0
@export_range(90.0, 180.0, 5.0) var bend_transition_length := 130.0
@export_range(4, 16, 1) var bend_curve_steps := 9
@export var sharp_bend_width_bonus := 34.0
@export var difficulty_narrowing_rate := 0.045
@export_category("Progression")
@export var bend_difficulty_growth := 0.018
@export var corridor_width_reduction := 4.0

var points: Array[Vector2] = []
var widths: Array[float] = []
var segment_angles: Array[float] = []
var path_points: Array[Vector2] = []
var path_widths: Array[float] = []
var generated_pads: Dictionary = {}
var rng := RandomNumberGenerator.new()
var debug_draw := false

func _ready() -> void:
	rng.seed = 73571

func reset() -> void:
	rng.seed = 73571
	points = [Vector2(0, 360), Vector2(0, -360)]
	widths = [corridor_width, corridor_width]
	segment_angles = [0.0]
	generated_pads.clear()
	_generate_until(-5200.0, 0.0)
	queue_redraw()

func ensure_ahead(world_y: float, difficulty: float) -> void:
	_generate_until(world_y - 4300.0, difficulty)

func _generate_until(target_y: float, difficulty: float) -> void:
	var generated := false
	while points.back().y > target_y:
		generated = true
		var index := points.size() - 1
		var sign_value := -1.0 if index % 2 == 0 else 1.0
		var angle_limit := minf(max_angle + difficulty * bend_difficulty_growth, 43.0)
		var angle_deg := sign_value * rng.randf_range(min_angle, angle_limit)
		var previous_angle: float = segment_angles.back()
		# Tighten the bend cap slightly as speed/distance rises. Shorter reaction
		# time should be the challenge, not an impossible generated heading jump.
		var fairness_factor := clampf(difficulty / 600.0, 0.0, 1.0)
		var allowed_delta := lerpf(max_bend_delta, max_bend_delta * 0.82, fairness_factor)
		angle_deg = clampf(angle_deg, previous_angle - allowed_delta, previous_angle + allowed_delta)
		var length_scale := clampf(1.0 - difficulty * 0.0015, 0.7, 1.0)
		var length := rng.randf_range(min_segment_length, max_segment_length) * length_scale
		var direction := Vector2(sin(deg_to_rad(angle_deg)), -cos(deg_to_rad(angle_deg)))
		var next_point: Vector2 = points.back() + direction * length
		var bend_delta := absf(angle_deg - previous_angle)
		var bend_ratio := clampf(bend_delta / maxf(1.0, max_bend_delta), 0.0, 1.0)
		var new_width := maxf(215.0, corridor_width - difficulty * difficulty_narrowing_rate - index * corridor_width_reduction * 0.08)
		new_width += sharp_bend_width_bonus * bend_ratio
		points.append(next_point)
		widths.append(new_width)
		segment_angles.append(angle_deg)

		# Pads follow the racing line. Sharper apexes favor center recovery; some
		# ordinary pads offset toward a wall for optional risk/reward.
		if index >= 2:
			var is_sharp := bend_delta > 30.0
			var base_position: Vector2
			if is_sharp:
				# Put the skill pad just inside the blended apex. The approach is still
				# the incoming line; a perfect hit assists toward the outgoing line.
				var corner := points[index]
				var incoming := (corner - points[index - 1]).normalized()
				var half_transition := minf(bend_transition_length * 0.5, minf((corner - points[index - 1]).length() * 0.28, length * 0.28))
				var entry := corner - incoming * half_transition
				var exit := corner + direction * half_transition
				base_position = _quadratic(entry, corner, exit, 0.28)
			else:
				base_position = points[index].lerp(next_point, rng.randf_range(0.48, 0.68))
			var normal := Vector2(-direction.y, direction.x)
			var risky := rng.randf() < 0.24 and not is_sharp
			var offset := normal * (new_width * 0.24 * (-1.0 if rng.randf() < 0.5 else 1.0)) if risky else Vector2.ZERO
			pad_requested.emit(base_position + offset, direction, difficulty, risky)
	if generated:
		_rebuild_smoothed_path()
		queue_redraw()

func _quadratic(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	var inverse := 1.0 - t
	return a * (inverse * inverse) + control * (2.0 * inverse * t) + b * (t * t)

func _append_path_point(point: Vector2, width: float) -> void:
	if path_points.is_empty() or path_points.back().distance_squared_to(point) > 0.01:
		path_points.append(point)
		path_widths.append(width)

func _rebuild_smoothed_path() -> void:
	path_points.clear()
	path_widths.clear()
	if points.size() < 2:
		return
	_append_path_point(points[0], widths[0])
	for i in range(1, points.size() - 1):
		var previous := points[i - 1]
		var corner := points[i]
		var following := points[i + 1]
		var incoming := (corner - previous).normalized()
		var outgoing := (following - corner).normalized()
		var half_transition := minf(bend_transition_length * 0.5, minf(corner.distance_to(previous) * 0.28, corner.distance_to(following) * 0.28))
		var entry := corner - incoming * half_transition
		var exit := corner + outgoing * half_transition
		_append_path_point(entry, widths[i])
		for step in range(1, bend_curve_steps + 1):
			var t := float(step) / float(bend_curve_steps)
			_append_path_point(_quadratic(entry, corner, exit, t), lerpf(widths[i], widths[i + 1], t * 0.5))
	_append_path_point(points.back(), widths.back())

func sample(position_value: Vector2) -> Dictionary:
	var best_distance := INF
	var result := {}
	for i in range(path_points.size() - 1):
		var a := path_points[i]
		var b := path_points[i + 1]
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
				"width": lerpf(path_widths[i], path_widths[i + 1], t),
				"angle": rad_to_deg(atan2(direction.x, -direction.y)),
				"segment": i,
			}
	return result

func _draw() -> void:
	for i in range(path_points.size() - 1):
		var a := path_points[i]
		var b := path_points[i + 1]
		var direction := (b - a).normalized()
		var normal := Vector2(-direction.y, direction.x)
		var half_a := path_widths[i] * 0.5
		var half_b := path_widths[i + 1] * 0.5
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
