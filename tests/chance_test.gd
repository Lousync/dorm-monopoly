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
	# 抉择卡（Task 12）那两个判别位也一并复位，用例之间不串味
	g._choice_pick = -1
	g._awaiting_card = 0

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
	# 脚手架那局**不要跑开局科技**（2026-10-09 起 `tech_on` 默认开；同 `casino_test` 那条）：
	# 实例化时 `_start()` 已经起跑（它先 `_wait(1.5)`），本文件又习惯**一上来就往 `hp` 里塞人**，
	# 于是 1.5 秒一到它就当"名单已就绪"：`_tech_phase` 会给在场每家发一张随机科技 +
	# 即时效果（可能直接动钱），还 `rpc_id` 给客户端位（测试里没这些 peer ⇒ 刷一堆
	# "unknown peer ID" 的 ERROR）。原先本套件在 1.5 秒内就跑完了、撞不上；Task 11 的
	# 地皮 / 位置用例带了一串走子等待，跑得比 1.5 秒长了 ⇒ 必须显式关掉。
	g._settings.tech_on = false
	# 先立一道存在性闸：实现缺席时下面每条用例都会在赋值 / 调用处报 SCRIPT ERROR 就地中断，
	# `fails` 一个都不涨 —— 汇总会**假绿**成 "ALL PASS"。有了这几条，"功能没写"才是红的。
	_test_iface(g)
	_test_kind_and_dist(g)
	_test_candidates(g)
	_test_enter_exit(g)
	_test_spectator(g)
	_test_seat_click(g)
	_test_cancel(g)
	_test_refresh_keeps_card(g)
	await _test_no_candidates(g)
	await _test_managed(g)
	await _test_target_fields(g)
	await _test_tile_move_fields(g)
	await _test_choices(g)
	_test_deck_iface(g)
	await _test_deck_fields(g)
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

# ================= 地皮与位置类 6 个字段（Task 11） =================
#
# 摆一桌地皮局：甲(1) / 乙(2) / 丙(3) 各 5000、丁(4) 出局。
# `own` = {peer: [地皮下标…]}（归谁）、`lvl` = {地皮下标: 等级}（只给 `own` 里那几块地设等级）。
# 位置一律由用例自己摆（`_mk_player` 给的是 0）。
func _tile_table(g, own := {}, lvl := {}) -> void:
	var t := _fresh_tiles()
	for peer in own:
		for idx in own[peer]:
			t[int(idx)].owner = int(peer)
	for idx in lvl:
		t[int(idx)].level = int(lvl[idx])
	var d := _mk_player(4, "丁")
	d.alive = false
	_setup(g, [_mk_player(1, "甲", 5000), _mk_player(2, "乙", 5000), _mk_player(3, "丙", 5000), d], t)

func _test_tile_move_fields(g) -> void:
	await _test_seize_tile(g)
	await _test_seize_swap(g)
	await _test_force_buy(g)
	await _test_swap_pos(g)
	await _test_pull_target(g)
	await _test_push_back(g)
	await _test_shuffle_pos(g)
	await _test_tile_soap(g)

func _test_seize_tile(g) -> void:
	print("== 地皮：夺地（seize_tile: take） ==")
	var p0 := _prop_idx(0)   # 1 号格：地价 2800（每级装修 = 地价一半 1400）
	var p1 := _prop_idx(1)   # 2 号格：地价 2540
	# 含装修等级：乙名下只有一块地、已到 Lv3 ⇒ 夺走时等级跟着地块走
	_tile_table(g, {2: [p0]}, {p0: 3})
	await g._apply_card(g.hp[0], {"t": "夺地令", "seize_tile": "take", "_target": 2})
	_check(int(g.htiles[p0].owner) == 1 and int(g.htiles[p0].level) == 3,
		"夺来的地**连装修等级一起走**（owner %d / level %d）" % [
			int(g.htiles[p0].owner), int(g.htiles[p0].level)])
	_check(g._own_props(2).is_empty(), "乙名下清空")
	# 「投入最少」= 地价 + 装修投入：p1 地价更低、但带 Lv4 ⇒ 投入反而更高 ⇒ 夺的是 p0
	_tile_table(g, {2: [p0, p1]}, {p1: 4})
	await g._apply_card(g.hp[0], {"t": "夺地令", "seize_tile": "take", "_target": 2})
	_check(int(g.htiles[p0].owner) == 1 and int(g.htiles[p1].owner) == 2,
		"取「投入最少」那块：p0(2800) 归甲、p1(2540 + Lv4 装修) 留乙")
	# 目标无地 ⇒ 作废（连甲自己那块地也不该动）
	_tile_table(g, {1: [p0]})
	var log0 := _log_len(g)
	await g._apply_card(g.hp[0], {"t": "夺地令", "seize_tile": "take", "_target": 2})
	_check(int(g.htiles[p0].owner) == 1 and _log_at(g, "抢无可抢", log0) >= 0,
		"目标无地 ⇒ 作废（甲自己那块地也没动）")

func _test_seize_swap(g) -> void:
	print("== 地皮：互换（seize_tile: swap） ==")
	var p0 := _prop_idx(0)
	var p1 := _prop_idx(1)
	# 各只有一块 ⇒ "各随机一块"也唯一，结果确定
	_tile_table(g, {1: [p0], 2: [p1]}, {p0: 2, p1: 1})
	await g._apply_card(g.hp[0], {"t": "换宿", "seize_tile": "swap", "_target": 2})
	_check(int(g.htiles[p0].owner) == 2 and int(g.htiles[p1].owner) == 1,
		"各随机一块互换：p0 ↔ p1（owner %d / %d）" % [
			int(g.htiles[p0].owner), int(g.htiles[p1].owner)])
	_check(int(g.htiles[p0].level) == 2 and int(g.htiles[p1].level) == 1,
		"装修等级跟着地块走（level %d / %d）" % [
			int(g.htiles[p0].level), int(g.htiles[p1].level)])
	# 任一方无地 ⇒ 作废
	_tile_table(g, {1: [p0]})
	var log0 := _log_len(g)
	await g._apply_card(g.hp[0], {"t": "换宿", "seize_tile": "swap", "_target": 2})
	_check(int(g.htiles[p0].owner) == 1 and _log_at(g, "抢无可抢", log0) >= 0,
		"目标无地 ⇒ 作废（甲那块地还在）")
	_tile_table(g, {2: [p1]})
	log0 = _log_len(g)
	await g._apply_card(g.hp[0], {"t": "换宿", "seize_tile": "swap", "_target": 2})
	_check(int(g.htiles[p1].owner) == 2 and _log_at(g, "换不了", log0) >= 0,
		"自己无地 ⇒ 作废（乙那块地还在）")

