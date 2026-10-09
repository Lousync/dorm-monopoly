extends Control
## 道具试验场（Item Lab）：独立沙盒，逐个验证道具效果。
## 复用 game.tscn 的真实房主逻辑（lab_mode：建局但不跑回合循环），在其上叠一层工作台 UI。
## 入口：启动参数 --lab，或 dev 开关下主菜单的「道具试验场」按钮。见 docs/dev/道具试验场.md。
##
## 单机本地权威：本机即房主，不联机。

var g                       # 内嵌的 game.tscn 实例

var sel_item := ""
var actor_i := 0            # 当前操作对象（hp 下标）
var target_i := -1          # 目标玩家（需要选玩家的道具）
var target_tile := -1       # 目标格（需要选地块的道具）
var qfilter := "全部"
var free_energy := false    # 「不耗能量」：立即使用不扣体力
var no_cooldown := false    # 「关冷却」：立即使用忽略冷却、使用后不进冷却
var snap: Dictionary = {}
var _panels: Array = []     # 可隐藏的面板（左/右/底）
var _hud_hidden := false
var _p_left: PanelContainer
var _p_right: PanelContainer
var _p_bottom: PanelContainer
var _grip_left: ColorRect
var _grip_right: ColorRect
var _grip_bottom: ColorRect
var _drag_kind := ""
var _drag_orig := 0.0
var _pm0 := Vector2.ZERO

var _players_box: VBoxContainer
var _q_box: HBoxContainer
var _list_box: VBoxContainer
var _desc_l: Label
var _ctx_l: Label
var _hint_l: Label
var _log_box: VBoxContainer
var _diff_box: VBoxContainer
var _param_edit: LineEdit
var _case_edit: LineEdit
var _tile_l: Label

func _ready() -> void:
	# 本机权威
	Net.my_name = "房主"
	Net.host_game(7795)
	Net.players = [
		{"peer": 1, "name": "房主", "color": 0, "bot": false, "ready": true},
		{"peer": -1, "name": "机器人A", "color": 1, "bot": true, "ready": true},
		{"peer": -2, "name": "机器人B", "color": 2, "bot": true, "ready": true},
		{"peer": -3, "name": "机器人C", "color": 3, "bot": true, "ready": true},
	]
	# 内嵌对局场景（真实逻辑）
	g = load("res://scenes/game.tscn").instantiate()
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(g)
	g.enter_lab_mode()
	g.lab_reset()
	# 只保留棋盘：隐藏游戏自带的全部 HUD（F1 面板、规则按钮、行动条、结算页…）
	for c in g.get_children():
		if c != g.board and c is CanvasItem:
			(c as CanvasItem).visible = false
	if g.board != null:
		g.board.tile_clicked.connect(_on_lab_tile)
	_build_ui()
	_snap()
	render()
	_log("试验场就绪：4 名玩家、真实玩法逻辑、回合循环已停")
	# `--lab-case=名字`：直达回放（main_menu 已把它当 `--lab` 的入口；这里读出名字并载入）。
	var cn := _case_arg()
	if cn != "":
		_load_case(cn)

# ================= UI =================

## 可滚动面板（左/右栏）：内容超出高度时不遮别的东西，直接滚
func _panel(title: String) -> PanelContainer:
	var pc := UIKit.panel_container(Color(0.05, 0.06, 0.1, 0.96), 10, Color(0.4, 0.75, 0.6, 0.5), 1)
	add_child(pc)
	_panels.append(pc)
	var m := UIKit.margins(10, 10, 8, 8)
	pc.add_child(m)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 5)
	sc.add_child(v)
	if title != "":
		v.add_child(UIKit.label(title, 13, Color(0.55, 0.9, 0.65)))
	return pc

func _body(pc: PanelContainer) -> VBoxContainer:
	return pc.get_child(0).get_child(0).get_child(0) as VBoxContainer

## 不套滚动层的面板（顶栏；底栏自带 log/diff 滚动）
func _panel_plain(title: String) -> PanelContainer:
	var pc := UIKit.panel_container(Color(0.05, 0.06, 0.1, 0.96), 10, Color(0.4, 0.75, 0.6, 0.5), 1)
	add_child(pc)
	var m := UIKit.margins(10, 10, 8, 8)
	pc.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	m.add_child(v)
	if title != "":
		v.add_child(UIKit.label(title, 13, Color(0.55, 0.9, 0.65)))
	return pc

