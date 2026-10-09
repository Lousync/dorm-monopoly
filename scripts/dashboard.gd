class_name Dashboard
extends Node
## 对局仪表盘（回合 / 行动者 / 阶段流程）—— 由 `TableHud.build_play_ui` 建，
## 挂在屏幕层 `hud` 上，与左上「暂停」/右上「战报·规则」同层。
##
## 动机：把「第几轮 / 轮到谁 / 到哪个阶段 / 还剩多久」从散落多处收拢成一条顶部指挥带
##（回合卡 + 当前行动 + 阶段 stepper + 等待提示）+ 右侧玩家纵览。
##
## 数据**全部读已同步的 `st` 与 `_op_*`**（`s_state` / `s_op_timer` 推的那份）——
## 客户端（非房主）也准，**不需要任何新协议**。
##
## 施工落位（融合，2026-10-09 用户拍板）：顶部横条与现有「暂停 / 战报·规则」按钮同一条
## 带上——横条铺满顶部（玻璃底），中间放仪表盘内容，左右各留出一段空位让现有按钮"坐进"
## 横条两端（按钮本身位置一字未动）。畸变横幅与战报气泡挪到横条下方，互不打架。
##
## 底部那排「控制按钮」只是原型演示用，**这里不要**（见 `doc/game-design/对局仪表盘-原型.html`）。

# ---- 阶段（粗粒度，与原型一致；`await` 与它并非一一对应）----
const PHASES := ["回合开始", "① 掷轮盘", "移动", "落地结算", "② 使用道具", "回合结束"]

const STEP_DONE := 0
const STEP_CUR := 1
const STEP_TODO := 2

## 顶条高度（屏幕像素）：`table_hud.build_play_ui` 里量过，横条 y 8..76。
const BAR_TOP := 8.0
const BAR_BOTTOM := 76.0
## 右侧纵览的落位（贴右、在横条之下）。
const RAIL_TOP := 84.0
const RAIL_W := 196.0
const RAIL_RIGHT := 12.0

var g: Node
var host: Control               # 屏幕层容器（`g.hud_layer`）—— 控件挂它才拿得到正确尺寸
var enabled := true             # 试验场等场景可整体关掉（关掉后 refresh 不再点灯）

# ---- 顶条控件 ----
var bar: PanelContainer
var round_n: Label
var round_of: Label
var round_fill: ColorRect
var who_dot: Panel
var who_name: Label
var who_tag: Label
var steps_row: HBoxContainer
var _steps: Array = []          # [{root: PanelContainer, label: Label, dot: Panel}]
var wait_pill: Label
var wait_text: Label
var wait_time: Label

# ---- 右侧纵览 ----
var rail: VBoxContainer
var rail_title: Label
var _rows: Dictionary = {}      # peer -> row dict
var _rail_sig := ""

# ---- 阶段推进追踪（按「回合/行动者」为键，单调前进）----
var _phase := 0
var _turn_key := ""
var _last_phase := -1

func setup() -> void:
	host = g.get("hud_layer")
	if host == null:
		return
	_build_bar()
	_build_rail()

## 整体隐藏（道具试验场等复用 game 的场景用）：关掉刷新并收掉两块。
func hide_all() -> void:
	enabled = false
	if bar != null and is_instance_valid(bar):
		bar.visible = false
	if rail != null and is_instance_valid(rail):
		rail.visible = false

# ================= 建 =================

