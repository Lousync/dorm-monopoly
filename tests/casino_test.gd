extends SceneTree
## 赌场小游戏「投骰子」单测：纯规则（并列最大者 / 平分）+ 一局完整流程
## godot --headless --path . --script tests/casino_test.gd
##
## 流程测试是「把赌场从 game.gd 搬出去 / 换游戏」的安全网：赌场只有玩家踩到那 2 个格才
## 触发，联机回归碰不到它，没有这段覆盖就等于盲拆。

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
	# 运行时 load（不能用 preload：解析期编译时 autoload 还没注册，Fx 会找不到）
	var CasinoTable: GDScript = load("res://scripts/casino.gd")
	print("== 并列最大者 ==")
	_check(CasinoTable.max_peers({1: 3, 2: 5, 3: 5}, [1, 2, 3]) == [2, 3], "5/5 并列 → [2,3]")
	_check(CasinoTable.max_peers({1: 6, 2: 2}, [1, 2]) == [1], "唯一最大 → [1]")
	_check(CasinoTable.max_peers({5: 1, 6: 1, 7: 1}, [5, 6, 7]) == [5, 6, 7], "全并列 → 全部")
	_check(CasinoTable.max_peers({1: 2, 2: 4, 3: 3}, [1, 2, 3]) == [2], "4 最大 → [2]")

	print("== 平分（余数逐人 +1）==")
	_check(CasinoTable.split(3200, 1) == [3200], "3200 / 1 → [3200]")
	_check(CasinoTable.split(3200, 2) == [1600, 1600], "3200 / 2 → [1600,1600]")
	_check(CasinoTable.split(3200, 3) == [1067, 1067, 1066], "3200 / 3 → [1067,1067,1066]")
	_check(CasinoTable.split(100, 3) == [34, 33, 33], "100 / 3 → [34,33,33]")

func _test_round() -> void:
	print("== 一局完整流程：下注 → 掷骰 → 通吃/平分 → 奖池归零 ==")
	create_timer(60.0).timeout.connect(func() -> void:
		printerr("CASINO TEST TIMEOUT")
		quit(1))

	# peer 必须先装好（赌场 RPC 要用它）。注意 unique_id 为 1 时 is_server() 恒为真，
	# 所以 _ready 里的 _host_setup 一定会执行并拉起 _run_game —— 那个自动对局会和
	# 本测试手动摆的状态打架。先让它自己退出：running=false → _run_game 立刻结束。
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(7794, 3) != OK:
		_check(false, "server create failed")
		return
	var mp := MultiplayerAPI.create_default_interface()
	mp.multiplayer_peer = peer
	set_multiplayer(mp, "/root")

	root.get_node("Net").players = [_mk_bot(1, 5000), _mk_bot(2, 5000), _mk_bot(3, 5000)]

	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.running = false
	if g.board == null or g.casino == null:
		_check(false, "对局场景可加载（脚本编译失败？）")
		return
	await create_timer(2.5).timeout

	var ps := [_mk_bot(1, 5000), _mk_bot(2, 5000), _mk_bot(3, 5000)]
	g.hp = ps
	g.turn_i = 0
	g.htiles = _fresh_tiles()
	g.shops = {}
	g.items_consumed = {}
	g.running = true

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

	_check(after == before, "奖池全额回到玩家手里（前 %d / 后 %d）" % [before, after])
	_check(mx > mn, "产生了赢家（最低 %d / 最高 %d）" % [mn, mx])
	_check(g.casino._casino_table_pot == 0,
		"结算后桌面奖池显示归零（实得 %d）" % g.casino._casino_table_pot)

	# 赌场已改为自带全屏演出层（触发时独占整屏），不再是 board 的世界层区域
	# 先拦 null：下面是直接解引用，_ui_layer 为 null 时表达式会硬报错、协程中止而
	# fails 不增，汇总行照样打印 ALL PASS —— 假 PASS 等于这两条覆盖不存在
	# （同款先例见 tests/regression_test.gd 的「场景未正确加载」拦截）。
	if g.casino._ui_layer == null:
		_check(false, "赌场全屏层未建立")
		g.running = false
		g.free()
		return
	_check(g.casino._ui_layer != null, "赌场自带全屏演出层（已建立）")
	_check(not g.casino._ui_layer.visible, "一局结束后全屏层已收场")
	for m in ["casino_enter", "casino_leave", "focus_casino", "update_casino", "_build_casino_scene"]:
		_check(not g.board.has_method(m), "board.%s 已删除" % m)

	g.running = false
	g.free()
