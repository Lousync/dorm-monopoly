class_name CodexPanel
extends RefCounted
## 对局内的「📖 图鉴」：右上角一枚**开关按钮**（与「规则说明」「战报」同一条 y）+ 它打开的
## **屏幕中央大尺寸模态弹窗**。
##
## **落点史**：2026-10-11 初版是"按钮下方展开的小面板"（430×472，落点与规则面板逐字相同）；
## **2026-10-12 用户改成"屏幕中央的大尺寸弹窗"** —— 图鉴是**摊开来看**的东西（道具页要摆一排
## 真卡），挤在右上角一角既看不全、又和「规则说明」「战报」抢同一块地方。
##
## **内容 = `CardDB` 已归一化的三族**（道具 / 科技 / 畸变），与
## `doc/game-design/图鉴.html` **同源** —— 那张网页由 `tools/gen_gallery.gd` 从同一批数据表
## 生成，是**给团队查的**；这一份是**对局里给玩家查的**。事件族暂不纳入（`CardDB.FAMILIES`
## 的现状，与网页一致）。
##
## 与 `RulesPanel` 同约定：控件直接写回宿主（game.gd）的同名成员，而不是返回局部变量。
##
## **模态是两条腿**（与 `scripts/player_popup.gd` 逐条同款，别只做一半）：
##   * **拾取看树序**（Godot 的 GUI 拾取按子节点倒序，**不看 `z_index`**）：`CodexPanel.build`
##     在 `game._build_ui` 里排在 `TableHud.build_play_ui` 与 `RulesPanel.build` **之后** ⇒
##     压暗底挡得住那些建期控件；**运行时懒建**的结算(50) / 弹问(60)，以及显示时
##     `move_child(-1)` 的小卖部·赌场 / 暂停菜单(80) 天然更晚，仍压在它之上。
##   * **绘制看 `z_index = 45`**：高于棋盘 / 四角条 / 动作按钮 / 抽卡大字卡（40），
##     低于整个模态带（结算 50 / 弹问 60 / 小卖部·赌场 70 / 暂停 80）。
## 两条缺一不可：只调 z 挡不住点击，只挪树序压不住绘制。
## **与「规则说明」「战报」仍互斥** —— 压着压暗底时那两个面板透出来会很难看（`game._set_codex_open`）。
##
## **为什么不做成 `--card-gallery` 那种"卡片模板预览"**：那个（现在住在 `dev_tools.gd`）
## 陈列的是**三种尺寸 × 各种状态**的模板，用来核对卡面规格；玩家要查的是"有哪些道具、
## 各是什么效果" ⇒ 这里按**族**分页、按**条目**陈列。

## 弹窗尺寸（画布像素；项目画布是 1280×800）。**"大尺寸"= 按画布收窄留边**：1280×800 下取
## 1120×660（左右各余 80、上下各余 70）。上限按画布算而不是写死 ⇒ 窗口/画布更小时不会顶出去。
const PANEL_W_MAX := 1120.0
const PANEL_H_MAX := 660.0
const SCREEN_PAD_X := 128.0    # 两侧合计留白
const SCREEN_PAD_Y := 128.0
## 面板内边距（`UIKit.margins` 的水平那对）—— 算"内容可用宽度"时要从面板宽里减掉。
const PANEL_PAD := 18.0
const BTN_W := 96.0
## 本按钮排在「规则说明」按钮**左边 12px**（那枚占 `RULES_LEFT..-118`，见 `rules_panel.gd`）。
const RULES_LEFT := -250.0

## 一族一页（族键直接用 `CardDB` 的族名，`CardDB.ids(family)` 就是条目清单）。
const TABS := ["item", "tech", "aberration"]
const TAB_TITLES := {"item": "道具", "tech": "科技", "aberration": "畸变"}

## 清单四周的留白（**左 / 上 / 右 / 下**）—— **量出来的**：`ItemCard.badge_overhang` 就是
## "角标最多探出卡面多少"。与背包弹窗同一个坑：`ScrollContainer` 会把子节点裁在可视矩形内，
## 而真卡的角标是**半出卡外**画的 ⇒ 不留白就切掉第一行 / 第一列的角标（2026-10-12 一并修）。
static func grid_pad() -> Vector4:
	return ItemCard.badge_overhang(ItemCard.SIZE_SMALL)

## 清单可用宽度（= 面板宽 − 面板内边距 − 网格留白）：科技 / 畸变页的长描述按它换行。
## 读**声明出来的** `custom_minimum_size`，不读 `size` —— 首帧布局还没跑，`size` 会是 0。
static func content_w(g: Node) -> float:
	var gp := grid_pad()
	return g.codex_panel.custom_minimum_size.x - PANEL_PAD * 2.0 - gp.x - gp.z

