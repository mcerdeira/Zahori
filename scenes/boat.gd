extends CharacterBody2D

@export var speed: float = 80.0
@export var max_fall_speed: float = 240.0
@export var waterline: float = 5.0
@export var offscreen_time: float = 1.2
@export var bob_amplitude: float = 1.0
@export var bob_period: float = 1.8
@export var bob_fade: float = 4.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _dir := 0
var _vy := 0.0
var _falling := false
var _offscreen := 0.0
var _notifier: VisibleOnScreenNotifier2D
var _bob_t := 0.0
var _bob_weight := 0.0
var _floating := false

func _enter_tree() -> void:
	add_to_group("boat")

func place_under(feet: Vector2) -> void:
	var shape := $collider.shape as RectangleShape2D
	var top: float = $collider.position.y - shape.size.y / 2.0
	global_position = Vector2(feet.x, feet.y - top)
	_dir = 0
	_vy = 0.0

func place_at(pos: Vector2) -> void:
	global_position = pos
	_dir = 0
	_vy = 0.0

func _ready() -> void:
	_notifier = VisibleOnScreenNotifier2D.new()
	_notifier.rect = Rect2(-16, -8, 32, 16)
	add_child(_notifier)
	_bob_t = randf() * bob_period

func is_moving() -> bool:
	return _dir != 0

func can_move(dir: int) -> bool:
	return not _test(Vector2(dir, 0), null)

func launch(dir: int) -> bool:
	if _dir != 0 or dir == 0 or not can_move(dir):
		return false
	_dir = dir
	Sfx.play("step", 0.6)
	return true

func _physics_process(delta: float) -> void:
	var surface := _water_surface()
	_falling = false
	_floating = false
	if not is_nan(surface):
		var target := surface - waterline
		if global_position.y < target:
			_vy = minf(_vy + gravity * delta, max_fall_speed)
			global_position.y = minf(global_position.y + _vy * delta, target)
			_falling = global_position.y < target
		if not _falling:
			_vy = 0.0
			_floating = true
	else:
		_vy = minf(_vy + gravity * delta, max_fall_speed)
		if _move(Vector2(0, _vy * delta)):
			_vy = 0.0
		else:
			_falling = true

	if _dir != 0 and _move(Vector2(_dir * speed * delta, 0)):
		_dir = 0

	if _falling and not _notifier.is_on_screen():
		_offscreen += delta
		if _offscreen >= offscreen_time:
			queue_free()
	else:
		_offscreen = 0.0

func _process(delta: float) -> void:
	_update_bob(delta)

func _update_bob(delta: float) -> void:
	var active := _floating and _dir == 0 and not _has_rider()
	_bob_weight = move_toward(_bob_weight, 1.0 if active else 0.0, bob_fade * delta)
	_bob_t = fmod(_bob_t + delta, bob_period)
	var y := sin(_bob_t / bob_period * TAU) * bob_amplitude * _bob_weight
	$sprite.position.y = roundf(y)

func _has_rider() -> bool:
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_method("floor_boat") and p.floor_boat() == self:
			return true
	return false

func _water_surface() -> float:
	if not Global.water_active:
		return NAN
	var best := NAN
	for w in get_tree().get_nodes_in_group("water"):
		var r: Rect2 = w.get_rect()
		if global_position.x < r.position.x or global_position.x > r.end.x:
			continue
		if global_position.y > r.position.y - waterline + 1.0:
			continue
		if is_nan(best) or r.position.y < best:
			best = r.position.y
	return best

func _move(motion: Vector2) -> bool:
	var result := PhysicsTestMotionResult2D.new()
	var hit := _test(motion, result)
	global_position += result.get_travel()
	return hit

func _test(motion: Vector2, result: PhysicsTestMotionResult2D) -> bool:
	var params := PhysicsTestMotionParameters2D.new()
	params.from = global_transform
	params.motion = motion
	var exclude: Array[RID] = []
	for p in get_tree().get_nodes_in_group("player"):
		exclude.append(p.get_rid())
	params.exclude_bodies = exclude
	return PhysicsServer2D.body_test_motion(get_rid(), params, result)
