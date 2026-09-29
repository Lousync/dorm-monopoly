extends Control
## 对局场景。房主是权威服务器：回合推进、掷骰、结算都在房主侧计算，
## 通过 s_* RPC 广播状态快照与动画事件；客户端通过 c_* RPC 上报操作。
##
## 表现层：112 格大棋盘（缩放/平移/自动跟随）、横幅与事件卡弹入动画、
## 金额飘字与滚动、聊天并入战报、结算排名 + 彩带、程序合成音效。

signal roll_received

const DICE_WAIT := 1.35   # 与 DiceView.ROLL_TIME 保持同步
const STEP_TIME := 0.15   # 每格跳子时长

# ---------------- UI 引用 ----------------
var board: BoardView
var dice: DiceView
var banner: Label
var banner_pill: PanelContainer
var card_panel: PanelContainer
var card_label: Label
var round_label: Label
var players_box: VBoxContainer
var status_label: Label
var roll_btn: Button
var follow_btn: Button
var info_label: Label
var log_text: RichTextLabel
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

# ---------------- 表现层状态 ----------------
var _player_rows := {}      # peer -> {root,sb,chip,name_l,money_l,shown,tw}
var _chat_shown := 0
var _prompt_dlg: Control
var _prompt_tw: Tween
var _prompt_token := -1

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

	# 棋盘视口：占据顶栏以下全部空间（右侧留出面板宽度给镜头居中/全图适配）
	board = BoardView.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.offset_top = 44
	board.overlay_right = 506
	board.overlay_bottom = 130
	add_child(board)
	board.tile_clicked.connect(_on_tile_clicked)

	# 顶栏
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 12
	top.offset_right = -12
	top.offset_top = 6
	top.offset_bottom = 40
	add_child(top)
	var title := UIKit.title_label("宿舍大富翁", 20)
	top.add_child(title)
	round_label = UIKit.label("", 17, UIKit.TEXT)
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(round_label)
	var exit_btn := UIKit.button("退出房间", 14, "danger")
	exit_btn.pressed.connect(_on_exit)
	top.add_child(exit_btn)

	# 棋盘上方 HUD：横幅胶囊 / 事件卡 / 骰子（屏幕空间）
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)

	banner_pill = UIKit.panel_container(Color(0.058, 0.062, 0.098, 0.88), 12,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.5), 1, 8)
	banner_pill.position = Vector2(107, 50)
	banner_pill.size = Vector2(560, 36)
	banner_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(banner_pill)
	var bm := UIKit.margins(14, 14, 3, 3)
	bm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_pill.add_child(bm)
	banner = UIKit.label("", 16, UIKit.TEXT)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bm.add_child(banner)

	card_panel = UIKit.panel_container(Color(0.16, 0.14, 0.08, 0.94), 12, UIKit.ACCENT, 2, 10)
	card_panel.position = Vector2(107, 96)
	card_panel.size = Vector2(560, 104)
	card_panel.visible = false
	card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(card_panel)
	var cm := UIKit.margins(16, 16, 8, 8)
	cm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_panel.add_child(cm)
	card_label = UIKit.label("", 15, UIKit.ACCENT)
	card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cm.add_child(card_label)

	dice = DiceView.new()
	dice.position = Vector2(24, 706)
	hud.add_child(dice)

	# 右侧面板
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -494
	right.offset_right = -12
	right.offset_top = 48
	right.offset_bottom = -12
	right.add_theme_constant_override("separation", 8)
	add_child(right)

	var pp := UIKit.panel_container(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 6)
	pp.custom_minimum_size = Vector2(0, 186)
	var pm := UIKit.margins(8, 8, 6, 6)
	pp.add_child(pm)
	right.add_child(pp)
	players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 4)
	pm.add_child(players_box)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	right.add_child(action_row)
	status_label = UIKit.label("", 15, UIKit.TEXT)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	action_row.add_child(status_label)
	follow_btn = UIKit.button("跟随", 13)
	follow_btn.toggle_mode = true
	follow_btn.button_pressed = true
	follow_btn.toggled.connect(_on_follow_toggled)
	action_row.add_child(follow_btn)
	var over_btn := UIKit.button("全图", 13)
	over_btn.pressed.connect(func() -> void:
		board.fit_overview()
		follow_btn.button_pressed = false
	)
	action_row.add_child(over_btn)
	roll_btn = UIKit.button("🎲 掷骰子", 17, "primary")
	roll_btn.disabled = true
	action_row.add_child(roll_btn)

	info_label = UIKit.label("滚轮缩放 · 拖拽平移棋盘 · 点击格子查看详情", 13, UIKit.TEXT_DIM)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(0, 40)
	right.add_child(info_label)

	var lp := UIKit.panel_container(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 6)
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lm := UIKit.margins(10, 10, 8, 8)
	lp.add_child(lm)
	right.add_child(lp)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	lm.add_child(lv)
	lv.add_child(UIKit.label("战报", 13, UIKit.TEXT_DIM))
	log_text = RichTextLabel.new()
	log_text.scroll_following = true
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.add_theme_font_size_override("normal_font_size", 13)
	lv.add_child(log_text)

	var chat_row := HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 6)
	right.add_child(chat_row)
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
	_log("掷出双数可以再动一次；连续三双会被查寝抓走哦")
	await _wait(1.5)
	_broadcast_state()
	if at_mode == "host":
		get_tree().create_timer(3.0).timeout.connect(_autotest_watch)
	_run_game()

