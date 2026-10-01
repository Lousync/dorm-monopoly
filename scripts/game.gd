extends Control
## 对局场景。房主是权威服务器：回合推进、掷骰、结算都在房主侧计算，
## 通过 s_* RPC 广播状态快照与动画事件；客户端通过 c_* RPC 上报操作。
##
## 表现层：56 格棋盘（缩放/平移/自动跟随）、中央转盘与事件卡抽卡动画、
## 金额飘字与滚动、聊天并入战报、结算排名 + 彩带、程序合成音效。

signal roll_received

const STEP_TIME := 0.15   # 每格跳子时长

# ---------------- UI 引用 ----------------
var board: BoardView
var card_panel: PanelContainer
var card_label: Label
var status_label: Label
var roll_btn: Button
var mat_bar: PanelContainer
var ph1_lab: Label
var ph2_lab: Label
var log_head: Label
var opt_btn: Button
var menu_layer: Control
var menu_panel: PanelContainer
var menu_state: Label
var settings_panel: PanelContainer
var confirm_panel: PanelContainer
var confirm_note: Label
var vol_slider: HSlider
var mute_check: CheckButton
var pause_mask: ColorRect
var audio_volume := 1.0
var audio_mute := false

# ---------------- 道具系统（host 状态，详见 docs/道具系统设计.md） ----------------
var shops := {}            # tile_idx -> {slots: [id×3]}，每家小卖部独立货架
var refresh_count := 0     # 小卖部全局刷新次数（任何人刷新都让全场变贵，整局不重置）
var _shop_peer := 0        # 正在逛小卖部的玩家（0 = 无）
var _shop_tile := -1
var _shop_epoch := 0
var _awaiting_item := 0    # 道具阶段行动者（0 = 无）
var _item_epoch := 0
var _item_action := {}
var item_btn_box: HBoxContainer
var ph1_pill: Control
var ph2_pill: Control
var ph_arrow_l: Label
var cheat_picker: Control
var cheat_slot := -1
var shop_bar: PanelContainer
var shop_btns: Array = []
var shop_refresh_btn: Button
var card_gallery: Control
var card_gallery_flag := false

# ---------------- 开发者模式 ----------------
var dev_enabled := false
var dev_panel: PanelContainer
var dev_state_l: Label
var dev_cam_l: Label
var dev_players: HBoxContainer
var dev_pbtns: Array = []
var dev_sel_peer := 0
var dev_item_opt: OptionButton
var dev_item_desc: Label
var dev_stam_s: HSlider
var dev_tp_spin: SpinBox
var dev_roll_spin: SpinBox
var dev_ts_l: Label
var dev_inject_box: VBoxContainer
var menu_probe := false
var info_panel: PanelContainer
var info_title: Label
var info_body: Label
var info_sb: StyleBoxFlat
var log_text: RichTextLabel
var log_panel: PanelContainer
var log_toggle: Button
var chat_edit: LineEdit
var over_layer: Control

# ---------------- 同步状态（所有端） ----------------
var st := {}
var my_peer := 1

# ---------------- 房主权威 ----------------
var hp: Array = []          # 玩家 [{peer,name,color,bot,money,pos,alive,skip}]
var htiles: Array = []      # 地块 [{owner,level}]
var turn_i := 0
var round_no := 1
var running := false
var winner := -1
var _awaiting_roll := 0
var _awaiting_prompt := 0
var _pending_token := 0
var _decision := {"token": -1, "yes": false}
var _prompt_kind := ""
var _prompt_amount := 0
var _over_shown := false
var _card_tween_id := 0
var _roll_epoch := 0
var _shot_path := ""
var _shot_taken := false
var _shot_rot := 0

# ---------------- 表现层状态 ----------------
var _player_rows := {}      # peer -> {root,sb,chip,name_l,money_l,shown,tw}
var _chat_shown := 0
var _prompt_dlg: Control
var _prompt_tw: Tween
var _prompt_token := -1

# ---------------- 赌桌小游戏（炸弹猫） ----------------
const CASINO_STAKE := 800
var _casino_epoch := 0
var _casino_action := {"epoch": -1, "action": ""}
var _casino_layer: Control
var _casino_log: RichTextLabel
var _casino_pot_label: Label
var _casino_deck_label: Label
var _casino_status: Label
var _casino_rows := {}          # peer -> {root, sb, defuse_l, fish_l}
var _casino_btn_peek: Button
var _casino_btn_top: Button
var _casino_btn_bottom: Button
var _casino_my_epoch := -1
var _casino_table_pot := 0        # 桌面赌场设施显示中的奖池
var _casino_order: Array = []

# ---------------- 自动化测试 ----------------
var at_mode := ""
var at_rounds := 3
var _at_roll_epoch := -1

func _ready() -> void:
	my_peer = multiplayer.get_unique_id()
	var dev_flag := false
	for a in OS.get_cmdline_user_args():
		if a == "--dev":
			dev_flag = true
		if a.begins_with("--autotest="):
			at_mode = a.substr(11)
		elif a.begins_with("--rounds="):
			at_rounds = maxi(1, int(a.substr(9)))
		elif a.begins_with("--max-rounds="):
			GameData.MAX_ROUNDS = maxi(1, int(a.substr(13)))
		elif a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-rot="):
			_shot_rot = clampi(int(a.substr(11)), 0, 3)
	if at_mode != "":
		Engine.time_scale = 3.0

	_build_ui()

	if multiplayer.is_server():
		_host_setup()
	else:
		status_label.text = "等待房主同步状态…"

	roll_btn.pressed.connect(_on_roll_pressed)
	Net.chat_received.connect(_refresh_chat)
	Net.connection_lost.connect(_on_conn_lost)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_chat_shown = Net.chat_history.size()
	_refresh_chat()
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		audio_volume = clampf(float(cfg.get_value("audio", "volume", 1.0)), 0.0, 1.0)
		audio_mute = bool(cfg.get_value("audio", "mute", false))
		dev_enabled = bool(cfg.get_value("dev", "enabled", false)) or dev_flag
	if at_mode != "" and not dev_flag:
		dev_enabled = false
	_apply_audio()
	_apply_dev_mode()
	for a2 in OS.get_cmdline_user_args():
		if a2 == "--menu-probe":
			menu_probe = true
	if menu_probe:
		_menu_probe_run()
	for a3 in OS.get_cmdline_user_args():
		if a3 == "--card-gallery":
			card_gallery_flag = true
	if card_gallery_flag:
		dev_enabled = true
		_apply_dev_mode()
		_open_card_gallery()

func _exit_tree() -> void:
	if at_mode != "":
		Engine.time_scale = 1.0

# ================= 界面构建 =================

func _build_ui() -> void:
	# 纯渐变氛围底（棋盘外露出的部分），不撒尘埃保持棋盘清晰
	add_child(UIKit.decor_bg(false))

	# 棋盘视口：整屏（四座在桌面世界四周，镜头避开顶栏与底部行动条）
	board = BoardView.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.overlay_top = 46
	board.overlay_bottom = 70
	add_child(board)
	board.tile_clicked.connect(_on_tile_clicked)
	board.seat_clicked.connect(func(peer: int) -> void:
		if peer == my_peer:
			board.go_home_follow(my_peer)  # 点自己座位卡：回自己视角并恢复镜头跟随
	)

	# 悬浮事件卡（非牌堆提示，屏幕空间不随视角旋转）
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)

	card_panel = UIKit.panel_container(Color(0.16, 0.14, 0.08, 0.94), 12, UIKit.ACCENT, 2, 10)
	card_panel.position = Vector2(12, 54)
	card_panel.size = Vector2(430, 96)
	card_panel.visible = false
	card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(card_panel)
	var cm := UIKit.margins(16, 14, 8, 8)
	cm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_panel.add_child(cm)
	card_label = UIKit.label("", 15, UIKit.ACCENT)
	card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cm.add_child(card_label)


	# 牌垫阶段条（屏幕层，锚定自己座位卡下沿）：状态 / 回合两阶段 / 转动转盘
	mat_bar = UIKit.panel_container(Color(0.058, 0.062, 0.098, 0.88), 12,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.55), 1, 6)
	mat_bar.custom_minimum_size = Vector2(440, 46)
	mat_bar.visible = false
	add_child(mat_bar)
	var mbm := UIKit.margins(12, 10, 7, 7)
	mat_bar.add_child(mbm)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	mbm.add_child(mrow)
	status_label = UIKit.label("", 13, UIKit.TEXT)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mrow.add_child(status_label)
	var ph1 := UIKit.pill("① 转轮盘", UIKit.TEXT_DIM, 11)
	mrow.add_child(ph1)
	var ph_arrow := UIKit.label("→", 12, UIKit.TEXT_DIM)
	mrow.add_child(ph_arrow)
	var ph2 := UIKit.pill("② 使用道具", UIKit.TEXT_DIM, 11)
	mrow.add_child(ph2)
	ph1_lab = _pill_label(ph1)
	ph2_lab = _pill_label(ph2)
	ph1_pill = ph1
	ph2_pill = ph2
	ph_arrow_l = ph_arrow
	roll_btn = UIKit.button("转动转盘", 15, "normal")
	roll_btn.disabled = true
	mrow.add_child(roll_btn)
	item_btn_box = HBoxContainer.new()
	item_btn_box.add_theme_constant_override("separation", 6)
	item_btn_box.visible = false
	mrow.add_child(item_btn_box)

	# 小卖部操作条（行动者的屏幕层按钮；货架公开显示在桌面设施上）
	shop_bar = UIKit.panel_container(Color(0.058, 0.062, 0.098, 0.88), 12,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.55), 1, 6)
	shop_bar.custom_minimum_size = Vector2(440, 46)
	shop_bar.visible = false
	add_child(shop_bar)
	var sbm := UIKit.margins(10, 8, 7, 7)
	shop_bar.add_child(sbm)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	sbm.add_child(srow)
	shop_btns = []
	for i in 3:
		var b := UIKit.button("买", 12)
		b.visible = false
		var si := i
		b.pressed.connect(func() -> void:
			if multiplayer.is_server():
				_shop_buy(my_peer, si)
			else:
				c_shop_buy.rpc(si)
		)
		srow.add_child(b)
		shop_btns.append(b)
	shop_refresh_btn = UIKit.button("刷新", 12)
	shop_refresh_btn.pressed.connect(func() -> void:
		if multiplayer.is_server():
			_shop_refresh(my_peer)
		else:
			c_shop_refresh.rpc()
	)
	srow.add_child(shop_refresh_btn)
	var leave_btn := UIKit.button("离开", 12)
	leave_btn.pressed.connect(func() -> void:
		if multiplayer.is_server():
			_shop_leave(my_peer)
		else:
			c_shop_leave.rpc()
	)
	srow.add_child(leave_btn)

	# 左上角：选项按钮（打开暂停菜单族，见 _build_menu_ui）
	opt_btn = UIKit.button("☰ 选项", 13)
	opt_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	opt_btn.offset_left = 12
	opt_btn.offset_top = 10
	opt_btn.offset_right = 92
	opt_btn.offset_bottom = 38
	opt_btn.pressed.connect(_open_menu)
	add_child(opt_btn)
	_build_menu_ui()

	# 开发者模式面板（左侧；注入区仅房主可见）
	dev_panel = UIKit.panel_container(Color(0.05, 0.06, 0.1, 0.94), 12, Color(0.45, 0.85, 0.55, 0.5), 1)
	dev_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	dev_panel.offset_left = 8
	dev_panel.offset_top = 56
	dev_panel.offset_right = 276
	dev_panel.offset_bottom = 720
	dev_panel.visible = false
	add_child(dev_panel)
	var dm := UIKit.margins(10, 12, 10, 10)
	dev_panel.add_child(dm)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	dm.add_child(dv)
	dv.add_child(UIKit.label("开发者模式（F1 显隐）", 13, Color(0.5, 0.9, 0.5)))
	dev_state_l = UIKit.label("", 11, UIKit.TEXT)
	dv.add_child(dev_state_l)
	dev_cam_l = UIKit.label("", 11, UIKit.TEXT_DIM)
	dv.add_child(dev_cam_l)
	dv.add_child(UIKit.label("玩家（点选后注入）", 11, UIKit.TEXT_DIM))
	dev_players = HBoxContainer.new()
	dev_players.add_theme_constant_override("separation", 4)
	dv.add_child(dev_players)
	dev_inject_box = VBoxContainer.new()
	dev_inject_box.add_theme_constant_override("separation", 5)
	dv.add_child(dev_inject_box)
	var mrow1 := HBoxContainer.new()
	mrow1.add_theme_constant_override("separation", 4)
	dev_inject_box.add_child(mrow1)
	for amt in [["+1千", 1000], ["+1万", 10000], ["-1千", -1000]]:
		var ab := UIKit.button(String(amt[0]), 11)
		var av: int = amt[1]
		ab.pressed.connect(func() -> void: _dev_add_money(av))
		mrow1.add_child(ab)
	var irow := HBoxContainer.new()
	irow.add_theme_constant_override("separation", 4)
	dev_inject_box.add_child(irow)
	dev_item_opt = OptionButton.new()
	for id in ItemData.ITEMS:
		dev_item_opt.add_item(id)
	dev_item_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dev_item_opt.item_selected.connect(func(_i: int) -> void: _dev_item_desc_update())
	irow.add_child(dev_item_opt)
	dev_item_desc = UIKit.label("", 10, UIKit.TEXT_DIM)
	dev_item_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dev_item_desc.custom_minimum_size = Vector2(0, 26)
	dev_inject_box.add_child(dev_item_desc)
	var irow2 := HBoxContainer.new()
	irow2.add_theme_constant_override("separation", 4)
	dev_inject_box.add_child(irow2)
	var give_btn := UIKit.button("发放", 11)
	give_btn.pressed.connect(_dev_grant_item)
	irow2.add_child(give_btn)
	var use_btn := UIKit.button("强制使用", 11)
	use_btn.pressed.connect(_dev_force_use)
	irow2.add_child(use_btn)
	var clear_bag := UIKit.button("清背包", 11)
	clear_bag.pressed.connect(func() -> void: _dev_player_edit(func(p: Dictionary) -> void: p.items = []))
	irow2.add_child(clear_bag)
	var dsrow := HBoxContainer.new()
	dsrow.add_theme_constant_override("separation", 4)
	dev_inject_box.add_child(dsrow)
	dsrow.add_child(UIKit.label("体力", 11, UIKit.TEXT_DIM))
	dev_stam_s = HSlider.new()
	dev_stam_s.min_value = 0
	dev_stam_s.max_value = 5
	dev_stam_s.step = 1
	dev_stam_s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dev_stam_s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dsrow.add_child(dev_stam_s)
	var cds_btn := UIKit.button("清冷却", 11)
	cds_btn.pressed.connect(func() -> void: _dev_player_edit(func(p: Dictionary) -> void:
		for it in p.get("items", []):
			it.cd = 0
	))
	dsrow.add_child(cds_btn)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 4)
	dev_inject_box.add_child(trow)
	trow.add_child(UIKit.label("传送格", 11, UIKit.TEXT_DIM))
	dev_tp_spin = SpinBox.new()
	dev_tp_spin.min_value = 0
	dev_tp_spin.max_value = int(GameData.TILES.size()) - 1
	dev_tp_spin.custom_minimum_size = Vector2(64, 0)
	trow.add_child(dev_tp_spin)
	var tp_btn := UIKit.button("传送", 11)
	tp_btn.pressed.connect(func() -> void: _dev_player_edit(func(p: Dictionary) -> void: p.pos = int(dev_tp_spin.value)))
	trow.add_child(tp_btn)
	trow.add_child(UIKit.label("点数", 11, UIKit.TEXT_DIM))
	dev_roll_spin = SpinBox.new()
	dev_roll_spin.min_value = 0
	dev_roll_spin.max_value = 12
	dev_roll_spin.custom_minimum_size = Vector2(56, 0)
	trow.add_child(dev_roll_spin)
	var fr_btn := UIKit.button("强制", 11)
	fr_btn.pressed.connect(func() -> void: _dev_player_edit(func(p: Dictionary) -> void: p.cheat_roll = int(dev_roll_spin.value)))
	trow.add_child(fr_btn)
	var erow := HBoxContainer.new()
	erow.add_theme_constant_override("separation", 4)
	dev_inject_box.add_child(erow)
	var end_btn := UIKit.button("结束当前等待", 11)
	end_btn.pressed.connect(_dev_end_wait)
	erow.add_child(end_btn)
	erow.add_child(UIKit.label("时间倍率", 11, UIKit.TEXT_DIM))
	for ts in [[".25", 0.25], ["1", 1.0], ["4", 4.0], ["8", 8.0]]:
		var tb := UIKit.button(String(ts[0]), 11)
		var tv: float = ts[1]
		tb.pressed.connect(func() -> void:
			Engine.time_scale = tv
			_dev_ts_update()
		)
		erow.add_child(tb)
	dev_ts_l = UIKit.label("当前 1x", 11, UIKit.TEXT_DIM)
	erow.add_child(dev_ts_l)
	var gal_btn := UIKit.button("道具卡图鉴", 11)
	gal_btn.pressed.connect(_open_card_gallery)
	dev_inject_box.add_child(gal_btn)
	if not multiplayer.is_server():
		dev_inject_box.visible = false  # 客户端：仅观察

	# 左下角：格子详情卡（点击棋盘格子弹出相关信息）
	info_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 6)
	info_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	info_panel.offset_left = 14
	info_panel.offset_right = 356
	info_panel.offset_top = -196
	info_panel.offset_bottom = -66
	add_child(info_panel)
	info_sb = UIKit.stylebox(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1)
	info_panel.add_theme_stylebox_override("panel", info_sb)
	var im := UIKit.margins(12, 10, 10, 10)
	info_panel.add_child(im)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 5)
	im.add_child(iv)
	info_title = UIKit.label("操作提示", 16, UIKit.ACCENT)
	iv.add_child(info_title)
	info_body = UIKit.label("滚轮缩放 · 拖拽平移 · 点格子看详情\n点对手座位卡或按 Tab 转到 TA 视角 · 空格回自己", 13, UIKit.TEXT)
	info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(info_body)

	# 右上：战报 / 聊天（可折叠，保持桌面干净）
	log_toggle = UIKit.button("战报 ▴", 13)
	log_toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_toggle.offset_left = -106
	log_toggle.offset_right = -12
	log_toggle.offset_top = 12
	log_toggle.offset_bottom = 40
	log_toggle.pressed.connect(_toggle_log)
	add_child(log_toggle)

	log_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 6)
	log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_panel.offset_left = -352
	log_panel.offset_right = -12
	log_panel.offset_top = 46
	log_panel.offset_bottom = 780
	log_panel.visible = true
	add_child(log_panel)
	var lm := UIKit.margins(10, 10, 8, 8)
	log_panel.add_child(lm)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	lm.add_child(lv)
	log_head = UIKit.label("第 1/30 轮 · 战报", 13, UIKit.TEXT_DIM)
	lv.add_child(log_head)
	log_text = RichTextLabel.new()
	log_text.scroll_following = true
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.add_theme_font_size_override("normal_font_size", 13)
	lv.add_child(log_text)
	var chat_row := HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 6)
	lv.add_child(chat_row)
	chat_edit = UIKit.line_edit("聊天…（回车发送）")
	chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_edit.text_submitted.connect(func(_t: String) -> void:
		Net.send_chat(chat_edit.text)
		chat_edit.clear()
	)
	chat_row.add_child(chat_edit)
	var send_btn := UIKit.button("发送", 14)
	send_btn.pressed.connect(func() -> void:
		Net.send_chat(chat_edit.text)
		chat_edit.clear()
	)
	chat_row.add_child(send_btn)

