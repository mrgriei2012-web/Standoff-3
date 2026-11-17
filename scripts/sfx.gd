extends Node
## Звуки генерируются кодом (WAV в памяти) — не нужны файлы и лицензии.

var shot_stream: AudioStreamWAV
var hit_stream: AudioStreamWAV
var reload_stream: AudioStreamWAV
var beep_stream: AudioStreamWAV


func _ready() -> void:
	shot_stream = _noise(0.14, 0.6, 26.0)
	hit_stream = _noise(0.05, 0.45, 60.0)
	reload_stream = _click(0.07, 0.35)
	beep_stream = _tone(880.0, 0.12, 0.3)


func play_hit() -> void:
	if hit_stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = hit_stream
	p.volume_db = -6.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func play_beep() -> void:
	if beep_stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = beep_stream
	p.volume_db = -4.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _noise(duration: float, volume: float, decay: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * duration)
	var data := PackedByteArray()
	data.resize(n * 2)

	var smooth := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var env: float = exp(-t * decay)
		smooth = smooth * 0.65 + randf_range(-1.0, 1.0) * 0.35
		var v := int(clampf(smooth * env * volume, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)

	return _make(data, rate)


func _click(duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * duration)
	var data := PackedByteArray()
	data.resize(n * 2)

	for i in n:
		var t := float(i) / float(rate)
		var env: float = exp(-t * 70.0)
		var s: float = signf(sin(t * TAU * 2200.0)) * env * volume
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))

	return _make(data, rate)


func _tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * duration)
	var data := PackedByteArray()
	data.resize(n * 2)

	for i in n:
		var t := float(i) / float(rate)
		var env: float = exp(-t * 10.0)
		var s := sin(t * TAU * freq) * env * volume
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))

	return _make(data, rate)


func _make(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