func _test_force_buy(g) -> void:
	print("== 地皮：强买（force_buy_tile） ==")
	var p0 := _prop_idx(0)   # 地价 2800
	var p1 := _prop_idx(1)   # 地价 2540
	# 2540 × 33 / 100 = 838.2 ⇒ 整数除法**向下取整** 838（正数截断即向下）
	_tile_table(g, {2: [p1]})
	await g._apply_card(g.hp[0], {"t": "强买令", "force_buy_tile": 33, "_target": 2})
	_check(int(g.htiles[p1].owner) == 1 and int(g.hp[0].money) == 5000 - 838 \
		and int(g.hp[1].money) == 5000 + 838,
		"按 33%% 原价强买：地皮归甲、甲付 838 给乙（实得 %d / %d）" % [
			int(g.hp[0].money), int(g.hp[1].money)])
	# 现金不足 ⇒ 作废（地皮与钱都不动）
	_tile_table(g, {2: [p0]})
	g.hp[0].money = 100
	var log0 := _log_len(g)
	await g._apply_card(g.hp[0], {"t": "强买令", "force_buy_tile": 33, "_target": 2})
	_check(int(g.htiles[p0].owner) == 2 and int(g.hp[0].money) == 100 \
		and _log_at(g, "不够", log0) >= 0,
		"现金不足 ⇒ 作废（地皮仍归乙、甲那 100 没动）")
	# 目标无地 ⇒ 作废
	_tile_table(g, {1: [p0]})
	await g._apply_card(g.hp[0], {"t": "强买令", "force_buy_tile": 33, "_target": 2})
	_check(int(g.htiles[p0].owner) == 1 and int(g.hp[0].money) == 5000, "目标无地 ⇒ 作废")

func _test_swap_pos(g) -> void:
	print("== 位置：换位（swap_pos，不结算落点） ==")
	var p0 := _prop_idx(0)
	var p1 := _prop_idx(1)
	# 两个落点都归丙：真若结算落点，甲乙都得给丙付租金 ⇒ 钱一分不动才说明没结算
	_tile_table(g, {3: [p0, p1]})
	g.hp[0].pos = p0
	g.hp[1].pos = p1
	await g._apply_card(g.hp[0], {"t": "霸占床位", "swap_pos": true, "_target": 2})
	_check(int(g.hp[0].pos) == p1 and int(g.hp[1].pos) == p0,
		"甲 ↔ 乙 换位（pos %d / %d）" % [int(g.hp[0].pos), int(g.hp[1].pos)])
	_check(int(g.hp[0].money) == 5000 and int(g.hp[1].money) == 5000 and int(g.hp[2].money) == 5000,
		"**不结算落点**：两人都落在丙的地上，租金一分没动")

func _test_pull_target(g) -> void:
	print("== 位置：拉人（pull_target，照常结算落点） ==")
	var p0 := _prop_idx(0)
	# 甲站在**自己**的地上：被拉来的乙落在甲的格 ⇒ 照常付租金给甲（"真结算了"的可见凭据）
	_tile_table(g, {1: [p0]})
	g.hp[0].pos = p0
	g.hp[1].pos = 8
	await g._apply_card(g.hp[0], {"t": "拉你过来", "pull_target": true, "_target": 2})
	_check(int(g.hp[1].pos) == p0, "乙被拉到甲这一格（pos 8 ⇒ %d）" % int(g.hp[1].pos))
	var rent := GameData.rent_for(p0, g.htiles)
	_check(int(g.hp[1].money) == 5000 - rent and int(g.hp[0].money) == 5000 + rent,
		"被拉来的人**照常结算落点**：乙付租金 %d 给甲（实得 %d / %d）" % [
			rent, int(g.hp[1].money), int(g.hp[0].money)])
	_check(int(g.hp[0].pos) == p0, "甲自己没被挪动")

func _test_push_back(g) -> void:
	print("== 位置：推退（push_back，照常结算落点） ==")
	var p0 := _prop_idx(0)
	var from_idx := p0 + 2   # 从 p0 往后 2 格正好落回 p0（不经过起点）
	_tile_table(g, {1: [p0]})
	g.hp[0].pos = 0
	g.hp[1].pos = from_idx
	await g._apply_card(g.hp[0], {"t": "推你一把", "push_back": 2, "_target": 2})
	_check(int(g.hp[1].pos) == p0, "乙后退 2 格（pos %d ⇒ %d）" % [from_idx, int(g.hp[1].pos)])
	var rent := GameData.rent_for(p0, g.htiles)
	_check(int(g.hp[1].money) == 5000 - rent and int(g.hp[0].money) == 5000 + rent,
		"后退落点**照常结算**：乙付租金 %d 给甲（实得 %d / %d）" % [
			rent, int(g.hp[1].money), int(g.hp[0].money)])
	# 后退途中跨过起点 ⇒ 照常领工资（`机会卡.md` §三「与 move_steps 同口径」）；
	# 落点 52 号格是甲的地 ⇒ 再照常付一次租金
	var last := _prop_idx(29)   # 52 号格（最末一块地产）
	_tile_table(g, {1: [last]})
	g.hp[0].pos = 0
	g.hp[1].pos = 1
	var sal := int(g._salary_amount(g.hp[1]))
	var rent2 := GameData.rent_for(last, g.htiles)
	await g._apply_card(g.hp[0], {"t": "推你一把", "push_back": 5, "_target": 2})
	_check(int(g.hp[1].pos) == last, "后退 5 格：1 ⇒ %d（跨过起点绕回顶边）" % int(g.hp[1].pos))
	_check(int(g.hp[1].money) == 5000 + sal - rent2,
		"途中跨过起点领工资 +%d、落点又付租金 %d（实得 %d）" % [
			sal, rent2, int(g.hp[1].money)])

