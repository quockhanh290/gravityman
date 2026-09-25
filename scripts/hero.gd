class_name FlightHero
extends Node2D

@export_category("Flight")
@export var cruise_speed := 360.0
@export var max_speed := 920.0
@export var min_speed := 300.0
@export_range(1.0, 12.0, 0.1) var tap_angle_impulse_degrees := 9.5
@export_range(1.0, 6.0, 0.1) var neutral_blend_angle_degrees := 3.0
@export_range(10.0, 70.0, 1.0) var vertical_return_rate_degrees := 22.0
@export_range(30.0, 70.0, 1.0) var max_heading_angle_degrees := 52.0
@export_range(0.0, 3.0, 0.1) var weak_corridor_follow_rate := 0.0
@export var radius := 17.0

const WORLD_UP := Vector2.UP

var velocity := Vector2.ZERO
var correction_direction := Vector2.UP
var flight_direction := Vector2.UP
var forward_speed := 0.0
var heading_angle := 0.0
var desired_heading_degrees := 0.0
var lateral_velocity := 0.0
var steering_error_degrees := 0.0
var vertical_return_contribution_degrees := 0.0
var last_raw_tap_impulse_degrees := 0.0
var last_applied_tap_impulse_degrees := 0.0
var last_tap_blend_factor := 0.0
var alive := true
var trail_points: Array[Vector2] = []
var tumble := 0.0
var debug_visuals := false
var debug_desired_direction := Vector2.UP

func reset_flight(at_position: Vector2, initial_direction: Vector2) -> void:
	position = at_position
	forward_speed = cruise_speed
	flight_direction = initial_direction.normalized()
	heading_angle = wrapf(WORLD_UP.angle_to(flight_direction), -PI, PI)
	velocity = flight_direction * forward_speed
	correction_direction = initial_direction.normalized()
	debug_desired_direction = correction_direction
	lateral_velocity = 0.0
	steering_error_degrees = 0.0
	desired_heading_degrees = rad_to_deg(heading_angle)
	vertical_return_contribution_degrees = 0.0
	last_raw_tap_impulse_degrees = 0.0
	last_applied_tap_impulse_degrees = 0.0
	last_tap_blend_factor = 0.0
	alive = true
	tumble = 0.0
	rotation = velocity.angle() + PI * 0.5
	trail_points.clear()
	queue_redraw()

func apply_tap(target_direction: Vector2) -> void:
	if not alive:
		return
	correction_direction = target_direction.normalized()
	var desired_angle := wrapf(WORLD_UP.angle_to(correction_direction), -PI, PI)
	# Tap authority is constant outside a tiny neutral blend. Corridor angle picks
	# the direction, not the magnitude; only +/-3 degrees around vertical fades
	# smoothly to zero so the sign cannot flip abruptly through a bend.
	var tap_sign := signf(desired_angle)
	var neutral_angle := deg_to_rad(maxf(0.1, neutral_blend_angle_degrees))
	var blend_factor := clampf(absf(desired_angle) / neutral_angle, 0.0, 1.0)
	var raw_impulse := deg_to_rad(tap_angle_impulse_degrees) * tap_sign
	var impulse := raw_impulse * blend_factor
	heading_angle = clampf(heading_angle + impulse, -deg_to_rad(max_heading_angle_degrees), deg_to_rad(max_heading_angle_degrees))
	last_raw_tap_impulse_degrees = rad_to_deg(raw_impulse)
	last_applied_tap_impulse_degrees = rad_to_deg(impulse)
	last_tap_blend_factor = blend_factor
	flight_direction = WORLD_UP.rotated(heading_angle)
	velocity = flight_direction * forward_speed

