extends Node

# Modo debug: arranca directo en DEBUG_START_SCENE salteando título e intros.
const DEBUG: bool = false
const DEBUG_START_SCENE := "res://scenes/rooms/level0.tscn"

# Cantidad máxima de bloques
var max_blocks: int = 4

# Habilidades del player: { &"id": activa }
var abilities: Dictionary = {
	&"blocks": true,
	&"hydro": false,
	&"eat": false,
	&"reach": false,
	&"teleport": false,
	&"zahori": false,
}

# true entre la muerte del player y la recarga de la room: el player nuevo
# arranca con unos instantes de invulnerabilidad (player.respawn_grace).
var respawn_grace_pending: bool = false

# Altares cuyo puzzle ya se resolvió
var solved_altars: Dictionary = {}

# Fragmentos de la tableta de piedra (coleccionable opcional). Ver scenes/tablet_piece.gd.
# Un fragmento recién agarrado queda pendiente hasta que el player sale de la room
# por una puerta; si muere antes, se pierde y vuelve a aparecer (así no sirve
# suicidarse para volver a la puerta con el fragmento en la mano).
# { índice (0..TABLET_PIECE_COUNT-1): true }
const TABLET_PIECE_COUNT := 4
var tablet_pieces: Dictionary = {}          # confirmados
var pending_tablet_pieces: Dictionary = {}  # agarrados en la room actual

# Final elegido al tocar el corazón (&"transcend", &"destroy" o &"awaken"). No se guarda.
var ending: StringName = &""

# true si el player llegó a la room actual atravesando una puerta.
var came_from_door: bool = false
# Escena (res://...) de la que venía el player al cruzar la última puerta.
var previous_scene: String = ""
# Por cada escena, la puerta por la que se salió la última vez: { "res://...tscn": NodePath }
var last_door: Dictionary = {}

# Se emite cada vez que una habilidad se prende o se apaga.
signal ability_changed(id: StringName, enabled: bool)

const WATER_EVAPORATION := preload("res://scenes/water_evaporation.gd")

# false cuando el agua de la room está evaporada (hydro). Se pone en false recién
# cuando la evaporación borra los tiles, no al activar hydro: los botes flotan
# mientras el agua se vea.
var water_active: bool = true

# Meta que guarda, en cada TileMapLayer, las celdas de agua ocultas por hydro.
const HIDDEN_WATER_META := &"hidden_water_cells"

# --- Partida guardada -------------------------------------------------------------
# Se guarda al usar una terminal (scenes/altar.gd) en user://game.save, texto plano
# (formato ConfigFile): habilidades, altares resueltos, fragmentos de la tableta
# confirmados y la room + posición del altar, donde reaparece el player al cargar.
const SAVE_PATH := "user://game.save"
const SAVE_VERSION := 1

# Al cargar: el player aparece acá (coords de la room) en vez de en la posición inicial.
var has_load_spawn := false
var load_spawn := Vector2.ZERO

# Respawn en el último altar usado de la room: al morir, la room se recarga pero el
# player reaparece en el altar en vez de en la puerta por la que entró (así puede
# volver a prender una habilidad que apagó). Se borra al salir por una puerta.
var altar_respawn_scene := ""
var altar_respawn_pos := Vector2.ZERO

var _default_abilities: Dictionary

func _ready() -> void:
	_default_abilities = abilities.duplicate()
	ability_changed.connect(func(id, _enabled): if id == &"hydro": update_water_tiles())
	get_tree().scene_changed.connect(update_water_tiles)
	# Por si la escena inicial ya tiene agua
	update_water_tiles.call_deferred()

func has_ability(id: StringName) -> bool:
	return abilities.get(id, false)

func set_ability(id: StringName, enabled: bool) -> void:
	abilities[id] = enabled
	ability_changed.emit(id, enabled)

## true si el fragmento está confirmado o agarrado en esta room (no aparece en el mundo).
func has_tablet_piece(index: int) -> bool:
	return tablet_pieces.has(index) or pending_tablet_pieces.has(index)

## Agarrado: queda pendiente hasta salir de la room (confirm_tablet_pieces).
func add_tablet_piece(index: int) -> void:
	pending_tablet_pieces[index] = true

## Fragmentos que tiene el player, contando los pendientes.
func tablet_piece_count() -> int:
	return tablet_pieces.size() + pending_tablet_pieces.size()

## Al salir de la room por una puerta: los pendientes pasan a ser definitivos.
func confirm_tablet_pieces() -> void:
	tablet_pieces.merge(pending_tablet_pieces)
	pending_tablet_pieces.clear()

## Al morir (o salir al título): los pendientes se pierden y vuelven a su lugar.
func discard_pending_tablet_pieces() -> void:
	pending_tablet_pieces.clear()

func is_altar_solved(number: int) -> bool:
	return solved_altars.has(number)


# Marca el altar como resuelto
func solve_altar(number: int, ability_id: StringName) -> void:
	solved_altars[number] = true
	if not abilities.has(ability_id):
		push_warning("Altar %d: ability_id '%s' no existe en Global.abilities" % [number, ability_id])
		return
	set_ability(ability_id, true)

