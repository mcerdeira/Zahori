extends Area2D

const VIEWER := preload("res://scenes/tablet_viewer.tscn")
const FRAMES: Array[Texture2D] = [
	preload("res://sprites/tablet_piece_spr_0.png"),
	preload("res://sprites/tablet_piece_spr_1.png"),
]

@export_range(0, 3) var piece_index: int = 0
@export var bob_amplitude: float = 1.5 
@export var bob_speed: float = 2.2 
@export var glint_every: float = 2.0  
@export var glint_time: float = 0.12 

var _taken := false
var _time := 0.0

@onready var _sprite: Sprite2D = $sprite

func _ready() -> void:
	if Global.has_tablet_piece(piece_index):
		queue_free()
		return
	_time = randf() * glint_every
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_time += delta
	_sprite.position.y = roundf(sin(_time * bob_speed) * bob_amplitude)
	_sprite.texture = FRAMES[1 if fmod(_time, glint_every) < glint_time else 0]

func _on_body_entered(body: Node) -> void:
	if _taken or not body.is_in_group("player"):
		return
	if "state" in body and body.state == body.State.DEAD:
		return
	_taken = true
	Global.add_tablet_piece(piece_index)
	hide()
	set_deferred("monitoring", false)
	if body.has_method("show_item"):
		await body.show_item(FRAMES)
	else:
		Sfx.play("item_get")
	var viewer := VIEWER.instantiate()
	viewer.new_piece = piece_index
	get_tree().root.add_child(viewer)
	queue_free()
