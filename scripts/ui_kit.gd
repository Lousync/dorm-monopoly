class_name UIKit
## 界面小工具：统一配色与控件创建。按钮/卡片使用运行时生成的九宫格渐变纹理
## （圆角 + 纵向渐变 + 描边 + 顶部高光 + 光晕/投影），无需任何外部素材；
## 另附全屏氛围背景（渐变 + 暖光 + 暗角 + 尘埃）与自绘骰子图标、奖牌、徽章。

const BG := Color(0.106, 0.118, 0.153)        # 窗口底
const BG_DEEP := Color(0.055, 0.062, 0.098)   # 渐变深端
const PANEL := Color(0.153, 0.169, 0.216)     # 面板
const PANEL_GLASS := Color(0.153, 0.169, 0.216, 0.93)  # 覆在棋盘上的半透明面板
const PANEL_LIGHT := Color(0.196, 0.212, 0.271)
const BORDER := Color(0.235, 0.259, 0.325)
const ACCENT := Color(0.961, 0.702, 0.259)    # 骰子黄
const ACCENT_HI := Color(1.0, 0.845, 0.52)    # 金色高光端
const ACCENT_DEEP := Color(0.71, 0.462, 0.115)  # 金色暗端
const ACCENT_DARK := Color(0.55, 0.38, 0.10)
const TEXT := Color(0.898, 0.914, 0.945)
const TEXT_DIM := Color(0.604, 0.635, 0.702)
const GOOD := Color(0.455, 0.812, 0.529)
const DANGER := Color(0.937, 0.325, 0.314)

static var _tex_cache := {}

# ---------------- 开源素材加载 ----------------

const PIECE_COLORS := ["Red", "Blue", "Green", "Yellow"]  # 与 GameData.PLAYER_COLORS 顺序对应

## 运行时加载素材纹理：优先走资源导入缓存，未导入时直接读文件，双路径都可用
static func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	if t == null and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			t = ImageTexture.create_from_image(img)
	if t != null:
		_tex_cache[path] = t
	return t

## 主题图标（assets/icons/，Twemoji CC-BY 4.0）
static func icon(name: String) -> Texture2D:
	return tex("res://assets/icons/%s.png" % name)

## Kenney 棋子（assets/pieces/，CC0），color_idx 对应玩家槽位 0~3
static func piece_tex(color_idx: int) -> Texture2D:
	return tex("res://assets/pieces/piece%s_05.png" % PIECE_COLORS[clampi(color_idx, 0, 3)])

## 粗体字体（系统 CJK 字体的 700 字重）——与 theme.tres 同一族，只是加粗。
## 项目里没有粗体字体资源文件，用 SystemFont 现取；取不到时静默退化为常规字重。
static var _font_bold: Font
static func font_bold() -> Font:
	if _font_bold == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([
			"Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC",
			"SimHei", "sans-serif",
		])
		f.set("font_weight", 700)
		_font_bold = f
	return _font_bold

## 粗体标签（格子上的地点名这类要一眼看清的文本）
static func bold_label(text: String, size := 15, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", font_bold())
	return l

## HUD 图标（assets/icons/ui_*.png，Twemoji CC-BY 4.0）：规则/战报/骰子/设置…
static func ui_icon(name: String) -> Texture2D:
	return tex("res://assets/icons/ui_%s.png" % name)

## 给按钮挂 HUD 图标。图标缺货时静默跳过——按钮本身照常可用，
## 不会因为少一张 png 就少一个按钮（素材未导入时 UIKit.tex 会直接读文件兜底）。
##
## ⚠ **只适用于「宽度贴着内容」或「用 offset 钉死宽度」的按钮**（现有的三个调用点都是：
## 左上「暂停」、右上「规则说明」「战报」）。原因：Godot 里图标的落点由 `icon_alignment` 定、
## 文字的落点由 `alignment` 定，**两者互不相干** —— 按钮一旦比内容宽（比如撑满一行的菜单按钮），
## 文字居中而图标贴左内缘，中间会空出一大截。窄按钮看着没问题只是因为两个落点恰好重合。
## 遇到宽按钮请**改用文字符号**（如暂停菜单里「⚙ 设置」，与隔壁的「▶ 继续游戏」同例），
## 或者把图标与文字组成一个 HBox 塞进按钮再整体居中。
static func with_icon(b: Button, icon_name: String, side := 18) -> Button:
	var t := ui_icon(icon_name)
	if t != null:
		b.icon = t
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", side)
		b.add_theme_constant_override("h_separation", 6)
	return b

## 图标 + 标题（面板小标题用）；图标缺货时只剩文字，不会报错
static func icon_title(icon_name: String, text: String, size := 16, color: Color = ACCENT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	var t := ui_icon(icon_name)
	if t != null:
		var tr := TextureRect.new()
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(size + 4, size + 4)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tr)
	row.add_child(label(text, size, color))
	return row

# ---------------- 基础控件 ----------------

static func label(text: String, size: int = 15, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## 大标题：金色描边 + 投影，游戏 logo 感
static func title_label(text: String, size: int, color: Color = ACCENT, outline := -1) -> Label:
	var l := label(text, size, color)
	l.add_theme_color_override("font_outline_color", Color(0.10, 0.058, 0.012, 0.92))
	l.add_theme_constant_override("outline_size", outline if outline >= 0 else maxi(4, size / 5))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 14))
	return l