func _test_shuffle_pos(g) -> void:
	print("== 位置：全场洗位（shuffle_pos，无目标） ==")
	var p0 := _prop_idx(0)
	var p1 := _prop_idx(1)
	var p2 := _prop_idx(2)
	# 丁是**地主**（30 块地全归他）：谁被洗到谁的格上都要付租 ⇒ 钱一分不动才说明没结算
	var t := _fresh_tiles()
	for i in t.size():
		if int(t[i].owner) == GameData.NO_OWNER and String(GameData.TILES[i].get("type", "")) == "property":
			t[i].owner = 4
	_setup(g, [_mk_player(1, "甲", 5000), _mk_player(2, "乙", 5000),
		_mk_player(3, "丙", 5000), _mk_player(4, "丁", 5000)], t)
	g.hp[0].pos = p0
	g.hp[1].pos = p1
	g.hp[2].pos = p2
	g.hp[3].pos = 8   # 8 号格不是地产：丁换到别人格上要付租，别人换到 8 上什么也不用付
	var before := [int(g.hp[0].pos), int(g.hp[1].pos), int(g.hp[2].pos), int(g.hp[3].pos)]
	var t0 := Time.get_ticks_msec()
	await g._apply_card(g.hp[0], {"t": "大风吹", "shuffle_pos": true})
	var ms := Time.get_ticks_msec() - t0
	var after := [int(g.hp[0].pos), int(g.hp[1].pos), int(g.hp[2].pos), int(g.hp[3].pos)]
	before.sort()
	after.sort()
	_check(after == before, "存活玩家的位置**多重集守恒**（洗前 %s / 洗后 %s）" % [str(before), str(after)])
	_check(ms < 2000, "无目标：不进选目标态、也不空等一个操作窗口（实耗 %d ms）" % ms)
	_check(int(g.hp[0].money) == 5000 and int(g.hp[1].money) == 5000 \
		and int(g.hp[2].money) == 5000 and int(g.hp[3].money) == 5000,
		"洗位**不结算落点**：四个人都站在丁的地上，租金一分没动")
	# 出局者不参与洗牌（他的位置原地不动）
	_tile_table(g, {})
	g.hp[0].pos = 3
	g.hp[1].pos = 11
	g.hp[2].pos = 40
	g.hp[3].pos = 20   # 出局的丁
	await g._apply_card(g.hp[0], {"t": "大风吹", "shuffle_pos": true})
	var alive_pos := [int(g.hp[0].pos), int(g.hp[1].pos), int(g.hp[2].pos)]
	alive_pos.sort()
	_check(alive_pos == [3, 11, 40], "只洗存活的三家（实得 %s）" % str(alive_pos))
	_check(int(g.hp[3].pos) == 20, "出局者的位置不参与洗牌（仍是 20）")

## 免疫口径（`机会卡.md` §四）：夺地 take / 强买 / 拉人 / 推退是 debuff ⇒ 目标持皂整条免疫；
## 互换 / 换位是**中性**（一 debuff 一 buff 相抵）⇒ 香皂无效；全场洗位无目标 ⇒ 不吃任何人的香皂。
func _test_tile_soap(g) -> void:
	print("== 地皮 / 位置：香皂口径 ==")
	var p0 := _prop_idx(0)
	var p1 := _prop_idx(1)
	# debuff 四条：目标持皂 ⇒ 整条免疫
	var cases := {"seize_tile": "take", "force_buy_tile": 150,
		"pull_target": true, "push_back": 2}
	for field in cases:
		_tile_table(g, {2: [p1]}, {p1: 2})
		g.hp[0].pos = p0
		g.hp[1].pos = 8
		g.hp[1].items = [{"id": "空想者的香皂", "melt_left": 10}]
		var card := {"t": "地皮卡", "_target": 2}
		card[field] = cases[field]
		var log0 := _log_len(g)
		await g._apply_card(g.hp[0], card)
		_check(_log_at(g, "挡下了", log0) >= 0, "%s：战报写明被香皂挡下（真走了那道闸）" % field)
		_check(int(g.htiles[p1].owner) == 2 and int(g.htiles[p1].level) == 2, "%s：地皮没易主" % field)
		_check(int(g.hp[1].pos) == 8 and int(g.hp[0].pos) == p0, "%s：两边位置都没动" % field)
		_check(int(g.hp[0].money) == 5000 and int(g.hp[1].money) == 5000, "%s：现金一分没动" % field)
	# 中性两条：目标持皂照样生效（战报里连"挡下了"都不该有）
	_tile_table(g, {1: [p0], 2: [p1]}, {p0: 1, p1: 2})
	g.hp[1].items = [{"id": "空想者的香皂", "melt_left": 10}]
	var log1 := _log_len(g)
	await g._apply_card(g.hp[0], {"t": "换宿", "seize_tile": "swap", "_target": 2})
	_check(int(g.htiles[p0].owner) == 2 and int(g.htiles[p1].owner) == 1 \
		and _log_at(g, "挡下了", log1) < 0,
		"互换是**中性**：目标持皂照样换得成（也没走免疫那道闸）")
	_tile_table(g, {})
	g.hp[0].pos = p0
	g.hp[1].pos = p1
	g.hp[1].items = [{"id": "空想者的香皂", "melt_left": 10}]
	log1 = _log_len(g)
	await g._apply_card(g.hp[0], {"t": "霸占床位", "swap_pos": true, "_target": 2})
	_check(int(g.hp[0].pos) == p1 and int(g.hp[1].pos) == p0 and _log_at(g, "挡下了", log1) < 0,
		"换位是**中性**：目标持皂照样换得成")
	# 中性那两条**不碰** `_immune_debuff`：不然会顺手把护腕的盾扣掉（盾是给 debuff 用的）
	_tile_table(g, {})
	g.hp[0].pos = p0
	g.hp[1].pos = p1
	g.hp[1].shield = 1
	g.hp[1].items = [{"id": "护腕"}]
	await g._apply_card(g.hp[0], {"t": "霸占床位", "swap_pos": true, "_target": 2})
	_check(int(g.hp[1].get("shield", 0)) == 1 and g.hp[1].items.size() == 1 \
		and int(g.hp[1].pos) == p0,
		"中性换位不消耗护腕的盾（换位照常发生）")
	# 全场洗位：抽卡者持皂也挡不住（无目标）
	_tile_table(g, {})
	g.hp[0].pos = 3
	g.hp[1].pos = 11
	g.hp[2].pos = 40
	g.hp[0].items = [{"id": "空想者的香皂", "melt_left": 10}]
	var log2 := _log_len(g)
	await g._apply_card(g.hp[0], {"t": "大风吹", "shuffle_pos": true})
	var after := [int(g.hp[0].pos), int(g.hp[1].pos), int(g.hp[2].pos)]
	after.sort()
	_check(after == [3, 11, 40] and _log_at(g, "挡下了", log2) < 0,
		"全场洗位**无目标**：抽卡者持皂也挡不住（位置仍是那三个的多重集）")
	# debuff 那条走的仍是既有的 `_immune_debuff`：护腕的盾同样挡下、并消耗掉
	_tile_table(g, {2: [p1]})
	g.hp[1].shield = 1
	g.hp[1].items = [{"id": "护腕"}]
	await g._apply_card(g.hp[0], {"t": "夺地令", "seize_tile": "take", "_target": 2})
	_check(int(g.htiles[p1].owner) == 2 and int(g.hp[1].get("shield", 0)) == 0 \
		and g.hp[1].items.is_empty(),
		"debuff 夺地被护腕挡下、盾消耗掉（走的是既有 `_immune_debuff`）")