func _body_plain(pc: PanelContainer) -> VBoxContainer:
	return pc.get_child(0).get_child(0) as VBoxContainer

## 把面板锚到视口边缘（随窗口缩放）
func _anchors(pc: Control, al: float, at: float, ar: float, ab: float,
		ol: float, ot: float, orr: float, ob: float) -> void:
	pc.anchor_left = al; pc.anchor_top = at; pc.anchor_right = ar; pc.anchor_bottom = ab
	pc.offset_left = ol; pc.offset_top = ot; pc.offset_right = orr; pc.offset_bottom = ob

func _build_ui() -> void:
	# 顶栏
	var top := _panel_plain("")
	_anchors(top, 0, 0, 1, 0, 8, 8, -8, 52)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 8)
	_body_plain(top).add_child(trow)
	trow.add_child(UIKit.label("🧪 道具试验场", 16, UIKit.ACCENT))
	_ctx_l = UIKit.label("", 12, UIKit.TEXT_DIM)
	trow.add_child(_ctx_l)
	trow.add_child(_spacer())
	for b in [["⟲ 重置", _reset], ["⧉ 快照", _do_snap], ["↩ 回滚", _rollback], ["复制状态 JSON", _copy_state]]:
		var btn := UIKit.button(String(b[0]), 12)
		btn.pressed.connect(b[1])
		trow.add_child(btn)
	var hide_btn := UIKit.button("👁 隐藏面板", 12)
	hide_btn.pressed.connect(_toggle_panels)
	trow.add_child(hide_btn)
	# 用例保存 / 回放（§九 D / ⑭）：存 = 可复现状态写 `user://lab_cases/<名>.json`；
	# 读 = 清空后按 JSON 逐项注入（`LabCase`）。名字留空回落 `case`。启动参数 `--lab-case=名` 直达。
	_case_edit = LineEdit.new()
	_case_edit.text = "case1"
	_case_edit.custom_minimum_size = Vector2(120, 0)
	_case_edit.tooltip_text = "用例名（存 / 读共用）"
	trow.add_child(_case_edit)
	var save_case_btn := UIKit.button("💾 存用例", 12)
	save_case_btn.pressed.connect(_save_case)
	trow.add_child(save_case_btn)
	var load_case_btn := UIKit.button("📂 读用例", 12)
	load_case_btn.pressed.connect(func() -> void: _load_case(_case_edit.text))
	trow.add_child(load_case_btn)
	# 左：玩家（整栏可滚动）
	var left := _panel("玩家（点选 = 操作对象）")
	_p_left = left
	_anchors(left, 0, 0, 0, 1, 8, 54, 240, -212)
	_players_box = VBoxContainer.new()
	_players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players_box.add_theme_constant_override("separation", 4)
	_body(left).add_child(_players_box)
	# 右：工坊（整栏可滚动）
	var right := _panel("道具工坊")
	_p_right = right
	_anchors(right, 1, 0, 1, 1, -350, 54, -8, -212)
	var rb := _body(right)
	_q_box = HBoxContainer.new()
	_q_box.add_theme_constant_override("separation", 3)
	rb.add_child(_q_box)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 3)
	rb.add_child(_list_box)
	_desc_l = UIKit.label("", 11, UIKit.TEXT_DIM)
	_desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_l.custom_minimum_size = Vector2(0, 40)
	rb.add_child(_desc_l)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 4)
	rb.add_child(prow)
	prow.add_child(UIKit.label("参数(点数/目标)", 11, UIKit.TEXT_DIM))
	_param_edit = LineEdit.new()
	_param_edit.custom_minimum_size = Vector2(80, 0)
	prow.add_child(_param_edit)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 4)
	rb.add_child(arow)
	var grant_btn := UIKit.button("授予", 12)
	grant_btn.pressed.connect(_grant)
	arow.add_child(grant_btn)
	var use_btn := UIKit.button("立即使用", 12, "primary")
	use_btn.pressed.connect(func() -> void: _use(true))
	arow.add_child(use_btn)
	var trig_btn := UIKit.button("仅触发", 12)
	trig_btn.pressed.connect(func() -> void: _use(false))
	arow.add_child(trig_btn)
	var trow2 := HBoxContainer.new()
	trow2.add_theme_constant_override("separation", 4)
	rb.add_child(trow2)
	var turn_btn := UIKit.button("回合开始(被动)", 11)
	turn_btn.pressed.connect(_turn_start)
	trow2.add_child(turn_btn)
	var free_chk := CheckBox.new()
	free_chk.text = "不耗能量"
	free_chk.button_pressed = free_energy
	free_chk.toggled.connect(func(v: bool) -> void: free_energy = v)
	trow2.add_child(free_chk)
	var cd_chk := CheckBox.new()
	cd_chk.text = "关冷却"
	cd_chk.button_pressed = no_cooldown
	cd_chk.toggled.connect(func(v: bool) -> void: no_cooldown = v)
	trow2.add_child(cd_chk)
	# 地块注入
	_tile_l = UIKit.label("目标格：无（点棋盘选格）", 11, UIKit.TEXT_DIM)
	rb.add_child(_tile_l)
	var trow3 := HBoxContainer.new()
	trow3.add_theme_constant_override("separation", 4)
	rb.add_child(trow3)
	for e in [["设为地主", "own"], ["设无主", "none"], ["升级", "up"], ["降级", "down"], ["焦土", "soil"]]:
		var b := UIKit.button(String(e[0]), 11)
		var k: String = String(e[1])
		b.pressed.connect(func() -> void: _tile_edit(k))
		trow3.add_child(b)
	# 底：日志 + diff
	var bot := _panel_plain("")
	_p_bottom = bot
	_anchors(bot, 0, 1, 1, 1, 8, -204, -8, -8)
	_panels.append(bot)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 12)
	bh.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_plain(bot).add_child(bh)
	var lcol := VBoxContainer.new()
	lcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(lcol)
	lcol.add_child(UIKit.label("日志", 12, UIKit.TEXT_DIM))
	var log_scroll := ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lcol.add_child(log_scroll)
	_log_box = VBoxContainer.new()
	_log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(_log_box)
	var dcol := VBoxContainer.new()
	dcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(dcol)
	dcol.add_child(UIKit.label("效果前后 diff", 12, UIKit.TEXT_DIM))
	var dscroll := ScrollContainer.new()
	dscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dcol.add_child(dscroll)
	_diff_box = VBoxContainer.new()
	_diff_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dscroll.add_child(_diff_box)
	# 面板分隔条：拖动收放
	_grip_left = _mk_grip(true)
	_grip_right = _mk_grip(true)
	_grip_bottom = _mk_grip(false)
	_grip_left.gui_input.connect(_on_grip.bind("left"))
	_grip_right.gui_input.connect(_on_grip.bind("right"))
	_grip_bottom.gui_input.connect(_on_grip.bind("bottom"))
	_place_grips()

