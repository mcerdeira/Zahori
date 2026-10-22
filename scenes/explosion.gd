extends AnimatedSprite2D

## Efecto de un solo uso: se reproduce y se borra al terminar.
func _ready() -> void:
	animation_finished.connect(queue_free)
