extends Node3D
## Матч: карта, игрок, другие игроки по сети, боты в одиночном тесте.

const PlayerScript := preload("res://scripts/player.gd")
const ActorScript := preload("res://scripts/actor_model.gd")
const BotScript := preload("res://scripts/bot.gd")

## Сколько платят за убитого бота.
const KILL_REWARD := 300

## Режимы матча.
const TDM_TARGET := 20
const BOMB_ROUND_TIME := 90.0
const BOMB_FUSE := 40.0
const PLANT_TIME := 2.5
const DEFUSE_TIME := 4.0
const SITE_RADIUS := 4.0

## Экономика закладки: первый раунд — нож и пистолет, автомат копится.
const BOMB_START_MONEY := 400
const ROUND_INCOME := 900
const HudScript := preload("res://scripts/hud.gd")
const GlbLoader := preload("res://scripts/glb_loader.gd")

const TEAM_COLORS := [Color("ff6b3d"), Color("4aa3ff")]

# Точки спавна внутри карты в долях полугабарита: [x, z].
# Отрицательный z — половина команды АЛЬФА, положительный — БРАВО.
const SPAWN_SLOTS := [
	Vector2(-0.28, -0.40), Vector2(0.0, -0.46), Vector2(0.28, -0.40),
	Vector2(-0.28, 0.40), Vector2(0.0, 0.46), Vector2(0.28, 0.40),
	Vector2(-0.12, -0.15), Vector2(0.12, 0.15), Vector2(0.0, 0.0),
]

## Жёсткие базы по картам: {"polygon": {"0": [Vector3, ...], "1": [...]}}.
## Если для карты и команды точки заданы — берутся они, без всяких поисков.
const SPAWN_OVERRIDES := {}

const SPAWN_GRID := 10          # сетка поиска точек на своей половине карты
const SPAWN_MAX_POINTS := 8     # сколько точек кэшируем на команду

var _spawn_cache: Dictionary = {}   # team (int) -> Array[Vector3]

var player
var ghosts: Dictionary = {}   # peer_id -> модель игрока
var bots: Array = []          # живые боты-ИИ
var frags := 0                # фраги игрока за матч
var _hud = null               # HUD текущего матча
var _last_attacker_id := 0    # кто последним попал (для сетевой смерти)
var _spec_cam: Camera3D       # камера наблюдения после смерти
var _spec_target: Node3D
var _spec_angle := 0.0
var _fx_accum := 0.0          # таймер обновления маркеров

## Режим матча: бомба и командный счёт.
var _site := Vector3.ZERO
var _bomb_pos := Vector3.ZERO
var _bomb_planted := false
var _bomb_timer := 0.0
var _round_timer := 0.0
var _round_live := false
var _bomb_mesh: Node3D
var _action := ""             # "" | "plant" | "defuse"
var _action_work := 0.0
var _tdm_done := false
var _cheats_active := false   # читы пришли из лобби — снимем их после матча

var _map_loaded := false
var _map_center := Vector3.ZERO
var _map_half := Vector3(10, 1, 10)
var _map_floor := 0.5

var _respawn_point := Vector3(0, 2, 0)
var _respawn_team := 0


func _ready() -> void:
	_setup_input()
	_build_world()
	# Ждём кадр физики: без него коллизии карты ещё не в пространстве и
	# лучи спавна улетают в пустоту.
	await get_tree().physics_frame
	_spawn_player()

	Net.state_received.connect(_on_state_received)
	Net.players_changed.connect(_refresh_ghosts)
	Net.hit_received.connect(_on_hit_received)
	Net.player_killed.connect(_on_net_killed)
	Net.player_respawned.connect(_on_net_respawned)
	_refresh_ghosts()

	# Боты — в одиночном тесте (и когда в лобби один игрок).
	if Net.players.size() <= 1 or not Net.in_match:
		_spawn_bots()

	_setup_match()


# ---------------------------------------------------------------- ввод

func _setup_input() -> void:
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("jump", KEY_SPACE)
	_key("crouch", KEY_CTRL)
	_key("reload", KEY_R)
	_key("weapon_1", KEY_1)
	_key("weapon_2", KEY_2)
	_key("weapon_3", KEY_3)
	_key("weapon_4", KEY_4)
	_key("weapon_5", KEY_5)


func _key(action: String, keycode: int) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


func _mouse(action: String, button: int) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- мир

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = _make_sky()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8fa4bd")
	env.ambient_light_energy = 0.7

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	var map_loaded := false
	if Net.map_id == "polygon":
		map_loaded = _load_glb_map("res://assets/maps/polygon.glb")
	elif Net.map_id == "sendstone":
		map_loaded = _load_glb_map("res://assets/maps/sendstone_ref.glb")
	if not map_loaded:
		_build_arena()