func _build_bar() -> void:
	bar = UIKit.panel_container(UIKit.PANEL_GLASS, 12,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 6)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 8.0
	bar.offset_right = -8.0
	bar.offset_top = BAR_TOP
	bar.offset_bottom = BAR_BOTTOM
	# 不吃鼠标：横条只是浮在画面上，别挡住它下面（顶部那条）棋盘的可点内容。
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(bar)
	var m := UIKit.margins(12, 12, 8, 8)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(hb)

	# 左端让位：给左上角「暂停」（12..92）与客户端「网络质量」（100..268）留出空位。
	hb.add_child(UIKit.hspace(272))

	# ① 回合卡
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 1)
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(rv)
	var rl := UIKit.label("回合 / ROUND", 10, UIKit.TEXT_DIM)
	rv.add_child(rl)
	var rbig := HBoxContainer.new()
	rbig.add_theme_constant_override("separation", 4)
	rbig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(rbig)
	round_n = UIKit.label("1", 24, UIKit.ACCENT)
	round_n.add_theme_font_override("font", UIKit.font_bold())
	rbig.add_child(round_n)
	round_of = UIKit.label("/ 30", 12, UIKit.TEXT_DIM)
	round_of.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	rbig.add_child(round_of)
	var rtrack := ColorRect.new()
	rtrack.color = Color(0.10, 0.11, 0.15, 1.0)
	rtrack.custom_minimum_size = Vector2(132, 6)
	rtrack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rv.add_child(rtrack)
	round_fill = ColorRect.new()
	round_fill.color = UIKit.ACCENT
	round_fill.size = Vector2(0, 6)
	round_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtrack.add_child(round_fill)

	hb.add_child(_vline())

	# ② 当前行动 + 阶段 stepper + 等待提示
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 3)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(cv)

	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 7)
	wrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(wrow)
	who_dot = Panel.new()
	who_dot.custom_minimum_size = Vector2(12, 12)
	who_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	who_dot.add_theme_stylebox_override("panel",
		UIKit.stylebox(Color(0.9, 0.3, 0.3), 6, Color(0, 0, 0, 0.4), 1))
	wrow.add_child(who_dot)
	wrow.add_child(UIKit.label("当前行动：", 12, UIKit.TEXT_DIM))
	who_name = UIKit.label("", 14, UIKit.ACCENT)
	who_name.add_theme_font_override("font", UIKit.font_bold())
	wrow.add_child(who_name)
	who_tag = UIKit.label("", 12, UIKit.TEXT_DIM)
	wrow.add_child(who_tag)

	steps_row = HBoxContainer.new()
	steps_row.add_theme_constant_override("separation", 2)
	steps_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(steps_row)
	_build_steps()

	var wwrow := HBoxContainer.new()
	wwrow.add_theme_constant_override("separation", 7)
	wwrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(wwrow)
	wait_pill = UIKit.label("", 11, UIKit.ACCENT_HI)
	wwrow.add_child(wait_pill)
	wait_text = UIKit.label("", 12, UIKit.TEXT)
	wwrow.add_child(wait_text)
	wait_time = UIKit.label("", 12, UIKit.DANGER)
	wait_time.add_theme_font_override("font", UIKit.font_bold())
	wwrow.add_child(wait_time)

	hb.add_child(_vline())

	# 右端让位：给右上角「规则说明 / 战报」（约屏宽 −12 起、向左约 250 像素）留出空位。
	hb.add_child(UIKit.hspace(244))

func _build_steps() -> void:
	for i in PHASES.size():
		if i > 0:
			steps_row.add_child(UIKit.label("›", 11, UIKit.BORDER.lightened(0.4)))
		var step := PanelContainer.new()
		step.mouse_filter = Control.MOUSE_FILTER_IGNORE
		steps_row.add_child(step)
		var sm := UIKit.margins(7, 7, 2, 2)
		sm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		step.add_child(sm)
		var sh := HBoxContainer.new()
		sh.add_theme_constant_override("separation", 5)
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sm.add_child(sh)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(7, 7)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sh.add_child(dot)
		var lb := UIKit.label(PHASES[i], 12, UIKit.TEXT_DIM)
		sh.add_child(lb)
		_steps.append({"root": step, "label": lb, "dot": dot})

