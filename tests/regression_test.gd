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

## 重建座位：先停掉在途的金额滚动 tween（它们捕获了旧的标签节点，
## 座位一重建就会写到已释放的控件上），再清掉 game 侧陈旧的行引用缓存。
func _rebuild_seats(g, pls: Array) -> void:
	for peer in g._player_rows:
		var row: Dictionary = g._player_rows[peer]
		var tw = row.get("tw")
		if tw != null and (tw as Tween).is_valid():
			tw.kill()
	g.board.build_seats(pls, g.my_peer)
	g._player_rows.clear()

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
	if g.board == null or g.item_btn_box == null or g.shop_btns.is_empty():
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
	_test_rotate_next_empty(g)
	_test_turn_ring_first_render(g)
	_test_hot_chain(g)
	_test_shop_refresh_full_shelf(g)
	_test_camera_state(g)
	await _test_roll_button_off_home_view(g)

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
	print("== 客户端道具栏（真人可用道具） ==")
	g.hp = []          # 客户端没有房主的 hp（hp 只在 _host_setup 里填充）
	g.my_peer = 2
	g.st = {
		"phase": "playing", "turn": 2, "await": "item", "await_peer": 2,
		"players": [
			{"peer": 2, "name": "我", "alive": true, "money": 1000, "stamina": 3,
				"item_used": false, "items": [{"id": "作弊器", "cd": 0}, {"id": "交换生", "cd": 0}]},
			# 交换生的可换目标（有道具的存活玩家）
			{"peer": 3, "name": "乙", "alive": true, "money": 1000, "stamina": 3,
				"item_used": false, "items": [{"id": "招财猫", "cd": 0}]},
		],
	}
	g._refresh_item_buttons(true, "item")
	_check(g.item_btn_box.get_child_count() > 0,
		"轮到客户端时道具栏有按钮（实得 %d 个）" % g.item_btn_box.get_child_count())
	var swap_btn: Button = null
	for c in g.item_btn_box.get_children():
		if c is Button and String(c.text).begins_with("交换生"):
			swap_btn = c as Button
	_check(swap_btn != null, "客户端道具栏含「交换生」按钮")
	if swap_btn != null:
		_check(not swap_btn.disabled, "客户端上「交换生」可用（有可换目标时不置灰）")

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
	_check(g.shop_bar.visible, "轮到自己逛小卖部时操作条显示")
	_check(g.shop_btns.size() == 3 and g.shop_btns[0].visible, "有货的货架显示「买」按钮")
	_check(g.shop_btns.size() == 3 and not g.shop_btns[1].visible, "空货架不显示「买」按钮")

func _test_authority_guards(g) -> void:
	print("== 客户端→房主 RPC 的发送者校验 ==")
	# c_decision：只有被询问的那个玩家能回答（直接调用时 sender = 0）
	g._awaiting_prompt = 7
	g._pending_token = 3
	g._decision = {"token": -1, "yes": false}
	g.c_decision(3, true)
	_check(int(g._decision.token) == -1, "非当事玩家的 c_decision 被拒绝")
	# c_casino_action：只有当局出牌的玩家能操作
	g._casino_actor = 7
	g._casino_epoch = 5
	g._casino_action = {"epoch": -1, "action": ""}
	g.c_casino_action(5, "top")
	_check(String(g._casino_action.action) != "top", "非当局玩家的 c_casino_action 被拒绝")

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

func _test_rotate_next_empty(g) -> void:
	print("== 座位表为空时按 Tab 不应除零 ==")
	_check(g.board._next_edge([], 0) == -1, "空座位表返回 -1（不除零）")
	_check(g.board._next_edge([0, 1, 2], 0) == 1, "切到下一个座位")
	_check(g.board._next_edge([0, 1, 2], 2) == 0, "末尾回环到第一个")
	_check(g.board._next_edge([0, 1, 2], 9) == 0, "当前不在表内则取第一个")

func _test_turn_ring_first_render(g) -> void:
	print("== 首个行动玩家的脉冲光环应亮起 ==")
	var pls := [_mk_player(1, "我"), _mk_player(2, "乙")]
	_rebuild_seats(g, pls)
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
	g.board.render(g.st)
	_check(g.board._ring.visible, "首次渲染后光环亮起（实得 %s）" % str(g.board._ring.visible))
	g.board.render(g.st)
	_check(g.board._ring.visible, "再次渲染后光环仍亮")

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
	print("== 小卖部刷新：货架没变化就不收钱 ==")
	var tile := _shop_tile()
	var p := _mk_player(1, "甲")
	p.money = 9000
	g.hp = [p]
	g.turn_i = 0            # hp 只有 1 人，_broadcast_state 会索引 hp[turn_i]
	g.shops = {tile: {"slots": ["作弊器", "招财猫", "黑卡"]}}   # 三格都满
	g._shop_peer = 1
	g._shop_tile = tile
	g.refresh_count = 0
	g._shop_refresh(1)
	_check(int(p.money) == 9000, "满货架刷新不扣钱（实得 %s）" % str(p.money))
	_check(g.refresh_count == 0, "满货架刷新不推高全场刷新价")

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

