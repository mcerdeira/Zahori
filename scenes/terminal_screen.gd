extends Control
## Pantalla de la terminal: consola de texto (RichTextLabel para la salida y
## LineEdit para el prompt) que bootea y después corre el puzzle del glifo.
## Todo lo que "escribe" el sistema o el usuario simulado pasa por una cola
## que se tipea de a un carácter.

signal solved

## Respuesta del sistema: rápida y sin sonido.
const COLOR := Color(0.55, 0.88, 1.0)
const SYSTEM := 160.0
## "Usuario" tipeando: más lento y con click de tecla.
const USER := 14.0
const CORRECT_BBCODE := "[bgcolor=#8ce0ff][color=#000000]%s[/color][/bgcolor]"
const PRESENT_BBCODE := "%s"
const ABSENT_BBCODE := "[color=#8ce0ff40]%s[/color]"

@export var max_log_lines: int = 5         # líneas de historial visibles durante el puzzle
@export var unfold_scale: float = 0.5      # escala de las letras al desplegar la palabra

## Número de altar: define el puzzle y el texto de la barra de estado.
var altar_number := 1
var puzzle: GlyphPuzzle

var _log := ""         # bbcode de la salida
var _log_limit := 0    # 0 = sin límite de líneas (booteo)
var _queue: Array = [] # items {text, cps, input} | float (pausa) | Callable
var _type_timer := 0.0
var _awaiting := false # esperando que el jugador escriba
var _toggling := false # altar ya resuelto: se pregunta si prender/apagar la habilidad

@onready var glyphs: HBoxContainer = $vbox/glyphs
@onready var glyphs_gap: Control = $vbox/glyphs_gap
@onready var typed_col: Control = $vbox/glyphs/typed_col
## Glifo a descifrar y glifo que se va formando con lo que tipea el jugador.
@onready var target: GlyphView = $vbox/glyphs/target_col/target
@onready var typed: GlyphView = $vbox/glyphs/typed_col/typed
@onready var log_label: RichTextLabel = $vbox/log
@onready var prompt_row: HBoxContainer = $vbox/prompt_row
@onready var prompt: Label = $vbox/prompt_row/prompt
@onready var input: LineEdit = $vbox/prompt_row/input
@onready var status_right: Label = $status_bar/status_right


func _ready() -> void:
	status_right.text = "ALTAR-%02d" % altar_number
	input.text_changed.connect(_on_text_changed)
	input.text_submitted.connect(_on_submitted)
	if "keep_editing_on_text_submit" in input:
		input.set("keep_editing_on_text_submit", true)
	_refresh_log()


## true mientras el sistema está escribiendo (el jugador no puede tipear).
func is_busy() -> bool:
	return not _queue.is_empty()


## Termina al instante todo lo pendiente de la cola.
func skip() -> void:
	while not _queue.is_empty():
		var item = _queue.pop_front()
		if item is Callable:
			item.call()
		elif item is Dictionary:
			for ch in item.text:
				_put(ch, item.input)
	_type_timer = 0.0


func boot() -> void:
	_type_log("ZAH0R1 OS V1.14\n(C) 1989 ALTAR SYS.\n" + "-".repeat(20) + "\n")
	_wait(0.3)
	for check in [["MEMORY", "640K OK"], ["ALTAR LINK", "OK"], ["GLYPHS", "OK"]]:
		_type_log(check[0] + " ")
		_type_log(".".repeat(18 - check[0].length() - check[1].length()), 18.0)
		_type_log(" " + check[1] + "\n")
	_wait(0.4)
	_then(_show_prompt.bind("C:\\>"))
	_wait(0.5)
	_type_input("RUN GLYPH.EXE")
	_wait(0.25)
	_then(_echo_input)
	_type_log("LOADING...\n")
	_wait(0.6)
	_then(_start)


# --- Cola de tipeo -----------------------------------------------------------

func _type_log(text: String, cps: float = SYSTEM) -> void:
	_queue.append({"text": text, "cps": cps, "input": false})


func _type_input(text: String, cps: float = USER) -> void:
	_queue.append({"text": text, "cps": cps, "input": true})


func _wait(seconds: float) -> void:
	_queue.append(seconds)


func _then(action: Callable) -> void:
	_queue.append(action)


func _process(delta: float) -> void:
	if _queue.is_empty():
		_type_timer = 0.0
		return
	_type_timer -= delta
	while _type_timer <= 0.0 and not _queue.is_empty():
		var item = _queue[0]
		if item is float:
			_queue.pop_front()
			_type_timer += item
		elif item is Callable:
			_queue.pop_front()
			item.call()
		else:
			var ch: String = item.text[0]
			if item.text.length() == 1:
				_queue.pop_front()
			else:
				item.text = item.text.substr(1)
			_put(ch, item.input)
			_type_timer += 1.0 / item.cps


## Escribe un carácter en la salida o en el prompt (como si lo tipeara el usuario).
func _put(ch: String, to_input: bool) -> void:
	if to_input:
		input.text += ch
		input.caret_column = input.text.length()
		if ch != " ":
			Sfx.play("term_key", randf_range(0.85, 1.2), -6.0)
	else:
		_log += "[lb]" if ch == "[" else ch
		_refresh_log()


func _add_line(bbcode: String) -> void:
	_log += bbcode + "\n"
	_refresh_log()


