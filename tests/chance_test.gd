extends SceneTree
## 机会卡改造（2026-10-09 批 2）单测：三类卡分布 / 新字段效果 / 免疫口径 / **选目标**。
## 本文件按任务逐个长起来：Task 9 立「选目标基座」那一节，Task 10 接上「指定目标类 5 个字段」。
## godot --headless --path . --script tests/chance_test.gd
##
## 拿 game 实例的做法照 `tests/blackshop_test.gd`：起一个真实 server peer + 实例化对局场景。
## 不要退回 `load("res://scripts/game.gd").new()` —— 裸 new 出来的节点不在树上，
## `s_*` / `_log` 那套全员广播当场失效（本仓 `--script` 测试的既有坑，见
## doc/game-design/设计决策留痕.md §二十三）。

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
	var tiles := []
	for i in GameData.TILES.size():
		tiles.append({"owner": GameData.NO_OWNER, "level": 0})
	return tiles

## 第 offset 块地产的格号（按路径序）
func _prop_idx(offset: int) -> int:
	var n := 0
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "property":
			if n == offset:
				return i
			n += 1
	return -1

func _mk_player(peer: int, nm: String, money := 1000, bot := false) -> Dictionary:
	return {"peer": peer, "name": nm, "color": peer - 1, "bot": bot, "money": money,
		"pos": 0, "alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [],
		"item_used": false, "cheat_roll": -1}

## 摆一桌可用的局面：`hp` / `htiles` 是房主侧真身，`st.players` 是 `_state_player` 读的那一份。
## 这里直接摆 `st`（不调 `_broadcast_state`）—— 用例要的是"能查到人"，不是重贴整套界面
## （口径同 `blackshop_test._test_shop_ui`）。
## 选目标态的那几个字段一并复位，用例之间不串味。
func _setup(g, players: Array, tiles: Array) -> void:
	g.hp = players
	g.htiles = tiles
	var plist := []
	for p in players:
		plist.append(p)
	g.st = {"players": plist, "tiles": tiles, "turn": int(players[0].peer)}
	g.my_peer = int(players[0].peer)
	g._tgt_card = ""
	g._tgt_stage = ""
	g._tgt_slot = -1
	g._tgt_peer = -1
	g._card_target_peers = []
	g._target_pick = GameData.NO_PEER
	g._card_target_ack = false
	g._awaiting_card_target = 0
	g._hl_peers = []

## 甲(1) / 乙(2,名下有地) / 丙(3,bot) / 丁(4,出局)
func _table(g) -> void:
	var t := _fresh_tiles()
	t[_prop_idx(0)].owner = 2
	var p4 := _mk_player(4, "丁")
	p4.alive = false
	_setup(g, [_mk_player(1, "甲"), _mk_player(2, "乙"), _mk_player(3, "丙", 1000, true), p4], t)

func _run() -> void:
	seed(2026)
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(7795, 3) != OK:
		printerr("server create failed")
		quit(1)
		return
	var mp := MultiplayerAPI.create_default_interface()
	mp.multiplayer_peer = peer
	set_multiplayer(mp, "/root")
	create_timer(30.0).timeout.connect(func() -> void:
		printerr("CHANCE TEST TIMEOUT")
		quit(1)
	)
	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.running = false
	# 先立一道存在性闸：实现缺席时下面每条用例都会在赋值 / 调用处报 SCRIPT ERROR 就地中断，
	# `fails` 一个都不涨 —— 汇总会**假绿**成 "ALL PASS"。有了这几条，"功能没写"才是红的。
	_test_iface(g)
	_test_candidates(g)
	_test_enter_exit(g)
	_test_spectator(g)
	_test_seat_click(g)
	_test_cancel(g)
	_test_refresh_keeps_card(g)
	await _test_no_candidates(g)
	await _test_managed(g)
	await _test_target_fields(g)
	if fails == 0:
		print("CHANCE TEST: ALL PASS")
		quit(0)
	else:
		print("CHANCE TEST: %d FAILURES" % fails)
		quit(1)

# ================= 选目标基座（Task 9） =================

## 成员按 `get_property_list` 认（直接读不存在的属性只会刷 SCRIPT ERROR，判不出红）
func _has_prop(g, nm: String) -> bool:
	for pd in g.get_property_list():
		if String(pd.name) == nm:
			return true
	return false