func _make_sky() -> Sky:
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color("25405e")
	mat.sky_horizon_color = Color("9fb3c6")
	mat.ground_bottom_color = Color("1d2024")
	mat.ground_horizon_color = Color("6f7780")
	mat.sun_angle_max = 25.0

	var sky := Sky.new()
	sky.sky_material = mat
	return sky


## Загружает карту из glb и вешает на неё коллизии по мешу.
func _load_glb_map(path: String) -> bool:
	var map: Node3D = null

	if ResourceLoader.exists(path):
		var packed = load(path)
		if packed is PackedScene:
			map = (packed as PackedScene).instantiate() as Node3D

	# Импорт не удался — читаем .glb напрямую из файла.
	if map == null:
		map = GlbLoader.load_scene(path)

	if map == null:
		print("[map] не загрузилась: ", path)
		return false

	# Карту кладём в поворотный узел, чтобы можно было развернуть её целиком.
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.add_child(map)

	var meshes := _find_meshes(map)
	if meshes.is_empty():
		print("[map] нет мешей: ", path)
		pivot.queue_free()
		return false

	var box := AABB()
	var first := true
	var tris := 0

	for mi in meshes:
		var mesh_box: AABB = _rel_transform(mi, map) * mi.mesh.get_aabb()
		if first:
			box = mesh_box
			first = false
		else:
			box = box.merge(mesh_box)
		tris += mi.mesh.get_faces().size() / 3

	# Крайние точки сцены часто включают далёкий фон и «декорации» за картой,
	# поэтому габарит по AABB врёт и карта выходит маленькой. Берём 4–96%
	# вершин: это и есть реальная, игровая часть карты.
	var pts := _collect_points(meshes, map)
	var local := _robust_extent(pts, Transform3D.IDENTITY)
	if pts.size() < 50 or local["size"].length() < 0.001:
		local = {"lo": box.position, "size": box.size}

	# Карты из Sketchfab бывают в Z-up: самый тонкий габарит — это высота.
	var s: Vector3 = local["size"]
	if s.z < s.x * 0.7 and s.z < s.y * 0.7:
		pivot.rotation_degrees.x = -90.0
	elif s.x < s.y * 0.7 and s.x < s.z * 0.7:
		pivot.rotation_degrees.z = 90.0

	var placed := pivot.transform * map.transform
	var ext := _robust_extent(pts, placed)
	if pts.size() < 50 or ext["size"].length() < 0.001:
		var full: AABB = placed * box
		ext = {"lo": full.position, "size": full.size}

	# Приводим любую карту к одному масштабу: ~110 метров по ширине.
	var span: float = maxf(ext["size"].x, ext["size"].z)
	var k: float = 1.0
	if span > 0.2:
		k = 110.0 / span
		if absf(k - 1.0) > 0.05:
			pivot.scale = Vector3.ONE * k
			print("[map] масштаб карты: x", snappedf(k, 0.01))

	var lo: Vector3 = ext["lo"]
	var esize: Vector3 = ext["size"]

	_map_loaded = true
	_map_center = (lo + esize * 0.5) * k
	_map_half = esize * 0.5 * k
	_map_floor = lo.y * k

	# Коллизии сразу печём в метрах и без масштаба на узлах: масштабированные
	# concave-шейпы физика переваривает плохо.
	var pivot_xf := Transform3D(Basis.from_euler(pivot.rotation).scaled(Vector3.ONE * k), Vector3.ZERO)
	for mi in meshes:
		var faces: PackedVector3Array = mi.mesh.get_faces()
		if faces.is_empty():
			continue
		var xf: Transform3D = pivot_xf * map.transform * _rel_transform(mi, map)
		var world_faces := PackedVector3Array()
		world_faces.resize(faces.size())
		for i in faces.size():
			world_faces[i] = xf * faces[i]

		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var concave := ConcavePolygonShape3D.new()
		concave.set_faces(world_faces)
		concave.backface_collision = true
		shape.shape = concave
		body.add_child(shape)
		add_child(body)

	var world_box: AABB = pivot.transform * (map.transform * box)
	print("[map] загружена ", path.get_file(), ", мешей: ", meshes.size(), ", треугольников: ", tris,
		", игровая зона: ", esize * k, ", вся сцена: ", world_box.size,
		", центр: ", _map_center, ", пол: ", snappedf(_map_floor, 0.01))
	return true


