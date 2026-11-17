extends Node
## Сетевое лобби: состав игроков, команды, выбор карты, старт матча.
## Autoload. RPC идут через этот узел, поэтому путь у всех одинаковый.

signal players_changed
signal state_received(peer_id: int, pos: Vector3, yaw: float, pitch: float)
signal connection_lost

const GAME_PORT := 7778
const BROADCAST_PORT := 7777
const MAX_PLAYERS := 10

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


func start_match() -> void:
	if not is_host:
		return
	if players.size() < 1:
		return
	in_match = true
	start_client.rpc(map_id, players)
	start_client(map_id, players)


# ---------------------------------------------------------------- RPC

@rpc("any_peer", "call_remote", "reliable")
func register_player(nick: String, uid: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = {"nick": nick, "uid": uid, "team": _smaller_team()}
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
func apply_state(state: Dictionary, selected_map: String) -> void:
	players = state
	map_id = selected_map
	players_changed.emit()


@rpc("authority", "call_remote", "reliable")
func start_client(selected_map: String, state: Dictionary) -> void:
	map_id = selected_map
	players = state
	in_match = true
	get_tree().change_scene_to_file("res://game.tscn")


@rpc("any_peer", "call_remote", "unreliable_ordered")
func push_state(pos: Vector3, yaw: float, pitch: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	state_received.emit(id, pos, yaw, pitch)


# ---------------------------------------------------------------- служебное

func _push_state() -> void:
	apply_state.rpc(players, map_id)
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
	_push_state()
