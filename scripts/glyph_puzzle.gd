class_name GlyphPuzzle
extends Resource

const PATH := "res://puzzles/altar_%02d.tres"

@export var word: String = ""
@export var ability: String = ""
@export var ability_id: StringName = &""

static func for_altar(number: int) -> GlyphPuzzle:
	var path := PATH % number
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GlyphPuzzle

func answer() -> String:
	return word.strip_edges().to_upper()
