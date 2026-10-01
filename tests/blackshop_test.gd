extends SceneTree
## 黑市集成单测：地皮计价 / 逐块交地 / 挨打小黑屋 / bot 策略 / 机会卡过滤
## godot --headless --path . --script tests/blackshop_test.gd

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

func _prop_idx(offset: int) -> int:
	var n := 0
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "property":
			if n == offset:
				return i
			n += 1
	return -1

func _mk_player(peer: int, nm: String, money := 1000) -> Dictionary:
	return {"peer": peer, "name": nm, "color": peer - 1, "bot": false, "money": money,
		"pos": 0, "alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [],
		"item_used": false, "cheat_roll": -1}

func _run() -> void:
	seed(2026)
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(7793, 3) != OK:
		printerr("server create failed")
		quit(1)
		return
	var mp := MultiplayerAPI.create_default_interface()
	mp.multiplayer_peer = peer
	set_multiplayer(mp, "/root")
	create_timer(20.0).timeout.connect(func() -> void:
		printerr("BLACK TEST TIMEOUT")
		quit(1)
	)
	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.running = false
	_test_buy(g)
	_test_insufficient(g)
	_test_exit(g)
	_test_refresh(g)
	_test_bot(g)
	_test_stock_unique(g)
	_test_sleep(g)
	_test_events(g)
	await _test_session(g)
	await _test_session_empty(g)
	if fails == 0:
		print("BLACK TEST: ALL PASS")
		quit(0)
	else:
		print("BLACK TEST: %d FAILURES" % fails)
		quit(1)

func _setup(g, players: Array, tiles: Array, slots: Array) -> void:
	g.hp = players
	g.htiles = tiles
	g.shops = {}
	g.items_consumed = {}
	g._black_slots = slots.duplicate()
	g._black_pay_mode = ""
	g._black_pay_got = 0
	g._black_pay_slot = -1

func _test_buy(g) -> void:
	print("== 买紫货（1 块地皮）==")
	var a := _prop_idx(0)
	var p := _mk_player(1, "甲")
	var t := _fresh_tiles()
	t[a].owner = 1
	t[a].level = 2
	_setup(g, [p], t, ["平均主义", "", ""])
	g._black_peer = 1
	g._black_buy(1, 0)
	_check(g._black_pay_mode == "buy" and g._black_pay_need == 1, "进入交地支付（需 1 块）")
	g._black_pay(1, a)
	_check(int(g.htiles[a].owner) == GameData.NO_OWNER and int(g.htiles[a].level) == 0, "交出地皮回归无主且等级清零")
	_check(p.items.size() == 1 and String(p.items[0].id) == "平均主义", "获得所购道具")
	_check(String(g._black_slots[0]) == "", "货架该栏清空")
	_check(g._black_peer == 1 and g._black_pay_mode == "", "买完仍留在黑市")

func _test_insufficient(g) -> void:
	print("== 凑不出货钱 → 挨打 + 小黑屋 ==")
	var p := _mk_player(1, "甲", 1000)
	var t := _fresh_tiles()
	_setup(g, [p], t, ["黑卡", "", ""])  # 橙，需 2 块地皮
	g._black_peer = 1
	g._black_buy(1, 0)
	_check(g._black_peer == 0, "被扔出黑市")
	_check(p.money == 500, "扣当前现金一半（1000→500）")
	_check(int(p.sleep) == 1, "进入小黑屋（休眠一回合）")

func _test_exit(g) -> void:
	print("== 出口费 1 块 ==")
	var a := _prop_idx(1)
	var p := _mk_player(1, "甲")
	var t := _fresh_tiles()
	t[a].owner = 1
	_setup(g, [p], t, ["平均主义", "", ""])
	g._black_peer = 1
	g._black_leave(1)
	_check(g._black_pay_mode == "exit", "进入出口支付")
	g._black_pay(1, a)
	_check(g._black_peer == 0, "结清出口费后离店")
	_check(int(g.htiles[a].owner) == GameData.NO_OWNER, "出口费按地皮扣除")

func _test_refresh(g) -> void:
	print("== 刷新 1 块（不涨价）==")
	var a := _prop_idx(2)
	var p := _mk_player(1, "甲")
	var t := _fresh_tiles()
	t[a].owner = 1
	_setup(g, [p], t, ["平均主义", "黑卡", "作弊器"])
	g._black_peer = 1
	g._black_refresh(1)
	_check(g._black_pay_mode == "refresh" and g._black_pay_need == 1, "进入刷新支付")
	g._black_pay(1, a)
	_check(int(g.htiles[a].owner) == GameData.NO_OWNER, "刷新按地皮扣费")
	_check(g._black_peer == 1 and g._black_pay_mode == "", "刷新后仍在黑市")
	var filled := 0
	for s in g._black_slots:
		if String(s) != "":
			filled += 1
	_check(filled >= 1, "货架重新铺货")

