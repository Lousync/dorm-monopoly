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
	"card": "确认",   # 抽卡演出等「确定」（批次 12 C2 / ⑧⑪）
}

# ---------------- 道具系统（host 状态，详见 doc/game-design/道具系统.md） ----------------
var shops := {}            # tile_idx -> {slots: [id×3]}，每家小卖部独立货架
var items_consumed := {}   # 焚毁标记：一次性道具用后不回池（id -> true）
var refresh_count := 0     # 小卖部全局刷新次数（任何人刷新都让全场变贵，整局不重置）
var _extra_move := false   # 特浓咖啡：本次落地后再行动一次（_play_turn 每轮重置后消费）
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
## 「XX 正在挑选」说明条（批次 12 C2）：小卖部全员可见后，非本人看到的是只读货架，
## 没有这条旁观者只会看到一堆点不动的按钮。见 `_refresh_shop_ui`。
var shop_watch_l: Label
var shop_timer_row: HBoxContainer # 面板里的倒计时行：与身家条 / 名册行倒计时同一份 _op_* 数据（独立控件，不依赖座位卡）
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

# ---------------- 畸变（host 状态，规则与两道闸门见 doc/game-design/畸变.md §二） ----------------
var _ab_active: Array = []   # 生效中的持续型：[{id, left}]，left = 剩余玩家回合数
var _ab_queue: Array = []    # 条件型顺延队列（id × ≤2，超出丢弃）
var _ab_fired := {}          # 条件型一次性标记（id -> true，触发判定时即写）
var _ab_no_roll := false     # 调休：本回合不能掷轮（一次性，进掷轮循环即消费）
## 调休：该 peer 自己的下一回合连掷两次。**哨兵必须是 `NO_PEER`、不能是 −1** ——
## 机器人 peer 从 **−1** 起编号（`net._free_bot_id`），拿 −1 当"没人待补班"会让**第一台机器人
## 每回合**白拿一次双掷（且与畸变开关无关、不扣 `_ab_no_roll` ⇒ 纯加成）。
## 这是批次 13 ④ 修掉的真 bug；`AGENTS.md` §四「哨兵别用 −1」早有此约定（同类先例：
## `_set_ring(-1)`、`_shop_peer != 0`）。**判据**：合法调休会同时打 `【畸变】调休 —— …`
## 与 `【调休】补班时间…` 两条日志，哨兵撞车只有后者。
var _ab_extra_peer: int = GameData.NO_PEER
var ab_label: PanelContainer  # 「生效中」横幅（hud 层顶部居中，快照驱动，见 table_hud 里那段）
var ab_label_l: Label         # 生效中横幅的内层文本
var ab_wrap: Control          # 横幅的居中容器（TOP_WIDE + CenterContainer，见 table_hud 里那段）
var ab_row: HBoxContainer     # 对局内设置面板：畸变频率 chips（房主）
var ab_dur_row: HBoxContainer # 对局内设置面板：持续回合 chips（房主）
var ab_cond_row: HBoxContainer  # 对局内设置面板：条件触发 chips（房主）
var ab_title: Label           # 对局内设置面板：畸变小节标题（与只读行互斥显隐）
var ab_readonly: Label        # 对局内设置面板：畸变只读文本（客户端）

# ---------------- 格详情卡 / 规则说明（**右上角**，见 rules_panel.gd） ----------------
var info_panel: PanelContainer
var _info_tile := -1              # 格详情卡当前挂在哪一格（-1 = 没显示）
var info_title: Label
var info_body: Label
var info_sb: StyleBoxFlat
# ---- 决策区（批次 12 C1）：格详情卡里的「买下它！/ 装修！ + 算了 + 倒计时条」 ----
# 由 `TableHud.build_play_ui` 建；内容与显隐由 `_show_prompt` / `_refresh_decision_area` 管。
var decision_area: VBoxContainer
var decision_title: Label
var decision_text: Label
var decision_bar: ProgressBar
var decision_no: Button
var decision_ok: Button
var rules_btn: Button            # 「📖 规则说明」**开关**（批次 12 D2 起在右上角、与「战报」并列；批次 13 辛 ① 起恒可见、再点收起）
var rules_panel: PanelContainer  # 分页规则面板（批次 13 ① 起同在右上角、**自按钮下方展开**，不再"原位向上"）
var rules_body: RichTextLabel
var rules_tabs := {}             # 分页 key -> 按钮
var rules_open := false
var rules_tab := ""
## **「我」那条身家条**（屏幕左下角）。批次 5 起是"四条一起建"，**批次 12 D 起只剩这一条**：
## 他人的信息改由下面的名册条承担（`roster_strip` / `roster_strip_rows`，**批次 13 ② 起在左上角**），选目标高亮与
## 行动者倒计时也跟着搬了过去 —— 但**判据一字未改**（`_hl_peers` / `_op_owner`），
## 只是"贴到哪一块控件上"多了一处落点（`_hl_bars()` 把两者合成同一条循环）。
## 它取代的是更早的右侧名册栏（`roster_box` / `roster_rows` 已删，理由见 table_hud.gd 里那段）。
## **注意别与这里的 `roster_strip_rows` 混为一谈**：那个是批次 12 D 新加的**名册条**的格
##（批次 13 ② 起在**左上角**「暂停」旁），
## 与已删除的右侧名册栏不是同一样东西（`regression_test` 的反向契约仍钉着旧的 `roster_rows` 必须不存在）。
var corner_bars: Array = []
## 名册条（批次 12 D1 建；**批次 13 ② 从右上角搬到左上角「暂停」旁；批次 13 辛 ③ 改横排 + 做小**）：
## 「他人」一格一位（名次徽章 + 棋子色小片 + 昵称 + 那一格的倒计时）。
## 由 `TableHud.build_play_ui` 建、`_refresh_roster` 刷；**常驻**（不在可折叠的战报栏里）。
## 每一格的字典形态与 `corner_bars` 里那条**同形**（`table_hud._make_roster_row`），
## 于是高亮 / 倒计时两处刷新函数可以直接把它们并进同一条循环（见 `_hl_bars`）。
##
## **类型必须是 `HBoxContainer`**（批次 13 辛 ③ 用户拍板要横排、并从竖向每格 64 收到横排每格 42 高）：
## 条仍然只占**左上角**那一片（`ROSTER_X=104` 起、与「暂停」同一条 y 带），横排之后**宽度**才是
## 要盯的量 —— 由 `_refresh_roster` 里那道**屏幕中线软夹**兜住（详细理由见 `table_hud.build_play_ui`
## 那段"横排的由来"）。
## **容器种类写错会当场炸**：批次 13 ② 把这里写成 `HBoxContainer` 而 `build_play_ui` 赋的是
## `VBoxContainer`，赋值那行直接 `Invalid assignment …` **把整个界面构建打断**
##（后面 `RulesPanel.build` / 移动弹窗全没跑，测试里表现为"条全空 + 卡住"，排错花掉 9 分钟）——
## 改容器种类时**这一处必须与 `table_hud` 一起改**，别只改一边。
var roster_strip: HBoxContainer
var roster_strip_rows: Array = []
## 最近一次广播算出的身家表（peer -> `_refresh_players` 里那份 entry，带 rank / worth / money）。
## **名次徽章的唯一来源**：原先 `_rank_of` 是回头去 `corner_bars` 里翻，四角条只剩一条之后
## 那条路只查得到自己 ⇒ 弹窗里别人的徽章会集体消失，所以改成留一份表。
var _standing_by_peer := {}
## 右下角动作按钮（批次 7）：轮到我掷轮 → 「转动转盘」，掷完进道具阶段 → 「结束回合」，
## 其余时候整枚隐藏。由 `TableHud.build_play_ui` 建，状态见 `_refresh_action_button`。
var action_btn: Button
## 屏幕层容器（批次 11 Task 3）：`TableHud.build_play_ui` 建的 `hud`（不随摄像机旋转的悬浮控件
## 都挂它）。此前它只是那个静态函数里的局部变量 —— 悬停信息条要挂在**屏幕层**上，于是把它记一份
## 到 game 上（`hud_test` 靠它断言"条不在画布里"）。不改任何行为。
var hud_layer: Control
## 悬停棋子的信息条（批次 11 Task 3）：屏幕层 Control，由 `TableHud.build_play_ui` 建。
## 载体从画布搬到屏幕层的原因与 z 档见那里；内容 / 数据源（`board._peers_info`）与显隐由
## `_on_table_hover` / `_set_token_hover` / `_place_token_tip` 负责，`_process` 每帧重摆一次。
var token_tip: Control
var _tip_name: Label                # 条里那行昵称（颜色 = 该玩家的棋子色）
var _tip_sub: Label                 # 第二行「身家 … · 第 N 名（· 已出局）」
## 当前悬停到谁（哨兵是 `GameData.NO_PEER`，**不是 -1** —— 机器人 peer 从 -1 起编号）。
var _tip_peer := GameData.NO_PEER
## 抽卡演出的屏幕层大字卡（批次 8）：由 `TableHud.build_play_ui` 建、`s_card` 调它。
## 演出不再动 2D 相机（旧 `board.play_deck_card` 那一路已删），见 scripts/deck_reveal.gd。
var deck_reveal: DeckReveal
## 玩家道具弹窗（批次 9，见 scripts/player_popup.gd）：点身家条 / 名册行打开（`_on_corner_bar_clicked`），
## 装立牌退场后没有落点的**公开背包 + 能量**。由 `TableHud.build_play_ui` 建，**挂在 `game` 上并
## 排在所有建期屏幕层控件之后**（模态靠树序，见 `build_play_ui` 末尾那段）；数据由
## `_open_player_popup` **一处**组装（全取已同步的 st，客户端也准）。
var player_popup: PlayerPopup
## 「此刻可被选中的玩家」的**单一来源**（批次 9）：由 `_push_peer_highlight` 写、条与名册行高亮读
##（`_refresh_corner_highlight`，实现归 Task 3）。放在 game 上而不是条里，是因为广播会重排顺序。
var _hl_peers: Array = []
var _corner_sig := ""              # 身家条 + 名册条的刷新签名（状态没变就不重写）
var _log_flash_tw: Tween          # 新战报时头部闪金（沉浸感）
var _op_kind := ""                # 当前操作窗口 kind（"" = 无窗口，簇收起）
var _op_left := 0.0               # 本机显示用剩余秒数：广播到达时重置，_process 逐帧扣 delta
                                  # （暂停时 _process 不跑 → 计时与房主的窗口一起冻结）
var _op_total := 0.0              # 窗口总时长；<=0 = 不限时（不显示进度条）
var _op_owner := -1               # 窗口归属玩家（倒计时显示在他那条身家条 / 名册行上）
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
## 本帧待播的飞钞（批次 13 ⑥）：`_refresh_players` 的钱循环只**记**差分，等
## `_refresh_corner_bars` 把 peer→条/行的绑定刷成当帧的、再统一播（否则终点算早一帧）。
## 每帧在 `_refresh_players` 开头清空 —— 别让它跨帧累积。
var _money_flies: Array = []
## 测试观测点（批次 13 ⑥）：peer -> **当帧**飞钞终点（`_spawn_money_fly` 里写）。
## 用途：钉住"终点用的是 `_refresh_corner_bars` 之后的绑定"，不是上一次广播的旧绑定。
var _money_fly_goal := {}
var _chat_shown := 0
var _prompt_tw: Tween
var _prompt_bar: ProgressBar
var _prompt_token := -1
## 待决的那个决定挂在**哪一格**（批次 12 C1）：房主在 `_ask` 里按 `idx` 填；
## 客户端没有 `_awaiting_prompt` 这类房主私有变量，由 `_pending_tile_for_me` 从快照推
##（await=prompt 且 await_peer 是我 ⇒ 待决格 = **我棋子所在那一格**，因为 `_resolve_buy` /
## `_resolve_upgrade` 都是 `_resolve_tile` 以 `p.pos` 为 idx 调的、`re` 那次原地结算同用一个 pos）。
## ⇒ `s_prompt` 的签名不必带格号。
var _prompt_tile := -1
## 卡面确认（批次 12 C2 / ⑧⑪）：正在等谁点「确定」（0 = 没有）；他确认后 `_card_ack` 置真。
var _awaiting_card := 0
var _card_ack := false

# ---------------- 自动化测试 ----------------
var at_mode := ""
var at_rounds := 3
var at_tier := ""    # --tier= 指定的挡位（客户端 autotest 据此断言收到了正确的快照）
var _at_roll_epoch := -1
var _at_card_done := false     # 自动回归：本张抽卡演出的「确定」已经代点过（按钮收起时复位）
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
	_refresh_ab_settings_ui()

	# 客户端这里不再写任何东西：原来那句「等待房主同步状态…」写在底栏状态条上，
	# 底栏已随批次 3 Task 6 取消（等房主的首份 s_state 广播即可，见 _broadcast_state）。
	if multiplayer.is_server():
		_host_setup()

	board.item_slot_clicked.connect(_on_item_slot_clicked)
	board.item_discard_clicked.connect(_on_discard_clicked)
	board.cancel_clicked.connect(_cancel_target)
	table3d.on_table_click = _on_table_click   # 桌面实体（转盘 / 手牌）先于桌垫内容消费点击
	table3d.on_table_hover = _on_table_hover   # 悬停桌面实体（棋子）⇒ 屏幕层信息条的显隐
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
		if a3.begins_with("--fps="):
			dev.fps_probe = float(a3.substr(6))   # 帧率实测（批次 6 Task 3，见 dev_tools.fps_probe_run）
		elif a3 == "--fps-houses=1":
			# 帧率探针的"满盘装修"档（批次 11 T4）：采样前把地产格全灌满级装修再采，量最坏档。
			# 不带就是关（默认，批次 6/10 的旧口径一字不变）。见 `dev_tools.fps_houses`。
			dev.fps_houses = true
	if dev.fps_probe > 0.0:
		dev.fps_probe_run()
	for a4 in OS.get_cmdline_user_args():
		if a4 == "--card-gallery":
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
	# 右上角「📖 规则说明」（批次 12 D2 起的落点）：一枚开关按钮 + 其下方展开的分页规则面板
	#（文案见 RulesText）
	RulesPanel.build(self)
	# 玩家道具弹窗（批次 9）**排到最末**：GUI 拾取按**树序**（不看 z_index，见
	# `table_hud.build_play_ui` 末尾那段说明），而规则说明的按钮 / 面板是 `build_play_ui`
	# **之后**才挂的 —— 只在 `build_play_ui` 末尾 append 的话，它们仍会抢先拾取、点穿压暗底。
	# 排到最后 ⇒ 弹窗的压暗底挡得住所有建期控件；**运行时懒建的**结算(50) / 弹问(60) 层、
	# 以及显示时 `move_child(-1)` 的小卖部(70) / 赌场 / 暂停菜单(80) 天然更晚，仍压在它之上。
	move_child(player_popup, -1)
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
	_log("转盘决定步数（0~12）：转到 12 满值再动一次，转到 0 就地再结算脚下格子；连续三次 10+ 会被查寝抓走哦")
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
	_aberration_window(p)   # 畸变窗口：回合开始结算后、掷轮前（畸变.md §二/§五）
	while running:
		if _ab_no_roll:   # 调休：本回合不能转盘（不移动、不结算落点，道具阶段照常）
			_ab_no_roll = false
			_log("%s 碰上【调休】，本回合原地放假，转盘停转" % p.name, "#f0a0c0")
			break
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
		_extra_move = false  # 特浓咖啡标记每轮重算（上轮 12 满值续动不会残留）

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
		var ab_cut := _ab_move_cut(p)
		if ab_cut > 0:
			step = maxi(0, step - ab_cut)
			_log("【隔离】%s 的移动点数 −%d" % [p.name, ab_cut], "#c9a6ff")
		var path := GameData.compute_path(int(p.pos), step)
		if path.is_empty():
			_log("%s 转了个 0，原地待命一回合" % p.name, "#8a90a5")
			# 0 点再结算：脚下格子里有可结算的内容就再来一次（角格除外，不重复领工资）
			if not GameData.is_corner(int(p.pos)):
				await _resolve_tile(p, true)
				_broadcast_state()
				if not running or not bool(p.alive):
					return
				if _extra_move:
					continue  # 脚下正好是特浓咖啡：待命完还能再动
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
		if _extra_move:
			await _wait(0.5)
			continue  # 特浓咖啡：本回合再行动一次
		if bool(p.get("ab_extra_roll", false)):
			p.ab_extra_roll = false
			_log("【调休】第二趟：%s 再转一次！" % p.name, "#f0a0c0")
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

