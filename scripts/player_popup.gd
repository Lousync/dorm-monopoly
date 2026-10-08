class_name PlayerPopup
extends Control
## 某个玩家的**道具弹窗**（批次 9，见 doc/development/plans/v0.5.0-批次9-设计.md §4.3）。
##
## 为什么有它：桌上的 3D 立牌（名字/身家/公开背包/倒计时）于批次 9 整体退场 —— 其中
## **公开背包**这一样没有别的落点（四角条只有名字/身家/现金/倒计时）⇒ 收在这里。
## 顺带把"能量（体力）"也收进来（原来在桌上的体力件，批次 7 已删，此后一直只有四角条没有的读数）。
##
## **数据全取已同步的 `st`**（由 game 组装成 `data` 传进来）⇒ 客户端也准；本组件不碰 `hp`。
## **单一来源仍是 game**：这里只负责"长什么样"，`data` 由 `game._open_player_popup` 一处组装。
##
## **层级是两条腿**（终审 fix wave 改准 —— 拾取与绘制是两套，别混为一谈）：
##   * **拾取（= 模态）看树序**：Godot 4 的 GUI 拾取按**子节点倒序**，**不看 `z_index`**
##     （`z_index` 只管绘制）。所以本弹窗挂在 `game` 上，且排在**所有建期屏幕层控件之后**
##     （`table_hud.build_play_ui` 末尾 append + `game._build_ui` 末尾 `move_child(-1)`）——
##     它的压暗底是 `STOP`，靠**树序**挡住暂停按钮 / 战报开关 / 战报栏 / 格详情卡 / 黑市条 /
##     规则说明（原先它挂在 `hud` 上、树序在那几个之前 ⇒ 点击会**穿透**过去，已修）。
##   * **绘制看 `z_index`**：本层 `z_index = 45` —— 高于棋盘 / 四角条 / 动作按钮 / 抽卡大字卡（40），
##     **低于整个模态带**：结算 50 / 弹问 60 / 小卖部·赌场 70 / 暂停菜单 80。
## 两条缺一不可：**只调 z 挡不住点击**（曾把 45 当成模态手段 —— 错），**只挪树序也压不住绘制**。
## **为什么不能盖住弹问面板**：掷轮窗口里开着弹窗 → 超时被系统代掷 → 落在可买格弹询问；
## 若询问被压暗底盖住且点不到，那条链就断了 ⇒ 静默超时放弃。弹问（60）是**运行时懒建**的
## （`_show_prompt` 里才 append 到 `game`）⇒ 树序天然更晚、被优先拾取，模态仍成立。

## 屏幕上弹窗面板的最大宽度（屏幕像素）。**批次 13 ⑤ 放大**：卡面换成大档
##（`ItemCard.SIZE_LARGE` 220×300）之后，一行摆满 5 个槽位 = 5×220 + 4×8 = 1132，
## 加两侧内边距 = **1168**（1280 宽的窗口两侧各余 56）。
## 窗口更窄时 `_fill` 会按可用宽度**收窄**（槽位自动换行，见 `_slots_per_row`）——
## 所以这不是"写死就不管窗口"的那种宽度。
const PANEL_W := 1168.0
## 面板内边距（`_build` 的 `UIKit.margins` 是 18/18/16/16）—— 这里取水平那对，
## 用来把"面板内可用宽度"从面板宽里减出来。
const PANEL_PAD := 18.0
## 背包里每件道具**一整张卡**（批次 12 B2；**批次 13 ⑤ 换大档**）。用 `ItemCard` 按比例排版
## ⇒ 给什么尺寸都成立。描述字号 = `size.y × 0.042`：旧档 168 ⇒ **7px**（用户报"看不清"），
## 大档 300 ⇒ **12px**、名称 21px。
const ITEM_CARD_SIZE := ItemCard.SIZE_LARGE
## 背包槽位一行最多几个（规则上限 5 格正好一行放满；带「置物架」7 格时换第二行）。
const MAX_SLOT_COLS := 5
## 每件道具那一块在卡**之外**还要占的高度：名字一行 + 标签一行 + 两条分隔（`_item_row` 的 VBox）。
## **算高度时必须加上它**：只按卡高算的话 `ScrollContainer` 会矮一截，名字 / 标签那一行被裁掉
##（出图逮到：弹窗里只看得见卡、卡下面那行名字没了）。批次 13 ⑤ 随字号一起从 44 提到 48。
const ITEM_BLOCK_EXTRA := 48.0
## 背包区最大高度：超过就滚动（`ScrollContainer`），免得大背包把面板顶出屏幕。
## 大档卡一行（300+48+6 = 354）放得下；两行（710）就超了、开始滚 —— 带「置物架」的 7 格是这一档。
const BAG_MAX_H := 430.0