## kind: "normal" 次要 / "primary" 金色主按钮 / "good" / "danger" 危险操作
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

## 运行时切换按钮配色（如「准备」变绿）；四个状态各生成一张九宫格纹理
static func restyle_button(b: Button, kind: String) -> void:
	var pl := PANEL_LIGHT
	var st := {}
	st["normal"] = [pl.lightened(0.07), pl.darkened(0.13), BORDER, Color(0, 0, 0, 0), 5.0, 0.38]
	st["hover"] = [pl.lightened(0.18), pl.darkened(0.04), BORDER.lightened(0.32), Color(1, 1, 1, 0.06), 7.0, 0.45]
	st["pressed"] = [pl.darkened(0.0), pl.darkened(0.22), BORDER.darkened(0.12), Color(0, 0, 0, 0), 2.0, 0.30]
	st["disabled"] = [
		Color(pl.r, pl.g, pl.b, 0.30), Color(pl.darkened(0.10).r, pl.darkened(0.10).g, pl.darkened(0.10).b, 0.30),
		Color(BORDER.r, BORDER.g, BORDER.b, 0.25), Color(0, 0, 0, 0), 0.0, 0.0]
	var fg := TEXT
	match kind:
		"primary":
			fg = Color(0.17, 0.115, 0.02)
			st["normal"] = [ACCENT_HI, ACCENT.darkened(0.12), ACCENT_DEEP, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.30), 7.0, 0.42]
			st["hover"] = [ACCENT_HI.lightened(0.06), ACCENT.darkened(0.02), ACCENT_DEEP.lightened(0.10), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.44), 9.0, 0.48]
			st["pressed"] = [ACCENT.lightened(0.04), ACCENT_DEEP, ACCENT_DEEP.darkened(0.10), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16), 2.0, 0.34]
			st["disabled"] = [
				Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.28), Color(ACCENT_DEEP.r, ACCENT_DEEP.g, ACCENT_DEEP.b, 0.28),
				Color(ACCENT_DEEP.r, ACCENT_DEEP.g, ACCENT_DEEP.b, 0.25), Color(0, 0, 0, 0), 0.0, 0.0]
		"good":
			fg = Color(0.88, 0.98, 0.90)
			var g := GOOD
			st["normal"] = [g.lightened(0.16), g.darkened(0.24), g.darkened(0.34), Color(g.r, g.g, g.b, 0.22), 6.0, 0.40]
			st["hover"] = [g.lightened(0.26), g.darkened(0.14), g.darkened(0.24), Color(g.r, g.g, g.b, 0.34), 8.0, 0.46]
			st["pressed"] = [g.lightened(0.02), g.darkened(0.34), g.darkened(0.42), Color(0, 0, 0, 0), 2.0, 0.32]
			st["disabled"] = [
				Color(g.r, g.g, g.b, 0.26), Color(g.darkened(0.2).r, g.darkened(0.2).g, g.darkened(0.2).b, 0.26),
				Color(g.r, g.g, g.b, 0.22), Color(0, 0, 0, 0), 0.0, 0.0]
		"danger":
			fg = Color(1.0, 0.88, 0.88)
			var d := DANGER
			st["normal"] = [d.lightened(0.14), d.darkened(0.30), d.darkened(0.38), Color(d.r, d.g, d.b, 0.18), 5.0, 0.40]
			st["hover"] = [d.lightened(0.24), d.darkened(0.18), d.darkened(0.28), Color(d.r, d.g, d.b, 0.30), 7.0, 0.46]
			st["pressed"] = [d.lightened(0.0), d.darkened(0.40), d.darkened(0.46), Color(0, 0, 0, 0), 2.0, 0.32]

	for state in ["normal", "hover", "pressed", "disabled"]:
		var c: Array = st[state]
		b.add_theme_stylebox_override(state, _btn_sb(c[0], c[1], c[2], c[3], c[4], c[5]))
	for s in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, fg)
	b.add_theme_color_override("font_disabled_color", TEXT_DIM)

static func _btn_sb(top: Color, bottom: Color, border: Color, glow: Color, shadow_r: float, shadow_a: float) -> StyleBoxTexture:
	var tp := _rounded_tex(11, top, bottom, border, 1.2, glow, 5.0,
		Color(0, 0, 0, shadow_a), Vector2(0, 2 if shadow_r > 2.0 else 1))
	return _sbt(tp, 14, 14, 5, 7)

