extends Node3D
## Оружие от первого лица: выбор из пака, руки, стрельба, отдача.

# Положение оружия в руках, в координатах камеры.
const HOLD_POS := Vector3(0.16, -0.13, 0.0)
const HOLD_ROT := Vector3(0, 2, 0)

const BASE := "res://assets/weapons/guns_quaternius/"

# grip   — рукоятка (правая рука), support — цевьё (левая рука).
# Координаты в системе оружия: X — вправо, Y — вверх, Z — назад к игроку.
# depth  — насколько ствол впереди камеры, length — длина в кадре.
const WEAPONS := [
	{
		"name": "Автомат", "model": "Assault Rifle",
		"damage": 26.0, "rpm": 640.0, "mag": 30, "reserve": 120,
		"depth": -0.60, "length": 0.85, "price": 2700,
		"grip": Vector3(0, -0.10, 0.16), "support": Vector3(0, -0.045, -0.16), "offhand": true,
	},
	{
		"name": "ПП", "model": "Submachine Gun",
		"damage": 18.0, "rpm": 900.0, "mag": 30, "reserve": 150,
		"depth": -0.55, "length": 0.65, "price": 1250,
		"grip": Vector3(0, -0.09, 0.13), "support": Vector3(0, -0.04, -0.10), "offhand": true,
	},
	{
		"name": "Дробовик", "model": "Shotgun",
		"damage": 68.0, "rpm": 90.0, "mag": 6, "reserve": 24,
		"depth": -0.58, "length": 0.85, "price": 1100,
		"grip": Vector3(0, -0.09, 0.17), "support": Vector3(0, -0.05, -0.22), "offhand": true,
	},
	{
		"name": "Снайперка", "model": "Sniper Rifle",
		"damage": 88.0, "rpm": 50.0, "mag": 5, "reserve": 20,
		"depth": -0.68, "length": 1.00, "price": 4750,
		"grip": Vector3(0, -0.10, 0.20), "support": Vector3(0, -0.05, -0.18), "offhand": true,
	},
	{
		"name": "Пистолет", "model": "Pistol",
		"damage": 22.0, "rpm": 380.0, "mag": 15, "reserve": 60,
		"depth": -0.40, "length": 0.38, "price": 500,
		"grip": Vector3(0, -0.09, 0.06), "support": Vector3.ZERO, "offhand": false,
	},
]

const RANGE := 250.0

# Скины: цвет корпуса оружия. a = 0 — заводской вид (без покраски).
const SKINS := [
	{"name": "Заводской", "color": Color(0, 0, 0, 0), "price": 0},
	{"name": "Пустыня", "color": Color("c2a06a"), "price": 250},
	{"name": "Кибер", "color": Color("2fd8c4"), "price": 400},
	{"name": "Золото", "color": Color("d8ab3a"), "price": 700},
	{"name": "Кровь", "color": Color("b3272a"), "price": 500},
	{"name": "Лёд", "color": Color("9fc6ff"), "price": 500},
	{"name": "Ночь", "color": Color("2a3340"), "price": 300},
]

const RANDOM_SKIN_PRICE := 150
const SKIN_FILE := "user://skins.cfg"

## Сигнал: пуля попала в кого-то живого (для хитмаркера на HUD).
signal hit_confirmed

var shooter: Node3D = null

var index := 0
var ammo: int = 30
var reserve: int = 120

var _cam: Camera3D
var _model: Node3D
var _fallback: Node3D
var _arms: Node3D
var _flash: OmniLight3D
var _shot_player: AudioStreamPlayer3D
var _cooldown := 0.0
var _recoil := 0.0
var _depth := -0.60
var _base_rot := Vector3.ZERO
var _base_pos := Vector3.ZERO
var _status := "нет модели"

# Точки хвата считаются по фактическому габариту модели (в системе камеры).
var _grip := Vector3(0, -0.10, 0.16)
var _support := Vector3(0, -0.045, -0.16)
var _offhand := true

var _skin_color := Color(0, 0, 0, 0)
var _skin_mat: StandardMaterial3D
var _skins := {}   # имя оружия -> Color скина

var _sleeve: StandardMaterial3D
var _glove: StandardMaterial3D


