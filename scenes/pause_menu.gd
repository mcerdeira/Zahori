extends CanvasLayer

signal closed

const SETTINGS_SCENE := preload("res://scenes/settings_menu.tscn")
const TABLET_SCENE := preload("res://scenes/tablet_viewer.tscn")
const TITLE_SCENE := "res://scenes/Title.tscn"
const INK := Color(0.55, 0.88, 1, 1)

@export var power_on_time: float = 0.25
@export var power_off_time: float = 0.2
@export var led_blink: float = 0.6

@onready var dim: ColorRect = $dim
@onready var monitor: Control = $monitor
@onready var screen_rect: TextureRect = $monitor/screen
@onready var viewport: SubViewport = $monitor/screen/viewport
@onready var options_box: VBoxContainer = $monitor/screen/viewport/content/options
@onready var led: ColorRect = $monitor/led

var _selected := 0
var _closing := false
var _options: Array[String] = ["CONTINUE", "SETTINGS", "QUIT"]
var _submenu: Node = null
var _labels: Array[Label] = []
var _highlight := StyleBoxFlat.new()

func _ready() -> void:
	get_tree().paused = true
	screen_rect.texture = viewport.get_texture()
	screen_rect.pivot_offset = screen_rect.size / 2.0
	_highlight.bg_color = INK
	_highlight.content_margin_left = 2
	_highlight.content_margin_right = 2
	if Global.tablet_piece_count() > 0:
		_options.insert(2, "TABLET")
		options_box.offset_top -= 4
		options_box.add_theme_constant_override(&"separation", 3)
	for option in _options:
		var l := Label.new()
		l.text = option
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		options_box.add_child(l)
		_labels.append(l)
	_refresh()
	Sfx.play("term_on")

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
	if _closing or _submenu:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_close()
	elif event.is_action_pressed("UP") or event.is_action_pressed("DOWN"):
		_selected = (_selected + (1 if event.is_action_pressed("DOWN") else -1) + _options.size()) % _options.size()
		_refresh()
		Sfx.play("term_key")
	elif event.is_action_pressed("action") or event.is_action_pressed("ui_accept"):
		match _options[_selected]:
			"CONTINUE":
				_close()
			"SETTINGS":
				Sfx.play("term_ok")
				_open_submenu(SETTINGS_SCENE)
			"TABLET":
				Sfx.play("term_ok")
				_open_submenu(TABLET_SCENE)
			"QUIT":
				Sfx.play("term_ok")
				_quit_to_title()
	get_viewport().set_input_as_handled()

func _open_submenu(scene: PackedScene) -> void:
	_submenu = scene.instantiate()
	_submenu.closed.connect(func(): _submenu = null)
	add_child(_submenu)

func _refresh() -> void:
	for i in _labels.size():
		var l := _labels[i]
		if i == _selected:
			l.add_theme_stylebox_override("normal", _highlight)
			l.add_theme_color_override("font_color", Color.BLACK)
		else:
			l.remove_theme_stylebox_override("normal")
			l.remove_theme_color_override("font_color")

func _quit_to_title() -> void:
	Music.stop_main_theme(0.6)
	Global.discard_pending_tablet_pieces()
	_close(func(): get_tree().change_scene_to_file(TITLE_SCENE))

func _close(after := Callable()) -> void:
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
		if after.is_valid():
			after.call()
		queue_free())