# ================= 房主：畸变 =================
# 规则唯一来源：doc/game-design/畸变.md。两道闸门（2026-10-04 定稿）：
# 闸门一 每回合最多触发 1 条新畸变；闸门二 全场同时最多 1 条持续型「生效中」，
# 生效期间窗口跳过——随机候选丢弃、条件候选照常顺延。
# 挑选：条件 > 随机（顺延补发的条件再插队一级），同级图鉴序 + 掷骰。

## 畸变窗口：插在回合开始结算之后、掷轮之前（畸变.md §五）。同步函数，无 await。
func _aberration_window(p: Dictionary) -> void:
	p.ab_extra_roll = false   # 上回合残留的调休补班标记清掉（查寝等提前退回合的场合）
	_ab_tick()
	if _ab_extra_peer != GameData.NO_PEER and _ab_extra_peer == int(p.peer):
		if _is_sleeping(p):
			pass   # 休眠回合用不了调休，留到下一个自己的回合
		else:
			_ab_extra_peer = GameData.NO_PEER
			p.ab_extra_roll = true
			_log("【调休】补班时间：%s 本回合可以连转两次！" % p.name, "#f0a0c0")
	var pick := _ab_pick(_ab_candidates(p))
	if pick != "":
		_ab_trigger(p, pick)
	_check_end()
	_broadcast_state()

## 持续型计时：每个玩家回合开始 left−1，归零移除并广播结束
func _ab_tick() -> void:
	if _ab_active.is_empty():
		return
	var expired: Array = []
	for a in _ab_active:
		a.left = int(a.left) - 1
		if int(a.left) <= 0:
			expired.append(String(a.id))
	_ab_active = _ab_active.filter(func(a: Dictionary) -> bool: return int(a.left) > 0)
	for id in expired:
		_log("畸变【%s】退去了，一切恢复常轨" % id, "#8a90a5")
		s_aberr.rpc(id, "end", 0)

## 收集本回合候选：顺延队首（prio −1 插队）+ 新达成条件（prio 0）+ 随机掷中（prio 1）
func _ab_candidates(p: Dictionary) -> Array:
	var out: Array = []
	if not _settings.ab_cond:
		_ab_queue.clear()   # 关掉条件触发 = 顺延队列一并冻结
	else:
		for id in _ab_queue.duplicate():
			out.append({"id": id, "prio": -1})
		for id in AberrationData.ABERRATIONS:
			var d: Dictionary = AberrationData.def(id)
			if String(d.get("trigger", "")) != "条件" or not bool(d.get("implemented", false)):
				continue
			if _ab_fired.has(id) or _ab_queue.has(id):
				continue
			if _ab_cond_met(id):
				_ab_fired[id] = true
				out.append({"id": id, "prio": 0})
	if String(_settings.ab_freq) == "关":
		return out
	if randf() >= float(AberrationData.FREQ_P.get(_settings.ab_freq, 0.06)):
		return out
	var pool: Array = []
	for id in AberrationData.ABERRATIONS:
		var d: Dictionary = AberrationData.def(id)
		if String(d.get("trigger", "")) == "随机" and bool(d.get("implemented", false)):
			pool.append(id)
	if not pool.is_empty():
		out.append({"id": pool[randi_range(0, pool.size() - 1)], "prio": 1})
	return out

## 条件型是否在本回合窗口达成（一次性标记由候选收集方写）
func _ab_cond_met(id: String) -> bool:
	var cond: Dictionary = AberrationData.def(id).get("cond", {})
	if id == "房价崩盘":
		for o in hp:
			if bool(o.alive) and (_own_props(int(o.peer)) as Array).size() >= int(cond.get("props", 5)):
				return true
		return false
	if id == "枪打出头鸟":
		for o in hp:
			if bool(o.alive) and int(o.get("money", 0)) > int(cond.get("cash", 30000)):
				return true
		return false
	return false

## 挑选唯一触发者；被闸门 / 优先级刷掉的条件型进顺延队列。返回 id 或 ""。
func _ab_pick(cands: Array) -> String:
	if cands.is_empty():
		return ""
	var best := 99
	for c in cands:
		best = mini(best, int(c.get("prio", 1)))
	var top: Array = cands.filter(func(c: Dictionary) -> bool: return int(c.get("prio", 1)) == best)
	var persisting := not _ab_active.is_empty()
	if best <= 0:   # 条件型（含顺延补发）
		if persisting:   # 闸门二：持续型生效中 → 全部顺延
			for c in top:
				_ab_enqueue(String(c.id))
			return ""
		var chosen := String(top[randi_range(0, top.size() - 1)].id)
		for c in top:   # 闸门一：只发一条，落选的条件型顺延
			if String(c.id) != chosen:
				_ab_enqueue(String(c.id))
		_ab_queue.erase(chosen)
		return chosen
	if persisting:
		return ""   # 随机型撞上闸门二：本轮作废
	return String(top[randi_range(0, top.size() - 1)].id)

## 条件型顺延入队（上限 2，超出丢弃——该条件本局作废）
func _ab_enqueue(id: String) -> void:
	if _ab_queue.has(id) or _ab_queue.size() >= 2:
		return
	_ab_queue.append(id)

## 触发一条畸变：持续型入表 + 当刻一次性部分；非持续型立即结算。
## 公告走 _log（s_log 顶部气泡），debuff 的震屏在 s_aberr 里对所有端生效。
func _ab_trigger(p: Dictionary, id: String) -> void:
	var d: Dictionary = AberrationData.def(id)
	_log("【畸变】%s —— %s" % [id, String(d.get("desc", ""))], "#f0c064")
	if String(d.get("type", "")) == "持续":
		var left := int(d.get("dur", 0))
		if left <= 0:
			left = maxi(1, int(_settings.ab_dur))
		_ab_active.append({"id": id, "left": left})
		s_aberr.rpc(id, "start", left)
		_ab_apply_persistent_start(p, id)
	else:
		s_aberr.rpc(id, "start", 0)
		_ab_apply_instant(p, id)

## 非持续型：触发瞬间结算（debuff 逐玩家独立被香皂/护盾免疫）
func _ab_apply_instant(p: Dictionary, id: String) -> void:
	match id:
		"天降红包":
			for o in hp:
				if bool(o.alive):
					o.money = int(o.money) + 500
		"强制捐款":
			for o in hp:
				if not bool(o.alive):
					continue
				if _immune_debuff(o):
					_log("%s 的【空想者的香皂】挡下了强制捐款" % o.name, "#8fb7f2")
				else:
					_pay(o, 500, {})
		"集体感冒":
			for o in hp:
				if not bool(o.alive):
					continue
				if _immune_debuff(o):
					_log("%s 的【空想者的香皂】挡下了集体感冒" % o.name, "#8fb7f2")
				else:
					o.sleep = maxi(int(o.get("sleep", 0)), 1)
		"金融危机":
			for o in hp:
				if not bool(o.alive):
					continue
				if _immune_debuff(o):
					_log("%s 的【空想者的香皂】挡下了金融危机" % o.name, "#8fb7f2")
					continue
				var rate: float = AberrationData.FIN_RATE_NC
				if not (_own_props(int(o.peer)) as Array).is_empty():
					rate = AberrationData.FIN_RATE_C
				var amt := int(int(o.get("money", 0)) * rate)
				if amt > 0:
					_pay(o, amt, {})
		"枪打出头鸟":
			var cash_need := int(AberrationData.def(id).get("cond", {}).get("cash", 30000))
			var rich: Array = hp.filter(func(o: Dictionary) -> bool:
				return bool(o.alive) and int(o.get("money", 0)) > cash_need)
			if not rich.is_empty():
				var top: int = (rich as Array).map(func(o: Dictionary) -> int: return int(o.money)).max()
				rich = rich.filter(func(o: Dictionary) -> bool: return int(o.money) == top)
				var t: Dictionary = rich[randi_range(0, rich.size() - 1)]   # 并列掷骰（畸变.md §二）
				if _immune_debuff(t):
					_log("%s 的【空想者的香皂】挡下了强制捐款" % t.name, "#8fb7f2")
				else:
					_pay(t, int(int(t.money) * AberrationData.BIRD_RATE), {})
		"拆迁":
			var n := randi_range(1, 2)
			for i in n:
				var all_props: Array = []
				for o in hp:
					if bool(o.alive):
						all_props.append_array(_own_props(int(o.peer)))
				if all_props.is_empty():
					break
				var si: int = all_props[randi_range(0, all_props.size() - 1)]
				var owner := _player_by_peer(int(htiles[si].owner))
				if not owner.is_empty() and _immune_debuff(owner):
					_log("%s 的【空想者的香皂】保住了【%s】" % [owner.name, String(GameData.TILES[si].name)], "#8fb7f2")
					continue   # 该抽作废、不补抽（补抽规则待实现复核）
				htiles[si].owner = GameData.NO_OWNER
				htiles[si].level = 0
				_log("【拆迁】%s 被拆平了，归为无主" % String(GameData.TILES[si].name), "#c9a6ff")
		"调休":
			_ab_no_roll = true
			_ab_extra_peer = int(p.peer)
		_:
			pass

## 持续型入表当刻的一次性部分（其余持续效果由各挂点按 _ab_has 现查）
func _ab_apply_persistent_start(p: Dictionary, id: String) -> void:
	if id == "诚信考试":
		if _immune_debuff(p):
			_log("%s 的【空想者的香皂】让他在诚信考试里照样传小条" % p.name, "#8fb7f2")
		else:
			p.silence = maxi(int(p.get("silence", 0)), 1)   # 本回合道具阶段被禁（dur=1 只盖当前回合）

func _ab_has(id: String) -> bool:
	for a in _ab_active:
		if String(a.id) == id:
			return true
	return false

## 畸变的全局租金倍率（通胀 ×2 / 房价崩盘 ×0.5；闸门二保证二者不同屏）
func _ab_rent_mult() -> float:
	if _ab_has("通胀"):
		return 2.0
	if _ab_has("房价崩盘"):
		return 0.5
	return 1.0

## 畸变的移动点数削减（隔离 −2；debuff，逐玩家被香皂/护盾免疫）
func _ab_move_cut(p: Dictionary) -> int:
	return 2 if _ab_has("隔离") and not _immune_debuff(p) else 0

# ================= 房主：结算 =================

## 落地结算。re = 「0 点再结算」：站在原地补一次结算——
## 只保留询问类内容（买地 / 升级）与功能格效果，不重复交租 / 焦土捐款。
func _resolve_tile(p: Dictionary, re := false) -> void:
	var idx := int(p.pos)
	var d: Dictionary = GameData.TILES[idx]
	match String(d.type):
		"property":
			var t: Dictionary = htiles[idx]
			if bool(t.get("soil", false)):
				if re:
					_log("%s 在【%s】的焦土上罚站，这次不用捐款" % [p.name, String(d.name)], "#8a90a5")
				elif _immune_debuff(p):
					_log("%s 的【空想者的香皂】挡下了焦土捐款，进度不涨" % p.name, "#8fb7f2")
					await _wait(0.4)
				else:
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
			elif re:
				_log("%s 在【%s】原地罚站，站着的客人不用再交租" % [p.name, String(d.name)], "#8a90a5")
			else:
				await _resolve_rent(p, idx)
		"event":
			var card: Dictionary = _draw_event(String(d.name))
			# 仿桌游：机会/命运卡从棋盘中央对应牌堆抽出展示
			s_card.rpc(String(card.t), _card_kind(card), String(d.name))
			_log("%s 抽到事件：%s" % [p.name, card.t])
			# 批次 12 C2：演出停在 HOLD 等抽卡者点「确定」，**效果在确认之后才落地**。
			await _await_card_confirm(p)
			await _apply_card(p, card)
		"item":
			# 失物招领：按招领权重随机品质捡一件（品质缺货自动向下降档）
			var q := _roll_quality(ItemData.FIND_WEIGHTS)
			var qi: int = ItemData.QUALITIES.find(q)
			while qi > 0 and _item_pool(ItemData.QUALITIES[qi]).is_empty():
				qi -= 1
			var found := _grant_item_of_quality(p, ItemData.QUALITIES[qi], "失物招领")
			if String(found) != "":
				# 批次 12 C3：演**这张道具的卡面**，与机会/命运同一段演出、同一个「确定」、
				# 同一条超时/托管（`card_item` 非空 ⇒ DeckReveal 走道具卡面那一路）。
				_log("【失物招领】%s 捡到了【%s】！" % [p.name, found], "#74d188")
				s_card.rpc("【失物招领】%s 捡到了【%s】！" % [p.name, found], "good", "失物招领", found)
				await _await_card_confirm(p)
			else:
				s_card.rpc("【失物招领】%s 翻了半天，一无所获" % p.name, "info")
				await _wait(0.4)
		"again":
			_log("%s 在【特浓咖啡】灌了一大口，精神抖擞——本回合再行动一次！" % p.name, "#f0a0c0")
			s_card.rpc("【特浓咖啡】%s 再行动一次！" % p.name, "good")
			_extra_move = true
			await _wait(0.4)
		"shop":
			if _ab_has("停电"):
				_log("【停电】%s 路过小卖部——店里黑着呢" % p.name, "#8a90a5")
			else:
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
			if re:
				_log("%s 在【%s】继续歇着，无事发生" % [p.name, d.name])
			else:
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
	var ab_mult := _ab_rent_mult()
	if ab_mult != 1.0:
		rent = int(rent * ab_mult)   # 畸变：通胀 ×2 / 房价崩盘 ×0.5（中性，香皂无效）
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
		_grant_item_of_quality(p, String(card.gain_item_quality))
	if card.has("enter_shop"):
		var shop_keys: Array = shops.keys()
		if _ab_has("停电"):
			_log("【停电】商店进不去，卡上的逛街安排作废", "#8a90a5")
		elif not shop_keys.is_empty():
			await _run_shop(p, int(shop_keys.pick_random()))
	if card.has("enter_blackshop"):
		if _ab_has("停电"):
			_log("【停电】黑市也黑着，进不去", "#8a90a5")
		else:
			await _run_blackshop(p)
	_check_end()