# ================= 房主：初始化与主循环 =================

func _host_setup() -> void:
	running = true
	hp = []
	for p in Net.players:
		hp.append({
			"peer": int(p.peer), "name": String(p.name), "color": int(p.color),
			"bot": bool(p.bot), "money": GameData.START_MONEY,
			"pos": 0, "alive": true, "skip": 0,
			"stamina": 3, "items": [], "item_used": false, "cheat_roll": -1,
		})
	htiles = []
	for i in GameData.TILES.size():
		htiles.append({"owner": GameData.NO_OWNER, "level": 0})
	shops = {}
	refresh_count = 0
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "shop":
			shops[i] = {"slots": ["", "", ""]}
			_stock_shop(i)
	_log("游戏开始！每人初始资金 %s，踏上起点领工资 %s" % [
		GameData.fmt_money(GameData.START_MONEY), GameData.fmt_money(GameData.SALARY)], "#f0c064")
	_log("转盘决定步数（0~12）：转到 12 满值再动一次；连续三次 10+ 会被查寝抓走哦")
	await _wait(1.5)
	_broadcast_state()
	if at_mode == "host":
		get_tree().create_timer(3.0).timeout.connect(_autotest_watch)
	_run_game()

func _autotest_watch() -> void:
	# 房主在到达目标轮数后稍等片刻再退出，给客户端留出收尾时间；
	# 结算截图（shot 未拍出）时多等一会儿，避免提前退出截断保存
	while running and round_no < at_rounds:
		await _wait(0.5)
	if _shot_path != "" and not _shot_taken:
		await _wait(6.0)
	if not running or round_no >= at_rounds:
		await _wait(2.0)
		print("AUTOTEST HOST OK round=", round_no)
		get_tree().quit(0)

func _run_game() -> void:
	await _wait(0.3)
	while running:
		var p: Dictionary = hp[turn_i]
		if not bool(p.alive):
			_advance_turn()
			continue
		if int(p.skip) > 0:
			p.skip = int(p.skip) - 1
			_log("%s 在宿委会反省，跳过本回合" % p.name, "#c9a6ff")
			_broadcast_state()
			await _wait(1.0)
			if not running:
				return
			_advance_turn()
			continue
		await _play_turn(p)
		if not running:
			return
		_advance_turn()
		if turn_i == 0:
			round_no += 1
			if round_no > GameData.MAX_ROUNDS:
				_end_by_wealth()
				return

func _advance_turn() -> void:
	for k in hp.size():
		turn_i = (turn_i + 1) % hp.size()
		if bool(hp[turn_i].alive):
			break

func _play_turn(p: Dictionary) -> void:
	if at_mode != "":
		print("AT turn start: r%d %s" % [round_no, p.name])
	_item_turn_start(p)
	_broadcast_state()
	var chain := 0
	while running:
		_awaiting_roll = int(p.peer)
		_roll_epoch += 1
		var epoch := _roll_epoch
		_broadcast_state()
		if bool(p.bot):
			_bot_roll_later()
		else:
			_arm_roll_timeout(epoch, int(p.peer))
		await roll_received
		if not running:
			return
		_awaiting_roll = 0

		var roll := randi_range(0, 12)
		if int(p.get("cheat_roll", -1)) >= 0:
			roll = clampi(int(p.cheat_roll), 0, 12)
			p.cheat_roll = -1
			_log("%s 掏出【作弊器】——这次转盘他说了算" % p.name, "#8fb7f2")
		if at_mode != "":
			print("AT roll %s: %d" % [p.name, roll])
		s_roll.rpc(roll)
		await _wait(WheelView.SPIN_TIME + 0.15)
		if not running:
			return

		if roll >= 10:
			chain += 1
			if chain >= 3:
				_log("%s 连续三次转到 10 点以上，兴奋过度被查寝带走！" % p.name, "#c9a6ff")
				s_card.rpc("%s 连续三次 10+，被查寝带走！" % p.name, "jail")
				_send_to_jail(p)
				_broadcast_state()
				await _wait(1.0)
				return
		else:
			chain = 0

		var path := GameData.compute_path(int(p.pos), roll)
		if path.is_empty():
			_log("%s 转了个 0，原地待命一回合" % p.name, "#8a90a5")
			break  # 待命也算完成投掷，仍可用道具
		for idx in path:
			if idx == 0:
				p.money = int(p.money) + GameData.SALARY
				_log("%s 踏上起点，领取工资 %s" % [p.name, GameData.fmt_money(GameData.SALARY)], "#74d188")
		p.pos = path[path.size() - 1]
		s_move.rpc(int(p.peer), path, STEP_TIME)
		await _wait(0.35 + path.size() * STEP_TIME)
		if not running:
			return

		await _resolve_tile(p)
		_broadcast_state()
		if not running or not bool(p.alive):
			return
		if roll == 12:
			_log("%s 转到 12 满值，奖励再动一次！" % p.name, "#f0c064")
			await _wait(0.5)
			continue
		break
	if not running:
		return
	await _item_phase(p)

## 真人玩家发呆太久由系统代掷，避免整局卡死
func _arm_roll_timeout(epoch: int, peer: int) -> void:
	await _wait(GameData.ROLL_TIMEOUT)
	if running and _roll_epoch == epoch and _awaiting_roll == peer:
		var pl := _player_by_peer(peer)
		_log("%s 发呆太久，系统代掷一步" % String(pl.get("name", "?")), "#8a90a5")
		roll_received.emit()

func _bot_roll_later() -> void:
	await _wait(0.8)
	if running and _awaiting_roll != 0:
		roll_received.emit()

# ================= 房主：结算 =================

