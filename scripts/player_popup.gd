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

## 屏幕上弹窗面板的最大宽度（内容超出时内部滚动/换行；今天最多 7 件，够用）。
const PANEL_W := 460.0

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
## {name, worth, money, stamina, cap, alive, color_idx, items: [{id, cd, charges}]}
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
	var nm := UIKit.label(String(data.get("name", "?")), 18, UIKit.TEXT)
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
		20, UIKit.ACCENT if alive else UIKit.TEXT_DIM))
	if alive:
		_body.add_child(UIKit.label("现金 %s" % GameData.fmt_money(int(data.get("money", 0))),
			12, UIKit.TEXT_DIM))
	# 能量（体力）：读数 + 一排点亮/熄灭的小格。
	# 两个色值取自**已随批次 7 退场的桌上体力件**（亮金 / 熄灭），不引用 `TableProps.PIP_*`
	#（那两件已删，引用会直接编译不过）。
	var cap := maxi(int(data.get("cap", 0)), 0)
	var cur := clampi(int(data.get("stamina", 0)), 0, maxi(cap, 0))
	stamina_text = str(cur)
	var e_row := HBoxContainer.new()
	e_row.add_theme_constant_override("separation", 6)
	e_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(e_row)
	e_row.add_child(UIKit.label("能量 %s" % stamina_text, 13, UIKit.TEXT))
	for i in cap:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(14, 14)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_theme_stylebox_override("panel", UIKit.stylebox(
			Color(0.95, 0.78, 0.35) if i < cur else Color(0.22, 0.20, 0.18),
			4, Color(0, 0, 0, 0.4), 1))
		e_row.add_child(pip)
	# 卡牌列表：图标 + 品质色边框 + 名称 + 冷却 / 被动 / 未实装
	var items: Array = data.get("items", [])
	item_count = items.size()
	_body.add_child(UIKit.label("背包 %d 件" % item_count, 13, UIKit.TEXT_DIM))
	if items.is_empty():
		_body.add_child(UIKit.label("背包是空的", 13, UIKit.TEXT_DIM))
	for it in items:
		_body.add_child(_item_row(it as Dictionary))

## 一件道具一行：图标（有素材才贴）+ 名称 + 后缀（冷却 / 被动 / 未实装，可叠加）。
func _item_row(it: Dictionary) -> Control:
	var iid := String(it.get("id", ""))
	var d := ItemData.def(iid)
	var q := String(d.get("quality", "白"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(30, 30)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_stylebox_override("panel", UIKit.stylebox(
		ItemData.QUALITY_COLORS.get(q, Color.WHITE), 6, Color(0, 0, 0, 0.4), 1))
	row.add_child(holder)
	var ic := _item_icon(String(d.get("icon", "")))
	if ic != null:
		var tr := TextureRect.new()
		tr.texture = ic
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
	var name_l := UIKit.label(iid, 14, UIKit.TEXT)
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_l)
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
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(t)
	return row

## 道具图标（与手牌同一套素材；缺素材返回 null，只留品质色块）
func _item_icon(icon: String) -> Texture2D:
	if icon == "":
		return null
	var path := "res://assets/icons/%s.png" % icon
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