func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

## 一键隐藏左/右/底面板，方便看完整棋盘（顶栏保留以便再唤出）
func _toggle_panels() -> void:
	_hud_hidden = not _hud_hidden
	for pc in _panels:
		if is_instance_valid(pc):
			pc.visible = not _hud_hidden

## 分隔条
func _mk_grip(horizontal: bool) -> ColorRect:
	var g := ColorRect.new()
	g.color = Color(0.55, 0.9, 0.65, 0.22)
	g.mouse_filter = Control.MOUSE_FILTER_STOP
	g.mouse_default_cursor_shape = Control.CURSOR_HSIZE if horizontal else Control.CURSOR_VSIZE
	add_child(g)
	_panels.append(g)   # 隐藏面板时一并隐藏
	return g

func _on_grip(ev: InputEvent, kind: String) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
			and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag_kind = kind
		_pm0 = get_viewport().get_mouse_position()
		match kind:
			"left": _drag_orig = _p_left.offset_right
			"right": _drag_orig = _p_right.offset_left
			"bottom": _drag_orig = _p_bottom.offset_top

func _place_grips() -> void:
	if _grip_left == null:
		return
	var lx := _p_left.offset_right
	_grip_left.anchor_left = 0; _grip_left.anchor_right = 0
	_grip_left.anchor_top = 0; _grip_left.anchor_bottom = 1
	_grip_left.offset_left = lx - 3; _grip_left.offset_right = lx + 3
	_grip_left.offset_top = 54; _grip_left.offset_bottom = -212
	var rx := _p_right.offset_left
	_grip_right.anchor_left = 1; _grip_right.anchor_right = 1
	_grip_right.anchor_top = 0; _grip_right.anchor_bottom = 1
	_grip_right.offset_left = rx - 3; _grip_right.offset_right = rx + 3
	_grip_right.offset_top = 54; _grip_right.offset_bottom = -212
	var by := _p_bottom.offset_top
	_grip_bottom.anchor_left = 0; _grip_bottom.anchor_right = 1
	_grip_bottom.anchor_top = 1; _grip_bottom.anchor_bottom = 1
	_grip_bottom.offset_left = 8; _grip_bottom.offset_right = -8
	_grip_bottom.offset_top = by - 3; _grip_bottom.offset_bottom = by + 3