static func build(g: Node) -> void:
	_build_button(g)
	_build_modal(g)
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

## 打开态：**屏幕中央的大尺寸模态**（压暗底 + 居中面板）—— 照 `PlayerPopup` / 大厅设置弹窗的范式。
## 显隐切的是**模态包装** `g.codex_modal`（见 `game._set_codex_open`），面板本体只是它的孩子。
static func _build_modal(g: Node) -> void:
	g.codex_modal = Control.new()
	g.codex_modal.name = "CodexModal"
	g.codex_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.codex_modal.mouse_filter = Control.MOUSE_FILTER_IGNORE    # 本层不吃点击，只有压暗底吃
	g.codex_modal.z_index = 45
	g.codex_modal.visible = false
	g.add_child(g.codex_modal)

	g.codex_dim = ColorRect.new()
	g.codex_dim.name = "CodexDim"
	g.codex_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.codex_dim.color = Color(0.03, 0.035, 0.062, 0.62)
	g.codex_dim.mouse_filter = Control.MOUSE_FILTER_STOP        # 模态：点它 = 关闭
	# **只认左键**（与四角条 / 道具弹窗同一写法）：不判按键的话滚轮上/下、右键也会把弹窗关掉。
	g.codex_dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			g._set_codex_open(false))
	g.codex_modal.add_child(g.codex_dim)

	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.codex_modal.add_child(cc)

	# **面板本体有意保持 STOP**（`panel_container` 不设 `mouse_filter` ⇒ Godot 默认 STOP）：
	# 点面板的空白处**不**关闭 —— 关闭四条路：✕ / 压暗底 / Esc / 再点那枚「📖 图鉴」。
	g.codex_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.9), 1, 10)
	var vp: Vector2 = g.get_viewport_rect().size
	g.codex_panel.custom_minimum_size = Vector2(
		minf(PANEL_W_MAX, maxf(vp.x - SCREEN_PAD_X, 480.0)),
		minf(PANEL_H_MAX, maxf(vp.y - SCREEN_PAD_Y, 360.0)))
	cc.add_child(g.codex_panel)

	var m := UIKit.margins(int(PANEL_PAD), int(PANEL_PAD), 14, 14)
	g.codex_panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	m.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	head.add_child(UIKit.label("图鉴", 18, UIKit.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	var close_btn := UIKit.button("✕", 14)
	close_btn.name = "CodexClose"
	close_btn.custom_minimum_size = Vector2(34, 28)
	close_btn.tooltip_text = "关闭（Esc，或点弹窗外面）"
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
	scroll.name = "CodexScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	# 清单外面套一圈留白（`CodexPad`）：理由见 `grid_pad()`。
	# ⚠ `SIZE_EXPAND_FILL` **必须有** —— `ScrollContainer` 只把带 EXPAND 的**直接子节点**拉到
	# 自己的宽度。背包那边少写这个标志，网格当场被挤成一列（见 `player_popup._fill` 同一段注释）。
	var gpad := MarginContainer.new()
	gpad.name = "CodexPad"
	var gp := grid_pad()
	var gp_sides := ["left", "top", "right", "bottom"]   # 与 `badge_overhang()` 的 (左, 上, 右, 下) 同序
	for pi in 4:
		gpad.add_theme_constant_override("margin_" + gp_sides[pi], int(ceilf(gp[pi])))
	gpad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gpad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(gpad)
	g.codex_list = VBoxContainer.new()
	g.codex_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.codex_list.add_theme_constant_override("separation", 10)
	gpad.add_child(g.codex_list)

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
	var cw := content_w(g)
	var q := ""
	if g.codex_search != null and is_instance_valid(g.codex_search):
		q = String(g.codex_search.text).strip_edges().to_lower()
	var n := 0
	if fam == CardDB.FAMILY_ITEM:
		# 道具：摆真卡（`ItemCard.SIZE_SMALL`，与道具栏同尺寸）——"长什么样"本身就是图鉴的一半。
		# **不声明网格宽度**（与背包弹窗不同）：这里是"有多少摆多少"的陈列页，列数随面板宽度自动排，
		# 只有"最后那一列的角标别被裁"要靠 `CodexPad` 的右侧留白兜住。
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
			g.codex_list.add_child(_text_row(fam, String(id), cw))
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
## `cw` = 清单可用宽度（长描述按它换行 —— 弹窗尺寸变了它才跟着变，别写死）。
static func _text_row(fam: String, id: String, cw: float) -> Control:
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
	d.custom_minimum_size = Vector2(maxf(cw, 200.0), 0)
	box.add_child(d)
	return box
