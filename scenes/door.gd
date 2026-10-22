extends Area2D

## Escena a la que lleva la puerta.
@export_file("*.tscn") var target_scene: String
## Segundos que el player queda bloqueado antes del cambio de escena.
@export var transition_time: float = 1.3

var _player: Node = null
var _entering := false


func _enter_tree() -> void:
	add_to_group("doors")


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	if _player and not _entering and Input.is_action_just_pressed("UP"):
		if _player.enter_door(global_position.x):
			_enter()


## Posición donde debe quedar el player para aparecer parado en esta puerta.
func spawn_position(feet_offset: float) -> Vector2:
	var shape := $collider.shape as RectangleShape2D
	var bottom: float = global_position.y + $collider.position.y + shape.size.y / 2.0
	return Vector2(global_position.x, bottom - feet_offset)


func _enter() -> void:
	_entering = true
	await get_tree().create_timer(transition_time).timeout
	if target_scene.is_empty():
		push_warning("Door '%s' no tiene target_scene configurada" % name)
		return
	Global.register_door_exit(self)
	get_tree().change_scene_to_file(target_scene)


func _on_body_entered(body: Node) -> void:
	if body.has_method("enter_door"):
		_player = body
		body.set_silhouette(true)


func _on_body_exited(body: Node) -> void:
	if body == _player:
		body.set_silhouette(false)
		_player = null
