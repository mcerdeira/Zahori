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

enum State { NORMAL, BUILDING, VANISHING, DOOR }

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var state := State.NORMAL
var blocks: Array[Node] = []
var _timer := 0.0
var _door_x := 0.0
var _respawn_position := Vector2.ZERO

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
	var fx := EXPLOSION_SCENE.instantiate()
	fx.global_position = global_position
	get_parent().add_child(fx)

	for block in blocks:
		if is_instance_valid(block):
			block.queue_free()
	blocks.clear()
	state = State.NORMAL
	velocity = Vector2.ZERO
	global_position = _respawn_position


func _feet_offset() -> float:
	var shape := collider.shape as RectangleShape2D
	return collider.position.y + shape.size.y / 2.0


## Pinta al player 100% negro (lo usa la puerta al superponerse).
func set_silhouette(enabled: bool) -> void:
	(sprite.material as ShaderMaterial).set_shader_parameter("amount", 1.0 if enabled else 0.0)


## La puerta lo llama al apretar UP. Devuelve false si ahora no se puede entrar.
func enter_door(door_x: float) -> bool:
	if state == State.BUILDING or state == State.DOOR or not is_on_floor():
		return false
	state = State.DOOR
	_door_x = door_x
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

	move_and_slide()
	_update_animation(direction)


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
			if blocks.is_empty():
				state = State.NORMAL
				return
			_timer -= delta
			if _timer <= 0.0:
				var block: Node = blocks.pop_back() if vanish_last_first else blocks.pop_front()
				if is_instance_valid(block):
					block.vanish()
				_timer = vanish_interval


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
