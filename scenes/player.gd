extends CharacterBody2D

const BLOCK_SCENE := preload("res://scenes/block.tscn")
const SILHOUETTE_SHADER := preload("res://scenes/silhouette.gdshader")
const EXPLOSION_SCENE := preload("res://scenes/explosion.tscn")
const SHOT_SCENE := preload("res://scenes/teleport_shot.tscn")
const TILE := 16.0
const MAX_SFX_PITCH := 1.6
const EDIBLE_TEXTURE := "res://sprites/block_stone_spr_0.png"

@export var speed: float = 120.0
@export var acceleration: float = 900.0
@export var friction: float = 800.0
@export var max_fall_speed: float = 240.0
@export var build_interval: float = 0.2
@export var vanish_interval: float = 0.35
@export var vanish_last_first: bool = true
@export var reset_sound_gap: float = 0.14
@export var max_reset_sounds: int = 4
@export var step_interval: float = 0.28
@export var land_min_speed: float = 80.0
@export var chomp_interval: float = 0.1
@export var respawn_grace: float = 0.6
@export var death_reload_delay: float = 0.6
@export var shot_offset: Vector2 = Vector2(8, 1)
@export var item_show_time: float = 2.5
@export var item_offset: Vector2 = Vector2(0, -12)
@export var item_fps: float = 4.0
@export var item_dark_time: float = 0.3

enum State { NORMAL, BUILDING, VANISHING, DOOR, DEAD, ITEM }

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var state := State.NORMAL
var blocks: Array[Node] = []
var _vanishing: Array[Node] = []
var _timer := 0.0
var _door_x := 0.0
var _doors_touching := 0
var _step_timer := 0.0
var _boat: Node = null
var _grace := 0.0
var _shot: Node = null
var _shoot_anim := 0.0
var _shot_frames: SpriteFrames = null
var _chomp_timer := 0.0
var _chomp_anim := 0.0

@onready var sprite: AnimatedSprite2D = $sprite
@onready var collider: CollisionShape2D = $collider

var _drowned_door: Node = null

func _enter_tree() -> void:
	add_to_group("player")

func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE_SHADER
	sprite.material = mat

	var door := Global.find_spawn_door(get_tree())
	var altar_respawn = Global.altar_respawn_for_current()
	if Global.has_load_spawn:
		Global.has_load_spawn = false
		global_position = Global.load_spawn
	elif altar_respawn != null and Global.respawn_grace_pending:
		global_position = altar_respawn
	elif door:
		global_position = door.spawn_position(_feet_offset())
		_apply_door_arrival(door)
		if not resists_water() and _in_water():
			_drowned_door = door
			die.call_deferred(door)
	if Global.respawn_grace_pending:
		Global.respawn_grace_pending = false
		_grace = respawn_grace

func _apply_door_arrival(door: Node) -> void:
	match door.facing:
		"L": sprite.flip_h = true
		"R": sprite.flip_h = false
	if door.kill_vine:
		get_tree().call_group("vines", "queue_free")
	if door.with_boat:
		var boat := get_tree().get_first_node_in_group("boat")
		if not boat:
			push_warning("Puerta '%s' con with_boat pero la room no tiene bote" % door.name)
		elif door.use_boat_point:
			boat.place_at(door.boat_point)
		else:
			boat.place_under(global_position + Vector2(0, _feet_offset()))

func _in_water() -> bool:
	for w in get_tree().get_nodes_in_group("water"):
		if w.has_method("get_rect") and w.get_rect().has_point(global_position):
			return true
	return false

func resists_water() -> bool:
	return Global.has_ability(&"hydro")

func die(exit_door: Node = null) -> void:
	if exit_door == null:
		exit_door = _drowned_door
	if state == State.DOOR or state == State.DEAD or (_grace > 0.0 and exit_door == null):
		return
	state = State.DEAD
	Sfx.play("die")
	var fx := EXPLOSION_SCENE.instantiate()
	fx.global_position = global_position
	get_parent().add_child(fx)
	sprite.visible = false
	velocity = Vector2.ZERO
	set_physics_process(false)
	collider.set_deferred("disabled", true)
	for block in blocks:
		if is_instance_valid(block):
			block.queue_free()
	blocks.clear()
	_vanishing.clear()
	await get_tree().create_timer(death_reload_delay).timeout
	Global.respawn_grace_pending = true
	Global.discard_pending_tablet_pieces()
	if is_instance_valid(exit_door):
		exit_door.go_through()
	else:
		get_tree().reload_current_scene()

