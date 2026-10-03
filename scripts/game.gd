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
var table3d: TableView3D      # 2.5D 桌面容器（scripts/table_3d.gd）
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

# ---------------- 开局设置（房主权威，见 doc/game-design/开局设置.md §三之一） ----------------
const _WINDOW_TICK := 0.1            # 操作窗口的探测分片（秒）；也是 _ask 的应答粒度：
                                     # 玩家点了「买/不买」最多晚这么久被房主发现
const _BAR_LEAD := 1.0               # 弹窗倒计时条比窗口早这么多秒到底（沿袭基线的既有手感，
                                     # 条子归零即提交「拒绝」，见 _prompt_bar_arm）
var _settings: GameSettings          # 房主：来自大厅配置；客户端：从状态快照同步
var _timeout_rev := 0                # 挡位变化计数：等待中的环节据此重计时

# 操作窗口 kind → 倒计时条上的名称（与 GameSettings.turn_seconds 的 kind 一致）
const OP_KIND_LABELS := {
	"roll": "掷轮", "prompt": "决定", "item": "道具", "shop": "小卖部", "black": "黑市",
}

# ---------------- 道具系统（host 状态，详见 doc/game-design/道具系统.md） ----------------
var shops := {}            # tile_idx -> {slots: [id×3]}，每家小卖部独立货架
var items_consumed := {}   # 焚毁标记：一次性道具用后不回池（id -> true）
var refresh_count := 0     # 小卖部全局刷新次数（任何人刷新都让全场变贵，整局不重置）
var _shop_peer := 0        # 正在逛小卖部的玩家（0 = 无）
var _shop_tile := -1
var _shop_epoch := 0
var _awaiting_item := 0    # 道具阶段行动者（0 = 无）
var _item_epoch := 0
var _item_action := {}
var selected_slot := -1        # 当前选中的道具槽（阶段二；点桌上的手中牌由它记录）
var _discard_pending := -1     # 丢弃的二次确认槽位（手牌右键第一下点亮它；-1=无）
## 待确认丢弃**记住的那件道具 id**（与 `_discard_pending` 同生共死）。
##
## 为什么按 **id** 而不是按下标认这把「待确认」：下标是**位置**，背包一重排（交换生的换牌 /
## 蛋蛋节发牌 / 别处把它消耗掉）同一个下标就指向**另一张**牌 —— 只看下标的话，红标会落到玩家
## **从未 arm 过**的那张牌上，下一次右键**一下就把它丢了**（本该两步）。所以 arm 时记下 id，
## 每次重放红标之前先核对：id 对不上 = 这把待确认已经不作数，就地解除（见 `_refresh_table_props`）。
var _discard_pending_id := ""
## 待确认丢弃**arm 时的那个 (回合, 等待) 窗口**（与 `_discard_pending` 同生共死）。
##
## 规则：**待确认只在「arming 时的那个 (turn, await) 窗口」内有效**。为什么按窗口而不是按 `phase`：
## `phase` 只有 `"playing" if (running or lab_mode) else "ended"` 两种取值，`running` 只在开局 /
## 整局结束时翻转 ⇒ 「phase != playing」这条判据**在整局进行中恒假**，等于没有。而
## 「arm 一张牌 → 用『跳过』或超时结束道具阶段 → 背包没变 → 红标整轮挂着 → 下一次右键**一下**
## 就把它丢了」这条路正是从那儿漏过去的（本该两步确认）。换成窗口判据后两种自然解除都覆盖：
## **跳过 / 超时结束道具阶段**让 `await` 变、**回合推进**让 `turn` 变，任一变即失效；而**两次右键
## 之间不会有状态变化**，所以确认步骤仍然成立。
##
## 注意**不要**退化成 `await != "item"` 一刀切：arm 路径**刻意允许在非道具阶段 arm**
##（丢弃任何时候可用，见 `_on_table_click` 的右键分支），一刀切会把合法的一次 arm 直接抹掉。
var _discard_arm_turn := -9999
var _discard_arm_await := ""
var cheat_picker: Control
var cheat_slot := -1
var _tgt_slot := -1         # 指向性道具：待选目标的道具槽位（-1=无）
var _tgt_stage := ""        # ""=无 / "peer"=选玩家 / "tile"=选地块
var _tgt_peer := -1         # 两段式：已选定的目标玩家
var _tgt_tiles: Array = []  # 当前可选的地块 idx
var target_hint: Control
var target_hint_l: Label
var shop_layer: Control          # 小卖部全屏界面（触发时独占，见 table_hud.gd）
var shop_panel: PanelContainer
var shop_cards: Array = []       # 每格 {holder: CenterContainer, price_l: Label}
var shop_btns: Array = []
var shop_refresh_btn: Button
var shop_leave_btn: Button
var shop_tile_l: Label
var shop_money_l: Label           # 面板里的现金读数（买按钮置灰时看得出理由）
var shop_timer_row: HBoxContainer # 面板里的倒计时行：与立牌倒计时同一份 _op_* 数据（独立控件，不依赖座位卡）
var shop_timer_kind: Label
var shop_timer_track: ColorRect
var shop_timer_fill: ColorRect
var shop_timer_left: Label
var _shop_btn_sig := ""          # 小卖部界面刷新签名（避免每帧重建）
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
var _info_tile := -1              # 格详情卡当前挂在哪一格（-1 = 没显示）
var info_title: Label
var info_body: Label
var info_sb: StyleBoxFlat
var rules_btn: Button            # 收起态：左下角「📖 规则说明」按钮
var rules_panel: PanelContainer  # 展开态：分页规则面板（原位向上展开）
var rules_body: RichTextLabel
var rules_tabs := {}             # 分页 key -> 按钮
var rules_open := false
var rules_tab := ""
## 四角身家条（批次 5 Task 3）：四条一起建、只显示有人的那几条（见 `_refresh_corner_bars`）。
## 取代了原先的右侧名册栏（`roster_box` / `roster_rows` 已删，理由见 table_hud.gd 里那段）。
var corner_bars: Array = []
var _corner_sig := ""              # 四角条的刷新签名（状态没变就不重写）
var _log_flash_tw: Tween          # 新战报时头部闪金（沉浸感）
var _op_kind := ""                # 当前操作窗口 kind（"" = 无窗口，簇收起）
var _op_left := 0.0               # 本机显示用剩余秒数：广播到达时重置，_process 逐帧扣 delta
                                  # （暂停时 _process 不跑 → 计时与房主的窗口一起冻结）
var _op_total := 0.0              # 窗口总时长；<=0 = 不限时（不显示进度条）
var _op_owner := -1               # 窗口归属玩家（倒计时显示在他的立牌上）
var _op_shown := false            # 上一帧是否在显示（用于收起时只补推一次隐藏）
var log_text: RichTextLabel
var log_panel: PanelContainer
var log_toggle: Button
var log_toast: VBoxContainer      # 顶部居中的战报弹出条容器（战报框默认收起时的替代）
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
var _roll_epoch := 0
var _shot_path := ""
var _shot_taken := false
var _shot_round := 2          # 摆拍在第几轮触发（默认 2；看装修/房子这类局中状态就调大）

# ---------------- 表现层状态 ----------------
## peer -> 上一次显示的金额（收支播报的判据）。座位卡与它上面那块滚动数字的
## 控件已随批次 5 Task 2 退场，这份状态搬到对局层自己身上（语义与 row.shown 一字未改）。
var _money_shown := {}
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

var lab_mode := false   # 道具试验场模式：建好局面但不跑回合循环

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
		elif a.begins_with("--shot-round="):
			_shot_round = maxi(1, int(a.substr(13)))
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

	# 赌桌小游戏独立成子节点：两端都在这里建同名节点，保证 s_casino_* 的 RPC 路径一致
	# （它自带全屏演出层，触发时自己挂到 g 上，与 board / HUD 没有先后依赖）
	casino = preload("res://scripts/casino.gd").new()
	casino.name = "CasinoTable"
	casino.g = self
	add_child(casino)

	# 设置面板上一段已建好（_build_ui 在前），此处按身份定「操作限时」行显隐——
	# 否则两行同时可见，要等首次改挡才归位
	_refresh_tier_ui()

	# 客户端这里不再写任何东西：原来那句「等待房主同步状态…」写在底栏状态条上，
	# 底栏已随批次 3 Task 6 取消（等房主的首份 s_state 广播即可，见 _broadcast_state）。
	if multiplayer.is_server():
		_host_setup()

	board.item_slot_clicked.connect(_on_item_slot_clicked)
	board.item_discard_clicked.connect(_on_discard_clicked)
	board.phase_spin_clicked.connect(_on_roll_pressed)
	board.phase_use_clicked.connect(_on_use_pressed)
	board.cancel_clicked.connect(_cancel_target)
	table3d.on_table_click = _on_table_click   # 桌面实体（转盘 / 手牌）先于桌垫内容消费点击
	Net.chat_received.connect(_refresh_chat)
	Net.connection_lost.connect(_on_conn_lost)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_chat_shown = Net.chat_history.size()
	_refresh_chat()
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		audio_volume = clampf(float(cfg.get_value("audio", "volume", 1.0)), 0.0, 1.0)
		audio_mute = bool(cfg.get_value("audio", "mute", false))
		# 正式导出版（release）不带开发者模式：F1 面板 / --dev / --lab 全部只在
		# 编辑器或调试构建里存在（见 dev_tools.toggle 与主菜单入口的同款门控）。
		dev.enabled = (bool(cfg.get_value("dev", "enabled", false)) or dev_flag) \
			and OS.is_debug_build()
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

# ================= 道具试验场（Item Lab）宿主接口 =================

## 进入试验场：建局但停住回合循环、隐藏对局 HUD（item_lab 复用真实玩法逻辑）
func enter_lab_mode() -> void:
	lab_mode = true
	running = false
	if board != null:
		board.auto_follow = false
		board.cam_locked = false
	_lab_hide_hud()

func _lab_hide_hud() -> void:
	# card_panel（左上角公告）已并入屏幕上方居中的 log_toast，故这里改成隐藏气泡
	for c in [opt_btn, log_panel, log_toggle, log_toast]:
		if c != null and is_instance_valid(c):
			c.visible = false

## 重建一局沙盒（同步版，不跑回合循环）
func lab_reset() -> void:
	running = false
	_event_decks = {}
	hp = _build_hp()
	htiles = []
	for i in GameData.TILES.size():
		htiles.append({"owner": GameData.NO_OWNER, "level": 0})
	shops = {}
	refresh_count = 0
	items_consumed = {}
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "shop":
			shops[i] = {"slots": ["", "", ""]}
			_stock_shop(i)
	_broadcast_state()

# ================= 界面构建 =================

func _build_ui() -> void:
	# 根 Control 默认 mouse_filter=STOP，会把落在它上面的鼠标事件整个吃掉。2.5D 之后棋盘
	# 住在 TableView3D 的 SubViewport 里（另一个 Viewport，不参与根视口的 GUI 拾取），
	# 于是「点棋盘」根本走不到 TableView3D._unhandled_input，3D 层永远收不到鼠标。
	# 根节点改为不吃鼠标：屏幕层各控件（暂停/战报/底栏/弹层）自己按需 STOP，
	# 落在桌面上的事件则放行给 3D 层做射线映射。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
			# 补全道具新增字段（缺失时一律用 .get 默认，兼容测试构造的玩家字典）
			"item_used_n": 0, "cost_pen": [], "first_used": false,
			"roll_bonus": 0, "reroll_next": false, "silence": 0, "silence2": 0, "shield": 0,
			"charm_used": false, "emg_used": false, "loan_left": 0, "rework": 3,
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
		if bool(p.get("reroll_next", false)):
			p.reroll_next = false
			roll = maxi(roll, randi_range(0, 12))
			_log("%s 的【时光倒流】重掷取高" % p.name, "#8fb7f2")
		if int(p.get("roll_bonus", 0)) != 0:
			roll = clampi(roll + int(p.roll_bonus), 0, 12)
			_log("%s 被【点名】，点数 +%d" % [p.name, int(p.roll_bonus)], "#c9a6ff")
			p.roll_bonus = 0
		if int(p.get("cheat_roll", -1)) >= 0:
			roll = clampi(int(p.cheat_roll), 0, 12)
			p.cheat_roll = -1
			_log("%s 掏出【作弊器】——这次转盘他说了算" % p.name, "#8fb7f2")
		if roll == 7 and _has_item(p, "幸运数7"):
			p.money = int(p.money) + 700
			_log("%s 掷出 7，【幸运数7】额外 +¥700" % p.name, "#74d188")
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

		var step := roll
		if roll > 0 and _has_item(p, "公交卡"):
			step += 1   # 公交卡：前进额外多走 1 格（后退/待命不触发）
		var path := GameData.compute_path(int(p.pos), step)
		if path.is_empty():
			_log("%s 转了个 0，原地待命一回合" % p.name, "#8a90a5")
			break  # 待命也算完成投掷，仍可用道具
		for idx in path:
			if idx == 0:
				p.money = int(p.money) + _salary_amount(p)
				_log("%s 踏上起点，领取工资 %s" % [p.name, GameData.fmt_money(_salary_amount(p))], "#74d188")
				_maybe_emergency(p)
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
				var fee := _fine_mod(p, int(d.amount))
				_log("%s 落在【%s】，被强制缴费 %s" % [p.name, d.name, GameData.fmt_money(fee)], "#ef7b74")
				s_card.rpc("【%s】强制缴费 %s" % [d.name, GameData.fmt_money(fee)], "bad")
				await _wait(0.6)
				_pay(p, fee, {})
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

