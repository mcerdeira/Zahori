extends Area2D

@export_file("*.tscn") var target_scene: String
@export var transition_time: float = 1.1 # segundos de la animación de entrar
## Puerta instantánea (para salir por los bordes del nivel): cambia de escena
## apenas el player la toca, sin UP ni transición. En el juego es invisible.
@export var instant: bool = false

var _player: Node = null
var _entering := false
## Sólo para instant: false mientras el player esté encima desde el arranque
## (apareció en esta puerta al volver), para no rebotar de vuelta al instante.
var _armed := false

func _enter_tree() -> void:
	add_to_group("doors")

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if instant:
		$sprite.visible = false
		rearm()

## Sólo para instant: se desarma y se vuelve a armar si el player no está encima.
## Lo llama el player al reaparecer, por si reapareció en esta puerta.
func rearm() -> void:
	if not instant:
		return
	_armed = false
	# Esperar a que el player esté ubicado y la física haya detectado la superposición
	await get_tree().physics_frame
	await get_tree().physics_frame
	_armed = not get_overlapping_bodies().any(func(b): return b.has_method("enter_door"))

func _process(_delta: float) -> void:
	if _player and not _entering and Input.is_action_just_pressed("UP"):
		if _player.enter_door(global_position.x):
			_enter()

# Posición donde debe quedar el player para aparecer parado en esta puerta.
func spawn_position(feet_offset: float) -> Vector2:
	var shape := $collider.shape as RectangleShape2D
	var bottom: float = global_position.y + $collider.position.y + shape.size.y / 2.0
	return Vector2(global_position.x, bottom - feet_offset)

func _enter() -> void:
	_entering = true
	if not instant:
		await get_tree().create_timer(transition_time).timeout
	if target_scene.is_empty():
		push_warning("Door '%s' no tiene target_scene configurada" % name)
		return
	Global.register_door_exit(self)
	get_tree().change_scene_to_file(target_scene)

func _on_body_entered(body: Node) -> void:
	if instant:
		if _armed and not _entering and body.has_method("enter_door"):
			_enter.call_deferred()
		return
	if body.has_method("enter_door"):
		_player = body
		body.set_silhouette(true)

func _on_body_exited(body: Node) -> void:
	if instant:
		if body.has_method("enter_door"):
			_armed = true
		return
	if body == _player:
		body.set_silhouette(false)
		_player = null
