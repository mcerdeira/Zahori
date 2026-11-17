extends CharacterBody2D
## Canoa. Flota sobre los nodos Water (grupo "water") mientras el agua esté
## (Global.water_active); si no hay agua debajo cae hasta un tile, y si cae al
## vacío se borra al rato de salir de pantalla.
## El player, parado arriba y con el bote frenado, la lanza hacia un costado
## (player.gd llama a launch); avanza sola hasta chocar contra algo.
## Se mueve a mano (body_test_motion) excluyendo al player, así el player
## parado arriba no la frena. Al ser un cuerpo kinematic, el player parado
## encima hereda su velocidad como plataforma y viaja con ella.

@export var speed: float = 80.0 # px/s al avanzar
@export var max_fall_speed: float = 240.0 # px/s
@export var waterline: float = 5.0 # px desde el origen del bote hasta la línea de flotación
@export var offscreen_time: float = 1.2 # s fuera de pantalla cayendo antes de borrarse

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _dir := 0 # -1 / 1 mientras avanza, 0 frenado
var _vy := 0.0
var _falling := false
var _offscreen := 0.0
var _notifier: VisibleOnScreenNotifier2D


func _enter_tree() -> void:
	add_to_group("boat")


## Pone el bote justo debajo de unos pies (y global de la planta del player).
func place_under(feet: Vector2) -> void:
	var shape := $collider.shape as RectangleShape2D
	var top: float = $collider.position.y - shape.size.y / 2.0
	global_position = Vector2(feet.x, feet.y - top)
	_dir = 0
	_vy = 0.0


func _ready() -> void:
	_notifier = VisibleOnScreenNotifier2D.new()
	_notifier.rect = Rect2(-16, -8, 32, 16)
	add_child(_notifier)


func is_moving() -> bool:
	return _dir != 0


## true si hay lugar para avanzar en esa dirección.
func can_move(dir: int) -> bool:
	return not _test(Vector2(dir, 0), null)


## Arranca hacia dir (-1 / 1). Sólo si está frenado y hay lugar.
func launch(dir: int) -> bool:
	if _dir != 0 or dir == 0 or not can_move(dir):
		return false
	_dir = dir
	Sfx.play("step", 0.6)
	return true


func _physics_process(delta: float) -> void:
	var surface := _water_surface()
	_falling = false
	if not is_nan(surface):
		# Flotando (o cayendo hacia el agua): se clava en la línea de flotación
		var target := surface - waterline
		if global_position.y < target:
			_vy = minf(_vy + gravity * delta, max_fall_speed)
			global_position.y = minf(global_position.y + _vy * delta, target)
			_falling = global_position.y < target
		if not _falling:
			_vy = 0.0
	else:
		_vy = minf(_vy + gravity * delta, max_fall_speed)
		if _move(Vector2(0, _vy * delta)):
			_vy = 0.0
		else:
			_falling = true

	if _dir != 0 and _move(Vector2(_dir * speed * delta, 0)):
		_dir = 0 # chocó: queda frenado

	# Cayendo al vacío: se borra al rato de salir de pantalla
	if _falling and not _notifier.is_on_screen():
		_offscreen += delta
		if _offscreen >= offscreen_time:
			queue_free()
	else:
		_offscreen = 0.0


## Superficie (y global) del agua sobre la que flota, o NAN si no hay.
func _water_surface() -> float:
	if not Global.water_active:
		return NAN
	var best := NAN
	for w in get_tree().get_nodes_in_group("water"):
		var r: Rect2 = w.get_rect()
		if global_position.x < r.position.x or global_position.x > r.end.x:
			continue
		# Sólo si el bote está por encima de la superficie (o apenas debajo)
		if global_position.y > r.position.y - waterline + 1.0:
			continue
		if is_nan(best) or r.position.y < best:
			best = r.position.y
	return best


## Mueve el bote hasta donde pueda. Devuelve true si chocó.
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
