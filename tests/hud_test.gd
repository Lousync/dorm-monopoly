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
	_check(g.mat_bar.visible and g.action_bar.visible, "底栏两条可见")
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
	_check(not g.mat_bar.visible and not g.action_bar.visible, "底栏两条让位")
	_check(not g.dock_plate.visible, "底板一并收掉（不会留一块空底板）")

	print("== 战报：默认收起 + 消息在屏幕上方弹出 ==")
	_check(not g.log_panel.visible, "战报框默认收起")
	_check(String(g.log_toggle.text).contains("▾"),
		"收起时按钮显示「战报 ▾」（实得「%s」）" % String(g.log_toggle.text))
	_check(g.log_toast != null, "顶部弹出条容器已建")
	# 前面的几次 s_state 本身就产生过战报（走的是真实链路 _log → s_log），
	# 所以这里按「末条内容」断言，不依赖总数
	g._push_log_toast("[color=#74d188]甲 买下了便利店，花了 ¥1,600[/color]")
	await process_frame
	await process_frame
	var tn: int = g.log_toast.get_child_count()
	var last: Control = null
	var last_text := ""
	if tn > 0:
		last = g.log_toast.get_child(tn - 1)
		var rtls: Array = last.find_children("*", "RichTextLabel", true, false)
		if not rtls.is_empty():
			last_text = String((rtls[0] as RichTextLabel).text)
	_check(last_text.contains("便利店"),
		"战报消息会在屏幕上方弹出（末条 = 「%s」）" % last_text)
	# 宽度这条是防回归：RichTextLabel 的最小宽度默认是 0，若忘了关自动换行，
	# 气泡会被 SHRINK_CENTER 挤成一条几乎不可见的窄条（视觉上等于没有）。
	_check(last != null and last.size.x > 50.0,
		"弹出条裹得住文字而非被挤成窄条（实得 %.0f）" % (0.0 if last == null else last.size.x))
	for i in 6:
		g._push_log_toast("刷屏消息 %d" % i)
	await process_frame
	_check(g.log_toast.get_child_count() == 4,
		"连发刷屏时最多只留 4 条（实得 %d）" % g.log_toast.get_child_count())

	print("== 装修房子：4 级 + 等级配色 ==")
	_check(GameData.MAX_LEVEL == 4, "装修上限 4 级（实得 %d）" % GameData.MAX_LEVEL)
	_check(GameData.level_color(1) == Color(0.42, 0.80, 0.45), "1 级 = 绿")
	_check(GameData.level_color(2) == Color(0.36, 0.63, 0.94), "2 级 = 蓝")
	_check(GameData.level_color(3) == Color(0.68, 0.48, 0.92), "3 级 = 紫")
	_check(GameData.level_color(4) == Color(0.98, 0.80, 0.32), "4 级 = 金")
	_check(GameData.level_name(0) == "未装修" and GameData.level_name(4) == "金",
		"格详情卡的装修文案跟着等级走")
	_check(GameData.level_color(9) == GameData.level_color(4), "越界等级钳到 4 级（不越界崩）")
	_check(g.board._house_icons.size() == GameData.TILES.size(),
		"每格一个房子图标位（实得 %d）" % g.board._house_icons.size())
	g.board._set_house(0, 3)
	_check(g.board._house_icons[0].level == 3, "房子图标接得住等级（实得 %d）" % g.board._house_icons[0].level)
	_check(g.board._house_icons[0].size.x > 10.0,
		"房子图标有实际尺寸（实得 %.0f）" % g.board._house_icons[0].size.x)
	g.board._set_house(0, 0)
	_check(g.board._house_icons[0].level == 0, "等级归零后房子收起（无主/未装修不上房子）")

	print("== 收租飘字：红/绿两条不能叠在一起 ==")
	# 先把四位玩家的金额刷成基线（与 _state 一致），保证下一步的 diff 只来自这两家
	g.my_peer = 2
	g.s_state(_state(2, false))
	await process_frame
	# 模拟「甲 走到 乙 的地、付 500 租金」：同一帧里一个 -500、一个 +500，
	# 这正是当初两条飘字叠在一起的场景（都以各自棋子为中心，全景缩放下两棋子很近）
	var s2: Dictionary = _state(2, false)
	for p in s2.players:
		if int(p.peer) == 1:
			p.money = 11500
		elif int(p.peer) == 2:
			p.money = 20500
	g.s_state(s2)
	await process_frame
	var floats: Array = []
	for c in g.get_children():
		if c is Label and (c as Label).z_index == 90:
			floats.append(c)
	_check(floats.size() >= 2, "同一帧产生两条金额飘字（实得 %d）" % floats.size())
	if floats.size() >= 2:
		var fa := floats[floats.size() - 2] as Label
		var fb := floats[floats.size() - 1] as Label
		var dy: float = absf(fa.position.y - fb.position.y)
		_check(dy >= 30.0, "两条飘字纵向错开 ≥30px、不再叠住（实得 %.0f）" % dy)
	else:
		_check(false, "同一帧产生两条金额飘字（不足以比较位置）")

	print("== 抽卡：镜头拉近，牌面文字才看得清 ==")
	# 全景倍率下整张牌只有七八十像素宽，字是糊的 —— 抽卡时要临时拉近
	g.board.cam_locked = false
	var z0: float = g.board._zoom
	g.board.focus_point_zoom(Vector2(1008.0, 600.0), 0.78)
	_check(g.board._zoom > z0 + 0.05, "focus_point_zoom 能拉近镜头（%.2f → %.2f）" % [z0, g.board._zoom])

	g.get_tree().paused = false
	g.free()
	if fails == 0:
		print("HUD TEST: ALL PASS")
		quit(0)
	else:
		print("HUD TEST: %d FAILURES" % fails)
		quit(1)