func _ready() -> void:
	_cam = get_parent() as Camera3D
	position = HOLD_POS
	rotation_degrees = HOLD_ROT

	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.85, 0.5)
	_flash.light_energy = 0.0
	_flash.omni_range = 6.0
	_flash.position = Vector3(0, 0, -0.6)
	add_child(_flash)

	_shot_player = AudioStreamPlayer3D.new()
	_shot_player.stream = Sfx.shot_stream
	_shot_player.unit_size = 12.0
	_shot_player.position = Vector3(0, 0, -0.6)
	add_child(_shot_player)

	_fallback = Node3D.new()
	_fallback.position = Vector3(0, -0.02, -0.62)
	add_child(_fallback)
	_build_fallback()

	_arms = Node3D.new()
	add_child(_arms)

	_sleeve = StandardMaterial3D.new()
	_sleeve.albedo_color = Color("4d4a3c")
	_sleeve.roughness = 0.95

	_glove = StandardMaterial3D.new()
	_glove.albedo_color = Color("16191d")
	_glove.roughness = 0.9

	_skin_mat = StandardMaterial3D.new()
	_skin_mat.roughness = 0.5
	_skin_mat.metallic = 0.3

	_load_skins()
	equip(0)


# ---------------------------------------------------------------- выбор оружия

func equip(i: int) -> void:
	index = clampi(i, 0, WEAPONS.size() - 1)
	var w: Dictionary = WEAPONS[index]

	# Ствол ставим так, чтобы приклад не упирался в камеру.
	_depth = -(0.28 + float(w["length"]) * 0.5)
	ammo = int(w["mag"])
	reserve = int(w["reserve"])

	if _model != null:
		_model.queue_free()
		_model = null

	_show_fallback(true)
	_status = "заглушка"
	_skin_color = _skins.get(weapon_name(), Color(0, 0, 0, 0))

	# Пока модель не загрузилась — держим руки по табличным точкам.
	var g: Vector3 = w["grip"]
	var sp: Vector3 = w["support"]
	_grip = Vector3(g.x, g.y, _depth + g.z)
	_support = Vector3(sp.x, sp.y, _depth + sp.z)
	_offhand = bool(w["offhand"])

	var path: String = BASE + str(w["model"]) + ".glb"
	_try_load_model(path)
	_rebuild_arms()


func cycle() -> void:
	equip((index + 1) % WEAPONS.size())


func weapon_name() -> String:
	return str(WEAPONS[index]["name"])


func price(i: int) -> int:
	return int(WEAPONS[clampi(i, 0, WEAPONS.size() - 1)]["price"])


func get_list() -> Array:
	return WEAPONS


func current_index() -> int:
	return index


func status_text() -> String:
	return _status


func get_ammo_text() -> String:
	return "%d / %d" % [ammo, reserve]


func _damage() -> float:
	return float(WEAPONS[index]["damage"])


func _rpm() -> float:
	return float(WEAPONS[index]["rpm"])


func _mag() -> int:
	return int(WEAPONS[index]["mag"])


# ---------------------------------------------------------------- модель

func _try_load_model(path: String) -> void:
	if not ResourceLoader.exists(path):
		_status = "заглушка: нет файла"
		print("[weapon] нет файла ", path)
		return

	var packed = load(path)
	if packed == null or not (packed is PackedScene):
		_status = "заглушка: битый файл"
		print("[weapon] не читается ", path)
		return

	_model = (packed as PackedScene).instantiate() as Node3D
	if _model == null:
		_status = "заглушка: не Node3D"
		return
	add_child(_model)

	var meshes := _find_meshes(_model)
	if meshes.is_empty():
		_status = "заглушка: нет мешей"
		_model.queue_free()
		_model = null
		return

	var box := _local_box(_model, meshes)
	var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest <= 0.0001:
		_status = "заглушка: нулевой размер"
		_model.queue_free()
		_model = null
		return

	# Длина в кадре и поворот: дуло должно смотреть вперёд (-Z), приклад — к
	# игроку. Ориентацию определяем по свисающей рукоятке, а не «на глаз».
	var k: float = float(WEAPONS[index]["length"]) / longest
	_model.scale = Vector3.ONE * k
	_model.rotation_degrees = _model_rotation(meshes, box)

	# Центрируем уже с учётом поворота и масштаба — иначе ствол «уезжает»
	# вбок и руки оказываются мимо оружия.
	_model.position = -(_model.basis * box.get_center()) + Vector3(0.0, 0.0, _depth)

	_base_rot = _model.rotation
	_base_pos = _model.position

	# Руки цепляем по реальному габариту: правая на рукоятке (низ, ближе к
	# прикладу), левая на цевье (низ, ближе к дулу).
	var wb: AABB = _model.transform * box
	var cx: float = wb.get_center().x
	var by: float = wb.position.y + wb.size.y * 0.06
	_grip = Vector3(cx, by, wb.end.z - wb.size.z * 0.30)
	_support = Vector3(cx, by, wb.position.z + wb.size.z * 0.30)
	_offhand = bool(WEAPONS[index]["offhand"])

	_apply_view_override()

	_paint_skin()
	_status = "%s: %d мешей" % [weapon_name(), meshes.size()]
	_show_fallback(false)

	# Модель догрузилась и хват пересчитан — руки надо пересобрать по новым
	# точкам, иначе они остаются на табличных и «висят» мимо оружия.
	_rebuild_arms()