func _style_step(i: int, state: int) -> void:
	var s: Dictionary = _steps[i]
	var step: PanelContainer = s.root
	var lb: Label = s.label
	var dot: Panel = s.dot
	if state == STEP_CUR:
		step.add_theme_stylebox_override("panel",
			UIKit.stylebox(UIKit.ACCENT, 8, UIKit.ACCENT_HI, 1, 0))
		lb.add_theme_color_override("font_color", Color(0.10, 0.12, 0.16))
		lb.add_theme_font_override("font", UIKit.font_bold())
		dot.add_theme_stylebox_override("panel", UIKit.stylebox(Color(0.10, 0.12, 0.16), 4))
	elif state == STEP_DONE:
		step.add_theme_stylebox_override("panel", UIKit.stylebox(Color(0, 0, 0, 0), 8))
		lb.add_theme_color_override("font_color", Color(0.56, 0.75, 0.60))
		lb.remove_theme_font_override("font")
		dot.add_theme_stylebox_override("panel", UIKit.stylebox(Color(0.455, 0.812, 0.529), 4))
	else:
		step.add_theme_stylebox_override("panel", UIKit.stylebox(Color(0, 0, 0, 0), 8))
		lb.add_theme_color_override("font_color", UIKit.TEXT_DIM)
		lb.remove_theme_font_override("font")
		dot.add_theme_stylebox_override("panel", UIKit.stylebox(Color(0.29, 0.32, 0.38), 4))

func _build_rail() -> void:
	rail = VBoxContainer.new()
	rail.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	rail.offset_left = -RAIL_RIGHT - RAIL_W
	rail.offset_right = -RAIL_RIGHT
	rail.offset_top = RAIL_TOP
	rail.offset_bottom = 660.0
	rail.add_theme_constant_override("separation", 6)
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(rail)
	rail_title = UIKit.label("玩家纵览", 11, UIKit.TEXT_DIM)
	rail.add_child(rail_title)

func _vline() -> ColorRect:
	var v := ColorRect.new()
	v.color = Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.55)
	v.custom_minimum_size = Vector2(1, 0)
	v.size_flags_vertical = Control.SIZE_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v

# ================= 刷 =================

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	if not enabled:
		return
	if g == null or not is_instance_valid(g):
		return
	var st: Dictionary = g.get("st")
	if st == null or (st as Dictionary).is_empty():
		return
	var phase := String(st.get("phase", ""))
	var running := phase == "playing"
	bar.visible = running
	rail.visible = running
	if not running:
		return

	var turn_peer := int(st.get("turn", -1))
	var max_rounds := int(st.get("max_rounds", GameData.MAX_ROUNDS))
	var round_no := int(st.get("round", 1))

	# ① 回合卡
	round_n.text = str(round_no)
	if max_rounds <= 0:
		round_of.text = "/ ∞"
		round_fill.size.x = 132.0
	else:
		round_of.text = "/ %d" % max_rounds
		round_fill.size.x = 132.0 * clampf(float(round_no) / float(max_rounds), 0.0, 1.0)

	# ② 当前行动
	var p := _player(st, turn_peer)
	var col := _color_of(p)
	who_dot.add_theme_stylebox_override("panel",
		UIKit.stylebox(col, 6, Color(0, 0, 0, 0.4), 1))
	who_name.text = String(p.get("name", "—")) if not p.is_empty() else "—"
	who_name.add_theme_color_override("font_color", col)
	who_tag.text = _actor_tag(p, turn_peer)

	# 阶段推进（按「回合/行动者」为键，单调前进）
	var key := "%d/%d" % [round_no, turn_peer]
	if key != _turn_key:
		_turn_key = key
		_phase = 0
	var await_s := String(st.get("await", ""))
	var op_kind := String(g.get("_op_kind"))
	var tgt := _phase_target(await_s, op_kind)
	if tgt >= 0:
		_phase = maxi(_phase, tgt)
	elif await_s == "" and op_kind == "":
		if _phase == 1:
			_phase = 2          # 掷完、正在移动
		elif _phase >= 4:
			_phase = 5          # 道具阶段已过、正在收尾
	if _phase != _last_phase:
		_last_phase = _phase
		for i in _steps.size():
			_style_step(i, STEP_DONE if i < _phase else (STEP_CUR if i == _phase else STEP_TODO))

	# ③ 等待提示
	_set_wait(st, await_s, op_kind)

	# ④ 右侧纵览
	_refresh_rail(st, turn_peer)