func step_flight(delta: float, desired_direction: Vector2) -> void:
	if not alive:
		velocity.y += 760.0 * delta
		velocity *= maxf(0.0, 1.0 - 0.7 * delta)
		position += velocity * delta
		tumble += delta * 8.0
		rotation += delta * 8.0
		queue_redraw()
		return

	var desired := desired_direction.normalized()
	var desired_angle := wrapf(WORLD_UP.angle_to(desired), -PI, PI)
	var old_heading := heading_angle
	debug_desired_direction = desired
	desired_heading_degrees = rad_to_deg(desired_angle)

	# World-up is the sole natural attractor. The actual heading remains a stable
	# world-space angle and is never reconstructed from a rotating corridor basis.
	heading_angle = move_toward(heading_angle, 0.0, deg_to_rad(vertical_return_rate_degrees) * delta)
	vertical_return_contribution_degrees = rad_to_deg(heading_angle - old_heading) / maxf(delta, 0.0001)
	if weak_corridor_follow_rate > 0.0:
		heading_angle = move_toward(heading_angle, desired_angle, deg_to_rad(weak_corridor_follow_rate) * delta)
	heading_angle = clampf(heading_angle, -deg_to_rad(max_heading_angle_degrees), deg_to_rad(max_heading_angle_degrees))
	forward_speed = clampf(forward_speed, min_speed, max_speed)

	flight_direction = WORLD_UP.rotated(heading_angle)
	velocity = flight_direction * forward_speed
	var side := Vector2(-desired.y, desired.x)
	lateral_velocity = velocity.dot(side)
	steering_error_degrees = rad_to_deg(wrapf(heading_angle - desired_angle, -PI, PI))
	position += velocity * delta
	rotation = lerp_angle(rotation, velocity.angle() + PI * 0.5, delta * 7.0)

	trail_points.push_front(position)
	if trail_points.size() > 22:
		trail_points.pop_back()
	queue_redraw()

func boost(amount: float, ideal_direction: Vector2, reorient: float) -> void:
	var new_speed := minf(forward_speed + amount, max_speed)
	var new_dir := flight_direction.slerp(ideal_direction.normalized(), clampf(reorient, 0.0, 1.0)).normalized()
	forward_speed = new_speed
	flight_direction = new_dir
	heading_angle = clampf(wrapf(WORLD_UP.angle_to(flight_direction), -PI, PI), -deg_to_rad(max_heading_angle_degrees), deg_to_rad(max_heading_angle_degrees))
	flight_direction = WORLD_UP.rotated(heading_angle)
	velocity = flight_direction * forward_speed

func set_flight_direction(direction: Vector2) -> void:
	flight_direction = direction.normalized()
	heading_angle = clampf(wrapf(WORLD_UP.angle_to(flight_direction), -PI, PI), -deg_to_rad(max_heading_angle_degrees), deg_to_rad(max_heading_angle_degrees))
	flight_direction = WORLD_UP.rotated(heading_angle)
	velocity = flight_direction * forward_speed

func set_speed(value: float) -> void:
	forward_speed = clampf(value, min_speed, max_speed)
	velocity = velocity.normalized() * forward_speed

func crash() -> void:
	alive = false
	velocity *= 0.22
	queue_redraw()

func _draw() -> void:
	# Local trail is reconstructed from world samples.
	if trail_points.size() > 1:
		for i in range(1, trail_points.size()):
			var a: Vector2 = to_local(trail_points[i - 1])
			var b: Vector2 = to_local(trail_points[i])
			var alpha := 0.48 * (1.0 - float(i) / float(trail_points.size()))
			draw_line(a, b, Color(0.25, 0.92, 1.0, alpha), maxf(2.0, 13.0 - i * 0.45), true)
	draw_circle(Vector2.ZERO, radius + 7.0, Color(0.1, 0.8, 1.0, 0.16))
	draw_circle(Vector2.ZERO, radius, Color("f5fbff"))
	draw_circle(Vector2(0, -5), radius * 0.58, Color("4de2ff"))
	draw_polygon(PackedVector2Array([Vector2(-10, 12), Vector2(10, 12), Vector2(0, 30)]), PackedColorArray([Color("ff4e8a")]))
	if debug_visuals:
		var desired_local := debug_desired_direction.rotated(-rotation) * 125.0
		var velocity_local := flight_direction.rotated(-rotation) * 125.0
		var world_up_local := WORLD_UP.rotated(-rotation) * 105.0
		draw_line(Vector2.ZERO, desired_local, Color("62ff8b"), 5.0, true)
		draw_line(Vector2.ZERO, velocity_local, Color("4de2ff"), 4.0, true)
		draw_line(Vector2.ZERO, world_up_local, Color(0.9, 0.92, 0.96, 0.72), 3.0, true)
