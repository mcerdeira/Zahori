extends "res://scripts/monologue.gd"

## Texto del final elegido (Global.ending), con la voz y el estilo de la intro.
## Al terminar funde el texto y pasa a los créditos.

const CREDITS_SCENE := "res://scenes/Credits.tscn"

const ENDINGS := {
	# YES: el player se une al organismo
	&"transcend": [
		"I laid my hand upon the heart, and it knew me.",
		"Now, like you, sister, I am part of the organism. Root of its root, breath of its breath.",
		"Time has no hold on me anymore. At last, I have transcended it.",
		"Our minds are woven together, with those who came before us, and with those who are yet to come.",
	],
	# NO: destruye el núcleo y muere con todo lo que el organismo consumió
	&"destroy": [
		"I found the core of the organism, and I tore it apart.",
		"It withered, and all it had consumed withered with it: my sister, the countless others, and I.",
		"No one will speak our names. We shall be forgotten, forever.",
		"But those who come after us will walk free of its roots.",
	],
	# Mejor final (4 fragmentos): retoma la inscripción de la tableta
	&"awaken": [
		"The tablet spoke true. This temple was raised upon a sleeping spring.",
		"Its roots drink, and their drinking keeps it dreaming. So I raised my sister's rod, and it bowed toward the deep.",
		"I struck the spring awake. The water rose, and at last, the roots let go.",
		"Whoever falls is kept, the stone had said. Kept, not lost. And one by one, the kept opened their eyes.",
		"Two shall come seeking. One shall be found. It was never you or I, sister. It was the spring.",
		"Now, hand in hand, we walk out beneath a sky that has remembered time.",
	],
}

@export var leave_time: float = 1.2 # segundos del fundido del texto antes de los créditos


func _ready() -> void:
	get_tree().paused = false # viene pausado desde ending_choice
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	Music.stop_main_theme(0.5)
	lines.assign(ENDINGS.get(Global.ending, ENDINGS[&"destroy"]))
	super()


func _finish() -> void:
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 0.0, leave_time)
	tw.tween_interval(0.8)
	tw.tween_callback(func(): get_tree().change_scene_to_file(CREDITS_SCENE))
