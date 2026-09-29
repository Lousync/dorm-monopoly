class_name UIKit
## 界面小工具：统一配色与控件创建，按钮/输入框自带精装样式。

const BG := Color(0.106, 0.118, 0.153)        # 窗口底
const PANEL := Color(0.153, 0.169, 0.216)     # 面板
const PANEL_GLASS := Color(0.153, 0.169, 0.216, 0.93)  # 覆在棋盘上的半透明面板
const PANEL_LIGHT := Color(0.196, 0.212, 0.271)
const BORDER := Color(0.235, 0.259, 0.325)
const ACCENT := Color(0.961, 0.702, 0.259)    # 骰子黄
const ACCENT_DARK := Color(0.55, 0.38, 0.10)
const TEXT := Color(0.898, 0.914, 0.945)
const TEXT_DIM := Color(0.604, 0.635, 0.702)
const GOOD := Color(0.455, 0.812, 0.529)
const DANGER := Color(0.937, 0.325, 0.314)

static func label(text: String, size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## kind: "normal" 次要 / "primary" 金色主按钮 / "danger" 危险操作
static func button(text: String, size: int = 15, kind: String = "normal") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 34)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: Fx.play("click", -6.0, randf_range(0.95, 1.05)))
	restyle_button(b, kind)
	return b

## 运行时切换按钮配色（如「准备」变绿）
static func restyle_button(b: Button, kind: String) -> void:
	var bg := PANEL_LIGHT
	var bg_hover := PANEL_LIGHT.lightened(0.10)
	var bg_press := PANEL_LIGHT.darkened(0.14)
	var fg := TEXT
	var border := BORDER
	var corner := 9
	if kind == "primary":
		bg = ACCENT
		bg_hover = ACCENT.lightened(0.12)
		bg_press = ACCENT.darkened(0.12)
		fg = Color(0.16, 0.12, 0.03)
		border = ACCENT_DARK
	elif kind == "good":
		bg = Color(0.20, 0.42, 0.26)
		bg_hover = Color(0.24, 0.50, 0.30)
		bg_press = Color(0.16, 0.35, 0.22)
		fg = Color(0.88, 0.98, 0.90)
		border = Color(0.30, 0.60, 0.36)
	elif kind == "danger":
		bg = Color(0.42, 0.16, 0.16)
		bg_hover = Color(0.50, 0.19, 0.19)
		bg_press = Color(0.35, 0.13, 0.13)
		fg = Color(1.0, 0.88, 0.88)
		border = Color(0.62, 0.26, 0.26)

	var sb_n := stylebox(bg, corner, border, 1)
	var sb_h := stylebox(bg_hover, corner, border.lightened(0.15), 1)
	var sb_p := stylebox(bg_press, corner, border, 1)
	var sb_d := stylebox(Color(bg.r, bg.g, bg.b, 0.35), corner, Color(border.r, border.g, border.b, 0.3), 1)
	b.add_theme_stylebox_override("normal", sb_n)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_p)
	b.add_theme_stylebox_override("disabled", sb_d)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, fg)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)

static func line_edit(placeholder: String, size: int = 15) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size", size)
	e.custom_minimum_size = Vector2(0, 34)
	var sb_n := stylebox(Color(0.114, 0.125, 0.161), 8, BORDER, 1)
	sb_n.content_margin_left = 10
	sb_n.content_margin_right = 10
	var sb_f := stylebox(Color(0.13, 0.14, 0.18), 8, ACCENT, 1)
	sb_f.content_margin_left = 10
	sb_f.content_margin_right = 10
	e.add_theme_stylebox_override("normal", sb_n)
	e.add_theme_stylebox_override("focus", sb_f)
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", TEXT_DIM.darkened(0.25))
	e.add_theme_color_override("caret_color", ACCENT)
	e.add_theme_color_override("selection_color", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.3))
	return e

static func panel(bg: Color, corner: int = 10, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", stylebox(bg, corner, border, border_w))
	return p

## 会为子控件分配尺寸的面板（Panel 不会，装内容请用这个）
static func panel_container(bg: Color, corner: int = 10, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(bg, corner, border, border_w))
	return p

## 进度条（弹窗倒计时用）
static func progress(fg: Color = ACCENT) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	var sb_bg := stylebox(Color(0.10, 0.11, 0.15), 4)
	var sb_fill := stylebox(fg, 4)
	bar.add_theme_stylebox_override("background", sb_bg)
	bar.add_theme_stylebox_override("fill", sb_fill)
	return bar

static func margins(left: int = 12, right: int = 12, top: int = 10, bottom: int = 10) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_bottom", bottom)
	return m

static func stylebox(bg: Color, corner: int = 10, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(corner)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border
	return sb

## 玩家色小圆片
static func chip(color: Color, side: float = 16.0) -> Panel:
	var c := Panel.new()
	c.custom_minimum_size = Vector2(side, side)
	c.add_theme_stylebox_override("panel", stylebox(color, int(side * 0.5), Color(0.92, 0.92, 0.95), 1))
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func vspace(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

static func hspace(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c
