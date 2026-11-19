extends Node2D
## La hermana del player: muerta, atada a la pared del fondo por enredaderas.
## Al pararse delante suyo (en el piso y sin estar haciendo otra cosa) el player
## dice unas palabras (overlay de monólogo, como en la intro) y se lleva su vara
## zahorí: se activa la habilidad `zahori`. Pasa una sola vez: el estado es la
## propia habilidad (si ya la tiene, la hermana queda sin la vara y no dispara nada).

const OVERLAY := preload("res://scenes/monologue_overlay.tscn")
const NOROD_TEX := preload("res://sprites/sister_norod_spr_0.png")
const LINES: Array[String] = [
	"Oh, sister... I came too late.",
	"But your struggle shall not be in vain.",
	"I will carry on the search with your Zahori rod. May it guide my way.",
]

var _triggered := false

@onready var _sprite: Sprite2D = $sprite
@onready var _area: Area2D = $trigger


func _ready() -> void:
	if Global.has_ability(&"zahori"):
		_take_rod()


func _physics_process(_delta: float) -> void:
	if _triggered or Global.has_ability(&"zahori"):
		return
	for body in _area.get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("can_interact") and body.can_interact():
			_start()
			return


func _start() -> void:
	_triggered = true
	var overlay := OVERLAY.instantiate()
	overlay.lines = LINES
	overlay.finished.connect(_on_monologue_finished)
	get_tree().root.add_child(overlay)


func _on_monologue_finished() -> void:
	_take_rod()
	Global.set_ability(&"zahori", true)
	Sfx.play("dowse")


func _take_rod() -> void:
	_sprite.texture = NOROD_TEX
	set_physics_process(false)
