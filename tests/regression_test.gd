extends SceneTree
## fix/v0.0.2 回归单测（对应审查发现的 CRITICAL）
##   -- 被踢/连接失败后 Net 残留 players，导致再加入房间永久卡「正在连接…」
##   -- 回合计数绑定 turn_i == 0，0 号位破产后 30 回合结算不可达
##   -- 客户端 hp 为空，道具栏读不到道具 → 真人无法使用道具
##   -- 小卖部「买」按钮创建时 visible=false 且再未开启 → 真人无法购买
## godot --headless --path . --script tests/regression_test.gd

var fails := 0
# --script 模式下 autoload 不能按全局名引用（编译期尚未注册），运行时从 root 取
var _net = null

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

func _fresh_tiles() -> Array:
	var out := []
	for i in GameData.TILES.size():
		out.append({"owner": GameData.NO_OWNER, "level": 0})
	return out

func _mk_player(peer: int, nm: String) -> Dictionary:
	return {"peer": peer, "name": nm, "color": peer - 1, "bot": false, "money": 1000,
		"pos": 0, "alive": true, "skip": 0, "stamina": 3, "items": [], "item_used": false,
		"cheat_roll": -1}

func _prop_idx(offset: int) -> int:
	var n := 0
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "property":
			if n == offset:
				return i
			n += 1
	return -1

func _shop_tile() -> int:
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "shop":
			return i
	return -1

func _run() -> void:
	seed(12345)
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(7793, 3) != OK:
		printerr("server create failed")
		quit(1)
		return
	var mp := MultiplayerAPI.create_default_interface()
	mp.multiplayer_peer = peer
	set_multiplayer(mp, "/root")
	# 看门狗：任何卡死 20s 强制退出
	create_timer(20.0).timeout.connect(func() -> void:
		printerr("REGRESSION TEST TIMEOUT")
		quit(1)
	)

	# 1) Net 残留：必须在实例化对局场景之前跑（对局 _ready 会连 Net 信号）
	_net = root.get_node_or_null("Net")
	if _net == null:
		printerr("  FAIL - 未找到 Net autoload")
		fails += 1
	else:
		_test_net_reset(_net)
	_test_lobby_rules(_net)
	_test_endpoint_format()
	_test_room_info_port()

	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.running = false  # 冻结主循环：本测试手动摆状态
	# 场景/脚本编译失败时成员是 null，后续断言里的表达式会先报错、根本走不到
	# _check，于是整轮「全过」——必须在这里显式拦下（见 fix/v0.0.2）
	if g.board == null or g.corner_bars.is_empty() or g.shop_layer == null:
		printerr("  FAIL - 对局场景未正确加载（脚本编译失败？）")
		print("REGRESSION TEST: SCENE LOAD FAILED")
		quit(1)
		return

	_test_round_counter(g)
	_test_client_item_bar(g)
	_test_shop_buttons(g)
	_test_authority_guards(g)
	_test_dead_player_items_return_to_pool(g)
	_test_roster_marks_disconnected_bots(g, _net)
	_test_card_sound_once(g)
	_test_item_card_cooling_flag()
	_test_view_rotation_removed(g)
	_test_tab_space_no_longer_rotates(g)
	_test_turn_ring_first_render(g)
	_test_ui_widgets_applied(g)
	_test_dev_panel(g)
	_test_hot_chain(g)
	_test_shop_refresh_full_shelf(g)
	_test_camera_window_resize(g)
	await _test_roll_button_off_home_view(g)
	await _test_targeting(g)
	await _test_new_items(g)

	# 掉线路径会触发换场景，放到最后
	var lobby = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(lobby)
	_test_conn_lost_unpauses(g, lobby)

	# 收尾：本测试自建的节点自己释放，否则退出时的 leak 警告会盖住结果
	lobby.free()
	g.free()

	if fails == 0:
		print("REGRESSION TEST: ALL PASS")
		quit(0)
	else:
		print("REGRESSION TEST: %d FAILURES" % fails)
		quit(1)

func _test_net_reset(net) -> void:
	print("== 被踢/连接失败后的重置（net.gd） ==")
	# 模拟「玩家曾在房间里」的残留状态
	net.players = [{"peer": 7, "name": "旧玩家", "color": 0, "bot": false, "ready": true}]
	net.chat_history = [{"name": "旧玩家", "text": "hi"}]
	net._reset_peer()
	_check(net.players.is_empty(), "重置后 players 清空")
	_check(net.chat_history.is_empty(), "重置后 chat_history 清空")

	# 行为层：重置后再加入新房间，必须触发 lobby_joined（否则主菜单永久卡住）
	net.is_host = false
	var fired := [0]
	net.lobby_joined.connect(func() -> void: fired[0] += 1)
	net.s_lobby("新房", [
		{"peer": 1, "name": "房主", "color": 0, "bot": false, "ready": true},
		{"peer": 9, "name": "我", "color": 1, "bot": false, "ready": false},
	])
	_check(fired[0] == 1, "重置后加入新房间会触发 lobby_joined（实得 %d 次）" % fired[0])

