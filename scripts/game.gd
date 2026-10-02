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
var action_bar: PanelContainer   # 操作条：转动转盘 / 道具按钮（与视角无关，见 fix/v0.0.2）
var ph1_lab: Label
var ph2_lab: Label
var log_head: Label
var opt_btn: Button
var menu_layer: Control
var menu_dim: ColorRect
var menu_wraps := {}          # 面板名 -> 外层全屏容器（切换时连外层一起切，见 _menu_show）
var menu_panel: PanelContainer
var menu_state: Label
var settings_panel: PanelContainer
var confirm_panel: PanelContainer
var confirm_note: Label
var vol_slider: HSlider
var mute_check: CheckButton
var tier_title: Label          # 对局内设置面板：「操作限时」小标题（只跟 chips 一侧显隐）
var tier_row: HBoxContainer    # 对局内设置面板：挡位 chips（房主）
var tier_readonly: Label       # 对局内设置面板：挡位只读文本（客户端）
var pause_mask: ColorRect
var audio_volume := 1.0
var audio_mute := false

# ---------------- 开局设置（房主权威，见 docs/gameplay/开局设置.md §三之一） ----------------
const _WINDOW_TICK := 0.1            # 操作窗口的探测分片（秒）；也是 _ask 的应答粒度：
                                     # 玩家点了「买/不买」最多晚这么久被房主发现
const _BAR_LEAD := 1.0               # 弹窗倒计时条比窗口早这么多秒到底（沿袭基线的既有手感，
                                     # 条子归零即提交「拒绝」，见 _prompt_bar_arm）
var _settings: GameSettings          # 房主：来自大厅配置；客户端：从状态快照同步
var _timeout_rev := 0                # 挡位变化计数：等待中的环节据此重计时

# ---------------- 道具系统（host 状态，详见 docs/gameplay/道具系统.md） ----------------
var shops := {}            # tile_idx -> {slots: [id×3]}，每家小卖部独立货架
var items_consumed := {}   # 焚毁标记：一次性道具用后不回池（id -> true）
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
var target_picker: Control
var target_btn_box: VBoxContainer
var shop_bar: PanelContainer
var shop_btns: Array = []
var shop_refresh_btn: Button
var _shop_btn_sig := ""     # 小卖部「买」按钮刷新签名（避免每帧重建）
var card_gallery: Control
var card_gallery_flag := false

# ---------------- 黑市（host 状态，§8；仅由机会卡进入，地皮计价） ----------------
var blackshop_enabled := true   # 开局设置开关（面板后续批次接；关闭后机会卡池过滤该事件）
var _black_peer := 0            # 正在逛黑市的玩家（0 = 无）
var _black_epoch := 0
var _black_slots: Array = ["", "", ""]   # 3 栏货架（紫/橙）
var _black_pay_mode := ""       # "" / "buy" / "refresh" / "exit"：正在选地皮支付
var _black_pay_slot := -1
var _black_pay_need := 0        # 需交地皮数
var _black_pay_got := 0         # 已交地皮数
var black_bar: PanelContainer
var black_btns: Array = []
var black_hint: Label
var black_picker: Control
var black_picker_box: VBoxContainer
var _black_sig := ""

# ---------------- 格详情卡 / 规则说明（左下角，见 rules_panel.gd） ----------------
var info_panel: PanelContainer
var info_title: Label
var info_body: Label
var info_sb: StyleBoxFlat
var rules_btn: Button            # 收起态：左下角「📖 规则说明」按钮
var rules_panel: PanelContainer  # 展开态：分页规则面板（原位向上展开）
var rules_body: RichTextLabel
var rules_tabs := {}             # 分页 key -> 按钮
var rules_open := false
var rules_tab := ""
var dock_plate: Panel            # 底栏底板（把阶段条与操作条包成一整块，见 _place_dock）
var roster_box: VBoxContainer      # 右栏名册（固定 4 行，见 _refresh_rail）
var roster_rows: Array = []
var _rail_sig := ""
var _log_flash_tw: Tween          # 新战报时头部闪金（沉浸感）
var _pulse_t := 0.0               # 「该你掷了」按钮的呼吸相位（持续动画走 _process）
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
var casino: Node             # 赌桌小游戏（scripts/casino.gd，见 _ready）
var dev: Node                # 开发者面板 / 截图工具（scripts/dev_tools.gd，见 _ready）
var turn_i := 0
var round_no := 1
var _turns_taken := 0       # 本圈已行动人数：走满一圈（存活者各行动一次）记一轮
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
var _prompt_bar: ProgressBar
var _prompt_token := -1

# ---------------- 自动化测试 ----------------
var at_mode := ""
var at_rounds := 3
var at_tier := ""    # --tier= 指定的挡位（客户端 autotest 据此断言收到了正确的快照）
var _at_roll_epoch := -1
var _at_client_done := false   # 客户端 autotest 已收尾（防 quit() 生效前重复打印）

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
		elif a.begins_with("--tier="):
			# 自动回归用：把挡位写进大厅配置，下面的 _settings 副本因此取到它。
			# 必须早于 _build_ui（规则面板按挡位取秒数）与 _host_setup（房主开局读挡位）。
			var tid := a.substr(7)
			if GameSettings.TIERS.has(tid):
				at_tier = tid
				if Net.game_settings != null:
					Net.game_settings.timeout_tier = tid
			else:
				print("--tier 非法挡位，忽略：", tid)
		elif a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-rot="):
			_shot_rot = clampi(int(a.substr(11)), 0, 3)
	if at_mode != "":
		Engine.time_scale = 3.0

	# 开发者面板/截图工具独立成子节点。必须先于 _build_ui：面板是 _build_ui 建的
	dev = preload("res://scripts/dev_tools.gd").new()
	dev.name = "DevTools"
	dev.g = self
	add_child(dev)

	# 房主用自己的配置副本（中途改动不回写大厅），客户端先取默认值、随后由快照覆盖。
	# 必须早于 _build_ui：规则说明面板构建时就要按本局挡位取秒数（见 RulesPanel.build）
	_settings = Net.game_settings.copy() if Net.game_settings != null else GameSettings.new()

	_build_ui()

	# 赌桌小游戏独立成子节点（board 已就绪；两端都在这里建同名节点，
	# 保证 s_casino_* / c_casino_action 的 RPC 路径一致）
	casino = preload("res://scripts/casino.gd").new()
	casino.name = "CasinoTable"
	casino.g = self
	add_child(casino)

	# 设置面板上一段已建好（_build_ui 在前），此处按身份定「操作限时」行显隐——
	# 否则两行同时可见，要等首次改挡才归位
	_refresh_tier_ui()

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
		dev.enabled = bool(cfg.get_value("dev", "enabled", false)) or dev_flag
	if at_mode != "" and not dev_flag:
		dev.enabled = false
	_apply_audio()
	_hud_intro()
	dev.apply_mode()
	for a2 in OS.get_cmdline_user_args():
		if a2 == "--menu-probe":
			dev.menu_probe = true
	if dev.menu_probe:
		dev.menu_probe_run()
	for a3 in OS.get_cmdline_user_args():
		if a3 == "--card-gallery":
			card_gallery_flag = true
	if card_gallery_flag:
		dev.enabled = true
		dev.apply_mode()
		_open_card_gallery()

func _exit_tree() -> void:
	if at_mode != "":
		Engine.time_scale = 1.0

# ================= 界面构建 =================

func _build_ui() -> void:
	# 控件构建已搬到 TableHud（原先 500 行都在这里）；控件直接写回本类同名成员
	TableHud.build_play_ui(self)
	# 左下角「📖 规则说明」：收起是按钮、点开原位向上展开分页规则（文案见 RulesText）
	RulesPanel.build(self)
func _build_hp() -> Array:
	var out := []
	var live := multiplayer.get_peers()
	for p in Net.players:
		var peer := int(p.peer)
		var gone: bool = peer != 1 and not live.has(peer)
		out.append({
			"peer": peer, "name": String(p.name), "color": int(p.color),
			"bot": bool(p.bot) or gone, "money": GameData.START_MONEY,
			"pos": 0, "alive": true, "skip": 0, "sleep": 0,
			"stamina": 3, "items": [], "item_used": false, "cheat_roll": -1,
			"hot_chain": 0,
		})
	return out

func _host_setup() -> void:
	running = true
	hp = _build_hp()
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
			if _rounds_exhausted():
				return
			continue
		if int(p.skip) > 0:
			p.skip = int(p.skip) - 1
			_log("%s 在宿委会反省，跳过本回合" % p.name, "#c9a6ff")
			_broadcast_state()
			await _wait(1.0)
			if not running:
				return
			_advance_turn()
			if _rounds_exhausted():
				return
			continue
		await _play_turn(p)
		if not running:
			return
		_advance_turn()
		if _rounds_exhausted():
			return

