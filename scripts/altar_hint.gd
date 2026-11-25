class_name AltarHint
extends Resource

const PATH := "res://puzzles/hint_%02d.tres"

@export_multiline var text: String = ""
@export var puzzle: int = 0

static func for_altar(number: int) -> AltarHint:
	var path := PATH % number
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AltarHint
