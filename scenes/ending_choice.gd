extends CanvasLayer
## Lo que pasa al tocar el corazón: pausa el juego y pregunta si trascender
## (YES: final `transcend`, NO: final `destroy`). Con los 4 fragmentos de la tableta
## no pregunta nada y va directo al mejor final (`awaken`). El corazón sigue latiendo
## de fondo hasta que la pantalla queda en negro y se pasa a Ending.tscn.

const ENDING_SCENE := "res://scenes/Ending.tscn"
const FONT := preload("res://fonts/prstartk.ttf")
const OPTIONS: Array[String] = ["YES", "NO"]
const ENDINGS: Array[StringName] = [&"transcend", &"destroy"]

const INK := Color(0.95, 0.95, 0.97)
const DIM := Color(0.42, 0.43, 0.48)
const ACCENT := Color(1.0, 0.78, 0.42)

@export var dim_alpha: float = 0.82    # opacidad del fondo mientras pregunta (0..1)
@export var dim_time: float = 0.8      # segundos del oscurecido inicial
@export var input_delay: float = 0.6   # segundos sin aceptar teclas tras aparecer la pregunta
@export var leave_time: float = 1.8    # segundos del fundido a negro al elegir
@export var options_gap: float = 96.0  # px entre las dos opciones

var _selected := 0
var _accepting := false
var _leaving := false
var _time := 0.0

@onready var _bg: ColorRect = $bg
@onready var _question: Label = $question
@onready var _ui: Control = $ui


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Heartbeat.process_mode = Node.PROCESS_MODE_ALWAYS # que no se detenga con la pausa
	_ui.draw.connect(_draw_options)
	_bg.modulate.a = 0.0
	_question.modulate.a = 0.0
	_ui.modulate.a = 0.0
	if Global.tablet_piece_count() >= Global.TABLET_PIECE_COUNT:
		_leave(&"awaken")
		return
	var tw := create_tween()
	tw.tween_property(_bg, "modulate:a", dim_alpha, dim_time)
	tw.tween_property(_question, "modulate:a", 1.0, 0.6)
	tw.parallel().tween_property(_ui, "modulate:a", 1.0, 0.6)
	tw.tween_interval(input_delay)
	tw.tween_callback(func(): _accepting = true)


func _exit_tree() -> void:
	Heartbeat.process_mode = Node.PROCESS_MODE_INHERIT


func _process(delta: float) -> void:
	_time += delta
	_ui.queue_redraw()


func _input(event: InputEvent) -> void:
	if not _accepting or _leaving:
		return
	get_viewport().set_input_as_handled()
	if _pressed(event, ["LEFT", "RIGHT", "UP", "DOWN", "ui_left", "ui_right", "ui_up", "ui_down"]):
		_selected = 1 - _selected
		Sfx.play("term_key")
	elif _pressed(event, ["action", "ui_accept"]):
		Sfx.play("term_ok")
		_leave(ENDINGS[_selected])


func _pressed(event: InputEvent, actions: Array) -> bool:
	for a in actions:
		if InputMap.has_action(a) and event.is_action_pressed(a):
			return true
	return false


## Funde a negro y pasa a la escena del final. Ending.tscn saca la pausa al arrancar.
func _leave(ending: StringName) -> void:
	_leaving = true
	Global.ending = ending
	var tw := create_tween()
	tw.tween_property(_bg, "modulate:a", 1.0, leave_time)
	tw.parallel().tween_property(_question, "modulate:a", 0.0, leave_time * 0.5)
	tw.parallel().tween_property(_ui, "modulate:a", 0.0, leave_time * 0.5)
	tw.tween_interval(0.4)
	tw.tween_callback(func():
		get_tree().change_scene_to_file(ENDING_SCENE)
		queue_free())


func _draw_options() -> void:
	var center := Vector2(_ui.size.x / 2.0, _ui.size.y * 0.62)
	for i in OPTIONS.size():
		var pos := center + Vector2((i - 0.5) * options_gap, 0)
		var half := FONT.get_string_size(OPTIONS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x / 2.0
		var sel := i == _selected
		_ui.draw_string(FONT, Vector2(pos.x - half, pos.y).round(), OPTIONS[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, INK if sel else DIM)
		if sel:
			var bob := roundf(sin(_time * 4.0))
			_ui.draw_string(FONT, Vector2(pos.x - half - 16 - bob, pos.y).round(), ">",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ACCENT)
			_ui.draw_string(FONT, Vector2(pos.x + half + 8 + bob, pos.y).round(), "<",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ACCENT)
