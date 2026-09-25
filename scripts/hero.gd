class_name FlightHero
extends Node2D

@export_category("Flight")
@export var cruise_speed := 360.0
@export var max_speed := 920.0
@export var min_speed := 300.0
@export var tap_steering_impulse := 72.0
@export var natural_drift_acceleration := 52.0
@export_range(0.0, 2.0, 0.01) var steering_damping := 0.12
@export var max_lateral_velocity := 175.0
@export_range(1.0, 12.0, 0.1) var trajectory_follow_rate := 5.0
@export var radius := 17.0

var velocity := Vector2.ZERO
var correction_direction := Vector2.UP
var forward_direction := Vector2.UP
var forward_speed := 0.0
var steering_velocity := 0.0
var lateral_velocity := 0.0
var steering_error_degrees := 0.0
var tap_correction_state := 0.0
var alive := true
var trail_points: Array[Vector2] = []
var tumble := 0.0
var debug_visuals := false
var debug_desired_direction := Vector2.UP

func reset_flight(at_position: Vector2, initial_direction: Vector2) -> void:
	position = at_position
	forward_speed = cruise_speed
	steering_velocity = 0.0
	velocity = initial_direction.normalized() * forward_speed
	forward_direction = initial_direction.normalized()
	correction_direction = initial_direction.normalized()
	debug_desired_direction = correction_direction
	lateral_velocity = 0.0
	steering_error_degrees = 0.0
	tap_correction_state = 0.0
	alive = true
	tumble = 0.0
	rotation = velocity.angle() + PI * 0.5
	trail_points.clear()
	queue_redraw()

func apply_tap(target_direction: Vector2) -> void:
	if not alive:
		return
	correction_direction = target_direction.normalized()
	# A tap changes only the corridor-local lateral steering state. It never adds
	# forward energy, so rapid taps accumulate into visible opposite-wall oversteer.
	steering_velocity = maxf(-max_lateral_velocity, steering_velocity - tap_steering_impulse)
	tap_correction_state = -1.0

func step_flight(delta: float, desired_direction: Vector2) -> void:
	if not alive:
		velocity.y += 760.0 * delta
		velocity *= maxf(0.0, 1.0 - 0.7 * delta)
		position += velocity * delta
		tumble += delta * 8.0
		rotation += delta * 8.0
		queue_redraw()
		return

	var forward := desired_direction.normalized()
	var side := Vector2(-forward.y, forward.x)
	debug_desired_direction = forward
	forward_direction = forward_direction.slerp(forward, 1.0 - exp(-trajectory_follow_rate * delta)).normalized()

	# The one-button balance: natural drift continuously builds steering toward
	# +side, while taps push toward -side. Damping softens reversals but cannot
	# cancel drift on its own, so both no-input and spam-input eventually fail.
	steering_velocity += natural_drift_acceleration * delta
	steering_velocity *= maxf(0.0, 1.0 - steering_damping * delta)
	steering_velocity = clampf(steering_velocity, -max_lateral_velocity, max_lateral_velocity)
	forward_speed = clampf(forward_speed, min_speed, max_speed)

	# Compose direction from corridor-local components, then restore forward speed.
	# Therefore regular taps rotate the trajectory without accelerating the hero.
	var composed := forward_direction * forward_speed + side * steering_velocity
	velocity = composed.normalized() * forward_speed
	lateral_velocity = velocity.dot(side)
	steering_error_degrees = rad_to_deg(wrapf(velocity.angle() - forward.angle(), -PI, PI))
	tap_correction_state = move_toward(tap_correction_state, 0.0, delta * 3.5)
	position += velocity * delta
	rotation = lerp_angle(rotation, velocity.angle() + PI * 0.5, delta * 7.0)

	trail_points.push_front(position)
	if trail_points.size() > 22:
		trail_points.pop_back()
	queue_redraw()

func boost(amount: float, ideal_direction: Vector2, reorient: float) -> void:
	var new_speed := minf(forward_speed + amount, max_speed)
	var new_dir := velocity.normalized().slerp(ideal_direction.normalized(), clampf(reorient, 0.0, 1.0))
	forward_speed = new_speed
	forward_direction = forward_direction.slerp(ideal_direction.normalized(), clampf(reorient, 0.0, 1.0)).normalized()
	velocity = new_dir.normalized() * forward_speed
	var side := Vector2(-ideal_direction.y, ideal_direction.x).normalized()
	steering_velocity = clampf(velocity.dot(side), -max_lateral_velocity, max_lateral_velocity)

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
		var velocity_local := velocity.normalized().rotated(-rotation) * 125.0
		var side_world := Vector2(-debug_desired_direction.y, debug_desired_direction.x)
		var lateral_local := side_world.rotated(-rotation) * lateral_velocity * 0.55
		draw_line(Vector2.ZERO, desired_local, Color("62ff8b"), 5.0, true)
		draw_line(Vector2.ZERO, velocity_local, Color("4de2ff"), 4.0, true)
		draw_line(Vector2.ZERO, lateral_local, Color("ff5575"), 4.0, true)
