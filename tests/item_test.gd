extends SceneTree
## 道具批次四集成单测：蛋蛋节（礼物分发 + 焚毁）/ 亡牌飞行员coco（焦土状态机）
## godot --headless --path . --script tests/item_test.gd

var fails := 0

func _initialize() -> void:
	# 等主循环激活（root 进入场景树）后再跑，避免 RPC/timer 在 _initialize 期间不可用
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

func _mk_player(peer: int, nm: String) -> Dictionary:
	return {"peer": peer, "name": nm, "color": peer - 1, "bot": false, "money": 1000,
		"pos": 0, "alive": true, "skip": 0, "stamina": 3, "items": [], "item_used": false,
		"cheat_roll": -1}

func _run() -> void:
	seed(12345)
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(7792, 3) != OK:
		printerr("server create failed")
		quit(1)
		return
	var mp := MultiplayerAPI.create_default_interface()
	mp.multiplayer_peer = peer
	set_multiplayer(mp, "/root")
	# 看门狗：任何卡死 20s 强制退出，避免 CI 挂起
	create_timer(20.0).timeout.connect(func() -> void:
		printerr("ITEM TEST TIMEOUT")
		quit(1)
	)
	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.running = false  # 冻结主循环：本测试手动摆状态
	_test_egg(g)
	_test_coco(g)
	_test_use_guard(g)
	await _test_soil(g)
	await _test_discover(g)
	if fails == 0:
		print("ITEM TEST: ALL PASS")
		quit(0)
	else:
		print("ITEM TEST: %d FAILURES" % fails)
		quit(1)

func _test_egg(g) -> void:
	print("== 蛋蛋节 ==")
	var p0 := _mk_player(1, "甲")
	var p1 := _mk_player(2, "乙")
	var p2 := _mk_player(3, "丙")
	var p3 := _mk_player(4, "丁")
	p3.alive = false
	p0.items = [{"id": "蛋蛋节", "cd": 0}]
	for i in 5:
		p2.items.append({"id": "招财猫", "cd": 0})
	g.hp = [p0, p1, p2, p3]
	g.htiles = _fresh_tiles()
	g.shops = {}
	g.items_consumed = {}
	g._awaiting_item = 1
	g._item_epoch = 0
	g._use_item(1, 0, -1)
	_check(p0.stamina == 2, "消耗 1 体力")
	_check(bool(p0.item_used), "占用本回合使用额度")
	_check(g.items_consumed.has("蛋蛋节"), "用后焚毁不回池")
	_check(p0.items.size() == 1 and String(p0.items[0].id) != "蛋蛋节", "使用者拿到 1 份礼物")
	var q := String(ItemData.def(String(p0.items[0].id)).quality)
	_check(q == "紫" or q == "橙", "使用者礼物为紫/橙（实得 %s）" % q)
	_check(p2.money == 1100, "满包玩家改发 ¥100")
	_check(p1.items.size() == 1 or p1.money == 1100, "普通玩家收到礼物或现金")
	_check(p3.items.is_empty() and p3.money == 1000, "出局玩家不参与")
	_check(g._item_pool("").find("蛋蛋节") == -1, "焚毁道具已移出可获取池")

## 出局/观战玩家显式禁用道具（台账 §三「观战禁用道具」剩余半条 ⑱）：
## 破产虽已清空背包，`_use_item` 仍要有一道 alive 守卫，挡住其余一切入口。
func _test_use_guard(g) -> void:
	print("== 出局玩家禁用道具 ==")
	var p0 := _mk_player(1, "甲")
	p0.alive = false
	p0.items = [{"id": "招财猫", "cd": 0}]
	g.hp = [p0]
	g.htiles = _fresh_tiles()
	g.shops = {}
	g.items_consumed = {}
	g._awaiting_item = 1
	g._item_epoch = 0
	g._item_action = {}
	g._use_item(1, 0, -1)
	_check(p0.items.size() == 1 and String(p0.items[0].id) == "招财猫", "道具未被消耗")
	_check(int(p0.items[0].cd) == 0 and int(p0.stamina) == 3, "冷却 / 体力未动")
	_check(p0.money == 1000, "效果未生效（招财猫 +400 没发）")
	_check(not bool(p0.item_used), "未占本回合使用额度")
	_check(g._item_action.is_empty(), "未写道具动作（回合流程不被推进）")