# ================= 抉择卡（Task 12） =================
#
# 一张卡给 2~3 个分支、由抽到的人自己挑；**每个分支自带一段效果字段**，按 `_apply_card` 的
# 同一套分派结算（所以「告密还是包庇」可以一支带目标、一支给钱）。bot / 休眠托管 / 自动回归 /
# 没作答 ⇒ 取第一项。
#
# 作答走卡面那排按钮（`DeckReveal.show_choices` → `choice_picked` → `_on_card_choice` →
# 客户端 `c_choice` 回程 / 房主直接记下），归属校验与选目标同一套。

func _test_choices(g) -> void:
	_test_choices_iface(g)
	await _test_choices_single(g)
	await _test_choices_managed(g)
	await _test_choices_pick(g)
	_test_choices_spectator(g)
	_test_choices_ownership(g)

## 存在性闸（同上 `_test_iface` 那条）：实现缺席时下面每条都会在调用处中断、`fails` 一个都不涨。
func _test_choices_iface(g) -> void:
	print("== 抉择卡：接口齐备 ==")
	_check(_has_prop(g, "_choice_pick"), "成员 _choice_pick 在位")
	for nm in ["_await_card_choice", "_on_card_choice"]:
		_check(g.has_method(nm), "方法 %s 在位" % nm)
	for nm in ["s_card_choices", "c_choice"]:
		_check(g.has_method(nm), "RPC %s 在位" % nm)
	var dr = g.deck_reveal
	_check(dr != null, "（前置）屏幕层抽卡演出组件在（否则下面几条是空的）")
	if dr == null:
		return
	_check(dr.has_signal("choice_picked"), "DeckReveal.choice_picked 信号在位")
	for nm in ["show_choices", "is_choice_visible"]:
		_check(dr.has_method(nm), "DeckReveal.%s 在位" % nm)
	# 方向是协议的一部分（钉法同 hud_test 的 c_card_ok / s_card_close）。
	var rcfg: Dictionary = g.get_script().get_rpc_config()
	var ck := StringName("c_choice")
	var sk := StringName("s_card_choices")
	_check(rcfg.has(ck) and rcfg.has(sk), "c_choice / s_card_choices 都登记在册")
	if rcfg.has(ck):
		_check(int((rcfg[ck] as Dictionary).get("rpc_mode", -1)) == MultiplayerAPI.RPC_MODE_ANY_PEER,
			"c_choice 是 any_peer（客户端 → 房主）")
	if rcfg.has(sk):
		var sc: Dictionary = rcfg[sk]
		_check(int(sc.get("rpc_mode", -1)) == MultiplayerAPI.RPC_MODE_AUTHORITY \
			and bool(sc.get("call_local", false)),
			"s_card_choices 是 authority + call_local（房主 → 全员，房主自己也进抉择态）")

## 0 项 / 1 项：没什么可挑的 ⇒ **不进交互**（不开窗口、不发按钮），照常按第 0 项结算。
func _test_choices_single(g) -> void:
	print("== 抉择卡：≤1 项 ⇒ 直接取第 0 项、不进交互 ==")
	_target_table(g)   # 甲 5000
	var t0 := Time.get_ticks_msec()
	await g._apply_card(g.hp[0], {"t": "单选", "choices": [{"t": "唯一一支：+¥300", "money": 300}]})
	var ms := Time.get_ticks_msec() - t0
	_check(int(g.hp[0].money) == 5300, "一支也照常结算（甲 5300，实得 %d）" % int(g.hp[0].money))
	_check(ms < 300, "且**立刻**结算、不开操作窗口（实耗 %d ms，托管那支要 0.6s）" % ms)
	_check(g._choice_pick == -1 and g._awaiting_card == 0, "没进抉择态（判别位与归属位都没被写脏）")
	# 空表（数据写坏）：整段作废 —— 关键是**别去索引 `choices[0]`**（那样当场就越界崩）
	_target_table(g)
	await g._apply_card(g.hp[0], {"t": "空抉择", "choices": []})
	_check(int(g.hp[0].money) == 5000 and int(g.hp[0].pos) == 0,
		"空抉择表 ⇒ 当这张卡没有那段（一分没动、也没崩）")

