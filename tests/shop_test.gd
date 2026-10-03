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
	g.shops = {idx: {"slots": ["招财猫", "平均主义", ""]}}
	g.running = true

	# 会话进行中做检查 + 购买 + 离店（信号在 await 期间触发）
	create_timer(0.4).timeout.connect(func() -> void:
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

	if fails == 0:
		print("SHOP TEST: ALL PASS")
		quit(0)
	else:
		print("SHOP TEST: %d FAILURES" % fails)
		quit(1)
