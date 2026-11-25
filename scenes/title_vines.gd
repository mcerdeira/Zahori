extends Node2D

var area := Vector2(576, 324)
@export var max_plants: int = 6
@export var initial_plants: int = 3
@export var spawn_interval := Vector2(2.5, 6.0)
@export var grow_speed: float = 16.0
@export var length_range := Vector2(140, 300)
@export var base_width: float = 3.0
@export var leaf_size := Vector2(4, 8)
@export var leaf_spacing: float = 11.0
@export var branch_chance: float = 0.35
@export var bud_chance: float = 0.0
@export var stem_color := Color(0.1, 0.22, 0.17)
@export var leaf_color := Color(0.13, 0.3, 0.2)
@export var bud_color := Color(1.0, 0.75, 0.4)
@export var sway: float = 1.5
@export var hold_time := Vector2(14, 26)
@export var fade_time: float = 5.0
@export var edges: Array[int] = [0, 0, 1, 2, 3]
@export var corners_only: bool = false
@export var prewarm: float = 0.0

class Leaf:
	var idx: int
	var angle: float
	var size: float
	var grow := 0.0
	var color: Color
	var bud := false

class Vine:
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var leaves: Array[Leaf] = []
	var pos: Vector2
	var heading: float
	var target: float
	var length := 0.0
	var max_length: float
	var width0: float
	var depth := 0
	var phase: float
	var freq: float
	var curl_dir: float
	var since_point := 0.0
	var since_leaf := 0.0
	var since_branch := 0.0
	var leaf_side := 1.0
	var growing := true

class Plant:
	var vines: Array[Vine] = []
	var alpha := 1.0
	var hold := 0.0
	var fading := false

var _plants: Array[Plant] = []
var _spawn_timer := 0.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	set_process(false)

func start(size: Vector2) -> void:
	area = size
	_rng.randomize()
	for i in initial_plants:
		_spawn_plant()
		for v in _plants[-1].vines:
			v.length = -_rng.randf_range(0.0, 40.0) * i
	_spawn_timer = _rng.randf_range(spawn_interval.x, spawn_interval.y)
	var t := 0.0
	while t < prewarm:
		_step(1.0 / 30.0)
		t += 1.0 / 30.0
	set_process(true)

func _process(delta: float) -> void:
	_step(delta)
	queue_redraw()

func _step(delta: float) -> void:
	_time += delta
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = _rng.randf_range(spawn_interval.x, spawn_interval.y)
		if _plants.filter(func(p): return not p.fading).size() < max_plants:
			_spawn_plant()

	for plant in _plants.duplicate():
		var any_growing := false
		for v in plant.vines.duplicate():
			if v.growing:
				_grow(plant, v, delta)
				any_growing = true
			for leaf in v.leaves:
				leaf.grow = minf(leaf.grow + delta * 0.6, 1.0)
		if not any_growing and not plant.fading:
			plant.hold -= delta
			if plant.hold <= 0.0:
				plant.fading = true
		if plant.fading:
			plant.alpha -= delta / fade_time
			if plant.alpha <= 0.0:
				_plants.erase(plant)

func _spawn_plant() -> void:
	var edge: int = edges[_rng.randi() % edges.size()]
	var start: Vector2
	var target: float
	var along := _rng.randf()
	if corners_only:
		along = _rng.randf_range(0.0, 0.18) if _rng.randf() < 0.5 else _rng.randf_range(0.82, 1.0)
	match edge:
		0:
			start = Vector2(along * area.x, area.y + 4)
			target = -PI / 2 + _rng.randf_range(-0.45, 0.45)
		1:
			start = Vector2(-4, lerpf(area.y * 0.3, area.y, along))
			target = _rng.randf_range(-0.7, 0.1)
		2:
			start = Vector2(area.x + 4, lerpf(area.y * 0.3, area.y, along))
			target = PI + _rng.randf_range(-0.1, 0.7)
		_:
			start = Vector2(along * area.x, -4)
			target = PI / 2 + _rng.randf_range(-0.35, 0.35)
	var plant := Plant.new()
	plant.hold = _rng.randf_range(hold_time.x, hold_time.y)
	plant.vines.append(_new_vine(start, target, _rng.randf_range(length_range.x, length_range.y),
			base_width * _rng.randf_range(0.8, 1.2), 0))
	_plants.append(plant)

func _new_vine(start: Vector2, target: float, max_length: float, width: float, depth: int) -> Vine:
	var v := Vine.new()
	v.pos = start
	v.heading = target
	v.target = target
	v.max_length = max_length
	v.width0 = width
	v.depth = depth
	v.phase = _rng.randf() * TAU
	v.freq = _rng.randf_range(0.02, 0.045)
	v.curl_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	v.leaf_side = v.curl_dir
	v.points.append(start)
	v.widths.append(width)
	return v

