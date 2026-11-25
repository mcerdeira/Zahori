extends Area2D

@export var speed: float = 220.0
@export var max_lifetime: float = 4.0
@export var radius: float = 2.5

var direction := 1.0
var shooter: Node = null

var _done := false
var _life := 0.0
@onready var sprite: AnimatedSprite2D = $sprite

func _ready() -> void:
	monitoring = false
	$notifier.screen_exited.connect(queue_free)
	sprite.play(&"default")

func _physics_process(delta: float) -> void:
	if _done:
		return
	var motion := Vector2(direction * speed * delta, 0)
	var hit := _cast(motion)
	if hit.is_empty():
		global_position += motion
	else:
		global_position = hit.position - Vector2(direction * radius, 0)
		_on_hit(hit.collider)
		return
	_life += delta
	if _life >= max_lifetime:
		queue_free()

func _cast(motion: Vector2) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position,
			global_position + motion + Vector2(direction * radius, 0))
	query.collide_with_areas = true
	query.hit_from_inside = true
	var exclude: Array[RID] = [get_rid()]
	for p in get_tree().get_nodes_in_group("player"):
		exclude.append(p.get_rid())
	for i in 8:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}
		var col: Object = hit.collider
		if col is Area2D and not ("interchangeable" in col):
			exclude.append(hit.rid)
			continue
		return hit
	return {}

func _on_hit(target: Node) -> void:
	if _done or target == shooter:
		return
	_done = true
	if target.get("interchangeable") and is_instance_valid(shooter) \
			and shooter.has_method("swap_with"):
		shooter.swap_with(target)
	Sfx.play("pop", randf_range(0.95, 1.1))
	sprite.play(&"pop")
	await sprite.animation_finished
	queue_free()
