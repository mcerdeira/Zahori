extends "res://scripts/monologue.gd"

@export var dim_alpha: float = 0.88
@export var dim_time: float = 0.8
@export var keep_dark_on_finish: bool = false

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
	if not keep_dark_on_finish:
		tw.tween_property(_bg, "modulate:a", 0.0, dim_time)
	await tw.finished
	get_tree().paused = false
	finished.emit()
	queue_free()