func _test_round_counter(g) -> void:
	print("== 回合计数（0 号位破产后仍应计轮） ==")
	g.hp = [_mk_player(1, "甲"), _mk_player(2, "乙"), _mk_player(3, "丙"), _mk_player(4, "丁")]
	g.turn_i = 0
	g.round_no = 0
	for i in 4:
		g._advance_turn()
	_check(g.round_no == 1, "四人各行动一次 = 一轮（实得 %d）" % g.round_no)

	# 0 号位破产：剩下三人各行动一次，仍应记满一轮
	g.hp[0].alive = false
	g.turn_i = 0
	g.round_no = 0
	for i in 3:
		g._advance_turn()
	_check(g.round_no == 1, "0 号位破产后三人一圈仍记一轮（实得 %d）" % g.round_no)

func _test_client_item_bar(g) -> void:
	print("== 我的道具阶段 → 右下角动作按钮「结束回合」（玩法侧 selected_slot） ==")
	var pls := [
		{"peer": 2, "name": "我", "color": 1, "bot": false, "alive": true, "money": 1000,
			"pos": 0, "skip": 0, "stamina": 3, "item_used": false,
			"items": [{"id": "作弊器", "cd": 0}, {"id": "交换生", "cd": 0}]},
		{"peer": 3, "name": "乙", "color": 2, "bot": false, "alive": true, "money": 1000,
			"pos": 0, "skip": 0, "stamina": 3, "item_used": false, "items": [{"id": "招财猫", "cd": 0}]},
	]
	g.hp = []          # 客户端没有房主的 hp（hp 只在 _host_setup 里填充）
	g.my_peer = 2
	g.st = {"phase": "playing", "turn": 2, "await": "item", "await_peer": 2, "players": pls}
	# 座位卡已随批次 5 Task 2 退场；牌垫上的「使用道具」三态按钮又随批次 7 退场。
	# 道具阶段的可观察量改到**右下角动作按钮**（道具阶段恒为「结束回合」，见
	# `_refresh_action_button`）；选中态仍看玩法侧单一来源 `selected_slot`。
	g._refresh_actions()
	_check(g.action_btn != null and g.action_btn.visible \
			and String(g.action_btn.text) == "结束回合",
		"我的道具阶段：右下角动作按钮是「结束回合」且可见")
	# 选中「交换生」（槽 1）—— 走**玩法侧唯一入口** `_on_item_slot_clicked`（桌上手牌点击最终也落到它）。
	# 证据取 `g.selected_slot`（玩法侧单一来源）：座位卡牌位已随批次 3 Task 6 拆除后，
	# `board.item_selected` 不再有任何可见效果（`set_item_selected` 遍历的是恒空的 slots），
	# 拿它当证据的话「选择坏了」也会通过。选中的**可见**反馈在桌上那张手牌自己身上（抬起 + 提亮）。
	g._on_item_slot_clicked(2, 1)
	_check(g.selected_slot == 1, "选中「交换生」→ 玩法侧 selected_slot = 1（实得 %d）" % g.selected_slot)
	# 批次 7 的 R2：那条"非道具阶段 → 收掉选中态 / 未完成的选目标态"的清理从
	# `_refresh_item_buttons` 搬进了 `_refresh_action_button`。这里钉住它没被弄丢：
	# 切到掷轮窗口（不再是道具阶段）→ 选中态必须被收掉。
	g.st = {"phase": "playing", "turn": 2, "await": "roll", "await_peer": 2, "players": pls}
	g._refresh_actions()
	_check(g.selected_slot == -1, "非道具阶段 → 选中态被收掉（实得 %d）" % g.selected_slot)

