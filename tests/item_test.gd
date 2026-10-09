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

## 成员在位判据：**直接读不存在的属性只会在日志里刷 SCRIPT ERROR、判不出红** ⇒ 走属性表认。
## 与 `chance_test.gd` 的同名小助手一字不差。
func _has_prop(g, nm: String) -> bool:
	for pd in g.get_property_list():
		if String(pd.name) == nm:
			return true
	return false

## 机会牌堆当前的牌面文案序列 —— 用例拿它比对**顺序**，不是只比张数。
func _deck_titles(g) -> Array:
	var out := []
	for c in (g._event_deck as Array):
		out.append(String((c as Dictionary).get("t", "?")))
	return out

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
	_test_quality_tiers(g)
	_test_item_numbers(g)
	_test_icons(g)
	_test_egg(g)
	_test_coco(g)
	_test_use_guard(g)
	_test_roof(g)
	await _test_erging(g)
	_test_card_state(g)
	_test_price_state(g)
	_test_pricing(g)
	_test_bot_pricing(g)
	_test_roll_mods(g)
	await _test_soil(g)
	await _test_discover(g)
	await _test_taobao_guarantee(g)
	await _test_bury(g)
	_test_tile_shield(g)
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
	# 档位**从 `ItemData.QUALITIES` 派生**（不写字面量档名，见 Ruling BM：本任务跑在改键名之前）
	var top2: Array = ItemData.QUALITIES.slice(ItemData.QUALITIES.size() - 2)
	_check(top2.has(q), "使用者礼物为最高的两档（实得 %s；最高两档 = %s）" % [q, str(top2)])
	_check(p2.money == 1100, "满包玩家改发 ¥100")
	_check(p1.items.size() == 1 or p1.money == 1100, "普通玩家收到礼物或现金")
	_check(p3.items.is_empty() and p3.money == 1000, "出局玩家不参与")
	_check(g._item_pool("").find("蛋蛋节") == -1, "焚毁道具已移出可获取池")

	# ★ Ruling BG：只验「属于最高两档」证明不了「两档等概率」——补一条抽样断言。
	# 使用者礼物 = 最高两档**档位 50/50**、档内等概率（2026-10-10 重构；原 紫 70% / 橙 30%）。
	# n=400 时占比二项标准差 2.5%：门槛 40% 距旧口径的弱势档（30%）约 4.4σ、距新口径（50%）4σ。
	var giver := _mk_player(1, "甲")
	g.hp = [giver]
	var tier_hit := {}
	for i in 400:
		giver.items = []
		g._apply_egg_festival(giver)
		if giver.items.is_empty():
			continue
		var tq := String(ItemData.def(String(giver.items[0].id)).quality)
		tier_hit[tq] = int(tier_hit.get(tq, 0)) + 1
	var even := true
	for tq2 in top2:
		if float(int(tier_hit.get(tq2, 0))) / 400.0 < 0.4:
			even = false
	_check(even, "使用者礼物：最高两档档位 50/50 等概率（实得 %s）" % str(tier_hit))

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

## 二青会酒寒暑（紫·一次性·焚毁）+ 强化版「组队学习·寒暑」（1⚡ / 无冷却 / 独立次数）
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
	_check(g._item_pool("蓝").find("组队学习·寒暑") == -1, "授予件不进随机池（hidden）")
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
	p.techs = ["手速惊人"]
	s = g._card_state(p, p.items[0])
	_check(int(s.get("cd_preview", -1)) == 2 and int(s.get("cd_base", -1)) == 3, "手速惊人：冷却预览 -1（3→2）")
	# 熟能生巧：冷却 →0（绿）
	p.techs = ["熟能生巧"]
	s = g._card_state(p, p.items[0])
	_check(int(s.get("cd_preview", -1)) == 0 and int(s.get("cd_base", -1)) == 3, "熟能生巧：冷却预览 →0")
	# 冷却中：不给预览（由 badge_state 给剩余）
	p.techs = []
	p.items = [{"id": "交换生", "cd": 2}]
	s = g._card_state(p, p.items[0])
	_check(not s.has("cd_preview"), "冷却中不给冷却预览（改显剩余）")

## 品质四档（2026-10-10 道具重构）：**件数分布就是稀有度曲线**，件数与严格递减是硬契约。
func _test_quality_tiers(_g) -> void:
	print("== 品质四档分布 ==")
	_check(ItemData.QUALITIES == ["白", "蓝", "紫", "金"], "四档（实得 %s）" % str(ItemData.QUALITIES))
	_check(not ItemData.QUALITY_NAMES.has("绿") and not ItemData.QUALITY_NAMES.has("橙"),
		"旧键「绿」「橙」已从显示名表退场")
	var cnt := {"白": 0, "蓝": 0, "紫": 0, "金": 0}
	var stray: Array = []
	for id in ItemData.ITEMS:
		var q := String(ItemData.ITEMS[id].get("quality", ""))
		if cnt.has(q):
			cnt[q] += 1
		else:
			stray.append("%s=%s" % [id, q])
	_check(stray.is_empty(), "68 件的品质键全在四档内（越界：%s）" % ", ".join(PackedStringArray(stray)))
	_check(cnt["白"] == 27 and cnt["蓝"] == 20 and cnt["紫"] == 16 and cnt["金"] == 5,
		"件数 白27 / 蓝20 / 紫16 / 金5（实得 %d/%d/%d/%d）" % [cnt["白"], cnt["蓝"], cnt["紫"], cnt["金"]])
	# Ruling BG：合计 68 要**真的量**（不是由「件数相等」隐式推出）——ITEMS 少一件/多一件都该红。
	_check(ItemData.ITEMS.size() == 68, "数据表共 68 件（实得 %d）" % ItemData.ITEMS.size())
	_check(cnt["白"] + cnt["蓝"] + cnt["紫"] + cnt["金"] == 68, "四档合计 = 68（无越界件漏计）")
	_check(cnt["白"] > cnt["蓝"] and cnt["蓝"] > cnt["紫"] and cnt["紫"] > cnt["金"],
		"白 > 蓝 > 紫 > 金（严格递减）")
	for q in ItemData.QUALITIES:
		_check(ItemData.QUALITY_PRICES.has(q) and ItemData.QUALITY_COLORS.has(q),
			"%s 档在定价表与配色表里都有" % q)