func _input(event: InputEvent) -> void:
	if _drag_kind == "":
		return
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag_kind = ""
		return
	if event is InputEventMouseMotion:
		var mp := get_viewport().get_mouse_position()
		match _drag_kind:
			"left": _p_left.offset_right = clampf(_drag_orig + (mp.x - _pm0.x), 170, 520)
			"right": _p_right.offset_left = clampf(_drag_orig + (mp.x - _pm0.x), -520, -170)
			"bottom": _p_bottom.offset_top = clampf(_drag_orig + (mp.y - _pm0.y), -460, -120)
		_place_grips()

# ================= 渲染 =================

func _actor() -> Dictionary:
	if g.hp.is_empty():
		return {}
	actor_i = clampi(actor_i, 0, g.hp.size() - 1)
	return g.hp[actor_i]

func render() -> void:
	_render_players()
	_render_quality()
	_render_list()
	_update_hint()
	if _ctx_l != null:
		var an := String(g.hp[actor_i].get("name", "?")) if not g.hp.is_empty() else "-"
		var tn := "—"
		if target_i >= 0 and target_i < g.hp.size():
			tn = String(g.hp[target_i].get("name", "?"))
		_ctx_l.text = "　操作对象：%s　目标：%s　选中：%s" % [an, tn, ("—" if sel_item == "" else sel_item)]

func _render_players() -> void:
	for c in _players_box.get_children():
		c.queue_free()
	for i in g.hp.size():
		var p: Dictionary = g.hp[i]
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UIKit.stylebox(
			UIKit.ACCENT if i == actor_i else Color(0.1, 0.11, 0.16, 0.9), 8,
			Color(0.4, 0.7, 0.55, 0.9) if i == target_i else Color(0, 0, 0, 0), 1))
		_players_box.add_child(row)
		var m := UIKit.margins(8, 8, 4, 4)
		row.add_child(m)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		m.add_child(v)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		v.add_child(head)
		head.add_child(UIKit.chip(GameData.PLAYER_COLORS[int(p.get("color", 0)) % 4], 12))
		head.add_child(UIKit.label("%s%s" % [String(p.get("name", "?")),
			" ▶" if i == actor_i else (" 🎯" if i == target_i else "")], 12, UIKit.TEXT))
		var its := []
		for it in p.get("items", []):
			its.append(String(it.id))
		v.add_child(UIKit.label("¥%s · ⚡%d · 格%d" % [GameData.fmt_money(int(p.get("money", 0))),
			int(p.get("stamina", 0)), int(p.get("pos", 0))], 11, UIKit.ACCENT))
		v.add_child(UIKit.label("背包：" + ("空" if its.is_empty() else "、".join(its)), 10, UIKit.TEXT_DIM))
		# 明确分开：操作对象 / 目标（点卡片不再自动切目标）
		var r1 := HBoxContainer.new()
		r1.add_theme_constant_override("separation", 4)
		v.add_child(r1)
		var bop := UIKit.button("▶ 操作对象", 10, "primary" if i == actor_i else "normal")
		bop.pressed.connect(func() -> void:
			actor_i = i
			render())
		r1.add_child(bop)
		var btg := UIKit.button("🎯 设为目标", 10, "primary" if i == target_i else "normal")
		btg.pressed.connect(func() -> void:
			target_i = i
			render())
		r1.add_child(btg)
		var r2 := HBoxContainer.new()
		r2.add_theme_constant_override("separation", 4)
		v.add_child(r2)
		for e in [["+1千", 1000], ["+1万", 10000], ["-1千", -1000]]:
			var b := UIKit.button(String(e[0]), 10)
			var amt: int = int(e[1])
			b.pressed.connect(func() -> void:
				actor_i = i
				g.hp[i].money = int(g.hp[i].money) + amt
				_broadcast()
				render())
			r2.add_child(b)