func _test_coco(g) -> void:
	print("== 亡牌飞行员coco ==")
	var a := _prop_idx(0)
	var b := _prop_idx(1)
	var c := _prop_idx(2)
	var p0 := _mk_player(1, "甲")  # 持皂施放者，自有地皮 a
	var p1 := _mk_player(2, "乙")  # 地皮 b
	var p2 := _mk_player(3, "丙")  # 地皮 c
	var p3 := _mk_player(4, "丁")  # 无地
	p0.items = [{"id": "亡牌飞行员coco", "cd": 0},
		{"id": "空想者的香皂", "cd": 0, "melt_left": 10}]
	g.hp = [p0, p1, p2, p3]
	var t := _fresh_tiles()
	t[a].owner = 1
	t[a].level = 1
	t[b].owner = 2
	t[b].level = 2
	t[c].owner = 3
	t[c].level = 2
	g.htiles = t
	g.shops = {}
	g.items_consumed = {}
	g._awaiting_item = 1
	g._item_epoch = 0
	g._use_item(1, 0, -1)
	_check(g.items_consumed.has("亡牌飞行员coco"), "用后焚毁不回池")
	_check(not bool(g.htiles[a].get("soil", false)), "持皂施放者自己的地皮无伤")
	_check(int(g.htiles[b].get("owner", -1)) == GameData.NO_OWNER and bool(g.htiles[b].get("soil", false)),
		"受害者乙的地变焦土且无主")
	_check(int(g.htiles[c].get("owner", -1)) == GameData.NO_OWNER and bool(g.htiles[c].get("soil", false)),
		"受害者丙的地变焦土且无主")
	_check(int(g.htiles[b].get("level", -1)) == 0, "焦土等级清零")
	_check(p3.items.is_empty(), "无地玩家不产生焦土")
	var soil_n := 0
	for tile in g.htiles:
		if bool(tile.get("soil", false)):
			soil_n += 1
	_check(soil_n == 2, "每人至多一块地化焦土（实得 %d）" % soil_n)
	g._broadcast_state()  # 贯通渲染层：焦土配色/进度文本不应报错

## 「发现」三选一（术语表.md）：失物招领格改版后的载体。bot / 回退路径 + 私密候选结构
func _test_discover(g) -> void:
	print("== 发现三选一 ==")
	var p := _mk_player(1, "甲")
	var other := _mk_player(2, "乙")
	g.hp = [p, other]
	p.items = []
	# 正常流程：返回一件候选内的道具、进包、候选结构合法（≤3 件、彼此不同、全在白池内）。
	# 池子先快照：拿到手后唯一道具会立刻退出可获取池，事后查会对不上。
	var pool_before: Array = g._item_pool("白").duplicate()
	var id: String = await g._run_discover(p, "白", "失物招领")
	_check(id != "", "「发现」拿到了一件道具")
	_check(g._discover_offered.size() >= 2 and g._discover_offered.size() <= 3,
		"候选 2~3 件（池子不足 3 件时给几件算几件）")
	var seen := {}
	var in_pool := true
	for oid in g._discover_offered:
		seen[String(oid)] = true
		if not pool_before.has(String(oid)):
			in_pool = false
	_check(seen.size() == g._discover_offered.size(), "候选彼此不同")
	_check(in_pool, "候选全部来自目标品质的可获取池")
	_check(g._discover_offered.has(id), "拿到的是候选之一")
	_check(p.items.size() == 1 and String(p.items[0].id) == id, "选中的道具进了背包")
	# 背包满：不再触发，返回空串
	p.items = []
	for i in 5:
		p.items.append({"id": "招财猫" if i == 0 else "黑卡", "cd": 0})
	var full: int = g._bag_cap(p)   # g 是 Node：动态调用推不出类型，显式标 int
	while p.items.size() < full:
		p.items.append({"id": "校园卡", "cd": 0})
	var none: String = await g._run_discover(p, "白", "失物招领")
	_check(none == "" and p.items.size() == full, "背包满：不触发发现、背包不变")
	g.hp = []

func _test_soil(g) -> void:
	print("== 焦土捐款与恢复 ==")
	var a := _prop_idx(2)
	var price := int(GameData.TILES[a].price)
	var p := _mk_player(1, "甲")
	p.money = 5000
	p.pos = a
	g.hp = [p]
	var t := _fresh_tiles()
	t[a].soil = true
	t[a].soil_prog = 0
	g.htiles = t
	await g._resolve_tile(p)
	_check(p.money == 5000 - ItemData.SOIL_DONATE, "落地焦土自动扣捐款")
	_check(int(g.htiles[a].soil_prog) == ItemData.SOIL_DONATE, "捐款累进进度")
	# 达标恢复
	p.pos = a
	p.money = 5000
	g.htiles[a].soil_prog = price - ItemData.SOIL_DONATE
	await g._resolve_tile(p)
	_check(not bool(g.htiles[a].soil), "进度达标后焦土恢复")
	_check(int(g.htiles[a].owner) == GameData.NO_OWNER, "恢复后变为无主")
	_check(int(g.htiles[a].soil_prog) == 0, "恢复后进度清零")
	g._broadcast_state()  # 恢复后再渲染一次：废墟配色应还原
	# 香皂免疫：不扣钱、进度不涨
	var p2 := _mk_player(2, "乙")
	p2.items = [{"id": "空想者的香皂", "cd": 0, "melt_left": 10}]
	p2.money = 5000
	p2.pos = a
	g.hp = [p2]
	var t2 := _fresh_tiles()
	t2[a].soil = true
	t2[a].soil_prog = 100
	g.htiles = t2
	await g._resolve_tile(p2)
	_check(p2.money == 5000, "香皂挡下焦土捐款（不扣钱）")
	_check(int(g.htiles[a].soil_prog) == 100, "香皂挡下时进度不涨")