## 机会卡发道具（指定 id / 指定品质）；背包满则作废提示，唯一池过滤照旧
func _grant_card_item(p: Dictionary, id: String) -> void:
	if p.items.size() >= 5:
		_log("%s 背包已满，道具【%s】作废了" % [p.name, id], "#8a90a5")
		return
	if _grant_item(p, id):
		_log("%s 从机会卡获得道具【%s】" % [p.name, id], "#74d188")

## 按品质从可用池随机发一件道具（背包满 / 缺货则落空，返回 ""）。
## src = 来源名（「机会卡」/「失物招领」），只进战报文案。
func _grant_item_of_quality(p: Dictionary, q: String, src := "机会卡") -> String:
	if p.items.size() >= _bag_cap(p):
		_log("%s 背包已满，%s的道具放不下了" % [p.name, src], "#8a90a5")
		return ""
	var pool := _item_pool(q)
	if pool.is_empty():
		_log("%s 想领道具，可惜【%s】缺货" % [p.name, q], "#8a90a5")
		return ""
	var id: String = pool[randi_range(0, pool.size() - 1)]
	_grant_item(p, id)
	_log("%s 从%s获得道具【%s】" % [p.name, src, id], "#74d188")
	return id

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
	# 传送的淡出淡入在棋子自己身上（批次 11 Task 1 起棋子是 3D 的薄牌，见
	# scripts/table_props.gd「棋子（小人）」）：淡完才瞬移 —— 材质在不透明 ⇄ ALPHA 之间切。
	table3d.table_props.set_token_teleport(peer, idx)

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
	# 1) 手牌优先：左键命中一张牌 = **直接使用**（批次 7 起，杀戮尖塔式）；右键命中一张牌 = 丢弃（两步确认）。
	#    左键**只在道具阶段吃点击** —— 牌是常驻显示的（每次广播都摆一遍），别的阶段点它没有意义，
	#    吃下点击就等于把本该落到棋盘上的一次点击吞成「什么都没发生」。这条闸是必须的：手牌就摆在
	#    近端自己面前（棋盘下沿的木纹留白），与棋盘下沿相接，玩家想点棋盘时**很容易点到自己的牌**
	#    —— 没有闸的话这一下会被牌抢答成「直接把那张牌出掉」，本该落到棋盘上的那一点击就白吞了
	#（测试里有配对用例钉住：同样的点，非道具阶段必须落回桌垫、道具阶段才归牌）。
	#    **手牌与近排格子已经完全不相交**（批次 5 Task 3 把整排放大并下移到木纹留白；
	#    `hud_test` 断言牌盒与近排格子的相交处数为 0），所以这道闸防的是「抢答」，
	#    不再是「抢走格子下沿那几像素」。
	#    闸**含** `_tgt_stage == ""`（见 _hand_clickable）：选目标期间玩家**正要**点棋盘选格，
	#    那时更不该被自己的牌抢答成「把另一张牌出掉」。
	#    所以选目标期间手牌对点击**完全透明**：左键落回棋盘 = 选格，
	#    右键 = 既有的取消。退出选目标态走 Esc / 右键（点牌不再参与）。
	#    出牌就在 `_on_hand_clicked` 里：选中之后立刻走既有的 _on_use_pressed（两段式
	#    选目标 / 作弊器点数框 / 直接发 _send_use_item）——玩法路径一行没改。
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
	# 3) 选目标：改点**屏幕层的名册行**，见 `_on_corner_bar_clicked`（批次 9 落点在四角条，
	#    批次 12 D 起他人那一条在名册条上；**批次 13 ② 起那条在左上角「暂停」旁**）——
	#    原先的"点桌上立牌"那一支随立牌一起删掉了（立牌命中链已不存在）。
	return false

# ================= 悬停棋子的信息条（批次 11 Task 3）+ 悬停手牌放大（批次 12 B3） =================

## 鼠标在桌面上移动（画布像素）：命中**棋子**就浮出屏幕层的信息条，返回被悬停的 peer
## （`GameData.NO_PEER` = 谁都没悬停）。**不消费输入** —— 悬停照旧转发进 SubViewport
##（见 `TableView3D.on_table_hover` 的说明），这里只是"顺路把条的显隐更新一下"。
##
## 载体是**屏幕层**的 `token_tip`：原先它是画布里的一个 Control（随桌垫一起倾斜、3D 端读着是
## 歪的 —— 用户报的"角度不对"），搬到屏幕层后天然面向镜头。
## **内容与判据一字未改**（昵称 / 身家 / 名次 / 已出局），数据源仍是 **`board._peers_info`**
##（`board.render` 每次广播重填，身家公式与身家条 / 名册条同源）—— **单一来源**，不另取 game 那份 `standing`。
##
## **批次 12 B3：手牌也进这条链**。同一次移动里再问一句 `TableProps.hand_hit`，
## 命中的那一张走 `set_hand_hover(i)`（放大 + 抬起，见那里的注释）。
## **同一时刻只有一个悬停目标**：棋子**优先** —— 两样都命中时（棋子站在自己这排牌后面那种边角）
## 棋子赢，手牌那一问直接跳过（传 -1 收回去）。这与点击那条链的顺序**相反**是有意的：
## 点击时手牌排在棋盘之前（`_on_table_click` 先问 hand_hit），而悬停里棋子才是"有信息可给"的那一个。
##
## 降级：实体层还没就位 ⇒ 谁都不悬停（照 `_on_table_click` 的同一道守卫）。
## 拿不到画布点（射线打不到桌面，`TableView3D` 传 `Vector2.INF`）⇒ 谁都不悬停 ——
## 悬停是"每一动都重算"的语义，漏掉这一动会让条留在上一枚棋子上不掉（手牌同理，一起收回去）。
func _on_table_hover(canvas_px: Vector2) -> int:
	if table3d == null or table3d.table_props == null:
		return GameData.NO_PEER
	if not (is_finite(canvas_px.x) and is_finite(canvas_px.y)):
		_set_token_hover(GameData.NO_PEER)
		table3d.table_props.set_hand_hover(-1)
		return GameData.NO_PEER
	var tp = table3d.table_props
	var peer: int = tp.token_hit(canvas_px)
	_set_token_hover(peer)
	# 手牌：棋子优先（两样都命中时棋子赢），没命中棋子才轮到牌。
	tp.set_hand_hover(-1 if peer != GameData.NO_PEER else tp.hand_hit(canvas_px))
	return peer

## 悬停目标变了才重写条的内容；**同一枚棋子时也要重读内容 + 重摆位置**（悬停期间镜头会动、
## 状态广播也会改这个人的身家 / 名次 —— 两者都得跟上，见 `_fill_token_tip` / `_place_token_tip`）。
## `GameData.NO_PEER` ⇒ 收起。
##
## 降级：这枚棋子不在池里（已被移除 / 断线），或 `_peers_info` 里没有它（名册还没同步到）⇒ 收起，
## 不抛错、不漏半条（照 `_token_screen_pos` / `standee_screen_center` 那几条先例）。
##
## **`_tip_peer` 只在"真显出来"那条路上写**（R10-3）：若在"判据不过"的分支就把它写成这枚 peer，
## 那 peer 已在池里、只是名册尚未同步时条被隐藏，而 `_tip_peer` 已非哨兵 ⇒ 之后 `_peers_info`
## 填好了也不会自己出现（要移开再回来）。因此先把"显不出来"归一成 `NO_PEER` 再比 `_tip_peer`。
func _set_token_hover(peer: int) -> void:
	if token_tip == null or not is_instance_valid(token_tip):
		return
	if peer != GameData.NO_PEER:
		var info: Dictionary = board._peers_info.get(peer, {}) if board != null else {}
		var tp = table3d.table_props if table3d != null else null
		if info.is_empty() or tp == null or not tp.has_token(peer):
			peer = GameData.NO_PEER      # 显不出来 ⇒ 按"谁都没悬停"处理（收起，不写 `_tip_peer`）
	if peer == _tip_peer:
		if _tip_peer == GameData.NO_PEER:
			return
		# 还是同一枚：内容重读（R10-2：悬停期间来了状态广播改了他的身家 / 名次，
		# 只重摆位置会让条上的数字陈旧）+ 重摆位置（镜头可能动了）。
		_fill_token_tip(_tip_peer)
		token_tip.visible = true
		_place_token_tip()
		return
	_tip_peer = peer
	if peer == GameData.NO_PEER:
		token_tip.visible = false
		return
	_fill_token_tip(peer)
	token_tip.visible = true
	_place_token_tip()

## 把 `board._peers_info` 里这枚 peer 的昵称 / 身家 / 名次写进条上（**单一来源**，与身家条同源；
## 身家公式不另取 game 那份 `standing`）。只负责**内容** —— 显隐与位置由调用方决定。
## 判据一字未改（含「已出局」那一支），只换载体与朝向（批次 11 Task 3）。
func _fill_token_tip(peer: int) -> void:
	var info: Dictionary = board._peers_info.get(peer, {}) if board != null else {}
	_tip_name.text = String(info.get("name", "?"))
	_tip_name.add_theme_color_override("font_color", info.get("color", UIKit.TEXT))
	_tip_sub.text = "身家 %s · 第 %d 名%s" % [
		GameData.fmt_money(int(info.get("worth", 0))), int(info.get("rank", 0)),
		"" if bool(info.get("alive", true)) else " · 已出局",
	]

## 把信息条摆到棋子此刻**在屏幕上的位置**正上方，并夹在屏幕内（夹取规则沿用旧画布版：
## 左右不越界、上下不越界）。**每帧调**（`_process`）—— 悬停期间镜头会动（自动跟随 / 滚轮推移
## 视角 / 取景变化），照身家条 / 格详情卡那套"每帧贴一次"的既有做法。
##
## 位置必须**过相机**（`camera.unproject_position`：棋子的世界点 → 屏幕）：棋子在桌上的位置不动，
## 而"你看到它在哪"随镜头变 —— 这正是每帧重摆的理由，也是"屏幕层天然面向镜头"那条的实现。
##
## 降级：棋子不在池里（走子途中被移除 / 断线）⇒ 收起并清掉悬停目标，不抛错。
## `table3d.camera` 的空守卫（R10-4）与 `table_props._token_rect` 同处一样：相机实际在
## `TableView3D._init` 就建好、不可达空，但真为 null 时这一句会**每帧刷 SCRIPT ERROR**
##（`_process` 每帧调本函数），补进已有的隐藏判断里把它一起挡掉。
func _place_token_tip() -> void:
	if token_tip == null or not is_instance_valid(token_tip) or _tip_peer == GameData.NO_PEER:
		return
	if table3d == null or table3d.camera == null or table3d.table_props == null \
			or not table3d.table_props.has_token(_tip_peer):
		token_tip.visible = false
		_tip_peer = GameData.NO_PEER
		return
	var c: Vector2 = table3d.camera.unproject_position(table3d.table_props.token_world_pos(_tip_peer))
	var sz := token_tip.size
	var pos := Vector2(c.x - sz.x * 0.5, c.y - sz.y - 38.0)
	pos.x = clampf(pos.x, 6.0, maxf(6.0, size.x - sz.x - 6.0))
	pos.y = clampf(pos.y, 6.0, maxf(6.0, size.y - sz.y - 6.0))
	token_tip.position = pos

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

## 点手中的牌 = **直接使用**（杀戮尖塔式，批次 7）：点一张牌就出它，不再有"选中 → 再点确认"。
## 需要选目标的进选目标态，作弊器弹点数框，其余直接发 —— 分派逻辑复用既有的 `_on_use_pressed`，
## 一行没改。右键丢弃的两步确认（`_on_discard_clicked`）也不动。
## 调用前提由 `_hand_clickable` 保证（轮到我 + 道具阶段 + 没在选目标 + 已实装）。
func _on_hand_clicked(hi: int) -> void:
	_on_item_slot_clicked(my_peer, hi)   # 玩法侧唯一入口：记 selected_slot + 桌上那张牌抬起
	_on_use_pressed()                    # 既有的出牌分发（选玩家 / 选地块 / 点数框 / 直接发）

## 清掉「当前选中的道具」：玩法侧（selected_slot）+ 手牌表现（桌上那张牌还抬着）。
## `board.set_item_selected` 照旧一起调，但它那个落点（座位卡的**牌位**那一排）是**批次 3 Task 6**
## 拆掉的，座位卡**本身**随后在**批次 5** 退场 —— 如今它**只记状态、没有落点**
## （同 `_set_hl_peers` 那类无落点的接口按先例保留）；今天真正看得见的反馈只有手牌自己收起抬起。
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
	# 待决格 = 提问者脚下那一格（两个调用点都由 `_resolve_tile` 以 `p.pos` 为 idx 调过来）
	_prompt_tile = int(p.pos)
	_broadcast_state()
	if int(p.peer) == 1:
		_show_prompt(tok, title, text, ok_text)
	else:
		s_prompt.rpc_id(int(p.peer), tok, title, text, ok_text)
	var timed_out := await _await_turn_window("prompt",
		func() -> bool: return int(_decision.token) != tok,
		func(sec: float) -> void: _prompt_bar_arm(tok, sec))
	_awaiting_prompt = 0
	_prompt_tile = -1
	_close_prompt()   # 窗口关掉（答了 / 超时）⇒ 决策区收起（幂等；按钮那一侧已经收过一遍）
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

## 房主改畸变设置（对局内暂停面板；大厅入口随「开局设置面板」批次接入）
func _set_ab_freq(id: String) -> void:
	if not multiplayer.is_server() or not GameSettings.AB_FREQS.has(id) or id == _settings.ab_freq:
		return
	_settings.ab_freq = id
	_log("房主把畸变频率改为「%s」" % id, "#f0c064")
	_refresh_ab_settings_ui()
	_broadcast_state()

func _set_ab_dur(id: String) -> void:
	if not multiplayer.is_server() or not GameSettings.AB_DURS.has(id):
		return
	if int(id) == _settings.ab_dur:
		return
	_settings.ab_dur = int(id)
	_log("房主把畸变持续回合改为 %d" % int(id), "#f0c064")
	_refresh_ab_settings_ui()
	_broadcast_state()

func _set_ab_cond(id: String) -> void:
	if not multiplayer.is_server() or not GameSettings.AB_COND_SW.has(id):
		return
	var on := id == "on"
	if on == _settings.ab_cond:
		return
	_settings.ab_cond = on
	_log("房主把畸变条件触发改为「%s」" % String(GameSettings.AB_COND_LABELS.get(id, id)), "#f0c064")
	_refresh_ab_settings_ui()
	_broadcast_state()

