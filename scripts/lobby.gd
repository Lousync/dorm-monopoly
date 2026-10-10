extends Control
## 房间大厅：玩家列表、准备、机器人、开始游戏、本机直连地址、聊天。

var _players_box: VBoxContainer
var _ready_btn: Button
var _add_bot_btn: Button
var _remove_bot_btn: Button
var _start_btn: Button
var _settings_btn: Button
var _addr_box: VBoxContainer
var _chat_box: RichTextLabel
var _chat_edit: LineEdit
var _room_label: Label

# 网络自检弹窗（fix/0.14.1）：本机地址分类 + 出网连通性探测
var _net_btn: Button
var _net_wrap: Control
var _net_addr_lbl: Label
var _net_v6_lbl: Label
var _net_v4_lbl: Label
# 出网探测目标（公网 DNS 的 53 端口）：aliDNS 有两个任播 v6 地址，
# `2400:3200::1` 在本网 TCP 不通、`baba::1` 通，故以 baba 优先、::1 兜底。
const NS_V6 := ["2400:3200:baba::1", "2400:3200::1"]      # 阿里 IPv6 DNS
const NS_V4 := ["223.5.5.5", "119.29.29.29"]               # 阿里 / 腾讯 IPv4 DNS
const NS_PORT := 53
# 用 preload 取类，不依赖全局 class_name 缓存（新脚本的缓存要编辑器重建一次才在）
const NetProbeScript := preload("res://scripts/net_probe.gd")
var _ns_v6_probe = null
var _ns_v6_i := 0
var _ns_v4_probe = null
var _ns_v4_i := 0
var _ns_v6_done := true
var _ns_v4_done := true

# 房主开局设置弹窗（见 doc/game-design/开局设置.md）
var _set_wrap: Control
var _set_scroll: ScrollContainer
var _set_chips: HBoxContainer            # 操作限时挡位
var _set_tech_tier_chips: HBoxContainer  # 科技等级（随机 / 指定）
var _set_rounds_chips: HBoxContainer     # 回合上限档位
var _set_win_chips: HBoxContainer        # 胜利条件
var _set_ab_chips: HBoxContainer         # 畸变频率
var _set_ab_dur_chips: HBoxContainer     # 畸变持续回合
# on/off 的行一律走 **开关组件**（`UIKit.Switch`），不再用「关 / 开」两枚 chip（用户 2026-10-09）
var _set_liq_sw: UIKit.Switch            # 破产变卖保底
var _set_shop_sw: UIKit.Switch           # 小卖部开关
var _set_black_sw: UIKit.Switch          # 黑市开关
var _set_casino_sw: UIKit.Switch         # 赌场开关
var _set_tech_sw: UIKit.Switch           # 科技开关
var _set_ab_cond_sw: UIKit.Switch        # 畸变条件触发
var _set_cash_edit: LineEdit             # 起始资金
var _set_salary_edit: LineEdit           # 起点补贴
var _set_wincash_edit: LineEdit          # 目标现金金额
# 条件显隐的两块（用户 2026-10-09）：整行 / 整块跟着主选项走，由 `_sync_conditional_rows()` 统一刷
var _set_wincash_row: HBoxContainer       # 目标现金：仅 win = 目标现金 时显示
var _set_tech_tier_box: VBoxContainer     # 科技等级：仅科技开关打开时显示
var _set_tier := GameSettings.TIER_CURRENT
var _set_tech := true    # 科技开关（发车前配置；对局内不可改。默认开 = `GameSettings` 那份默认）
var _set_tech_tier := GameSettings.TECH_TIER_RANDOM   # 科技等级：random = 系统随机选一档；其余 = 指定
var _set_liq := true
var _set_rounds := 30
var _set_win := "rounds"
var _set_shop := true
var _set_black := true
var _set_casino := true
var _set_ab_freq := "关"
var _set_ab_dur := 2
var _set_ab_cond := true

