extends Node

const MENU_SCENE := preload("res://scenes/pause_menu.tscn")
const ROOMS_DIR := "res://scenes/rooms/"

@export var volume_drop: float = 0.6

var _menu: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if _menu or get_tree().paused:
		return
	if not event.is_action_pressed("pause") and not event.is_action_pressed("ui_cancel"):
		return
	var scene := get_tree().current_scene
	if scene == null or not scene.scene_file_path.begins_with(ROOMS_DIR):
		return
	get_viewport().set_input_as_handled()
	_open()

func _open() -> void:
	Settings.set_master_duck(1.0 - volume_drop)
	_menu = MENU_SCENE.instantiate()
	_menu.closed.connect(_on_closed)
	add_child(_menu)

func _on_closed() -> void:
	Settings.set_master_duck(1.0)
	_menu = null