func _set_wait(st: Dictionary, await_s: String, op_kind: String) -> void:
	var op_left := float(g.get("_op_left"))
	var op_total := float(g.get("_op_total"))
	var owner := int(g.get("_op_owner"))
	var timed := op_kind != "" and op_total > 0.0
	var who := ""
	var text := ""
	if op_kind != "":
		who = _peer_name(st, owner)
		text = _op_text(op_kind)
		if who == "":
			who = "系统"
	else:
		# 没有操作窗口（两次 s_op_timer 之间 / 不限时窗口）：按 await 给一句粗粒度说明（无秒数）。
		# 环节归属用 `_op_owner`（没有就退到当前行动者）。
		var fallback := {
			"tech": "开局科技：三选一",
			"roll": "等待掷轮盘",
			"renmen": "任意门：请选择目标格",
			"discover": "失物招领：三选一",
			"prompt": "等待决定：买地 / 升级",
			"item": "道具阶段（可跳过）",
			"shop": "正在逛小卖部",
			"black": "正在黑市交易",
			"card": "等待确认抽卡",
			"liq": "变卖保底：凑款中…",
		}
		if fallback.has(await_s):
			text = String(fallback[await_s])
			who = _peer_name(st, owner) if owner != 0 else "系统"
		elif _phase == 2:
			who = "系统"; text = "移动中…"
		elif _phase == 5:
			who = "系统"; text = "本回合结束，轮到下一位"
		else:
			who = "系统"; text = "…"
		if who == "":
			who = "系统"
	wait_pill.text = who
	wait_text.text = text
	if timed:
		wait_time.text = "· 剩 %d 秒" % ceili(maxf(op_left, 0.0))
		wait_time.visible = true
	else:
		wait_time.text = ""
		wait_time.visible = false

func _op_text(kind: String) -> String:
	match kind:
		"roll": return "等待掷轮盘"
		"prompt": return "等待决定：买地 / 升级"
		"item": return "道具阶段（可跳过）"
		"shop": return "正在逛小卖部"
		"black": return "正在黑市交易"
		"card": return "等待确认抽卡"
	return "等待操作（%s）" % kind

func _phase_target(await_s: String, op_kind: String) -> int:
	match await_s:
		"tech": return 0
		"roll": return 1
		"renmen": return 2
		"prompt", "card", "shop", "black", "liq", "discover": return 3
		"item": return 4
	match op_kind:
		"roll": return 1
		"prompt", "card", "shop", "black": return 3
		"item": return 4
	return -1

func _actor_tag(p: Dictionary, turn_peer: int) -> String:
	if p.is_empty():
		return ""
	var bits := PackedStringArray()
	bits.append("轮到你" if turn_peer == int(g.get("my_peer")) else "等待他行动")
	if int(p.get("sleep", 0)) > 0:
		bits.append("休眠")
	elif bool(p.get("bot", false)):
		bits.append("托管")
	return " · ".join(bits)

func _refresh_rail(st: Dictionary, turn_peer: int) -> void:
	var players: Array = st.get("players", [])
	var tiles: Array = st.get("tiles", [])
	var sig := "%d" % turn_peer
	for p in players:
		sig += "|%d,%d,%d,%d,%d,%d,%d" % [int(p.get("peer", 0)), int(p.get("money", 0)),
			int(p.get("stamina", 0)), int(p.get("color", 0)), 1 if bool(p.get("alive", true)) else 0,
			int(p.get("sleep", 0)), 1 if bool(p.get("bot", false)) else 0]
	# 地块归属进签名（地皮数会变）
	var props := {}
	for i in tiles.size():
		var o := int((tiles[i] as Dictionary).get("owner", GameData.NO_OWNER))
		if o != GameData.NO_OWNER:
			props[o] = int(props.get(o, 0)) + 1
	for p in players:
		sig += "|%d" % int(props.get(int(p.get("peer", 0)), 0))
	if sig == _rail_sig:
		return
	_rail_sig = sig

	# 复用已有行（题目不变就不重建）；玩家集合变化时重建。
	var want := {}
	for p in players:
		want[int(p.get("peer", 0))] = true
	for peer in _rows.keys():
		if not want.has(peer):
			(_rows[peer].root as Control).queue_free()
			_rows.erase(peer)
	for pi in players.size():
		var p: Dictionary = players[pi]
		var peer := int(p.get("peer", 0))
		if not _rows.has(peer):
			_rows[peer] = _make_row(peer)
		_fill_row(_rows[peer], p, int(props.get(peer, 0)), turn_peer)
	# 顺序：按 players 顺序重排
	for pi in players.size():
		var peer2 := int((players[pi] as Dictionary).get("peer", 0))
		if _rows.has(peer2):
			rail.move_child((_rows[peer2].root as Control), pi + 1)

