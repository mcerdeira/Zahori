extends CharacterBody2D
## Fantasma: va y viene en línea recta (horizontal o vertical) y da la vuelta
## apenas choca con algo: tiles, bloques verdes, el bote. Al player no lo
## esquiva: si lo toca (hurtbox) lo mata.
## Está en la capa de colisión 2 (mask 1): el player no choca con él ni puede
## pararse encima, pero el raycast del teleport sí lo encuentra, y con
## `interchangeable` el player intercambia lugar con él.

enum Axis { HORIZONTAL, VERTICAL }

## HORIZONTAL arranca hacia la derecha, VERTICAL hacia abajo (salvo start_reversed).
@export var direction: Axis = Axis.HORIZONTAL
@export var start_reversed: bool = false # true: arranca hacia la izquierda / arriba
@export var speed: float = 80.0 # px/s
## true: el proyectil de teleport intercambia al player con el fantasma.
@export var interchangeable: bool = true

var _sign := 1.0


func _ready() -> void:
	_sign = -1.0 if start_reversed else 1.0


func _physics_process(delta: float) -> void:
	var axis := Vector2.RIGHT if direction == Axis.HORIZONTAL else Vector2.DOWN
	var motion := axis * _sign * speed * delta
	var params := PhysicsTestMotionParameters2D.new()
	params.from = global_transform
	params.motion = motion
	# El player no lo frena: lo atraviesa y el hurtbox lo mata
	var exclude: Array[RID] = []
	for p in get_tree().get_nodes_in_group("player"):
		exclude.append(p.get_rid())
	params.exclude_bodies = exclude
	var result := PhysicsTestMotionResult2D.new()
	if PhysicsServer2D.body_test_motion(get_rid(), params, result):
		global_position += result.get_travel()
		_sign = -_sign # chocó: da la vuelta
	else:
		global_position += motion
	if direction == Axis.HORIZONTAL:
		$sprite.flip_h = _sign < 0.0
	_check_hurt()


## Mata al player si su forma se superpone de verdad con el hurtbox. Se chequea
## la geometría actual porque las áreas actualizan con un frame de atraso: tras
## un intercambio de teleport "veían" al player donde estaba el fantasma.
func _check_hurt() -> void:
	var hurt := _shape_rect($hurtbox/collider)
	for body in $hurtbox.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("die") \
				and hurt.intersects(_shape_rect(body.get_node("collider"))):
			body.die()


static func _shape_rect(cs: CollisionShape2D) -> Rect2:
	var size := (cs.shape as RectangleShape2D).size
	return cs.global_transform * Rect2(-size / 2.0, size)


## Distancia (px) del origen a la base del cuerpo, para el intercambio.
func feet_offset() -> float:
	var shape := $collider.shape as RectangleShape2D
	return $collider.position.y + shape.size.y / 2.0
