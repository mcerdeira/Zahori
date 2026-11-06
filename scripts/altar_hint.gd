class_name AltarHint
extends Resource
## Pista de un altar de pistas: un texto fijo que se muestra en la terminal y
## orienta sobre la palabra de algún altar de puzzle. Cada altar de pistas
## busca la suya en res://puzzles/hint_XX.tres según su número.
## La pantalla entra ~20 caracteres por línea y ~13 líneas.

const PATH := "res://puzzles/hint_%02d.tres"

## Texto de la pista (en inglés; los saltos de línea se respetan).
@export_multiline var text: String = ""


## Pista que le corresponde al altar de pistas number, o null si no existe.
static func for_altar(number: int) -> AltarHint:
	var path := PATH % number
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AltarHint