func _make_row(peer: int) -> Dictionary:
	var root := UIKit.panel_container(Color(0.085, 0.095, 0.138, 0.82), 10,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.7), 1, 3)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_meta("peer", peer)
	root.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			g._on_corner_bar_clicked(int(root.get_meta("peer", GameData.NO_PEER)))
	)
	rail.add_child(root)
	var m := UIKit.margins(9, 9, 6, 6)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(m)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(hb)
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(16, 16)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(slot)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 1)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(mid)
	var nm := UIKit.label("", 13, UIKit.TEXT)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size = Vector2(72, 0)
	mid.add_child(nm)
	var tg := UIKit.label("", 10, UIKit.TEXT_DIM)
	mid.add_child(tg)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 1)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(right)
	var mn := UIKit.label("", 12, UIKit.ACCENT)
	mn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(mn)
	var meta := UIKit.label("", 10, UIKit.TEXT_DIM)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(meta)
	return {"root": root, "peer": peer, "slot": slot, "chip": null, "chip_color": -999,
		"name_l": nm, "tag_l": tg, "money_l": mn, "meta_l": meta, "active": false, "alive": true}

func _fill_row(row: Dictionary, p: Dictionary, props: int, turn_peer: int) -> void:
	var peer := int(p.get("peer", 0))
	var col := _color_of(p)
	if row.chip == null or int(row.chip_color) != int(p.get("color", 0)):
		for c in (row.slot as Control).get_children():
			c.queue_free()
		row.chip = UIKit.chip(col, 14)
		(row.slot as Control).add_child(row.chip)
		row.chip_color = int(p.get("color", 0))
	var alive := bool(p.get("alive", true))
	(row.root as Control).modulate.a = 1.0 if alive else 0.45
	(row.name_l as Label).text = String(p.get("name", "?"))
	(row.name_l as Label).add_theme_color_override("font_color",
		UIKit.TEXT_DIM if not alive else (UIKit.ACCENT if peer == turn_peer else UIKit.TEXT))
	var tags := PackedStringArray()
	if int(p.get("sleep", 0)) > 0:
		tags.append("休眠")
	elif bool(p.get("bot", false)):
		tags.append("托管")
	if not alive:
		tags.append("出局")
	(row.tag_l as Label).text = " ".join(tags)
	(row.tag_l as Label).visible = tags.size() > 0
	(row.money_l as Label).text = "已出局" if not alive else GameData.fmt_money(int(p.get("money", 0)))
	(row.meta_l as Label).text = "地 %d · 力 %d" % [props, int(p.get("stamina", 0))]
	var active := peer == turn_peer and alive
	if bool(row.active) != active:
		row.active = active
		var bg := Color(0.085, 0.095, 0.138, 0.82)
		var border := Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.7)
		if active:
			bg = Color(0.235, 0.205, 0.135, 0.95)
			border = Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.95)
		(row.root as Control).add_theme_stylebox_override("panel",
			UIKit.card_stylebox(bg, 10, border, 1, 3))

# ================= 小工具 =================

func _player(st: Dictionary, peer: int) -> Dictionary:
	for p in st.get("players", []):
		if int(p.get("peer", 0)) == peer:
			return p
	return {}

func _peer_name(st: Dictionary, peer: int) -> String:
	var p := _player(st, peer)
	return String(p.get("name", "")) if not p.is_empty() else ""

func _color_of(p: Dictionary) -> Color:
	return GameData.PLAYER_COLORS[clampi(int(p.get("color", 0)), 0, GameData.PLAYER_COLORS.size() - 1)]