## Собирает вершины всех мешей (с шагом) в пространстве карты.
func _collect_points(meshes: Array, map: Node) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for mi in meshes:
		var xf := _rel_transform(mi, map)
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var step: int = maxi(1, int(verts.size() / 400))
			var i: int = 0
			while i < verts.size():
				pts.append(xf * verts[i])
				i += step
	return pts


## Габарит по «ядру» облака точек: отсекаем 4% хвостов с каждой стороны.
func _robust_extent(pts: PackedVector3Array, xf: Transform3D) -> Dictionary:
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var zs := PackedFloat32Array()
	xs.resize(pts.size())
	ys.resize(pts.size())
	zs.resize(pts.size())
	for i in pts.size():
		var p: Vector3 = xf * pts[i]
		xs[i] = p.x
		ys[i] = p.y
		zs[i] = p.z
	xs.sort()
	ys.sort()
	zs.sort()
	var lo := Vector3(_pick(xs, 0.04), _pick(ys, 0.02), _pick(zs, 0.04))
	var hi := Vector3(_pick(xs, 0.96), _pick(ys, 0.98), _pick(zs, 0.96))
	return {"lo": lo, "size": hi - lo}


func _pick(arr: PackedFloat32Array, q: float) -> float:
	if arr.is_empty():
		return 0.0
	var i: int = clampi(int(round(q * float(arr.size() - 1))), 0, arr.size() - 1)
	return arr[i]


func _rel_transform(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _find_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and node.mesh != null:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_meshes(child))
	return out


func _build_arena() -> void:
	_box_static(Vector3(60, 1, 60), Vector3(0, -0.5, 0), Color("3a4350"))
	_box_static(Vector3(60, 5, 1), Vector3(0, 2.5, -30), Color("2f3844"))
	_box_static(Vector3(60, 5, 1), Vector3(0, 2.5, 30), Color("2f3844"))
	_box_static(Vector3(1, 5, 60), Vector3(-30, 2.5, 0), Color("2f3844"))
	_box_static(Vector3(1, 5, 60), Vector3(30, 2.5, 0), Color("2f3844"))

	_box_static(Vector3(6, 2, 1), Vector3(-10, 1, -6), Color("57616f"))
	_box_static(Vector3(1, 2, 6), Vector3(6, 1, 4), Color("57616f"))
	_box_static(Vector3(3, 3, 3), Vector3(0, 1.5, -14), Color("57616f"))
	_box_static(Vector3(3, 3, 3), Vector3(14, 1.5, 2), Color("57616f"))
	_box_static(Vector3(8, 1.2, 2), Vector3(-4, 0.6, 12), Color("6b7482"))


func _box_static(size: Vector3, pos: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = size
	mesh.mesh = bmesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)

	add_child(body)


# ---------------------------------------------------------------- игроки

func _spawn_player() -> void:
	var my_id := Net.my_id()
	var team := 0
	if Net.players.has(my_id):
		team = int(Net.players[my_id].get("team", 0))

	player = PlayerScript.new()
	_respawn_team = team
	_respawn_point = _spawn_point(team, my_id)
	player.position = _respawn_point
	player.health = 100.0
	add_child(player)
	player.add_to_group("team_%d" % team)
	player.died.connect(_on_player_died)

	# Закладка бомбы: денег только на пистолет, автомат — с фрагов.
	if Net.mode == "bomb":
		player.money = BOMB_START_MONEY
		player.has_primary = false
		player.primary_index = 0
		player.equip_slot(2)

	var hud = HudScript.new()
	hud.player = player
	add_child(hud)
	_hud = hud

	if OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_settle_spawn()


## Первый кадр физики: проверяем, что под ногами правда пол, и подправляем.
func _settle_spawn() -> void:
	await get_tree().physics_frame
	if player == null or not is_instance_valid(player):
		return
	if player.global_position.distance_to(_respawn_point) > 1.5:
		return   # игрок уже пошёл
	var p: Vector3 = _spawn_point(_respawn_team, Net.my_id())
	var moved := Vector2(p.x - _respawn_point.x, p.z - _respawn_point.z).length()
	if moved < 5.0:
		player.global_position = p
		player.velocity = Vector3.ZERO
		_respawn_point = p
		print("[spawn] старт: ", p)


## Страховка: упал за карту — возвращаем на респавн.
func _process(delta: float) -> void:
	_update_spectate(delta)

	_fx_accum += delta
	if _fx_accum >= 0.25:
		_fx_accum = 0.0
		_update_bot_outline()
		_update_team_markers()

	if Net.mode == "bomb":
		_bomb_update(delta)
		_update_bomb_action(delta)
		_bomb_hud()
	elif Net.mode == "tdm":
		_bomb_hud()

	if player == null or not is_instance_valid(player):
		return
	if player.global_position.y < _map_floor - 10.0:
		var p: Vector3 = _spawn_point(_respawn_team, Net.my_id())
		player.global_position = p + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
		player.velocity = Vector3.ZERO
		print("[spawn] упал за карту — вернул на ", p)