func _test_shop_buttons(g) -> void:
	print("== 小卖部购买按钮 ==")
	var tile := _shop_tile()
	g.hp = []
	g.my_peer = 2
	g.st = {
		"phase": "playing", "turn": 2, "shop_peer": 2, "shop_open": tile,
		"shops": {tile: {"slots": ["作弊器", "", ""]}}, "refresh_price": 500,
		"players": [{"peer": 2, "name": "我", "alive": true, "money": 9000, "items": [],
			"stamina": 3, "item_used": false}],
		"tiles": _fresh_tiles(),
	}
	g._process(0.0)
	_check(g.shop_layer.visible, "轮到自己逛小卖部时全屏界面显示")
	_check(g.shop_btns.size() == 3 and g.shop_btns[0].visible, "有货的货架显示「买」按钮")
	_check(g.shop_btns.size() == 3 and not g.shop_btns[1].visible, "空货架不显示「买」按钮")
	# 全屏层层级（终审 I2）：z_index 要压过 board 内元素（15/20/30/60），且显示时置顶
	_check(g.shop_layer.z_index > 60, "小卖部全屏层 z_index 高于 board 内元素")
	_check(g.shop_layer.get_index() == g.get_child_count() - 1, "小卖部全屏层显示时置顶")
	_check(g.shop_money_l != null and g.shop_money_l.text.contains("9,000"),
		"面板显示自己的现金（买按钮置灰时看得出理由）")
	# 倒计时（终审 I1）：与座位卡共用同一份 _op_*，不是另起一套计时
	g._op_kind = "shop"
	g._op_left = 12.0
	g._op_total = 20.0
	g._process(0.0)
	_check(g.shop_timer_row.visible and g.shop_timer_left.text == "12 秒",
		"小卖部面板显示倒计时（与座位卡同一数据源）")
	g._op_kind = ""
	g._op_left = 0.0
	g._op_total = 0.0
	g._process(0.0)
	_check(not g.shop_timer_row.visible, "窗口关闭后面板倒计时收起")

func _test_authority_guards(g) -> void:
	print("== 客户端→房主 RPC 的发送者校验 ==")
	# c_decision：只有被询问的那个玩家能回答（直接调用时 sender = 0）
	g._awaiting_prompt = 7
	g._pending_token = 3
	g._decision = {"token": -1, "yes": false}
	g.c_decision(3, true)
	_check(int(g._decision.token) == -1, "非当事玩家的 c_decision 被拒绝")
	# 注：赌场改「投骰子」后已无 c_casino_action（房主全权掷骰），该鉴权测试随之移除

func _test_card_sound_once(g) -> void:
	print("== s_card 的音效只响一次 ==")
	var fx = root.get_node_or_null("Fx")
	_check(fx != null, "Fx 单例可用")
	if fx == null:
		return
	var before: int = int(fx._pool_i)
	g.s_card("强制缴费", "info", "")   # 非牌堆路径：此前这里会再播一次
	var n: int = int(fx._pool_i) - before
	_check(n == 1, "一次 s_card 只播一次音效（实得 %d 次）" % n)

func _test_item_card_cooling_flag() -> void:
	print("== 黑卡带剩余次数时不应画成「冷却中」 ==")
	# 必须 load 而不是直接写 ItemCard：--script 主脚本编译期解析不到 autoload，
	# 而 ItemCard → UIKit → Fx 这条依赖链会把整个测试编译搞崩。
	var ic = load("res://scripts/item_card.gd")
	if ic == null:
		_check(false, "item_card.gd 可加载")
		return
	var medium: Vector2 = ic.SIZE_MEDIUM
	var counter: Control = ic.make("黑卡", medium, {"count": 2})
	_check(counter.modulate != Color(0.6, 0.62, 0.7), "计数位（黑卡剩余次数）不压暗")
	var cooling: Control = ic.make("作弊器", medium, {"count": 2, "cooling": true})
	_check(cooling.modulate == Color(0.6, 0.62, 0.7), "显式 cooling 的卡才压暗")
	counter.free()   # 这两张卡没进场景树，不自己释放会留 leak 警告
	cooling.free()

func _test_view_rotation_removed(g) -> void:
	print("== 转视角已删除（入口不存在） ==")
	for m in ["rotate_to_seat", "rotate_to_edge", "rotate_home", "go_home_follow",
			"rotate_next", "at_home_view"]:
		_check(not g.board.has_method(m), "board.%s 已删除" % m)

func _test_tab_space_no_longer_rotates(g) -> void:
	print("== Tab / 空格 不再切视角 ==")
	var pls := [_mk_player(1, "我"), _mk_player(2, "乙"), _mk_player(3, "丙")]
	g.board._process(0.0)
	g.board._zoom = 1.2
	var rot_target_before: float = g.board._rot_target
	for code in [KEY_TAB, KEY_SPACE]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.pressed = true
		g._unhandled_input(ev)
		_check(g.board._rot_target == rot_target_before,
			"按 %s 后镜头旋转目标未变（实得 %.3f / 期望 %.3f）" % [
				OS.get_keycode_string(int(code)), g.board._rot_target, rot_target_before])
	# Esc 分支必须还在（别把 _unhandled_input 整段删了）：真的走一遍取消选目标
	g._tgt_stage = "peer"
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	g._unhandled_input(esc)
	_check(g._tgt_stage == "", "Esc 仍能取消选目标（Esc 分支未因删视角误删）")