func _test_iface(g) -> void:
	print("== 接口齐备 ==")
	for nm in ["_tgt_card", "_card_target_peers", "_target_pick", "_card_target_ack",
			"_awaiting_card_target"]:
		_check(_has_prop(g, nm), "成员 %s 在位" % nm)
	for nm in ["_await_card_target", "_card_target_candidates"]:
		_check(g.has_method(nm), "方法 %s 在位" % nm)
	for nm in ["s_card_target", "c_card_target"]:
		_check(g.has_method(nm), "RPC %s 在位" % nm)

func _test_candidates(g) -> void:
	print("== 可选目标：按字段过滤 ==")
	_table(g)
	var p1: Dictionary = g.hp[0]
	var all: Array = g._card_target_candidates(p1, "steal_from")
	_check(all == [2, 3], "普通字段列所有其他**存活**玩家（排除自己与出局者，实得 %s）" % str(all))
	var seize: Array = g._card_target_candidates(p1, "seize_tile")
	_check(seize == [2], "seize_tile 只列名下有地的人（实得 %s）" % str(seize))
	var buy: Array = g._card_target_candidates(p1, "force_buy_tile")
	_check(buy == [2], "force_buy_tile 同上（实得 %s）" % str(buy))
	# 自己名下有地也照样不列自己（排除自己在前，与"有没有地"无关）
	_check(not all.has(1) and not seize.has(1), "自己永远不是候选")

## brief 让首参传 `NO_PEER` 时，`s_card_target` 分不出「我是抽卡者」与「我是旁观者」⇒ **全员**
## 都进了选目标态、都挂了提示条。首参本来就是为这件事准备的（`owner_peer`）。
func _test_spectator(g) -> void:
	print("== 旁观者不进态 ==")
	_table(g)   # my_peer = 1
	_check(g.target_hint != null, "提示条控件在（否则下面那条断言是空的）")
	if g.target_hint != null:
		g.target_hint.visible = false
	g.s_card_target.rpc(2, "steal_from", [1, 3], false)   # 抽卡者是 peer 2，本机是 peer 1
	_check(g._tgt_card == "", "旁观者不进态（判别位仍为空，实得「%s」）" % g._tgt_card)
	_check(g._tgt_stage == "", "旁观者不挂选目标阶段（实得「%s」）" % g._tgt_stage)
	_check(g._hl_peers.is_empty(), "旁观者不点亮任何候选人")
	_check(g.target_hint == null or not g.target_hint.visible, "旁观者不挂提示条")
	# 抽卡者那一端照旧进态
	g.s_card_target.rpc(1, "steal_from", [2, 3], false)
	_check(g._tgt_card == "steal_from" and g._tgt_stage == "peer", "抽卡者本人照旧进态")
	_check(g.target_hint == null or g.target_hint.visible, "抽卡者本人照旧挂提示条")
	# 收尾包一视同仁：旁观者哪怕没进过态也照收一遍（不报错、也不清出别的花来）
	g.s_card_target.rpc(2, "", [], true)
	_check(g._tgt_card == "" and g._tgt_stage == "" and g._hl_peers.is_empty(), "收尾包对旁观者也无害")
	# 「只有抽卡者进态」之后，旁观者那端的另外三条路径也应当一切照常（`_tgt_card` 恒为空）：
	g._target_pick = 5
	g._on_seat_clicked(3)          # 立牌点击：不是选目标态 ⇒ 既不产目标、也不进卡态
	_check(g._target_pick == 5 and g._tgt_card == "", "旁观者点立牌不产出目标、也不进卡态")
	g._refresh_action_button()     # `_refresh_action_button` 那条清理：旁观者与从前一模一样
	_check(g._tgt_stage == "" and g._tgt_card == "", "旁观者过一遍广播清理仍是无事态")
	g._cancel_target()             # 取消路径：没有卡态 ⇒ 不回报房主、不碰哨兵
	_check(g._target_pick == 5, "旁观者取消路径不碰卡的哨兵")

