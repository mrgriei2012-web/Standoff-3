extends VBoxContainer
## Экран "Профиль": аватарка, никнейм, айди, статистика.

var _avatar: TextureRect
var _nick: LineEdit
var _id_value: Label


func _ready() -> void:
	_build()
	Profile.profile_changed.connect(_refresh)


func _build() -> void:
	add_theme_constant_override("separation", 12)
	add_child(UITheme.heading("Профиль"))
	add_child(UITheme.caption("Айди создаётся один раз и не меняется. Он же — твоя аватарка."))

	var card := UITheme.card()
	add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	card.add_child(row)

	_avatar = TextureRect.new()
	_avatar.custom_minimum_size = Vector2(140, 140)
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_avatar)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)

	col.add_child(UITheme.caption("НИКНЕЙМ"))
	_nick = UITheme.line_edit("Твой ник")
	_nick.max_length = 16
	_nick.text = Profile.nickname
	_nick.text_changed.connect(_on_nick_changed)
	col.add_child(_nick)

	col.add_child(UITheme.caption("ИДЕНТИФИКАТОР"))
	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 8)
	col.add_child(id_row)

	_id_value = UITheme.label(Profile.uid, 16, UITheme.ACCENT)
	_id_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(_id_value)

	var copy_btn := UITheme.button("Копировать", false, 13)
	copy_btn.custom_minimum_size = Vector2(130, 38)
	copy_btn.pressed.connect(_on_copy)
	id_row.add_child(copy_btn)

	var stats := UITheme.card()
	add_child(stats)

	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 8)
	stats.add_child(stats_box)
	stats_box.add_child(UITheme.section("Статистика"))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	stats_box.add_child(grid)

	for pair in [["Матчи", "0"], ["Убийства", "0"], ["Смерти", "0"], ["K/D", "—"]]:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.add_child(UITheme.label(str(pair[0]).to_upper(), 11, UITheme.DIM))
		cell.add_child(UITheme.label(str(pair[1]), 22))
		grid.add_child(cell)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(spacer)

	_refresh()


func _on_nick_changed(value: String) -> void:
	Profile.set_nickname(value)


func _on_copy() -> void:
	DisplayServer.clipboard_set(Profile.uid)


func _refresh() -> void:
	if _avatar == null:
		return
	_avatar.texture = Profile.make_avatar(Profile.uid, 160)
	_id_value.text = Profile.uid
	if not _nick.has_focus() and _nick.text != Profile.nickname:
		_nick.text = Profile.nickname