## 轮数用尽 → 按身家结算。回合计数已由 _advance_turn 按圈维护（见 fix/v0.0.2）。
func _rounds_exhausted() -> bool:
	if round_no <= GameData.MAX_ROUNDS:
		return false
	_end_by_wealth()
	return true

func _advance_turn() -> void:
	for k in hp.size():
		turn_i = (turn_i + 1) % hp.size()
		if bool(hp[turn_i].alive):
			break
	# 每走完一圈（所有存活者各行动一次）记一轮。
	# 不能用 turn_i == 0 判定：0 号位是房主，他破产或被查寝跳过时那一圈永远
	# 轮不到 0，round_no 会彻底冻结 → MAX_ROUNDS 结算不可达、对局可能永不结束，
	# _autotest_watch 也会挂死（见 fix/v0.0.2）。
	_turns_taken += 1
	var alive := _alive_count()
	if alive > 0 and _turns_taken >= alive:
		_turns_taken = 0
		round_no += 1

func _alive_count() -> int:
	var n := 0
	for p in hp:
		if bool(p.alive):
			n += 1
	return n

## 记录一次转盘结果对「连续三次 10+ 被查寝」的累计，返回是否应触发查寝。
## 计数必须存在玩家表里跨回合保留：原来 chain 是 _play_turn 的局部变量，每回合
## 清零，而重转的 while 只在 12 点时才循环，于是这条开局就广播的规则
##（「连续三次 10+ 会被查寝」）实际只在同回合连开三个 12 时才触发（见 fix/v0.0.2）。
func _note_roll_hot(p: Dictionary, roll: int) -> bool:
	if roll < 10:
		p.hot_chain = 0
		return false
	p.hot_chain = int(p.get("hot_chain", 0)) + 1
	if int(p.hot_chain) < 3:
		return false
	p.hot_chain = 0
	return true

func _play_turn(p: Dictionary) -> void:
	if at_mode != "":
		print("AT turn start: r%d %s" % [round_no, p.name])
	var sleeping := _is_sleeping(p)
	if sleeping:
		_log("%s 在小黑屋反省，本回合强制保守托管" % p.name, "#c9a6ff")
	_item_turn_start(p)  # 休眠=保守托管：被动与自动结算照常（§1）
	_broadcast_state()
	while running:
		_awaiting_roll = int(p.peer)
		_roll_epoch += 1
		var epoch := _roll_epoch
		_broadcast_state()
		if bool(p.bot) or sleeping:
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

		if _note_roll_hot(p, roll):
			_log("%s 连续三次转到 10 点以上，兴奋过度被查寝带走！" % p.name, "#c9a6ff")
			s_card.rpc("%s 连续三次 10+，被查寝带走！" % p.name, "jail")
			_send_to_jail(p)
			_broadcast_state()
			await _wait(1.0)
			return

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
	if sleeping:
		p.sleep = maxi(0, int(p.get("sleep", 0)) - 1)  # 休眠一回合到期
		_broadcast_state()
		return
	await _item_phase(p)

## 真人玩家发呆太久由系统代掷，避免整局卡死
func _arm_roll_timeout(epoch: int, peer: int) -> void:
	var timed_out := await _await_turn_window("roll",
		func() -> bool: return _roll_epoch == epoch and _awaiting_roll == peer)
	if timed_out:
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
			if bool(t.get("soil", false)):
				if _immune_debuff(p):
					_log("%s 的【空想者的香皂】挡下了焦土捐款，进度不涨" % p.name, "#8fb7f2")
					await _wait(0.4)
					return
				var amt: int = mini(ItemData.SOIL_DONATE, int(p.money))
				p.money = int(p.money) - amt
				t.soil_prog = int(t.get("soil_prog", 0)) + amt
				var target: int = int(GameData.TILES[idx].price)
				_log("%s 往【%s】的焦土投了 %s 捐款（%d/%d）" % [p.name,
					String(GameData.TILES[idx].name), GameData.fmt_money(amt), int(t.soil_prog), target], "#8a90a5")
				if int(t.soil_prog) >= target:
					t.soil = false
					t.owner = GameData.NO_OWNER
					t.level = 0  # 恢复为无主：等级清零，重新购买从 Lv0 起
					t.soil_prog = 0
					_log("【%s】的焦土修复完成，恢复为无主地产！" % String(GameData.TILES[idx].name), "#74d188")
			elif int(t.owner) == GameData.NO_OWNER:
				await _resolve_buy(p, idx)
			elif int(t.owner) == int(p.peer):
				await _resolve_upgrade(p, idx)
			else:
				await _resolve_rent(p, idx)
		"event":
			var card: Dictionary = _draw_event(String(d.name))
			# 仿桌游：机会/命运卡从棋盘中央对应牌堆抽出展示
			s_card.rpc(String(card.t), _card_kind(card), String(d.name))
			_log("%s 抽到事件：%s" % [p.name, card.t])
			await _wait(BoardView.DECK_CARD_TIME + 0.1)
			await _apply_card(p, card)
		"fine":
			if _immune_debuff(p):
				_log("%s 的【空想者的香皂】挡下了强制缴费" % p.name, "#8fb7f2")
				await _wait(0.4)
			else:
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
			await casino.run(p)
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

## 按格子类型（机会/命运）取卡池；黑市关闭时过滤进入黑市的卡（§8）
func _draw_event(kind: String) -> Dictionary:
	var pool := GameData.events_for(kind)
	if not blackshop_enabled:
		pool = pool.filter(func(c: Dictionary) -> bool: return not c.has("enter_blackshop"))
	if pool.is_empty():
		pool = GameData.events_for(kind)
	return pool.pick_random()

func _card_kind(card: Dictionary) -> String:
	if card.has("go_jail"):
		return "jail"
	if card.has("move_steps"):
		return "move"
	if card.has("money"):
		return "good" if int(card.money) >= 0 else "bad"
	if card.has("from_each") or card.has("gain_item") or card.has("gain_item_quality"):
		return "good"
	if card.has("to_each"):
		return "bad"
	if card.has("enter_blackshop"):
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
		elif _immune_debuff(p):
			_log("%s 的【空想者的香皂】挡下了扣钱" % p.name, "#8fb7f2")
		else:
			_pay(p, -m, {})
	if card.has("from_each"):
		for o in hp:
			if int(o.peer) != int(p.peer) and bool(o.alive):
				if _immune_debuff(o):
					_log("%s 的【空想者的香皂】挡下了红包" % o.name, "#8fb7f2")
					continue
				var amt: int = mini(int(card.from_each), int(o.money))
				o.money = int(o.money) - amt
				p.money = int(p.money) + amt
	if card.has("to_each") and not _immune_debuff(p):
		for o in hp:
			if int(o.peer) != int(p.peer) and bool(o.alive) and int(p.money) > 0:
				var amt2: int = mini(int(card.to_each), int(p.money))
				p.money = int(p.money) - amt2
				o.money = int(o.money) + amt2
	if card.has("go_jail"):
		if _immune_debuff(p):
			_log("%s 的【空想者的香皂】挡下了查寝" % p.name, "#8fb7f2")
		else:
			_log("%s 被查寝抄了近道，直接送宿委会" % p.name, "#c9a6ff")
			_send_to_jail(p)
	if card.has("move_steps"):
		if int(card.move_steps) < 0 and _immune_debuff(p):
			_log("%s 的【空想者的香皂】免除了后退" % p.name, "#8fb7f2")
			return
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
	if card.has("gain_item"):
		_grant_card_item(p, String(card.gain_item))
	if card.has("gain_item_quality"):
		_grant_card_quality(p, String(card.gain_item_quality))
	if card.has("enter_shop"):
		var shop_keys: Array = shops.keys()
		if not shop_keys.is_empty():
			await _run_shop(p, int(shop_keys.pick_random()))
	if card.has("enter_blackshop"):
		await _run_blackshop(p)
	_check_end()

## 机会卡发道具（指定 id / 指定品质）；背包满则作废提示，唯一池过滤照旧
func _grant_card_item(p: Dictionary, id: String) -> void:
	if p.items.size() >= 5:
		_log("%s 背包已满，道具【%s】作废了" % [p.name, id], "#8a90a5")
		return
	if _grant_item(p, id):
		_log("%s 从机会卡获得道具【%s】" % [p.name, id], "#74d188")