func _test_enter_exit(g) -> void:
	print("== 进 / 退选目标态 ==")
	_table(g)
	g._tgt_slot = 0   # 故意先摆一个"道具槽位"：卡态必须把它归 -1，否则 _target_item_id() 会越界
	g.s_card_target.rpc(1, "steal_from", [2, 3], false)
	_check(g._tgt_card == "steal_from", "判别位记下字段名")
	_check(g._tgt_stage == "peer", "复用既有的选玩家阶段")
	_check(g._tgt_slot == -1, "卡态下 _tgt_slot 归 -1")
	_check(g._tgt_peer == -1, "两段式的 _tgt_peer 也归 -1")
	_check(g._card_target_peers == [2, 3], "候选名单记下来")
	_check(g._hl_peers == [2, 3], "候选人点亮（判据仍是唯一一份 _hl_peers）")
	g.s_card_target.rpc(1, "", [], true)
	_check(g._tgt_card == "" and g._tgt_stage == "" and g._tgt_slot == -1, "收尾清干净")
	_check(g._hl_peers.is_empty(), "收尾熄灭高亮")

func _test_seat_click(g) -> void:
	print("== 点名册条 / 立牌选人 ==")
	_table(g)
	g._tgt_card = "steal_from"
	g._tgt_stage = "peer"
	g._tgt_slot = -1
	g._card_target_peers = [2, 3]
	g._target_pick = GameData.NO_PEER
	g._on_seat_clicked(1)
	_check(g._target_pick == GameData.NO_PEER, "点自己不受理")
	g._on_seat_clicked(9)
	_check(g._target_pick == GameData.NO_PEER, "点非候选不受理")
	g._on_corner_bar_clicked(2)   # 真实入口：立牌 / 名册格点一下
	_check(g._target_pick == 2, "点候选 = 选中（哨兵让位，实得 %d）" % g._target_pick)
	# 这条才是"卡的分支在道具那条之前"的钉子：落到道具那条会走 _send_use_item → _cancel_target()，
	# 卡态当场被收走（而 `_tgt_slot == -1` 还会让它去用一个不存在的槽位）。
	_check(g._tgt_card == "steal_from" and g._tgt_stage == "peer", "选中后卡态还在（没被道具那条的 _cancel_target 收走）")

func _test_cancel(g) -> void:
	print("== 取消 ==")
	_table(g)
	g._tgt_card = "steal_from"
	g._tgt_stage = "peer"
	g._tgt_slot = -1
	g._card_target_peers = [2, 3]
	g._target_pick = 2
	g._card_target_ack = false
	g._cancel_target()
	_check(g._tgt_card == "" and g._tgt_stage == "" and g._tgt_slot == -1, "取消把卡态清干净")
	_check(g._target_pick == GameData.NO_PEER, "取消 ⇒ 没有目标（这张卡的目标部分作废）")
	_check(g._card_target_ack, "取消也回报房主：房主不再空等一个操作窗口")
	_check(g._hl_peers.is_empty(), "取消熄灭高亮")
	# 道具那条取消路径一字未动：不碰卡的哨兵
	g._target_pick = 7
	g._card_target_ack = false
	g._tgt_card = ""
	g._tgt_stage = "peer"
	g._tgt_slot = 0
	g._cancel_target()
	_check(g._target_pick == 7 and not g._card_target_ack, "道具取消路径不动卡的哨兵")
	_check(g._tgt_stage == "" and g._tgt_slot == -1, "道具取消照旧清自己的态")

func _test_refresh_keeps_card(g) -> void:
	print("== 状态广播不冲掉卡选目标态 ==")
	_table(g)
	g.s_card_target.rpc(1, "steal_from", [2, 3], false)
	# `_refresh_action_button`（每次状态广播经 `_refresh_actions` 推一遍）里有"非道具阶段收掉
	# 未完成的选目标态"那条清理 —— 它判的是 `await == "item"`，卡选目标态**不是**那种阶段。
	# 不排除的话，窗口期里任何一次广播（别人丢张牌、掉线）都会把这次选目标当场收掉，
	# 而收掉现在会回报房主 ⇒ 这张卡的目标白丢。
	g._refresh_action_button()   # 直接调那条闸（真实触发链是 s_state → _refresh_actions → 这里）
	_check(g._tgt_card == "steal_from" and g._tgt_stage == "peer",
		"广播之后卡态还在（实得「%s」/「%s」）" % [g._tgt_card, g._tgt_stage])
	_check(not g._card_target_ack, "也没有被误报成取消")
	_check(g._hl_peers == [2, 3], "候选仍然亮着")
	# 道具那条清理照旧（既有行为一字未改）：道具态遇到同样的广播仍然被收掉
	g._tgt_card = ""
	g._tgt_stage = "peer"
	g._tgt_slot = 0
	g._refresh_action_button()
	_check(g._tgt_stage == "" and g._tgt_slot == -1, "道具态照旧被广播收掉")