func _test_turn_ring_first_render(g) -> void:
	print("== 首个行动玩家的脉冲光环应亮起（批次 11 Task 1 起光环是 3D 的） ==")
	# 原先这条读 `g.board._ring`（2D Panel）。棋子与光环搬进 3D 之后，单一来源是
	# `table_props.set_tokens` / `set_ring`（由 `game._refresh_tokens` 在每次广播时推），
	# 所以这里走**真入口**：喂状态 → 广播路径的刷新函数，再读桌面上那个 3D 环节点。
	# （钉的仍是 fix/v0.0.2 那个病：光环必须在**棋子建好之后**才置位，否则会被记成"已设置"
	#  而永远不亮 —— 顺序错时 `set_ring` 找不到那枚棋子、环直接不显示。）
	g.st = {
		"phase": "playing", "turn": 1, "round": 1, "max_rounds": 30,
		"players": [
			{"peer": 1, "name": "我", "color": 0, "pos": 0, "money": 1000, "alive": true,
				"items": [], "stamina": 3, "skip": 0, "sleep": 0},
			{"peer": 2, "name": "乙", "color": 1, "pos": 0, "money": 1000, "alive": true,
				"items": [], "stamina": 3, "skip": 0, "sleep": 0},
		],
		"tiles": _fresh_tiles(),
	}
	g._refresh_table_props()
	var tp = g.table3d.table_props
	var ring: Node3D = tp.get_node_or_null("Ring") as Node3D
	_check(ring != null and ring.visible,
		"首次刷新后光环亮起（环在？%s / 实得 %s）" % [str(ring != null), str(ring != null and ring.visible)])
	# 环心落在 peer 1 那枚棋子上（光环是"套在行动者脚下"的，位置错就是套错人）
	var tp_pos: Vector3 = tp.token_world_pos(1)
	var ring_back: Vector2 = g.table3d.world_to_canvas_px(ring.global_position)
	var tok_back: Vector2 = g.table3d.world_to_canvas_px(tp_pos)
	_check(ring_back.distance_to(tok_back) < 8.0,
		"环心落在 peer 1 的棋子上（环 %s / 棋子 %s 画布像素）" % [ring_back, tok_back])
	g._refresh_table_props()
	_check(ring.visible, "再次刷新后光环仍亮")

func _test_ui_widgets_applied(g) -> void:
	print("== HUD 控件回填（TableHud → game 同名成员）==")
	# _build_ui 现在靠 set(k, w[k]) 回填，名字对不上是「静默失败」——
	# 控件为 null 也不会报错，只会界面缺一块。这里逐个钉住。
	var names := ["board",
		"shop_layer", "shop_btns", "shop_refresh_btn", "black_bar", "log_panel",
		"log_text", "log_head", "log_toggle", "info_panel", "info_title",
		"info_body", "info_sb", "chat_edit",
		"opt_btn", "black_btns", "black_hint",
		"menu_dim", "menu_wraps", "rules_btn", "rules_panel", "rules_body", "rules_tabs",
		# 批次 5 Task 3：身家条取代了右侧名册栏（roster_box / roster_rows 已从 game 上删净）
		# 批次 12 D：四角条只剩「我」那一条，他人的信息与"选目标落点"搬到**顶部名册条**
		#（`roster_strip` / `roster_strip_rows`）—— 那两个名字是新的，与上面已删的旧名册栏无关。
		# **批次 13 ② 又把它搬到左上角「暂停」旁；辛 ③ 起是那边一行里的一格**；两个控件名一字未变。
		"corner_bars", "roster_strip", "roster_strip_rows", "ab_wrap"]
	var missing: Array = []
	for n in names:
		if g.get(n) == null:
			missing.append(n)
	_check(missing.is_empty(), "全部 %d 个控件已回填（缺失：%s）" % [names.size(), str(missing)])
	# 反向契约（批次 3 Task 6）：底栏那 12 个名字必须**从表里刻意去掉** —— 它们已被删除，
	# 留在表里就是一条恒假的红条。这里把「确实删掉了」也钉住：谁要是把它们加回来，
	# 等于坞又长出来了，这条会先红。
	var removed := ["mat_bar", "action_bar", "dock_plate", "roll_btn", "use_phase_btn", "item_btn_box",
		"status_label", "ph1_lab", "ph2_lab", "ph1_pill", "ph2_pill", "ph_arrow_l",
		# 批次 5 Task 3：右侧名册栏被四角身家条取代 —— 这两个名字必须**从 game 上删净**，
		# 谁把它们加回来就等于名册栏又长出来了（四角条与它挂的是同一份东西，重复）。
		"roster_box", "roster_rows"]
	var back: Array = []
	for n in removed:
		if g.get(n) != null:
			back.append(n)
	_check(back.is_empty(), "底部操作坞 + 右栏名册的成员均已删净（残留：%s）" % str(back))

