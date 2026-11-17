class_name UITheme
extends RefCounted
## Общая палитра и готовые элементы в стиле соревновательного шутера.

const BG := Color("0a0d13")
const PANEL := Color("121821")
const PANEL_ALT := Color("1a2230")
const BORDER := Color("25303f")
const ACCENT := Color("ff8a00")
const ACCENT_SOFT := Color("ffb347")
const TEXT := Color("e8eef7")
const DIM := Color("7d8a9c")
const DANGER := Color("ff4d4d")
const ON_ACCENT := Color("1a1205")

const RARITY := {
	"common": Color("93a5bb"),
	"rare": Color("4aa3ff"),
	"epic": Color("b06bff"),
	"legend": Color("ffb038"),
}


static func box(fill: Color, radius: int = 10, border: Color = Color(0, 0, 0, 0), border_width: int = 1, pad: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	if border.a > 0.0:
		sb.set_border_width_all(border_width)
		sb.border_color = border
	return sb


static func label(text: String, font_size: int = 16, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func heading(text: String, font_size: int = 22) -> Label:
	return label(text.to_upper(), font_size, TEXT)


static func caption(text: String) -> Label:
	var l := label(text, 12, DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func section(text: String) -> Label:
	var l := label(text.to_upper(), 13, ACCENT)
	l.custom_minimum_size = Vector2(0, 28)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


static func card(fill: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(fill, 12, BORDER))
	return p


static func button(text: String, accent: bool = false, font_size: int = 15) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size = Vector2(0, 44)

	var normal := box(PANEL_ALT, 8, BORDER)
	var hover := box(PANEL_ALT.lightened(0.08), 8, ACCENT)
	var pressed := box(PANEL_ALT.lightened(0.14), 8, ACCENT)
	var focus := box(Color(0, 0, 0, 0), 8, ACCENT)

	if accent:
		normal = box(ACCENT, 8)
		hover = box(ACCENT.lightened(0.12), 8)
		pressed = box(ACCENT.darkened(0.12), 8)
		b.add_theme_color_override("font_color", ON_ACCENT)
		b.add_theme_color_override("font_hover_color", ON_ACCENT)
		b.add_theme_color_override("font_pressed_color", ON_ACCENT)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", box(PANEL, 8, BORDER))
	return b


static func nav_button(text: String) -> Button:
	var b := button(text)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(168, 46)
	b.add_theme_stylebox_override("pressed", box(ACCENT, 8))
	b.add_theme_stylebox_override("hover_pressed", box(ACCENT.lightened(0.1), 8))
	b.add_theme_color_override("font_pressed_color", ON_ACCENT)
	b.add_theme_color_override("font_hover_pressed_color", ON_ACCENT)
	return b


static func line_edit(placeholder: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 42)
	e.add_theme_stylebox_override("normal", box(PANEL_ALT, 8, BORDER))
	e.add_theme_stylebox_override("focus", box(PANEL_ALT, 8, ACCENT))
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", DIM)
	e.add_theme_color_override("caret_color", ACCENT)
	return e


static func option(items: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = clampi(selected, 0, maxi(items.size() - 1, 0))
	o.custom_minimum_size = Vector2(180, 42)
	o.add_theme_stylebox_override("normal", box(PANEL_ALT, 8, BORDER))
	o.add_theme_stylebox_override("hover", box(PANEL_ALT.lightened(0.08), 8, ACCENT))
	o.add_theme_stylebox_override("pressed", box(PANEL_ALT.lightened(0.12), 8, ACCENT))
	o.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), 8, ACCENT))
	o.add_theme_color_override("font_color", TEXT)
	return o


static func slider(min_v: float, max_v: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(0, 30)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var track := box(PANEL_ALT, 4, BORDER, 1, 4)
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", box(ACCENT, 4, Color(0, 0, 0, 0), 1, 4))
	s.add_theme_stylebox_override("grabber_area_highlight", box(ACCENT_SOFT, 4, Color(0, 0, 0, 0), 1, 4))
	return s


static func row(label_text: String, control: Control, hint: String = "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(label(label_text, 15))
	if not hint.is_empty():
		left.add_child(caption(hint))
	h.add_child(left)

	h.add_child(control)
	return h
