extends CharacterBody2D

const BLOCK_SCENE := preload("res://scenes/block.tscn")
const SILHOUETTE_SHADER := preload("res://scenes/silhouette.gdshader")
const EXPLOSION_SCENE := preload("res://scenes/explosion.tscn")
const TILE := 16.0

@export var speed: float = 120.0           # px/s horizontal
@export var acceleration: float = 900.0   # px/s² al arrancar
@export var friction: float = 800.0       # px/s² al frenar
@export var max_fall_speed: float = 240.0 # velocidad terminal de caída
@export var build_interval: float = 0.2   # segundos entre cada bloque generado
@export var vanish_interval: float = 0.35 # segundos entre cada bloque que desaparece
@export var vanish_last_first: bool = true # true: desaparece primero el de arriba (el último puesto)
@export var step_interval: float = 0.28   # segundos entre pasos al caminar
@export var land_min_speed: float = 80.0  # px/s de caída mínima para que suene el aterrizaje

enum State { NORMAL, BUILDING, VANISHING, DOOR }

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var state := State.NORMAL
var blocks: Array[Node] = []
var _vanishing: Array[Node] = [] # bloques en pleno fade (todavía sólidos)
var _timer := 0.0
var _door_x := 0.0
var _respawn_position := Vector2.ZERO
var _doors_touching := 0 # puertas superpuestas ahora (para la silueta)
var _step_timer := 0.0

@onready var sprite: AnimatedSprite2D = $sprite
@onready var collider: CollisionShape2D = $collider


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE_SHADER
	sprite.material = mat

	# Si venimos de una puerta, aparecer parado en la puerta correspondiente
	var door := Global.find_spawn_door(get_tree())
	if door:
		global_position = door.spawn_position(_feet_offset())
	_respawn_position = global_position


## Muerte instantánea: explota y reaparece en la puerta por la que entró
## (o en su posición inicial si todavía no cruzó ninguna puerta).
func die() -> void:
	if state == State.DOOR:
		return # ya se está yendo por una puerta
	Sfx.play("die")
	var fx := EXPLOSION_SCENE.instantiate()
	fx.global_position = global_position
	get_parent().add_child(fx)

	for block in blocks:
		if is_instance_valid(block):
			block.queue_free()
	blocks.clear()
	_vanishing.clear()
	state = State.NORMAL
	velocity = Vector2.ZERO
	global_position = _respawn_position


func _feet_offset() -> float:
	var shape := collider.shape as RectangleShape2D
	return collider.position.y + shape.size.y / 2.0


## Pinta al player 100% negro (lo usa la puerta al superponerse).
## Lleva la cuenta de puertas tocando al player: así, si sale de una mientras
## está en otra (p. ej. al aparecer en una puerta distinta a la inicial), la
## silueta no se apaga.
func set_silhouette(enabled: bool) -> void:
	_doors_touching = maxi(_doors_touching + (1 if enabled else -1), 0)
	(sprite.material as ShaderMaterial).set_shader_parameter("amount", 1.0 if _doors_touching > 0 else 0.0)


## La puerta lo llama al apretar UP. Devuelve false si ahora no se puede entrar.
func enter_door(door_x: float) -> bool:
	if state == State.BUILDING or state == State.DOOR or not is_on_floor():
		return false
	state = State.DOOR
	_door_x = door_x
	Sfx.play("door")
	return true


func _physics_process(delta: float) -> void:
	# Gravedad
	if not is_on_floor():
		velocity.y = min(velocity.y + gravity * delta, max_fall_speed)

	_update_ability(delta)

	# Movimiento horizontal (bloqueado mientras se construye o se entra por una puerta)
	var direction := 0.0
	if state != State.BUILDING and state != State.DOOR:
		direction = Input.get_axis("LEFT", "RIGHT")
	if state == State.DOOR:
		_walk_to_door_center(delta)
	elif direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * delta)
		sprite.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	var fall_speed := velocity.y
	var was_on_floor := is_on_floor()
	move_and_slide()
	if is_on_floor() and not was_on_floor and fall_speed >= land_min_speed:
		Sfx.play("land", randf_range(0.9, 1.1))
	_update_steps(delta)
	_update_animation(direction)