func _resolve_tile(p: Dictionary) -> void:
	var idx := int(p.pos)
	var d: Dictionary = GameData.TILES[idx]
	match String(d.type):
		"property":
			var t: Dictionary = htiles[idx]
			if int(t.owner) == GameData.NO_OWNER:
				await _resolve_buy(p, idx)
			elif int(t.owner) == int(p.peer):
				await _resolve_upgrade(p, idx)
			else:
				await _resolve_rent(p, idx)
		"event":
			var card: Dictionary = GameData.EVENTS.pick_random()
			# 仿桌游：机会/命运卡从棋盘中央对应牌堆抽出展示
			s_card.rpc(String(card.t), _card_kind(card), String(d.name))
			_log("%s 抽到事件：%s" % [p.name, card.t])
			await _wait(BoardView.DECK_CARD_TIME + 0.1)
			await _apply_card(p, card)
		"fine":
			_log("%s 落在【%s】，被强制缴费 %s" % [p.name, d.name, GameData.fmt_money(int(d.amount))], "#ef7b74")
			s_card.rpc("【%s】强制缴费 %s" % [d.name, GameData.fmt_money(int(d.amount))], "bad")
			await _wait(0.6)
			_pay(p, int(d.amount), {})
		"bonus":
			p.money = int(p.money) + int(d.amount)
			_log("%s 在【%s】赚到 %s" % [p.name, d.name, GameData.fmt_money(int(d.amount))], "#74d188")
		"shop":
			await _run_shop(p, idx)
		"casino":
			_log("%s 踏进【宿舍赌场】，全员开赌！" % p.name, "#f0a0c0")
			await _run_casino(p)
		"go_jail":
			_log("%s 撞上查寝！被押送到宿委会" % p.name, "#c9a6ff")
			s_card.rpc("【查寝！】%s 被押送到宿委会" % p.name, "jail")
			_send_to_jail(p)
		"jail":
			_log("%s 来宿委会探监，一切安好" % p.name)
		"rest":
			_log("%s 在【%s】歇了口气，无事发生" % [p.name, d.name])
		"start":
			_log("%s 恰好停在起点，工资已到账！" % p.name, "#74d188")
	if not bool(p.alive):
		_check_end()

func _card_kind(card: Dictionary) -> String:
	if card.has("go_jail"):
		return "jail"
	if card.has("move_steps"):
		return "move"
	if card.has("money"):
		return "good" if int(card.money) >= 0 else "bad"
	if card.has("from_each"):
		return "good"
	if card.has("to_each"):
		return "bad"
	return "info"

func _resolve_buy(p: Dictionary, idx: int) -> void:
	var d: Dictionary = GameData.TILES[idx]
	if int(p.money) < int(d.price):
		_log("%s 的现金买不起【%s】，只能眼馋路过" % [p.name, d.name])
		return
	var ok := await _ask(p, "buy", int(d.price), "购买地产",
		"要买下【%s】吗？\n售价 %s · 基础租金 %s\n你的现金 %s" % [
			d.name, GameData.fmt_money(int(d.price)), GameData.fmt_money(int(d.rent)), GameData.fmt_money(int(p.money))],
		"买下它！")
	if ok and running and int(p.money) >= int(d.price) and int(htiles[idx].owner) == GameData.NO_OWNER:
		p.money = int(p.money) - int(d.price)
		htiles[idx].owner = int(p.peer)
		_log("%s 以 %s 买下了【%s】" % [p.name, GameData.fmt_money(int(d.price)), d.name], "#f0c064")

func _resolve_upgrade(p: Dictionary, idx: int) -> void:
	var d: Dictionary = GameData.TILES[idx]
	var t: Dictionary = htiles[idx]
	var cost := GameData.upgrade_cost(idx)
	if int(t.level) >= GameData.MAX_LEVEL or int(p.money) < cost:
		return
	var next_rent := int(d.rent) * (2 + int(t.level))
	if _group_complete_for(idx, int(p.peer)):
		next_rent *= 2
	var ok := await _ask(p, "upgrade", cost, "升级地产",
		"要装修自己的【%s】吗？\nLv%d → Lv%d · 费用 %s\n升级后租金 %s" % [
			d.name, int(t.level), int(t.level) + 1, GameData.fmt_money(cost), GameData.fmt_money(next_rent)],
		"装修！")
	if ok and running and int(p.money) >= cost:
		p.money = int(p.money) - cost
		t.level = int(t.level) + 1
		_log("%s 花费 %s 把【%s】升级到 Lv%d" % [p.name, GameData.fmt_money(cost), d.name, int(t.level)], "#f0c064")

func _resolve_rent(p: Dictionary, idx: int) -> void:
	var d: Dictionary = GameData.TILES[idx]
	var rent := GameData.rent_for(idx, htiles)
	var op := _player_by_peer(int(htiles[idx].owner))
	if op.is_empty() or not bool(op.alive):
		return
	if _has_item(op, "招财猫"):
		rent += 50  # 【招财猫】：租金 +50
	_log("%s 闯进【%s】，付租金 %s 给 %s" % [p.name, d.name, GameData.fmt_money(rent), op.name], "#ef7b74")
	_pay(p, rent, op)

func _apply_card(p: Dictionary, card: Dictionary) -> void:
	if card.has("money"):
		var m := int(card.money)
		if m >= 0:
			p.money = int(p.money) + m
		else:
			_pay(p, -m, {})
	if card.has("from_each"):
		for o in hp:
			if int(o.peer) != int(p.peer) and bool(o.alive):
				var amt: int = mini(int(card.from_each), int(o.money))
				o.money = int(o.money) - amt
				p.money = int(p.money) + amt
	if card.has("to_each"):
		for o in hp:
			if int(o.peer) != int(p.peer) and bool(o.alive) and int(p.money) > 0:
				var amt2: int = mini(int(card.to_each), int(p.money))
				p.money = int(p.money) - amt2
				o.money = int(o.money) + amt2
	if card.has("go_jail"):
		_log("%s 被查寝抄了近道，直接送宿委会" % p.name, "#c9a6ff")
		_send_to_jail(p)
	if card.has("move_steps"):
		var path := GameData.compute_path_steps(int(p.pos), int(card.move_steps))
		for idx in path:
			if idx == 0:
				p.money = int(p.money) + GameData.SALARY
				_log("%s 顺路踏上起点，领工资 %s" % [p.name, GameData.fmt_money(GameData.SALARY)], "#74d188")
		if not path.is_empty():
			p.pos = path[path.size() - 1]
			s_move.rpc(int(p.peer), path, 0.09)
			await _wait(0.25 + path.size() * 0.09)
		# 移动后的落点照常结算
		await _resolve_tile(p)
	_check_end()

func _pay(p: Dictionary, amount: int, receiver: Dictionary) -> void:
	var paid: int = mini(amount, maxi(int(p.money), 0))
	p.money = int(p.money) - paid
	if not receiver.is_empty():
		receiver.money = int(receiver.money) + paid
	if paid < amount:
		p.alive = false
		p.money = 0
		for t in htiles:
			if int(t.owner) == int(p.peer):
				t.owner = GameData.NO_OWNER
				t.level = 0
		_log("%s 无力支付 %s，宣告破产出局！名下地产收归学校" % [p.name, GameData.fmt_money(amount)], "#ef7b74")
		s_card.rpc("%s 破产出局！" % p.name, "bust")

func _send_to_jail(p: Dictionary) -> void:
	p.pos = GameData.JAIL_TILE
	p.skip = 1
	s_tp.rpc(int(p.peer), GameData.JAIL_TILE)

@rpc("authority", "call_local", "reliable")
func s_tp(peer: int, idx: int) -> void:
	board.set_teleport_target(peer, idx)
	board.play_move(peer, [], 0.0)

func _group_complete_for(idx: int, owner: int) -> bool:
	var group: String = GameData.TILES[idx].group
	for i in GameData.TILES.size():
		if GameData.TILES[i].get("group", "") == group and int(htiles[i].owner) != owner:
			return false
	return true

func _player_by_peer(peer: int) -> Dictionary:
	for p in hp:
		if int(p.peer) == peer:
			return p
	return {}

func _check_end() -> void:
	var alive := hp.filter(func(x) -> bool: return bool(x.alive))
	if alive.size() <= 1:
		if alive.size() == 1:
			_end_game(int(alive[0].peer), "最后存活：%s！" % alive[0].name)
		else:
			_end_game(-1, "全员破产，学校赢麻了")

func _end_by_wealth() -> void:
	var alive := hp.filter(func(x) -> bool: return bool(x.alive))
	if alive.is_empty():
		_end_game(-1, "回合数耗尽，无人幸存")
		return
	alive.sort_custom(func(a, b) -> bool: return _net_worth(a) > _net_worth(b))
	_end_game(int(alive[0].peer), "%d 轮结算！最富有的是 %s（总资产 %s）" % [
		GameData.MAX_ROUNDS, alive[0].name, GameData.fmt_money(_net_worth(alive[0]))])

func _net_worth(p: Dictionary) -> int:
	var v := int(p.money)
	for i in htiles.size():
		if int(htiles[i].owner) == int(p.peer):
			v += int(GameData.TILES[i].price) + int(htiles[i].level) * GameData.upgrade_cost(i)
	return v

func _end_game(wpeer: int, line: String) -> void:
	running = false
	winner = wpeer
	_awaiting_roll = 0
	_awaiting_prompt = 0
	_log(line, "#f0c064")
	_broadcast_state()

# ================= 房主：交互 =================

## 掷骰：房主本地发信号；客户端走 RPC（此前按钮只查房主变量，客户端点了没反应）
func _on_roll_pressed() -> void:
	if String(st.get("await", "")) != "roll" or int(st.get("turn", -1)) != my_peer:
		return
	roll_btn.disabled = true  # 即时反馈，等下一次状态广播再恢复
	if multiplayer.is_server():
		if _awaiting_roll == my_peer:
			roll_received.emit()
	else:
		c_roll.rpc_id(1)

func _bot_decide(kind: String, amount: int, money: int) -> bool:
	if kind == "buy":
		return money - amount >= 2500
	if kind == "upgrade":
		return money - amount >= 3000
	return false

## 向目标玩家询问（房主弹窗 / 客户端 RPC / 机器人自动决策），超时视为拒绝
func _ask(p: Dictionary, kind: String, amount: int, title: String, text: String, ok_text: String) -> bool:
	if bool(p.bot):
		return _bot_decide(kind, amount, int(p.money))
	_pending_token += 1
	var tok := _pending_token
	_decision = {"token": -1, "yes": false}
	_awaiting_prompt = int(p.peer)
	_prompt_kind = kind
	_prompt_amount = amount
	_broadcast_state()
	if int(p.peer) == 1:
		_show_prompt(tok, title, text, ok_text)
	else:
		s_prompt.rpc_id(int(p.peer), tok, title, text, ok_text)
	var waited := 0.0
	while waited < GameData.PROMPT_TIMEOUT:
		await _wait(0.1)
		if not running:
			return false
		waited += 0.1
		if int(_decision.token) == tok:
			break
	_awaiting_prompt = 0
	if int(_decision.token) != tok:
		_log("%s 思考超时，放弃了" % p.name, "#8a90a5")
	return int(_decision.token) == tok and bool(_decision.yes)

func _answer(token: int, yes: bool) -> void:
	if multiplayer.is_server():
		_decision = {"token": token, "yes": yes}
	else:
		c_decision.rpc_id(1, token, yes)

@rpc("any_peer", "call_remote", "reliable")
func c_decision(token: int, yes: bool) -> void:
	if not multiplayer.is_server():
		return
	_decision = {"token": token, "yes": yes}

@rpc("any_peer", "call_remote", "reliable")
func c_roll() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == _awaiting_roll:
		roll_received.emit()

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server() or not running:
		return
	var found := false
	for p in hp:
		if int(p.peer) == id and not bool(p.bot):
			p.bot = true
			found = true
			_log("%s 掉线了，机器人接管他的回合" % p.name, "#8a90a5")
			break
	if not found:
		return
	if _awaiting_roll == id:
		_bot_roll_later()
	if _awaiting_prompt == id:
		# 立刻按机器人策略替他做决定，不让全场等 25 秒超时
		var pd := _player_by_peer(id)
		_decision = {"token": _pending_token, "yes": _bot_decide(_prompt_kind, _prompt_amount, int(pd.get("money", 0)))}
	_broadcast_state()

# ================= 房主：广播 =================

func _broadcast_state() -> void:
	if not multiplayer.is_server():
		return
	var plist := []
	for p in hp:
		plist.append({
			"peer": int(p.peer), "name": p.name, "color": int(p.color), "bot": bool(p.bot),
			"money": int(p.money), "pos": int(p.pos), "alive": bool(p.alive), "skip": int(p.skip),
			"stamina": int(p.get("stamina", 3)), "items": p.get("items", []),
			"item_used": bool(p.get("item_used", false)),
		})
	var await_state := ""
	var await_peer := -1
	if _awaiting_roll != 0:
		await_state = "roll"
		await_peer = _awaiting_roll
	elif _awaiting_prompt != 0:
		await_state = "prompt"
		await_peer = _awaiting_prompt
	elif _awaiting_item != 0:
		await_state = "item"
		await_peer = _awaiting_item
	elif _shop_peer != 0:
		await_state = "shop"
		await_peer = _shop_peer
	s_state.rpc({
		"phase": "ended" if not running else "playing",
		"round": round_no, "max_rounds": GameData.MAX_ROUNDS,
		"turn": int(hp[turn_i].peer),
		"await": await_state, "await_peer": await_peer,
		"players": plist, "tiles": htiles,
		"shops": shops, "refresh_price": _refresh_price(),
		"shop_open": (_shop_tile if _shop_peer != 0 else -1),
		"winner": winner, "roll_epoch": _roll_epoch,
	})

func _log(line: String, color: String = "#dfe3ee") -> void:
	var safe := line.replace("[", "［")
	if color != "#dfe3ee":
		safe = "[color=%s]%s[/color]" % [color, safe]
	s_log.rpc(safe)

# ================= 全员：接收 RPC =================

