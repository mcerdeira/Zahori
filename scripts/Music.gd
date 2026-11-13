extends Node

## Música de fondo. Es autoload para que el tema no se corte al cambiar de room,
## y sigue sonando con el juego pausado (terminal abierta).
## El tema se genera con tools/gen_music.py.

const MAIN_THEME := preload("res://music/main_theme.ogg")

## Volumen de la música (dB).
@export var volume_db: float = -8.0

var _player: AudioStreamPlayer

func play_main_theme() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	add_child(_player)
	var stream: AudioStreamOggVorbis = MAIN_THEME
	stream.loop = true
	_player.stream = stream
	_player.volume_db = volume_db
	_player.play()
