class_name CodexPanel
extends RefCounted
## 对局内右上角的「📖 图鉴」：一枚**开关按钮** + 其下方展开的**图鉴面板**（2026-10-11 加）。
##
## **内容 = `CardDB` 已归一化的三族**（道具 / 科技 / 畸变），与
## `doc/game-design/图鉴.html` **同源** —— 那张网页由 `tools/gen_gallery.gd` 从同一批数据表
## 生成，是**给团队查的**；这一份是**对局里给玩家查的**。事件族暂不纳入（`CardDB.FAMILIES`
## 的现状，与网页一致）。
##
## 与 `RulesPanel` 同约定：控件直接写回宿主（game.gd）的同名成员，而不是返回局部变量。
## 与「规则说明」「战报」**互斥** —— 三者占右上同一块地方（见 `game._set_codex_open`）。
##
## **为什么不做成 `--card-gallery` 那种"卡片模板预览"**：那个（现在住在 `dev_tools.gd`）
## 陈列的是**三种尺寸 × 各种状态**的模板，用来核对卡面规格；玩家要查的是"有哪些道具、
## 各是什么效果" ⇒ 这里按**族**分页、按**条目**陈列。

const PANEL_W := 430.0
const PANEL_H := 472.0
const BTN_W := 96.0
## 本按钮排在「规则说明」按钮**左边 12px**（那枚占 `RULES_LEFT..-118`，见 `rules_panel.gd`）。
const RULES_LEFT := -250.0

## 一族一页（族键直接用 `CardDB` 的族名，`CardDB.ids(family)` 就是条目清单）。
const TABS := ["item", "tech", "aberration"]
const TAB_TITLES := {"item": "道具", "tech": "科技", "aberration": "畸变"}

static func build(g: Node) -> void:
	_build_button(g)
	_build_panel(g)
	select_tab(g, "item")

## 收起态：**右上角**一枚按钮（与「规则说明」「战报」同一条 y）。
##
## 图标用**文字符号**而不是 `UIKit.with_icon`：`assets/icons/ui_*.png` 里没有"书 / 图鉴"
## 这一枚，而复用「战报」的 `report` 会让紧挨着的两枚按钮**同一张图**（那两枚就在隔壁）。
## 文字符号是本仓已有的先例（暂停菜单里的「⚙ 设置」），且不新增素材（AGENTS §四）。
static func _build_button(g: Node) -> void:
	g.codex_btn = UIKit.button("📖 图鉴", 13)
	g.codex_btn.tooltip_text = "查看道具 / 科技 / 畸变图鉴（再点一次收起）"
	g.codex_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	g.codex_btn.offset_left = RULES_LEFT - 12.0 - BTN_W
	g.codex_btn.offset_right = RULES_LEFT - 12.0
	g.codex_btn.offset_top = 12
	g.codex_btn.offset_bottom = 40
	g.codex_btn.pressed.connect(func() -> void: g._set_codex_open(not g.codex_open))
	g.add_child(g.codex_btn)