func _test_camera_state(g) -> void:
	print("== 镜头状态：回自己视角 / 窗口缩放 ==")
	var pls := [_mk_player(1, "我"), _mk_player(2, "乙"), _mk_player(3, "丙")]
	_rebuild_seats(g, pls)
	g.board._process(0.0)             # 首次布局：fit_overview
	_check(g.board.size.x > 10.0, "棋盘控件已布局（w=%.0f）" % g.board.size.x)
	# 默认全景倍率下 _clamp_center 会退化成「恒等于桌面中心」，座座位目标无从区分
	g.board._zoom = 1.2

	# A) 回自己视角必须更新镜头目标，否则会沿用别人座位的旧目标，
	#    与跟随镜头互相拉扯、_rotating 永不归位
	g.board.rotate_to_edge(0, true)
	var home_target: Vector2 = g.board._center_target
	g.board.rotate_to_edge(1, true)
	_check(g.board._center_target != home_target, "转到别人座位后镜头目标随之改变")
	g.board.go_home_follow(1)
	_check(g.board._center_target == home_target, "回自己视角后镜头目标回到自己座位")
	for i in 180:
		g.board._process(1.0 / 60.0)
	_check(not g.board.is_rotating(), "回自己视角后镜头动画能收敛归位")

	# B) 窗口尺寸变化不该把视角拽回全景并关掉跟随（对局中途改窗口/缩放）
	g.board.rotate_to_edge(2, true)
	g.board.emit_signal("resized")
	g.board._process(0.016)
	_check(absf(wrapf(g.board._rot, -PI, PI)) > 0.5,
		"窗口尺寸变化后视角仍在别人座位（实得 %.2f rad）" % g.board._rot)

func _test_roll_button_off_home_view(g) -> void:
	print("== 转离自己视角后仍能操作（「转动转盘」不再被一起隐藏） ==")
	var pls := [
		{"peer": 1, "name": "我", "color": 0, "bot": false, "alive": true, "money": 1000,
			"items": [], "stamina": 3, "item_used": false},
		{"peer": 2, "name": "乙", "color": 1, "bot": false, "alive": true, "money": 1000,
			"items": [], "stamina": 3, "item_used": false},
	]
	g.hp = []
	g.my_peer = 1
	g.st = {
		"phase": "playing", "turn": 1, "await": "roll", "await_peer": 1, "roll_epoch": 1,
		"round": 1, "max_rounds": 30, "players": pls, "tiles": _fresh_tiles(),
		"shops": {}, "shop_open": -1, "shop_peer": 0, "black_peer": 0,
	}
	_rebuild_seats(g, pls)            # 建立座位（边 0 = 自己）
	g.board.rotate_to_edge(0, true)   # 前面的镜头用例可能把视角留在别人座位
	g._refresh_actions()              # 掷骰按钮的显隐/可用由状态决定
	await process_frame
	await process_frame               # 等容器布局算出真实尺寸
	g._process(0.0)                   # 阶段条落到屏幕上（真实游戏每帧都会跑）
	_check(g.roll_btn.is_visible_in_tree(), "自己视角下「转动转盘」可见")
	# 布局：自己视角下阶段条仍在（牌垫贴自家座位卡），操作条接在它下面
	_check(g.mat_bar.is_visible_in_tree(), "自己视角下阶段条显示")
	# 自己视角：两条并排成原来那一行（座位卡下沿放不下两行）
	var mb: Control = g.mat_bar
	var vp0: Vector2 = g.get_viewport_rect().size
	_check(g.action_bar.is_visible_in_tree() and absf(g.action_bar.position.y - mb.position.y) < 1.0,
		"自己视角下阶段条与操作条同一行（mat_bar y %.0f / action_bar y %.0f）"
			% [mb.position.y, g.action_bar.position.y])
	_check(g.action_bar.position.x >= mb.position.x + mb.size.x - 1.0,
		"自己视角下操作条排在阶段条右侧（mat_bar 右 %.0f / action_bar x %.0f）"
			% [mb.position.x + mb.size.x, g.action_bar.position.x])
	_check(mb.position.y + mb.size.y <= vp0.y + 1.0 \
			and g.action_bar.position.y + g.action_bar.size.y <= vp0.y + 1.0,
		"自己视角下整行仍在屏幕内（行底 %.0f / 屏高 %.0f）"
			% [maxf(mb.position.y + mb.size.y, g.action_bar.position.y + g.action_bar.size.y), vp0.y])

	g.board.rotate_to_edge(1, true)   # 硬转到别人座位视角
	_check(not g.board.at_home_view(), "已转离自己视角")
	g._process(0.0)
	_check(g.roll_btn.is_visible_in_tree(), "转离视角后「转动转盘」仍在屏幕上可见")
	_check(not g.roll_btn.disabled, "转离视角后「转动转盘」仍可点")
	_check(not g.mat_bar.is_visible_in_tree(), "转离视角后阶段条隐藏（牌垫仍贴自家座位卡）")
	var vp: Vector2 = g.get_viewport_rect().size
	var ab: Control = g.action_bar
	_check(ab.size.y > 1.0, "操作条已算出真实尺寸（h=%.0f）" % ab.size.y)
	_check(ab.position.y >= 0.0 and ab.position.y + ab.size.y <= vp.y + 1.0,
		"转离视角后操作条竖直在屏幕内（y=%.0f h=%.0f vp=%.0f）" % [ab.position.y, ab.size.y, vp.y])
	_check(ab.position.x >= 0.0 and ab.position.x + ab.size.x <= vp.x + 1.0,
		"转离视角后操作条水平在屏幕内（x=%.0f w=%.0f vp=%.0f）" % [ab.position.x, ab.size.x, vp.x])