## Guarda la partida: el player va a reaparecer en `position` (coords de la room) de
## la escena `room`. Los fragmentos pendientes (sin salir de la room) no se guardan.
func save_game(room: String, position: Vector2) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "version", SAVE_VERSION)
	cfg.set_value("game", "room", room)
	cfg.set_value("game", "position", position)
	for id in abilities:
		cfg.set_value("abilities", String(id), abilities[id])
	cfg.set_value("progress", "solved_altars", solved_altars.keys())
	cfg.set_value("progress", "tablet_pieces", tablet_pieces.keys())
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("No se pudo guardar la partida en %s (error %d)" % [SAVE_PATH, err])

## Marca el altar como punto de reaparición de la room actual (lo llama el altar al usarlo).
func set_altar_respawn(position: Vector2) -> void:
	altar_respawn_scene = get_tree().current_scene.scene_file_path
	altar_respawn_pos = position

## Al salir de la room por una puerta: vuelve a reaparecer en la puerta.
func clear_altar_respawn() -> void:
	altar_respawn_scene = ""

## Posición del altar donde reaparecer en la room actual, o null si no hay.
func altar_respawn_for_current() -> Variant:
	var scene := get_tree().current_scene
	if scene and altar_respawn_scene == scene.scene_file_path:
		return altar_respawn_pos
	return null

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## Carga la partida guardada en el estado global y devuelve la escena de la room
## a la que hay que ir ("" si no hay save o está roto). No cambia de escena.
func load_game() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return ""
	var room: String = cfg.get_value("game", "room", "")
	if room.is_empty() or not ResourceLoader.exists(room):
		push_warning("Partida guardada con una room inválida: '%s'" % room)
		return ""
	reset_game()
	for id in abilities:
		abilities[id] = bool(cfg.get_value("abilities", String(id), abilities[id]))
	for n in cfg.get_value("progress", "solved_altars", []):
		solved_altars[int(n)] = true
	for i in cfg.get_value("progress", "tablet_pieces", []):
		tablet_pieces[int(i)] = true
	load_spawn = cfg.get_value("game", "position", Vector2.ZERO)
	has_load_spawn = true
	# Si muere antes de salir de la room, reaparece en el altar donde guardó
	altar_respawn_scene = room
	altar_respawn_pos = load_spawn
	return room

## Deja el estado como al empezar una partida nueva (no toca el archivo de save).
func reset_game() -> void:
	abilities = _default_abilities.duplicate()
	solved_altars.clear()
	tablet_pieces.clear()
	pending_tablet_pieces.clear()
	ending = &""
	respawn_grace_pending = false
	came_from_door = false
	previous_scene = ""
	last_door.clear()
	has_load_spawn = false
	altar_respawn_scene = ""

#Activar o desactivar agua
func update_water_tiles() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var hide := has_ability(&"hydro")
	# Sin hydro el agua está; con hydro, si no hay evaporación en curso, ya no.
	water_active = not hide
	for layer in scene.find_children("*", "TileMapLayer", true, false):
		if hide:
			_hide_water_cells(layer)
		else:
			_restore_water_cells(layer)

func _hide_water_cells(layer: TileMapLayer) -> void:
	if layer.has_meta(HIDDEN_WATER_META) or layer.tile_set == null:
		return
	var water_sources := []
	for i in layer.tile_set.get_source_count():
		var id := layer.tile_set.get_source_id(i)
		var src := layer.tile_set.get_source(id) as TileSetAtlasSource
		if src and src.texture and src.texture.resource_path.get_file().begins_with("water"):
			water_sources.append(id)
	if water_sources.is_empty():
		return
	var cells := []
	for coords in layer.get_used_cells():
		var source := layer.get_cell_source_id(coords)
		if source in water_sources:
			cells.append([coords, source, layer.get_cell_atlas_coords(coords), layer.get_cell_alternative_tile(coords)])
	if cells.is_empty():
		return
	layer.set_meta(HIDDEN_WATER_META, cells)
	# Los tiles no se borran acá: el efecto muestra el agua un momento y la
	# evapora (borra las celdas al terminar la espera).
	water_active = true # hasta que el efecto borre los tiles
	var fx := WATER_EVAPORATION.new()
	fx.setup(layer, cells)
	layer.add_child(fx)

func _restore_water_cells(layer: TileMapLayer) -> void:
	if not layer.has_meta(HIDDEN_WATER_META):
		return
	for c in layer.get_meta(HIDDEN_WATER_META):
		layer.set_cell(c[0], c[1], c[2], c[3])
	layer.remove_meta(HIDDEN_WATER_META)

# Llamado por la puerta justo antes de cambiar de escena
func register_door_exit(door: Node) -> void:
	var scene := door.get_tree().current_scene
	came_from_door = true
	previous_scene = scene.scene_file_path
	last_door[previous_scene] = scene.get_path_to(door)

# Devuelve la puerta de la room actual donde debe aparecer el player
func find_spawn_door(tree: SceneTree) -> Node:
	if not came_from_door:
		return null
	var scene := tree.current_scene
	var doors := tree.get_nodes_in_group("doors")

	var saved: NodePath = last_door.get(scene.scene_file_path, NodePath())
	var saved_door: Node = null
	if not saved.is_empty():
		saved_door = scene.get_node_or_null(saved)
	var candidates := doors.filter(func(d): return to_path(d.target_scene) == previous_scene)
	if saved_door and saved_door in candidates:
		return saved_door
	if not candidates.is_empty():
		return candidates[0]
	return saved_door

static func to_path(scene: String) -> String:
	if scene.begins_with("uid://"):
		var id := ResourceUID.text_to_id(scene)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return scene
