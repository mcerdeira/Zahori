extends CanvasLayer
## Pantalla de opciones: volumen (Master / Music / SFX), pantalla completa y
## remapeo de teclas. Se dibuja entera a mano (`_draw` del nodo `canvas`) con la
## fuente de la terminal. Funciona aunque el juego esté pausado.
## UP/DOWN eligen, LEFT/RIGHT cambian valores, `action`/ENTER confirman,
## ESC o `pause` vuelven atrás.

signal closed

enum Page { MAIN, CONTROLS }

const FONT := preload("res://fonts/prstartk.ttf")
const MAIN_ROWS: Array[String] = ["MASTER", "MUSIC", "SFX", "DISPLAY", "CONTROLS", "BACK"]
## Fila del menú -> bus de audio que regula.
const BUS_OF := {"MASTER": &"Master", "MUSIC": &"Music", "SFX": &"SFX"}

const INK := Color(0.92, 0.92, 0.95)
const DIM := Color(0.45, 0.46, 0.52)
const ACCENT := Color(1.0, 0.78, 0.42) # mismo dorado que las chispas del título
const PANEL_BG := Color(0.02, 0.025, 0.035, 0.92)
const PANEL_BORDER := Color(0.32, 0.33, 0.4)

@export var volume_step: float = 0.1 # cuánto cambia un slider por pulsación (0..1)
@export var fade_time: float = 0.15  # segundos del fade de entrada/salida

@onready var canvas: Control = $canvas

var _page := Page.MAIN
var _row := 0
var _col := 0           # en CONTROLS: 0 tecla primaria, 1 alternativa
var _waiting_key := false
var _closing := false
var _blink := 0.0


func _ready() -> void:
	canvas.draw.connect(_draw_menu)
	Settings.changed.connect(canvas.queue_redraw)
	canvas.modulate.a = 0.0
	create_tween().tween_property(canvas, "modulate:a", 1.0, fade_time)


func _process(delta: float) -> void:
	_blink += delta
	if _waiting_key:
		canvas.queue_redraw()


# --- Input ----------------------------------------------------------------------

func _pressed(event: InputEvent, actions: Array, echo := false) -> bool:
	for a in actions:
		if InputMap.has_action(a) and event.is_action_pressed(a, echo):
			return true
	return false


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if _waiting_key:
		_capture_key(event)
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey or event is InputEventJoypadButton):
		return
	var handled := true
	if _pressed(event, ["ui_cancel", "pause"]):
		_back()
	elif _pressed(event, ["UP", "ui_up"], true):
		_move(-1)
	elif _pressed(event, ["DOWN", "ui_down"], true):
		_move(1)
	elif _pressed(event, ["LEFT", "ui_left"], true):
		_side(-1)
	elif _pressed(event, ["RIGHT", "ui_right"], true):
		_side(1)
	elif _pressed(event, ["action", "ui_accept"]):
		_confirm()
	elif _page == Page.CONTROLS and event is InputEventKey and event.pressed \
			and (event.physical_keycode == KEY_DELETE or event.physical_keycode == KEY_BACKSPACE):
		if _row < Settings.ACTIONS.size():
			Settings.clear_key(Settings.ACTIONS[_row], _col)
			Sfx.play("term_err")
	else:
		handled = false
	if handled:
		canvas.queue_redraw()
	get_viewport().set_input_as_handled()


func _row_count() -> int:
	return MAIN_ROWS.size() if _page == Page.MAIN else Settings.ACTIONS.size() + 2


func _move(dir: int) -> void:
	_row = (_row + dir + _row_count()) % _row_count()
	Sfx.play("term_key")


