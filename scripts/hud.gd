extends CanvasLayer
## Прицел, патроны, кнопки для телефона.

var player
var _ammo_label: Label
var _weapon_status: Label
var _weapon_name: Label
var _money_label: Label
var _buy_root: Control
var _buy_list: VBoxContainer
var _skin_box: VBoxContainer

var _health_bar: ProgressBar
var _health_label: Label
var _hit_marker: Label
var _feed: VBoxContainer
var _frags_label: Label
var _death_box: ColorRect
var _death_label: Label
var _hit_t := 0.0
var _death_t := 0.0

## Режим матча: счёт, таймер, баннер, кнопки бомбы.
signal bomb_press(kind: String)
signal bomb_release

var _score_label: Label
var _round_label: Label
var _banner: Label
var _banner_t := 0.0
var _plant_btn: Button
var _defuse_btn: Button
var _bomb_bar: ProgressBar
var _cheats_badge: Label
var _cheat_btn: Button
var _cheat_root: Control
var _slot_btns: Array = []
var _slot_state := ""


func _ready() -> void:
	_build()
	if player != null and player.weapon != null and player.weapon.has_signal("hit_confirmed"):
		player.weapon.hit_confirmed.connect(_on_hit)
	if player != null and player.has_signal("died"):
		player.died.connect(_on_player_died)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# прицел
	var h := ColorRect.new()
	h.color = Color(1, 1, 1, 0.85)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_preset(Control.PRESET_CENTER)
	h.offset_left = -9
	h.offset_top = -1
	h.offset_right = 9
	h.offset_bottom = 1
	root.add_child(h)

	var v := ColorRect.new()
	v.color = Color(1, 1, 1, 0.85)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.offset_left = -1
	v.offset_top = -9
	v.offset_right = 1
	v.offset_bottom = 9
	root.add_child(v)

	# патроны
	var ammo := Label.new()
	ammo.name = "AmmoLabel"
	ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo.offset_left = -190
	ammo.offset_top = -56
	ammo.offset_right = -24
	ammo.offset_bottom = -20
	ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo.add_theme_font_size_override("font_size", 26)
	ammo.add_theme_color_override("font_color", Color("ffb347"))
	ammo.text = "30 / 120"
	root.add_child(ammo)
	_ammo_label = ammo

	# огонь (для телефона)
	var fire := Button.new()
	fire.text = "ОГОНЬ"
	fire.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fire.offset_left = -160
	fire.offset_top = -200
	fire.offset_right = -30
	fire.offset_bottom = -70
	fire.add_theme_font_size_override("font_size", 14)
	var sb := UITheme.box(Color(1, 0.54, 0, 0.55), 60, UITheme.ACCENT, 2)
	fire.add_theme_stylebox_override("normal", sb)
	fire.add_theme_stylebox_override("hover", UITheme.box(Color(1, 0.54, 0, 0.7), 60, UITheme.ACCENT, 2))
	fire.add_theme_stylebox_override("pressed", UITheme.box(Color(1, 0.54, 0, 0.9), 60, UITheme.ACCENT, 2))
	fire.add_theme_color_override("font_color", Color.WHITE)
	fire.button_down.connect(_on_fire.bind(true))
	fire.button_up.connect(_on_fire.bind(false))
	root.add_child(fire)

	# перезарядка
	var reload := Button.new()
	reload.text = "ПЕРЕЗАРЯДКА"
	reload.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	reload.offset_left = -250
	reload.offset_top = -70
	reload.offset_right = -170
	reload.offset_bottom = -20
	reload.add_theme_font_size_override("font_size", 11)
	var rstyle := UITheme.box(UITheme.PANEL_ALT, 8, UITheme.BORDER)
	reload.add_theme_stylebox_override("normal", rstyle)
	reload.add_theme_stylebox_override("hover", UITheme.box(UITheme.PANEL_ALT.lightened(0.1), 8, UITheme.ACCENT))
	reload.add_theme_stylebox_override("pressed", UITheme.box(UITheme.PANEL_ALT.lightened(0.15), 8, UITheme.ACCENT))
	reload.pressed.connect(_on_reload)
	root.add_child(reload)

	# прыжок
	var jump := Button.new()
	jump.text = "ПРЫЖОК"
	jump.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	jump.offset_left = -285
	jump.offset_top = -170
	jump.offset_right = -190
	jump.offset_bottom = -75
	jump.add_theme_font_size_override("font_size", 11)
	jump.add_theme_stylebox_override("normal", UITheme.box(Color(1, 1, 1, 0.1), 48, Color(1, 1, 1, 0.3), 2))
	jump.add_theme_stylebox_override("hover", UITheme.box(Color(1, 1, 1, 0.16), 48, UITheme.ACCENT, 2))
	jump.add_theme_stylebox_override("pressed", UITheme.box(Color(1, 0.54, 0, 0.5), 48, UITheme.ACCENT, 2))
	jump.pressed.connect(_on_jump)
	root.add_child(jump)

	# присесть (переключатель)
	var crouch := Button.new()
	crouch.text = "ПРИСЕСТЬ"
	crouch.toggle_mode = true
	crouch.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	crouch.offset_left = -285
	crouch.offset_top = -275
	crouch.offset_right = -190
	crouch.offset_bottom = -180
	crouch.add_theme_font_size_override("font_size", 11)
	crouch.add_theme_stylebox_override("normal", UITheme.box(Color(1, 1, 1, 0.1), 48, Color(1, 1, 1, 0.3), 2))
	crouch.add_theme_stylebox_override("hover", UITheme.box(Color(1, 1, 1, 0.16), 48, UITheme.ACCENT, 2))
	crouch.add_theme_stylebox_override("pressed", UITheme.box(Color(1, 0.54, 0, 0.5), 48, UITheme.ACCENT, 2))
	crouch.toggled.connect(_on_crouch)
	root.add_child(crouch)

	# выход
	var exit := Button.new()
	exit.text = "Выход"
	exit.set_anchors_preset(Control.PRESET_TOP_LEFT)
	exit.offset_left = 18
	exit.offset_top = 14
	exit.offset_right = 120
	exit.offset_bottom = 56
	exit.add_theme_stylebox_override("normal", UITheme.box(Color(0, 0, 0, 0.35), 8, UITheme.BORDER))
	exit.add_theme_stylebox_override("hover", UITheme.box(Color(0, 0, 0, 0.5), 8, UITheme.ACCENT))
	exit.pressed.connect(_on_exit)
	root.add_child(exit)

	_weapon_status = Label.new()
	_weapon_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_weapon_status.offset_left = 20
	_weapon_status.offset_top = -46
	_weapon_status.offset_right = 520
	_weapon_status.offset_bottom = -22
	_weapon_status.add_theme_font_size_override("font_size", 12)
	_weapon_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_weapon_status.text = "оружие: …"
	root.add_child(_weapon_status)

	# название оружия
	_weapon_name = Label.new()
	_weapon_name.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_name.offset_left = -220
	_weapon_name.offset_top = -92
	_weapon_name.offset_right = -30
	_weapon_name.offset_bottom = -60
	_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_name.add_theme_font_size_override("font_size", 15)
	_weapon_name.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_weapon_name.text = "Автомат"
	root.add_child(_weapon_name)

	# арсенал: покупка оружия
	var shop := Button.new()
	shop.text = "АРСЕНАЛ"
	shop.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	shop.offset_left = 20
	shop.offset_top = -206
	shop.offset_right = 190
	shop.offset_bottom = -150
	shop.add_theme_font_size_override("font_size", 14)
	shop.add_theme_stylebox_override("normal", UITheme.box(Color(0, 0, 0, 0.4), 8, UITheme.BORDER))
	shop.add_theme_stylebox_override("hover", UITheme.box(Color(0, 0, 0, 0.55), 8, UITheme.ACCENT))
	shop.pressed.connect(_open_buy)
	root.add_child(shop)

	# деньги
	_money_label = Label.new()
	_money_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_money_label.offset_left = 20
	_money_label.offset_top = -90
	_money_label.offset_right = 240
	_money_label.offset_bottom = -46
	_money_label.add_theme_font_size_override("font_size", 26)
	_money_label.add_theme_color_override("font_color", Color("ffcf5c"))
	_money_label.text = "$1600"
	root.add_child(_money_label)

	_build_buy_overlay()
	_build_health(root)
	_build_hit_marker(root)
	_build_feed(root)
	_build_death(root)
	_build_match_ui(root)
	_build_weapon_bar(root)


