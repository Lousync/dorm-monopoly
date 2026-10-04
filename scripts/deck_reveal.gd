class_name DeckReveal
extends Control
## 「机会 / 命运」抽卡演出的**屏幕层大字卡**（批次 8，见 doc/development/plans/v0.5.0-批次8-设计.md）。
##
## 为什么搬到屏幕层：原先演在桌垫画布（`BoardView._world`）里，靠把 **2D 相机**拉近 2 倍
## （旧 `DECK_PUSH_FACTOR`）才读得出字 —— 那一推会让**印在桌垫上的图案**整体放大滑动，而手牌 /
## 立牌是"不跟 2D 相机"的实物 ⇒ 两者明显错位（用户 ① 报的"画面聚集导致 3D 物品错位"）。
## 本组件把卡改到屏幕层以固定大尺寸演出，**相机全程不动**，错位从根上消失。
##
## 唯一失去的是"从桌上那摞抽起"的实体感（用户选的就是这一档，已接受）⇒ **本组件不依赖
## board / table3d**（不再需要起点供给 `deck_top_provider`，那一路已随本批删除）。
##
## 四段相位与时长与旧版（`BoardView.play_deck_card`）一字不差；房主的等待
##（`game.s_card` 里 `await _wait(DeckReveal.CARD_TIME + 0.1)`）靠 `CARD_TIME` 保持同步。

## 卡的屏幕尺寸（2:3 —— 与旧 `BoardView.CARD_SIZE`(260×390) 同比例，放大到"大字"档）。
const CARD_SIZE := Vector2(320.0, 480.0)
## 四段相位时长（秒）：抽出 → 翻面 → 停留 → 收回。数值与旧版一字不差。
const OUT := 0.34
const FLIP := 0.30
const HOLD := 1.50
const BACK := 0.28
## 总时长（房主结算等待与它同步）。由四相位派生 ⇒ 改相位不会忘记同步。
const CARD_TIME := OUT + FLIP + HOLD + BACK

var _card: Control            # 卡片本体（正反两面铺满它；翻面 = 绕竖轴压扁再张开）
var _back: Control            # 卡背（抽出阶段显示）
var _front: Control           # 卡面（正文）
var _t := 0.0                 # 相位计时（_process 驱动，见项目约定"持续动画手写 _process 相位"）
var _bob := 0.0               # 停留段的上下浮动（屏幕像素）
var _showing := false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 压在棋盘 / 四角身家条之上、**模态带之下**（暂停菜单 / 结算 50 / 弹问 60 / 小卖部 70）。
	# 40 < 模态带里最低的 50 ⇒ 卡绝不压在模态面板之上（模态面板也绝不被卡盖住）。
	# **不能只靠树序**：`z_as_relative` 默认为真，本组件挂在 `hud`(z 0) 里 ⇒ 实效 z 就是 40；
	# 而 `menu_layer` 挂在 `game` 下（也是 0）—— 靠树序时谁在上取决于建/搬节点的顺序，
	# 所以模态层自己也**显式**设了 z（见 `table_hud.build_menu_ui` 的 `menu_layer.z_index`）。
	z_index = 40
	visible = false
	resized.connect(_place)

func _process(delta: float) -> void:
	if _showing:
		tick(delta)

## 屏幕正中亮出一张卡。重复调用先把上一张收掉（幂等）。
func show_card(deck: String, kind: String, text: String) -> void:
	_close()
	var style: Array = UIKit.card_palette(kind)
	var accent: Color = style[0]
	var card := Control.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size = CARD_SIZE
	card.pivot_offset = CARD_SIZE * 0.5        # 绕自己中心压扁 / 缩放
	add_child(card)
	_back = _card_face_back(deck, accent)
	card.add_child(_back)
	_front = _card_face_front(deck, text, style)
	_front.visible = false
	card.add_child(_front)
	card.modulate = Color(1, 1, 1, 0.0)
	card.scale = Vector2(0.55, 0.55)
	card.rotation = -0.05
	_card = card
	_bob = 0.0
	_t = 0.0
	_showing = true
	visible = true
	_place()

