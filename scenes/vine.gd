extends Node2D

const TILE := 16
const DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const STEM_TEX := preload("res://sprites/vine_stem_spr_0.png")
const CORNER_TEX := preload("res://sprites/vine_corner_spr_0.png")
const SPRIG_TEX: Array[Texture2D] = [
	preload("res://sprites/vine_sprig_spr_0.png"),
	preload("res://sprites/vine_sprig_spr_1.png"),
]

@export var start_delay: float = 1.5
@export var step_time: float = 0.17
@export var eat_time: float = 0.9
@export var cling_range: int = 2
@export var max_straight: int = 2
@export var straight_penalty: float = 3.0
@export var wander: float = 3.0
@export var self_cross_cost: float = 6.0
@export var sprig_chance: float = 0.3
@export var creep_sound_every: int = 3
@export var grid_size := Vector2i(36, 21)
@export var kill_margin: float = 3.0

var _cells: Array[Vector2i] = []
var _dirs: Array[int] = []
var _body_sprites: Array[Node2D] = []
var _timer := 0.0
var _awake := false
var _eating: Node = null
var _steps := 0
var _noise := PackedFloat32Array()
var _root_cell := Vector2i.ZERO
var _origin := Vector2i.ZERO
var _dims := Vector2i.ZERO

static var _plan_frame := -1
static var _tiles_version := 0
static var _tile_cache := {}

@onready var _root: Sprite2D = $root
@onready var _head: AnimatedSprite2D = $head

func _enter_tree() -> void:
	add_to_group("vines")

func _ready() -> void:
	_root_cell = Vector2i((global_position / TILE).floor())
	global_position = Vector2(_root_cell * TILE) + Vector2.ONE * TILE / 2.0
	_origin = Vector2i(mini(0, _root_cell.x - 1), mini(0, _root_cell.y - 1))
	var far := Vector2i(maxi(grid_size.x, _root_cell.x + 2), maxi(grid_size.y, _root_cell.y + 2))
	_dims = far - _origin
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
		var frame := Engine.get_physics_frames()
		if _plan_frame == frame:
			return
		_plan_frame = frame
		_grow()
		if not _eating:
			_timer = maxf(_timer, -step_time) + step_time

func _wake() -> void:
	var first := not get_tree().get_nodes_in_group("vines").any(
			func(v): return v != self and v._awake)
	_awake = true
	_timer = 0.0
	if first:
		Sfx.play("vine_scream")
	Music.suspend()

func _is_voice() -> bool:
	for v in get_tree().get_nodes_in_group("vines"):
		if v._awake:
			return v == self
	return false

func _grow() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var target := _player_cell(player)
	var blocks := _block_cells()
	var dir := _plan(target, blocks)
	if dir < 0:
		return
	var cell := _cells[-1] + DIRS[dir]
	_extend(cell, dir)
	if blocks.has(cell):
		_eating = blocks[cell]
		_eating.remove_from_group("blocks")
		_timer = eat_time
		_head.speed_scale = 3.0
		if _is_voice():
			Sfx.play("vine_eat", randf_range(0.9, 1.05))
	_steps += 1
	if _steps % creep_sound_every == 0 and _is_voice():
		Sfx.play("vine_creep", randf_range(0.8, 1.2), -4.0)

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
		s.texture = CORNER_TEX
		var a := (in_dir + 2) % 4
		for k in 4:
			var sides := [(2 + k) % 4, (1 + k) % 4]
			if a in sides and out_dir in sides:
				s.rotation = k * PI / 2.0
				break
	add_child(s)
	_body_sprites.append(s)
	if randf() < sprig_chance:
		_add_sprig(i, [(in_dir + 2) % 4, out_dir])

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
	s.z_index = -1
	s.position = _local(_cells[i]) + Vector2(DIRS[d]) * TILE / 2.0
	_orient(s, d)
	s.flip_v = randf() < 0.5
	add_child(s)
	s.play()
	s.frame = randi() % 2
	_body_sprites.append(s)

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

var _solid := PackedByteArray()
var _support := PackedByteArray()

func _in_grid(c: Vector2i) -> bool:
	var l := c - _origin
	return l.x >= 0 and l.y >= 0 and l.x < _dims.x and l.y < _dims.y

func _idx(c: Vector2i) -> int:
	return (c.y - _origin.y) * _dims.x + (c.x - _origin.x)

func _solid_at(c: Vector2i) -> bool:
	return _solid.size() > 0 and _solid[_idx(c)] == 1

