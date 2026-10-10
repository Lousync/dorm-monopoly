class_name Dashboard
extends Node
## 对局仪表盘（回合 / 行动者 / 阶段流程）—— 由 `TableHud.build_play_ui` 建，
## 挂在屏幕层 `hud` 上，与左上「暂停」/右上「战报·规则」同层。
##
## 动机：把「第几轮 / 轮到谁 / 到哪个阶段 / 还剩多久」从散落多处收拢成一条顶部指挥带
##（回合卡 + 当前行动 + 阶段 stepper + 等待提示）。
##
## 数据**全部读已同步的 `st` 与 `_op_*`**（`s_state` / `s_op_timer` 推的那份）——
## 客户端（非房主）也准，**不需要任何新协议**。
##
## 施工落位（2026-10-09 用户 drawio 定稿，只取布局、不照比例）：顶部**仪表盘横条**是「暂停（选项）」
## 右侧的一条带（不铺到选项背后），右端让开「规则说明 / 战报」。畸变横幅与战报气泡挪到横条下方，
## 互不打架。**玩家纵览已按用户要求删除**（改为在玩家道具弹窗里看地皮数，见 `player_popup.gd`）。
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
## 顶条左右端：左端在「暂停」右侧（房主）/「暂停 + 网络质量」右侧（客户端）；右端让开
## 「规则说明 / 战报」（其最左缘 ≈ 屏宽 −250）。
const BAR_LEFT_HOST := 104.0
const BAR_LEFT_CLIENT := 276.0
const BAR_RIGHT := -258.0

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

# ---- 阶段推进追踪（按「回合/行动者」为键，单调前进）----
var _phase := 0
var _turn_key := ""
var _last_phase := -1

func setup() -> void:
	host = g.get("hud_layer")
	if host == null:
		return
	_build_bar()

## 整体隐藏（道具试验场等复用 game 的场景用）：关掉刷新并收掉横条。
func hide_all() -> void:
	enabled = false
	if bar != null and is_instance_valid(bar):
		bar.visible = false

# ================= 建 =================

func _build_bar() -> void:
	bar = UIKit.panel_container(UIKit.PANEL_GLASS, 12,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 6)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# 横条是「选项」右侧的一条带：左端让开暂停（房主）/ 暂停 + 网络质量（客户端），
	# 右端让开「规则说明 / 战报」。不再铺满整宽（原先把两端盖住、靠内部空位避让）。
	bar.offset_left = BAR_LEFT_HOST if g.multiplayer.is_server() else BAR_LEFT_CLIENT
	bar.offset_right = BAR_RIGHT
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