## Полоска здоровья над деньгами.
func _build_health(root: Control) -> void:
	_health_bar = ProgressBar.new()
	_health_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_health_bar.offset_left = 20
	_health_bar.offset_top = -128
	_health_bar.offset_right = 260
	_health_bar.offset_bottom = -100
	_health_bar.max_value = 100.0
	_health_bar.value = 100.0
	_health_bar.show_percentage = false
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("5ad06a")
	fill.set_corner_radius_all(5)
	_health_bar.add_theme_stylebox_override("fill", fill)

	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.45)
	back.set_corner_radius_all(5)
	_health_bar.add_theme_stylebox_override("background", back)
	root.add_child(_health_bar)

	_health_label = Label.new()
	_health_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_health_label.offset_left = 24
	_health_label.offset_top = -132
	_health_label.offset_right = 260
	_health_label.offset_bottom = -104
	_health_label.add_theme_font_size_override("font_size", 15)
	_health_label.add_theme_color_override("font_color", Color(0, 0, 0, 0.75))
	_health_label.text = "100"
	_health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_health_label)


## Хитмаркер: короткая вспышка крестика в центре, когда пуля попала.
func _build_hit_marker(root: Control) -> void:
	_hit_marker = Label.new()
	_hit_marker.text = "✕"
	_hit_marker.set_anchors_preset(Control.PRESET_CENTER)
	_hit_marker.offset_left = -16
	_hit_marker.offset_top = -22
	_hit_marker.offset_right = 16
	_hit_marker.offset_bottom = 10
	_hit_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hit_marker.add_theme_font_size_override("font_size", 28)
	_hit_marker.add_theme_color_override("font_color", Color("ffd24a"))
	_hit_marker.modulate.a = 0.0
	_hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hit_marker)