# ---------------------------------------------------------------- режимы матча

## Ушли из матча — читы из лобби больше не действуют.
func _exit_tree() -> void:
	if not _cheats_active:
		return
	_cheats_active = false
	for key in ["god_mode", "inf_ammo", "super_jump", "speed_boost", "rapid_fire"]:
		Settings.set(key, false)
	Settings.save()


func _is_authority() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return multiplayer.is_server()


func _setup_match() -> void:
	Net.score_changed.connect(_on_score_changed)
	Net.bomb_event.connect(_on_bomb_event)
	Net.round_result.connect(_on_round_result)

	# Читы лобби: одинаковые для всех, без ESP по живым игрокам.
	# В режиме ХВХ они включены всегда.
	var cheat_on: bool = Net.cheats or Net.mode == "hvh"
	if cheat_on:
		_cheats_active = true
		Settings.god_mode = true
		Settings.inf_ammo = true
		Settings.super_jump = true
		Settings.speed_boost = true
		Settings.rapid_fire = true
		Settings.save()

	if _hud != null and is_instance_valid(_hud):
		_hud.set_mode_ui(Net.mode, cheat_on)
		_hud.set_score(Net.score[0], Net.score[1])
		_hud.bomb_press.connect(_on_bomb_press)
		_hud.bomb_release.connect(_on_bomb_release)

	if Net.mode == "bomb":
		_site = _bomb_site()
		_build_site_marker()
		_bomb_pos = _site
		_round_live = true
		_round_timer = BOMB_ROUND_TIME
		_bomb_timer = BOMB_FUSE
		if _is_authority():
			_start_bomb_round()


func _bomb_site() -> Vector3:
	return _drop_to_floor(Vector3(_map_center.x, _map_center.y + 20.0, _map_center.z))


func _build_site_marker() -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = SITE_RADIUS
	cyl.bottom_radius = SITE_RADIUS
	cyl.height = 0.08
	mi.mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.2, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	add_child(mi)
	mi.global_position = _site + Vector3(0, 0.05, 0)


func _show_bomb(pos: Vector3) -> void:
	if _bomb_mesh == null or not is_instance_valid(_bomb_mesh):
		_bomb_mesh = Node3D.new()
		add_child(_bomb_mesh)

		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.36, 0.22, 0.5)
		mi.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("2b2f33")
		mi.material_override = mat
		_bomb_mesh.add_child(mi)

		var lamp := OmniLight3D.new()
		lamp.light_color = Color("ff3b30")
		lamp.light_energy = 2.0
		lamp.omni_range = 3.5
		lamp.position = Vector3(0, 0.35, 0)
		_bomb_mesh.add_child(lamp)

	_bomb_mesh.global_position = pos + Vector3(0, 0.15, 0)
	_bomb_mesh.visible = true


func _start_bomb_round() -> void:
	_round_timer = BOMB_ROUND_TIME
	_bomb_timer = BOMB_FUSE
	_round_live = true
	_bomb_planted = false
	_action = ""
	_action_work = 0.0
	Net.bomb_e("reset", _site)


## Тиканье таймеров раунда. Решение о конце раунда принимает хост.
func _bomb_update(delta: float) -> void:
	if not _round_live:
		return

	if _bomb_planted:
		_bomb_timer = maxf(_bomb_timer - delta, 0.0)
		if _is_authority() and _bomb_timer <= 0.0:
			# Событие "exploded" само закроет раунд и начислит очко.
			Net.bomb_e("exploded", _bomb_pos)
		return

	_round_timer = maxf(_round_timer - delta, 0.0)
	if _is_authority() and _round_timer <= 0.0:
		_end_round(1, "Время вышло")


func _end_round(winner: int, reason: String) -> void:
	if not _round_live:
		return
	_round_live = false
	_bomb_planted = false

	if _is_authority():
		Net.finish_round(winner, reason)
		await get_tree().create_timer(6.0).timeout
		if not is_inside_tree():
			return
		if _is_authority():
			_start_bomb_round()