## 刷新设置面板的「畸变」小节：房主 = 小节标题 + 三行可点 chips，客户端 = 一行只读文本。
## 显隐分工与「操作限时」行同理（两侧互斥，见 _refresh_tier_ui 的注释）。
func _refresh_ab_settings_ui() -> void:
	if ab_row == null or ab_readonly == null or ab_title == null:
		return
	var is_host := multiplayer.is_server()
	ab_title.visible = is_host
	ab_row.visible = is_host
	ab_dur_row.visible = is_host
	ab_cond_row.visible = is_host
	ab_readonly.visible = not is_host
	ab_readonly.text = "畸变：%s · 持续%d回合 · 条件触发%s（房主设置）" % [
		_settings.ab_freq, _settings.ab_dur, "开" if _settings.ab_cond else "关"]
	UIKit.chip_select(ab_row, _settings.ab_freq)
	UIKit.chip_select(ab_dur_row, str(_settings.ab_dur))
	UIKit.chip_select(ab_cond_row, "on" if _settings.ab_cond else "off")

## 「生效中」小标签：读快照的 aberrations 字段（s_state 两端同路径触发）。
## 界面美术重构后这里升级为正式横幅 + 座位卡角标（当前从简）。
func _refresh_ab_ui() -> void:
	if ab_label == null or ab_label_l == null:
		return
	var act: Array = st.get("aberrations", [])
	if act.is_empty():
		ab_label.visible = false
		return
	var parts := PackedStringArray()
	for a in act:
		parts.append("%s·剩%d回合" % [String(a.id), int(a.left)])
	ab_label_l.text = "🌀 畸变生效中：%s" % "、".join(parts)
	ab_label.visible = true

## 操作窗口剩余时间（全员可见）走这条专用 RPC，而不进 _broadcast_state：
## 它按秒高频变化，进全量状态会让所有端每秒白渲染一整帧棋盘。
## kind="" 表示当前没有操作窗口（收簇）；total<=0 = 不限时；owner_peer = 窗口归属玩家
## （倒计时挂在他那条身家条 / 名册行上，D 方案）。
@rpc("authority", "call_local", "reliable")
func s_op_timer(kind: String, left: float, total: float, owner_peer: int) -> void:
	_op_kind = kind
	_op_left = left
	_op_total = total
	_op_owner = owner_peer
	# 抽卡演出的「确定」按钮**只给该确认的人**（= 本窗口的归属 = 抽卡者）。观众看到同一张卡、
	# 按钮不出镜，由抽卡者的确认统一收起（批次 12 C2）。走这条事件驱动而不是逐帧刷，
	# 摆拍的 `dev_force_confirm` 才不会被下一帧覆写掉。
	if deck_reveal != null and is_instance_valid(deck_reveal):
		deck_reveal.set_can_confirm(kind == "card" and owner_peer == my_peer)

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
	if _awaiting_card != 0:
		return _awaiting_card
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
	elif _awaiting_card != 0:
		# 抽卡演出等「确定」（批次 12 C2）：await_peer = 该点确定的人（= 抽卡者）。
		await_state = "card"
		await_peer = _awaiting_card
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
		"aberrations": _ab_active,
		"ab_freq": _settings.ab_freq, "ab_dur": _settings.ab_dur, "ab_cond": _settings.ab_cond,
		"winner": winner, "roll_epoch": _roll_epoch,
	})

func _log(line: String, color: String = "#dfe3ee") -> void:
	var safe := line.replace("[", "［")
	if color != "#dfe3ee":
		safe = "[color=%s]%s[/color]" % [color, safe]
	s_log.rpc(safe)

## 畸变公告：start / end。文本公告已由 _log→s_log 走顶部气泡；
## 这里补全场动效（debuff 触发震屏），持续期「生效中」标签由快照的 aberrations 驱动。
@rpc("authority", "call_local", "reliable")
func s_aberr(id: String, action: String, left: int) -> void:
	if action == "start" and String(AberrationData.def(id).get("tag", "")) == "debuff":
		Fx.shake(self, 9.0, 0.35)

# ================= 全员：接收 RPC =================

@rpc("authority", "call_local", "reliable")
func s_state(state: Dictionary) -> void:
	st = state
	# 决定已经不在我身上了（答了 / 超时 / 窗口被别人接手）⇒ 决策区收起（批次 12 C1）。
	# 按钮那一侧点完就收过一遍，这条是**兜底**：房主超时时本机可能一帧都没点。
	if _prompt_token != -1 and not (String(state.get("await", "")) == "prompt" \
			and int(state.get("await_peer", -1)) == my_peer):
		_close_prompt()
	var tier := String(state.get("timeout_tier", GameSettings.TIER_CURRENT))
	if tier != _settings.timeout_tier:
		_settings.timeout_tier = tier
		if _prompt_token != -1:   # 弹窗开着 → 按新挡位重启倒计时条
			_prompt_bar_arm(_prompt_token, GameSettings.turn_seconds(tier, "prompt"))
		_refresh_tier_ui()
	var abf := String(state.get("ab_freq", "关"))
	if abf != _settings.ab_freq or int(state.get("ab_dur", 2)) != _settings.ab_dur \
			or bool(state.get("ab_cond", true)) != _settings.ab_cond:
		_settings.ab_freq = abf
		_settings.ab_dur = int(state.get("ab_dur", 2))
		_settings.ab_cond = bool(state.get("ab_cond", true))
		_refresh_ab_settings_ui()
	_refresh_ab_ui()
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
	# 逐格走子 = 世界坐标补间 + 竖直小跳的弧 + 挤压（棋子已搬进 3D，见 table_props.play_token_move）
	table3d.table_props.play_token_move(peer, path, step_time)

@rpc("authority", "call_local", "reliable")
func s_card(text: String, kind: String = "info", deck: String = "", card_item: String = "") -> void:
	Fx.play("card", -4.0)
	if deck != "":
		# 事件卡：在屏幕层大字演出（批次 8）。相机全程不动 —— 旧版会推近 2D 镜头去读字，
		# 那一推让桌垫图案滑动、与不跟相机的手牌错位（见 scripts/deck_reveal.gd）。
		# 空守卫：`deck_reveal` 由 `_build_ui` 建、首个 `s_card` 之前必已就位（今天无害），
		# 但缺了它将来一旦次序变了就会在对局中途崩 —— 宁可跳过演出，也不崩。
		# `card_item` 非空 = 演**那张道具的卡面**（批次 12 C3 / ⑪ 失物招领），走同一段演出。
		if deck_reveal != null:
			deck_reveal.show_card(deck, kind, text, card_item)
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

## 客户端 → 房主：本机玩家点了抽卡演出的「确定」（批次 12 C2 / ⑧⑪）。
## 只认抽卡者本人（`_awaiting_card`），与 `c_decision` 的归属校验同一套做法。
@rpc("any_peer", "call_remote", "reliable")
func c_card_ok() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _awaiting_card:
		return
	_card_ack = true

## 房主 → 全员：收卡。抽卡者的确认 / 超时 / 机器人托管三条路都汇到这里，**全员一起收**。
@rpc("authority", "call_local", "reliable")
func s_card_close() -> void:
	if deck_reveal != null and is_instance_valid(deck_reveal):
		deck_reveal.request_close()

## 本机玩家点了「确定」（`DeckReveal.confirmed`）：房主直接放行，客户端回 `c_card_ok`。
func _on_card_confirm() -> void:
	if multiplayer.is_server():
		if _awaiting_card == my_peer:
			_card_ack = true
	else:
		c_card_ok.rpc_id(1)

## 等抽卡者点「确定」。**效果在确认之后才落地**（原来这里是 `await _wait(CARD_TIME + 0.1)`
## 然后直接 `_apply_card`）。
##
## 超时走**既有操作限位**（`_await_turn_window` 的 "card" 挡位 ⇒ 倒计时挂在抽卡者的条 / 名册行上）；
## 机器人 / 休眠托管 / 自动回归**短暂延时后自动确认**，不卡节奏。
func _await_card_confirm(p: Dictionary) -> void:
	_awaiting_card = int(p.peer)
	_card_ack = false
	_broadcast_state()   # 快照里 await="card" / await_peer=抽卡者（见 _broadcast_state 的等待链）
	if _is_managed(p):
		# 机器人 / 休眠托管：短暂延时后自动确认（不卡节奏）
		await _wait(0.6)
	elif at_mode != "" and int(p.peer) == my_peer:
		# 自动回归里房主自己那张：不等真人点。**注意别把它扩成"整局都自动确认"** ——
		# 别人（客户端）那一张要走真正的操作窗口 + `c_card_ok` 回程，联机回归才验得到协议。
		await _wait(0.3)
	else:
		# `alive` 的语义是"**还**在等"（同 `_ask` 的 `_decision.token != tok`）—— 写反了
		# 会让窗口一次都不进（`s_op_timer` 也不发、超时也不计），卡一闪而过。
		await _await_turn_window("card", func() -> bool: return not _card_ack)
	s_card_close.rpc()
	_awaiting_card = 0
	_broadcast_state()

# ================= 界面刷新 =================

## 「跟印刷图案走」的两件实体（转盘轮缘 / 两摞牌堆）此刻能不能算：3D 物件层在、
## board 也已取景（布局还没跑时 `wheel_screen_pos` / `deck_screen_pos` 全是错的 ——
## 判据与 fit_overview 的触发条件同源）。
func _board_follow_ready() -> bool:
	return table3d != null and table3d.table_props != null and board != null \
		and board.size.x > 10.0

## 把**跟着桌垫印刷图案走**的两件实体重摆一遍：转盘轮缘 + 两摞牌堆。
##
## 为什么是这两件、为什么位置每次都要重算：它们是「压在画着**同一个物体**的印刷图案上」那一类
##（轮缘压着桌垫上画出来的轮盘、牌堆压着桌垫上画出来的卡背）—— 图案随 2D 取景（`_zoom` /
## `_center`）走，实体不跟就会脱开。位置一律走 `board.*_screen_pos()` 那几个公开入口
##（内部就是 `global_position + _view_from_world(...)`，见 `deck_screen_pos` 那段）。
##
## 幂等（只改 transform / mesh 尺寸，不重建节点）⇒ **每条路都能调**：
##   * 状态广播（`_refresh_table_props`）—— 数据变了的那一条（常态）；
##   * 逐帧补推（`_refresh_followers_if_cam_moved`）—— 只动镜头、没有广播的那一条。
## （原先还有一条"抽卡演出期间逐帧重推"，那是给抽卡的 ≥2× 推近兜底的；演出搬到屏幕层
##  `DeckReveal` 后相机全程不动，那段连同它的前提一起删了。**批次 11 T1 审查 Important #1
##  又以另一条判据（"取景键变没变"）把逐帧这条接回来了** —— 自动跟随 / `focus_grid` 都会让
##  2D 取景逐帧动，只挂广播的话跟图案的实物会脱开。）
##
## 注意**滚轮推移视角不算在内** —— 那是 TableView3D 的 3D 相机（`set_view` 改的是**视角推移**，
## 批次 4 起已取消推拉），只改相机的俯角与到桌心的距离，不碰 2D 的 `_zoom`，
## 桌垫图案与实物一起原样不动（3D 端点变化不改变画布像素口径）。「谁跟相机、谁不跟」见
## table_props.gd 文件头的摆放约定：**跟 2D 相机的是四件 + 棋子的位置**（本函数这两件、`_refresh_tokens`
## 里的光环与棋子、`_refresh_houses` 里的房子 —— 它们都压在印刷图案上），手牌是画布常量的实物、不跟。
func _refresh_board_followers() -> void:
	table3d.table_props.build_wheel(board.wheel_screen_pos(), board.wheel_screen_radius())
	# 牌堆：**位置与尺寸都跟印刷图案**（`deck_screen_pos` / `deck_screen_size`，同轮缘那一套）。
	# 尺寸是修复波 F 补的：取景一变印刷卡背整体放大/缩小，只跟位置的话摞会盖不住它。
	table3d.table_props.build_decks({
		"机会": board.deck_screen_pos("机会"),
		"命运": board.deck_screen_pos("命运")},
		board.deck_screen_size("机会"))

## 棋子（小人）与当前行动者光环：**都住在 3D 的 `TableProps` 里**（批次 11 Task 1 搬进去的，
## 原先由 `board.render` 在画布上建 2D Control —— 那份已整段删除）。
##
## 数据来源与判据一字未改：棋子 = `st.players` 的 `peer / color(槽位) / pos(格号)`；
## 光环 = `st.turn`（`phase == "ended"` ⇒ 收起，哨兵是 `GameData.NO_PEER`，**不是 -1**
## —— 机器人 peer 从 -1 起编号；旧代码那处写的 `_set_ring(-1)` 会把机器人 peer -1 误当行动者）。
## `set_tokens` 幂等、`set_ring` 幂等，所以每次广播都推一遍（同轮缘 / 牌堆那两件）。
##
## 为什么在 `_refresh_table_props` 里排得**靠前**（`mine.is_empty()` 那道早退之前）：
## 棋子与光环是"全员可见"的状态，与"我自己在不在名册里"无关 —— 掉线重连时也该看得见别人走子。
func _refresh_tokens() -> void:
	if not _board_follow_ready():
		return
	var rows: Array = []
	for p in st.get("players", []):
		# 键一律用 `.get(..., 默认)`：这条路现在**也挂在 `_process` 的补推上**（镜头一动就调），
		# 而 `st` 可能是测试手搓的、字段不全的状态（真实 `s_state` 的这三项恒在）。
		# 少了默认值，一次缺键就是一条 SCRIPT ERROR 并让整段刷新中断（regression_test 逮到过）。
		rows.append({"peer": int(p.get("peer", GameData.NO_PEER)),
			"slot": int(p.get("color", 0)), "idx": int(p.get("pos", 0))})
	table3d.table_props.set_tokens(rows)
	var ended := String(st.get("phase", "playing")) == "ended"
	table3d.table_props.set_ring(GameData.NO_PEER if ended else int(st.get("turn", GameData.NO_PEER)))

## 装修房子：**也住在 3D 的 `TableProps` 里**（批次 11 Task 2 搬进去的，原先由 `board.render`
## 在画布上建 2D `HouseIcon` —— 那份已整段删除，见 `board_view` 里那段退场说明）。
##
## 数据来源与判据一字未改：`st.tiles[i].level`（`0` = 未装修 / 无主 ⇒ 不摆）。
## 房子**压在格子上** ⇒ 位置与尺寸都跟印刷图案（`board.house_screen_pos` / `house_screen_size`），
## 与轮缘 / 牌堆 / 光环同一条口径 —— 所以它也必须在**镜头动过的那一帧**被重推
##（`_refresh_followers_if_cam_moved` 里与棋子同一批，见那里的注释）。
##
## **等级表缓存在本节点**（`_house_levels`）：逐帧那条路每帧都会走这里，每帧现造一个 56 元素的
## 数组是白白分配（T1 审查 Minor #6 那条"别每帧造东西"的教训，56 格会被放大成 56 倍）——
## 只在**广播**时重建（`_cache_house_levels`），逐帧这条只把缓存重推下去
##（`TableProps.set_houses` 幂等：等级没变就只重贴位置，不碰材质 / 可见性）。
var _house_levels: Array = []

func _refresh_houses() -> void:
	if not _board_follow_ready():
		return
	table3d.table_props.set_houses(_house_levels)

