extends CanvasLayer
signal closed

const TabletMesh := preload("res://scenes/tablet_mesh.gd")
const SHADER := preload("res://scenes/tablet.gdshader")
const TEX_FRONT := preload("res://sprites/tablet_front_spr_0.png")
const TEX_BACK := preload("res://sprites/tablet_back_spr_0.png")
const TEX_SIDE := preload("res://sprites/tablet_side_spr_0.png")

const INSCRIPTION: Array[String] = [
	"This temple was raised upon a sleeping spring.",
	"Its roots drink, and their drinking keeps it dreaming.",
	"Whoever climbs feeds the green. Whoever falls is kept.",
	"Two shall come seeking. One shall be found.",
]

@export var new_piece: int = -1
@export var rotate_speed: float = 2.6
@export var tilt_speed: float = 1.6 
@export var tilt_max: float = 0.7   
@export var smoothing: float = 9.0     
@export var sway: float = 0.06     
@export var fade_time: float = 0.35     
@export var fly_time: float = 0.9     
@export var center_y: float = 0.3
@export var raised_y: float = 1.45
@export var camera_distance: float = 10.0
@export var raised_camera_distance: float = 11.5

var _yaw := 0.0
var _pitch := 0.0
var _target_yaw := 0.0
var _target_pitch := 0.0
var _time := 0.0
var _closing := false
var _input_delay := 0.3
var _paused_by_me := false
var _pieces := {}

@onready var _bg: ColorRect = $bg
@onready var _view: TextureRect = $view
@onready var _viewport: SubViewport = $view/viewport
@onready var _counter: Label = $counter
@onready var _text: Node = $inscription
@onready var _text_label: RichTextLabel = $inscription/RichTextLabel

var _cam: Camera3D
var _pivot: Node3D 
var _spin: Node3D   

func _ready() -> void:
	_paused_by_me = not get_tree().paused
	get_tree().paused = true
	_view.texture = _viewport.get_texture()
	_build_scene()
	var text: Array[String] = ["\n".join(INSCRIPTION)]
	_text.lines = text
	_refresh_labels()
	var complete := Global.tablet_piece_count() >= Global.TABLET_PIECE_COUNT
	var completes_now := complete and new_piece >= 0
	if complete and not completes_now:
		_pivot.position.y = raised_y
		_cam.position.z = raised_camera_distance

	for node: CanvasItem in [_bg, _view, _counter, _text_label]:
		node.modulate.a = 0.0
		create_tween().tween_property(node, "modulate:a", 1.0, fade_time)

	if new_piece >= 0 and _pieces.has(new_piece):
		await _fly_in(_pieces[new_piece])
		if completes_now:
			await _reveal()
	elif complete:
		await get_tree().create_timer(fade_time).timeout
		_text.start()

func _build_scene() -> void:
	_cam = Camera3D.new()
	_cam.fov = 44.0
	_cam.position = Vector3(0, 0, camera_distance)
	_viewport.add_child(_cam)
	_cam.current = true
	_pivot = Node3D.new()
	_pivot.position.y = center_y
	_viewport.add_child(_pivot)
	_spin = Node3D.new()
	_pivot.add_child(_spin)

	var mats := [_material(TEX_FRONT), _material(TEX_BACK), _material(TEX_SIDE)]
	var data := TabletMesh.build_pieces()
	for i in data.size():
		if not Global.has_tablet_piece(i):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = data[i].mesh
		for s in mats.size():
			mi.set_surface_override_material(s, mats[s])
		mi.position = data[i].offset
		mi.set_meta(&"home", data[i].offset)
		_spin.add_child(mi)
		_pieces[i] = mi

func _material(tex: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"tex", tex)
	return m

func _refresh_labels() -> void:
	_counter.text = "FRAGMENTS %d/%d" % [Global.tablet_piece_count(), Global.TABLET_PIECE_COUNT]

static func _key(action: StringName) -> String:
	var keys: Array = Settings.keys.get(action, [0])
	return Settings.key_name(keys[0])

func _fly_in(mi: MeshInstance3D) -> void:
	var home: Vector3 = mi.get_meta(&"home")
	var dir := Vector3(home.x, home.y, 0.0).normalized()
	mi.position = home + dir * 3.0 + Vector3(0, 0, 4.5)
	mi.rotation = Vector3(1.6, -2.4, 0.9) * Vector3(signf(home.y), signf(home.x), 1.0)
	await get_tree().create_timer(0.35).timeout
	var tw := create_tween().set_parallel()
	tw.tween_property(mi, "position", home, fly_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(mi, "rotation", Vector3.ZERO, fly_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	Sfx.play("stone_clack")
	_shake()

func _shake() -> void:
	var tw := create_tween()
	var base := _spin.position
	for off in [Vector3(0.08, -0.05, 0), Vector3(-0.06, 0.03, 0), Vector3(0.03, 0, 0), Vector3.ZERO]:
		tw.tween_property(_spin, "position", base + off, 0.04)

func _reveal() -> void:
	await get_tree().create_timer(0.5).timeout
	Sfx.play("tablet_reveal")
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_pivot, "position:y", raised_y, 1.2)
	tw.tween_property(_cam, "position:z", raised_camera_distance, 1.2)
	await tw.finished
	_text.start()

func _process(delta: float) -> void:
	_time += delta
	_input_delay -= delta
	if not _closing:
		var turn := Input.get_axis(&"LEFT", &"RIGHT")
		var tilt := Input.get_axis(&"UP", &"DOWN")
		_target_yaw += turn * rotate_speed * delta
		_target_pitch = clampf(_target_pitch + tilt * tilt_speed * delta, -tilt_max, tilt_max)
	var k := 1.0 - exp(-smoothing * delta)
	_yaw = lerpf(_yaw, _target_yaw, k)
	_pitch = lerpf(_pitch, _target_pitch, k)
	_spin.rotation = Vector3(_pitch + sin(_time * 0.9) * sway * 0.6, _yaw + sin(_time * 0.6) * sway, 0.0)

func _input(event: InputEvent) -> void:
	if _closing:
		return
	if _input_delay > 0.0:
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"action") or event.is_action_pressed(&"pause") \
			or event.is_action_pressed(&"ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"shoot"):
		_target_yaw = (roundf(_target_yaw / PI) + 1.0) * PI
		Sfx.play("stone_clack", 1.6, -10.0)
		get_viewport().set_input_as_handled()

func _close() -> void:
	_closing = true
	var tw := create_tween().set_parallel()
	for node: CanvasItem in [_bg, _view, _counter, _text_label]:
		tw.tween_property(node, "modulate:a", 0.0, fade_time)
	await tw.finished
	if _paused_by_me:
		get_tree().paused = false
	closed.emit()
	queue_free()