## Suena un paso cada step_interval mientras camina por el piso.
func _update_steps(delta: float) -> void:
	if not is_on_floor() or absf(velocity.x) < speed * 0.3:
		_step_timer = 0.0 # el primer paso suena apenas arranca
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		Sfx.play("step", randf_range(0.85, 1.15))
		_step_timer = step_interval


## Camina hasta el centro de la puerta (sin pasarse) y ahí se queda.
func _walk_to_door_center(delta: float) -> void:
	var dx := _door_x - global_position.x
	if absf(dx) < 0.5:
		velocity.x = 0.0
		return
	velocity.x = signf(dx) * minf(speed * 0.5, absf(dx) / delta)
	sprite.flip_h = dx < 0.0


func _update_ability(delta: float) -> void:
	match state:
		State.NORMAL:
			if Input.is_action_just_pressed("action") and is_on_floor():
				state = State.BUILDING
				velocity.x = 0.0
				_timer = 0.0 # el primer bloque sale al instante
		State.BUILDING:
			if not Input.is_action_pressed("action"):
				state = State.VANISHING
				_timer = 0.0
			else:
				_timer -= delta
				if _timer <= 0.0 and blocks.size() < Global.max_blocks:
					_spawn_block()
					_timer = build_interval
		State.VANISHING:
			# Esperar también a que terminen los fades: mientras un bloque se desvanece
			# sigue siendo sólido, y si volviéramos a NORMAL se podría construir encima.
			_vanishing = _vanishing.filter(func(b): return is_instance_valid(b))
			# Si se bajó de sus bloques y pisa otro piso, se resetean todos al instante
			if _on_foreign_floor():
				_reset_blocks()
				return
			if blocks.is_empty():
				if _vanishing.is_empty():
					state = State.NORMAL
				return
			_timer -= delta
			if _timer <= 0.0:
				var block: Node = blocks.pop_back() if vanish_last_first else blocks.pop_front()
				if is_instance_valid(block):
					block.vanish()
					_vanishing.append(block)
					Sfx.play("vanish", 1.0 + 0.12 * blocks.size())
				_timer = vanish_interval


## true si está apoyado en un piso que no es uno de sus propios bloques
## (usa las colisiones del último move_and_slide).
func _on_foreign_floor() -> bool:
	if not is_on_floor():
		return false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().dot(up_direction) < 0.7:
			continue # no es piso (pared o techo)
		var other := col.get_collider()
		if other not in blocks and other not in _vanishing:
			return true
	return false


## Desvanece todos los bloques a la vez y deja la habilidad lista para usar.
## Los que ya estaban en pleno fade se terminan solos.
func _reset_blocks() -> void:
	if not blocks.is_empty():
		Sfx.play("reset")
	for block in blocks:
		if is_instance_valid(block):
			block.vanish()
	blocks.clear()
	_vanishing.clear()
	state = State.NORMAL


## Eleva al player una celda y pone un bloque donde estaban sus pies.
func _spawn_block() -> void:
	# Si hay techo arriba no hay lugar para subir
	if test_move(global_transform, Vector2(0, -TILE)):
		return

	var feet_offset := _feet_offset()
	var feet_y := snappedf(global_position.y + feet_offset, TILE)

	# Alinear a la grilla horizontalmente (en el primer bloque centra al player)
	var block_x := floorf(global_position.x / TILE) * TILE + TILE / 2.0
	var target_x := block_x - collider.position.x
	if not test_move(global_transform, Vector2(target_x - global_position.x, -TILE)):
		global_position.x = target_x

	global_position.y = feet_y - TILE - feet_offset
	velocity.y = 0.0

	var block := BLOCK_SCENE.instantiate()
	block.global_position = Vector2(block_x, feet_y - TILE / 2.0)
	get_parent().add_child(block)
	blocks.append(block)
	Sfx.play("block", 1.0 + 0.15 * (blocks.size() - 1))


func _update_animation(direction: float) -> void:
	if state == State.BUILDING:
		sprite.play("build")
	elif state == State.DOOR:
		sprite.play("walk")
	elif not is_on_floor():
		sprite.play("fall")
	elif direction != 0.0:
		sprite.play("walk")
	else:
		sprite.play("default")
