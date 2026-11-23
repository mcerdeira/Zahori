extends Node2D

## Corazón vegetal del jefe final. Por ahora sólo late: toma el pulso del autoload Heartbeat,
## así va siempre en sincronía con el sonido y la sacudida de los objetos `heartbeat.tscn`.

const FRAMES: Array[Texture2D] = [
	preload("res://sprites/boss_heart_beat_spr_0.png"),
	preload("res://sprites/boss_heart_beat_spr_1.png"),
	preload("res://sprites/boss_heart_beat_spr_2.png"),
	preload("res://sprites/boss_heart_beat_spr_3.png"),
]

@export_range(0.0, 1.0, 0.01) var glow_strength: float = 0.55 # opacidad máxima del halo
@export var glow_growth: float = 0.18 # cuánto crece el halo en cada golpe (1 = el doble)

@onready var _sprite: Sprite2D = $Sprite
@onready var _glow: Sprite2D = $Glow


func _process(_delta: float) -> void:
	# Con poca intensidad el corazón late, pero sin llegar a la dilatación máxima
	var amount: float = Heartbeat.pulse * lerpf(0.67, 1.0, Heartbeat.intensity)
	_sprite.texture = FRAMES[clampi(roundi(amount * (FRAMES.size() - 1)), 0, FRAMES.size() - 1)]
	_glow.modulate.a = amount * glow_strength
	_glow.scale = Vector2.ONE * (1.35 + glow_growth * amount)
