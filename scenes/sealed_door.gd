extends Area2D

const OPEN_FRAMES: Array[Texture2D] = [
	preload("res://sprites/door1.png"),
	preload("res://sprites/door2.png"),
	preload("res://sprites/door3.png"),
	preload("res://sprites/door4.png"),
]
const SEALED := preload("res://sprites/door_sealed_spr_0.png")

@export var open_time: float = 0.6
@export var open_fps: float = 15.0
@export var shake_px: float = 2.0
@export var dust_amount: int = 14

var _player: Node = null
var _closed_on_load := false
var _busy := false

@onready var _sprite: Sprite2D = $sprite

func _enter_tree() -> void:
	_closed_on_load = Global.respawn_grace_pending

func _ready() -> void:
	body_entered.connect(func(b): if b.has_method("can_interact"): _player = b)
	body_exited.connect(func(b): if b == _player: _player = null)
	if _closed_on_load:
		_sprite.texture = SEALED
		return
	_play_closing()

func _process(_delta: float) -> void:
	if _player and not _busy and Input.is_action_just_pressed("UP") and _player.can_interact():
		_knock()

func _play_closing() -> void:
	_busy = true
	var t := 0.0
	while t < open_time:
		_sprite.texture = OPEN_FRAMES[int(t * open_fps) % OPEN_FRAMES.size()]
		await get_tree().process_frame
		t += get_process_delta_time()
	_sprite.texture = SEALED
	Sfx.play("door_seal")
	_dust()
	await _shake(shake_px, 6)
	_busy = false

func _knock() -> void:
	_busy = true
	Sfx.play("door_seal", 1.7, -9.0)
	await _shake(1.0, 3)
	_busy = false

func _shake(amount: float, steps: int) -> void:
	var tw := create_tween()
	for i in steps:
		var a := amount * (1.0 - float(i) / steps)
		tw.tween_property(_sprite, "position:x", a if i % 2 == 0 else -a, 0.03)
	tw.tween_property(_sprite, "position:x", 0.0, 0.03)
	await tw.finished

func _dust() -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = dust_amount
	p.lifetime = 0.7
	p.explosiveness = 0.9
	p.position = Vector2(0, 9)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(7, 1)
	p.direction = Vector2(0, -1)
	p.spread = 80.0
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 28.0
	p.gravity = Vector2(0, 60)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	p.color = Color(0.65, 0.65, 0.65, 0.9)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.2).timeout.connect(p.queue_free)