## 逐件平衡（2026-10-10 道具重构 §三 3.2）：12 处数值，效果逻辑不变。
## **数值一律从数据类读出核对**（不是把设计稿的那张表再抄一份进断言）—— 表与设计稿一脱钩就红。
## 奖金那一件多钉一条：金额的**唯一来源**是 `ItemData.LUCK7_BONUS`，结算与卡面文案都读它，
## 所以连常量一起钉住（只验 `desc` 的话，结算里留着旧数照样全绿 —— 验不到声称的改动）。
func _test_item_numbers(_g) -> void:
	print("== 逐件数值 ==")
	# id 先逐个点名：`ItemData.def` 对不存在的 id 返回 `{}`，打错字会变成硬崩而不是一条 FAIL，
	# 那会把整轮用例的结果一起带走。这条先把「12 个 id 都真的在表里」钉住。
	for id in ["幸运数7", "二手交易", "占座", "团购拼单", "刮刮乐", "体测", "换课", "点名",
			"出老千", "宿舍改造", "强拆令", "二青会酒寒暑"]:
		_check(ItemData.ITEMS.has(id), "数据表里有「%s」（逐件数值的 id 不许打错）" % id)
	_check(int(ItemData.def("幸运数7").cooldown) == 0
		and "¥1000" in String(ItemData.def("幸运数7").desc),
		"幸运数7：掷 7 奖金 ¥1400 → ¥1000（文案同步）")
	_check(int(ItemData.LUCK7_BONUS) == 1000,
		"幸运数7：奖金常量 LUCK7_BONUS = ¥1000（实得 %d）" % int(ItemData.LUCK7_BONUS))
	_check(String(ItemData.def("幸运数7").desc).contains(str(ItemData.LUCK7_BONUS)),
		"幸运数7：卡面文案与奖金常量同额（desc = %s）" % String(ItemData.def("幸运数7").desc))
	_check("¥1500" in String(ItemData.def("二手交易").desc), "二手交易：兑换 ¥2000 → ¥1500（文案同步）")
	_check(int(ItemData.def("占座").cooldown) == 3, "占座：冷却 4 → 3")
	_check(int(ItemData.def("团购拼单").cost) == 1, "团购拼单：2⚡ → 1⚡")
	_check(int(ItemData.def("刮刮乐").cost) == 1, "刮刮乐：2⚡ → 1⚡")
	_check(int(ItemData.def("体测").cost) == 2, "体测：3⚡ → 2⚡")
	_check(int(ItemData.def("换课").cost) == 2, "换课：3⚡ → 2⚡")
	_check(int(ItemData.def("点名").cost) == 2, "点名：3⚡ → 2⚡")
	_check(int(ItemData.def("出老千").cost) == 3, "出老千：4⚡ → 3⚡")
	_check(int(ItemData.def("宿舍改造").cost) == 3, "宿舍改造：4⚡ → 3⚡")
	_check(int(ItemData.def("强拆令").cooldown) == 0, "强拆令：冷却 4 → 0（一次性件用后即回池）")
	_check(ItemData.item_price("二青会酒寒暑") == 2600, "二青会酒寒暑：单件售价 ¥8000 → ¥2600")

## 图标齐备：68 件的 `icon` 字段都要能在 `assets/icons/` 找到对应 PNG。
## 用 `FileAccess.file_exists` 而不是 `ResourceLoader.exists` —— 后者要求资源先导入过
## （新克隆 / CI 未必导入），会把「文件真缺」和「没导入」混为一谈。
func _test_icons(_g) -> void:
	print("== 道具图标齐备 ==")
	var missing: Array = []
	var seen := 0
	for id in ItemData.ITEMS:
		seen += 1
		var ic := String(ItemData.ITEMS[id].get("icon", ""))
		if ic == "" or not FileAccess.file_exists("res://assets/icons/%s.png" % ic):
			missing.append("%s→%s" % [id, ic])
	# 防「空转」：循环得真的走过 68 件 —— 表一旦变空，上面那条会恒真。
	_check(seen == 68, "遍历到 68 件道具（实得 %d）" % seen)
	_check(missing.is_empty(), "68 件图标文件齐备（缺：%s）" % ", ".join(missing))

## 单件售价覆盖（二青会 ¥2600，2026-10-10 道具重构 §三 3.2 由 ¥8000 压到蓝档价与紫档价之间）
## + 货架冷却预览状态
func _test_price_state(g) -> void:
	print("== 售价覆盖 / 货架冷却预览 ==")
	_check(ItemData.item_price("二青会酒寒暑") == 2600, "二青会单件售价 = ¥2600")
	_check(ItemData.item_price("招财猫") == ItemData.QUALITY_PRICES["白"], "普通件仍按品质定价")
	var ss: Dictionary = ItemData.shop_state("拼车")
	_check(int(ss.get("cd_preview", -1)) == 5, "货架：拼车显示冷却预览 5")
	_check(ItemData.shop_state("刮刮乐").is_empty(), "货架：一次性件无冷却预览")
	_check(ItemData.shop_state("招财猫").is_empty(), "货架：被动件无冷却预览")