## Киллфид в правом верхнем углу.
func _build_feed(root: Control) -> void:
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -380
	_feed.offset_top = 14
	_feed.offset_right = -16
	_feed.offset_bottom = 200
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)

	_frags_label = Label.new()
	_frags_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_frags_label.offset_left = 132
	_frags_label.offset_top = 20
	_frags_label.offset_right = 360
	_frags_label.offset_bottom = 52
	_frags_label.add_theme_font_size_override("font_size", 18)
	_frags_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_frags_label.text = "Фраги: 0"
	_frags_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_frags_label)


## Экран смерти с отсчётом до возрождения.
func _build_death(root: Control) -> void:
	_death_box = ColorRect.new()
	_death_box.color = Color(0.35, 0.03, 0.03, 0.28)
	_death_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_box.visible = false
	root.add_child(_death_box)

	_death_label = Label.new()
	_death_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_label.offset_left = -220
	_death_label.offset_top = -40
	_death_label.offset_right = 220
	_death_label.offset_bottom = 40
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.add_theme_font_size_override("font_size", 34)
	_death_label.add_theme_color_override("font_color", Color(1, 0.85, 0.85))
	_death_label.text = "УБИТ"
	_death_box.add_child(_death_label)


## ---- режим матча: счёт, таймер, бомба, баннер

