extends Control
## Каркас: верхняя панель с профилем, боковое меню, области экрана.

const PlayPanel := preload("res://scripts/panels/play_panel.gd")
const ProfilePanel := preload("res://scripts/panels/profile_panel.gd")
# const InventoryPanel := preload("res://scripts/panels/inventory_panel.gd")  # вернём, когда будет оружие
const SettingsPanel := preload("res://scripts/panels/settings_panel.gd")

const TAB_TITLES := ["Играть", "Профиль", "Настройки"]

var _tab_buttons: Array = []
var _panels: Array = []
var _nick_label: Label
var _id_label: Label
var _avatar: TextureRect


func _ready() -> void:
	_build()
	Profile.profile_changed.connect(_refresh_profile)
	_select_tab(0)


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
