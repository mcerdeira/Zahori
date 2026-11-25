extends Node

const MAZE_TARGET := "-1"
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
const FINAL_SCENE := ""
const INDICATOR_SCRIPT := preload("res://scenes/dowse_indicator.gd")

@export var dowse_range: float = 220.0
@export var dowse_min_interval: float = 0.12
@export var dowse_max_interval: float = 1.1
@export var dowse_glow: float = 0.9
@export var indicator_on_time: float = 0.5

var _solution: Dictionary = {}
var _dowse_timer := 0.0
var _glowing: CanvasItem = null

func is_maze_door(door: Node) -> bool:
	return door.target_scene == MAZE_TARGET

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

func _correct_name(tree: SceneTree, step: int) -> StringName:
	if not _solution.has(step):
		var names := tree.get_nodes_in_group("doors").filter(is_maze_door).map(func(d): return d.name)
		if names.is_empty():
			return &""
		_solution[step] = names.pick_random()
	return _solution[step]

func _process(delta: float) -> void:
	var door := _current_correct_door()
	var player := _find_player()
	if door == null or player == null or not Global.has_ability(&"zahori"):
		_set_glow(null, 0.0)
		_set_indicator(player, 0)
		return
	var dist: float = door.global_position.distance_to(player.global_position)
	var near := 1.0 - clampf(dist / dowse_range, 0.0, 1.0)
	if near <= 0.0:
		_set_glow(null, 0.0)
		_set_indicator(player, 0)
		return
	var interval := lerpf(dowse_max_interval, dowse_min_interval, near)
	_dowse_timer -= delta
	if _dowse_timer <= 0.0:
		_dowse_timer = interval
		Sfx.play("dowse", lerpf(0.8, 1.4, near), lerpf(-14.0, -4.0, near))
	var pulse := clampf(_dowse_timer / interval, 0.0, 1.0)
	_set_glow(door.get_node_or_null("sprite"), dowse_glow * near * pulse)
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
