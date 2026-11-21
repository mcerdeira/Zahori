extends Area2D

@export_file("*.tscn") var target_scene: String
@export var transition_time: float = 1.1 # segundos de la animación de entrar
## Puerta instantánea (para salir por los bordes del nivel): cambia de escena
## apenas el player la toca, sin UP ni transición. En el juego es invisible y emite una luz (ver Glow).
@export var instant: bool = false
## Si está activo, el player aparece en spawn_point (coordenadas de la room,
## misma convención que la posición del nodo Player) en vez de sobre la puerta.
## Útil en las instant fuera del nivel, para no aparecer encima de ellas.
@export var use_spawn_point: bool = false
@export var spawn_point: Vector2 = Vector2.ZERO # px, coordenadas de la room
## Al aparecer en esta puerta, trae el bote de la room y lo pone debajo del
## player (para salir de una room navegando y seguir en la otra).
@export var with_boat: bool = false
## Con with_boat: si está activo, el bote aparece en boat_point (coordenadas de la
## room, misma convención que la posición del nodo Boat) en vez de bajo el player.
## Útil cuando el player vuelve a pie y el bote tiene que quedar en la costa.
@export var use_boat_point: bool = false
@export var boat_point: Vector2 = Vector2.ZERO # px, coordenadas de la room
## Al aparecer en esta puerta, para dónde mira el player ("-" = no cambiar).
@export_enum("-", "L", "R") var facing: String = "-"
## Al aparecer en esta puerta, borra las enredaderas de la room (grupo `vines`):
## p. ej. para que no persiga al player si entra por el otro lado.
@export var kill_vine: bool = false

@export_group("Glow (instant)")
## Las instant emiten una luz que parpadea con los colores de la puerta normal.
@export var glow_enabled: bool = true
@export var glow_radius: float = 40.0 # px que se extiende la luz desde el hueco
@export var glow_strength: float = 0.45 # intensidad máxima (0..1)
@export var glow_steps: int = 4 # bandas de la degradación (look pixel art)

const GLOW_SHADER := preload("res://scenes/door_glow.gdshader")

var _player: Node = null
var _entering := false
## Sólo para instant: false mientras el player esté encima desde el arranque
## (apareció en esta puerta al volver), para no rebotar de vuelta al instante.
var _armed := false
var _glow: ColorRect = null
var _glow_time := 0.0
var _glow_fps := 15.0 # frames/s, se lee del sprite
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

## Sólo para instant: se desarma y se vuelve a armar si el player no está encima.
## Lo llama el player al reaparecer, por si reapareció en esta puerta.
func rearm() -> void:
	if not instant:
		return
	_armed = false
	# Esperar a que el player esté ubicado y la física haya detectado la superposición
	await get_tree().physics_frame
	await get_tree().physics_frame
	_armed = not get_overlapping_bodies().any(func(b): return b.has_method("enter_door"))

func _process(delta: float) -> void:
	if _glow:
		_update_glow(delta)
	if _player and not _entering and Input.is_action_just_pressed("UP"):
		if _player.enter_door(global_position.x):
			_enter()

# Posición donde debe quedar el player para aparecer parado en esta puerta.
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
	Global.confirm_tablet_pieces() # salió de la room: los fragmentos agarrados quedan
	if DoorMaze.is_maze_door(self):
		# Puerta del laberinto: el destino lo decide DoorMaze. El player aparece
		# en su posición inicial de la room (la entrada), no en una puerta.
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

## Rect global del collider (las instant suelen estar escaladas para cubrir el hueco).
func _collider_rect() -> Rect2:
	var shape := $collider.shape as RectangleShape2D
	var xf: Transform2D = $collider.global_transform
	var half := shape.size / 2.0
	return xf * Rect2(-half, shape.size)

## Crea la luz: un rect top-level que cubre el collider más glow_radius en
## cada lado, con un shader aditivo que decae desde el borde del hueco.
func _build_glow() -> void:
	var rect := _collider_rect()
	_glow = ColorRect.new()
	_glow.top_level = true
	_glow.z_as_relative = false
	_glow.z_index = 1 # por encima de los tiles: ilumina también las paredes del hueco
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

## Mismo ciclo de colores que la animación del sprite de la puerta normal.
func _update_glow(delta: float) -> void:
	_glow_time += delta
	var idx := int(_glow_time * _glow_fps) % _glow_colors.size()
	(_glow.material as ShaderMaterial).set_shader_parameter("glow_color", _glow_colors[idx])

## Color sólido de cada frame del sprite (los de la puerta son de un solo color).
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
