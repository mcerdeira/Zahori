extends Control

const NEXT_SCENE := "res://scenes/Intro.tscn"
const SETTINGS_SCENE := preload("res://scenes/settings_menu.tscn")
const FONT := preload("res://fonts/prstartk.ttf")
const OPTIONS: Array[String] = ["NEW GAME", "CONTINUE", "SETTINGS", "QUIT"]

const INK := Color(0.95, 0.95, 0.97)
const DIM := Color(0.42, 0.43, 0.48)
const ACCENT := Color(1.0, 0.78, 0.42)
const DISABLED := Color(0.22, 0.22, 0.26)

@export var fade_in_time: float = 2.0
@export var title_delay: float = 1.2
@export var title_fade_time: float = 2.5
@export var prompt_delay: float = 1.0
@export var leave_time: float = 1.4
@export var menu_bottom: float = 70.0
@export var menu_spacing: float = 16.0

@onready var back_view: TextureRect = $back_view
@onready var back_viewport: SubViewport = $back_view/viewport
@onready var back_vines: Node2D = $back_view/viewport/vines
@onready var front_vines: Node2D = $front_vines
@onready var sparks: Node2D = $sparks
@onready var title_label: Label = $title
@onready var glow: TextureRect = $glow
@onready var ui: Control = $ui
@onready var fade: ColorRect = $fade

enum State { INTRO, PROMPT, MENU, LEAVING }

var _state := State.INTRO
var _selected := 0
var _prompt_t := -1.0
var _menu_t := 0.0
var _time := 0.0
var _settings: Node = null
var _intro_tween: Tween
var _has_save := false

func _ready() -> void:
	if Global.DEBUG:
		Music.play_main_theme()
		get_tree().change_scene_to_file.call_deferred(Global.DEBUG_START_SCENE)
		return
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_has_save = Global.has_save()
	if _has_save:
		_selected = OPTIONS.find("CONTINUE")
	var area := size
	back_viewport.size = Vector2i((area / 2.0).ceil())
	back_vines.scale = Vector2(0.5, 0.5)
	back_view.texture = back_viewport.get_texture()
	back_vines.start(area)
	front_vines.start(area)
	sparks.start(area)
	ui.draw.connect(_draw_ui)

	title_label.position = ((area - title_label.size) / 2.0 - Vector2(0, area.y * 0.1)).round()
	glow.position = (title_label.position + title_label.size / 2.0 - glow.size / 2.0).round()
	title_label.modulate.a = 0.0
	glow.modulate.a = 0.0
	fade.modulate.a = 1.0

	Music.play_title_theme()
	_intro_tween = create_tween()
	_intro_tween.tween_property(fade, "modulate:a", 0.0, fade_in_time)
	_intro_tween.parallel().tween_interval(title_delay)
	_intro_tween.chain().tween_callback(_title_sparks)
	_intro_tween.tween_property(title_label, "modulate:a", 1.0, title_fade_time)
	_intro_tween.parallel().tween_property(glow, "modulate:a", 1.0, title_fade_time * 1.5)
	_intro_tween.parallel().tween_property(title_label, "position:y", title_label.position.y, title_fade_time) \
			.from(title_label.position.y + 6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_intro_tween.tween_interval(prompt_delay)
	_intro_tween.tween_callback(func():
		_state = State.PROMPT
		_prompt_t = 0.0)

func _title_sparks() -> void:
	var r := Rect2(title_label.position, title_label.size)
	for i in 5:
		sparks.burst(Vector2(lerpf(r.position.x + 30, r.end.x - 30, i / 4.0),
				r.position.y + r.size.y * randf_range(0.35, 0.7)), randi_range(4, 8))

func _process(delta: float) -> void:
	_time += delta
	if _prompt_t >= 0.0:
		_prompt_t += delta
	if _state == State.MENU:
		_menu_t += delta
	var flicker := 0.93 + 0.04 * sin(_time * 1.7) + 0.03 * sin(_time * 7.3 + sin(_time * 2.1))
	title_label.self_modulate = Color(flicker, flicker, flicker)
	glow.self_modulate.a = 0.75 + 0.25 * sin(_time * 0.8)
	ui.queue_redraw()

func _input(event: InputEvent) -> void:
	if _settings or _state == State.LEAVING:
		return
	var is_press: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventJoypadButton and event.pressed)
	if not is_press:
		return
	get_viewport().set_input_as_handled()
	if _state != State.MENU:
		_show_menu()
		return
	if _pressed(event, ["UP", "ui_up"]):
		_selected = (_selected - 1 + OPTIONS.size()) % OPTIONS.size()
		Sfx.play("term_key")
	elif _pressed(event, ["DOWN", "ui_down"]):
		_selected = (_selected + 1) % OPTIONS.size()
		Sfx.play("term_key")
	elif _pressed(event, ["action", "ui_accept"]):
		_choose()