## bot / 休眠托管 / 自动回归（房主自己那张）都不等人点 ⇒ 取第一项。
func _test_choices_managed(g) -> void:
	print("== 抉择卡：托管 / 机器人 / 自动回归 ⇒ 取第一项 ==")
	var card := {"t": "翘课去兼职", "choices": [
		{"t": "去兼职：+¥1200", "money": 1200},
		{"t": "去上课：前进 4 格", "move_steps": 4}]}
	# 休眠托管。用**真实机制**：`sleep = 1` ⇒ `_is_managed` 为真（给实例覆盖 `_is_managed`
	# 那种写法在 GDScript 里做不到，见 tests/blackshop_test.gd 里同款做法）。
	_target_table(g)
	g.hp[0].sleep = 1
	await g._apply_card(g.hp[0], card)
	_check(int(g.hp[0].money) == 6200, "休眠托管取第一项（甲 5000 → 6200，实得 %d）" % int(g.hp[0].money))
	_check(int(g.hp[0].pos) == 0, "第二项（前进 4 格）没被结算")
	# 机器人
	_target_table(g)
	g.hp[0].bot = true
	await g._apply_card(g.hp[0], card)
	_check(int(g.hp[0].money) == 6200, "机器人取第一项（实得 %d）" % int(g.hp[0].money))
	_check(int(g.hp[0].pos) == 0, "第二项也没被结算")
	# 自动回归里房主自己那张：不等真人点（`_await_card_confirm` 的同一支）
	_target_table(g)
	g.at_mode = "host"
	await g._apply_card(g.hp[0], card)
	g.at_mode = ""
	_check(int(g.hp[0].money) == 6200, "自动回归里房主自己那张取第一项（实得 %d）" % int(g.hp[0].money))
	# 没人作答（真人窗口没开出来 / 超时）：`_choice_pick` 一直没人写 ⇒ 落到第 0 项。
	# **真超时那一趟要空等满 25 秒**（本机成本太高），`_await_turn_window` 的超时本身由
	# hud_test 的抽卡确认那段钉；这里钉的是"没等到作答时取第一项"这个落点。
	_target_table(g)
	await g._apply_card(g.hp[0], card)   # `running` 关着 ⇒ 窗口一次都不进（hud_test 里同一条）
	_check(int(g.hp[0].money) == 6200, "没人作答 → 落到第 0 项（实得 %d）" % int(g.hp[0].money))
	_check(int(g.hp[0].pos) == 0, "第二项同样没被结算")
	_check(g._choice_pick == -1 and g._awaiting_card == 0, "四路都收尾干净（判别位与归属位复位）")

## 真人作答（走真实那条：房主本机点击 ⇒ `_on_card_choice`）：**挑中的那一支才结算**。
func _test_choices_pick(g) -> void:
	print("== 抉择卡：挑中的那一支才结算 ==")
	# 「告密还是包庇」的骨架：两支都带目标字段，一支给钱、一支送监 ⇒ 一眼看得出走了哪支。
	# `_target` 是测试 / 摆拍的注入键（见 `_card_target_for`），绕开选目标交互 ——
	# 那条交互由 T9 那节单独钉。
	var card := {"t": "告密还是包庇", "choices": [
		{"t": "包庇：他给你 ¥800", "steal_from": 800, "_target": 2},
		{"t": "告密：送他去宿委会", "jail_to": true, "_target": 2}]}
	_target_table(g)   # 甲 5000 / 乙 1000 / 丙 800 / 丁（出局）
	g.running = true   # 窗口才进得去（本套件开头把它关了，见 hud_test 里同一条说明）
	var out: Array = []
	_answer_choice_when_waiting(g, 1, out)   # 不 await：等协程跑到窗口那句再作答
	await g._apply_card(g.hp[0], card)
	g.running = false
	_check(out.size() == 1 and int(out[0]) == 1, "（前置）确实进了抉择态、等的是抽卡者本人")
	_check(int(g.hp[1].pos) == GameData.JAIL_TILE and int(g.hp[1].skip) == 1,
		"第二支生效：乙被送进宿委会并跳过下一回合（pos %d / skip %d）" % [
			int(g.hp[1].pos), int(g.hp[1].skip)])
	_check(int(g.hp[0].money) == 5000 and int(g.hp[1].money) == 1000,
		"第一支（夺取 800）一点没落地（实得 甲 %d / 乙 %d）" % [int(g.hp[0].money), int(g.hp[1].money)])
	_check(g._choice_pick == -1 and g._awaiting_card == 0, "收尾干净（判别位与归属位复位）")
	# 递进结算**只读**原来那张卡（`merged` 是分支的副本）：同一份 `card` 再来一次，结果一模一样
	#（下面这段就是拿**同一个字典**重跑一遍 —— 上一趟真要把 `t` / 字段挖走或改写，这里就崩了）
	_check((card.choices as Array).size() == 2 and (card.choices as Array)[1].has("t") \
		and not card.has("steal_from") and not card.has("jail_to") and not card.has("_target"),
		"原 card 字典没被污染（分支还在、没往外漏字段）")
	# 反过来选第一支：钱的活也照同一套字段结算
	_target_table(g)
	g.running = true
	out = []
	_answer_choice_when_waiting(g, 0, out)
	await g._apply_card(g.hp[0], card)
	g.running = false
	_check(int(g.hp[0].money) == 5800 and int(g.hp[1].money) == 200,
		"第一支生效：甲夺取 800（实得 甲 %d / 乙 %d）" % [int(g.hp[0].money), int(g.hp[1].money)])
	_check(int(g.hp[1].pos) == 0 and int(g.hp[1].skip) == 0, "第二支（送监）没落地")

## 等协程跑进抉择态之后替玩家点第 idx 枚（房主本机那条路）。`out` 收回实际的归属位
##（顺便把"等的是不是抽卡者本人"钉死）。测试里拿不到挂起的协程句柄，就这么错帧作答。
func _answer_choice_when_waiting(g, idx: int, out: Array) -> void:
	for _i in 300:
		await process_frame
		if int(g._awaiting_card) != 0:
			out.append(int(g._awaiting_card))
			g._on_card_choice(idx)
			return

