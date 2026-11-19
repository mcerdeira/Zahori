extends StaticBody2D

@export var vanish_time: float = 0.2

func _enter_tree() -> void:
	add_to_group("blocks") # la enredadera los busca para comérselos

func vanish() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, vanish_time)
	tween.tween_callback(queue_free)