func _grant_card_quality(p: Dictionary, q: String) -> void:
	if p.items.size() >= 5:
		_log("%s 背包已满，到手的道具作废了" % p.name, "#8a90a5")
		return
	var pool := _item_pool(q)
	if pool.is_empty():
		_log("%s 想领道具，可惜【%s】缺货" % [p.name, q], "#8a90a5")
		return
	var id: String = pool[randi_range(0, pool.size() - 1)]
	_grant_item(p, id)
	_log("%s 从机会卡获得道具【%s】" % [p.name, id], "#74d188")

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

## 取「已同步」的玩家字典（st.players）。房主与客户端都可用；
## 客户端没有 hp，凡是要在客户端渲染的玩家信息都必须走这里（见 fix/v0.0.2）。
func _state_player(peer: int) -> Dictionary:
	for p in st.get("players", []):
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
	if _is_sleeping(p):
		return false  # 休眠=保守托管：买地/升级一律拒绝
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
	var timed_out := await _await_turn_window("prompt",
		func() -> bool: return int(_decision.token) != tok,
		func(sec: float) -> void: _prompt_bar_arm(tok, sec))
	_awaiting_prompt = 0
	if timed_out and int(_decision.token) != tok:
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
	# 只有被询问的本人能回答：token 是自增小整数、状态又是全员广播的，
	# 少了这道校验任何客户端都能替别人决定买地/装修（见 fix/v0.0.2）。
	# 房主自己是走 _answer 直接赋值，不经过这里。
	if multiplayer.get_remote_sender_id() != _awaiting_prompt:
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

## 房主改「操作限时」挡位：立即生效并重计时（见 docs/gameplay/开局设置.md §三之一）
func _set_timeout_tier(id: String) -> void:
	if not multiplayer.is_server() or not GameSettings.TIERS.has(id):
		return
	if id == _settings.timeout_tier:
		return
	_settings.timeout_tier = id
	_timeout_rev += 1
	_log("房主把操作限时改为「%s」" % String(GameSettings.TIER_LABELS.get(id, id)), "#f0c064")
	_refresh_tier_ui()
	if rules_open:
		RulesPanel.select_tab(self, rules_tab)   # 规则文案里的秒数跟着变
	_broadcast_state()

## 刷新设置面板的「操作限时」一行：房主 = 小标题 + 可点 chips，客户端 = 一行只读文本。
## 两侧互斥（小标题只跟 chips 一起显隐），否则客户端会看到「操作限时」两行同义文本。
## 只读行文案的唯一来源就在这里（table_hud.gd 只建空标签），别再复制一份格式串。
func _refresh_tier_ui() -> void:
	if tier_row == null or tier_readonly == null or tier_title == null:
		return
	var is_host := multiplayer.is_server()
	tier_title.visible = is_host
	tier_row.visible = is_host
	tier_readonly.visible = not is_host
	tier_readonly.text = "操作限时：%s（房主设置）" % String(
		GameSettings.TIER_LABELS.get(_settings.timeout_tier, "现状"))
	UIKit.chip_select(tier_row, _settings.timeout_tier)

