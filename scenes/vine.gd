extends Node2D
## Enredadera enemiga: nace en la celda donde está el nodo y crece de a una celda
## (16 px) persiguiendo al player. El tallo es un solo camino desde la raíz hasta
## la cabeza; las ramitas que le salen son sólo decorativas (no matan ni ocupan lugar).
##
## Cada paso replanifica con A* sobre la grilla: no atraviesa tiles sólidos y sólo
## crece pegada a superficies (a `cling_range` celdas o menos de algún tile), como
## una enredadera de verdad (si nace o queda en el aire, crece colgando hasta
## agarrarse de algo). Seguir derecho más de `max_straight` celdas cuesta
## extra y cada celda tiene un costo al azar, así que serpentea y nunca va en línea
## recta. Los bloques verdes del player los atraviesa comiéndoselos (tarda
## `eat_time` cada uno): construir una torre sirve para ganar tiempo.
##
## Mata al player si la cabeza lo toca. Al despertar pausa la música (se reanuda
## sola al cambiar de room, ver Music) y cuando el player muere vuelve a empezar
## desde la raíz (grupo `player_death_listeners`, lo llama player.die()).

const TILE := 16
## Direcciones; el índice por 90° es la rotación de los sprites (0 = derecha).
const DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const STEM_TEX := preload("res://sprites/vine_stem_spr_0.png")
const CORNER_TEX := preload("res://sprites/vine_corner_spr_0.png")
const SPRIG_TEX: Array[Texture2D] = [
	preload("res://sprites/vine_sprig_spr_0.png"),
	preload("res://sprites/vine_sprig_spr_1.png"),
]

@export var start_delay: float = 1.5 # s hasta que despierta (al entrar a la room y tras cada muerte)
@export var step_time: float = 0.17 # s que tarda en crecer una celda
@export var eat_time: float = 0.9 # s que tarda en comerse un bloque verde
@export var cling_range: int = 2 # celdas: sólo crece a esta distancia (o menos) de un tile sólido
@export var max_straight: int = 2 # celdas seguidas en la misma dirección antes de penalizar
@export var straight_penalty: float = 3.0 # costo extra (en celdas) por seguir derecho de más
@export var wander: float = 3.0 # costo extra máximo al azar por celda (en celdas), para que serpentee
@export var self_cross_cost: float = 6.0 # costo extra (en celdas) por pasar por encima de su propio tallo
@export var sprig_chance: float = 0.3 # probabilidad de ramita decorativa por celda de tallo
@export var creep_sound_every: int = 3 # celdas entre cada crujido de crecimiento
## Celdas de la room (576x324 px). La grilla se agranda sola para incluir la raíz
## si el nodo está fuera de la room (p. ej. para que entre desde un borde).
@export var grid_size := Vector2i(36, 21)
@export var kill_margin: float = 3.0 # px que se achica la celda de la cabeza para matar al player

var _cells: Array[Vector2i] = [] # el tallo, de la raíz a la cabeza
var _dirs: Array[int] = [] # dirección con la que se llegó a cada celda (-1 en la raíz)
var _body_sprites: Array[Node2D] = [] # tallos y ramitas creados (se borran al reiniciar)
var _timer := 0.0
var _awake := false
var _eating: Node = null # bloque que se está comiendo
var _steps := 0
var _noise := PackedFloat32Array()
var _root_cell := Vector2i.ZERO
var _origin := Vector2i.ZERO # celda de la esquina superior izquierda de la grilla
var _dims := Vector2i.ZERO # celdas de la grilla (la room más lo que haga falta para la raíz)

@onready var _root: Sprite2D = $root
@onready var _head: AnimatedSprite2D = $head


func _enter_tree() -> void:
	add_to_group("player_death_listeners")
	add_to_group("vines") # las puertas con kill_vine la borran al aparecer en ellas


