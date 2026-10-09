extends SceneTree
## 科技集成单测：掷骰定档 / 同档抽三 / 全 bot 跑通科技阶段 /
## 逐条效果（上限叠加、回合开始型、路径收益、折扣、保单、里程碑、回收返现）/ 快照字段。
## 跑法：godot --headless --path . --script tests/tech_test.gd
## 规则来源：doc/game-design/科技.md（2026-10-04 定稿）

var fails := 0

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)
	create_timer(40.0).timeout.connect(func() -> void:
		printerr("TECH TEST: WATCHDOG TIMEOUT")
		quit(1))

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

## 递归收一棵子树里所有 Label 的文本（弹层 / 演出层的文案断言用；本文件原先没有）。
func _labels_under(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append(String((n as Label).text))
	for c in n.get_children():
		out.append_array(_labels_under(c))
	return out

func _fresh_tiles() -> Array:
	var out := []
	for i in GameData.TILES.size():
		out.append({"owner": GameData.NO_OWNER, "level": 0})
	return out

func _mk_player(peer: int, nm: String) -> Dictionary:
	return {"peer": peer, "name": nm, "color": peer - 1, "bot": false, "money": 20000,
		"pos": 0, "alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [],
		"item_used": false, "cheat_roll": -1, "hot_chain": 0,
		"techs": [], "wuyun_left": 0, "yanguang_left": 0, "kingtu": 0}

## 科技容器与发放函数（2026-10-10 方案 B）：`p.techs` 是列表、`_grant_tech` 幂等且走 implemented 闸。
## 「科技可以有多条」从这一天起是**数据形状上的事实** —— 但唯一发放路径仍是发车前那次三选一（恰好 1 条）。
func _test_grant_tech(g) -> void:
	print("== _grant_tech：幂等 + implemented 闸 ==")
	var p := _mk_player(1, "甲")
	_check((p.techs as Array).is_empty(), "_mk_player 造出来的科技列表是空的")
	_check(bool(TechData.def("助学金").implemented), "（前置）助学金已实装")
	_check(g._has_tech(p, "助学金") == false, "（前置）空列表下 _has_tech 为假")
	p.techs = ["助学金"]
	_check(g._has_tech(p, "助学金") == true, "_has_tech 认列表里的条目")
	_check(g._has_tech(p, "天选之人") == false, "_has_tech 对不在列表里的条目为假")
	# 幂等：重复发放不叠加、不改动列表，且返回 false（`_grant_tech` **不是协程**，直接调、不用 await）
	p.techs = []
	_check(g._grant_tech(p, "助学金") == true, "首次发放成功（true）")
	_check((p.techs as Array) == ["助学金"], "列表里就这一条")
	_check(g._grant_tech(p, "助学金") == false, "重复发放返回 false（幂等，不做数值补偿）")
	_check((p.techs as Array).size() == 1, "重复发放不叠加（仍然是 1 条）")
	# implemented 闸：此刻「眼尖手快」是**唯一**一条未定稿的（T5 会翻成 true）—— 用它当活体样本。
	# ⚠ T5 落地时这两行**整段删掉**（它一实装这条就红），见 T5 Step 1。
	_check(g._grant_tech(p, "眼尖手快") == false, "未定稿的科技发不出去（implemented 闸）")
	_check(g._grant_tech(p, "查无此科技") == false, "表里没有的名字发不出去")
	_check((p.techs as Array).size() == 1, "被闸门挡下的都没进列表")
	# 多条共存：结构上成立（本批在对局上仍不可达，唯一路径是发车前那次三选一）
	g._grant_tech(p, "天选之人")
	_check((p.techs as Array).size() == 2 and g._has_tech(p, "助学金") and g._has_tech(p, "天选之人"),
		"两条共存：结构上支持「科技可以有多条」")

func _run() -> void:
	seed(4321)
	var mp := ENetMultiplayerPeer.new()
	if mp.create_server(7794, 3) != OK:
		printerr("TECH TEST: cannot create server")
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
	g.running = false   # 冻结主循环
	g._settings.ab_freq = "关"
	await create_timer(2.0).timeout   # 等 _host_setup 恢复执行完（1.5s）且 _run_game 因 running=false 退出，避免并发

	# ---------- 定档与抽卡 ----------
	print("== 随机定档与抽卡 ==")
	# 2026-10-09：取代原「掷骰 1~6 → 三档」那三条映射断言。骰子已删，但**分布必须仍是等分**
	# （原路 = 均匀 6 面映射到 3 档 = 各 1/3）⇒ 这里改成抽一批看三档都出现过、且不越界。
	var seen := {}
	for i in 600:
		seen[TechData.random_tier()] = true
	_check((seen.keys() as Array).all(func(t: String) -> bool: return t in TechData.TIERS),
		"随机定档只会抽到三档之内（实得 %s）" % str(seen.keys()))
	_check(seen.size() == TechData.TIERS.size(),
		"随机定档抽 600 次三档都出现过（不是死抽一档，实得 %d 档）" % seen.size())
	# 2026-10-10 批 1 审查 I4：「眼尖手快」标 implemented:false ⇒ 移出抽取池 ⇒ 白银可用池 20 → 19
	_check((TechData.pool("白银") as Array).size() == 19, "白银池 19 条（「眼尖手快」未实装、已移出池）")
	_check((TechData.pool("黄金") as Array).size() == 19, "黄金池 19 条（样板房弃案留空）")
	_check((TechData.pool("钻石") as Array).size() == 20, "钻石池 20 条")
	var ok3 := true
	for r in range(10):
		var s: Array = g._tech_sample("白银")
		ok3 = ok3 and s.size() == 3 and s[0] != s[1] and s[1] != s[2] and s[0] != s[2]
		ok3 = ok3 and (s as Array).all(func(n: String) -> bool: return n in TechData.pool("白银"))
	_check(ok3, "同档抽 3 张且互不重复")

	# ---------- 定档演出（2026-10-07 补齐；2026-10-09 去掉骰面） ----------
	print("== 定档演出 ==")
	# 2026-10-09 起配色**唯一来源**是 `TechData.TIER_COLORS`（原在 `game.gd._tier_color()`，
	# 挪走是为了让图鉴生成器也能读它）—— 所以这里直接钉 TechData，不再绕 `g._tier_color`。
	_check(TechData.tier_color("白银") != TechData.tier_color("黄金")
		and TechData.tier_color("黄金") != TechData.tier_color("钻石")
		and TechData.tier_color("白银") != TechData.tier_color("钻石"), "三档等级色互不相同")
	# 钉住**那一层本身**，别数 `get_child_count()`：对局的广播刷新会不停增删自己的子节点
	# （实测这 2.8 秒里别的分支增删了 90 来个），总数对比会假红/假绿。做法 = 演出前后做差集，
	# 找出新挂上的那一层，随后只看它有没有被释放。
	var kids_before := {}
	for c in g.get_children():
		kids_before[c] = true
	g._show_tech_tier("黄金")
	var layer: Node = null
	for c in g.get_children():
		if not kids_before.has(c):
			layer = c
			break
	_check(layer != null and (layer as Control).z_index == 75, "定档演出挂了一层屏幕层控件（z=75）")
	_check(_labels_under(layer).has("科技 · 本局等级"),
		"定档演出标题 = 「科技 · 本局等级」（实得 %s）" % str(_labels_under(layer)))
	await create_timer(2.8).timeout
	await process_frame
	_check(not is_instance_valid(layer), "定档演出自动收（那一层已释放）")

	# ---------- 全 bot 跑通科技阶段 ----------
	print("== 科技阶段（全 bot） ==")
	var p1 := _mk_player(1, "甲")
	var p2 := _mk_player(2, "乙")
	p1.bot = true
	p2.bot = true
	g.hp = [p1, p2]
	g.htiles = _fresh_tiles()
	g._settings.tech_on = true
	g.running = true   # 科技阶段内部有 while running 守卫，需临时解冻
	await g._tech_phase()
	g.running = false
	_check(g._tech_tier in TechData.TIERS,
		"随机定档：本局档落在三档之内 = %s" % g._tech_tier)
	_check((p1.techs as Array).size() == 1 and String(p1.techs[0]) in TechData.pool(g._tech_tier)
		and (p2.techs as Array).size() == 1 and String(p2.techs[0]) in TechData.pool(g._tech_tier),
		"全员都拿到了本档科技（各 1 条）")
	_check(not bool(g._tech_open), "科技阶段结束：三选一阶段收口（tech_open=false）")
	g._settings.tech_on = false

	# ---------- 房主指定等级（2026-10-07） ----------
	print("== 房主指定科技等级 ==")
	g.hp = [_mk_player(1, "甲"), _mk_player(2, "乙")]
	g.hp[0].bot = true
	g.hp[1].bot = true
	g._settings.tech_on = true
	g._settings.tech_tier = "钻石"
	g.running = true
	await g._tech_phase()
	g.running = false
	_check(g._tech_tier == "钻石", "指定「钻石」→ 不随机，本局档 = 钻石（实得 %s）" % g._tech_tier)
	_check((g.hp[0].techs as Array).size() == 1 and String(g.hp[0].techs[0]) in TechData.pool("钻石"),
		"指定档抽卡来自钻石池（各 1 条）")
	g._settings.tech_tier = GameSettings.TECH_TIER_RANDOM
	g._settings.tech_on = false

	# ---------- 全员**同时**三选一（2026-10-07：原先逐个问） ----------
	print("== 全员同时三选一 ==")
	var h1 := _mk_player(1, "甲")
	var h2 := _mk_player(2, "乙")
	g.hp = [h1, h2]
	g.htiles = _fresh_tiles()
	g._settings.tech_on = true
	g._settings.tech_tier = "白银"
	g.running = true
	g._tech_phase()   # 后台跑（不 await：本测试要并发地代两个客户端作答）
	var w := 0.0
	while g._tech_offers.size() < 2 and w < 10.0:
		await create_timer(0.1).timeout
		w += 0.1
	_check(g._tech_offers.size() == 2, "两份选卡 offer 同时发出（实得 %d）" % g._tech_offers.size())
	_check(bool(g._tech_open), "阶段进行中：tech_open = true")
	var off_peers: Array = []
	for tok in g._tech_offers:
		off_peers.append(int(g._tech_offers[tok].peer))
	_check(off_peers.has(1) and off_peers.has(2), "两份 offer 分别指向两个真人（不是逐个）")
	_check(g._tech_picks.is_empty(), "没人作答时 picks 为空（两人同时在等）")
	# 三选一弹层也是**玩家可见面**（房主本人那一份是本地直调的，所以这台机器上一定挂着层）。
	_check(g._tech_offer_layer != null and _labels_under(g._tech_offer_layer).has("科技 · 白银"),
		"三选一弹层标题 = 「科技 · 白银」（实得 %s）"
			% str(_labels_under(g._tech_offer_layer) if g._tech_offer_layer != null else []))
	for tok in g._tech_offers.keys():
		g._tech_answer(int(tok), String(g._tech_offers[tok].names[0]))
	w = 0.0
	while bool(g._tech_open) and w < 8.0:
		await create_timer(0.1).timeout
		w += 0.1
	_check(not bool(g._tech_open), "两份都答完 → 阶段收口")
	_check((h1.techs as Array).size() == 1 and (h2.techs as Array).size() == 1, "两个真人都拿到科技")
	g._settings.tech_tier = GameSettings.TECH_TIER_RANDOM
	g._settings.tech_on = false
	g.running = false

	# ---------- 科技容器与发放函数（方案 B） ----------
	_test_grant_tech(g)

	# ---------- 即时型效果 ----------
	print("== 即时型效果 ==")
	p1.money = 20000
	g._tech_apply_instant(p1, "助学金")
	_check(int(p1.money) == 22000, "助学金：起始资金 +2000")
	p1.money = 20000
	g._tech_apply_instant(p1, "富二代")
	_check(int(p1.money) == 40000, "富二代：起始资金 ×2")
	p1.money = 20000
	g._tech_apply_instant(p1, "风险投资")
	_check(int(p1.money) == 15000, "风险投资：起始资金 −5000")
	g._tech_apply_instant(p1, "厄运保单")
	_check(int(p1.get("wuyun_left", 0)) == 4, "厄运保单：置 4 次抵消")
	g._tech_apply_instant(p1, "地产眼光")
	_check(int(p1.get("yanguang_left", 0)) == 2, "地产眼光：置 2 次半价")
	p1.items = []
	g._tech_apply_instant(p1, "二手教材")
	_check(p1.items.size() == 1 and String(ItemData.def(String(p1.items[0].id)).quality) == "白",
		"二手教材：开局获得一件白档道具")
	p1.items = []
	g._tech_apply_instant(p1, "名师指点")
	_check(p1.items.size() == 1 and String(ItemData.def(String(p1.items[0].id)).quality) == "蓝",
		"名师指点：开局获得一件蓝档道具")
	p1.items = []
	p1.money = 20000
	g._tech_apply_instant(p1, "孤注一掷")
	_check(int(p1.money) == 14000 and p1.items.size() == 1
		and String(ItemData.def(String(p1.items[0].id)).quality) == "紫",
		"孤注一掷：起始资金 −6000 换一件紫档道具")
	p1.items = []
	p1.money = 20000
	g._tech_apply_instant(p1, "欧皇附体")
	_check(int(p1.money) == 20000 and p1.items.size() == 1
		and String(ItemData.def(String(p1.items[0].id)).quality) == "金",
		"欧皇附体：开局获得一件金档道具")
	g._tech_apply_instant(p1, "悔棋")
	_check(int(p1.get("meiqi_left", 0)) == 1, "悔棋：置 1 次")
	g._tech_apply_instant(p1, "天命在握")
	_check(int(p1.get("tianming_left", 0)) == 4, "天命在握：置 4 次")
	g._tech_apply_instant(p1, "任意门")
	_check(int(p1.get("renmen_left", 0)) == 2, "任意门：置 2 次")
	p1.money = 20000
	g._tech_apply_instant(p1, "预支未来")
	_check(int(p1.money) == 50000, "预支未来：开局立得 +30000")

	# ---------- 上限叠加 ----------
	print("== 精力充沛 ==")
	var pc := _mk_player(3, "丙")
	_check(g._stamina_cap(pc) == 5, "无科技：体力上限 5")
	pc.techs = ["精力充沛"]
	_check(g._stamina_cap(pc) == 6, "精力充沛：体力上限 6")
	pc.items.append({"id": "充电宝", "cd": 0})
	_check(g._stamina_cap(pc) == 7, "精力充沛 + 充电宝：叠加到 7")

	# ---------- 回合开始型 ----------
	print("== 回合开始型 ==")
	var pt := _mk_player(1, "丁")
	pt.techs = ["零花钱规划"]
	g._item_turn_start(pt)
	_check(int(pt.money) == 20000 + 100, "零花钱规划：回合开始 +100")
	pt.techs = ["天选之人"]
	pt.money = 20000
	pt.stamina = 3
	g._item_turn_start(pt)
	_check(int(pt.money) == 20500, "天选之人：回合开始 +500")
	pt.techs = ["风险投资"]
	pt.money = 20000
	g._item_turn_start(pt)
	_check(int(pt.money) == 20500, "风险投资：回合开始 +500（2026-10-07 定稿降档）")
	pt.techs = ["反思津贴"]
	pt.money = 20000
	pt.skip = 1
	g._item_turn_start(pt)
	_check(int(pt.money) == 20500, "反思津贴：反省回合 +500")
	pt.skip = 0
	pt.techs = ["助困金"]
	pt.money = 800
	g._item_turn_start(pt)
	_check(int(pt.money) == 1300, "助困金：贫困线（<1000）回合开始 +500")
	pt.techs = ["卷王"]
	pt.money = 20000
	pt.stamina = 3
	g._item_turn_start(pt)
	_check(int(pt.stamina) == 5, "卷王：回合开始体力 +1+1（上限内）")
	pt.stamina = 6   # 上限 5（无上限类科技）
	pt.techs = []
	g._item_turn_start(pt)
	_check(int(pt.stamina) == 6, "满体力不再 +1（对照）")

	# ---------- 兼职达人 ----------
	print("== 兼职达人 ==")
	g.htiles = _fresh_tiles()
	var prop_a := -1
	var prop_b := -1
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "property":
			if prop_a < 0:
				prop_a = i
			elif prop_b < 0:
				prop_b = i
	var pp := _mk_player(2, "戊")
	pp.techs = ["兼职达人"]
	var m0 := int(pp.money)
	g._tech_pass_gain(pp, 0)
	_check(int(pp.money) == m0, "兼职达人：起点格不触发")
	g._tech_pass_gain(pp, prop_a)
	_check(int(pp.money) == m0, "兼职达人：无主地皮不触发")
	g.htiles[prop_a] = {"owner": 2, "level": 1}
	g._tech_pass_gain(pp, prop_a)
	_check(int(pp.money) == m0 + 300, "兼职达人：路过自有地皮 +300")
	g.htiles[prop_b] = {"owner": 2, "level": 0, "soil": true}
	g._tech_pass_gain(pp, prop_b)
	_check(int(pp.money) == m0 + 300, "兼职达人：焦土期间不触发")
	pp.techs = []
	g._tech_pass_gain(pp, prop_a)
	_check(int(pp.money) == m0 + 300, "兼职达人：无科技不触发")

	# ---------- 学生折扣 ----------
	print("== 学生折扣 ==")
	var ps := _mk_player(1, "己")
	ps.money = 2000
	ps.techs = ["学生折扣"]
	g.hp = [ps, pp]
	g.shops = {prop_a: {"slots": ["饭卡", "", ""]}}
	g._shop_peer = 1   # _shop_buy 要求商店处于打开态
	g._shop_tile = prop_a
	g._shop_buy(1, 0)
	g._shop_peer = 0
	g._shop_tile = -1
	_check(int(ps.money) == 2000 - 400 and ps.items.size() == 1,
		"学生折扣：饭卡 600 → 400（¥2000−400=1600）")

	# ---------- 地产眼光（半价买地，bot 自动拍板） ----------
	print("== 地产眼光 ==")
	var pb := _mk_player(2, "庚")
	pb.bot = true
	pb.money = 50000
	pb.techs = ["地产眼光"]
	g._tech_apply_instant(pb, "地产眼光")
	g.hp = [pb]
	g.htiles = _fresh_tiles()
	g.running = true   # 买地完成受 while running 守卫
	var base_price: int = int(GameData.TILES[prop_a].price)
	await g._resolve_buy(pb, prop_a)
	_check(int(g.htiles[prop_a].owner) == 2 and int(pb.money) == 50000 - int(base_price / 2.0)
		and int(pb.get("yanguang_left", 0)) == 1, "地产眼光：第一块地半价（¥%d → ¥%d）" % [base_price, base_price / 2])
	await g._resolve_buy(pb, prop_b)
	_check(int(pb.get("yanguang_left", 0)) == 0, "地产眼光：次数消耗")

	# ---------- 开疆拓土 ----------
	print("== 开疆拓土 ==")
	var pk := _mk_player(1, "辛")
	pk.techs = ["开疆拓土"]
	pk.money = 20000
	for i in range(5):
		g.htiles = g.htiles   # 保持引用
		var extra := 20 + i
		while String(GameData.TILES[extra].get("type", "")) != "property" \
				or int(g.htiles[extra].owner) != GameData.NO_OWNER:
			extra = (extra + 1) % GameData.TILES.size()
		g.htiles[extra] = {"owner": 1, "level": 0}
	g._check_tech_milestone(pk)
	_check(int(pk.money) == 20800 and int(pk.get("kingtu", 0)) == 1, "开疆拓土：5 块地首达 +800")
	for i in range(5):
		var extra2 := 30 + i
		while String(GameData.TILES[extra2].get("type", "")) != "property" \
				or int(g.htiles[extra2].owner) != GameData.NO_OWNER:
			extra2 = (extra2 + 1) % GameData.TILES.size()
		g.htiles[extra2] = {"owner": 1, "level": 0}
	g._check_tech_milestone(pk)
	_check(int(pk.money) == 21600 and int(pk.get("kingtu", 0)) == 2, "开疆拓土：10 块地再 +800")

	# ---------- 厄运保单 / 喜报频传 ----------
	print("== 事件卡两件 ==")
	var pe := _mk_player(1, "壬")
	pe.money = 5000
	pe.wuyun_left = 4
	pe.techs = ["厄运保单"]
	g.hp = [pe, pb]   # 两名存活玩家，避免 _apply_card 末尾 _check_end 误判终局
	await g._apply_card(pe, {"money": -800})
	_check(int(pe.money) == 5000 and int(pe.wuyun_left) == 3, "厄运保单：抵消一次扣款（剩 3）")
	pe.techs = []
	await g._apply_card(pe, {"money": -800})
	_check(int(pe.money) == 4200, "无保单：正常扣款")
	pe.techs = ["喜报频传"]
	await g._apply_card(pe, {"money": 500})
	_check(int(pe.money) == 4900, "喜报频传：事件进账 +200")

	# ---------- 心理素质 / 旧物回收 / 装修返现 ----------
	print("== 其余钩子 ==")
	var pm := _mk_player(1, "癸")
	pm.techs = ["心理素质"]
	_check(not g._note_roll_hot(pm, 10) and not g._note_roll_hot(pm, 12) and not g._note_roll_hot(pm, 11),
		"心理素质：连续三次 10+ 不查寝")
	_check(int(pm.get("hot_chain", 0)) == 0, "心理素质：触发后链路清零")
	var pd := _mk_player(1, "甲二")
	pd.money = 1000
	pd.techs = ["旧物回收"]
	pd.items.append({"id": "饭卡", "cd": 0})
	var pv := _mk_player(2, "乙二")
	pv.bot = true
	g.hp = [pd, pv]   # _discard_item 按 peer 查玩家
	g._discard_item(1, 0)
	_check(pd.items.size() == 0 and int(pd.money) == 1150, "旧物回收：丢弃回收 ¥150")
	pv.money = 50000
	pv.techs = ["装修返现"]
	g.htiles = _fresh_tiles()
	g.htiles[prop_a] = {"owner": 2, "level": 0}
	var lv_cost: int = GameData.upgrade_cost(prop_a)
	await g._resolve_upgrade(pv, prop_a)
	_check(int(g.htiles[prop_a].level) == 1 and int(pv.money) == 50000 - lv_cost + 150,
		"装修返现：升级花费 −¥150 返现")

	# ---------- 2026-10-07 批次：黄金 / 钻石定稿逐条 ----------
	print("== 工资三件（工资上调 / 金饭碗 / 预支未来） ==")
	var pw := _mk_player(1, "工资员")
	_check(g._salary_amount(pw) == 4500, "无科技：工资 4500")
	pw.techs = ["工资上调"]
	_check(g._salary_amount(pw) == 6000, "工资上调：每次经过起点 4500 → 6000")
	pw.techs = ["金饭碗"]
	_check(g._salary_amount(pw) == 8500, "金饭碗：4500 → 8500")
	pw.techs = ["预支未来"]
	_check(g._salary_amount(pw) == 0, "预支未来：本局工资归零")
	pw.money = 20000
	await g._pass_start(pw, "顺路踏上起点")
	_check(int(pw.money) == 20000, "预支未来：踏起点不领工资（抵押）")

	print("== 装修师傅 / 置业补贴 / 批发拿地 ==")
	g.running = true
	var pz := _mk_player(2, "装修师")
	pz.bot = true
	pz.money = 50000
	pz.techs = ["装修师傅"]
	g.hp = [pz, _mk_player(1, "旁人甲")]
	g.htiles = _fresh_tiles()
	g.htiles[prop_a] = {"owner": 2, "level": 0}
	var lv_cost2: int = int(GameData.upgrade_cost(prop_a) * 3 / 4)
	await g._resolve_upgrade(pz, prop_a)
	_check(int(g.htiles[prop_a].level) == 1 and int(pz.money) == 50000 - lv_cost2,
		"装修师傅：升级费打 75 折（¥%d → ¥%d）" % [GameData.upgrade_cost(prop_a), lv_cost2])
	var py := _mk_player(2, "置业商")
	py.bot = true
	py.money = 50000
	py.techs = ["置业补贴"]
	g.hp = [py, _mk_player(1, "旁人乙")]
	g.htiles = _fresh_tiles()
	await g._resolve_buy(py, prop_a)
	_check(int(g.htiles[prop_a].owner) == 2 and int(py.money) == 50000 - base_price + 500,
		"置业补贴：购地后 +¥500")
	var ppf := _mk_player(2, "批发商")
	ppf.bot = true
	ppf.money = 50000
	ppf.techs = ["批发拿地"]
	g.hp = [ppf, _mk_player(1, "旁人丙")]
	g.htiles = _fresh_tiles()
	await g._resolve_buy(ppf, prop_a)
	_check(int(ppf.money) == 50000 - int(base_price * 3 / 4),
		"批发拿地：购地立减 25%%（¥%d → ¥%d）" % [base_price, int(base_price * 3 / 4)])
	g.running = false

	print("== 定期存款 / 复利 / 大器晚成 ==")
	var pi := _mk_player(1, "储户")
	pi.techs = ["定期存款"]
	pi.money = 1000
	g._item_turn_start(pi)
	_check(int(pi.money) == 1020, "定期存款：现金 ×2%（¥1000 → +20）")
	pi.money = 200000
	g._item_turn_start(pi)
	_check(int(pi.money) == 200600, "定期存款：单次上限 ¥600")
	pi.techs = ["复利"]
	pi.money = 1000
	g._item_turn_start(pi)
	_check(int(pi.money) == 1025, "复利：现金 ×2.5%（¥1000 → +25）")
	pi.money = 200000
	g._item_turn_start(pi)
	_check(int(pi.money) == 201000, "复利：单次上限 ¥1000")
	var pdw := _mk_player(1, "晚成")
	pdw.techs = ["大器晚成"]
	pdw.money = 20000
	g.round_no = 14
	g._item_turn_start(pdw)
	_check(int(pdw.money) == 20000, "大器晚成：第 14 轮不发")
	g.round_no = 15
	g._item_turn_start(pdw)
	_check(int(pdw.money) == 21000, "大器晚成：第 15 轮起每回合 +1000")
	g.round_no = 1

	print("== 活力全开 ==")
	var pv2 := _mk_player(3, "活力")
	pv2.techs = ["活力全开"]
	_check(g._stamina_cap(pv2) == 7, "活力全开：体力上限 5 → 7")
	pv2.items.append({"id": "充电宝", "cd": 0})
	_check(g._stamina_cap(pv2) == 8, "活力全开 + 充电宝：叠加到 8（科技与道具上限可叠）")
	pv2.items = []

	print("== 会员卡 / 小金库 ==")
	var pvip := _mk_player(1, "会员")
	pvip.money = 2000
	pvip.techs = ["会员卡"]
	g.hp = [pvip, pp]
	g.shops = {prop_a: {"slots": ["饭卡", "", ""]}}
	g._shop_peer = 1
	g._shop_tile = prop_a
	g._shop_buy(1, 0)
	g._shop_peer = 0
	g._shop_tile = -1
	_check(int(pvip.money) == 2000 - 480 and pvip.items.size() == 1,
		"会员卡：饭卡 600 → 480（8 折）")
	var px := _mk_player(1, "金库")
	px.techs = ["小金库"]
	px.money = 29999
	g._check_xiaojinku(px)
	_check(int(px.money) == 29999, "小金库：未达 30000 不发")
	px.money = 30000
	g._check_xiaojinku(px)
	_check(int(px.money) == 35000 and int(px.get("xjk_done", 0)) == 1, "小金库：首达 ¥30000 → +5000")
	g._check_xiaojinku(px)
	_check(int(px.money) == 35000, "小金库：一次性，不重复发")

	print("== 双开 / 手速惊人 / 熟能生巧 / 能量回收 ==")
	var pduo := _mk_player(1, "双开侠")
	pduo.money = 0
	pduo.stamina = 5
	pduo.techs = ["双开"]
	pduo.items = [{"id": "兼职中介", "cd": 0}]
	var foe := _mk_player(2, "陪练")
	g.hp = [pduo, foe]
	g._awaiting_item = 1
	g._use_item(1, 0, -1)
	_check(int(pduo.money) == 800 and int(pduo.get("item_used_n", 0)) == 1 and not bool(pduo.item_used),
		"双开：第一件用完仍可再出")
	pduo.items.append({"id": "兼职中介", "cd": 0})
	g._use_item(1, 1, -1)   # 第一件已进冷却（cd=2），第二件从新槽位出
	_check(int(pduo.money) == 1600 and bool(pduo.item_used), "双开：第二件出完封手")
	_check(int(pduo.get("rework", 3)) == 3, "双开：不消耗重修卡耐久")
	var pcd := _mk_player(1, "手速")
	pcd.stamina = 5
	pcd.money = 0
	pcd.techs = ["手速惊人"]
	pcd.items = [{"id": "兼职中介", "cd": 0}]
	g.hp = [pcd, foe]
	g._awaiting_item = 1
	g._use_item(1, 0, -1)
	_check(int(pcd.items[0].cd) == 1, "手速惊人：冷却 2 → 1")
	var pshu := _mk_player(1, "熟练")
	pshu.stamina = 5
	pshu.money = 0
	pshu.techs = ["熟能生巧"]
	pshu.items = [{"id": "兼职中介", "cd": 0}]
	g.hp = [pshu, foe]
	g._awaiting_item = 1
	g._use_item(1, 0, -1)
	_check(int(pshu.items[0].cd) == 0, "熟能生巧：用后不进冷却")
	var refunds := 0
	for i in range(100):
		var pr := _mk_player(1, "回收%d" % i)
		pr.stamina = 5
		pr.money = 0
		pr.techs = ["能量回收"]
		pr.items = [{"id": "兼职中介", "cd": 0}]
		g.hp = [pr, foe]
		g._awaiting_item = 1
		g._use_item(1, 0, -1)
		if int(pr.stamina) == 4:
			refunds += 1
	_check(refunds >= 30 and refunds <= 70, "能量回收：100 次约 50 次退回 1⚡（实测 %d）" % refunds)

	print("== 谈判专家 / 金字招牌 ==")
	var ptn := _mk_player(1, "谈判")
	ptn.techs = ["谈判专家"]
	_check(g._rent_pay(ptn, 1000) == 600, "谈判专家：付租 −40%")
	ptn.techs = ["宿舍威望"]
	_check(g._rent_pay(ptn, 1000) == 700, "宿舍威望：付租 −30%（对照）")
	var pjz := _mk_player(1, "招牌")
	pjz.money = 10000
	pjz.techs = ["金字招牌"]
	g.htiles = _fresh_tiles()
	g.htiles[prop_a] = {"owner": 1, "level": 2}
	var plain: int = g._net_worth(pjz)
	var boosted: int = 10000 + int(round(float(int(GameData.TILES[prop_a].price)
		+ 2 * GameData.upgrade_cost(prop_a)) * 1.3))
	_check(g._net_worth_final(pjz) == boosted and boosted > plain, "金字招牌：到轮结算地皮 ×1.3")
	_check(g._net_worth(pjz) == plain, "金字招牌：对局中实时身家不放大")

	print("== 广置家业 ==")
	var pgz := _mk_player(1, "广置")
	pgz.techs = ["广置家业"]
	pgz.money = 20000
	g.htiles = _fresh_tiles()
	for i in range(2):
		var e1 := 20 + i
		while String(GameData.TILES[e1].get("type", "")) != "property" \
				or int(g.htiles[e1].owner) != GameData.NO_OWNER:
			e1 = (e1 + 1) % GameData.TILES.size()
		g.htiles[e1] = {"owner": 1, "level": 0}
	g._check_tech_milestone(pgz)
	_check(int(pgz.money) == 25000 and int(pgz.get("guangzhi", 0)) == 1, "广置家业：2 块首档 +5000")
	for i in range(4):
		var e2 := 25 + i
		while String(GameData.TILES[e2].get("type", "")) != "property" \
				or int(g.htiles[e2].owner) != GameData.NO_OWNER:
			e2 = (e2 + 1) % GameData.TILES.size()
		g.htiles[e2] = {"owner": 1, "level": 0}
	g._check_tech_milestone(pgz)
	_check(int(pgz.money) == 35000 and int(pgz.get("guangzhi", 0)) == 3, "广置家业：4 / 6 块两档连发（共 +15000）")

	print("== 东山再起 / 接收大员 ==")
	g._settings.liq_on = false
	var pds := _mk_player(1, "东山")
	pds.money = 100
	pds.techs = ["东山再起"]
	var foe2 := _mk_player(2, "对手乙")
	g.hp = [pds, foe2]
	g.htiles = _fresh_tiles()
	await g._pay(pds, 5000, {})
	_check(bool(pds.alive) and int(pds.money) == 8000 and int(pds.get("dongshan_used", 0)) == 1,
		"东山再起：首次破产不出局，现金回 ¥8000")
	await g._pay(pds, 99999, {})
	_check(not bool(pds.alive), "东山再起：仅一次，二度资不抵债仍出局")
	var bust := _mk_player(1, "破产者")
	bust.money = 0
	var taker := _mk_player(2, "接收者")
	taker.bot = true
	taker.money = 50000
	taker.techs = ["接收大员"]
	g.hp = [bust, taker]
	g.htiles = _fresh_tiles()
	g.htiles[prop_a] = {"owner": 1, "level": 2}
	g.running = true   # 收购完成的守卫含 while running
	await g._pay(bust, 10000, {})
	g.running = false
	_check(not bool(bust.alive), "接收大员：破产成立")
	var half_price: int = int(GameData.TILES[prop_a].price) / 2
	_check(int(g.htiles[prop_a].owner) == 2 and int(taker.get("jieshou_used", 0)) == 1
		and int(taker.money) == 50000 - half_price,
		"接收大员：5 折（¥%d）收购遗产地，每局一次" % half_price)
	g._settings.liq_on = true

	print("== 天命在握（bot 路径） ==")
	var pft := _mk_player(1, "天命bot")
	pft.bot = true
	_check(await g._ask_tianming(pft) == 7, "天命在握：bot 指定 7（避开 10/11 查寝风险）")

	# ---------- 快照 ----------
	print("== 快照字段 ==")
	g.hp[1].techs = ["助学金"]   # 当前 hp[1] = 接收者（前面用例换过 hp，不再用旧的 pv）
	g._tech_tier = "白银"
	g._broadcast_state()
	await process_frame
	var plist: Array = g.st.get("players", [])
	# **双向钉住**：只看「有 techs」不够 —— 同时留着旧键 `tech` 也能过。
	_check(plist.size() >= 2 and (plist[1].get("techs", []) as Array).has("助学金"),
		"快照：players[].techs 随状态下发（列表）")
	_check(plist.size() >= 2 and not plist[1].has("tech"),
		"快照：旧键 tech 已退场，players 条目里不留双份真相")
	_check(String(g.st.get("tech_tier", "")) == "白银", "快照：tech_tier 随状态下发")
	g.st = {}

	if fails == 0:
		print("TECH TEST: ALL PASS")
		quit(0)
	else:
		print("TECH TEST: %d FAILURES" % fails)
		quit(1)
