extends Node2D

@export_category("Pads")
@export var pad_radius := 54.0
@export var perfect_radius := 18.0
@export var edge_boost := 12.0
@export var normal_boost := 24.0
@export var perfect_boost := 42.0
@export_range(0.15, 0.6, 0.01) var perfect_min_effectiveness := 0.32
@export_range(0.2, 0.35, 0.01) var perfect_trajectory_reorientation := 0.28
@export_category("Graze")
@export var graze_distance := 28.0
@export_range(1.2, 2.5, 0.1) var graze_exit_multiplier := 1.6
@export var graze_score := 75
@export_category("Progression")
@export var speed_growth := 0.0

@onready var corridor: CorridorGenerator = $Corridor
@onready var hero: FlightHero = $Hero
@onready var camera: Camera2D = $Camera2D
@onready var score_label: Label = $UI/Score
@onready var event_label: Label = $UI/Event
@onready var debug_label: Label = $UI/Debug
@onready var crash_panel: Control = $UI/CrashPanel
@onready var crash_score: Label = $UI/CrashPanel/Score
@onready var flash: ColorRect = $UI/Flash

var pad_scene := preload("res://scenes/boost_pad.tscn")
var pads: Array[BoostPad] = []
var running := false
var distance_score := 0
var bonus_score := 0
var pads_hit := 0
var perfect_hits := 0
var perfect_streak := 0
var grazes := 0
var graze_chain := 0
var max_speed_reached := 0.0
var best_score := 0
var elapsed := 0.0
var last_pad_quality := "-"
var debug_enabled := false
var death_disabled := false
var slow_enabled := false
var event_tween: Tween
var camera_punch := Vector2.ZERO
var crash_freeze := 0.0

# A graze is an encounter, not a timer. It starts on entry, records the closest
# clearance, and awards once only after a safe exit past the hysteresis threshold.
var graze_active := false
var graze_side := 0
var graze_min_clearance := INF
var last_graze_quality := "-"

func _ready() -> void:
	best_score = int(load_best())
	corridor.pad_requested.connect(_spawn_pad)
	start_run()

func start_run() -> void:
	for pad in pads:
		if is_instance_valid(pad):
			pad.queue_free()
	pads.clear()
	corridor.reset()
	var start_sample := corridor.sample(Vector2(0, 160))
	hero.reset_flight(start_sample.center, start_sample.direction)
	distance_score = 0
	bonus_score = 0
	pads_hit = 0
	perfect_hits = 0
	perfect_streak = 0
	grazes = 0
	graze_chain = 0
	max_speed_reached = hero.forward_speed
	graze_active = false
	graze_side = 0
	graze_min_clearance = INF
	last_graze_quality = "-"
	elapsed = 0.0
	last_pad_quality = "-"
	running = true
	crash_freeze = 0.0
	crash_panel.visible = false
	flash.color.a = 0.0
	Engine.time_scale = 0.5 if slow_enabled else 1.0
	camera.position = hero.position + Vector2(0, -300)
	_show_event("TAP TO CORRECT", Color("aeeeff"), 0.9)

func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = event.is_action_pressed("tap") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
	if pressed:
		if running:
			var sample := corridor.sample(hero.position)
			var look_ahead := corridor.sample(hero.position + Vector2(sample.direction) * 180.0)
			hero.apply_tap(look_ahead.direction)
			camera_punch += -hero.correction_direction * 4.0
		else:
			start_run()
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("restart"):
		start_run()
	if event.is_action_pressed("debug_overlay"):
		debug_enabled = not debug_enabled
		debug_label.visible = debug_enabled
		corridor.debug_draw = debug_enabled
		hero.debug_visuals = debug_enabled
		corridor.queue_redraw()
		hero.queue_redraw()
	if event.is_action_pressed("slow_motion"):
		slow_enabled = not slow_enabled
		Engine.time_scale = 0.5 if slow_enabled else 1.0
	if event.is_action_pressed("disable_death"):
		death_disabled = not death_disabled
	if event.is_action_pressed("force_low_speed") and running:
		hero.set_speed(hero.min_speed)
	if event.is_action_pressed("force_high_speed") and running:
		hero.set_speed(hero.max_speed)