func _render_quality() -> void:
	for c in _q_box.get_children():
		c.queue_free()
	for q in ["全部"] + ItemData.QUALITIES:   # 档位从 `ItemData.QUALITIES` 派生：改档位只动数据表（Ruling BL/BM）
		var b := UIKit.button(q, 11)
		if q == qfilter:
			UIKit.restyle_button(b, "primary")
		var qq: String = q
		b.pressed.connect(func() -> void:
			qfilter = qq
			_render_quality()
			_render_list())
		_q_box.add_child(b)

func _render_list() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	for id in ItemData.ITEMS:
		var d: Dictionary = ItemData.ITEMS[id]
		if qfilter != "全部" and String(d.get("quality", "")) != qfilter:
			continue
		var impl := bool(d.get("implemented", false))
		var b := UIKit.button("%s%s" % [String(id), "" if impl else "（未实装）"], 11)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not impl
		var iid := String(id)
		b.pressed.connect(func() -> void: select_item(iid))
		if iid == sel_item:
			UIKit.restyle_button(b, "primary")
		_list_box.add_child(b)

func select_item(id: String) -> void:
	sel_item = id
	target_i = -1
	_update_hint()
	_render_list()

func _update_hint() -> void:
	if sel_item == "":
		_desc_l.text = "从上方选一件道具"
		if _tile_l != null:
			_tile_l.text = "目标格：无（点棋盘选格）"
		return
	var d := ItemData.def(sel_item)
	var tgt := String(d.get("target", ""))
	var then := String(d.get("then", ""))
	var need := ""
	if tgt == "player":
		need = "\n→ 需点左侧「🎯 设为目标」选目标" + \
			("（当前：%s）" % String(g.hp[target_i].get("name", "?")) if target_i >= 0 else "（未选）")
		if then == "own_prop":
			need += "\n→ 再点棋盘选他名下的一块地"
	elif tgt == "tile":
		need = "\n→ 需点棋盘选目标格" + ("（当前：#%d）" % target_tile if target_tile >= 0 else "（未选）")
	_desc_l.text = "%s · %s · %s\n%s%s" % [sel_item, String(d.get("quality", "?")),
		("被动" if String(d.get("type", "")) == "passive" else "⚡%d" % int(d.get("cost", 0))),
		String(d.get("desc", "")), need]
	if _tile_l != null:
		_tile_l.text = "目标格：%s" % ("#" + str(target_tile) if target_tile >= 0 else "无（点棋盘选格）")

# ================= 动作 =================

func _needs_player(id: String) -> bool:
	return String(ItemData.def(id).get("target", "")) == "player"

func _grant() -> void:
	var p := _actor()
	if p.is_empty() or sel_item == "":
		return
	var ok: bool = g._grant_item(p, sel_item)
	_log(("授予 %s → %s（背包 %d/%d）" % [sel_item, String(p.name), p.items.size(), g._bag_cap(p)]) if ok
		else "背包已满，授予失败")
	_after()