## 机会/命运预生成牌堆（抽完再补洗）——「小抄」要能预览顶张，就必须有稳定牌序
var _event_decks := {}

func _new_event_deck(kind: String) -> Array:
	var pool := GameData.events_for(kind)
	if not blackshop_enabled:
		pool = pool.filter(func(c: Dictionary) -> bool: return not c.has("enter_blackshop"))
	if pool.is_empty():
		pool = GameData.events_for(kind)
	var d := pool.duplicate(true)
	d.shuffle()
	return d

func _draw_event(kind: String) -> Dictionary:
	if not _event_decks.has(kind) or (_event_decks[kind] as Array).is_empty():
		_event_decks[kind] = _new_event_deck(kind)
	return (_event_decks[kind] as Array).pop_front()

func _peek_event(kind: String) -> Dictionary:
	if not _event_decks.has(kind) or (_event_decks[kind] as Array).is_empty():
		_event_decks[kind] = _new_event_deck(kind)
	return (_event_decks[kind] as Array)[0]

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
	var price := _buy_price(p, int(d.price))
	if int(p.money) < price:
		_log("%s 的现金买不起【%s】，只能眼馋路过" % [p.name, d.name])
		return
	var ok := await _ask(p, "buy", price, "购买地产",
		"要买下【%s】吗？\n售价 %s · 基础租金 %s\n你的现金 %s" % [
			d.name, GameData.fmt_money(price), GameData.fmt_money(int(d.rent)), GameData.fmt_money(int(p.money))],
		"买下它！")
	if ok and running and int(p.money) >= price and int(htiles[idx].owner) == GameData.NO_OWNER:
		p.money = int(p.money) - price
		htiles[idx].owner = int(p.peer)
		_log("%s 以 %s 买下了【%s】" % [p.name, GameData.fmt_money(price), d.name], "#f0c064")

func _resolve_upgrade(p: Dictionary, idx: int) -> void:
	var d: Dictionary = GameData.TILES[idx]
	var t: Dictionary = htiles[idx]
	var cost := GameData.upgrade_cost(idx)
	if int(t.level) >= GameData.MAX_LEVEL or int(p.money) < cost:
		return
	var next_rent := int(d.rent) * (2 + int(t.level))
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
	rent = _rent_gain(op, rent)   # 招财猫 +50 / 包租婆 ×1.2
	rent = _rent_pay(p, rent)     # 保安巡逻 -30%
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
		if int(card.move_steps) < 0 and (_immune_debuff(p) or _has_item(p, "雨伞")):
			_log("%s 免疫了后退" % p.name, "#8fb7f2")
			return
		var path := GameData.compute_path_steps(int(p.pos), int(card.move_steps))
		for idx in path:
			if idx == 0:
				p.money = int(p.money) + _salary_amount(p)
				_log("%s 顺路踏上起点，领工资 %s" % [p.name, GameData.fmt_money(_salary_amount(p))], "#74d188")
				_maybe_emergency(p)
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
	var short := amount - paid
	if short > 0:
		_maybe_emergency(p)   # 应急基金：可能补足救场
		if int(p.money) >= short:
			p.money = int(p.money) - short
			if not receiver.is_empty():
				receiver.money = int(receiver.money) + short
			short = 0
	if short > 0:
		p.alive = false
		p.money = 0
		for t in htiles:
			if int(t.owner) == int(p.peer):
				t.owner = GameData.NO_OWNER
				t.level = 0
		_log("%s 无力支付 %s，宣告破产出局！名下地产收归学校" % [p.name, GameData.fmt_money(amount)], "#ef7b74")
		s_card.rpc("%s 破产出局！" % p.name, "bust")

func _send_to_jail(p: Dictionary) -> void:
	if _immune_debuff(p):
		_log("%s 的香皂/护盾免除了这次送监" % p.name, "#8fb7f2")
		return
	if _has_item(p, "护身符") and not bool(p.get("charm_used", false)):
		p.charm_used = true
		_remove_item(p, "护身符")
		_log("%s 的【护身符】免除了这次送监（用掉）" % p.name, "#8fb7f2")
		return
	p.pos = GameData.JAIL_TILE
	p.skip = 1
	s_tp.rpc(int(p.peer), GameData.JAIL_TILE)

@rpc("authority", "call_local", "reliable")
func s_tp(peer: int, idx: int) -> void:
	board.set_teleport_target(peer, idx)
	board.play_move(peer, [], 0.0)

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

## 桌面实体被点中（画布像素 + 鼠标键）：命中手牌就左键选中 / 右键丢弃，命中转盘就掷轮；
## 返回 true 表示这次点击已被实体消费。未命中返回 false，点击照旧送进桌垫
##（点格子、点座位那些不受影响）。各条后果都沿用**既有的**路径，不新增 RPC、不新写一套。
##
## button 由 TableView3D 的输入映射原样带进来（MOUSE_BUTTON_LEFT / RIGHT），实体层据此分辨语义。
func _on_table_click(canvas_px: Vector2, button: int = MOUSE_BUTTON_LEFT) -> bool:
	if table3d == null or table3d.table_props == null:
		return false
	var tp = table3d.table_props
	# 1) 手牌优先：左键命中一张牌 = 选中，再点同一张 = 取消；右键命中一张牌 = 丢弃（两步确认）。
	#    左键**只在道具阶段吃点击** —— 牌是常驻显示的（每次广播都摆一遍），别的阶段点它没有意义，
	#    吃下点击就等于把本该落到棋盘上的一次点击吞成「什么都没发生」。这条闸是必须的：手牌就摆在
	#    近端自己面前（牌垫阶段按钮之下的木纹留白），与棋盘下沿相接，玩家想点棋盘时**很容易点到自己的牌**
	#    —— 没有闸的话这一下会被牌抢答成「改选另一张牌」，本该落到棋盘上的那一点击就白吞了
	#（测试里有配对用例钉住：同样的点，非道具阶段必须落回桌垫、道具阶段才归牌）。
	#    **手牌与近排格子已经完全不相交**（批次 5 Task 3 把整排放大并下移到阶段按钮之下的木纹留白；
	#    `hud_test` 断言牌盒与近排格子的相交处数为 0），所以这道闸防的是「抢答」，
	#    不再是「抢走格子下沿那几像素」。
	#    闸**含** `_tgt_stage == ""`（见 _hand_clickable）：选目标期间（牌垫上挂着「点地图选择目标格」
	#    的提示）玩家**正要**点棋盘选格，那时更不该被自己的牌抢答成「改选另一张牌」。
	#    所以选目标期间手牌对点击**完全透明**：左键落回棋盘 = 选格，
	#    右键 = 既有的取消。退出选目标态走 Esc / 右键（点牌不再参与）。
	#    出牌不在这里：选中之后由牌垫上的「使用道具」按钮走既有的 _on_use_pressed（两段式
	#    选目标 / 直接发 _send_use_item）——玩法路径一行没改。
	var hi: int = tp.hand_hit(canvas_px)
	if hi >= 0:
		if button == MOUSE_BUTTON_RIGHT:
			# 右键丢弃：走**既有的** _on_discard_clicked（第一步点亮待确认、第二步真丢 →
			# _discard_item / c_discard）。生效条件是「正在进行的对局」且「没在选目标」；
			# 其余情形（非 playing / 选目标中）**不消费**，落回棋盘 —— 右键在那里是既有的取消。
			# 这条正是补回「主动丢弃」入口（终审 R1）：座位卡的「✕」随牌位拆除后，
			# _on_discard_clicked 一度没有发射方。
			if String(st.get("phase", "")) == "playing" and _tgt_stage == "":
				_on_discard_clicked(my_peer, hi)
				return true
		elif _hand_clickable(hi):
			_on_hand_clicked(hi)
			return true
	# 2) 转盘：**只吃左键**（掷轮是主操作）。其它按键不消费 —— 右键落在转盘上等同落在棋盘上
	#    （既有的取消），于是「右键 = 牌上丢弃 / 转盘上不动作 / 棋盘上取消」三者自洽。
	if button == MOUSE_BUTTON_LEFT and tp.wheel_hit(canvas_px):
		_on_roll_pressed()
		return true
	# 3) 立牌：**只在"选目标"态吃点击** —— 判据与 `_on_seat_clicked` 的第一行**同源**
	#    （它只在 `_tgt_stage == "peer"` 且目标不是自己时才做事；其余情形它是无害的空转）。
	#    非选目标态下点立牌**没有后果**，消费它就是白吞一次点击 —— 立牌立在桌沿的木纹带上
	#    （桌垫之外），而它那块屏幕区域与近端那排格子 / 手牌是相接的，
	#    凭空多一块死区是不能接受的。
	#    只吃左键：右键在棋盘上是既有的取消（转盘上同理不吃），立牌不该破例。
	#    排在**手牌与转盘之后**：那两处一个在近端、一个在盘心，与桌沿的立牌互不重叠；
	#    反过来把立牌排前面，2D 端（自己的立牌这时看得见也点得到）会先把手牌 / 格子那一片吃掉。
	#    后果一律走**既有的** `_on_seat_clicked(peer)` —— 玩法链路一行没改。
	if button == MOUSE_BUTTON_LEFT and _tgt_stage == "peer":
		var si: int = tp.standee_hit(canvas_px)
		if si >= 0:
			var sp: int = tp.standee_peer(si)
			if sp != GameData.NO_PEER and sp != my_peer:
				_on_seat_clicked(sp)
				return true
	return false

## 这张手牌此刻点得动吗：轮到我、正在道具阶段、没在选目标，且这一张是已实装的道具。
## 判据与 _on_item_slot_clicked 的守卫**同源** —— 只有它真会做事的那一次点击才该被手牌消费。
## `_tgt_stage == ""` 是后补的一条（终审 R2）：选目标期间玩家正要**点棋盘选格**，而他点下去的那一下
## 很可能落在自己面前那排牌上（手牌就在近端、紧挨棋盘下沿）—— 没有这一条，牌会把这点击抢答成
## 「改选另一张牌」，本该落到棋盘上的那一次点击就白吞了（功能性漏洞）。
## 放行给桌垫之后，左键落回棋盘 = 选格、右键 = 既有的取消 —— 手牌在选目标期间对点击完全透明。
func _hand_clickable(hi: int) -> bool:
	if String(st.get("await", "")) != "item" or int(st.get("await_peer", -1)) != my_peer:
		return false
	if _tgt_stage != "":
		return false
	var items: Array = _state_player(my_peer).get("items", [])
	if hi < 0 or hi >= items.size():
		return false
	return bool(ItemData.def(String(items[hi].id)).get("implemented", false))

## 点手中的牌：选中 / 再点同一张取消。选中即调用**既有的** _on_item_slot_clicked
##（牌位时代的入口，玩法侧一个字没改）；出牌仍由牌垫上的「使用道具」走 _on_use_pressed。
## 选中的**表现侧**（桌上那张牌抬起 + 提亮）由 _on_item_slot_clicked 内部统一同步，这里不补。
func _on_hand_clicked(hi: int) -> void:
	if selected_slot == hi:
		_clear_item_selection()
		_refresh_actions()
		return
	_on_item_slot_clicked(my_peer, hi)

## 清掉「当前选中的道具」：玩法侧（selected_slot）+ 两处表现侧（牌垫牌位 / 桌上手牌）。
## 三处必须一起动 —— 只清 selected_slot，牌垫上会留一块绿光、桌上一张牌还抬着。
func _clear_item_selection() -> void:
	selected_slot = -1
	if board != null:
		board.set_item_selected(-1, -1)
	if table3d != null and table3d.table_props != null:
		table3d.table_props.set_hand_selected(-1)

## 掷骰：房主本地发信号；客户端走 RPC（此前按钮只查房主变量，客户端点了没反应）
func _on_roll_pressed() -> void:
	if String(st.get("await", "")) != "roll" or int(st.get("turn", -1)) != my_peer:
		return
	# 原先这里 `roll_btn.disabled = true` 做「按下即置灰」的本地即时反馈；底栏已随
	# 批次 3 Task 6 拆除，这条反馈也一并去掉。重复点击由房主侧的 `_awaiting_roll` 兜住：
	# 第一次掷出后它立刻归 0（`_play_turn`），后续点击在此处就被 await/turn 守卫挡住。
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

## 房主改「操作限时」挡位：立即生效并重计时（见 doc/game-design/开局设置.md §三之一）
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

## 操作窗口剩余时间（全员可见）走这条专用 RPC，而不进 _broadcast_state：
## 它按秒高频变化，进全量状态会让所有端每秒白渲染一整帧棋盘。
## kind="" 表示当前没有操作窗口（收簇）；total<=0 = 不限时；owner_peer = 窗口归属玩家
## （倒计时挂在他的立牌上，D 方案）。
@rpc("authority", "call_local", "reliable")
func s_op_timer(kind: String, left: float, total: float, owner_peer: int) -> void:
	_op_kind = kind
	_op_left = left
	_op_total = total
	_op_owner = owner_peer

