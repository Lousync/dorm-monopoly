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
	_test_quality_tiers(g)
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
	await _test_soil(g)
	await _test_discover(g)
	await _test_taobao_guarantee(g)
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

## 单件售价覆盖（二青会 ¥8000）+ 货架冷却预览状态
func _test_price_state(g) -> void:
	print("== 售价覆盖 / 货架冷却预览 ==")
	_check(ItemData.item_price("二青会酒寒暑") == 8000, "二青会单件售价 = ¥8000")
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
func _test_bot_pricing(g) -> void:
	print("== bot 定价读单件覆盖 ==")
	# 方向一（发现三选一）：三件**同为紫档** —— 只按档价排就是「三件一样贵」（取第一件），
	# 只有读 item_price 才分得出高下（二青会单件覆盖 ¥8000 > 紫档价 ¥3200）。
	# 用三件而非两件：无论将来单件覆盖的数怎么改，「最贵的那件不是 ids[0]」恒成立。
	var ids := ["作弊器", "平均主义", "二青会酒寒暑"]
	var want := ""
	for id in ids:
		if want == "" or ItemData.item_price(id) > ItemData.item_price(want):
			want = id
	_check(want != ids[0], "（前置）按 item_price 排最贵的不是列表第一件（实得最贵 = %s）" % want)
	_check(g._discover_bot_pick(ids) == want,
		"发现三选一：bot 按 item_price 挑最贵（期望 %s，实得 %s）" % [want, g._discover_bot_pick(ids)])

	# 方向二（小卖部）：同一架上是「真有单件覆盖、bot 买不起」的件 + 「只按档价、买得起」的件，
	# bot 只揣 ¥5000。读 item_price 才知道二青会要 ¥8000 ⇒ 转头买 ¥3200 的紫货；
	# 只按档价（两件都被看成 ¥3200）则先撞上二青会、再被 `_shop_buy` 的真实价 ¥8000 拒付 ⇒ 空手离店。
	var tile := -1
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "shop":
			tile = i
			break
	_check(tile >= 0, "找到小卖部格子")
	if tile < 0:
		return
	var cheap := "作弊器"   # 紫档 · 无单件覆盖 ⇒ 按档价 ¥3200
	_check(ItemData.item_price(cheap) == ItemData.item_price("平均主义")
		and ItemData.item_price(cheap) < ItemData.item_price("二青会酒寒暑"),
		"（前置）廉价件按档价、贵件按单件覆盖（%d < %d）" % [
			ItemData.item_price(cheap), ItemData.item_price("二青会酒寒暑")])
	var p := _mk_player(1, "甲")
	p.bot = true
	p.money = 5000
	g.hp = [p]
	g.shops = {tile: {"slots": ["二青会酒寒暑", cheap, ""]}}
	g._shop_peer = 1
	g._shop_tile = tile
	g._bot_shop(p, tile)
	_check(p.items.size() == 1 and String(p.items[0].id) == cheap,
		"小卖部：bot 跳过买不起的 ¥8000 件、买下买得起的档价件（实得 %s）" % str(p.items))
	_check(int(p.money) == 5000 - ItemData.item_price(cheap),
		"小卖部：按真实价 ¥%d 扣钱（余 %d，期望 %d）" % [
			ItemData.item_price(cheap), int(p.money), 5000 - ItemData.item_price(cheap)])
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
## 池子收成「1 紫 + 3 非紫」四件时三种口径的区分力：
##   · 新口径（全池等概率 + 保底）：每轮候选都是 3 件、且必含那件紫 ⇒ 全绿；
##   · 保底被摘掉（回归）：3 选 2 漏掉那件紫的概率 = 1/4 ⇒ 8 轮全绿的 chance 只有 0.25^8 ≈ 1.5e-5 ⇒ 必红；
##   · 批 1 之前（第三参 = 品质，整池只抽紫）：候选只有那件紫、件数 1 ⇒ 件数/非紫两条必红。
## 用 bot 走 `_run_discover`（不发 UI，只为拿 `_discover_offered`）。
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
	for i in 8:
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
	_check(all_have_purple, "每轮候选里都保底一件紫档（8 轮全绿）")
	_check(saw_non_purple, "候选里出现过非紫件（不是旧口径「整池只抽紫」）")
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