## 只有抽卡者那一端出按钮（口径同 T9 对选目标态的修法）：`s_card_choices` 是全员广播，
## 观众看到的是同一张卡，但按钮整排不出镜 —— 也**不该**由他作答（另有 `c_choice` 的归属校验兜底）。
func _test_choices_spectator(g) -> void:
	print("== 抉择卡：只有抽卡者出按钮 ==")
	_setup(g, [_mk_player(1, "甲"), _mk_player(2, "乙")], _fresh_tiles())   # my_peer = 1
	var dr = g.deck_reveal
	if dr == null:
		return   # 存在性闸已经报过红了
	dr.show_card("机会", "info", "测试：抉择卡")
	dr.tick(dr.CARD_TIME + 0.05)   # 推出停留段：卡停住
	_check(dr.is_showing() and dr.is_awaiting_confirm(), "（前置）卡已停在「等作答」上")
	g.s_card_choices.rpc(["包庇", "告密"], 2)   # 抽卡者是 2，本机是 1
	_check(not dr.is_choice_visible(), "旁观者（不是抽卡者）→ 按钮整排不出镜")
	_check((dr._choice_labels as Array).is_empty(), "旁观者那端连标签都不留")
	g.s_card_choices.rpc(["包庇", "告密"], 1)   # 这一张是抽卡者自己抽的
	_check(dr.is_choice_visible(), "抽卡者本人 → 按钮出镜")
	_check((dr._choice_btns as Array).size() == 2, "按标签建了 2 枚（实得 %d 枚）" % (dr._choice_btns as Array).size())
	g.s_card_choices.rpc([], 1)                 # 收尾（空标签 = 退出抉择态）
	_check(not dr.is_choice_visible(), "收尾包 ⇒ 退出抉择态、按钮收掉")
	dr.request_close()
	dr.tick(dr.BACK + 0.05)
	_check(not dr.is_showing(), "（收尾）演出照旧收回")

## 作答只有抽卡者本人算数（做法同 `c_card_ok` / `c_card_target`）：`s_card_choices` 是全员广播，
## 别人那端也有同一张卡与同一排按钮 —— 少了这道闸，谁先点一下就能替抽卡者定下分支。
func _test_choices_ownership(g) -> void:
	print("== 抉择卡：归属校验 ==")
	_target_table(g)
	g._awaiting_card = 999        # 假装正等着别人（headless 下本机不是任何人的"远端"）
	g._choice_pick = -1
	g.c_choice(1)
	_check(g._choice_pick == -1, "不是抽卡者本人 → c_choice 被丢掉")
	g._awaiting_card = 0          # 哨兵：没有抉择在等
	g.c_choice(1)
	_check(g._choice_pick == -1, "没有抉择在等 → 也丢掉（哨兵 0 谁都不匹配）")
	g._awaiting_card = 1          # 本机就是抽卡者（直连：sender = 0）
	g.c_choice(1)
	_check(g._choice_pick == 1, "本机就是抽卡者 → 收下（实得 %d）" % g._choice_pick)
	g._choice_pick = -1
	g._awaiting_card = 0

# ================= 情报类 3 个字段（Task 13） =================
#
# 为什么情报类只能围绕**牌堆**做：本作的身家、现金、背包、地皮本来就全是公开信息
#（`_peers_info` 把 `worth` 挂在桌面立牌上、公开背包另有弹窗、地皮归属肉眼可见）——
# **唯一真正隐藏的是机会牌堆的牌序**。所以「窥探现金 / 公开身家」那类卡是废卡（已从字段表里
# 去掉），这一类的三条都只动牌堆、**不动任何对局状态**（钱 / 位置 / 跳过一概不碰）。
#
# 三条字段的落点见 `机会卡.md` §三：与目标类 / 地皮类**同组**、排在 `move_steps` 之前
#（`_apply_card` 里那两段 `for` 之后、`move_steps` 那条之前）。

func _test_deck_iface(g) -> void:
	print("== 情报：接口齐备 ==")
	_check(_has_prop(g, "_peeked"), "成员 _peeked 在位")
	_check(g.has_method("_card_apply_deck"), "方法 _card_apply_deck 在位")
	# 私密那条**不该另起一套**：既有的 `s_peek_card`（广播 + 收端自过滤）就是那条路
	_check(g.has_method("s_peek_card"), "私密那条走既有的 s_peek_card")

## 摆一桌干净局面，并把牌堆换成**已知序列**（`_new_event_deck` 每次都洗牌 ⇒ 必须自己覆盖），
## `_peeked` 也清空 —— 用例之间不串味。
func _deck_table(g, cards: Array) -> void:
	_target_table(g)   # 甲 5000 / 乙 1000 / 丙 800 / 丁（出局）
	g._event_deck = []
	for c in cards:
		g._event_deck.append({"t": String(c)})
	g._peeked = []

## 牌堆当前的牌面文案序列（用例拿它比对**顺序**，不是只比张数）。
func _deck_titles(g) -> Array:
	var out := []
	for c in (g._event_deck as Array):
		out.append(String((c as Dictionary).get("t", "?")))
	return out

## `_peeked` 当前的牌面文案序列（同上一份，读的是"被记下的那几张"）。
func _peeked_titles(g) -> Array:
	var out := []
	for c in (g._peeked as Array):
		out.append(String((c as Dictionary).get("t", "?")))
	return out

func _test_deck_fields(g) -> void:
	# 存在性闸（`_test_deck_iface`）已经单独报过红；实现缺席时再往下走，只会在读 `_peeked` /
	# 调 `_card_apply_deck` 那一行 SCRIPT ERROR 就地中断 —— `await` 就此挂住，整个套件要跑到
	# 30s 超时才退，红得看不出是哪一条。所以这里先按同一套判据挡一道。
	if not _has_prop(g, "_peeked") or not g.has_method("_card_apply_deck"):
		return
	await _test_bury_deck(g)
	await _test_peek_deck(g)
	await _test_shuffle_deck(g)
	await _test_deck_pure(g)
	await _test_deck_order(g)

func _test_bury_deck(g) -> void:
	print("== 情报：塞底（bury_deck） ==")
	_deck_table(g, ["一", "二", "三"])
	await g._apply_card(g.hp[0], {"t": "压箱底", "bury_deck": true})
	_check(_deck_titles(g) == ["二", "三", "一"],
		"顶张真的去了底部、其余相对顺序不变（实得 %s）" % str(_deck_titles(g)))
	_check((g._event_deck as Array).size() == 3, "牌堆不增不减（仍 3 张）")
	# 只剩一张：塞底等于原样（既不崩、也不掉牌）
	_deck_table(g, ["独苗"])
	await g._apply_card(g.hp[0], {"t": "压箱底", "bury_deck": true})
	_check(_deck_titles(g) == ["独苗"], "牌堆只剩一张时塞底仍是那一张（实得 %s）" % str(_deck_titles(g)))
	# 牌堆见底 ⇒ 先补洗一手再塞（不能对着空数组 `pop_front`）
	_deck_table(g, [])
	await g._apply_card(g.hp[0], {"t": "压箱底", "bury_deck": true})
	_check((g._event_deck as Array).size() > 1,
		"空牌堆 ⇒ 先补洗一手（实得 %d 张）" % (g._event_deck as Array).size())