func _side(dir: int) -> void:
	if _page == Page.CONTROLS:
		if _row < Settings.ACTIONS.size():
			_col = clampi(_col + dir, 0, 1)
			Sfx.play("term_key")
		return
	match MAIN_ROWS[_row]:
		"MASTER", "MUSIC", "SFX":
			var bus: StringName = BUS_OF[MAIN_ROWS[_row]]
			var v: float = Settings.volumes[bus]
			Settings.set_volume(bus, snappedf(v + dir * volume_step, volume_step))
			Sfx.play("term_key")
		"DISPLAY":
			Settings.set_fullscreen(not Settings.fullscreen)
			Sfx.play("term_key")


func _confirm() -> void:
	if _page == Page.MAIN:
		match MAIN_ROWS[_row]:
			"DISPLAY":
				Settings.set_fullscreen(not Settings.fullscreen)
				Sfx.play("term_ok")
			"CONTROLS":
				_page = Page.CONTROLS
				_row = 0
				_col = 0
				Sfx.play("term_ok")
			"BACK":
				_back()
		return
	var n := Settings.ACTIONS.size()
	if _row < n:
		_waiting_key = true
		_blink = 0.0
		Sfx.play("term_on")
	elif _row == n:
		Settings.reset_keys()
		Sfx.play("term_ok")
	else:
		_back()


func _capture_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = event.physical_keycode
	if key == KEY_NONE:
		key = event.keycode
	_waiting_key = false
	if key == KEY_ESCAPE:
		Sfx.play("term_off")
	elif key in Settings.RESERVED_KEYS:
		Sfx.play("term_err")
	else:
		Settings.bind_key(Settings.ACTIONS[_row], _col, key)
		Sfx.play("term_ok")
	canvas.queue_redraw()


func _back() -> void:
	if _page == Page.CONTROLS:
		_page = Page.MAIN
		_row = MAIN_ROWS.find("CONTROLS")
		Sfx.play("term_off")
		return
	_closing = true
	Sfx.play("term_off")
	var tw := create_tween()
	tw.tween_property(canvas, "modulate:a", 0.0, fade_time)
	tw.tween_callback(func():
		closed.emit()
		queue_free())


# --- Dibujo ---------------------------------------------------------------------

func _text(pos: Vector2, s: String, color: Color, size := 8,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	canvas.draw_string(FONT, pos.round(), s, align, width, size, color)


func _draw_menu() -> void:
	var view := canvas.size
	var panel := Rect2(Vector2.ZERO, Vector2(352, 248))
	panel.position = ((view - panel.size) / 2.0).round()
	canvas.draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.55))
	canvas.draw_rect(panel, PANEL_BG)
	canvas.draw_rect(panel.grow(-0.5), PANEL_BORDER, false, 1.0)
	canvas.draw_rect(panel.grow(-3.5), Color(PANEL_BORDER, 0.35), false, 1.0)

	var title := "SETTINGS" if _page == Page.MAIN else "CONTROLS"
	_text(panel.position + Vector2(0, 30), title, INK, 16, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x)
	canvas.draw_line(panel.position + Vector2(40, 40.5), panel.position + Vector2(panel.size.x - 40, 40.5),
			Color(PANEL_BORDER, 0.8))

	if _page == Page.MAIN:
		_draw_main(panel)
	else:
		_draw_controls(panel)


