extends Node2D

## Corazón vegetal del jefe final. Toma el pulso del autoload Heartbeat, así va siempre en
## sincronía con el sonido y la sacudida de los objetos `heartbeat.tscn`.
## Al tocarlo el player (también subido a sus bloques) arranca el final: `ending_choice.tscn`.

const ENDING_CHOICE := preload("res://scenes/ending_choice.tscn")
const FRAMES: Array[Texture2D] = [
	preload("res://sprites/boss_heart_beat_spr_0.png"),
	preload("res://sprites/boss_heart_beat_spr_1.png")
]

@export_range(0.0, 1.0, 0.01) var glow_strength: float = 0.55 # opacidad máxima del halo
@export var glow_growth: float = 0.18 # cuánto crece el halo en cada golpe (1 = el doble)

@onready var _sprite: Sprite2D = $Sprite
@onready var _touch: Area2D = $touch


func _physics_process(_delta: float) -> void:
	for body in _touch.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("can_touch") and body.can_touch():
			set_physics_process(false)
			process_mode = Node.PROCESS_MODE_ALWAYS # sigue latiendo durante la pregunta
			get_tree().root.add_child(ENDING_CHOICE.instantiate())
			return


func _process(_delta: float) -> void:
	# Con poca intensidad el corazón late, pero sin llegar a la dilatación máxima
	var amount: float = Heartbeat.pulse * lerpf(0.67, 1.0, Heartbeat.intensity)
	_sprite.texture = FRAMES[clampi(roundi(amount * (FRAMES.size() - 1)), 0, FRAMES.size() - 1)]
