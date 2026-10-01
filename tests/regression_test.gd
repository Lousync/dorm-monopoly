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

	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.running = false  # 冻结主循环：本测试手动摆状态

	_test_round_counter(g)
	_test_client_item_bar(g)
	_test_shop_buttons(g)

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