var _at_mode := ""
var _shot_path := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			_at_mode = a.substr(11)
		elif a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-lobby="):
			_shot_path = a.substr(13)

	var bg := UIKit.decor_bg()
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 20)
	add_child(root)

	# 左列：玩家与操作
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)

	_room_label = UIKit.title_label("房间大厅", 28)
	left.add_child(_room_label)

	var players_panel := UIKit.panel_container(UIKit.PANEL, 12, _card_border(), 1, 8)
	players_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pm := UIKit.margins(10, 10, 8, 8)
	players_panel.add_child(pm)
	left.add_child(players_panel)

	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 8)
	pm.add_child(_players_box)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	left.add_child(btn_row)
	_ready_btn = UIKit.button("准备", 16)
	_ready_btn.pressed.connect(func() -> void: Net.toggle_ready())
	btn_row.add_child(_ready_btn)
	_add_bot_btn = UIKit.button("＋ 机器人", 15)
	_add_bot_btn.pressed.connect(func() -> void: Net.host_add_bot())
	btn_row.add_child(_add_bot_btn)
	_remove_bot_btn = UIKit.button("－ 机器人", 15)
	_remove_bot_btn.pressed.connect(func() -> void: Net.host_remove_bot())
	btn_row.add_child(_remove_bot_btn)
	_settings_btn = UIKit.button("游戏设置", 15)
	_settings_btn.custom_minimum_size = Vector2(0, 40)
	_settings_btn.tooltip_text = "开局设置（仅房主可改）"
	_settings_btn.pressed.connect(_on_open_settings)
	btn_row.add_child(_settings_btn)
	_net_btn = UIKit.button("网络自检", 15)
	_net_btn.custom_minimum_size = Vector2(0, 40)
	_net_btn.tooltip_text = "检查本机 IPv6 地址、出网连通性与直连建议"
	_net_btn.pressed.connect(_on_open_netself)
	btn_row.add_child(_net_btn)
	_start_btn = UIKit.button("开始游戏！", 17, "primary")
	_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_btn.custom_minimum_size = Vector2(0, 40)
	_start_btn.pressed.connect(_on_start)
	btn_row.add_child(_start_btn)
	var leave_btn := UIKit.button("离开", 15, "danger")
	leave_btn.pressed.connect(_on_leave)
	btn_row.add_child(leave_btn)

	# 右列：直连地址 + 聊天
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	root.add_child(right)

	var addr_panel := UIKit.panel_container(UIKit.PANEL, 12, _card_border(), 1, 8)
	var am := UIKit.margins(10, 10, 8, 8)
	addr_panel.add_child(am)
	right.add_child(addr_panel)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 4)
	am.add_child(av)
	av.add_child(UIKit.label("点「复制」把地址发给室友（加入时粘进「地址」框）", 14, UIKit.TEXT_DIM))
	# 逐条地址 + 各自的「复制」（fix/0.14.1）：以前是一个按钮复制**整块带标签的多行文本**，
	# 室友粘进地址框根本解析不出 host —— 现在每条复制的是**裸地址**（可直接粘）。
	_addr_box = VBoxContainer.new()
	_addr_box.add_theme_constant_override("separation", 4)
	av.add_child(_addr_box)

	var chat_panel := UIKit.panel_container(UIKit.PANEL, 12, _card_border(), 1, 8)
	chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cm := UIKit.margins(10, 10, 8, 8)
	chat_panel.add_child(cm)
	right.add_child(chat_panel)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	cm.add_child(cv)
	cv.add_child(UIKit.label("房间聊天", 14, UIKit.TEXT_DIM))
	_chat_box = RichTextLabel.new()
	_chat_box.scroll_following = true
	_chat_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_box.add_theme_font_size_override("normal_font_size", 14)
	cv.add_child(_chat_box)
	var chat_row := HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 6)
	cv.add_child(chat_row)
	_chat_edit = UIKit.line_edit("说点什么…（回车发送）")
	_chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_edit.text_submitted.connect(func(_t: String) -> void: _send_chat())
	chat_row.add_child(_chat_edit)
	var send_btn := UIKit.button("发送", 14)
	send_btn.pressed.connect(func() -> void: _send_chat())
	chat_row.add_child(send_btn)

	Net.lobby_changed.connect(_refresh)
	Net.chat_received.connect(_refresh_chat)
	Net.connection_lost.connect(_on_conn_lost)

	# 入场：左右两列错落淡入
	Fx.animate_in(left, 0.0)
	Fx.animate_in(right, 0.12)

	_refresh()
	_refresh_chat()
	_build_settings_dialog()
	_build_net_dialog()

	if _at_mode == "host":
		_autotest_host()
	elif _at_mode == "client" or _at_mode == "reconnect":
		_autotest_client()
	elif _shot_path != "":
		_shot()

func _exit_tree() -> void:
	Net.lobby_changed.disconnect(_refresh)
	Net.chat_received.disconnect(_refresh_chat)

