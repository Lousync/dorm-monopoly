extends Control
## 对局场景。房主是权威服务器：回合推进、掷骰、结算都在房主侧计算，
## 通过 s_* RPC 广播状态快照与动画事件；客户端通过 c_* RPC 上报操作。

signal roll_received

# ---------------- UI 引用 ----------------
var board: BoardView
var dice: DiceView
var banner: Label
var card_panel: Panel
var card_label: Label
var round_label: Label
var players_box: VBoxContainer
var status_label: Label
var roll_btn: Button
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
var _over_shown := false
var _card_tween_id := 0
var _roll_epoch := 0
var _at_roll_epoch := -1
var _shot_path := ""
var _shot_taken := false

# ---------------- 自动化测试 ----------------
var at_mode := ""
var at_rounds := 3
var _at_roll_key := ""

func _ready() -> void:
	my_peer = multiplayer.get_unique_id()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			at_mode = a.substr(11)
		elif a.begins_with("--rounds="):
			at_rounds = maxi(1, int(a.substr(9)))
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
	_refresh_chat()

func _exit_tree() -> void:
	if at_mode != "":
		Engine.time_scale = 1.0

# ================= 界面构建 =================

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var top := HBoxContainer.new()
	top.position = Vector2(12, 8)
	top.size = Vector2(1256, 30)
	add_child(top)
	var title := UIKit.label("宿舍大富翁", 20, UIKit.ACCENT)
	top.add_child(title)
	round_label = UIKit.label("", 17, UIKit.TEXT)
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(round_label)
	var exit_btn := UIKit.button("退出房间", 14)
	exit_btn.pressed.connect(_on_exit)
	top.add_child(exit_btn)

	var board_bg := UIKit.panel(Color(0.078, 0.086, 0.118), 14, Color("#3c4254"), 2)
	board_bg.position = Vector2(10, 46)
	board_bg.size = Vector2(BoardView.BOARD + 16, BoardView.BOARD + 16)
	add_child(board_bg)

	board = BoardView.new()
	board.position = Vector2(18, 54)
	add_child(board)
	board.tile_clicked.connect(_on_tile_clicked)

	# 棋盘中央：回合横幅 + 骰子 + 事件卡
	banner = UIKit.label("", 19, UIKit.TEXT)
	banner.position = Vector2(90, 262)
	banner.size = Vector2(540, 28)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	board.add_child(banner)

	dice = DiceView.new()
	dice.position = Vector2(285, 320)
	board.add_child(dice)

	card_panel = UIKit.panel(Color(0.208, 0.176, 0.098), 12, UIKit.ACCENT, 2)
	card_panel.position = Vector2(130, 438)
	card_panel.size = Vector2(460, 104)
	card_panel.visible = false
	card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(card_panel)
	card_label = UIKit.label("", 15, UIKit.ACCENT)
	card_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_label.offset_left = 14
	card_label.offset_right = -14
	card_label.offset_top = 8
	card_label.offset_bottom = -8
	card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_panel.add_child(card_label)

	# 右侧面板
	var right := VBoxContainer.new()
	right.position = Vector2(762, 46)
	right.size = Vector2(508, 742)
	right.add_theme_constant_override("separation", 8)
	add_child(right)

	var pp := UIKit.panel_container(UIKit.PANEL, 10)
	pp.custom_minimum_size = Vector2(0, 168)
	var pm := UIKit.margins(10, 10, 8, 8)
	pp.add_child(pm)
	right.add_child(pp)
	players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 6)
	pm.add_child(players_box)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	right.add_child(action_row)
	status_label = UIKit.label("", 15, UIKit.TEXT)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	action_row.add_child(status_label)
	roll_btn = UIKit.button("🎲 掷骰子", 17)
	roll_btn.disabled = true
	action_row.add_child(roll_btn)

	info_label = UIKit.label("点击棋盘上的格子可以查看详情", 13, UIKit.TEXT_DIM)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(0, 40)
	right.add_child(info_label)

	var lp := UIKit.panel_container(UIKit.PANEL, 10)
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
		htiles.append({"owner": -1, "level": 0})
	_log("游戏开始！每人初始资金 %s，踏上起点领工资 %s" % [
		GameData.fmt_money(GameData.START_MONEY), GameData.fmt_money(GameData.SALARY)])
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
			_log("%s 在宿委会反省，跳过本回合" % p.name)
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
		_broadcast_state()
		if bool(p.bot):
			_bot_roll_later()
		await roll_received
		if not running:
			return
		_awaiting_roll = 0

		var d1 := randi_range(1, 6)
		var d2 := randi_range(1, 6)
		if at_mode != "":
			print("AT roll %s: %d+%d" % [p.name, d1, d2])
		s_roll.rpc(d1, d2)
		await _wait(1.15)
		if not running:
			return

		if d1 == d2:
			chain += 1
			if chain >= 3:
				_log("%s 连续三次掷出双数，兴奋过度被查寝带走！" % p.name)
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
				_log("%s 踏上起点，领取工资 %s" % [p.name, GameData.fmt_money(GameData.SALARY)])
		p.pos = path[path.size() - 1]
		s_move.rpc(int(p.peer), path, 0.16)
		await _wait(0.3 + path.size() * 0.16)
		if not running:
			return

		await _resolve_tile(p)
		_broadcast_state()
		if not running or not bool(p.alive):
			return
		if d1 == d2:
			_log("%s 掷出双数，奖励再动一次！" % p.name)
			await _wait(0.5)
			continue
		return

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
			if int(t.owner) == -1:
				await _resolve_buy(p, idx)
			elif int(t.owner) == int(p.peer):
				await _resolve_upgrade(p, idx)
			else:
				await _resolve_rent(p, idx)
		"event":
			var card: Dictionary = GameData.EVENTS.pick_random()
			s_card.rpc("【%s】%s" % [d.name, card.t])
			_log("%s 抽到事件：%s" % [p.name, card.t])
			await _wait(1.4)
			await _apply_card(p, card)
		"fine":
			_log("%s 落在【%s】，被强制缴费 %s" % [p.name, d.name, GameData.fmt_money(int(d.amount))])
			_pay(p, int(d.amount), {})
		"go_jail":
			_log("%s 撞上查寝！被押送到宿委会" % p.name)
			_send_to_jail(p)
		"jail":
			_log("%s 来宿委会探监，一切安好" % p.name)
		"rest":
			_log("%s 卧谈会聊到熄灯，免费休息一晚" % p.name)
		"start":
			_log("%s 恰好停在起点，工资已到账！" % p.name)
	if not bool(p.alive):
		_check_end()