func _refresh_log() -> void:
	var lines := _log.trim_suffix("\n").split("\n")
	if _log_limit > 0 and lines.size() > _log_limit:
		lines = lines.slice(lines.size() - _log_limit)
	log_label.text = "\n".join(lines)
	log_label.visible = not log_label.text.is_empty()


func _show_prompt(symbol: String) -> void:
	prompt.text = symbol
	input.text = ""
	prompt_row.visible = true
	input.grab_focus()
	if input.has_method("edit"):
		input.edit()


## Pasa la línea del prompt a la salida, como al apretar Enter.
func _echo_input() -> void:
	_log += (prompt.text + " " + input.text).replace("[", "[lb]") + "\n"
	input.text = ""
	prompt_row.visible = false
	_refresh_log()


# --- Puzzle ------------------------------------------------------------------

func _start() -> void:
	_log = ""
	_log_limit = max_log_lines
	_refresh_log()
	puzzle = GlyphPuzzle.for_altar(altar_number)
	if puzzle == null or puzzle.answer().is_empty():
		_type_log("ERROR: NO GLYPH DATA\nFOR ALTAR-%02d\n" % altar_number)
	elif Global.is_altar_solved(altar_number):
		_start_toggle()
	else:
		_start_puzzle()


func _start_puzzle() -> void:
	var word := puzzle.answer()
	glyphs.visible = true
	glyphs_gap.visible = true
	target.letters = word
	typed.letters = ""
	input.max_length = word.length()
	_show_prompt(">")
	_awaiting = true


## Sólo letras y en mayúsculas; cada tecla hace click.
func _on_text_changed(text: String) -> void:
	var clean := ""
	for ch in text.to_upper():
		if ch >= "A" and ch <= "Z":
			clean += ch
	if clean != text:
		var caret := input.caret_column
		input.text = clean
		input.caret_column = mini(caret, clean.length())
	if _awaiting:
		typed.letters = clean
	Sfx.play("term_key", randf_range(0.85, 1.2), -6.0)


func _on_submitted(text: String) -> void:
	if not _awaiting or is_busy():
		return
	if _toggling:
		_answer_toggle(text.strip_edges().to_upper())
		return
	var word := puzzle.answer()
	var guess := text.strip_edges().to_upper()
	input.text = ""
	typed.letters = ""
	if guess.length() != word.length():
		_add_line("> " + ABSENT_BBCODE % "?")
		Sfx.play("term_err")
		return
	_add_line("> " + _score(guess, word))
	if guess == word:
		_win()
	else:
		Sfx.play("term_err")


## Resultado estilo Wordle: letra justa, letra en otro lugar o letra que no está.
func _score(guess: String, word: String) -> String:
	var result: Array[String] = []
	result.resize(guess.length())
	var pending := {} # letras de la palabra que no fueron acertadas en su lugar
	for i in guess.length():
		if guess[i] == word[i]:
			result[i] = CORRECT_BBCODE % guess[i]
		else:
			pending[word[i]] = pending.get(word[i], 0) + 1
	for i in guess.length():
		if result[i] != "":
			continue
		if pending.get(guess[i], 0) > 0:
			pending[guess[i]] -= 1
			result[i] = PRESENT_BBCODE % guess[i]
		else:
			result[i] = ABSENT_BBCODE % guess[i]
	return " ".join(result)


func _win() -> void:
	_awaiting = false
	Global.solve_altar(altar_number, puzzle.ability_id)
	prompt_row.visible = false
	# Sólo queda la jugada ganadora, así el mensaje final entra con su espaciado
	var lines := _log.trim_suffix("\n").split("\n")
	_log = lines[-1] + "\n"
	_log_limit = 0
	_refresh_log()
	Sfx.play("term_ok")
	_unfold_glyph()
	_wait(0.8)
	_type_log("\nACCESS GRANTED\n\n")
	_wait(0.3)
	_type_log("UNLOCKED:\n" + puzzle.ability + "\n")
	_wait(0.5)
	_then(solved.emit)


## Separa las letras superpuestas del glifo y las acomoda en fila (a lo ancho
## de los dos cuadros) para revelar la palabra.
func _unfold_glyph() -> void:
	var tw := create_tween().set_parallel()
	tw.tween_property(typed_col, "modulate:a", 0.0, 0.3)
	# Alineada a la izquierda, como el resto del texto de la consola
	var left_x := glyphs.global_position.x - target.global_position.x
	target.unfold_row(left_x, unfold_scale, 0.6)


# --- Altar ya resuelto: prender/apagar la habilidad --------------------------

func _start_toggle() -> void:
	_toggling = true
	var verb := "TURN OFF" if Global.has_ability(puzzle.ability_id) else "TURN ON"
	_type_log("%s %s?\nYES/NO\n" % [verb, puzzle.ability])
	_then(func():
		input.max_length = 3
		_show_prompt(">")
		_awaiting = true)


func _answer_toggle(answer: String) -> void:
	input.text = ""
	if answer not in ["YES", "Y", "NO", "N"]:
		_add_line("> " + ABSENT_BBCODE % "?")
		Sfx.play("term_err")
		return
	_awaiting = false
	prompt_row.visible = false
	_add_line("> " + answer)
	if answer.begins_with("Y"):
		var enabled := not Global.has_ability(puzzle.ability_id)
		Global.set_ability(puzzle.ability_id, enabled)
		Sfx.play("term_ok")
		_type_log("%s: %s\n" % [puzzle.ability, "ON" if enabled else "OFF"])
	else:
		_type_log("ABORTED\n")
