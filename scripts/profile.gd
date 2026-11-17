extends Node
## Профиль игрока: айди, никнейм, аватарка. Хранится локально в user://.

signal profile_changed

const SAVE_PATH := "user://profile.json"

var uid: String = ""
var nickname: String = "Игрок"
var color_hex: String = "#66b3ff"


func _ready() -> void:
	load_profile()


func load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		uid = _new_uid()
		save()
		return

	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		uid = _new_uid()
		return

	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		uid = _new_uid()
		save()
		return

	var d: Dictionary = data
	uid = str(d.get("uid", ""))
	if uid.is_empty():
		uid = _new_uid()
	nickname = str(d.get("nickname", "Игрок"))
	color_hex = str(d.get("color", "#66b3ff"))
	save()


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"uid": uid,
		"nickname": nickname,
		"color": color_hex,
	}))


func set_nickname(value: String) -> void:
	nickname = value.strip_edges().substr(0, 16)
	if nickname.is_empty():
		nickname = "Игрок"
	save()
	profile_changed.emit()


func _new_uid() -> String:
	return Crypto.new().generate_random_bytes(8).hex_encode()


## Аватарка генерируется из айди: симметричный узор 5x5, как identicon.
## Ничего качать не надо, у каждого игрока она своя и стабильная.
func make_avatar(seed_text: String, size: int = 128) -> ImageTexture:
	var digest := seed_text.sha256_text()
	var bits := digest.hex_decode()
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color("1b1e26"))

	var cell: int = int(size / 5.0)
	var base := Color(color_hex)
	var bidx := 0

	for row in 5:
		for col in 3:
			var b: int = int(bits[bidx % bits.size()])
			bidx += 1
			if b % 2 == 0:
				continue
			var shade := base.darkened(float(b % 40) / 100.0)
			for dx in [col, 4 - col]:
				img.fill_rect(Rect2i(dx * cell, row * cell, cell, cell), shade)

	return ImageTexture.create_from_image(img)