## 点输入框之外要收掉焦点（用户 2026-10-09 报「鼠标点到别处，聊天框还亮着」）。
## 与主菜单那条是**同一处根因、同一个兜底**（按钮都 FOCUS_NONE ⇒ 点哪儿 LineEdit 都攥着焦点），
## 只是主菜单 2026-10-08 已补、大厅漏了。判据与细节见 `UIKit.release_focus_on_click`。
func _input(e: InputEvent) -> void:
	UIKit.release_focus_on_click(self, e)

func _refresh() -> void:
	_room_label.text = "房间：%s（%d/%d 人）" % [Net.room_name, Net.players.size(), Net.MAX_PLAYERS]
	for c in _players_box.get_children():
		c.queue_free()
	for p in Net.players:
		var card := UIKit.panel_container(Color(0.125, 0.14, 0.19, 0.9), 10,
			Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.65), 1, 3)
		var cm := UIKit.margins(10, 10, 6, 6)
		card.add_child(cm)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		cm.add_child(row)
		row.add_child(UIKit.chip(GameData.PLAYER_COLORS[int(p.color)], 20))
		var tags := ""
		if int(p.peer) == 1:
			tags += "（房主）"
		if bool(p.bot):
			tags += "（机器人）"
		var name_l := UIKit.label(p.name + tags, 16, UIKit.TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_l)
		if bool(p.ready) or bool(p.bot):
			row.add_child(UIKit.pill("已准备", UIKit.GOOD, 12))
		elif not bool(p.bot):
			row.add_child(UIKit.pill("未准备", UIKit.TEXT_DIM, 12))
		_players_box.add_child(card)
	if Net.players.size() < Net.MAX_PLAYERS:
		var wait := UIKit.label("（等待其他室友加入，最多 4 人）", 13, UIKit.TEXT_DIM)
		wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_players_box.add_child(wait)

	var human_ready := true
	for p in Net.players:
		if not bool(p.bot) and not bool(p.ready):
			human_ready = false
	_ready_btn.visible = not Net.is_host
	_ready_btn.text = "取消准备" if _i_am_ready() else "准备"
	if not Net.is_host:
		UIKit.restyle_button(_ready_btn, "good" if _i_am_ready() else "normal")
	_add_bot_btn.visible = Net.is_host
	_remove_bot_btn.visible = Net.is_host
	_settings_btn.visible = Net.is_host
	_start_btn.visible = Net.is_host
	_start_btn.disabled = not (Net.players.size() >= 2 and human_ready)
	_start_btn.tooltip_text = "" if not _start_btn.disabled else "需要所有真人都点「准备」"

	for c in _addr_box.get_children():
		c.queue_free()
	if Net.is_host:
		var a := Net.split_addresses()
		var port := Net.host_port if Net.host_port > 0 else Net.PORT
		# IPv6 必须带方括号，否则朋友粘贴后解析不出端口（见 fix/v0.0.2）
		var entries: Array = []
		for ip in a.lan4:
			entries.append(["局域网 IPv4", ip])
		for ip in a.lan6:
			entries.append(["内网 IPv6", ip])
		for ip in a.pub6:
			entries.append(["全球 IPv6（跨网直连）", ip])
		for ip in a.pub4:
			entries.append(["公网 IPv4", ip])
		if entries.is_empty():
			_addr_box.add_child(UIKit.label("未检测到可用地址，室友可尝试 127.0.0.1（同机测试）", 13, UIKit.TEXT_DIM))
		for e in entries:
			_addr_box.add_child(_make_addr_row(String(e[0]), String(e[1]), port))

## 一条直连地址行：标签 + 裸地址 + 复制按钮（复制的是**裸** `[v6]:port`，可直接粘进地址框）。
func _make_addr_row(tag: String, ip: String, port: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var ep := NetAddr.format_endpoint(ip, port)
	var lab := UIKit.label("%s　%s" % [tag, ep], 14, UIKit.TEXT)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(lab)
	var cb := UIKit.button("复制", 12)
	cb.tooltip_text = "复制 %s（直接粘进「地址」框）" % ep
	cb.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(ep)
		cb.text = "已复制 ✓"
		Fx.play("pop", -6.0)
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(cb):
			cb.text = "复制"
	)
	row.add_child(cb)
	return row

func _card_border() -> Color:
	return Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.85)

func _i_am_ready() -> bool:
	for p in Net.players:
		if int(p.peer) == Net.multiplayer.get_unique_id():
			return bool(p.ready)
	return false

