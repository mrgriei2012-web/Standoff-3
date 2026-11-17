extends Control
## Комната лобби: список игроков, команды, выбор карты (у хоста), старт.

const MAPS := [
	["arena", "Арена (кубы)"],
	["sendstone", "Сендстоун"],
	["polygon", "Полигон"],
]

const TEAM_NAMES := ["АЛЬФА", "БРАВО"]
const TEAM_COLORS := [Color("ff6b3d"), Color("4aa3ff")]
const MODE_NAMES := ["Все против всех", "Командный бой", "Закладка бомбы", "ХВХ (читы)"]

var _players_box: VBoxContainer
var _map_opt: OptionButton
var _mode_opt: OptionButton
var _cheats_check: CheckBox
var _start_btn: Button
var _host_box: VBoxContainer
var _status: Label
var _ip_label: Label


func _ready() -> void:
	_build()
	Net.players_changed.connect(_refresh)
	Net.connection_lost.connect(_on_lost)
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var page := ScrollContainer.new()
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(page)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	page.add_child(box)

	# верхняя строка
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	box.add_child(top)

	top.add_child(UITheme.heading("Лобби", 24))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	_ip_label = UITheme.caption("")
	top.add_child(_ip_label)

	var leave := UITheme.button("Выйти", false, 13)
	leave.custom_minimum_size = Vector2(110, 40)
	leave.pressed.connect(_on_leave)
	top.add_child(leave)

	_status = UITheme.label("Подключение…", 14, UITheme.DIM)
	box.add_child(_status)

	# игроки
	var card := UITheme.card()
	card.custom_minimum_size = Vector2(0, 180)
	box.add_child(card)

	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 8)
	card.add_child(card_box)
	card_box.add_child(UITheme.section("Игроки"))

	_players_box = VBoxContainer.new()
	_players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players_box.add_theme_constant_override("separation", 6)
	card_box.add_child(_players_box)

	# своя команда
	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 8)
	box.add_child(team_row)
	team_row.add_child(UITheme.caption("Твоя команда:"))

	var a_btn := UITheme.button(TEAM_NAMES[0], false, 13)
	a_btn.custom_minimum_size = Vector2(120, 40)
	a_btn.pressed.connect(Net.request_team.bind(0))
	team_row.add_child(a_btn)

	var b_btn := UITheme.button(TEAM_NAMES[1], false, 13)
	b_btn.custom_minimum_size = Vector2(120, 40)
	b_btn.pressed.connect(Net.request_team.bind(1))
	team_row.add_child(b_btn)

	# хост-панель
	_host_box = VBoxContainer.new()
	_host_box.add_theme_constant_override("separation", 8)
	box.add_child(_host_box)

	_host_box.add_child(UITheme.section("Матч"))

	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 10)
	_host_box.add_child(map_row)

	var map_label := UITheme.label("Карта", 15)
	map_row.add_child(map_label)

	var labels: Array = []
	for entry in MAPS:
		labels.append(str(entry[1]))

	_map_opt = UITheme.option(labels, 0)
	_map_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_opt.item_selected.connect(_on_map_selected)
	map_row.add_child(_map_opt)

	# режим матча
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	_host_box.add_child(mode_row)
	mode_row.add_child(UITheme.label("Режим", 15))

	_mode_opt = UITheme.option(MODE_NAMES, 0)
	_mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_opt.item_selected.connect(_on_mode_selected)
	mode_row.add_child(_mode_opt)

	_cheats_check = CheckBox.new()
	_cheats_check.text = "Читы для всех (без ESP)"
	_cheats_check.add_theme_font_size_override("font_size", 14)
	_cheats_check.toggled.connect(_on_cheats)
	_host_box.add_child(_cheats_check)

	_start_btn = UITheme.button("НАЧАТЬ МАТЧ", true, 17)
	_start_btn.custom_minimum_size = Vector2(0, 56)
	_start_btn.pressed.connect(Net.start_match)
	_host_box.add_child(_start_btn)

	# быстрый соло-тест карты, без второго игрока
	var solo := UITheme.button("СОЛО-ТЕСТ: СЕНДСТОУН", false, 14)
	solo.custom_minimum_size = Vector2(0, 46)
	solo.pressed.connect(_on_solo)
	_host_box.add_child(solo)


func _on_solo() -> void:
	if not Net.is_host:
		return
	Net.set_map("sendstone")
	Net.start_match()


func _refresh() -> void:
	if _players_box == null:
		return

	for child in _players_box.get_children():
		_players_box.remove_child(child)
		child.queue_free()

	if Net.players.is_empty():
		_players_box.add_child(UITheme.caption("Ждём данные от хоста…"))
	else:
		var my := Net.my_id()
		for id in Net.players.keys():
			_players_box.add_child(_make_row(int(id), Net.players[id], int(id) == my))

	var is_host := Net.is_host
	_host_box.visible = is_host

	if is_host:
		_ip_label.text = "IP: %s:%d" % [_local_ip(), Net.GAME_PORT]
		_set_map_selection(Net.map_id)
		_set_mode_selection(Net.mode)
		if _cheats_check != null:
			_cheats_check.button_pressed = Net.cheats
	else:
		_ip_label.text = "ждём хоста"

	_status.text = "Ты хост. Выбери карту и жми «Начать матч»." if is_host else "Ждём, пока хост начнёт матч."

	_update_counts()


func _make_row(id: int, data: Dictionary, is_me: bool) -> Control:
	var row := PanelContainer.new()
	var accent: Color = TEAM_COLORS[clampi(int(data.get("team", 0)), 0, 1)]
	row.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL_ALT, 8, accent, 2))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)

	var nick := UITheme.label(str(data.get("nick", "Игрок")), 15)
	nick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nick)

	if is_me:
		h.add_child(UITheme.label("это ты", 11, UITheme.DIM))

	var team := UITheme.label(TEAM_NAMES[clampi(int(data.get("team", 0)), 0, 1)], 12, accent)
	h.add_child(team)

	return row


func _update_counts() -> void:
	var text := "АЛЬФА %d   •   БРАВО %d" % [Net.team_count(0), Net.team_count(1)]
	_status.text = text


func _set_map_selection(id: String) -> void:
	for i in MAPS.size():
		if str(MAPS[i][0]) == id:
			if _map_opt.selected != i:
				_map_opt.selected = i
			return


func _set_mode_selection(id: String) -> void:
	for i in Net.MODES.size():
		if str(Net.MODES[i]) == id:
			if _mode_opt != null and _mode_opt.selected != i:
				_mode_opt.selected = i
			return


func _on_map_selected(index: int) -> void:
	if Net.is_host:
		Net.set_map(str(MAPS[index][0]))


func _on_mode_selected(index: int) -> void:
	if not Net.is_host or index < 0 or index >= Net.MODES.size():
		return
	Net.set_mode(str(Net.MODES[index]))
	# ХВХ — это тот же deathmatch, но с включённым меню читов.
	if str(Net.MODES[index]) == "hvh" and _cheats_check != null:
		_cheats_check.button_pressed = true
		Net.set_cheats(true)


func _on_cheats(on: bool) -> void:
	if Net.is_host:
		Net.set_cheats(on)


func _on_leave() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://main.tscn")


func _on_lost() -> void:
	if _status != null:
		_status.text = "Соединение потеряно"


func _local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	return "127.0.0.1"