func _ready() -> void:
	# Se alinea a la grilla: la raíz queda centrada en su celda
	_root_cell = Vector2i((global_position / TILE).floor())
	global_position = Vector2(_root_cell * TILE) + Vector2.ONE * TILE / 2.0
	# Un margen de una celda alrededor de la raíz para que pueda salir hacia cualquier lado
	_origin = Vector2i(mini(0, _root_cell.x - 1), mini(0, _root_cell.y - 1))
	var far := Vector2i(maxi(grid_size.x, _root_cell.x + 2), maxi(grid_size.y, _root_cell.y + 2))
	_dims = far - _origin
	_reset()


## Lo llama player.die(): la enredadera vuelve a la raíz y despierta de nuevo.
func on_player_died() -> void:
	_reset()


func _reset() -> void:
	for s in _body_sprites:
		s.queue_free()
	_body_sprites.clear()
	_cells = [_root_cell]
	_dirs = [-1]
	_eating = null
	_awake = false
	_steps = 0
	_timer = start_delay
	_head.visible = false
	_orient(_root, 0)
	# Ruido nuevo en cada intento: el camino serpentea distinto
	_noise.resize(_dims.x * _dims.y)
	for i in _noise.size():
		_noise[i] = randf()


func _physics_process(delta: float) -> void:
	_timer -= delta
	if not _awake:
		if _timer <= 0.0:
			_wake()
		return
	_check_kill()
	if _eating:
		if is_instance_valid(_eating) and _timer > 0.0:
			return
		if is_instance_valid(_eating):
			_eating.vanish()
		_eating = null
		_head.speed_scale = 1.0
		_timer = step_time
	if _timer <= 0.0:
		_grow()
		if not _eating:
			_timer = step_time


func _wake() -> void:
	_awake = true
	_timer = 0.0
	Sfx.play("vine_scream")
	Music.suspend()


## Avanza la cabeza una celda por el camino que le marca el A*.
func _grow() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var target := _player_cell(player)
	var blocks := _block_cells()
	var dir := _plan(target, blocks)
	if dir < 0:
		return # no hay por dónde avanzar: espera
	var cell := _cells[-1] + DIRS[dir]
	_extend(cell, dir)
	if blocks.has(cell):
		_eating = blocks[cell]
		_eating.remove_from_group("blocks") # que nadie más lo cuente
		_timer = eat_time
		_head.speed_scale = 3.0 # mastica rápido
		Sfx.play("vine_eat", randf_range(0.9, 1.05))
	_steps += 1
	if _steps % creep_sound_every == 0:
		Sfx.play("vine_creep", randf_range(0.8, 1.2), -4.0)


## Agrega una celda al tallo: la cabeza vieja pasa a ser tallo (recto o curva).
func _extend(cell: Vector2i, dir: int) -> void:
	var i := _cells.size() - 1
	if i == 0:
		_orient(_root, dir)
	else:
		_add_stem(i, dir)
	_cells.append(cell)
	_dirs.append(dir)
	_head.visible = true
	_head.position = _local(cell)
	_orient(_head, dir)


func _add_stem(i: int, out_dir: int) -> void:
	var in_dir := _dirs[i]
	var s := Sprite2D.new()
	s.position = _local(_cells[i])
	if in_dir == out_dir:
		s.texture = STEM_TEX
		s.rotation = (in_dir % 2) * PI / 2.0
	else:
		# La curva base conecta IZQUIERDA (2) y ABAJO (1); rotar k*90° suma k a cada lado
		s.texture = CORNER_TEX
		var a := (in_dir + 2) % 4 # lado por el que entra
		for k in 4:
			var sides := [(2 + k) % 4, (1 + k) % 4]
			if a in sides and out_dir in sides:
				s.rotation = k * PI / 2.0
				break
	add_child(s)
	_body_sprites.append(s)
	if randf() < sprig_chance:
		_add_sprig(i, [(in_dir + 2) % 4, out_dir])


