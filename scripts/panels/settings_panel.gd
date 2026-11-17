extends VBoxContainer
## Экран "Настройки": FPS, разрешение рендера, графика, сенса, звук.

const FPS_VALUES := [30, 60, 90, 120, 0]
const FPS_LABELS := ["30", "60", "90", "120", "Без лимита"]
const SCALE_VALUES := [0.5, 0.75, 1.0]
const SCALE_LABELS := ["50% — максимум FPS", "75% — баланс", "100% — чётко"]
const QUALITY_LABELS := ["Низкое", "Среднее", "Высокое"]

var _sens_label: Label
var _vol_label: Label


func _ready() -> void:
	_build()


func _build() -> void:
	add_theme_constant_override("separation", 10)
	add_child(UITheme.heading("Настройки"))
	add_child(UITheme.caption("Всё сохраняется сразу и применяется без перезапуска."))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

	# --- Графика и производительность
	box.add_child(UITheme.section("Графика"))

	var fps := UITheme.option(FPS_LABELS, FPS_VALUES.find(Settings.fps_limit))
	fps.item_selected.connect(_on_fps)
	box.add_child(UITheme.row("Лимит FPS", fps, "Влияет на нагрев телефона и стабильность"))

	var scale_opt := UITheme.option(SCALE_LABELS, SCALE_VALUES.find(Settings.render_scale))
	scale_opt.item_selected.connect(_on_scale)
	box.add_child(UITheme.row("Разрешение рендера", scale_opt, "Меньше — больше FPS, картинка мягче"))

	var quality_opt := UITheme.option(QUALITY_LABELS, Settings.quality)
	quality_opt.item_selected.connect(_on_quality)
	box.add_child(UITheme.row("Качество", quality_opt, "Сглаживание MSAA"))

	# --- Управление
	box.add_child(UITheme.section("Управление"))

	var sens := UITheme.slider(0.1, 5.0, 0.05, Settings.sensitivity)
	sens.custom_minimum_size = Vector2(280, 30)
	sens.value_changed.connect(_on_sens)

	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 10)
	sens_row.add_child(sens)

	_sens_label = UITheme.label("%.2f" % Settings.sensitivity, 15, UITheme.ACCENT)
	_sens_label.custom_minimum_size = Vector2(56, 0)
	_sens_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sens_row.add_child(_sens_label)

	box.add_child(UITheme.row("Сенса", sens_row, "Используется камерой игрока в матче"))

	# --- Звук
	box.add_child(UITheme.section("Звук"))

	var vol := UITheme.slider(0.0, 1.0, 0.05, Settings.volume)
	vol.custom_minimum_size = Vector2(280, 30)
	vol.value_changed.connect(_on_volume)

	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 10)
	vol_row.add_child(vol)

	_vol_label = UITheme.label("%d%%" % int(round(Settings.volume * 100.0)), 15, UITheme.ACCENT)
	_vol_label.custom_minimum_size = Vector2(56, 0)
	_vol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vol_row.add_child(_vol_label)

	box.add_child(UITheme.row("Громкость", vol_row, "Общая громкость игры"))

	# --- Секретный код
	box.add_child(UITheme.section("Секретный код"))

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)

	var field := LineEdit.new()
	field.placeholder_text = "код"
	field.custom_minimum_size = Vector2(180, 40)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(field)

	var ok := UITheme.button("ОК", true, 14)
	ok.custom_minimum_size = Vector2(70, 40)
	ok.pressed.connect(func() -> void:
		if Settings.try_secret(field.text):
			call_deferred("_rebuild")
			return
		field.text = ""
		field.placeholder_text = "не тот код")
	code_row.add_child(ok)

	box.add_child(UITheme.row("Ввести код", code_row, "Если знаешь, что тут спрятано"))

	if Settings.secrets_unlocked:
		box.add_child(UITheme.section("Секреты"))
		box.add_child(_check("Бессмертие", Settings.god_mode, func(v: bool) -> void:
			Settings.god_mode = v))
		box.add_child(_check("Бесконечные патроны", Settings.inf_ammo, func(v: bool) -> void:
			Settings.inf_ammo = v))
		box.add_child(_check("Высокий прыжок", Settings.super_jump, func(v: bool) -> void:
			Settings.super_jump = v))
		box.add_child(_check("Сквозь стены (полёт)", Settings.noclip, func(v: bool) -> void:
			Settings.noclip = v))
		box.add_child(_check("Ускорение", Settings.speed_boost, func(v: bool) -> void:
			Settings.speed_boost = v))
		box.add_child(_check("Замедление времени", Settings.slowmo, func(v: bool) -> void:
			Settings.slowmo = v))
		box.add_child(_check("Подсветка ботов (не игроков)", Settings.bot_outline, func(v: bool) -> void:
			Settings.bot_outline = v))
		box.add_child(_check("Быстрая стрельба", Settings.rapid_fire, func(v: bool) -> void:
			Settings.rapid_fire = v))

	var reset := UITheme.button("СБРОСИТЬ НАСТРОЙКИ", false, 14)
	reset.pressed.connect(_on_reset)
	box.add_child(reset)


## Чекбокс секрета: переключает значение в настройках и сразу сохраняет.
func _check(text: String, value: bool, on_toggle: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.add_theme_font_size_override("font_size", 15)
	c.toggled.connect(func(v: bool) -> void:
		on_toggle.call(v)
		Settings.apply_time()
		Settings.save())
	return c


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build()


func _on_fps(index: int) -> void:
	Settings.fps_limit = FPS_VALUES[index]
	Settings.apply_fps()
	Settings.save()


func _on_scale(index: int) -> void:
	Settings.render_scale = SCALE_VALUES[index]
	Settings.apply_graphics()
	Settings.save()


func _on_quality(index: int) -> void:
	Settings.quality = index
	Settings.apply_graphics()
	Settings.save()


func _on_sens(value: float) -> void:
	Settings.sensitivity = value
	_sens_label.text = "%.2f" % value
	Settings.save()


func _on_volume(value: float) -> void:
	Settings.volume = value
	_vol_label.text = "%d%%" % int(round(value * 100.0))
	Settings.apply_volume()
	Settings.save()


func _on_reset() -> void:
	Settings.reset_defaults()
	_rebuild()