## 展开态：标题行 + 分页标签 + 搜索框 + 滚动清单。
## 落点与「规则说明」面板**逐字相同**（右边缘 −12、顶边 84）—— 两者本就互斥，重合无妨，
## 而且"点哪一枚都在同一块地方长出来"才不跳眼。
static func _build_panel(g: Node) -> void:
	g.codex_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 12,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.85), 1, 8)
	g.codex_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	g.codex_panel.offset_left = -12.0 - PANEL_W
	g.codex_panel.offset_right = -12.0
	g.codex_panel.offset_top = 84
	g.codex_panel.offset_bottom = 84 + PANEL_H
	g.codex_panel.visible = false
	g.add_child(g.codex_panel)
	# 自右上角向下「长出来」，缩放支点放右上角（与规则面板同）
	g.codex_panel.pivot_offset = Vector2(PANEL_W, 0.0)

	var m := UIKit.margins(12, 12, 10, 10)
	g.codex_panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	m.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	head.add_child(UIKit.label("图鉴", 16, UIKit.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	var close_btn := UIKit.button("收起 ▾", 12)
	close_btn.pressed.connect(func() -> void: g._set_codex_open(false))
	head.add_child(close_btn)
	v.add_child(UIKit.label("道具 / 科技 / 畸变 · 与 doc/game-design/图鉴.html 同源", 11, UIKit.TEXT_DIM))

	# 分页标签（HFlowContainer：窗口再窄也只是折行，不溢出）
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	v.add_child(flow)
	g.codex_tabs = {}
	for key in TABS:
		var b := UIKit.button(String(TAB_TITLES.get(key, key)), 12)
		b.custom_minimum_size = Vector2(0, 26)
		b.pressed.connect(func() -> void: select_tab(g, key))
		flow.add_child(b)
		g.codex_tabs[key] = b

	g.codex_search = LineEdit.new()
	g.codex_search.placeholder_text = "搜索名称 / 描述…"
	g.codex_search.clear_button_enabled = true
	g.codex_search.add_theme_font_size_override("font_size", 12)
	g.codex_search.text_changed.connect(func(_t: String) -> void: refresh(g))
	v.add_child(g.codex_search)

	var sep := ColorRect.new()
	sep.color = Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.65)
	sep.custom_minimum_size = Vector2(0, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	g.codex_list = VBoxContainer.new()
	g.codex_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.codex_list.add_theme_constant_override("separation", 10)
	scroll.add_child(g.codex_list)

## 切到某一页：标签高亮当前页，清单重刷。
static func select_tab(g: Node, key: String) -> void:
	g.codex_tab = key
	for k in g.codex_tabs:
		UIKit.restyle_button(g.codex_tabs[k], "primary" if String(k) == key else "normal")
	refresh(g)

## 按**当前页 + 搜索词**重刷清单。数据是常量表、对局中不变 ⇒ 只在切页 / 改词时跑，不逐帧。
static func refresh(g: Node) -> void:
	if g.codex_list == null or not is_instance_valid(g.codex_list):
		return
	_clear(g.codex_list)
	var fam := String(g.codex_tab)
	var q := ""
	if g.codex_search != null and is_instance_valid(g.codex_search):
		q = String(g.codex_search.text).strip_edges().to_lower()
	var n := 0
	if fam == CardDB.FAMILY_ITEM:
		# 道具：摆真卡（`ItemCard.SIZE_SMALL`，与道具栏同尺寸）——"长什么样"本身就是图鉴的一半
		var row := HFlowContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("h_separation", 10)
		row.add_theme_constant_override("v_separation", 8)
		g.codex_list.add_child(row)
		for id in CardDB.ids(fam):
			if not _match(fam, String(id), q):
				continue
			row.add_child(_item_cell(String(id)))
			n += 1
	else:
		for id in CardDB.ids(fam):
			if not _match(fam, String(id), q):
				continue
			g.codex_list.add_child(_text_row(fam, String(id)))
			n += 1
	if n == 0:
		g.codex_list.add_child(UIKit.label("没有匹配的条目", 12, UIKit.TEXT_DIM))

## 搜索命中：名称或描述含关键词（大小写不敏感）。空词 = 全过。
static func _match(fam: String, id: String, q: String) -> bool:
	if q == "":
		return true
	var meta := CardDB.def(fam, id)
	return id.to_lower().contains(q) or String(meta.get("desc", "")).to_lower().contains(q)

static func _clear(n: Node) -> void:
	for c in n.get_children():
		# **先摘再 free**：`queue_free` 要到帧末才真删，同帧再刷一次会看到旧的还挂在树上。
		n.remove_child(c)
		c.queue_free()

## 道具格：真卡 + 名称（品质已印在卡面底条上，这里不重复写一遍）
static func _item_cell(id: String) -> Control:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 3)
	var holder := Control.new()
	holder.custom_minimum_size = ItemCard.SIZE_SMALL + Vector2(8, 8)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(holder)
	var card := ItemCard.make(id, ItemCard.SIZE_SMALL)
	card.position = Vector2(4, 4)
	holder.add_child(card)
	var col: Color = CardDB.category_color(CardDB.FAMILY_ITEM,
		String(CardDB.def(CardDB.FAMILY_ITEM, id).get("category", "")))
	var cap := UIKit.label(id, 11, col)
	cap.custom_minimum_size = Vector2(ItemCard.SIZE_SMALL.x + 8.0, 0)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cell.add_child(cap)
	return cell

## 文字条目（科技 / 畸变）：分级色小片 + 名称 + 描述。畸变的字形当图标（`CardDB` 的 `icon`）。
static func _text_row(fam: String, id: String) -> Control:
	var meta := CardDB.def(fam, id)
	var cat := String(meta.get("category", ""))
	var col: Color = CardDB.category_color(fam, cat)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(48, 20)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", UIKit.stylebox(
		Color(col.r, col.g, col.b, 0.20), 6, Color(col.r, col.g, col.b, 0.70), 1))
	var cl := UIKit.label(CardDB.category_label(fam, cat), 11, col)
	cl.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(cl)
	head.add_child(chip)
	var glyph := String(meta.get("icon", ""))
	if glyph != "":
		head.add_child(UIKit.label(glyph, 13, col))
	head.add_child(UIKit.label(id, 14, UIKit.TEXT))
	if not bool(meta.get("implemented", true)):
		# 未实装要写出来：图鉴里有、对局里摸不到，不标就是个"看着像 bug"的东西
		head.add_child(UIKit.label("（未实装）", 11, UIKit.TEXT_DIM))
	box.add_child(head)
	var d := UIKit.label(String(meta.get("desc", "")), 12, UIKit.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(PANEL_W - 56.0, 0)
	box.add_child(d)
	return box
