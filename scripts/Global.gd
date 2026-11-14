extends Node

# Cantidad máxima de bloques
var max_blocks: int = 4

# Habilidades del player: { &"id": activa }
var abilities: Dictionary = {
	&"blocks": true,
	&"hydro": true,
	&"eat": true,
	&"reach": true,
	&"zahori": true, # varita zahorí (la da la hermana): marca la puerta correcta del laberinto (DoorMaze)
}

# Altares cuyo puzzle ya se resolvió
var solved_altars: Dictionary = {}

# true si el player llegó a la room actual atravesando una puerta.
var came_from_door: bool = false
# Escena (res://...) de la que venía el player al cruzar la última puerta.
var previous_scene: String = ""
# Por cada escena, la puerta por la que se salió la última vez: { "res://...tscn": NodePath }
var last_door: Dictionary = {}

# Se emite cada vez que una habilidad se prende o se apaga.
signal ability_changed(id: StringName, enabled: bool)

# Meta que guarda, en cada TileMapLayer, las celdas de agua ocultas por hydro.
const HIDDEN_WATER_META := &"hidden_water_cells"

func _ready() -> void:
	ability_changed.connect(func(id, _enabled): if id == &"hydro": update_water_tiles())
	get_tree().scene_changed.connect(update_water_tiles)
	# Por si la escena inicial ya tiene agua
	update_water_tiles.call_deferred()

func has_ability(id: StringName) -> bool:
	return abilities.get(id, false)

func set_ability(id: StringName, enabled: bool) -> void:
	abilities[id] = enabled
	ability_changed.emit(id, enabled)

func is_altar_solved(number: int) -> bool:
	return solved_altars.has(number)


# Marca el altar como resuelto
func solve_altar(number: int, ability_id: StringName) -> void:
	solved_altars[number] = true
	if not abilities.has(ability_id):
		push_warning("Altar %d: ability_id '%s' no existe en Global.abilities" % [number, ability_id])
		return
	set_ability(ability_id, true)

#Activar o desactivar agua
func update_water_tiles() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var hide := has_ability(&"hydro")
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
	for c in cells:
		layer.erase_cell(c[0])
	layer.set_meta(HIDDEN_WATER_META, cells)

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
