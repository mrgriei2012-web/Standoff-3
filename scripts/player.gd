extends CharacterBody3D
## Игрок от первого лица: WASD на ПК, джойстик и свайп на телефоне.

const WeaponScript := preload("res://scripts/weapon.gd")

const SPEED := 6.0
const JUMP := 4.6
const GRAVITY := 18.0
const LOOK_BASE := 0.0024
const CLIMB_SPEED := 2.6
const FLY_SPEED := 12.0

var camera: Camera3D
var weapon

signal died

var pitch := 0.0
var fire_held := false
var crouch_held := false
var money := 1600
var health := 100.0
var input_locked := false
var last_attacker: Node = null
var climbing := false
var _wall_time := 0.0
var _jump_queued := false
var _net_accum := 0.0

var _joy_id := -1
var _joy_origin := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _look_id := -1

var _joy_base: Panel
var _joy_knob: Panel


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)

	camera = Camera3D.new()
	camera.position = Vector3(0, 1.62, 0)
	camera.fov = 82.0
	camera.current = true
	add_child(camera)

	weapon = WeaponScript.new()
	camera.add_child(weapon)
	weapon.shooter = self

	_build_joystick()


## Видимый джойстик под пальцем: база 140 px и шарик.
func _build_joystick() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_joy_base = Panel.new()
	_joy_base.size = Vector2(140, 140)
	_joy_base.visible = false
	_joy_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_base.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.07), 70, Color(1, 1, 1, 0.22), 2))
	root.add_child(_joy_base)

	_joy_knob = Panel.new()
	_joy_knob.size = Vector2(62, 62)
	_joy_knob.position = Vector2(39, 39)
	_joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_knob.add_theme_stylebox_override("panel", UITheme.box(Color(1, 0.54, 0, 0.45), 31, UITheme.ACCENT, 2))
	_joy_base.add_child(_joy_knob)


func set_fire(value: bool) -> void:
	fire_held = value


func request_jump() -> void:
	_jump_queued = true


func set_crouch(value: bool) -> void:
	crouch_held = value


## Покупка оружия. Возвращает true, если денег хватило.
func buy(i: int) -> bool:
	if weapon == null:
		return false
	var cost: int = weapon.price(i)
	if money < cost:
		return false
	money -= cost
	weapon.equip(i)
	return true


func is_alive() -> bool:
	return health > 0.0


## Кто последним попал — для киллфида.
func set_last_attacker(who: Node) -> void:
	last_attacker = who


## Урон от ботов. Бессмертие из секретов отменяет его целиком.
func take_damage(amount: float) -> void:
	if not is_alive():
		return
	if Settings.god_mode:
		return
	health -= amount
	if health <= 0.0:
		health = 0.0
		died.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_look(event.relative)
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			var half_w: float = get_viewport().get_visible_rect().size.x * 0.4
			if event.position.x < half_w:
				_joy_id = event.index
				_joy_origin = event.position
				_show_joy(event.position)
				_update_joy(event.position)
			else:
				_look_id = event.index
		else:
			if event.index == _joy_id:
				_joy_id = -1
				_hide_joy()
			elif event.index == _look_id:
				_look_id = -1
		return

	if event is InputEventScreenDrag:
		if event.index == _joy_id:
			_update_joy(event.position)
		elif event.index == _look_id:
			_look(event.relative)


func _look(rel: Vector2) -> void:
	var s: float = LOOK_BASE * Settings.sensitivity
	rotate_y(-rel.x * s)
	pitch = clampf(pitch - rel.y * s, deg_to_rad(-85.0), deg_to_rad(85.0))
	camera.rotation.x = pitch


func _update_joy(pos: Vector2) -> void:
	var v := (pos - _joy_origin) / 90.0
	_joy_vec = v.limit_length(1.0)
	if _joy_knob != null:
		_joy_knob.position = Vector2(39, 39) + _joy_vec * 45.0


func _show_joy(pos: Vector2) -> void:
	if _joy_base == null:
		return
	_joy_base.position = pos - Vector2(70, 70)
	_joy_base.visible = true


func _hide_joy() -> void:
	if _joy_base != null:
		_joy_base.visible = false
	_joy_vec = Vector2.ZERO


