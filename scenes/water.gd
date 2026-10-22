extends Area2D

## Tocar el agua es muerte instantánea.
func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.has_method("die"):
		body.die()