## 房主：广播当前操作窗口的剩余时间（_await_turn_window 在窗口（重）开始、
## 剩余整秒变化、窗口关闭时各发一次；本机经 call_local 同路径生效）
func _op_timer_send(kind: String, left: float, total: float) -> void:
	s_op_timer.rpc(kind, left, total, _op_window_owner())

## 当前操作窗口的归属玩家（与 _broadcast_state 的 await 归属同一套判定；
## 各归属变量都在启动计时前赋值，见 _play_turn / _ask / 商店 / 黑市入口）。
## 找不到时回退当前行动者。
func _op_window_owner() -> int:
	if _awaiting_roll != 0:
		return _awaiting_roll
	if _awaiting_prompt != 0:
		return _awaiting_prompt
	if _awaiting_item != 0:
		return _awaiting_item
	if _shop_peer != 0:
		return _shop_peer
	if _black_peer != 0:
		return _black_peer
	return int(hp[turn_i].peer) if turn_i < hp.size() else -1

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
			"item_used": bool(p.get("item_used", false)), "silence": int(p.get("silence", 0)),
			"shield": int(p.get("shield", 0)),
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
		"phase": "playing" if (running or lab_mode) else "ended",
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
	log_head.text = "第 %d/%d 轮 · 战报" % [int(state.round), int(state.max_rounds)]
	_refresh_players()
	_refresh_actions()
	_refresh_chat()
	if String(state.phase) == "ended":
		_show_game_over()
		if at_mode != "" and not multiplayer.is_server():
			_autotest_client_finish(state)
	elif _shot_path != "" and not _shot_taken and (int(state.round) >= _shot_round or at_mode == ""):
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
	board.spin_wheel(v, int(st.get("turn", GameData.NO_PEER)))
	if v == 24 or v == 0:
		_flair_roll(v)

func _flair_roll(v: int) -> void:
	await get_tree().create_timer(WheelView.SPIN_TIME, false).timeout
	if not is_inside_tree():
		return
	if v == 24:
		Fx.float_text(self, _board_to_screen(board.wheel_screen_pos()) + Vector2(0, -60), "满值 12！再来一次", UIKit.ACCENT, 21)
	elif v == 0:
		Fx.float_text(self, _board_to_screen(board.wheel_screen_pos()) + Vector2(0, -60), "0……转了个寂寞", UIKit.TEXT_DIM, 19)

@rpc("authority", "call_local", "reliable")
func s_move(peer: int, path: Array, step_time: float) -> void:
	board.play_move(peer, path, step_time)

@rpc("authority", "call_local", "reliable")
func s_card(text: String, kind: String = "info", deck: String = "") -> void:
	Fx.play("card", -4.0)
	if deck != "":
		# 事件卡：从棋盘中央牌堆抽出，展示完镜头回到行动棋子
		board.play_deck_card(deck, kind, text, int(st.get("turn", GameData.NO_PEER)))
		if kind == "jail":
			Fx.shake(self, 9.0, 0.35)
			Fx.play("jail", -2.0)
		return
	# 非事件卡的公告（缴费 / 查寝 / 破产 / 黑市）不再占屏幕左上角：
	# 这些事件的调用点都已经先写过一条战报（`_log`），而战报现在就是屏幕上方居中的
	# 彩色气泡 —— 所以视觉交给那条居中提示即可，这里只保留「震屏 + 音效」这类强调。
	# （原先的左上角 card_panel 与战报是同一句话的第二份，属重复展示。）
	if kind == "jail":
		Fx.shake(self, 9.0, 0.35)
		Fx.play("jail", -2.0)
	elif kind == "bust":
		Fx.shake(self, 7.0, 0.3)
		Fx.play("bust", 0.0)

@rpc("authority", "call_local", "reliable")
func s_log(line: String) -> void:
	log_text.append_text(line + "\n")
	_push_log_toast(line)
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

## 战报消息在屏幕上方弹出：加一条、最多同时留 4 条、自动淡出。
## 战报框（log_panel）默认收起，但记录照旧全写进 log_text，一条不丢。
func _push_log_toast(line: String) -> void:
	if log_toast == null or not is_instance_valid(log_toast):
		return
	var pill := TableHud.make_log_toast(line)
	log_toast.add_child(pill)
	pill.modulate.a = 0.0
	# 补间挂在 pill 自身上：pill 被回收时补间随之销毁，不会去动已释放的节点
	var tw := pill.create_tween()
	tw.tween_property(pill, "modulate:a", 1.0, 0.18)
	tw.tween_interval(2.4)
	tw.tween_property(pill, "modulate:a", 0.0, 0.45)
	tw.tween_callback(pill.queue_free)
	# 只留最近 4 条，避免连击刷屏堆满整屏（先 remove 再 free，否则计数不降会死循环）
	while log_toast.get_child_count() > 4:
		var old := log_toast.get_child(0)
		log_toast.remove_child(old)
		old.queue_free()

@rpc("authority", "call_local", "reliable")
func s_prompt(token: int, title: String, text: String, ok_text: String) -> void:
	_show_prompt(token, title, text, ok_text)

# ================= 界面刷新 =================

## 桌面实体物件的刷新挂点：把物件重新贴回桌垫坐标（筹码堆 / 体力件 / 手牌也在这里）。
##
## 为什么**每次状态广播**都要刷、而不是建一次就完：**转盘轮缘**的位置与半径都是 BoardView 的
## **画布像素**口径（`wheel_screen_pos` / `wheel_screen_radius`），而半径 = `200 × 2D 镜头倍率`，
## 倍率会被 `focus_grid` / `focus_point_zoom` / `fit_overview` / 人数变化改动 —— 只建一次，
## 轮缘就会与桌垫上画出来的那个轮盘脱开。build_wheel 是幂等的，只改 transform 与
## mesh 尺寸，**不重建节点**，所以每次状态都调它没有代价。
##
## 注意**滚轮推移视角不算在内** —— 那是 TableView3D 的 3D 相机（`set_view` 改的是**视角推移**，
## 批次 4 起已取消推拉），只改相机的俯角与到桌心的距离，不碰 2D 的 `_zoom`，
## 桌垫图案与轮缘一起原样不动。「谁跟相机、谁不跟」见 table_props.gd
## 文件头的摆放约定：只有轮缘跟 2D 相机，筹码 / 体力件 / 手牌是画布常量的实物、不跟。
func _refresh_table_props() -> void:
	if table3d == null or table3d.table_props == null or board == null:
		return
	# 布局还没跑（首个 _process 之前）时取景没做，wheel_screen_pos/radius 都是错的 ——
	# 这一轮先跳过，等下一次状态广播（那时早有尺寸了）。判据与 fit_overview 的触发条件同源。
	if board.size.x <= 10.0:
		return
	table3d.table_props.build_wheel(board.wheel_screen_pos(), board.wheel_screen_radius())
	# 四块立牌（批次 5 Task 1）：名字 / 身家 / 公开背包。放在 `mine.is_empty()` 那道早退**之前**
	# —— 立牌的数据全来自 st.players（客户端也准），观战者（自己不在名册里）照样该看见四家。
	_refresh_standees()
	# 自己的现金 / 体力也搬到桌上（Task 3）：筹码堆按金额分档、体力件用掉的熄灭。
	# 输入只要**画布像素**那点信息 —— _state_player 读的是已同步的 st.players（客户端也有）。
	# 两者与 build_wheel 一样幂等（只改 transform / visible / 材质色，不重建节点），
	# 所以每次状态广播都调它们没有代价。
	var mine := _state_player(my_peer)
	if mine.is_empty():
		return                      # 还没轮到自己进状态（理论上不会）：宁可什么都不摆
	table3d.table_props.set_chips(int(mine.get("money", 0)))
	table3d.table_props.set_stamina(int(mine.get("stamina", 0)), _stamina_cap(mine))
	# 自己的道具 = 桌上一排「手中牌」（Task 4 显示 / Task 5 点选）
	table3d.table_props.set_hand(mine.get("items", []))
	# 选中反馈（抬起 + 提亮）画在桌上那张牌身上：set_hand 重摆位置时不会带上它，
	# 所以每次广播都按玩法侧的 selected_slot 重设一遍（单一来源始终是 selected_slot）。
	table3d.table_props.set_hand_selected(selected_slot)
	# 待确认丢弃的红标同理：单一来源是 _discard_pending，每次广播重放一遍，广播后不丢。
	# 但**重放前先核对这把待确认还作不作数**：armed 之后它原本永不解除 ⇒ ①道具阶段结束
	#（跳过 / 超时 / 回合推进），红标整轮挂着，下一次右键**一下**就把牌丢了（本该两步确认）；
	# ②背包在此期间重排，下标指到了另一张牌，红标落到玩家从未 arm 过的牌上、一次右键就丢错东西。
	# 判据两条：窗口（arm 时的 turn/await，理由见 _discard_arm_turn）+ 按 **id** 认牌而不是按下标
	#（下标会在重排时指向另一张，理由见 _discard_pending_id）。
	# 注意它只是**表现层**的本地状态：不进 s_state、不改玩法，清掉之后照旧把 -1 重放下去。
	if _discard_pending >= 0:
		var hand_items: Array = mine.get("items", [])
		var stale: bool = int(st.get("turn", -1)) != _discard_arm_turn \
			or String(st.get("await", "")) != _discard_arm_await \
			or _discard_pending >= hand_items.size() \
			or String(hand_items[_discard_pending].id) != _discard_pending_id
		if stale:
			_clear_discard_pending()
	table3d.table_props.set_hand_discard_pending(_discard_pending)

## 客户端也能算的身家：与 `_refresh_players` 顶部战况面板**同一公式**，但读的是已同步的
## `st.tiles`，而不是房主专有的 `htiles` —— 立牌两端都要显示（客户端没有 hp / htiles）。
func _state_worth(peer: int) -> int:
	var v := int(_state_player(peer).get("money", 0))
	var tiles_arr: Array = st.get("tiles", [])
	for i in mini(tiles_arr.size(), GameData.TILES.size()):
		var td: Dictionary = tiles_arr[i]
		if int(td.get("owner", GameData.NO_OWNER)) == peer:
			v += int(GameData.TILES[i].price) + int(td.get("level", 0)) * GameData.upgrade_cost(i)
	return v

## 桌位顺序（底 / 左 / 上 / 右）的 peer 列表 = 把 st.players **轮转成"自己打头、其余按行动序"**，
## 于是 `STANDEE_BASE_PX[0..3]` / `TableHud.CORNER_SLOTS[0..3]` 依次对上 e0..e3
##（自己 / 下家 / 对家 / 上家）。
##
## **这是"谁坐哪个桌位"的唯一判据**（批次 5 Task 3 起）：桌上立牌与屏幕层四角身家条都读它，
## 所以"哪个角标对着哪块立牌"永远一致。自己不在名册里（观战 / 掉线重连）时从第 0 家起轮转
## —— 与立牌同一条退化路径（那时四块立牌都没有 `is_self`）。
func _seat_peers() -> Array:
	var pls: Array = st.get("players", [])
	var out: Array = []
	if pls.is_empty():
		return out
	var my_i := 0
	for i in pls.size():
		if int(pls[i].peer) == my_peer:
			my_i = i
			break
	for k in pls.size():
		out.append(int(pls[(my_i + k) % pls.size()].peer))
	return out

## 四块立牌的**数据**（批次 5 Task 1）。行序 = 桌位顺序（底 / 左 / 上 / 右），由 `_seat_peers` 定。
## 身家走 `_state_worth`（读 st.tiles）而不是 host 专有的 `_net_worth`：客户端也要显示。
func _refresh_standees() -> void:
	var t3 = table3d
	if t3 == null or t3.table_props == null:
		return
	var pls: Array = st.get("players", [])
	if pls.is_empty():
		t3.table_props.set_standees([])     # 还没进对局：一块都不摆（池子是空的）
		return
	var seats: Array = _seat_peers()
	var rows: Array = []
	for peer_v in seats:
		var peer := int(peer_v)
		var p: Dictionary = _state_player(peer)
		rows.append({
			"peer": peer, "name": String(p.get("name", "?")), "worth": _state_worth(peer),
			"color_idx": int(p.get("color", 0)), "alive": bool(p.get("alive", true)),
			"items": p.get("items", []), "is_self": peer == my_peer,
		})
	t3.table_props.set_standees(rows)

func _name_by_peer(peer: int) -> String:
	for p in st.get("players", []):
		if int(p.peer) == peer:
			return String(p.name)
	return "?"