## Ramita decorativa hacia algún costado libre de la celda i.
func _add_sprig(i: int, used: Array) -> void:
	var free_sides := []
	for d in 4:
		var n := _cells[i] + DIRS[d]
		if d not in used and _in_grid(n) and not _solid_at(n):
			free_sides.append(d)
	if free_sides.is_empty():
		return
	var d: int = free_sides.pick_random()
	var frames := SpriteFrames.new()
	for tex in SPRIG_TEX:
		frames.add_frame(&"default", tex)
	frames.set_animation_speed(&"default", randf_range(1.5, 2.5))
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.z_index = -1 # la base queda tapada por el tallo
	# El sprite nace en su borde izquierdo: se corre media celda hacia el costado
	s.position = _local(_cells[i]) + Vector2(DIRS[d]) * TILE / 2.0
	_orient(s, d)
	s.flip_v = randf() < 0.5
	add_child(s)
	s.play()
	s.frame = randi() % 2
	_body_sprites.append(s)


## Mira hacia `dir`. Hacia la izquierda se espeja en vez de rotar (que no quede patas arriba).
static func _orient(s: Node2D, dir: int) -> void:
	s.rotation = 0.0 if dir == 2 else dir * PI / 2.0
	s.set("flip_h", dir == 2)


func _local(cell: Vector2i) -> Vector2:
	return Vector2((cell - _root_cell) * TILE)


func _player_cell(player: Node2D) -> Vector2i:
	var col := player.get_node_or_null("collider") as Node2D
	var center := col.global_position if col else player.global_position
	return Vector2i((center / TILE).floor())


func _check_kill() -> void:
	if _cells.size() < 2:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("die"):
		return
	var cs := player.get_node_or_null("collider") as CollisionShape2D
	if cs == null:
		return
	var size := (cs.shape as RectangleShape2D).size
	var player_rect := cs.global_transform * Rect2(-size / 2.0, size)
	var head_rect := Rect2(Vector2(_cells[-1] * TILE), Vector2.ONE * TILE).grow(-kill_margin)
	if head_rect.intersects(player_rect):
		player.die()


# --- Grilla ---------------------------------------------------------------

var _solid := PackedByteArray()
var _support := PackedByteArray()


func _in_grid(c: Vector2i) -> bool:
	var l := c - _origin
	return l.x >= 0 and l.y >= 0 and l.x < _dims.x and l.y < _dims.y


func _idx(c: Vector2i) -> int:
	return (c.y - _origin.y) * _dims.x + (c.x - _origin.x)


func _solid_at(c: Vector2i) -> bool:
	return _solid.size() > 0 and _solid[_idx(c)] == 1


## Relee los tiles sólidos de la room (pueden cambiar: el player come piedras)
## y marca las celdas lo bastante cerca de alguno como para que la enredadera se agarre.
func _scan_tiles() -> void:
	var n := _dims.x * _dims.y
	_solid.resize(n)
	_solid.fill(0)
	_support.resize(n)
	_support.fill(0)
	var scene := get_tree().current_scene
	if scene == null:
		return
	for layer: TileMapLayer in scene.find_children("*", "TileMapLayer", true, false):
		if layer.tile_set == null or layer.tile_set.get_physics_layers_count() == 0:
			continue
		for c in layer.get_used_cells():
			var td := layer.get_cell_tile_data(c)
			if td == null or td.get_collision_polygons_count(0) == 0:
				continue # agua y decorado: no son sólidos
			var g := Vector2i((layer.to_global(layer.map_to_local(c)) / TILE).floor())
			if _in_grid(g):
				_solid[_idx(g)] = 1
	for i in n:
		if _solid[i] == 0:
			continue
		var cell := _origin + Vector2i(i % _dims.x, i / _dims.x)
		for dy in range(-cling_range, cling_range + 1):
			for dx in range(-cling_range, cling_range + 1):
				var c := cell + Vector2i(dx, dy)
				if _in_grid(c):
					_support[_idx(c)] = 1


## Bloques verdes del player por celda: { Vector2i: Node }.
func _block_cells() -> Dictionary:
	var out := {}
	for b in get_tree().get_nodes_in_group("blocks"):
		out[Vector2i(((b as Node2D).global_position / TILE).floor())] = b
	return out


# --- A* -------------------------------------------------------------------
# Estado = (celda, dirección con la que se llegó, celdas seguidas en esa dirección).
# Guardar la dirección permite penalizar las rectas largas.

