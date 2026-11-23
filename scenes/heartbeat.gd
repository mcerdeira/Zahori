@tool
extends Node2D

## Hace latir la room: sonido y mini sacudida de cámara, sincronizados por el autoload Heartbeat.
## No se ve en el juego; en el editor se muestra como un marcador rojo.

## Fuerza del latido: volumen, sacudida y velocidad. 0 = no se oye ni sacude.
@export_range(0.0, 1.0, 0.01) var intensity: float = 0.5:
	set(value):
		intensity = clampf(value, 0.0, 1.0)
		queue_redraw()
@export var bpm_min: float = 48.0 # pulsaciones por minuto con intensidad 0
@export var bpm_max: float = 112.0 # pulsaciones por minuto con intensidad 1
@export var volume_min_db: float = -8.0 # dB con intensidad casi 0
@export var volume_max_db: float = 4.0 # dB con intensidad 1
@export var shake_px: float = 3.0 # px de sacudida con intensidad 1 (0 = sin sacudida)

var _fade: Tween


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		Heartbeat.add_source(self)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		Heartbeat.remove_source(self)


## Lleva la intensidad a `value` en `time` segundos (para graduarla durante la room).
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