## 房主「游戏设置」弹窗：经济 / 节奏 / 胜利条件 / 各系统开关（开局设置.md 定稿项 + 开关先行项）
##
## **版式（2026-10-09 用户 3 条 + 布局优化）**：
##   * 去掉顶上那句「默认值 = 现状常量…」提示（用户要求）；
##   * 每一节套一个 `UIKit.SectionBox` —— 带边框，**小标题骑在上边框正中**（legend 式）；
##   * on/off 的行从「关 / 开」两枚 chip 换成 `UIKit.Switch` **开关组件**；
##   * 原先的「特殊机制」一节拆成**「科技」+「畸变」两节**（两套系统挤在一节里读不清）。
##
## 行内版式沿用两种既有形态：**多选一（chip 行）**用「说明一行 + 整行 chip」，
## **开关 / 数字**用「说明左边、控件右边」—— 控件因此贴着小节盒的右内缘、纵向对齐。
func _build_settings_dialog() -> void:
	_set_wrap = Control.new()
	_set_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_set_wrap.visible = false
	add_child(_set_wrap)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # 模态：吞掉落在面板外的点击
	_set_wrap.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_wrap.add_child(center)
	var panel := UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.9), 1, 12)
	panel.custom_minimum_size = Vector2(680, 0)
	center.add_child(panel)
	var m := UIKit.margins(18, 18, 14, 12)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	v.add_child(UIKit.title_label("游戏设置", 20))
	_set_cash_edit = UIKit.line_edit("20000")
	_set_salary_edit = UIKit.line_edit("4500")
	_set_wincash_edit = UIKit.line_edit("50000")

	_set_scroll = ScrollContainer.new()
	_set_scroll.custom_minimum_size = Vector2(0, 520)
	_set_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_set_scroll)
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 间隔要**大于 legend 标题探出盒外的那半截**，否则上一节的边框压到下一节的标题
	sv.add_theme_constant_override("separation", 20)
	_set_scroll.add_child(sv)
	# 滚动容器会裁掉框外内容 ⇒ 第一节的标题上半截得先垫一块空白出来
	sv.add_child(UIKit.vspace(10))

	# —— A · 经济 ——
	var econ := UIKit.section_box("经济")
	sv.add_child(econ)
	var eb := econ.body()
	eb.add_child(UIKit.num_row("起始资金（每人开局现金）", _set_cash_edit))
	eb.add_child(UIKit.num_row("起点补贴（踏过 / 停在起点的工资）", _set_salary_edit))
	_set_liq_sw = UIKit.switch_toggle(_set_liq, func(on: bool) -> void: _set_liq = on)
	# 文案（用户 2026-10-09）：条目名「破产变卖保底」→「破产变卖」，比例 30% → 50%，
	# 原括注（回收公式 + 「窗口 = 操作限时」）整句删除 —— 窗口来源在第二节「操作限时」的
	# 说明里已写明"破产变卖自选"按本档计时，这一行不必重复。
	# 比例**不写死**：读 `GameData.LIQ_RATE`，改比例时这里自动跟上。
	eb.add_child(UIKit.ctrl_row(
		"破产变卖：付不起钱时可变卖地皮凑差价，可回收地皮价值（含房屋）的 %d%%"
			% int(round(GameData.LIQ_RATE * 100.0)),
		_set_liq_sw))

	# —— B · 回合与节奏 ——
	var pace := UIKit.section_box("回合与节奏")
	sv.add_child(pace)
	var pb := pace.body()
	# 这一句顺带点明**覆盖范围**：凡"要你拿主意"的窗口都归本挡位（含破产变卖那个自选变卖），
	# 免得再有人以为变卖另有一个旋钮（用户 2026-10-09 就是这么问的）。
	pb.add_child(UIKit.note("操作限时：轮到你时超过该时间没操作，就由系统托管。买地 / 装修决策、破产变卖自选、抽卡确认都按本档计时。"))
	_set_chips = UIKit.chip_row(GameSettings.TIERS, GameSettings.TIER_LABELS,
		func(id: String) -> void:
			_set_tier = id
			UIKit.chip_select(_set_chips, id),
		{GameSettings.TIER_CURRENT: GameSettings.TIER_CURRENT_HINT})
	pb.add_child(_set_chips)
	pb.add_child(UIKit.note("回合上限：轮次结束后未分胜负则按总资产排名"))
	_set_rounds_chips = UIKit.chip_row(GameSettings.ROUNDS_SW, GameSettings.ROUNDS_LABELS,
		func(id: String) -> void:
			_set_rounds = 0 if id == "none" else int(id)
			UIKit.chip_select(_set_rounds_chips, id))
	pb.add_child(_set_rounds_chips)

	# —— C · 胜利条件 ——
	var win := UIKit.section_box("胜利条件")
	sv.add_child(win)
	var wb := win.body()
	# 顶上原有一句说明「先达成者立即获胜，本局随即结算」，按用户 2026-10-09 去掉
	_set_win_chips = UIKit.chip_row(GameSettings.WIN_MODES, GameSettings.WIN_LABELS,
		func(id: String) -> void:
			_set_win = id
			UIKit.chip_select(_set_win_chips, id)
			_sync_conditional_rows())   # 目标现金那一行跟着主选项显隐
	wb.add_child(_set_win_chips)
	# 目标现金金额：**只在 win = 目标现金 时出现**（用户 2026-10-09）——
	# 其余模式下这个数字没有任何消费方，常显只会让人以为它一直生效。
	_set_wincash_row = UIKit.num_row("目标现金", _set_wincash_edit)
	wb.add_child(_set_wincash_row)

	# —— 道具 / 商店 / 赌场 ——
	var shops := UIKit.section_box("道具 / 商店 / 赌场")
	sv.add_child(shops)
	var shb := shops.body()
	# 三行只留名字，括注（关掉之后会发生什么）按用户 2026-10-09 全部去掉
	_set_shop_sw = UIKit.switch_toggle(_set_shop, func(on: bool) -> void: _set_shop = on)
	shb.add_child(UIKit.ctrl_row("小卖部", _set_shop_sw))
	_set_black_sw = UIKit.switch_toggle(_set_black, func(on: bool) -> void: _set_black = on)
	shb.add_child(UIKit.ctrl_row("黑市", _set_black_sw))
	_set_casino_sw = UIKit.switch_toggle(_set_casino, func(on: bool) -> void: _set_casino = on)
	shb.add_child(UIKit.ctrl_row("宿舍赌场", _set_casino_sw))

	# —— 科技（doc/game-design/科技.md）：关 = 本局不定档不选卡 ——
	var tech := UIKit.section_box("科技")
	sv.add_child(tech)
	var tb := tech.body()
	_set_tech_sw = UIKit.switch_toggle(_set_tech, func(on: bool) -> void:
		_set_tech = on
		_sync_conditional_rows())   # 等级选择跟着开关显隐
	tb.add_child(UIKit.ctrl_row("开局时每人三选一，科技整局游戏生效", _set_tech_sw))
	# 科技等级（2026-10-07）：随机 = 系统随机选一档；指定 = 本局固定该档。
	# **整块只在开关打开时露出**（用户 2026-10-09）—— 关着的时候这个选择没有任何消费方。
	_set_tech_tier_box = VBoxContainer.new()
	_set_tech_tier_box.add_theme_constant_override("separation", 7)
	tb.add_child(_set_tech_tier_box)
	_set_tech_tier_box.add_child(UIKit.note("等级：随机 = 系统随机选一档；白银 / 黄金 / 钻石 = 本局固定该档"))
	_set_tech_tier_chips = UIKit.chip_row(GameSettings.TECH_TIERS, GameSettings.TECH_TIER_LABELS,
		func(id: String) -> void:
			_set_tech_tier = id
			UIKit.chip_select(_set_tech_tier_chips, id))
	_set_tech_tier_box.add_child(_set_tech_tier_chips)

	# —— 畸变 ——
	var ab := UIKit.section_box("畸变")
	sv.add_child(ab)
	var ab_body := ab.body()
	ab_body.add_child(UIKit.note("回合开始时可能触发的全场事件；频率「关」= 整局不触发"))
	_set_ab_chips = UIKit.chip_row(GameSettings.AB_FREQS, GameSettings.AB_FREQ_LABELS,
		func(id: String) -> void:
			_set_ab_freq = id
			UIKit.chip_select(_set_ab_chips, id))
	ab_body.add_child(_set_ab_chips)
	ab_body.add_child(UIKit.note("持续（持续型畸变默认几回合）"))
	_set_ab_dur_chips = UIKit.chip_row(GameSettings.AB_DURS, GameSettings.AB_DUR_LABELS,
		func(id: String) -> void:
			_set_ab_dur = int(id)
			UIKit.chip_select(_set_ab_dur_chips, id))
	ab_body.add_child(_set_ab_dur_chips)
	_set_ab_cond_sw = UIKit.switch_toggle(_set_ab_cond, func(on: bool) -> void: _set_ab_cond = on)
	ab_body.add_child(UIKit.ctrl_row("条件触发（满足条目条件时也会触发）", _set_ab_cond_sw))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var cancel := UIKit.button("取消", 15)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func() -> void: _set_wrap.visible = false)
	row.add_child(cancel)
	var ok := UIKit.button("确定", 16, "primary")
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(_on_settings_save)
	row.add_child(ok)