func _feet_offset() -> float:
	var shape := collider.shape as RectangleShape2D
	return collider.position.y + shape.size.y / 2.0

func set_silhouette(enabled: bool) -> void:
	_doors_touching = maxi(_doors_touching + (1 if enabled else -1), 0)
	(sprite.material as ShaderMaterial).set_shader_parameter("amount", 1.0 if _doors_touching > 0 else 0.0)

func can_interact() -> bool:
	return is_on_floor() and state != State.BUILDING and state != State.DOOR and state != State.DEAD \
			and state != State.ITEM \
			and not _riding_moving_boat() and not _shot_alive()

func can_touch() -> bool:
	return state != State.DOOR and state != State.DEAD and state != State.ITEM

func _shot_alive() -> bool:
	return is_instance_valid(_shot)

func enter_door(door_x: float) -> bool:
	if state == State.BUILDING or state == State.DOOR or state == State.DEAD or state == State.ITEM \
			or not is_on_floor() \
			or _riding_moving_boat() or _shot_alive():
		return false
	state = State.DOOR
	_door_x = door_x
	Sfx.play("door")
	return true

func _physics_process(delta: float) -> void:
	if _grace > 0.0:
		_grace -= delta
		sprite.visible = _grace <= 0.0 or fmod(_grace, 0.12) < 0.06
	if not is_on_floor():
		velocity.y = min(velocity.y + gravity * delta, max_fall_speed)

	var riding := _riding_moving_boat()
	if not riding:
		_update_ability(delta)

	var direction := 0.0
	if state != State.BUILDING and state != State.DOOR and state != State.ITEM and not riding \
			and not _shot_alive():
		direction = Input.get_axis("LEFT", "RIGHT")
	if direction != 0.0 and state == State.NORMAL and _boat \
			and is_instance_valid(_boat) and _boat.launch(int(signf(direction))):
		sprite.flip_h = direction < 0.0
		direction = 0.0
		riding = true
	if riding:
		velocity.x = 0.0
	elif state == State.DOOR:
		_walk_to_door_center(delta)
	elif direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * delta)
		sprite.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	var fall_speed := velocity.y
	var was_on_floor := is_on_floor()
	move_and_slide()
	_boat = _floor_boat()
	if is_on_floor() and not was_on_floor and fall_speed >= land_min_speed:
		Sfx.play("land", randf_range(0.9, 1.1))
	_update_steps(delta)
	_update_animation(direction)

