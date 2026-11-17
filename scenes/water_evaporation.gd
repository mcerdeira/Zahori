extends Node2D
## Evaporación del agua al activarse hydro (al entrar a una room o al prender
## la habilidad). Primero el agua sigue visible hold_time segundos mientras
## empieza a subir vapor; después se borran los tiles y una copia de ellos se
## disuelve pixel a pixel, blanqueándose, entre más vapor.
## Lo crea Global con setup(); se borra solo al terminar.

const DISSOLVE_SHADER := preload("res://scenes/water_evaporation.gdshader")

@export var hold_time: float = 1.0 # s que el agua se ve antes de evaporarse
@export var dissolve_time: float = 0.8 # s que tarda la copia en desaparecer
@export var steam_per_cell: float = 2.5 # partículas de vapor por celda (promedio)
@export var steam_rise: float = 18.0 # px/s que sube el vapor
@export var steam_life: float = 1.2 # s que dura cada partícula

var _layer: TileMapLayer
var _cells: Array = [] # [coords, source, atlas_coords, alternative]
var _time := 0.0
var _erased := false
var _steam: Array = [] # {pos: Vector2, life: float, max: float, size: int}
var _copy: Node2D # dibuja la copia de los tiles con el shader de disolución
var _copy_mat: ShaderMaterial
var _spawn_acc := 0.0


func setup(layer: TileMapLayer, cells: Array) -> void:
	_layer = layer
	_cells = cells


func _ready() -> void:
	z_index = 5
	_copy = Node2D.new()
	_copy_mat = ShaderMaterial.new()
	_copy_mat.shader = DISSOLVE_SHADER
	_copy.material = _copy_mat
	_copy.visible = false
	_copy.draw.connect(_draw_copy)
	add_child(_copy)
	Sfx.play("hiss", randf_range(0.95, 1.05))


func _process(delta: float) -> void:
	_time += delta
	if not _erased and _time >= hold_time:
		# Si hydro se apagó mientras tanto, Global ya restauró el agua: abortar
		if not _layer.has_meta(Global.HIDDEN_WATER_META):
			queue_free()
			return
		_erased = true
		Global.water_active = false
		for c in _cells:
			_layer.erase_cell(c[0])
		_copy.visible = true
		_copy.queue_redraw()
		_burst(3.0) # bocanada de vapor al evaporarse
	if _erased:
		var p := clampf((_time - hold_time) / dissolve_time, 0.0, 1.0)
		_copy_mat.set_shader_parameter("progress", p)

	# Vapor: arranca de a poco durante la espera y sigue un rato al disolverse
	var emitting := _time < hold_time + dissolve_time * 0.7
	if emitting:
		var rate := steam_per_cell * _cells.size() * (0.6 if not _erased else 1.5)
		_spawn_acc += rate * delta
		while _spawn_acc >= 1.0:
			_spawn_acc -= 1.0
			_spawn_steam()
	for s in _steam:
		s.life += delta
		s.pos += Vector2(sin(s.life * 6.0 + s.phase) * 4.0, -steam_rise) * delta
	_steam = _steam.filter(func(s): return s.life < s.max)
	queue_redraw()
	if not emitting and _steam.is_empty() and _time >= hold_time + dissolve_time:
		queue_free()


func _burst(per_cell: float) -> void:
	for i in int(_cells.size() * per_cell):
		_spawn_steam()


func _spawn_steam() -> void:
	var c: Array = _cells.pick_random()
	var half := Vector2(_layer.tile_set.tile_size) / 2.0
	var center := _layer.map_to_local(c[0])
	_steam.append({
		pos = center + Vector2(randf_range(-half.x, half.x), randf_range(-half.y, half.y * 0.3)),
		life = 0.0,
		max = steam_life * randf_range(0.6, 1.2),
		size = 1 if randf() < 0.6 else 2,
		phase = randf() * TAU,
	})


func _draw() -> void:
	for s in _steam:
		var k: float = s.life / s.max
		var a := (1.0 - k * k) * 0.9
		var col := Color(0.85, 0.95, 1.0, a)
		draw_rect(Rect2(s.pos.round(), Vector2.ONE * s.size), col)


## Copia estática de los tiles (primer frame del atlas) para disolverla.
func _draw_copy() -> void:
	for c in _cells:
		var src := _layer.tile_set.get_source(c[1]) as TileSetAtlasSource
		if src == null:
			continue
		var region := src.get_tile_texture_region(c[2])
		var pos := _layer.map_to_local(c[0]) - Vector2(region.size) / 2.0
		_copy.draw_texture_rect_region(src.texture, Rect2(pos, region.size), region)