func _scan_tiles() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var layers := scene.find_children("*", "TileMapLayer", true, false)
	for layer: TileMapLayer in layers:
		if not layer.changed.is_connected(_on_tiles_changed):
			layer.changed.connect(_on_tiles_changed)
	var key := [scene.get_instance_id(), _origin, _dims, cling_range]
	var cached: Array = _tile_cache.get(key, [])
	if not cached.is_empty() and cached[0] == _tiles_version:
		_solid = cached[1]
		_support = cached[2]
		return
	_tile_cache = _tile_cache if _tile_cache.size() < 16 else {}
	var n := _dims.x * _dims.y
	_solid = PackedByteArray()
	_solid.resize(n)
	_support = PackedByteArray()
	_support.resize(n)
	for layer: TileMapLayer in layers:
		if layer.tile_set == null or layer.tile_set.get_physics_layers_count() == 0:
			continue
		for c in layer.get_used_cells():
			var td := layer.get_cell_tile_data(c)
			if td == null or td.get_collision_polygons_count(0) == 0:
				continue
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
	_tile_cache[key] = [_tiles_version, _solid, _support]

static func _on_tiles_changed() -> void:
	_tiles_version += 1

func _block_cells() -> Dictionary:
	var out := {}
	for b in get_tree().get_nodes_in_group("blocks"):
		out[Vector2i(((b as Node2D).global_position / TILE).floor())] = b
	return out

func _plan(target: Vector2i, blocks: Dictionary) -> int:
	_scan_tiles()
	if _solid.is_empty():
		return -1
	var solid := _solid
	var support := _support
	var noise := _noise
	var w := _dims.x
	var hgt := _dims.y
	var cells_n := w * hgt
	var runs := max_straight + 2
	var n := cells_n * 4 * runs
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(INF)
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var body := PackedByteArray()
	body.resize(cells_n)
	for c in _cells:
		if _in_grid(c):
			body[_idx(c)] = 1
	var block_at := PackedByteArray()
	block_at.resize(cells_n)
	for c: Vector2i in blocks:
		if _in_grid(c):
			block_at[_idx(c)] = 1
	var eat_cost := eat_time / step_time
	var dxs: Array[int] = [1, 0, -1, 0]
	var dys: Array[int] = [0, 1, 0, -1]
	var tx := target.x - _origin.x
	var ty := target.y - _origin.y

	var head := _cells[-1]
	var air_ok := support[_idx(head)] == 0
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
	var best := start
	var best_h := _dist(head, target)
	var best_g := 0.0
	heap.push(best_h, start)

	while not heap.is_empty():
		var s := heap.pop()
		if closed[s]:
			continue
		closed[s] = 1
		var run := s % runs
		var rest := s / runs
		var dir := rest % 4
		var ci := rest / 4
		var x := ci % w
		var y := ci / w
		var h := absi(x - tx) + absi(y - ty)
		var gs := g[s]
		if h < best_h or (h == best_h and gs < best_g):
			best = s
			best_h = h
			best_g = gs
		if h == 0:
			break
		var back := (dir + 2) % 4
		for nd in 4:
			if run > 0 and nd == back:
				continue
			var nx := x + dxs[nd]
			var ny := y + dys[nd]
			if nx < 0 or ny < 0 or nx >= w or ny >= hgt:
				continue
			var ni := ny * w + nx
			if solid[ni] == 1:
				continue
			var is_block := block_at[ni] == 1
			if not is_block and not air_ok and support[ni] == 0 and (nx != tx or ny != ty):
				continue
			var nrun := mini(run + 1, max_straight + 1) if nd == dir and run > 0 else 1
			var cost := 1.0 + noise[ni] * wander
			if nrun > max_straight:
				cost += straight_penalty
			if body[ni] == 1:
				cost += self_cross_cost
			if is_block:
				cost += eat_cost
			var ns := (ni * 4 + nd) * runs + nrun
			var ng := gs + cost
			if ng < g[ns]:
				g[ns] = ng
				parent[ns] = s
				heap.push(ng + absi(nx - tx) + absi(ny - ty), ns)

	if best == start:
		return -1
	var s := best
	while parent[s] != start:
		s = parent[s]
	return (s / runs) % 4

func _state(c: Vector2i, dir: int, run: int, runs: int) -> int:
	return ((_idx(c) * 4) + dir) * runs + run

static func _dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

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
