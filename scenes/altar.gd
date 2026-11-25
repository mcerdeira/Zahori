extends Area2D

const TERMINAL_SCENE := preload("res://scenes/terminal.tscn")

signal puzzle_solved(altar_number: int)

enum Kind { PUZZLE, HINT }

@export var kind: Kind = Kind.PUZZLE
@export var altar_number: int = 1

var _player: Node = null
var _terminal: Node = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if _player and _terminal == null and Input.is_action_just_pressed("UP") \
			and _player.can_interact():
		_open_terminal()

func _open_terminal() -> void:
	_save()
	_terminal = TERMINAL_SCENE.instantiate()
	_terminal.altar_number = altar_number
	_terminal.is_hint = kind == Kind.HINT
	_terminal.solved.connect(puzzle_solved.emit)
	_terminal.closed.connect(func():
		_terminal = null
		_save())
	get_tree().current_scene.add_child(_terminal)

func _save() -> void:
	Global.save_game(get_tree().current_scene.scene_file_path, global_position)
	Global.set_altar_respawn(global_position)

func _on_body_entered(body: Node) -> void:
	if body.has_method("can_interact"):
		_player = body

func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null