@rpc("authority", "call_local", "reliable")
func s_state(state: Dictionary) -> void:
	st = state
	board.render(state)
	board.set_shop_display(state.get("shops", {}), int(state.get("refresh_price", 0)),
		int(state.get("shop_open", -1)))
	log_head.text = "第 %d/%d 轮 · 战报" % [int(state.round), int(state.max_rounds)]
	_refresh_players()
	_refresh_actions()
	_refresh_chat()
	if String(state.phase) == "ended":
		_show_game_over()
		if at_mode != "" and not multiplayer.is_server():
			print("AUTOTEST CLIENT OK round=", state.round)
			get_tree().quit(0)
	elif _shot_path != "" and not _shot_taken and (int(state.round) >= 2 or at_mode == ""):
		_shot_taken = true
		_take_shot(_shot_path)
	elif at_mode != "" and not multiplayer.is_server() and int(state.round) >= at_rounds:
		print("AUTOTEST CLIENT OK round=", state.round)
		get_tree().quit(0)

@rpc("authority", "call_local", "reliable")
func s_roll(v: int) -> void:
	board.spin_wheel(v, int(st.get("turn", -1)))
	if v == 24 or v == 0:
		_flair_roll(v)

func _flair_roll(v: int) -> void:
	await get_tree().create_timer(WheelView.SPIN_TIME, false).timeout
	if not is_inside_tree():
		return
	if v == 24:
		Fx.float_text(self, board.wheel_screen_pos() + Vector2(0, -60), "满值 12！再来一次", UIKit.ACCENT, 21)
	elif v == 0:
		Fx.float_text(self, board.wheel_screen_pos() + Vector2(0, -60), "0……转了个寂寞", UIKit.TEXT_DIM, 19)

@rpc("authority", "call_local", "reliable")
func s_move(peer: int, path: Array, step_time: float) -> void:
	board.play_move(peer, path, step_time)

@rpc("authority", "call_local", "reliable")
func s_card(text: String, kind: String = "info", deck: String = "") -> void:
	Fx.play("card", -4.0)
	if deck != "":
		# 事件卡：从棋盘中央牌堆抽出，展示完镜头回到行动棋子
		board.play_deck_card(deck, kind, text, int(st.get("turn", -1)))
		if kind == "jail":
			Fx.shake(self, 9.0, 0.35)
			Fx.play("jail", -2.0)
		return
	var style: Array = UIKit.card_palette(kind)
	card_panel.add_theme_stylebox_override("panel", UIKit.card_stylebox(style[1], 12, style[0], 2, 10))
	card_label.text = text
	card_label.add_theme_color_override("font_color", style[0])
	card_panel.visible = true
	card_panel.pivot_offset = card_panel.size * 0.5
	card_panel.scale = Vector2(0.7, 0.7)
	card_panel.modulate.a = 0.0
	Fx.play("card", -4.0)
	_card_tween_id += 1
	var my_id := _card_tween_id
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card_panel, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card_panel, "modulate:a", 1.0, 0.16)
	tw.set_parallel(false)
	_hide_card_later(my_id)
	if kind == "jail":
		Fx.shake(self, 9.0, 0.35)
		Fx.play("jail", -2.0)
	elif kind == "bust":
		Fx.shake(self, 7.0, 0.3)
		Fx.play("bust", 0.0)

func _hide_card_later(my_id: int) -> void:
	await get_tree().create_timer(2.5, false).timeout
	if not is_inside_tree() or _card_tween_id != my_id:
		return
	var tw := create_tween()
	tw.tween_property(card_panel, "modulate:a", 0.0, 0.25)
	await tw.finished
	if _card_tween_id == my_id:
		card_panel.visible = false
		card_panel.modulate.a = 1.0

@rpc("authority", "call_local", "reliable")
func s_log(line: String) -> void:
	log_text.append_text(line + "\n")

@rpc("authority", "call_local", "reliable")
func s_prompt(token: int, title: String, text: String, ok_text: String) -> void:
	_show_prompt(token, title, text, ok_text)

# ================= 界面刷新 =================

func _name_by_peer(peer: int) -> String:
	for p in st.get("players", []):
		if int(p.peer) == peer:
			return String(p.name)
	return "?"

func _refresh_players() -> void:
	var seen := {}
	var phase := String(st.get("phase", "playing"))
	# 座位一次性落位（按行动顺序：自己坐底，下家在左，对家在上，上家在右）
	if board.seat_count() == 0:
		var pls: Array = st.get("players", [])
		if not pls.is_empty():
			board.build_seats(pls, my_peer)
	var tiles_arr: Array = st.get("tiles", [])
	var worth_map := {}
	var est_map := {}
	for p in st.get("players", []):
		var peer := int(p.peer)
		seen[peer] = true
		var row: Dictionary = _player_rows.get(peer, {})
		if row.is_empty():
			row = board.seat(peer)
			if row.is_empty():
				continue
			_player_rows[peer] = row
		var active: bool = phase == "playing" and int(st.get("turn", -1)) == peer
		var sb: StyleBoxFlat = row.sb
		sb.bg_color = Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.13) if active else Color(0.52, 0.56, 0.68, 0.05)
		sb.border_color = Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.65) if active else Color(0, 0, 0, 0)

		var tags := ""
		if active:
			tags += "▶ "
		if bool(p.bot):
			tags += "（机器人）"
		if not bool(p.alive):
			tags += "（破产）"
		elif int(p.skip) > 0:
			tags += "（反省中）"
		row.name_l.text = String(p.name) + tags

		# 棋子（Kenney 小人 / 纯色圆片）：破产时整体置灰
		var chip_c: Control = row.chip
		chip_c.modulate = Color(0.42, 0.42, 0.48, 0.85) if not bool(p.alive) else Color.WHITE
		var seat_root: Control = row.get("root")
		if seat_root != null:
			seat_root.modulate = Color(1, 1, 1, 0.55) if not bool(p.alive) else Color.WHITE

		# 体力闪电（道具系统的展示预留，暂为常量 3/5）
		var stamina := int(p.get("stamina", 3))
		for i in (row.pips as Array).size():
			var pip: Panel = row.pips[i]
			pip.add_theme_stylebox_override("panel", UIKit.stylebox(
				Color(1.0, 0.85, 0.3, 0.85) if i < stamina else Color(1, 1, 1, 0.07),
				4, Color(0, 0, 0, 0.25), 1))

		# 道具牌位：公开背包（名字 + 品质描边 + 冷却标记）
		var items: Array = p.get("items", [])
		for i in (row.slots as Array).size():
			board.set_seat_slot(peer, i, items[i] if i < items.size() else null)

		# 金额：滚动数字 + 涨跌闪色 + 棋盘飘字
		var target := int(p.money)
		var shown := int(row.shown)
		if shown != target:
			var diff := target - shown
			row.shown = target
			if row.tw != null and (row.tw as Tween).is_valid():
				row.tw.kill()
			var tw := create_tween()
			row.tw = tw
			var ml: Label = row.money_l
			tw.tween_method(func(v: int) -> void: ml.text = GameData.fmt_money(v), shown, target, 0.45) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			var col := UIKit.GOOD if diff > 0 else UIKit.DANGER
			ml.add_theme_color_override("font_color", col)
			tw.tween_callback(func() -> void:
				ml.add_theme_color_override("font_color", UIKit.TEXT)
			).set_delay(0.6)
			if bool(p.alive):
				var pos := board.token_screen_pos(peer) + Vector2(0, -30)
				Fx.float_text(self, pos, ("+" if diff > 0 else "") + GameData.fmt_money(diff), col, 19)
				Fx.play("cash" if diff > 0 else "pay", -5.0)
				_spawn_money_fly(peer, diff, ml)
		# 顶部战况面板：现金 / 地产数 / 身家（与房主 _net_worth 同一公式）
		var prop_n := 0
		var worth := int(p.money)
		for i in tiles_arr.size():
			var td: Dictionary = tiles_arr[i]
			if int(td.get("owner", GameData.NO_OWNER)) == peer:
				prop_n += 1
				worth += int(GameData.TILES[i].price) + int(td.get("level", 0)) * GameData.upgrade_cost(i)
		est_map[peer] = "地产 ×%d · 身家 %s" % [prop_n, GameData.fmt_money(worth)]
		worth_map[peer] = worth

		if not bool(p.alive):
			row.money_l.text = "已出局"
			row.money_l.add_theme_color_override("font_color", UIKit.TEXT_DIM)

	# 身家排名 → 座位徽章 + 地产/身家行
	var order: Array = worth_map.keys()
	order.sort_custom(func(a, b) -> bool: return int(worth_map[a]) > int(worth_map[b]))
	for i in order.size():
		board.update_seat_stats(int(order[i]), i + 1, String(est_map[int(order[i])]))

	for peer in _player_rows.keys():
		if not seen.has(peer):
			_player_rows.erase(peer)  # 座位是桌面世界的一部分，保留在桌上（掉线/出局只改显示）

func _refresh_actions() -> void:
	var phase := String(st.get("phase", "playing"))
	var await_state := String(st.get("await", ""))
	var is_my_roll := await_state == "roll" and int(st.get("turn", -1)) == my_peer
	roll_btn.disabled = not is_my_roll
	roll_btn.visible = phase == "playing" and await_state == "roll"
	UIKit.restyle_button(roll_btn, "primary" if is_my_roll else "normal")
	var my_turn := phase == "playing" and int(st.get("turn", -1)) == my_peer
	if ph1_lab != null:
		ph1_lab.add_theme_color_override("font_color",
			UIKit.ACCENT if (my_turn and await_state == "roll") else UIKit.TEXT_DIM)
	if ph2_lab != null:
		ph2_lab.add_theme_color_override("font_color",
			UIKit.ACCENT if (my_turn and await_state != "roll") else UIKit.TEXT_DIM)
	_refresh_item_buttons(my_turn, await_state)
	var turn_name := _name_by_peer(int(st.get("turn", -1)))
	match await_state:
		"item":
			status_label.text = "轮到你使用道具！" if int(st.get("await_peer", -1)) == my_peer \
				else "等待 %s 使用道具…" % turn_name
		"shop":
			status_label.text = "慢慢逛，看好就买" if int(st.get("await_peer", -1)) == my_peer \
				else "%s 在小卖部购物…" % turn_name
		"roll":
			if is_my_roll:
				status_label.text = "轮到你转盘了！"
				if not board.is_showing_deck_card() and not board.is_wheel_spinning() \
						and not board.is_rotating() and board.at_home_view():
					board.focus_peer(my_peer)
			else:
				status_label.text = "等待 %s 转盘…" % turn_name
		"prompt":
			if int(st.get("await_peer", -1)) == my_peer:
				status_label.text = "轮到你决定！"
			else:
				status_label.text = "等待 %s 做决定…" % _name_by_peer(int(st.get("await_peer", -1)))
		_:
			if phase == "playing":
				status_label.text = "%s 的回合" % turn_name
			else:
				status_label.text = "游戏结束"
	# 自动化测试：轮到自己时自动掷骰（用 roll_epoch 区分连掷的新请求）
	if at_mode != "" and is_my_roll and int(st.get("roll_epoch", -1)) != _at_roll_epoch:
		_at_roll_epoch = int(st.get("roll_epoch", -1))
		_at_auto_roll()

func _unhandled_input(event: InputEvent) -> void:
	# 空格：视角转回自己座位；Tab：循环切到下一家视角
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_F1:
			_toggle_dev()
		elif k.keycode == KEY_SPACE:
			board.go_home_follow(my_peer)
		elif k.keycode == KEY_TAB:
			board.rotate_next()

## 临时自测：合成一次对顶部座位卡的点击，验证视角旋转链路（--click-test）
func _toggle_log() -> void:
	log_panel.visible = not log_panel.visible
	log_toggle.text = "战报 ▴" if log_panel.visible else "战报 ▾"

func _at_auto_roll() -> void:
	await get_tree().create_timer(0.4).timeout
	if not is_inside_tree():
		return
	if String(st.get("await", "")) == "roll" and int(st.get("turn", -1)) == my_peer:
		if multiplayer.is_server():
			roll_received.emit()
		else:
			c_roll.rpc_id(1)

