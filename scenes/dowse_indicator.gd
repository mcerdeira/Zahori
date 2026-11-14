extends Node2D

## Indicador de la varita zahorí: un ícono de señal (punto + 2 arcos, tipo wifi)
## sobre la cabeza del player. Lo crea y maneja DoorMaze: cuantas más rayitas
## prendidas, más cerca está la puerta correcta, y parpadea junto con el ping.

## Píxeles de cada nivel de señal (x, y), dibujados de abajo hacia arriba.
const DOT := [Vector2i(4, 6)]
const ARC_1 := [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(2, 4), Vector2i(6, 4)]
const ARC_2 := [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0),
		Vector2i(1, 1), Vector2i(7, 1), Vector2i(0, 2), Vector2i(8, 2)]
const SIZE := Vector2i(9, 7) # px del ícono
const COLOR := Color.WHITE
const SHADOW := Color.BLACK # sombra de 1 px abajo a la derecha, para que se lea sobre fondos claros

@export var head_gap: float = 3.0 # px entre la cabeza del player y el ícono

var bars := 0: # rayitas prendidas (0 = nada, 1 = punto, 2 = + arco chico, 3 = + arco grande)
	set(value):
		if value != bars:
			bars = value
			queue_redraw()


func _ready() -> void:
	z_index = 50
	# El sprite del player es de 16 px centrado: la cabeza queda en y = -8
	position = Vector2(-SIZE.x / 2.0, -8.0 - head_gap - SIZE.y).round()


func _draw() -> void:
	var pixels := []
	for level in [DOT, ARC_1, ARC_2].slice(0, bars):
		pixels.append_array(level)
	# Sombra primero y el blanco encima
	for p in pixels:
		draw_rect(Rect2(Vector2(p) + Vector2.ONE, Vector2.ONE), SHADOW)
	for p in pixels:
		draw_rect(Rect2(Vector2(p), Vector2.ONE), COLOR)