## 广播路径专用的那一半：把 `st.tiles` 的等级读进缓存（原地改，常态**不分配**新数组）。
func _cache_house_levels() -> void:
	var tiles: Array = st.get("tiles", [])
	if _house_levels.size() != tiles.size():
		_house_levels.resize(tiles.size())   # 只在尺寸真的变了时动一次（对局里不会发生）
	for i in tiles.size():
		# 键一律用 `.get(..., 默认)`：这条路与棋子那条一样也挂在逐帧补推上，
		# 手搓的不全状态（测试）会缺键 —— 少了默认值就是一条 SCRIPT ERROR 并中断整段刷新。
		_house_levels[i] = int((tiles[i] as Dictionary).get("level", 0))

## 某枚棋子此刻在**屏幕**上的位置 —— 棋子住在 3D 层（`TableProps`），所以走
## "世界点 → 相机投影"（`camera.unproject_position` 给的就是屏幕/窗口坐标，正是飘字与飞钞要的）。
##
## 拿不到这块棋子（名单里还没有它 / 相机不可用）时退回**它那一格的格心**
##（`board.tile_screen_pos` + `_board_to_screen` 那条既有链）—— 反馈照旧有个落点，
## 不会因为"棋子还没建出来"就静默消失（同 `_corner_bar_screen_center` 的降级精神）。
func _token_screen_pos(peer: int, idx: int = -1) -> Vector2:
	if table3d != null and table3d.table_props != null and table3d.table_props.has_token(peer):
		return table3d.camera.unproject_position(table3d.table_props.token_world_pos(peer))
	if idx >= 0 and board != null:
		return _board_to_screen(board.tile_screen_pos(idx))
	return size * 0.5

## 上一次把"跟图案"的实体推给 3D 时的 **2D 取景键**（`board.cam_key()` = 缩放 + 注视点）。
## 初值 `Vector3.INF` ⇒ 第一次一定推一次（`is_equal_approx(INF)` 为假）。
var _follow_cam_key := Vector3.INF

## 镜头动过就补推一次"跟图案"的那批（轮缘 / 两摞牌堆 / 棋子 / 光环）。
##
## **为什么需要它**（批次 11 T1 审查 Important #1）：这四件的世界位置是按**摆放那一刻**的镜头算的
##（它们要落在**印在桌垫上**的图案上，见 table_props 文件头"摆放约定"），而 2D 相机是**逐帧**在动的
## —— `board._process` 的自动跟随 `_pan_toward` 每帧把 `_center` 推向行动棋子（`fit_overview` /
## `focus_grid` 也会改取景）。只挂状态广播的话，"镜头动了但没有广播"的那一段里印在 `_world` 里的
## 格子会整体滑动、而实物纹丝不动（实测约半格、~1s 衰减）——
## 对旧 2D 棋子（它活在 `_world` 里、任何时刻都钉在格子上）来说是**回归**；轮缘 / 牌堆则是老毛病。
##
## **镜头静止时零开销**：只比三个浮点数就早退（`_process` 每帧调它）。
## 与 `_refresh_table_props` 的关系：那边是广播路径（数据也变了），这边只补"镜头变了"这一半；
## 两条都幂等，重叠着调没有代价。
func _refresh_followers_if_cam_moved() -> void:
	if not _board_follow_ready():
		return
	var key: Vector3 = board.cam_key()
	if key.is_equal_approx(_follow_cam_key):
		return
	_follow_cam_key = key
	_refresh_board_followers()
	_refresh_tokens()       # 棋子 + 光环
	_refresh_houses()       # 装修房子（批次 11 Task 2 并进这同一批：房子也压在格子上）

## 桌面实体物件的刷新挂点：把物件重新贴回桌垫坐标（手牌也在这里）。
##
## 为什么**每次状态广播**都要刷、而不是建一次就完：跟图案走的那几件（轮缘 / 牌堆 / 棋子与光环 /
## 装修房子）见 `_refresh_board_followers` / `_refresh_tokens` / `_refresh_houses`；
## 其余物件（手牌）也一律幂等，每次广播重贴一遍没有代价。它们读的都是**已同步**的状态
##（客户端也能算）。
## **镜头动了却没广播**那一段由 `_refresh_followers_if_cam_moved` 逐帧兜（见那里的注释）。
func _refresh_table_props() -> void:
	if not _board_follow_ready():
		return
	# 广播这条路上顺手认下"当前取景"：否则紧接着的那一帧会因键不同再补推一遍（无害，但白跑）
	_follow_cam_key = board.cam_key()
	_refresh_board_followers()
	_refresh_tokens()
	_cache_house_levels()   # 等级表只在广播这条路上重建（逐帧那条只重推缓存，见 `_refresh_houses`）
	_refresh_houses()
	var mine := _state_player(my_peer)
	if mine.is_empty():
		return                      # 还没轮到自己进状态（理论上不会）：宁可什么都不摆
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
## `st.tiles`，而不是房主专有的 `htiles`（客户端没有 hp / htiles）。
##
## 调用方：`_open_player_popup`（批次 9 的道具弹窗，见 批次9-设计 §4.3）—— 立牌退场后它接手了
## "看别人身家"那个落点。与 `_refresh_players` 里那份 `worth_map` 同式，**改公式要两处一起改**。
func _state_worth(peer: int) -> int:
	var v := int(_state_player(peer).get("money", 0))
	var tiles_arr: Array = st.get("tiles", [])
	for i in mini(tiles_arr.size(), GameData.TILES.size()):
		var td: Dictionary = tiles_arr[i]
		if int(td.get("owner", GameData.NO_OWNER)) == peer:
			v += int(GameData.TILES[i].price) + int(td.get("level", 0)) * GameData.upgrade_cost(i)
	return v

## 名册顺序 = 把 st.players **轮转成"自己打头、其余按行动序"**（自己 / 下家 / 对家 / 上家）。
##
## **这是"我自己排在哪一位"的唯一判据**（批次 5 Task 3 起）：`_refresh_corner_bars` 取它的
## **第 0 位**当作"我"（`TableHud.MY_BAR_SLOT`，屏幕左下角那条）；批次 12 D1 之前它同时喂四角条，
## 现在只喂这一条（立牌已于批次 9 退场，那条"角标对着哪块立牌"的对齐关系随之作废）。
## 自己不在名册里（观战 / 掉线重连）时从第 0 家起轮转。
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

func _name_by_peer(peer: int) -> String:
	for p in st.get("players", []):
		if int(p.peer) == peer:
			return String(p.name)
	return "?"

func _refresh_players() -> void:
	# 桌面实体物件：每次状态广播都重新贴回桌垫坐标（见 _refresh_table_props 的注释）
	_refresh_table_props()
	_money_flies.clear()     # 本帧飞钞队列（批次 13 ⑥：记在钱循环里、播在身家条刷完之后）
	var tiles_arr: Array = st.get("tiles", [])
	var worth_map := {}
	for p in st.get("players", []):
		var peer := int(p.peer)
		# 座位卡已随批次 5 Task 2 整体退场：这里**不再**给四条座位栏刷名字 / 现金 / 棋子 /
		# 体力 / 回合描边（`board._player_rows` 那套一并删除）。名字 / 身家 / 现金现在由
		# **屏幕层身家条 / 名册条**承担（`_refresh_corner_bars`，批次 9 起公开背包另有玩家道具弹窗），
		# 画布上不再有"哪张卡"可写。
		# 金额滚动 / 涨跌闪色也**没有落点了**，但飘字与音效仍以**棋子**为锚（下面那段），保留。

		# 身家 = 现金 + 名下地皮（地价 + 装修），与房主 `_net_worth` 同一公式。
		# 消费方：身家条 / 名册条（`_refresh_corner_bars` 的 standing）与悬停棋子的信息条
		#（后者在 board.render 里另算一份、同为这个公式）。
		# **这里不是唯一一处**：同式的还有 `_state_worth(peer)`（喂玩家道具弹窗，批次 9 接上）
		# 与房主 `_net_worth`（喂结算）—— **改公式要几处一起改**，别只改这里。
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
			# 锚点 = 那枚棋子此刻在屏幕上的位置（棋子已是 3D 实物，见 `_token_screen_pos`）
			var pos := _token_screen_pos(peer, int(p.pos)) + Vector2(0, fy)
			Fx.float_text(self, pos, ("+" if diff > 0 else "") + GameData.fmt_money(diff), col, 19)
			Fx.play("cash" if diff > 0 else "pay", -5.0)
			# **飞钞要等一帧再播**（批次 13 ⑥ 修的真 bug，见下面 `_money_flies` 那段注释）：
			# 这里只记差分，播放在 `_refresh_corner_bars` 之后。
			_money_flies.append({"peer": peer, "diff": diff})

	# 身家排名（名次徽章的依据）
	var order: Array = worth_map.keys()
	order.sort_custom(func(a, b) -> bool: return int(worth_map[a]) > int(worth_map[b]))

	# 身家条 / 名册条复用上面刚算出的身家/排名（这份 `worth_map` 只喂它们；
	# **同式的另有 `_state_worth` 喂道具弹窗** —— 改公式要一起改，别只改这里）
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
	# 高亮重放：`_refresh_corner_bars` 有签名缓存（状态没变就早退），而"只变高亮"的广播
	#（`_push_peer_highlight` 不伴随状态变化）会在那里被早退掉；而且广播会重排角位 ——
	# 只贴"变化的那一次"会漏。所以每次广播末尾都按 `_hl_peers` 重放一遍。
	_refresh_corner_highlight()
	# **飞钞最后播**（批次 13 ⑥ 修的真 bug）：`_spawn_money_fly` 的终点取
	# `_corner_bar_screen_center(peer)`，而那个查询读的是每条 bar 的 `peer` 绑定与可见性 ——
	# 那些**只有当帧的 `_refresh_corner_bars` / `_refresh_roster` 跑完才成立**。原先在钱循环里
	# 就地播（上面那段）⇒ 读的是**上一次广播**的绑定；名册按身家排序，于是"金额变了、名次也变了"
	# 的那一帧，钞票会飞向一行、下一帧那行换了人（或正要被藏起来）。
	# 飘字与音效锚在**棋子**上、与名册无关，留在上面原位不动。
	for f in _money_flies:
		_spawn_money_fly(int(f.peer), int(f.diff))
	_money_flies.clear()
	# 玩家道具弹窗（批次 9）：打开期间随广播重填（数值实时）；那个人离场或整局结束即关掉
	#（弹一个已经不存在的人的弹窗没有意义）。
	if player_popup != null and player_popup.is_open():
		var op := player_popup.open_peer()
		if String(st.get("phase", "")) == "ended" or _state_player(op).is_empty():
			player_popup.close()
		else:
			_open_player_popup(op)

## 「我」那条身家条 + 名册条 —— **一处刷完**（批次 12 D1 起；**批次 13 ② 起名册条在左上角**）。
##
## **为什么合成一处**：两者挂的是同一份 `standing`（身家 / 名次 / 现金 / 是否出局）、同一个
## 行动者高亮、同一条倒计时，只是载体不同（左下角我这一条 vs 名册条里的一格）。分两个函数各刷一遍，
## 就等于把"哪一位的身家是什么"算两次、还可能刷出不一致 —— 所以入口仍是这一个。
##
## **「我」那条**（`corner_bars[0]`）挂 `_seat_peers()[0]`：自己打头 ⇒ 就是"我"；
## 自己不在名册里（观战 / 掉线重连）时从第 0 家起轮转（与批次 5 同一语义）。
## 三行：名字（自己标「我」/ 破产标「破产」）、**身家**（大字）、**现金**（第二行小字），
## 外加**能量行**（批次 12 D1：读数 + 小格）与**倒计时行**（常驻占位）。
##
## **名册条**列出其余所有人（一条一行），点击 → 开该玩家的道具弹窗 / 选目标态下选中 TA。
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
	_standing_by_peer = by_peer
	var seats: Array = _seat_peers()
	var mine_peer: int = int(seats[0]) if not seats.is_empty() else GameData.NO_PEER
	var turn_peer := int(st.get("turn", -1))
	var phase := String(st.get("phase", ""))
	# 签名：行动者与阶段 + 每一条（我那条 + 名册每一行）的 rank/worth/money/alive/color +
	# **我这条的能量**（用道具扣体力时身家不一定变，不带上它能量行就不刷新）。
	var mine_st := _state_player(mine_peer)
	var sig := "%d|%d|%s|%d|%d|" % [mine_peer, turn_peer, phase,
		int(mine_st.get("stamina", -1)), _stamina_cap(mine_st)]
	for e in standing:
		sig += "%d,%d,%d,%d,%d,%d;" % [int(e.peer), int(e.get("rank", 0)),
			int(e.get("worth", 0)), int(e.get("money", 0)),
			int(e.get("color", -1)), 1 if bool(e.get("alive", true)) else 0]
	if sig == _corner_sig:
		return
	_corner_sig = sig

	# ① 「我」那条（`corner_bars[0]`）
	var mine: Dictionary = corner_bars[0]
	var mine_e: Dictionary = by_peer.get(mine_peer, {})
	if mine_e.is_empty():
		(mine.root as Control).visible = false
		mine.peer = GameData.NO_PEER
		(mine.root as Control).set_meta("peer", GameData.NO_PEER)
	else:
		(mine.root as Control).visible = true
		_fill_peer_bar(mine, mine_e, turn_peer, phase, true)
		_refresh_my_energy(mine, mine_peer)

	# ② 名册条：其余所有人
	_refresh_roster(standing, mine_peer, turn_peer, phase)

