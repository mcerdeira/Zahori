extends "res://scripts/monologue.gd"

## Monólogo dentro de una room (p. ej. al encontrar a la hermana): pausa el juego,
## oscurece la pantalla con un fundido, corre las líneas como en la intro y al
## terminar vuelve a mostrar la room, despausa, emite finished y se borra.

@export var dim_alpha: float = 0.88 # opacidad del fondo negro (0..1)
@export var dim_time: float = 0.8   # segundos del fundido de entrada y de salida

@onready var _bg: ColorRect = $bg


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	autostart = false
	get_tree().paused = true
	super()
	_bg.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_bg, "modulate:a", dim_alpha, dim_time)
	tw.tween_callback(start)


func _finish() -> void:
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 0.0, fade_time)
	tw.tween_property(_bg, "modulate:a", 0.0, dim_time)
	await tw.finished
	get_tree().paused = false
	finished.emit()
	queue_free()
