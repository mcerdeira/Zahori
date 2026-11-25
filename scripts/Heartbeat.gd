extends Node

signal beat(strength: float)

const DUB_PHASE := 0.3
const DUB_STRENGTH := 0.62
const IDLE_BPM := 48.0

@export var intensity_smoothing: float = 1.2
@export var pulse_decay: float = 7.0

var intensity := 0.0
var pulse := 0.0

var _sources: Array[Node] = []
var _phase := 0.0
var _bpm := IDLE_BPM
var _pending: Array[Dictionary] = []
var _shake_amp := 0.0
var _shake_time := 0.0
var _shake_max := 0.0

func add_source(source: Node) -> void:
	if source not in _sources:
		_sources.append(source)

func remove_source(source: Node) -> void:
	_sources.erase(source)

func _strongest() -> Node:
	var best: Node = null
	for s in _sources:
		if best == null or s.intensity > best.intensity:
			best = s
	return best

func _process(delta: float) -> void:
	var source := _strongest()
	var target: float = source.intensity if source else 0.0
	intensity = move_toward(intensity, target, delta / maxf(intensity_smoothing, 0.01))
	_bpm = lerpf(source.bpm_min, source.bpm_max, intensity) if source else IDLE_BPM
	if source:
		_shake_max = source.shake_px

	var next := _phase + delta * _bpm / 60.0
	if _phase < DUB_PHASE and next >= DUB_PHASE:
		_hit(&"heart_dub", DUB_STRENGTH, source)
	if next >= 1.0:
		_hit(&"heart_lub", 1.0, source)
	_phase = fmod(next, 1.0)

	_flush_pending(delta)
	pulse *= exp(-pulse_decay * delta)
	_update_shake(delta)

func _hit(sound: StringName, strength: float, source: Node) -> void:
	if source and intensity > 0.01:
		var db: float = lerpf(source.volume_min_db, source.volume_max_db, intensity)
		Sfx.play(sound, 1.0, db)
	_pending.append({"time": AudioServer.get_output_latency(), "strength": strength})

func _flush_pending(delta: float) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		_pending[i].time -= delta
		if _pending[i].time <= 0.0:
			_fire(_pending[i].strength)
			_pending.remove_at(i)

func _fire(strength: float) -> void:
	pulse = maxf(pulse, strength)
	if intensity > 0.01 and _shake_max > 0.0:
		_shake_amp = lerpf(1.0, _shake_max, intensity) * strength
		_shake_time = 0.0
	beat.emit(strength)

func _update_shake(delta: float) -> void:
	if _shake_amp <= 0.0:
		return
	var camera := get_viewport().get_camera_2d()
	if _shake_time > 0.35:
		_shake_amp = 0.0
		if camera:
			camera.offset = Vector2.ZERO
		return
	if camera:
		var y := _shake_amp * exp(-_shake_time * 14.0) * cos(_shake_time * 55.0)
		camera.offset = Vector2(0, round(y))
	_shake_time += delta
