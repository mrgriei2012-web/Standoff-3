extends StaticBody3D
## Модель игрока. Сначала пробуем настоящую модель, если её нет —
## собираем аккуратную фигуру из кубов: каска, бронежилет, руки на автомате.

const CHAR_ALPHA := "res://assets/characters/specnaz.glb"
const CHAR_BRAVO := "res://assets/characters/kontrterrorist.glb"

const GlbLoader := preload("res://scripts/glb_loader.gd")

## true — сначала пробовать модели из .glb, false — всегда кубические бойцы.
const USE_MODELS := false

## Рост модели в метрах.
const HEIGHT := 1.8

var nick := "Игрок"
var team := 0
var color := Color("ff6b3d")
var health := 100.0
var status := ""

var _label: Label3D
var _model: Node3D
var _meshes: Array = []
var _flash_mat: StandardMaterial3D
var _block_mats: Array = []
var _dead := false


func _ready() -> void:
	_build()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.8
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)

	var main_path: String = CHAR_ALPHA if team == 0 else CHAR_BRAVO
	var spare_path: String = CHAR_BRAVO if team == 0 else CHAR_ALPHA

	if USE_MODELS:
		_model = _try_model(main_path)
		if _model == null:
			_model = _try_model(spare_path)

	if _model == null:
		_build_blocky()
		status = "кубический"
	else:
		status = "модель"

	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color = Color(1.0, 0.15, 0.15, 0.55)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_label = Label3D.new()
	_label.text = nick
	_label.position = Vector3(0, 2.05, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 40
	_label.outline_size = 8
	_label.modulate = Color(1, 1, 1, 0.95)
	add_child(_label)


# ---------------------------------------------------------------- настоящая модель

func _try_model(path: String) -> Node3D:
	var model: Node3D = null

	if ResourceLoader.exists(path):
		var packed = load(path)
		if packed is PackedScene:
			model = (packed as PackedScene).instantiate() as Node3D

	# Импорт не удался — читаем .glb напрямую из файла.
	if model == null:
		model = GlbLoader.load_scene(path)

	if model == null:
		print("[actor] не загрузилась модель: ", path)
		return null

	add_child(model)

	var meshes := _pick_meshes(model)
	if meshes.is_empty():
		print("[actor] нет мешей: ", path)
		model.queue_free()
		return null

	var box := _local_box(model, meshes)
	var height := box.size.y
	if height < 0.05 or height > 500.0:
		print("[actor] габарит не измерен (", box.size, "), ставлю без масштаба")
		_meshes = meshes
		return model

	var k: float = HEIGHT / height
	model.scale = Vector3.ONE * k
	model.position = Vector3(
		-box.get_center().x * k,
		-box.position.y * k,
		-box.get_center().z * k
	)
	# Разворот лицом к нам: модели-рипы обычно смотрят в +Z.
	model.rotation_degrees.y = 180.0

	_meshes = meshes
	print("[actor] модель: ", path.get_file(), " рост ", snappedf(height, 0.01), " м, множитель ", snappedf(k, 0.001))
	return model


## У моделей-рипов внутри лежат LOD0..LOD3 друг на друге — оставляем только LOD0.
func _pick_meshes(model: Node) -> Array:
	var all := _find_meshes(model)
	var has_lod0 := false
	for mi in all:
		if str(mi.name).to_upper().begins_with("LOD0"):
			has_lod0 = true

	var out: Array = []
	for mi in all:
		var n := str(mi.name).to_upper()
		if has_lod0 and n.begins_with("LOD") and not n.begins_with("LOD0"):
			mi.visible = false
			continue
		out.append(mi)
	return out


func _find_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and node.mesh != null:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_meshes(child))
	return out


## Габарит мешей в системе координат корня модели.
func _local_box(root: Node3D, meshes: Array) -> AABB:
	var box := AABB()
	var first := true

	for mi in meshes:
		var xf := _rel_transform(mi, root)
		# Берём габарит самого меша: у скелетных моделей get_aabb() узла
		# бывает пустым, пока скелет не обновлён.
		var b: AABB = xf * mi.mesh.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)

	return box