## 定价与刷新曲线（2026-10-10 道具重构：全池等概率后件数占比就是出现率，
## **价格是唯一剩下的稀有度门闸**）。档价与黑市地皮价一律从数据类读出断言（不抄第二份表）。
## Ruling BG：刷新曲线**驱动两次真刷新**看价格递增与真扣钱，而不是只读常量。
func _test_pricing(g) -> void:
	print("== 定价与刷新曲线 ==")
	var tbl: Dictionary = ItemData.QUALITY_PRICES
	_check(int(tbl["白"]) == 600, "白档价 600（不动）")
	_check(int(tbl["蓝"]) == 1600, "蓝档价 1600")
	_check(int(tbl["紫"]) == 3200, "紫档价 3200")
	_check(int(tbl["金"]) == 8000, "金档价 8000（= 开局 ¥20000 的四成）")
	# 档价必须是**升序且拉开量级**，否则「用价格当门闸」不成立
	_check(int(tbl["白"]) < int(tbl["蓝"]) and int(tbl["蓝"]) < int(tbl["紫"])
		and int(tbl["紫"]) < int(tbl["金"]), "四档价严格递增")
	# 定价与 item_price 同源：无单件覆盖的件照新档价走（招财猫白 / 黑卡金）
	_check(ItemData.item_price("招财猫") == int(tbl["白"])
		and ItemData.item_price("黑卡") == int(tbl["金"]),
		"无单件覆盖的件按新档价定价（招财猫 %d / 黑卡 %d）" % [
			ItemData.item_price("招财猫"), ItemData.item_price("黑卡")])

	# 黑市地皮价：紫 1 / 金 3（黑市只从紫/金抽，是金档的主要来源 ⇒ 用价格收口）
	_check(int(ItemData.BLACK_COST["紫"]) == 1, "黑市紫的地皮价 1（不动）")
	_check(int(ItemData.BLACK_COST["金"]) == 3, "黑市金的地皮价抬到 3 块")
	_check(int(ItemData.BLACK_COST["金"]) > int(ItemData.BLACK_COST["紫"]),
		"黑市档价随品质递增（金比紫贵）")

	# —— 刷新曲线：真的开一次小卖部、连刷两次，看「起点 > 白档价」与「按步进递增 + 真扣钱」——
	var tile := -1
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "shop":
			tile = i
			break
	_check(tile >= 0, "找到小卖部格子")
	if tile < 0:
		return
	var p := _mk_player(1, "甲")
	p.money = 20000
	g.hp = [p]
	g.turn_i = 0
	g.shops = {tile: {"slots": ["招财猫", "兼职中介", "饭卡"]}}   # 摆三件白货，保证整架重掷会换人
	g._shop_peer = 1
	g._shop_tile = tile
	g.refresh_count = 0
	var c0: int = g._refresh_price()
	_check(c0 == int(ItemData.REFRESH_BASE),
		"首次刷新价 = 起点 %d（实得 %d）" % [int(ItemData.REFRESH_BASE), c0])
	_check(c0 > int(tbl["白"]),
		"刷新起点高于白档价（%d > %d）：刷新 = 再赌一次有没有金，不能比买白货更便宜" % [c0, int(tbl["白"])])
	g._shop_refresh(1)
	_check(g.refresh_count == 1 and int(p.money) == 20000 - c0,
		"第一次刷新照起点价扣钱并推高全场价（余 %d，期望 %d）" % [int(p.money), 20000 - c0])
	var c1: int = g._refresh_price()
	_check(c1 == c0 + int(ItemData.REFRESH_STEP),
		"第二次刷新价 = 首次 + 步进 %d（%d → %d）" % [int(ItemData.REFRESH_STEP), c0, c1])
	g._shop_refresh(1)
	_check(g.refresh_count == 2 and int(p.money) == 20000 - c0 - c1,
		"第二次刷新照 c1 扣钱（余 %d，期望 %d）" % [int(p.money), 20000 - c0 - c1])
	# 收摊：本用例造的货架与刷新计数就地清干净，免得后面 _item_pool 的断言看运气（本文件既有约定）
	g.shops = {}
	g._shop_peer = 0
	g.refresh_count = 0

