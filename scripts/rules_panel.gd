class_name RulesPanel
extends RefCounted
## 对局内左下角的「📖 规则说明」：收起时只是一个按钮，点开后**原位向上展开**一个
## 分页规则面板（基础操作 / 回合与行动 / 棋盘与地产 / 经济与胜负 / 道具与事件）。
##
## 与 TableHud 同约定：控件直接写回宿主（game.gd）的同名成员，而不是返回局部变量。
## 文案全部来自 RulesText（数值引用 GameData/ItemData 常量，见该文件说明）。

const PANEL_W := 384.0
const PANEL_H := 422.0
const BTN_W := 132.0

static func build(g: Node) -> void:
	_build_button(g)
	_build_panel(g)
	select_tab(g, "basic")

## 收起态：**右上角**一枚按钮（批次 12 D2 / 设计 §⑩4：从左上角搬到右上、与「战报」并列）。
## 位置是照着「战报」按钮（`table_hud` 里 -106..-12 / 12..40）排的：同一条 y、再往左让开 12 像素。
## 展开的面板**仍在左下角**（384×422 那么大，放右上会盖住战报栏与名册条）——
## 所以这枚按钮的作用更像是"翻到规则那一页"，面板从屏幕另一侧升起来。
static func _build_button(g: Node) -> void:
	g.rules_btn = UIKit.with_icon(UIKit.button("规则说明", 13), "rules", 17)
	g.rules_btn.tooltip_text = "查看操作提示与完整游戏规则"
	g.rules_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	g.rules_btn.offset_left = -118 - BTN_W
	g.rules_btn.offset_right = -118
	g.rules_btn.offset_top = 12
	g.rules_btn.offset_bottom = 40
	g.rules_btn.pressed.connect(func() -> void: g._set_rules_open(true))
	g.add_child(g.rules_btn)

## 展开态：面板 + 分页标签 + 滚动正文
static func _build_panel(g: Node) -> void:
	g.rules_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 12,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.85), 1, 8)
	g.rules_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	g.rules_panel.offset_left = 14
	g.rules_panel.offset_right = 14 + PANEL_W
	g.rules_panel.offset_top = -12 - PANEL_H
	g.rules_panel.offset_bottom = -12
	g.rules_panel.visible = false
	g.add_child(g.rules_panel)
	# 自左下角向上「长出来」，所以缩放的支点放在左下角
	g.rules_panel.pivot_offset = Vector2(0.0, PANEL_H)

	var m := UIKit.margins(12, 12, 10, 10)
	g.rules_panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	m.add_child(v)

	# 标题行：标题 + 收起
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	head.add_child(UIKit.icon_title("rules", "规则说明", 16, UIKit.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	var close_btn := UIKit.button("收起 ▾", 12)
	close_btn.pressed.connect(func() -> void: g._set_rules_open(false))
	head.add_child(close_btn)
	v.add_child(UIKit.label("对局内速查 · 数值随当前版本", 11, UIKit.TEXT_DIM))

	# 分页标签（HFlowContainer：窗口再窄也只是折行，不会溢出）
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	v.add_child(flow)
	g.rules_tabs = {}
	for p in RulesText.pages(g._settings.timeout_tier):
		var key := String(p.key)
		var b := UIKit.button(String(p.title), 12)
		b.custom_minimum_size = Vector2(0, 26)
		b.pressed.connect(func() -> void: select_tab(g, key))
		flow.add_child(b)
		g.rules_tabs[key] = b

	var sep := ColorRect.new()
	sep.color = Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.65)
	sep.custom_minimum_size = Vector2(0, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sep)

	# 正文：RichTextLabel 自带滚动，不必再套 ScrollContainer
	g.rules_body = RichTextLabel.new()
	g.rules_body.bbcode_enabled = true
	g.rules_body.scroll_active = true
	g.rules_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	g.rules_body.add_theme_font_size_override("normal_font_size", 13)
	g.rules_body.add_theme_constant_override("line_separation", 3)
	g.rules_body.add_theme_color_override("default_color", UIKit.TEXT)
	v.add_child(g.rules_body)

## 切换到某一页：正文换文案，标签高亮当前页
static func select_tab(g: Node, key: String) -> void:
	g.rules_tab = key
	for k in g.rules_tabs:
		var b: Button = g.rules_tabs[k]
		UIKit.restyle_button(b, "primary" if k == key else "normal")
	for p in RulesText.pages(g._settings.timeout_tier):
		if String(p.key) == key:
			g.rules_body.text = String(p.body)
			# 换页淡入：正文整块换掉太生硬（一次性过渡，用 Tween）
			g.rules_body.modulate.a = 0.0
			var tw: Tween = g.rules_body.create_tween()
			tw.tween_property(g.rules_body, "modulate:a", 1.0, 0.16)
			return