## 「网络自检」弹窗（fix/0.14.1）：本机地址分类 + 出网连通性才算真正「能不能用」。
## 出网探测走 NetProbe（TCP 连公网 DNS 的 53 端口），在 `_process` 里逐帧轮询。
func _build_net_dialog() -> void:
	_net_wrap = Control.new()
	_net_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_net_wrap.visible = false
	add_child(_net_wrap)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_net_wrap.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_wrap.add_child(center)
	var panel := UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.9), 1, 12)
	panel.custom_minimum_size = Vector2(588, 0)
	center.add_child(panel)
	var m := UIKit.margins(18, 18, 14, 12)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	v.add_child(UIKit.title_label("网络自检", 20))
	_net_addr_lbl = UIKit.label("", 13, UIKit.TEXT)
	_net_addr_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_net_addr_lbl)
	v.add_child(UIKit.label("── 出网检测（连公网 DNS 的 53 端口）──", 13, UIKit.ACCENT))
	_net_v6_lbl = UIKit.label("IPv6 出网：未检测", 14, UIKit.TEXT)
	_net_v6_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_net_v6_lbl)
	_net_v4_lbl = UIKit.label("IPv4 出网：未检测", 14, UIKit.TEXT)
	_net_v4_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_net_v4_lbl)
	var hint := UIKit.label(
		"· 有「全球 IPv6」且 IPv6 出网 ✓ → 跨网直连可用，把该地址发给室友。\n"
		+ "· 出网 ✓ ≠ 别人能连进来：入站常被 Windows 防火墙 / 校园网挡 —— 室友连不上先查这个。\n"
		+ "· 两边都要有 IPv6；室友那边没有 IPv6 就只能走 IPv4。", 12, UIKit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var again := UIKit.button("重新检测", 15)
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(_start_netself)
	row.add_child(again)
	var close := UIKit.button("关闭", 15, "primary")
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func() -> void: _net_wrap.visible = false)
	row.add_child(close)