## 相位推进（`_process` 每帧调；测试与摆拍可直接快进）。
func tick(delta: float) -> void:
	if not _showing or _card == null or not is_instance_valid(_card):
		return
	_t += delta
	var c: Control = _card
	var t := _t
	if t < OUT:
		var k: float = _ease_out_back(t / OUT)
		c.scale = Vector2(0.55 + 0.45 * k, 0.55 + 0.45 * k)
		c.rotation = -0.05 * (1.0 - k)
		c.modulate = Color(1, 1, 1, clampf(t / 0.16, 0.0, 1.0))
		_bob = 0.0
	elif t < OUT + FLIP:
		var k2 := (t - OUT) / FLIP
		c.rotation = 0.0
		c.scale = Vector2(maxf(1.0 - k2 * 2.0, 0.02), 1.0 + 0.06 * k2)
		if k2 >= 0.5:
			_show_deck_face(false)             # 压到最扁的一瞬换面，看不出来
			var k3 := (k2 - 0.5) * 2.0
			c.scale = Vector2(maxf(k3, 0.02), 1.06 - 0.06 * k3)
		var flash := 1.0 + 0.4 * (1.0 - absf(k2 * 2.0 - 1.0))   # 换面点附近提亮，模拟翻牌反光
		c.modulate = Color(flash, flash, flash, 1.0)
		_bob = 0.0
	elif t < OUT + FLIP + HOLD:
		var h := t - OUT - FLIP
		c.scale = Vector2.ONE
		c.rotation = 0.0
		_bob = sin(h * 2.4) * 3.0
		var breath := 1.0 + 0.03 * (0.5 + 0.5 * sin(h * 3.2))   # 呼吸微光，别像钉在屏幕上
		c.modulate = Color(breath, breath, breath, 1.0)
	elif t < CARD_TIME:
		var k4 := (t - OUT - FLIP - HOLD) / BACK
		c.modulate = Color(1, 1, 1, 1.0 - k4)
		var sc4 := 1.0 - 0.42 * k4
		c.scale = Vector2(sc4, sc4)
		_bob = 0.0
	else:
		_close()
		return
	_place()

## 演出是否进行中（`dev_tools` 的摆拍等待与测试都读它）。
func is_showing() -> bool:
	return _showing

## 把卡摆到本层正中（+ 停留段的浮动）。本层是 FULL_RECT ⇒ 屏幕一改尺寸这里跟着重摆。
func _place() -> void:
	if _card == null or not is_instance_valid(_card):
		return
	_card.position = (size - CARD_SIZE) * 0.5 + Vector2(0.0, _bob)

## 收掉当前这张（重复开演 / 演出结束都走它）。
func _close() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = null
	_back = null
	_front = null
	_bob = 0.0
	_showing = false
	visible = false

## 翻面：true = 显示卡背，false = 显示卡面
func _show_deck_face(back: bool) -> void:
	if _back != null and is_instance_valid(_back):
		_back.visible = back
	if _front != null and is_instance_valid(_front):
		_front.visible = not back

func _ease_out_back(t: float) -> float:
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)

## ---- 以下四个构建函数**从 board_view.gd 原样搬来**，只改两处：
## ① 正文锁宽用新的 `CARD_SIZE`（`CARD_SIZE.x - 104`）；② 字号放大（标题 24→30、正文 15→18、
##    行距 separation 6→8）。其余（卡背图案的 modulate、plate 的配色与内缩、描边）一字不改。

## 机会 / 命运各用一套 CC0 的 Atlas 牌卡背（矢量，来源见根目录 LICENSE）
func _deck_back_tex(deck: String) -> Texture2D:
	return UIKit.tex("res://assets/cards/atlas_back_green_darkred.svg" if deck == "机会"
		else "res://assets/cards/atlas_back_blue_brown.svg")

## 铺满整张牌的卡背图案（压成低透明度线纹）
func _make_card_art(deck: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = _deck_back_tex(deck)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate = Color(1.0, 0.86, 0.55, 0.30) if deck == "机会" else Color(0.78, 0.72, 1.0, 0.30)
	return tr

## 卡面（正面）：同一张牌的图案 + 中央一块文字牌面（牌堆名 + 卡文）
func _card_face_front(deck: String, text: String, style: Array) -> Control:
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UIKit.card_stylebox(style[1], 16, style[0], 2, 12))
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(layer)
	layer.add_child(_make_card_art(deck))
	var plate := UIKit.panel_container(Color(0.045, 0.05, 0.078, 0.88), 12,
		Color(style[0].r, style[0].g, style[0].b, 0.5), 1, 0)
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.offset_left = 34.0
	plate.offset_right = -34.0
	plate.offset_top = 34.0
	plate.offset_bottom = -34.0
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(plate)
	var m := UIKit.margins(16, 16, 14, 14)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(m)
	var v := VBoxContainer.new()
	# 契约是"绝不吃点击"：`STOP` 的后代不会被 `IGNORE` 的祖先屏蔽 ⇒ 这一层也要显式 IGNORE
	#（根 / card / plate / m / layer / rule 都已经是 IGNORE，别只漏这一层）。
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	var title := UIKit.label(deck, 30, style[0])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var rule := ColorRect.new()
	rule.color = Color(style[0].r, style[0].g, style[0].b, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rule)
	var body := UIKit.label(text, 18, UIKit.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(CARD_SIZE.x - 104, 0)   # 锁换行宽度（内宽 − 4）
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	return card

## 卡背：整张铺 CC0 的 Atlas 牌卡背图案
func _card_face_back(deck: String, accent: Color) -> Control:
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UIKit.card_stylebox(
		Color(0.075, 0.068, 0.045), 16, accent, 3, 12,
		Color(accent.r, accent.g, accent.b, 0.12)))
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(layer)
	layer.add_child(_make_card_art(deck))
	return card