## Ручная подгонка вида под конкретную пушку: авто-подгонка угадывает хват,
## а здесь можно поправить руками. Ключ — имя оружия.
##   pos   — сдвиг ствола (метры), rot — доворот (градусы),
##   grip  — правка правой руки, support — левой.
const VIEW_OVERRIDES := {
	# "AKR-12": {"pos": Vector3(0.0, -0.02, 0.03), "rot": Vector3(0, 2, 0)},
}


func _apply_view_override() -> void:
	var key: String = weapon_name()
	if not VIEW_OVERRIDES.has(key):
		return
	var ov: Dictionary = VIEW_OVERRIDES[key]
	if _model == null:
		return

	if ov.has("pos"):
		_base_pos += ov["pos"]
		_model.position = _base_pos
	if ov.has("rot"):
		var rot: Vector3 = ov["rot"]
		_base_rot += rot * (PI / 180.0)
		_model.rotation = _base_rot

	_grip += ov.get("grip", Vector3.ZERO)
	_support += ov.get("support", Vector3.ZERO)


func _find_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and node.mesh != null:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_meshes(child))
	return out


func _local_box(root: Node3D, meshes: Array) -> AABB:
	var box := AABB()
	var first := true
	for mi in meshes:
		var xf := _rel_transform(mi, root)
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


## Поворот модели так, чтобы дуло смотрело вперёд (-Z), приклад — к игроку.
func _model_rotation(meshes: Array, box: AABB) -> Vector3:
	var s := box.size
	if s.x >= s.y and s.x >= s.z:
		var d := _hang_side(meshes, box, 0)
		return Vector3(0.0, -90.0 if d > 0 else 90.0, 0.0)
	if s.z >= s.y:
		var d2 := _hang_side(meshes, box, 2)
		return Vector3(0.0, 0.0 if d2 > 0 else 180.0, 0.0)
	return Vector3(-90.0, 0.0, 0.0)


## +1, если ниже свисает сторона +axis (там рукоятка/приклад), -1 — если -axis.
func _hang_side(meshes: Array, box: AABB, axis: int) -> int:
	var mid: float = box.position[axis] + box.size[axis] * 0.5
	var pad: float = box.size[axis] * 0.15
	var plus_y := INF
	var minus_y := INF

	for mi in meshes:
		var xf := _rel_transform(mi, _model)
		var mesh: Mesh = mi.mesh
		for si in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(si)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var step: int = maxi(1, int(verts.size() / 300))
			var i: int = 0
			while i < verts.size():
				var p: Vector3 = xf * verts[i]
				i += step
				if p[axis] > mid + pad:
					plus_y = minf(plus_y, p.y)
				elif p[axis] < mid - pad:
					minus_y = minf(minus_y, p.y)

	if plus_y == INF or minus_y == INF:
		return 1
	return 1 if plus_y < minus_y else -1


func _show_fallback(value: bool) -> void:
	if _fallback != null:
		_fallback.visible = value


func _build_fallback() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("2b3138")
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color("ff8a00")

	_part(_fallback, Vector3(0.06, 0.09, 0.42), Vector3(0, 0, -0.24), dark)
	_part(_fallback, Vector3(0.03, 0.03, 0.34), Vector3(0, 0.01, -0.55), dark)
	_part(_fallback, Vector3(0.04, 0.16, 0.08), Vector3(0, -0.12, -0.18), accent)
	_part(_fallback, Vector3(0.045, 0.07, 0.2), Vector3(0, -0.01, 0.0), dark)
	_part(_fallback, Vector3(0.04, 0.1, 0.06), Vector3(0, -0.09, -0.02), dark)


func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


# ---------------------------------------------------------------- руки

func _rebuild_arms() -> void:
	if _arms == null:
		return

	for child in _arms.get_children():
		_arms.remove_child(child)
		child.queue_free()

	# Точки хвата уже посчитаны по модели (_grip / _support).

	# Правая кисть на рукоятке, предплечье уходит вниз-вправо за кадр.
	_arm(Vector3(0.40, -0.40, 0.10), _grip + Vector3(0, 0, 0.05), 0.028, _sleeve)
	_hand(_grip, 0.0)

	# Левая кисть на цевье, предплечье из левого нижнего угла.
	if _offhand:
		_arm(Vector3(-0.26, -0.44, 0.08), _support + Vector3(0, -0.02, 0.04), 0.028, _sleeve)
		_hand(_support, -0.12)


func _arm(from: Vector3, to: Vector3, radius: float, mat: Material) -> void:
	var dir := to - from
	var length := dir.length()
	if length <= 0.001:
		return

	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = length
	mi.mesh = cap

	var up := dir.normalized()
	var right := up.cross(Vector3.FORWARD)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()
	var forward := right.cross(up).normalized()

	mi.transform.basis = Basis(right, up, forward)
	mi.position = (from + to) * 0.5
	mi.material_override = mat
	_arms.add_child(mi)


