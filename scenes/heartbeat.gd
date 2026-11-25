@tool
extends Node2D

@export_range(0.0, 1.0, 0.01) var intensity: float = 0.5:
	set(value):
		intensity = clampf(value, 0.0, 1.0)
		queue_redraw()
@export var bpm_min: float = 48.0
@export var bpm_max: float = 112.0
@export var volume_min_db: float = -8.0
@export var volume_max_db: float = 4.0
@export var shake_px: float = 3.0

var _fade: Tween

func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		Heartbeat.add_source(self)

func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		Heartbeat.remove_source(self)

func fade_to(value: float, time: float) -> void:
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "intensity", clampf(value, 0.0, 1.0), time)

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_circle(Vector2.ZERO, 8.0, Color(0.58, 0.23, 0.23, 0.6))
	draw_circle(Vector2.ZERO, 1.0 + 7.0 * intensity, Color(0.9, 0.0, 0.0))
