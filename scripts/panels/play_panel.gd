extends VBoxContainer
## Экран "Играть": создать лобби, найти лобби в сети, подключиться по IP.

const BROADCAST_PORT := 7777
const LOBBY_TTL_MS := 4000

const MAPS := [
	["arena", "Арена (кубы)"],
	["sendstone", "Сендстоун"],
	["polygon", "Полигон"],
]

var _listen := PacketPeerUDP.new()

var _lobbies: Dictionary = {}
var _list_dirty := false

var _ip_edit: LineEdit
var _status: Label
var _lobby_box: VBoxContainer
var _map_opt: OptionButton
var _map_id := "sendstone"


func _ready() -> void:
	_build()
	_listen.bind(BROADCAST_PORT)
	Net.connection_lost.connect(_on_lost)


func _build() -> void:
	add_theme_constant_override("separation", 12)
	add_child(UITheme.heading("Сетевая игра"))
	add_child(UITheme.caption("Хост ищется по локальной сети или вручную по IP. Через ZeroTier поиск работает так же."))

	var host_card := UITheme.card()
	add_child(host_card)

	var host_box := VBoxContainer.new()
	host_box.add_theme_constant_override("separation", 10)
	host_card.add_child(host_box)

	var host_btn := UITheme.button("СОЗДАТЬ ЛОББИ", true, 16)
	host_btn.pressed.connect(_on_host_pressed)
	host_box.add_child(host_btn)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	host_box.add_child(join_row)

	_ip_edit = UITheme.line_edit("IP хоста, например 192.168.1.10")
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(_ip_edit)

	var join_btn := UITheme.button("Подключиться")
	join_btn.pressed.connect(_on_join_pressed)
	join_row.add_child(join_btn)

	var test_btn := UITheme.button("БЫСТРО: АРЕНА", false, 14)
	test_btn.pressed.connect(_on_test_pressed)
	host_box.add_child(test_btn)

	# соло-тест карты, без лобби и второго игрока
	var solo_card := UITheme.card()
	add_child(solo_card)

	var solo_box := VBoxContainer.new()
	solo_box.add_theme_constant_override("separation", 10)
	solo_card.add_child(solo_box)

	solo_box.add_child(UITheme.section("Соло-тест карты"))

	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 10)
	solo_box.add_child(map_row)

	map_row.add_child(UITheme.label("Карта", 15))

	var labels: Array = []
	for entry in MAPS:
		labels.append(str(entry[1]))

	_map_opt = UITheme.option(labels, 1)
	_map_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_opt.item_selected.connect(_on_map_selected)
	map_row.add_child(_map_opt)

	var play_btn := UITheme.button("СОЛО: ИГРАТЬ", true, 16)
	play_btn.pressed.connect(_on_solo_pressed)
	solo_box.add_child(play_btn)

	var list_card := UITheme.card()
	list_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(list_card)

	var list_box := VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 8)
	list_card.add_child(list_box)

	list_box.add_child(UITheme.section("Лобби в сети"))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_box.add_child(scroll)

	_lobby_box = VBoxContainer.new()
	_lobby_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_lobby_box)

	_status = UITheme.label("Готово к подключению", 14, UITheme.DIM)
	add_child(_status)

	_rebuild_lobby_list()


func on_show() -> void:
	_rebuild_lobby_list()


# ---------------------------------------------------------------- поиск лобби

func _process(_delta: float) -> void:
	_poll_packets()

	var now := Time.get_ticks_msec()
	var stale: Array = []
	for ip in _lobbies.keys():
		if now - int(_lobbies[ip]["last"]) > LOBBY_TTL_MS:
			stale.append(ip)
	for ip in stale:
		_lobbies.erase(ip)
		_list_dirty = true

	if _list_dirty:
		_list_dirty = false
		_rebuild_lobby_list()


func _poll_packets() -> void:
	while _listen.get_available_packet_count() > 0:
		var pkt := _listen.get_packet()
		var ip := _listen.get_packet_ip()

		if ip.is_empty() or ip == "127.0.0.1":
			continue

		var data: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(data) != TYPE_DICTIONARY:
			continue

		var d: Dictionary = data
		if str(d.get("game", "")) != "fps_proto":
			continue

		_lobbies[ip] = {
			"name": str(d.get("name", "Лобби")),
			"last": Time.get_ticks_msec(),
		}
		_list_dirty = true


func _rebuild_lobby_list() -> void:
	if _lobby_box == null:
		return

	for child in _lobby_box.get_children():
		_lobby_box.remove_child(child)
		child.queue_free()

	if _lobbies.is_empty():
		var empty := UITheme.caption("Пока никого. Создай лобби или введи IP вручную.")
		empty.custom_minimum_size = Vector2(0, 40)
		_lobby_box.add_child(empty)
		return

	for ip in _lobbies.keys():
		var entry: Dictionary = _lobbies[ip]
		var btn := UITheme.button("%s    —    %s" % [str(entry["name"]), ip])
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_join.bind(ip))
		_lobby_box.add_child(btn)


# ---------------------------------------------------------------- действия

func _on_host_pressed() -> void:
	var err := Net.host_game(Profile.nickname, Profile.uid)
	if err != OK:
		_set_status("Сервер не создался: %s" % error_string(err))
		return
	get_tree().change_scene_to_file("res://lobby.tscn")


func _on_join_pressed() -> void:
	var ip := _ip_edit.text.strip_edges()
	if ip.is_empty():
		_set_status("Введи IP хоста")
		return
	_join(ip)


func _join(ip: String) -> void:
	var err := Net.join_game(ip)
	if err != OK:
		_set_status("Не подключиться: %s" % error_string(err))
		return
	get_tree().change_scene_to_file("res://lobby.tscn")


func _on_test_pressed() -> void:
	Net.leave()
	Net.map_id = "arena"
	get_tree().change_scene_to_file("res://game.tscn")


func _on_map_selected(index: int) -> void:
	_map_id = str(MAPS[clampi(index, 0, MAPS.size() - 1)][0])


func _on_solo_pressed() -> void:
	Net.leave()
	Net.map_id = _map_id
	get_tree().change_scene_to_file("res://game.tscn")


func _on_lost() -> void:
	_set_status("Соединение потеряно")


func _set_status(text: String) -> void:
	if _status:
		_status.text = text
