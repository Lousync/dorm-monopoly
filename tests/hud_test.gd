extends SceneTree
## HUD 回归：右栏名册 + 底栏（含「客户端视角」这一段）
##
## 为什么要有「客户端视角」：`s_state` 是 call_local，房主与客户端跑的是同一个处理函数，
## 差别只在「谁算出的状态」和 `my_peer`。所以喂一份状态、把 my_peer 设成客户端，
## 走的就是客户端那条路——比在本机拉两个实例更可靠（本机 UDP 端口常被环境拦掉）。
## godot --headless --path . --script tests/hud_test.gd

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

## 一份 4 人、身家互不相同的状态：甲(最富) 乙 丙 丁(最穷)，轮到我(=乙) 行动
## 棋盘上第一格小卖部（进店状态需要一个真实格号：shop_open 必须 >= 0）
func _shop_tile() -> int:
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "shop":
			return i
	return -1

func _state(turn_peer: int, with_shop: bool) -> Dictionary:
	var tiles := _fresh_tiles()
	var shop_idx := _shop_tile()
	var shops_d := {}
	if with_shop:
		shops_d[shop_idx] = {"slots": ["作弊器", "", ""]}
	# 给甲一块最贵的地（宿舍楼），让身家顺序与现金顺序不同 —— 名次必须按身家排
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].name) == "一号楼":
			tiles[i].owner = 1
			break
	return {
		"phase": "playing", "turn": turn_peer, "await": "roll", "await_peer": turn_peer,
		"roll_epoch": 1, "round": 3, "max_rounds": 30,
		"players": [
			{"peer": 1, "name": "甲", "color": 0, "bot": false, "money": 12000, "pos": 0,
				"alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [], "item_used": false},
			{"peer": 2, "name": "乙", "color": 1, "bot": false, "money": 20000, "pos": 3,
				"alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [], "item_used": false},
			{"peer": 3, "name": "丙", "color": 2, "bot": false, "money": 8000, "pos": 6,
				"alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [], "item_used": false},
			{"peer": 4, "name": "丁", "color": 3, "bot": false, "money": 100, "pos": 9,
				"alive": false, "skip": 0, "sleep": 0, "stamina": 0, "items": [{"id": "招财猫", "cd": 0}]},
		],
		"tiles": tiles, "shops": shops_d, "shop_open": shop_idx if with_shop else -1,
		"shop_peer": 2 if with_shop else 0, "black_peer": 0, "refresh_price": 500,
	}

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var net = root.get_node_or_null("Net")
	if net == null:
		printerr("  FAIL - 未找到 Net autoload")
		quit(1)
		return

	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.running = false
	for i in 4:
		await process_frame
	await create_timer(0.4).timeout

	print("== 右栏名册（客户端视角：我是乙，行动的也是我）==")
	g.my_peer = 2
	g.s_state(_state(2, false))          # 走客户端真正跑的那个处理函数
	await process_frame
	var rows: Array = g.roster_rows
	_check(rows.size() >= 4, "名册建了 4 行（实得 %d）" % rows.size())
	var visible_rows: Array = rows.filter(func(r) -> bool: return (r.root as Control).visible)
	_check(visible_rows.size() == 4, "4 名玩家各占一行（实得 %d）" % visible_rows.size())
	# 身家 = 现金 + 地产；甲 12000 + 一号楼地价(3800) = 15800 < 乙 20000 → 乙第一
	_check(String(visible_rows[0].name_l.text).begins_with("1. 乙"), "名次按身家排，乙第一（实得「%s」）"
		% String(visible_rows[0].name_l.text))
	_check(String(visible_rows[0].name_l.text).contains("（我）"), "自己那行标「（我）」")
	_check(String(visible_rows[0].money_l.text) == GameData.fmt_money(20000),
		"大字显示身家（实得 %s）" % String(visible_rows[0].money_l.text))
	_check(String(visible_rows[0].cash_l.text).contains(GameData.fmt_money(20000)),
		"次行显示现金（实得 %s）" % String(visible_rows[0].cash_l.text))
	# 甲 12000 现金 + 一号楼(宿舍楼 3800) = 15800 身家 → 排在现金 8000 的丙前面，
	# 这条正是「名次按身家而不是现金」的证据
	_check(String(visible_rows[1].name_l.text).begins_with("2. 甲"),
		"甲现金少但有地产，靠身家排到第 2（实得「%s」）" % String(visible_rows[1].name_l.text))
	_check(String(visible_rows[2].name_l.text).begins_with("3. 丙"),
		"丙只有现金，排到第 3（实得「%s」）" % String(visible_rows[2].name_l.text))
	_check(String(visible_rows[3].name_l.text).contains("破产"), "破产玩家标「破产」")
	_check(String(visible_rows[3].money_l.text) == "已出局", "破产玩家身家列显示「已出局」")
	# 行动者（我）的竖条点亮
	_check((visible_rows[0].bar as ColorRect).color.a > 0.5, "行动者那行竖条点亮")
	_check((visible_rows[1].bar as ColorRect).color.a < 0.5, "非行动者竖条不亮")

	print("== 客户端视角：行动者不是我 ==")
	g.my_peer = 9                         # 观战/掉线后重连之类：自己不在名册里
	g.s_state(_state(1, false))
	await process_frame
	var rows2: Array = g.roster_rows.filter(func(r) -> bool: return (r.root as Control).visible)
	_check(rows2.size() == 4, "自己不在名册里也不崩、仍是 4 行")
	var marked: Array = rows2.filter(func(r) -> bool: return String(r.name_l.text).contains("（我）"))
	_check(marked.is_empty(), "自己不在名册时没人被误标「（我）」")
	_check((rows2[1].bar as ColorRect).color.a > 0.5, "轮到甲（名次 2）时他的竖条点亮")

	print("== 名册缓存：状态没变不重建 ==")
	var sig_before: String = g._rail_sig
	g.s_state(_state(1, false))
	await process_frame
	_check(g._rail_sig == sig_before, "同一状态重复广播不复算（签名不变）")

	print("== 底栏与底板 ==")
	g.my_peer = 2
	g.s_state(_state(2, false))
	g._refresh_actions()
	await process_frame
	await process_frame
	g._process(0.0)
	_check(g.mat_bar.visible, "底栏（状态条）可见；阶段按钮已移到牌垫上")
	_check(g.dock_plate.visible, "底板随底栏一起出现")
	var band: Vector2 = g._dock_band()
	_check(g.dock_plate.position.x >= band.x - 0.5, "底板左缘不越过可用带（实得 %.0f / 带左 %.0f）"
		% [g.dock_plate.position.x, band.x])
	_check(g.dock_plate.position.x + g.dock_plate.size.x <= band.y + 0.5,
		"底板右缘不越过可用带（实得 %.0f / 带右 %.0f）"
			% [g.dock_plate.position.x + g.dock_plate.size.x, band.y])

	print("== 交易条顶掉底栏时底板一起收 ==")
	g.s_state(_state(2, true))            # shop_peer = 我
	g._process(0.0)
	await process_frame
	_check(g.shop_bar.visible, "小卖部操作条可见")
	_check(not g.mat_bar.visible, "底栏让位")
	_check(not g.dock_plate.visible, "底板一并收掉（不会留一块空底板）")

	g.get_tree().paused = false
	g.free()
	if fails == 0:
		print("HUD TEST: ALL PASS")
		quit(0)
	else:
		print("HUD TEST: %d FAILURES" % fails)
		quit(1)
