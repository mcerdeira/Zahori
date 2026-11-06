extends CanvasLayer
## Monitor de terminal que abre el altar. Pausa el juego mientras está abierto
## y se cierra con ESC (ui_cancel). Con `action` o ENTER se saltea el tipeo del sistema.
## La pantalla vive en un SubViewport (para el shader CRT), así que el input
## de teclado se le reenvía a mano.

signal closed
## El jugador descifró el glifo del altar.
signal solved(altar_number: int)

@export var power_on_time: float = 0.25 # segundos de la animación de encendido
@export var power_off_time: float = 0.2 # segundos de la animación de apagado
@export var led_blink: float = 0.6      # segundos por estado del LED

## Lo setea el altar antes de agregar la terminal al árbol.
var altar_number := 1

@onready var dim: ColorRect = $dim
@onready var monitor: Control = $monitor
@onready var screen_rect: TextureRect = $monitor/screen
@onready var viewport: SubViewport = $monitor/screen/viewport
@onready var screen: Control = $monitor/screen/viewport/content
@onready var led: ColorRect = $monitor/led

var _closing := false


func _enter_tree() -> void:
	# Antes del _ready de la pantalla, que arma la barra de estado con el número
	$monitor/screen/viewport/content.altar_number = altar_number


func _ready() -> void:
	get_tree().paused = true
	screen_rect.texture = viewport.get_texture()
	screen_rect.pivot_offset = screen_rect.size / 2.0
	screen.solved.connect(func(): solved.emit(altar_number))
	Sfx.play("term_on")

	# Encendido del tubo: aparece una línea horizontal que se abre hacia arriba y abajo
	dim.modulate.a = 0.0
	monitor.modulate.a = 0.0
	screen_rect.scale = Vector2(1.0, 0.02)
	var tw := create_tween()
	tw.tween_property(dim, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(monitor, "modulate:a", 1.0, 0.12)
	tw.tween_property(screen_rect, "scale:y", 1.0, power_on_time) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_callback(screen.boot)

	var blink := create_tween().set_loops()
	blink.tween_interval(led_blink)
	blink.tween_callback(func(): led.visible = not led.visible)


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
	elif screen.is_busy():
		# Mientras el sistema escribe el teclado no tipea; `action` o ENTER saltean
		if event.is_action_pressed("action") or event.is_action_pressed("ui_accept"):
			screen.skip()
	else:
		viewport.push_input(event)
	get_viewport().set_input_as_handled()


## Apaga el monitor (se colapsa a una línea y después a un punto) y despausa.
func close() -> void:
	_closing = true
	Sfx.play("term_off")
	var tw := create_tween()
	tw.tween_property(screen_rect, "scale:y", 0.02, power_off_time * 0.6)
	tw.tween_property(screen_rect, "scale:x", 0.0, power_off_time * 0.4)
	tw.tween_property(dim, "modulate:a", 0.0, 0.1)
	tw.parallel().tween_property(monitor, "modulate:a", 0.0, 0.1)
	tw.tween_callback(func():
		get_tree().paused = false
		closed.emit()
		queue_free())