## bot 定价读单件覆盖（2026-10-10 修）：`_discover_bot_pick` / `_bot_shop` 与 UI（`_refresh_shop_ui`）
## 及购买链路（`_shop_buy`）**同源** —— 都该读 `ItemData.item_price(id)`（先看单件 `price` 覆盖）。
## 黑市比价按 `BLACK_COST` 档位（地皮计价）**是对的**，不在本条内。
##
## **区分力从哪来**：全仓唯一带单件覆盖的是 `二青会酒寒暑`（`price` 字段）。T8 起它是 **¥2600**，
## **低于**同档紫货的档价 ¥3200 —— 方向与批 1（当时 ¥8000，高于档价）相反。
## `_discover_bot_pick` 取**严格最大**（同价时取列表里靠前的那件）⇒ 单件覆盖**低于**档价时，
## 必须把它**摆在前面**才分得出「旧实现按档价 ⇒ 取列表第一件」。两个方向各摆一次：
## 无论覆盖值是高于还是低于档价，至少有一条能把「只看档价」的旧实现钉红，而正确实现两条都绿。
func _test_bot_pricing(g) -> void:
	print("== bot 定价读单件覆盖 ==")
	var ov := "二青会酒寒暑"   # 紫档 · 有单件覆盖
	var other := "作弊器"      # 同为紫档 · 无单件覆盖 ⇒ item_price == 档价
	_check(ItemData.item_price(ov) != ItemData.item_price(other),
		"（前置）单件覆盖与同档紫货的档价不同（¥%d vs ¥%d）" % [
			ItemData.item_price(ov), ItemData.item_price(other)])

	# 方向一（发现三选一）：两个方向各摆一次 —— 只按档价时两件同价、恒取列表第一件。
	for pair in [[other, ov], [ov, other]]:
		var want := ""
		for id in pair:
			if want == "" or ItemData.item_price(String(id)) > ItemData.item_price(want):
				want = String(id)
		_check(g._discover_bot_pick(pair) == want,
			"发现三选一：%s → bot 取 %s（期望 %s）" % [str(pair), g._discover_bot_pick(pair), want])

	# 方向二（小卖部）：bot 只揣 ¥3000 —— 二青会单件覆盖 ¥2600 买得起，同档紫货档价 ¥3200 买不起。
	# 读 item_price 才知道该拿二青会；只按档价（两件都看成 ¥3200）则两件都「买不起」⇒ 空手离店。
	var tile := -1
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "shop":
			tile = i
			break
	_check(tile >= 0, "找到小卖部格子")
	if tile < 0:
		return
	_check(ItemData.item_price(ov) < 3000 and 3000 < ItemData.item_price(other),
		"（前置）¥3000 买得起单件覆盖件、买不起同档紫货（%d < 3000 < %d）" % [
			ItemData.item_price(ov), ItemData.item_price(other)])
	var p := _mk_player(1, "甲")
	p.bot = true
	p.money = 3000
	g.hp = [p]
	g.shops = {tile: {"slots": [ov, other, ""]}}
	g._shop_peer = 1
	g._shop_tile = tile
	g._bot_shop(p, tile)
	_check(p.items.size() == 1 and String(p.items[0].id) == ov,
		"小卖部：bot 买下买得起的单件覆盖件、跳过按档价买不起的那件（实得 %s）" % str(p.items))
	_check(int(p.money) == 3000 - ItemData.item_price(ov),
		"小卖部：按真实价 ¥%d 扣钱（余 %d，期望 %d）" % [
			ItemData.item_price(ov), int(p.money), 3000 - ItemData.item_price(ov)])
	# 收摊：本用例造的货架就地清干净（本文件既有约定），免得后面 _item_pool 的断言看运气
	g.shops = {}
	g._shop_peer = 0
	g.hp = []

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
	# 正常流程：返回一件候选内的道具、进包、候选结构合法（≤3 件、彼此不同、全在可获取池内）。
	# 池子先快照：拿到手后唯一道具会立刻退出可获取池，事后查会对不上。
	var pool_before: Array = g._item_pool("").duplicate()   # 全池（新口径不再有「目标品质」）
	var id: String = await g._run_discover(p, "失物招领")
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
	_check(in_pool, "候选全部来自可获取池（全池）")
	_check(g._discover_offered.has(id), "拿到的是候选之一")
	_check(p.items.size() == 1 and String(p.items[0].id) == id, "选中的道具进了背包")
	# 背包满：不再触发，返回空串
	p.items = []
	for i in 5:
		p.items.append({"id": "招财猫" if i == 0 else "黑卡", "cd": 0})
	var full: int = g._bag_cap(p)   # g 是 Node：动态调用推不出类型，显式标 int
	while p.items.size() < full:
		p.items.append({"id": "校园卡", "cd": 0})
	var none: String = await g._run_discover(p, "失物招领")
	_check(none == "" and p.items.size() == full, "背包满：不触发发现、背包不变")
	g.hp = []

## 科技「淘宝达人」的保底（2026-10-10 道具重构 I3）：候选里**保底一件紫档**（池里有紫就保证出现）。
## 池子收成「1 紫 + 3 非紫」四件，跑 `ROUNDS` 轮，三种口径的区分力：
##   · 新口径（全池等概率 + 保底）：每轮候选都是 3 件、且必含那件紫 ⇒ **确定全绿**（不是概率绿）；
##   · 保底被摘掉（回归）：3 选 2 漏掉那件紫的概率 = 1/4 ⇒ 一轮绿的 chance 是 3/4 ⇒
##     `ROUNDS` 轮全绿的 chance = (3/4)^ROUNDS。取 40 ⇒ **≈ 1.0e-5**（40 是比复审建议的 30 再翻一点，
##     把假绿压到 1e-5 量级）；**只有 `all_have_purple` 这一条**能抓到它。
##   · 批 1 之前（第三参 = 品质、且**沿品质向下降档**）：本池下 紫(1)<3 → 降蓝(0)<3 → 降绿(0)<3 → 白(3)
##     ⇒ 产出**三件全白**。所以旧口径下「件数 == 3」与「出现过非紫」**也绿**，区分新旧口径的仍是
##     `all_have_purple`（旧口径必红）。（我第一版把这两条当成区分项，是错的：那时模型漏了降档环。）
## 用 bot 走 `_run_discover`（不发 UI，只为拿 `_discover_offered`）。
const DISCOVER_ROUNDS := 40
func _test_taobao_guarantee(g) -> void:
	print("== 淘宝达人保底（候选保底一件紫） ==")
	var p := _mk_player(1, "甲")
	p.bot = true
	g.hp = [p]
	p.items = []
	# 以**当前真实池**为基准挑（前面用例可能已占用唯一件）：1 紫 + 3 非紫
	var live: Array = g._item_pool("")
	var purple_id := ""
	var others: Array = []
	for id in live:
		var q := String(ItemData.def(String(id)).quality)
		if q == "紫" and purple_id == "":
			purple_id = String(id)
		elif q != "紫" and others.size() < 3:
			others.append(String(id))
		if purple_id != "" and others.size() >= 3:
			break
	_check(purple_id != "" and others.size() == 3,
		"前置：池里凑得出 1 紫 + 3 非紫（紫=%s 非紫=%d）" % [purple_id, others.size()])
	if purple_id == "" or others.size() < 3:
		g.hp = []
		return
	# 只留这四件，其余一律焚毁 ⇒ 可获取池收成 4 件（本用例收摊时还原）
	var keep := {purple_id: true}
	for oid in others:
		keep[String(oid)] = true
	var saved_burn: Dictionary = g.items_consumed
	var burn := {}
	for id in ItemData.ITEMS:
		if not keep.has(String(id)):
			burn[String(id)] = true
	g.items_consumed = burn
	_check(g._item_pool("").size() == 4, "池子收成 4 件（实得 %d）" % g._item_pool("").size())
	var size_ok := true
	var all_have_purple := true
	var saw_non_purple := false
	for i in DISCOVER_ROUNDS:
		p.items = []   # 每轮清背包：唯一件不占池、也不撑满背包
		await g._run_discover(p, "失物招领", "紫")
		if g._discover_offered.size() != 3:
			size_ok = false
		var has_p := false
		for oid in g._discover_offered:
			if String(ItemData.def(String(oid)).quality) == "紫":
				has_p = true
			else:
				saw_non_purple = true
		if not has_p:
			all_have_purple = false
	_check(size_ok, "每轮候选都是 3 件（全池 4 件等概率 + 保底）")
	_check(all_have_purple, "每轮候选里都保底一件紫档（%d 轮全绿）" % DISCOVER_ROUNDS)
	_check(saw_non_purple, "候选里出现过非紫件（候选来自全池，不是单档池）")
	g.items_consumed = saved_burn
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