func _resolve_buy(p: Dictionary, idx: int) -> void:
	var d: Dictionary = GameData.TILES[idx]
	if int(p.money) < int(d.price):
		_log("%s 的现金买不起【%s】，只能眼馋路过" % [p.name, d.name])
		return
	var ok := await _ask(p, "buy", int(d.price), "购买地产",
		"要买下【%s】吗？\n售价 %s · 基础租金 %s\n你的现金 %s" % [
			d.name, GameData.fmt_money(int(d.price)), GameData.fmt_money(int(d.rent)), GameData.fmt_money(int(p.money))],
		"买下它！")
	if ok and running and int(p.money) >= int(d.price) and int(htiles[idx].owner) == -1:
		p.money = int(p.money) - int(d.price)
		htiles[idx].owner = int(p.peer)
		_log("%s 以 %s 买下了【%s】" % [p.name, GameData.fmt_money(int(d.price)), d.name])

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
		_log("%s 花费 %s 把【%s】升级到 Lv%d" % [p.name, GameData.fmt_money(cost), d.name, int(t.level)])

func _resolve_rent(p: Dictionary, idx: int) -> void:
	var d: Dictionary = GameData.TILES[idx]
	var rent := GameData.rent_for(idx, htiles)
	var op := _player_by_peer(int(htiles[idx].owner))
	if op.is_empty() or not bool(op.alive):
		return
	_log("%s 闯进【%s】，付租金 %s 给 %s" % [p.name, d.name, GameData.fmt_money(rent), op.name])
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
		_log("%s 被查寝抄了近道，直接送宿委会" % p.name)
		_send_to_jail(p)
	if card.has("move_to"):
		var target := int(card.move_to)
		var path := GameData.compute_path_to(int(p.pos), target)
		for idx in path:
			if idx == 0:
				p.money = int(p.money) + GameData.SALARY
				_log("%s 顺路踏上起点，领工资 %s" % [p.name, GameData.fmt_money(GameData.SALARY)])
		p.pos = target
		if not path.is_empty():
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
				t.owner = -1
				t.level = 0
		_log("%s 无力支付 %s，宣告破产出局！名下地产收归学校" % [p.name, GameData.fmt_money(amount)])
		s_card.rpc("%s 破产出局！" % p.name)

