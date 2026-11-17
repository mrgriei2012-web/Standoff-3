extends Node
## Настройки игры: сохраняются в user://settings.json и применяются на лету.

const PATH := "user://settings.json"

const DEFAULT_FPS := 60
const DEFAULT_SCALE := 1.0
const DEFAULT_SENS := 1.0
const DEFAULT_VOLUME := 0.8
const DEFAULT_QUALITY := 1

var fps_limit: int = DEFAULT_FPS
var render_scale: float = DEFAULT_SCALE
var sensitivity: float = DEFAULT_SENS
var volume: float = DEFAULT_VOLUME
var quality: int = DEFAULT_QUALITY

## Секреты. Открываются кодом в настройках, живут в отдельном флаге.
const SECRET_CODE := "abx"

var secrets_unlocked := false
var god_mode := false
var inf_ammo := false
var super_jump := false
var noclip := false
var speed_boost := false
var slowmo := false


## Проверка кода. Возвращает true, если код верный и секреты открылись.
func try_secret(code: String) -> bool:
	if code.strip_edges().to_lower() != SECRET_CODE:
		return false
	secrets_unlocked = true
	save()
	return true


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	fps_limit = int(d.get("fps_limit", DEFAULT_FPS))
	render_scale = float(d.get("render_scale", DEFAULT_SCALE))
	sensitivity = float(d.get("sensitivity", DEFAULT_SENS))
	volume = float(d.get("volume", DEFAULT_VOLUME))
	quality = int(d.get("quality", DEFAULT_QUALITY))
	secrets_unlocked = bool(d.get("secrets", false))
	god_mode = bool(d.get("god", false))
	inf_ammo = bool(d.get("ammo", false))
	super_jump = bool(d.get("jump", false))
	noclip = bool(d.get("noclip", false))
	speed_boost = bool(d.get("speed", false))
	slowmo = bool(d.get("slowmo", false))


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"fps_limit": fps_limit,
		"render_scale": render_scale,
		"sensitivity": sensitivity,
		"volume": volume,
		"quality": quality,
		"secrets": secrets_unlocked,
		"god": god_mode,
		"ammo": inf_ammo,
		"jump": super_jump,
		"noclip": noclip,
		"speed": speed_boost,
		"slowmo": slowmo,
	}))


func reset_defaults() -> void:
	fps_limit = DEFAULT_FPS
	render_scale = DEFAULT_SCALE
	sensitivity = DEFAULT_SENS
	volume = DEFAULT_VOLUME
	quality = DEFAULT_QUALITY
	secrets_unlocked = false
	god_mode = false
	inf_ammo = false
	super_jump = false
	noclip = false
	speed_boost = false
	slowmo = false
	apply_all()
	save()


func apply_all() -> void:
	apply_fps()
	apply_volume()
	apply_graphics()
	apply_time()


## Замедление времени — только для соло-режима с ботами.
func apply_time() -> void:
	Engine.time_scale = 0.35 if slowmo else 1.0


func apply_fps() -> void:
	Engine.max_fps = maxi(fps_limit, 0)


func apply_volume() -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, volume <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volume, 0.001)))


func apply_graphics() -> void:
	var vp := get_viewport()
	if vp == null:
		return

	# Внутреннее разрешение 3D-рендера: 0.5 = вдвое меньше пикселей, больше FPS.
	vp.scaling_3d_scale = clampf(render_scale, 0.25, 2.0)

	match quality:
		0:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		1:
			vp.msaa_3d = Viewport.MSAA_2X
		2:
			vp.msaa_3d = Viewport.MSAA_4X