## 真人分支的作答（模拟 `c_bury_ok` 的回程）：**等 `_await_bury_choice` 真的把窗口开起来**再写
## 标志 —— 那个函数开头就会把它们清成 false（两分法的既定形状，同 `_await_card_target`），
## 抢在复位之前作答必被冲掉。找不到开窗机会（实现缺席 / 走了托管分支）就自己退，不挂住套件。
func _bury_answer_when_open(g, bury: bool) -> void:
	for _i in 40:                       # ≈2s（`_WINDOW_TICK` 级轮询），足够覆盖 `_use_item` 那 0.4s 前摇
		if int(g._awaiting_bury) != 0:
			break
		await create_timer(0.05).timeout
	g._bury_pick = bury
	g._bury_ack = true

## 小抄升级（2026-10-10 M1）：看顶张 + 可把它塞到牌堆底 —— 复用机会卡已有的 `bury_deck` 原语。
## 分七块钉：① 接口齐备；② 置底原语真的把顶张转到底、其余相对顺序不变；③ 托管分支；
## ④ 归属链三处同源；⑤ `at_mode` 旁路；⑥ 真人分支（作答 / 取消，两半分开）；
## ⑦ 整条 `_use_item` 链路真的改了牌序。
##
## **别用「预置 `_bury_ack`/`_bury_pick` 再调 `_use_item`」那种写法**：预置值必被复位冲掉，
## 而且那条路会真的开操作窗口、无人作答 ⇒ 白等满一窗（「不限时」档更会挂住）。
## 窗口类一律**直接测那个 await 函数**，真人那一支由 `_bury_answer_when_open` 在窗口开起来之后作答。
func _test_bury(g) -> void:
	print("== 小抄：看顶张 + 可置底 ==")
	for nm in ["_bury_ack", "_bury_pick", "_awaiting_bury"]:
		_check(_has_prop(g, nm), "成员 %s 在位" % nm)
	_check(g.has_method("_await_bury_choice"), "方法 _await_bury_choice 在位")
	for nm in ["s_ask_bury", "c_bury_ok"]:
		_check(g.has_method(nm), "RPC %s 在位" % nm)
	# 实现缺席时就地打住：再往下走只会在调用那一行报 SCRIPT ERROR、协程当场中断（套件要跑到
	# 20s 看门狗才退，红得看不出是哪一条）。判据与 `chance_test._test_deck_fields` 同一套。
	if not g.has_method("_await_bury_choice") or not _has_prop(g, "_bury_ack"):
		return

	# ①b 前端接线（`DeckReveal` 那一侧，Step 5）：只有作答者本人那一端出按钮
	for nm2 in ["show_bury_ask", "is_bury_visible"]:
		_check(g.deck_reveal.has_method(nm2), "DeckReveal.%s 在位" % nm2)
	_check(g.deck_reveal.has_signal("bury_picked"), "DeckReveal.bury_picked 信号在位")
	g.deck_reveal.show_bury_ask(true, true)
	_check(g.deck_reveal.is_bury_visible(), "询问亮起（本机就是作答者）")
	g.deck_reveal.show_bury_ask(true, false)
	_check(not g.deck_reveal.is_bury_visible(), "旁观者那一端不出按钮")
	g.deck_reveal.show_bury_ask(false, true)
	_check(not g.deck_reveal.is_bury_visible(), "收尾（done）后按钮收掉")

	# ② 置底原语（既有 `_card_apply_deck` 的 `bury_deck` 分支，本任务不重写它）
	var p := _mk_player(1, "甲")
	var q := _mk_player(2, "乙")   # 第二个活人：`_check_end` 见只剩一人会判胜、把 running 关掉
	g.hp = [p, q]
	g.htiles = _fresh_tiles()
	g.shops = {}
	g.items_consumed = {}
	g._event_deck = [{"t": "顶张"}, {"t": "第二张"}, {"t": "第三张"}]
	g._card_apply_deck(p, {"bury_deck": true}, "bury_deck")
	_check(_deck_titles(g) == ["第二张", "第三张", "顶张"],
		"置底原语：顶张去底、其余相对顺序不变（实得 %s）" % str(_deck_titles(g)))

	# ③ 托管分支（bot）：不置底、不挂起、牌序一字不动、归属位不脏
	g._event_deck = [{"t": "顶张"}, {"t": "第二张"}]
	p.bot = true
	var t0 := Time.get_ticks_msec()
	_check(await g._await_bury_choice(p) == false, "托管：不置底（返回 false）")
	_check(Time.get_ticks_msec() - t0 < 2000, "托管：短暂延时、不挂起（%d ms）" % (Time.get_ticks_msec() - t0))
	_check(_deck_titles(g) == ["顶张", "第二张"], "托管：牌序一字不动")
	_check(int(g._awaiting_bury) == 0, "托管：归属位没被写脏")

	# ④ 归属链三处同源（体例照 `chance_test._test_op_owner_card_target`）
	p.bot = false
	# `turn_i` 指向**另一个玩家**：归属链全空时 `_op_window_owner` 会回退到当前行动者 ——
	# 不这样摆，这一条会被回退值 1 蒙对（甲恰好也是 1 号位），等于没验到归属链。
	g.turn_i = 1
	g._awaiting_roll = 0
	g._awaiting_prompt = 0
	g._awaiting_card_target = 0
	g._awaiting_card = 0
	g._awaiting_item = 0
	g._shop_peer = 0
	g._black_peer = 0
	g._awaiting_bury = 1
	_check(int(g._op_window_owner()) == 1, "① 倒计时归属 = 小抄使用者（实得 %d）" % int(g._op_window_owner()))
	g._op_timer_send("item", 12.0, 12.0)
	_check(int(g._op_owner) == 1, "① 同源：s_op_timer 推的归属也是他（实得 %d）" % int(g._op_owner))
	g._broadcast_state()
	_check(String(g.st.get("await", "")) == "item" and int(g.st.get("await_peer", -1)) == 1,
		"② 快照 await=item / await_peer=1（实得「%s」/%d）" % [
			String(g.st.get("await", "")), int(g.st.get("await_peer", -1))])
	# 这一条钉**插入位置**：置底窗口是在 `_use_item` 内部开的，那一刻 `_awaiting_item` 仍非零
	# ⇒ 那一支必须排在 `elif _awaiting_item != 0:` **之前**，否则恒不可达（await_peer 会读到 2）。
	g._awaiting_item = 2
	g._broadcast_state()
	_check(int(g.st.get("await_peer", -1)) == 1,
		"② 同窗口期 `_awaiting_item` 也非零时，await_peer 仍归小抄使用者（实得 %d）" % int(g.st.get("await_peer", -1)))
	g._awaiting_item = 0
	g._awaiting_bury = 0
	g._op_timer_send("", 0.0, 0.0)

	# ⑧ 掉线放行钩子（`_on_peer_disconnected`）：正等的人掉线即视作「不置底」，别让全场白等一窗
	g.running = true
	g._awaiting_bury = 1
	g._on_peer_disconnected(1)
	_check(bool(g._bury_ack), "③ 掉线：置底询问当场放行（_bury_ack 置真）")
	_check(int(g._awaiting_bury) == 1, "③ 掉线：不替掉线者清归属位（收尾留给等待方）")
	g._bury_ack = false
	p.bot = false   # `_on_peer_disconnected` 顺带把掉线者转成机器人托管，用完还原（后面几条要真人）

	# ⑨ 重连换 key（`_rekey_transient`）：不换 key，重连者作答会被 `c_bury_ok` 当外人丢掉
	g._awaiting_bury = 1
	g._rekey_transient(1, 9)
	_check(int(g._awaiting_bury) == 9, "④ 重连：归属位换到新 key（实得 %d）" % int(g._awaiting_bury))
	g._awaiting_bury = 0
	g._rekey_transient(9, 1)

	# ⑥ 真人分支：点「塞到底」与点「算了」**分开**钉，两条各查返回值 + 牌序。
	#
	# 这一段刻意走**「不限时」档**（`sec <= 0` ⇒ `_await_turn_window` 根本不计时）：窗口只能被
	# 「已作答」关掉。**判据写成 `_bury_pick`（选了置底吗）的实现在这里会当场挂住**（靠 20s
	# 看门狗兜底），而不会像"12 秒窗口"那样恰好也返回 false 蒙混过关 —— 于是这条断言与机器
	# 的计时精度无关（本机实测：无头模式下 0.3s 与 0.4s 两段 `_wait` 的实测耗时几乎一样、
	# 都在 267~314 ms 之间，拿绝对耗时当判据不可靠）。
	var prev_tier := String(g._settings.timeout_tier)
	g._settings.timeout_tier = GameSettings.TIER_NONE
	g.running = true
	g._event_deck = [{"t": "顶张"}, {"t": "第二张"}, {"t": "第三张"}]
	_bury_answer_when_open(g, true)
	_check(await g._await_bury_choice(p) == true, "真人：点「塞到底」→ 返回 true")
	_check(int(g._awaiting_bury) == 0, "真人：收窗后归属位清零")
	g._card_apply_deck(p, {"bury_deck": true}, "bury_deck")   # 与 `_use_item` 小抄分支同一句
	_check(_deck_titles(g) == ["第二张", "第三张", "顶张"],
		"真人：置底真的改了牌序（实得 %s）" % str(_deck_titles(g)))

	g._event_deck = [{"t": "顶张"}, {"t": "第二张"}]
	_bury_answer_when_open(g, false)
	_check(await g._await_bury_choice(p) == false, "真人：点「算了」→ 返回 false（不置底）")
	_check(_deck_titles(g) == ["顶张", "第二张"], "真人：不置底 ⇒ 牌序不变")

	# ⑦ 整条链路（`_use_item` → 小抄分支 → 请求 → 作答 → 置底原语）：牌堆真的被改
	p.items = [{"id": "小抄", "cd": 0}]
	p.stamina = 3
	p.item_used = false
	p.item_used_n = 0
	g._awaiting_item = 1
	g._item_epoch = 0
	g._item_action = {}
	g._event_deck = [{"t": "顶张"}, {"t": "第二张"}, {"t": "第三张"}]
	_bury_answer_when_open(g, true)
	await g._use_item(1, 0, -1)
	_check(_deck_titles(g) == ["第二张", "第三张", "顶张"],
		"整条链路：小抄真的把顶张塞到了底（实得 %s）" % str(_deck_titles(g)))
	g._settings.timeout_tier = prev_tier

	# ⑤ `at_mode` 旁路：自动回归里房主自己是「真人」（`_is_managed` 为假）⇒ 本机那张不白等一窗。
	# **留在最后**：`at_mode` 是「这台机子在自动回归里」的状态，上面那几条要的是普通对局，
	# 别让这个标志盖在它们头上（它还会让 `_process` 里的自动作答钩子开始认牌）。
	# 判据仍是耗时：走真窗口要等满 `ITEM_TIMEOUT`（实测 12112 ms），走旁路只等 0.3 s。
	g.at_mode = "host"
	t0 = Time.get_ticks_msec()
	_check(await g._await_bury_choice(p) == false, "at_mode：本机自动作答（不置底）")
	_check(Time.get_ticks_msec() - t0 < 2000,
		"at_mode：短暂延时、没开真人那一窗（%d ms）" % (Time.get_ticks_msec() - t0))
	g.at_mode = ""
	g.running = false
	g.hp = []

