extends Area2D
## Planta: un ser vivo con el que el player se puede intercambiar disparándole
## el proyectil de teleport. No es sólida (se la atraviesa caminando).
## Cualquier objeto con la propiedad `interchangeable` funciona igual
## (ver teleport_shot.gd); feet_offset() le dice al player dónde están sus pies.

## true: el proyectil de teleport intercambia al player con este objeto.
@export var interchangeable: bool = true


func _ready() -> void:
	$sprite.play(&"default")


## Distancia (px) del origen a la base, para apoyarla en el piso al intercambiar.
func feet_offset() -> float:
	return 8.0
