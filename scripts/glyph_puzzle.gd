class_name GlyphPuzzle
extends Resource
## Puzzle del glifo de un altar: una sola palabra (2 a 7 letras, sin espacios)
## relacionada con la habilidad que desbloquea. Cada altar busca el suyo en
## res://puzzles/altar_XX.tres según su número.

const PATH := "res://puzzles/altar_%02d.tres"

## Palabra a adivinar (sólo letras; se compara en mayúsculas).
@export var word: String = ""
## Nombre de la habilidad que se muestra al resolverlo (y al prenderla/apagarla).
@export var ability: String = ""
## Id de la habilidad en Global.abilities que se activa al resolverlo.
@export var ability_id: StringName = &""


## Puzzle que le corresponde al altar number, o null si no existe.
static func for_altar(number: int) -> GlyphPuzzle:
	var path := PATH % number
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GlyphPuzzle


func answer() -> String:
	return word.strip_edges().to_upper()