func _on_bomb_event(kind: String, pos: Vector3) -> void:
	if _bomb_mesh != null and is_instance_valid(_bomb_mesh) and (kind == "reset" or kind == "defused" or kind == "exploded"):
		_bomb_mesh.visible = false

	match kind:
		"reset":
			_round_live = true
			_bomb_planted = false
			_round_timer = BOMB_ROUND_TIME
			_bomb_timer = BOMB_FUSE
			_bomb_pos = pos
		"planted":
			_bomb_planted = true
			_bomb_pos = pos
			_bomb_timer = BOMB_FUSE
			_round_live = true
			_show_bomb(pos)
			if _hud != null and is_instance_valid(_hud):
				_hud.show_banner("БОМБА ЗАЛОЖЕНА", 2.0)
		"defused":
			_bomb_planted = false
			_round_live = false
			if _hud != null and is_instance_valid(_hud):
				_hud.show_banner("БОМБА РАЗМИНИРОВАНА", 2.0)
			if _is_authority():
				_restart_after_round(1, "Бомба разминирована")
		"exploded":
			_bomb_planted = false
			_round_live = false
			if _hud != null and is_instance_valid(_hud):
				_hud.show_banner("БОМБА ВЗОРВАЛАСЬ", 2.0)
			if _is_authority():
				_restart_after_round(0, "Бомба взорвалась")


func _restart_after_round(winner: int, reason: String) -> void:
	Net.finish_round(winner, reason)
	await get_tree().create_timer(6.0).timeout
	if not is_inside_tree():
		return
	if _is_authority():
		_start_bomb_round()


func _on_round_result(winner: int, reason: String) -> void:
	var team_name := "АЛЬФА" if winner == 0 else "БРАВО"
	if _hud != null and is_instance_valid(_hud):
		_hud.show_banner("%s — %s" % [team_name, reason], 5.0)

	# Доход за раунд получают все — и живые, и убитые. Иначе те, кто
	# проиграл раунд, навсегда остаются с пистолетом против автомата.
	if Net.mode == "bomb" and player != null and is_instance_valid(player):
		player.money += ROUND_INCOME


func _on_score_changed(a: int, b: int) -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.set_score(a, b)

	if Net.mode != "tdm" or _tdm_done:
		return
	if a >= TDM_TARGET or b >= TDM_TARGET:
		_tdm_done = true
		var team_name := "АЛЬФА" if a >= TDM_TARGET else "БРАВО"
		if _hud != null and is_instance_valid(_hud):
			_hud.show_banner("ПОБЕДА: %s" % team_name, 6.0)


func _bomb_hud() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return

	var text := ""
	if Net.mode == "bomb":
		if not _round_live:
			text = "РАУНД ОКОНЧЕН"
		elif _bomb_planted:
			text = "БОМБА: %d с" % int(ceil(_bomb_timer))
		else:
			text = "%d:%02d" % [int(int(_round_timer) / 60), int(_round_timer) % 60]
	elif Net.mode == "tdm":
		text = "ДО %d УБИЙСТВ" % TDM_TARGET

	_hud.set_round_text(text)


func _my_team() -> int:
	return _respawn_team


func _near(point: Vector3, radius: float) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return player.global_position.distance_to(point) <= radius


func _on_bomb_press(kind: String) -> void:
	_action = kind
	_action_work = 0.0


func _on_bomb_release() -> void:
	_action = ""
	_action_work = 0.0


## Закладка и разминирование: прогресс копится, пока держишь кнопку.
func _update_bomb_action(delta: float) -> void:
	# В соло доступны обе роли: иначе режим не проверить без второго игрока.
	var solo := not Net.networked()
	var can_plant := _round_live and not _bomb_planted and (solo or _my_team() == 0) and _near(_site, SITE_RADIUS + 1.5)
	var can_defuse := _round_live and _bomb_planted and (solo or _my_team() == 1) and _near(_bomb_pos, 4.0)

	if _action == "plant":
		if not can_plant:
			_action = ""
			_action_work = 0.0
		else:
			_action_work += delta
			if _action_work >= PLANT_TIME:
				_action = ""
				_action_work = 0.0
				Net.report_bomb("planted", _site)
	elif _action == "defuse":
		if not can_defuse:
			_action = ""
			_action_work = 0.0
		else:
			_action_work += delta
			if _action_work >= DEFUSE_TIME:
				_action = ""
				_action_work = 0.0
				Net.report_bomb("defused", _bomb_pos)

	var progress := 0.0
	if _action == "plant":
		progress = _action_work / PLANT_TIME
	elif _action == "defuse":
		progress = _action_work / DEFUSE_TIME

	if _hud != null and is_instance_valid(_hud):
		_hud.set_bomb_buttons(can_plant, can_defuse, progress)


# ---------------------------------------------------------------- маркеры и спектатор

