class_name BoostPad
extends Node2D

enum HitQuality { NONE, EDGE, NORMAL, PERFECT }

@export var pad_radius := 54.0
@export var perfect_radius := 18.0
var consumed := false
var ideal_direction := Vector2.UP
var risky := false
var pulse := 0.0

func setup(world_position: Vector2, direction: Vector2, radius_value: float, perfect_value: float, is_risky: bool) -> void:
	position = world_position
	ideal_direction = direction.normalized()
	pad_radius = radius_value
	perfect_radius = perfect_value
	risky = is_risky
	queue_redraw()

func test_hit(hero_position: Vector2, hero_radius: float) -> int:
	if consumed:
		return HitQuality.NONE
	var distance := hero_position.distance_to(position)
	if distance > pad_radius + hero_radius:
		return HitQuality.NONE
	consumed = true
	queue_redraw()
	if distance <= perfect_radius:
		return HitQuality.PERFECT
	if distance <= pad_radius * 0.66:
		return HitQuality.NORMAL
	return HitQuality.EDGE

func _process(delta: float) -> void:
	pulse += delta
	if not consumed:
		queue_redraw()

func _draw() -> void:
	if consumed:
		draw_circle(Vector2.ZERO, pad_radius, Color(0.3, 0.8, 1.0, 0.05))
		return
	var glow := 0.12 + sin(pulse * 5.0) * 0.035
	draw_circle(Vector2.ZERO, pad_radius + 9.0, Color(0.2, 0.9, 1.0, glow))
	draw_arc(Vector2.ZERO, pad_radius, 0.0, TAU, 48, Color("42e8ff"), 7.0, true)
	draw_circle(Vector2.ZERO, perfect_radius, Color(1.0, 0.82, 0.25, 0.28))
	draw_arc(Vector2.ZERO, perfect_radius, 0.0, TAU, 32, Color("ffe05a"), 4.0, true)
	draw_line(-ideal_direction * 14.0, ideal_direction * 14.0, Color(1, 1, 1, 0.72), 3.0, true)