func _test_dev_panel(g) -> void:
	print("== 开发者面板（已搬到 dev_tools.gd）==")
	_check(g.dev != null, "dev 节点已建立")
	if g.dev == null:
		return
	_check(g.dev.dev_panel != null, "面板已在 _build_ui 里构建")
	g.dev.enabled = true
	g.dev.apply_mode()
	_check(g.dev.dev_panel.visible, "开启后面板可见")
	g.hp = [_mk_player(1, "甲")]
	g.turn_i = 0
	g.dev.dev_sel_peer = 1
	g.dev._dev_add_money(1000)
	_check(int(g.hp[0].money) == 2000, "开发者加钱生效（实得 %d）" % int(g.hp[0].money))
	g.dev.enabled = false
	g.dev.apply_mode()
	_check(not g.dev.dev_panel.visible, "关闭后面板隐藏")

func _test_hot_chain(g) -> void:
	print("== 「连续三次 10+」必须跨回合累计 ==")
	var p := _mk_player(1, "甲")
	p["hot_chain"] = 0
	_check(not g._note_roll_hot(p, 10), "第 1 次 10+ 不抓")
	_check(not g._note_roll_hot(p, 12), "第 2 次 10+ 不抓")
	_check(g._note_roll_hot(p, 11), "第 3 次 10+ 触发查寝")
	_check(int(p.hot_chain) == 0, "触发后计数清零")
	_check(not g._note_roll_hot(p, 3), "低于 10 不计入")
	_check(not g._note_roll_hot(p, 10), "中断后重新累计（第 1 次）")
	_check(not g._note_roll_hot(p, 10), "中断后重新累计（第 2 次）")
	_check(g._note_roll_hot(p, 10), "中断后重新累计（第 3 次再抓）")

func _test_shop_refresh_full_shelf(g) -> void:
	print("== 小卖部刷新：整架重掷（三格全换）并照价扣钱 ==")
	var tile := _shop_tile()
	var p := _mk_player(1, "甲")
	p.money = 9000
	g.hp = [p]
	g.turn_i = 0            # hp 只有 1 人，_broadcast_state 会索引 hp[turn_i]
	g.shops = {tile: {"slots": ["作弊器", "招财猫", "黑卡"]}}   # 三格都满
	g._shop_peer = 1
	g._shop_tile = tile
	g.refresh_count = 0
	var cost: int = g._refresh_price()
	g._shop_refresh(1)
	# 整架重掷：三格全换、照价扣钱、推高全场刷新价（#12）
	_check(int(p.money) == 9000 - cost, "整架刷新照价扣钱（9000 → %s）" % str(p.money))
	_check(g.refresh_count == 1, "整架刷新推高全场刷新价")
	var slots: Array = g.shops[tile].slots
	_check(slots.size() == 3 and String(slots[0]) != "" and String(slots[1]) != "" and String(slots[2]) != "",
		"刷新后三格仍满（整架重掷而非只补空位）")

func _test_roster_marks_disconnected_bots(g, net) -> void:
	print("== 开局名册：淡出期间掉线的玩家应转机器人 ==")
	net.players = [
		{"peer": 1, "name": "房主", "color": 0, "bot": false, "ready": true},
		{"peer": 2, "name": "乙", "color": 1, "bot": false, "ready": true},
	]
	var h: Array = g._build_hp()
	_check(h.size() == 2, "名册人数正确（实得 %d）" % h.size())
	_check(not bool(h[0].bot), "房主仍为真人")
	_check(bool(h[1].bot), "未真正连上的玩家在对局里标记为机器人")

func _test_dead_player_items_return_to_pool(g) -> void:
	print("== 破产玩家的唯一道具应回池 ==")
	var dead := _mk_player(1, "甲")
	dead.alive = false
	dead.items = [{"id": "黑卡", "cd": 0, "charges": 1}]
	g.hp = [dead, _mk_player(2, "乙")]
	g.htiles = _fresh_tiles()
	g.shops = {}
	g._black_slots = []
	g.items_consumed = {}
	_check(g._item_pool("橙").has("黑卡"), "破产玩家持有的唯一道具回到可获取池")

func _test_conn_lost_unpauses(g, lobby) -> void:
	print("== 掉线回主菜单必须解除暂停 ==")
	# 房主开菜单会全场暂停；此时房主掉线，客户端不能停在暂停的菜单上
	g.get_tree().paused = true
	g._on_conn_lost("房主已离开")
	_check(not g.get_tree().paused, "对局场景掉线后解除暂停")
	g.get_tree().paused = true
	lobby._on_conn_lost("房主已离开")
	_check(not lobby.get_tree().paused, "大厅场景掉线后解除暂停")