func _test_peek_deck(g) -> void:
	print("== 情报：偷看（peek_deck） ==")
	_deck_table(g, ["一", "二", "三", "四"])
	await g._apply_card(g.hp[0], {"t": "小道消息", "peek_deck": 2})
	_check((g._peeked as Array).size() == 2, "记下顶 2 张（实得 %d）" % (g._peeked as Array).size())
	_check(_peeked_titles(g) == ["一", "二"],
		"记的就是**顶 N 张**、顺序一致（实得 %s）" % str(_peeked_titles(g)))
	_check(_deck_titles(g) == ["一", "二", "三", "四"], "偷看**不抽牌**：牌堆原封不动")
	# N 比牌堆还大 ⇒ 只看到牌堆现有那几张（`mini` 挡住越界）
	await g._apply_card(g.hp[0], {"t": "小道消息", "peek_deck": 99})
	_check(_peeked_titles(g) == ["一", "二", "三", "四"],
		"N 超过牌堆大小 ⇒ 只记到现有那几张、不越界（实得 %s）" % str(_peeked_titles(g)))
	# 牌堆见底 ⇒ 先补洗一手再偷看
	_deck_table(g, [])
	await g._apply_card(g.hp[0], {"t": "小道消息", "peek_deck": 1})
	_check((g._peeked as Array).size() == 1,
		"空牌堆 ⇒ 先补洗一手（偷看得一张，实得 %d）" % (g._peeked as Array).size())
	# **私密**那半：走的是既有 `s_peek_card`（广播 + 收端自过滤，见该函数注释）——
	# 抽卡者本人看得到，旁人那端一个字都不该有。
	_deck_table(g, ["私密甲", "私密乙"])
	var log1 := _log_len(g)
	await g._apply_card(g.hp[0], {"t": "小道消息", "peek_deck": 2})
	_check(_log_at(g, "私密甲", log1) >= 0, "抽卡者本人看得到内容（走的仍是既有 `s_peek_card`）")
	_deck_table(g, ["私密丙", "私密丁"])
	g.my_peer = 2   # 本机是乙，抽卡的是甲
	var log2 := _log_len(g)
	await g._apply_card(g.hp[0], {"t": "小道消息", "peek_deck": 2})
	_check(_log_at(g, "私密丙", log2) < 0, "旁观者那端看不到内容（既有那条「广播 + 收端自过滤」照旧）")
	_check(_peeked_titles(g) == ["私密丙", "私密丁"],
		"牌堆情报本身照旧记在房主侧（私密只关战报那半，实得 %s）" % str(_peeked_titles(g)))

func _test_shuffle_deck(g) -> void:
	print("== 情报：重洗（shuffle_deck） ==")
	_deck_table(g, ["一", "二", "三", "四", "五"])
	g._peeked = [{"t": "旧预知"}]   # 先摆一条预知：重洗必须把它作废
	var before := _deck_titles(g)
	before.sort()
	await g._apply_card(g.hp[0], {"t": "重新洗牌", "shuffle_deck": true})
	var after := _deck_titles(g)
	after.sort()
	_check(after == before, "洗牌**元素多重集守恒**（不增不减：洗前 %s / 洗后 %s）" % [str(before), str(after)])
	_check((g._event_deck as Array).size() == 5, "张数不变（仍 5 张）")
	_check((g._peeked as Array).is_empty(), "重洗把所有人的预知作废（`_peeked` 清空）")
	# 钉「真的调了 shuffle」而不只是顺手清了 `_peeked`：连洗 20 次，至少有一次牌序与原先不同。
	# 5 张的排列有 120 种 ⇒ 20 次全同的概率是 (1/120)^20，不是靠运气过的。
	_deck_table(g, ["一", "二", "三", "四", "五"])
	var orig := _deck_titles(g)
	var changed := 0
	for _i in 20:
		await g._apply_card(g.hp[0], {"t": "重新洗牌", "shuffle_deck": true})
		if _deck_titles(g) != orig:
			changed += 1
	_check(changed > 0, "确实重洗了牌序（20 次里有 %d 次与原先不同）" % changed)
	# 牌堆见底 ⇒ 先补洗一手（先有牌可洗）
	_deck_table(g, [])
	await g._apply_card(g.hp[0], {"t": "重新洗牌", "shuffle_deck": true})
	_check((g._event_deck as Array).size() > 1,
		"空牌堆 ⇒ 先补洗一手（实得 %d 张）" % (g._event_deck as Array).size())

## 三个字段都**不产生任何对局状态变化**（不动钱、不动位置、不动跳过）—— 纯情报 / 牌序操作。
func _test_deck_pure(g) -> void:
	print("== 情报：不动任何对局状态 ==")
	var cases := {"peek_deck": 2, "shuffle_deck": true, "bury_deck": true}
	for field in cases:
		_deck_table(g, ["一", "二", "三", "四"])
		g.hp[0].pos = 3
		g.hp[1].pos = 11
		var card := {"t": "情报卡"}
		card[field] = cases[field]
		await g._apply_card(g.hp[0], card)
		_check(int(g.hp[0].money) == 5000 and int(g.hp[1].money) == 1000 \
			and int(g.hp[2].money) == 800 and int(g.hp[3].money) == 1000,
			"%s：四家现金一分没动" % field)
		_check(int(g.hp[0].pos) == 3 and int(g.hp[1].pos) == 11,
			"%s：位置没动（连落点都没结算）" % field)
		_check(int(g.hp[0].skip) == 0 and int(g.hp[1].skip) == 0, "%s：跳过回合也没被写" % field)