## Подсветка ботов. Только ботов: чужих игроков это не касается.
func _update_bot_outline() -> void:
	for b in bots:
		if not is_instance_valid(b):
			continue
		var vis = b.get("_visual")
		if vis == null or not is_instance_valid(vis):
			continue
		if vis.has_method("set_outline"):
			vis.call("set_outline", Settings.bot_outline, TEAM_COLORS[clampi(int(b.team), 0, 1)])


## Метки над сетевыми игроками: свои — с дистанцией и цветом команды.
func _update_team_markers() -> void:
	if player == null or not is_instance_valid(player):
		return

	for id in ghosts.keys():
		var ghost = ghosts[id]
		if ghost == null or not is_instance_valid(ghost):
			continue
		if ghost.has_method("is_dead") and ghost.is_dead():
			continue

		var data: Dictionary = Net.players.get(int(id), {})
		var team := int(data.get("team", ghost.team))
		var dist := int(round(player.global_position.distance_to(ghost.global_position)))

		if team == _respawn_team:
			ghost.call("set_label_text", "%s  %d м" % [ghost.nick, dist])
			ghost.call("set_label_color", Color("6fd3ff"))
		else:
			ghost.call("set_label_text", str(ghost.nick))
			ghost.call("set_label_color", Color(1, 1, 1, 0.95))


## После смерти смотрим за ближайшим живым игроком, пока идёт отсчёт.
func _start_spectate() -> void:
	if _spec_cam == null:
		_spec_cam = Camera3D.new()
		_spec_cam.fov = 78.0
		add_child(_spec_cam)

	_spec_target = _pick_spectate_target()
	_spec_cam.current = true


func _pick_spectate_target() -> Node3D:
	if player == null or not is_instance_valid(player):
		return null

	var best: Node3D = null
	var best_d := 1.0e9
	for id in ghosts.keys():
		var g = ghosts[id]
		if g == null or not is_instance_valid(g):
			continue
		if g.has_method("is_dead") and g.is_dead():
			continue
		var d: float = player.global_position.distance_to(g.global_position)
		if d < best_d:
			best_d = d
			best = g
	return best


func _update_spectate(delta: float) -> void:
	if _spec_cam == null or not _spec_cam.is_current():
		return

	if _spec_target != null and is_instance_valid(_spec_target):
		if _spec_target.has_method("is_dead") and _spec_target.is_dead():
			_spec_target = _pick_spectate_target()
	else:
		_spec_target = _pick_spectate_target()

	var base: Vector3
	if _spec_target != null and is_instance_valid(_spec_target):
		base = _spec_target.global_position
	elif player != null and is_instance_valid(player):
		base = player.global_position
	else:
		return

	_spec_angle += delta * 0.4
	_spec_cam.global_position = base + Vector3(sin(_spec_angle) * 4.5, 3.2, cos(_spec_angle) * 4.5)
	_spec_cam.look_at(base + Vector3(0, 1.2, 0), Vector3.UP)


func _stop_spectate() -> void:
	if _spec_cam != null and is_instance_valid(_spec_cam):
		_spec_cam.current = false
	if player != null and is_instance_valid(player) and player.camera != null:
		player.camera.current = true
	_spec_target = null


func _spawn_point(team: int, index: int) -> Vector3:
	if _map_loaded:
		return _map_spawn(team, index)

	var z0 := 10.0 if team == 0 else -10.0
	var x0 := -6.0 + float(abs(index) % 5) * 3.0
	return _drop_to_floor(Vector3(x0, 40.0, z0))


## Спавн внутри загруженной карты. Точки для каждой команды ищутся один раз
## и кэшируются, чтобы весь матч базы стояли на одних и тех же местах.
func _map_spawn(team: int, index: int) -> Vector3:
	if not _spawn_cache.has(team):
		_spawn_cache[team] = _find_team_spawns(team)
	var pts: Array = _spawn_cache[team]
	return pts[int(abs(index)) % pts.size()]


