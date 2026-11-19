extends Node

## Música de fondo. Es autoload para que el tema no se corte al cambiar de room,
## y sigue sonando con el juego pausado (terminal abierta).
## El tema se genera con tools/gen_music.py.

const MAIN_THEME := preload("res://music/main_theme.ogg")
const TITLE_THEME := preload("res://music/title_theme.ogg")

## A partir de esta room (levelN con N >= este número) es la parte final del
## juego: la música se apaga. Al volver a una room anterior se reanuda.
const SILENT_FROM_LEVEL := 180
const LEVEL_RE := "level(\\d+)[a-z]?\\.tscn$"

## Volumen de la música (dB).
@export var volume_db: float = -8.0
@export var fade_out_time: float = 2.5 # segundos del fade al entrar a la parte final
@export var fade_in_time: float = 1.5  # segundos del fade al reanudar
@export var suspend_fade_time: float = 0.4 # segundos del fade al pausarla por un enemigo (enredadera)
## Volumen del tema del título (dB). Más bajo que el principal: es un fondo sutil.
@export var title_volume_db: float = -15.0
@export var title_fade_in_time: float = 3.0 # segundos del fade de entrada del título

var _player: AudioStreamPlayer
var _fade: Tween
var _title_player: AudioStreamPlayer
var _title_fade: Tween
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


## Pausa el tema en la room actual (la enredadera al despertar). Se reanuda solo
## al pasar a otra room, como al volver de la parte final.
func suspend() -> void:
	if _player == null or _player.stream_paused:
		return
	_start_fade(-80.0, suspend_fade_time).tween_callback(func(): _player.stream_paused = true)


func _start_fade(to_db: float, time: float) -> Tween:
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_player, "volume_db", to_db, time)
	return _fade

func play_main_theme() -> void:
	if _player:
		return # ya está sonando (p. ej. si se vuelve a pasar por las intros)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	add_child(_player)
	var stream: AudioStreamOggVorbis = MAIN_THEME
	stream.loop = true
	_player.stream = stream
	_player.volume_db = volume_db
	_player.play()


## Tema del menú de título: entra con un fade largo.
func play_title_theme() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _title_player:
		return
	_title_player = AudioStreamPlayer.new()
	_title_player.bus = &"Music"
	add_child(_title_player)
	var stream: AudioStreamOggVorbis = TITLE_THEME
	stream.loop = true
	_title_player.stream = stream
	_title_player.volume_db = -60.0
	_title_player.play()
	_title_fade = create_tween()
	_title_fade.tween_property(_title_player, "volume_db", title_volume_db, title_fade_in_time)


## Apaga el tema del título con un fade de `time` segundos.
func stop_title_theme(time: float = 1.0) -> void:
	if _title_player == null:
		return
	var p := _title_player
	_title_player = null
	if _title_fade:
		_title_fade.kill()
	_title_fade = create_tween()
	_title_fade.tween_property(p, "volume_db", -60.0, time)
	_title_fade.tween_callback(p.queue_free)


## Apaga el tema principal con un fade (al volver al menú de título). La próxima
## llamada a play_main_theme() lo arranca de nuevo desde el principio.
func stop_main_theme(time: float = 1.0) -> void:
	if _player == null:
		return
	var p := _player
	_player = null
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(p, "volume_db", -60.0, time)
	_fade.tween_callback(p.queue_free)
