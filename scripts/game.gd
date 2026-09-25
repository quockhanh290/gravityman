extends Node2D

@export_category("Pads")
@export var pad_radius := 54.0
@export var perfect_radius := 18.0
@export var edge_boost := 28.0
@export var normal_boost := 58.0
@export var perfect_boost := 104.0
@export var perfect_streak_multiplier := 6.0
@export_range(0.2, 0.35, 0.01) var perfect_trajectory_reorientation := 0.28
@export_category("Graze")
@export var graze_distance := 28.0
@export var graze_score := 75
@export var graze_cooldown := 0.7
@export_category("Progression")
@export var speed_growth := 1.5

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
var last_graze_time := -10.0
var elapsed := 0.0
var last_pad_quality := "—"
var debug_enabled := false
var death_disabled := false
var slow_enabled := false
var event_tween: Tween
var camera_punch := Vector2.ZERO
var crash_freeze := 0.0

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
	max_speed_reached = hero.velocity.length()
	last_graze_time = -10.0
	elapsed = 0.0
	last_pad_quality = "—"
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
			var look_ahead := corridor.sample(hero.position + sample.direction * 180.0)
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
		corridor.queue_redraw()
	if event.is_action_pressed("slow_motion"):
		slow_enabled = not slow_enabled
		Engine.time_scale = 0.5 if slow_enabled else 1.0
	if event.is_action_pressed("disable_death"):
		death_disabled = not death_disabled
	if event.is_action_pressed("force_low_speed") and running:
		hero.velocity = hero.velocity.normalized() * hero.min_speed
	if event.is_action_pressed("force_high_speed") and running:
		hero.velocity = hero.velocity.normalized() * hero.max_speed

func _physics_process(delta: float) -> void:
	if crash_freeze > 0.0:
		crash_freeze -= delta
		return
	if not running:
		hero.step_flight(delta, Vector2.DOWN)
		camera.position = camera.position.lerp(hero.position + Vector2(0, -100), delta * 2.0)
		return

	elapsed += delta
	var sample := corridor.sample(hero.position)
	var look_ahead := corridor.sample(hero.position + sample.direction * 220.0)
	hero.step_flight(delta, look_ahead.direction)
	corridor.ensure_ahead(hero.position.y, float(distance_score))

	distance_score = maxi(distance_score, int(maxf(0.0, (160.0 - hero.position.y) / 45.0)))
	max_speed_reached = maxf(max_speed_reached, hero.velocity.length())
	_update_collision(sample)
	_update_pads()
	_update_camera(delta, look_ahead)
	_update_ui(sample, look_ahead)

func _update_collision(sample: Dictionary) -> void:
	var wall_clearance: float = sample.width * 0.5 - absf(sample.signed_distance) - hero.radius
	if wall_clearance <= 0.0:
		if death_disabled:
			hero.position = sample.center + sample.normal * signf(sample.signed_distance) * (sample.width * 0.5 - hero.radius - 3.0)
			hero.velocity = hero.velocity.bounce(sample.normal) * 0.65
			_show_event("SAVED (NO DEATH)", Color("ff9eb8"), 0.35)
		else:
			_crash(sample.normal * signf(sample.signed_distance))
	elif wall_clearance <= graze_distance and elapsed - last_graze_time >= graze_cooldown:
		last_graze_time = elapsed
		grazes += 1
		graze_chain += 1
		bonus_score += graze_score * graze_chain
		_show_event("GRAZE x%d" % graze_chain, Color("ff81af"), 0.45)
		camera_punch += sample.normal * -signf(sample.signed_distance) * 6.0
	elif wall_clearance > graze_distance * 2.2:
		graze_chain = 0

func _update_pads() -> void:
	for pad in pads:
		if not is_instance_valid(pad) or pad.consumed:
			continue
		var quality := pad.test_hit(hero.position, hero.radius)
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
				var boost_value := perfect_boost + perfect_streak_multiplier * perfect_streak
				hero.boost(boost_value, pad.ideal_direction, perfect_trajectory_reorientation)
				_show_event("PERFECT x%d" % perfect_streak, Color("ffe86a"), 0.62)
				_flash(Color(0.25, 0.9, 1.0, 0.2))
				camera_punch += -hero.velocity.normalized() * minf(12.0, 5.0 + perfect_streak)

func _update_camera(delta: float, look_ahead: Dictionary) -> void:
	var speed_factor := inverse_lerp(hero.min_speed, hero.max_speed, hero.velocity.length())
	var target: Vector2 = hero.position + Vector2(look_ahead.direction) * lerpf(285.0, 390.0, speed_factor)
	camera.position = camera.position.lerp(target, 1.0 - exp(-delta * 5.5))
	camera_punch = camera_punch.lerp(Vector2.ZERO, 1.0 - exp(-delta * 13.0))
	camera.offset = camera_punch
	camera.zoom = Vector2.ONE * lerpf(1.0, 0.88, speed_factor)

func _update_ui(sample: Dictionary, desired: Dictionary) -> void:
	score_label.text = str(distance_score + bonus_score / 100)
	if debug_enabled:
		debug_label.text = "F3 DEBUG\nvelocity  %7.1f, %7.1f\nspeed     %7.1f\nangle     %7.1f°\ndesired   %7.1f°\ncorrect   %7.2f, %7.2f\nstreak    %d\npad       %s\nfps       %d\n\nR restart | 1 half speed: %s\n2 no death: %s | 3 low | 4 high" % [hero.velocity.x, hero.velocity.y, hero.velocity.length(), sample.angle, desired.angle, hero.correction_direction.x, hero.correction_direction.y, perfect_streak, last_pad_quality, Engine.get_frames_per_second(), str(slow_enabled), str(death_disabled)]

func _spawn_pad(world_position: Vector2, direction: Vector2, difficulty: float, risky: bool) -> void:
	var pad: BoostPad = pad_scene.instantiate()
	var shrinking_perfect := maxf(12.0, perfect_radius - difficulty * 0.002)
	pad.setup(world_position, direction, pad_radius, shrinking_perfect, risky)
	$Pads.add_child(pad)
	pads.append(pad)

func _crash(wall_normal: Vector2) -> void:
	running = false
	crash_freeze = 0.065
	hero.crash()
	camera_punch = wall_normal * 24.0
	_flash(Color(1.0, 0.2, 0.35, 0.34))
	var total := distance_score + bonus_score / 100
	best_score = maxi(best_score, total)
	save_best(best_score)
	crash_score.text = "SCORE  %d\nBEST   %d\n\n%d pads  ·  %d perfect  ·  %d grazes\nmax speed  %d" % [total, best_score, pads_hit, perfect_hits, grazes, int(max_speed_reached)]
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
