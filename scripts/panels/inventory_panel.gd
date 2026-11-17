extends VBoxContainer
## Экран "Инвентарь": карточки скинов с редкостью. Пока локальный список.

const ITEMS := [
	{"name": "AKR-12 | Пепел", "kind": "Автомат", "rarity": "legend", "owned": true},
	{"name": "M4A1 | Город", "kind": "Автомат", "rarity": "epic", "owned": true},
	{"name": "AWM | Холод", "kind": "Снайперка", "rarity": "legend", "owned": false},
	{"name": "USP | Стандарт", "kind": "Пистолет", "rarity": "common", "owned": true},
	{"name": "Керамбит | Синий", "kind": "Нож", "rarity": "epic", "owned": false},
	{"name": "MP5 | Ржавчина", "kind": "ПП", "rarity": "common", "owned": true},
	{"name": "Deagle | Золото", "kind": "Пистолет", "rarity": "legend", "owned": false},
	{"name": "SG-553 | Сетка", "kind": "Автомат", "rarity": "rare", "owned": true},
	{"name": "Перчатки | Тактические", "kind": "Перчатки", "rarity": "rare", "owned": true},
]

var _detail: Label


func _ready() -> void:
	_build()


func _build() -> void:
	add_theme_constant_override("separation", 12)
	add_child(UITheme.heading("Инвентарь"))
	add_child(UITheme.caption("Клик по карточке — подробности. Редкость влияет на цвет рамки."))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	for item in ITEMS:
		grid.add_child(_make_card(item))

	_detail = UITheme.label("Выбери предмет", 15, UITheme.DIM)
	add_child(_detail)


func _make_card(item: Dictionary) -> Button:
	var rarity := str(item["rarity"])
	var owned: bool = bool(item["owned"])
	var tint: Color = UITheme.RARITY.get(rarity, UITheme.DIM)

	var b := Button.new()
	b.text = "%s\n%s" % [str(item["name"]), str(item["kind"])]
	b.custom_minimum_size = Vector2(200, 108)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", UITheme.TEXT if owned else UITheme.DIM)

	var fill := UITheme.PANEL_ALT if owned else UITheme.PANEL
	b.add_theme_stylebox_override("normal", UITheme.box(fill, 10, tint, 2 if owned else 1))
	b.add_theme_stylebox_override("hover", UITheme.box(fill.lightened(0.06), 10, tint, 2))
	b.add_theme_stylebox_override("pressed", UITheme.box(fill.lightened(0.12), 10, tint, 2))
	b.add_theme_stylebox_override("focus", UITheme.box(Color(0, 0, 0, 0), 10, tint, 2))

	b.pressed.connect(_on_card_pressed.bind(item))
	return b


func _on_card_pressed(item: Dictionary) -> void:
	var rarity := str(item["rarity"])
	var owned: bool = bool(item["owned"])
	_detail.text = "%s (%s) — %s — %s" % [
		str(item["name"]),
		str(item["kind"]),
		"в инвентаре" if owned else "не получен",
		rarity,
	]
	_detail.add_theme_color_override("font_color", UITheme.RARITY.get(rarity, UITheme.DIM))