func _build_match_ui(root: Control) -> void:
	_score_label = Label.new()
	_score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score_label.offset_left = -240
	_score_label.offset_top = 8
	_score_label.offset_right = 240
	_score_label.offset_bottom = 40
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 20)
	_score_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_label.visible = false
	root.add_child(_score_label)

	_round_label = Label.new()
	_round_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_round_label.offset_left = -240
	_round_label.offset_top = 40
	_round_label.offset_right = 240
	_round_label.offset_bottom = 66
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.add_theme_font_size_override("font_size", 15)
	_round_label.add_theme_color_override("font_color", Color("ffcf5c"))
	_round_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_round_label.visible = false
	root.add_child(_round_label)

	_cheats_badge = Label.new()
	_cheats_badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_cheats_badge.offset_left = -240
	_cheats_badge.offset_top = 66
	_cheats_badge.offset_right = 240
	_cheats_badge.offset_bottom = 90
	_cheats_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cheats_badge.add_theme_font_size_override("font_size", 13)
	_cheats_badge.add_theme_color_override("font_color", Color("ff7a45"))
	_cheats_badge.text = "ЧИТЫ ВКЛ"
	_cheats_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cheats_badge.visible = false
	root.add_child(_cheats_badge)

	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -400
	_banner.offset_top = -120
	_banner.offset_right = 400
	_banner.offset_bottom = -40
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 28)
	_banner.add_theme_color_override("font_color", Color("ffd24a"))
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	var bomb_box := VBoxContainer.new()
	bomb_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bomb_box.offset_left = -180
	bomb_box.offset_top = -330
	bomb_box.offset_right = 180
	bomb_box.offset_bottom = -150
	bomb_box.add_theme_constant_override("separation", 8)
	bomb_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bomb_box)

	_bomb_bar = ProgressBar.new()
	_bomb_bar.min_value = 0.0
	_bomb_bar.max_value = 1.0
	_bomb_bar.value = 0.0
	_bomb_bar.show_percentage = false
	_bomb_bar.custom_minimum_size = Vector2(0, 12)
	_bomb_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bomb_bar.visible = false

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color("ff7a45")
	bar_fill.set_corner_radius_all(6)
	_bomb_bar.add_theme_stylebox_override("fill", bar_fill)
	var bar_back := StyleBoxFlat.new()
	bar_back.bg_color = Color(0, 0, 0, 0.5)
	bar_back.set_corner_radius_all(6)
	_bomb_bar.add_theme_stylebox_override("background", bar_back)
	bomb_box.add_child(_bomb_bar)

	_plant_btn = UITheme.button("ЗАЛОЖИТЬ БОМБУ", true, 15)
	_plant_btn.custom_minimum_size = Vector2(0, 52)
	_plant_btn.visible = false
	_plant_btn.button_down.connect(func() -> void: bomb_press.emit("plant"))
	_plant_btn.button_up.connect(func() -> void: bomb_release.emit())
	bomb_box.add_child(_plant_btn)

	_defuse_btn = UITheme.button("РАЗМИНИРОВАТЬ", true, 15)
	_defuse_btn.custom_minimum_size = Vector2(0, 52)
	_defuse_btn.visible = false
	_defuse_btn.button_down.connect(func() -> void: bomb_press.emit("defuse"))
	_defuse_btn.button_up.connect(func() -> void: bomb_release.emit())
	bomb_box.add_child(_defuse_btn)

	# Меню читов: появляется, только если матч запущен с читами.
	_cheat_btn = UITheme.button("ЧИТЫ", false, 13)
	_cheat_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_cheat_btn.offset_left = -108
	_cheat_btn.offset_top = 12
	_cheat_btn.offset_right = -16
	_cheat_btn.offset_bottom = 48
	_cheat_btn.visible = false
	_cheat_btn.pressed.connect(func() -> void: _cheat_root.visible = not _cheat_root.visible)
	root.add_child(_cheat_btn)

	_build_cheat_menu()


func _build_cheat_menu() -> void:
	_cheat_root = Control.new()
	_cheat_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cheat_root.visible = false
	_cheat_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cheat_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_cheat_root.visible = false)
	_cheat_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cheat_root.add_child(center)

	var card := UITheme.card()
	card.custom_minimum_size = Vector2(300, 0)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	box.add_child(UITheme.heading("Меню читов", 18))
	box.add_child(UITheme.caption("Только этот матч. ESP по живым игрокам не делаем: это портит игру другим людям."))

	box.add_child(_cheat_check("Неуязвимость", func() -> bool: return Settings.god_mode,
		func(v: bool) -> void: Settings.god_mode = v))
	box.add_child(_cheat_check("Бесконечные патроны", func() -> bool: return Settings.inf_ammo,
		func(v: bool) -> void: Settings.inf_ammo = v))
	box.add_child(_cheat_check("Супер-прыжок", func() -> bool: return Settings.super_jump,
		func(v: bool) -> void: Settings.super_jump = v))
	box.add_child(_cheat_check("Скорость x1.6", func() -> bool: return Settings.speed_boost,
		func(v: bool) -> void: Settings.speed_boost = v))
	box.add_child(_cheat_check("Быстрая стрельба", func() -> bool: return Settings.rapid_fire,
		func(v: bool) -> void: Settings.rapid_fire = v))

	var close := UITheme.button("ЗАКРЫТЬ", true, 15)
	close.pressed.connect(func() -> void: _cheat_root.visible = false)
	box.add_child(close)


