extends RefCounted

## Общая палитра и фабрики виджетов UI в индустриальном стиле: тёмный графит,
## сдержанные бронзово-янтарные акценты, тонкие рамки и скругление 4–6 px.
## Используется окнами рюкзака, верстака, генератора, настроек и диалогов.

const COLOR_BG: Color = Color(0.10, 0.12, 0.15, 0.98)
const COLOR_CARD: Color = Color(0.13, 0.15, 0.19, 0.95)
const COLOR_CARD_EMPTY: Color = Color(0.08, 0.09, 0.11, 0.75)
const COLOR_BORDER: Color = Color(0.24, 0.28, 0.35, 0.65)
const COLOR_ACCENT: Color = Color(0.88, 0.68, 0.30, 1.0)
const COLOR_TITLE: Color = Color(0.95, 0.95, 0.96, 1.0)
const COLOR_TEXT: Color = Color(0.88, 0.90, 0.93, 1.0)
const COLOR_MUTED: Color = Color(0.65, 0.70, 0.78, 1.0)
const COLOR_DIM: Color = Color(0.48, 0.52, 0.58, 1.0)
const COLOR_OK: Color = Color(0.32, 0.76, 0.52, 1.0)
const COLOR_DANGER: Color = Color(0.86, 0.30, 0.26, 1.0)
const COLOR_OVERLAY: Color = Color(0.04, 0.05, 0.07, 0.75)

# Расширенная индустриальная палитра (Industrial Survival)
const COLOR_AMBER: Color = Color(0.88, 0.68, 0.30, 1.0)
const COLOR_AMBER_HOVER: Color = Color(0.96, 0.76, 0.38, 1.0)
const COLOR_GRAPHITE_DARK: Color = Color(0.07, 0.08, 0.10, 0.98)
const COLOR_GRAPHITE_PANEL: Color = Color(0.10, 0.12, 0.15, 0.98)
const COLOR_GRAPHITE_SURFACE: Color = Color(0.13, 0.15, 0.19, 0.95)
const COLOR_GRAPHITE_CARD: Color = Color(0.15, 0.18, 0.22, 0.95)
const COLOR_GRAPHITE_INSET: Color = Color(0.08, 0.09, 0.11, 0.90)
const COLOR_BORDER_SUBTLE: Color = Color(0.22, 0.25, 0.32, 0.55)
const COLOR_BORDER_STRONG: Color = Color(0.38, 0.44, 0.54, 0.85)
const COLOR_BADGE_BG: Color = Color(0.14, 0.17, 0.22, 0.9)

