extends Node

const MAIN_THEME := preload("res://music/main_theme.ogg")
const TITLE_THEME := preload("res://music/title_theme.ogg")
const SILENT_FROM_LEVEL := 180
const LEVEL_RE := "level(\\d+)[a-z]?\\.tscn$"

@export var volume_db: float = -8.0
@export var fade_out_time: float = 2.5
@export var fade_in_time: float = 1.5
@export var suspend_fade_time: float = 0.4
@export var title_volume_db: float = -15.0
@export var title_fade_in_time: float = 3.0 

var _player: AudioStreamPlayer
var _fade: Tween
var _title_player: AudioStreamPlayer
var _title_fade: Tween
var _level_re := RegEx.create_from_string(LEVEL_RE)

func _ready() -> void:
	get_tree().scene_changed.connect(_on_scene_changed)

func _level_number(scene: Node) -> int:
	if scene == null:
		return -1
	var m := _level_re.search(scene.scene_file_path)
	return m.get_string(1).to_int() if m else -1

func _on_scene_changed() -> void:
	if _player == null:
		return
	var level := _level_number(get_tree().current_scene)
	if level == -1:
		return
	if level >= SILENT_FROM_LEVEL:
		_fade_out()
	else:
		_fade_in()

func _fade_out() -> void:
	if _player.stream_paused:
		return
	_start_fade(-80.0, fade_out_time).tween_callback(func(): _player.stream_paused = true)

func _fade_in() -> void:
	if not _player.stream_paused and is_equal_approx(_player.volume_db, volume_db):
		return
	_player.stream_paused = false
	_start_fade(volume_db, fade_in_time)

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
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	add_child(_player)
	var stream: AudioStreamOggVorbis = MAIN_THEME
	stream.loop = true
	_player.stream = stream
	_player.volume_db = volume_db
	_player.play()

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