func _use(consume: bool) -> void:
	var p := _actor()
	if p.is_empty() or sel_item == "":
		return
	var d := ItemData.def(sel_item)
	var tgt := String(d.get("target", ""))
	# 目标 / 参数
	var arg := -1
	var arg2 := -1
	var then := String(d.get("then", ""))
	if tgt == "player":
		if target_i < 0:
			_log("【%s】需要选目标玩家（点左侧玩家卡）" % sel_item)
			return
		arg = int(g.hp[target_i].peer)
		if then == "own_prop":
			if target_tile < 0:
				_log("【%s】需点棋盘选他名下的一块地" % sel_item)
				return
			arg2 = target_tile
	elif tgt == "tile":
		if target_tile < 0:
			_log("【%s】需要点棋盘选格" % sel_item)
			return
		arg = target_tile
	else:
		arg = int(_param_edit.text.strip_edges().to_int())
	# 保证背包里有这件实例（效果本体可能要用）
	var inst := _find_inst(p, sel_item)
	if inst.is_empty():
		if not g._grant_item(p, sel_item):
			_log("背包已满，无法使用")
			return
		inst = p.items[p.items.size() - 1]
	# 闸门：两个开关独立控制「不耗能量」「关冷却」；「仅触发」完全不看闸门
	var cost: int = g._item_cost(p, inst)
	if consume:
		if not no_cooldown and int(inst.get("cd", 0)) > 0:
			_log("【%s】冷却中（剩 %d 回合，可勾「关冷却」忽略）" % [sel_item, int(inst.cd)])
			return
		if not free_energy:
			if int(p.stamina) < cost:
				_log("体力不足（需 ⚡%d，可勾「不耗能量」忽略）" % cost)
				return
			p.stamina = int(p.stamina) - cost
			g._consume_cost_pen(p)
			p.first_used = true
		inst.cd = 0 if no_cooldown else int(d.get("cooldown", 0))
		_log("（立即使用：%s，%s）" % [
			"不耗能量" if free_energy else "扣体力 ⚡%d" % cost,
			"冷却已关" if no_cooldown else "冷却 %d" % int(d.get("cooldown", 0))])
	var before := _snap_dict()
	var ok: bool = await g._apply_item_effect(p, inst, arg, arg2)
	if not ok:
		_log("【%s】效果前置条件不满足（未生效）" % sel_item)
		_after(before)
		return
	# 一次性 + 焚毁
	if consume and String(d.get("type", "")) == "consumable":
		g.items_consumed[sel_item] = true
		var idx: int = p.items.find(inst)
		if idx >= 0:
			p.items.remove_at(idx)
		_log("【%s】用后焚毁（离池）" % sel_item)
	elif not consume:
		# 仅触发：用完就丢（被动也丢掉，除非想留）
		if String(d.get("type", "")) == "passive":
			_log("【%s】为被动，仅触发一次" % sel_item)
		else:
			var idx2: int = p.items.find(inst)
			if idx2 >= 0:
				p.items.remove_at(idx2)
	_log("使用【%s】" % sel_item)
	_after(before)

func _turn_start() -> void:
	var p := _actor()
	if p.is_empty():
		return
	var before := _snap_dict()
	g._item_turn_start(p)
	_log("对 %s 结算一次「回合开始」（被动/冷却/香皂融化）" % String(p.name))
	_after(before)

func _tile_edit(kind: String) -> void:
	if target_tile < 0:
		_log("先点棋盘选一个格子")
		return
	var t: Dictionary = g.htiles[target_tile]
	var p := _actor()
	match kind:
		"own":
			t.owner = int(p.get("peer", GameData.NO_OWNER)); t.soil = false
		"none":
			t.owner = GameData.NO_OWNER; t.soil = false
		"up":
			t.level = mini(int(t.get("level", 0)) + 1, 3)
		"down":
			t.level = maxi(int(t.get("level", 0)) - 1, 0)
		"soil":
			t.soil = true; t.soil_prog = 0; t.owner = GameData.NO_OWNER; t.level = 0
	_log("地块 #%d → %s" % [target_tile, kind])
	_broadcast()
	render()

func _on_lab_tile(idx: int) -> void:
	target_tile = idx
	_update_hint()
	_log("选中目标格 #%d（%s）" % [idx, String(GameData.TILES[idx].get("name", ""))])

# ================= 快照 / diff / 工具 =================

func _snap_dict() -> Dictionary:
	var players := []
	for p in g.hp:
		players.append({"money": int(p.get("money", 0)), "stamina": int(p.get("stamina", 0)),
			"pos": int(p.get("pos", 0)), "items": _ids(p)})
	var tiles := []
	for t in g.htiles:
		tiles.append({"owner": int(t.get("owner", GameData.NO_OWNER)), "level": int(t.get("level", 0)),
			"soil": bool(t.get("soil", false))})
	return {"players": players, "tiles": tiles}

func _ids(p: Dictionary) -> Array:
	var out := []
	for it in p.get("items", []):
		out.append(String(it.id))
	return out

func _snap() -> void:
	snap = _snap_dict()

func _do_snap() -> void:
	_snap()
	_log("已保存快照")