func _send_to_jail(p: Dictionary) -> void:
	p.pos = GameData.JAIL_TILE
	p.skip = 1

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

func _net_worth(p: Dictionary) -> int:
	var v := int(p.money)
	for i in htiles.size():
		if int(htiles[i].owner) == int(p.peer):
			v += int(GameData.TILES[i].price) + int(htiles[i].level) * GameData.upgrade_cost(i)
	return v

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

func _end_game(wpeer: int, line: String) -> void:
	running = false
	winner = wpeer
	_awaiting_roll = 0
	_awaiting_prompt = 0
	_log(line)
	_broadcast_state()

# ================= 房主：交互 =================

func _on_roll_pressed() -> void:
	if _awaiting_roll == my_peer:
		roll_received.emit()

func _bot_decide(kind: String, amount: int, money: int) -> bool:
	if kind == "buy":
		return money - amount >= 1500
	if kind == "upgrade":
		return money - amount >= 2000
	return false

## 向目标玩家询问（房主弹窗 / 客户端 RPC / 机器人自动决策），超时视为拒绝
func _ask(p: Dictionary, kind: String, amount: int, title: String, text: String, ok_text: String) -> bool:
	if bool(p.bot):
		return _bot_decide(kind, amount, int(p.money))
	_pending_token += 1
	var tok := _pending_token
	_decision = {"token": -1, "yes": false}
	_awaiting_prompt = int(p.peer)
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
		_log("%s 思考超时，放弃了" % p.name)
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
	for p in hp:
		if int(p.peer) == id and not bool(p.bot):
			p.bot = true
			_log("%s 掉线了，机器人接管他的回合" % p.name)
			if _awaiting_roll == id:
				_bot_roll_later()
			_broadcast_state()
			break

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

func _log(line: String) -> void:
	s_log.rpc(line)

# ================= 全员：接收 RPC =================

@rpc("authority", "call_local", "reliable")
func s_state(state: Dictionary) -> void:
	st = state
	board.render(state)
	round_label.text = "第 %d/%d 轮 · %s" % [int(state.round), int(state.max_rounds), Net.room_name]
	_refresh_players()
	_refresh_actions()
	if String(state.phase) == "ended":
		_show_game_over()
	elif _shot_path != "" and not _shot_taken and int(state.round) >= 2:
		_shot_taken = true
		_take_shot(_shot_path)
	elif at_mode != "" and int(state.round) >= at_rounds and not multiplayer.is_server():
		print("AUTOTEST CLIENT OK round=", state.round)
		get_tree().quit(0)

@rpc("authority", "call_local", "reliable")
func s_roll(d1: int, d2: int) -> void:
	dice.play_roll(d1, d2)

@rpc("authority", "call_local", "reliable")
func s_move(peer: int, path: Array, step_time: float) -> void:
	board.play_move(peer, path, step_time)

@rpc("authority", "call_local", "reliable")
func s_card(text: String) -> void:
	card_label.text = text
	card_panel.visible = true
	_card_tween_id += 1
	var my_id := _card_tween_id
	await get_tree().create_timer(2.6).timeout
	if _card_tween_id == my_id:
		card_panel.visible = false

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
			return p.name
	return "?"