## 把一条身家条 / 名册行按 `standing` 里那一项刷一遍 —— **「我」那条与名册条共用的同一个填法**。
## 只有三处按"是哪一种载体"分叉（`is_self`）：徽章位、现金行、名字后面的「（我）」标记 ——
## 名册条按设计 §⑩2 只画「徽记 + 名字 + 身家」，那两样它没有。
## `active` = 这一位正是当前行动者（描 1px 金边；与"可被选中"的 2px 高亮合成在同一张样式盒里）。
func _fill_peer_bar(bar: Dictionary, e: Dictionary, turn_peer: int, phase: String,
		is_self: bool) -> void:
	var root: Control = bar.root
	var peer := int(e.peer)
	var alive := bool(e.alive)
	bar.peer = peer
	# 批次 9：条根上镜像一份 peer 给点击回调用（`table_hud._make_corner_bar` / `_make_roster_row`
	# 的 `gui_input` 现读 `root` 的 meta）—— **必须与 `bar.peer` 同处写**，否则回调会点到上一个人。
	root.set_meta("peer", peer)
	# 棋子色小片：与棋盘上的棋子同一个配色来源（只在真变了才重建）
	var col := int(e.color)
	if bar.chip == null or not is_instance_valid(bar.chip) or int(bar.chip_color) != col:
		for c in (bar.chip_slot as Control).get_children():
			c.queue_free()
		# **尺寸取小片位自己的最小宽**（与下面名次徽章同一写法，批次 13 辛 复核 M1 修）：
		# 小片位是个**普通 `Control`**、不是容器 —— 它不会给小片分配尺寸，小片按自己的
		# `custom_minimum_size` 铺开。所以写死的 16 放进名册格那个 14 宽的位里会**出血 2 像素**、
		# 挤进 4 像素的格间距（③ 把名册格瘦到 14 之后才暴露出来的）。
		# 读位宽同时覆盖两种载体：四角身家条的位是 **18**、名册格是 **14** —— 不必再按 `is_self` 分叉
		#（两处 `chip_slot.custom_minimum_size` 都在 `table_hud` 里显式写死，见 `_make_corner_bar`
		# / `_make_roster_row`）。
		var csz: int = int((bar.chip_slot as Control).custom_minimum_size.x)
		bar.chip = UIKit.chip(GameData.PLAYER_COLORS[clampi(col, 0, 3)], csz)
		(bar.chip_slot as Control).add_child(bar.chip)
		bar.chip_color = col
	# 名次徽章（批次 13 ② 起**两处都有**：我那条 24、名册格 20 —— 尺寸取徽章位自己的最小宽）：
	# 1 金 / 2 银 / 3 铜 / 其余石板灰（真变了才重建）
	var rank := int(e.get("rank", 0))
	bar["rank"] = rank
	if bar.get("badge_slot") != null and int(bar.badge_rank) != rank:
		for c in (bar.badge_slot as Control).get_children():
			c.queue_free()
		var bsz: int = int((bar.badge_slot as Control).custom_minimum_size.x)
		bar.badge = UIKit.rank_badge(rank, maxi(bsz, 16))
		(bar.badge_slot as Control).add_child(bar.badge)
		bar.badge_rank = rank
	# 名字（「我」那条标「我」、破产标「破产」）；轮到谁行动谁的名字变金
	var active: bool = phase == "playing" and peer == turn_peer and alive
	var tags := ""
	if is_self and peer == my_peer:
		tags += "（我）"
	if not alive:
		tags += "（破产）"
	var name_l: Label = bar.name_l
	name_l.text = "%s%s" % [String(e.get("name", "?")), tags]
	name_l.add_theme_color_override("font_color",
		UIKit.TEXT_DIM if not alive else (UIKit.ACCENT if active else UIKit.TEXT))
	# 身家（名次的依据）；破产与座位卡同款提示：不报数字。
	# **批次 13 ② 起名册条那一格没有这一行**（瘦身成"名次 + 小人 + 昵称"）⇒ 按 `bar.get` 守卫，
	# 与下面 `money_l` 同一写法。名次徽章两处都有（`badge_slot` 各自建）。
	if bar.get("worth_l") != null:
		var worth_l: Label = bar.worth_l
		worth_l.text = "已出局" if not alive else GameData.fmt_money(int(e.worth))
		worth_l.add_theme_color_override("font_color",
			UIKit.TEXT_DIM if not alive else UIKit.ACCENT)
	# 现金（B，只有「我」那条有这一行）：身家是「现金 + 地产」，决定买卖 / 付租的是这一行。
	# 破产那家没有现金可言，留空（**不隐藏控件** —— 藏了会把这一条的内容高度改掉）。
	if bar.get("money_l") != null:
		(bar.money_l as Label).text = "" if not alive \
			else "现金 %s" % GameData.fmt_money(int(e.get("money", 0)))
	# 轮到谁行动：那一条描金边（与这一条上的倒计时是同一件事）。
	# 只在真变化时换样式盒（每次换都是一次九宫格纹理查找）。样式本身走**同一个**合成函数
	#（`_apply_corner_style`）—— "本条正亮着（可选中）"也带进条件：行动者一变、而本条又亮着时，
	# 必须重贴（否则会绕过合成、把高亮那张盖掉）。
	var hot: bool = bool(bar.get("hot", false))
	if bool(bar.border_active) != active or hot:
		bar.border_active = active
		_apply_corner_style(bar, active, hot)

## 「我」那条身家条上的**能力行**（批次 12 D1）：读数 + 一排点亮/熄灭的小格。
## 视觉语言与玩家道具弹窗（`player_popup._fill` 那排小格）**同一套**（亮金 / 熄灭 + 圆角），
## 只小一号；数据同样取已同步的 `st`（`_state_player` + `_stamina_cap`，客户端也准）。
## 小格只在**上限真的变了**（`充电宝` 进出背包）时重建 —— 6 个小格每次广播重建一遍不值得。
func _refresh_my_energy(bar: Dictionary, peer: int) -> void:
	var p := _state_player(peer)
	if p.is_empty():
		return
	var cap := maxi(_stamina_cap(p), 0)
	var cur := clampi(int(p.get("stamina", 0)), 0, cap)
	(bar.energy_l as Label).text = "能量 %d" % cur
	if int(bar.get("pip_cap", -1)) != cap:
		var box: Control = bar.pip_box
		for c in box.get_children():
			c.queue_free()
		var pips: Array = []
		for i in cap:
			var pip := Panel.new()
			pip.custom_minimum_size = Vector2(12, 12)
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(pip)
			pips.append(pip)
		bar.pips = pips
		bar.pip_cap = cap
	for i in (bar.pips as Array).size():
		var lit: bool = i < cur
		(bar.pips[i] as Panel).add_theme_stylebox_override("panel", UIKit.stylebox(
			Color(0.95, 0.78, 0.35) if lit else Color(0.22, 0.20, 0.18),
			4, Color(0, 0, 0, 0.4), 1))

## 名册条（批次 12 D1 建；**批次 13 ② 搬左上角「暂停」旁；批次 13 辛 ③ 改横排**）：其余玩家一格一位，
## 按 `standing` 的顺序（身家倒序 = 名次）**自左往右**排 —— 用户 ② 要的就是"排列顺序根据排名实时变化"，
## 所以**这一份顺序一个字都不用改**，搬位 / 改朝向顺手就拿到了实时排序。
##
## 格数按需增删（人少了把多出来的格**藏起来**、不拆节点，同四角条那套）；
## 条宽/条高（右边缘 / 下边缘）取**容器自己算的那份**，左边缘固定在 `ROSTER_X`。
## 格内容走 `_fill_peer_bar(..., is_self = false)`：与「我」那条同一个填法。
func _refresh_roster(standing: Array, mine_peer: int, turn_peer: int, phase: String) -> void:
	if roster_strip == null or not is_instance_valid(roster_strip):
		return
	var others: Array = []
	for e in standing:
		if int(e.peer) != mine_peer:
			others.append(e)
	while roster_strip_rows.size() < others.size():
		roster_strip_rows.append(TableHud._make_roster_row(self, roster_strip))
	for i in roster_strip_rows.size():
		var row: Dictionary = roster_strip_rows[i]
		var root: Control = row.root
		if i >= others.size():
			root.visible = false                  # 人少了：多出来的行藏起来
			row.peer = GameData.NO_PEER
			root.set_meta("peer", GameData.NO_PEER)
			continue
		root.visible = true
		_fill_peer_bar(row, others[i], turn_peer, phase, false)
	# 落位（**批次 13 ② 起条锚在 TOP_LEFT**；**批次 13 辛 ③ 起是横排，所以"宽"才是要盯的量**）：
	# 左边缘固定在 `ROSTER_X`（暂停按钮右侧），宽/高取**容器自己算的那份**
	#（`get_combined_minimum_size()`：格是内容驱动的宽度，自己按"格数 × 固定格宽"手算会与真实
	# 宽度对不上 —— 实测踩过）。**这一段对横排 / 竖排都成立**（容器给的就是各自朝向的那一份），
	# 所以③改朝向时这里一个字都没改。
	# **夹一道屏幕中线**：名册条整条只许待在左半 —— 横排之后这条比竖排时代更要紧，
	# 免得昵称一长就把右边缘推进居中的横幅 / 气泡里。
	roster_strip.offset_left = TableHud.ROSTER_X
	var strip_min: Vector2 = roster_strip.get_combined_minimum_size()
	var left_limit: float = maxf(TableHud.ROSTER_X + 120.0, size.x * 0.5 - 20.0)
	roster_strip.offset_right = minf(TableHud.ROSTER_X + strip_min.x, left_limit)
	roster_strip.offset_bottom = TableHud.ROSTER_Y + strip_min.y

## 高亮 / 倒计时共用的**条 + 行**清单（批次 12 D1）：「我」那条 + 名册条的每一行。
## **别把它们分别遍历** —— "谁亮着"（`_hl_peers`）与"倒计时挂谁"（`_op_owner`）各只有一份判据，
## 两处刷新函数对着同一份清单贴，才不会出现"四角条时代能亮、搬到名册条之后亮不了"这类分叉。
func _hl_bars() -> Array:
	var out: Array = []
	for b in corner_bars:
		out.append(b)
	for r in roster_strip_rows:
		out.append(r)
	return out

## 把「此刻可被选中的玩家」（`_hl_peers`）那份高亮贴到**条与名册行**上 —— **每次状态广播末尾重放一遍**。
##
## **为什么单独一个函数、不塞进 `_refresh_corner_bars`**：那个函数有签名缓存（状态没变就早退），
## 而"只变高亮"的广播（`_push_peer_highlight` 不伴随状态变化）会在那里被早退掉；并且广播会重排名册，
## 只贴"变化的那一次"会漏。所以留一处独立落点、每次广播都重放。
##
## 条根 `STOP` 只让"点它"这件事成立（`_on_corner_bar_clicked`），"哪条亮着"由这里贴：
## **2px 金边 + 底色提亮**，与行动者的 1px 金边分得开（两件事合成在同一张样式盒里，
## 见 `_apply_corner_style`）。**批次 12 D1 起清单是 `_hl_bars()`（我那条 + 名册每一行）** ——
## 选目标的落点就是这么从四角条搬到名册条上的，判据（`_hl_peers`）一个字没动。
##
## `bar["hot"]` 是这一条的**样式缓存位**（"现在贴的是不是高亮那张"）：常态早退省一次九宫格
## 纹理查找，而**点亮那一次一定重贴**（条件里带了 `not hot`）。
func _refresh_corner_highlight() -> void:
	for b in _hl_bars():
		var bar: Dictionary = b
		var root: Control = bar.root
		if root == null or not is_instance_valid(root):
			continue
		var hot: bool = _hl_peers.has(int(bar.get("peer", GameData.NO_PEER)))
		if bool(bar.get("hot", false)) == hot and not hot:
			continue                     # 常态早退；点亮那一次一定重贴
		bar["hot"] = hot
		_apply_corner_style(bar, bool(bar.get("border_active", false)), hot)

## 一条身家条 / 一个名册行的样式（行动者 / 可选中两件事合成一张样式盒）。
## 行动者 = 1px 金边；**可选中 = 2px 金边 + 底色提亮一档**（两者可叠加：选中态若正好轮到 TA 行动，
## 就是 2px 金边 + 提亮）。
## **两处调用共用这一份**（`_refresh_corner_bars` 的"行动者变了"与 `_refresh_corner_highlight`
## 的"亮/灭变了"）—— 样式只有一处，免得两边各贴一套、互相盖掉。
func _apply_corner_style(bar: Dictionary, active: bool, hot: bool) -> void:
	var root: Control = bar.root
	var bg := Color(0.085, 0.095, 0.138, 0.82)
	if hot:
		bg = bg.lightened(0.10)
	var border := Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.7)
	var bw := 1
	if hot or active:
		border = Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.9)
	if hot:
		bw = 2
	var sb: StyleBoxTexture = UIKit.card_stylebox(bg, 10, border, bw, 4)
	# 名册格比四角身家条矮一档 ⇒ 它那张卡片的**上下**内边距要跟着收（见 `table_hud.ROSTER_CARD_PAD`）。
	# **这一笔不能少**：本函数每次都新造一张样式盒换上去，不贴回去那一格就弹回默认的 8+8
	#（高 42 → 52），而**只有"行动者变了 / 亮灭变了"的那些格才会走到这里** ⇒
	# 同一排的格会一半 42 一半 52、名册条一开一合。判据走 `bar` 上那一位 `slim_pad`
	#（`table_hud._make_roster_row` 建的格才有；四角身家条没有 ⇒ 保持默认）。
	if bool(bar.get("slim_pad", false)):
		TableHud.slim_card_pad(sb)
	root.add_theme_stylebox_override("panel", sb)

func _refresh_actions() -> void:
	var await_state := String(st.get("await", ""))
	var is_my_roll := await_state == "roll" and int(st.get("turn", -1)) == my_peer
	_refresh_action_button()
	# 「轮到你转盘了」——原来这里写底栏状态条文案并顺手把镜头对回自己。底栏已随批次 3
	# Task 6 取消：**状态文案这一层信息没有了**（见 doc/development/架构总览.md §五），
	# 「该你了」改由右下角动作按钮的点亮与身家条 / 名册行上的操作倒计时承担，发生过的事由战报承担。
	# 镜头对焦这半与文字无关，保留。
	if await_state == "roll" and is_my_roll:
		if not board.is_wheel_spinning() and not board.is_rotating():
			board.focus_peer(my_peer)
	# 自动化测试：轮到自己时自动掷骰（用 roll_epoch 区分连掷的新请求）
	if at_mode != "" and is_my_roll and int(st.get("roll_epoch", -1)) != _at_roll_epoch:
		_at_roll_epoch = int(st.get("roll_epoch", -1))
		_at_auto_roll()

## 自动回归：等「确定」按钮亮出来之后点一下（与 `_at_auto_roll` 同类，只是触发源是演出相位）。
func _at_auto_card_confirm() -> void:
	await get_tree().create_timer(0.4).timeout
	if not is_inside_tree():
		return
	if deck_reveal != null and is_instance_valid(deck_reveal) and deck_reveal.is_confirm_visible():
		_on_card_confirm()

## 右下角动作按钮的状态（唯一来源是 st，客户端也准）：每次状态广播推一遍。
##
## 三态（见 批次7-设计 §5.2）：
##   * 轮到我掷轮   → 「转动转盘」（primary，点亮）
##   * 轮到我用道具 → 「结束回合」（normal）
##   * 其余         → 整枚隐藏
## "其余"含「我掷完、正在移动与落地结算」那段（await==""）—— 那一段没有可做的操作，
## 显示一枚禁用的「转动转盘」会让玩家以为还能再掷。
func _refresh_action_button() -> void:
	var await_state := String(st.get("await", ""))
	# 非道具阶段 → 收掉选中态与未完成的选目标态。**这一段是从 _refresh_item_buttons 顶部搬来的**
	# （那个函数随按钮退场整段删掉，但这条清理不能丢）：道具阶段**超时**结束时 `_tgt_stage` 会挂着，
	# 没有这一笔，选目标提示与牌上那点高亮会一直亮到下个回合。
	# **必须排在下面那道 `action_btn == null` 早退之前**：清理与按钮无关（原来 `_refresh_item_buttons`
	# 守的是 `board`、不是按钮），早退只护后面的按钮写入 —— 否则按钮一旦不存在，这条清理会静默消失。
	var using: bool = await_state == "item" and int(st.get("await_peer", -1)) == my_peer
	if not using and selected_slot >= 0:
		_clear_item_selection()
	if not using and _tgt_stage != "":
		_cancel_target()
	if action_btn == null or not is_instance_valid(action_btn):
		return
	var phase := String(st.get("phase", ""))
	var my_roll: bool = phase == "playing" and await_state == "roll" \
		and int(st.get("turn", -1)) == my_peer
	var my_item: bool = phase == "playing" and await_state == "item" \
		and int(st.get("await_peer", -1)) == my_peer
	# 我有待决的买地/装修（批次 12 C1）：面板可以被 ✕ 关掉，忘了就白亏一次机会 ⇒
	# 这枚按钮改文案「回格上决定」兜住"忘了"，点它把面板重新弹到那一格上。
	# 判据与 `_pending_tile_for_me` 同源（这里从 st 读，房主/客户端一致）。
	var my_prompt: bool = phase == "playing" and await_state == "prompt" \
		and int(st.get("await_peer", -1)) == my_peer
	action_btn.visible = my_roll or my_item or my_prompt
	if my_roll:
		action_btn.text = "转动转盘"
		UIKit.restyle_button(action_btn, "primary")
	elif my_item:
		action_btn.text = "结束回合"
		UIKit.restyle_button(action_btn, "normal")
	elif my_prompt:
		action_btn.text = "回格上决定"
		UIKit.restyle_button(action_btn, "primary")