func _test_lobby_rules(net) -> void:
	print("== 大厅：hello 判定顺序 / 昵称清洗 / 发现器兜底重启 ==")
	# 满员房间（其中含 peer 0）里，已入座玩家重发 hello 不能被当成新人踢掉
	net.players = [
		{"peer": 0, "name": "甲", "color": 0, "bot": false, "ready": true},
		{"peer": 5, "name": "乙", "color": 1, "bot": false, "ready": true},
		{"peer": 6, "name": "丙", "color": 2, "bot": false, "ready": true},
		{"peer": 7, "name": "丁", "color": 3, "bot": false, "ready": true},
	]
	net.in_game = false
	_check(net.hello_verdict(0) == "", "满员房间里已入座的玩家重发 hello 不被踢")
	_check(net.hello_verdict(99) != "", "满员房间里的新玩家被拒")
	net.in_game = true
	_check(net.hello_verdict(5) == "", "开局后已入座玩家重发 hello 不被踢")
	net.in_game = false

	# 昵称清洗：| 与换行都会污染大厅/发现报文
	_check(net.sanitize_name("A|B") == "AB", "昵称里的 | 被剔除")
	_check(net.sanitize_name("a\nb") == "ab", "昵称里的换行被剔除")
	_check(net.sanitize_name("   ") == "玩家", "空白昵称回落为「玩家」")

	# 加入失败后房间发现器必须能自动重启
	net._reset_peer()
	_check(net._disco_client == null, "重置后发现器已停")
	net.ensure_disco_client()
	_check(net._disco_client != null, "主菜单刷新时发现器自动重启")

func _test_endpoint_format() -> void:
	print("== 地址展示串：IPv6 必须带方括号（否则解析不出端口） ==")
	var cases := [["10.11.28.88", 7777], ["2001:db8::1", 8000], ["::1", 7777], ["fe80::abcd", 9000]]
	for c in cases:
		var host := String(c[0])
		var port := int(c[1])
		var s := NetAddr.format_endpoint(host, port)
		var back := NetAddr.parse_endpoint(s, 1)
		_check(back.size() == 2 and String(back[0]) == host and int(back[1]) == port,
			"\"%s\" 往返解析回 %s:%d（实得 %s）" % [s, host, port, str(back)])

func _test_room_info_port() -> void:
	print("== 房间发现报文必须带房主端口（否则从列表加入会拨错端口） ==")
	var info := NetAddr.parse_room_info("%s|INFO|宿舍A|2/4|open|8123" % "DMONO3")
	_check(String(info.get("name", "")) == "宿舍A", "解析出房间名")
	_check(String(info.get("count", "")) == "2/4", "解析出人数")
	_check(int(info.get("port", 0)) == 8123, "解析出房主端口")
	_check(NetAddr.parse_room_info("bad").is_empty(), "坏报文返回空")

func _test_camera_window_resize(g) -> void:
	print("== 镜头状态：窗口缩放不重置镜头 ==")
	var pls := [_mk_player(1, "我"), _mk_player(2, "乙"), _mk_player(3, "丙")]
	g.board._process(0.0)             # 首次布局：fit_overview
	_check(g.board.size.x > 10.0, "棋盘控件已布局（w=%.0f）" % g.board.size.x)
	g.board._zoom = 1.2
	g.board.focus_grid(27, 2.0, true) # 模拟对局中途镜头停在某格（2.0 是「全景的倍数」，见 board_view 顶部常量）
	var center_before: Vector2 = g.board._center
	g.board.emit_signal("resized")
	g.board._process(0.016)
	_check(g.board._center == center_before,
		"窗口尺寸变化后镜头注视点不被拽回（实得 %s / 期望 %s）" % [g.board._center, center_before])
	_check(absf(g.board._rot) < 0.001, "镜头旋转恒为 0（实得 %.4f rad）" % g.board._rot)