## 把施放者摆回「这一件还没用过」的样子：备好道具 + 复位每回合闸门 / 体力 / 首件标记，
## 并把 `_use_item` 的窗口开给他。
## **本用例要连摆好几个方向，不重置就会假绿**：第二发会被 `_item_used_up`（每回合 1 件）
## 或体力不足静默挡掉，断言以「什么都没发生」的样子通过 —— 看着绿、其实一行没跑到。
func _arm_use(g, p: Dictionary, iid: String, stamina := 6) -> void:
	p.items = [{"id": iid, "cd": 0}]
	p.stamina = stamina
	p.item_used_n = 0
	p.item_used = false
	p.first_used = false
	p.cost_pen = []
	g._awaiting_item = int(p.peer)
	g._item_epoch = 0
	g._item_action = {}

## 园中叶（2026-10-10 M5）落定为「地产护罩」被动 —— 68 件里最后一件未实装的。
## 设计稿（`doc/development/plans/道具重构.md` §二 金档最后一行，**该计划文件随本版本删除、历史见
## `git log`**）：「你名下的地皮不会被降级、变无主或被收购」，被 `抄家队` / `强拆令` /
## `宿舍改造` 三处读取；`implemented` 置 true。
##
## **两个方向各摆一次**：持罩 与 摘罩 摆同一副局面、结果必须相反。
## 只摆持罩那一半的话，「抄家队整个坏掉」这类回归也会全绿（降级根本没发生 ≠ 被挡住了）。
## 反向那几条本就在实现之前就是绿的（它们是"区分力"的对照组，不是待红的断言）；
## 待红的是持罩那三条 + 选地表两条 + 首段候选那条。
func _test_tile_shield(g) -> void:
	print("== 园中叶：地产护罩 ==")
	_check(bool(ItemData.def("园中叶").implemented), "园中叶已实装（68 件全实装）")
	_check(String(ItemData.def("园中叶").desc) != "？？？",
		"园中叶卡面文案已落定（desc 不再是占位：%s）" % String(ItemData.def("园中叶").desc))

	var a := _prop_idx(0)
	var b := _prop_idx(1)
	var p0 := _mk_player(1, "甲")   # 施放者
	var p1 := _mk_player(2, "乙")   # 受害者；自有地皮 b
	g.hp = [p0, p1]
	g.shops = {}
	g.items_consumed = {}
	var t := _fresh_tiles()
	t[a].owner = 1
	t[a].level = 1
	t[b].owner = 2
	t[b].level = 2
	g.htiles = t

	# ① 抄家队（降 1 级）：持罩不动 / 摘罩照降
	p1.items = [{"id": "园中叶", "cd": 0}]
	_arm_use(g, p0, "抄家队")
	g._use_item(1, 0, 2, b)   # arg = 目标 peer，arg2 = 目标格
	_check(int(g.htiles[b].get("level", -1)) == 2, "持园中叶：自家地皮不被抄家降级（仍 Lv2）")
	p1.items = []
	g.htiles[b].level = 2
	_arm_use(g, p0, "抄家队")
	g._use_item(1, 0, 2, b)
	_check(int(g.htiles[b].get("level", -1)) == 1, "无护罩（反向）：同一副局面照常降 1 级")

	# ② 强拆令（归无主）
	p1.items = [{"id": "园中叶", "cd": 0}]
	g.htiles[b].owner = 2
	g.htiles[b].level = 2
	_arm_use(g, p0, "强拆令", 8)
	g._use_item(1, 0, 2, b)
	_check(int(g.htiles[b].get("owner", GameData.NO_PEER)) == 2, "持园中叶：自家地皮不被强拆（仍归乙）")
	p1.items = []
	g.htiles[b].owner = 2
	g.htiles[b].level = 2
	_arm_use(g, p0, "强拆令", 8)
	g._use_item(1, 0, 2, b)
	_check(int(g.htiles[b].get("owner", GameData.NO_PEER)) == GameData.NO_OWNER,
		"无护罩（反向）：照常强拆为无主")
	_check(int(g.htiles[b].get("level", -1)) == 0, "无护罩（反向）：强拆后等级清零")

	# ③ 宿舍改造（学校八折收购；只挑一块地，乙名下就 b 一块 ⇒ 落点确定）
	p1.items = [{"id": "园中叶", "cd": 0}]
	g.htiles[b].owner = 2
	g.htiles[b].level = 2
	_arm_use(g, p0, "宿舍改造")
	g._use_item(1, 0, 2)
	_check(int(g.htiles[b].get("owner", GameData.NO_PEER)) == 2, "持园中叶：自家地皮拒绝被收购（仍归乙）")
	p1.items = []
	g.htiles[b].owner = 2
	g.htiles[b].level = 2
	_arm_use(g, p0, "宿舍改造")
	g._use_item(1, 0, 2)
	_check(int(g.htiles[b].get("owner", GameData.NO_PEER)) == GameData.NO_OWNER,
		"无护罩（反向）：照常被征收为无主")

	# ④ 两段式选地表（UI 侧）：护罩是**全有全无**的标记 —— 持罩者名下一块地都不进可选表；
	#    转专业（互换，不是夺占）照旧可选，否则玩家点了受保护的地只会静默失败
	p1.items = [{"id": "园中叶", "cd": 0}]
	g.htiles[b].owner = 2
	g._broadcast_state()
	_check(g._selectable_props(2, true).is_empty(), "两段式选地表（抄家/强拆）：持护罩者的地皮不入选")
	_check(not g._selectable_props(2, false).is_empty(),
		"普通选地表（转专业 / 顶楼加盖）：不受护罩影响")
	p1.items = []
	g._broadcast_state()
	_check(not g._selectable_props(2, true).is_empty(), "无护罩（反向）：地皮重新进可选表")

	# ⑤ 首段候选玩家（`_begin_peer_target`）：持罩者若名下一块地都动不了，就不该出现在「选谁」的
	#    名单里（否则点了才说"没有可指定的地皮"）。**判据按 id 分流**：`then_prop` 同时覆盖
	#    转专业（`then == "swap_both"`），拿它整体去过滤会把互换类也一起挡掉。
	p1.items = [{"id": "园中叶", "cd": 0}]
	g.htiles[b].owner = 2
	g._broadcast_state()
	g.my_peer = 1
	g._tgt_stage = ""
	_arm_use(g, p0, "强拆令", 8)
	g._begin_peer_target(0, false, true, true)
	_check(g._tgt_stage != "peer", "首段候选：持护罩者不进「选谁」的名单（夺占地皮类）")
	g._tgt_stage = ""
	_arm_use(g, p0, "转专业", 8)
	g._begin_peer_target(0, false, true, false)
	_check(g._tgt_stage == "peer", "首段候选：互换类（转专业）照旧列得出持护罩者")
	g._cancel_target()
	g._tgt_stage = ""
	g.hp = []

