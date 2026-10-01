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
var banner: Label
var banner_pill: PanelContainer
var card_panel: PanelContainer
var card_label: Label
var round_label: Label
var status_label: Label
var roll_btn: Button
var follow_btn: Button
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
	for a in OS.get_cmdline_user_args():
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
	board.seat_clicked.connect(func(_peer: int) -> void: pass)  # 转视角已在视图内处理；预留扩展

	# 顶栏：标题 / 回合横幅 / 轮次 / 退出
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 12
	top.offset_right = -12
	top.offset_top = 6
	top.offset_bottom = 40
	add_child(top)
	var title := UIKit.title_label("宿舍大富翁", 20)
	top.add_child(title)

	banner_pill = UIKit.panel_container(Color(0.058, 0.062, 0.098, 0.88), 12,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.5), 1, 8)
	banner_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(banner_pill)
	var bm := UIKit.margins(14, 3, 3, 3)
	bm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_pill.add_child(bm)
	banner = UIKit.label("", 16, UIKit.TEXT)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bm.add_child(banner)

	round_label = UIKit.label("", 15, UIKit.TEXT)
	top.add_child(round_label)
	var exit_btn := UIKit.button("退出房间", 14, "danger")
	exit_btn.pressed.connect(_on_exit)
	top.add_child(exit_btn)

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


	# 底部行动条（屏幕层，正对自己座位）：状态 / 镜头与视角控制 / 转盘
	var bar := UIKit.panel_container(Color(0.058, 0.062, 0.098, 0.85), 14, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.7), 1, 6)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -400
	bar.offset_right = 400
	bar.offset_top = -64
	bar.offset_bottom = -10
	add_child(bar)
	var barm := UIKit.margins(12, 8, 12, 8)
	bar.add_child(barm)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 8)
	barm.add_child(bar_row)
	status_label = UIKit.label("", 15, UIKit.TEXT)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar_row.add_child(status_label)
	follow_btn = UIKit.button("跟随", 13)
	follow_btn.toggle_mode = true
	follow_btn.button_pressed = true
	follow_btn.toggled.connect(_on_follow_toggled)
	bar_row.add_child(follow_btn)
	var over_btn := UIKit.button("全桌", 13)
	over_btn.pressed.connect(func() -> void:
		board.fit_overview()
		follow_btn.button_pressed = false
	)
	bar_row.add_child(over_btn)
	# 视角切换：对局中镜头跟着棋子走时座位卡常在屏幕外，这里提供常驻入口
	for seat_btn in [["左家", 1], ["对家", 2], ["右家", 3]]:
		var sb_btn := UIKit.button(seat_btn[0], 13)
		var edge: int = seat_btn[1]
		sb_btn.pressed.connect(func() -> void:
			board.rotate_to_edge(edge)
			follow_btn.button_pressed = false
		)
		bar_row.add_child(sb_btn)
	roll_btn = UIKit.button("转动转盘", 17, "primary")
	roll_btn.disabled = true
	bar_row.add_child(roll_btn)

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
	log_toggle = UIKit.button("战报 ▾", 13)
	log_toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_toggle.offset_left = -106
	log_toggle.offset_right = -12
	log_toggle.offset_top = 48
	log_toggle.offset_bottom = 76
	log_toggle.pressed.connect(_toggle_log)
	add_child(log_toggle)

	log_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 6)
	log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_panel.offset_left = -352
	log_panel.offset_right = -12
	log_panel.offset_top = 48
	log_panel.offset_bottom = -12
	log_panel.visible = false
	add_child(log_panel)
	var lm := UIKit.margins(10, 10, 8, 8)
	log_panel.add_child(lm)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	lm.add_child(lv)
	lv.add_child(UIKit.label("战报 / 聊天", 13, UIKit.TEXT_DIM))
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
		})
	htiles = []
	for i in GameData.TILES.size():
		htiles.append({"owner": GameData.NO_OWNER, "level": 0})
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
			return
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
		return

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
		})
	var await_state := ""
	var await_peer := -1
	if _awaiting_roll != 0:
		await_state = "roll"
		await_peer = _awaiting_roll
	elif _awaiting_prompt != 0:
		await_state = "prompt"
		await_peer = _awaiting_prompt
	s_state.rpc({
		"phase": "ended" if not running else "playing",
		"round": round_no, "max_rounds": GameData.MAX_ROUNDS,
		"turn": int(hp[turn_i].peer),
		"await": await_state, "await_peer": await_peer,
		"players": plist, "tiles": htiles,
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
	round_label.text = "第 %d/%d 轮 · %s" % [int(state.round), int(state.max_rounds), Net.room_name]
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
	await get_tree().create_timer(WheelView.SPIN_TIME).timeout
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
	await get_tree().create_timer(2.5).timeout
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
	board.world_log_line(line)

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
	if board.rank_count() == 0:
		var pls2: Array = st.get("players", [])
		if not pls2.is_empty():
			board.build_rank(pls2)
	var tiles_arr: Array = st.get("tiles", [])
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
		# 顶部战况面板：现金 / 地产数 / 身家（与房主 _net_worth 同一公式）
		var prop_n := 0
		var worth := int(p.money)
		for i in tiles_arr.size():
			var td: Dictionary = tiles_arr[i]
			if int(td.get("owner", GameData.NO_OWNER)) == peer:
				prop_n += 1
				worth += int(GameData.TILES[i].price) + int(td.get("level", 0)) * GameData.upgrade_cost(i)
		board.update_rank_row(peer, int(p.money), "地产 ×%d · 身家 %s" % [prop_n, GameData.fmt_money(worth)])

		if not bool(p.alive):
			row.money_l.text = "已出局"
			row.money_l.add_theme_color_override("font_color", UIKit.TEXT_DIM)

	for peer in _player_rows.keys():
		if not seen.has(peer):
			_player_rows.erase(peer)  # 座位是桌面世界的一部分，保留在桌上（掉线/出局只改显示）

func _refresh_actions() -> void:
	var phase := String(st.get("phase", "playing"))
	var await_state := String(st.get("await", ""))
	var is_my_roll := await_state == "roll" and int(st.get("turn", -1)) == my_peer
	roll_btn.disabled = not is_my_roll
	roll_btn.visible = phase == "playing"
	UIKit.restyle_button(roll_btn, "primary" if is_my_roll else "normal")
	var turn_name := _name_by_peer(int(st.get("turn", -1)))
	match await_state:
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
	_set_banner(status_label.text)

	# 自动化测试：轮到自己时自动掷骰（用 roll_epoch 区分连掷的新请求）
	if at_mode != "" and is_my_roll and int(st.get("roll_epoch", -1)) != _at_roll_epoch:
		_at_roll_epoch = int(st.get("roll_epoch", -1))
		_at_auto_roll()

func _set_banner(text: String) -> void:
	if banner.text == text:
		return
	banner.text = text
	banner_pill.modulate.a = 0.0
	banner_pill.pivot_offset = banner_pill.size * 0.5
	banner_pill.scale = Vector2(0.96, 0.96)
	var tw := create_tween()
	tw.tween_property(banner_pill, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(banner_pill, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_follow_toggled(on: bool) -> void:
	board.auto_follow = on
	if on:
		board.go_home_follow(my_peer)  # 转回自己视角并恢复行动跟随

func _unhandled_input(event: InputEvent) -> void:
	# 空格：视角转回自己座位；Tab：循环切到下一家视角
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_SPACE:
			board.rotate_home()
		elif k.keycode == KEY_TAB:
			board.rotate_next()
			follow_btn.button_pressed = false

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
		board.world_log_line("[color=#7f8699]%s[/color]" % line.replace("[", "［"))

func _on_conn_lost(reason: String) -> void:
	Net.last_error = reason
	Fx.go_to("res://scenes/main_menu.tscn")

func _on_exit() -> void:
	Net.leave()
	Fx.go_to("res://scenes/main_menu.tscn")

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

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