var _dim: ColorRect
var _panel: PanelContainer
var _body: VBoxContainer
var _open_peer := GameData.NO_PEER
## 供测试读取的两个可观察量（弹窗"填对了没有"的最强证据）：
var item_count := 0
var stamina_text := ""

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE          # 本层不吃点击，只有压暗底吃
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 45
	visible = false

## 打开某玩家的弹窗。`data` 形如：
## {name, worth, money, stamina, cap, bag_cap, alive, color_idx, items: [{id, cd, charges}]}
## **`cap` 与 `bag_cap` 是两件事、别互相顶替**：前者是**体力上限**（画「能量」那排小格），
## 后者是**背包上限**（决定画几个槽位）。两者会分叉（「充电宝」只抬体力、「置物架」只抬背包），
## 所以各占一个键；混用会让"还能装几张"读错 —— 批次 13 ⑤ 修过一次，见 `_fill` 里那两段注释。
func open(peer: int, data: Dictionary) -> void:
	_open_peer = peer
	_build()
	_fill(data)
	visible = true

func close() -> void:
	_open_peer = GameData.NO_PEER
	visible = false
	if _body != null and is_instance_valid(_body):
		for c in _body.get_children():
			c.queue_free()

func is_open() -> bool:
	return _open_peer != GameData.NO_PEER and visible

## 当前打开的玩家（关闭时 NO_PEER）。状态广播到达时 game 靠它决定要不要重填。
func open_peer() -> int:
	return _open_peer

## 搭骨架（只搭一次；`_fill` 每次重填内容）。
func _build() -> void:
	if _panel != null and is_instance_valid(_panel):
		return
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.03, 0.035, 0.062, 0.62)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP        # 模态：点它 = 关闭
	# **只认左键**（与四角条那边同一写法）：不判按键的话滚轮上/下、右键也会把弹窗关掉。
	_dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	add_child(_dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	# **面板本体有意保持 STOP**（`panel_container` 不设 `mouse_filter` ⇒ Godot 默认 STOP）：
	# 点面板的空白处**不**关闭 —— 关闭只有三条路：压暗底 / ✕ / Esc。别当成漏设去改成 IGNORE。
	_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.9), 1, 10)
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	cc.add_child(_panel)
	var m := UIKit.margins(18, 18, 16, 16)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(m)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(_body)

