extends CanvasLayer
## Pantalla de pausa con el estilo del monitor de las terminales: CONTINUE / QUIT.
## UP/DOWN eligen, `action` o ENTER confirman; Q o ESC continúan.

signal closed

const OPTIONS: Array[String] = ["CONTINUE", "QUIT"]
const INK := Color(0.55, 0.88, 1, 1)

@export var power_on_time: float = 0.25 # segundos de la animación de encendido
@export var power_off_time: float = 0.2 # segundos de la animación de apagado
@export var led_blink: float = 0.6      # segundos por estado del LED

@onready var dim: ColorRect = $dim
@onready var monitor: Control = $monitor
@onready var screen_rect: TextureRect = $monitor/screen
@onready var viewport: SubViewport = $monitor/screen/viewport
@onready var options_box: VBoxContainer = $monitor/screen/viewport/content/options
@onready var led: ColorRect = $monitor/led

var _selected := 0
var _closing := false
var _labels: Array[Label] = []
var _highlight := StyleBoxFlat.new()


func _ready() -> void:
	get_tree().paused = true
	screen_rect.texture = viewport.get_texture()
	screen_rect.pivot_offset = screen_rect.size / 2.0
	_highlight.bg_color = INK
	_highlight.content_margin_left = 2
	_highlight.content_margin_right = 2
	for option in OPTIONS:
		var l := Label.new()
		l.text = option
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		options_box.add_child(l)
		_labels.append(l)
	_refresh()
	Sfx.play("term_on")

	# Encendido del tubo, igual que la terminal
	dim.modulate.a = 0.0
	monitor.modulate.a = 0.0
	screen_rect.scale = Vector2(1.0, 0.02)
	var tw := create_tween()
	tw.tween_property(dim, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(monitor, "modulate:a", 1.0, 0.12)
	tw.tween_property(screen_rect, "scale:y", 1.0, power_on_time) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	var blink := create_tween().set_loops()
	blink.tween_interval(led_blink)
	blink.tween_callback(func(): led.visible = not led.visible)


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_close()
	elif event.is_action_pressed("UP") or event.is_action_pressed("DOWN"):
		_selected = (_selected + (1 if event.is_action_pressed("DOWN") else -1) + OPTIONS.size()) % OPTIONS.size()
		_refresh()
		Sfx.play("term_key")
	elif event.is_action_pressed("action") or event.is_action_pressed("ui_accept"):
		match OPTIONS[_selected]:
			"CONTINUE":
				_close()
			"QUIT":
				Sfx.play("term_ok")
				get_tree().quit()
	get_viewport().set_input_as_handled()


## La opción elegida va en negativo (fondo cian, letra negra), como la barra de estado.
func _refresh() -> void:
	for i in _labels.size():
		var l := _labels[i]
		if i == _selected:
			l.add_theme_stylebox_override("normal", _highlight)
			l.add_theme_color_override("font_color", Color.BLACK)
		else:
			l.remove_theme_stylebox_override("normal")
			l.remove_theme_color_override("font_color")


## Apaga el monitor y despausa.
func _close() -> void:
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