func _physics_process(delta: float) -> void:
	if crash_freeze > 0.0:
		crash_freeze -= delta
		return
	if not running:
		hero.step_flight(delta, Vector2.DOWN)
		camera.position = camera.position.lerp(hero.position + Vector2(0, -100), delta * 2.0)
		return

	elapsed += delta
	var previous_position := hero.position
	var sample := corridor.sample(hero.position)
	var look_ahead := corridor.sample(hero.position + Vector2(sample.direction) * 220.0)
	hero.step_flight(delta, look_ahead.direction)
	if speed_growth > 0.0:
		hero.set_speed(hero.forward_speed + speed_growth * delta)
	corridor.ensure_ahead(hero.position.y, float(distance_score))

	distance_score = maxi(distance_score, int(maxf(0.0, (160.0 - hero.position.y) / 45.0)))
	max_speed_reached = maxf(max_speed_reached, hero.forward_speed)
	var current_sample := corridor.sample(hero.position)
	var current_look_ahead := corridor.sample(hero.position + Vector2(current_sample.direction) * 220.0)
	var crashed := _update_collision(previous_position, hero.position)
	if not crashed:
		_update_pads(previous_position, hero.position)
	_update_camera(delta, current_look_ahead)
	_update_ui(current_sample, current_look_ahead)

func _update_collision(from_position: Vector2, to_position: Vector2) -> bool:
	# Sweep the frame path. At max speed this resolves the movement into samples
	# smaller than the hero radius, preventing skipped walls at blended corners.
	var travel_distance := from_position.distance_to(to_position)
	var steps := maxi(1, int(ceil(travel_distance / maxf(6.0, hero.radius * 0.55))))
	var minimum_clearance := INF
	var closest_sample := {}
	for step in range(steps + 1):
		var test_position := from_position.lerp(to_position, float(step) / float(steps))
		var test_sample := corridor.sample(test_position)
		var clearance: float = test_sample.width * 0.5 - absf(test_sample.signed_distance) - hero.radius
		if clearance < minimum_clearance:
			minimum_clearance = clearance
			closest_sample = test_sample

	if minimum_clearance <= 0.0:
		graze_active = false
		if death_disabled:
			var wall_side := signf(float(closest_sample.signed_distance))
			hero.position = Vector2(closest_sample.center) + Vector2(closest_sample.normal) * wall_side * (float(closest_sample.width) * 0.5 - hero.radius - 3.0)
			hero.set_flight_direction(hero.velocity.bounce(Vector2(closest_sample.normal)).normalized())
			_show_event("SAVED (NO DEATH)", Color("ff9eb8"), 0.35)
		else:
			_crash(Vector2(closest_sample.normal) * signf(float(closest_sample.signed_distance)))
		return true

	if minimum_clearance <= graze_distance:
		if not graze_active:
			graze_active = true
			graze_side = 1 if float(closest_sample.signed_distance) >= 0.0 else -1
			graze_min_clearance = minimum_clearance
		else:
			graze_min_clearance = minf(graze_min_clearance, minimum_clearance)
	elif graze_active:
		var end_sample := corridor.sample(to_position)
		var end_clearance: float = end_sample.width * 0.5 - absf(end_sample.signed_distance) - hero.radius
		if end_clearance >= graze_distance * graze_exit_multiplier:
			_award_graze(Vector2(end_sample.normal))
	return false

func _award_graze(wall_normal: Vector2) -> void:
	grazes += 1
	graze_chain += 1
	bonus_score += graze_score * graze_chain
	if graze_min_clearance <= graze_distance * 0.22:
		last_graze_quality = "INSANE"
	elif graze_min_clearance <= graze_distance * 0.52:
		last_graze_quality = "VERY CLOSE"
	else:
		last_graze_quality = "CLOSE"
	_show_event("GRAZE x%d" % graze_chain, Color("ff81af"), 0.45)
	camera_punch += wall_normal * -graze_side * 6.0
	graze_active = false
	graze_side = 0
	graze_min_clearance = INF

func _update_pads(from_position: Vector2, to_position: Vector2) -> void:
	for pad in pads:
		if not is_instance_valid(pad) or pad.consumed:
			continue
		var quality := pad.test_swept_hit(from_position, to_position, hero.radius)
		if quality == BoostPad.HitQuality.NONE:
			continue
		pads_hit += 1
		match quality:
			BoostPad.HitQuality.EDGE:
				perfect_streak = 0
				last_pad_quality = "EDGE"
				hero.boost(edge_boost, pad.ideal_direction, 0.02)
				_show_event("EDGE", Color("8ad9ff"), 0.45)
			BoostPad.HitQuality.NORMAL:
				perfect_streak = 0
				last_pad_quality = "NORMAL"
				hero.boost(normal_boost, pad.ideal_direction, 0.10)
				_show_event("BOOST", Color("52e8ff"), 0.5)
			BoostPad.HitQuality.PERFECT:
				perfect_hits += 1
				perfect_streak += 1
				last_pad_quality = "PERFECT"
				bonus_score += 100 * perfect_streak
				var boost_value := calculate_perfect_boost()
				hero.boost(boost_value, pad.ideal_direction, perfect_trajectory_reorientation)
				_show_event("PERFECT x%d" % perfect_streak, Color("ffe86a"), 0.62)
				_flash(Color(0.25, 0.9, 1.0, 0.2))
				camera_punch += -hero.velocity.normalized() * minf(12.0, 5.0 + perfect_streak)