## 掷点修正链（`game._apply_roll_mods`）：**单独**用「作弊器」/「天命在握」也该生效。
## 原来这两件嵌在 `if roll_bonus != 0`（点名）块里 ⇒ 没被点名时**静默无效**：
## 道具/次数照扣、点数照旧随机，且 `cheat_roll` 一直挂着、直到某次被点名才突然生效。
## 本用例先钉住「单独用就生效」，再钉住叠加时**语义与从前一致**（指名点数的两件盖过 +3）。
func _test_roll_mods(g) -> void:
	print("== 掷点修正链 ==")
	# ① 单独用「作弊器」：点数被指定、标记一次性消费（修复前：返回原随机值且 cheat_roll 仍挂着 ⇒ 红）
	var p := _mk_player(1, "甲")
	p.cheat_roll = 7
	_check(g._apply_roll_mods(p, 3) == 7, "单独用「作弊器」：点数被指定为 7（不再随原值）")
	_check(int(p.get("cheat_roll", -1)) == -1, "单独用「作弊器」：标记一次性消费（不再挂着等点名）")
	# ② 单独用「天命在握」：同上
	var q := _mk_player(2, "乙")
	q.tianming_roll = 9
	_check(g._apply_roll_mods(q, 3) == 9, "单独用「天命在握」：点数被指定为 9")
	_check(int(q.get("tianming_roll", -1)) == -1, "单独用「天命在握」：标记一次性消费")
	# ③ 叠加语义不变：点名 +3 在前、指名点数盖过 +3（与修复前嵌在点名块里的结果一致）
	var r := _mk_player(3, "丙")
	r.roll_bonus = 3
	r.cheat_roll = 5
	_check(g._apply_roll_mods(r, 0) == 5, "点名 + 作弊器：指名点数盖过 +3（叠加语义与修复前一致）")
	_check(int(r.get("roll_bonus", 0)) == 0 and int(r.get("cheat_roll", -1)) == -1,
		"点名 + 作弊器：两个标记都被消费")
	# ④ 两件指名点数互叠时，「天命在握」胜（顺序：点名 → 作弊器 → 天命在握，与修复前一致）
	var s := _mk_player(4, "丁")
	s.cheat_roll = 4
	s.tianming_roll = 11
	_check(g._apply_roll_mods(s, 0) == 11, "作弊器 + 天命在握：「天命在握」胜（顺序与修复前一致）")
	# ⑤ 无任何修正：点数原样通过（别把普通的一转也改动）
	var t := _mk_player(1, "戊")
	_check(g._apply_roll_mods(t, 6) == 6, "无任何修正：点数原样通过")
