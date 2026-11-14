extends Node

## Laberinto de puertas: level181 → 181a → 181b → ... → 181g.
##
## En cada room del laberinto, las puertas con `target_scene = "-1"` son puertas
## del laberinto: sólo una por room es la correcta y lleva a la room siguiente;
## cualquier otra devuelve al inicio (level181). Las puertas se identifican por
## el nombre del nodo (Door2, Door3, ...), que es el mismo en todas las rooms.
##
## Anti fuerza bruta: la combinación se sortea de a un paso (la primera vez que
## se necesita) y al errar se descarta entera. Sin la varita zahorí, llegar al
## final es acertar 7 veces seguidas entre ~12 puertas (1 en ~35 millones).
## Con la varita (habilidad `zahori`), la puerta correcta late y suena un "ping"
## que se acelera a medida que el player se acerca; sobre la cabeza del player
## aparece un ícono de señal (dowse_indicator.gd) que parpadea con el ping.

## Valor de `target_scene` que marca una puerta del laberinto.
const MAZE_TARGET := "-1"
## Rooms del laberinto, en orden. Entrar por la puerta correcta de una lleva a la siguiente.
const ROOMS: Array[String] = [
	"res://scenes/rooms/level181.tscn",
	"res://scenes/rooms/level181a.tscn",
	"res://scenes/rooms/level181b.tscn",
	"res://scenes/rooms/level181c.tscn",
	"res://scenes/rooms/level181d.tscn",
	"res://scenes/rooms/level181e.tscn",
	"res://scenes/rooms/level181f.tscn",
	"res://scenes/rooms/level181g.tscn",
]
## Adónde lleva la puerta correcta de la última room. Vacío: la última room no
## tiene puerta correcta (sus puertas del laberinto vuelven al inicio).
const FINAL_SCENE := ""
const INDICATOR_SCRIPT := preload("res://scenes/dowse_indicator.gd")

@export var dowse_range: float = 220.0       # px: más lejos que esto la varita no reacciona
@export var dowse_min_interval: float = 0.12 # segundos entre pings pegado a la puerta
@export var dowse_max_interval: float = 1.1  # segundos entre pings en el borde del rango
@export var dowse_glow: float = 0.9          # brillo extra máximo de la puerta correcta (0 = nada)
@export var indicator_on_time: float = 0.5   # fracción (0-1) de cada intervalo en que el ícono de señal queda prendido

## Puerta correcta (nombre del nodo) por paso: { índice de room: StringName }.
var _solution: Dictionary = {}
var _dowse_timer := 0.0
var _glowing: CanvasItem = null # sprite de la puerta que está latiendo


func is_maze_door(door: Node) -> bool:
	return door.target_scene == MAZE_TARGET


## Llamado por la puerta del laberinto al entrar: devuelve la escena destino
## y, si el player se equivocó, descarta la combinación.
func resolve(door: Node) -> String:
	var step := ROOMS.find(door.get_tree().current_scene.scene_file_path)
	if step == -1:
		push_warning("DoorMaze: la puerta '%s' apunta a -1 pero la room no está en ROOMS" % door.name)
		return ROOMS[0]
	var next_scene := FINAL_SCENE if step == ROOMS.size() - 1 else ROOMS[step + 1]
	if door.name == _correct_name(door.get_tree(), step) and not next_scene.is_empty():
		return next_scene
	_solution.clear()
	return ROOMS[0]


## Nombre de la puerta correcta del paso; la sortea si todavía no hay.
func _correct_name(tree: SceneTree, step: int) -> StringName:
	if not _solution.has(step):
		var names := tree.get_nodes_in_group("doors").filter(is_maze_door).map(func(d): return d.name)
		if names.is_empty():
			return &""
		_solution[step] = names.pick_random()
	return _solution[step]


# --- Varita zahorí ---------------------------------------------------------

func _process(delta: float) -> void:
	var door := _current_correct_door()
	var player := _find_player()
	if door == null or player == null or not Global.has_ability(&"zahori"):
		_set_glow(null, 0.0)
		_set_indicator(player, 0)
		return
	var dist: float = door.global_position.distance_to(player.global_position)
	var near := 1.0 - clampf(dist / dowse_range, 0.0, 1.0) # 0 lejos, 1 encima
	if near <= 0.0:
		_set_glow(null, 0.0)
		_set_indicator(player, 0)
		return
	var interval := lerpf(dowse_max_interval, dowse_min_interval, near)
	_dowse_timer -= delta
	if _dowse_timer <= 0.0:
		_dowse_timer = interval
		Sfx.play("dowse", lerpf(0.8, 1.4, near), lerpf(-14.0, -4.0, near))
	# El latido va sincronizado con el ping: arranca a full y se apaga hasta el próximo
	var pulse := clampf(_dowse_timer / interval, 0.0, 1.0)
	_set_glow(door.get_node_or_null("sprite"), dowse_glow * near * pulse)
	# Ícono de señal: 1 a 3 rayitas según la cercanía, prendido justo después de cada ping
	var lit := pulse > 1.0 - indicator_on_time
	_set_indicator(player, (1 + int(near * 2.999)) if lit else 0)


func _current_correct_door() -> Node:
	var tree := get_tree()
	var scene := tree.current_scene
	if scene == null:
		return null
	var step := ROOMS.find(scene.scene_file_path)
	if step == -1 or (step == ROOMS.size() - 1 and FINAL_SCENE.is_empty()):
		return null
	return scene.get_node_or_null(NodePath(String(_correct_name(tree, step))))


func _find_player() -> Node2D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for child in scene.get_children():
		if child.has_method("enter_door"):
			return child
	return null


## Muestra el ícono de señal sobre el player con esa cantidad de rayitas (0 = oculto).
func _set_indicator(player: Node2D, bars: int) -> void:
	if player == null:
		return
	var indicator := player.get_node_or_null(^"DowseIndicator")
	if indicator == null:
		if bars == 0:
			return
		indicator = INDICATOR_SCRIPT.new()
		indicator.name = "DowseIndicator"
		player.add_child(indicator)
	indicator.bars = bars


func _set_glow(sprite: CanvasItem, amount: float) -> void:
	if _glowing and _glowing != sprite and is_instance_valid(_glowing):
		_glowing.modulate = Color.WHITE
	_glowing = sprite
	if sprite:
		sprite.modulate = Color(1.0 + amount, 1.0 + amount, 1.0 + amount * 0.4)
