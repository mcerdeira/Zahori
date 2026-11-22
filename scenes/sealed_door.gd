extends Area2D
## Puerta sellada: decorativa, marca por dónde se entró a una room de la que ya no
## se puede volver (p. ej. level182, al salir del laberinto de puertas).
## Al llegar a la room se ve un instante como una puerta normal (titilando) y se
## cierra de golpe: queda de piedra con enredaderas, suena `door_seal`, se sacude y
## levanta polvo. Si la room se recarga porque el player murió, ya aparece cerrada.
## Apretar UP delante sólo da un golpe sordo: no lleva a ningún lado.
## No está en el grupo `doors`: no cuenta para los spawns ni para los tools.

const OPEN_FRAMES: Array[Texture2D] = [
	preload("res://sprites/door1.png"),
	preload("res://sprites/door2.png"),
	preload("res://sprites/door3.png"),
	preload("res://sprites/door4.png"),
]
const SEALED := preload("res://sprites/door_sealed_spr_0.png")

@export var open_time: float = 0.6     # segundos que se ve abierta antes de cerrarse
@export var open_fps: float = 15.0     # frames/s del titileo de puerta abierta (como door.tscn)
@export var shake_px: float = 2.0      # px de la sacudida al cerrarse
@export var dust_amount: int = 14      # partículas de polvo al cerrarse

var _player: Node = null
var _closed_on_load := false
var _busy := false

@onready var _sprite: Sprite2D = $sprite


func _enter_tree() -> void:
	# Antes de cualquier _ready (el player consume este flag en el suyo): si se está
	# recargando la room por una muerte, la puerta ya estaba cerrada.
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


## Titila como puerta abierta un momento y se cierra de golpe.
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


## UP delante de la puerta sellada: golpe sordo y una sacudida chiquita.
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


## Polvo que cae de arriba de la puerta y se desparrama por el piso.
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