func _refresh_players() -> void:
	# 桌面实体物件：每次状态广播都重新贴回桌垫坐标（见 _refresh_table_props 的注释）
	_refresh_table_props()
	var tiles_arr: Array = st.get("tiles", [])
	var worth_map := {}
	for p in st.get("players", []):
		var peer := int(p.peer)
		# 座位卡已随批次 5 Task 2 整体退场：这里**不再**给四条座位栏刷名字 / 现金 / 棋子 /
		# 体力 / 回合描边（`board._player_rows` 那套一并删除）。名字与身家现在由桌上的
		# 3D 立牌承担（`_refresh_standees`，就在上一行 `_refresh_table_props` 里），
		# 公开背包也归它；画布上不再有"哪张卡"可写。
		# 金额滚动 / 涨跌闪色也**没有落点了**，但飘字与音效仍以**棋子**为锚（下面那段），保留。

		# 身家 = 现金 + 名下地皮（地价 + 装修），与房主 `_net_worth` 同一公式。
		# 消费方：四角身家条（`_refresh_corner_bars` 的 standing）与悬停棋子的信息条
		#（后者在 board.render 里另算一份、同为这个公式）。
		var worth := int(p.money)
		for i in tiles_arr.size():
			var td: Dictionary = tiles_arr[i]
			if int(td.get("owner", GameData.NO_OWNER)) == peer:
				worth += int(GameData.TILES[i].price) + int(td.get("level", 0)) * GameData.upgrade_cost(i)
		worth_map[peer] = worth
		# 金额变动：数字滚动的那块控件没了，**收支反馈保留在棋子上的飘字 + 飞钞 + 音效**。
		# 「上一次显示的金额」从行里搬到一个 peer -> int 的表（`_money_shown`），
		# 判据与语义一字未改 —— 只有真的变了才播。
		var target := int(p.money)
		var shown := int(_money_shown.get(peer, target))
		_money_shown[peer] = target
		if shown != target and bool(p.alive):
			var diff := target - shown
			var col := UIKit.GOOD if diff > 0 else UIKit.DANGER
			# 收租时这一帧会有两条飘字（付款方红、收款方绿），两者都以「各自棋子」为中心，
			# 而全景缩放下两枚棋子可能只差十几像素、标签却有七八十像素宽 → 必然叠在一起。
			# 按涨/跌分开纵向落点：进账往上飘、支出往下飘，拉开约 46px，任何格距都不重叠。
			var fy := -26.0 if diff > 0 else 20.0
			var pos := _board_to_screen(board.token_screen_pos(peer)) + Vector2(0, fy)
			Fx.float_text(self, pos, ("+" if diff > 0 else "") + GameData.fmt_money(diff), col, 19)
			Fx.play("cash" if diff > 0 else "pay", -5.0)
			_spawn_money_fly(peer, diff)

	# 身家排名（名次徽章的依据）
	var order: Array = worth_map.keys()
	order.sort_custom(func(a, b) -> bool: return int(worth_map[a]) > int(worth_map[b]))

	# 四角身家条复用上面刚算出的身家/排名（公式只留这一处，避免两套算法悄悄跑偏）
	var standing: Array = []
	for i in order.size():
		var rp := int(order[i])
		var rpl := _state_player(rp)
		standing.append({
			"peer": rp, "rank": i + 1, "worth": int(worth_map[rp]),
			"name": String(rpl.get("name", "?")), "color": int(rpl.get("color", 0)),
			"money": int(rpl.get("money", 0)), "alive": bool(rpl.get("alive", true)),
		})
	_refresh_corner_bars(standing)

## 四角身家条（批次 5 Task 3）：取代右侧名册栏（理由与落位见 table_hud.gd 的 CORNER_SLOTS）。
##
## **角位 = 桌位**：第 i 条挂的玩家 = `_seat_peers()[i]`，与桌上第 i 块立牌是同一个人 ——
## 于是"选目标态哪块立牌亮着"与"哪一条角标在这儿"对得上。
##
## 每一条三行：名字（自己标「我」/ 破产标「破产」）、**身家**（大字）、**现金**（第二行小字，B）。
## 现金那行取的就是 `standing` 里现成的 `money`（`_refresh_players` 里已算好，**不重算**）——
## 身家 = 现金 + 地产，只有身家时玩家在买卖 / 付租那一刻看不到自己有多少现金。
##
## 数据一律取 `_refresh_players` 顶部**同一次**算出来的 `standing`（按身家倒序、带 rank）——
## 与 `board.render` 的悬停信息、以及房主的 `_net_worth` 同一公式，客户端也准
##（读的是已同步的 st.tiles）。**不要在这里另算一遍身家**。
##
## 带签名缓存：状态没变就不重写（每次广播都会走这里）。
func _refresh_corner_bars(standing: Array) -> void:
	if corner_bars.is_empty():
		return
	var by_peer := {}
	for e in standing:
		by_peer[int(e.peer)] = e
	var seats: Array = _seat_peers()
	var turn_peer := int(st.get("turn", -1))
	var phase := String(st.get("phase", ""))
	# 签名：角位归属（peer）+ 该条的 rank/worth/money/alive/color + 当前行动者与阶段
	var sig := "%d|%s|" % [turn_peer, phase]
	for i in corner_bars.size():
		var e: Dictionary = by_peer.get(int(seats[i]), {}) if i < seats.size() else {}
		sig += "%d,%d,%d,%d,%d,%d;" % [int(seats[i]) if i < seats.size() else GameData.NO_PEER,
			int(e.get("rank", 0)), int(e.get("worth", 0)), int(e.get("money", 0)),
			int(e.get("color", -1)), 1 if bool(e.get("alive", true)) else 0]
	if sig == _corner_sig:
		return
	_corner_sig = sig

	for i in corner_bars.size():
		var bar: Dictionary = corner_bars[i]
		var root: Control = bar.root
		var e: Dictionary = by_peer.get(int(seats[i]), {}) if i < seats.size() else {}
		if e.is_empty():
			root.visible = false          # 人少了：多出来的那一条藏起来（不拆节点）
			continue
		root.visible = true
		var peer := int(e.peer)
		var alive := bool(e.alive)
		bar.peer = peer
		# 棋子色小片：与棋盘上的棋子同一个配色来源（只在真变了才重建）
		var col := int(e.color)
		if bar.chip == null or not is_instance_valid(bar.chip) or int(bar.chip_color) != col:
			for c in (bar.chip_slot as Control).get_children():
				c.queue_free()
			bar.chip = UIKit.chip(GameData.PLAYER_COLORS[clampi(col, 0, 3)], 18)
			(bar.chip_slot as Control).add_child(bar.chip)
			bar.chip_color = col
		# 名次徽章：1 金 / 2 银 / 3 铜 / 其余石板灰（它是一棵小节点树，只在名次真变了才重建）
		var rank := int(e.get("rank", 0))
		if int(bar.badge_rank) != rank:
			for c in (bar.badge_slot as Control).get_children():
				c.queue_free()
			bar.badge = UIKit.rank_badge(rank, 24)
			(bar.badge_slot as Control).add_child(bar.badge)
			bar.badge_rank = rank
		# 名字（自己标「我」、破产标「破产」）；轮到谁行动谁的名字变金
		var active: bool = phase == "playing" and peer == turn_peer and alive
		var tags := ""
		if peer == my_peer:
			tags += "（我）"
		if not alive:
			tags += "（破产）"
		var name_l: Label = bar.name_l
		name_l.text = "%s%s" % [String(e.get("name", "?")), tags]
		name_l.add_theme_color_override("font_color",
			UIKit.TEXT_DIM if not alive else (UIKit.ACCENT if active else UIKit.TEXT))
		# 身家（名次的依据）；破产与立牌 / 座位卡同款提示：不报数字
		var worth_l: Label = bar.worth_l
		worth_l.text = "已出局" if not alive else GameData.fmt_money(int(e.worth))
		worth_l.add_theme_color_override("font_color",
			UIKit.TEXT_DIM if not alive else UIKit.ACCENT)
		# 现金（B）：身家是「现金 + 地产」，决定买卖 / 付租的是这一行。破产那家没有现金可言，
		# 留空（**不隐藏控件** —— 藏了会把这一条的内容高度改掉、四条边线就不齐了）。
		var money_l: Label = bar.money_l
		money_l.text = "" if not alive else "现金 %s" % GameData.fmt_money(int(e.get("money", 0)))
		# 轮到谁行动：那一条描金边（与立牌上的倒计时、牌垫按钮的点亮是同一件事）。
		# 只在真变化时换样式盒（每次换都是一次九宫格纹理查找）。
		if bool(bar.border_active) != active:
			bar.border_active = active
			root.add_theme_stylebox_override("panel", UIKit.card_stylebox(
				Color(0.085, 0.095, 0.138, 0.82), 10,
				Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.9) if active
					else Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.7), 1, 4))

