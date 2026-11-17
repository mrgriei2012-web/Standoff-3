extends Node
## Сетевое лобби: состав игроков, команды, выбор карты, старт матча.
## Autoload. RPC идут через этот узел, поэтому путь у всех одинаковый.

signal players_changed
signal state_received(peer_id: int, pos: Vector3, yaw: float, pitch: float)
signal connection_lost

## Боевые события сетевых игроков. Решает всё хост.
signal hit_received(damage: float, attacker_id: int)
signal player_killed(victim_id: int, killer_id: int)
signal player_respawned(victim_id: int)

## Режимы и счёт матча.
signal score_changed(a: int, b: int)
signal bomb_event(kind: String, pos: Vector3)
signal round_result(winner: int, reason: String)

const MODES := ["dm", "tdm", "bomb", "hvh"]

const GAME_PORT := 7778
const BROADCAST_PORT := 7777
const MAX_PLAYERS := 10

## Сколько секунд лежим после смерти.
const RESPAWN_DELAY := 3.0

## peer_id -> жив ли. Авторитет только у хоста.
var alive_state: Dictionary = {}

## "dm" — все против всех, "tdm" — командный бой, "bomb" — закладка бомбы.
var mode := "dm"
## Читы для всех в этом матче (без ESP по живым игрокам).
var cheats := false
## [альфа, браво]
var score := [0, 0]

var players: Dictionary = {}   # peer_id -> { nick, uid, team }
var map_id := "arena"
var is_host := false
var in_match := false

var _bcast := PacketPeerUDP.new()
var _bcast_accum := 0.0


func _ready() -> void:
	_bcast.set_broadcast_enabled(true)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


# ---------------------------------------------------------------- создание / вход

func host_game(nick: String, uid: String) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_PLAYERS)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	is_host = true
	players = {1: {"nick": nick, "uid": uid, "team": 0}}
	players_changed.emit()
	return OK


func join_game(ip: String) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, GAME_PORT)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	is_host = false

	# пока не пришёл состав — показываем себя, чтобы экран не был пустым
	players = {}
	players_changed.emit()
	return OK


func leave() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	alive_state.clear()
	is_host = false
	in_match = false


func my_id() -> int:
	if multiplayer.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return 1


func team_count(team: int) -> int:
	var n := 0
	for id in players.keys():
		if int(players[id].get("team", 0)) == team:
			n += 1
	return n


# ---------------------------------------------------------------- запросы игроков

func request_team(team: int) -> void:
	var t := clampi(team, 0, 1)
	if is_host:
		players[1]["team"] = t
		_push_state()
		players_changed.emit()
	else:
		set_team.rpc_id(1, t)


func set_map(id: String) -> void:
	if not is_host:
		return
	map_id = id
	_push_state()


## Режим матча: dm / tdm / bomb.
func set_mode(id: String) -> void:
	if not is_host:
		return
	if not MODES.has(id):
		return
	mode = id
	_push_state()


## Читы для всех участников этого матча.
func set_cheats(on: bool) -> void:
	if not is_host:
		return
	cheats = on
	_push_state()


func start_match() -> void:
	if not is_host:
		return
	if players.size() < 1:
		return
	in_match = true
	reset_combat()
	score = [0, 0]
	start_client.rpc(map_id, players, mode, cheats)
	start_client(map_id, players, mode, cheats)


# ---------------------------------------------------------------- RPC