func _cheat_check(title: String, getter: Callable, setter: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = title
	c.add_theme_font_size_override("font_size", 15)
	c.button_pressed = bool(getter.call())
	c.toggled.connect(func(v: bool) -> void:
		setter.call(v)
		Settings.apply_all()
		Settings.save())
	return c


# ---------------------------------------------------------------- смена оружия

## Панель слотов: 1 основное, 2 пистолет, 3 нож, 4 бомба (только в закладке).
func _build_weapon_bar(root: Control) -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -230
	bar.offset_top = -128
	bar.offset_right = 230
	bar.offset_bottom = -76
	bar.add_theme_constant_override("separation", 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)

	var names := ["1 АВТ", "2 ПИСТ", "3 НОЖ", "4 БОМБА"]
	for i in names.size():
		var b := UITheme.button(names[i], false, 12)
		b.custom_minimum_size = Vector2(0, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.pressed.connect(_on_slot_pressed.bind(i + 1))
		bar.add_child(b)
		_slot_btns.append(b)


func _on_slot_pressed(slot: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.equip_slot(slot):
		_refresh_weapon_bar(true)


## Подсветка активного слота. Перерисовываем только при изменениях.
func _refresh_weapon_bar(force: bool = false) -> void:
	if _slot_btns.is_empty():
		return
	if player == null or not is_instance_valid(player) or player.weapon == null:
		return

	var active: int = player.current_slot()
	var has_primary: bool = bool(player.has_primary)
	var bomb_on: bool = Net.mode == "bomb"
	var state := "%d|%s|%s" % [active, has_primary, bomb_on]
	if not force and state == _slot_state:
		return
	_slot_state = state

	for i in _slot_btns.size():
		var slot := i + 1
		var b: Button = _slot_btns[i]
		var ok := true
		if slot == 1:
			ok = has_primary
		elif slot == 4:
			ok = bomb_on
		b.disabled = not ok
		b.modulate.a = 1.0 if ok else 0.5

		if slot == active and ok:
			b.add_theme_stylebox_override("normal", UITheme.box(UITheme.ACCENT, 8))
			b.add_theme_stylebox_override("hover", UITheme.box(UITheme.ACCENT.lightened(0.1), 8))
			b.add_theme_color_override("font_color", UITheme.ON_ACCENT)
			b.add_theme_color_override("font_hover_color", UITheme.ON_ACCENT)
		else:
			b.add_theme_stylebox_override("normal", UITheme.box(UITheme.PANEL_ALT, 8, UITheme.BORDER))
			b.add_theme_stylebox_override("hover", UITheme.box(UITheme.PANEL_ALT.lightened(0.08), 8, UITheme.ACCENT))
			b.add_theme_color_override("font_color", UITheme.TEXT)
			b.add_theme_color_override("font_hover_color", UITheme.TEXT)


func set_mode_ui(mode: String, cheats: bool) -> void:
	var team_mode := mode == "tdm" or mode == "bomb"
	if _score_label != null:
		_score_label.visible = team_mode
	if _cheats_badge != null:
		_cheats_badge.visible = cheats
	if _cheat_btn != null:
		_cheat_btn.visible = cheats
	if _cheat_root != null and not cheats:
		_cheat_root.visible = false
	if mode != "bomb":
		set_bomb_buttons(false, false, 0.0)


func set_score(a: int, b: int) -> void:
	if _score_label == null:
		return
	_score_label.text = "АЛЬФА %d  :  %d БРАВО" % [a, b]


func set_round_text(text: String) -> void:
	if _round_label == null:
		return
	_round_label.text = text
	_round_label.visible = text != ""


func set_bomb_buttons(show_plant: bool, show_defuse: bool, progress: float) -> void:
	if _plant_btn != null:
		_plant_btn.visible = show_plant
	if _defuse_btn != null:
		_defuse_btn.visible = show_defuse
	if _bomb_bar != null:
		_bomb_bar.visible = progress > 0.0
		_bomb_bar.value = clampf(progress, 0.0, 1.0)


func show_banner(text: String, seconds: float = 3.0) -> void:
	if _banner == null:
		return
	_banner.text = text
	_banner_t = seconds


func _on_hit() -> void:
	_hit_t = 0.14


func _on_player_died() -> void:
	_death_t = 3.0
	_death_box.visible = true


## Строка киллфида: живёт 6 секунд, держим не больше пяти.
func add_kill(killer: String, victim: String) -> void:
	if _feed == null:
		return
	var l := Label.new()
	l.text = "%s  →  %s" % [killer, victim]
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_child(l)

	while _feed.get_child_count() > 5:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()

	await get_tree().create_timer(6.0).timeout
	if is_instance_valid(l):
		l.queue_free()


func set_frags(value: int) -> void:
	if _frags_label != null:
		_frags_label.text = "Фраги: %d" % value


func _build_buy_overlay() -> void:
	_buy_root = Control.new()
	_buy_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_buy_root.visible = false
	_buy_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_buy_root)

	# Затемнение: тап мимо панели закрывает арсенал.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	_buy_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buy_root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL, 14, UITheme.ACCENT))
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	_buy_list = VBoxContainer.new()
	_buy_list.add_theme_constant_override("separation", 8)

	# Список длинный — на телефоне прокручиваем, кнопка закрытия остаётся внизу.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(392, 470)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(_buy_list)
	column.add_child(scroll)

	var close := UITheme.button("ЗАКРЫТЬ", true, 15)
	close.pressed.connect(_close_buy)
	column.add_child(close)


## Содержимое арсенала пересобирается при каждом открытии: цены и деньги
## всегда актуальные, и кнопка закрытия не может «потеряться».
func _fill_buy() -> void:
	if _buy_list == null:
		return
	for child in _buy_list.get_children():
		_buy_list.remove_child(child)
		child.queue_free()

	_buy_list.add_child(UITheme.heading("Арсенал", 22))
	_buy_list.add_child(UITheme.caption("Пистолет и нож есть всегда. В закладке бомбы первый раунд — без автомата: деньги за фраги и доход за раунд."))

	if player == null or player.weapon == null:
		_buy_list.add_child(UITheme.caption("Оружие ещё готовится — открой арсенал через секунду."))
		_skin_box = null
		return

	var list: Array = player.weapon.get_buy_list()
	for i in list.size():
		var w: Dictionary = list[i]
		var btn := UITheme.button("%s    —    $%d" % [str(w["name"]), int(w["price"])], false, 15)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(380, 48)
		btn.pressed.connect(_on_buy.bind(i))
		_buy_list.add_child(btn)

	_skin_box = VBoxContainer.new()
	_skin_box.add_theme_constant_override("separation", 8)
	_buy_list.add_child(_skin_box)
	_refresh_skins()


## Перестраивает блок скинов под текущее оружие.
func _refresh_skins() -> void:
	if _skin_box == null:
		return
	for child in _skin_box.get_children():
		_skin_box.remove_child(child)
		child.queue_free()
	if player == null or player.weapon == null:
		return

	var w = player.weapon
	_skin_box.add_child(UITheme.section("СКИН: %s" % str(w.skin_name())))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_skin_box.add_child(grid)

	var list: Array = w.skin_list()
	for i in list.size():
		var s: Dictionary = list[i]
		var price := int(s["price"])
		var text: String = str(s["name"]) if price <= 0 else "%s  $%d" % [str(s["name"]), price]
		var btn := UITheme.button(text, false, 13)
		btn.custom_minimum_size = Vector2(186, 44)
		var col: Color = s["color"]
		if col.a > 0.01:
			btn.add_theme_color_override("font_color", col.lightened(0.3))
		btn.pressed.connect(_on_skin.bind(i))
		grid.add_child(btn)

	var rnd := UITheme.button("СЛУЧАЙНЫЙ ЦВЕТ  $%d" % int(w.random_skin_price()), true, 14)
	rnd.pressed.connect(_on_random_skin)
	_skin_box.add_child(rnd)


func _open_buy() -> void:
	if _buy_root == null:
		return
	_fill_buy()
	_buy_root.visible = true
	if player != null:
		player.input_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_buy() -> void:
	if _buy_root != null:
		_buy_root.visible = false
	if player != null:
		player.input_locked = false
	if not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Тап по затемнению — тоже закрыть.
func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_buy()
	elif event is InputEventScreenTouch and event.pressed:
		_close_buy()


func _unhandled_input(event: InputEvent) -> void:
	if _buy_root == null or not _buy_root.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close_buy()
		get_viewport().set_input_as_handled()


func _on_buy(i: int) -> void:
	if player == null:
		return
	if player.buy(i):
		_close_buy()
	else:
		_flash_money()


func _on_skin(i: int) -> void:
	if player == null or player.weapon == null:
		return
	var cost: int = player.weapon.skin_price(i)
	if cost > 0 and player.money < cost:
		_flash_money()
		return
	player.money -= cost
	player.weapon.apply_skin(i)
	_refresh_skins()


func _on_random_skin() -> void:
	if player == null or player.weapon == null:
		return
	var cost: int = player.weapon.random_skin_price()
	if player.money < cost:
		_flash_money()
		return
	player.money -= cost
	player.weapon.random_skin()
	_refresh_skins()


func _flash_money() -> void:
	if _money_label == null:
		return
	_money_label.add_theme_color_override("font_color", UITheme.DANGER)
	var t := get_tree().create_timer(0.5)
	t.timeout.connect(_reset_money_color)


func _reset_money_color() -> void:
	if _money_label != null:
		_money_label.add_theme_color_override("font_color", Color("ffcf5c"))


func _on_jump() -> void:
	if player != null:
		player.request_jump()


func _on_crouch(value: bool) -> void:
	if player != null:
		player.set_crouch(value)


func _on_fire(value: bool) -> void:
	if player != null:
		player.set_fire(value)


func _on_reload() -> void:
	if player != null and player.weapon != null:
		player.weapon.reload()


func _on_exit() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.leave()
	get_tree().change_scene_to_file("res://main.tscn")


## Здоровье, хитмаркер и отсчёт возрождения — всё, что живёт каждый кадр.
func _update_feedback(delta: float) -> void:
	if _banner_t > 0.0:
		_banner_t = maxf(_banner_t - delta, 0.0)
		if _banner != null:
			_banner.modulate.a = clampf(_banner_t, 0.0, 1.0)

	if player != null and is_instance_valid(player):
		var hp: float = clampf(player.health, 0.0, 100.0)
		if _health_bar != null:
			_health_bar.value = hp
			var fill := _health_bar.get_theme_stylebox("fill")
			if fill is StyleBoxFlat:
				var col := Color("5ad06a")
				if hp <= 30.0:
					col = Color("e0453c")
				elif hp <= 60.0:
					col = Color("e0a83c")
				(fill as StyleBoxFlat).bg_color = col
		if _health_label != null:
			_health_label.text = "%d" % int(ceil(hp))

	if _hit_t > 0.0:
		_hit_t = maxf(_hit_t - delta, 0.0)
	if _hit_marker != null:
		_hit_marker.modulate.a = clampf(_hit_t / 0.14, 0.0, 1.0)

	if _death_t > 0.0:
		_death_t = maxf(_death_t - delta, 0.0)
		if _death_label != null:
			_death_label.text = "УБИТ\n%.1f" % _death_t
		if _death_box != null:
			_death_box.visible = true
		if _death_t <= 0.0 and _death_box != null:
			_death_box.visible = false


func _process(delta: float) -> void:
	_update_feedback(delta)
	_refresh_weapon_bar()

	if player == null or player.weapon == null:
		return
	if _ammo_label != null:
		_ammo_label.text = player.weapon.get_ammo_text()
	if _weapon_status != null:
		_weapon_status.text = "%s · скин: %s" % [str(player.weapon.weapon_name()), str(player.weapon.skin_name())]
	if _weapon_name != null:
		_weapon_name.text = str(player.weapon.weapon_name())
	if _money_label != null:
		_money_label.text = "$%d" % int(player.money)