## 重填内容（幂等：先清空 `_body`）。打开期间来广播时 game 会再调一次。
func _fill(data: Dictionary) -> void:
	for c in _body.get_children():
		c.queue_free()
	var alive := bool(data.get("alive", true))
	# 背包数据与面板宽度先算出来（§六 科技描述要按同一份可用宽度换行；背包区随后复用这几个量）。
	var items: Array = data.get("items", [])
	item_count = items.size()
	# 槽位数 = **背包上限**（基础 5、带「置物架」7）；数据缺失时退回件数，至少 1 格。
	# **必须读 `bag_cap`、不是 `cap`**：`cap` 是**体力上限**（5，带「充电宝」6）——
	# 拿它当槽位数会同时错两头（充电宝多画一格、置物架少画两格），见 `game._open_player_popup` 那段。
	var slots: int = maxi(int(data.get("bag_cap", 0)), maxi(items.size(), 1))
	# 面板宽度按**槽位数与窗口宽度**收窄（窄窗口里 5 列放不下就换行），别硬撑出屏。
	var per_row: int = _slots_per_row(slots)
	var panel_w := float(per_row) * ITEM_CARD_SIZE.x + float(per_row - 1) * 8.0 + PANEL_PAD * 2.0
	_panel.custom_minimum_size = Vector2(panel_w, 0)
	# 标题行：棋子色小片 + 名字 + 名次徽章 + 关闭
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(head)
	var chip_slot := Control.new()
	chip_slot.custom_minimum_size = Vector2(18, 18)
	chip_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_slot.add_child(UIKit.chip(
		GameData.PLAYER_COLORS[clampi(int(data.get("color_idx", 0)), 0, 3)], 18))
	head.add_child(chip_slot)
	var nm := UIKit.label(String(data.get("name", "?")), 22, UIKit.TEXT)
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(nm)
	var rank := int(data.get("rank", 0))
	var badge_slot := Control.new()
	badge_slot.custom_minimum_size = Vector2(24, 24)
	badge_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rank > 0:
		badge_slot.add_child(UIKit.rank_badge(rank, 24))
	head.add_child(badge_slot)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var x := UIKit.button("✕", 14)
	x.custom_minimum_size = Vector2(32, 26)
	x.tooltip_text = "关闭"
	x.pressed.connect(close)
	head.add_child(x)
	# 身家（大字）+ 现金（小字）
	_body.add_child(UIKit.label("已出局" if not alive else GameData.fmt_money(int(data.get("worth", 0))),
		26, UIKit.ACCENT if alive else UIKit.TEXT_DIM))
	if alive:
		_body.add_child(UIKit.label("现金 %s" % GameData.fmt_money(int(data.get("money", 0))),
			14, UIKit.TEXT_DIM))
	# 能量（体力）：读数 + 一排点亮/熄灭的小格。
	# 两个色值取自**已随批次 7 退场的桌上体力件**（亮金 / 熄灭），不引用 `TableProps.PIP_*`
	#（那两件已删，引用会直接编译不过）。
	# `cap` = **体力上限**（不是背包上限）：小格数 = 上限、亮格数 = 当前值。别拿 `bag_cap` 顶它。
	var cap := maxi(int(data.get("cap", 0)), 0)
	var cur := clampi(int(data.get("stamina", 0)), 0, maxi(cap, 0))
	stamina_text = str(cur)
	var e_row := HBoxContainer.new()
	e_row.add_theme_constant_override("separation", 6)
	e_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(e_row)
	e_row.add_child(UIKit.label("能量 %s" % stamina_text, 15, UIKit.TEXT))
	for i in cap:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(16, 16)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_theme_stylebox_override("panel", UIKit.stylebox(
			Color(0.95, 0.78, 0.35) if i < cur else Color(0.22, 0.20, 0.18),
			4, Color(0, 0, 0, 0.4), 1))
		e_row.add_child(pip)
	# 已选科技（§六）：**仅存活且确实选了科技**时显示 —— 名字一行 + 其下小字描述。
	# 空串（未开科技 / 未选 / 已出局）则整段不显示。
	var tech := String(data.get("tech", ""))
	if alive and tech != "":
		_body.add_child(UIKit.label("科技：%s" % tech, 15, UIKit.TEXT))
		var tdesc := String(TechData.def(tech).get("desc", ""))
		if tdesc != "":
			var tl := UIKit.label(tdesc, 12, UIKit.TEXT_DIM)
			tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tl.custom_minimum_size = Vector2(panel_w - PANEL_PAD * 2.0, 0)
			tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_body.add_child(tl)
	# 卡牌列表（批次 12 B2：一行一件的"小图标 + 名字"改成**一整张 `ItemCard`**；
	# **批次 13 ⑤：按规则上限画固定槽位** —— 已拥有的是整张卡，未拥有的是**细边框占位框**
	#（**不是虚线**：Compatibility 渲染器没有虚线画笔，见 `_empty_slot`），
	# 让玩家一眼看出"最多只能同时拥有 5 张"）。
	# 换行排布（`FlowContainer`）+ 超高滚动（`ScrollContainer`）—— 大背包不会把面板顶出屏幕。
	# 弹窗本来就是 Control 树 ⇒ 直接挂真节点即可，**与商店货架同一份画法**，没有任何烘焙。
	# （`items` / `slots` / `per_row` / `panel_w` 已在 `_fill` 顶部算好。）
	_body.add_child(UIKit.label("背包 %d / %d 格" % [item_count, slots], 14, UIKit.TEXT_DIM))
	var sc := ScrollContainer.new()
	sc.name = "BagScroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED   # 关横向 ⇒ 子节点按容器宽度换行
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 高度取"装得下的自然高度"与上限的较小者（`_bag_needed_h`）—— 行数少时不留一大片空白，
	# 行数多时封顶、由 `ScrollContainer` 接管。
	sc.custom_minimum_size = Vector2(panel_w - PANEL_PAD * 2.0, _bag_needed_h(slots, per_row))
	_body.add_child(sc)
	var flow := FlowContainer.new()
	flow.name = "BagFlow"
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(flow)
	for i in slots:
		if i < items.size():
			flow.add_child(_item_row(items[i] as Dictionary))
		else:
			flow.add_child(_empty_slot())

