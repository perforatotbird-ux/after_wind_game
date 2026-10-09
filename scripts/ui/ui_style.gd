extends RefCounted

## Общая палитра и фабрики виджетов UI в стиле HUD: тёмные панели, золотые акценты,
## скругление 6 px. Используется стартовым меню, окнами сохранений, настроек и
## подтверждений. Цвета совпадают с hud.gd (_init_styles, карточки рецептов/контрактов).

const COLOR_BG: Color = Color(0.12, 0.15, 0.18, 0.95)
const COLOR_CARD: Color = Color(0.14, 0.17, 0.22, 0.95)
const COLOR_CARD_EMPTY: Color = Color(0.11, 0.13, 0.15, 0.8)
const COLOR_BORDER: Color = Color(0.3, 0.35, 0.4, 0.6)
const COLOR_ACCENT: Color = Color(1.0, 0.85, 0.25, 1.0)
const COLOR_TITLE: Color = Color(1.0, 0.9, 0.45)
const COLOR_TEXT: Color = Color(0.9, 0.9, 0.9)
const COLOR_MUTED: Color = Color(0.75, 0.8, 0.85)
const COLOR_DIM: Color = Color(0.55, 0.6, 0.65)
const COLOR_OK: Color = Color(0.4, 0.9, 0.55)
const COLOR_DANGER: Color = Color(1.0, 0.4, 0.4)
const COLOR_OVERLAY: Color = Color(0.0, 0.0, 0.0, 0.55)

static func make_stylebox(bg: Color, border: Color = COLOR_BORDER, border_width: int = 1, radius: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	return s

static func make_panel(bg: Color = COLOR_BG, border: Color = COLOR_BORDER, border_width: int = 1) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", make_stylebox(bg, border, border_width))
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
	return make_label(text, 15, COLOR_TITLE)

static func _button_box(bg: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var s := make_stylebox(bg, border, border_width)
	s.content_margin_left = 14.0
	s.content_margin_right = 14.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	return s

## Кнопка в стиле HUD. primary — золотая рамка (главное действие), danger — красная.
static func make_button(text: String, min_size: Vector2 = Vector2(0, 36), primary: bool = false, danger: bool = false, font_size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	var normal_bg: Color = Color(0.16, 0.2, 0.26, 0.95)
	var normal_border: Color = COLOR_BORDER
	if primary:
		normal_bg = Color(0.2, 0.3, 0.45, 0.95)
		normal_border = COLOR_ACCENT
	elif danger:
		normal_bg = Color(0.32, 0.14, 0.14, 0.95)
		normal_border = COLOR_DANGER
	b.add_theme_stylebox_override("normal", _button_box(normal_bg, normal_border))
	b.add_theme_stylebox_override("hover", _button_box(normal_bg.lightened(0.15), COLOR_DANGER if danger else COLOR_ACCENT, 2))
	b.add_theme_stylebox_override("pressed", _button_box(normal_bg.lightened(0.25), COLOR_DANGER if danger else COLOR_ACCENT, 2))
	b.add_theme_stylebox_override("disabled", _button_box(COLOR_CARD_EMPTY, Color(0.25, 0.28, 0.32, 0.5)))
	var focus := _button_box(Color(0, 0, 0, 0), COLOR_ACCENT, 1)
	focus.draw_center = false
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", COLOR_TEXT)
	b.add_theme_color_override("font_hover_color", COLOR_TITLE)
	b.add_theme_color_override("font_pressed_color", COLOR_ACCENT)
	b.add_theme_color_override("font_focus_color", COLOR_TEXT)
	b.add_theme_color_override("font_disabled_color", COLOR_DIM)
	b.add_theme_font_size_override("font_size", font_size)
	return b

## Полноэкранное затемнение под модальным окном (перехватывает клики).
static func make_overlay() -> ColorRect:
	var r := ColorRect.new()
	r.color = COLOR_OVERLAY
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r