func _on_tile_clicked(idx: int) -> void:
	var d: Dictionary = GameData.TILES[idx]
	var t := String(d.type)
	var tiles: Array = st.get("tiles", [])
	var level := 0
	var owner_id := GameData.NO_OWNER
	if idx < tiles.size():
		owner_id = int(tiles[idx].get("owner", GameData.NO_OWNER))
		level = int(tiles[idx].get("level", 0))

	var accent := UIKit.ACCENT
	var body := String(GameData.TILE_DESC.get(t, "宿舍一角，岁月静好"))
	match t:
		"property":
			accent = GameData.GROUP_COLORS.get(String(d.group), UIKit.ACCENT)
			var owner_name := "无主 · 踩到可购买"
			if owner_id != GameData.NO_OWNER:
				owner_name = _name_by_peer(owner_id)
			body = "%s产业 · 售价 %s\n当前租金 %s · 装修 Lv%d（%s）\n持有：%s" % [
				GameData.GROUP_NAMES.get(String(d.group), "?"), GameData.fmt_money(int(d.price)),
				GameData.fmt_money(GameData.rent_for(idx, tiles)), level, "★".repeat(level) if level > 0 else "未装修",
				owner_name]
		"fine":
			accent = UIKit.DANGER
			body = "%s\n金额：%s" % [body, GameData.fmt_money(int(d.amount))]
		"bonus":
			accent = UIKit.GOOD
			body = "%s\n金额：%s" % [body, GameData.fmt_money(int(d.amount))]
	info_title.text = "【%s】" % String(d.name)
	info_title.add_theme_color_override("font_color", accent)
	info_body.text = body
	info_sb.border_color = Color(accent.r, accent.g, accent.b, 0.7)
	info_panel.add_theme_stylebox_override("panel", info_sb)
	info_panel.pivot_offset = info_panel.size * 0.5
	info_panel.scale = Vector2(0.94, 0.94)
	var tw := create_tween()
	tw.tween_property(info_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ================= 弹窗与结算 =================

func _show_game_over() -> void:
	if _over_shown:
		return
	_over_shown = true
	_close_prompt()
	_close_casino()
	over_layer = Control.new()
	over_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_layer.z_index = 50
	add_child(over_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_layer.add_child(dim)
	var tw := create_tween()
	tw.tween_property(dim, "color", Color(0, 0, 0, 0.62), 0.4)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_layer.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var panel := UIKit.panel_container(UIKit.PANEL, 14, UIKit.ACCENT, 2, 20)
	panel.custom_minimum_size = Vector2(470, 0)
	box.add_child(panel)
	var pm := UIKit.margins(24, 24, 20, 20)
	panel.add_child(pm)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	pm.add_child(pv)

	var wname := "平局"
	if int(st.get("winner", -1)) != -1:
		wname = _name_by_peer(int(st.winner))
	var big := UIKit.title_label("游戏结束！平局" if int(st.get("winner", -1)) == -1 else "游戏结束！%s 获胜" % wname, 26)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(big)

	pv.add_child(UIKit.label("── 最终资产排名 ──", 13, UIKit.TEXT_DIM))
	for i in _standings().size():
		var r: Dictionary = _standings()[i]
		var is_winner := int(st.get("winner", -1)) != -1 and i == 0
		var row_card := UIKit.panel_container(
			Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.10) if is_winner else Color(0.5, 0.55, 0.68, 0.05),
			10,
			Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.55) if is_winner else Color(0, 0, 0, 0), 1)
		var rm := UIKit.margins(10, 10, 5, 5)
		row_card.add_child(rm)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		rm.add_child(row)
		row.add_child(UIKit.rank_badge(i + 1, 24))
		row.add_child(UIKit.chip(GameData.PLAYER_COLORS[int(r.color)], 16))
		var nm := UIKit.label(String(r.name) + ("" if bool(r.alive) else "（破产）"), 15,
			UIKit.ACCENT if is_winner else UIKit.TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(nm)
		var worth_l := UIKit.label(GameData.fmt_money(int(r.worth)), 15,
			UIKit.ACCENT if is_winner else UIKit.TEXT)
		worth_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(worth_l)
		pv.add_child(row_card)

	var vs := UIKit.vspace(6)
	pv.add_child(vs)
	var back := UIKit.button("返回主菜单", 17, "primary")
	back.pressed.connect(_on_exit)
	pv.add_child(back)

	# 面板弹入 + 彩带 + 胜利音
	panel.resized.connect(func() -> void: panel.pivot_offset = panel.size * 0.5)
	panel.scale = Vector2(0.8, 0.8)
	panel.modulate.a = 0.0
	var tw2 := create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw2.tween_property(panel, "modulate:a", 1.0, 0.2)
	tw2.set_parallel(false)
	Fx.play("win")
	Fx.confetti(self, Rect2(Vector2(0, 0), Vector2(size.x, 120)), 90)

func _standings() -> Array:
	var rows := []
	var tiles: Array = st.get("tiles", [])
	for p in st.get("players", []):
		var worth := int(p.money)
		for i in tiles.size():
			if int(tiles[i].get("owner", GameData.NO_OWNER)) == int(p.peer):
				worth += int(GameData.TILES[i].price) + int(tiles[i].get("level", 0)) * GameData.upgrade_cost(i)
		rows.append({"name": String(p.name), "worth": worth, "alive": bool(p.alive), "color": int(p.color)})
	rows.sort_custom(func(a, b) -> bool: return int(a.worth) > int(b.worth))
	return rows

## 购买/升级询问弹窗：游戏内风格面板 + 倒计时条，超时自动放弃
func _show_prompt(token: int, title: String, text: String, ok_text: String) -> void:
	if at_mode != "":
		await get_tree().create_timer(0.3).timeout
		_answer(token, true)
		return
	_close_prompt()
	_prompt_token = token
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 60
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	_prompt_dlg = layer
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var panel := UIKit.panel_container(UIKit.PANEL, 14, UIKit.ACCENT, 2, 18)
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var pm := UIKit.margins(22, 22, 18, 18)
	panel.add_child(pm)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 12)
	pm.add_child(pv)
	pv.add_child(UIKit.title_label(title, 20))
	var text_l := UIKit.label(text, 14, UIKit.TEXT)
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(text_l)
	var bar := UIKit.progress(UIKit.ACCENT)
	pv.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	pv.add_child(row)
	var no_btn := UIKit.button("算了", 15)
	no_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(no_btn)
	var ok_btn := UIKit.button(ok_text, 15, "primary")
	ok_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ok_btn)
	ok_btn.pressed.connect(func() -> void:
		_answer(token, true)
		_close_prompt()
	)
	no_btn.pressed.connect(func() -> void:
		_answer(token, false)
		_close_prompt()
	)
	_prompt_tw = create_tween()
	_prompt_tw.tween_property(bar, "value", 0.0, GameData.PROMPT_TIMEOUT - 1.0)
	_prompt_tw.tween_callback(func() -> void:
		if _prompt_token == token:
			_answer(token, false)
			_close_prompt()
	)

func _close_prompt() -> void:
	if _prompt_tw != null and _prompt_tw.is_valid():
		_prompt_tw.kill()
	_prompt_tw = null
	if _prompt_dlg != null and is_instance_valid(_prompt_dlg):
		_prompt_dlg.queue_free()
	_prompt_dlg = null
	_prompt_token = -1

func _refresh_chat() -> void:
	# 对局期间的聊天并入战报（弱化颜色），避免错过消息
	while _chat_shown < Net.chat_history.size():
		var line := str(Net.chat_history[_chat_shown])
		_chat_shown += 1
		log_text.append_text("[color=#7f8699]%s[/color]\n" % line.replace("[", "［"))
	
# ================= 道具卡图鉴（模板预览） =================

func _open_card_gallery() -> void:
	if card_gallery != null and is_instance_valid(card_gallery):
		card_gallery.visible = true
		return
	card_gallery = Control.new()
	card_gallery.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_gallery.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card_gallery)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.03, 0.07, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_gallery.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_gallery.add_child(cc)
	var panel := UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(0.45, 0.85, 0.55, 0.7), 1, 10)
	panel.custom_minimum_size = Vector2(1160, 740)
	cc.add_child(panel)
	var m := UIKit.margins(16, 14, 12, 12)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	head.add_child(UIKit.label("道具卡片模板 · §12 规格（品质框 / 左上⚡或被动 / 右上计数 / 图区占位 / 价格不上卡）",
		14, UIKit.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close_btn := UIKit.button("✕ 关闭", 13)
	close_btn.pressed.connect(func() -> void: card_gallery.visible = false)
	head.add_child(close_btn)
	v.add_child(UIKit.label("小 = 道具栏 · 中 = 货架（价格随货架显示）· 大 = 发现三选一 / 使用展示 —— 图区为占位，正式图画归美术对话",
		11, UIKit.TEXT_DIM))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var gv := VBoxContainer.new()
	gv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gv.add_theme_constant_override("separation", 12)
	scroll.add_child(gv)

	gv.add_child(_card_section("道具栏尺寸（小 · 96×132）", [
		_card_cell("招财猫", ItemCard.SIZE_SMALL, {}, "普通 · 被动"),
		_card_cell("信托基金", ItemCard.SIZE_SMALL, {}, "稀有 · 被动"),
		_card_cell("作弊器", ItemCard.SIZE_SMALL, {}, "超稀有 · ⚡3"),
		_card_cell("平均主义", ItemCard.SIZE_SMALL, {}, "史诗 · ⚡5"),
		_card_cell("黑卡", ItemCard.SIZE_SMALL, {}, "传说 · ⚡4"),
		_card_cell("蛋蛋节", ItemCard.SIZE_SMALL, {}, "传说 · 一次性"),
	]))
	gv.add_child(_card_section("货架尺寸（中 · 150×210）· 状态一览", [
		_card_cell("作弊器", ItemCard.SIZE_MEDIUM, {}, "普通"),
		_card_cell("作弊器", ItemCard.SIZE_MEDIUM, {"count": 2}, "冷却中 · 右上剩 2 回合·压暗"),
		_card_cell("黑卡", ItemCard.SIZE_MEDIUM, {"count": 2}, "计数中 · 剩 2 次购买"),
		_card_cell("空想者的香皂", ItemCard.SIZE_MEDIUM, {"count": 7, "melt": true}, "融化中 · 剩 7 回合"),
		_card_cell("蛋蛋节", ItemCard.SIZE_MEDIUM, {}, "一次性 · 用后焚毁"),
		_card_cell("平均主义", ItemCard.SIZE_MEDIUM, {"dim": true}, "买不起 · 压暗"),
		_card_cell("平均主义", ItemCard.SIZE_MEDIUM, {"selected": true}, "发现可选 · 金框高亮"),
	]))
	gv.add_child(_card_section("发现 / 使用展示尺寸（大 · 220×300）", [
		_card_cell("蛋蛋节", ItemCard.SIZE_LARGE, {"selected": true}, "发现三选一（高亮）"),
		_card_cell("黑卡", ItemCard.SIZE_LARGE, {}, "使用展示"),
	]))

func _card_section(title: String, cells: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UIKit.label(title, 12, UIKit.TEXT_DIM))
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 14)
	row.add_theme_constant_override("v_separation", 6)
	box.add_child(row)
	for c in cells:
		row.add_child(c)
	return box

func _card_cell(id: String, size: Vector2, state: Dictionary, caption: String) -> Control:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 3)
	var holder := Control.new()
	holder.custom_minimum_size = size + Vector2(14, 14)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(holder)
	var card := ItemCard.make(id, size, state)
	card.position = Vector2(7, 7)
	holder.add_child(card)
	var cap := UIKit.label(caption, 10, UIKit.TEXT_DIM)
	cap.custom_minimum_size = Vector2(size.x + 14, 0)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cell.add_child(cap)
	return cell

# ================= 道具系统：host 逻辑与 RPC（阶段一） =================

func _refresh_price() -> int:
	return ItemData.REFRESH_BASE + refresh_count * ItemData.REFRESH_STEP

func _has_item(p: Dictionary, id: String) -> bool:
	for it in p.get("items", []):
		if String(it.id) == id:
			return true
	return false

func _item_pool(quality: String) -> Array:
	var held := {}
	for pl in hp:
		for it in pl.get("items", []):
			held[String(it.id)] = true
	var out := []
	for id in ItemData.ITEMS:
		var d: Dictionary = ItemData.ITEMS[id]
		if not bool(d.implemented):
			continue
		if quality != "" and String(d.quality) != quality:
			continue
		if bool(d.unique) and held.has(id):
			continue
		out.append(String(id))
	return out

func _roll_quality() -> String:
	var total := 0
	for q in ItemData.SHOP_WEIGHTS:
		total += int(ItemData.SHOP_WEIGHTS[q])
	var r := randi_range(0, maxi(total - 1, 0))
	for q in ItemData.SHOP_WEIGHTS:
		r -= int(ItemData.SHOP_WEIGHTS[q])
		if r < 0:
			return q
	return "白"

func _stock_one() -> String:
	var q := _roll_quality()
	if q == "橙" and _item_pool("橙").is_empty():
		q = "紫"  # 橙池空并入紫（定稿）
	var pool := _item_pool(q)
	if pool.is_empty():
		return ""
	return pool[randi_range(0, pool.size() - 1)]

func _stock_shop(idx: int) -> void:
	var arr: Array = shops[idx].slots
	for i in arr.size():
		if String(arr[i]) == "":
			arr[i] = _stock_one()

func _item_turn_start(p: Dictionary) -> void:
	p.stamina = mini(int(p.get("stamina", 3)) + 1, 5)
	p.item_used = false
	for it in p.get("items", []):
		if int(it.get("cd", 0)) > 0:
			it.cd = int(it.cd) - 1
	if _has_item(p, "信托基金"):
		p.money = int(p.money) + 100
		_log("【信托基金】给 %s 发了 %s 零花钱" % [p.name, GameData.fmt_money(100)], "#74d188")

func _has_usable(p: Dictionary) -> bool:
	if bool(p.get("item_used", false)):
		return false
	for it in p.get("items", []):
		var d := ItemData.def(String(it.id))
		if String(d.type) == "passive" or not bool(d.implemented):
			continue
		if int(it.get("cd", 0)) > 0:
			continue
		if int(p.get("stamina", 0)) < int(d.cost):
			continue
		return true
	return false