@rpc("any_peer", "call_remote", "reliable")
func register_player(nick: String, uid: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = {"nick": nick, "uid": uid, "team": _smaller_team()}
	alive_state[id] = true
	_push_state()


@rpc("any_peer", "call_remote", "reliable")
func set_team(team: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id]["team"] = clampi(team, 0, 1)
		_push_state()


@rpc("authority", "call_remote", "reliable")
func apply_state(state: Dictionary, selected_map: String, selected_mode: String, cheat_flag: bool) -> void:
	players = state
	map_id = selected_map
	mode = selected_mode
	cheats = cheat_flag
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func start_client(selected_map: String, state: Dictionary, selected_mode: String, cheat_flag: bool) -> void:
	map_id = selected_map
	players = state
	mode = selected_mode
	cheats = cheat_flag
	in_match = true
	reset_combat()
	get_tree().change_scene_to_file("res://game.tscn")


@rpc("any_peer", "call_remote", "unreliable_ordered")
func push_state(pos: Vector3, yaw: float, pitch: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	state_received.emit(id, pos, yaw, pitch)


# ---------------------------------------------------------------- бой по сети

## Идёт ли сейчас сетевой матч.
func networked() -> bool:
	return in_match and multiplayer.has_multiplayer_peer()


## Сброс состояния «жив/убит» на старте матча.
func reset_combat() -> void:
	alive_state.clear()
	for id in players.keys():
		alive_state[int(id)] = true


## Я попал в игрока. Клиент шлёт хосту, хост передаёт жертве.
func report_hit(victim_id: int, damage: float) -> void:
	if not networked():
		return
	if multiplayer.is_server():
		_accept_hit(my_id(), victim_id, damage)
	else:
		hit_request.rpc_id(1, victim_id, damage)


@rpc("any_peer", "call_remote", "reliable")
func hit_request(victim_id: int, damage: float) -> void:
	if not multiplayer.is_server():
		return
	_accept_hit(multiplayer.get_remote_sender_id(), victim_id, damage)


func _accept_hit(attacker_id: int, victim_id: int, damage: float) -> void:
	if attacker_id == victim_id:
		return
	if not alive_state.get(victim_id, false):
		return
	if not players.has(victim_id):
		return

	var dmg := clampf(damage, 1.0, 100.0)

	# Хост — сам себе жертва, rpc_id(1) до себя не дойдёт.
	if victim_id == 1:
		hit_received.emit(dmg, attacker_id)
	else:
		hit_client.rpc_id(victim_id, dmg, attacker_id)


@rpc("authority", "call_remote", "reliable")
func hit_client(damage: float, attacker_id: int) -> void:
	hit_received.emit(damage, attacker_id)


## Жертва сообщает хосту, что умерла. Кто убил — решает хост.
func report_death(killer_id: int) -> void:
	if not networked():
		return
	if multiplayer.is_server():
		_accept_death(my_id(), killer_id)
	else:
		death_request.rpc_id(1, killer_id)


@rpc("any_peer", "call_remote", "reliable")
func death_request(killer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_accept_death(multiplayer.get_remote_sender_id(), killer_id)


func _accept_death(victim_id: int, killer_id: int) -> void:
	# второй раз за тот же труп не платим
	if not alive_state.get(victim_id, false):
		return
	alive_state[victim_id] = false

	if mode == "tdm":
		_tdm_point(victim_id, killer_id)

	player_killed.emit(victim_id, killer_id)
	player_killed_rpc.rpc(victim_id, killer_id)

	await get_tree().create_timer(RESPAWN_DELAY).timeout
	_respawn_peer(victim_id)


## Командный бой: очко получает команда убийцы, свои не в счёт.
func _tdm_point(victim_id: int, killer_id: int) -> void:
	var victim_team := int(players.get(victim_id, {}).get("team", 0))
	var killer_team := int(players.get(killer_id, {}).get("team", 0))
	if killer_team == victim_team:
		return
	score[killer_team] += 1
	score_changed.emit(score[0], score[1])
	if networked():
		score_sync.rpc(score[0], score[1])


@rpc("authority", "call_remote", "reliable")
func score_sync(a: int, b: int) -> void:
	score = [a, b]
	score_changed.emit(a, b)


## Хост разослал событие бомбы (заложена / разминирована / взорвалась / сброс).
func bomb_e(kind: String, pos: Vector3 = Vector3.ZERO) -> void:
	bomb_event.emit(kind, pos)
	if networked():
		bomb_rpc.rpc(kind, pos)


@rpc("authority", "call_remote", "reliable")
func bomb_rpc(kind: String, pos: Vector3) -> void:
	bomb_event.emit(kind, pos)


## Игрок закончил закладку или разминирование — сообщаем хосту.
func report_bomb(kind: String, pos: Vector3) -> void:
	if not networked():
		bomb_event.emit(kind, pos)
		return
	if multiplayer.is_server():
		bomb_e(kind, pos)
	else:
		bomb_request.rpc_id(1, kind, pos)


@rpc("any_peer", "call_remote", "reliable")
func bomb_request(kind: String, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	bomb_e(kind, pos)


## Конец раунда: очко победителю и оповещение всем.
func finish_round(winner: int, reason: String) -> void:
	score[clampi(winner, 0, 1)] += 1
	round_result.emit(winner, reason)
	score_changed.emit(score[0], score[1])
	if networked():
		round_result_rpc.rpc(winner, reason)
		score_sync.rpc(score[0], score[1])


@rpc("authority", "call_remote", "reliable")
func round_result_rpc(winner: int, reason: String) -> void:
	round_result.emit(winner, reason)


func _respawn_peer(victim_id: int) -> void:
	if not players.has(victim_id):
		alive_state.erase(victim_id)
		return
	alive_state[victim_id] = true
	player_respawned.emit(victim_id)
	player_respawned_rpc.rpc(victim_id)


@rpc("authority", "call_remote", "reliable")
func player_killed_rpc(victim_id: int, killer_id: int) -> void:
	player_killed.emit(victim_id, killer_id)


@rpc("authority", "call_remote", "reliable")
func player_respawned_rpc(victim_id: int) -> void:
	player_respawned.emit(victim_id)


# ---------------------------------------------------------------- служебное

func _push_state() -> void:
	apply_state.rpc(players, map_id, mode, cheats)
	players_changed.emit()


## Хост раз в секунду вещает в сеть, чтобы его лобби было видно в меню.
func _process(delta: float) -> void:
	if not is_host:
		return

	_bcast_accum += delta
	if _bcast_accum < 1.0:
		return
	_bcast_accum = 0.0

	var payload := JSON.stringify({
		"game": "fps_proto",
		"name": Profile.nickname,
		"port": GAME_PORT,
	})
	_bcast.set_dest_address("255.255.255.255", BROADCAST_PORT)
	_bcast.put_packet(payload.to_utf8_buffer())


func _smaller_team() -> int:
	return 0 if team_count(0) <= team_count(1) else 1


func _on_connected() -> void:
	register_player.rpc_id(1, Profile.nickname, Profile.uid)


func _on_connection_failed() -> void:
	connection_lost.emit()


func _on_server_disconnected() -> void:
	players.clear()
	is_host = false
	in_match = false
	connection_lost.emit()


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players.erase(id)
	alive_state.erase(id)
	_push_state()