## 右下角动作按钮的唯一后果函数（文案与状态由 _refresh_action_button 决定）。
## 只有"我的掷轮窗口 / 我的道具窗口 / 我的待决买地装修"三次点击会做事，其余一律空转。
func _on_action_pressed() -> void:
	match String(st.get("await", "")):
		"roll":
			_on_roll_pressed()
		"item":
			_on_skip_pressed()
		"prompt":
			_reopen_decision_panel()

## 「回格上决定」：把待决那格的详情卡（含决策区）重新弹出来。
## 展开着的规则说明面板与格详情卡抢同一块地方，先收掉它（否则面板会"点了没反应"）。
func _reopen_decision_panel() -> void:
	var tile := _pending_tile_for_me()
	if tile < 0:
		return
	if rules_open:
		_set_rules_open(false)
	_show_info_panel(tile)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_F1:
			dev.toggle()
		elif k.keycode == KEY_ESCAPE and (_tgt_stage != "" or selected_slot >= 0):
			_cancel_target()   # 选目标态或「选中了一张牌」都算可取消的状态
		elif k.keycode == KEY_ESCAPE and player_popup != null and player_popup.is_open():
			# 批次 9：Esc 关道具弹窗。**排在"选目标态"之后** —— 选目标态优先（那时不该有弹窗，
			# 真有也不是当前这一步要取消的东西）。
			player_popup.close()

func _toggle_log() -> void:
	_set_log_open(not log_panel.visible)

## 展开/收起战报栏（批次 13 ① 从 `_toggle_log` 里抽出来，好让规则面板那边也能调）。
## **与「规则说明」面板互斥**：两者自批次 13 ① 起同在右上角、占同一块地方 ——
## 展开战报先收规则；`_set_rules_open` 那边对称地收战报。两边都只调对方那个"关"分支，
## 不构成递归。
func _set_log_open(on: bool) -> void:
	if log_panel == null:
		return
	if on and rules_open:
		_set_rules_open(false)
	log_panel.visible = on
	log_toggle.text = "战报 ▴" if on else "战报 ▾"

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
	_show_info_panel(idx)

## 把某一格的详情填进格详情卡并弹出来。**批次 12 C1 从 `_on_tile_clicked` 里原样抽出来** ——
## 待决的买地/装修要能自己把这张卡叫回来（✕ 关掉不算放弃，再点该格 / 点右下角
## 「回格上决定」都走这一条），所以它不能再是点击处理器里的一段。
func _show_info_panel(idx: int) -> void:
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
		"item":
			accent = ItemData.QUALITY_COLORS["紫"]
		"again":
			accent = ItemData.QUALITY_COLORS["橙"]
	info_title.text = "【%s】" % String(d.name)
	info_title.add_theme_color_override("font_color", accent)
	info_body.text = body
	info_sb.border_color = Color(accent.r, accent.g, accent.b, 0.7)
	info_panel.add_theme_stylebox_override("panel", info_sb)
	# 规则说明展开时占着右上角（批次 13 ① 起面板也在右上），格详情卡让位（见 _set_rules_open）
	_info_tile = idx
	info_panel.visible = not rules_open
	# 面板尺寸随「决策区」一起变（有决策时更高），所以位置要**先填完内容再摆**：
	# 这里 `_refresh_decision_area` 会改高度，紧接着 `_place_info_panel` 按新高度锚上去。
	_refresh_decision_area()
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

## 购买/升级询问（**批次 12 C1：改成格详情卡上的决策区**）。
##
## 不再是屏幕居中的模态弹窗：`_arm_decision` 把问题交给 `info_panel` 里的决策区，
## 面板由 `_place_info_panel` 锚在**那一格的上方**。旧的居中弹窗（`_prompt_dlg` 那套）已删净 ——
## 不留第二条路径。倒计时 / 超时 / 托管的语义一字未改（都在 `_await_turn_window("prompt", …)`）。
func _show_prompt(token: int, title: String, text: String, ok_text: String) -> void:
	if at_mode != "":
		await get_tree().create_timer(0.3).timeout
		_answer(token, true)
		return
	_arm_decision(token, _pending_tile_for_me(), title, text, ok_text)

## 把「待决」摆到格详情卡上：填内容 + 弹出该格的面板（决策区随之显出来）。
## 房主侧由 `_ask` 调（格号来自 `_prompt_tile`）；客户端由 `s_prompt` 调（格号从快照推）。
func _arm_decision(token: int, tile: int, title: String, text: String, ok_text: String) -> void:
	_close_prompt()
	_prompt_token = token
	if tile >= 0:
		_prompt_tile = tile
	if decision_area != null and is_instance_valid(decision_area):
		decision_title.text = title
		decision_text.text = text
		decision_ok.text = ok_text
	if tile >= 0:
		_show_info_panel(tile)   # 填详情 + `_refresh_decision_area` + 锚到该格上方
	else:
		_refresh_decision_area()
	_prompt_bar_arm(token, GameSettings.turn_seconds(_settings.timeout_tier, "prompt"))

## 决策区该不该露面：**我有待决、且面板正挂着那一格**。
func _refresh_decision_area() -> void:
	if decision_area == null or not is_instance_valid(decision_area):
		return
	decision_area.visible = _prompt_token != -1 and _info_tile >= 0 \
		and _info_tile == _pending_tile_for_me()

## 本机玩家此刻待决的是哪一格（没有则 -1）。
## 客户端没有房主私有变量，就从快照推（见 `_prompt_tile` 那段说明）。
func _pending_tile_for_me() -> int:
	if multiplayer.is_server():
		return _prompt_tile if _awaiting_prompt == my_peer else -1
	if String(st.get("await", "")) != "prompt" or int(st.get("await_peer", -1)) != my_peer:
		return -1
	return int(_state_player(my_peer).get("pos", -1))

## 决策区里的两枚按钮（唯一的后果函数）。**点完就把决策区收起**，与旧弹窗的按钮一致。
func _on_decision_yes() -> void:
	if _prompt_token == -1:
		return
	_answer(_prompt_token, true)
	_close_prompt()

func _on_decision_no() -> void:
	if _prompt_token == -1:
		return
	_answer(_prompt_token, false)
	_close_prompt()

## 收起决策区（答了 / 超时 / 窗口关掉都走它）。**注意它与「关掉面板」是两回事**：
## ✕ 只把 `info_panel.visible` 置假（见 table_hud 的关闭按钮），决策本身照旧在走 ——
## 这正是设计 §③ 的「关闭 = 暂缓，不是放弃」。倒计时条的补间挂在面板之外，照跑不误。
func _close_prompt() -> void:
	if _prompt_tw != null and _prompt_tw.is_valid():
		_prompt_tw.kill()
	_prompt_tw = null
	if decision_area != null and is_instance_valid(decision_area):
		decision_area.visible = false
	_prompt_token = -1
	_prompt_tile = -1

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
	var ab_cut := _ab_move_cut(p)
	if ab_cut > 0:
		s = maxi(0, s - ab_cut)
		_log("【隔离】%s 的移动点数 −%d" % [p.name, ab_cut], "#c9a6ff")
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

## 按权重表抽品质（小卖部补货用 SHOP_WEIGHTS，失物招领格用 FIND_WEIGHTS）
func _roll_quality(weights: Dictionary = ItemData.SHOP_WEIGHTS) -> String:
	var total := 0
	for q in weights:
		total += int(weights[q])
	var r := randi_range(0, maxi(total - 1, 0))
	for q in weights:
		r -= int(weights[q])
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
	if _ab_has("限电") and not _immune_debuff(p):
		_log("【限电】%s 本回合体力没有回复" % p.name, "#c9a6ff")
	elif int(p.get("stamina", 3)) >= cap:
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
	if _ab_has("奖学金季"):
		p.money = int(p.money) + 300
		_log("【奖学金季】%s 领到 %s 补贴" % [p.name, GameData.fmt_money(300)], "#74d188")
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
		# 批次 13 T6：机器人访客不像真人——真人会停在店里等操作，机器人却在 `_bot_shop` 里
		# 一路同步买完就走，于是「进店」那份快照会被同一帧里「店已关」的那份盖掉，
		# 任何一端的 `_process` 都来不及把 `shop_layer` 显出来 ⇒ 机器人进店对所有人不可见。
		# 先给一个看得见的节拍，再让它动手。
		await _wait(1.5)
		# 节拍期间会话可能已被换掉（超时/换人）或整局已停：照 `_arm_shop_timeout` 的同一套判据守卫，
		# 免得替一个已经不在店里的 peer 买东西。
		if running and _shop_peer == int(p.peer) and _shop_epoch == epoch:
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

## 选中一件道具（玩法侧入口，唯一）：写 selected_slot 并把**表现侧**一起同步。
##
## 表现侧有两处，必须都在这一个函数里做：① 桌上手牌抬起 + 提亮（`table_props.set_hand_selected`）；
## ② 待确认丢弃的红标清掉（选中任何一张 = 撤回待丢弃）。**不留给调用点** —— 原先那行
## `set_hand_selected` 补在唯一调用点（`_on_hand_clicked`），将来任何新入口（如批次 9 的四角条）都会
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
	# 任意道具都可选中（被动也能选中以丢弃）；能不能用由 _on_use_pressed 的分派判定
	#（批次 7 起选中与出牌是同一次点击，这里仍只负责「写入选中」这一步）
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
		return          # 直出之后这里恒不成立（本函数只在选中之后被调）；留着当守卫
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

## 把「此刻可被选中的玩家」高亮**一次推给两处**：
##   * 画布（`board.set_select_peers` —— 座位卡的金框，座位卡随批次 5 Task 2 退场后它空转、接口保留）；
##   * **身家条 / 名册行**（`_refresh_corner_highlight`，批次 9 补的可见反馈；亮着 = 能点；
##     批次 12 D 起他人那一格是名册条的一格；**批次 13 ② 起那条在左上角**）。
##
## **判据只有一份**：可选玩家由调用方（`_begin_peer_target`）算出，本函数只做转发 ——
## 于是"哪几条亮着"与"点谁真的有反应"（`_on_corner_bar_clicked` → `_on_seat_clicked` 第一行）永远同源。
## 传空数组 = 全部熄灭；换阶段（peer → tile）与取消都走它。
##
## 批次 9：立牌退场，原先"推给立牌"那一路随之删掉；高亮改画在屏幕层的条上（批次 12 D 起
## 他人那一格在名册条上（**批次 13 ② 起在左上角「暂停」旁**），见
## `_refresh_corner_highlight`）。`_hl_peers` 是这份高亮的**单一来源**（广播末尾按它重放）。
func _push_peer_highlight(peers: Array) -> void:
	if board != null:
		board.set_select_peers(peers)
	_hl_peers = []
	for p in peers:
		_hl_peers.append(int(p))
	_refresh_corner_highlight()

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
	# 入口是**屏幕左上角名册条里对手那一格**（落点史：桌上立牌（批次 5）→ 屏幕四角条（批次 9）
	# → 顶部名册条右上（批次 12 D）→ **名册条左上角、暂停按钮旁（批次 13 ②）**）——
	# 与规则说明（`rules_text.gd` 基础操作页）同源口径，
	# 别再说"立牌 / 玩家卡 / 四角条"（玩家会照着找一样已经不存在的东西）。
	_show_target_hint("点左上角名册条里对手那一格选择目标" + ("（Esc/右键取消）" if not then_prop else "（再点他的一块地）"))
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
	# 直接进选格态（快递直达）：那份"可选玩家"高亮一并熄灭（同 board 的 set_select_tiles）
	_push_peer_highlight([])
	if board != null:
		board.set_select_tiles(arr)

## 点身家条 / 名册行的唯一后果函数（批次 9）。**入口在 `table_hud._make_corner_bar` 与
## `_make_roster_row` 的 `gui_input`**
##（条根 `mouse_filter = STOP`，回调里现读 `root` 的 meta 得 peer）。
##   * 选目标态下 → 走**既有的** `_on_seat_clicked`（它自己判"是不是可选目标"，非目标静默 no-op）；
##     **不开弹窗**（选目标途中弹一个模态会互相打架）。
##   * 平时 → 打开该玩家的道具弹窗。
func _on_corner_bar_clicked(peer: int) -> void:
	if peer == GameData.NO_PEER:
		return
	if _tgt_stage == "peer":
		_on_seat_clicked(peer)
		return
	_open_player_popup(peer)

## 开某玩家的道具弹窗（数据在这里**一处**组装；单一来源仍是已同步的 st / _state_*）。
## 取不到这个人（peer 不存在 / 已离场）就什么都不做 —— 不发请求、不崩。
##
## **两个上限是两件事，各有各的键、别合并**（批次 13 ⑤ 修复）：
##   * `"cap"` = **体力上限**（`_stamina_cap`：基础 5、带「充电宝」6）—— 画的是「能量」那排小格；
##   * `"bag_cap"` = **背包上限**（`_bag_cap`：基础 5、带「置物架」**7**）—— 决定背包区画几个槽位。
## 曾经两处都读 `"cap"`（= 体力上限）⇒ 带「充电宝」的人看到 6 个槽位（规则上限是 5）、
## 带「置物架」的人只看到 5 个槽位（本该 7），正是用户 ⑤ 要"一眼看出还能装几张"的反面。
func _open_player_popup(peer: int) -> void:
	if player_popup == null:
		return
	var p := _state_player(peer)
	if p.is_empty():
		return
	player_popup.open(peer, {
		"name": String(p.get("name", "?")), "worth": _state_worth(peer),
		"money": int(p.get("money", 0)), "stamina": int(p.get("stamina", 0)),
		"cap": _stamina_cap(p), "bag_cap": _bag_cap(p),
		"alive": bool(p.get("alive", true)),
		"color_idx": int(p.get("color", 0)), "rank": _rank_of(peer),
		"items": p.get("items", []),
	})

## 某玩家的名次（`standing` 里的 rank；查不到给 0 = 不画徽章）。
## 批次 12 D1 起读 `_standing_by_peer` **那张表**，不再回头去条里翻：四角条只剩「我」一条之后，
## 从条里翻只查得到自己 ⇒ 道具弹窗里别人的名次徽章会集体消失。
func _rank_of(peer: int) -> int:
	return int((_standing_by_peer.get(peer, {}) as Dictionary).get("rank", 0))