func _item_phase(p: Dictionary) -> void:
	if not running or not bool(p.alive) or not _has_usable(p):
		return
	_item_epoch += 1
	var epoch := _item_epoch
	_awaiting_item = int(p.peer)
	_item_action = {"epoch": -1}
	_broadcast_state()
	if bool(p.bot):
		_item_action = {"epoch": epoch, "action": "skip"}  # 机器人道具策略后续批次
	else:
		_arm_item_timeout(epoch, int(p.peer))
	while running and _awaiting_item == int(p.peer) and int(_item_action.get("epoch", -1)) != epoch:
		await _wait(0.1)
	if not running:
		return
	_awaiting_item = 0
	_broadcast_state()

func _arm_item_timeout(epoch: int, peer: int) -> void:
	await _wait(ItemData.ITEM_TIMEOUT)
	if running and _awaiting_item == peer and int(_item_action.get("epoch", -1)) != epoch:
		_log("%s 在道具阶段发呆，跳过" % _name_by_peer(peer), "#8a90a5")
		_item_action = {"epoch": epoch, "action": "skip"}

func _use_item(peer: int, slot: int, arg: int) -> void:
	var p := _player_by_peer(peer)
	if p.is_empty() or _awaiting_item != peer or bool(p.get("item_used", false)):
		return
	var items: Array = p.get("items", [])
	if slot < 0 or slot >= items.size():
		return
	var it: Dictionary = items[slot]
	var d := ItemData.def(String(it.id))
	if String(d.type) == "passive" or not bool(d.implemented):
		return
	if int(it.get("cd", 0)) > 0 or int(p.get("stamina", 0)) < int(d.cost):
		return
	p.stamina = int(p.stamina) - int(d.cost)
	it.cd = int(d.cooldown)
	p.item_used = true
	match String(it.id):
		"作弊器":
			p.cheat_roll = clampi(arg, 0, 12)
			_log("%s 掏出【作弊器】，下一次转盘他说了算" % p.name, "#8fb7f2")
		"平均主义":
			var alive: Array = hp.filter(func(x) -> bool: return bool(x.alive))
			var total := 0
			for a in alive:
				total += int(a.money)
			var share := int(total / alive.size())
			var rem := total - share * alive.size()
			for a in alive:
				a.money = share
			for k in rem:
				alive[k].money = int(alive[k].money) + 1
			_log("%s 发动【平均主义】，全场现金拉平！" % p.name, "#c9a6ff")
		_:
			p.item_used = false
			p.stamina = int(p.stamina) + int(d.cost)
			return
	_item_action = {"epoch": _item_epoch, "action": "used"}
	_broadcast_state()

func _run_shop(p: Dictionary, idx: int) -> void:
	_shop_tile = idx
	_shop_peer = int(p.peer)
	_shop_epoch += 1
	var epoch := _shop_epoch
	if not shops.has(idx):
		shops[idx] = {"slots": ["", "", ""]}
	_stock_shop(idx)
	_broadcast_state()
	if bool(p.bot):
		_bot_shop(p, idx)
	else:
		_arm_shop_timeout(epoch, int(p.peer))
	while running and _shop_peer == int(p.peer) and _shop_epoch == epoch:
		await _wait(0.1)
	if not running:
		return
	_shop_peer = 0
	_broadcast_state()

func _arm_shop_timeout(epoch: int, peer: int) -> void:
	await _wait(ItemData.SHOP_TIMEOUT)
	if running and _shop_peer == peer and _shop_epoch == epoch:
		_log("%s 在小卖部逛太久，被老板请了出去" % _name_by_peer(peer), "#8a90a5")
		_shop_peer = 0

func _bot_shop(p: Dictionary, idx: int) -> void:
	var arr: Array = shops[idx].slots
	var best := -1
	var best_price := 0
	for i in arr.size():
		var id := String(arr[i])
		if id == "":
			continue
		var price := ItemData.price(String(ItemData.def(id).quality))
		if int(p.money) >= price and p.items.size() < 5 and price > best_price:
			best = i
			best_price = price
	if best != -1:
		_shop_buy(int(p.peer), best)
	_shop_leave(int(p.peer))

func _shop_buy(peer: int, slot: int) -> void:
	if _shop_peer != peer or _shop_tile < 0 or not shops.has(_shop_tile):
		return
	var arr: Array = shops[_shop_tile].slots
	if slot < 0 or slot >= arr.size() or String(arr[slot]) == "":
		return
	var id := String(arr[slot])
	var price := ItemData.price(String(ItemData.def(id).quality))
	var p := _player_by_peer(peer)
	if p.is_empty() or p.items.size() >= 5 or int(p.money) < price:
		return
	p.money = int(p.money) - price
	p.items.append({"id": id, "cd": 0})
	arr[slot] = ""
	_log("%s 在小卖部买下了【%s】（%s）" % [p.name, id, GameData.fmt_money(price)], "#8fb7f2")
	_broadcast_state()

func _shop_refresh(peer: int) -> void:
	if _shop_peer != peer or _shop_tile < 0 or not shops.has(_shop_tile):
		return
	var p := _player_by_peer(peer)
	var cost := _refresh_price()
	if p.is_empty() or int(p.money) < cost:
		return
	p.money = int(p.money) - cost
	refresh_count += 1
	_stock_shop(_shop_tile)
	_log("%s 花 %s 刷新了货架（全场刷新价上涨）" % [p.name, GameData.fmt_money(cost)], "#8a90a5")
	_broadcast_state()

func _shop_leave(peer: int) -> void:
	if _shop_peer != peer:
		return
	_log("%s 走出了小卖部" % _name_by_peer(peer), "#8a90a5")
	_shop_peer = 0
	_broadcast_state()

@rpc("any_peer", "call_remote", "reliable")
func c_use_item(slot: int, arg: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == _awaiting_item:
		_use_item(sender, slot, arg)

@rpc("any_peer", "call_remote", "reliable")
func c_item_skip() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == _awaiting_item:
		_item_action = {"epoch": _item_epoch, "action": "skip"}

@rpc("any_peer", "call_remote", "reliable")
func c_shop_buy(slot: int) -> void:
	if not multiplayer.is_server():
		return
	_shop_buy(multiplayer.get_remote_sender_id(), slot)

@rpc("any_peer", "call_remote", "reliable")
func c_shop_refresh() -> void:
	if not multiplayer.is_server():
		return
	_shop_refresh(multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable")
func c_shop_leave() -> void:
	if not multiplayer.is_server():
		return
	_shop_leave(multiplayer.get_remote_sender_id())

func _refresh_item_buttons(my_turn: bool, await_state: String) -> void:
	if item_btn_box == null:
		return
	var mine: bool = my_turn and await_state == "item"
	ph1_pill.visible = not mine
	ph2_pill.visible = not mine
	ph_arrow_l.visible = not mine
	roll_btn.visible = roll_btn.visible and not mine
	item_btn_box.visible = mine
	if not mine:
		return
	for c in item_btn_box.get_children():
		c.queue_free()
	var p := _player_by_peer(my_peer)
	if p.is_empty():
		return
	var items: Array = p.get("items", [])
	for i in items.size():
		var it: Dictionary = items[i]
		var d := ItemData.def(String(it.id))
		if String(d.type) == "passive" or not bool(d.implemented):
			continue
		var usable: bool = int(it.get("cd", 0)) == 0 \
			and int(p.get("stamina", 0)) >= int(d.cost) and not bool(p.get("item_used", false))
		var b := UIKit.button("%s ⚡%d" % [String(it.id), int(d.cost)], 12)
		b.disabled = not usable
		var slot := i
		var iid := String(it.id)
		b.pressed.connect(func() -> void:
			if iid == "作弊器":
				_open_cheat_picker(slot)
			else:
				_send_use_item(slot, -1)
		)
		item_btn_box.add_child(b)
	var skip := UIKit.button("跳过", 12)
	skip.pressed.connect(func() -> void:
		if multiplayer.is_server():
			_item_action = {"epoch": _item_epoch, "action": "skip"}
		else:
			c_item_skip.rpc()
	)
	item_btn_box.add_child(skip)

func _send_use_item(slot: int, arg: int) -> void:
	_close_cheat_picker()
	if multiplayer.is_server():
		_use_item(my_peer, slot, arg)
	else:
		c_use_item.rpc(slot, arg)

func _open_cheat_picker(slot: int) -> void:
	cheat_slot = slot
	cheat_picker.visible = true

func _close_cheat_picker() -> void:
	cheat_picker.visible = false

# ================= 选项菜单 / 房主暂停 / 设置 =================

func _pill_label(p: Control) -> Label:
	for c in p.find_children("", "Label", true, false):
		return c as Label
	return null

func _build_menu_ui() -> void:
	menu_layer = Control.new()
	menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ALWAYS 而非 WHEN_PAUSED：非房主本地打开菜单时对局仍在跑，菜单必须可交互
	menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_layer.visible = false
	add_child(menu_layer)

	# 非房主看到的「房主已暂停」遮罩
	pause_mask = ColorRect.new()
	pause_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_mask.color = Color(0.03, 0.03, 0.07, 0.62)
	pause_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_mask.visible = false
	pause_mask.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_mask)
	var pm_lab := UIKit.label("⏸ 房主已暂停 · 等待继续…", 20, UIKit.ACCENT)
	pm_lab.set_anchors_preset(Control.PRESET_FULL_RECT)
	pm_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pm_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pm_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_mask.add_child(pm_lab)

	# 主菜单：继续 / 设置 / 退出
	var mc := CenterContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(mc)
	menu_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.9), 1, 10)
	menu_panel.custom_minimum_size = Vector2(320, 0)
	mc.add_child(menu_panel)
	var mm := UIKit.margins(20, 20, 16, 14)
	menu_panel.add_child(mm)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	mm.add_child(mv)
	menu_state = UIKit.label("", 13, UIKit.TEXT_DIM)
	mv.add_child(menu_state)
	var cont_btn := UIKit.button("▶ 继续游戏", 15)
	cont_btn.pressed.connect(_menu_resume)
	mv.add_child(cont_btn)
	var set_btn := UIKit.button("⚙ 设置", 15)
	set_btn.pressed.connect(func() -> void:
		menu_panel.visible = false
		vol_slider.value = audio_volume * 100.0
		mute_check.button_pressed = audio_mute
		settings_panel.visible = true
	)
	mv.add_child(set_btn)
	var quit_btn := UIKit.button("⏻ 退出游戏", 15, "danger")
	quit_btn.pressed.connect(func() -> void:
		confirm_note.text = "你是房主：退出后对局结束，所有人回到主菜单。" \
			if multiplayer.is_server() else "退出后你的回合将由机器人接管，对局继续。"
		menu_panel.visible = false
		confirm_panel.visible = true
	)
	mv.add_child(quit_btn)

	# 设置：音量 / 静音（后续会加更多设置项）
	var sc := CenterContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(sc)
	settings_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.9), 1, 10)
	settings_panel.custom_minimum_size = Vector2(320, 0)
	sc.add_child(settings_panel)
	var sm := UIKit.margins(20, 20, 16, 14)
	settings_panel.add_child(sm)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	sm.add_child(sv)
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 10)
	sv.add_child(vol_row)
	vol_row.add_child(UIKit.label("音效音量", 14, UIKit.TEXT))
	vol_slider = HSlider.new()
	vol_slider.min_value = 0
	vol_slider.max_value = 100
	vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vol_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vol_slider.value_changed.connect(func(v: float) -> void:
		audio_volume = v / 100.0
		_apply_audio()
	)
	vol_row.add_child(vol_slider)
	var mute_row := HBoxContainer.new()
	mute_row.add_theme_constant_override("separation", 10)
	sv.add_child(mute_row)
	mute_row.add_child(UIKit.label("静音", 14, UIKit.TEXT))
	mute_check = CheckButton.new()
	mute_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mute_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mute_check.toggled.connect(func(on: bool) -> void:
		audio_mute = on
		_apply_audio()
	)
	mute_row.add_child(mute_check)
	sv.add_child(UIKit.label("—— 更多设置项（后续加入） ——", 12, UIKit.TEXT_DIM))
	var back_btn := UIKit.button("‹ 返回", 14)
	back_btn.pressed.connect(func() -> void:
		settings_panel.visible = false
		menu_panel.visible = true
	)
	sv.add_child(back_btn)

	# 退出二次确认
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(cc)
	confirm_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(UIKit.DANGER.r, UIKit.DANGER.g, UIKit.DANGER.b, 0.75), 1, 10)
	confirm_panel.custom_minimum_size = Vector2(320, 0)
	cc.add_child(confirm_panel)
	var cm2 := UIKit.margins(20, 20, 16, 14)
	confirm_panel.add_child(cm2)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cm2.add_child(cv)
	cv.add_child(UIKit.label("确定要退出本局吗？", 15, UIKit.TEXT))
	confirm_note = UIKit.label("", 12, UIKit.TEXT_DIM)
	confirm_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(confirm_note)
	var cbtn_row := HBoxContainer.new()
	cbtn_row.add_theme_constant_override("separation", 10)
	cv.add_child(cbtn_row)
	var cancel_btn := UIKit.button("取消", 14)
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(func() -> void:
		confirm_panel.visible = false
		menu_panel.visible = true
	)
	cbtn_row.add_child(cancel_btn)
	var sure_btn := UIKit.button("确认退出", 14, "danger")
	sure_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sure_btn.pressed.connect(func() -> void:
		get_tree().paused = false
		_on_exit()
	)
	cbtn_row.add_child(sure_btn)

	# 作弊器点数选框（0~12，本地弹出）
	cheat_picker = Control.new()
	cheat_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	cheat_picker.visible = false
	add_child(cheat_picker)
	var cd_dim := ColorRect.new()
	cd_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd_dim.color = Color(0.04, 0.04, 0.08, 0.55)
	cheat_picker.add_child(cd_dim)
	var cc2 := CenterContainer.new()
	cc2.set_anchors_preset(Control.PRESET_FULL_RECT)
	cheat_picker.add_child(cc2)
	var cp := UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.8), 1, 10)
	cc2.add_child(cp)
	var cpm := UIKit.margins(20, 20, 14, 12)
	cp.add_child(cpm)
	var cv2 := VBoxContainer.new()
	cv2.add_theme_constant_override("separation", 8)
	cpm.add_child(cv2)
	cv2.add_child(UIKit.label("选定下一次转盘点数（0~12）", 14, UIKit.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	cv2.add_child(grid)
	for v in 13:
		var vb := UIKit.button(str(v), 14)
		var vv := v
		vb.pressed.connect(func() -> void:
			_send_use_item(cheat_slot, vv)
		)
		grid.add_child(vb)
	var cv_cancel := UIKit.button("取消", 13)
	cv_cancel.pressed.connect(_close_cheat_picker)
	cv2.add_child(cv_cancel)

func _open_menu() -> void:
	if multiplayer.is_server():
		s_pause.rpc(true)  # 房主打开菜单 = 全场暂停
		menu_state.text = "⏸ 已暂停（全场）"
	else:
		menu_state.text = "对局进行中 · 仅房主可暂停"
	menu_panel.visible = true
	settings_panel.visible = false
	confirm_panel.visible = false
	menu_layer.visible = true

func _menu_resume() -> void:
	if multiplayer.is_server():
		s_pause.rpc(false)
	menu_layer.visible = false

@rpc("authority", "call_local", "reliable")
func s_pause(on: bool) -> void:
	get_tree().paused = on
	pause_mask.visible = on and not multiplayer.is_server()

func _apply_audio() -> void:
	AudioServer.set_bus_mute(0, audio_mute)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(audio_volume, 0.0001)))