static func line_edit(placeholder: String, size: int = 15) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size", size)
	e.custom_minimum_size = Vector2(0, 34)
	var sb_n := stylebox(Color(0.104, 0.115, 0.153), 8, BORDER.darkened(0.08), 1, 3, Color(0, 0, 0, 0.32))
	sb_n.content_margin_left = 10
	sb_n.content_margin_right = 10
	var sb_f := stylebox(Color(0.125, 0.137, 0.178), 8, ACCENT, 1, 7, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.28), Vector2.ZERO)
	sb_f.content_margin_left = 10
	sb_f.content_margin_right = 10
	e.add_theme_stylebox_override("normal", sb_n)
	e.add_theme_stylebox_override("focus", sb_f)
	e.add_theme_color_override("font_color", TEXT)
	e.add_theme_color_override("font_placeholder_color", TEXT_DIM.darkened(0.25))
	e.add_theme_color_override("caret_color", ACCENT)
	e.add_theme_color_override("selection_color", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.3))
	return e

## 点击输入框之外时收掉 LineEdit 的焦点。**凡是有 LineEdit 的场景，在 `_input()` 里调一行即可**：
##     func _input(e: InputEvent) -> void:
##         UIKit.release_focus_on_click(self, e)
##
## **病因（用户在两个入口各报过一次，同一处根因）**：本项目按钮一律 `FOCUS_NONE`（见 `button()`），
## 标签 `MOUSE_FILTER_IGNORE`、面板也不吃键盘焦点 ⇒ **点哪儿 LineEdit 都还攥着焦点**，
## 那个金色的 `focus` 样式（见 `line_edit()`）就一直挂着 —— 2026-10-08 主菜单的昵称框、
## 2026-10-09 大厅的聊天框。
##
## **走 `_input`（比 GUI 拾取**先**拿到事件）**：点**落在输入框内**就一个字都不动、让 LineEdit
## 自己处理光标定位；落在别处才收焦点，而这次点击**照常派发给下面的控件** —— 不吞按钮的点击，
## 也不影响「点房间列表的加入」「点确定」这些操作（它们在 `release_focus()` 之后照常收到事件）。
##
## **判据读事件自带的位置，不读 `get_mouse_position()`**：合成事件（测试用 `push_input` 塞进来的）
## 里两者不是一回事 —— 读后者会让本函数在测试里形同虚设（永远拿真鼠标的位置去比）。真机点击两者相同。
static func release_focus_on_click(host: Node, e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var vp := host.get_viewport()
	if vp == null:
		return
	var f := vp.gui_get_focus_owner()
	if f is LineEdit and not f.get_global_rect().has_point(mb.global_position):
		f.release_focus()

# ---------------- 小节容器（legend 式边框盒）与开关组件（设置弹窗用，2026-10-09） ----------------

## 小节盒子的底色。**必须不透明** —— 标题是用这一色盖掉上边框中间那一截画出来的
##（见 `SectionBox`），半透明就盖不干净。比弹窗底色（`PANEL_GLASS`）稍暗一档 ⇒ 读作"嵌进去的盒子"。
const SECTION_BG := Color(0.116, 0.130, 0.172)

## 开关的轨道尺寸与关机色（开机色直接用 `GOOD` 绿）。
const SWITCH_W := 52.0
const SWITCH_H := 26.0
const SWITCH_OFF := Color(0.30, 0.33, 0.40)

## 一个带边框的小节盒子，小标题骑在上边框正中（legend 式）。往里塞内容用 `body()` 拿那个 VBox。
static func section_box(title: String) -> SectionBox:
	return SectionBox.new(title, SECTION_BG, Color(BORDER.r, BORDER.g, BORDER.b, 0.85))

## 一个 on/off 开关组件；点一下翻转，翻转后回调 `on_change(新值)`。
## **替代原先「关 / 开」两枚 chip**（用户 2026-10-09）。外部改状态走 `set_on()`。
static func switch_toggle(initial: bool, on_change: Callable) -> Switch:
	var s := Switch.new(initial)
	s.toggled.connect(on_change)
	return s

## ---- 小节内容的三行「说明 + 控件」套路 ----------------------------------------------------
## **两个设置面板共用这一份**（大厅「游戏设置」弹窗 / 对局内暂停的设置面板，2026-10-09 统一）：
## 原先只有大厅那三只是 `lobby.gd` 的私有方法，对局内那一版要照着再抄一遍 —— 抄件迟早走样。
## 说明一律 `TEXT_DIM` + **可折行**：不带 `autowrap_mode` 的 Label 会把**整个弹窗撑宽**
##（实测大厅那边一句长说明就把弹窗从 680 顶到 758：中心容器按内容最小宽走）。

## 一行说明（无控件，占整行）
static func note(text: String, px := 13) -> Label:
	var l := label(text, px, TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## 「说明 + 任意控件」一行（开关 / 滑块都用它）：说明占满剩余宽度并折行，控件贴右内缘
static func ctrl_row(text: String, ctrl: Control, px := 13) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := label(text, px, TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	row.add_child(ctrl)
	return row

## 「说明 + 数字输入」一行（只收数字；越界钳制由调用方做）
static func num_row(text: String, edit: LineEdit, px := 13) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := label(text, px, TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	row.add_child(edit)
	return row

static func panel(bg: Color, corner: int = 10, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", stylebox(bg, corner, border, border_w))
	return p

## 会为子控件分配尺寸的面板（Panel 不会，装内容请用这个）；
## 默认带纵向渐变与投影，是游戏里的「卡片」。
static func panel_container(bg: Color, corner: int = 10, border: Color = Color(0, 0, 0, 0), border_w: int = 0, shadow := 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", card_stylebox(bg, corner, border, border_w, shadow))
	return p

## 渐变卡片样式：顶亮底暗 + 描边 + 可选金色光晕 / 投影
## 图形本体铺满九宫格中心区，阴影/光晕画在四周 pad 余量里并经 expand_margin 画出控件外，
## 圆角因此始终落在角切片内，不会被拉伸变形。
static func card_stylebox(bg: Color, corner := 10, border := Color(0, 0, 0, 0), border_w := 0, shadow := 0, glow := Color(0, 0, 0, 0)) -> StyleBoxTexture:
	var top := bg.lightened(0.055)
	top.a = bg.a
	var bottom := bg.darkened(0.075)
	bottom.a = bg.a
	var sh := Color(0, 0, 0, 0.4) if shadow > 0 else Color(0, 0, 0, 0)
	var tp := _rounded_tex(corner, top, bottom, border, border_w, glow, 5.0, sh, Vector2(0, 2))
	return _sbt(tp)

## 事件/公告卡配色：按 kind 返回 [边框色, 底色]（牌堆抽卡与顶部公告共用）。
## **2026-10-10 卡面美化**：卡型色的**单一来源改到 `GameData.CARD_KINDS`**（图鉴页与演出同源），
## 本函数只做"取色 + 补底色"的适配，不再自己写色 —— 原先三处各写一套、五路全不等
##（`jail` 卡面紫 / 页面琥珀，`info` 卡面金 / 页面灰蓝）。
## `bust` / `aberr` 是**公告类**、不在 `card_kind()` 的五个返回值里 ⇒ 不进 `CARD_KINDS`，照旧字面量。
## 注意：本文件不能反过来被 `game_data.gd` 引（它要在 `--script` 下裸用），所以是单向依赖。
static func card_palette(kind: String) -> Array:
	var fg := func(k: String, fb: Color) -> Color:
		var d: Dictionary = GameData.CARD_KINDS.get(k, {})
		return d.get("color", fb)
	match kind:
		"good":
			return [fg.call("good", GOOD), Color(0.10, 0.18, 0.12, 0.95)]
		"bad":
			return [fg.call("bad", Color(0.94, 0.45, 0.42)), Color(0.20, 0.09, 0.09, 0.95)]
		"move":
			return [fg.call("move", Color(0.42, 0.70, 0.95)), Color(0.09, 0.14, 0.21, 0.95)]
		"jail":
			return [fg.call("jail", Color(0.66, 0.52, 0.95)), Color(0.13, 0.10, 0.20, 0.95)]
		"info":
			return [fg.call("info", ACCENT), Color(0.16, 0.14, 0.08, 0.95)]
		"bust":
			return [Color(0.95, 0.35, 0.35), Color(0.22, 0.07, 0.07, 0.95)]
		"aberr":
			return [Color(0.79, 0.65, 1.0), Color(0.12, 0.09, 0.20, 0.95)]   # 畸变：紫
		_:
			return [ACCENT, Color(0.16, 0.14, 0.08, 0.95)]

## 进度条（弹窗倒计时用），填充带微光
static func progress(fg: Color = ACCENT) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	var sb_bg := stylebox(Color(0.075, 0.082, 0.118), 4, Color(BORDER.r, BORDER.g, BORDER.b, 0.6), 1)
	var sb_fill := stylebox(fg, 4, Color(1, 1, 1, 0.25), 1, 4, Color(fg.r, fg.g, fg.b, 0.5), Vector2.ZERO)
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

static func stylebox(bg: Color, corner: int = 10, border: Color = Color(0, 0, 0, 0), border_w: int = 0,
		shadow := 0, shadow_col := Color(0, 0, 0, 0.38), shadow_off := Vector2(0, 2)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(corner)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border
	if shadow > 0:
		sb.shadow_color = shadow_col
		sb.shadow_size = shadow
		sb.shadow_offset = shadow_off
	return sb

## 玩家色小棋子（Kenney 桌游棋子，CC0）；素材缺失时退回纯色圆片
static func chip(color: Color, side: float = 16.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(side, side)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var idx: int = GameData.PLAYER_COLORS.find(color)
	if idx >= 0:
		var t := piece_tex(idx)
		if t != null:
			var tr := TextureRect.new()
			tr.texture = t
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.offset_bottom = -1.0
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.add_child(tr)
			return c
	var p := Panel.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.add_theme_stylebox_override("panel", stylebox(color, int(side * 0.5),
		Color(0.93, 0.93, 0.96, 0.9), 2 if side >= 18 else 1, 3, Color(0, 0, 0, 0.4)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(p)
	return c

## 一排单选 chips（ids + id->文案）；点选回调 on_pick(id)。
## 建出来的 HBox 带 meta "chips" = {id: Button}，用 chip_select() 刷新高亮。
## `tooltips`（可选，id → 文案）给某几枚挂悬停说明 —— 用于"这一档的真实含义看文案看不出来"的场合
##（现用：操作限时的「现状」档，见 `GameSettings.TIER_CURRENT_HINT`）。没给到的 id 不挂。
static func chip_row(ids: Array, labels: Dictionary, on_pick: Callable,
		tooltips: Dictionary = {}) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var map := {}
	for id in ids:
		var sid := String(id)
		var b := button(String(labels.get(sid, sid)), 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = String(tooltips.get(sid, ""))
		b.pressed.connect(func() -> void: on_pick.call(sid))
		row.add_child(b)
		map[sid] = b
	row.set_meta("chips", map)
	return row

## 高亮某个 chip，其余回普通样式
static func chip_select(row: HBoxContainer, id: String) -> void:
	if row == null:
		return
	var map: Dictionary = row.get_meta("chips", {})
	for k in map:
		restyle_button(map[k], "primary" if String(k) == id else "normal")

## 圆角小徽章（「已准备」等），fg 决定文字与描边色调
static func pill(text: String, fg: Color, size := 12) -> PanelContainer:
	var p := PanelContainer.new()
	var bg := Color(fg.r, fg.g, fg.b, 0.13)
	p.add_theme_stylebox_override("panel", card_stylebox(bg, 9, Color(fg.r, fg.g, fg.b, 0.6), 1, 0, Color(fg.r, fg.g, fg.b, 0.10)))
	var m := margins(9, 9, 2, 3)
	p.add_child(m)
	m.add_child(label(text, size, fg.lightened(0.28)))
	return p

## 圆形徽章（**从 `ItemCard._badge` 纯搬移**，外观零变化）：圆 + 描边 + 投影。
## 「骑在卡边外」是**使用者给的落点**决定的（如 `(-bs * 0.42, -bs * 0.42)`，约六成落在卡内），
## 本函数不管落点 —— 文字卡与 `ItemCard` 各自在自己那边摆。
## ⚠ 名字带 `badge` 是为了与上面那个 `pill(text, fg, size)`（**文字胶囊 chip**）分开 —— 两者不是一回事。
static func badge_round(side: float, bg: Color, border: Color) -> Panel:
	var b := Panel.new()
	b.size = Vector2(side, side)
	b.add_theme_stylebox_override("panel", stylebox(bg, int(side * 0.5), border, 2, 2))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

## 胶囊徽章（文字标用，如「一次性」「🚨 查寝」）：圆角矩形而非圆。同上，纯搬移、不管落点。
static func badge_pill(sz: Vector2, bg: Color, border: Color) -> Panel:
	var b := Panel.new()
	b.size = sz
	b.add_theme_stylebox_override("panel", stylebox(bg, int(sz.y * 0.5), border, 2, 2))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

## 排名奖牌：1 金 / 2 银 / 3 铜 / 其余石板灰
static func rank_badge(rank: int, side := 26.0) -> Panel:
	var palettes := [
		[Color(1.0, 0.86, 0.52), Color(0.72, 0.47, 0.10)],
		[Color(0.86, 0.90, 0.96), Color(0.48, 0.54, 0.64)],
		[Color(0.94, 0.68, 0.42), Color(0.55, 0.32, 0.13)],
		[Color(0.42, 0.46, 0.56), Color(0.24, 0.27, 0.34)],
	]
	var pal: Array = palettes[mini(rank - 1, palettes.size() - 1)]
	var p := Panel.new()
	p.custom_minimum_size = Vector2(side, side)
	# 深色金属外环 + 亮色内芯模拟立体奖牌
	p.add_theme_stylebox_override("panel", stylebox(pal[1], int(side * 0.5),
		Color(0.95, 0.95, 0.98, 0.85), 2, 3, Color(0, 0, 0, 0.45)))
	var inner := Panel.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 3
	inner.offset_top = 3
	inner.offset_right = -3
	inner.offset_bottom = -3
	inner.add_theme_stylebox_override("panel", stylebox(pal[0], int(side * 0.5) - 2))
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(inner)
	var l := label(str(rank), int(side * 0.52), Color(0.24, 0.15, 0.03) if rank <= 3 else Color(0.92, 0.94, 0.98))
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func vspace(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

static func hspace(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c

# ---------------- 九宫格渐变纹理（程序生成） ----------------

## 圆角矩形 SDF（负值在内部）
static func _sdf_round(p: Vector2, center: Vector2, half: Vector2, r: float) -> float:
	var q := (p - center).abs() - (half - Vector2(r, r))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r

## 逐像素生成「圆角 + 纵向渐变 + 描边 + 顶部高光 + 光晕/投影」纹理。
## 九宫格布局：图形本体从 pad 处铺到纹理边缘（pad 只容纳阴影/光晕溢出），
## 切片边距 m = pad + 圆角 + 1，圆角完整落在角切片内；返回 [纹理, 切片边距, pad]。结果全部缓存。
static func _rounded_tex(corner: float, top: Color, bottom: Color, border: Color, border_w: float,
		glow: Color, glow_r: float, shadow: Color, shadow_off: Vector2, pad := 6) -> Array:
	var m := int(pad + corner) + 1
	var size := m * 2 + 24
	var key := "%s|%s|%s|%.1f|%.0f|%s|%.0f|%s|%s|%d" % [top, bottom, border, border_w, corner, glow, glow_r, shadow, shadow_off, pad]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rect := Rect2(Vector2(pad, pad), Vector2.ONE * (size - pad * 2.0))
	var center := rect.get_center()
	var half := rect.size * 0.5
	for y in size:
		for x in size:
			var p := Vector2(x, y) + Vector2(0.5, 0.5)
			var d := _sdf_round(p, center, half, corner)
			var col := Color(0, 0, 0, 0)
			if d < 0.0:
				var v := clampf((p.y - rect.position.y) / rect.size.y, 0.0, 1.0)
				var rgb := top.lerp(bottom, v)
				rgb = rgb.lerp(Color(1, 1, 1), clampf(1.0 - v / 0.42, 0.0, 1.0) * 0.10)
				var a := top.a
				if border_w > 0.0 and border.a > 0.0:
					# 描边带：最外缘为纯描边色，向内 border_w 像素渐变回填充色
					var t := 1.0 - clampf(-d / maxf(border_w, 0.5), 0.0, 1.0)
					rgb = rgb.lerp(border, t)
					a = maxf(a, border.a * t)
				# 保留填充自身透明度（半透明卡片/玻璃），乘边缘抗锯齿覆盖
				col = Color(rgb.r, rgb.g, rgb.b, a * clampf(0.5 - d, 0.0, 1.0))
			else:
				var a_g := 0.0
				if glow.a > 0.0:
					a_g = glow.a * exp(-maxf(d, 0.0) / glow_r)
				var a_s := 0.0
				if shadow.a > 0.0:
					a_s = shadow.a * exp(-maxf(_sdf_round(p - shadow_off, center, half, corner), 0.0) / 4.0)
				var a := a_g + a_s * (1.0 - a_g)
				if a > 0.004:
					col = Color(
						(glow.r * a_g + shadow.r * a_s * (1.0 - a_g)) / a,
						(glow.g * a_g + shadow.g * a_s * (1.0 - a_g)) / a,
						(glow.b * a_g + shadow.b * a_s * (1.0 - a_g)) / a, a)
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	var out := [tex, m, pad]
	_tex_cache[key] = out
	return out

static func _sbt(tp: Array, cl := -1, cr := -1, ct := -1, cb := -1) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tp[0]
	var m: int = tp[1]
	var pad: int = tp[2]
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	# 阴影/光晕余量画到控件矩形之外，图形本体正好对齐控件边界
	sb.expand_margin_left = pad
	sb.expand_margin_right = pad
	sb.expand_margin_top = pad
	sb.expand_margin_bottom = pad
	sb.content_margin_left = cl if cl >= 0 else 12
	sb.content_margin_right = cr if cr >= 0 else 12
	sb.content_margin_top = ct if ct >= 0 else 8
	sb.content_margin_bottom = cb if cb >= 0 else 8
	return sb

## 纯色渐变 TextureRect（背景 / 光斑 / 暗角用）
static func grad_rect(colors: Array, offsets: Array, radial := false, from := Vector2(0.5, 0.0), to := Vector2(0.5, 1.0)) -> TextureRect:
	var g := Gradient.new()
	var cs := PackedColorArray()
	for c in colors:
		cs.append(c)
	g.colors = cs
	var os := PackedFloat32Array()
	for o in offsets:
		os.append(o)
	g.offsets = os
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL if radial else GradientTexture2D.FILL_LINEAR
	tex.fill_from = from
	tex.fill_to = to
	tex.width = 128
	tex.height = 128
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

# ---------------- 氛围背景与装饰部件 ----------------

## 全屏氛围背景：深蓝纵向渐变 + 顶部金色暖光 + 四角暗角（+ 尘埃粒子）
static func decor_bg(with_dust := true) -> Control:
	return DecorBg.new(with_dust)

## 自绘小骰子（五点面），标题 / 棋盘装饰用
static func dice_icon(px := 34.0) -> Control:
	return DiceIcon.new(px)

class DecorBg extends Control:
	## 渐变底 + 暖光 + 暗角 + 缓缓上浮的微光尘埃（菜单 / 大厅）
	const DUST_N := 44
	var _dust := []
	var _t := 0.0
	var _with_dust := true

	func _init(with_dust := true) -> void:
		_with_dust = with_dust
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _ready() -> void:
		add_child(UIKit.grad_rect(
			[Color(0.045, 0.05, 0.082), Color(0.108, 0.12, 0.168), Color(0.072, 0.08, 0.122)],
			[0.0, 0.46, 1.0]))
		add_child(UIKit.grad_rect(
			[Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.12), Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.0)],
			[0.0, 1.0], true, Vector2(0.5, 0.14), Vector2(0.5, 0.92)))
		add_child(UIKit.grad_rect(
			[Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.42)],
			[0.0, 1.0], true, Vector2(0.5, 0.5), Vector2(0.5, -0.12)))
		for i in DUST_N:
			_dust.append({
				"x": randf(), "y": randf(), "spd": randf_range(0.012, 0.045),
				"r": randf_range(1.2, 3.2), "ph": randf() * TAU, "gold": randf() < 0.62,
			})

	func _process(delta: float) -> void:
		if not _with_dust:
			return
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if not _with_dust:
			return
		for d in _dust:
			var y := fposmod(float(d.y) - _t * float(d.spd), 1.06) - 0.03
			var x := float(d.x) + sin(_t * 0.5 + float(d.ph)) * 0.014
			var a := 0.05 + 0.10 * (0.5 + 0.5 * sin(_t * 1.4 + float(d.ph) * 2.0))
			var col := Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, a) if bool(d.gold) else Color(0.85, 0.9, 1.0, a)
			draw_circle(Vector2(x, y) * size, float(d.r), col)

class DiceIcon extends Control:
	## 渐变骰面 + 五点骰点 + 高光，尺寸随构造参数
	var _face: StyleBoxTexture

	func _init(px := 34.0) -> void:
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_face = UIKit.card_stylebox(UIKit.ACCENT, int(px * 0.30), UIKit.ACCENT_DEEP.darkened(0.1), 2, 3,
			Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.22))

	func _draw() -> void:
		draw_style_box(_face, Rect2(Vector2.ZERO, size))
		var inset := size.x * 0.27
		var r := size.x * 0.075
		for q in [Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 0.5), Vector2(0, 1), Vector2(1, 1)]:
			var c := Vector2(inset, inset) + Vector2(q) * (size.x - inset * 2.0)
			draw_circle(c + Vector2(0, 1.2), r, Color(0, 0, 0, 0.35))
			draw_circle(c, r, Color(0.16, 0.115, 0.03))
			draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.34, Color(1, 0.96, 0.82, 0.3))

class SectionBox extends MarginContainer:
	## 带边框的小节盒，小标题**骑在上边框正中**（legend / fieldset 式）。
	##
	## **为什么要自己写**：Godot 没有 fieldset 这类现成控件。想在边框中间开个缺口放标题，
	## 有两条路 —— 拆成两段 StyleBox 手工拼，或者像这里：`_draw()` 先把整圈边框画出来，
	## 再用**与小节底色同色**的一小块**盖掉**上边框中间那一截，最后把标题画上去。
	## 于是有了那条硬前提：小节底色必须**不透明**（见 `UIKit.SECTION_BG`）。
	##
	## **标题不是子节点、是在 `_draw()` 里画的** —— 这样它不参与布局，盒子的高度仍然
	## 完全由内容驱动（本类就是 `MarginContainer`）；代价是内容的上边距得自己给标题留位置
	##（`TOP_PAD`）。标题有一半在盒子**外**（上边框之上），所以放它的容器（滚动区的 VBox）
	## 要留够间隔，最上面一节还得垫一块空白，否则会被 `ScrollContainer` 裁掉。
	const TOP_PAD := 24        # 内容距盒顶（给骑在边框上的标题让位）
	const SIDE_PAD := 14
	const BOTTOM_PAD := 12
	const TITLE_PX := 14
	const TITLE_GAP := 9       # 标题底色往两侧多留的宽，做出"缺口"

	var _text := ""
	var _bg := Color.BLACK
	var _sb: StyleBoxFlat
	var _body: VBoxContainer

	func _init(title: String, bg: Color, border: Color) -> void:
		_text = title
		_bg = bg
		add_theme_constant_override("margin_top", TOP_PAD)
		add_theme_constant_override("margin_left", SIDE_PAD)
		add_theme_constant_override("margin_right", SIDE_PAD)
		add_theme_constant_override("margin_bottom", BOTTOM_PAD)
		_sb = StyleBoxFlat.new()
		_sb.bg_color = bg
		_sb.set_corner_radius_all(10)
		_sb.set_border_width_all(1)
		_sb.border_color = border
		_body = VBoxContainer.new()
		_body.add_theme_constant_override("separation", 7)
		add_child(_body)

	## 往里放内容的 VBox（行与行之间已给好 7px 间隔）。
	func body() -> VBoxContainer:
		return _body

	## 尺寸一变就得重画（标题是按 `size.x` 居中的）。
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		draw_style_box(_sb, Rect2(Vector2.ZERO, size))
		var f := UIKit.font_bold()
		var tw: float = f.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_PX).x
		var asc: float = f.get_ascent(TITLE_PX)
		var desc: float = f.get_descent(TITLE_PX)
		var h: float = asc + desc
		# 标题的竖直中心 = 上边框（y = 0）⇒ 上半个字探到盒外，正是 legend 的样子
		var left: float = size.x * 0.5 - tw * 0.5
		draw_rect(Rect2(left - TITLE_GAP, -h * 0.5, tw + TITLE_GAP * 2.0, h), _bg, true)
		draw_string(f, Vector2(left, (asc - desc) * 0.5), _text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_PX, UIKit.ACCENT)

class Switch extends Control:
	## on/off 开关组件（程序化绘制 —— 与项目"能画出来的就别加素材"那条一致：转盘 / 房子贴图 /
	## 卡面 / 按钮九宫格都是这么来的）。点一下翻转，翻转后 `toggled.emit(新值)`。
	##
	## 滑块位置 `_t` 是**手写的 `_process` 相位**（0 = 关、1 = 开，静止时 `set_process(false)`），
	## 与项目"持续动画手写相位"那条约定同形；一次翻转约 1/7 秒。
	signal toggled(on: bool)

	var on := false
	var _t := 0.0
	var _hover := false

	func _init(initial := false) -> void:
		on = initial
		_t = 1.0 if initial else 0.0
		custom_minimum_size = Vector2(UIKit.SWITCH_W, UIKit.SWITCH_H)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		focus_mode = Control.FOCUS_NONE
		tooltip_text = "开 / 关"
		set_process(false)

	## 外部改状态（`_sync_panel` 刷回显用）。`animate = false` 直接落位 ——
	## 打开弹窗时不该看到滑块自己滑一遍。
	func set_on(v: bool, animate := true) -> void:
		if v == on:
			return
		on = v
		if animate:
			set_process(true)
		else:
			_t = 1.0 if v else 0.0
			set_process(false)
			queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		set_on(not on)
		toggled.emit(on)
		accept_event()
		Fx.play("click", -8.0, randf_range(0.95, 1.05))

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			_hover = true
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			_hover = false
			queue_redraw()

	func _process(delta: float) -> void:
		var target := 1.0 if on else 0.0
		_t = move_toward(_t, target, delta * 7.0)
		if is_equal_approx(_t, target):
			_t = target
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		var r: float = size.y * 0.5
		var col: Color = UIKit.SWITCH_OFF.lerp(UIKit.GOOD, _t)
		if _hover:
			col = col.lightened(0.10)
		_capsule(Rect2(Vector2.ZERO, size), col.darkened(0.45))                 # 一圈暗边
		_capsule(Rect2(Vector2(1.5, 1.5), size - Vector2(3.0, 3.0)), col)
		var kr: float = r - 3.0
		var kx: float = r + _t * (size.x - r * 2.0)
		draw_circle(Vector2(kx, r + 1.0), kr, Color(0, 0, 0, 0.30))             # 滑块投影
		draw_circle(Vector2(kx, r), kr, Color(0.94, 0.95, 0.97))

	## 胶囊形（两端半圆的长条）：中段矩形 + 两端圆。
	func _capsule(rect: Rect2, col: Color) -> void:
		var r: float = rect.size.y * 0.5
		draw_rect(Rect2(rect.position.x + r, rect.position.y, rect.size.x - r * 2.0, rect.size.y), col, true)
		draw_circle(rect.position + Vector2(r, r), r, col)
		draw_circle(rect.position + Vector2(rect.size.x - r, r), r, col)
