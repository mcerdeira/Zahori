extends Node

## Menú de pausa (Q). Sólo se abre dentro del juego (rooms), no en las intros,
## y no si el juego ya está pausado (p. ej. con una terminal abierta).
## El menú cuelga de este autoload, así sobrevive si la escena cambia por debajo.

const MENU_SCENE := preload("res://scenes/pause_menu.tscn")
const ROOMS_DIR := "res://scenes/rooms/"

## Cuánto baja el volumen del bus Master mientras está en pausa (0.6 = 60%).
@export var volume_drop: float = 0.6

var _menu: Node = null
var _saved_master_db := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if _menu or not event.is_action_pressed("pause") or get_tree().paused:
		return
	var scene := get_tree().current_scene
	if scene == null or not scene.scene_file_path.begins_with(ROOMS_DIR):
		return
	get_viewport().set_input_as_handled()
	_open()


func _open() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	_saved_master_db = AudioServer.get_bus_volume_db(master)
	AudioServer.set_bus_volume_db(master,
			linear_to_db(db_to_linear(_saved_master_db) * (1.0 - volume_drop)))
	_menu = MENU_SCENE.instantiate()
	_menu.closed.connect(_on_closed)
	add_child(_menu)


func _on_closed() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Master"), _saved_master_db)
	_menu = null
