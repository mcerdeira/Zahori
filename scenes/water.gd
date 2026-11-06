extends Area2D

## Tocar el agua es muerte instantánea, salvo que el cuerpo la resista
## (el player con la habilidad hydro).
func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.has_method("resists_water") and body.resists_water():
		return
	if body.has_method("die"):
		body.die()
