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
	_test_roof(g)
	await _test_erging(g)
	_test_card_state(g)
	_test_price_state(g)
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

## 顶楼加盖（own_tile）：`arg` 是**格号**、不是 peer —— 走完整 `_use_item` 链路回归
## 「真机选了地用不出」（原 `_apply_item_effect` 把 tile/own_tile 的 arg 也当 peer 校验）。
func _test_roof(g) -> void:
	print("== 顶楼加盖（格号 ≠ peer） ==")
	var p0 := _mk_player(1, "甲")
	var p1 := _mk_player(2, "乙")
	g.hp = [p0, p1]
	g.htiles = _fresh_tiles()
	var pi := -1
	for k in range(GameData.TILES.size()):
		if String(GameData.TILES[k].get("type", "")) == "property" and k >= 10:
			pi = k
			break
	g.htiles[pi].owner = 1
	g.htiles[pi].level = 1
	p0.items = [{"id": "顶楼加盖", "cd": 0}]
	p0.stamina = 5
	p0.item_used_n = 0
	p0.item_used = false
	g._awaiting_item = 1
	g._item_epoch = 0
	g._use_item(1, 0, pi)
	_check(int(g.htiles[pi].level) == 3, "顶楼加盖：+2 级（格号 %d，实得 Lv%d）" % [pi, int(g.htiles[pi].level)])
	_check(int(p0.stamina) == 2, "顶楼加盖：消耗 3⚡（5→2）")
	_check(p0.items.is_empty(), "顶楼加盖：一次性用后丢弃")

## 二青会酒寒暑（橙·一次性·焚毁）+ 强化版「组队学习·寒暑」（1⚡ / 无冷却 / 独立次数）
func _test_erging(g) -> void:
	print("== 二青会酒寒暑 ==")
	var p0 := _mk_player(1, "甲")
	var p1 := _mk_player(2, "乙")
	g.hp = [p0, p1]
	var dest := _prop_idx(2)           # 找一块真地产当落点（焦土只长在地产上，board_view 要读 price）
	var t := _fresh_tiles()
	t[dest].soil = true                # 落点设焦土，不弹买地询问
	t[dest].soil_prog = 0
	g.htiles = t
	g.shops = {}
	g.items_consumed = {}
	g._awaiting_item = 1
	g._item_epoch = 0
	p0.items = [{"id": "二青会酒寒暑", "cd": 0}]
	p0.stamina = 3
	p0.item_used_n = 0
	p0.item_used = false
	p0.bonus_used = 0
	g._use_item(1, 0, -1)
	_check(p0.stamina == 2, "二青会消耗 1⚡")
	_check(g.items_consumed.has("二青会酒寒暑"), "二青会用后焚毁不回池")
	_check(p0.items.size() == 1 and String(p0.items[0].id) == "组队学习·寒暑", "授予强化版组队学习")
	_check(int(p0.item_used_n) == 1 and bool(p0.item_used), "二青会占用普通使用额度")
	_check(g._item_pool("绿").find("组队学习·寒暑") == -1, "授予件不进随机池（hidden）")
	var grade := ItemData.def("组队学习·寒暑")
	_check(int(grade.get("cost", 0)) == 1, "授予件能量 = 1")
	_check(int(grade.get("cooldown", 0)) == 0, "授予件无冷却")
	_check(bool(grade.get("bonus", false)), "授予件带 bonus 标记")
	# 本回合普通额度已用满（item_used_n=1 / item_used=true），授予件仍可用 → 独立次数
	p0.pos = dest - 2                  # 走 2 步正好落在焦土上
	p0.money = 5000
	_check(g._item_usable_now(p0, p0.items[0]), "普通额度用满后授予件仍可用")
	await g._use_item(1, 0, int(p0.peer))     # 目标给自己：running=false 故只动 p0
	_check(int(p0.bonus_used) == 1, "授予件用后计入独立次数")
	_check(int(p0.item_used_n) == 1, "授予件不写 item_used_n（普通额度不变）")
	_check(int(p0.stamina) == 1, "授予件消耗 1⚡（基础 2 → 1）")
	_check(not g._item_usable_now(p0, p0.items[0]), "独立次数每回合 1 次：再用被挡")
	var stamina2 := int(p0.stamina)
	g._use_item(1, 0, int(p0.peer))
	_check(int(p0.bonus_used) == 1 and int(p0.stamina) == stamina2, "第二次使用不生效")

## §十六 卡面红绿：能量 / 冷却的生效值 vs 基础值
func _test_card_state(g) -> void:
	print("== 卡面红绿（§十六）==")
	var p := _mk_player(1, "甲")
	p.items = [{"id": "交换生", "cd": 0}]
	p.first_used = false
	var s: Dictionary = g._card_state(p, p.items[0])
	_check(int(s.get("cost_eff", -1)) == 3 and int(s.get("cost_base", -1)) == 3, "无修正：能量生效=基础=3")
	_check(int(s.get("cd_preview", -1)) == 3 and int(s.get("cd_base", -1)) == 3, "无修正：冷却预览=基础=3")
	# 错峰用电：本回合首件 -1（绿）
	p.items = [{"id": "交换生", "cd": 0}, {"id": "错峰用电", "cd": 0}]
	s = g._card_state(p, p.items[0])
	_check(int(s.get("cost_eff", -1)) == 2 and int(s.get("cost_base", -1)) == 3, "错峰用电：首件能量 -1（3→2）")
	# 手速惊人：冷却 -1（绿）
	p.items = [{"id": "交换生", "cd": 0}]
	p.tech = "手速惊人"
	s = g._card_state(p, p.items[0])
	_check(int(s.get("cd_preview", -1)) == 2 and int(s.get("cd_base", -1)) == 3, "手速惊人：冷却预览 -1（3→2）")
	# 熟能生巧：冷却 →0（绿）
	p.tech = "熟能生巧"
	s = g._card_state(p, p.items[0])
	_check(int(s.get("cd_preview", -1)) == 0 and int(s.get("cd_base", -1)) == 3, "熟能生巧：冷却预览 →0")
	# 冷却中：不给预览（由 badge_state 给剩余）
	p.tech = ""
	p.items = [{"id": "交换生", "cd": 2}]
	s = g._card_state(p, p.items[0])
	_check(not s.has("cd_preview"), "冷却中不给冷却预览（改显剩余）")

## 单件售价覆盖（二青会 ¥8000）+ 货架冷却预览状态
func _test_price_state(g) -> void:
	print("== 售价覆盖 / 货架冷却预览 ==")
	_check(ItemData.item_price("二青会酒寒暑") == 8000, "二青会单件售价 = ¥8000")
	_check(ItemData.item_price("招财猫") == ItemData.QUALITY_PRICES["白"], "普通件仍按品质定价")
	var ss: Dictionary = ItemData.shop_state("拼车")
	_check(int(ss.get("cd_preview", -1)) == 5, "货架：拼车显示冷却预览 5")
	_check(ItemData.shop_state("刮刮乐").is_empty(), "货架：一次性件无冷却预览")
	_check(ItemData.shop_state("招财猫").is_empty(), "货架：被动件无冷却预览")

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