func _draw_main(panel: Rect2) -> void:
	var x := panel.position.x + 44
	var y := panel.position.y + 72
	for i in MAIN_ROWS.size():
		var sel := i == _row
		var row_name := MAIN_ROWS[i]
		var color := INK if sel else DIM
		# Separación extra antes de cada grupo
		if row_name == "DISPLAY" or row_name == "CONTROLS" or row_name == "BACK":
			y += 8
		if i == 0:
			_text(Vector2(x - 20, y - 14), "AUDIO", Color(DIM, 0.7))
		if sel:
			_text(Vector2(x - 14, y), ">", ACCENT)
		_text(Vector2(x, y), row_name, color)
		match row_name:
			"MASTER", "MUSIC", "SFX":
				_draw_slider(Vector2(x + 96, y - 7), Settings.volumes[BUS_OF[row_name]], sel)
			"DISPLAY":
				var mode := "FULLSCREEN" if Settings.fullscreen else "WINDOWED"
				var vx := x + 96
				_text(Vector2(vx, y), "<", ACCENT if sel else Color(DIM, 0.6))
				_text(Vector2(vx + 12, y), mode, color, 8, HORIZONTAL_ALIGNMENT_CENTER, 112)
				_text(Vector2(vx + 132, y), ">", ACCENT if sel else Color(DIM, 0.6))
		y += 20
	var hint := "LEFT/RIGHT: ADJUST   ESC: BACK" if _row <= 3 else "ENTER: SELECT   ESC: BACK"
	_text(Vector2(panel.position.x, panel.end.y - 12), hint, Color(DIM, 0.8), 8,
			HORIZONTAL_ALIGNMENT_CENTER, panel.size.x)


func _draw_slider(pos: Vector2, value: float, sel: bool) -> void:
	const SEGMENTS := 10
	const SEG_W := 10.0
	const SEG_H := 7.0
	var filled := int(round(value * SEGMENTS))
	for s in SEGMENTS:
		var r := Rect2(pos + Vector2(s * (SEG_W + 2), 0), Vector2(SEG_W, SEG_H))
		if s < filled:
			canvas.draw_rect(r, ACCENT if sel else Color(INK, 0.55))
		else:
			canvas.draw_rect(r.grow(-0.5), Color(DIM, 0.5), false, 1.0)
	_text(pos + Vector2(SEGMENTS * (SEG_W + 2) + 8, 7), "%3d%%" % roundi(value * 100),
			INK if sel else DIM)


func _draw_controls(panel: Rect2) -> void:
	var x := panel.position.x + 36
	var c1 := panel.position.x + 160
	var c2 := panel.position.x + 256
	var y := panel.position.y + 60
	_text(Vector2(c1, y), "KEY 1", Color(DIM, 0.7), 8, HORIZONTAL_ALIGNMENT_CENTER, 80)
	_text(Vector2(c2, y), "KEY 2", Color(DIM, 0.7), 8, HORIZONTAL_ALIGNMENT_CENTER, 80)
	y += 18
	var n := Settings.ACTIONS.size()
	for i in n:
		var action: StringName = Settings.ACTIONS[i]
		var sel := i == _row
		if sel:
			_text(Vector2(x - 14, y), ">", ACCENT)
		_text(Vector2(x, y), Settings.ACTION_NAMES[action], INK if sel else DIM)
		for s in 2:
			var cx := c1 if s == 0 else c2
			var cell := Rect2(cx, y - 10, 80, 13)
			var key_text := Settings.key_name(Settings.keys[action][s])
			var color := INK if sel else DIM
			if sel and s == _col:
				if _waiting_key:
					key_text = "PRESS KEY" if fmod(_blink, 0.8) < 0.5 else ""
					canvas.draw_rect(cell, Color(ACCENT, 0.18))
					color = ACCENT
				else:
					canvas.draw_rect(cell, ACCENT)
					color = Color.BLACK
			_text(Vector2(cx, y), key_text, color, 8, HORIZONTAL_ALIGNMENT_CENTER, 80)
		y += 16
	y += 6
	for i in 2:
		var row := n + i
		var label := "RESET DEFAULTS" if i == 0 else "BACK"
		var sel := row == _row
		if sel:
			_text(Vector2(x - 14, y), ">", ACCENT)
		_text(Vector2(x, y), label, INK if sel else DIM)
		y += 16
	var hint := "ESC: CANCEL" if _waiting_key else "ENTER: CHANGE  DEL: CLEAR  ESC: BACK"
	_text(Vector2(panel.position.x, panel.end.y - 12), hint, Color(DIM, 0.8), 8,
			HORIZONTAL_ALIGNMENT_CENTER, panel.size.x)
