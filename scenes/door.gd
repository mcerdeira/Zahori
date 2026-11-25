extends Area2D

@export_file("*.tscn") var target_scene: String
@export var transition_time: float = 1.1
@export var instant: bool = false
@export var use_spawn_point: bool = false
@export var spawn_point: Vector2 = Vector2.ZERO
@export var with_boat: bool = false
@export var use_boat_point: bool = false
@export var boat_point: Vector2 = Vector2.ZERO
@export_enum("-", "L", "R") var facing: String = "-"
@export var kill_vine: bool = false

@export_group("Glow (instant)")
@export var glow_enabled: bool = true
@export var glow_radius: float = 40.0
@export var glow_strength: float = 0.45
@export var glow_steps: int = 4

const GLOW_SHADER := preload("res://scenes/door_glow.gdshader")

var _player: Node = null
var _entering := false
var _armed := false
var _glow: ColorRect = null
var _glow_time := 0.0
var _glow_fps := 15.0
var _glow_colors: Array[Color] = []

func _enter_tree() -> void:
	add_to_group("doors")

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if instant:
		$sprite.visible = false
		if glow_enabled:
			_build_glow()
		rearm()

func rearm() -> void:
	if not instant:
		return
	_armed = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	_armed = not get_overlapping_bodies().any(func(b): return b.has_method("enter_door"))

func _process(delta: float) -> void:
	if _glow:
		_update_glow(delta)
	if _player and not _entering and Input.is_action_just_pressed("UP"):
		if _player.enter_door(global_position.x):
			_enter()

func spawn_position(feet_offset: float) -> Vector2:
	if use_spawn_point:
		return spawn_point
	var shape := $collider.shape as RectangleShape2D
	var bottom: float = global_position.y + $collider.position.y + shape.size.y / 2.0
	return Vector2(global_position.x, bottom - feet_offset)

func _enter() -> void:
	_entering = true
	if not instant:
		await get_tree().create_timer(transition_time).timeout
	if target_scene.is_empty():
		push_warning("Door '%s' no tiene target_scene configurada" % name)
		return
	Global.confirm_tablet_pieces()
	go_through()

func go_through() -> void:
	if target_scene.is_empty():
		push_warning("Door '%s' no tiene target_scene configurada" % name)
		return
	Global.clear_altar_respawn()
	if DoorMaze.is_maze_door(self):
		Global.came_from_door = false
		get_tree().change_scene_to_file(DoorMaze.resolve(self))
		return
	Global.register_door_exit(self)
	get_tree().change_scene_to_file(target_scene)

func _on_body_entered(body: Node) -> void:
	if instant:
		if _armed and not _entering and body.has_method("enter_door"):
			_enter.call_deferred()
		return
	if body.has_method("enter_door"):
		_player = body
		body.set_silhouette(true)

func _on_body_exited(body: Node) -> void:
	if instant:
		if body.has_method("enter_door"):
			_armed = true
		return
	if body == _player:
		body.set_silhouette(false)
		_player = null

func _collider_rect() -> Rect2:
	var shape := $collider.shape as RectangleShape2D
	var xf: Transform2D = $collider.global_transform
	var half := shape.size / 2.0
	return xf * Rect2(-half, shape.size)

func _build_glow() -> void:
	var rect := _collider_rect()
	_glow = ColorRect.new()
	_glow.top_level = true
	_glow.z_as_relative = false
	_glow.z_index = 1
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.position = (rect.position - Vector2.ONE * glow_radius).round()
	_glow.size = (rect.size + Vector2.ONE * glow_radius * 2.0).round()
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	mat.set_shader_parameter("rect_size", _glow.size)
	mat.set_shader_parameter("hole_half", rect.size / 2.0)
	mat.set_shader_parameter("radius", glow_radius)
	mat.set_shader_parameter("steps", glow_steps)
	mat.set_shader_parameter("strength", glow_strength)
	_glow.material = mat
	add_child(_glow)
	_read_frame_colors()
	_update_glow(0.0)

func _update_glow(delta: float) -> void:
	_glow_time += delta
	var idx := int(_glow_time * _glow_fps) % _glow_colors.size()
	(_glow.material as ShaderMaterial).set_shader_parameter("glow_color", _glow_colors[idx])

func _read_frame_colors() -> void:
	var frames: SpriteFrames = $sprite.sprite_frames
	_glow_fps = frames.get_animation_speed(&"default") * $sprite.speed_scale
	for i in frames.get_frame_count(&"default"):
		var img := frames.get_frame_texture(&"default", i).get_image()
		_glow_colors.append(_solid_color(img))

func _solid_color(img: Image) -> Color:
	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			if px.a > 0.5:
				return px
	return Color.BLACK
