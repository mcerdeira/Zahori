extends "res://scripts/monologue.gd"

## Intro 2: monólogo del protagonista antes de entrar al juego (la lógica del
## texto y la voz está en scripts/monologue.gd). Al terminar arranca el tema
## principal y pasa a level0.

const NEXT_SCENE := "res://scenes/rooms/level0.tscn"


func _init() -> void:
	lines = [
		"At last... the threshold lies before me.",
		"Wherever you have gone, sister, I shall find you, and I shall know what befell you.",
		"Then, hand in hand, we shall unveil the secret that sleeps beneath eternity and time.",
	]


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	super()


func _finish() -> void:
	Music.play_main_theme()
	get_tree().change_scene_to_file(NEXT_SCENE)
