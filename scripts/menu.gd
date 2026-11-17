extends Control
## Каркас: верхняя панель с профилем, боковое меню, области экрана.

const PlayPanel := preload("res://scripts/panels/play_panel.gd")
const ProfilePanel := preload("res://scripts/panels/profile_panel.gd")
# const InventoryPanel := preload("res://scripts/panels/inventory_panel.gd")  # вернём, когда будет оружие
const SettingsPanel := preload("res://scripts/panels/settings_panel.gd")

const TAB_TITLES := ["Играть", "Профиль", "Настройки"]

## Ссылка на Telegram-канал. Когда будет готова — вписать сюда, и всё.
const TG_URL := "https://t.me/arctgha"
const TG_SEEN_PATH := "user://tg_invite.cfg"

var _tab_buttons: Array = []
var _panels: Array = []
var _nick_label: Label
var _id_label: Label
var _avatar: TextureRect
var _tg_root: Control
var _tg_waiting := false


func _ready() -> void:
	_build()
	Profile.profile_changed.connect(_refresh_profile)
	_select_tab(0)
	_maybe_show_tg()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 0)
	add_child(v)

	v.add_child(_build_topbar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	v.add_child(body)

	body.add_child(_build_nav())

	var content := MarginContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		content.add_theme_constant_override("margin_" + side, 18)
	body.add_child(content)

	_panels = [PlayPanel.new(), ProfilePanel.new(), SettingsPanel.new()]
	for p in _panels:
		content.add_child(p)


func _build_topbar() -> PanelContainer:
	var bar := PanelContainer.new()
	var sb := UITheme.box(UITheme.PANEL, 0, Color(0, 0, 0, 0), 0, 14)
	sb.border_width_bottom = 1
	sb.border_color = UITheme.BORDER
	bar.add_theme_stylebox_override("panel", sb)
	bar.custom_minimum_size = Vector2(0, 78)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	bar.add_child(h)

	_avatar = TextureRect.new()
	_avatar.custom_minimum_size = Vector2(52, 52)
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(_avatar)

	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(names)

	_nick_label = UITheme.label(Profile.nickname, 20)
	names.add_child(_nick_label)

	_id_label = UITheme.caption("ID: " + Profile.uid)
	names.add_child(_id_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UITheme.box(UITheme.PANEL_ALT, 8, UITheme.BORDER))
	var lvl := UITheme.label("LVL 1", 15, UITheme.ACCENT)
	lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(lvl)
	h.add_child(badge)

	_refresh_profile()
	return bar


func _build_nav() -> PanelContainer:
	var nav := PanelContainer.new()
	var sb := UITheme.box(UITheme.PANEL, 0, Color(0, 0, 0, 0), 0, 14)
	sb.border_width_right = 1
	sb.border_color = UITheme.BORDER
	nav.add_theme_stylebox_override("panel", sb)
	nav.custom_minimum_size = Vector2(196, 0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	nav.add_child(box)

	for i in TAB_TITLES.size():
		var b := UITheme.nav_button(TAB_TITLES[i])
		b.pressed.connect(_select_tab.bind(i))
		box.add_child(b)
		_tab_buttons.append(b)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	box.add_child(UITheme.caption("prototype 0.1"))
	return nav


func _select_tab(index: int) -> void:
	for i in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == index)

	for i in _panels.size():
		_panels[i].visible = (i == index)

	var panel = _panels[index]
	if panel.has_method("on_show"):
		panel.call("on_show")


func _refresh_profile() -> void:
	if _nick_label == null:
		return
	_nick_label.text = Profile.nickname
	_id_label.text = "ID: " + Profile.uid
	_avatar.texture = Profile.make_avatar(Profile.uid, 64)


# ---------------------------------------------------------------- приглашение в Telegram

## Показываем один раз: пока человек не нажмёт «Подписаться» и не вернётся.
func _maybe_show_tg() -> void:
	if _tg_seen():
		return
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree() or _tg_seen() or _tg_root != null:
		return
	_build_tg()


func _build_tg() -> void:
	_tg_root = Control.new()
	_tg_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tg_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_tg_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_tg_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tg_root.add_child(center)

	var card := UITheme.card()
	card.custom_minimum_size = Vector2(430, 0)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)

	box.add_child(UITheme.heading("standoff 3", 26))

	var text := UITheme.label("Канал @arctgha — новые режимы, карты и свежие сборки APK. Подпишись, чтобы не пропустить обновление.", 15)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(390, 0)
	box.add_child(text)

	var go := UITheme.button("ПОДПИСАТЬСЯ В TELEGRAM", true, 17)
	go.custom_minimum_size = Vector2(0, 66)
	go.pressed.connect(_on_tg_go)
	box.add_child(go)

	var later := UITheme.button("Позже", false, 13)
	later.pressed.connect(func() -> void: _close_tg(false))
	box.add_child(later)


func _on_tg_go() -> void:
	_tg_waiting = true
	OS.shell_open(TG_URL)


func _close_tg(mark_seen: bool) -> void:
	_tg_waiting = false
	if _tg_root != null and is_instance_valid(_tg_root):
		_tg_root.queue_free()
	_tg_root = null
	if mark_seen:
		_tg_mark_seen()


## Вернулись из Telegram — приглашение больше не показываем.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		if _tg_waiting and _tg_root != null and is_instance_valid(_tg_root):
			_close_tg(true)


func _tg_seen() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(TG_SEEN_PATH) != OK:
		return false
	return bool(cfg.get_value("tg", "seen", false))


func _tg_mark_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("tg", "seen", true)
	cfg.save(TG_SEEN_PATH)