func _physics_process(delta: float) -> void:
	var want_crouch: bool = Input.is_action_pressed("crouch") or crouch_held
	var target_y := 1.12 if want_crouch else 1.62
	camera.position.y = lerpf(camera.position.y, target_y, clampf(delta * 10.0, 0.0, 1.0))

	# Секрет «сквозь стены»: летим свободно, физику пропускаем.
	if Settings.noclip:
		_fly(delta)
		return

	var forward: bool = Input.is_action_pressed("move_forward") or _joy_vec.y < -0.3
	var back: bool = Input.is_action_pressed("move_back") or _joy_vec.y > 0.3

	# --- лестницы: стена перед лицом + держим вперёд = лезем.
	var wall_mid := _wall_ahead(1.0)     # настоящая стена, а не бордюр
	var wall_low := _wall_ahead(0.3)

	if wall_mid != Vector3.ZERO and forward:
		_wall_time += delta
	else:
		_wall_time = maxf(0.0, _wall_time - delta * 3.0)

	if _wall_time > 0.2:
		climbing = true
	if climbing and wall_low == Vector3.ZERO:
		climbing = false   # стена кончилась — дальше обычное падение
	if climbing and not forward and not back:
		climbing = false   # отпустили — падаем

	if climbing:
		_jump_queued = false
		if forward:
			velocity.y = CLIMB_SPEED
		elif back:
			velocity.y = -CLIMB_SPEED * 0.8
		else:
			velocity.y = 0.0

		# прижимаемся к стене по направлению взгляда, чтобы не оторваться
		var face := -global_transform.basis.z
		face.y = 0.0
		face = face.normalized()
		velocity.x = face.x * 1.6
		velocity.z = face.z * 1.6
		move_and_slide()

		# Ноги поднялись выше края — перелезаем на площадку.
		if forward and _wall_ahead(0.3) == Vector3.ZERO:
			climbing = false
			_wall_time = 0.0
			velocity.x = face.x * 4.5
			velocity.z = face.z * 4.5
			move_and_slide()
		return

	if is_on_floor():
		if Input.is_action_just_pressed("jump") or _jump_queued:
			velocity.y = JUMP * (1.7 if Settings.super_jump else 1.0)
	else:
		velocity.y -= GRAVITY * delta
	_jump_queued = false

	var speed := (3.2 if want_crouch else SPEED) * (1.6 if Settings.speed_boost else 1.0)

	var ix: float = Input.get_axis("move_left", "move_right") + _joy_vec.x
	var iz: float = Input.get_axis("move_forward", "move_back") + _joy_vec.y
	var dir := Vector3(ix, 0, iz).limit_length(1.0)
	var move := global_transform.basis * dir * speed

	velocity.x = move.x
	velocity.z = move.z
	move_and_slide()


## Полёт сквозь стены (секрет из настроек, для соло с ботами).
func _fly(delta: float) -> void:
	var ix: float = Input.get_axis("move_left", "move_right") + _joy_vec.x
	var iz: float = Input.get_axis("move_forward", "move_back") + _joy_vec.y
	var dir := (global_transform.basis * Vector3(ix, 0, iz)).limit_length(1.0)
	var up: float = 1.0 if Input.is_action_pressed("jump") else 0.0
	var down: float = 1.0 if Input.is_action_pressed("crouch") else 0.0
	global_position += (dir + Vector3.UP * (up - down)) * FLY_SPEED * delta
	velocity = Vector3.ZERO
	climbing = false
	_jump_queued = false


## Нормаль стены на высоте height, если она в 0.75 м перед игроком.
func _wall_ahead(height: float) -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, height, 0)
	var dir := -global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 0.75)
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return Vector3.ZERO
	var n: Vector3 = hit.get("normal", Vector3.UP)
	if absf(n.y) > 0.55:
		return Vector3.ZERO   # пол, потолок или склон — не лестница
	return n


func _process(delta: float) -> void:
	if input_locked:
		pass
	elif Input.is_action_pressed("shoot") or fire_held:
		weapon.try_shoot()
	if not input_locked and Input.is_action_just_pressed("reload"):
		weapon.reload()

	for i in 5:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			buy(i)

	# 16 раз в секунду сообщаем остальным, где мы и куда смотрим.
	_net_accum += delta
	if _net_accum >= 0.06 and multiplayer.has_multiplayer_peer():
		_net_accum = 0.0
		Net.push_state.rpc(global_position, rotation.y, pitch)
