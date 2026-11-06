class_name GlyphView
extends Control
## Cuadro que dibuja un glifo: varias letras superpuestas en el mismo lugar,
## cada una hecha con trazos finos (fuente vectorial propia en una grilla de
## 4x6). Con trazos de 1 px las superposiciones se siguen leyendo como líneas
## en vez de empastarse como con una fuente de bloques.

## Trazos de cada letra: lista de polilíneas en la grilla (x 0..4, y 0..6).
const STROKES := {
	"A": [[Vector2(0, 6), Vector2(2, 0), Vector2(4, 6)], [Vector2(1, 3), Vector2(3, 3)]],
	"B": [[Vector2(0, 0), Vector2(0, 6), Vector2(3, 6), Vector2(4, 5), Vector2(4, 4), Vector2(3, 3), Vector2(0, 3)],
		[Vector2(0, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 2), Vector2(3, 3)]],
	"C": [[Vector2(4, 1), Vector2(3, 0), Vector2(1, 0), Vector2(0, 1), Vector2(0, 5), Vector2(1, 6), Vector2(3, 6), Vector2(4, 5)]],
	"D": [[Vector2(0, 0), Vector2(0, 6), Vector2(2, 6), Vector2(4, 4), Vector2(4, 2), Vector2(2, 0), Vector2(0, 0)]],
	"E": [[Vector2(4, 0), Vector2(0, 0), Vector2(0, 6), Vector2(4, 6)], [Vector2(0, 3), Vector2(3, 3)]],
	"F": [[Vector2(4, 0), Vector2(0, 0), Vector2(0, 6)], [Vector2(0, 3), Vector2(3, 3)]],
	"G": [[Vector2(4, 1), Vector2(3, 0), Vector2(1, 0), Vector2(0, 1), Vector2(0, 5), Vector2(1, 6), Vector2(3, 6), Vector2(4, 5), Vector2(4, 3), Vector2(2, 3)]],
	"H": [[Vector2(0, 0), Vector2(0, 6)], [Vector2(4, 0), Vector2(4, 6)], [Vector2(0, 3), Vector2(4, 3)]],
	"I": [[Vector2(1, 0), Vector2(3, 0)], [Vector2(2, 0), Vector2(2, 6)], [Vector2(1, 6), Vector2(3, 6)]],
	"J": [[Vector2(4, 0), Vector2(4, 5), Vector2(3, 6), Vector2(1, 6), Vector2(0, 5)]],
	"K": [[Vector2(0, 0), Vector2(0, 6)], [Vector2(4, 0), Vector2(0, 4)], [Vector2(1, 3), Vector2(4, 6)]],
	"L": [[Vector2(0, 0), Vector2(0, 6), Vector2(4, 6)]],
	"M": [[Vector2(0, 6), Vector2(0, 0), Vector2(2, 3), Vector2(4, 0), Vector2(4, 6)]],
	"N": [[Vector2(0, 6), Vector2(0, 0), Vector2(4, 6), Vector2(4, 0)]],
	"O": [[Vector2(1, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 5), Vector2(3, 6), Vector2(1, 6), Vector2(0, 5), Vector2(0, 1), Vector2(1, 0)]],
	"P": [[Vector2(0, 6), Vector2(0, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 2), Vector2(3, 3), Vector2(0, 3)]],
	"Q": [[Vector2(1, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 5), Vector2(3, 6), Vector2(1, 6), Vector2(0, 5), Vector2(0, 1), Vector2(1, 0)],
		[Vector2(2, 4), Vector2(4, 6)]],
	"R": [[Vector2(0, 6), Vector2(0, 0), Vector2(3, 0), Vector2(4, 1), Vector2(4, 2), Vector2(3, 3), Vector2(0, 3)],
		[Vector2(2, 3), Vector2(4, 6)]],
	"S": [[Vector2(4, 1), Vector2(3, 0), Vector2(1, 0), Vector2(0, 1), Vector2(0, 2), Vector2(1, 3), Vector2(3, 3), Vector2(4, 4), Vector2(4, 5), Vector2(3, 6), Vector2(1, 6), Vector2(0, 5)]],
	"T": [[Vector2(0, 0), Vector2(4, 0)], [Vector2(2, 0), Vector2(2, 6)]],
	"U": [[Vector2(0, 0), Vector2(0, 5), Vector2(1, 6), Vector2(3, 6), Vector2(4, 5), Vector2(4, 0)]],
	"V": [[Vector2(0, 0), Vector2(2, 6), Vector2(4, 0)]],
	"W": [[Vector2(0, 0), Vector2(1, 6), Vector2(2, 3), Vector2(3, 6), Vector2(4, 0)]],
	"X": [[Vector2(0, 0), Vector2(4, 6)], [Vector2(4, 0), Vector2(0, 6)]],
	"Y": [[Vector2(0, 0), Vector2(2, 3), Vector2(4, 0)], [Vector2(2, 3), Vector2(2, 6)]],
	"Z": [[Vector2(0, 0), Vector2(4, 0), Vector2(0, 6), Vector2(4, 6)]],
}
const GRID := Vector2(4, 6)

@export var unit: int = 8                  # px por celda de la grilla (la letra mide 4x6 celdas)
@export var margin: int = 4                # px entre la letra y el marco
@export var line_width: float = 1.0        # px de grosor del trazo (1 = línea fina sin antialias)
@export var color := Color(0.55, 0.88, 1.0)

## Letras a superponer (mayúsculas A-Z; el resto se ignora).
var letters := "":
	set(value):
		letters = value
		queue_redraw()
## Opacidad del marco (se apaga al desplegar).
var frame_alpha := 1.0:
	set(value):
		frame_alpha = value
		queue_redraw()
## 0 = letras superpuestas, 1 = acomodadas en fila (ver unfold_row).
var unfold := 0.0:
	set(value):
		unfold = value
		queue_redraw()

var _row: Array[Vector2] = [] # posición de cada letra en la fila desplegada
var _row_scale := 1.0


func _ready() -> void:
	custom_minimum_size = GRID * unit + Vector2.ONE * (margin * 2 + 1)


## Separa las letras y las acomoda en fila empezando en left_x (coordenadas
## locales; puede salirse del cuadro), achicadas a row_scale.
func unfold_row(left_x: float, row_scale: float, duration: float) -> Tween:
	var u := unit * row_scale
	var step := (GRID.x + 1) * u
	var start := left_x
	var y := (size.y - GRID.y * u) / 2.0
	_row.clear()
	for i in letters.length():
		_row.append(Vector2(start + i * step, y).round())
	_row_scale = row_scale
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "frame_alpha", 0.0, duration * 0.5)
	tw.tween_property(self, "unfold", 1.0, duration)
	return tw


func _draw() -> void:
	if frame_alpha > 0.0:
		var frame := Color(color, color.a * frame_alpha)
		draw_rect(Rect2(Vector2.ONE * 0.5, size - Vector2.ONE), frame, false, -1.0)

	var center := ((size - GRID * unit) / 2.0).floor()
	for i in letters.length():
		var strokes: Array = STROKES.get(letters[i], [])
		var origin := center
		var u := float(unit)
		if unfold > 0.0 and i < _row.size():
			origin = center.lerp(_row[i], unfold)
			u = lerpf(unit, unit * _row_scale, unfold)
		for stroke in strokes:
			var points := PackedVector2Array()
			for p in stroke:
				# Centro del pixel para que las líneas de 1 px queden nítidas
				points.append((origin + p * u).round() + Vector2.ONE * 0.5)
			draw_polyline(points, color, -1.0 if line_width <= 1.0 else line_width)
