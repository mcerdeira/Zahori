extends Node2D

const DOT := [Vector2i(4, 6)]
const ARC_1 := [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(2, 4), Vector2i(6, 4)]
const ARC_2 := [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0),
		Vector2i(1, 1), Vector2i(7, 1), Vector2i(0, 2), Vector2i(8, 2)]
const SIZE := Vector2i(9, 7)
const COLOR := Color.WHITE
const SHADOW := Color.BLACK

@export var head_gap: float = 3.0

var bars := 0:
	set(value):
		if value != bars:
			bars = value
			queue_redraw()

func _ready() -> void:
	z_index = 50
	position = Vector2(-SIZE.x / 2.0, -8.0 - head_gap - SIZE.y).round()

func _draw() -> void:
	var pixels := []
	for level in [DOT, ARC_1, ARC_2].slice(0, bars):
		pixels.append_array(level)
	for p in pixels:
		draw_rect(Rect2(Vector2(p) + Vector2.ONE, Vector2.ONE), SHADOW)
	for p in pixels:
		draw_rect(Rect2(Vector2(p), Vector2.ONE), COLOR)
