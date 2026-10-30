extends Node2D

var _starting := false


func _physics_process(_delta: float) -> void:
	if not _starting and Input.is_action_pressed("ui_accept"):
		_starting = true
		Sfx.play("start")
		get_tree().change_scene_to_file("res://scenes/rooms/level0.tscn")
