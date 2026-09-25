class_name FlightHero
extends Node2D

@export_category("Flight")
@export var base_speed := 360.0
@export var max_speed := 920.0
@export var min_speed := 280.0
@export var correction_impulse := 92.0
@export var vertical_drift := 4.0
@export_range(0.0, 2.0, 0.01) var velocity_damping := 0.06
@export_range(0.0, 12.0, 0.1) var turn_responsiveness := 3.2
@export_range(0.0, 1.0, 0.01) var steering_inertia := 0.82
@export var radius := 17.0

var velocity := Vector2.ZERO
var correction_direction := Vector2.UP
var alive := true
var trail_points: Array[Vector2] = []
var tumble := 0.0

func reset_flight(at_position: Vector2, initial_direction: Vector2) -> void:
	position = at_position
	velocity = initial_direction.normalized() * base_speed
	correction_direction = initial_direction.normalized()
	alive = true
	tumble = 0.0
	rotation = velocity.angle() + PI * 0.5
	trail_points.clear()
	queue_redraw()

func apply_tap(target_direction: Vector2) -> void:
	if not alive:
		return
	correction_direction = target_direction.normalized()
	velocity += correction_direction * correction_impulse
	var speed := velocity.length()
	if speed > max_speed:
		velocity = velocity.normalized() * max_speed

func step_flight(delta: float, desired_direction: Vector2) -> void:
	if not alive:
		velocity.y += 760.0 * delta
		velocity *= maxf(0.0, 1.0 - 0.7 * delta)
		position += velocity * delta
		tumble += delta * 8.0
		rotation += delta * 8.0
		queue_redraw()
		return

	# Momentum stays dominant. The weak continuous term only prevents numerical drift;
	# meaningful course changes come from taps and perfect-pad assistance.
	var speed := clampf(velocity.length(), min_speed, max_speed)
	var current_dir := velocity.normalized()
	var passive_turn := (1.0 - steering_inertia) * turn_responsiveness * 0.08
	var blended := current_dir.slerp(desired_direction.normalized(), clampf(passive_turn * delta, 0.0, 0.08))
	velocity = blended.normalized() * speed
	velocity.y += vertical_drift * delta
	velocity *= maxf(0.0, 1.0 - velocity_damping * delta)
	if velocity.length() < min_speed:
		velocity = velocity.normalized() * min_speed
	position += velocity * delta
	rotation = lerp_angle(rotation, velocity.angle() + PI * 0.5, delta * 7.0)

	trail_points.push_front(position)
	if trail_points.size() > 22:
		trail_points.pop_back()
	queue_redraw()

func boost(amount: float, ideal_direction: Vector2, reorient: float) -> void:
	var new_speed := minf(velocity.length() + amount, max_speed)
	var new_dir := velocity.normalized().slerp(ideal_direction.normalized(), clampf(reorient, 0.0, 1.0))
	velocity = new_dir.normalized() * new_speed

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

