extends Node

## Música de fondo. Es autoload para que el tema no se corte al cambiar de room,
## y sigue sonando con el juego pausado (terminal abierta).
## El tema se genera con tools/gen_music.py.

const MAIN_THEME := preload("res://music/main_theme.ogg")

## A partir de esta room (levelN con N >= este número) es la parte final del
## juego: la música se apaga. Al volver a una room anterior se reanuda.
const SILENT_FROM_LEVEL := 180
const LEVEL_RE := "level(\\d+)[a-z]?\\.tscn$"

## Volumen de la música (dB).
@export var volume_db: float = -8.0
@export var fade_out_time: float = 2.5 # segundos del fade al entrar a la parte final
@export var fade_in_time: float = 1.5  # segundos del fade al reanudar

var _player: AudioStreamPlayer
var _fade: Tween
var _level_re := RegEx.create_from_string(LEVEL_RE)


func _ready() -> void:
	get_tree().scene_changed.connect(_on_scene_changed)


## Número de la room (level181b -> 181), o -1 si la escena no es una room (intros).
func _level_number(scene: Node) -> int:
	if scene == null:
		return -1
	var m := _level_re.search(scene.scene_file_path)
	return m.get_string(1).to_int() if m else -1


func _on_scene_changed() -> void:
	if _player == null:
		return # el tema todavía no arrancó (intros)
	var level := _level_number(get_tree().current_scene)
	if level == -1:
		return
	if level >= SILENT_FROM_LEVEL:
		_fade_out()
	else:
		_fade_in()


## Baja el volumen y pausa el tema (queda en la misma posición para reanudarlo).
func _fade_out() -> void:
	if _player.stream_paused:
		return
	_start_fade(-80.0, fade_out_time).tween_callback(func(): _player.stream_paused = true)


## Reanuda el tema desde donde quedó, subiendo el volumen.
func _fade_in() -> void:
	if not _player.stream_paused and is_equal_approx(_player.volume_db, volume_db):
		return
	_player.stream_paused = false
	_start_fade(volume_db, fade_in_time)


func _start_fade(to_db: float, time: float) -> Tween:
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_player, "volume_db", to_db, time)
	return _fade

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
