extends Node

const SOUNDS := {
	"block": preload("res://sounds/block.wav"),
	"vanish": preload("res://sounds/vanish.wav"),
	"land": preload("res://sounds/land.wav"),
	"step": preload("res://sounds/step.wav"),
	"door": preload("res://sounds/door.wav"),
	"die": preload("res://sounds/die.wav"),
	"chomp": preload("res://sounds/chomp.wav"),
	"term_on": preload("res://sounds/term_on.wav"),
	"term_off": preload("res://sounds/term_off.wav"),
	"term_key": preload("res://sounds/term_key.wav"),
	"term_ok": preload("res://sounds/term_ok.wav"),
	"term_err": preload("res://sounds/term_err.wav"),
	"dowse": preload("res://sounds/dowse.wav"),
	"hiss": preload("res://sounds/hiss.wav"),
	"shoot": preload("res://sounds/shoot.wav"),
	"pop": preload("res://sounds/pop.wav"),
	"teleport": preload("res://sounds/teleport.wav"),
	"vine_scream": preload("res://sounds/vine_scream.wav"),
	"vine_creep": preload("res://sounds/vine_creep.wav"),
	"vine_eat": preload("res://sounds/vine_eat.wav"),
	"item_get": preload("res://sounds/item_get.wav"),
	"stone_clack": preload("res://sounds/stone_clack.wav"),
	"tablet_reveal": preload("res://sounds/tablet_reveal.wav"),
	"door_seal": preload("res://sounds/door_seal.wav"),
	"heart_lub": preload("res://sounds/heart_lub.wav"),
	"heart_dub": preload("res://sounds/heart_dub.wav"),
}

@export var voices: int = 8
@export var volume_db: float = -4.0

var _players: Array[AudioStreamPlayer] = []
var _next := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in voices:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)

func play(sound: String, pitch: float = 1.0, volume: float = 0.0) -> void:
	if not SOUNDS.has(sound):
		push_warning("Sfx: no existe el sonido '%s'" % sound)
		return
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