## Ищет площадки под спавн на половине команды: сначала явные координаты из
## SPAWN_OVERRIDES, потом привычные слоты, потом сетка по половине карты.
func _find_team_spawns(team: int) -> Array:
	var side: float = -1.0 if team == 0 else 1.0
	var top: float = _map_center.y + _map_half.y + 8.0
	var bottom: float = _map_floor - 25.0
	var max_y: float = _map_floor + maxf(4.0, _map_half.y * 0.25)

	# 1. Явные точки из конфига карты.
	var per_map: Dictionary = SPAWN_OVERRIDES.get(Net.map_id, {})
	if per_map.has(str(team)):
		var explicit: Array = []
		for p in per_map[str(team)]:
			explicit.append(_drop_to_floor(p))
		if not explicit.is_empty():
			print("[spawn] команда ", team, ": точки заданы вручную")
			return explicit

	# 2. Привычные слоты — так базы выглядят ровно и предсказуемо.
	var found: Array = []
	for loc in SPAWN_SLOTS:
		if loc.y * side < 0.0:
			continue
		var p = _probe_spawn(loc, top, bottom, max_y)
		if p != null:
			found.append(p)
	if found.size() >= 2:
		print("[spawn] команда ", team, ": ", found.size(), " точек по слотам")
		return _sorted_by_base(found, side)

	# 3. Слоты не подошли — обходим сеткой свою половину карты.
	found.clear()
	var n: int = SPAWN_GRID
	for iz in n:
		for ix in n:
			var fx: float = (float(ix) + 0.5) / float(n) * 2.0 - 1.0
			var fz: float = (float(iz) + 0.5) / float(n) * 2.0 - 1.0
			if fz * side < 0.1:
				continue
			var pt = _probe_spawn(Vector2(fx * 0.92, fz * 0.92), top, bottom, max_y)
			if pt != null:
				found.append(pt)
		if found.size() >= SPAWN_MAX_POINTS:
			break

	if found.is_empty():
		print("[spawn] площадок не нашлось, ставлю в центр карты")
		return [Vector3(_map_center.x, _map_floor + 2.0, _map_center.z)]

	print("[spawn] команда ", team, ": ", found.size(), " точек по сетке")
	return _sorted_by_base(found, side)


## Проверяет одну точку: есть ли пол, не крыша ли это и влезает ли туда игрок.
## Возвращает Vector3 или null.
func _probe_spawn(loc: Vector2, top: float, bottom: float, max_y: float):
	var x: float = _map_center.x + loc.x * _map_half.x
	var z: float = _map_center.z + loc.y * _map_half.z
	var hit := _ray(Vector3(x, top, z), Vector3(x, bottom, z))
	if hit.is_empty():
		return null
	var pos: Vector3 = hit.get("position", Vector3.ZERO)
	if pos.y > max_y:
		return null           # это крыша, а не пол
	var p := Vector3(x, pos.y + 0.4, z)
	if _blocked(p):
		return null
	return p


## Занято ли место под игрока (капсула 0.4 × 1.7).
func _blocked(p: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), p + Vector3(0, 0.9, 0))
	return not space.intersect_shape(q, 1).is_empty()


## Ближние к своей базе точки — первыми, чтобы порядок спавна был стабильным.
func _sorted_by_base(points: Array, side: float) -> Array:
	var base_z: float = _map_center.z + side * _map_half.z * 0.6
	var copy: Array = points.duplicate()
	copy.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return absf(a.z - base_z) < absf(b.z - base_z))
	return copy


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))


## Ищет пол под точкой, чтобы не спавниться в воздухе или в стене.
func _drop_to_floor(p: Vector3) -> Vector3:
	var hit := _ray(p, p + Vector3(0, -120, 0))
	if hit.is_empty():
		return Vector3(p.x, 1.2, p.z)
	var pos: Vector3 = hit.get("position", Vector3.ZERO)
	return Vector3(p.x, pos.y + 0.1, p.z)


func _refresh_ghosts() -> void:
	var my_id := Net.my_id()

	for id in Net.players.keys():
		if int(id) == my_id:
			continue
		if ghosts.has(int(id)):
			continue

		var data: Dictionary = Net.players[id]
		var team := int(data.get("team", 0))

		var ghost = ActorScript.new()
		ghost.nick = str(data.get("nick", "Игрок"))
		ghost.team = team
		ghost.color = TEAM_COLORS[clampi(team, 0, 1)]
		ghost.peer_id = int(id)
		ghost.position = _spawn_point(team, int(id))
		add_child(ghost)
		ghosts[int(id)] = ghost


func _on_state_received(peer_id: int, pos: Vector3, yaw: float, _pitch: float) -> void:
	if not ghosts.has(peer_id):
		return
	var ghost: Node3D = ghosts[peer_id]
	ghost.global_position = pos
	ghost.rotation.y = yaw


func _spawn_bots() -> void:
	var data := [
		["Бот 1", 1],
		["Бот 2", 1],
		["Бот 3", 0],
	]

	var i := 0
	for entry in data:
		var bot = BotScript.new()
		bot.nick = str(entry[0])
		bot.team = int(entry[1])
		bot.color = TEAM_COLORS[clampi(int(entry[1]), 0, 1)]
		bot.position = _spawn_point(int(entry[1]), 2 + i)
		bot.killed.connect(_on_bot_killed)
		add_child(bot)
		bots.append(bot)
		print("[bot] ", bot.nick, " в команде ", bot.team)
		i += 1


