extends SceneTree
## 小卖部购买全链路单测（复现"进店买不了"）
## godot --headless --path . --script tests/shop_test.gd

var fails := 0

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

func _shop_idx() -> int:
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "shop":
			return i
	return -1

func _mk_player(peer: int, nm: String, money := 5000) -> Dictionary:
	return {"peer": peer, "name": nm, "color": peer - 1, "bot": false, "money": money,
		"pos": 0, "alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [],
		"item_used": false, "cheat_roll": -1}

## 批次 13 T6 观察者：机器人进店期间，有没有过「同一帧里 shop_open >= 0 且小卖部界面可见」。
## 结果用成员变量回传（`await` 里观察到的东西带不回来）；每拍**手推一帧 `_process`**
##（与 hud_test 同一手法），否则判定会依赖"引擎这一帧刚好跑到哪"，等于没测。
## 判据不能只看 `shop_layer.visible`：上一段用例可能留下一个"可见"的残留值，
## 必须与"快照里确实开了店、且开的就是这个 peer"同拍成立才算数。
var _saw_shop_beat := false

func _watch_shop(g, peer: int) -> void:
	var entered := false
	var budget := 200          # ≈4 秒上限：判据写错时不至于把整个测试挂死
	while budget > 0:
		budget -= 1
		g._process(0.0)
		if int(g.st.get("shop_open", -1)) >= 0 and int(g.st.get("shop_peer", 0)) == peer:
			entered = true
			if g.shop_layer.visible:
				_saw_shop_beat = true
		if entered and g._shop_peer == 0:
			return
		await create_timer(0.02).timeout

func _run() -> void:
	seed(1)
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(7794, 3) != OK:
		printerr("server create failed"); quit(1); return
	var mp := MultiplayerAPI.create_default_interface()
	mp.multiplayer_peer = peer
	set_multiplayer(mp, "/root")
	create_timer(20.0).timeout.connect(func() -> void:
		printerr("SHOP TEST TIMEOUT"); quit(1)
	)
	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.my_peer = 1

	var idx := _shop_idx()
	print("== 小卖部全链路 ==")
	print("  [debug] visible_rect=%s" % str(root.get_visible_rect().size))
	var p := _mk_player(1, "甲", 5000)
	g.hp = [p]
	var tiles := []
	for i in GameData.TILES.size():
		tiles.append({"owner": GameData.NO_OWNER, "level": 0})
	g.htiles = tiles
	g.shops = {idx: {"slots": ["", "", ""]}}
	g.running = true

	# 会话进行中做检查 + 购买 + 离店（信号在 await 期间触发）
	create_timer(0.4).timeout.connect(func() -> void:
		# 进店会「整架重掷」（#13：每次进店都给新货架）⇒ 单测要验「买第 1 格」，
		# 这里把货架固定成已知内容再广播，而不是指望进店时预置的货还在。
		g.shops[idx].slots = ["招财猫", "平均主义", ""]
		g._broadcast_state()
		g._process(0.016)
		print("  [debug] st.shop_peer=%s st.shop_open=%s layer.visible=%s" % [
			str(g.st.get("shop_peer")), str(g.st.get("shop_open")), str(g.shop_layer.visible)])
		_check(g.shop_layer.visible, "小卖部全屏界面可见")
		_check(g.shop_btns[0].visible and not g.shop_btns[0].disabled, "买按钮可用")
		_check(String(g.shop_cards[0].holder.get_meta("item_id", "")) == "招财猫",
			"第 1 格摆出招财猫卡面")
		g.shop_btns[0].pressed.emit()   # 走真实按钮链路（不再点桌面货架卡）
		_check(p.money == 4400, "点买按钮扣款（5000→4400）")
		_check(p.items.size() == 1 and String(p.items[0].id) == "招财猫", "购入道具")
		g._shop_leave(1)
	)
	await g._run_shop(p, idx)
	await create_timer(0.2).timeout
	_check(p.money == 4400, "购买后扣款（5000→4400）")
	_check(p.items.size() == 1 and String(p.items[0].id) == "招财猫", "道具入包")
	_check(g._shop_peer == 0, "离开后会话结束")

	# ---- ③ 机器人进店也看得见（批次 13 T6）----
	# 机器人在 _bot_shop 里同步买完就走：没有节拍时，「进店」的快照会被同一帧里
	# 「店已关」的快照盖掉，任何一端的 _process 都来不及把界面显出来（用户 ③）。
	print("== 机器人进店也看得见 ==")
	var botp := _mk_player(2, "机器人乙", 5000)
	botp.bot = true
	g.hp = [p, botp]
	g.shops = {idx: {"slots": ["招财猫", "", ""]}}
	g.running = true
	g._process(0.0)                       # 先把上一段的可见性推到当前快照（shop_open = -1）
	_check(not g.shop_layer.visible, "（前置）开跑前小卖部是收起的")
	_saw_shop_beat = false
	_watch_shop(g, 2)                     # 先起观察者；它等会话真的开始才开始计分
	await g._run_shop(botp, idx)
	await create_timer(0.1).timeout       # 留一拍给观察者自行退出
	g._process(0.0)                       # 判定前再手推一帧，不靠帧率
	_check(_saw_shop_beat, "机器人进店过程中，有至少一帧「shop_open >= 0 且小卖部界面可见」")
	_check(g._shop_peer == 0, "机器人离店后会话结束（_shop_peer == 0）")
	_check(not g.shop_layer.visible, "机器人离店后界面重新收起")

	# ---- ④ 品质权重运行时可变（⑧，小卖部.md §二）----
	# 权重是对局状态（game.shop_weights），改它要真实影响铺货；且不许污染 ItemData 常量表。
	print("== 品质权重运行时可变 ==")
	g.hp = [_mk_player(1, "甲", 5000)]
	g.shops = {idx: {"slots": ["", "", ""]}}
	g.shop_weights = {"白": 0, "绿": 100, "蓝": 0, "紫": 0, "橙": 0}
	g._stock_shop(idx, true)
	var all_green := true
	for sid in g.shops[idx].slots:
		var iid := String(sid)
		if iid == "" or String(ItemData.def(iid).quality) != "绿":
			all_green = false
			break
	_check(all_green, "权重全给绿 ⇒ 整架重掷后都是绿货（改权重真实影响铺货）")
	_check(int(ItemData.SHOP_WEIGHTS["白"]) == 40, "对局权重是独立副本，常量表不被污染")

	if fails == 0:
		print("SHOP TEST: ALL PASS")
		quit(0)
	else:
		print("SHOP TEST: %d FAILURES" % fails)
		quit(1)