## 一行放得下几个槽位：按**可用宽度**推（不写死 5），窗口窄时自动换行。
## 可用宽度 = 视口宽 − 两侧各 40 的余量 − 面板内边距。1280 宽、内边距 36 ⇒ n = 5。
func _slots_per_row(slots: int) -> int:
	# 首帧 `size` 可能还是 0（布局未跑）⇒ 退回视口宽度，免得误判成"窄窗口"、只摆 1 列。
	var vw: float = size.x
	if vw <= 1.0:
		vw = get_viewport_rect().size.x
	var avail: float = maxf(vw, 1.0) - 80.0 - PANEL_PAD * 2.0
	var n: int = int((avail + 8.0) / (ITEM_CARD_SIZE.x + 8.0))
	return clampi(n, 1, maxi(1, mini(slots, MAX_SLOT_COLS)))

## 空槽：与整张卡同尺寸的占位框。Compatibility 下没有虚线画笔，用**细边框 + 极低对比底**
## 代替 —— 与"有卡"一眼分得开即可（用户 ⑤ 要的是"看得出最多只能同时拥有 5 张"）。
func _empty_slot() -> Control:
	var box := Panel.new()
	box.custom_minimum_size = ITEM_CARD_SIZE
	box.size = ITEM_CARD_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", UIKit.stylebox(
		Color(1, 1, 1, 0.03), 12,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.32), 1))
	var l := UIKit.label("空槽", 14, UIKit.TEXT_DIM)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return box

## 背包区需要多高（= 按**槽位数**与每行格数算出的行数，封顶 `BAG_MAX_H`）。
## `per_row` 由 `_slots_per_row` 按可用宽度给出（窄窗口里会换行 ⇒ 行数变多）。
func _bag_needed_h(slots: int, per_row: int) -> float:
	var rows: int = maxi(ceili(float(slots) / float(maxi(per_row, 1))), 1)
	return minf(float(rows) * (ITEM_CARD_SIZE.y + ITEM_BLOCK_EXTRA) + float(rows - 1) * 8.0 + 6.0,
		BAG_MAX_H)

## 一件道具一整块：**一张 `ItemCard`**（与商店货架同一画法）+ 名字 + 状态标签（被动 / 冷却 N / 未实装）。
## 名字与标签挂在卡**下面**（卡面自带名称条，但近处再写一行大字更好认；标签卡面上没有）。
func _item_row(it: Dictionary) -> Control:
	var iid := String(it.get("id", ""))
	var d := ItemData.def(iid)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ItemCard.make(iid, ITEM_CARD_SIZE, ItemData.badge_state(it)))
	var name_l := UIKit.label(iid, 15, UIKit.TEXT)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.custom_minimum_size = Vector2(ITEM_CARD_SIZE.x, 0)
	name_l.clip_text = true
	box.add_child(name_l)
	var tags: Array = []
	if String(d.get("type", "")) == "passive":
		tags.append("被动")
	var cd := int(it.get("cd", 0))
	if cd > 0:
		tags.append("冷却 %d" % cd)
	if not bool(d.get("implemented", false)):
		tags.append("未实装")
	if not tags.is_empty():
		var t := UIKit.label("（%s）" % " · ".join(tags), 12, UIKit.TEXT_DIM)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.custom_minimum_size = Vector2(ITEM_CARD_SIZE.x, 0)
		t.clip_text = true
		box.add_child(t)
	return box