## 插卡顺序（`机会卡.md` §三）：情报类与目标类 / 地皮类**同组**，都排在 `move_steps` 之前。
## 钉法：一张卡同时带 `bury_deck` + `move_steps: -1`，且抽卡者持【雨伞】—— `move_steps` 那条
## 遇后退会**提前 `return`**，情报类要是排在它后面就一并被跳过。
func _test_deck_order(g) -> void:
	print("== 情报：插卡顺序在 move_steps 之前 ==")
	_deck_table(g, ["一", "二", "三", "四"])
	g.hp[0].items = [{"id": "雨伞"}]
	var log0 := _log_len(g)
	await g._apply_card(g.hp[0], {"t": "顺序钉子", "bury_deck": true, "move_steps": -1})
	_check(_deck_titles(g) == ["二", "三", "四", "一"],
		"情报类生效：没被 move_steps 的提前 return 跳过（实得 %s）" % str(_deck_titles(g)))
	var i_move := _log_at(g, "免疫了后退", log0)
	var i_deck := _log_at(g, "塞到了最底下", log0)
	_check(i_move >= 0, "（前提）move_steps 那条确实提前 return 了")
	_check(i_deck >= 0 and i_deck < i_move, "战报次序：情报类在 move_steps 之前（%d < %d）" % [i_deck, i_move])

# ================= 卡型配色 + 三类卡分布（Task 14，批 2 收尾） =================
#
# 卡型（`GameData.card_kind`）决定**卡面配色**：抽卡演出（`s_card.rpc(..., kind, ...)`）与
# 图鉴页读的是同一份，所以这里是「15 个新字段都认得」的钉子 —— 漏认的字段会掉进兜底的 info，
# 卡面配色当场错（口径见 机会卡.md §三）。
#
# 分布这块是本批补上的：批 1 立三类抽卡时，85/10/5 一直**没有测试钉住**（批 1 审查时明确
# 记了「接受欠到批 2」）。概率是写死的常量（`GameData.CHANCE_P` 等），大样本 + ±3% 足够。

## 只摆一个字段的卡，取它的卡型 —— 省得 15 份字典字面量抄一遍。
func _kind_of(field: String, val: Variant) -> String:
	var card := {}
	card[field] = val
	return GameData.card_kind(card)

func _test_kind_and_dist(g) -> void:
	print("== 卡型配色 + 三类卡分布 ==")
	var good_f := {"steal_from": 400, "charge_to": 300, "each_from_target": 200,
		"steal_item_from": true, "seize_tile": "take", "force_buy_tile": 33}
	for f in good_f:
		_check(_kind_of(f, good_f[f]) == "good", "%s ⇒ good（目标 / 地皮类：对抽卡者有利）" % f)
	var move_f := {"swap_pos": true, "pull_target": true, "push_back": 2, "shuffle_pos": true}
	for f in move_f:
		_check(_kind_of(f, move_f[f]) == "move", "%s ⇒ move（位移类）" % f)
	var info_f := {"choices": [{"t": "甲"}], "peek_deck": 2, "shuffle_deck": true, "bury_deck": true}
	for f in info_f:
		_check(_kind_of(f, info_f[f]) == "info", "%s ⇒ info（抉择 / 情报类）" % f)
	_check(_kind_of("jail_to", true) == "jail", "jail_to ⇒ jail（送**别人**去宿委会，单列一色）")
	# 契约：`jail_to` 的判定**先于** `go_jail`（今天没有同时带两者的卡，但顺序是契约）。
	# 能钉住的是「jail_to 压过新插进来那一整块」：同带位移字段时仍取 jail。
	_check(GameData.card_kind({"jail_to": true, "swap_pos": true}) == "jail",
		"jail_to 先命中：同带位移字段仍是 jail")
	_check(_kind_of("go_jail", true) == "jail", "go_jail 照旧 ⇒ jail（原有那份判定没被顶掉）")
	# 新插的整块排在 `move_steps` 之前：好字段压过位移（同带两者时按更重的那类上色）
	_check(GameData.card_kind({"force_buy_tile": 33, "move_steps": 3}) == "good",
		"新块先于 move_steps：地皮字段压过位移")

	# ---- 分布 ----
	# `_settings` 是**静态类型** `GameSettings`，赋字典会当场 SCRIPT ERROR ⇒ 运行期
	# `load()` 一份真 settings 换进去（别写 `GameSettings.` 那个编译期类名标识符，
	# 本仓 `--script` 下踩过，见 doc/game-design/设计决策留痕.md §二十三）。
	var saved = g._settings
	var st = load("res://scripts/game_settings.gd").new()
	g._settings = st
	var n := 20000
	# 开档（畸变「中」）：85 / 10 / 5
	st.ab_freq = "中"
	var cnt := {"card": 0, "item": 0, "aberr": 0}
	for _i in n:
		cnt[g._roll_chance_kind()] += 1
	var pc := float(cnt.card) / float(n)
	var pi := float(cnt.item) / float(n)
	var pa := float(cnt.aberr) / float(n)
	_check(absf(pc - 0.85) < 0.03, "开档：机会卡 ≈85%%（实得 %.3f）" % pc)
	_check(absf(pi - 0.10) < 0.03, "开档：道具卡 ≈10%%（实得 %.3f）" % pi)
	_check(absf(pa - 0.05) < 0.03, "开档：畸变卡 ≈5%%（实得 %.3f）" % pa)
	# 关档（畸变「关」）：那 5% **并入机会卡** ⇒ 90 / 10 / 0（机会卡.md §一 边界规则 1）。
	# **三条都要钉**：只断言「aberr == 0」钉不住任何东西 —— 把道具卡那 10% 也一并吞掉的写法
	# （阈值误写成 `CHANCE_P + CHANCE_ITEM_P + CHANCE_AB_P`）同样能让 aberr 归零、照样绿。
	st.ab_freq = "关"
	cnt = {"card": 0, "item": 0, "aberr": 0}
	for _i in n:
		cnt[g._roll_chance_kind()] += 1
	pc = float(cnt.card) / float(n)
	pi = float(cnt.item) / float(n)
	_check(int(cnt.aberr) == 0, "关档：畸变一次都不出（实得 %d 次）" % int(cnt.aberr))
	_check(absf(pc - 0.90) < 0.03, "关档：机会卡 ≈90%%——5%% 那档并进来了（实得 %.3f）" % pc)
	_check(absf(pi - 0.10) < 0.03, "关档：道具卡 ≈10%%——没被那 5%% 顺手吞掉（实得 %.3f）" % pi)
	g._settings = saved
