extends Control
## Créditos, después de cualquiera de los finales: las enredaderas desenfocadas del
## título con el nombre del juego encima. Tras unos segundos se puede salir con
## cualquier tecla y se vuelve al título (el tema sigue sonando sin cortarse).

const TITLE_SCENE := "res://scenes/Title.tscn"

@export var fade_in_time: float = 2.5  # segundos del fundido desde negro
@export var lock_time: float = 6.0     # segundos antes de poder salir
@export var leave_time: float = 1.4    # segundos del fundido a negro al salir

var _can_leave := false
var _leaving := false
var _prompt_t := 0.0

@onready var back_view: TextureRect = $back_view
@onready var back_viewport: SubViewport = $back_view/viewport
@onready var back_vines: Node2D = $back_view/viewport/vines
@onready var text: Control = $text
@onready var prompt: Label = $prompt
@onready var fade: ColorRect = $fade


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var area := size
	back_viewport.size = Vector2i((area / 2.0).ceil())
	back_vines.scale = Vector2(0.5, 0.5)
	back_view.texture = back_viewport.get_texture()
	back_vines.start(area)
	prompt.modulate.a = 0.0
	text.modulate.a = 0.0
	fade.modulate.a = 1.0
	Music.play_title_theme()
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 0.0, fade_in_time)
	tw.tween_property(text, "modulate:a", 1.0, 2.0)
	var unlock := create_tween()
	unlock.tween_interval(lock_time)
	unlock.tween_callback(func(): _can_leave = true)


func _process(delta: float) -> void:
	if not _can_leave or _leaving:
		return
	_prompt_t += delta
	prompt.modulate.a = clampf(_prompt_t, 0.0, 1.0) * (0.45 + 0.35 * sin(_prompt_t * 2.6))


func _input(event: InputEvent) -> void:
	if not _can_leave or _leaving:
		return
	var is_press: bool = (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventJoypadButton and event.pressed)
	if not is_press:
		return
	get_viewport().set_input_as_handled()
	_leaving = true
	Sfx.play("term_ok")
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, leave_time)
	tw.tween_interval(0.3)
	tw.tween_callback(func(): get_tree().change_scene_to_file(TITLE_SCENE))