func _on_open_netself() -> void:
	_net_wrap.visible = true
	_start_netself()

## 刷新本机地址摘要 + 起一轮出网探测（IPv6 先走阿里、失败再试谷歌）。
func _start_netself() -> void:
	var a := NetAddr.split_addresses()
	_net_addr_lbl.text = "── 本机地址 ──\n" \
		+ "全球 IPv6：%s\n" % _join_cn(a.pub6) \
		+ "内网 IPv6：%s\n" % _join_cn(a.lan6) \
		+ "局域网 IPv4：%s\n" % _join_cn(a.lan4) \
		+ "公网 IPv4：%s" % _join_cn(a.pub4)
	_ns_v6_i = 0
	_ns_v4_i = 0
	_ns_v6_done = false
	_ns_v4_done = false
	_ns_v6_probe = NetProbeScript.new()
	_ns_v6_probe.start(NS_V6[0], NS_PORT)
	_ns_v4_probe = NetProbeScript.new()
	_ns_v4_probe.start(NS_V4[0], NS_PORT)
	_net_v6_lbl.text = "IPv6 出网：检测中…"
	_net_v6_lbl.modulate = UIKit.TEXT_DIM
	_net_v4_lbl.text = "IPv4 出网：检测中…"
	_net_v4_lbl.modulate = UIKit.TEXT_DIM

## 逗号分隔地址（Array → PackedStringArray，避免 String.join 类型不匹配）
func _join_cn(arr: Array) -> String:
	if arr.is_empty():
		return "未检测到"
	var ps := PackedStringArray()
	for x in arr:
		ps.append(String(x))
	return "、".join(ps)

func _process(_delta: float) -> void:
	if _ns_v6_done and _ns_v4_done:
		return
	if not _ns_v6_done:
		var s: int = _ns_v6_probe.poll()
		if s == NetProbeScript.ST_FAIL and _ns_v6_i + 1 < NS_V6.size():
			_ns_v6_i += 1
			_ns_v6_probe = NetProbeScript.new()
			_ns_v6_probe.start(NS_V6[_ns_v6_i], NS_PORT)
			s = _ns_v6_probe.state
		if s != NetProbeScript.ST_CONNECTING:
			_ns_v6_done = true
			_net_v6_lbl.text = "IPv6 出网（%s）：%s" % [NS_V6[_ns_v6_i], _ns_v6_probe.status_text()]
			_net_v6_lbl.modulate = _ns_color(s)
	if not _ns_v4_done:
		var s2: int = _ns_v4_probe.poll()
		if s2 == NetProbeScript.ST_FAIL and _ns_v4_i + 1 < NS_V4.size():
			_ns_v4_i += 1
			_ns_v4_probe = NetProbeScript.new()
			_ns_v4_probe.start(NS_V4[_ns_v4_i], NS_PORT)
			s2 = _ns_v4_probe.state
		if s2 != NetProbeScript.ST_CONNECTING:
			_ns_v4_done = true
			_net_v4_lbl.text = "IPv4 出网（%s）：%s" % [NS_V4[_ns_v4_i], _ns_v4_probe.status_text()]
			_net_v4_lbl.modulate = _ns_color(s2)