func _autotest_watch() -> void:
	# 房主在到达目标轮数后稍等片刻再退出，给客户端留出收尾时间
	while running and round_no < at_rounds:
		await _wait(0.5)
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

		var d1 := randi_range(1, 6)
		var d2 := randi_range(1, 6)
		if at_mode != "":
			print("AT roll %s: %d+%d" % [p.name, d1, d2])
		s_roll.rpc(d1, d2)
		await _wait(DICE_WAIT)
		if not running:
			return

		if d1 == d2:
			chain += 1
			if chain >= 3:
				_log("%s 连续三次掷出双数，兴奋过度被查寝带走！" % p.name, "#c9a6ff")
				s_card.rpc("%s 连续三双，被查寝带走！" % p.name, "jail")
				_send_to_jail(p)
				_broadcast_state()
				await _wait(1.0)
				return
		else:
			chain = 0

		var path := GameData.compute_path(int(p.pos), d1 + d2)
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
		if d1 == d2:
			_log("%s 掷出双数，奖励再动一次！" % p.name, "#f0c064")
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
func s_roll(d1: int, d2: int) -> void:
	dice.play_roll(d1, d2)
	if d1 == d2:
		_flair_doubles()

func _flair_doubles() -> void:
	await get_tree().create_timer(DiceView.ROLL_TIME).timeout
	if not is_inside_tree():
		return
	Fx.float_text(self, dice.position + dice.size * Vector2(0.5, 0.1), "双数！再来一次", UIKit.ACCENT, 21)

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
	for p in st.get("players", []):
		var peer := int(p.peer)
		seen[peer] = true
		var row: Dictionary = _player_rows.get(peer, {})
		if row.is_empty():
			row = _make_player_row(p)
			_player_rows[peer] = row
			players_box.add_child(row.root)
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

		var chip_sb: StyleBoxFlat = row.chip.get_theme_stylebox("panel")
		chip_sb.bg_color = Color(0.35, 0.35, 0.35) if not bool(p.alive) else GameData.PLAYER_COLORS[int(p.color)]

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
		if not bool(p.alive):
			row.money_l.text = "已出局"
			row.money_l.add_theme_color_override("font_color", UIKit.TEXT_DIM)

	for peer in _player_rows.keys():
		if not seen.has(peer):
			_player_rows[peer].root.queue_free()
			_player_rows.erase(peer)

func ml_needs_init(_row: Dictionary) -> bool:
	# 新行首次填充文本
	return true

func _make_player_row(p: Dictionary) -> Dictionary:
	var root := PanelContainer.new()
	var sb := UIKit.stylebox(Color(0.52, 0.56, 0.68, 0.05), 8, Color(0, 0, 0, 0), 1)
	root.add_theme_stylebox_override("panel", sb)
	var m := UIKit.margins(8, 8, 5, 5)
	root.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	m.add_child(row)
	var chip := UIKit.chip(GameData.PLAYER_COLORS[int(p.color)], 16)
	row.add_child(chip)
	var name_l := UIKit.label(String(p.name), 14, UIKit.TEXT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_l)
	var money_l := UIKit.label(GameData.fmt_money(int(p.money)), 14, UIKit.TEXT)
	row.add_child(money_l)
	return {"root": root, "sb": sb, "chip": chip, "name_l": name_l, "money_l": money_l,
		"shown": int(p.money), "tw": null, "peer": int(p.peer)}

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
				status_label.text = "轮到你掷骰子！"
				if not board.is_showing_deck_card():
					board.focus_peer(my_peer)
			else:
				status_label.text = "等待 %s 掷骰子…" % turn_name
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
		board.focus_peer(my_peer, true)

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
	var line := "【%s】%s" % [d.name, GameData.TILE_DESC.get(d.type, "")]
	if String(d.type) == "property":
		var owner_name := "无主"
		var tiles: Array = st.get("tiles", [])
		if idx < tiles.size() and int(tiles[idx].get("owner", GameData.NO_OWNER)) != GameData.NO_OWNER:
			owner_name = _name_by_peer(int(tiles[idx].owner))
		var rent := GameData.rent_for(idx, st.get("tiles", []))
		line += "\n%s组 · 售价 %s · 当前租金 %s · 持有：%s" % [
			GameData.GROUP_NAMES.get(d.group, "?"), GameData.fmt_money(int(d.price)),
			GameData.fmt_money(rent), owner_name]
	elif String(d.type) == "fine" or String(d.type) == "bonus":
		line += "：%s" % GameData.fmt_money(int(d.amount))
	info_label.text = line

# ================= 弹窗与结算 =================

func _show_game_over() -> void:
	if _over_shown:
		return
	_over_shown = true
	_close_prompt()
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
	var big := UIKit.title_label("游戏结束！%s 获胜" % wname, 26)
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
	board.focus_grid(27, 0.8, true)
	await get_tree().create_timer(0.15).timeout
	board.play_deck_card("机会", "good", "帮宿管阿姨搬了一下午矿泉水，辛苦费 +600")
	# 连拍三帧，避开 3 倍速下真实抽卡与摆拍的相互干扰
	for i in 3:
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var p := path if i == 0 else path.replace(".png", "_%d.png" % i)
		get_viewport().get_texture().get_image().save_png(p)
		print("SHOT SAVED ", p)
	get_tree().quit(0)
