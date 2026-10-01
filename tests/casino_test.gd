extends SceneTree
## 赌场小游戏「炸弹猫」单测：纯规则 + 一局完整流程
## godot --headless --path . --script tests/casino_test.gd
##
## 流程测试是「把赌场从 game.gd 搬出去」的安全网：赌场只有玩家踩到那 2 个格才触发，
## 3 轮联机回归碰不到它，没有这段覆盖就搬等于盲拆。

var fails := 0

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

func _mk_bot(peer: int, money: int) -> Dictionary:
	return {"peer": peer, "name": "机器人%d" % peer, "color": peer - 1, "bot": true,
		"money": money, "pos": 0, "alive": true, "skip": 0, "sleep": 0,
		"stamina": 3, "items": [], "item_used": false, "cheat_roll": -1, "hot_chain": 0}

func _run() -> void:
	seed(4242)
	_test_rules()
	await _test_round()
	if fails == 0:
		print("CASINO TEST: ALL PASS")
		quit(0)
	else:
		print("CASINO TEST: %d FAILURES" % fails)
		quit(1)

func _test_rules() -> void:
	print("== 牌堆构成 ==")
	var d: Array = BombCat.deck()
	_check(d.size() == 12, "牌堆 12 张（实得 %d）" % d.size())
	_check(d.count(BombCat.BOMB) == 3, "炸弹 ×3（实得 %d）" % d.count(BombCat.BOMB))
	_check(d.count(BombCat.DEFUSE) == 2, "拆除 ×2（实得 %d）" % d.count(BombCat.DEFUSE))
	_check(d.count(BombCat.FISH) == 7, "小鱼 ×7（实得 %d）" % d.count(BombCat.FISH))

	print("== 卡面名 ==")
	_check(BombCat.card_name("bomb") == "炸弹", "bomb → 炸弹")
	_check(BombCat.card_name("defuse") == "拆除", "defuse → 拆除")
	_check(BombCat.card_name("fish") == "小鱼", "fish → 小鱼")

	print("== 胜负判定 ==")
	_check(BombCat.winner([7], [1, 7, 9], {7: 0}) == 7, "场上只剩一人 → 他通吃")
	_check(BombCat.winner([1, 7, 9], [1, 7, 9], {1: 1, 7: 3, 9: 2}) == 7, "小鱼最多者通吃")
	_check(BombCat.winner([1, 7], [1, 7], {1: 2, 7: 2}) == 1, "同鱼数取行动顺序靠前者")
	_check(BombCat.winner([1, 7], [1, 7], {}) == 1, "全员零鱼也能判出赢家")
	_check(BombCat.winner([7, 9], [1, 7, 9], {1: 9, 7: 1, 9: 2}) == 9,
		"已出局者的小鱼数不参与（1 号被炸掉后 9 号胜）")
	_check(BombCat.winner([], [1], {}) == -1, "无人可判返回 -1")
	# 牌没抽空且还剩多人：保持既有行为（判不出赢家），正常流程不可达
	_check(BombCat.winner([1, 7], [1, 7], {1: 3, 7: 1}, false) == -1,
		"牌堆未空且多人时判不出赢家（保持原行为）")

func _test_round() -> void:
	print("== 一局完整流程：下注 → 通吃 → 奖池归零 ==")
	create_timer(60.0).timeout.connect(func() -> void:
		printerr("CASINO TEST TIMEOUT")
		quit(1))

	# peer 必须先装好（赌场 RPC 要用它）。注意 unique_id 为 1 时 is_server() 恒为真，
	# 所以 _ready 里的 _host_setup 一定会执行并拉起 _run_game —— 那个自动对局会和
	# 本测试手动摆的状态打架（实测会凭空多出钱）。先让它自己退出：
	# running=false → _host_setup 里那次 _run_game 走到 while 就结束。
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(7794, 3) != OK:
		_check(false, "server create failed")
		return
	var mp := MultiplayerAPI.create_default_interface()
	mp.multiplayer_peer = peer
	set_multiplayer(mp, "/root")

	# 名册先给一份有效的：_host_setup 会在 1.5s 后 _broadcast_state()，
	# 那时 hp 为空会越界报错。
	root.get_node("Net").players = [_mk_bot(1, 5000), _mk_bot(2, 5000), _mk_bot(3, 5000)]

	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.running = false
	if g.board == null or g.casino == null:
		# 脚本编译失败时成员会是 null；后续断言里的表达式先报错、根本走不到
		# _check，整轮会假报「全过」（见 fix/v0.0.2）
		_check(false, "对局场景可加载（脚本编译失败？）")
		return
	# 等 _host_setup 的 1.5s 与 _run_game 的 0.3s 都过去，确认自动对局已经停住
	await create_timer(2.5).timeout

	var ps := [_mk_bot(1, 5000), _mk_bot(2, 5000), _mk_bot(3, 5000)]
	g.hp = ps
	g.turn_i = 0
	g.htiles = _fresh_tiles()
	g.shops = {}
	g.items_consumed = {}
	g.casino._casino_layer = null
	g.running = true          # 赌场回合循环靠它推进（全场皆 bot，无需人工出牌）

	var before := 0
	for p in ps:
		before += int(p.money)
	await g.casino.run(ps[0])

	var after := 0
	var mx := -1
	var mn := 1 << 30
	for p in ps:
		var m := int(p.money)
		after += m
		mx = maxi(mx, m)
		mn = mini(mn, m)
	var top := 0
	for p in ps:
		if int(p.money) == mx:
			top += 1

	_check(after == before, "奖池全额回到玩家手里（前 %d / 后 %d）" % [before, after])
	_check(mx > mn, "产生了赢家（最低 %d / 最高 %d）" % [mn, mx])
	_check(top == 1, "只有一个人通吃（实得 %d 人并列最高）" % top)
	_check(g.casino._casino_table_pot == 0,
		"结算后桌面奖池显示归零（实得 %d）" % g.casino._casino_table_pot)

	g.running = false
	g.free()