func _refresh_players() -> void:
	for c in players_box.get_children():
		c.queue_free()
	for p in st.get("players", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(16, 16)
		var chip_sb := UIKit.stylebox(GameData.PLAYER_COLORS[int(p.color)], 8, Color(0.9, 0.9, 0.9), 1)
		if not bool(p.alive):
			chip_sb.bg_color = Color(0.35, 0.35, 0.35)
		chip.add_theme_stylebox_override("panel", chip_sb)
		row.add_child(chip)

		var tags := ""
		if int(st.get("turn", -1)) == int(p.peer) and String(st.get("phase", "playing")) == "playing":
			tags += "▶ "
		if bool(p.bot):
			tags += "（机器人）"
		if not bool(p.alive):
			tags += "（破产）"
		elif int(p.skip) > 0:
			tags += "（反省中）"
		var name_l := UIKit.label(p.name + tags, 14, UIKit.TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_l)

		var worth := int(p.money)
		if bool(p.alive):
			row.add_child(UIKit.label(GameData.fmt_money(worth), 14, UIKit.TEXT))
		else:
			row.add_child(UIKit.label("已出局", 14, UIKit.TEXT_DIM))
		players_box.add_child(row)

func _refresh_actions() -> void:
	var phase := String(st.get("phase", "playing"))
	var is_my_roll := String(st.get("await", "")) == "roll" and int(st.get("turn", -1)) == my_peer
	roll_btn.disabled = not is_my_roll
	roll_btn.visible = phase == "playing"
	var turn_name := _name_by_peer(int(st.get("turn", -1)))
	match String(st.get("await", "")):
		"roll":
			status_label.text = "等待 %s 掷骰子…" % turn_name
		"prompt":
			status_label.text = "等待 %s 做决定…" % _name_by_peer(int(st.get("await_peer", -1)))
		_:
			if phase == "playing":
				status_label.text = "%s 的回合" % turn_name
			else:
				status_label.text = "游戏结束"
	if phase != "playing":
		banner.text = "游戏结束"
	else:
		banner.text = status_label.text

	# 自动化测试：轮到自己时自动掷骰（用 roll_epoch 区分连掷的新请求）
	if at_mode != "" and is_my_roll and int(st.get("roll_epoch", -1)) != _at_roll_epoch:
		_at_roll_epoch = int(st.get("roll_epoch", -1))
		_at_auto_roll()

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
		if idx < tiles.size() and int(tiles[idx].get("owner", -1)) != -1:
			owner_name = _name_by_peer(int(tiles[idx].owner))
		var rent := GameData.rent_for(idx, st.get("tiles", []))
		line += "\n%s组 · 售价 %s · 当前租金 %s · 持有：%s" % [
			GameData.GROUP_NAMES.get(d.group, "?"), GameData.fmt_money(int(d.price)),
			GameData.fmt_money(rent), owner_name]
	elif String(d.type) == "fine":
		line += "：%s" % GameData.fmt_money(int(d.amount))
	info_label.text = line

func _show_game_over() -> void:
	if _over_shown:
		return
	_over_shown = true
	for c in get_children():
		if c is ConfirmationDialog:
			c.queue_free()
	over_layer = Control.new()
	over_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_layer.z_index = 50
	add_child(over_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_layer.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var panel := UIKit.panel_container(UIKit.PANEL, 14, UIKit.ACCENT, 2)
	panel.custom_minimum_size = Vector2(420, 200)
	box.add_child(panel)
	var pm := UIKit.margins(20, 20, 20, 20)
	panel.add_child(pm)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 12)
	pm.add_child(pv)
	var wname := "平局"
	if int(st.get("winner", -1)) != -1:
		wname = _name_by_peer(int(st.winner))
	var big := UIKit.label("游戏结束！%s 获胜" % wname, 26, UIKit.ACCENT)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(big)
	var hint := UIKit.label("（最后一条战报见左侧日志）", 14, UIKit.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(hint)
	var back := UIKit.button("返回主菜单", 17)
	back.pressed.connect(_on_exit)
	pv.add_child(back)

func _show_prompt(token: int, title: String, text: String, ok_text: String) -> void:
	if at_mode != "":
		await get_tree().create_timer(0.3).timeout
		_answer(token, true)
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = title
	dlg.dialog_text = text
	dlg.ok_button_text = ok_text
	dlg.cancel_button_text = "算了"
	dlg.exclusive = true
	dlg.min_size = Vector2i(380, 160)
	add_child(dlg)
	dlg.confirmed.connect(_on_prompt_ok.bind(token, dlg))
	dlg.canceled.connect(_on_prompt_no.bind(token, dlg))
	dlg.close_requested.connect(_on_prompt_no.bind(token, dlg))
	dlg.popup_centered()

func _on_prompt_ok(token: int, dlg: ConfirmationDialog) -> void:
	_answer(token, true)
	dlg.queue_free()

func _on_prompt_no(token: int, dlg: ConfirmationDialog) -> void:
	_answer(token, false)
	dlg.queue_free()

func _refresh_chat() -> void:
	# 对局场景不重复展示聊天框历史，聊天走日志即可；预留接口
	pass

func _on_conn_lost(reason: String) -> void:
	Net.last_error = reason
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_exit() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _take_shot(path: String) -> void:
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT SAVED ", path)
	get_tree().quit(0)
