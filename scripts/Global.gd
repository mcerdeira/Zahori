extends Node

## Cantidad máxima de bloques que el player puede generar con la habilidad.
var max_blocks: int = 4

## true si el player llegó a la room actual atravesando una puerta.
var came_from_door: bool = false
## Escena (res://...) de la que venía el player al cruzar la última puerta.
var previous_scene: String = ""
## Por cada escena, la puerta por la que se salió la última vez: { "res://...tscn": NodePath }
var last_door: Dictionary = {}


## Llamado por la puerta justo antes de cambiar de escena.
func register_door_exit(door: Node) -> void:
	var scene := door.get_tree().current_scene
	came_from_door = true
	previous_scene = scene.scene_file_path
	last_door[previous_scene] = scene.get_path_to(door)


## Devuelve la puerta de la room actual donde debe aparecer el player, o null
## si no viene de una puerta (usa entonces su posición de la escena).
func find_spawn_door(tree: SceneTree) -> Node:
	if not came_from_door:
		return null
	var scene := tree.current_scene
	var doors := tree.get_nodes_in_group("doors")

	# 1) Si ya salimos de esta room por una puerta que lleva a donde veníamos, volvemos a esa
	var saved: NodePath = last_door.get(scene.scene_file_path, NodePath())
	var saved_door: Node = null
	if not saved.is_empty():
		saved_door = scene.get_node_or_null(saved)
	var candidates := doors.filter(func(d): return to_path(d.target_scene) == previous_scene)
	if saved_door and saved_door in candidates:
		return saved_door
	# 2) Si no, la primera puerta que lleva a la room de la que venimos
	if not candidates.is_empty():
		return candidates[0]
	# 3) Si ninguna lleva de vuelta, la última puerta usada en esta room
	return saved_door


## Convierte "uid://..." a "res://..." para poder comparar rutas de escenas.
static func to_path(scene: String) -> String:
	if scene.begins_with("uid://"):
		var id := ResourceUID.text_to_id(scene)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return scene
