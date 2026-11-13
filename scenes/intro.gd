extends Node2D

var _starting := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _physics_process(_delta: float) -> void:
	if not _starting and Input.is_action_pressed("ui_accept"):
		_starting = true
		get_tree().change_scene_to_file("res://scenes/Intro2.tscn")