func _rel_transform(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


# ---------------------------------------------------------------- кубический боец

func _build_blocky() -> void:
	var pants := Color("2c322b") if team == 0 else Color("272b31")
	var vest := Color("40492f") if team == 0 else Color("343b45")
	var plate := Color("2a3025") if team == 0 else Color("242930")
	var boots := Color("171a1c")
	var glove := Color("1b1e21")
	var skin := Color("d3a882")
	var helmet := Color("31382c") if team == 0 else Color("2a2f36")
	var gun := Color("1e2226")

	var m_pants := _block_mat(pants)
	var m_vest := _block_mat(vest)
	var m_plate := _block_mat(plate)
	var m_boots := _block_mat(boots)
	var m_glove := _block_mat(glove)
	var m_skin := _block_mat(skin)
	var m_helmet := _block_mat(helmet)
	var m_gun := _block_mat(gun)
	var m_team := _block_mat(color)

	# ноги и ботинки
	_part(Vector3(0.17, 0.84, 0.22), Vector3(-0.12, 0.53, 0), m_pants)
	_part(Vector3(0.17, 0.84, 0.22), Vector3(0.12, 0.53, 0), m_pants)
	_part(Vector3(0.19, 0.16, 0.30), Vector3(-0.12, 0.08, -0.03), m_boots)
	_part(Vector3(0.19, 0.16, 0.30), Vector3(0.12, 0.08, -0.03), m_boots)

	# пояс
	_part(Vector3(0.44, 0.16, 0.27), Vector3(0, 0.99, 0), _block_mat(Color("22262a")))

	# торс и бронежилет
	_part(Vector3(0.46, 0.52, 0.27), Vector3(0, 1.26, 0), m_vest)
	_part(Vector3(0.36, 0.34, 0.32), Vector3(0, 1.26, -0.01), m_plate)
	_part(Vector3(0.36, 0.06, 0.33), Vector3(0, 1.10, -0.01), m_team)

	# плечи
	_part(Vector3(0.16, 0.18, 0.27), Vector3(-0.31, 1.44, 0), m_vest)
	_part(Vector3(0.16, 0.18, 0.27), Vector3(0.31, 1.44, 0), m_vest)

	# шея и голова
	_part(Vector3(0.12, 0.10, 0.12), Vector3(0, 1.55, 0), m_skin)
	_part(Vector3(0.22, 0.24, 0.22), Vector3(0, 1.65, 0), m_skin)

	# каска с козырьком
	_part(Vector3(0.26, 0.13, 0.27), Vector3(0, 1.79, 0.005), m_helmet)
	_part(Vector3(0.24, 0.04, 0.06), Vector3(0, 1.74, -0.14), m_helmet)

	# плечи-руки, согнутые вперёд
	_part(Vector3(0.14, 0.34, 0.16), Vector3(-0.32, 1.24, 0.02), m_vest)
	_part(Vector3(0.14, 0.34, 0.16), Vector3(0.32, 1.24, 0.02), m_vest)

	# предплечья к оружию
	_part(Vector3(0.13, 0.13, 0.34), Vector3(0.17, 1.06, -0.20), m_vest)
	_part(Vector3(0.13, 0.13, 0.36), Vector3(-0.06, 1.12, -0.32), m_vest)

	# кисти
	_part(Vector3(0.11, 0.12, 0.13), Vector3(0.15, 1.03, -0.33), m_glove)
	_part(Vector3(0.11, 0.11, 0.13), Vector3(-0.03, 1.10, -0.47), m_glove)

	# автомат в руках
	_part(Vector3(0.055, 0.10, 0.46), Vector3(0.11, 1.07, -0.34), m_gun)
	_part(Vector3(0.045, 0.05, 0.26), Vector3(0.11, 1.13, -0.60), m_gun)
	_part(Vector3(0.05, 0.17, 0.09), Vector3(0.11, 0.96, -0.30), m_gun)
	_part(Vector3(0.05, 0.08, 0.16), Vector3(0.11, 1.02, 0.02), m_gun)


func _block_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	_block_mats.append({"mat": m, "base": c})
	return m


func _part(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


# ---------------------------------------------------------------- урон

func take_damage(amount: float) -> void:
	if _dead:
		return

	health -= amount
	_tint(true)

	if health <= 0.0:
		_die()


func _tint(value: bool) -> void:
	if not _block_mats.is_empty():
		for entry in _block_mats:
			entry["mat"].albedo_color = Color(1, 0.35, 0.35) if value else entry["base"]
		if value:
			var t := get_tree().create_timer(0.12)
			t.timeout.connect(_tint.bind(false))
		return

	if _model == null:
		return

	for mi in _meshes:
		if mi is MeshInstance3D:
			mi.material_overlay = _flash_mat if value else null

	if value:
		var t2 := get_tree().create_timer(0.12)
		t2.timeout.connect(_tint.bind(false))


func _die() -> void:
	_dead = true
	_label.text = nick + " — убит"

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "rotation_degrees:x", 90.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_label, "position:y", 0.9, 0.45)

	await get_tree().create_timer(2.5).timeout
	_respawn()


func _respawn() -> void:
	health = 100.0
	_dead = false
	rotation_degrees = Vector3.ZERO
	_label.position = Vector3(0, 2.05, 0)
	_label.text = nick
	_tint(false)
