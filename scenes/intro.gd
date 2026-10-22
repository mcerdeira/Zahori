extends Node2D

func _physics_process(delta: float) -> void:
	if Input.is_action_pressed("ui_accept"):
		get_tree().change_scene_to_file("res://scenes/rooms/level0.tscn")
