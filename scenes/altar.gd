extends Area2D
## Altar: parado encima y apretando UP se abre la terminal (pausa el juego).
## Puede ser de puzzle (glifo que desbloquea una habilidad) o de pista (sólo
## muestra un texto fijo que orienta sobre la palabra de otro altar).
## Usar la terminal guarda la partida (al abrirla y al cerrarla, por si adentro
## se resolvió el puzzle o se prendió/apagó la habilidad): al cargar, el player
## reaparece parado en este altar. También pasa a ser el punto de reaparición de la
## room si muere antes de salir por una puerta.

const TERMINAL_SCENE := preload("res://scenes/terminal.tscn")

## El jugador descifró el glifo de este altar.
signal puzzle_solved(altar_number: int)

enum Kind { PUZZLE, HINT }

## PUZZLE: corre el glifo. HINT: muestra la pista de res://puzzles/hint_XX.tres.
@export var kind: Kind = Kind.PUZZLE
## Número de altar: elige el puzzle (res://puzzles/altar_XX.tres) o la pista
## (res://puzzles/hint_XX.tres) y se muestra como ALTAR-XX en los dos casos.
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
	Global.set_altar_respawn(global_position) # al morir en esta room, reaparece acá


func _on_body_entered(body: Node) -> void:
	if body.has_method("can_interact"):
		_player = body


func _on_body_exited(body: Node) -> void:
	if body == _player:
		_player = null