func _test_no_candidates(g) -> void:
	print("== 无人可选 ==")
	_setup(g, [_mk_player(1, "甲")], _fresh_tiles())
	var t0 := Time.get_ticks_msec()
	var got: Dictionary = await g._await_card_target(g.hp[0], "steal_from")
	var ms := Time.get_ticks_msec() - t0
	_check(got.is_empty(), "无人可选 ⇒ 返回空字典（目标部分作废）")
	_check(ms < 300, "且**立刻**返回、不挂起（实耗 %d ms）" % ms)
	_check(g._target_pick == GameData.NO_PEER and not g._card_target_ack, "哨兵没被写脏")
	# 托管也一样：0 候选时不该先等那 0.6s 再自动选
	g.hp[0].bot = true
	t0 = Time.get_ticks_msec()
	got = await g._await_card_target(g.hp[0], "steal_from")
	_check(got.is_empty() and Time.get_ticks_msec() - t0 < 300, "托管且无人可选时同样立刻返回")

func _test_managed(g) -> void:
	print("== 托管（机器人）自动选 ==")
	var t := _fresh_tiles()
	t[_prop_idx(0)].owner = 2   # 只有乙名下有地
	_setup(g, [_mk_player(1, "机器人甲", 1000, true), _mk_player(2, "乙"), _mk_player(3, "丙")], t)
	var got: Dictionary = await g._await_card_target(g.hp[0], "steal_from")
	var pick := int(got.get("peer", -1))
	_check(pick == 2 or pick == 3, "托管时自动挑了一位候选（实得 %d）" % pick)
	_check(g._tgt_card == "" and g._tgt_stage == "" and g._tgt_slot == -1, "自动选完收尾清干净")
	_check(g._hl_peers.is_empty(), "自动选完高亮熄灭")
	_check(g._target_pick == GameData.NO_PEER and not g._card_target_ack, "哨兵与 ack 都复位")
	_check(g._awaiting_card_target == 0, "归属位复位")
	# 只有乙名下有地 ⇒ seize_tile 时自动选的一定是乙（按字段过滤后的名单）
	var got2: Dictionary = await g._await_card_target(g.hp[0], "seize_tile")
	_check(int(got2.get("peer", -1)) == 2, "按字段过滤后自动选的仍是合法目标（实得 %d）" % int(got2.get("peer", -1)))

# ================= 指定目标类 5 个字段（Task 10） =================
#
# 多数用例用卡里的 `_target` 注入键喂目标（值 = peer），绕开选目标交互 —— 那条交互由上面 T9
# 那节单独钉；**走正路**那一条（托管自动选）不喂，用来钉"`_target` 缺席时照常能选"。`_target`
# **不是玩法字段**，只是测试 / 摆拍的旁路（见 `game.gd._card_target_for`）。

## 摆一桌指定现金的局面：甲 5000 / 乙 1000 / 丙 800 / 丁（出局）。
## 钱数彼此不同才看得出"谁给了谁多少"；留一个出局者，用来钉「存活」这道过滤。
func _target_table(g, snap := false) -> void:
	var t := _fresh_tiles()
	var d := _mk_player(4, "丁")
	d.alive = false
	var ps := [_mk_player(1, "甲", 5000), _mk_player(2, "乙", 1000), _mk_player(3, "丙", 800), d]
	_setup(g, ps, t)
	if snap:
		# 真实对局里 `st.players` 是 `_broadcast_state` **每次新建**的快照副本
		#（`_setup` 图省事让两者同物 —— 用例要的是"能查到人"）。这条把副本关系摆回来。
		var copies := []
		for p in ps:
			copies.append(p.duplicate(true))
		g.st = {"players": copies, "tiles": t, "turn": 1}

## 战报里从 `from` 起找 `needle` 的下标（-1 = 没有）—— 用来钉结算**先后**。
## `g` 是无类型的 Variant，取回来的都是 Variant，显式 `int(...)` 收口（本仓静态类型的规矩）。
func _log_at(g, needle: String, from: int) -> int:
	return int(g.log_text.get_parsed_text().find(needle, from))

