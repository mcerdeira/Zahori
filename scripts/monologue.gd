extends Node

signal finished

const VOWELS := "aeiou"

@export var lines: Array[String] = []
@export var autostart: bool = true
@export var char_interval: float = 0.075
@export var comma_pause: float = 0.35
@export var dot_pause: float = 0.3
@export var hold_time: float = 2.5
@export var fade_time: float = 0.6
@export var pitch_start: float = 1.0
@export var pitch_end: float = 0.86
@export var pitch_jitter: float = 0.04
@export var voice_volume_db: float = -2.0

var _line := -1
var _timer := 0.0
var _holding := false
var _fading := false
var _running := false
var _text := ""
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _syllables := {}

@onready var label: RichTextLabel = $RichTextLabel

func _ready() -> void:
	for onset in ["", "m"]:
		for v in VOWELS:
			_syllables[onset + v] = load("res://sounds/voice_%s%s.wav" % [onset, v])
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = &"Voice"
		p.volume_db = voice_volume_db
		add_child(p)
		_voices.append(p)
	label.text = ""
	if autostart:
		start()

func start() -> void:
	_running = true
	_line = -1
	_next_line()

func _finish() -> void:
	finished.emit()

func _process(delta: float) -> void:
	if not _running or _fading:
		return
	if Input.is_action_just_pressed("ui_accept"):
		if _holding:
			_next_line()
		else:
			label.visible_characters = -1
			_holding = true
			_timer = hold_time
		return
	_timer -= delta
	if _holding:
		if _timer <= 0.0:
			_next_line()
		return
	while _timer <= 0.0 and not _holding:
		_reveal_next_char()

func _next_line() -> void:
	_line += 1
	if _line >= lines.size():
		_running = false
		_finish()
		return
	if _line > 0:
		_fading = true
		var tw := create_tween()
		tw.tween_property(label, "modulate:a", 0.0, fade_time)
		await tw.finished
	label.text = "[wave amp=30.0 freq=3.0 connected=1]%s[/wave]" % lines[_line]
	_text = label.get_parsed_text()
	label.visible_characters = 0
	label.modulate.a = 1.0
	_holding = false
	_fading = false
	_timer = 0.6

func _reveal_next_char() -> void:
	var i := label.visible_characters
	if i >= _text.length():
		_holding = true
		_timer = hold_time
		return
	label.visible_characters = i + 1
	var c := _text[i]
	_timer += char_interval
	match c:
		",", ";", ":":
			_timer += comma_pause
		".", "!", "?":
			_timer += dot_pause
		_:
			_speak(c.to_lower(), float(i) / _text.length())

func _speak(c: String, progress: float) -> void:
	if c < "a" or c > "z":
		return
	var key: String
	if c in VOWELS:
		key = c
	else:
		var v := VOWELS[(c.unicode_at(0) * 7) % VOWELS.length()]
		key = "m" + v
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = _syllables[key]
	p.pitch_scale = lerpf(pitch_start, pitch_end, progress) * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()