func _pressed(event: InputEvent, actions: Array) -> bool:
	for a in actions:
		if InputMap.has_action(a) and event.is_action_pressed(a):
			return true
	return false

func _show_menu() -> void:
	if _intro_tween and _intro_tween.is_running():
		_intro_tween.kill()
		fade.modulate.a = 0.0
		title_label.modulate.a = 1.0
		glow.modulate.a = 1.0
		title_label.position.y = ((size.y - title_label.size.y) / 2.0 - size.y * 0.1)
	_state = State.MENU
	_menu_t = 0.0
	_prompt_t = -1.0
	Sfx.play("term_on", 0.8, -6.0)

func _choose() -> void:
	if OPTIONS[_selected] == "CONTINUE" and not _has_save:
		Sfx.play("term_err")
		return
	Sfx.play("term_ok")
	sparks.burst(_option_pos(_selected) + Vector2(0, -4), 10)
	match OPTIONS[_selected]:
		"NEW GAME":
			Global.reset_game()
			_start_game(NEXT_SCENE)
		"CONTINUE":
			var room := Global.load_game() if _has_save else ""
			if room.is_empty():
				Sfx.play("term_err")
				return
			_start_game(room, true)
		"SETTINGS":
			_settings = SETTINGS_SCENE.instantiate()
			_settings.closed.connect(func(): _settings = null)
			add_child(_settings)
		"QUIT":
			_state = State.LEAVING
			Music.stop_title_theme(0.5)
			var tw := create_tween()
			tw.tween_property(fade, "modulate:a", 1.0, 0.5)
			tw.tween_callback(get_tree().quit)

func _start_game(scene: String, in_game := false) -> void:
	_state = State.LEAVING
	Music.stop_title_theme(leave_time)
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, leave_time)
	tw.tween_interval(0.3)
	tw.tween_callback(func():
		if in_game:
			Music.play_main_theme()
		get_tree().change_scene_to_file(scene))

func _option_pos(i: int) -> Vector2:
	return Vector2(size.x / 2.0, size.y - menu_bottom + i * menu_spacing)

func _text_centered(center: Vector2, s: String, color: Color) -> void:
	var w := FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	ui.draw_string(FONT, Vector2(center.x - w / 2.0, center.y).round(), s,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)

func _draw_ui() -> void:
	if _prompt_t >= 0.0:
		var a := clampf(_prompt_t / 1.0, 0.0, 1.0) * (0.45 + 0.35 * sin(_prompt_t * 2.6))
		_text_centered(_option_pos(1), "PRESS ANY KEY", Color(INK, a))
	if _state != State.MENU and _state != State.LEAVING:
		return
	if _settings:
		return
	for i in OPTIONS.size():
		var a := clampf((_menu_t - i * 0.09) / 0.3, 0.0, 1.0)
		if a <= 0.0:
			continue
		var pos := _option_pos(i) + Vector2(0, (1.0 - a) * 6.0)
		var sel := i == _selected
		var color := INK if sel else DIM
		if OPTIONS[i] == "CONTINUE" and not _has_save:
			color = DISABLED
		_text_centered(pos, OPTIONS[i], Color(color, a))
		if sel:
			var half := FONT.get_string_size(OPTIONS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x / 2.0
			var bob := roundf(sin(_time * 4.0))
			var marker := Color(ACCENT, a)
			ui.draw_string(FONT, Vector2(pos.x - half - 16 - bob, pos.y).round(), ">",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 8, marker)
			ui.draw_string(FONT, Vector2(pos.x + half + 8 + bob, pos.y).round(), "<",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 8, marker)