func _refresh_actions() -> void:
	var phase := String(st.get("phase", "playing"))
	var await_state := String(st.get("await", ""))
	var is_my_roll := await_state == "roll" and int(st.get("turn", -1)) == my_peer
	var my_turn := phase == "playing" and int(st.get("turn", -1)) == my_peer
	_refresh_item_buttons(my_turn, await_state)
	# 「轮到你转盘了」——原来这里写底栏状态条文案并顺手把镜头对回自己。底栏已随批次 3
	# Task 6 取消：**状态文案这一层信息没有了**（见 doc/development/架构总览.md §五），
	# 「该你了」改由牌垫阶段按钮的点亮/置灰（set_phase_buttons 的 style）与立牌上的
	# 操作倒计时承担，发生过的事由战报承担。镜头对焦这半与文字无关，保留。
	if await_state == "roll" and is_my_roll:
		if not board.is_showing_deck_card() and not board.is_wheel_spinning() \
				and not board.is_rotating():
			board.focus_peer(my_peer)
	# 自动化测试：轮到自己时自动掷骰（用 roll_epoch 区分连掷的新请求）
	if at_mode != "" and is_my_roll and int(st.get("roll_epoch", -1)) != _at_roll_epoch:
		_at_roll_epoch = int(st.get("roll_epoch", -1))
		_at_auto_roll()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_F1:
			dev.toggle()
		elif k.keycode == KEY_ESCAPE and (_tgt_stage != "" or selected_slot >= 0):
			_cancel_target()   # 选目标态或「选中了一张牌」都算可取消的状态

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
	if _tgt_stage == "tile":
		if idx in _tgt_tiles:
			_finish_tile_target(idx)
		else:
			_log("该格不在可选范围内", "#8a90a5")
		return
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
			var owner_name := "无主 · 踩到可购买"
			if owner_id != GameData.NO_OWNER:
				owner_name = _name_by_peer(owner_id)
				var op := _player_by_peer(owner_id)
				if not op.is_empty():
					accent = GameData.PLAYER_COLORS[int(op.color) % GameData.PLAYER_COLORS.size()]
			body = "售价 %s · 租金 %s\n装修 Lv%d（%s）\n持有：%s" % [
				GameData.fmt_money(int(d.price)),
				GameData.fmt_money(GameData.rent_for(idx, tiles)), level, GameData.level_name(level),
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
	_info_tile = idx
	info_panel.visible = not rules_open
	_place_info_panel()
	info_panel.pivot_offset = info_panel.size * 0.5
	info_panel.scale = Vector2(0.94, 0.94)
	var tw := create_tween()
	tw.tween_property(info_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## 棋盘坐标 → 屏幕坐标。Batch2 把 BoardView 搬进 TableView3D 的 SubViewport 后，
## tile/token/wheel_screen_pos 返回的都是那个 2048² 画布的坐标，而消费它们的屏幕层 HUD
## 活在窗口空间（1280×800）—— 少了这步换算，格详情卡会被下面的 clamp 钉在屏幕边缘、
## 收租/转盘飘字也整体错位（Task 3 实测）。table3d 缺失或该点不在桌面上时原样返回（降级）。
func _board_to_screen(p: Vector2) -> Vector2:
	if table3d == null:
		return p
	var sp = table3d.viewport_to_screen(p)
	return p if sp == null else (sp as Vector2)

## 格详情卡悬浮在被点格子的正上方（原来是钉在屏幕左下角，和格子对不上号）。
## 镜头会平移/缩放/旋转，所以逐帧跟着格子走；上方放不下就翻到格子下方，并夹在屏幕内。
func _place_info_panel() -> void:
	if info_panel == null or not info_panel.visible or _info_tile < 0 or board == null:
		return
	var c := _board_to_screen(board.tile_screen_pos(_info_tile))
	var sz := info_panel.size
	var pos := Vector2(c.x - sz.x * 0.5, c.y - sz.y - 20.0)
	if pos.y < 8.0:
		pos.y = c.y + 20.0
	pos.x = clampf(pos.x, 8.0, maxf(8.0, size.x - sz.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, size.y - sz.y - 8.0))
	info_panel.position = pos

# ================= 弹窗与结算 =================

func _show_game_over() -> void:
	if _over_shown:
		return
	_over_shown = true
	_close_prompt()
	casino.close()
	# 小卖部面板同属模态：结算层不该被它压着（它的 z_index 高于结算层）
	shop_layer.visible = false
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
		var safe := line.replace("[", "［")
		log_text.append_text("[color=#7f8699]%s[/color]\n" % safe)
		# 聊天也要在屏幕上方弹一条：战报框默认收起，只写进记录里等于看不见
		_push_log_toast("[color=#9db2d8]%s[/color]" % safe)
	
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
	head.add_child(UIKit.label("道具卡片模板 · §12 规格（品质框 / 左上⚡或被动 / 右上计数 / 道具图案 / 价格不上卡）",
		14, UIKit.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close_btn := UIKit.button("✕ 关闭", 13)
	close_btn.pressed.connect(func() -> void: card_gallery.visible = false)
	head.add_child(close_btn)
	v.add_child(UIKit.label("小 = 道具栏 · 中 = 货架（价格随货架显示）· 大 = 发现三选一 / 使用展示 —— 图案 = assets/icons/item_*.png（Twemoji 烘焙，缺素材回退占位）",
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
		_card_cell("交换生", ItemCard.SIZE_SMALL, {}, "超稀有 · ⚡3"),
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
		_card_cell("亡牌飞行员coco", ItemCard.SIZE_LARGE, {}, "一次性 · 用后焚毁"),
		_card_cell("空想者的香皂", ItemCard.SIZE_LARGE, {"count": 7, "melt": true}, "融化中 · 剩 7 回合"),
		_card_cell("园中叶", ItemCard.SIZE_LARGE, {}, "预留 · 效果未定"),
	]))

	# 品质补全（草案 51 件）：按品质分组动态陈列，图案逐件核对用
	var first10 := ["平均主义", "作弊器", "交换生", "招财猫", "信托基金", "黑卡",
		"空想者的香皂", "蛋蛋节", "亡牌飞行员coco", "园中叶"]
	for q in ItemData.QUALITIES:
		var q_ids: Array = []
		for id2 in ItemData.ITEMS:
			if not first10.has(id2) and String(ItemData.ITEMS[id2].get("quality", "")) == q:
				q_ids.append(id2)
		if q_ids.is_empty():
			continue
		var q_cells: Array = []
		for id3 in q_ids:
			q_cells.append(_card_cell(id3, ItemCard.SIZE_MEDIUM, {}, ""))
		gv.add_child(_card_section("%s档 · 品质补全（%d 件）" % [ItemData.QUALITY_NAMES.get(q, q), q_ids.size()], q_cells))

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
	if _has_item(p, "空想者的香皂"):
		return true
	if int(p.get("shield", 0)) > 0:
		p.shield = int(p.get("shield", 0)) - 1
		_remove_item(p, "护腕")   # 护腕抵消一次后损坏
		_log("%s 的护腕挡住了这次负面效果" % p.name, "#8fb7f2")
		return true
	return false

func _remove_item(p: Dictionary, id: String) -> bool:
	for i in range((p.get("items", []) as Array).size() - 1, -1, -1):
		if String(p.items[i].id) == id:
			p.items.remove_at(i)
			return true
	return false

## 背包 / 体力上限（置物架 / 充电宝改「写死 5」为按玩家计算）
func _bag_cap(p: Dictionary) -> int:
	return 5 + (2 if _has_item(p, "置物架") else 0)

func _stamina_cap(p: Dictionary) -> int:
	return 5 + (1 if _has_item(p, "充电宝") else 0)

func _salary_amount(p: Dictionary) -> int:
	return GameData.SALARY + (300 if _has_item(p, "校园卡") else 0)

## 强制缴费修正：学费上涨(全员 +50%) → 保修卡(减半) → 优惠券(-300)
func _fine_mod(victim: Dictionary, amount: int) -> int:
	var a := amount
	for o in hp:
		if bool(o.get("alive", true)) and _has_item(o, "学费上涨"):
			a = int(a * 1.5)
			break
	if _has_item(victim, "保修卡"):
		a = int(a / 2)
	if _has_item(victim, "优惠券"):
		a = maxi(0, a - 300)
	return maxi(0, a)

func _buy_price(p: Dictionary, price: int) -> int:
	return maxi(0, price - (300 if _has_item(p, "砍价高手") else 0))

func _rent_gain(op: Dictionary, rent: int) -> int:
	if _has_item(op, "招财猫"):
		rent += 50
	if _has_item(op, "包租婆"):
		rent = int(rent * 1.2)
	return maxi(0, rent)

func _rent_pay(payer: Dictionary, rent: int) -> int:
	if _has_item(payer, "保安巡逻"):
		rent = int(rent * 0.7)
	return maxi(0, rent)

## 应急基金：现金低于 5000 时补足（每局一次，触发即弃）
func _maybe_emergency(p: Dictionary) -> void:
	if not bool(p.get("alive", true)):
		return
	if _has_item(p, "应急基金") and not bool(p.get("emg_used", false)) and int(p.get("money", 0)) < 5000:
		p.emg_used = true
		p.money = 5000
		_remove_item(p, "应急基金")
		_log("%s 的【应急基金】到账，现金补足到 %s" % [p.name, GameData.fmt_money(5000)], "#74d188")

## 单件道具的实付体力：错峰用电(本回合首件 -1) + 待消耗消耗修正(喇叭/二两寒暑) + 实例成本差(二手群接龙)
func _item_cost(p: Dictionary, it: Dictionary) -> int:
	var d := ItemData.def(String(it.id))
	var cost := int(d.get("cost", 0))
	if _has_item(p, "错峰用电") and not bool(p.get("first_used", false)):
		cost -= 1
	var pen: Array = p.get("cost_pen", [])
	if not pen.is_empty():
		cost += int(pen[0])
	cost += int(it.get("cost_delta", 0))
	return maxi(0, cost)

func _consume_cost_pen(p: Dictionary) -> void:
	var pen: Array = p.get("cost_pen", [])
	if not pen.is_empty():
		pen.pop_front()

## 前进并结算落点（含公交卡 +1；路过起点领工资）
func _move_and_resolve(p: Dictionary, steps: int) -> void:
	var s := steps
	if s > 0 and _has_item(p, "公交卡"):
		s += 1
	var path := GameData.compute_path_steps(int(p.pos), s)
	for idx in path:
		if idx == 0:
			p.money = int(p.money) + _salary_amount(p)
			_log("%s 顺路踏上起点，领工资 %s" % [p.name, GameData.fmt_money(_salary_amount(p))], "#74d188")
			_maybe_emergency(p)
	if not path.is_empty():
		p.pos = path[path.size() - 1]
		s_move.rpc(int(p.peer), path, 0.09)
		await _wait(0.25 + path.size() * 0.09)
	await _resolve_tile(p)

## 统一发放入口：背包满返回 false；香皂入场初始化融化计数（他人拾取重新计 10 回合）
func _grant_item(p: Dictionary, id: String) -> bool:
	if p.items.size() >= _bag_cap(p):
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
	var cap := _stamina_cap(p)
	if int(p.get("stamina", 3)) >= cap:
		if _has_item(p, "校历"):
			p.money = int(p.money) + 300
			_log("【校历】%s 体力已满，溢出折算为 %s" % [p.name, GameData.fmt_money(300)], "#74d188")
	else:
		p.stamina = mini(int(p.get("stamina", 3)) + 1, cap)
	p.item_used = false
	p.item_used_n = 0
	p.first_used = false
	if int(p.get("silence", 0)) > 0:
		p.silence = int(p.get("silence", 0)) - 1   # 包场/反作弊：禁道具回合数 -1
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
	# 助学贷款：连续 3 回合各还 600（debuff，可被香皂/护盾免疫）
	if int(p.get("loan_left", 0)) > 0:
		p.loan_left = int(p.loan_left) - 1
		if _immune_debuff(p):
			_log("%s 的护盾/香皂免除了助学贷款还款" % p.name, "#8fb7f2")
		else:
			_pay(p, 600, {})
	if _has_item(p, "信托基金"):
		p.money = int(p.money) + 100
		_log("【信托基金】给 %s 发了 %s 零花钱" % [p.name, GameData.fmt_money(100)], "#74d188")
	_maybe_emergency(p)

func _has_usable(p: Dictionary) -> bool:
	if int(p.get("silence", 0)) > 0:
		return false
	var limit := 2 if _has_item(p, "重修卡") else 1
	if int(p.get("item_used_n", 0)) >= limit or bool(p.get("item_used", false)):
		return false
	for it in p.get("items", []):
		var d := ItemData.def(String(it.id))
		if String(d.type) == "passive" or not bool(d.implemented):
			continue
		if int(it.get("cd", 0)) > 0:
			continue
		if int(p.get("stamina", 0)) < _item_cost(p, it):
			continue
		return true
	return false

func _item_phase(p: Dictionary) -> void:
	if not running or not bool(p.alive) or not _has_usable(p):
		return
	var limit := 2 if _has_item(p, "重修卡") else 1
	while running and int(p.get("item_used_n", 0)) < limit and _has_usable(p):
		_item_epoch += 1
		var epoch := _item_epoch
		_awaiting_item = int(p.peer)
		_item_action = {"epoch": -1}
		_broadcast_state()
		if bool(p.bot):
			if not _bot_use_one(p):
				_item_action = {"epoch": epoch, "action": "skip"}
		else:
			_arm_item_timeout(epoch, int(p.peer))
		while running and _awaiting_item == int(p.peer) and int(_item_action.get("epoch", -1)) != epoch:
			await _wait(0.1)
		if not running:
			return
		_awaiting_item = 0
		_broadcast_state()
		if String(_item_action.get("action", "")) == "skip":
			break

## 机器人用一次道具：选第一件可用；需选目标的挑一名随机存活对手（两段式再挑一块地）；选地块的随机瞬移
func _bot_use_one(p: Dictionary) -> bool:
	for i in p.get("items", []).size():
		var it: Dictionary = p.items[i]
		var d := ItemData.def(String(it.id))
		if String(d.type) == "passive" or not bool(d.implemented):
			continue
		if int(it.get("cd", 0)) > 0 or int(p.get("stamina", 0)) < _item_cost(p, it):
			continue
		var arg := -1
		var arg2 := -1
		var tgt := String(d.get("target", ""))
		if tgt == "player":
			var others := _item_targets(int(p.peer))
			if String(d.get("then", "")) == "own_prop":
				others = others.filter(func(x) -> bool: return not _own_props(int(x.peer)).is_empty())
			if String(it.id) == "交换生":
				others = others.filter(func(x) -> bool: return not (x.get("items", []) as Array).is_empty())
			if others.is_empty():
				continue
			arg = int(others[randi_range(0, others.size() - 1)].peer)
			if String(d.get("then", "")) == "own_prop":
				var props := _own_props(arg)
				arg2 = props[randi_range(0, props.size() - 1)]
		elif tgt == "tile":
			arg = randi_range(0, GameData.TILES.size() - 1)
		_use_item(int(p.peer), i, arg, arg2)
		return true
	return false

func _arm_item_timeout(epoch: int, peer: int) -> void:
	var timed_out := await _await_turn_window("item",
		func() -> bool: return _awaiting_item == peer and int(_item_action.get("epoch", -1)) != epoch)
	if timed_out:
		_log("%s 在道具阶段发呆，跳过" % _name_by_peer(peer), "#8a90a5")
		_item_action = {"epoch": epoch, "action": "skip"}

func _use_item(peer: int, slot: int, arg: int, arg2: int = -1) -> void:
	var p := _player_by_peer(peer)
	if p.is_empty() or _awaiting_item != peer:
		return
	if int(p.get("silence", 0)) > 0:
		return
	var limit := 2 if _has_item(p, "重修卡") else 1
	if int(p.get("item_used_n", 0)) >= limit or bool(p.get("item_used", false)):
		return
	var items: Array = p.get("items", [])
	if slot < 0 or slot >= items.size():
		return
	var it: Dictionary = items[slot]
	var d := ItemData.def(String(it.id))
	if String(d.type) == "passive" or not bool(d.implemented):
		return
	var cost := _item_cost(p, it)
	if int(it.get("cd", 0)) > 0 or int(p.get("stamina", 0)) < cost:
		return
	var prev_cd := int(it.get("cd", 0))
	if String(it.id) == "蛋蛋节" or String(it.id) == "亡牌飞行员coco":
		items_consumed[String(it.id)] = true
		items.remove_at(slot)
	p.stamina = int(p.stamina) - cost
	it.cd = int(d.cooldown)
	if not await _apply_item_effect(p, it, arg, arg2):
		# 前置条件不满足 → 退还体力/冷却
		it.cd = prev_cd
		p.stamina = int(p.stamina) + cost
		return
	p.item_used_n = int(p.get("item_used_n", 0)) + 1
	p.first_used = true
	_consume_cost_pen(p)
	if int(p.item_used_n) >= limit:
		p.item_used = true
		if limit == 2:
			p.rework = int(p.get("rework", 3)) - 1
			if int(p.rework) <= 0:
				_remove_item(p, "重修卡")
				_log("%s 的【重修卡】用尽三次，作废回池" % p.name, "#c9a6ff")
	_item_action = {"epoch": _item_epoch, "action": "used"}
	_broadcast_state()

## 某玩家名下的地产序号
func _own_props(peer: int) -> Array:
	var out := []
	for i in htiles.size():
		if int(htiles[i].get("owner", GameData.NO_OWNER)) == peer \
				and String(GameData.TILES[i].get("type", "")) == "property" \
				and not bool(htiles[i].get("soil", false)):
			out.append(i)
	return out

## 道具效果本体（不含体力/冷却/每回合/焚毁；对局与试验场共用）。
## 返回 true = 效果已发生；false = 前置条件不满足（调用方退还体力/冷却）。
func _apply_item_effect(p: Dictionary, it: Dictionary, arg: int, arg2: int = -1) -> bool:
	var id := String(it.id)
	var t := _player_by_peer(arg)
	var need_target: bool = String(ItemData.def(id).get("target", "")) != ""
	if need_target and (t.is_empty() or not bool(t.alive)):
		return false
	match id:
		# ---- 首批 ----
		"作弊器":
			p.cheat_roll = clampi(arg, 0, 12)
			_log("%s 掏出【作弊器】，下一次转盘他说了算" % p.name, "#8fb7f2")
		"平均主义":
			var alive: Array = hp.filter(func(x: Dictionary) -> bool: return bool(x.alive))
			if alive.is_empty():
				return false
			var total := 0
			for a in alive:
				total += int(a.money)
			var share := int(total / alive.size())
			var rem := total - share * alive.size()
			for a in alive:
				if _immune_debuff(a):
					continue
				a.money = share
			for k in rem:
				if not _immune_debuff(alive[k]):
					alive[k].money = int(alive[k].money) + 1
			_log("%s 发动【平均主义】，全场现金拉平！" % p.name, "#c9a6ff")
		"交换生":
			if t.is_empty() or int(t.peer) == int(p.peer) or (t.get("items", []) as Array).is_empty():
				return false
			var titems: Array = t.items
			var tidx := randi_range(0, titems.size() - 1)
			var theirs: Dictionary = titems[tidx]
			titems[tidx] = it
			var pitems: Array = p.get("items", [])
			var pslot := pitems.find(it)
			if pslot >= 0:
				pitems[pslot] = theirs
			_log("%s 用【交换生】从 %s 处换来【%s】！" % [p.name, t.name, String(theirs.id)], "#c9a6ff")
		"黑卡":
			it.charges = 3
			_log("%s 使用【黑卡】，接下来 3 次购买免单！" % p.name, "#f0a0c0")
		"蛋蛋节":
			_apply_egg_festival(p)
		"亡牌飞行员coco":
			_apply_coco(p)
		# ---- 白 ----
		"兼职中介":
			p.money = int(p.money) + 800
			_log("%s 找【兼职中介】拿到 ¥800" % p.name, "#74d188")
		"饭卡":
			p.money = int(p.money) + 300
			_log("%s 用【饭卡】刷出 ¥300" % p.name, "#74d188")
		"许愿池":
			var v := randi_range(-6, 6) * 100
			p.money = maxi(0, int(p.money) + v)
			_log("%s 往【许愿池】投币：%+d" % [p.name, v], "#74d188" if v >= 0 else "#ef7b74")
		"共享单车":
			await _move_and_resolve(p, 2)
		"外卖箱":
			p.money = int(p.money) + 200
			await _move_and_resolve(p, 1)
		"跑腿券":
			if _immune_debuff(t):
				_log("%s 被香皂/护盾挡下了跑腿费" % t.name, "#8fb7f2")
			else:
				var amt := mini(200, int(t.money))
				t.money = int(t.money) - amt
				p.money = int(p.money) + amt
				_log("%s 支使 %s 跑腿，收 ¥%d" % [p.name, t.name, amt], "#c9a6ff")
		"小抄":
			s_peek_card.rpc(int(p.peer), String(_peek_event("命运").get("t", "?")))
			_log("%s 偷偷看了眼命运牌堆顶" % p.name, "#f0c064")
		# ---- 绿 ----
		"占座":
			var own := _own_props(int(p.peer))
			if own.is_empty():
				return false
			var near: int = own[0]
			for i in own:
				if absi(int(i) - int(p.pos)) < absi(int(near) - int(p.pos)):
					near = int(i)
			p.pos = near
			s_tp.rpc(int(p.peer), near)
			_log("%s 用【占座】挪到最近的自家地皮（格 %d）" % [p.name, near], "#8fb7f2")
		"夜跑":
			await _move_and_resolve(p, 3)
		"团购拼单":
			p.money = int(p.money) + 400
			t.money = int(t.money) + 400
			_log("%s 与 %s 拼单，各 +¥400" % [p.name, t.name], "#74d188")
		"护腕":
			p.shield = int(p.get("shield", 0)) + 1
			_log("%s 戴上【护腕】，获得 1 层护盾" % p.name, "#8fb7f2")
		"助学贷款":
			p.money = int(p.money) + 1500
			p.loan_left = 3
			_log("%s 办了【助学贷款】：+¥1500，之后 3 回合各还 ¥600" % p.name, "#74d188")
		"二手交易":
			var other := []
			for oi in p.get("items", []):
				if oi != it:
					other.append(oi)
			if other.is_empty():
				return false
			var rm: Dictionary = other[randi_range(0, other.size() - 1)]
			_remove_item(p, String(rm.id))
			p.money = int(p.money) + 800
			_log("%s 二手卖掉【%s】，得 ¥800" % [p.name, String(rm.id)], "#74d188")
		"喇叭":
			var cpen: Array = t.get("cost_pen", [])
			cpen.append(1)
			t.cost_pen = cpen
			_log("%s 朝 %s 喊话：下个道具消耗 +1" % [p.name, t.name], "#c9a6ff")
		"组队学习":
			await _move_and_resolve(p, 2)
			if bool(t.alive) and running:
				await _move_and_resolve(t, 2)
		"二手群接龙":
			var pool := _item_pool("绿")
			if pool.is_empty():
				return false
			var gid: String = pool[randi_range(0, pool.size() - 1)]
			if not _grant_item(p, gid):
				return false
			(p.items[p.items.size() - 1] as Dictionary).cost_delta = -1
			_log("%s 从【二手群接龙】拿到【%s】（消耗 -1）" % [p.name, gid], "#74d188")
		"校园卡充值":
			if int(p.money) < 500:
				return false
			p.money = int(p.money) - 500
			p.stamina = mini(int(p.stamina) + 3, _stamina_cap(p))
			_log("%s 充了 ¥500 校园卡，恢复体力" % p.name, "#74d188")
		# ---- 蓝 ----
		"换座位":
			if t.is_empty() or int(t.peer) == int(p.peer):
				return false
			var pp := int(p.pos)
			p.pos = int(t.pos)
			t.pos = pp
			s_tp.rpc(int(p.peer), int(p.pos))
			s_tp.rpc(int(t.peer), int(t.pos))
			_log("%s 与 %s 交换了座位（不结算落点）" % [p.name, t.name], "#8fb7f2")
		"强制募捐":
			var got := 0
			for o in hp:
				if int(o.peer) != int(p.peer) and bool(o.alive):
					if _immune_debuff(o):
						continue
					var a2 := mini(500, int(o.money))
					o.money = int(o.money) - a2
					got += a2
			p.money = int(p.money) + got
			_log("%s 强制募捐，收了 ¥%d" % [p.name, got], "#c9a6ff")
		"交换课表":
			var mine := _own_props(int(p.peer))
			var yours := _own_props(int(t.peer))
			if mine.is_empty() or yours.is_empty():
				return false
			var mi: int = mine[randi_range(0, mine.size() - 1)]
			var yi: int = yours[randi_range(0, yours.size() - 1)]
			var o1 := int(htiles[mi].owner)
			htiles[mi].owner = int(htiles[yi].owner)
			htiles[yi].owner = o1
			_log("%s 与 %s 交换了地皮 #%d↔#%d" % [p.name, t.name, mi, yi], "#c9a6ff")
		"时光倒流":
			p.reroll_next = true
			_log("%s 使用【时光倒流】：下次转盘可重掷取高" % p.name, "#8fb7f2")
		"抄家队":
			var props := _own_props(int(t.peer))
			if props.is_empty():
				return false
			if _immune_debuff(t):
				_log("%s 被香皂/护盾挡下了抄家" % t.name, "#8fb7f2")
			else:
				var pi: int = arg2 if (arg2 in props) else props[randi_range(0, props.size() - 1)]
				htiles[pi].level = maxi(0, int(htiles[pi].level) - 1)
				_log("%s 抄了 %s 的【%s】（降 1 级）" % [p.name, t.name, String(GameData.TILES[pi].name)], "#c9a6ff")
		"拼车":
			p.pos = int(t.pos)
			s_tp.rpc(int(p.peer), int(p.pos))
			_log("%s 拼车到 %s 所在的格子" % [p.name, t.name], "#8fb7f2")
			await _resolve_tile(p)
		"保安队长":
			if (t.get("items", []) as Array).is_empty():
				return false
			if _immune_debuff(t):
				_log("%s 被香皂/护盾挡下了" % t.name, "#8fb7f2")
			else:
				var ti := randi_range(0, (t.items as Array).size() - 1)
				t.items[ti].cd = mini(5, int(t.items[ti].get("cd", 0)) + 2)
				_log("%s 让 %s 的【%s】冷却 +2" % [p.name, t.name, String(t.items[ti].id)], "#c9a6ff")
		"反作弊":
			for o in hp:
				if int(o.peer) != int(p.peer) and bool(o.alive):
					if _immune_debuff(o):
						continue
					o.silence = maxi(int(o.get("silence", 0)), 2)
			_log("%s 使用【反作弊】：本回合其他玩家不能使用道具" % p.name, "#c9a6ff")
		"体测":
			if _immune_debuff(t):
				_log("%s 被香皂/护盾挡下了体测" % t.name, "#8fb7f2")
			else:
				t.stamina = maxi(0, int(t.stamina) - 2)
				_log("%s 拉 %s 体测：体力 -2" % [p.name, t.name], "#c9a6ff")
		"换课":
			var s1 := int(p.stamina)
			p.stamina = mini(int(t.stamina), _stamina_cap(p))
			t.stamina = mini(s1, _stamina_cap(t))
			_log("%s 与 %s 交换了体力" % [p.name, t.name], "#8fb7f2")
		"点名":
			if _immune_debuff(t):
				_log("%s 被香皂/护盾挡下了点名" % t.name, "#8fb7f2")
			else:
				t.roll_bonus = int(t.get("roll_bonus", 0)) + 3
				_log("%s 点名 %s：下回合点数 +3" % [p.name, t.name], "#c9a6ff")
		# ---- 紫 ----
		"拆解钳":
			if (t.get("items", []) as Array).is_empty():
				return false
			var di := randi_range(0, (t.items as Array).size() - 1)
			var did := String(t.items[di].id)
			t.items.remove_at(di)
			_log("%s 用【拆解钳】摧毁了 %s 的【%s】（回池）" % [p.name, t.name, did], "#c9a6ff")
		"快递直达":
			if arg < 0 or arg >= GameData.TILES.size():
				return false
			p.pos = arg
			s_tp.rpc(int(p.peer), arg)
			_log("%s 用【快递直达】瞬移到格 %d" % [p.name, arg], "#8fb7f2")
			await _resolve_tile(p)
		"强拆令":
			var tp2 := _own_props(int(t.peer))
			if tp2.is_empty():
				return false
			if _immune_debuff(t):
				_log("%s 被香皂/护盾挡下了强拆" % t.name, "#8fb7f2")
			else:
				var si: int = arg2 if (arg2 in tp2) else tp2[randi_range(0, tp2.size() - 1)]
				htiles[si].owner = GameData.NO_OWNER
				htiles[si].level = 0
				_log("%s 强拆了 %s 的【%s】（归为无主）" % [p.name, t.name, String(GameData.TILES[si].name)], "#c9a6ff")
		"时间暂停":
			if _immune_debuff(t):
				_log("%s 被香皂/护盾挡下了时间暂停" % t.name, "#8fb7f2")
			else:
				t.sleep = 1
				_log("%s 让 %s 下一回合休眠" % [p.name, t.name], "#c9a6ff")
		"包场":
			if _immune_debuff(t):
				_log("%s 被香皂/护盾挡下了包场" % t.name, "#8fb7f2")
			else:
				t.silence = maxi(int(t.get("silence", 0)), 3)
				_log("%s 包场：%s 接下来两个回合不能使用道具" % [p.name, t.name], "#c9a6ff")
		# ---- 橙 ----
		"二两寒暑":
			var cpen2: Array = t.get("cost_pen", [])
			cpen2.append(2)
			cpen2.append(2)
			t.cost_pen = cpen2
			_log("%s 对 %s 施放【二两寒暑】：接下来两个道具消耗各 +2" % [p.name, t.name], "#c9a6ff")
		_:
			return false
	return true

## 小抄：把命运牌堆顶卡私密发给该玩家
@rpc("authority", "call_local", "reliable")
func s_peek_card(peer: int, text: String) -> void:
	if peer == my_peer:
		_log("（小抄）命运牌堆下一张：%s" % text, "#f0c064")

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
func c_use_item(slot: int, arg: int, arg2: int = -1) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == _awaiting_item:
		_use_item(sender, slot, arg, arg2)

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

## 蛋蛋节：全员送礼（规则见 doc/game-design/道具图鉴.md：他人白/绿/蓝三档均分，
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
	if board == null:
		return
	var using: bool = await_state == "item" and int(st.get("await_peer", -1)) == my_peer
	# 非道具阶段 → 清掉选中（绿光收掉）与未完成的选目标态
	if not using and selected_slot >= 0:
		_clear_item_selection()
	if not using and _tgt_stage != "":
		_cancel_target()
	# 「使用道具」按钮三态：未选=跳过 / 选中可用=绿 / 选中不可用（含被动）=灰
	var use_txt := "使用道具"
	var use_style := "normal"
	var use_dis := true
	if using:
		var p0 := _state_player(my_peer)
		var its0: Array = p0.get("items", [])
		if selected_slot < 0 or selected_slot >= its0.size():
			use_txt = "跳过"; use_style = "normal"; use_dis = false
		else:
			var it: Dictionary = its0[selected_slot]
			var d := ItemData.def(String(it.id))
			var usable: bool = String(d.get("type", "")) == "active" \
				and int(it.get("cd", 0)) == 0 \
				and int(p0.get("stamina", 0)) >= _item_cost(p0, it) \
				and not bool(p0.get("item_used", false)) and int(p0.get("silence", 0)) == 0
			use_txt = "使用「%s」" % String(it.id)
			use_style = "good" if usable else "normal"
			use_dis = not usable
	var spin_active: bool = my_turn and await_state == "roll"
	board.set_phase_buttons("转转盘", "primary" if spin_active else "normal", not spin_active,
		use_txt, use_style, use_dis)

## 选中一件道具（玩法侧入口，唯一）：写 selected_slot 并把**表现侧**一起同步。
##
## 表现侧有两处，必须都在这一个函数里做：① 桌上手牌抬起 + 提亮（`table_props.set_hand_selected`）；
## ② 待确认丢弃的红标清掉（选中任何一张 = 撤回待丢弃）。**不留给调用点** —— 原先那行
## `set_hand_selected` 补在唯一调用点（`_on_hand_clicked`），将来任何新入口（批次 5 的立牌）都会
## 静默丢掉可见的选中反馈。`board.set_item_selected` 现在只记状态、没有落点（座位卡已退场），
## 保留是为玩法侧接口不变。
func _on_item_slot_clicked(peer: int, slot: int) -> void:
	if peer != my_peer:
		return
	if String(st.get("await", "")) != "item" or int(st.get("await_peer", -1)) != my_peer:
		return
	var p := _state_player(my_peer)
	var items: Array = p.get("items", [])
	if slot < 0 or slot >= items.size():
		return
	if not bool(ItemData.def(String(items[slot].id)).get("implemented", false)):
		return
	# 任意道具都可选中（被动也能选中以丢弃）；能不能用由「使用」按钮三态表示
	selected_slot = slot
	_clear_discard_pending()                            # 选中任何一张 = 撤回上一步的待丢弃（槽位与 id 一起清）
	if board != null:
		board.set_item_selected(my_peer, slot)
		board.mark_discard_pending(-1, -1)
	if table3d != null and table3d.table_props != null:
		table3d.table_props.set_hand_selected(slot)     # 桌上那张牌抬起 + 提亮
	_sync_hand_discard_pending()                        # 撤回上一步的待丢弃红标
	_refresh_actions()

## 阶段二：使用选中的道具（按类型弹点数框 / 选玩家 / 点地）
func _on_use_pressed() -> void:
	if String(st.get("await", "")) != "item" or int(st.get("await_peer", -1)) != my_peer:
		return
	if selected_slot < 0:
		_on_skip_pressed()   # 未选卡时该按钮就是「跳过」
		return
	var p := _state_player(my_peer)
	var items: Array = p.get("items", [])
	if selected_slot >= items.size():
		return
	var iid := String(items[selected_slot].id)
	var tgt := String(ItemData.def(iid).get("target", ""))
	var then := String(ItemData.def(iid).get("then", ""))
	var slot := selected_slot
	_clear_item_selection()
	if iid == "作弊器":
		_open_cheat_picker(slot)
	elif tgt == "player":
		# 交换生：只能选「持有道具」的玩家；两段式道具：只能选「名下有地」的玩家
		_begin_peer_target(slot, iid == "交换生", then == "own_prop")
	elif tgt == "tile":
		_begin_tile_target(slot, range(GameData.TILES.size()))
	else:
		_send_use_item(slot, -1)

func _on_skip_pressed() -> void:
	if String(st.get("await", "")) != "item" or int(st.get("await_peer", -1)) != my_peer:
		return
	_cancel_target()
	if multiplayer.is_server():
		_item_action = {"epoch": _item_epoch, "action": "skip"}
	else:
		c_item_skip.rpc()

## 丢弃一件道具（两步确认）：第一次点亮「待确认」（牌身染红），第二次真丢。
## 落点现在是**桌面手牌上点右键**（见 _on_table_click）；本函数是那条右键链路的唯一后果函数，
## 沿用座位卡时代的两步语义与 _discard_item / c_discard 路径，一行玩法没改。
func _on_discard_clicked(peer: int, slot: int) -> void:
	if peer != my_peer:
		return
	if _discard_pending == slot:
		_clear_discard_pending()
		if board != null:
			board.mark_discard_pending(-1, -1)
		if multiplayer.is_server():
			_discard_item(my_peer, slot)
		else:
			c_discard.rpc(slot)
	else:
		# 除了下标，还要记下这件的 **id**：背包重排后下标会指向另一张牌，只有 id 认得出来
		# 「我 arm 的到底是哪一件」（理由与判据见 _discard_pending_id）。
		# 以及这一把的 **(turn, await) 窗口**：跳过 / 超时结束道具阶段、或回合推进之后，
		# 这把待确认就该失效（理由见 _discard_arm_turn）。
		var items: Array = _state_player(my_peer).get("items", [])
		_discard_pending = slot
		_discard_pending_id = String(items[slot].id) if slot < items.size() else ""
		_discard_arm_turn = int(st.get("turn", -1))
		_discard_arm_await = String(st.get("await", ""))
		if board != null:
			board.mark_discard_pending(my_peer, slot)
	# 可见反馈：待确认那张手牌染红。设 / 清待确认时**不广播**，所以这里立即贴一次，
	# 不然要等下一次状态到达才变色（_refresh_table_props 里另有重放，保证广播后不丢）。
	_sync_hand_discard_pending()

## 解除「待确认丢弃」（槽位、记住的 id 与 arm 时的 (turn, await) 窗口一起清）。**单一入口** ——
## 三处解除点（选中别的牌 / 第二下右键真丢 / 重放前发现这把待确认已失效）都该走它，
## 别单独写 `_discard_pending = -1` 把 id / 窗口漏在原地（漏掉的后果见 _discard_pending_id 与
## _discard_arm_turn 的注释）。调用方各自负责补表现侧同步。
func _clear_discard_pending() -> void:
	_discard_pending = -1
	_discard_pending_id = ""
	_discard_arm_turn = -9999
	_discard_arm_await = ""

## 把「待确认丢弃」的可见反馈贴到桌上手牌：单一来源是 _discard_pending，与 _refresh_table_props
## 里的重放同源。任何写 _discard_pending 的地方都该在写完调它一次。
func _sync_hand_discard_pending() -> void:
	if table3d != null and table3d.table_props != null:
		table3d.table_props.set_hand_discard_pending(_discard_pending)

## 丢弃道具：从背包移除、回道具池
func _discard_item(peer: int, slot: int) -> void:
	var p := _player_by_peer(peer)
	if p.is_empty():
		return
	var items: Array = p.get("items", [])
	if slot < 0 or slot >= items.size():
		return
	var id := String(items[slot].id)
	items.remove_at(slot)
	_log("%s 丢弃了【%s】（回道具池）" % [p.name, id], "#8a90a5")
	_broadcast_state()

@rpc("any_peer", "call_remote", "reliable")
func c_discard(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _player_by_peer(sender).is_empty():
		return
	_discard_item(sender, slot)

func _send_use_item(slot: int, arg: int, arg2: int = -1) -> void:
	_cancel_target()
	_close_cheat_picker()
	if multiplayer.is_server():
		_use_item(my_peer, slot, arg, arg2)
	else:
		c_use_item.rpc(slot, arg, arg2)

func _open_cheat_picker(slot: int) -> void:
	cheat_slot = slot
	cheat_picker.visible = true

func _close_cheat_picker() -> void:
	cheat_picker.visible = false

# ---------------- 指向性道具：点棋盘选目标（选玩家 / 选地块 / 两段式） ----------------

## 通用「选玩家」道具的目标列表（所有其他存活玩家；读已同步的 st，客户端也准）
func _item_targets(exclude_peer: int) -> Array:
	var out: Array = []
	for x in st.get("players", []):
		if bool(x.get("alive", true)) and int(x.peer) != exclude_peer:
			out.append(x)
	return out

## 某玩家名下可拆/可降的地皮序号（读已同步的 st.tiles，客户端也准）
func _selectable_props(peer: int) -> Array:
	var out: Array = []
	var tiles: Array = st.get("tiles", [])
	for i in tiles.size():
		if int(tiles[i].get("owner", GameData.NO_OWNER)) == peer \
				and String(GameData.TILES[i].get("type", "")) == "property" \
				and not bool(tiles[i].get("soil", false)):
			out.append(i)
	return out

## 把「此刻可被选中的玩家」高亮**一次推给两处**：画布（`board.set_select_peers` —— 座位卡上的
## 金框，座位卡随批次 5 Task 2 退场后它空转、接口保留）与**桌上的立牌**
##（`table_props.set_standee_highlight`，批次 5 Task 3 补回的可见反馈；立牌亮着 = 能点）。
##
## **判据只有一份**：可选玩家由调用方（`_begin_peer_target`）算出，本函数只做转发 ——
## 于是"哪几块牌亮着"与"点谁真的有反应"（`_on_seat_clicked` 的第一行）永远同源。
## 传空数组 = 全部熄灭；换阶段（peer → tile）与取消都走它。
func _push_peer_highlight(peers: Array) -> void:
	if board != null:
		board.set_select_peers(peers)
	if table3d != null and table3d.table_props != null:
		table3d.table_props.set_standee_highlight(peers)

## 进入「选玩家」阶段。only_with_items=交换生（目标须持有道具）；then_prop=两段式（目标须有地）
func _begin_peer_target(slot: int, only_with_items: bool, then_prop: bool) -> void:
	var peers: Array = []
	for t in _item_targets(my_peer):
		if only_with_items and (t.get("items", []) as Array).is_empty():
			continue
		if then_prop and _selectable_props(int(t.peer)).is_empty():
			continue
		peers.append(int(t.peer))
	if peers.is_empty():
		_log("没有可选目标（退体力/冷却）", "#8a90a5")
		return
	_tgt_slot = slot
	_tgt_stage = "peer"
	_tgt_peer = -1
	_tgt_tiles = []
	_show_target_hint("点棋盘上的玩家卡选择目标" + ("（Esc/右键取消）" if not then_prop else "（再点他的一块地）"))
	_push_peer_highlight(peers)

## 进入「选地块」阶段（快递直达：任意格）
func _begin_tile_target(slot: int, idxs) -> void:
	var arr: Array = []
	for i in idxs:
		arr.append(int(i))
	if arr.is_empty():
		return
	_tgt_slot = slot
	_tgt_stage = "tile"
	_tgt_peer = -1
	_tgt_tiles = arr
	_show_target_hint("点地图选择目标格（Esc/右键取消）")
	# 直接进选格态（快递直达）：立牌上那份"可选玩家"高亮一并熄灭（同 board 的 set_select_tiles）
	_push_peer_highlight([])
	if board != null:
		board.set_select_tiles(arr)

## 选玩家完成（桌上**立牌**点击 —— 座位卡已随批次 5 Task 2 退场，立牌是这条链路唯一的来源）
func _on_seat_clicked(peer: int) -> void:
	if _tgt_stage == "peer" and peer != my_peer:
		var then := String(ItemData.def(_target_item_id()).get("then", ""))
		if then == "own_prop":
			# 两段式：进入选地块，只高亮该玩家名下地皮
			var props := _selectable_props(peer)
			if props.is_empty():
				_log("该玩家名下没有可指定的地皮", "#8a90a5")
				return
			_tgt_peer = peer
			_tgt_stage = "tile"
			_tgt_tiles = props
			_show_target_hint("点选 %s 名下的一块地（Esc/右键取消）" % _name_by_peer(peer))
			# 从"选玩家"走进"选地块"：立牌那份可选玩家高亮随之熄灭（同 board 的 set_select_tiles）
			_push_peer_highlight([])
			if board != null:
				board.set_select_tiles(props)
			return
		_log("选定目标：%s" % _name_by_peer(peer), "#f0c064")
		_send_use_item(_tgt_slot, peer)
		return

## 选地块完成（棋盘格子点击）
func _finish_tile_target(idx: int) -> void:
	var slot := _tgt_slot
	var peer := _tgt_peer
	_log("选定目标格 #%d" % idx, "#f0c064")
	_send_use_item(slot, peer if peer >= 0 else idx, idx if peer >= 0 else -1)

func _target_item_id() -> String:
	var p := _state_player(my_peer)
	var items: Array = p.get("items", [])
	if _tgt_slot < 0 or _tgt_slot >= items.size():
		return ""
	return String(items[_tgt_slot].id)

func _show_target_hint(text: String) -> void:
	if target_hint == null:
		return
	target_hint.visible = true
	if target_hint_l != null:
		target_hint_l.text = text

func _cancel_target() -> void:
	# 选中态与「选目标态」是两件事：点手中的牌只**选中**，再点「使用道具」才可能进选目标态。
	# 取消（Esc / 右键 / 出牌前收尾）要把两者一起收回 —— 只清 _tgt_stage 的话，
	# 桌上一张牌会永远抬着、牌垫上留一块绿光。
	_clear_item_selection()
	if _tgt_stage == "":
		return
	_tgt_slot = -1
	_tgt_stage = ""
	_tgt_peer = -1
	_tgt_tiles = []
	if target_hint != null:
		target_hint.visible = false
	# 立牌上的可选玩家高亮随选目标态一起熄灭（与 board.clear_select 同一处收口）
	_push_peer_highlight([])
	if board != null:
		board.clear_select()

# ================= 选项菜单 / 房主暂停 / 设置 =================

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

## 飞钞：金额变动时账单在棋子与**那个人的立牌**之间飞（Monopoly GO 式收支反馈）。
##
## 座位卡已随批次 5 Task 2 退场，落点（原来传进来的金额 Label）换成桌上立牌的牌心
## —— 立牌就是今天的"座位卡"，上面也写着身家。立牌还没建出来时退回棋子那一点，
## 只影响飞钞的终点、不改变"金额变了才飞"的判据。
func _spawn_money_fly(peer: int, diff: int) -> void:
	var good := diff > 0
	var token_at := _board_to_screen(board.token_screen_pos(peer)) + Vector2(0, -18)
	var card_at := token_at
	if table3d != null and table3d.table_props != null:
		var sp = table3d.table_props.standee_screen_center(peer)
		if sp != null:
			card_at = sp as Vector2
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
	_place_info_panel()   # 格详情卡要跟着格子走（镜头会平移/缩放/旋转）
	# 屏幕底部原来还有一条固定操作坞（牌垫阶段条 + 操作条 + 底板）。批次 3 Task 6 把它
	# 整条拆了：掷轮改点桌面转盘、出牌改点手中牌（选中后点牌垫「使用道具」确认）、
	# 现金与体力在桌上。**注意这里不能留 `if <坞成员> == null: return` 之类的提前返回** ——
	# 那会把下面小卖部 / 黑市 / 操作倒计时 / 开发者面板整段静默打死（本任务真踩过这个坑，
	# hud_test 有对应的守卫断言）。
	var phase := String(st.get("phase", ""))
	# 交易面板独立于视角：保证行动者一定能操作（相机可能停在棋子上而非自家座位）
	var shop_mine: bool = phase == "playing" and int(st.get("shop_peer", 0)) == my_peer \
		and int(st.get("shop_open", -1)) >= 0
	shop_layer.visible = shop_mine
	if shop_mine:
		# 置顶（照 _menu_show）：build_play_ui 里后建的屏幕层控件（暂停按钮 / 格详情卡 /
		# 战报开关与战报栏）默认按树序画在压暗底之上——亮着、看着能点，点击却被
		# dim 的 MOUSE_FILTER_STOP 吃掉。已置顶时不重复搬。
		if shop_layer.get_index() != get_child_count() - 1:
			move_child(shop_layer, -1)
		_refresh_shop_ui()
	var black_mine: bool = phase == "playing" and int(st.get("black_peer", 0)) == my_peer
	black_bar.visible = black_mine
	if black_mine:
		_place_overlay_bar(black_bar)
		_refresh_black_ui()
	else:
		black_picker.visible = false
		_black_sig = ""
	_refresh_op_timer(_delta)
	if dev.enabled:
		dev.refresh_panel()

## 操作倒计时（D 方案）：**只挂当前行动者那一块**（留痕 §四 的原设计：嵌在行动者的
## 座位卡里 —— 批次 5 Task 2 起载体换成桌上的 3D 立牌，这条"只挂行动者"的语义一字未改）。
## 广播一秒一条，本机逐帧扣 delta 插值：暂停时 _process 不跑、计时随房主窗口一起冻结，
## Engine.time_scale（仅 autotest 会改）也天然对齐——这正是持续动画走 _process 相位的约定。
func _refresh_op_timer(delta: float) -> void:
	var show := _op_kind != ""
	if show:
		_op_left = maxf(_op_left - delta, 0.0)
	if show or _op_shown:
		var kind_text := String(OP_KIND_LABELS.get(_op_kind, _op_kind)) if show else ""
		# 立牌上只有**当前行动者**那一块露倒计时，所以窗口收起时传 NO_PEER = 四块一起收起。
		if table3d != null and table3d.table_props != null:
			table3d.table_props.set_standee_timer(_op_owner if show else GameData.NO_PEER,
				kind_text, _op_left, _op_total)
		# 小卖部全屏界面盖住整块棋盘，立牌上的倒计时在里面看不见：同一份数据再推一份到面板
		if shop_layer != null and shop_layer.visible:
			_refresh_shop_timer(kind_text)
	_op_shown = show
	# 四角条那一份**每帧都贴**（不受上面那道 `show or _op_shown` 早退限制）：角位与行动者
	# 会随状态广播重排（`_refresh_corner_bars` 改 bar.peer），只贴"变化的那一次"会漏。
	_refresh_corner_timer()

## 四角条上的操作倒计时（批次 5 修复波 A）：把**当前行动者**那份倒计时镜像到 TA 的四角条上。
##
## **为什么必须有这一条**：立牌上那份只挂在行动者那一块，而**自己**的立牌在 3D 端是藏起来的
##（`table_props.STANDEE_SELF_HIDE_T`）⇒ 自己的回合在 3D 端看不到还剩几秒（批次 4 时它在
## 座位卡上，3D 端看得见）。四角条在 3D / 2D 两端都常驻，是唯一合适的落点。
##
## **不另立计时**：数据就是 `_op_*` 这同一份（广播重置 + 本机逐帧扣 delta 的那个插值）。
## 暂停时 `_process` 不跑 ⇒ 这里也不会被调用 ⇒ 与房主窗口一起冻结，**同一条暂停语义**。
##
## 形态：环节名 + 细进度条 + 剩余秒数，**只出现在 `_op_owner` 那一条上**（其余三条内容收起）；
## 没有操作窗口时四条的倒计时内容一律收起。`_op_total <= 0`（黑市那种不限时）= 仍写环节名，
## 但**不写秒数、不画进度条** —— 与立牌、小卖部面板那两份逐条对齐（三处同一口径）。
func _refresh_corner_timer() -> void:
	if corner_bars.is_empty():
		return
	var show := _op_kind != ""
	var timed := show and _op_total > 0.0
	var kind_text := String(OP_KIND_LABELS.get(_op_kind, _op_kind)) if show else ""
	var warn: bool = timed and _op_left <= 5.0
	for b in corner_bars:
		var bar: Dictionary = b
		var on: bool = show and int(bar.peer) == _op_owner
		# 只切**行内内容**的显隐：行本身常驻占位（`table_hud.CORNER_TIMER_ROW_H`），
		# 否则行动者换人时那一条会一开一合，四个角的边线就看齐不了了。
		var kind_l: Label = bar.timer_kind
		var left_l: Label = bar.timer_left
		var track: ColorRect = bar.timer_track
		kind_l.visible = on
		left_l.visible = on and timed
		track.visible = on and timed
		if not on:
			continue
		if kind_l.text != kind_text:
			kind_l.text = kind_text
		kind_l.add_theme_color_override("font_color", UIKit.DANGER if warn else UIKit.ACCENT)
		if not timed:
			continue
		var txt := "%d 秒" % ceili(maxf(_op_left, 0.0))
		if left_l.text != txt:
			left_l.text = txt
		left_l.add_theme_color_override("font_color", UIKit.DANGER if warn else UIKit.TEXT)
		# 进度条：左端固定、长度按剩余比例缩（底轨常驻、填充显式设宽度 —— 同小卖部那条）
		var fill: ColorRect = bar.timer_fill
		fill.size.x = maxf(track.size.x, 1.0) * clampf(_op_left / _op_total, 0.0, 1.0)

## 小卖部面板底部的倒计时：呈现口径与立牌上那条（原座位卡那条）逐条对齐。
## 数据全部来自 _op_*（由 s_op_timer 广播 + 本机逐帧扣 delta），不另起一套计时，
## 否则会与房主窗口漂移。kind_text="" 表示窗口已关，整行收起。
func _refresh_shop_timer(kind_text: String) -> void:
	if shop_timer_row == null or not is_instance_valid(shop_timer_row):
		return
	shop_timer_row.visible = kind_text != ""
	if kind_text == "":
		return
	if shop_timer_kind.text != kind_text:
		shop_timer_kind.text = kind_text
	if _op_total > 0.0:
		shop_timer_track.visible = true
		shop_timer_fill.size.x = shop_timer_track.size.x * clampf(_op_left / _op_total, 0.0, 1.0)
		var warn := _op_left <= 5.0
		shop_timer_fill.color = UIKit.DANGER if warn else UIKit.ACCENT
		var txt := "%d 秒" % ceili(_op_left)
		if shop_timer_left.text != txt:
			shop_timer_left.text = txt
			shop_timer_left.add_theme_color_override("font_color", UIKit.DANGER if warn else UIKit.TEXT)
	else:
		shop_timer_track.visible = false
		if shop_timer_left.text != "不限时":
			shop_timer_left.text = "不限时"
			shop_timer_left.add_theme_color_override("font_color", UIKit.TEXT_DIM)

## 屏幕底部「贴底条」可用的横向带（左起 / 右止）。现在只剩黑市操作条在用（底栏已随
## 批次 3 Task 6 拆除）；它只按屏幕居中，一旦左下角展开规则说明面板、或右上角战报栏
## 展开，就会被压住，所以按两侧栏的实际几何夹位。
func _dock_band() -> Vector2:
	var x0 := 14.0
	if rules_panel != null and rules_panel.visible:
		x0 = maxf(x0, rules_panel.offset_right + 10.0)
	# 格详情卡已改成悬浮在格子上方，不再占左下角，所以不需要再为它让位
	var x1 := size.x - 14.0
	if log_panel != null and log_panel.visible:
		# 战报栏挂 TOP_RIGHT 锚点，所以它的左边缘 = 屏宽 + offset_left（不写死宽度）
		x1 = minf(x1, size.x + log_panel.offset_left - 8.0)
	return Vector2(x0, maxf(x1, x0 + 120.0))

## 把贴底条左边缘夹进可用带内（带太窄时以左边缘为准，宁可溢出也不推到屏幕外）
func _clamp_dock_x(want: float, width: float, band: Vector2) -> float:
	return clampf(want, band.x, maxf(band.x, band.y - width))

## 交易面板贴底居中：按自身高度上移，保证整块（含刷新/离开）都在屏内；
## 横向同样夹进可用带，免得展开规则说明后被压住
func _place_overlay_bar(c: Control) -> void:
	var vp := size
	c.position = Vector2(_clamp_dock_x(vp.x * 0.5 - c.size.x * 0.5, c.size.x, _dock_band()),
		maxf(vp.y - c.size.y - 16.0, 8.0))

## 小卖部全屏界面刷新：按货架逐格换卡面 / 标价 / 可买判定（缓存签名，避免每帧重建）。
func _refresh_shop_ui() -> void:
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
	for i in shop_cards.size():
		var id := String(slots[i]) if i < slots.size() else ""
		var e: Dictionary = shop_cards[i]
		var holder: CenterContainer = e.holder
		var price_l: Label = e.price_l
		var b: Button = shop_btns[i]
		if String(holder.get_meta("item_id", "")) != id:
			holder.set_meta("item_id", id)
			for c in holder.get_children():
				c.queue_free()
			if id != "":
				holder.add_child(ItemCard.make(id, ItemCard.SIZE_MEDIUM, {}))
		if id == "":
			price_l.text = "空货位"
			b.visible = false
			continue
		var price := ItemData.price(String(ItemData.def(id).quality))
		price_l.text = GameData.fmt_money(price)
		b.visible = true
		b.disabled = bag.size() >= 5 or (not free_buy and money < price)
	if shop_tile_l != null:
		shop_tile_l.text = "第 %d 号店 · 刷新费随全场次数递增" % open
	if shop_money_l != null:
		# 现金变了签名就变（sig 里含 money），所以在这里刷就够了
		shop_money_l.text = "现金 %s" % GameData.fmt_money(money)
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
	var timed_out := false
	while running and alive.call():
		var rev := _timeout_rev
		var sec := GameSettings.turn_seconds(_settings.timeout_tier, kind)
		if on_arm.is_valid():
			on_arm.call(sec)
		_op_timer_send(kind, sec, sec)   # 窗口（重）开始：全员倒计时条从满条起跳
		# 分片等待（_WINDOW_TICK 一探，开销可忽略）：环节结束、挡位变化、到点超时都能及时响应。
		# 不能整段 `await _wait(sec)`——那样挡位中途变化要等满一整段才按新值重计时。
		# 到期判定锚定窗口起点的绝对时刻，不累加每跳的名义时长：SceneTreeTimer 要下一帧才触发，
		# 累加会每跳少算 0~1 帧，长窗口（掷轮 140 跳）越跑越晚。
		# 时间基准乘 Engine.time_scale：_wait 走 SceneTreeTimer，吃的本就是缩放后的时间
		# （只有 autotest 会改它），不乘的话自动回归里的等待会被放大到不可接受。
		# sec <= 0（不限时）→ 没有到期时刻，只等前两种。
		var t0 := Time.get_ticks_msec()
		var last_sent := int(ceilf(sec))
		while running and alive.call() and _timeout_rev == rev:
			var elapsed := float(Time.get_ticks_msec() - t0) / 1000.0 * Engine.time_scale
			if sec > 0.0 and elapsed >= sec:
				timed_out = true
				break
			# 剩余整秒变化才广播：一秒一条，不按 0.1s 的探测分片刷屏
			if sec > 0.0 and int(ceilf(sec - elapsed)) != last_sent:
				last_sent = int(ceilf(sec - elapsed))
				_op_timer_send(kind, sec - elapsed, sec)
			await _wait(_WINDOW_TICK)
		if timed_out:
			break
	_op_timer_send("", 0.0, 0.0)   # 窗口关闭（结束或超时）都收条；紧接的新窗口会立刻重发
	return timed_out

