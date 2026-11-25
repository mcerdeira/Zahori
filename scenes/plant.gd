extends Area2D

@export var interchangeable: bool = true

func _ready() -> void:
	$sprite.play(&"default")

func feet_offset() -> float:
	return 8.0
