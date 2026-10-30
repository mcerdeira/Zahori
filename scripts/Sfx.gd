extends Node

## Efectos de sonido globales. Al ser autoload sobrevive a los cambios de
## escena, así un sonido no se corta cuando el player cruza una puerta.
## Los .wav se generan con tools/gen_sfx.py.

const SOUNDS := {
	"block": preload("res://sounds/block.wav"),
	"vanish": preload("res://sounds/vanish.wav"),
	"land": preload("res://sounds/land.wav"),
	"step": preload("res://sounds/step.wav"),
	"door": preload("res://sounds/door.wav"),
	"die": preload("res://sounds/die.wav"),
	"start": preload("res://sounds/start.wav"),
}

## Cantidad de sonidos que pueden sonar a la vez.
@export var voices: int = 8
## Volumen general de los efectos (dB).
@export var volume_db: float = -4.0

var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in voices:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## Reproduce un efecto por nombre. pitch: multiplicador de tono; volume: dB extra.
func play(sound: String, pitch: float = 1.0, volume: float = 0.0) -> void:
	if not SOUNDS.has(sound):
		push_warning("Sfx: no existe el sonido '%s'" % sound)
		return
	# Usa una voz libre; si están todas ocupadas, pisa la más vieja (round robin)
	var player: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _players[_next]
		_next = (_next + 1) % _players.size()
	player.stream = SOUNDS[sound]
	player.pitch_scale = pitch
	player.volume_db = volume_db + volume
	player.play()