## Игрок убил бота — платим за фраг. Боты, убившие друг друга, денег не дают.
func _on_bot_killed(_victim: Node, killer: Node) -> void:
	var victim_name := "Бот"
	if "nick" in _victim:
		victim_name = str(_victim.nick)

	var killer_name := "Бот"
	if killer == player:
		killer_name = Profile.nickname
	elif killer != null and "nick" in killer:
		killer_name = str(killer.nick)

	if _hud != null and is_instance_valid(_hud):
		_hud.add_kill(killer_name, victim_name)

	if killer != player:
		return

	frags += 1
	if _hud != null and is_instance_valid(_hud):
		_hud.set_frags(frags)
	if player != null and is_instance_valid(player):
		player.money += KILL_REWARD
		print("[eco] +", KILL_REWARD, " за фраг, всего ", player.money)

	# В соло командный счёт считаем локально: хоста нет.
	if Net.mode == "tdm" and not multiplayer.has_multiplayer_peer():
		Net.score[_respawn_team] += 1
		Net.score_changed.emit(Net.score[0], Net.score[1])


## Игрока убили — в онлайне возвращаем только по команде хоста.
func _on_player_died() -> void:
	_start_spectate()

	# В сетевой игре смерть подтверждает хост, а не мой клиент.
	if Net.networked():
		Net.report_death(_last_attacker_id)
		return

	var killer_name := "Бот"
	if player != null and player.last_attacker != null and "nick" in player.last_attacker:
		killer_name = str(player.last_attacker.nick)
	if _hud != null and is_instance_valid(_hud):
		_hud.add_kill(killer_name, Profile.nickname)

	await get_tree().create_timer(3.0).timeout
	if player == null or not is_instance_valid(player):
		return
	var p: Vector3 = _spawn_point(_respawn_team, Net.my_id())
	player.global_position = p
	player.velocity = Vector3.ZERO
	player.health = 100.0
	player.last_attacker = null
	_stop_spectate()
	print("[spawn] игрок возродился на ", p)


# ---------------------------------------------------------------- сетевой бой

## По мне попал живой игрок. Урон прислал хост, поэтому он общий для всех.
func _on_hit_received(damage: float, attacker_id: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not player.is_alive():
		return
	_last_attacker_id = attacker_id
	player.take_damage(damage)


## Хост сообщил, кого и кем убили. Считаем фраг только у убийцы.
func _on_net_killed(victim_id: int, killer_id: int) -> void:
	var victim_name := _nick_of(victim_id)
	var killer_name := _nick_of(killer_id)

	if _hud != null and is_instance_valid(_hud):
		_hud.add_kill(killer_name, victim_name)

	if victim_id == Net.my_id():
		_last_attacker_id = killer_id
		# Пакет с последним попаданием мог не дойти — добиваем локально,
		# чтобы экран смерти точно появился.
		if player != null and is_instance_valid(player) and player.is_alive():
			player.take_damage(999.0)
		return

	var ghost = ghosts.get(victim_id)
	if ghost != null and is_instance_valid(ghost):
		ghost.call("set_network_dead", true)

	if killer_id != Net.my_id():
		return

	frags += 1
	if _hud != null and is_instance_valid(_hud):
		_hud.set_frags(frags)
	if player != null and is_instance_valid(player):
		player.money += KILL_REWARD
		print("[eco] +", KILL_REWARD, " за сетевой фраг, всего ", player.money)


## Хост вернул игрока в бой.
func _on_net_respawned(victim_id: int) -> void:
	if victim_id == Net.my_id():
		if player == null or not is_instance_valid(player):
			return
		var p: Vector3 = _spawn_point(_respawn_team, Net.my_id())
		player.global_position = p
		player.velocity = Vector3.ZERO
		player.health = 100.0
		player.last_attacker = null
		_last_attacker_id = 0
		_stop_spectate()
		print("[spawn] сетевой респавн на ", p)
		return

	var ghost = ghosts.get(victim_id)
	if ghost != null and is_instance_valid(ghost):
		ghost.call("set_network_dead", false)
		var data: Dictionary = Net.players.get(victim_id, {})
		ghost.global_position = _spawn_point(int(data.get("team", 0)), victim_id)


func _nick_of(id: int) -> String:
	if Net.players.has(id):
		return str(Net.players[id].get("nick", "Игрок"))
	if ghosts.has(id) and is_instance_valid(ghosts[id]):
		return str(ghosts[id].nick)
	return "Игрок"
