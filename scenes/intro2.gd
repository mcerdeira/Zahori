extends Node2D

## Intro 2: monólogo del protagonista. El texto aparece letra por letra y cada
## letra dispara una sílaba de una voz sintética con fonemas inventados
## (sounds/voice_*.wav, generados con tools/gen_sfx.py), así quedan sincronizados.

const NEXT_SCENE := "res://scenes/rooms/level0.tscn"
const LINES: Array[String] = [
	"At last... the threshold lies before me.",
	"Wherever you have gone, sister, I shall find you, and I shall know what befell you.",
	"Then, hand in hand, we shall unveil the secret that sleeps beneath eternity and time.",
]
const VOWELS := "aeiou"
## Consonantes "suaves": arrancan con ataque nasal; el resto, con ataque explosivo.
const SOFT_CONSONANTS := "lmnrvwyhj"

@export var char_interval: float = 0.075 # segundos entre cada letra
@export var comma_pause: float = 0.35    # segundos extra tras una coma
@export var dot_pause: float = 0.3       # segundos extra tras cada punto
@export var hold_time: float = 2.5       # segundos que queda la línea completa antes de seguir
@export var fade_time: float = 0.6       # segundos del fundido entre líneas
@export var pitch_start: float = 1.0     # tono al principio de cada línea
@export var pitch_end: float = 0.86      # tono al final (cae, como cerrando la frase)
@export var pitch_jitter: float = 0.04   # variación aleatoria del tono por sílaba
@export var voice_volume_db: float = -2.0

var _line := -1
var _timer := 0.0
var _holding := false
var _fading := false
var _leaving := false
var _text := "" # texto plano de la línea actual (sin bbcode)
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _syllables := {}

@onready var label: RichTextLabel = $RichTextLabel


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	for onset in ["", "m", "k"]:
		for v in VOWELS:
			_syllables[onset + v] = load("res://sounds/voice_%s%s.wav" % [onset, v])
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = &"Voice"
		p.volume_db = voice_volume_db
		add_child(p)
		_voices.append(p)
	_next_line()


func _process(delta: float) -> void:
	if _leaving or _fading:
		return
	if Input.is_action_just_pressed("ui_accept"):
		if _holding:
			_next_line()
		else:
			label.visible_characters = -1 # completar la línea de golpe
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
	if _line >= LINES.size():
		_leaving = true
		Music.play_main_theme()
		get_tree().change_scene_to_file(NEXT_SCENE)
		return
	if _line > 0:
		_fading = true
		var tw := create_tween()
		tw.tween_property(label, "modulate:a", 0.0, fade_time)
		await tw.finished
	label.text = "[wave amp=30.0 freq=3.0 connected=1]%s[/wave]" % LINES[_line]
	_text = label.get_parsed_text()
	label.visible_characters = 0
	label.modulate.a = 1.0
	_holding = false
	_fading = false
	_timer = 0.6 # pequeña pausa antes de empezar a hablar


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


## Una sílaba por letra: las vocales suenan solas; cada consonante elige
## siempre la misma vocal (idioma inventado pero consistente) con su ataque.
func _speak(c: String, progress: float) -> void:
	if c < "a" or c > "z":
		return # espacios y otros signos no suenan
	var key: String
	if c in VOWELS:
		key = c
	else:
		var v := VOWELS[(c.unicode_at(0) * 7) % VOWELS.length()]
		key = ("m" if c in SOFT_CONSONANTS else "k") + v
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = _syllables[key]
	p.pitch_scale = lerpf(pitch_start, pitch_end, progress) * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()
