extends Area2D

func _enter_tree() -> void:
	add_to_group("water")

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.has_method("resists_water") and body.resists_water():
		return
	if body.has_method("die"):
		body.die()

## Rect global del agua (el nodo suele estar escalado para cubrir la pileta).
func get_rect() -> Rect2:
	var shape := $collider.shape as RectangleShape2D
	var half := shape.size / 2.0
	return $collider.global_transform * Rect2(-half, shape.size)