func _hand(pos: Vector3, tilt: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.z = tilt
	_arms.add_child(root)

	# ладонь за рукояткой
	_box(root, Vector3(0.055, 0.10, 0.05), Vector3(0, 0, 0.032))

	# пальцы обхватывают рукоятку спереди
	_box(root, Vector3(0.062, 0.088, 0.022), Vector3(0, -0.004, -0.036))

	# большой палец сверху сбоку
	_box(root, Vector3(0.022, 0.042, 0.062), Vector3(0.032, 0.032, 0.006))

	# манжета у запястья
	_box(root, Vector3(0.062, 0.062, 0.035), Vector3(0, 0, 0.068))


func _box(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _glove
	parent.add_child(mi)


# ---------------------------------------------------------------- скины

func skin_list() -> Array:
	return SKINS


func skin_price(i: int) -> int:
	return int(SKINS[clampi(i, 0, SKINS.size() - 1)]["price"])


func random_skin_price() -> int:
	return RANDOM_SKIN_PRICE


func skin_name() -> String:
	if _skin_color.a <= 0.01:
		return "Заводской"
	for s in SKINS:
		var c: Color = s["color"]
		if c.a > 0.01 and c.is_equal_approx(_skin_color):
			return str(s["name"])
	return "Свой"


## Красим текущее оружие готовым скином.
func apply_skin(i: int) -> void:
	var s: Dictionary = SKINS[clampi(i, 0, SKINS.size() - 1)]
	set_skin_color(s["color"])


## Свой скин: любой цвет. a = 0 возвращает заводской вид.
func set_skin_color(c: Color) -> void:
	_skin_color = c
	_skins[weapon_name()] = c
	_paint_skin()
	_save_skins()


## Случайный цвет — «сделать свой скин».
func random_skin() -> Color:
	var c := Color.from_hsv(randf(), randf_range(0.55, 0.95), randf_range(0.6, 1.0))
	set_skin_color(c)
	return c


func _paint_skin() -> void:
	if _model == null or _skin_mat == null:
		return
	var painted: bool = _skin_color.a > 0.01
	if painted:
		_skin_mat.albedo_color = _skin_color
	for mi in _find_meshes(_model):
		if mi is MeshInstance3D:
			mi.material_override = _skin_mat if painted else null


func _load_skins() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SKIN_FILE) != OK:
		return
	if not cfg.has_section("skins"):
		return
	for key in cfg.get_section_keys("skins"):
		_skins[key] = cfg.get_value("skins", key)


func _save_skins() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SKIN_FILE)
	for key in _skins.keys():
		cfg.set_value("skins", str(key), _skins[key])
	cfg.save(SKIN_FILE)


# ---------------------------------------------------------------- стрельба

func try_shoot() -> void:
	if _cooldown > 0.0 or ammo <= 0:
		return

	if Settings.inf_ammo:
		ammo = _mag()
		reserve = maxi(reserve, _mag())

	ammo -= 1
	_cooldown = 60.0 / _rpm()
	_recoil = minf(_recoil + 0.035, 0.09)

	if _flash != null:
		_flash.light_energy = 3.0
	if _shot_player != null:
		_shot_player.play()

	_cast_shot()


func reload() -> void:
	var mag := _mag()
	if ammo >= mag or reserve <= 0:
		return
	var take: int = mini(mag - ammo, reserve)
	ammo += take
	reserve -= take


func _cast_shot() -> void:
	if _cam == null:
		return

	var from := _cam.global_position
	var dir := -_cam.global_transform.basis.z
	var to := from + dir * RANGE

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false

	if shooter != null and shooter is CollisionObject3D:
		query.exclude = [shooter.get_rid()]

	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return

	var collider = hit.get("collider")
	var point: Vector3 = hit.get("position")
	_spawn_impact(point)

	if collider != null and collider.has_method("take_damage"):
		if collider.has_method("set_last_attacker"):
			collider.call("set_last_attacker", shooter)
		collider.call("take_damage", _damage())
		hit_confirmed.emit()
		Sfx.play_hit()


func _spawn_impact(point: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.08
	mi.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat

	scene.add_child(mi)
	mi.global_position = point

	get_tree().create_timer(0.08).timeout.connect(mi.queue_free)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_recoil = move_toward(_recoil, 0.0, delta * 0.7)

	if _model != null:
		_model.position = _base_pos - Vector3(0, 0, _recoil)
		_model.rotation.x = _base_rot.x + _recoil * 0.4

	if _flash != null and _flash.light_energy > 0.0:
		_flash.light_energy = maxf(_flash.light_energy - delta * 30.0, 0.0)