func _test_bot(g) -> void:
	print("== bot：买最值一件并留出口费 ==")
	var a := _prop_idx(3)
	var b := _prop_idx(4)
	var c := _prop_idx(5)
	var p := _mk_player(1, "机器人甲")
	p.bot = true
	var t := _fresh_tiles()
	t[a].owner = 1
	t[b].owner = 1
	t[c].owner = 1
	_setup(g, [p], t, ["平均主义", "黑卡", ""])  # 紫1 / 橙2
	g._black_peer = 1
	g._bot_blackshop(p)
	_check(p.items.size() == 1 and String(p.items[0].id) == "黑卡", "bot 选最值的橙货")
	_check(g._black_peer == 0, "bot 交完出口费离店")
	_check((g.htiles[a].owner as int) == GameData.NO_OWNER, "bot 用地皮结账")

func _test_stock_unique(g) -> void:
	print("== 货架唯一性 ==")
	var p := _mk_player(1, "甲")
	_setup(g, [p], _fresh_tiles(), ["", "", ""])
	for round_i in 12:
		g._black_slots = ["", "", ""]
		g._black_stock()
		var seen := {}
		var dup := false
		for s in g._black_slots:
			var id := String(s)
			if id == "" or not bool(ItemData.def(id).unique):
				continue
			if seen.has(id):
				dup = true
			seen[id] = true
		if dup:
			_check(false, "黑市货架重复上架唯一道具（第 %d 次）" % round_i)
			return
	_check(true, "黑市货架不重复上架同一唯一道具")

func _test_sleep(g) -> void:
	print("== 小黑屋休眠=保守托管 ==")
	var p := _mk_player(1, "甲")
	_setup(g, [p], _fresh_tiles(), ["", "", ""])
	_check(not g._is_sleeping(p), "初始不在小黑屋")
	p.sleep = 1
	_check(g._is_sleeping(p) and g._is_managed(p), "标记为休眠托管")
	var ok: bool = g._ask(p, "buy", 100, "买", "买？", "买")
	_check(not ok, "休眠时买地一律拒绝")

func _test_events(g) -> void:
	print("== 机会卡池过滤 ==")
	var chance := GameData.events_for("机会")
	var fate := GameData.events_for("命运")
	var has_black := false
	for e in chance:
		if e.has("enter_blackshop"):
			has_black = true
	_check(has_black, "机会格卡池含进入黑市")
	var fate_has := false
	for e in fate:
		if e.has("enter_blackshop"):
			fate_has = true
	_check(not fate_has, "命运格卡池不含进入黑市（only 过滤）")
	g.blackshop_enabled = false
	var leaked := false
	for i in 60:
		if g._draw_event("机会").has("enter_blackshop"):
			leaked = true
			break
	_check(not leaked, "关闭黑市后机会卡不再发出该事件")
	g.blackshop_enabled = true

## 端到端：进入黑市会话 → 玩家交费离店
func _test_session(g) -> void:
	print("== 会话全流程 ==")
	var a := _prop_idx(6)
	var p := _mk_player(1, "甲")
	var t := _fresh_tiles()
	t[a].owner = 1
	_setup(g, [p], t, ["", "", ""])
	g.running = true  # 会话循环需要 running
	# 定时器在会话进行中触发离店（await 期间）
	create_timer(0.9).timeout.connect(func() -> void:
		if g._black_peer != 1:
			return
		g._black_leave(1)
		var props: Array = g._prop_indices_of(1)
		if not props.is_empty():
			g._black_pay(1, int(props[0]))
	)
	await g._run_blackshop(p)  # 等会话收尾
	g.running = false
	_check(g._black_peer == 0, "离店后会话结束")
	_check(int(g.htiles[a].owner) == GameData.NO_OWNER, "离店时扣了出口费")

## 端到端：0 地皮进店即挨打
func _test_session_empty(g) -> void:
	print("== 0 地皮进店 ==")
	var p := _mk_player(1, "甲", 800)
	_setup(g, [p], _fresh_tiles(), ["", "", ""])
	await g._run_blackshop(p)
	_check(g._black_peer == 0, "无地皮被直接扔出")
	_check(p.money == 400 and int(p.sleep) == 1, "立即挨打 + 小黑屋")
