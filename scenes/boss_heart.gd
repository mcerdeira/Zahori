extends Node2D

const ENDING_CHOICE := preload("res://scenes/ending_choice.tscn")
const FRAMES: Array[Texture2D] = [
	preload("res://sprites/boss_heart_beat_spr_0.png"),
	preload("res://sprites/boss_heart_beat_spr_1.png")
]

@export_range(0.0, 1.0, 0.01) var glow_strength: float = 0.55
@export var glow_growth: float = 0.18

@onready var _sprite: Sprite2D = $Sprite
@onready var _touch: Area2D = $touch

func _physics_process(_delta: float) -> void:
	for body in _touch.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("can_touch") and body.can_touch():
			set_physics_process(false)
			process_mode = Node.PROCESS_MODE_ALWAYS
			get_tree().root.add_child(ENDING_CHOICE.instantiate())
			return

func _process(_delta: float) -> void:
	var amount: float = Heartbeat.pulse * lerpf(0.67, 1.0, Heartbeat.intensity)
	_sprite.texture = FRAMES[clampi(roundi(amount * (FRAMES.size() - 1)), 0, FRAMES.size() - 1)]
