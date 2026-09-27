class_name UIKit
## 界面小工具：统一配色与控件创建。

const BG := Color(0.106, 0.118, 0.153)        # 窗口底
const PANEL := Color(0.153, 0.169, 0.216)     # 面板
const PANEL_LIGHT := Color(0.196, 0.212, 0.271)
const ACCENT := Color(0.961, 0.702, 0.259)    # 骰子黄
const TEXT := Color(0.898, 0.914, 0.945)
const TEXT_DIM := Color(0.604, 0.635, 0.702)
const DANGER := Color(0.937, 0.325, 0.314)

static func label(text: String, size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func button(text: String, size: int = 15) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	return b

static func line_edit(placeholder: String, size: int = 15) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size", size)
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

static func vspace(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

static func hspace(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c