func _rollback() -> void:
	if snap.is_empty():
		_log("没有快照")
		return
	for i in g.hp.size():
		var b: Dictionary = snap.players[i]
		g.hp[i].money = int(b.money)
		g.hp[i].stamina = int(b.stamina)
		g.hp[i].pos = int(b.pos)
	for i in g.htiles.size():
		var bt: Dictionary = snap.tiles[i]
		g.htiles[i].owner = int(bt.owner)
		g.htiles[i].level = int(bt.level)
		g.htiles[i].soil = bool(bt.soil)
	_broadcast()
	_log("已回滚到快照")
	render()

func _after(before: Dictionary = {}) -> void:
	_broadcast()
	render()
	if not before.is_empty():
		_diff(before)

func _diff(before: Dictionary) -> void:
	for c in _diff_box.get_children():
		c.queue_free()
	var now := _snap_dict()
	var lines: Array = []
	for i in g.hp.size():
		var nm := String(g.hp[i].get("name", "?"))
		var b: Dictionary = before.players[i]
		var n: Dictionary = now.players[i]
		if n.money != b.money:
			lines.append("%s 现金 %s → %s (%+d)" % [nm, GameData.fmt_money(int(b.money)),
				GameData.fmt_money(int(n.money)), int(n.money) - int(b.money)])
		if n.stamina != b.stamina:
			lines.append("%s 体力 %d → %d" % [nm, int(b.stamina), int(n.stamina)])
		if n.pos != b.pos:
			lines.append("%s 位置 %d → %d" % [nm, int(b.pos), int(n.pos)])
		if String(n.items) != String(b.items):
			lines.append("%s 背包 %s → %s" % [nm, str(b.items), str(n.items)])
	for i in g.htiles.size():
		var bt: Dictionary = before.tiles[i]
		var nt: Dictionary = now.tiles[i]
		if int(bt.owner) != int(nt.owner) or int(bt.level) != int(nt.level) or bool(bt.soil) != bool(nt.soil):
			lines.append("地块 #%d 归属/等级/焦土 %s → %s" % [i,
				"%d/L%d/%s" % [int(bt.owner), int(bt.level), bt.soil],
				"%d/L%d/%s" % [int(nt.owner), int(nt.level), nt.soil]])
	if lines.is_empty():
		lines.append("（无可见状态变化）")
	for s in lines:
		_diff_box.add_child(UIKit.label(String(s), 11, UIKit.TEXT))
	_log("— 效果 diff —")

func _reset() -> void:
	g.lab_reset()
	actor_i = 0
	target_i = -1
	target_tile = -1
	sel_item = ""
	snap = {}
	_snap()
	_log("沙盒已重置")
	render()
	for c in _diff_box.get_children():
		c.queue_free()

func _copy_state() -> void:
	var payload := JSON.stringify(_snap_dict(), "  ")
	DisplayServer.clipboard_set(payload)
	_log("状态 JSON 已复制到剪贴板")
	print(payload)

# ================= 用例保存 / 回放（§九 D / ⑭） =================

func _save_case() -> void:
	var name := _case_edit.text if _case_edit != null else "case"
	var path := LabCase.save(name, g)
	if path == "":
		_log("存用例失败（目录不可写？）")
		return
	_log("已存用例 → %s（现有：%s）" % [path, ", ".join(LabCase.list_cases())])

func _load_case(name: String) -> bool:
	var data := LabCase.load_data(name)
	if data.is_empty():
		_log("没有这个用例：%s（现有：%s）" % [LabCase.safe_name(name), ", ".join(LabCase.list_cases())])
		return false
	LabCase.apply(g, data)
	if _case_edit != null:
		_case_edit.text = name
	actor_i = clampi(actor_i, 0, maxi(g.hp.size() - 1, 0))
	target_i = -1
	target_tile = -1
	render()
	_log("已回放用例 ← %s" % LabCase.path_for(name))
	return true

## 启动参数 `--lab-case=名字`（`main_menu` 把它与 `--lab` 同链处理；这里读出名字直达回放）。
func _case_arg() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lab-case="):
			return a.substr("--lab-case=".length())
	return ""

func _find_inst(p: Dictionary, id: String) -> Dictionary:
	for it in p.get("items", []):
		if String(it.id) == id:
			return it
	return {}

func _broadcast() -> void:
	if g != null:
		g._broadcast_state()

func _log(s: String) -> void:
	if _log_box == null:
		return
	_log_box.add_child(UIKit.label("· " + s, 11, UIKit.TEXT))
	while _log_box.get_child_count() > 60:
		_log_box.get_child(0).queue_free()
