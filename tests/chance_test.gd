extends SceneTree
## 机会卡改造（2026-10-09 批 2）单测：三类卡分布 / 新字段效果 / 免疫口径 / **选目标**。
## 本文件按任务逐个长起来，Task 9（选目标基座）先立起最后的「选目标」那一节。
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
	_test_seat_click(g)
	_test_cancel(g)
	_test_refresh_keeps_card(g)
	await _test_no_candidates(g)
	await _test_managed(g)
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

func _test_enter_exit(g) -> void:
	print("== 进 / 退选目标态 ==")
	_table(g)
	g._tgt_slot = 0   # 故意先摆一个"道具槽位"：卡态必须把它归 -1，否则 _target_item_id() 会越界
	g.s_card_target.rpc(GameData.NO_PEER, "steal_from", [2, 3], false)
	_check(g._tgt_card == "steal_from", "判别位记下字段名")
	_check(g._tgt_stage == "peer", "复用既有的选玩家阶段")
	_check(g._tgt_slot == -1, "卡态下 _tgt_slot 归 -1")
	_check(g._tgt_peer == -1, "两段式的 _tgt_peer 也归 -1")
	_check(g._card_target_peers == [2, 3], "候选名单记下来")
	_check(g._hl_peers == [2, 3], "候选人点亮（判据仍是唯一一份 _hl_peers）")
	g.s_card_target.rpc(GameData.NO_PEER, "", [], true)
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
	g.s_card_target.rpc(GameData.NO_PEER, "steal_from", [2, 3], false)
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