func _test_roll_button_off_home_view(g) -> void:
	print("== 右下角动作按钮（批次 7；本人掷轮时是「转动转盘」） ==")
	var pls := [
		{"peer": 1, "name": "我", "color": 0, "bot": false, "alive": true, "money": 1000,
			"pos": 0, "skip": 0, "stamina": 3, "item_used": false, "items": []},
		{"peer": 2, "name": "乙", "color": 1, "bot": false, "alive": true, "money": 1000,
			"pos": 0, "skip": 0, "stamina": 3, "item_used": false, "items": []},
	]
	g.hp = []
	g.my_peer = 1
	g.st = {
		"phase": "playing", "turn": 1, "await": "roll", "await_peer": 1, "roll_epoch": 1,
		"round": 1, "max_rounds": 30, "players": pls, "tiles": _fresh_tiles(),
		"shops": {}, "shop_open": -1, "shop_peer": 0, "black_peer": 0,
	}
	g._refresh_actions()              # 动作按钮的状态由状态决定
	await process_frame
	await process_frame               # 等容器布局算出真实尺寸
	g._process(0.0)
	_check(g.action_btn != null and g.action_btn.visible \
			and String(g.action_btn.text) == "转动转盘",
		"轮到我掷轮：右下角按钮是「转动转盘」且可见")
	_check(g.get("mat_bar") == null, "底栏成员已删净（不会留成一块不可见的空壳）")
	# 批次 5 Task 2 的牌垫阶段按钮层，批次 7 已整体退场 —— 反向契约：谁加回来，这条先红。
	_check(g.board.get_node_or_null("PhaseButtons") == null, "牌垫阶段按钮层已拆净（不留空壳）")
	# 座位卡那一套 API 必须**真的没了**（不是留着空壳）：谁把它加回来，这条先红。
	var seat_api: Array = ["build_seats", "seat_count", "seat", "set_op_timer", "set_self_peer",
		"update_seat_stats", "_make_seat", "_seat_bar"]
	var back: Array = []
	for m in seat_api:
		if g.board.has_method(m):
			back.append(m)
	_check(back.is_empty(), "座位卡的成员函数已删净（残留：%s）" % str(back))

## 指向性道具：点棋盘选玩家 / 两段式手选地块（本轮返工）
func _test_targeting(g) -> void:
	print("== 指向性道具：选玩家 / 两段式手选地块 ==")
	var p1 := _mk_player(1, "我")
	var p2 := _mk_player(2, "乙")
	var p3 := _mk_player(3, "丙")
	g.my_peer = 1
	var tiles := _fresh_tiles()
	var pa := _prop_idx(0)
	var pb := _prop_idx(1)
	tiles[pa]["owner"] = 2
	tiles[pa]["level"] = 2
	tiles[pb]["owner"] = 2
	tiles[pb]["level"] = 1
	g.st = {
		"phase": "playing", "turn": 1, "await": "item", "await_peer": 1, "roll_epoch": 1,
		"round": 1, "max_rounds": 30, "players": [p1, p2, p3], "tiles": tiles,
		"shops": {}, "shop_open": -1, "shop_peer": 0, "black_peer": 0,
	}
	# 选玩家：其他两名存活玩家；两段式只列「名下有地」的玩家
	_check(g._item_targets(1).size() == 2, "选玩家列表 = 其他两名存活玩家")
	_check(g._selectable_props(2) == [pa, pb], "乙名下两块地皮（读已同步的 st.tiles）")
	_check(g._selectable_props(3).is_empty(), "丙名下无地皮")

	# 两段式：强拆令 选乙 → 指定 pa → 只有 pa 归无主（而非随机）
	g.hp = [p1, p2, p3]
	g.htiles = []
	for i in GameData.TILES.size():
		g.htiles.append({"owner": GameData.NO_OWNER, "level": 0, "soil": false})
	g.htiles[pa]["owner"] = 2
	g.htiles[pa]["level"] = 2
	g.htiles[pb]["owner"] = 2
	g.htiles[pb]["level"] = 1
	var inst := {"id": "强拆令", "cd": 0}
	var ok: bool = await g._apply_item_effect(p1, inst, 2, pa)
	_check(ok, "强拆令（两段式）返回成功")
	_check(int(g.htiles[pa].owner) == GameData.NO_OWNER, "指定的 pa 归为无主")
	_check(int(g.htiles[pb].owner) == 2, "未指定的 pb 不受影响（不是随机乱拆）")
	_check(int(g.htiles[pa].level) == 0, "被强拆的地皮等级清零")

	# 抄家队：两段式指定 pb → 只降 pb 一级
	g.htiles[pa]["owner"] = 2
	g.htiles[pa]["level"] = 2
	g.htiles[pb]["owner"] = 2
	g.htiles[pb]["level"] = 2
	var inst2 := {"id": "抄家队", "cd": 0}
	var ok2: bool = await g._apply_item_effect(p1, inst2, 2, pb)
	_check(ok2, "抄家队（两段式）返回成功")
	_check(int(g.htiles[pb].level) == 1, "指定的 pb 降 1 级")
	_check(int(g.htiles[pa].level) == 2, "未指定的 pa 不受影响")

	# 非法 arg2（不属于目标）→ 回落随机，不崩
	var ok3: bool = await g._apply_item_effect(p1, inst2, 2, 9999)
	_check(ok3, "非法 arg2 回落随机仍返回成功")

	# 保安队长（#26）：只挑**有冷却的主动件**，绝不碰被动
	var tgt := _mk_player(2, "乙")
	tgt.items = [{"id": "招财猫", "cd": 0}, {"id": "交换生", "cd": 0}]
	g.hp = [p1, tgt]
	var ok4: bool = await g._apply_item_effect(p1, {"id": "保安队长", "cd": 0}, 2)
	_check(ok4, "保安队长返回成功")
	_check(int(tgt.items[0].cd) == 0, "保安队长不动被动（招财猫 cd 仍 0）")
	_check(int(tgt.items[1].cd) == 2, "保安队长只给有冷却的主动件 +2（交换生 cd=2）")