## 飞钞：金额变动时账单在棋子与座位卡金额栏之间飞（Monopoly GO 式收支反馈）
func _spawn_money_fly(peer: int, diff: int, ml: Label) -> void:
	var good := diff > 0
	var card_at := ml.get_global_rect().get_center()
	var token_at := board.token_screen_pos(peer) + Vector2(0, -18)
	for i in 4:
		var bill := Panel.new()
		bill.size = Vector2(22, 12)
		bill.z_index = 90
		bill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bill.add_theme_stylebox_override("panel", UIKit.stylebox(
			Color(0.5, 0.85, 0.6) if good else Color(0.9, 0.55, 0.52), 3, Color(0, 0, 0, 0.4), 1))
		var start := token_at + Vector2(randf_range(-34, 34), randf_range(-16, 16)) if good \
			else card_at + Vector2(randf_range(-10, 10), randf_range(-8, 8))
		var goal := card_at + Vector2(randf_range(-10, 10), randf_range(-8, 8)) if good \
			else token_at + Vector2(randf_range(-34, 34), randf_range(-16, 16))
		bill.position = start
		add_child(bill)
		var tw := create_tween()
		tw.tween_interval(0.05 + i * 0.08)
		tw.tween_property(bill, "position", goal, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(bill, "modulate:a", 0.0, 0.2).set_delay(0.36)
		tw.tween_callback(bill.queue_free)

# ================= 开发者模式 =================

func _apply_dev_mode() -> void:
	if dev_panel != null and is_instance_valid(dev_panel):
		dev_panel.visible = dev_enabled
	if board != null:
		board.dev_tile_index = dev_enabled
	_dev_ts_update()

func _toggle_dev() -> void:
	dev_enabled = not dev_enabled
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("dev", "enabled", dev_enabled)
	cfg.save("user://settings.cfg")
	_apply_dev_mode()

func _dev_ts_update() -> void:
	if dev_ts_l != null and is_instance_valid(dev_ts_l):
		dev_ts_l.text = "当前 " + String.num(Engine.time_scale, 2) + "x"

func _dev_selected() -> Dictionary:
	var p := _player_by_peer(dev_sel_peer)
	return p

func _dev_edit_selected(edit: Callable) -> void:
	if not multiplayer.is_server():
		return
	var p := _dev_selected()
	if p.is_empty():
		return
	edit.call(p)
	_broadcast_state()

func _dev_add_money(amount: int) -> void:
	_dev_edit_selected(func(p: Dictionary) -> void: p.money = int(p.money) + amount)

func _dev_grant_item() -> void:
	var id := _dev_selected_item()
	if id == "":
		return
	_dev_edit_selected(func(p: Dictionary) -> void: p.items.append({"id": id, "cd": 0}))

func _dev_selected_item() -> String:
	if dev_item_opt == null or dev_item_opt.selected < 0:
		return ""
	return String(ItemData.ITEMS.keys()[dev_item_opt.selected])

func _dev_item_desc_update() -> void:
	var d := ItemData.def(_dev_selected_item())
	dev_item_desc.text = "%s · %d⚡ · %s" % [String(d.get("quality", "?")), int(d.get("cost", 0)), String(d.get("desc", ""))] \
		if String(d.get("type", "")) == "active" else "%s · 被动 · %s" % [String(d.get("quality", "?")), String(d.get("desc", ""))]

func _dev_force_use() -> void:
	if not multiplayer.is_server():
		return
	var id := _dev_selected_item()
	var p := _dev_selected()
	if p.is_empty() or id == "":
		return
	if not _has_item(p, id):
		p.items.append({"id": id, "cd": 0})
	match id:
		"作弊器":
			p.cheat_roll = clampi(int(dev_roll_spin.value), 0, 12)
			_log("[dev] %s 的下一次转盘点数被锁成 %d" % [p.name, int(dev_roll_spin.value)], "#7fd88f")
		"平均主义":
			var alive: Array = hp.filter(func(x) -> bool: return bool(x.alive))
			var total := 0
			for a in alive:
				total += int(a.money)
			var share := int(total / alive.size())
			var rem := total - share * alive.size()
			for a in alive:
				a.money = share
			for k in rem:
				alive[k].money = int(alive[k].money) + 1
			_log("[dev] 全场现金已拉平", "#7fd88f")
		_:
			_log("[dev] 【%s】效果尚未实装（被动持有即可生效 / 后续批次）" % id, "#7fd88f")
	_broadcast_state()

func _dev_end_wait() -> void:
	if not multiplayer.is_server():
		return
	match String(st.get("await", "")):
		"roll":
			roll_received.emit()
		"item":
			_item_action = {"epoch": _item_epoch, "action": "skip"}
		"shop":
			_shop_leave(_shop_peer)

func _dev_refresh_panel() -> void:
	if dev_panel == null or not is_instance_valid(dev_panel) or not dev_panel.visible:
		return
	var lines := ["第%d/%d轮 · await=%s" % [int(st.get("round", 0)), int(st.get("max_rounds", 0)), String(st.get("await", ""))]]
	for p in st.get("players", []):
		var its := []
		for it in p.get("items", []):
			its.append(String(it.id) + (("·%d" % int(it.cd)) if int(it.cd) > 0 else ""))
		lines.append("%s ¥%d ⚡%d 格%d %s" % [String(p.name), int(p.money), int(p.get("stamina", 0)),
			int(p.pos), " ".join(its)])
	var shop_txt := ""
	for k in st.get("shops", {}):
		var arr: Array = st.shops[k].slots
		var names := []
		for id in arr:
			names.append("空" if String(id) == "" else String(id))
		shop_txt += "[%s]" % ",".join(names)
	lines.append("刷¥%d %s" % [int(st.get("refresh_price", 0)), shop_txt])
	dev_state_l.text = "\n".join(lines)
	dev_cam_l.text = board.cam_info()
	# 玩家选择按钮懒建 + 文本刷新
	if dev_pbtns.is_empty() and board.seat_count() > 0:
		for p in st.get("players", []):
			var peer := int(p.peer)
			var b := UIKit.button(String(p.name), 11)
			b.toggle_mode = true
			b.pressed.connect(func() -> void:
				dev_sel_peer = peer
				_dev_sel_refresh()
			)
			dev_players.add_child(b)
			dev_pbtns.append({"peer": peer, "btn": b})
	_dev_sel_refresh()

func _dev_sel_refresh() -> void:
	if dev_sel_peer == 0 and not dev_pbtns.is_empty():
		dev_sel_peer = int(dev_pbtns[0].peer)
	for e in dev_pbtns:
		var btn: Button = e.btn
		btn.button_pressed = int(e.peer) == dev_sel_peer

func _menu_probe_run() -> void:
	await _wait(2.0)
	print("PROBE open menu...")
	_open_menu()
	await get_tree().create_timer(0.5, true).timeout
	print("PROBE paused=", get_tree().paused, " menu_visible=", menu_layer.visible,
		" panel=", menu_panel.visible, " state=", menu_state.text)
	_menu_resume()
	await get_tree().create_timer(0.5, true).timeout
	print("PROBE resumed paused=", get_tree().paused, " menu_visible=", menu_layer.visible)
	_open_menu()
	await get_tree().create_timer(0.5, true).timeout
	print("PROBE reopen paused=", get_tree().paused, " menu_visible=", menu_layer.visible)
	_menu_resume()
	await get_tree().create_timer(0.5, true).timeout
	print("PROBE final paused=", get_tree().paused)
	print("PROBE DONE")
	get_tree().quit(0)

func _process(_delta: float) -> void:
	# 牌垫阶段条锚定自己座位卡下沿；不在自己视角 / 非对局阶段时隐藏
	if mat_bar == null:
		return
	var show := board.seat_count() > 0 and board.at_home_view() \
		and String(st.get("phase", "")) == "playing"
	var shop_mine: bool = show and int(st.get("shop_peer", 0)) == my_peer \
		and int(st.get("shop_open", -1)) >= 0
	shop_bar.visible = shop_mine
	if shop_mine:
		var r2 := board.home_card_screen_rect()
		shop_bar.position = Vector2(r2.get_center().x - shop_bar.size.x * 0.5, r2.end.y + 10.0)
	mat_bar.visible = show and not shop_mine
	if show and not shop_mine:
		var r := board.home_card_screen_rect()
		mat_bar.position = Vector2(r.get_center().x - mat_bar.size.x * 0.5, r.end.y + 10.0)
	if dev_enabled:
		_dev_refresh_panel()

func _on_conn_lost(reason: String) -> void:
	Net.last_error = reason
	Fx.go_to("res://scenes/main_menu.tscn")

func _on_exit() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Net.leave()
	Fx.go_to("res://scenes/main_menu.tscn")

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, false).timeout

func _take_shot(path: String) -> void:
	await get_tree().create_timer(0.4).timeout
	while board.is_showing_deck_card():
		await get_tree().create_timer(0.25).timeout
	board.fit_overview()
	await get_tree().create_timer(0.2).timeout
	board.cam_locked = true  # 摆拍期间锁住自动镜头，避免对局推进拽走视角
	if _shot_rot > 0:
		board.rotate_to_edge(_shot_rot, true)  # 摆拍：转到对应座位的视角
		await get_tree().create_timer(0.15).timeout
	if not path.contains("table"):
		# 对局近景摆拍；路径带 table 则停在围桌全景（验证布局用）
		board.focus_grid(27, 0.8, true)
		await get_tree().create_timer(0.15).timeout
		_on_tile_clicked(27)  # 顺便展示格子详情卡
	if not path.contains("plain"):
		board.play_deck_card("机会", "good", "帮宿管阿姨搬了一下午矿泉水，辛苦费 +600")
		board.spin_wheel(12)
		# 赌局界面预览（单行假数据，验证布局用）
		s_casino_start.rpc("炸弹猫", 800, 3200, [my_peer])
		s_casino_turn.rpc(my_peer, 1, {my_peer: 1}, {my_peer: 2}, 9, true)
		s_casino_event.rpc("你 摸到一张【拆除】揣进兜里", "move")
		s_casino_event.rpc("你 摸到炸弹，紧急打出【拆除】化解！", "move")
		s_casino_event.rpc("你 摸到一条小鱼", "good")
	# 连拍三帧，避开 3 倍速下真实抽卡与摆拍的相互干扰
	for i in 3:
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var p := path if i == 0 else path.replace(".png", "_%d.png" % i)
		get_viewport().get_texture().get_image().save_png(p)
		print("SHOT SAVED ", p)
	get_tree().quit(0)

# ================= 赌桌小游戏：炸弹猫 =================

func _casino_card_name(c: String) -> String:
	match c:
		"bomb": return "炸弹"
		"defuse": return "拆除"
		_: return "小鱼"

func _bombcat_deck() -> Array:
	var deck := ["bomb", "bomb", "bomb", "defuse", "defuse",
		"fish", "fish", "fish", "fish", "fish", "fish", "fish"]
	deck.shuffle()
	return deck

