extends Node2D
## Chispas del título: brasas sueltas que suben despacio titilando y, cada
## tanto, un chisporroteo en un punto al azar. Se dibujan como píxeles con
## blend aditivo (lo pone la escena) y un halo tenue.

var area := Vector2(576, 324) # lo pone title.gd con start()
@export var ambient_rate: float = 5.0            # brasas sueltas por segundo
@export var burst_interval := Vector2(1.2, 3.5)  # segundos entre chisporroteos
@export var burst_count := Vector2i(5, 12)       # chispas por chisporroteo
@export var colors: Array[Color] = [
	Color(1.0, 0.78, 0.42), Color(1.0, 0.62, 0.3), Color(1.0, 0.9, 0.65),
	Color(0.55, 0.88, 1.0), # alguna cian, como la tinta de los altares
]


class Spark:
	var pos: Vector2
	var vel: Vector2
	var life: float
	var max_life: float
	var color: Color
	var size: float
	var drag: float
	var gravity: float
	var wobble: float
	var phase: float


var _sparks: Array[Spark] = []
var _ambient_acc := 0.0
var _burst_timer := 1.0
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_process(false)


func start(size: Vector2) -> void:
	area = size
	_rng.randomize()
	set_process(true)


func _pick_color() -> Color:
	# La cian es rara: 1 de cada 8
	if _rng.randf() < 0.12:
		return colors[-1]
	return colors[_rng.randi() % (colors.size() - 1)]


func _process(delta: float) -> void:
	_time += delta
	_ambient_acc += ambient_rate * delta
	while _ambient_acc >= 1.0:
		_ambient_acc -= 1.0
		_spawn_ember()
	_burst_timer -= delta
	if _burst_timer <= 0.0:
		_burst_timer = _rng.randf_range(burst_interval.x, burst_interval.y)
		burst(Vector2(_rng.randf_range(0.08, 0.92) * area.x, _rng.randf_range(0.25, 0.95) * area.y),
				_rng.randi_range(burst_count.x, burst_count.y))

	for s in _sparks.duplicate():
		s.life -= delta
		if s.life <= 0.0:
			_sparks.erase(s)
			continue
		s.vel *= 1.0 / (1.0 + s.drag * delta)
		s.vel.y += s.gravity * delta
		s.pos += (s.vel + Vector2(sin(_time * 2.0 + s.phase) * s.wobble, 0.0)) * delta
	queue_redraw()


## Brasa suelta: nace abajo y sube despacio, meciéndose.
func _spawn_ember() -> void:
	var s := Spark.new()
	s.pos = Vector2(_rng.randf() * area.x, _rng.randf_range(0.4, 1.05) * area.y)
	s.vel = Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-22, -7))
	s.max_life = _rng.randf_range(2.0, 5.0)
	s.life = s.max_life
	s.color = _pick_color()
	s.size = 1.0 if _rng.randf() < 0.8 else 2.0
	s.drag = 0.0
	s.gravity = -2.0
	s.wobble = _rng.randf_range(3, 10)
	s.phase = _rng.randf() * TAU
	_sparks.append(s)


## Chisporroteo: `count` chispas que saltan desde `at` y caen apagándose.
func burst(at: Vector2, count: int) -> void:
	var color := _pick_color()
	for i in count:
		var s := Spark.new()
		s.pos = at
		s.vel = Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(15, 70) + Vector2(0, -15)
		s.max_life = _rng.randf_range(0.35, 1.1)
		s.life = s.max_life
		s.color = color.lerp(Color.WHITE, _rng.randf() * 0.3)
		s.size = 1.0
		s.drag = 2.5
		s.gravity = 40.0
		s.wobble = 0.0
		s.phase = _rng.randf() * TAU
		_sparks.append(s)


func _draw() -> void:
	for s in _sparks:
		var k := s.life / s.max_life
		# Entra rápido, se apaga lento, y titila
		var a := clampf((1.0 - k) * 8.0, 0.0, 1.0) * k
		a *= 0.55 + 0.45 * sin(_time * 23.0 + s.phase * 7.0)
		var p := s.pos.round()
		draw_rect(Rect2(p - Vector2.ONE, Vector2.ONE * (s.size + 2)), Color(s.color, a * 0.18))
		draw_rect(Rect2(p - Vector2.ONE * 2, Vector2.ONE * (s.size + 4)), Color(s.color, a * 0.06))
		draw_rect(Rect2(p, Vector2.ONE * s.size), Color(s.color, a))