## 战报当前长度（当"游标"用：只看一张卡**自己**新增的那几行，免得撞上前面用例的同名战报）
func _log_len(g) -> int:
	return int(g.log_text.get_parsed_text().length())

func _test_target_fields(g) -> void:
	await _test_steal_charge(g)
	await _test_each_from_target(g)
	await _test_steal_item(g)
	await _test_jail_to(g)
	await _test_target_soap(g)
	await _test_owner_soap(g)
	await _test_target_real_owner(g)
	await _test_target_via_real_path(g)
	await _test_field_order(g)

func _test_steal_charge(g) -> void:
	print("== 指定目标：夺取 / 索取 ==")
	_target_table(g)
	await g._apply_card(g.hp[0], {"t": "顺走外卖", "steal_from": 400, "_target": 2})
	_check(int(g.hp[0].money) == 5400 and int(g.hp[1].money) == 600 and int(g.hp[2].money) == 800,
		"steal_from 400：甲 5400 / 乙 600 / 丙 不被牵连（实得 %d / %d / %d）" % [
			int(g.hp[0].money), int(g.hp[1].money), int(g.hp[2].money)])
	# 不足则取其所有：乙只剩 600 ⇒ 夺 600。归零但**不出局**（不走 `_pay`，没钱可给 ≠ 破产）
	await g._apply_card(g.hp[0], {"t": "讨债", "steal_from": 1000, "_target": 2})
	_check(int(g.hp[0].money) == 6000 and int(g.hp[1].money) == 0 and bool(g.hp[1].alive),
		"不足则取其所有：乙归零但仍存活（实得 %d / %d）" % [int(g.hp[0].money), int(g.hp[1].money)])

	_target_table(g)
	await g._apply_card(g.hp[0], {"t": "宿舍费", "charge_to": 300, "_target": 2})
	_check(int(g.hp[0].money) == 5300 and int(g.hp[1].money) == 700,
		"charge_to 300：甲 5300 / 乙 700（实得 %d / %d）" % [int(g.hp[0].money), int(g.hp[1].money)])

	# 目标部分作废的三条路：出局者 / 自己是自己 / 查无此人 —— 都不动钱、也不该崩
	_target_table(g)
	for who in [4, 1, 99]:
		await g._apply_card(g.hp[0], {"t": "点名", "steal_from": 400, "_target": who})
	_check(int(g.hp[0].money) == 5000 and int(g.hp[1].money) == 1000 and int(g.hp[2].money) == 800,
		"目标出局 / 是自己 / 查无此人 ⇒ 目标部分作废（三家钱都没动）")

func _test_each_from_target(g) -> void:
	print("== 指定目标：让他请客 ==")
	_target_table(g)
	await g._apply_card(g.hp[0], {"t": "请客", "each_from_target": 200, "_target": 2})
	_check(int(g.hp[0].money) == 5200 and int(g.hp[2].money) == 1000 and int(g.hp[1].money) == 600,
		"乙 给每位其他存活玩家 200：甲 5200 / 丙 1000 / 乙 600（实得 %d / %d / %d）" % [
			int(g.hp[0].money), int(g.hp[2].money), int(g.hp[1].money)])
	_check(int(g.hp[3].money) == 1000, "出局的丁不算「存活玩家」（一分没给他）")
	# 见底：乙只有 300 ⇒ 先轮到的拿满、后轮到的只拿得到剩下的（按 hp 顺序，甲在丙前）
	_target_table(g)
	g.hp[1].money = 300
	await g._apply_card(g.hp[0], {"t": "请客", "each_from_target": 200, "_target": 2})
	_check(int(g.hp[1].money) == 0 and int(g.hp[0].money) == 5200 and int(g.hp[2].money) == 900,
		"目标见底时按当时剩下的给：乙 0 / 甲 +200 / 丙 +100（实得 %d / %d / %d）" % [
			int(g.hp[1].money), int(g.hp[0].money), int(g.hp[2].money)])