## Devuelve la dirección del primer paso hacia `target`, o -1 si no puede avanzar.
## Si no hay camino hasta el player, va hacia la celda alcanzable más cercana a él.
func _plan(target: Vector2i, blocks: Dictionary) -> int:
	_scan_tiles()
	var runs := max_straight + 2 # 0 = sin dirección (raíz) .. max_straight + 1
	var n := _dims.x * _dims.y * 4 * runs
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var body := {}
	for c in _cells:
		body[c] = true
	var eat_cost := eat_time / step_time

	var head := _cells[-1]
	# Con la cabeza en el aire (p. ej. la raíz puesta lejos de todo) puede crecer
	# colgando por el aire hasta agarrarse de una superficie.
	var air_ok := _support[_idx(head)] == 0
	var head_dir := maxi(_dirs[-1], 0)
	var head_run := 0
	if _dirs[-1] >= 0:
		head_run = 1
		var k := _dirs.size() - 2
		while k > 0 and _dirs[k] == _dirs[-1] and head_run < max_straight + 1:
			head_run += 1
			k -= 1
	var start := _state(head, head_dir, head_run, runs)
	g[start] = 0.0
	var heap := _Heap.new()
	heap.push(_dist(head, target), start)
	var best := start
	var best_h := _dist(head, target)
	var best_g := 0.0

	while not heap.is_empty():
		var s := heap.pop()
		if closed[s]:
			continue
		closed[s] = 1
		var run := s % runs
		var dir := (s / runs) % 4
		var cell := _origin + Vector2i((s / runs / 4) % _dims.x, (s / runs / 4) / _dims.x)
		var h := _dist(cell, target)
		if h < best_h or (h == best_h and g[s] < best_g):
			best = s
			best_h = h
			best_g = g[s]
		if cell == target:
			break
		for nd in 4:
			if run > 0 and nd == (dir + 2) % 4:
				continue # no da media vuelta sobre sí misma
			var nc := cell + DIRS[nd]
			if not _in_grid(nc) or _solid[_idx(nc)] == 1:
				continue
			var is_block := blocks.has(nc)
			if not is_block and not air_ok and _support[_idx(nc)] == 0 and nc != target:
				continue # en el aire, lejos de toda superficie
			var nrun := mini(run + 1, max_straight + 1) if nd == dir and run > 0 else 1
			var cost := 1.0 + _noise[_idx(nc)] * wander
			if nrun > max_straight:
				cost += straight_penalty
			if body.has(nc):
				cost += self_cross_cost
			if is_block:
				cost += eat_cost
			var ns := _state(nc, nd, nrun, runs)
			var ng := g[s] + cost
			if ng < g[ns]:
				g[ns] = ng
				parent[ns] = s
				heap.push(ng + _dist(nc, target), ns)

	if best == start:
		return -1
	# Volver por los padres hasta el primer paso
	var s := best
	while parent[s] != start:
		s = parent[s]
	return (s / runs) % 4


func _state(c: Vector2i, dir: int, run: int, runs: int) -> int:
	return ((_idx(c) * 4) + dir) * runs + run


static func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Cola de prioridad mínima (heap binario) para el A*.
class _Heap:
	var keys := PackedFloat32Array()
	var vals := PackedInt32Array()

	func is_empty() -> bool:
		return vals.is_empty()

	func push(key: float, val: int) -> void:
		keys.append(key)
		vals.append(val)
		var i := vals.size() - 1
		while i > 0:
			var p := (i - 1) / 2
			if keys[p] <= keys[i]:
				break
			_swap(i, p)
			i = p

	func pop() -> int:
		var top := vals[0]
		var last := vals.size() - 1
		_swap(0, last)
		keys.resize(last)
		vals.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < last and keys[l] < keys[m]:
				m = l
			if r < last and keys[r] < keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var k := keys[a]
		keys[a] = keys[b]
		keys[b] = k
		var v := vals[a]
		vals[a] = vals[b]
		vals[b] = v