func calculate_perfect_boost() -> float:
	# Remaining-headroom scaling produces a long, diminishing acceleration curve.
	var total_headroom := maxf(1.0, hero.max_speed - hero.cruise_speed)
	var headroom_ratio := clampf((hero.max_speed - hero.forward_speed) / total_headroom, 0.0, 1.0)
	return perfect_boost * lerpf(perfect_min_effectiveness, 1.0, sqrt(headroom_ratio))

func _update_camera(delta: float, look_ahead: Dictionary) -> void:
	var speed_factor := inverse_lerp(hero.min_speed, hero.max_speed, hero.forward_speed)
	var target: Vector2 = hero.position + Vector2(look_ahead.direction) * lerpf(285.0, 390.0, speed_factor)
	camera.position = camera.position.lerp(target, 1.0 - exp(-delta * 5.5))
	camera_punch = camera_punch.lerp(Vector2.ZERO, 1.0 - exp(-delta * 13.0))
	camera.offset = camera_punch
	camera.zoom = Vector2.ONE * lerpf(1.0, 0.88, speed_factor)

func _update_ui(sample: Dictionary, desired: Dictionary) -> void:
	score_label.text = str(distance_score + bonus_score / 100)
	if debug_enabled:
		debug_label.text = "F3 DEBUG\nvelocity   %7.1f, %7.1f\nforward    %7.1f\nheading    %+7.1f deg\ndesired    %+7.1f deg\nworld up      0.0 deg\nerror      %+7.1f deg\nreturn     %+7.1f deg/s\ntap impulse %+6.1f deg\nlateral    %+7.1f\nstreak     %d\npad        %s\ngraze      %s (%s)\nfps        %d\n\nR restart | 1 half speed: %s\n2 no death: %s | 3 low | 4 high" % [hero.velocity.x, hero.velocity.y, hero.forward_speed, rad_to_deg(hero.heading_angle), hero.desired_heading_degrees, hero.steering_error_degrees, hero.vertical_return_contribution_degrees, hero.last_tap_impulse_degrees, hero.lateral_velocity, perfect_streak, last_pad_quality, str(graze_active), last_graze_quality, Engine.get_frames_per_second(), str(slow_enabled), str(death_disabled)]

func _spawn_pad(world_position: Vector2, direction: Vector2, difficulty: float, risky: bool) -> void:
	var pad: BoostPad = pad_scene.instantiate()
	var shrinking_perfect := maxf(12.0, perfect_radius - difficulty * 0.002)
	pad.setup(world_position, direction, pad_radius, shrinking_perfect, risky)
	$Pads.add_child(pad)
	pads.append(pad)

func _crash(wall_normal: Vector2) -> void:
	running = false
	graze_active = false
	crash_freeze = 0.065
	hero.crash()
	camera_punch = wall_normal * 24.0
	_flash(Color(1.0, 0.2, 0.35, 0.34))
	var total := distance_score + bonus_score / 100
	best_score = maxi(best_score, total)
	save_best(best_score)
	crash_score.text = "SCORE  %d\nBEST   %d\n\n%d pads  -  %d perfect  -  %d grazes\nmax speed  %d" % [total, best_score, pads_hit, perfect_hits, grazes, int(max_speed_reached)]
	crash_panel.visible = true

func _show_event(message: String, color_value: Color, duration: float) -> void:
	event_label.text = message
	event_label.modulate = color_value
	event_label.scale = Vector2(1.28, 1.28)
	event_label.modulate.a = 1.0
	if event_tween and event_tween.is_valid():
		event_tween.kill()
	event_tween = create_tween().set_parallel()
	event_tween.tween_property(event_label, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK)
	event_tween.tween_property(event_label, "modulate:a", 0.0, duration).set_delay(0.16)

func _flash(color_value: Color) -> void:
	flash.color = color_value
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.24)

func load_best() -> int:
	var config := ConfigFile.new()
	if config.load("user://save.cfg") == OK:
		return int(config.get_value("score", "best", 0))
	return 0

func save_best(value: int) -> void:
	var config := ConfigFile.new()
	config.set_value("score", "best", value)
	config.save("user://save.cfg")