func _ns_color(s: int) -> Color:
	if s == NetProbeScript.ST_OK:
		return Color(0.42, 0.82, 0.45)
	if s == NetProbeScript.ST_FAIL:
		return Color(0.90, 0.42, 0.45)
	return UIKit.TEXT_DIM

## 把弹窗里全部控件刷成当前 `_set_*` 值。
##
## 只在**打开弹窗时**调（`_on_open_settings`）—— 原先预设 chip 一键填之后也调一次，
## **预设方案已整段删除**（用户 2026-10-09：改为「每次开新的一局都从默认值起、房主自行调整」，
## 见 `net.host_game()` 里那次重置）。
func _sync_panel() -> void:
	_set_cash_edit.text = str(_read_num(_set_cash_edit))
	_set_salary_edit.text = str(_read_num(_set_salary_edit))
	_set_wincash_edit.text = str(_read_num(_set_wincash_edit))
	# 开关注：`animate = false` —— 打开弹窗时滑块直接落位，不该自己滑一遍
	_set_liq_sw.set_on(_set_liq, false)
	_set_shop_sw.set_on(_set_shop, false)
	_set_black_sw.set_on(_set_black, false)
	_set_casino_sw.set_on(_set_casino, false)
	_set_tech_sw.set_on(_set_tech, false)
	_set_ab_cond_sw.set_on(_set_ab_cond, false)
	UIKit.chip_select(_set_rounds_chips, "none" if _set_rounds == 0 else str(_set_rounds))
	UIKit.chip_select(_set_win_chips, _set_win)
	UIKit.chip_select(_set_tech_tier_chips, _set_tech_tier)
	UIKit.chip_select(_set_chips, _set_tier)
	UIKit.chip_select(_set_ab_chips, _set_ab_freq)
	UIKit.chip_select(_set_ab_dur_chips, str(_set_ab_dur))
	_sync_conditional_rows()

## 条件显隐（用户 2026-10-09）：跟着主选项走的两块。
##   * **目标现金金额**：仅 `_set_win == "cash"` 时显示；
##   * **科技等级选择**：仅 `_set_tech` 打开时显示。
## 三个调用点：开弹窗（`_sync_panel()`）、点胜利条件 chip、拨科技开关 —— 都要过这里，
## 否则关了弹窗再开、或先改主选项，副项会停在上一轮的状态。
func _sync_conditional_rows() -> void:
	_set_wincash_row.visible = _set_win == "cash"
	_set_tech_tier_box.visible = _set_tech

## LineEdit 只留数字（防空串 / 杂字符进 int 解析）
func _read_num(edit: LineEdit) -> int:
	var s := ""
	for c in edit.text:
		if c >= "0" and c <= "9":
			s += c
	return int(s) if s != "" else 0

## 「开始游戏！」：直接开局。设置改由旁边的「游戏设置」按钮负责
func _on_start() -> void:
	if not multiplayer.is_server():
		return
	Net.start_game()

## 「游戏设置」：打开设置弹窗（每次打开都从**当前配置**同步一遍）。
## **这份"当前配置"在一局新游戏开始时是默认值** —— `Net.host_game()` 每次开房都把
## `game_settings` 重置成一份新的 `GameSettings`（用户 2026-10-09：预设方案删掉，改成
## 「每次开新的一局都展示默认数值 / 开关，房主自行调整」）。同一局里反复开弹窗回显的是
## 房主刚存的配置，方便复核；对局结束回主菜单、再开房 ⇒ 又是默认值。
func _on_open_settings() -> void:
	if not multiplayer.is_server():
		return
	var gs := Net.game_settings
	_set_tier = gs.timeout_tier
	_set_tech = gs.tech_on
	_set_tech_tier = gs.tech_tier
	_set_liq = gs.liq_on
	_set_rounds = gs.max_rounds
	_set_win = gs.win_mode
	_set_shop = gs.shop_on
	_set_black = gs.black_on
	_set_casino = gs.casino_on
	_set_ab_freq = gs.ab_freq
	_set_ab_dur = gs.ab_dur
	_set_ab_cond = gs.ab_cond
	_set_cash_edit.text = str(gs.start_cash)
	_set_salary_edit.text = str(gs.start_salary)
	_set_wincash_edit.text = str(gs.win_cash)
	_sync_panel()
	_set_wrap.visible = true