## 选玩家完成。批次 9 起入口是**屏幕层的条**（`_on_corner_bar_clicked` 转到这儿；批次 12 D 起
## 他人那一格在名册条上（**批次 13 ② 起在左上角「暂停」旁**））；
## 座位卡与立牌都已退场，这里只是后果函数。
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
			# 从"选玩家"走进"选地块"：那份可选玩家高亮随之熄灭（同 board 的 set_select_tiles）
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
	# 选中态与「选目标态」是两件事：点手中的牌 = 选中并**紧接着**用掉（批次 7 起直出），
	# 但选中态本身仍由 `_on_item_slot_clicked` 单独维护，所以取消要把两者一起收回 ——
	# 只清 _tgt_stage 的话，桌上一张牌可能一直抬着（Esc / 右键这两条取消路径正是这么来的）。
	_clear_item_selection()
	if _tgt_stage == "":
		return
	_tgt_slot = -1
	_tgt_stage = ""
	_tgt_peer = -1
	_tgt_tiles = []
	if target_hint != null:
		target_hint.visible = false
	# 可选玩家高亮随选目标态一起熄灭（与 board.clear_select 同一处收口）
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

# ================= 规则说明面板（右上角） =================

## 展开/收起规则说明。**批次 13 ①**：面板与「战报」栏同在右上角 ⇒ 两者**互斥**
##（展开规则先收战报，见下）；格子详情卡仍然让位（隐藏）——它悬浮在被点格子上方，
## 右上角那几格仍会与面板重叠；收起后格详情卡照常弹出。
##
## **批次 13 辛 ①**：`rules_btn` **恒可见**（去掉了原先的 `rules_btn.visible = not on`）。
## 用户的原话是「弹窗规则说明弹窗时，『规则说明』按钮不要消失」—— 按钮是**切换开关**，
## 藏起来就等于把"用同一枚按钮收起"这条路掐断了；`rules_panel.gd` 那边同步把回调改成
## `_set_rules_open(not rules_open)`。面板自带的那枚「收起 ▾」是**第二条路**，两条都保留。
## 位置上两者本就不打架：按钮在 y 12..40、面板从 y 52 起。
func _set_rules_open(on: bool) -> void:
	if rules_open == on:
		return
	rules_open = on
	rules_panel.visible = on
	if on:
		info_panel.visible = false
		# ① 与战报栏互斥：两者占右上同一块地方，同时开会叠。
		if log_panel != null and log_panel.visible:
			_set_log_open(false)
		# 自右上角向下「长出来」：缩放支点在右上角（构建时已设，这里兜底重算）
		rules_panel.pivot_offset = Vector2(rules_panel.size.x, 0.0)
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

## 某玩家的身家条 / 名册行在**屏幕**上的中心（查不到或那一条此刻不可见 ⇒ `null`）。
## 收租 / 付租的飞钞终点：批次 9 起立牌退场，终点从天上的立牌牌心换成屏幕层的条；
## 批次 12 D1 起"别人"那一条变成了名册条的一行（`_hl_bars` 一并查，别只查 `corner_bars` ——
## 只查它的话，别人的飞钞终点会全部退回棋子那一点）。调用方保持"拿不到就退回棋子"的既有降级。
func _corner_bar_screen_center(peer: int) -> Variant:
	for b in _hl_bars():
		var bar: Dictionary = b
		var root: Control = bar.root
		if root == null or not is_instance_valid(root):
			continue
		if not root.visible or int(bar.get("peer", GameData.NO_PEER)) != peer:
			continue
		return root.get_global_rect().get_center()
	return null

## 飞钞：金额变动时账单在棋子与**那个人那一条身家条 / 名册行**之间飞（Monopoly GO 式收支反馈）。
##
## 座位卡已随批次 5 Task 2 退场、立牌随批次 9 退场：落点（原来传进来的金额 Label）
## 换成屏幕层那一条的中心（`_corner_bar_screen_center`）。拿不到（那条不可见）时退回棋子那一点，
## 只影响飞钞的终点、不改变"金额变了才飞"的判据。
func _spawn_money_fly(peer: int, diff: int) -> void:
	var good := diff > 0
	var token_at := _token_screen_pos(peer, int(_state_player(peer).get("pos", -1))) + Vector2(0, -18)
	var card_at := token_at
	var sp = _corner_bar_screen_center(peer)
	if sp != null:
		card_at = sp as Vector2
	# **测试观测点**（批次 13 ⑥）：记下这一位这一帧用的终点，供 `hud_test` 钉住"终点是当帧
	# 那一行"（读的是 `_refresh_corner_bars` 刷完之后的绑定，不是上一次广播的）。
	_money_fly_goal[peer] = card_at
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
	_place_token_tip()    # 悬停信息条同理（它跟着**棋子**走；悬停期间镜头也会动）
	# 待决格描一圈脉冲高亮（批次 12 C1）：决策面板可以被 ✕ 关掉，这圈高亮是
	# "我还有个没决定的事，就在那格"的第一眼提示；右下角那枚「回格上决定」是第二处兜底。
	# 传 -1 = 没有待决；`set_pending_tile` 自己按"变了才改"早退，逐帧调是免费的。
	if board != null:
		board.set_pending_tile(_pending_tile_for_me())
	# （原先这里有一段"抽卡演出期间逐帧重推跟图案的实体" —— 前提是抽卡会把 2D 取景推近。
	#  批次 8 把演出搬到屏幕层、相机全程不动 ⇒ 不再有逐帧的取景变化要跟，整段删掉。）
	# 批次 11 T1 起又回来了，但**换了判据**：自动跟随（`board._process` 的 `_pan_toward`）与
	# `focus_grid` 都会让 2D 取景逐帧动，而跟图案的实物只挂状态广播 ⇒ 镜头动了没广播时它们会脱开。
	# 这里按"取景键是否变过"补推；镜头静止时只比三个浮点数就早退（见 `_refresh_followers_if_cam_moved`）。
	_refresh_followers_if_cam_moved()
	# 屏幕底部原来还有一条固定操作坞（牌垫阶段条 + 操作条 + 底板）。批次 3 Task 6 把它
	# 整条拆了：掷轮改点桌面转盘、出牌改点手中牌（选中后点牌垫「使用道具」确认）、
	# 现金与体力在桌上。**注意这里不能留 `if <坞成员> == null: return` 之类的提前返回** ——
	# 那会把下面小卖部 / 黑市 / 操作倒计时 / 开发者面板整段静默打死（本任务真踩过这个坑，
	# hud_test 有对应的守卫断言）。
	var phase := String(st.get("phase", ""))
	# 交易面板独立于视角：保证行动者一定能操作（相机可能停在棋子上而非自家座位）
	# **批次 12 C2：小卖部改为全员可见** —— 门槛从"正在逛的是我"改成"有人正在逛"
	#（`shop_open >= 0`）。只有本人能操作：`_refresh_shop_ui` 按 `shop_peer` 把别人的按钮置灰，
	# 并给旁观者一条「XX 正在挑选」说明。
	var shop_open_now: bool = phase == "playing" and int(st.get("shop_open", -1)) >= 0 \
		and int(st.get("shop_peer", 0)) != 0
	shop_layer.visible = shop_open_now
	if shop_open_now:
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
	# 自动化测试：该我确认抽卡演出时自动点「确定」——**客户端那一侧的自动回归**，
	# 让 `c_card_ok` 真的走一趟回程（房主只代自己那张，见 `_await_card_confirm`）。
	# **必须挂在 `_process` 上、不能挂在 `_refresh_actions` 上**：抽卡窗口期间房主**不再广播
	# `s_state`**（只有 `s_op_timer` 按秒走），而「确定」按钮要等演出走到 CARD_TIME 才出镜 ——
	# 挂在状态广播上就永远等不到那一下（实测：客户端一直不确认，靠 25 秒超时收场）。
	if at_mode != "" and deck_reveal != null and is_instance_valid(deck_reveal):
		if deck_reveal.is_confirm_visible():
			if not _at_card_done:
				_at_card_done = true
				_at_auto_card_confirm()
		else:
			_at_card_done = false
	if dev.enabled:
		dev.refresh_panel()

## 操作倒计时（D 方案）：**只挂当前行动者那一块**（留痕 §四 的原设计：嵌在行动者的
## 座位卡里 —— 载体换过两次（立牌已于批次 9 退场），这条"只挂行动者"的语义一字未改）。
## 广播一秒一条，本机逐帧扣 delta 插值：暂停时 _process 不跑、计时随房主窗口一起冻结，
## Engine.time_scale（仅 autotest 会改）也天然对齐——这正是持续动画走 _process 相位的约定。
func _refresh_op_timer(delta: float) -> void:
	var show := _op_kind != ""
	if show:
		_op_left = maxf(_op_left - delta, 0.0)
	if show or _op_shown:
		var kind_text := String(OP_KIND_LABELS.get(_op_kind, _op_kind)) if show else ""
		# 小卖部全屏界面盖住整块棋盘，屏幕层的倒计时在里面看不见：同一份数据再推一份到面板
		if shop_layer != null and shop_layer.visible:
			_refresh_shop_timer(kind_text)
	_op_shown = show
	# 身家条 / 名册行那一份**每帧都贴**（不受上面那道 `show or _op_shown` 早退限制）：行序与
	# 行动者会随状态广播重排（`_refresh_corner_bars` 改 bar.peer），只贴"变化的那一次"会漏。
	_refresh_corner_timer()

## 身家条 / 名册行上的操作倒计时（批次 5 修复波 A）：把**当前行动者**那份倒计时镜像到 TA 那一条上。
##
## **为什么必须有这一条**：立牌已于批次 9 退场 ⇒ 本条现在是倒计时在屏幕层的唯一落点。
## 它在 3D / 2D 两端都常驻（比立牌稳），自己的回合在 3D 端也看得到还剩几秒
##（批次 4 时它在座位卡上，3D 端看得见）。
## **批次 12 D 起清单是 `_hl_bars()`**：行动者是我 ⇒ 落在左下角我自己那条；
## 是别人 ⇒ 落在名册条 TA 那一格（**批次 13 ② 起在左上角「暂停」旁**）。
##
## **不另立计时**：数据就是 `_op_*` 这同一份（广播重置 + 本机逐帧扣 delta 的那个插值）。
## 暂停时 `_process` 不跑 ⇒ 这里也不会被调用 ⇒ 与房主窗口一起冻结，**同一条暂停语义**。
##
## 形态：环节名 + 细进度条 + 剩余秒数，**只出现在 `_op_owner` 那一条上**（其余各条内容收起）；
## 没有操作窗口时所有条的倒计时内容一律收起。`_op_total <= 0`（黑市那种不限时）= 仍写环节名，
## 但**不写秒数、不画进度条** —— 与小卖部面板那份逐条对齐（同一口径）。
func _refresh_corner_timer() -> void:
	if _hl_bars().is_empty():
		return
	var show := _op_kind != ""
	var timed := show and _op_total > 0.0
	var kind_text := String(OP_KIND_LABELS.get(_op_kind, _op_kind)) if show else ""
	var warn: bool = timed and _op_left <= 5.0
	for b in _hl_bars():
		var bar: Dictionary = b
		var on: bool = show and int(bar.peer) == _op_owner
		# 只切**行内内容**的显隐：行本身常驻占位（`table_hud.CORNER_TIMER_ROW_H`），
		# 否则行动者换人时那一条会一开一合（名册条上尤其明显）。
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
		# 颜色**只在真的变了**才写 override（同本函数下面「秒数只在文本变化时写」的先例）：
		# 这两个 `add_theme_color_override` 原先每帧都写一次 —— 本函数由 `_process` 逐帧调、
		# 而 override 会触发一次主题重算与重绘（行动者那一条每帧白跑两遍）。
		var want_kind_col: Color = UIKit.DANGER if warn else UIKit.ACCENT
		if kind_l.get_theme_color("font_color") != want_kind_col:
			kind_l.add_theme_color_override("font_color", want_kind_col)
		if not timed:
			continue
		var txt := "%d 秒" % ceili(maxf(_op_left, 0.0))
		if left_l.text != txt:
			left_l.text = txt
		var want_left_col: Color = UIKit.DANGER if warn else UIKit.TEXT
		if left_l.get_theme_color("font_color") != want_left_col:
			left_l.add_theme_color_override("font_color", want_left_col)
		# 进度条：左端固定、长度按剩余比例缩（底轨常驻、填充显式设宽度 —— 同小卖部那条）
		var fill: ColorRect = bar.timer_fill
		fill.size.x = maxf(track.size.x, 1.0) * clampf(_op_left / _op_total, 0.0, 1.0)

## 小卖部面板底部的倒计时：呈现口径与身家条 / 名册行上那条（原座位卡 / 立牌那条）逐条对齐。
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
## 批次 3 Task 6 拆除）；它只按屏幕居中，一旦右上角战报栏展开就会被压住，所以按它的实际几何夹位。
##
## **批次 13 ① 起不再为「规则说明」面板让位**：面板已从左下角搬到右上角、且与战报栏互斥 ⇒
## 它不再占屏幕底部那条带（原先那句 `rules_panel.offset_right + 10` 在新锚点下恒为负、
## 是个 no-op，留着会误导后来人，故删）。
func _dock_band() -> Vector2:
	var x0 := 14.0
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
	# 小卖部全员可见（批次 12 C2）：本人能买，别人只读 —— 按钮一律置灰 + 一条说明。
	var owner_peer := int(st.get("shop_peer", 0))
	var mine_shop := owner_peer == my_peer
	var mine: Dictionary = _state_player(my_peer)
	var money := int(mine.get("money", 0))
	var bag: Array = mine.get("items", [])
	# 黑卡还有次数时本次购买免费：不该因为现金不够而置灰
	var free_buy := false
	for it in bag:
		if String(it.id) == "黑卡" and int(it.get("charges", 0)) > 0:
			free_buy = true
	var refresh := int(st.get("refresh_price", 0))
	var sig := "%d|%s|%d|%d|%s|%d|%d|%d" % [open, str(slots), money, bag.size(),
		str(free_buy), refresh, owner_peer, my_peer]
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
		b.disabled = (not mine_shop) or bag.size() >= 5 or (not free_buy and money < price)
	if shop_tile_l != null:
		shop_tile_l.text = "第 %d 号店 · 刷新费随全场次数递增" % open
	if shop_money_l != null:
		# 现金变了签名就变（sig 里含 money），所以在这里刷就够了
		shop_money_l.text = "现金 %s" % GameData.fmt_money(money)
	if shop_refresh_btn != null:
		shop_refresh_btn.text = "刷新 · %s" % GameData.fmt_money(refresh)
		shop_refresh_btn.disabled = (not mine_shop) or money < refresh
	if shop_leave_btn != null:
		# 别人店里没有「离开」这一手：那是店主自己的动作（置灰防误点，房主侧还会再校验一次）
		shop_leave_btn.disabled = not mine_shop
	if shop_watch_l != null:
		shop_watch_l.visible = not mine_shop
		if not mine_shop:
			shop_watch_l.text = "%s 正在挑选…（你只能旁观，货架不可操作）" % _name_by_peer(owner_peer)

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