func _test_steal_item(g) -> void:
	print("== 指定目标：抢道具 ==")
	_target_table(g)
	g.hp[1].items = [{"id": "招财猫", "cd": 3}]
	await g._apply_card(g.hp[0], {"t": "翻你抽屉", "steal_item_from": true, "_target": 2})
	var got_it: bool = g.hp[0].items.size() == 1 and String(g.hp[0].items[0].id) == "招财猫"
	_check(got_it, "抢走的那件进了甲的背包（实得 %s）" % str(g.hp[0].items))
	# 取件状态那两条挂在前一条上：抢不着时 `items[0]` 会越界报错，就地中断会把后面几条用例一起吞掉
	_check(got_it and int(g.hp[0].items[0].get("cd", -1)) == 3,
		"抢的是他手里那一件：实例状态（cd）跟着走，不是重新发一件")
	_check(g.hp[1].items.is_empty(), "乙的背包空了")
	# 自己背包满 ⇒ 整条作废（不把目标那件掏出来再发现没处放 —— 中间态会真的丢件）
	_target_table(g)
	var fill := []
	for _i in g._bag_cap(g.hp[0]):
		fill.append({"id": "护腕", "cd": 0})
	g.hp[0].items = fill
	g.hp[1].items = [{"id": "招财猫", "cd": 0}]
	await g._apply_card(g.hp[0], {"t": "翻你抽屉", "steal_item_from": true, "_target": 2})
	_check(g.hp[0].items.size() == fill.size() and g.hp[1].items.size() == 1,
		"自己背包满 ⇒ 抢不动（甲仍是 %d 件、乙那件还在）" % int(fill.size()))
	# 目标空背包 ⇒ 没得抢（要走提示那条，不是静默无事）
	_target_table(g)
	var log0 := _log_len(g)
	await g._apply_card(g.hp[0], {"t": "翻你抽屉", "steal_item_from": true, "_target": 2})
	_check(g.hp[0].items.is_empty() and _log_at(g, "没得抢", log0) >= 0,
		"目标背包空空 ⇒ 提示「没得抢」、甲也没多东西")

func _test_jail_to(g) -> void:
	print("== 指定目标：送去宿委会 ==")
	_target_table(g)
	g.hp[1].pos = 8
	await g._apply_card(g.hp[0], {"t": "举报你", "jail_to": true, "_target": 2})
	_check(int(g.hp[1].pos) == GameData.JAIL_TILE and int(g.hp[1].skip) == 1,
		"目标被送到宿委会并跳过下一回合（pos %d / skip %d）" % [int(g.hp[1].pos), int(g.hp[1].skip)])
	_check(int(g.hp[0].pos) == 0 and int(g.hp[0].skip) == 0, "抽卡者自己没被牵连")
	# 护身符照旧挡一次：它不是香皂 ⇒ 不走"整条免疫"那道闸，由 `_send_to_jail` 自己判
	_target_table(g)
	g.hp[1].pos = 8
	g.hp[1].items = [{"id": "护身符"}]
	await g._apply_card(g.hp[0], {"t": "举报你", "jail_to": true, "_target": 2})
	_check(int(g.hp[1].pos) == 8 and g.hp[1].items.is_empty(),
		"目标持护身符 ⇒ 免掉这次送监、护身符用掉（pos %d）" % int(g.hp[1].pos))

## 五条**全部**对目标不利 ⇒ 目标持皂整条免疫（口径同 `from_each` 的逐受害者独立免疫）
func _test_target_soap(g) -> void:
	print("== 目标持皂 ⇒ 五条逐条整条免疫 ==")
	for field in ["steal_from", "charge_to", "each_from_target", "steal_item_from", "jail_to"]:
		_target_table(g)
		g.hp[1].pos = 8
		g.hp[1].items = [{"id": "空想者的香皂", "melt_left": 10}]
		var card := {"t": "指定目标", "_target": 2}
		card[field] = 200 if field in ["steal_from", "charge_to", "each_from_target"] else true
		var log0 := _log_len(g)
		await g._apply_card(g.hp[0], card)
		_check(_log_at(g, "挡下了", log0) >= 0, "%s：战报写明被香皂挡下（真走了那道闸，不是整条没跑）" % field)
		_check(int(g.hp[0].money) == 5000 and int(g.hp[1].money) == 1000 and int(g.hp[2].money) == 800,
			"%s：三家的现金一分没动" % field)
		_check(int(g.hp[1].pos) == 8 and int(g.hp[1].skip) == 0, "%s：位置 / 跳过都没动" % field)
		_check(g.hp[0].items.is_empty() and g.hp[1].items.size() == 1,
			"%s：连「抢道具」也抢不走那块香皂" % field)