func _broadcast_state() -> void:
	if not multiplayer.is_server():
		return
	var plist := []
	for p in hp:
		plist.append({
			"peer": int(p.peer), "name": p.name, "color": int(p.color), "bot": bool(p.bot),
			"money": int(p.money), "pos": int(p.pos), "alive": bool(p.alive), "skip": int(p.skip),
			"sleep": int(p.get("sleep", 0)),
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
	elif _black_peer != 0:
		await_state = "black"
		await_peer = _black_peer
	s_state.rpc({
		"phase": "ended" if not running else "playing",
		"round": round_no, "max_rounds": GameData.MAX_ROUNDS,
		"turn": int(hp[turn_i].peer),
		"await": await_state, "await_peer": await_peer,
		"players": plist, "tiles": htiles,
		"shops": shops, "refresh_price": _refresh_price(),
		"shop_open": (_shop_tile if _shop_peer != 0 else -1),
		"shop_peer": _shop_peer,
		"black_peer": _black_peer, "black_slots": _black_slots,
		"black_pay_mode": _black_pay_mode, "black_pay_need": _black_pay_need,
		"black_pay_got": _black_pay_got,
		"timeout_tier": _settings.timeout_tier,
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
	var tier := String(state.get("timeout_tier", GameSettings.TIER_CURRENT))
	if tier != _settings.timeout_tier:
		_settings.timeout_tier = tier
		if _prompt_token != -1:   # 弹窗开着 → 按新挡位重启倒计时条
			_prompt_bar_arm(_prompt_token, GameSettings.turn_seconds(tier, "prompt"))
		_refresh_tier_ui()
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
			_autotest_client_finish(state)
	elif _shot_path != "" and not _shot_taken and (int(state.round) >= 2 or at_mode == ""):
		_shot_taken = true
		dev.take_shot(_shot_path)
	elif at_mode != "" and not multiplayer.is_server() and int(state.round) >= at_rounds:
		_autotest_client_finish(state)

## 客户端 autotest 收尾：先校验挡位链路，再打印 OK 行退出。
## quit() 要到本帧末才生效，期间还可能再收到一次 s_state —— 用标记挡住重复打印。
func _autotest_client_finish(state: Dictionary) -> void:
	if _at_client_done:
		return
	_at_client_done = true
	if not _autotest_tier_ok(state):
		return   # 已在里面打印 FAIL 并 quit(1)
	print("AUTOTEST CLIENT OK round=%d tier=%s chips=%s readonly=%s" % [
		int(state.round), String(state.get("timeout_tier", "")),
		tier_row.visible, tier_readonly.visible])
	get_tree().quit(0)

## 只用 `--autotest=` 时才跑：被传了 `--tier=` 的客户端必须收到同挡位的快照，
## 且「操作限时」只读行可见、可点 chips 不可见（客户端只读 + 中途改档同步的取证）。
## 不满足 → 打印 AUTOTEST CLIENT TIER FAIL 并 quit(1)，返回 false。
func _autotest_tier_ok(state: Dictionary) -> bool:
	if at_mode == "" or at_tier == "" or multiplayer.is_server():
		return true
	var got := String(state.get("timeout_tier", ""))
	if got == at_tier and not tier_row.visible and tier_readonly.visible:
		return true
	print("AUTOTEST CLIENT TIER FAIL want=%s got=%s chips=%s readonly=%s" % [
		at_tier, got, tier_row.visible, tier_readonly.visible])
	get_tree().quit(1)
	return false

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
	# 新战报：头部闪一记金色。连续刷屏时只重启这一条补间，不叠一堆。
	if log_head == null or not is_instance_valid(log_head):
		return
	if _log_flash_tw != null and _log_flash_tw.is_valid():
		_log_flash_tw.kill()
	var from := UIKit.ACCENT
	var to := UIKit.TEXT_DIM
	_log_flash_tw = create_tween()
	_log_flash_tw.tween_method(func(t: float) -> void:
		log_head.add_theme_color_override("font_color", from.lerp(to, t)), 0.0, 1.0, 0.55)

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
	var prop_map := {}   # peer -> 地产块数（右栏名册复用，避免再算一遍）
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
		elif int(p.get("sleep", 0)) > 0:
			tags += "（小黑屋）"
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
		prop_map[peer] = prop_n

		if not bool(p.alive):
			row.money_l.text = "已出局"
			row.money_l.add_theme_color_override("font_color", UIKit.TEXT_DIM)

	# 身家排名 → 座位徽章 + 地产/身家行
	var order: Array = worth_map.keys()
	order.sort_custom(func(a, b) -> bool: return int(worth_map[a]) > int(worth_map[b]))
	for i in order.size():
		board.update_seat_stats(int(order[i]), i + 1, String(est_map[int(order[i])]))

	# 右栏名册复用上面刚算出的身家/排名（公式只留这一处，避免两套算法悄悄跑偏）
	var standing: Array = []
	for i in order.size():
		var rp := int(order[i])
		var rpl := _state_player(rp)
		standing.append({
			"peer": rp, "rank": i + 1, "worth": int(worth_map[rp]),
			"name": String(rpl.get("name", "?")), "color": int(rpl.get("color", 0)),
			"money": int(rpl.get("money", 0)), "alive": bool(rpl.get("alive", true)),
			"props": int(prop_map.get(rp, 0)), "items": (rpl.get("items", []) as Array).size(),
		})
	_refresh_rail(standing)

	for peer in _player_rows.keys():
		if not seen.has(peer):
			_player_rows.erase(peer)  # 座位是桌面世界的一部分，保留在桌上（掉线/出局只改显示）

## 右栏名册：按身家倒序填 4 行（名次 / 棋子色 / 名字 / 现金 / 地产·道具），
## 轮到谁行动就把谁的左侧竖条点亮，自己那行标出来。
## 带签名缓存：状态没变就不重建（每次广播都会走这里）。
func _refresh_rail(standing: Array) -> void:
	if roster_rows.is_empty():
		return
	var sig := "%d|" % int(st.get("turn", -1))
	for e in standing:
		sig += "%d,%d,%d,%d,%d,%d;" % [int(e.peer), int(e.rank), int(e.money),
			int(e.props), int(e.items), 1 if bool(e.alive) else 0]
	sig += "|%s" % String(st.get("phase", ""))
	if sig == _rail_sig:
		return
	_rail_sig = sig

	var turn_peer := int(st.get("turn", -1))
	for i in roster_rows.size():
		var row: Dictionary = roster_rows[i]
		var root: Control = row.root
		if i >= standing.size():
			root.visible = false
			continue
		var e: Dictionary = standing[i]
		var peer := int(e.peer)
		root.visible = true
		var chip_slot: Control = row.chip_slot
		if row.chip == null or not is_instance_valid(row.chip):
			for c in chip_slot.get_children():
				c.queue_free()
			row.chip = UIKit.chip(GameData.PLAYER_COLORS[clampi(int(e.color), 0, 3)], 16)
			chip_slot.add_child(row.chip)
		# 名次 + 名字（自己标「我」，轮到谁行动加 ▶）
		var active: bool = String(st.get("phase", "")) == "playing" and peer == turn_peer
		var tags := ""
		if peer == my_peer:
			tags += "（我）"
		if not bool(e.alive):
			tags += "（破产）"
		var name_l: Label = row.name_l
		name_l.text = "%d. %s%s" % [int(e.rank), String(e.name), tags]
		# 名字变金 = 轮到 TA 行动（左侧竖条同时点亮）；自己只靠「（我）」标
		name_l.add_theme_color_override("font_color",
			UIKit.TEXT_DIM if not bool(e.alive) else (UIKit.ACCENT if active else UIKit.TEXT))
		var sub_l: Label = row.sub_l
		sub_l.text = "地产 ×%d · 道具 %d" % [int(e.props), int(e.items)]
		# 右列：大字身家（名次依据）+ 小字现金
		var money_l: Label = row.money_l
		money_l.text = "已出局" if not bool(e.alive) else GameData.fmt_money(int(e.worth))
		money_l.add_theme_color_override("font_color",
			UIKit.TEXT_DIM if not bool(e.alive) else UIKit.ACCENT)
		var cash_l: Label = row.cash_l
		cash_l.text = "" if not bool(e.alive) else "现金 %s" % GameData.fmt_money(int(e.money))
		var bar: ColorRect = row.bar
		bar.color = UIKit.ACCENT if active else Color(0, 0, 0, 0)

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
		"black":
			status_label.text = "黑市开张：用你的地皮结账！" if int(st.get("await_peer", -1)) == my_peer \
				else "%s 在黑市交易…" % turn_name
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
			dev.toggle()
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
			if idx < tiles.size() and bool(tiles[idx].get("soil", false)):
				accent = Color(0.55, 0.35, 0.2)
				body = "焦土恢复中……\n落地自动捐款 · 已筹 %s / %s\n修复完成后变为无主地产" % [
					GameData.fmt_money(int(tiles[idx].get("soil_prog", 0))), GameData.fmt_money(int(d.price))]
			else:
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
	# 规则说明展开时占着左下角，格详情卡让位（见 _set_rules_open）
	info_panel.visible = not rules_open
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
	casino.close()
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
	_prompt_bar = bar
	_prompt_bar_arm(token, GameSettings.turn_seconds(_settings.timeout_tier, "prompt"))

func _close_prompt() -> void:
	if _prompt_tw != null and _prompt_tw.is_valid():
		_prompt_tw.kill()
	_prompt_tw = null
	if _prompt_dlg != null and is_instance_valid(_prompt_dlg):
		_prompt_dlg.queue_free()
	_prompt_dlg = null
	_prompt_bar = null
	_prompt_token = -1

## （重）启动弹窗倒计时条。sec <= 0（不限时）则只隐藏条子、不自动拒绝。
## 挡位中途变化时房主与客户端都会重新调用它（见 _await_turn_window / s_state）。
func _prompt_bar_arm(token: int, sec: float) -> void:
	# 先判 token 再 kill：不是当前弹窗的（重）启动不该掐掉当前条子的 tween
	if _prompt_bar == null or not is_instance_valid(_prompt_bar) or _prompt_token != token:
		return
	if _prompt_tw != null and _prompt_tw.is_valid():
		_prompt_tw.kill()
	if sec <= 0.0:
		_prompt_bar.visible = false
		return
	_prompt_bar.visible = true
	_prompt_bar.value = 100.0
	_prompt_tw = create_tween()
	# 条子提前 _BAR_LEAD 秒到底：tween_callback 会直接提交「拒绝」，
	# 所以「15 秒」档实际在 14 秒生效——这是基线就有的口径，改动前先确认规则文案是否要跟。
	_prompt_tw.tween_property(_prompt_bar, "value", 0.0, maxf(0.5, sec - _BAR_LEAD))
	_prompt_tw.tween_callback(func() -> void:
		if _prompt_token == token:
			_answer(token, false)
			_close_prompt()
	)

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
		_card_cell("作弊器", ItemCard.SIZE_MEDIUM, {"count": 2, "cooling": true}, "冷却中 · 右上剩 2 回合·压暗"),
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

## 香皂免疫：持有【空想者的香皂】时免疫一切带 debuff 标签的效果（§3 标签表）
func _immune_debuff(p: Dictionary) -> bool:
	return _has_item(p, "空想者的香皂")

## 统一发放入口：背包满返回 false；香皂入场初始化融化计数（他人拾取重新计 10 回合）
func _grant_item(p: Dictionary, id: String) -> bool:
	if p.items.size() >= 5:
		return false
	var inst := {"id": id, "cd": 0}
	if id == "空想者的香皂":
		inst.melt_left = 10
	p.items.append(inst)
	return true

func _item_pool(quality: String) -> Array:
	var held := {}
	for pl in hp:
		if not bool(pl.get("alive", true)):
			continue  # 破产玩家的背包不再占用唯一性，否则那件唯一道具永久退出池
		for it in pl.get("items", []):
			held[String(it.id)] = true
	for k in shops:  # 货架在售的唯一道具同样占用唯一性（不同货架不会出现两件）
		for sid in shops[k].slots:
			if String(sid) != "":
				held[String(sid)] = true
	for sid in _black_slots:  # 黑市在售的唯一道具同样占用唯一性
		if String(sid) != "":
			held[String(sid)] = true
	var out := []
	for id in ItemData.ITEMS:
		var d: Dictionary = ItemData.ITEMS[id]
		if not bool(d.implemented):
			continue
		if items_consumed.has(String(id)):
			continue  # 焚毁的一次性道具永久离池
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
	for it in p.get("items", []):
		if String(it.id) == "空想者的香皂":
			it.melt_left = int(it.get("melt_left", 10)) - 1
	var melted: Array = (p.get("items", []) as Array).filter(func(it) -> bool:
		return String(it.id) == "空想者的香皂" and int(it.get("melt_left", 10)) <= 0)
	for m in melted:
		p.items.erase(m)
	if not melted.is_empty():
		_log("%s 的【空想者的香皂】化没了，溜进了地缝（回池）" % p.name, "#8fb7f2")
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
		var used := false
		for i in p.get("items", []).size():
			var it: Dictionary = p.items[i]
			var d := ItemData.def(String(it.id))
			if String(d.type) == "passive" or not bool(d.implemented) \
					or int(it.get("cd", 0)) > 0 or int(p.get("stamina", 0)) < int(d.cost):
				continue
			if String(it.id) == "黑卡":
				_use_item(int(p.peer), i, -1)
				used = true
			elif String(it.id) == "蛋蛋节" or String(it.id) == "亡牌飞行员coco":
				_use_item(int(p.peer), i, -1)
				used = true
			elif String(it.id) == "交换生":
				var targets: Array = _swap_targets(int(p.peer))
				if not targets.is_empty():
					var t: Dictionary = targets[randi_range(0, targets.size() - 1)]
					_use_item(int(p.peer), i, int(t.peer))
					used = true
			if used:
				break
		if not used:
			_item_action = {"epoch": epoch, "action": "skip"}
	else:
		_arm_item_timeout(epoch, int(p.peer))
	while running and _awaiting_item == int(p.peer) and int(_item_action.get("epoch", -1)) != epoch:
		await _wait(0.1)
	if not running:
		return
	_awaiting_item = 0
	_broadcast_state()

func _arm_item_timeout(epoch: int, peer: int) -> void:
	var timed_out := await _await_turn_window("item",
		func() -> bool: return _awaiting_item == peer and int(_item_action.get("epoch", -1)) != epoch)
	if timed_out:
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
	var prev_cd := int(it.get("cd", 0))
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
				if _immune_debuff(a):
					continue  # 香皂免疫：不被拉平
				a.money = share
			for k in rem:
				if not _immune_debuff(alive[k]):
					alive[k].money = int(alive[k].money) + 1
			_log("%s 发动【平均主义】，全场现金拉平！" % p.name, "#c9a6ff")
		"交换生":
			var target := _player_by_peer(arg)
			if target.is_empty() or arg == peer or not bool(target.alive) \
					or (target.get("items", []) as Array).is_empty():
				it.cd = prev_cd  # 不消耗：找不到可交换对象
				p.item_used = false
				p.stamina = int(p.stamina) + int(d.cost)
				_log("%s 的【交换生】没找到可交换的对象" % p.name, "#8a90a5")
				return
			var titems: Array = target.items
			var tidx := randi_range(0, titems.size() - 1)
			var theirs: Dictionary = titems[tidx]
			titems[tidx] = it  # 我的交换生（含新冷却）给对方——冷却随实例走
			items[slot] = theirs
			_log("%s 用【交换生】从 %s 处换来【%s】！" % [p.name, target.name, String(theirs.id)], "#c9a6ff")
		"黑卡":
			it.charges = 3
			_log("%s 使用【黑卡】，接下来 3 次购买免单！" % p.name, "#f0a0c0")
		"蛋蛋节":
			items_consumed[String(it.id)] = true  # 用后焚毁不回池（先焚毁腾位再发礼物）
			items.remove_at(slot)
			_apply_egg_festival(p)
		"亡牌飞行员coco":
			items_consumed[String(it.id)] = true
			items.remove_at(slot)
			_apply_coco(p)
		_:
			p.item_used = false
			p.stamina = int(p.stamina) + int(d.cost)
			it.cd = prev_cd
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
	if _is_sleeping(p):
		_shop_leave(int(p.peer))  # 休眠=商店自动离开
	elif bool(p.bot):
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
	var timed_out := await _await_turn_window("shop",
		func() -> bool: return _shop_peer == peer and _shop_epoch == epoch)
	if timed_out:
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
	if p.is_empty() or p.items.size() >= 5:
		return
	var free := false
	for pit in p.get("items", []):
		if String(pit.id) == "黑卡" and int(pit.get("charges", 0)) > 0:
			pit.charges = int(pit.charges) - 1
			free = true
			break
	if not free:
		if int(p.money) < price:
			return
		p.money = int(p.money) - price
	else:
		_log("%s 刷【黑卡】免单拿下【%s】" % [p.name, id], "#f0a0c0")
	if not _grant_item(p, id):
		return
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
	# _stock_shop 只补空位：三格都满时刷新什么也不会发生，却照收钱还推高全场刷新价
	#（此前玩家会「花钱买了个寂寞」，见 fix/v0.0.2）
	var before := str(shops[_shop_tile].slots)
	_stock_shop(_shop_tile)
	if str(shops[_shop_tile].slots) == before:
		_log("货架满满当当，刷新也不会有新货（没花钱）", "#8a90a5")
		return
	p.money = int(p.money) - cost
	refresh_count += 1
	_log("%s 花 %s 刷新了货架（全场刷新价上涨）" % [p.name, GameData.fmt_money(cost)], "#8a90a5")
	_broadcast_state()

func _shop_leave(peer: int) -> void:
	if _shop_peer != peer:
		return
	_log("%s 走出了小卖部" % _name_by_peer(peer), "#8a90a5")
	_shop_peer = 0
	_broadcast_state()

# ================= 黑市（§8：仅由机会卡进入，一切消费用地产） =================

func _is_sleeping(p: Dictionary) -> bool:
	return int(p.get("sleep", 0)) > 0

## 需要系统代为决策（机器人 / 休眠托管）
func _is_managed(p: Dictionary) -> bool:
	return bool(p.bot) or _is_sleeping(p)

func _prop_indices_of(peer: int) -> Array:
	var out := []
	for i in htiles.size():
		if int(htiles[i].get("owner", GameData.NO_OWNER)) == peer \
				and not bool(htiles[i].get("soil", false)) \
				and String(GameData.TILES[i].get("type", "")) == "property":
			out.append(i)
	return out

func _prop_indices_sorted(peer: int) -> Array:
	var out := _prop_indices_of(peer)
	out.sort_custom(func(a: int, b: int) -> bool:
		return int(GameData.TILES[a].price) < int(GameData.TILES[b].price))
	return out

func _black_roll_quality() -> String:
	var total := 0
	for q in ItemData.BLACK_WEIGHTS:
		total += int(ItemData.BLACK_WEIGHTS[q])
	var r := randi_range(0, maxi(total - 1, 0))
	for q in ItemData.BLACK_WEIGHTS:
		r -= int(ItemData.BLACK_WEIGHTS[q])
		if r < 0:
			return q
	return "紫"

func _black_stock_one() -> String:
	var q := _black_roll_quality()
	if _item_pool(q).is_empty():
		q = "橙" if q == "紫" else "紫"
	var pool := _item_pool(q)
	if pool.is_empty():
		return ""
	return pool[randi_range(0, pool.size() - 1)]

func _black_stock() -> void:
	if _black_slots.size() != 3:
		_black_slots = ["", "", ""]
	for i in _black_slots.size():
		if String(_black_slots[i]) == "":
			_black_slots[i] = _black_stock_one()

func _run_blackshop(p: Dictionary) -> void:
	_black_epoch += 1
	var epoch := _black_epoch
	_black_peer = int(p.peer)
	_black_pay_mode = ""
	_black_pay_got = 0
	_black_stock()
	_broadcast_state()
	_log("%s 被拽进了【黑市】——这里只收地皮" % p.name, "#ef7b74")
	s_card.rpc("【黑市】欢迎光临，请用你的地皮结账", "bad")
	# 带着 0 块地皮进店 = 进店即挨打
	if _prop_indices_of(int(p.peer)).is_empty():
		_black_beat(p, "一块地皮都没有")
		return
	await _wait(0.6)
	if bool(p.bot) or _is_sleeping(p):
		_bot_blackshop(p)
	else:
		_arm_black_timeout(epoch, int(p.peer))
	while running and _black_peer == int(p.peer) and _black_epoch == epoch:
		await _wait(0.1)
	if not running:
		return
	_black_peer = 0
	_black_pay_mode = ""
	_broadcast_state()

func _arm_black_timeout(epoch: int, peer: int) -> void:
	var timed_out := await _await_turn_window("black",
		func() -> bool: return _black_peer == peer and _black_epoch == epoch)
	if timed_out:
		_log("%s 在黑市里发愣，被看场子的请了出去" % _name_by_peer(peer), "#8a90a5")
		_black_force_exit(peer)

func _black_beat(p: Dictionary, reason: String) -> void:
	var lost := int(int(p.money) / 2)
	p.money = int(p.money) - lost
	p.sleep = maxi(1, int(p.get("sleep", 0)))
	_black_peer = 0
	_black_pay_mode = ""
	_log("%s %s，挨了一顿打：损失 %s，还被关进小黑屋（休眠一回合）" % [
		p.name, reason, GameData.fmt_money(lost)], "#ef7b74")
	s_card.rpc("%s 在黑市挨打：损失 %s + 小黑屋" % [p.name, GameData.fmt_money(lost)], "bust")
	_broadcast_state()

func _black_buy(peer: int, slot: int) -> void:
	if _black_peer != peer or _black_pay_mode != "":
		return
	if slot < 0 or slot >= _black_slots.size() or String(_black_slots[slot]) == "":
		return
	var p := _player_by_peer(peer)
	if p.is_empty() or p.items.size() >= 5:
		_log("%s 背包已满，买不了" % _name_by_peer(peer), "#8a90a5")
		return
	var id := String(_black_slots[slot])
	var cost := int(ItemData.BLACK_COST.get(String(ItemData.def(id).quality), 1))
	if _prop_indices_of(peer).size() < cost:
		_black_beat(p, "凑不出货钱")
		return
	_black_pay_mode = "buy"
	_black_pay_slot = slot
	_black_pay_need = cost
	_black_pay_got = 0
	_broadcast_state()

func _black_refresh(peer: int) -> void:
	if _black_peer != peer or _black_pay_mode != "":
		return
	var p := _player_by_peer(peer)
	if p.is_empty():
		return
	if _prop_indices_of(peer).size() < ItemData.BLACK_REFRESH_COST:
		_black_beat(p, "掏不出刷新费")
		return
	_black_pay_mode = "refresh"
	_black_pay_slot = -1
	_black_pay_need = ItemData.BLACK_REFRESH_COST
	_black_pay_got = 0
	_broadcast_state()

func _black_leave(peer: int) -> void:
	if _black_peer != peer or _black_pay_mode != "":
		return
	var p := _player_by_peer(peer)
	if p.is_empty():
		return
	if _prop_indices_of(peer).size() < ItemData.BLACK_EXIT_COST:
		_black_beat(p, "交不起出口费")
		return
	_black_pay_mode = "exit"
	_black_pay_slot = -1
	_black_pay_need = ItemData.BLACK_EXIT_COST
	_black_pay_got = 0
	_broadcast_state()

## 玩家点选一块地皮交出去（逐块支付，凑齐后结算挂起的动作）
func _black_pay(peer: int, prop_idx: int) -> void:
	if _black_peer != peer or _black_pay_mode == "":
		return
	if prop_idx < 0 or prop_idx >= htiles.size():
		return
	if int(htiles[prop_idx].get("owner", GameData.NO_OWNER)) != peer:
		return
	if bool(htiles[prop_idx].get("soil", false)):
		return
	if String(GameData.TILES[prop_idx].get("type", "")) != "property":
		return
	htiles[prop_idx].owner = GameData.NO_OWNER  # 被收地皮回归无主、可再购买（定稿）
	htiles[prop_idx].level = 0
	_black_pay_got += 1
	_log("%s 交出【%s】抵账" % [_name_by_peer(peer), String(GameData.TILES[prop_idx].name)], "#c9a6ff")
	if _black_pay_got >= _black_pay_need:
		_black_settle(peer)
	else:
		_broadcast_state()

func _black_settle(peer: int) -> void:
	var p := _player_by_peer(peer)
	var mode := _black_pay_mode
	var slot := _black_pay_slot
	_black_pay_mode = ""
	_black_pay_slot = -1
	_black_pay_got = 0
	_black_pay_need = 0
	match mode:
		"buy":
			var id := String(_black_slots[slot])
			_black_slots[slot] = ""
			_grant_item(p, id)
			_log("%s 在黑市拿下了【%s】" % [p.name, id], "#8fb7f2")
		"refresh":
			_black_stock()
			_log("%s 花地皮刷新了黑市货架" % p.name, "#8a90a5")
		"exit":
			_black_peer = 0
			_log("%s 交完出口费，走出了黑市" % p.name, "#8a90a5")
	_broadcast_state()

## 超时托管：先把挂起的动作付完，再自动用最便宜的地皮付出口费
func _black_force_exit(peer: int) -> void:
	var p := _player_by_peer(peer)
	if p.is_empty():
		return
	while _black_pay_mode != "" and _black_peer == peer:
		var props := _prop_indices_sorted(peer)
		if props.is_empty():
			_black_beat(p, "凑不出地皮")
			return
		_black_pay(peer, int(props[0]))
	if _black_peer != peer:
		return
	_black_leave(peer)
	while _black_pay_mode == "exit" and _black_peer == peer:
		var ps := _prop_indices_sorted(peer)
		if ps.is_empty():
			_black_beat(p, "凑不出地皮")
			return
		_black_pay(peer, int(ps[0]))

## bot 策略：留 1 块地皮付出口费，用余下地皮买最值的一件，然后交费走人
func _bot_blackshop(p: Dictionary) -> void:
	var props := _prop_indices_sorted(int(p.peer))
	var best_slot := -1
	var best_val := -1
	for i in _black_slots.size():
		var id := String(_black_slots[i])
		if id == "":
			continue
		var cost := int(ItemData.BLACK_COST.get(String(ItemData.def(id).quality), 1))
		if props.size() - cost < 1:
			continue
		var val := int(ItemData.QUALITY_PRICES.get(String(ItemData.def(id).quality), 0))
		if val > best_val:
			best_val = val
			best_slot = i
	if best_slot >= 0 and p.items.size() < 5:
		_black_buy(int(p.peer), best_slot)
		while _black_pay_mode == "buy" and _black_peer == int(p.peer):
			var ps := _prop_indices_sorted(int(p.peer))
			if ps.is_empty():
				break
			_black_pay(int(p.peer), int(ps[0]))
	_black_leave(int(p.peer))
	while _black_pay_mode == "exit" and _black_peer == int(p.peer):
		var ps2 := _prop_indices_sorted(int(p.peer))
		if ps2.is_empty():
			break
		_black_pay(int(p.peer), int(ps2[0]))

@rpc("any_peer", "call_remote", "reliable")
func c_black_buy(slot: int) -> void:
	if not multiplayer.is_server():
		return
	_black_buy(multiplayer.get_remote_sender_id(), slot)

@rpc("any_peer", "call_remote", "reliable")
func c_black_refresh() -> void:
	if not multiplayer.is_server():
		return
	_black_refresh(multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable")
func c_black_leave() -> void:
	if not multiplayer.is_server():
		return
	_black_leave(multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable")
func c_black_pay(prop_idx: int) -> void:
	if not multiplayer.is_server():
		return
	_black_pay(multiplayer.get_remote_sender_id(), prop_idx)

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

## 蛋蛋节：全员送礼（规则见 docs/gameplay/道具图鉴.md：他人白/绿/蓝三档均分，
## 使用者紫 70%/橙 30%；礼物取自当前可获取池，满包改发 ¥100，池空同额兜底）
func _apply_egg_festival(p: Dictionary) -> void:
	_log("%s 点燃了【蛋蛋节】，礼物撒满全场！" % p.name, "#f0a0c0")
	for o in hp:
		if int(o.peer) == int(p.peer) or not bool(o.alive):
			continue
		if o.items.size() >= 5:
			o.money = int(o.money) + 100
			_log("%s 背包已满，改收 %s 现金" % [o.name, GameData.fmt_money(100)], "#74d188")
			continue
		var q: String = ["白", "绿", "蓝"][randi_range(0, 2)]
		var pool := _item_pool(q)
		if pool.is_empty():
			o.money = int(o.money) + 100
			_log("%s 的礼物缺货，改收 %s 现金" % [o.name, GameData.fmt_money(100)], "#74d188")
			continue
		var id: String = pool[randi_range(0, pool.size() - 1)]
		_grant_item(o, id)
		_log("%s 收到礼物【%s】" % [o.name, id], "#74d188")
	var my_q: String = "紫" if randi_range(1, 100) <= 70 else "橙"
	var my_pool := _item_pool(my_q)
	if my_pool.is_empty():
		my_pool = _item_pool("紫") + _item_pool("橙")
	if not my_pool.is_empty():
		var id2: String = my_pool[randi_range(0, my_pool.size() - 1)]
		_grant_item(p, id2)
		_log("%s 自己抽到了【%s】！" % [p.name, id2], "#f0a0c0")

## 亡牌飞行员coco：每名玩家（含使用者）随机一块地皮化为焦土（§五 焦土状态机）
func _apply_coco(p: Dictionary) -> void:
	_log("%s 召唤了【亡牌飞行员coco】，轰炸开始！" % p.name, "#ef7b74")
	Fx.shake(self, 7.0, 0.3)
	for o in hp:
		if not bool(o.alive):
			continue
		if _immune_debuff(o):
			_log("%s 的【空想者的香皂】挡下了轰炸" % o.name, "#8fb7f2")
			continue
		var owned: Array = []
		for i in htiles.size():
			if int(htiles[i].get("owner", GameData.NO_OWNER)) == int(o.peer) \
					and not bool(htiles[i].get("soil", false)) \
					and String(GameData.TILES[i].get("type", "")) == "property":
				owned.append(i)
		if owned.is_empty():
			_log("%s 名下没有地皮，逃过一劫" % o.name, "#8a90a5")
			continue
		var idx: int = owned[randi_range(0, owned.size() - 1)]
		var t: Dictionary = htiles[idx]
		t.soil = true
		t.soil_prog = 0
		t.owner = GameData.NO_OWNER
		t.level = 0
		_log("%s 的【%s】被炸成了焦土！落地捐款可以修复它" % [o.name, String(GameData.TILES[idx].name)], "#ef7b74")

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
	# 必须读「已同步的」状态：hp 只在房主 _host_setup 里填充，
	# 客户端 hp 恒为空 → 道具栏一个按钮都建不出来，真人整局无法使用道具，
	# 只能等房主 12 秒超时跳过（见 fix/v0.0.2）。
	var p := _state_player(my_peer)
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
		var iid := String(it.id)
		if iid == "交换生" and usable:
			usable = not _swap_targets(my_peer).is_empty()
		var b := UIKit.button("%s ⚡%d" % [iid, int(d.cost)], 12)
		b.disabled = not usable
		var slot := i
		b.pressed.connect(func() -> void:
			if iid == "作弊器":
				_open_cheat_picker(slot)
			elif iid == "交换生":
				_open_target_picker(slot)
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

func _swap_targets(exclude_peer: int) -> Array:
	# 与道具栏同理：hp 只在房主填充，客户端为空会让「交换生」永远置灰、换人列表为空，
	# 必须读已同步的 st（见 fix/v0.0.2）。
	var out: Array = []
	for x in st.get("players", []):
		if bool(x.get("alive", true)) and int(x.peer) != exclude_peer \
				and not (x.get("items", []) as Array).is_empty():
			out.append(x)
	return out

func _open_target_picker(slot: int) -> void:
	_close_cheat_picker()
	for c in target_btn_box.get_children():
		c.queue_free()
	for t in _swap_targets(my_peer):
		var b := UIKit.button("%s（%d 件道具）" % [String(t.name), (t.get("items", []) as Array).size()], 13)
		var tp := int(t.peer)
		b.pressed.connect(func() -> void:
			_close_target_picker()
			_send_use_item(slot, tp)
		)
		target_btn_box.add_child(b)
	target_picker.visible = true

func _close_target_picker() -> void:
	target_picker.visible = false

# ================= 选项菜单 / 房主暂停 / 设置 =================

func _pill_label(p: Control) -> Label:
	for c in p.find_children("", "Label", true, false):
		return c as Label
	return null

func _build_menu_ui() -> void:
	TableHud.build_menu_ui(self)
## 切换暂停菜单族的当前面板（""=全部收起）。
##
## 三块面板（主菜单 / 设置 / 退出确认）各套一个全屏 CenterContainer，**必须连外层
## 容器一起切**：外层是 set_anchors_preset(FULL_RECT) + 默认 mouse_filter=STOP 的容器，
## 只切内层 *_panel.visible 的话，最后那块（退出确认的）全屏容器依旧可见，
## 会把整屏点击全部吃掉 —— 对局里点开暂停后「界面卡死、按钮全点不动」的真凶
##（见 fix/v0.1.0 与 tests/pause_menu_test.gd）。
func _menu_show(which: String) -> void:
	menu_layer.visible = which != ""
	if menu_layer.visible and menu_layer.get_index() != get_child_count() - 1:
		move_child(menu_layer, -1)  # 开局后新挂的节点（结算层等）不该压在菜单上
	for k in menu_wraps:
		var e: Dictionary = menu_wraps[k]
		# wrap 负责吃输入（全屏 STOP），panel 负责「当前显示哪块」的可查询状态
		for key in ["wrap", "panel"]:
			var c: Control = e[key]
			if c != null and is_instance_valid(c):
				c.visible = k == which

func _open_menu() -> void:
	if multiplayer.is_server():
		s_pause.rpc(true)  # 房主打开菜单 = 全场暂停
		menu_state.text = "⏸ 已暂停（全场）"
	else:
		menu_state.text = "对局进行中 · 仅房主可暂停"
	_menu_show("menu")

func _menu_resume() -> void:
	if multiplayer.is_server():
		s_pause.rpc(false)
	_menu_show("")

@rpc("authority", "call_local", "reliable")
func s_pause(on: bool) -> void:
	get_tree().paused = on
	pause_mask.visible = on and not multiplayer.is_server()

# ================= HUD 入场 =================

## 入场：棋盘与两侧栏错落淡入，别让 HUD 在一帧之间「啪」地全糊上来。
## 底栏不参与——它要等开局（phase=playing）才出现，淡入会跟它的显隐打架。
func _hud_intro() -> void:
	for it in [[board, 0.0], [opt_btn, 0.04], [log_toggle, 0.08], [log_panel, 0.12],
			[rules_btn, 0.18]]:
		var c: Control = it[0]
		if c != null and is_instance_valid(c):
			Fx.animate_in(c, float(it[1]))

# ================= 规则说明面板（左下角） =================

## 展开/收起规则说明。展开时它占据左下角，格子详情卡让位（隐藏）——
## 两者锚在同一块地方，同时显示会互相压住；收起后格详情卡照常弹出。
func _set_rules_open(on: bool) -> void:
	if rules_open == on:
		return
	rules_open = on
	rules_btn.visible = not on
	rules_panel.visible = on
	if on:
		info_panel.visible = false
		# 自左下角向上「长出来」：缩放支点在左下角（构建时已设，这里兜底重算）
		rules_panel.pivot_offset = Vector2(0.0, rules_panel.size.y)
		rules_panel.modulate.a = 0.0
		rules_panel.scale = Vector2(0.96, 0.96)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(rules_panel, "modulate:a", 1.0, 0.16)
		tw.tween_property(rules_panel, "scale", Vector2.ONE, 0.2) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		rules_body.scroll_to_line(0)
		Fx.play("pop", -8.0, 0.9)
	else:
		rules_panel.modulate.a = 1.0
		rules_panel.scale = Vector2.ONE

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


func _process(_delta: float) -> void:
	# 底栏（牌垫阶段条 + 操作条）统一成屏幕底部一条固定操作坞，不再锚在自己座位卡下沿：
	# 原来「自己视角贴座位卡、转开视角改贴屏幕底」，按钮会跟着镜头满屏跳，转视角时
	# 阶段条还会整条消失（fix/v0.0.2 打的补丁）。固定之后位置恒定、阶段永远可见。
	if mat_bar == null:
		return
	var phase := String(st.get("phase", ""))
	var show := board.seat_count() > 0 and phase == "playing"
	# 交易面板独立于视角：底栏居中，保证行动者一定能操作（相机可能停在棋子上而非自家座位）
	var shop_mine: bool = phase == "playing" and int(st.get("shop_peer", 0)) == my_peer \
		and int(st.get("shop_open", -1)) >= 0
	shop_bar.visible = shop_mine
	if shop_mine:
		_place_overlay_bar(shop_bar)
		_refresh_shop_buttons()
	var black_mine: bool = phase == "playing" and int(st.get("black_peer", 0)) == my_peer
	black_bar.visible = black_mine
	if black_mine:
		_place_overlay_bar(black_bar)
		_refresh_black_ui()
	else:
		black_picker.visible = false
		_black_sig = ""
	mat_bar.visible = show and not shop_mine and not black_mine
	var want_actions: bool = phase == "playing" and (roll_btn.visible or item_btn_box.visible)
	action_bar.visible = want_actions and not shop_mine and not black_mine
	_place_dock()  # 交易/黑市条顶掉底栏时，内部会把底板一并收掉
	# 「该你掷了」时按钮轻微呼吸：持续动画手写相位（项目的表现层约定）
	if roll_btn.visible and not roll_btn.disabled and roll_btn.size.x > 1.0:
		_pulse_t += _delta
		roll_btn.pivot_offset = roll_btn.size * 0.5
		var sc := 1.0 + 0.022 * (0.5 + 0.5 * sin(_pulse_t * 4.4))
		roll_btn.scale = Vector2(sc, sc)
	elif roll_btn.scale != Vector2.ONE:
		roll_btn.scale = Vector2.ONE
		_pulse_t = 0.0
	if dev.enabled:
		dev.refresh_panel()

## 底栏统一贴底居中：可见的两条并排成一条操作坞，横向夹进可用带；
## 顶边对齐（两条容器高度差一两像素，对齐顶边看起来才是一条）。
func _place_dock() -> void:
	var parts: Array = []
	for c in [mat_bar, action_bar]:
		if c != null and c.visible:
			parts.append(c)
	if parts.is_empty():
		if dock_plate != null:
			dock_plate.visible = false
		return
	var gap := 8.0
	var total := 0.0
	var tallest := 0.0
	for c in parts:
		total += c.size.x
		tallest = maxf(tallest, c.size.y)
	total += gap * float(parts.size() - 1)
	var left := _clamp_dock_x(size.x * 0.5 - total * 0.5, total, _dock_band())
	var top := size.y - 16.0 - tallest
	var x := left
	for c in parts:
		c.position = Vector2(x, top)
		x += c.size.x + gap
	# 底板兜住整行：留 7px 内边距，读数上就是「一整块操作坞」而不是两条浮着的条
	if dock_plate != null:
		var pad := 7.0
		dock_plate.visible = true
		dock_plate.position = Vector2(left - pad, top - pad)
		dock_plate.size = Vector2(total + pad * 2.0, tallest + pad * 2.0)

## 底栏可用的横向带（左起 / 右止）。底栏原本只按座位卡居中，一旦左下角展开
## 规则说明面板、或右上角战报栏展开，它就会被压住（状态文字被切掉）。
func _dock_band() -> Vector2:
	var x0 := 14.0
	if rules_panel != null and rules_panel.visible:
		x0 = maxf(x0, rules_panel.offset_right + 10.0)
	elif info_panel != null and info_panel.visible:
		x0 = maxf(x0, info_panel.offset_right + 10.0)
	var x1 := size.x - 14.0
	if log_panel != null and log_panel.visible:
		# 战报栏挂 TOP_RIGHT 锚点，所以它的左边缘 = 屏宽 + offset_left（不写死宽度）
		x1 = minf(x1, size.x + log_panel.offset_left - 8.0)
	return Vector2(x0, maxf(x1, x0 + 120.0))

## 把底栏左边缘夹进可用带内（带太窄时以左边缘为准，宁可溢出也不推到屏幕外）
func _clamp_dock_x(want: float, width: float, band: Vector2) -> float:
	return clampf(want, band.x, maxf(band.x, band.y - width))

## 交易面板贴底居中：按自身高度上移，保证整块（含刷新/离开）都在屏内；
## 横向同样夹进可用带，免得展开规则说明后被压住
func _place_overlay_bar(c: Control) -> void:
	var vp := size
	c.position = Vector2(_clamp_dock_x(vp.x * 0.5 - c.size.x * 0.5, c.size.x, _dock_band()),
		maxf(vp.y - c.size.y - 16.0, 8.0))

## 小卖部「买」按钮：按货架逐格显隐 + 标价 + 可买判定（缓存签名，避免每帧重建）。
## 这三个按钮创建时 visible=false，此前没有任何代码把它们打开过，
## 于是真人踩到小卖部格只能「刷新 / 离开」、买不了任何东西（见 fix/v0.0.2）。
func _refresh_shop_buttons() -> void:
	var open := int(st.get("shop_open", -1))
	var shops_d: Dictionary = st.get("shops", {})
	var slots: Array = []
	if shops_d.has(open):
		slots = shops_d[open].get("slots", [])
	var mine: Dictionary = _state_player(my_peer)
	var money := int(mine.get("money", 0))
	var bag: Array = mine.get("items", [])
	# 黑卡还有次数时本次购买免费：不该因为现金不够而置灰
	var free_buy := false
	for it in bag:
		if String(it.id) == "黑卡" and int(it.get("charges", 0)) > 0:
			free_buy = true
	var refresh := int(st.get("refresh_price", 0))
	var sig := "%d|%s|%d|%d|%s|%d" % [open, str(slots), money, bag.size(), str(free_buy), refresh]
	if sig == _shop_btn_sig:
		return
	_shop_btn_sig = sig
	for i in shop_btns.size():
		var b: Button = shop_btns[i]
		var id := String(slots[i]) if i < slots.size() else ""
		if id == "":
			b.visible = false
			continue
		var price := ItemData.price(String(ItemData.def(id).quality))
		b.visible = true
		b.text = "买 %s %s" % [id, GameData.fmt_money(price)]
		b.disabled = bag.size() >= 5 or (not free_buy and money < price)
	if shop_refresh_btn != null:
		shop_refresh_btn.text = "刷新 · %s" % GameData.fmt_money(refresh)
		shop_refresh_btn.disabled = money < refresh

## 黑市面板刷新（缓存签名，避免每帧重建）
func _refresh_black_ui() -> void:
	var slots: Array = st.get("black_slots", [])
	var pay_mode := String(st.get("black_pay_mode", ""))
	var need := int(st.get("black_pay_need", 0))
	var got := int(st.get("black_pay_got", 0))
	var sig := "%s|%s|%d|%d" % [str(slots), pay_mode, need, got]
	if sig == _black_sig:
		return
	_black_sig = sig
	for i in black_btns.size():
		var b: Button = black_btns[i]
		var id := String(slots[i]) if i < slots.size() else ""
		if id == "":
			b.text = "（已售）"
			b.disabled = true
		else:
			var q := String(ItemData.def(id).quality)
			var cost := int(ItemData.BLACK_COST.get(q, 1))
			b.text = "买【%s】·%s（%d地）" % [id, String(ItemData.QUALITY_NAMES.get(q, q)), cost]
			b.disabled = pay_mode != ""
	if pay_mode == "":
		black_hint.text = "选一件商品，或直接交费离开。"
	else:
		var what := String({"buy": "购买", "refresh": "刷新", "exit": "出口"}.get(pay_mode, pay_mode))
		black_hint.text = "正在结【%s】的账：已交 %d/%d 块地皮，点下方列表选择地皮。" % [what, got, need]
	_rebuild_black_picker(pay_mode != "")

func _rebuild_black_picker(active: bool) -> void:
	black_picker.visible = active
	for c in black_picker_box.get_children():
		c.free()
	if not active:
		return
	var tiles_arr: Array = st.get("tiles", [])
	var added := 0
	for i in mini(tiles_arr.size(), GameData.TILES.size()):
		var d: Dictionary = GameData.TILES[i]
		if String(d.get("type", "")) != "property":
			continue
		var t: Dictionary = tiles_arr[i]
		if int(t.get("owner", GameData.NO_OWNER)) != my_peer or bool(t.get("soil", false)):
			continue
		var b := UIKit.button("交出【%s】Lv%d · 地价 %s" % [
			String(d.name), int(t.get("level", 0)), GameData.fmt_money(int(d.price))], 13)
		var idx := i
		b.pressed.connect(func() -> void:
			if multiplayer.is_server():
				_black_pay(my_peer, idx)
			else:
				c_black_pay.rpc(idx)
		)
		black_picker_box.add_child(b)
		added += 1
	if added == 0:
		black_picker_box.add_child(UIKit.label("没有可用地皮", 12, UIKit.TEXT_DIM))

func _on_conn_lost(reason: String) -> void:
	Net.last_error = reason
	# 房主开菜单会 s_pause 全场暂停；若此时房主掉线，SceneTree.paused 不会被
	# change_scene_to_file 重置，新主菜单会继承暂停态 → 按钮/Room 列表 Timer
	# 全部不响应，界面看着正常却完全点不动（见 fix/v0.0.2）。
	get_tree().paused = false
	Engine.time_scale = 1.0
	Fx.go_to("res://scenes/main_menu.tscn")

func _on_exit() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Net.leave()
	Fx.go_to("res://scenes/main_menu.tscn")

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, false).timeout

## 等一个环节的操作窗口。返回 true = 真超时（该自动托管）；false = 环节已结束。
## 挡位变化（_timeout_rev 变）会按新秒数重计时；挡位为「不限时」则不托管。
## on_arm(sec) 在每次窗口（重）开始时调一次——弹窗倒计时条据此重启。
func _await_turn_window(kind: String, alive: Callable, on_arm := Callable()) -> bool:
	while running and alive.call():
		var rev := _timeout_rev
		var sec := GameSettings.turn_seconds(_settings.timeout_tier, kind)
		if on_arm.is_valid():
			on_arm.call(sec)
		# 分片等待（_WINDOW_TICK 一探，开销可忽略）：环节结束、挡位变化、到点超时都能及时响应。
		# 不能整段 `await _wait(sec)`——那样挡位中途变化要等满一整段才按新值重计时。
		# 到期判定锚定窗口起点的绝对时刻，不累加每跳的名义时长：SceneTreeTimer 要下一帧才触发，
		# 累加会每跳少算 0~1 帧，长窗口（掷轮 140 跳）越跑越晚。
		# 时间基准乘 Engine.time_scale：_wait 走 SceneTreeTimer，吃的本就是缩放后的时间
		# （只有 autotest 会改它），不乘的话自动回归里的等待会被放大到不可接受。
		# sec <= 0（不限时）→ 没有到期时刻，只等前两种。
		var t0 := Time.get_ticks_msec()
		while running and alive.call() and _timeout_rev == rev:
			if sec > 0.0 and float(Time.get_ticks_msec() - t0) / 1000.0 * Engine.time_scale >= sec:
				return true
			await _wait(_WINDOW_TICK)
	return false

