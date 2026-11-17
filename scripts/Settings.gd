extends Node

## Opciones del jugador: volúmenes, pantalla completa y teclas.
## Se guardan en user://settings.cfg y se aplican al arrancar el juego.
## Cada acción tiene dos teclas (primaria y alternativa); por default funcionan
## a la vez las flechas + Z/X y WASD + J/K.

signal changed

const PATH := "user://settings.cfg"

## Buses que se pueden regular desde el menú, en el orden en que se muestran.
const BUSES: Array[StringName] = [&"Master", &"Music", &"SFX"]

## Acciones remapeables, en el orden en que se muestran, con su nombre visible.
const ACTIONS: Array[StringName] = [&"LEFT", &"RIGHT", &"UP", &"DOWN", &"action", &"shoot", &"pause"]
const ACTION_NAMES := {
	&"LEFT": "LEFT",
	&"RIGHT": "RIGHT",
	&"UP": "UP",
	&"DOWN": "DOWN",
	&"action": "ACTION 1",
	&"shoot": "ACTION 2",
	&"pause": "PAUSE",
}
## Teclas por default (physical keycodes): [primaria, alternativa].
const DEFAULT_KEYS := {
	&"LEFT": [KEY_LEFT, KEY_A],
	&"RIGHT": [KEY_RIGHT, KEY_D],
	&"UP": [KEY_UP, KEY_W],
	&"DOWN": [KEY_DOWN, KEY_S],
	&"action": [KEY_Z, KEY_J],
	&"shoot": [KEY_X, KEY_K],
	&"pause": [KEY_Q, KEY_P],
}
## Teclas que no se pueden asignar (las usan los menús para cancelar/salir).
const RESERVED_KEYS: Array[int] = [KEY_ESCAPE]

## Tamaño de la ventana en modo ventana (múltiplo de la resolución base 576x324).
@export var windowed_scale: int = 2

## Volumen de cada bus, lineal de 0 a 1 (1 = el volumen original del bus).
var volumes := {}
## Factor temporal sobre Master (lo baja el menú de pausa); no se guarda.
var master_duck := 1.0
var fullscreen := true
## Acción -> [keycode primario, keycode alternativo] (0 = sin tecla).
var keys := {}

var _base_db := {} # volumen original de cada bus en default_bus_layout.tres (dB)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in BUSES:
		_base_db[bus] = AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))
		volumes[bus] = 1.0
	_reset_keys()
	_load()
	apply_all()


func _reset_keys() -> void:
	keys.clear()
	for a in ACTIONS:
		keys[a] = (DEFAULT_KEYS[a] as Array).duplicate()


func apply_all() -> void:
	for bus in BUSES:
		_apply_volume(bus)
	_apply_window()
	for a in ACTIONS:
		_apply_action(a)


# --- Audio ----------------------------------------------------------------------

func set_volume(bus: StringName, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)
	save()


## Baja temporalmente el Master (1 = normal), sin tocar el volumen elegido.
func set_master_duck(factor: float) -> void:
	master_duck = factor
	_apply_volume(&"Master")


func _apply_volume(bus: StringName) -> void:
	var idx := AudioServer.get_bus_index(bus)
	var v: float = volumes[bus]
	if bus == &"Master":
		v *= master_duck
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, _base_db[bus] + linear_to_db(maxf(v, 0.001)))


# --- Pantalla -------------------------------------------------------------------

func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_window()
	save()


func _apply_window() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var size := Vector2i(576, 324) * windowed_scale
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


# --- Teclas ---------------------------------------------------------------------

## Asigna `keycode` a la acción en el slot dado (0 primario, 1 alternativo).
## Si la tecla ya la usaba otra acción (u otro slot), ahí queda la tecla que
## se reemplazó, así nunca hay dos acciones con la misma tecla.
func bind_key(action: StringName, slot: int, keycode: int) -> void:
	var previous: int = keys[action][slot]
	for a in ACTIONS:
		for s in 2:
			if keys[a][s] == keycode and not (a == action and s == slot):
				keys[a][s] = previous
				_apply_action(a)
	keys[action][slot] = keycode
	_apply_action(action)
	save()
	changed.emit()


func clear_key(action: StringName, slot: int) -> void:
	keys[action][slot] = 0
	_apply_action(action)
	save()
	changed.emit()


func reset_keys() -> void:
	_reset_keys()
	for a in ACTIONS:
		_apply_action(a)
	save()
	changed.emit()


func _apply_action(action: StringName) -> void:
	InputMap.action_erase_events(action)
	for keycode in keys[action]:
		if keycode == 0:
			continue
		var ev := InputEventKey.new()
		ev.physical_keycode = keycode
		InputMap.action_add_event(action, ev)


## Nombre visible de una tecla según la distribución del teclado ("---" si no hay).
static func key_name(keycode: int) -> String:
	if keycode == 0:
		return "---"
	var label := DisplayServer.keyboard_get_keycode_from_physical(keycode)
	var text := OS.get_keycode_string(label if label != KEY_NONE else keycode)
	return text.to_upper()


# --- Guardado -------------------------------------------------------------------

func save() -> void:
	var cfg := ConfigFile.new()
	for bus in BUSES:
		cfg.set_value("audio", bus, volumes[bus])
	cfg.set_value("display", "fullscreen", fullscreen)
	for a in ACTIONS:
		cfg.set_value("keys", a, keys[a])
	cfg.save(PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for bus in BUSES:
		volumes[bus] = clampf(float(cfg.get_value("audio", bus, 1.0)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("display", "fullscreen", true))
	for a in ACTIONS:
		var saved = cfg.get_value("keys", a, null)
		if saved is Array and saved.size() == 2:
			keys[a] = [int(saved[0]), int(saved[1])]