func _test_owner_soap(g) -> void:
	print("== 抽卡者自己持皂：不影响这些字段 ==")
	_target_table(g)
	g.hp[0].items = [{"id": "空想者的香皂", "melt_left": 10}]
	await g._apply_card(g.hp[0], {"t": "顺走外卖", "steal_from": 400, "_target": 2})
	_check(int(g.hp[0].money) == 5400 and int(g.hp[1].money) == 600,
		"甲持皂也照样夺得到钱（判的是**目标**那一方，实得 %d / %d）" % [int(g.hp[0].money), int(g.hp[1].money)])

## `st.players` 是快照副本时，目标必须**归位到 hp 真身** —— 直接改副本就是"看着结算了、其实一分没动"。
func _test_target_real_owner(g) -> void:
	print("== 目标落在 hp 真身上 ==")
	_target_table(g, true)
	g.hp[1].money = 1234
	_check(int(g._state_player(2).money) == 1000,
		"前提：st.players 里那份不是 hp 真身（改真身不动它，实得 %d）" % int(g._state_player(2).money))
	g.hp[1].money = 1000
	await g._apply_card(g.hp[0], {"t": "顺走外卖", "steal_from": 400, "_target": 2})
	_check(int(g.hp[1].money) == 600 and int(g.hp[0].money) == 5400,
		"钱扣在 hp 真身上（实得 %d / %d）" % [int(g.hp[1].money), int(g.hp[0].money)])

## 走**正路**（卡里不喂 `_target`）：托管玩家自动选目标，房主照常结算。
## 这条把「`_apply_card` → 取目标 → `_await_card_target` → 落回 hp 真身」串起来钉一遍
##（上一条只钉了最后那半）；`st` 摆成快照副本，正是真实对局的样子。
func _test_target_via_real_path(g) -> void:
	print("== 正路：托管自动选 ==")
	_target_table(g, true)
	g.hp[0].bot = true
	await g._apply_card(g.hp[0], {"t": "顺走外卖", "steal_from": 400})
	var lost := 0
	if int(g.hp[1].money) == 600:
		lost += 1
	if int(g.hp[2].money) == 400:
		lost += 1
	_check(int(g.hp[0].money) == 5400 and lost == 1,
		"自动点了一位：乙 / 丙 里**恰好一位** -400、甲 +400（实得 %d / %d，命中 %d 位）" % [
			int(g.hp[1].money), int(g.hp[2].money), lost])
	_check(int(g.hp[0].money) + int(g.hp[1].money) + int(g.hp[2].money) == 6800,
		"三家现金总量守恒（5000+1000+800，实得 %d）" % (int(g.hp[0].money) + int(g.hp[1].money) + int(g.hp[2].money)))
	_check(g._tgt_card == "" and g._hl_peers.is_empty() and g._target_pick == GameData.NO_PEER,
		"选目标态收干净（不留给下一张卡）")

## 插卡顺序：目标类必须**在 go_jail 之后、move_steps 之前**（机会卡.md §三）。
## 钉法：一张卡同时带 `go_jail` + 目标字段 + `move_steps: -1`，且抽卡者持【雨伞】
## —— `move_steps` 那条遇到后退会**提前 `return`**，目标类要是排在它后面就一并被跳过。
func _test_field_order(g) -> void:
	print("== 插卡顺序 ==")
	_target_table(g)
	g.hp[0].pos = 3
	g.hp[0].items = [{"id": "雨伞"}]
	var log0 := _log_len(g)
	await g._apply_card(g.hp[0], {"t": "顺序钉子", "go_jail": true, "steal_from": 100,
		"_target": 2, "move_steps": -1})
	_check(int(g.hp[1].money) == 900, "目标类生效（乙 1000 → 900）：没被 move_steps 的提前 return 跳过")
	_check(int(g.hp[0].pos) == GameData.JAIL_TILE, "go_jail 也照常生效（甲被送监）")
	var i_jail := _log_at(g, "查寝", log0)
	var i_steal := _log_at(g, "夺走", log0)
	var i_move := _log_at(g, "免疫了后退", log0)
	_check(i_jail >= 0 and i_steal > i_jail, "战报次序：go_jail 在目标类之前（%d < %d）" % [i_jail, i_steal])
	# `i_steal >= 0` 不能省：两条都缺时 `-1 < 160` 也成立，会白送一条假绿
	_check(i_steal >= 0 and i_move > i_steal, "战报次序：目标类在 move_steps 之前（%d < %d）" % [i_steal, i_move])