static func make_stylebox(bg: Color, border: Color = COLOR_BORDER, border_width: int = 1, radius: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	return s

static func make_panel(bg: Color = COLOR_BG, border: Color = COLOR_BORDER, border_width: int = 1, radius: int = 6) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", make_stylebox(bg, border, border_width, radius))
	return panel

static func make_margin(px: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		m.add_theme_constant_override(side, px)
	return m

static func make_label(text: String, font_size: int = 14, color: Color = COLOR_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l

static func make_section_header(text: String) -> Label:
	return make_label(text, 14, COLOR_TITLE)

static func make_badge(text: String, font_size: int = 10, color: Color = COLOR_MUTED, bg: Color = COLOR_BADGE_BG, border: Color = COLOR_BORDER_SUBTLE) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := make_stylebox(bg, border, 1, 3)
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	pc.add_theme_stylebox_override("panel", sb)
	var lbl := make_label(text, font_size, color)
	pc.add_child(lbl)
	return pc

static func make_divider(vertical: bool = false, color: Color = Color(0.22, 0.25, 0.32, 0.5)) -> Control:
	var sep: Control = VSeparator.new() if vertical else HSeparator.new()
	var sb := StyleBoxLine.new()
	sb.color = color
	sb.thickness = 1
	sep.add_theme_stylebox_override("separator", sb)
	return sep

static func _button_box(bg: Color, border: Color, border_width: int = 1, radius: int = 4) -> StyleBoxFlat:
	var s := make_stylebox(bg, border, border_width, radius)
	s.content_margin_left = 12.0
	s.content_margin_right = 12.0
	s.content_margin_top = 5.0
	s.content_margin_bottom = 5.0
	return s

## Кнопка в стиле HUD / Industrial Survival. primary — янтарно-бронзовая рамка, danger — приглушенная красная.
static func make_button(text: String, min_size: Vector2 = Vector2(0, 34), primary: bool = false, danger: bool = false, font_size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	style_button(b, primary, danger, font_size)
	return b

## Применяет индустриальное оформление к кнопке.
static func style_button(b: Button, primary: bool = false, danger: bool = false, font_size: int = 14) -> void:
	var normal_bg: Color = COLOR_GRAPHITE_CARD
	var normal_border: Color = COLOR_BORDER
	if primary:
		normal_bg = Color(0.18, 0.23, 0.32, 0.95)
		normal_border = COLOR_ACCENT
	elif danger:
		normal_bg = Color(0.26, 0.12, 0.12, 0.95)
		normal_border = COLOR_DANGER
	b.add_theme_stylebox_override("normal", _button_box(normal_bg, normal_border, 1, 4))
	b.add_theme_stylebox_override("hover", _button_box(normal_bg.lightened(0.12), COLOR_DANGER if danger else COLOR_ACCENT, 1, 4))
	b.add_theme_stylebox_override("pressed", _button_box(normal_bg.lightened(0.20), COLOR_DANGER if danger else COLOR_ACCENT, 2, 4))
	b.add_theme_stylebox_override("disabled", _button_box(COLOR_CARD_EMPTY, Color(0.20, 0.23, 0.28, 0.5), 1, 4))
	var focus := _button_box(Color(0, 0, 0, 0), COLOR_ACCENT, 1, 4)
	focus.draw_center = false
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", COLOR_TEXT)
	b.add_theme_color_override("font_hover_color", COLOR_TITLE)
	b.add_theme_color_override("font_pressed_color", COLOR_ACCENT)
	b.add_theme_color_override("font_focus_color", COLOR_TEXT)
	b.add_theme_color_override("font_disabled_color", COLOR_DIM)
	b.add_theme_font_size_override("font_size", font_size)

## Минимальный размер шрифта в окнах (логические пиксели базы 1600×900).
const MIN_FONT_LABEL: int = 12
const MIN_FONT_BUTTON: int = 13

## Делает текст окна читаемым и не вылезающим за края: прокрутка только по
## вертикали, перенос строк у меток (кроме коротких подписей в строках HBox),
## минимальный кегль, оформление кнопок, обрезка «…» у длинных подписей в строках.
static func polish_text(node: Node) -> void:
	if node is ScrollContainer:
		(node as ScrollContainer).horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	elif node is Label:
		var l := node as Label
		var fs: int = l.get_theme_font_size("font_size")
		if fs < MIN_FONT_LABEL:
			l.add_theme_font_size_override("font_size", MIN_FONT_LABEL)
		var parent := l.get_parent()
		var in_row: bool = parent is HBoxContainer or parent is ProgressBar or parent is FlowContainer or parent is GridContainer or parent is CenterContainer
		if not in_row:
			if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		elif (l.size_flags_horizontal & Control.SIZE_EXPAND) != 0:
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			l.clip_text = true
			l.tooltip_text = l.text
			l.mouse_filter = Control.MOUSE_FILTER_PASS
	elif node is Button and not (node is OptionButton or node is CheckButton or node is CheckBox):
		var b := node as Button
		var fs_b: int = maxi(MIN_FONT_BUTTON, b.get_theme_font_size("font_size"))
		if not b.has_theme_stylebox_override("normal"):
			style_button(b, false, false, fs_b)
		else:
			b.add_theme_font_size_override("font_size", fs_b)
		b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, 30.0)
		if b.get_parent() is VBoxContainer and b.text.length() > 24:
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for child in node.get_children():
		polish_text(child)

## Полноэкранное затемнение под модальным окном (перехватывает клики).
static func make_overlay() -> ColorRect:
	var r := ColorRect.new()
	r.color = COLOR_OVERLAY
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r