## 弹窗「确定」：写回 + 钳制 + 关闭
func _on_settings_save() -> void:
	var gs := Net.game_settings
	gs.timeout_tier = _set_tier
	gs.tech_on = _set_tech
	gs.tech_tier = _set_tech_tier
	gs.liq_on = _set_liq
	gs.max_rounds = _set_rounds
	gs.win_mode = _set_win
	gs.shop_on = _set_shop
	gs.black_on = _set_black
	gs.casino_on = _set_casino
	gs.ab_freq = _set_ab_freq
	gs.ab_dur = _set_ab_dur
	gs.ab_cond = _set_ab_cond
	gs.start_cash = _read_num(_set_cash_edit)
	gs.start_salary = _read_num(_set_salary_edit)
	gs.win_cash = _read_num(_set_wincash_edit)
	gs.clamp_all()
	_set_wrap.visible = false

func _on_leave() -> void:
	Net.leave()
	Fx.go_to("res://scenes/main_menu.tscn")

func _on_conn_lost(reason: String) -> void:
	Net.last_error = reason
	# 与对局场景同理：房主暂停中掉线时，新菜单会继承 paused 而完全无响应
	get_tree().paused = false
	Engine.time_scale = 1.0
	Fx.go_to("res://scenes/main_menu.tscn")

func _send_chat() -> void:
	Net.send_chat(_chat_edit.text)
	_chat_edit.clear()

func _refresh_chat() -> void:
	if _chat_box == null:
		return
	_chat_box.clear()
	for line in Net.chat_history:
		_chat_box.append_text(line.replace("[", "［") + "\n")

# ---------------- 自动化测试钩子 ----------------

func _autotest_host() -> void:
	await get_tree().create_timer(1.0).timeout
	# 先等真人客户端加入（最多 12 秒），再补机器人
	var waited := 0.0
	var humans := 0
	while waited < 12.0:
		humans = 0
		for p in Net.players:
			if not bool(p.bot):
				humans += 1
		if humans >= 2:
			break
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	print("AUTOTEST LOBBY humans=", humans)
	while Net.players.size() < Net.MAX_PLAYERS:
		Net.host_add_bot()
		await get_tree().create_timer(0.2).timeout
	var waited2 := 0.0
	while waited2 < 15.0:
		if Net.can_start():
			break
		await get_tree().create_timer(0.5).timeout
		waited2 += 0.5
	if Net.can_start():
		print("AUTOTEST LOBBY START players=", Net.players.size())
		Net.start_game()
	else:
		print("AUTOTEST HOST LOBBY FAIL")
		get_tree().quit(1)

func _autotest_client() -> void:
	await get_tree().create_timer(1.5).timeout
	if Net.players.is_empty():
		print("AUTOTEST CLIENT LOBBY EMPTY")
		get_tree().quit(1)
		return
	Net.toggle_ready()
	print("AUTOTEST CLIENT READY")

## 大厅截图：需要先 host_game，再 --shot=路径
func _shot() -> void:
	for i in 3:
		Net.host_add_bot()
	Net.chat_history = ["房主：开了开了，都进来", "机器人A：来了来了"]
	_refresh_chat()
	if _shot_path.contains("settings"):
		_on_open_settings()   # 摆拍：打开「游戏设置」弹窗（含操作限时 + 科技开关）
		# 文件名再带 `_end` ⇒ 顺手把滚动区拉到底，用来拍**下半截**（道具/科技/畸变那几节）。
		# 弹窗内容比 520 高的滚动区多，一张图拍不全 —— 与游戏侧那些按文件名分支的摆拍同例。
		# ⚠ 得先等一帧布局落定，否则滚动区还不知道自己有多少内容，`scroll_vertical` 会被夹回 0。
		if _shot_path.contains("settings_end"):
			await get_tree().create_timer(0.4).timeout
			_set_scroll.scroll_vertical = 100000
	elif _shot_path.contains("netself"):
		_on_open_netself()    # 摆拍：打开「网络自检」弹窗（fix/0.14.1）
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot_path)
	print("SHOT SAVED ", _shot_path)
	get_tree().quit(0)
