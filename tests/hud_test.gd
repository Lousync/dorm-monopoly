extends SceneTree
## HUD 回归：右栏名册 + 底部操作坞**已拆**的反向契约 + 桌上实体入口（含「客户端视角」这一段）
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

## 某个 peer 的立牌是第几块（-1 = 没这块牌）。行序由 game._refresh_standees 定，
## 这里不重写那套轮转，直接问立牌自己。
func _standee_idx_of(g, peer: int) -> int:
	var tp = g.table3d.table_props
	for i in tp._standee_rows.size():
		if tp.standee_peer(i) == peer:
			return i
	return -1

## 第 i 块立牌上的倒计时标签（座位卡退场后，倒计时簇的落点就是它）。
func _standee_timer(g, i: int) -> Label3D:
	var root: Node = g.table3d.table_props.get_node_or_null("Standees")
	if root == null or i < 0 or i >= root.get_child_count():
		return null
	return root.get_child(i).get_node_or_null("Timer") as Label3D

## 第 i 块立牌上的倒计时进度条（底轨 / 填充）
func _standee_bar(g, i: int, nm: String) -> MeshInstance3D:
	var root: Node = g.table3d.table_props.get_node_or_null("Standees")
	if root == null or i < 0 or i >= root.get_child_count():
		return null
	return root.get_child(i).get_node_or_null(nm) as MeshInstance3D

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

	print("== 底部操作坞已拆（批次 3 Task 6）：底栏没有，玩法入口还在 ==")
	g.my_peer = 2
	g.s_state(_state(2, false))
	g._refresh_actions()
	await process_frame
	await process_frame
	g._process(0.0)
	# 反向契约：坞的成员（含状态条）必须从 game 上**删净**，而不是留成一块不可见的空壳。
	# 一律用 g.get() 读 —— 成员真删掉时它返回 null；直接写 g.mat_bar 会因标识符不存在而报错。
	var gone: Array = []
	for n in ["mat_bar", "action_bar", "dock_plate", "roll_btn", "use_phase_btn", "item_btn_box",
			"status_label", "ph1_lab", "ph2_lab", "ph1_pill", "ph2_pill", "ph_arrow_l"]:
		if g.get(n) != null:
			gone.append(n)
	_check(gone.is_empty(), "底部操作坞的成员已删净（残留：%s）" % str(gone))
	# 另一半：坞拆了，**玩法入口**必须还在 —— 牌垫上的两个阶段按钮是掷轮与出牌确认的落点
	#（坞里的 roll_btn / use_phase_btn 早就 visible=false，真正管事的一直是这两枚）。
	_check(g.board._phase_spin != null and g.board._phase_spin.is_visible_in_tree(),
		"牌垫上的「转转盘」仍在（掷轮入口）")
	_check(g.board._phase_use != null and String(g.board._phase_use.text) != "",
		"牌垫上的「使用道具」仍在（出牌确认的唯一落点，实得「%s」）" % String(g.board._phase_use.text))
	# 陷阱：`_process` 原有一句 `if mat_bar == null: return` 的**提前返回**。只删构建、不删守卫的话，
	# `_process` 后半段（小卖部 / 黑市 / 操作倒计时 / 开发者面板）会**静默**不再执行。
	# 这里用「倒计时簇仍被推进」把后半段钉住（簇的推送在 `_process` 最末）。
	g.s_op_timer("roll", 30.0, 30.0, 3)
	g._process(0.0)
	await process_frame
	_check(_standee_timer(g, _standee_idx_of(g, 3)) != null
			and _standee_timer(g, _standee_idx_of(g, 3)).visible,
		"_process 的后半段仍在跑（倒计时没被提前返回吞掉）")
	g.s_op_timer("", 0.0, 0.0, -1)
	g._process(0.0)

	print("== 小卖部全屏层照旧（坞拆了与它无关）==")
	g.s_state(_state(2, true))            # shop_peer = 我
	g._process(0.0)
	await process_frame
	_check(g.shop_layer.visible, "小卖部全屏界面可见")

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
	# 第三个参数现在是「基准倍率（全景）的倍数」，不再是屏幕时代的绝对倍率：
	# 画布从 1280×800 换成 2048² 的 SubViewport 后，绝对字面量的含义差了约 3 倍
	#（全景从 0.40 变成 0.97）。2.0 对应原来那个 0.78（0.78/0.40 ≈ 1.96）。
	g.board.focus_point_zoom(Vector2(1008.0, 600.0), 2.0)
	_check(g.board._zoom > z0 * 1.5, "focus_point_zoom 能拉近镜头（%.2f → %.2f）" % [z0, g.board._zoom])

	print("== 抽卡推近：比全景明显更近，展示完还原（DECK_PUSH_FACTOR 链，triage #3）==")
	# 这条链在批次 2 里静默坏过一次：推近值写成了绝对 0.78（屏幕时代的字面量），
	# 在 2048² 画布下比全景的 0.97 还小 → 完全不推近，且当时没有任何测试能红。
	# 现在钉住「抽出阶段确实推近到 ≥ DECK_PUSH_FACTOR × 全景」+「演完能还原」。
	g.board.cam_locked = false
	g.board.fit_overview(true)
	await process_frame
	var fit_zoom: float = g.board._fit_zoom
	g.board.play_deck_card("机会", "good", "帮宿管阿姨搬了一下午矿泉水，辛苦费 +600")
	_check(g.board.is_showing_deck_card(), "抽卡演出已开始")
	_check(g.board._zoom >= g.board.DECK_PUSH_FACTOR * fit_zoom - 0.001,
		"抽卡把镜头推近到 ≥ %.1f × 全景（实得 %.2f / 门槛 %.2f）" % [
			g.board.DECK_PUSH_FACTOR, g.board._zoom, g.board.DECK_PUSH_FACTOR * fit_zoom])
	# 把相位计时一次推到底（走演出自己的收尾分支），缩放应还原到抽卡前的全景
	g.board._tick_deck_card(g.board.DECK_CARD_TIME + 0.1)
	_check(not g.board.is_showing_deck_card(), "演出结束卡片已收回")
	_check(absf(g.board._zoom - fit_zoom) < 0.001,
		"展示完还原到抽卡前的缩放（实得 %.3f / 期望 %.3f）" % [g.board._zoom, fit_zoom])

	print("== 悬停棋子：浮出昵称 / 身家 / 排名 ==")
	var hs: Dictionary = _state(2, false)
	hs.players.append({"peer": -1, "name": "机器人A", "color": 0, "bot": true,
		"money": 20000, "pos": 1, "alive": true, "skip": 0, "sleep": 0,
		"stamina": 3, "items": [], "item_used": false})
	g.s_state(hs)
	await process_frame
	g.board._set_token_hover(1)
	_check(g.board._token_tip != null and g.board._token_tip.visible, "悬停真人后信息条显示")
	_check(String(g.board._token_tip_name.text) == "甲",
		"显示昵称（实得「%s」）" % String(g.board._token_tip_name.text))
	_check(String(g.board._token_tip_sub.text).contains("身家")
		and String(g.board._token_tip_sub.text).contains("名"),
		"显示身家与排名（实得「%s」）" % String(g.board._token_tip_sub.text))
	# 关键：**机器人 peer 是负数**。之前判据写成 `peer < 0` 就把机器人全挡了，
	# 表现正是「悬停自己的小人有效、悬停别人的（机器人）没反应」。
	g.board._set_token_hover(-1)
	_check(g.board._token_tip.visible, "**悬停机器人也显示信息条（负 peer）**")
	_check(String(g.board._token_tip_name.text) == "机器人A",
		"显示机器人的昵称（实得「%s」）" % String(g.board._token_tip_name.text))
	g.board._set_token_hover(GameData.NO_PEER)
	_check(not g.board._token_tip.visible, "移开后信息条收起")

	print("== 格详情卡：悬浮在被点格子的上方 ==")
	g.board.cam_locked = false
	g.board.fit_overview(true)
	g._on_tile_clicked(27)
	await process_frame
	await process_frame
	_check(g.info_panel.visible, "点格子后详情卡显示")
	# 跨层断言（Task 3b）：期望位置必须走「棋盘画布坐标 → 屏幕坐标」的反变换 —— 这正是
	# game.gd 消费点做的事。旧写法两边都取自 board.tile_screen_pos，而棋盘搬进 SubViewport
	# 后那个值是 0..2048 的画布坐标，两边一起缩放：卡片被 clamp 钉死在屏幕边缘也照样成立。
	# 现在期望值走 TableView3D.viewport_to_screen（屏幕空间），卡片位置由屏幕层自己摆 ——
	# 少了反变换，两者会差出上百像素。
	var raw: Vector2 = g.board.tile_screen_pos(27)
	var anchored = g.table3d.viewport_to_screen(raw)
	_check(anchored != null, "27 号格的画布坐标 %s 可解算到屏幕坐标" % raw)
	var tc: Vector2 = anchored if anchored != null else Vector2(-9999.0, -9999.0)
	var pc: Vector2 = g.info_panel.position
	var pcz: float = pc.x + g.info_panel.size.x * 0.5
	_check(absf(pcz - tc.x) < 4.0, "卡片横向居中于该格（卡中心 %.0f / 格 %.0f）" % [pcz, tc.x])
	_check(pc.y + g.info_panel.size.y < tc.y, "卡片在格子上方（卡底 %.0f / 格 %.0f）"
		% [pc.y + g.info_panel.size.y, tc.y])
	# 错位的旧症状正是「卡片贴死屏幕边缘」：卡片必须完整落在屏幕内，且横向居中不是靠
	# clamp 凑出来的（被夹住时 pcz 会偏离锚点 x，上面那条居中检查随之失败）。
	_check(pc.x >= 8.0 and pc.y >= 8.0 and pc.x + g.info_panel.size.x <= g.size.x
		and pc.y + g.info_panel.size.y <= g.size.y, "卡片完整落在屏幕内（位置 %s）" % pc)

	print("== 归属色条：谁的地都要有，颜色与该玩家的棋子一致 ==")
	var ts: Dictionary = _state(2, false)
	# 关键：必须覆盖**机器人**（peer 为负数，从 -1 起编号）。
	# 之前用 `owner_id >= 0` 判「有主」，把机器人买的地全部漏掉了 —— 真人自己买的地
	# 有色条、机器人买的全没有，正是玩家看到的现象。这个用例就是为了钉住它。
	ts.players.append({"peer": -1, "name": "机器人A", "color": 0, "bot": true,
		"money": 20000, "pos": 1, "alive": true, "skip": 0, "sleep": 0,
		"stamina": 3, "items": [], "item_used": false})
	var mine_t := -1
	var bot_t := -1
	var free_t := -1
	for i in ts.tiles.size():
		if String(GameData.TILES[i].get("type", "")) != "property":
			continue
		ts.tiles[i].owner = GameData.NO_OWNER
		if mine_t < 0:
			mine_t = i
			ts.tiles[i].owner = 2          # 乙 = 我（真人，正 peer）
		elif bot_t < 0:
			bot_t = i
			ts.tiles[i].owner = -1         # 机器人（负 peer）
		elif free_t < 0:
			free_t = i
	g.s_state(ts)
	await process_frame
	_check(g.board._strips[mine_t].visible, "我买的地：色条显示")
	_check(g.board._strips[bot_t].visible, "**机器人买的地：我这边也要显示色条（负 peer）**")
	_check(not g.board._strips[free_t].visible, "无主的地：不显示色条")
	_check(g.board._strip_cols[mine_t] == GameData.PLAYER_COLORS[1], "我的色条 = 我的棋子色")
	_check(g.board._strip_cols[bot_t] == GameData.PLAYER_COLORS[0], "机器人的色条 = 它的棋子色")
	_check(g.board._strips[mine_t].position == Vector2(3, 3), "色条贴在格子左上角（不在文字上）")
	_check(g.board._strips[mine_t].size.y <= 14.0,
		"色条只有顶带那么高（实得 %.0f）" % g.board._strips[mine_t].size.y)
	# 关键：光 visible=true 不代表看得见 —— 没有样式就是一块透明板
	var strip_sb = g.board._strips[mine_t].get_theme_stylebox("panel")
	_check(strip_sb is StyleBoxTexture,
		"色条挂着真正的卡样式（实得 %s）" % ("null" if strip_sb == null else strip_sb.get_class()))

	print("== 操作倒计时（D 方案）：挂在当前行动者的立牌上 ==")
	# 座位卡退场后，倒计时簇的落点换成立牌；数据链路一字未改（仍由 _refresh_op_timer 逐帧推）。
	g.my_peer = 2
	g.s_state(_state(2, false))
	g._refresh_actions()
	await process_frame
	await process_frame
	g._process(0.0)
	g.s_op_timer("roll", 35.0, 35.0, 2)
	g._process(0.0)
	await process_frame
	var i2: int = _standee_idx_of(g, 2)     # 乙 = 行动者
	var i1: int = _standee_idx_of(g, 1)     # 甲 = 非行动者
	var tm2: Label3D = _standee_timer(g, i2)
	var tm1: Label3D = _standee_timer(g, i1)
	_check(i2 >= 0 and tm2 != null and tm2.visible, "行动者（乙）的立牌上倒计时显示")
	_check(tm1 != null and not tm1.visible, "非行动者的立牌不显示倒计时")
	_check(String(tm2.text) == "掷轮 35 秒",
		"显示环节名与剩余秒数（实得「%s」）" % String(tm2.text))
	var bar2: MeshInstance3D = _standee_bar(g, i2, "Fill")
	_check(bar2 != null and bar2.scale.x > 0.9, "进度条接近满格（实得 %.2f）" % bar2.scale.x)
	# 广播一秒一条，本机 _process 逐帧扣 delta 插值——喂剩 5 秒的道具窗口，
	# 等 1.5 秒（自然帧累积扣减），进度条应明显缩水、环节名跟着窗口走
	g.s_op_timer("item", 5.0, 12.0, 2)
	await create_timer(1.5).timeout
	g._process(0.0)
	var w0: float = bar2.scale.x
	_check(w0 < 0.45 and w0 > 0.15, "一秒多后进度条平滑缩水到中段（实得 %.2f）" % w0)
	_check(String(tm2.text).begins_with("道具"),
		"环节名跟着窗口走（实得「%s」）" % String(tm2.text))
	# 窗口换人：倒计时跟到丙的立牌
	g.s_op_timer("black", 15.0, 20.0, 3)
	g._process(0.0)
	await process_frame
	var i3: int = _standee_idx_of(g, 3)
	var tm3: Label3D = _standee_timer(g, i3)
	_check(tm3 != null and tm3.visible and not tm2.visible,
		"窗口换人时倒计时跟到丙的立牌")
	_check(String(tm3.text) == "黑市 15 秒",
		"环节名「黑市」（实得「%s」）" % String(tm3.text))
	# 不限时：仍显示环节名，但不写"0 秒"、进度条整条收起（语义原在座位卡上："不限时"）
	g.s_op_timer("roll", 0.0, 0.0, 3)
	g._process(0.0)
	_check(tm3.visible and not _standee_bar(g, i3, "Track").visible
			and not _standee_bar(g, i3, "Fill").visible,
		"不限时窗口仍显示环节名但进度条藏掉")
	_check(String(tm3.text) == "掷轮",
		"不限时文案不写秒数（实得「%s」）" % String(tm3.text))
	# 窗口关闭：kind="" 四块一起收
	g.s_op_timer("", 0.0, 0.0, -1)
	g._process(0.0)
	await process_frame
	_check(not tm3.visible and not tm2.visible, "窗口关闭后所有立牌的倒计时收起")

	print("== 点转盘 = 掷轮入口（批次 3 Task 2）==")
	# 为什么挑 roll_received 当证据：底栏那个「转动转盘」按钮已随 Task 6 拆除，`roll_btn.disabled`
	# 早就不存在；而 roll_received 是**掷轮这件事本身** —— game.gd 的 _play_turn 正 await 它，
	# 房主侧玩家点不点转盘，最终都落到这一条信号上。这里跑的是房主侧分支（`--script` 下
	# multiplayer 是默认接口、unique_id = 1 ⇒ is_server() 恒真，同 casino_test 的说明）；
	# 客户端那条走 c_roll，是另一条路，本机不联机验不了。
	g.my_peer = 2
	g.s_state(_state(2, false))          # await="roll"、turn=2=我 ⇒ 正是我的掷轮窗口
	await process_frame
	# 房主侧「轮到谁掷」的权威值（_play_turn 里设）。本测试不跑对局循环，直接给。
	g._awaiting_roll = 2
	var rolls := [0]
	var on_roll := func() -> void: rolls[0] += 1
	g.roll_received.connect(on_roll)
	var wc: Vector2 = g.board.wheel_screen_pos()
	var wr: float = g.board.wheel_screen_radius()
	_check(g._on_table_click(wc), "点转盘圆心：返回 true（这次点击被实体消费）")
	_check(rolls[0] == 1, "点转盘圆心：掷轮路径走通（roll_received 发出，实得 %d 次）" % rolls[0])
	_check(g._on_table_click(wc + Vector2(wr * 0.5, 0.0)), "轮缘上（半径一半处）也算命中")
	_check(rolls[0] == 2, "轮缘上同样掷轮（实得 %d 次）" % rolls[0])
	# 转盘**只吃左键**（修复波）：右键落在转盘上**不消费** —— 落回棋盘 = 既有的取消。
	# 这条没有用例就是静默回归（右键又能掷轮）而所有套件仍然全绿：别的用例都不碰
	# `MOUSE_BUTTON_RIGHT` 的转盘分支。此处断言两件事：不消费 + 掷轮计数不变。
	_check(not g._on_table_click(wc, MOUSE_BUTTON_RIGHT),
		"右键落在转盘上不消费（落回棋盘 = 取消）")
	_check(not g._on_table_click(wc + Vector2(wr * 0.5, 0.0), MOUSE_BUTTON_RIGHT),
		"右键落在轮缘上同样不消费")
	_check(rolls[0] == 2, "右键落在转盘上**不掷轮**（掷轮计数没变，实得 %d 次）" % rolls[0])
	# 负路径一：不在掷轮环节 —— 点击仍被转盘消费（返回 true，不会漏给桌垫），但**不掷轮**
	var s_item: Dictionary = _state(2, false)
	s_item.await = "item"
	g.s_state(s_item)
	g._awaiting_roll = 2
	await process_frame
	_check(g._on_table_click(wc), "非掷轮环节（await=item）：点击仍被转盘消费")
	_check(rolls[0] == 2, "非掷轮环节：不掷轮（实得 %d 次）" % rolls[0])
	# 负路径二：不是我的回合 —— 同理不掷轮
	g.s_state(_state(1, false))
	g._awaiting_roll = 2
	await process_frame
	_check(g._on_table_click(wc), "不是我的回合：点击仍被转盘消费")
	_check(rolls[0] == 2, "不是我的回合：不掷轮（实得 %d 次）" % rolls[0])
	g.roll_received.disconnect(on_roll)

	print("== 点手中牌：选中 / 取消（批次 3 Task 5）==")
	# 走**真实**的 `_on_table_click`（table_3d 命中实体那条链路），命中点取 `hand_rect` 的中心。
	# 证据一律挑底栏拆掉之后还活着的可观察量：`selected_slot`（玩法侧的选中态，单一来源）、
	# `hand_rect`（桌上手牌自己的命中盒）、`info_panel`（格详情卡）——底栏按钮与座位卡牌位都不碰。
	g.my_peer = 2
	var s_hand: Dictionary = _state(2, false)
	s_hand.await = "item"          # 轮到我、道具阶段
	s_hand.await_peer = 2
	for p in s_hand.players:
		if int(p.peer) == 2:
			# 三件刚好盖住既有三分支：不带目标（直接出牌）/ 选玩家 / 选格子
			p.items = [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.s_state(s_hand)
	await process_frame
	await process_frame
	g._process(0.0)
	var tph = g.table3d.table_props
	_check(tph.hand_count() == 3, "我的三件道具摆成三张手牌（实得 %d）" % tph.hand_count())
	_check(g.selected_slot == -1, "初始未选中")

	var c0: Vector2 = tph.hand_rect(0).get_center()
	var y_before: float = c0.y
	_check(g._on_table_click(c0), "点第一张牌：这次点击被手牌消费")
	_check(g.selected_slot == 0, "点第一张 → 选中下标 0（实得 %d）" % g.selected_slot)
	# 选中反馈在**3D**上（座位卡牌位已随 Task 6 拆掉，board.set_item_selected 现在空转）：
	# 牌抬起来 → 屏幕上看更高 → 射线打到桌面的点更远 → 画布 y 变小。
	_check(tph.hand_rect(0).get_center().y < y_before - 3.0,
		"选中的牌抬起来了（命中盒中心 %.0f → %.0f）" % [y_before, tph.hand_rect(0).get_center().y])
	_check(absf(tph.hand_rect(1).get_center().y - tph.hand_rect(2).get_center().y) < 60.0,
		"没选中的两张不受影响（仍在原位附近）")
	_check(g._on_table_click(c0), "再点同一张：仍被手牌消费")
	_check(g.selected_slot == -1, "再点同一张 → 取消选中（实得 %d）" % g.selected_slot)
	_check(absf(tph.hand_rect(0).get_center().y - y_before) < 3.0, "取消后牌落回原位")

	# 选中之后走**既有**出牌路径：牌垫上的「使用道具」（_on_use_pressed），本任务一行不改它
	g._on_table_click(tph.hand_rect(1).get_center())
	_check(g.selected_slot == 1, "点第二张（跑腿券）→ 选中下标 1（实得 %d）" % g.selected_slot)
	g._on_use_pressed()
	_check(g._tgt_stage == "peer", "需要选玩家的道具：转进既有的两段式选目标态（实得「%s」）" % g._tgt_stage)
	_check(g.selected_slot == -1, "出牌路径把选中态清掉（既有行为不变）")
	g._cancel_target()
	_check(g._tgt_stage == "", "取消目标后回到无事态")
	g._on_table_click(tph.hand_rect(2).get_center())
	_check(g.selected_slot == 2, "点第三张（快递直达）→ 选中下标 2（实得 %d）" % g.selected_slot)
	g._on_use_pressed()
	_check(g._tgt_stage == "tile", "选格子类道具：进既有的选地块态（实得「%s」）" % g._tgt_stage)
	g._cancel_target()

	# 取消（Esc / 右键走的是同一个 _cancel_target）也要把手牌选中态收回
	g._on_table_click(tph.hand_rect(0).get_center())
	_check(g.selected_slot == 0, "重新选中第一张（实得 %d）" % g.selected_slot)
	g._cancel_target()
	_check(g.selected_slot == -1, "取消把选中态一并清掉（实得 %d）" % g.selected_slot)
	_check(absf(tph.hand_rect(0).get_center().y - y_before) < 3.0, "取消后抬起反馈收回")

	print("== 手牌不吃格子的点击（近排格子不能有点不动的死区）==")
	# 近排（grid 最后一行，离镜头最近）= 手牌所在的那条带。判定顺序必须做到两件事：
	# ① 牌只在道具阶段吃点击（别的阶段吃下点击毫无后果）；② 被吃掉的点屏幕上真的画着那张牌。
	# 验收落点不是「格子完全不受影响」（牌就摆在格子上，物理上做不到），而是
	# **「牌底下那几格在非道具阶段全都能点 / 道具阶段归牌且看得见牌」**。
	var cell_of := func(i: int) -> Rect2:
		var p: Vector2 = g.board._view_from_world(g.board.tile_pos(i))
		var s: float = g.board.TILE * g.board._zoom
		return Rect2(p, Vector2(s, s))
	var near_row: Array = []
	for i in GameData.TILES.size():
		if g.board.tile_grid(i).y == GameData.BOARD_ROWS - 1:
			near_row.append(i)
	_check(near_row.size() == GameData.BOARD_COLS, "近排 %d 格都在（实得 %d）" % [GameData.BOARD_COLS, near_row.size()])

	# ① 手牌只在道具阶段吃点击：牌是常驻显示的（每次广播都摆一遍），但别的阶段点它没有意义，
	#    吃下点击就等于把本该落到格子上的一次点击吞成「什么都没发生」——那才是真正的死区。
	var s_roll: Dictionary = s_hand.duplicate(true)
	s_roll.await = "roll"          # 掷轮阶段（仍是我的回合），手牌照样摆在桌上
	g.s_state(s_roll)
	await process_frame
	var c0b: Vector2 = tph.hand_rect(0).get_center()
	_check(tph.hand_hit(c0b) == 0, "（对照）这个点确实落在第一张牌的命中盒里")
	_check(not g._on_table_click(c0b), "不是道具阶段：点手牌不消费点击（漏给桌垫）")
	_check(g.selected_slot == -1, "不是道具阶段：点了也不会选中")

	# ② 牌底下的那几格：三种情况各点一次 —— **这才是「近排格子还能不能点」的验收**。
	#    采样点一律取**真的落在牌盒里**的那种点（格子下沿 -3 画布像素）：格子上沿在牌盒
	#    之上（近排格子 y∈[1651,1740]、牌盒 y∈[1662,1769]），拿上沿验「不吞」是恒真式 ——
	#    那儿 hand_hit 本来就返回 -1，有没有阶段闸都过，什么都证明不了。
	#    格子矩形是**左上锚定**的（board_view.tile_pos = BOARD_OFFSET + grid*TILE，
	#    _index_at 做 floor(w/TILE)），所以 cell.position.y 就是格子上沿。
	var covered: Array = []          # [{tile: int, card: int, pt: Vector2}]
	var idx_bad := 0
	for i in near_row:
		var cell: Rect2 = cell_of.call(i)
		var low := Vector2(cell.get_center().x, cell.end.y - 3.0)
		if g.board._index_at(low) != i:
			idx_bad += 1
		for k in tph.hand_count():
			if tph.hand_rect(k).has_point(low):
				covered.append({"tile": i, "card": k, "pt": low})
				break
	_check(idx_bad == 0, "近排每格的下沿采样点都解算到它自己（解错 %d 格）" % idx_bad)
	_check(covered.size() > 0, "有格子被手牌命中盒盖住（实得 %d 格）——这条重叠是实测事实" % covered.size())

	# 2a 非道具阶段：这几个点必须**不被吞**（漏给桌垫）—— 这才是阶段闸的功劳，去掉闸这里就红
	var blocked := 0
	var still_covered := 0
	for c in covered:
		g._cancel_target()
		if tph.hand_hit(c.pt) >= 0:
			still_covered += 1
		if g._on_table_click(c.pt):
			blocked += 1
	_check(still_covered == covered.size(),
		"（对照）这 %d 个点确实落在牌盒里（实得 %d）——「不被吞」不是空谈" % [covered.size(), still_covered])
	_check(blocked == 0, "不是道具阶段：牌底那 %d 格的下沿**全都能点**（被吞 %d 格）——阶段闸在干活"
		% [covered.size(), blocked])
	g._cancel_target()

	# 2b 道具阶段：这几个点**被吞**，而且屏幕投影落在**那张牌**的屏幕包围盒里
	#（两条链路只差一次 screen_to_viewport / viewport_to_screen 往返，所以这条是
	#「牌的命中盒与牌角点的投影互相对得上」，不是完全独立的两次测量）
	var screen_box := func(k: int) -> Rect2:
		var mi := tph.get_node("Hand").get_child(k) as MeshInstance3D
		var bm: BoxMesh = mi.mesh as BoxMesh
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for sx in [-0.5, 0.5]:
			for sy in [-0.5, 0.5]:
				for sz in [-0.5, 0.5]:
					var sp: Vector2 = g.table3d.camera.unproject_position(mi.global_transform * Vector3(
						bm.size.x * float(sx), bm.size.y * float(sy), bm.size.z * float(sz)))
					mn = mn.min(sp)
					mx = mx.max(sp)
		return Rect2(mn, mx - mn)
	g.s_state(s_hand)
	await process_frame
	g._process(0.0)
	var eaten := 0
	var eaten_visible := 0
	for c in covered:
		# 每次点之前先清空选中态：这样「点之前的手牌摆位」每次都一样，屏幕包围盒才在点之前算得准
		#（点下去会把选中的牌抬起来，摆位就变了）。
		g._cancel_target()
		var low2: Vector2 = c.pt
		var boxes: Array = []
		for k in tph.hand_count():
			boxes.append(screen_box.call(k))
		if g._on_table_click(low2):
			eaten += 1
			var sp2 = g.table3d.viewport_to_screen(low2)
			if sp2 != null and (boxes[c.card] as Rect2).has_point(sp2 as Vector2):
				eaten_visible += 1
	g._cancel_target()
	_check(eaten == covered.size(), "道具阶段：牌底那 %d 格的下沿都被手牌接收（实得 %d）"
		% [covered.size(), eaten])
	_check(eaten_visible == eaten, "被接收的点屏幕上确实画着**它自己那张**牌（%d / %d）"
		% [eaten_visible, eaten])

	# 2c 实测取证（不为它下断言 —— 选中时的条带归零是批次 5 已知要改摆位解决的问题）：
	#    未选中时牌盒上沿在格子下沿之上，留下一条可点的缝；**被选中那张抬起来之后**这条缝归零。
	for c in covered:
		var cell3: Rect2 = cell_of.call(c.tile)
		g._cancel_target()
		var gap_plain: float = maxf(0.0, tph.hand_rect(c.card).position.y - cell3.position.y)
		g._on_table_click(c.pt)          # 选中那一张（抬起 ≈11 画布像素）
		var gap_sel: float = maxf(0.0, tph.hand_rect(c.card).position.y - cell3.position.y)
		print("    [实测] tile #%d ← 牌 %d：未选中时可点缝 %.1f 画布像素（格高 %.1f），选中后 %.1f"
			% [c.tile, c.card, gap_plain, cell3.size.y, gap_sel])
	g._cancel_target()

	# ③ 下沿：取一个没被手牌盖住的近排格子，点它的下沿必须**不被消费**，并打开该格详情。
	#    说明措辞：这里验的是**下游那一半**（board._index_at 把它解算成这格 → game._on_tile_clicked
	#    打开详情卡）；上游那一半（BoardView 在鼠标松开时 emit tile_clicked）是既有代码、
	#    本任务没碰，`_on_table_click` 返回 false 意味着这次点击会照原样送进桌垫走到它。
	var free_tile := -1
	for i in near_row:
		var cell: Rect2 = cell_of.call(i)
		var low_pt := Vector2(cell.get_center().x, cell.end.y - 3.0)
		var is_covered := false
		for k in tph.hand_count():
			if tph.hand_rect(k).has_point(low_pt):
				is_covered = true
		if not is_covered and g.board._index_at(low_pt) == i:
			free_tile = i
			break
	_check(free_tile >= 0, "找到一个没被手牌盖住的近排格子（实得 #%d）" % free_tile)
	if free_tile >= 0:
		var cell_f: Rect2 = cell_of.call(free_tile)
		var low_f := Vector2(cell_f.get_center().x, cell_f.end.y - 3.0)
		_check(not g._on_table_click(low_f), "点它（#%d）的下沿：手牌不消费这次点击" % free_tile)
		_check(g.board._index_at(low_f) == free_tile, "该点仍解算到这格（点击会照原样进桌垫）")
		g.info_panel.visible = false
		g._on_tile_clicked(free_tile)          # 桌垫那一端（tile_clicked）接的就是它
		await process_frame
		_check(g.info_panel.visible, "该格详情卡打开（_index_at → _on_tile_clicked 这一半打通）")

	print("== 手牌重排：选中态不漂（每次广播都重摆一遍手牌）==")
	g.s_state(s_hand)
	await process_frame
	var y1_plain: float = tph.hand_rect(1).get_center().y      # 选中前的第二张
	g._on_table_click(tph.hand_rect(1).get_center())
	_check(g.selected_slot == 1, "选中第二张（实得 %d）" % g.selected_slot)
	g.s_state(s_hand)                    # 再来一次广播：手牌被重摆
	await process_frame
	_check(g.selected_slot == 1, "广播重摆手牌后选中态不漂（实得 %d）" % g.selected_slot)
	_check(tph.hand_rect(1).get_center().y < y1_plain - 4.0,
		"重摆后抬起反馈还在（选中的第二张 %.0f，未选中时是 %.0f）"
			% [tph.hand_rect(1).get_center().y, y1_plain])
	g._cancel_target()
	g._on_table_click(tph.hand_rect(1).get_center())
	g._cancel_target()
	_check(g.selected_slot == -1, "收尾：选中态清空（实得 %d）" % g.selected_slot)

	print("== 丢弃入口已回补：手牌右键 = 丢弃（两步确认，走既有 _discard_item）==")
	# 座位卡「✕」随牌位拆除后 `_on_discard_clicked` 一度**没有发射方**（终审 R1）；
	# 现在右键落在手牌上即丢弃：第一下进入待确认（牌身染红）、第二下真丢。
	# 证据必须落在**玩法侧**：房主侧背包真的少一件，且走的是既有 `_discard_item`（没绕开玩法）。
	# 走**真实**的 `_on_table_click`（按键由 TableView3D 的输入映射带进来）。
	g.my_peer = 2
	g.hp = [
		{"peer": 2, "name": "我", "color": 1, "bot": false, "alive": true, "money": 20000,
			"pos": 0, "skip": 0, "stamina": 3, "item_used": false, "silence": 0, "shield": 0,
			"items": [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]},
	]
	var s_disc: Dictionary = _state(2, false)
	s_disc.await = "item"
	s_disc.await_peer = 2
	for p in s_disc.players:
		if int(p.peer) == 2:
			p.items = [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.s_state(s_disc)
	await process_frame
	await process_frame
	g._process(0.0)
	_check(int(g._player_by_peer(2).items.size()) == 3, "前置：房主侧背包 3 件（实得 %d）"
		% int(g._player_by_peer(2).items.size()))
	var c1: Vector2 = tph.hand_rect(1).get_center()
	_check(g._on_table_click(c1, MOUSE_BUTTON_RIGHT), "右键点第二张牌：这次点击被手牌消费（丢弃入口回来了）")
	_check(g._discard_pending == 1, "第一下右键：进入待确认（实得 %d）" % g._discard_pending)
	_check(int(g._player_by_peer(2).items.size()) == 3, "第一下右键：**还没**真丢（背包仍 3 件）")
	_check(tph._hand_disc == 1, "待确认那张牌身的红标已贴上（实得 _hand_disc=%d）" % tph._hand_disc)
	var dcol: Color = tph._hand_body_mats[1].albedo_color
	_check(dcol.r > dcol.g + 0.3 and dcol.r > dcol.b + 0.3, "牌身染红（实得 %s）" % str(dcol))
	_check(tph._hand_face_mats[1].albedo_color == Color.WHITE, "牌面贴图**没**被染（face 材质仍是原色）")
	_check(absf(tph.hand_rect(1).get_center().y - c1.y) < 3.0, "待确认**不**抬起（抬起是选中态的事）")
	# 广播后不丢：`_refresh_table_props` 会按 `_discard_pending` 重放红标（与 set_hand_selected 同款）
	g.s_state(s_disc)
	await process_frame
	g._process(0.0)
	_check(tph._hand_disc == 1 and g._discard_pending == 1, "广播重摆手牌后待确认态不漂（实得 %d / %d）"
		% [tph._hand_disc, g._discard_pending])
	# 第二下右键：真丢 —— 走既有 _discard_item（背包少一件、待确认清掉）
	_check(g._on_table_click(c1, MOUSE_BUTTON_RIGHT), "第二下右键：仍被手牌消费")
	_check(g._discard_pending == -1, "第二下右键：待确认清掉（实得 %d）" % g._discard_pending)
	var its_after: Array = g._player_by_peer(2).items
	_check(its_after.size() == 2, "第二下右键：房主侧背包真的少了一件（实得 %d）" % its_after.size())
	var ids_after: Array = []
	for it in its_after:
		ids_after.append(String(it.id))
	_check(not ids_after.has("跑腿券"), "丢掉的正是点中的那张（跑腿券）——走既有 _discard_item（剩 %s）" % str(ids_after))

	# 生效条件：非 playing 阶段 / 选目标中 → 右键手牌**不消费**（落回棋盘 = 既有取消）
	var s_not: Dictionary = s_disc.duplicate(true)
	s_not.phase = "ended"
	g.s_state(s_not)
	await process_frame
	g._process(0.0)
	var n_not: int = int(g._player_by_peer(2).items.size())
	_check(not g._on_table_click(tph.hand_rect(0).get_center(), MOUSE_BUTTON_RIGHT),
		"非 playing 阶段：右键手牌不消费（落回棋盘，那里右键仍是取消）")
	_check(g._discard_pending == -1 and int(g._player_by_peer(2).items.size()) == n_not,
		"非 playing 阶段：既不进待确认、也不丢")

	print("== 待确认丢弃不再永不解除（终审 Minor）==")
	# 背景：`_discard_pending` 原先 armed 之后**永不解除**，而 `_refresh_table_props` 每次广播
	# 会**无条件重放**它，于是 ① 道具阶段结束（跳过 / 超时 / 回合推进）红标整轮挂着，下一次右键
	# **一下**就把牌丢了（本该两步）；② armed 期间背包重排（交换生换牌 / 蛋蛋节发牌），下标指到
	# **另一张**牌 ⇒ 红标落到玩家从未 arm 过的那张上，一次右键就丢错东西。
	# 修法：重放前按两条判据核对这把待确认还作不作数 —— **arm 时的 (turn, await) 窗口**
	#（理由见 game.gd 的 `_discard_arm_turn`；`phase` 判据是恒假的，别退回去）+ **按 id 认牌**
	#（理由见 game.gd 的 `_discard_pending_id`）。这里三条各钉一次。
	g.my_peer = 2
	var s_re: Dictionary = _state(2, false)
	s_re.await = "item"
	s_re.await_peer = 2
	for p in s_re.players:
		if int(p.peer) == 2:
			p.items = [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.hp = [
		{"peer": 2, "name": "我", "color": 1, "bot": false, "alive": true, "money": 20000,
			"pos": 0, "skip": 0, "stamina": 3, "item_used": false, "silence": 0, "shield": 0,
			"items": [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]},
	]
	g.s_state(s_re)
	await process_frame
	g._process(0.0)

	# ① 背包重排：该下标的 **id 变了**（位置不变、内容变了 —— 交换生换牌就长这样）
	var cr: Vector2 = tph.hand_rect(1).get_center()
	_check(g._on_table_click(cr, MOUSE_BUTTON_RIGHT), "（前置）右键第二张：进待确认")
	_check(g._discard_pending == 1 and tph._hand_disc == 1,
		"（前置）待确认槽位 = 1、红标已贴（实得 %d / %d）" % [g._discard_pending, tph._hand_disc])
	var s_re2: Dictionary = s_re.duplicate(true)
	for p in s_re2.players:
		if int(p.peer) == 2:
			p.items = [{"id": "共享单车", "cd": 0}, {"id": "招财猫", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.hp[0].items = [{"id": "共享单车", "cd": 0}, {"id": "招财猫", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.s_state(s_re2)
	await process_frame
	g._process(0.0)
	_check(g._discard_pending == -1, "重排后该下标的 id 变了：待确认自动解除（实得 %d）" % g._discard_pending)
	_check(tph._hand_disc == -1, "红标随之收掉（实得 _hand_disc=%d）" % tph._hand_disc)
	# 关键：解除之后下一次右键只**进入待确认**，不会一下就把牌丢出去
	var n_re: int = int(g._player_by_peer(2).items.size())
	_check(g._on_table_click(tph.hand_rect(1).get_center(), MOUSE_BUTTON_RIGHT), "解除后再右键：仍被手牌消费")
	_check(g._discard_pending == 1, "解除后再右键：只进入待确认（实得 %d）" % g._discard_pending)
	_check(int(g._player_by_peer(2).items.size()) == n_re,
		"解除后再右键：**没有**真丢（背包仍 %d 件）——两步确认回来了" % n_re)
	g._cancel_target()

	# ② armed 之后**道具阶段结束**（「跳过」/ 超时 ⇒ `await` 变），而**背包一件没动**：
	#    待确认必须解除、红标不跨阶段挂着。守卫原先那条 `phase != "playing"` 是**恒假**的
	#   （`phase` 整局只有 "playing" / 整局结束才 "ended"，见 game.gd 的 `_discard_arm_turn`），
	#    所以这条路一直漏着：arm 一张牌 → 跳过 → 背包没变 → 红标整轮挂着 → 下一次右键**一下**
	#    就把牌丢了。现在按 **arm 时的 (turn, await) 窗口**核对（判据与理由见 `_discard_arm_turn`）。
	var s_re3: Dictionary = _state(2, false)
	s_re3.await = "item"
	s_re3.await_peer = 2
	for p in s_re3.players:
		if int(p.peer) == 2:
			p.items = [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.hp[0].items = [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.s_state(s_re3)
	await process_frame
	g._process(0.0)
	_check(g._on_table_click(tph.hand_rect(0).get_center(), MOUSE_BUTTON_RIGHT), "（前置）右键第一张：进待确认")
	_check(g._discard_pending == 0 and tph._hand_disc == 0,
		"（前置）待确认槽位 = 0、红标已贴（实得 %d / %d）" % [g._discard_pending, tph._hand_disc])
	var s_re4: Dictionary = s_re3.duplicate(true)
	s_re4.await = "roll"                       # 道具阶段结束（跳过 / 超时后环节变了；背包不动）
	g.s_state(s_re4)
	await process_frame
	g._process(0.0)
	_check(g._discard_pending == -1, "道具阶段结束（await 变）时待确认解除（实得 %d）" % g._discard_pending)
	_check(tph._hand_disc == -1, "道具阶段结束后红标收掉（实得 _hand_disc=%d）" % tph._hand_disc)
	# 关键：解除之后下一次右键只**进入待确认**，不会一下就把牌丢出去（背包故意一件没动）
	var n_aw: int = int(g._player_by_peer(2).items.size())
	_check(g._on_table_click(tph.hand_rect(0).get_center(), MOUSE_BUTTON_RIGHT), "解除后再右键：仍被手牌消费")
	_check(g._discard_pending == 0, "解除后再右键：只进入待确认（实得 %d）" % g._discard_pending)
	_check(int(g._player_by_peer(2).items.size()) == n_aw and n_aw == 3,
		"解除后再右键：**没有**真丢（背包仍 %d 件）——两步确认回来了" % n_aw)

	# ③ 另一半解除路径：**回合推进**（`turn` 变、`await` 不变）。窗口判据对两者一视同仁。
	var s_re5: Dictionary = s_re4.duplicate(true)
	s_re5.turn = 3
	g.s_state(s_re5)
	await process_frame
	g._process(0.0)
	_check(g._discard_pending == -1, "回合推进（turn 变）时待确认解除（实得 %d）" % g._discard_pending)
	_check(tph._hand_disc == -1, "回合推进后红标收掉（实得 _hand_disc=%d）" % tph._hand_disc)

	print("== 选目标期间：手牌让位给格子（终审 R2）==")
	# `_hand_clickable` 补上 `_tgt_stage == ""`：选目标时玩家**正要**点格子，而牌底那 3~5 格
	# 会被手牌抢答成「改选另一张牌」⇒ 指向性格子的道具打不到自家附近的格子。修完后手牌在
	# 选目标期间对点击**完全透明**：左键落回棋盘 = 选格、右键 = 既有取消。
	g.hp[0].items = [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.s_state(s_disc)
	await process_frame
	g._process(0.0)
	var cov_tile := -1
	var cov_card := -1
	var cov_pt := Vector2.ZERO
	for i in GameData.TILES.size():
		if g.board.tile_grid(i).y != GameData.BOARD_ROWS - 1:
			continue
		var cell: Rect2 = cell_of.call(i)
		var low := Vector2(cell.get_center().x, cell.end.y - 3.0)
		for k in tph.hand_count():
			if tph.hand_rect(k).has_point(low):
				cov_tile = i
				cov_card = k
				cov_pt = low
				break
		if cov_tile >= 0:
			break
	_check(cov_tile >= 0, "找到一个被手牌盖住下沿的近排格子（实得 #%d / 牌 %d）" % [cov_tile, cov_card])
	if cov_tile >= 0:
		_check(tph.hand_hit(cov_pt) >= 0, "（对照）这个点确实落在手牌命中盒里")
		# 进选地块态，把该格设为可选；此期间点它必须**不被手牌消费**
		g._begin_tile_target(0, [cov_tile])
		_check(g._tgt_stage == "tile" and g._tgt_tiles.has(cov_tile), "进了选地块态、该格可选")
		var eaten2: bool = g._on_table_click(cov_pt, MOUSE_BUTTON_LEFT)
		_check(not eaten2, "选目标期间：点被牌盖住的格子，手牌不消费（让位给格子）")
		_check(not g._on_table_click(tph.hand_rect(0).get_center(), MOUSE_BUTTON_RIGHT),
			"选目标期间：右键手牌也不消费（落回棋盘 = 既有取消）")
		_check(g.selected_slot == -1, "选目标期间点牌不改选中态（实得 %d）" % g.selected_slot)
		_check(g.board._index_at(cov_pt) == cov_tile, "该点仍解算到这格（会照原样进桌垫 → tile_clicked）")
		if not eaten2:                    # 没被手牌吃掉，才谈得上"点到了那格"
			g._on_tile_clicked(cov_tile)  # 桌垫那一端（tile_clicked）接的就是它
			_check(g._tgt_stage == "", "该格被选中 → 选目标态收尾（实得「%s」）" % g._tgt_stage)
		g._cancel_target()

	print("== 立牌（批次 5 Task 1）：数据来自已同步的 st、点对手立牌能选目标 ==")
	# 座位卡的 3D 版。数据全走 st.players / st.tiles（客户端也准），顺序按"自己打头、
	# 其余按行动序"轮转 —— 与 STANDEE_BASE_PX[0..3] 的四个桌位一一对应（座位卡已退场）。
	# 点击那条：`_on_table_click` 里立牌只多一个命中分支，后果一律走**既有的** `_on_seat_clicked`。
	g.my_peer = 2
	g.s_state(_state(2, false))
	await process_frame
	await process_frame
	g._process(0.0)
	var srh: Node = tph.get_node_or_null("Standees")
	_check(srh != null, "立牌的父节点在（game._refresh_table_props 驱动）")
	if srh == null:
		_check(false, "立牌父节点缺了，下面整段跳过")
	else:
		_check(tph._standee_rows.size() == 4, "四家都有立牌（实得 %d）" % tph._standee_rows.size())
		_check(tph.standee_peer(0) == 2 and tph.standee_peer(1) == 3 \
			and tph.standee_peer(2) == 4 and tph.standee_peer(3) == 1,
			"自己打头、其余按行动序（实得 %d/%d/%d/%d）" % [tph.standee_peer(0), tph.standee_peer(1),
				tph.standee_peer(2), tph.standee_peer(3)])
		_check(String((srh.get_child(0).get_node("Name") as Label3D).text) == "乙",
			"第一块（自己）是「乙」（实得「%s」）"
				% String((srh.get_child(0).get_node("Name") as Label3D).text))
		# 身家读 st.tiles 而不是 host 专有的 htiles（客户端也要显示）：甲现金 12000 + 他名下那块地。
		# 期望值在测试里按**数据表**自己算一遍 —— 写死"15,800"会随地产价格调整假红。
		var want_w := 12000
		var st_t: Array = g.st.tiles
		for i in mini(st_t.size(), GameData.TILES.size()):
			if int(st_t[i].get("owner", GameData.NO_OWNER)) == 1:
				want_w += int(GameData.TILES[i].price)
		var w1 := String((srh.get_child(3).get_node("Worth") as Label3D).text)
		_check(w1.contains(GameData.fmt_money(want_w)) and not w1.contains(GameData.fmt_money(12000)),
			"身家按「现金 + 地产」（已同步的口径）算（实得「%s」，期望含 %s、不等于现金 %s）"
				% [w1, GameData.fmt_money(want_w), GameData.fmt_money(12000)])
		_check(String((srh.get_child(2).get_node("Worth") as Label3D).text) == "已出局",
			"破产那家（丁）写「已出局」")
		_check(not (srh.get_child(0) as Node3D).visible,
			"3D 端自己的立牌藏起来（view_t = 0）")
		# 「看得见的那块牌面」= 板心经真实点击链路折回画布像素
		var seen_h := func(i: int) -> Vector2:
			var pl := (srh.get_child(i) as Node3D).get_node("Plate") as MeshInstance3D
			var got = g.table3d.screen_to_viewport(g.table3d.camera.unproject_position(pl.global_position))
			return got if got != null else Vector2(-9999.0, -9999.0)
		var foe_pt: Vector2 = seen_h.call(3)          # 第 4 块 = 甲（peer 1）
		_check(tph.standee_hit(foe_pt) == 3, "点甲那块立牌命中（实得 %d）" % tph.standee_hit(foe_pt))
		# 非选目标态：立牌**不消费**点击 —— 它立在桌沿、与近端那排格子 / 手牌相接，
		# 凭空多一块死区是不能接受的（判据与 _on_seat_clicked 同源：它那时本来就什么都不做）。
		g._cancel_target()
		_check(g._tgt_stage == "", "前置：当前不在选目标态")
		_check(not g._on_table_click(foe_pt), "非选目标态：点立牌**不消费**（点击照旧落回棋盘）")
		# 选目标态：点对手立牌 = 选定目标，走的仍是既有的 _on_seat_clicked
		# （强拆令是两段式：选完玩家要再点他名下的一块地）。
		# 手上那张要从**已同步的 st** 里读（`_target_item_id` 读的是 st.players）——只改 hp 不够。
		var s_tgt: Dictionary = _state(2, false)
		for p in s_tgt.players:
			if int(p.peer) == 2:
				p.items = [{"id": "强拆令", "cd": 0}]
		g.hp = [{"peer": 2, "name": "乙", "color": 1, "bot": false, "alive": true, "money": 20000,
			"pos": 0, "skip": 0, "stamina": 3, "item_used": false, "silence": 0, "shield": 0,
			"items": [{"id": "强拆令", "cd": 0}]}]
		g.s_state(s_tgt)
		await process_frame
		g._begin_peer_target(0, false, true)
		_check(g._tgt_stage == "peer", "进了既有的「选玩家」态（实得「%s」）" % g._tgt_stage)
		_check(g._on_table_click(foe_pt), "选目标态：点甲那块立牌被消费（选目标链路接上了）")
		_check(g._tgt_stage == "tile" and g._tgt_peer == 1,
			"选定甲 → 转进既有的第二段「选他名下的一块地」（实得「%s」/ target=%d）"
				% [g._tgt_stage, g._tgt_peer])
		g._cancel_target()
		# 右键不消费：棋盘上右键是既有的取消，立牌不破例
		g._begin_peer_target(0, false, true)
		_check(not g._on_table_click(foe_pt, MOUSE_BUTTON_RIGHT),
			"选目标态下右键点立牌不消费（右键在棋盘上是既有的取消）")
		g._cancel_target()

	g.get_tree().paused = false
	g.free()
	if fails == 0:
		print("HUD TEST: ALL PASS")
		quit(0)
	else:
		print("HUD TEST: %d FAILURES" % fails)
		quit(1)
