extends SceneTree
## 畸变系统集成单测：两道闸门（每回合 1 条 / 持续型唯一生效）、顺延队列、
## 14 条效果逐条钉住、香皂免疫、快照字段。
## 跑法：godot --headless --path . --script tests/aberration_test.gd
## 规则来源：doc/game-design/畸变.md（触发限制 2026-10-04 定稿）

var fails := 0

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)
	create_timer(30.0).timeout.connect(func() -> void:
		printerr("ABERRATION TEST: WATCHDOG TIMEOUT")
		quit(1))

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

func _soap(p: Dictionary) -> void:
	p.items.append({"id": "空想者的香皂", "cd": 0, "melt_left": 10})

func _ab(g: Node, id: String, left: int) -> void:
	g._ab_active.append({"id": id, "left": left})

func _run() -> void:
	seed(12345)
	var mp := ENetMultiplayerPeer.new()
	var err := mp.create_server(7793, 3)
	if err != OK:
		printerr("ABERRATION TEST: cannot create server: %d" % err)
		quit(1)
		return
	root.multiplayer.multiplayer_peer = mp
	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	await process_frame
	if g.board == null:
		printerr("对局场景未正确加载（脚本编译失败？）")
		quit(1)
		return
	g.running = false   # 冻结主循环：手动摆状态
	g._settings.ab_freq = "关"   # 窗口测试默认不掷随机，条件型手动摆
	g._settings.ab_cond = true

	# ---------- 闸门与挑选（_ab_pick 纯逻辑） ----------
	print("== 两道闸门 ==")
	_check(g._ab_pick([{"id": "通胀", "prio": 1}, {"id": "天降红包", "prio": 1}]) in ["通胀", "天降红包"],
		"同级随机候选掷骰决出一条")
	_check(g._ab_pick([{"id": "天降红包", "prio": 1}, {"id": "拆迁", "prio": 0}]) == "拆迁",
		"条件触发优先于随机触发")
	_ab(g, "通胀", 2)
	_check(g._ab_pick([{"id": "天降红包", "prio": 1}]) == "", "闸门二：持续型生效中随机候选作废")
	_check(g._ab_pick([{"id": "枪打出头鸟", "prio": 0}]) == "" and g._ab_queue == ["枪打出头鸟"],
		"闸门二：条件型生效中转顺延队列")
	g._ab_active.clear()   # 解封后验证插队与落选顺延
	_check(g._ab_pick([{"id": "房价崩盘", "prio": -1}, {"id": "枪打出头鸟", "prio": 0}]) == "房价崩盘",
		"顺延补发插队：队列候选压过新条件")
	_check(g._ab_pick([{"id": "枪打出头鸟", "prio": 0}, {"id": "房价崩盘", "prio": 0}]) in ["枪打出头鸟", "房价崩盘"]
		and g._ab_queue.size() == 1, "闸门一：条件型落选者顺延（队列 ≤2）")
	_ab(g, "强制捐款", 1)
	_ab(g, "隔离", 1)
	_ab_enqueue_triple(g)
	_check(g._ab_queue.size() == 2, "顺延队列上限 2，超出丢弃")
	g._ab_active.clear()
	g._ab_queue.clear()

	# ---------- 公告文案（畸变可读性，台账 §六 #28） ----------
	print("== 公告文案 ==")
	var t1: String = g._ab_announce_text("限电", 2)
	_check(t1.contains("体力") and t1.contains("持续 2 回合") and t1.contains("到期自动解除"),
		"持续型公告带效果全文 + 持续回合 + 自动解除（畸变无手动解除）")
	var t2: String = g._ab_announce_text("金融危机")
	_check(t2.contains("无房产者扣 10%") and t2.contains("有房产者扣 20%"),
		"比例类公告带实时数值（占位 10% / 20%）")
	var t3: String = g._ab_announce_text("天降红包")
	_check(not t3.contains("持续"), "非持续型公告不带持续回合")

	# ---------- 条件检测与窗口 ----------
	print("== 条件触发与窗口 ==")
	var p1 := _mk_player(1, "甲")
	var p2 := _mk_player(2, "乙")
	p1.money = 40000
	g.hp = [p1, p2]
	g.htiles = _fresh_tiles()
	g._ab_active = []
	g._ab_queue = []
	g._ab_fired = {}
	g._aberration_window(p1)
	_check(int(p1.money) == 40000 - 8000, "枪打出头鸟：现金 40000 被强制捐款 20%%（-8000）")
	_check(bool(g._ab_fired.get("枪打出头鸟", false)), "条件型一次性标记已写")
	# 闸门二拦截 → 顺延 → 解封后补发
	p1.money = 40000
	g._ab_fired = {}
	_ab(g, "通胀", 2)
	g._aberration_window(p1)
	_check(int(p1.money) == 40000, "通胀生效中：条件候选被拦下（不扣钱）")
	_check(g._ab_queue == ["枪打出头鸟"] and bool(g._ab_fired.get("枪打出头鸟", false)),
		"被拦的条件进顺延队列且已记一次性")
	_check(int(g._ab_active[0].left) == 1, "持续型按玩家回合计时：窗口 tick 后剩 1")
	g._ab_active.clear()
	g._aberration_window(p1)
	_check(int(p1.money) == 40000 - 8000 and g._ab_queue.is_empty(),
		"解封后顺延补发：枪打出头鸟从队列触发")

	# ---------- 逐条效果 ----------
	print("== 持续型效果 ==")
	g._ab_active = []
	g.htiles = _fresh_tiles()
	var shop_idx := -1
	var prop_idx := -1
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "property" and prop_idx < 0:
			prop_idx = i
		if String(GameData.TILES[i].get("type", "")) == "shop" and shop_idx < 0:
			shop_idx = i
	g.htiles[prop_idx] = {"owner": 2, "level": 0}
	var base_rent: int = GameData.rent_for(prop_idx, g.htiles)
	p1.money = 50000
	p2.money = 100
	g._resolve_rent(p1, prop_idx)
	_check(int(p2.money) == 100 + base_rent, "无畸变：租金按基础价结算")
	p2.money = 100
	_ab(g, "通胀", 2)
	g._resolve_rent(p1, prop_idx)
	_check(int(p2.money) == 100 + base_rent * 2, "通胀：租金 ×2")
	g._ab_active = [{"id": "房价崩盘", "left": 3}]
	g._resolve_rent(p1, prop_idx)
	_check(int(p2.money) == 100 + base_rent * 2 + int(base_rent * 0.5), "房价崩盘：租金减半")
	g._ab_active = []
	_check(g._ab_rent_mult() == 1.0, "无畸变：租金倍率 1.0")

	p1.stamina = 2
	_ab(g, "限电", 2)
	g._item_turn_start(p1)
	_check(int(p1.stamina) == 2, "限电：回合开始体力不再 +1")
	g._ab_active = []
	g._item_turn_start(p1)
	_check(int(p1.stamina) == 3, "限电结束：体力恢复 +1")
	_ab(g, "奖学金季", 2)
	var m0 := int(p1.money)
	g._item_turn_start(p1)
	_check(int(p1.money) == m0 + 300, "奖学金季：自己回合开始 +¥300")
	g._ab_active = []

	print("== 隔离与停电 ==")
	_ab(g, "隔离", 2)
	_check(g._ab_move_cut(p1) == 2, "隔离：移动点数 −2")
	_soap(p2)
	_check(g._ab_move_cut(p2) == 0, "隔离：持皂者免疫")
	g._ab_active = []
	_check(g._ab_move_cut(p1) == 0, "隔离结束：不再削减")
	_ab(g, "停电", 2)
	p1.pos = shop_idx
	await g._resolve_tile(p1)
	_check(int(g._shop_peer) == 0, "停电：落小卖部格不进店（=路过）")
	g._ab_active = []

	print("== 瞬间结算效果 ==")
	p1.money = 5000
	p2.money = 5000
	p2.items = []   # 去皂再测
	g._ab_apply_instant(p1, "天降红包")
	_check(int(p1.money) == 5500 and int(p2.money) == 5500, "天降红包：全员 +¥500")
	g._ab_apply_instant(p1, "强制捐款")
	_check(int(p1.money) == 5000 and int(p2.money) == 5000, "强制捐款：全员 −¥500")
	_soap(p2)
	g._ab_apply_instant(p1, "强制捐款")
	_check(int(p2.money) == 5000 and int(p1.money) == 4500, "强制捐款：持皂者免疫")
	p2.items = []
	p1.items = []
	g._ab_apply_instant(p1, "集体感冒")
	_check(int(p1.get("sleep", 0)) == 1 and int(p2.get("sleep", 0)) == 1, "集体感冒：全员下回合休眠")
	_soap(p2)
	p2.sleep = 0
	g._ab_apply_instant(p1, "集体感冒")
	_check(int(p2.get("sleep", 0)) == 0, "集体感冒：持皂者不休眠")
	p2.items = []
	p1.money = 10000
	g._ab_apply_instant(p1, "金融危机")
	_check(int(p1.money) == 9000, "金融危机：无房产扣 10%%")
	g.htiles[prop_idx] = {"owner": 1, "level": 0}
	p1.money = 10000
	g._ab_apply_instant(p1, "金融危机")
	_check(int(p1.money) == 8000, "金融危机：有房产扣 20%%")
	g.htiles[prop_idx] = {"owner": GameData.NO_OWNER, "level": 0}

	print("== 拆迁 ==")
	g.htiles = _fresh_tiles()
	var t_a := prop_idx
	var t_b := (prop_idx + 1) % GameData.TILES.size()
	while String(GameData.TILES[t_b].get("type", "")) != "property":
		t_b = (t_b + 1) % GameData.TILES.size()
	g.htiles[t_a] = {"owner": 1, "level": 1}
	g.htiles[t_b] = {"owner": 2, "level": 2}
	var owned_before := 2
	seed(777)
	g._ab_apply_instant(p1, "拆迁")
	var owned_after := int(g.htiles[t_a].owner != GameData.NO_OWNER) + int(g.htiles[t_b].owner != GameData.NO_OWNER)
	_check(owned_after < owned_before, "拆迁：至少一块地变无主")
	var wrecked := [t_a, t_b].filter(func(i: int) -> bool: return int(g.htiles[i].owner) == GameData.NO_OWNER)
	var lv_ok := true
	for i in wrecked:
		lv_ok = lv_ok and int(g.htiles[i].level) == 0
	_check(lv_ok or wrecked.is_empty(), "拆迁：被拆地块等级清零")
	_soap(p1)
	g.htiles[t_a] = {"owner": 1, "level": 3}
	for r in range(20):
		g._ab_apply_instant(p1, "拆迁")
	_check(int(g.htiles[t_a].owner) == 1, "拆迁：持皂地主的街道不被拆")
	p1.items = []

	print("== 诚信考试 / 调休 ==")
	g._ab_apply_persistent_start(p1, "诚信考试")
	_check(int(p1.get("silence", 0)) == 1, "诚信考试：当前行动者本回合禁道具")
	_check(not g._has_usable(p1), "诚信考试：_has_usable 拦住道具阶段")
	_soap(p2)
	g._ab_apply_persistent_start(p2, "诚信考试")
	_check(int(p2.get("silence", 0)) == 0, "诚信考试：持皂者不受封")
	p2.items = []
	p1.silence = 0
	p1.sleep = 0   # 前面集体感冒留下的休眠要清掉，否则调休补班被正确推迟
	g._ab_apply_instant(p1, "调休")
	_check(bool(g._ab_no_roll) and int(g._ab_extra_peer) == 1, "调休：本回合停转 + 自己下回合补班")
	g._ab_no_roll = false
	g._aberration_window(p1)
	_check(bool(p1.get("ab_extra_roll", false)) and int(g._ab_extra_peer) == GameData.NO_PEER,
		"调休：下一个自己的回合消费补班标记")
	# ---- 批次 13 ④ 回归：哨兵撞车（真 bug，已修）----
	# 旧实现 `_ab_extra_peer := -1` 与**第一台机器人**的 peer id（机器人从 −1 起编号）撞车 ⇒
	# 那台机器人**每回合**白拿一次双掷，且与畸变开关无关（`_aberration_window` 的比对在
	# 频率闸门之前）。两条判据：① 哨兵本身不许是 −1；② 畸变关闭时 peer=−1 的玩家拿不到补班。
	_check(int(g._ab_extra_peer) != -1,
		"调休补班哨兵不是 −1（机器人 peer 从 −1 起编号，撞车会让第一台机器人每回合白拿双掷）")
	var bot := _mk_player(-1, "机器人A")
	bot.bot = true
	# **有意不预设 `_ab_extra_peer`**：就是要看"干净状态"下 peer=−1 的人会不会被误判为待补班。
	g._aberration_window(bot)
	_check(not bool(bot.get("ab_extra_roll", false)),
		"畸变关闭时 peer=−1 的机器人不白拿双掷（哨兵撞车回归）")

	print("== 快照字段 ==")
	_ab(g, "通胀", 2)
	g._settings.ab_freq = "低"
	g._settings.ab_dur = 3
	g._broadcast_state()
	await process_frame
	var snap: Array = g.st.get("aberrations", [])
	_check(snap.size() == 1 and String(snap[0].id) == "通胀" and int(snap[0].left) == 2,
		"快照：aberrations 字段随状态下发")
	_check(String(g.st.get("ab_freq", "")) == "低" and int(g.st.get("ab_dur", 0)) == 3,
		"快照：ab_freq / ab_dur 随状态下发")
	g.st = {}

	if fails == 0:
		print("ABERRATION TEST: ALL PASS")
		quit(0)
	else:
		print("ABERRATION TEST: %d FAILURES" % fails)
		quit(1)

## 连续入队 3 条（队列只有 2 个位置），验证上限丢弃
func _ab_enqueue_triple(g: Node) -> void:
	g._ab_queue.clear()
	g._ab_enqueue("天降红包")
	g._ab_enqueue("强制捐款")
	g._ab_enqueue("集体感冒")