## 数值专场行为代码（§六 #3）+ 紫档新批次（§六 #11）
func _test_new_items(g) -> void:
	print("== 道具：数值专场行为 + 紫档新批次 ==")
	var p1 := _mk_player(1, "我")
	var p2 := _mk_player(2, "乙")
	g.my_peer = 1
	g.hp = [p1, p2]
	g.htiles = []
	for i in GameData.TILES.size():
		g.htiles.append({"owner": GameData.NO_OWNER, "level": 0, "soil": false})

	# 数值专场行为：招财猫 +400 / 保安巡逻 ×1.3 / 校园卡 +1000
	p1.items = [{"id": "招财猫", "cd": 0}]
	_check(int(g._rent_gain(p1, 1000)) == 1400, "招财猫：租金 +400（实得 %d）" % int(g._rent_gain(p1, 1000)))
	p1.items = [{"id": "保安巡逻", "cd": 0}]
	_check(int(g._rent_gain(p1, 1000)) == 1300, "保安巡逻：收租 +30%（实得 %d）" % int(g._rent_gain(p1, 1000)))
	p1.items = [{"id": "校园卡", "cd": 0}]
	_check(int(g._salary_amount(p1)) == GameData.SALARY + 1000, "校园卡：过起点 +1000")

	# 二手交易：弃本道具 +¥2000
	p1.items = [{"id": "二手交易", "cd": 0}]
	p1.money = 0
	var ok_se: bool = await g._apply_item_effect(p1, p1.items[0], -1)
	_check(ok_se and int(p1.money) == 2000, "二手交易：+¥2000（实得 %d）" % int(p1.money))

	# 刮刮乐：¥100~1000 十档
	p1.money = 0
	var ok_sc: bool = await g._apply_item_effect(p1, {"id": "刮刮乐", "cd": 0}, -1)
	_check(ok_sc and int(p1.money) >= 100 and int(p1.money) <= 1000 and int(p1.money) % 100 == 0,
		"刮刮乐：¥100~1000 十档（实得 %d）" % int(p1.money))

	# 顶楼加盖：自有地 +2 级
	var pi := _prop_idx(0)
	g.htiles[pi].owner = 1
	g.htiles[pi].level = 1
	var ok_rf: bool = await g._apply_item_effect(p1, {"id": "顶楼加盖", "cd": 0}, pi)
	_check(ok_rf and int(g.htiles[pi].level) == 3, "顶楼加盖：+2 级（实得 Lv%d）" % int(g.htiles[pi].level))

	# 没收：抢一件道具过来
	p2.items = [{"id": "饭卡", "cd": 0}]
	p1.items = []
	var ok_cf: bool = await g._apply_item_effect(p1, {"id": "没收", "cd": 0}, 2)
	_check(ok_cf and p1.items.size() == 1 and p2.items.is_empty(), "没收：抢走对方一件道具")

	# 打印店：复制件带 fake 标记（用后焚毁不回池）
	p2.items = [{"id": "饭卡", "cd": 0}]
	p1.items = []
	var ok_cp: bool = await g._apply_item_effect(p1, {"id": "打印店", "cd": 0}, 2)
	_check(ok_cp and p1.items.size() == 1 and bool(p1.items[0].get("fake", false)),
		"打印店：复制件带 fake 标记")

	# 代课：置下笔租金反转标记
	p1.items = []
	var ok_sub: bool = await g._apply_item_effect(p1, {"id": "代课", "cd": 0}, -1)
	_check(ok_sub and bool(p1.get("sub_rent", false)), "代课：置下笔租金反转标记")

	# 转专业：交换两块地归属（arg2=我的地, arg3=他的地）
	var pa := _prop_idx(0)
	var pb := _prop_idx(1)
	g.htiles[pa].owner = 1
	g.htiles[pb].owner = 2
	var ok_tr: bool = await g._apply_item_effect(p1, {"id": "转专业", "cd": 0}, 2, pa, pb)
	_check(ok_tr and int(g.htiles[pa].owner) == 2 and int(g.htiles[pb].owner) == 1,
		"转专业：交换两块地归属")