func show_item(frames: Array[Texture2D], start_dark: float = 0.0) -> void:
	if state == State.DEAD or state == State.DOOR:
		return
	state = State.ITEM
	velocity.x = 0.0
	var dark := ColorRect.new()
	dark.top_level = true
	dark.z_as_relative = false
	dark.z_index = 100
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dark.color = Color.BLACK
	dark.position = Vector2(-64, -64)
	dark.size = get_viewport_rect().size + Vector2(128, 128)
	dark.modulate.a = start_dark
	get_parent().add_child(dark)
	var old_z := z_index
	var old_relative := z_as_relative
	z_as_relative = false
	z_index = 101
	create_tween().tween_property(dark, "modulate:a", 1.0, item_dark_time)
	var item_frames := SpriteFrames.new()
	item_frames.set_animation_speed(&"default", item_fps)
	for tex in frames:
		item_frames.add_frame(&"default", tex)
	var item := AnimatedSprite2D.new()
	item.sprite_frames = item_frames
	item.position = item_offset + Vector2(0, 4)
	add_child(item)
	item.play(&"default")
	create_tween().tween_property(item, "position", item_offset, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("item_get")
	await get_tree().create_timer(item_show_time).timeout
	if is_instance_valid(item):
		item.queue_free()
	var tw := create_tween()
	tw.tween_property(dark, "modulate:a", 0.0, item_dark_time)
	await tw.finished
	dark.queue_free()
	z_index = old_z
	z_as_relative = old_relative
	if state == State.ITEM:
		state = State.NORMAL

func _fire_shot() -> void:
	var dir := -1.0 if sprite.flip_h else 1.0
	_shot = SHOT_SCENE.instantiate()
	_shot.direction = dir
	_shot.shooter = self
	_shot.global_position = global_position + Vector2(shot_offset.x * dir, shot_offset.y)
	get_parent().add_child(_shot)
	velocity.x = 0.0
	Sfx.play("shoot", randf_range(0.95, 1.05))
	var frames := sprite.sprite_frames
	_shoot_anim = frames.get_frame_count(&"shoot") / frames.get_animation_speed(&"shoot")
	sprite.play(&"shoot")
	sprite.frame = 0

func swap_with(target: Node2D) -> void:
	var my_feet := global_position + Vector2(0, _feet_offset())
	var their_offset: float = target.feet_offset() if target.has_method("feet_offset") else 0.0
	var their_feet := target.global_position + Vector2(0, their_offset)
	global_position = their_feet - Vector2(0, _feet_offset())
	target.global_position = my_feet - Vector2(0, their_offset)
	velocity = Vector2.ZERO
	if target.has_method("on_swapped"):
		target.on_swapped()
	Sfx.play("teleport")
	_flash_at(my_feet - Vector2(0, _feet_offset()))
	_flash_at(global_position)
	get_tree().call_group("doors", "rearm")

func _flash_at(pos: Vector2) -> void:
	if _shot_frames == null:
		var tmp := SHOT_SCENE.instantiate()
		_shot_frames = (tmp.get_node("sprite") as AnimatedSprite2D).sprite_frames
		tmp.free()
	var fx := AnimatedSprite2D.new()
	fx.sprite_frames = _shot_frames
	fx.global_position = pos
	get_parent().add_child(fx)
	fx.play(&"pop")
	fx.animation_finished.connect(fx.queue_free)

func _floor_boat() -> Node:
	if not is_on_floor():
		return null
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().dot(up_direction) < 0.7:
			continue
		var other := col.get_collider()
		if other and other.has_method("launch"):
			return other
	return null

func floor_boat() -> Node:
	return _boat if is_instance_valid(_boat) else null

func _riding_moving_boat() -> bool:
	return _boat != null and is_instance_valid(_boat) and _boat.is_moving()

func _update_steps(delta: float) -> void:
	if not is_on_floor() or absf(velocity.x) < speed * 0.3:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		Sfx.play("step", randf_range(0.85, 1.15))
		_step_timer = step_interval

func _walk_to_door_center(delta: float) -> void:
	var dx := _door_x - global_position.x
	if absf(dx) < 0.5:
		velocity.x = 0.0
		return
	velocity.x = signf(dx) * minf(speed * 0.5, absf(dx) / delta)
	sprite.flip_h = dx < 0.0

func _update_ability(delta: float) -> void:
	_chomp_timer -= delta
	_chomp_anim -= delta
	_shoot_anim -= delta
	if state == State.NORMAL and Input.is_action_just_pressed("shoot") and is_on_floor() \
			and Global.has_ability(&"teleport") and not _shot_alive():
		_fire_shot()
	if state != State.DOOR and state != State.ITEM and _chomp_timer <= 0.0 and Global.has_ability(&"eat"):
		if _chomp_walls():
			_chomp_timer = chomp_interval
	match state:
		State.NORMAL:
			if Input.is_action_just_pressed("action") and is_on_floor() \
					and Global.has_ability(&"blocks") and not _shot_alive():
				state = State.BUILDING
				velocity.x = 0.0
				_timer = 0.0
			elif is_on_floor() and _chomp_timer <= 0.0 and Global.has_ability(&"eat"):
				if _chomp():
					_chomp_timer = chomp_interval
		State.BUILDING:
			if not Input.is_action_pressed("action"):
				state = State.VANISHING
				_timer = 0.0
			else:
				_timer -= delta
				if _timer <= 0.0 and (blocks.size() < Global.max_blocks \
						or Global.has_ability(&"reach")):
					_spawn_block()
					_timer = build_interval
		State.VANISHING:
			_vanishing = _vanishing.filter(func(b): return is_instance_valid(b))
			if _on_foreign_floor():
				_reset_blocks()
				return
			if blocks.is_empty():
				if _vanishing.is_empty():
					state = State.NORMAL
				return
			_timer -= delta
			if _timer <= 0.0:
				var block: Node = blocks.pop_back() if vanish_last_first else blocks.pop_front()
				if is_instance_valid(block):
					block.vanish()
					_vanishing.append(block)
					Sfx.play("vanish", minf(1.0 + 0.12 * blocks.size(), MAX_SFX_PITCH))
				_timer = vanish_interval

func _on_foreign_floor() -> bool:
	if not is_on_floor():
		return false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().dot(up_direction) < 0.7:
			continue
		var other := col.get_collider()
		if other not in blocks and other not in _vanishing:
			return true
	return false

func _reset_blocks() -> void:
	var sounds := mini(blocks.size(), max_reset_sounds)
	for i in sounds:
		var pitch := minf(1.0 + 0.12 * (sounds - 1 - i), MAX_SFX_PITCH)
		get_tree().create_timer(reset_sound_gap * i).timeout.connect(Sfx.play.bind("vanish", pitch))
	for block in blocks:
		if is_instance_valid(block):
			block.vanish()
	blocks.clear()
	_vanishing.clear()
	state = State.NORMAL

func _chomp() -> bool:
	var below := global_position + Vector2(collider.position.x, _feet_offset() + TILE / 2.0)
	for i in get_slide_collision_count():
		var layer := get_slide_collision(i).get_collider() as TileMapLayer
		if layer == null:
			continue
		var cell := layer.local_to_map(layer.to_local(below))
		if not _is_edible(layer, cell):
			continue
		_eat_cell(layer, cell)
		var target_x := layer.to_global(layer.map_to_local(cell)).x - collider.position.x
		if not test_move(global_transform.translated(Vector2(0, -1)), Vector2(target_x - global_position.x, 0)):
			global_position.x = target_x
		velocity.x = 0.0
		return true
	return false

func _chomp_walls() -> bool:
	var ate := false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if absf(col.get_normal().dot(up_direction)) >= 0.7:
			continue
		if _chomp_collision(col):
			ate = true
	return ate

func _chomp_collision(col: KinematicCollision2D) -> bool:
	var layer := col.get_collider() as TileMapLayer
	if layer == null:
		return false
	var point := col.get_position() - col.get_normal()
	var cell := layer.local_to_map(layer.to_local(point))
	if not _is_edible(layer, cell):
		return false
	_eat_cell(layer, cell)
	return true

func _eat_cell(layer: TileMapLayer, cell: Vector2i) -> void:
	layer.erase_cell(cell)
	Sfx.play("chomp", randf_range(0.9, 1.1))
	var frames := sprite.sprite_frames
	_chomp_anim = frames.get_frame_count(&"chomp") / frames.get_animation_speed(&"chomp")
	sprite.play(&"chomp")
	sprite.frame = 0

static func _is_edible(layer: TileMapLayer, cell: Vector2i) -> bool:
	var source_id := layer.get_cell_source_id(cell)
	if source_id < 0:
		return false
	var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
	return source != null and source.texture != null \
			and source.texture.resource_path == EDIBLE_TEXTURE

func _spawn_block() -> void:
	var ceiling := KinematicCollision2D.new()
	if test_move(global_transform, Vector2(0, -TILE), ceiling):
		if Global.has_ability(&"eat") and _chomp_collision(ceiling):
			_chomp_timer = chomp_interval
		return

	var feet_offset := _feet_offset()
	var feet_y := snappedf(global_position.y + feet_offset, TILE)

	var block_x := floorf(global_position.x / TILE) * TILE + TILE / 2.0
	var target_x := block_x - collider.position.x
	if not test_move(global_transform, Vector2(target_x - global_position.x, -TILE)):
		global_position.x = target_x

	global_position.y = feet_y - TILE - feet_offset
	velocity.y = 0.0

	var block := BLOCK_SCENE.instantiate()
	block.global_position = Vector2(block_x, feet_y - TILE / 2.0)
	get_parent().add_child(block)
	blocks.append(block)
	Sfx.play("block", minf(1.0 + 0.15 * (blocks.size() - 1), MAX_SFX_PITCH))

func _update_animation(direction: float) -> void:
	if state == State.ITEM:
		sprite.play("itemget")
	elif state == State.BUILDING:
		sprite.play("build")
	elif state == State.DOOR:
		sprite.play("walk")
	elif _chomp_anim > 0.0:
		sprite.play("chomp")
	elif _shoot_anim > 0.0:
		sprite.play("shoot")
	elif not is_on_floor():
		sprite.play("fall")
	elif direction != 0.0:
		sprite.play("walk")
	else:
		sprite.play("default")
