extends CharacterBody3D
## Бот: бродит по карте, замечает противника, стреляет очередями, стрейфит,
## держит дистанцию и после смерти возвращается на базу. Никакой навигационной
## сетки — только лучи и немного упорства.

const ActorScript := preload("res://scripts/actor_model.gd")

const SPEED := 4.0
const GRAVITY := 18.0
const SIGHT := 38.0
const EYE := 1.5
const REACTION := 0.30     # сколько секунд «узнаёт» цель перед первым выстрелом
const DAMAGE := 16.0
const RANGE := 60.0
const RESPAWN_TIME := 3.0
const ROAM_RADIUS := 16.0

signal killed(victim, killer)

var nick := "Бот"
var team := 0
var color := Color("ff6b3d")
var health := 100.0
var _attacker: Node = null

var _visual: Node3D
var _shoot_sound: AudioStreamPlayer3D
var _dead := false
var _target: Node3D = null
var _think := 0.0
var _see_time := 0.0
var _shot_cd := 0.0
var _burst := 0
var _strafe_t := 0.0
var _strafe_dir := 1.0
var _roam := Vector3.ZERO
var _home := Vector3.ZERO
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	shape.shape = cap
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)

	# Внешний вид берём тот же, что у моделей игроков, но без собственных
	# коллизий: физику бота считает капсула выше.
	_visual = ActorScript.new()
	_visual.nick = nick
	_visual.team = team
	_visual.color = color
	_visual.collision_layer = 0
	_visual.collision_mask = 0
	add_child(_visual)

	_shoot_sound = AudioStreamPlayer3D.new()
	_shoot_sound.stream = Sfx.shot_stream
	_shoot_sound.unit_size = 14.0
	_shoot_sound.max_distance = 60.0
	add_child(_shoot_sound)

	add_to_group("team_%d" % team)
	_home = global_position
	_last_pos = global_position
	_pick_roam()


func is_alive() -> bool:
	return not _dead


## Кто последним попал — нужно для награды за фраг.
func set_last_attacker(who: Node) -> void:
	_attacker = who


func _physics_process(delta: float) -> void:
	if _dead:
		return

	_think -= delta
	_shot_cd = maxf(_shot_cd - delta, 0.0)
	_strafe_t += delta

	if _think <= 0.0:
		_think = 0.15
		_scan()

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if _can_see_target():
		_see_time += delta
		_attack(delta)
	else:
		_see_time = 0.0
		_target = null
		_wander(delta)

	move_and_slide()
	_check_stuck(delta)


# ---------------------------------------------------------------- восприятие

func _scan() -> void:
	var group := "team_%d" % (1 - team)
	var best: Node3D = null
	var best_dist := SIGHT

	for node in get_tree().get_nodes_in_group(group):
		var n3 := node as Node3D
		if n3 == null or n3 == self:
			continue
		if n3.has_method("is_alive") and not bool(n3.call("is_alive")):
			continue
		var d: float = global_position.distance_to(n3.global_position)
		if d < best_dist:
			best_dist = d
			best = n3

	_target = best


func _can_see_target() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, EYE, 0)
	var to := _target.global_position + Vector3(0, 1.2, 0)
	if from.distance_to(to) > SIGHT:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	return not hit.is_empty() and hit.get("collider") == _target


# ---------------------------------------------------------------- бой

func _attack(delta: float) -> void:
	var to := _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.01:
		return
	var flat := to.normalized()

	# Плавно доворачиваемся на цель, как человек, а не мгновенно.
	var want := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(delta * 7.0, 0.0, 1.0))

	# Держим дистанцию: далеко — подходим, близко — отходим, в норме — стрейфим.
	var move := Vector3.ZERO
	if dist > 14.0:
		move = flat
	elif dist < 5.0:
		move = -flat
	else:
		if _strafe_t > 1.2:
			_strafe_t = 0.0
			_strafe_dir = -_strafe_dir
		move = flat.rotated(Vector3.UP, PI * 0.5 * _strafe_dir)

	velocity.x = move.x * SPEED
	velocity.z = move.z * SPEED

	if _see_time < REACTION or _shot_cd > 0.0:
		return

	_fire()


func _fire() -> void:
	if _burst <= 0:
		_burst = 4

	var from := global_position + Vector3(0, EYE, 0)
	var aim := _target.global_position + Vector3(0, 1.1, 0)
	var dir := (aim - from).normalized()

	# Человеческая неточность: чем дальше, тем сильнее разброс.
	var spread: float = 0.02 + clampf(from.distance_to(aim) / 400.0, 0.0, 0.06)
	dir = (dir + Vector3(
		randf_range(-spread, spread),
		randf_range(-spread, spread),
		randf_range(-spread, spread)
	)).normalized()

	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RANGE)
	q.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if not hit.is_empty():
		var col = hit.get("collider")
		if col != null and col.has_method("take_damage"):
			if col.has_method("set_last_attacker"):
				col.call("set_last_attacker", self)
			col.call("take_damage", DAMAGE)

	_burst -= 1
	_shot_cd = randf_range(0.09, 0.16) if _burst > 0 else randf_range(0.5, 1.0)
	if _shoot_sound != null:
		_shoot_sound.play()


# ---------------------------------------------------------------- движение

func _wander(delta: float) -> void:
	var to := _roam - global_position
	to.y = 0.0
	if to.length() < 1.5:
		_pick_roam()
		return
	var flat := to.normalized()
	var want := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(delta * 4.0, 0.0, 1.0))
	velocity.x = flat.x * SPEED * 0.7
	velocity.z = flat.z * SPEED * 0.7


func _pick_roam() -> void:
	_roam = _home + Vector3(
		randf_range(-ROAM_RADIUS, ROAM_RADIUS),
		0.0,
		randf_range(-ROAM_RADIUS, ROAM_RADIUS)
	)


## Упёрлись в стену и стоим — выбираем другую точку.
func _check_stuck(delta: float) -> void:
	_stuck_t += delta
	if _stuck_t < 0.5:
		return
	_stuck_t = 0.0
	if global_position.distance_to(_last_pos) < 0.15:
		_pick_roam()
	_last_pos = global_position


# ---------------------------------------------------------------- урон

func take_damage(amount: float) -> void:
	if _dead:
		return

	health -= amount
	if _visual != null and _visual.has_method("take_damage"):
		_visual.call("take_damage", 0.0)   # 0 урона — только вспышка модели

	if health <= 0.0:
		_die()


func _die() -> void:
	_dead = true
	health = 0.0
	if _visual != null:
		_visual.visible = false
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	killed.emit(self, _attacker)
	_attacker = null

	await get_tree().create_timer(RESPAWN_TIME).timeout
	_respawn()


func _respawn() -> void:
	health = 100.0
	_dead = false
	_burst = 0
	_shot_cd = 0.0
	_see_time = 0.0
	velocity = Vector3.ZERO
	global_position = _home + Vector3(
		randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5)
	)
	if _visual != null:
		_visual.visible = true
	set_deferred("collision_layer", 1)
	set_deferred("collision_mask", 1)
	_pick_roam()