func _casino_next_epoch() -> int:
	_casino_epoch += 1
	_casino_action = {"epoch": -1, "action": ""}
	return _casino_epoch

## 等待人类玩家行动；超时默认抽牌堆顶
func _casino_wait_action(epoch: int, timeout: float) -> String:
	var waited := 0.0
	while waited < timeout and running:
		await _wait(0.1)
		waited += 0.1
		if int(_casino_action.epoch) == epoch:
			return String(_casino_action.action)
	return "top"

## 落进赌场格：全员下注，跑一局炸弹猫，赢家通吃
func _run_casino(p: Dictionary) -> void:
	var alive := hp.filter(func(x) -> bool: return bool(x.alive))
	if alive.size() < 2:
		_log("%s 走进赌场，却无人奉陪，悻悻离开" % p.name, "#8a90a5")
		return
	var pot := 0
	for a in alive:
		var pay: int = mini(CASINO_STAKE, int(a.money))
		a.money = int(a.money) - pay
		pot += pay
	_broadcast_state()
	var order: Array = []
	for a in alive:
		order.append(int(a.peer))
	s_casino_start.rpc("炸弹猫", CASINO_STAKE, pot, order)
	_log("全员下注 %s，奖池 %s，赢家通吃！" % [
		GameData.fmt_money(CASINO_STAKE), GameData.fmt_money(pot)], "#f0a0c0")

	var deck := _bombcat_deck()
	var defuse := {}
	var fish := {}
	var used_peek := {}
	for a in alive:
		defuse[int(a.peer)] = 0
		fish[int(a.peer)] = 0
	var table: Array = order.duplicate()
	var idx := 0
	var guard := 0
	while running and table.size() > 1 and not deck.is_empty() and guard < 64:
		guard += 1
		var peer: int = table[idx]
		var pl := _player_by_peer(peer)
		var epoch := _casino_next_epoch()
		var can_peek: bool = not used_peek.has(peer)
		s_casino_turn.rpc(peer, epoch, defuse, fish, int(deck.size()), not bool(pl.bot) and can_peek)
		var drew := "top"
		if bool(pl.bot):
			await _wait(0.7)
		else:
			drew = await _casino_wait_action(epoch, 9.0)
			while drew == "peek" and running:
				used_peek[peer] = true
				s_casino_peek.rpc_id(peer, _casino_card_name(String(deck.back())))
				s_casino_event.rpc("%s 偷看了牌堆顶" % pl.name, "move")
				epoch = _casino_next_epoch()
				s_casino_turn.rpc(peer, epoch, defuse, fish, int(deck.size()), false)
				drew = await _casino_wait_action(epoch, 7.0)
		if not running:
			return
		var card: String = String(deck.pop_back()) if drew != "bottom" else String(deck.pop_front())
		if card == "bomb":
			if int(defuse[peer]) > 0:
				defuse[peer] = int(defuse[peer]) - 1
				s_casino_event.rpc("%s 摸到炸弹，紧急打出【拆除】化解！" % pl.name, "move")
			else:
				s_casino_event.rpc("%s 摸到炸弹，轰！出局！" % pl.name, "bad")
				table.erase(peer)
		elif card == "defuse":
			defuse[peer] = int(defuse[peer]) + 1
			s_casino_event.rpc("%s 摸到一张【拆除】揣进兜里" % pl.name, "move")
		else:
			fish[peer] = int(fish[peer]) + 1
			s_casino_event.rpc("%s 摸到一条小鱼" % pl.name, "good")
		idx += 1
		if idx >= table.size():
			idx = 0
		await _wait(0.85)
	if not running:
		return

	var winner := -1
	if table.size() == 1:
		winner = int(table[0])
	elif deck.is_empty():
		var best := -1
		for peer2 in order:
			if table.has(peer2) and int(fish[peer2]) > best:
				best = int(fish[peer2])
				winner = int(peer2)
	if winner == -1:
		s_casino_end.rpc(-1, 0)
		_log("赌局不了了之，奖池退还", "#8a90a5")
		return
	var wp := _player_by_peer(winner)
	wp.money = int(wp.money) + pot
	s_casino_end.rpc(winner, pot)
	_log("%s 赢下【炸弹猫】，独吞奖池 %s！" % [wp.name, GameData.fmt_money(pot)], "#f0a0c0")
	_broadcast_state()
	await _wait(2.8)

@rpc("authority", "call_local", "reliable")
func s_casino_start(game_name: String, stake: int, pot: int, order: Array) -> void:
	_close_casino()
	_casino_order = order
	_casino_table_pot = pot
	board.update_casino(pot, "开局中 · %s" % game_name)
	_casino_layer = Control.new()
	_casino_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_casino_layer.z_index = 55
	_casino_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_casino_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_casino_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_casino_layer.add_child(center)
	var panel := UIKit.panel_container(UIKit.PANEL, 14, Color(0.93, 0.30, 0.55), 2, 10)
	panel.custom_minimum_size = Vector2(540, 0)
	center.add_child(panel)
	var pm := UIKit.margins(20, 20, 16, 16)
	panel.add_child(pm)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pm.add_child(v)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	v.add_child(title_row)
	title_row.add_child(UIKit.label("宿舍赌场 · %s" % game_name, 20, Color(0.98, 0.58, 0.78)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)
	_casino_pot_label = UIKit.label("奖池 %s" % GameData.fmt_money(pot), 17, UIKit.ACCENT)
	title_row.add_child(_casino_pot_label)
	v.add_child(UIKit.label("每人入局费 %s · 赢家通吃 · 摸到炸弹没【拆除】就出局" % GameData.fmt_money(stake),
		13, UIKit.TEXT_DIM))
	var rows_panel := UIKit.panel_container(Color(0.10, 0.11, 0.16, 0.6), 10)
	v.add_child(rows_panel)
	var rm := UIKit.margins(10, 10, 6, 6)
	rows_panel.add_child(rm)
	var rows_box := VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 4)
	rm.add_child(rows_box)
	for peer in order:
		var row := PanelContainer.new()
		var sb := UIKit.stylebox(Color(0, 0, 0, 0), 8, Color(0, 0, 0, 0), 1)
		row.add_theme_stylebox_override("panel", sb)
		var m := UIKit.margins(6, 6, 3, 3)
		row.add_child(m)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		m.add_child(h)
		var pidx := order.find(peer)
		h.add_child(UIKit.chip(GameData.PLAYER_COLORS[pidx % GameData.PLAYER_COLORS.size()], 14))
		var nm := UIKit.label(_name_by_peer(int(peer)), 14, UIKit.TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		var dl := UIKit.label("拆除 ×0", 13, Color(0.66, 0.52, 0.95))
		h.add_child(dl)
		var fl := UIKit.label("小鱼 ×0", 13, UIKit.GOOD)
		h.add_child(fl)
		rows_box.add_child(row)
		_casino_rows[int(peer)] = {"root": row, "sb": sb, "defuse_l": dl, "fish_l": fl}
	_casino_deck_label = UIKit.label("牌堆剩余 12 张", 13, UIKit.TEXT_DIM)
	v.add_child(_casino_deck_label)
	_casino_log = RichTextLabel.new()
	_casino_log.scroll_following = true
	_casino_log.custom_minimum_size = Vector2(0, 108)
	_casino_log.add_theme_font_size_override("normal_font_size", 13)
	v.add_child(_casino_log)
	_casino_status = UIKit.label("", 14, UIKit.TEXT)
	_casino_status.custom_minimum_size = Vector2(0, 20)
	v.add_child(_casino_status)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	v.add_child(btn_row)
	_casino_btn_peek = UIKit.button("透视一次（看牌堆顶）", 14)
	_casino_btn_peek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_casino_btn_peek.pressed.connect(func() -> void: _on_casino_action("peek"))
	btn_row.add_child(_casino_btn_peek)
	_casino_btn_top = UIKit.button("抽牌堆顶", 14, "primary")
	_casino_btn_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_casino_btn_top.pressed.connect(func() -> void: _on_casino_action("top"))
	btn_row.add_child(_casino_btn_top)
	_casino_btn_bottom = UIKit.button("抽牌堆底", 14)
	_casino_btn_bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_casino_btn_bottom.pressed.connect(func() -> void: _on_casino_action("bottom"))
	btn_row.add_child(_casino_btn_bottom)
	for b in [_casino_btn_peek, _casino_btn_top, _casino_btn_bottom]:
		b.disabled = true
	_casino_my_epoch = -1
	Fx.play("card", -2.0)

@rpc("authority", "call_local", "reliable")
func s_casino_turn(peer: int, epoch: int, defuse: Dictionary, fish: Dictionary, deck_left: int, interactive: bool) -> void:
	board.update_casino(_casino_table_pot, "轮到 %s · 牌堆剩 %d 张" % [_name_by_peer(peer), deck_left])
	if _casino_layer == null or not is_instance_valid(_casino_layer):
		return
	_casino_deck_label.text = "牌堆剩余 %d 张" % deck_left
	for k in _casino_rows:
		var row: Dictionary = _casino_rows[k]
		var active: bool = int(k) == peer
		var sb: StyleBoxFlat = row.sb
		sb.bg_color = Color(0.93, 0.30, 0.55, 0.12) if active else Color(0, 0, 0, 0)
		sb.border_color = Color(0.93, 0.30, 0.55, 0.6) if active else Color(0, 0, 0, 0)
		row.defuse_l.text = "拆除 ×%d" % int(defuse.get(k, 0))
		row.fish_l.text = "小鱼 ×%d" % int(fish.get(k, 0))
	var my := peer == my_peer and interactive
	_casino_my_epoch = epoch if my else -1
	_casino_btn_top.disabled = not my
	_casino_btn_bottom.disabled = not my
	_casino_btn_peek.disabled = not my or not interactive
	if my:
		_casino_status.text = "轮到你！选择从哪抽一张（透视可先偷看牌堆顶）"
		_casino_status.add_theme_color_override("font_color", UIKit.ACCENT)
	else:
		_casino_status.text = "等待 %s 行动…" % _name_by_peer(peer)
		_casino_status.add_theme_color_override("font_color", UIKit.TEXT_DIM)

@rpc("authority", "call_local", "reliable")
func s_casino_event(text: String, kind: String) -> void:
	if _casino_log == null or not is_instance_valid(_casino_log):
		return
	var col := "#dfe3ee"
	match kind:
		"good": col = "#74d188"
		"bad": col = "#ef7b74"
		"move": col = "#8fb7f2"
	_log_text_append(_casino_log, text, col)
	if kind == "bad":
		Fx.play("bust", -6.0)

func _log_text_append(rt: RichTextLabel, text: String, col: String) -> void:
	var safe := text.replace("[", "［")
	rt.append_text("[color=%s]%s[/color]\n" % [col, safe])

@rpc("authority", "call_remote", "reliable")
func s_casino_peek(card: String) -> void:
	if _casino_log == null or not is_instance_valid(_casino_log):
		return
	_log_text_append(_casino_log, "（透视）牌堆顶是【%s】" % card, "#f0c064")

@rpc("authority", "call_local", "reliable")
func s_casino_end(winner_peer: int, pot: int) -> void:
	_casino_table_pot = 0
	board.update_casino(0, "歇业中")
	if _casino_layer == null or not is_instance_valid(_casino_layer):
		return
	_casino_my_epoch = -1
	for b in [_casino_btn_peek, _casino_btn_top, _casino_btn_bottom]:
		b.disabled = true
	if winner_peer == -1:
		_casino_status.text = "赌局不了了之…"
	elif winner_peer == my_peer:
		_casino_status.text = "你赢下了 %s 奖池，通吃全场！" % GameData.fmt_money(pot)
		_casino_status.add_theme_color_override("font_color", UIKit.ACCENT)
		Fx.play("cash", 0.0)
	else:
		_casino_status.text = "%s 独吞奖池 %s！" % [_name_by_peer(winner_peer), GameData.fmt_money(pot)]
		_casino_status.add_theme_color_override("font_color", Color(0.98, 0.58, 0.78))
	var t := create_tween()
	t.tween_interval(2.6)
	t.tween_callback(_close_casino)

func _on_casino_action(action: String) -> void:
	if _casino_my_epoch < 0:
		return
	var epoch := _casino_my_epoch
	_casino_my_epoch = -1
	for b in [_casino_btn_peek, _casino_btn_top, _casino_btn_bottom]:
		b.disabled = true
	if multiplayer.is_server():
		_casino_action = {"epoch": epoch, "action": action}
	else:
		c_casino_action.rpc_id(1, epoch, action)

@rpc("any_peer", "call_remote", "reliable")
func c_casino_action(epoch: int, action: String) -> void:
	if not multiplayer.is_server():
		return
	_casino_action = {"epoch": epoch, "action": action}

func _close_casino() -> void:
	_casino_my_epoch = -1
	if _casino_layer != null and is_instance_valid(_casino_layer):
		_casino_layer.queue_free()
	_casino_layer = null
	_casino_rows = {}
	_casino_log = null


func _dev_player_edit(edit: Callable) -> void:
	if not multiplayer.is_server():
		return
	var p := _dev_selected()
	if p.is_empty():
		return
	edit.call(p)
	_broadcast_state()