func _width_at(v: Vine, length: float) -> float:
	return v.width0 * lerpf(1.0, 0.22, clampf(length / v.max_length, 0.0, 1.0))

func _grow(plant: Plant, v: Vine, delta: float) -> void:
	var step := grow_speed * delta * (1.0 if v.depth == 0 else 0.8)
	if v.length < 0.0:
		v.length += step
		return
	var k := v.length / v.max_length
	if k > 0.82:
		var radius := lerpf(9.0, 1.6, (k - 0.82) / 0.18)
		v.heading += v.curl_dir * step / radius
	else:
		var wobble := sin(v.length * v.freq + v.phase) * 0.7
		v.heading = lerp_angle(v.heading, v.target + wobble, clampf(delta * 1.5, 0.0, 1.0))
	v.pos += Vector2.from_angle(v.heading) * step
	v.length += step
	v.since_point += step
	v.since_leaf += step
	v.since_branch += step

	if v.since_point >= 3.0:
		v.since_point = 0.0
		v.points.append(v.pos)
		v.widths.append(_width_at(v, v.length))

	if v.since_leaf >= leaf_spacing and k < 0.85:
		v.since_leaf = _rng.randf_range(-3.0, 3.0)
		var leaf := Leaf.new()
		leaf.idx = v.points.size() - 1
		leaf.angle = v.heading + v.leaf_side * _rng.randf_range(0.8, 1.3)
		leaf.size = _rng.randf_range(leaf_size.x, leaf_size.y) * lerpf(1.0, 0.6, k) \
				* (1.0 if v.depth == 0 else 0.8)
		leaf.color = leaf_color.lerp(leaf_color.lightened(0.25), _rng.randf())
		leaf.bud = _rng.randf() < bud_chance
		v.leaves.append(leaf)
		v.leaf_side = -v.leaf_side

	if v.since_branch >= 30.0:
		v.since_branch = 0.0
		if v.depth < 2 and k < 0.6 and _rng.randf() < branch_chance:
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var child := _new_vine(v.pos, v.heading + side * _rng.randf_range(0.6, 1.1),
					(v.max_length - v.length) * _rng.randf_range(0.4, 0.7),
					_width_at(v, v.length) * 0.75, v.depth + 1)
			child.curl_dir = side
			plant.vines.append(child)

	var margin := 40.0
	if v.length >= v.max_length or v.pos.x < -margin or v.pos.y < -margin \
			or v.pos.x > area.x + margin or v.pos.y > area.y + margin:
		v.growing = false

func _sway(p: Vector2) -> Vector2:
	return Vector2(sin(_time * 0.6 + p.y * 0.014 + p.x * 0.006),
			cos(_time * 0.45 + p.x * 0.012) * 0.5) * sway

func _draw() -> void:
	for plant in _plants:
		var a := plant.alpha
		for v in plant.vines:
			var n := v.points.size()
			if n < 1:
				continue
			var stem := Color(stem_color, stem_color.a * a)
			var prev := v.points[0] + _sway(v.points[0])
			for i in range(1, n + (1 if v.growing else 0)):
				var p := (v.points[i] if i < n else v.pos)
				p += _sway(p)
				var w: float = v.widths[mini(i, n - 1)]
				draw_line(prev, p, stem, w)
				if w >= 2.0:
					draw_circle(p, w * 0.5, stem)
				prev = p
			for leaf in v.leaves:
				_draw_leaf(v.points[leaf.idx] + _sway(v.points[leaf.idx]), leaf, a)

func _draw_leaf(base: Vector2, leaf: Leaf, alpha: float) -> void:
	var g := ease(leaf.grow, 0.4)
	var size := leaf.size * g
	if size < 0.5:
		return
	var d := Vector2.from_angle(leaf.angle + sin(_time * 1.3 + leaf.idx) * 0.12)
	var nrm := d.orthogonal()
	var pts := PackedVector2Array()
	const SEG := 6
	for i in SEG + 1:
		var t := float(i) / SEG
		pts.append(base + d * size * t + nrm * size * 0.38 * sin(PI * t))
	for i in range(SEG - 1, 0, -1):
		var t := float(i) / SEG
		pts.append(base + d * size * t - nrm * size * 0.38 * sin(PI * t))
	draw_colored_polygon(pts, Color(leaf.color, leaf.color.a * alpha))
	if leaf.bud:
		var pulse := 0.6 + 0.4 * sin(_time * 2.0 + leaf.idx * 1.7)
		draw_circle(base + d * size, 1.6 * g, Color(bud_color, bud_color.a * alpha * pulse))
