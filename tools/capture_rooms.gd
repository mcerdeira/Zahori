extends Node

const ROOMS_DIR := "res://scenes/rooms/"
const OUT_DIR := "res://tools/room_shots/"
const SIZE := Vector2i(576, 324)
const WAIT_FRAMES := 6

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var re := RegEx.create_from_string("^(level|secret)\\d+\\.tscn$")
	var files := Array(DirAccess.get_files_at(ROOMS_DIR)).filter(func(f): return re.search(f) != null)
	for f in files:
		await _capture(f)
	print("capturas guardadas en %s (%d rooms)" % [OUT_DIR, files.size()])
	get_tree().quit()

func _capture(file: String) -> void:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.audio_listener_enable_2d = false
	add_child(vp)
	var room: Node = load(ROOMS_DIR + file).instantiate()
	vp.add_child(room)
	for i in WAIT_FRAMES:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + file.get_basename() + ".png"))
	vp.queue_free()
	await get_tree().process_frame
