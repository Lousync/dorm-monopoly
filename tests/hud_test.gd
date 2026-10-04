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

## 房子薄牌的节点（按 **meta("tile")** 找，不按节点名 —— 同棋子的 `meta("peer")` 约定）。
func _house_node(houses_root: Node, idx: int) -> Node3D:
	if houses_root == null:
		return null
	for ch in houses_root.get_children():
		if (ch as Node).has_meta("tile") and int((ch as Node).get_meta("tile")) == idx:
			return ch as Node3D
	return null

## 房子薄牌的**正面**（贴等级纹理的那张方片）。
func _house_face(houses_root: Node, idx: int) -> MeshInstance3D:
	var h := _house_node(houses_root, idx)
	return h.get_node_or_null("Face") as MeshInstance3D if h != null else null

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

## 房主侧名册（4 家，字段与 `game._build_hp` 对齐）。两个用途：
##  ① 房主 `_host_setup` 在开局 1.5 秒后会自己 `_broadcast_state()` 一次（见 game.gd:382），
##     而 `_broadcast_state` 要读 `hp[turn_i].peer` —— 名册为空时它抛
##     `SCRIPT ERROR: Out of bounds`（本批之前就挂着的噪声）。给一份**与 `_state()` 同形**的
##     名册（peer 顺序与 `_state()` 一致），那次自动广播就与测试自己喂的状态一致。
##  ② 「点手中牌」段要走真房主路径 `_use_item`，它读的就是这份名册（不是 st）。
func _host_roster() -> Array:
	var out := []
	var seeds := [[1, "甲", 0, 12000, 0, true], [2, "乙", 1, 20000, 3, true],
		[3, "丙", 2, 8000, 6, true], [4, "丁", 3, 100, 9, false]]
	for s in seeds:
		out.append({
			"peer": int(s[0]), "name": String(s[1]), "color": int(s[2]), "bot": false,
			"money": int(s[3]), "pos": int(s[4]), "alive": bool(s[5]), "skip": 0, "sleep": 0,
			"stamina": 3, "items": [], "item_used": false, "item_used_n": 0,
			"cheat_roll": -1, "hot_chain": 0, "cost_pen": [], "first_used": false,
			"roll_bonus": 0, "reroll_next": false, "silence": 0, "silence2": 0, "shield": 0,
			"charm_used": false, "emg_used": false, "loan_left": 0, "rework": 3,
		})
	return out

## 按 peer 找四角条（角位是"自己打头"轮转出来的，**不能按下标找**）。找不到返回空字典。
func _bar_of(g, peer: int) -> Dictionary:
	for b in g.corner_bars:
		if int((b as Dictionary).get("peer", GameData.NO_PEER)) == peer:
			return b
	return {}

## 第 bar 条四角身家条此刻"亮着"（可被选中）吗：读它**真的贴上去的那张样式盒**，判据是
## "这张描边图是不是 UIKit 按『可选中』那套参数（2px 金边 + 底色提亮一档）生成的那张"。
## `UIKit._rounded_tex` 按**参数**缓存 ⇒ 同参必得**同一个 Texture2D 实例**，所以身份比较成立。
## **不读任何内部标志**（那会在"高亮坏了但标志还对"时骗过断言），也不按文字 / 位置反推 ——
## 行动者那条（1px 金边）与它参数不同、纹理不同，不会被误判成亮着。
func _corner_bar_hot(_g, bar: Dictionary) -> bool:
	var root: Control = bar.get("root")
	if root == null or not is_instance_valid(root):
		return false
	var sb := root.get_theme_stylebox("panel")
	if not (sb is StyleBoxTexture):
		return false
	var UK = load("res://scripts/ui_kit.gd")
	var bg := Color(0.085, 0.095, 0.138, 0.82).lightened(0.10)
	var border := Color(UK.ACCENT.r, UK.ACCENT.g, UK.ACCENT.b, 0.9)
	var hot_sb: StyleBoxTexture = UK.card_stylebox(bg, 10, border, 2, 4)
	return (sb as StyleBoxTexture).texture == hot_sb.texture

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
	# 名册为空时，房主 `_host_setup` 开局 1.5 秒后那次自动 `_broadcast_state()` 会读 `hp[turn_i]`
	# 越界（`SCRIPT ERROR: Out of bounds`，本批之前就有）。先种一份最小名册让那次广播成立。
	# `lab_mode` 只是让它的 `phase` 落在 "playing"（不跑回合循环的沙盒 = 道具试验场同一档），
	# 免得那一下被 `s_state` 当成对局结束、给 g 挂上结算层；`turn_i = 0`（peer 2 那份在 index 1，
	# 但后面几段会把 hp 换成 1 家的名册 —— 恒取 0 号位对两种规模都成立）。
	g.hp = _host_roster()
	g.turn_i = 0
	g.lab_mode = true
	for i in 4:
		await process_frame
	await create_timer(0.4).timeout

	print("== 四角身家条（客户端视角：我是乙，行动的也是我）==")
	# 角位 = 桌位（`game._seat_peers`：自己打头、其余按行动序 → 底/左/上/右），
	# 取代了右侧名册栏（名册栏与它挂的是同一份东西）。
	# UIKit 一律**运行时 load**：静态写 `UIKit.X` 会把 ui_kit.gd 拽进本脚本的静态依赖链，
	# 而它引用了 autoload `Fx` —— 在 `--script` 入口下此时 autoload 还没注册，
	# 整链会以「Identifier not found: Fx」编译失败（同 layout_test 顶部那段说明）。
	var UK = load("res://scripts/ui_kit.gd")
	g.my_peer = 2
	g.s_state(_state(2, false))          # 走客户端真正跑的那个处理函数
	await process_frame
	var bars: Array = g.corner_bars
	_check(bars.size() == 4, "四角条建了 4 条（实得 %d）" % bars.size())
	var vis_bars: Array = bars.filter(func(b) -> bool: return (b.root as Control).visible)
	_check(vis_bars.size() == 4, "4 名玩家各占一条（实得 %d）" % vis_bars.size())
	# 反向契约：右侧名册栏必须从 game 上**删净**（同时留着就是重复：都挂"名次+名字+身家"）
	_check(g.get("roster_box") == null and g.get("roster_rows") == null,
		"右侧名册栏已从 game 上删净（roster_box / roster_rows）")
	# 角位 = 桌位：我是乙 ⇒ 左下是乙、左上丙、右上丁、右下甲（自己打头、其余按行动序）
	_check(int(bars[0].peer) == 2 and int(bars[1].peer) == 3 \
		and int(bars[2].peer) == 4 and int(bars[3].peer) == 1,
		"角位 = 桌位（左下/左上/右上/右下 = 乙/丙/丁/甲，实得 %d/%d/%d/%d）" % [
			int(bars[0].peer), int(bars[1].peer), int(bars[2].peer), int(bars[3].peer)])
	# 名次徽章上的数字就是身家名次。身家 = 现金 + 地产；甲 12000 + 一号楼地价(3800) = 15800，
	# 于是 乙(20000) > 甲(15800) > 丙(8000) > 丁(100)。
	var rank_of := func(b: Dictionary) -> int:
		var badge = b.get("badge")
		if badge == null or not is_instance_valid(badge):
			return -1
		for c in (badge as Control).get_children():
			if c is Label:
				return int(String((c as Label).text))
		return -1
	_check(rank_of.call(bars[0]) == 1, "乙（我）身家最高 = 名次 1（实得 %d）" % rank_of.call(bars[0]))
	_check(rank_of.call(bars[3]) == 2, "甲现金少但有地产，靠身家排到第 2（实得 %d）" % rank_of.call(bars[3]))
	_check(rank_of.call(bars[1]) == 3, "丙只有现金，排到第 3（实得 %d）" % rank_of.call(bars[1]))
	_check(rank_of.call(bars[2]) == 4, "丁最穷 = 名次 4（实得 %d）" % rank_of.call(bars[2]))
	# 身家读数：期望值按**数据表**在测试里自己算一遍（与 game 的 `_state_worth` / 房主的
	# `_net_worth` 同一公式：现金 + 名下地皮的地价）。写死"20,000"会随地产价格调整假红。
	var worth_of := func(peer: int, cash: int) -> int:
		var v := cash
		var st_w: Array = g.st.tiles
		for i in mini(st_w.size(), GameData.TILES.size()):
			if int(st_w[i].get("owner", GameData.NO_OWNER)) == peer:
				v += int(GameData.TILES[i].price)
		return v
	_check(String(bars[0].worth_l.text) == GameData.fmt_money(worth_of.call(2, 20000)),
		"乙那条的身家 = 现金 + 地产（实得「%s」）" % String(bars[0].worth_l.text))
	_check(String(bars[3].worth_l.text) == GameData.fmt_money(worth_of.call(1, 12000)),
		"甲那条的身家 = 12000 + 他名下那块地（实得「%s」）" % String(bars[3].worth_l.text))
	_check(String(bars[0].name_l.text).contains("乙") and String(bars[0].name_l.text).contains("（我）"),
		"自己那条标「（我）」（实得「%s」）" % String(bars[0].name_l.text))
	_check(String(bars[2].name_l.text).contains("破产"), "破产那家标「破产」（实得「%s」）"
		% String(bars[2].name_l.text))
	_check(String(bars[2].worth_l.text) == "已出局", "破产那家身家列显示「已出局」")
	# 轮到谁行动：那一条的名字变金（角位的"该你了"提示，与四角条的倒计时行同一件事）
	_check((bars[0].name_l as Label).get_theme_color("font_color") == UK.ACCENT,
		"行动者（我）那条名字变金")
	_check((bars[1].name_l as Label).get_theme_color("font_color") != UK.ACCENT,
		"非行动者那条名字不变金")
	# 现金那一行（修复波 B）：身家 = 现金 + 地产，只报身家时买卖 / 付租看不到自己有多少现金。
	# 期望值同样按**数据表**算（写死金额会随起始资金调整假红）。
	var cash_of := func(peer: int) -> int:
		return int(g._state_player(peer).get("money", 0))
	_check(String(bars[0].money_l.text) == "现金 " + GameData.fmt_money(cash_of.call(2)),
		"自己那条写了现金（实得「%s」，期望 %s）" % [String(bars[0].money_l.text),
			GameData.fmt_money(cash_of.call(2))])
	_check(String(bars[3].money_l.text) == "现金 " + GameData.fmt_money(cash_of.call(1)),
		"甲那条写了现金（实得「%s」）" % String(bars[3].money_l.text))
	_check(String(bars[2].money_l.text) == "",
		"破产那家的现金行留空（不报数字；控件不隐藏 —— 藏了四条就不一样高了）")
	# 写死的条尺寸必须装得下内容：内容更大会把面板撑大，底边那两条就朝下长进「规则说明」按钮。
	# 常驻占位（倒计时行）保证四条**永远**一样高 —— 行动者换人时那一角不会一开一合。
	var TH = load("res://scripts/table_hud.gd")
	var content_max := 0.0
	for b in vis_bars:
		var root_c: Control = b.root
		# 量内容真实需要的高度：**把写死的那份先清零**再问 —— `get_combined_minimum_size()`
		# 会把 `custom_minimum_size` 也并进去，不清零就永远等于那个写死的数、看不出内容撑不撑破。
		var keep: Vector2 = root_c.custom_minimum_size
		root_c.custom_minimum_size = Vector2.ZERO
		var need: Vector2 = root_c.get_combined_minimum_size()
		root_c.custom_minimum_size = keep
		content_max = maxf(content_max, need.y)
		_check(is_equal_approx(root_c.size.y, TH.CORNER_BAR_SIZE.y) \
				and is_equal_approx(root_c.size.x, TH.CORNER_BAR_SIZE.x),
			"四角条尺寸 = CORNER_BAR_SIZE（实得 %s）" % str(root_c.size))
	print("    [实测] 四角条内容最小高 %.1f / CORNER_BAR_SIZE %s" % [content_max, str(TH.CORNER_BAR_SIZE)])
	_check(content_max <= TH.CORNER_BAR_SIZE.y + 0.01,
		"写死的高度装得下内容（内容最小高 %.1f ≤ %.1f）" % [content_max, TH.CORNER_BAR_SIZE.y])
	# 四角条不许挡住三个角按钮（左上暂停 / 右上战报 / 左下规则说明），也不许出屏。
	# 位置是"对着出图定"的（见 table_hud.CORNER_SLOTS），这条把结论钉住。
	var quad_hit := {}
	var overlap_bad := 0
	var off_screen := 0
	for b in vis_bars:
		var r: Rect2 = (b.root as Control).get_global_rect()
		var cx: int = 1 if r.get_center().x > g.size.x * 0.5 else 0
		var cy: int = 1 if r.get_center().y > g.size.y * 0.5 else 0
		quad_hit["%d%d" % [cx, cy]] = true
		if r.position.x < 0.0 or r.position.y < 0.0 \
				or r.end.x > g.size.x or r.end.y > g.size.y:
			off_screen += 1
		for btn in [g.opt_btn, g.log_toggle, g.rules_btn]:
			if btn != null and is_instance_valid(btn) and r.intersects((btn as Control).get_global_rect()):
				overlap_bad += 1
		print("    [实测] 角标 peer %d：%s（面板 %s）" % [int(b.peer), r, (b.root as Control).size])
	print("    [实测] 角按钮：暂停 %s / 战报 %s / 规则 %s" % [
		(g.opt_btn as Control).get_global_rect(), (g.log_toggle as Control).get_global_rect(),
		(g.rules_btn as Control).get_global_rect()])
	_check(quad_hit.size() == 4, "四条各占一个角（实得 %d 个角）" % quad_hit.size())
	_check(off_screen == 0, "四条都完整落在屏幕内（出屏 %d 条）" % off_screen)
	_check(overlap_bad == 0, "四条都没挡住角按钮（暂停/战报/规则说明，重叠 %d 处）" % overlap_bad)
	# 两两不相交：上面"四条各占一个角"是从**中心象限**推的 —— 两条真叠在一起、而中心恰落在
	# 不同象限时照样通过。四角条自批次 9 起是"点它选人 / 开弹窗"的入口，叠在一起就有一条永远点不到
	#（立牌时代那条"整条视角轨道上都看得见 / 贴桌沿"的守卫随立牌退场，本条是它在屏幕层的对应物）。
	var quad_rects: Array = []
	for b in vis_bars:
		quad_rects.append((b.root as Control).get_global_rect())
	var quad_cross := 0
	for i in quad_rects.size():
		for j in range(i + 1, quad_rects.size()):
			if (quad_rects[i] as Rect2).intersects(quad_rects[j] as Rect2):
				quad_cross += 1
	_check(quad_cross == 0, "四条两两不相交（相交 %d 对）" % quad_cross)
	g.table3d.snap_view(0.0)
	await process_frame

	print("== 客户端视角：行动者不是我 ==")
	g.my_peer = 9                         # 观战/掉线后重连之类：自己不在名册里
	g.s_state(_state(1, false))
	await process_frame
	var vis2: Array = g.corner_bars.filter(func(b) -> bool: return (b.root as Control).visible)
	_check(vis2.size() == 4, "自己不在名册里也不崩、仍是 4 条")
	var marked: Array = vis2.filter(func(b) -> bool: return String(b.name_l.text).contains("（我）"))
	_check(marked.is_empty(), "自己不在名册时没人被误标「（我）」")
	# 自己不在名册 ⇒ 从第 0 家起轮转：甲排到左下、乙到左上
	_check(int(g.corner_bars[0].peer) == 1 and int(g.corner_bars[1].peer) == 2,
		"自己不在名册时从第 0 家起轮转（实得 %d/%d）"
			% [int(g.corner_bars[0].peer), int(g.corner_bars[1].peer)])
	_check((g.corner_bars[0].name_l as Label).get_theme_color("font_color") == UK.ACCENT,
		"轮到甲（左下那条）时他的名字变金")

	print("== 四角条缓存：状态没变不重建 ==")
	var sig_before: String = g._corner_sig
	g.s_state(_state(1, false))
	await process_frame
	_check(g._corner_sig == sig_before, "同一状态重复广播不复算（签名不变）")

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
	# 另一半：坞拆了，**玩法入口**必须还在 —— 批次 7 起掷轮的落点是右下角动作按钮
	#（坞里的 roll_btn / use_phase_btn 早就 visible=false，牌垫上那两枚也已在批次 7 退场）。
	_check(g.action_btn != null and g.action_btn.visible \
			and String(g.action_btn.text) == "转动转盘",
		"右下角动作按钮仍在（掷轮入口，实得「%s」）"
			% ("无" if g.action_btn == null else String(g.action_btn.text)))
	# 陷阱：`_process` 原有一句 `if mat_bar == null: return` 的**提前返回**。只删构建、不删守卫的话，
	# `_process` 后半段（小卖部 / 黑市 / 操作倒计时 / 开发者面板）会**静默**不再执行。
	# 这里用「倒计时仍被推进到四角条」把后半段钉住（簇的推送在 `_process` 最末）。
	g.s_op_timer("roll", 30.0, 30.0, 3)
	g._process(0.0)
	await process_frame
	var cb3g: Dictionary = {}
	for b in g.corner_bars:
		if int(b.peer) == 3:
			cb3g = b
	_check(not cb3g.is_empty() and (cb3g.timer_kind as Label).visible,
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

	print("== 装修房子：4 级 + 等级配色 + 3D 薄牌（批次 11 Task 2） ==")
	_check(GameData.MAX_LEVEL == 4, "装修上限 4 级（实得 %d）" % GameData.MAX_LEVEL)
	_check(GameData.level_color(1) == Color(0.42, 0.80, 0.45), "1 级 = 绿")
	_check(GameData.level_color(2) == Color(0.36, 0.63, 0.94), "2 级 = 蓝")
	_check(GameData.level_color(3) == Color(0.68, 0.48, 0.92), "3 级 = 紫")
	_check(GameData.level_color(4) == Color(0.98, 0.80, 0.32), "4 级 = 金")
	_check(GameData.level_name(0) == "未装修" and GameData.level_name(4) == "金",
		"格详情卡的装修文案跟着等级走")
	_check(GameData.level_color(9) == GameData.level_color(4), "越界等级钳到 4 级（不越界崩）")
	# 2D 的 `HouseIcon` 整套已删（批次 11 Task 2 搬进 3D 的 `TableProps`）——这里改读**桌面上那块
	# 薄牌**：走真入口（`s_state` → 广播 → `_refresh_houses`），判据是"贴上去的材质/纹理"。
	var tpH = g.table3d.table_props
	if tpH == null or not tpH.has_method("set_houses"):
		_check(false, "TableProps 没有 set_houses（房子还没搬进来），本段整段跳过")
	else:
		var tiles_h: Array = _fresh_tiles()
		tiles_h[3].level = 3
		var st_h: Dictionary = _state(2, false)
		st_h.tiles = tiles_h
		g.s_state(st_h)
		await process_frame
		var hroot_h: Node = tpH.get_node_or_null("Houses")
		_check(hroot_h != null and hroot_h.get_child_count() == GameData.TILES.size(),
			"每格一块房子薄牌（实得 %d）"
				% (0 if hroot_h == null else hroot_h.get_child_count()))
		var h3: Node3D = _house_node(hroot_h, 3)
		var f3: MeshInstance3D = _house_face(hroot_h, 3)
		_check(h3 != null and h3.visible, "有等级的那格立起了房子薄牌")
		var m3: StandardMaterial3D = f3.material_override as StandardMaterial3D if f3 != null else null
		_check(m3 != null and m3.albedo_texture != null,
			"房子正面贴的是**烘出来的等级纹理**（读贴上去的材质，不是内部标志）")
		_check(m3 != null and m3.albedo_texture == tpH.house_tex(3),
			"贴的正是 3 级那一张（与 house_tex(3) 同源）")
		_check(m3 != null and m3.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
			"房子正面是 ALPHA_SCISSOR（透明边裁掉、仍在不透明队列里写深度/投影，实得 %s）"
				% str(m3.transparency if m3 != null else -1))
		# 等级归零 ⇒ 收起（无主 / 未装修不上房子）
		tiles_h[3].level = 0
		st_h.tiles = tiles_h
		g.s_state(st_h)
		await process_frame
		_check(h3 != null and not h3.visible, "等级归零后房子收起（无主/未装修不上房子）")

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

	print("== 抽卡演出：在屏幕层大字演、**相机全程不动**（批次 8）==")
	# 批次 8 的判据就一句：演出前后 2D 相机的缩放与注视点**完全相同**。
	# 旧版会把 `_zoom` 推到 ≥2× 全景（DECK_PUSH_FACTOR）—— 那一推让印在桌垫上的图案整体放大滑动，
	# 而手牌是不跟 2D 相机的实物 ⇒ 明显错位（用户 ① 报的就是它）。
	g.board.cam_locked = false
	g.board.fit_overview(true)
	await process_frame
	var z_before: float = g.board._zoom
	var c_before: Vector2 = g.board._center
	_check(g.deck_reveal != null, "屏幕层抽卡演出组件已建（TableHud.build_play_ui）")
	g.deck_reveal.show_card("机会", "good", "帮宿管阿姨搬了一下午矿泉水，辛苦费 +600")
	await process_frame
	_check(g.deck_reveal.is_showing(), "抽卡演出已开始")
	g.deck_reveal.tick(g.deck_reveal.HOLD * 0.5)   # 推进到停留段中途
	await process_frame
	_check(absf(g.board._zoom - z_before) < 0.001,
		"演出期间 2D 相机缩放一动不动（实得 %.3f / 演出前 %.3f）" % [g.board._zoom, z_before])
	_check(g.board._center.distance_to(c_before) < 0.001,
		"演出期间 2D 相机注视点一动不动（实得 %s / 演出前 %s）" % [g.board._center, c_before])
	# 把相位计时一次推到底（走演出自己的收尾分支）
	g.deck_reveal.tick(g.deck_reveal.CARD_TIME + 0.1)
	_check(not g.deck_reveal.is_showing(), "演出结束卡片已收回")
	# 设计 §6 的后半：不能只把 is_showing 置假 —— 节点要真回收、层要真隐藏。
	_check(g.deck_reveal._card == null and not g.deck_reveal.visible,
		"演出结束卡片已回收（不是只把 is_showing 置假：_card 已清、层已隐藏）")
	# 反向契约：旧那套"演在画布上"的接口必须**真的没了**（不留空壳）
	_check(not g.board.has_method("play_deck_card"), "BoardView.play_deck_card 已退场")
	_check(not g.board.has_method("is_showing_deck_card"), "BoardView.is_showing_deck_card 已退场")
	_check(not g.board.has_method("focus_point_zoom"), "focus_point_zoom 已退场（唯一调用方是抽卡推近）")
	var B1 = load("res://scripts/board_view.gd")
	_check(not B1.get_script_constant_map().has("DECK_PUSH_FACTOR"), "DECK_PUSH_FACTOR 常量已删")
	# z 层级（批次 8 审查 R5）：卡绝不能盖在模态面板上 —— 房主暂停会把树 `paused`，
	# `DeckReveal._process` 随之停 ⇒ 卡收不掉、冻在暂停面板上。判据走**显式 z**，不看树序：
	# `z_as_relative` 默认为真，卡挂在 hud(0) 下、菜单挂在 game(0) 下，靠树序谁在上会漂。
	_check(g.deck_reveal.z_index < g.menu_layer.z_index,
		"抽卡大字卡在暂停菜单之下（z %d < %d）" % [g.deck_reveal.z_index, g.menu_layer.z_index])
	# 同类残留（批次 8 审查 R7）：非房主看到的「⏸ 房主已暂停 · 等待继续…」全屏遮罩也在模态带，
	# 客户机被房主暂停时卡会冻住 ⇒ 遮罩必须同样压在卡之上，否则那句提示被冻住的卡盖住。
	_check(g.deck_reveal.z_index < g.pause_mask.z_index,
		"抽卡大字卡在「房主已暂停」遮罩之下（z %d < %d）" % [g.deck_reveal.z_index, g.pause_mask.z_index])
	# 把"卡在**所有**模态层之下"钉住（不止菜单与暂停遮罩）：小卖部·赌场层(70) 也必须压住卡。
	_check(g.deck_reveal.z_index < g.shop_layer.z_index,
		"抽卡大字卡在小卖部·赌场层之下（z %d < %d）" % [g.deck_reveal.z_index, g.shop_layer.z_index])

	print("== 悬停信息条：本批搬到屏幕层（过渡态：Task 3 之前没有悬停反馈）==")
	# **R2 裁定**：2D 悬停条整套（`_token_tip` / `_token_at_view` / `_set_token_hover` /
	# `_ensure_token_tip` / `_place_token_tip`）随 Task 1 一起删 —— 它们的数据源就是 `_tokens`，
	# 那套一删整段必然解析失败。屏幕层的条由 **Task 3** 重建（那时它会带回"悬停出条"的断言）。
	# 这里只钉**数据源**仍然在、且内容同源（Task 3 要读它）：`board._peers_info`。
	# 关键仍是「机器人 peer 是负数」—— 判据写成 `peer < 0` 就会把机器人全挡掉。
	var hs: Dictionary = _state(2, false)
	hs.players.append({"peer": -1, "name": "机器人A", "color": 0, "bot": true,
		"money": 20000, "pos": 1, "alive": true, "skip": 0, "sleep": 0,
		"stamina": 3, "items": [], "item_used": false})
	g.s_state(hs)
	await process_frame
	var pinfo: Dictionary = g.board._peers_info
	_check(pinfo.has(1) and String(pinfo[1].get("name", "")) == "甲",
		"悬停信息的数据源 `board._peers_info` 仍在（Task 3 要读）")
	_check(pinfo.has(-1) and String(pinfo[-1].get("name", "")) == "机器人A",
		"**负数 peer 的机器人也在 `_peers_info` 里**（判据别写成 peer < 0）")
	_check(int(pinfo[1].get("rank", 0)) > 0 and int(pinfo[1].get("worth", 0)) > 0,
		"`_peers_info` 里带着身家与名次（信息条的内容与它同源）")

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

	print("== 操作倒计时（D 方案）：四角条是倒计时唯一的落点（立牌已于批次 9 退场）==")
	# 倒计时簇原先立牌 / 四角条各一份；立牌随批次 9 退场 ⇒ 四角条成了唯一落点。它"3D / 2D 两端
	# 都常驻"的性质本来就比立牌稳。数据链路一字未改（仍由 _refresh_op_timer 逐帧推）。
	g.my_peer = 2
	g.s_state(_state(2, false))
	g._refresh_actions()
	await process_frame
	await process_frame
	g._process(0.0)
	g.s_op_timer("roll", 35.0, 35.0, 2)
	g._process(0.0)
	await process_frame
	var cbar_of := func(peer: int) -> Dictionary:
		for b in g.corner_bars:
			if int(b.peer) == peer:
				return b
		return {}
	var cb2: Dictionary = cbar_of.call(2)      # 乙 = 行动者
	var cb1: Dictionary = cbar_of.call(1)      # 甲 = 非行动者
	_check(not cb2.is_empty() and (cb2.timer_kind as Label).visible,
		"行动者的四角条上出现倒计时（环节名可见）")
	_check(String((cb2.timer_kind as Label).text) == "掷轮",
		"四角条上写环节名（实得「%s」）" % String((cb2.timer_kind as Label).text))
	_check(String((cb2.timer_left as Label).text) == "35 秒",
		"四角条上写剩余秒数（实得「%s」）" % String((cb2.timer_left as Label).text))
	var ctk2: ColorRect = cb2.timer_track
	var cfl2: ColorRect = cb2.timer_fill
	_check(ctk2.visible and cfl2.size.x > 0.9 * maxf(ctk2.size.x, 1.0),
		"四角条上的细进度条接近满格（%.1f / %.1f）" % [cfl2.size.x, ctk2.size.x])
	_check(not (cb1.timer_kind as Label).visible and not (cb1.timer_track as ColorRect).visible
			and not (cb1.timer_left as Label).visible,
		"其余三条不显示倒计时（只出现在行动者那一条上）")
	# 行常驻占位：倒计时**出现之后**那一条不许变高（变了四条边线就不齐、还会挤角按钮）
	var heights_ok := true
	for b in g.corner_bars:
		if not is_equal_approx((b.root as Control).size.y, TH.CORNER_BAR_SIZE.y):
			heights_ok = false
			print("    [实测] 倒计时出现后 peer %d 那条高 %.1f（应 %.1f）" % [
				int(b.peer), (b.root as Control).size.y, TH.CORNER_BAR_SIZE.y])
	_check(heights_ok, "倒计时出现后四条仍一样高（= CORNER_BAR_SIZE.y）")
	# 广播一秒一条，本机 _process 逐帧扣 delta 插值——喂剩 5 秒的道具窗口，
	# 等 1.5 秒（自然帧累积扣减），进度条应明显缩水、环节名跟着窗口走
	g.s_op_timer("item", 5.0, 12.0, 2)
	await create_timer(1.5).timeout
	g._process(0.0)
	var frac2: float = cfl2.size.x / maxf(ctk2.size.x, 1.0)
	_check(frac2 < 0.45 and frac2 > 0.15, "一秒多后进度条平滑缩水到中段（实得 %.2f）" % frac2)
	_check(String((cb2.timer_kind as Label).text).begins_with("道具"),
		"环节名跟着窗口走（实得「%s」）" % String((cb2.timer_kind as Label).text))
	# 窗口换人：倒计时跟到丙那一条
	g.s_op_timer("black", 15.0, 20.0, 3)
	g._process(0.0)
	await process_frame
	var cb3: Dictionary = cbar_of.call(3)
	_check((cb3.timer_kind as Label).visible and not (cb2.timer_kind as Label).visible,
		"窗口换人时倒计时跟着行动者换到丙那一条")
	_check(String((cb3.timer_kind as Label).text) == "黑市",
		"环节名「黑市」（实得「%s」）" % String((cb3.timer_kind as Label).text))
	_check(String((cb3.timer_left as Label).text) == "15 秒",
		"剩余秒数跟着换人（实得「%s」）" % String((cb3.timer_left as Label).text))
	# 不限时：仍显示环节名，但不写"0 秒"、进度条整条收起（语义原在座位卡上："不限时"）
	g.s_op_timer("roll", 0.0, 0.0, 3)
	g._process(0.0)
	_check((cb3.timer_kind as Label).visible and String((cb3.timer_kind as Label).text) == "掷轮"
			and not (cb3.timer_left as Label).visible and not (cb3.timer_track as ColorRect).visible,
		"不限时窗口仍显示环节名但不写秒数、不画进度条")
	# 窗口关闭：kind="" 四条一起收
	g.s_op_timer("", 0.0, 0.0, -1)
	g._process(0.0)
	await process_frame
	var any_corner_timer := false
	for b in g.corner_bars:
		if (b.timer_kind as Label).visible or (b.timer_track as ColorRect).visible \
				or (b.timer_left as Label).visible:
			any_corner_timer = true
	_check(not any_corner_timer, "窗口关闭后四条四角条的倒计时内容全部收起（四条都不显示）")

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

	print("== 右下角动作按钮（批次 7）：转动转盘 ↔ 结束回合 ↔ 隐藏 ==")
	_check(g.action_btn != null, "右下角动作按钮已建（TableHud.build_play_ui）")
	g.my_peer = 2
	g.s_state(_state(2, false))            # await="roll"、turn=2=我 ⇒ 我的掷轮窗口
	await process_frame
	g._process(0.0)
	_check(g.action_btn.visible and String(g.action_btn.text) == "转动转盘",
		"轮到我掷轮 → 按钮是「转动转盘」且可见（实得「%s」）" % String(g.action_btn.text))
	# 点它 = 掷轮（走既有的 _on_roll_pressed；本机是"服务端"路径，见文件头那段说明）
	var acted := [0]
	var on_act := func() -> void: acted[0] += 1
	g.roll_received.connect(on_act)
	g._awaiting_roll = 2
	g._on_action_pressed()
	_check(acted[0] == 1, "点「转动转盘」→ 走既有的掷轮入口（实得 %d 次）" % acted[0])
	g.roll_received.disconnect(on_act)
	# 掷完进道具阶段 → 变「结束回合」，点它 = 收尾道具阶段（_on_skip_pressed）
	var s_item2: Dictionary = _state(2, false)
	s_item2.await = "item"
	s_item2.await_peer = 2
	g._item_epoch = 7
	g.s_state(s_item2)
	await process_frame
	g._process(0.0)
	_check(g.action_btn.visible and String(g.action_btn.text) == "结束回合",
		"道具阶段 → 按钮变「结束回合」（实得「%s」）" % String(g.action_btn.text))
	g._on_action_pressed()
	_check(String(g._item_action.get("action", "")) == "skip",
		"点「结束回合」→ 走既有的跳过入口（实得「%s」）" % String(g._item_action.get("action", "")))
	# 不是我的窗口 → 隐藏
	g.s_state(_state(1, false))            # turn=1 ≠ 我
	await process_frame
	g._process(0.0)
	_check(not g.action_btn.visible, "不是我的回合 → 按钮隐藏")
	# 落位：在右下角身家条（上沿 offset -160）之上，两者不打架
	_check(g.action_btn.offset_bottom <= -160.0,
		"动作按钮落在右下角身家条之上（offset_bottom=%.0f ≤ -160）" % g.action_btn.offset_bottom)
	# 牌垫阶段按钮那一套必须**真的没了**（不是留成不可见空壳）
	_check(g.board.get_node_or_null("PhaseButtons") == null, "牌垫阶段按钮层已拆净")
	_check(not g.board.has_method("set_phase_buttons"), "set_phase_buttons 接口已退场")

	print("== 点手中牌：一次点击直出（批次 7）==")
	# 直出 = 点一张牌就出它，不再有"选中 → 再点确认"。走**真实**的 `_on_table_click` 链路。
	# 本机是默认 multiplayer（unique_id=1 ⇒ is_server() 恒真，见文件头），所以直接出牌走的是
	# 房主路径 `_use_item`（不是 RPC），可以安全地跑在无头测试里。
	# 关键：`_use_item` 的两条守卫是「房主名册（**hp**，不是 st）里有这个人」与「`_awaiting_item` == 我」
	# （game.gd:2371/2402）。名册 / 窗口归属不种齐，点击会在第二行就 return，牌根本没离手 ——
	# 只断言「点击被消费」就成了空转（空实现的 `_on_hand_clicked` 也能过）。第一张特意选
	# **效果只动现金、不走 await** 的 兼职中介，好让"真的执行了"有硬证据。
	g.my_peer = 2
	var hand_items: Array = [{"id": "兼职中介", "cd": 0}, {"id": "跑腿券", "cd": 0},
		{"id": "快递直达", "cd": 0}, {"id": "作弊器", "cd": 0}, {"id": "共享单车", "cd": 0}]
	var s_hand: Dictionary = _state(2, false)
	s_hand.await = "item"          # 轮到我、道具阶段
	s_hand.await_peer = 2
	for p in s_hand.players:
		if int(p.peer) == 2:
			p.items = hand_items.duplicate(true)
	g.s_state(s_hand)
	g.hp[1].items = hand_items.duplicate(true)   # 房主名册里 peer 2 那一份（_host_roster 的 index 1）
	g._awaiting_item = 2                          # 道具阶段窗口归属 = 我
	# `_awaiting_roll` 还留着上面「点转盘」段的 2：不清掉的话出牌后那次 `_broadcast_state`
	# 会把它当成掷轮窗口（`await` 先判 roll），下面 ②③④ 的 `_hand_clickable` 就整个不成立。
	g._awaiting_roll = 0
	await process_frame
	await process_frame
	g._process(0.0)
	var tph = g.table3d.table_props
	_check(tph.hand_count() == 5, "我的五件道具摆成五张手牌（满手，实得 %d）" % tph.hand_count())
	_check(g.selected_slot == -1, "初始未选中")

	# ① 不带目标的牌：点一下就出去了（不留在选中态、不进任何选目标态），**而且牌真的离手**：
	#    房主名册里那一件进了冷却、体力被扣、本回合计数 +1，现金真的到账（兼职中介 = 立刻 +¥800）。
	var money0: int = int(g._player_by_peer(2).money)
	var stam0: int = int(g._player_by_peer(2).stamina)
	var cost0: int = int(ItemData.def("兼职中介").cost)
	_check(g._on_table_click(tph.hand_rect(0).get_center()), "点第一张牌（不带目标）：点击被手牌消费")
	_check(int(g._player_by_peer(2).item_used_n) == 1 \
			and int(g._player_by_peer(2).items[0].cd) > 0 \
			and int(g._player_by_peer(2).stamina) == stam0 - cost0 \
			and int(g._player_by_peer(2).money) == money0 + 800,
		"不带目标的牌：**真的执行了 _use_item**（item_used_n=%d / 那件 cd=%d / 体力 %d→%d / 现金 %d→%d）"
			% [int(g._player_by_peer(2).item_used_n), int(g._player_by_peer(2).items[0].cd),
				stam0, int(g._player_by_peer(2).stamina), money0, int(g._player_by_peer(2).money)])
	_check(g.selected_slot == -1 and g._tgt_stage == "",
		"不带目标的牌：点一下直接出（selected_slot=%d / tgt_stage=「%s」）"
			% [g.selected_slot, g._tgt_stage])
	# 用完还原：别的段落不该有「道具阶段窗口」一直开着 —— 会让那几处点选目标后的
	# `_send_use_item` 真的走到 `_use_item`（本段只需它一次）。
	g._awaiting_item = 0

	# ② 需要选玩家的牌（跑腿券）：点一下**直接进**选目标态（不再需要第二次点击确认）
	_check(g._on_table_click(tph.hand_rect(1).get_center()), "点第二张（跑腿券）：点击被手牌消费")
	_check(g._tgt_stage == "peer", "点一下就跑腿券直接进选目标态（实得「%s」）" % g._tgt_stage)
	_check(g.selected_slot == -1, "进选目标态后 selected_slot 已清（不常驻）")
	g._cancel_target()
	_check(g._tgt_stage == "", "取消目标后回到无事态")

	# ③ 需要选格子的牌（快递直达）：同理，点一下直接进选地块态
	_check(g._on_table_click(tph.hand_rect(2).get_center()), "点第三张（快递直达）：点击被手牌消费")
	_check(g._tgt_stage == "tile", "点一下就快递直达直接进选地块态（实得「%s」）" % g._tgt_stage)
	g._cancel_target()

	# ④ 作弊器：点一下弹点数框（既不直接发也不进选目标态）
	_check(g._on_table_click(tph.hand_rect(3).get_center()), "点第四张（作弊器）：点击被手牌消费")
	_check(g.cheat_picker != null and g.cheat_picker.visible and g.cheat_slot == 3,
		"点作弊器 → 弹点数框、记下槽位 3（实得槽位 %d）" % g.cheat_slot)
	g._close_cheat_picker()

	print("== 近排格子不再被手牌压住（批次 5 Task 3：整排下移到木纹留白）==")
	# 批次 3 那条老问题（R38/R40）是「牌盒上沿咬住近排格子，只在格子顶部留下十几画布像素的
	# 可点缝；选中那张一抬起来，外侧两张的缝直接归零」。Task 3 把整排**放大 1.5 倍并下移到
	# 桌垫前沿的木纹留白（桌垫下沿之外、木桌之内）之后，牌与近排格子**完全不重叠** —— 这条钉住新结论。
	# 下面那段"牌底可点条带"的实测数值随之从 11~19 变成"整格皆可点"（报告与注释都按新值写）。
	var cell_of := func(i: int) -> Rect2:
		var p: Vector2 = g.board._view_from_world(g.board.tile_pos(i))
		var s: float = g.board.TILE * g.board._zoom
		return Rect2(p, Vector2(s, s))
	var near_row: Array = []
	for i in GameData.TILES.size():
		if g.board.tile_grid(i).y == GameData.BOARD_ROWS - 1:
			near_row.append(i)
	_check(near_row.size() == GameData.BOARD_COLS, "近排 %d 格都在（实得 %d）" % [GameData.BOARD_COLS, near_row.size()])
	g.s_state(s_hand)
	await process_frame
	g._process(0.0)
	var lowest_cell := 0.0
	for i in near_row:
		lowest_cell = maxf(lowest_cell, cell_of.call(i).end.y)
	var hand_top := INF
	var hand_bot := -INF
	var hand_x0 := INF
	var hand_x1 := -INF
	for k in tph.hand_count():
		var r: Rect2 = tph.hand_rect(k)
		hand_top = minf(hand_top, r.position.y)
		hand_bot = maxf(hand_bot, r.end.y)
		hand_x0 = minf(hand_x0, r.position.x)
		hand_x1 = maxf(hand_x1, r.end.x)
	_check(hand_top > lowest_cell,
		"手牌整排落在近排格子之下（牌上沿 %.1f > 格区下沿 %.1f）" % [hand_top, lowest_cell])
	# 逐格逐张验「真的不相交」（只看整体上沿是不够的：扇形外侧那两张更靠上）
	var cell_hits := 0
	for i in near_row:
		var cell: Rect2 = cell_of.call(i)
		for k in tph.hand_count():
			if cell.intersects(tph.hand_rect(k)):
				cell_hits += 1
	_check(cell_hits == 0, "没有一格与任何一张牌相交（相交 %d 处）—— 批次 3 的 R38/R40 就此消失" % cell_hits)
	# 批次 7：牌垫上的两枚阶段按钮已退场 ⇒ 原来这条"手牌不与按钮交叠"作废。
	# 手牌与近排格子不相交那条（上面 `cell_hits == 0`）仍在，落位硬约束由它守着。

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

	# ② 牌自己身上：三种情况各点一次。采样点一律取**牌面的中心**（真落在牌盒里，
	#    不是"格子下沿恰好也在盒里"那种巧合）——「不被吞」才不是空谈。
	#    取法走**真实的点击链路**：牌面八角的屏幕包围盒 → 盒心 → `screen_to_viewport` → 画布。
	#    （**不能**反过来用 `viewport_to_screen` 把画布点映回屏幕：批次 5 Task 3 起牌整排
	#     落在纹理窗口**之外**的木纹留白上，那个函数对窗口外的画布点一律返回 null。）
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
	var pts: Array = []              # [{card: int, pt: Vector2}]
	for k in tph.hand_count():
		var sp_c: Vector2 = (screen_box.call(k) as Rect2).get_center()
		var cv = g.table3d.screen_to_viewport(sp_c)
		pts.append({"card": k, "pt": cv if cv != null else Vector2(-9999.0, -9999.0),
			"screen": sp_c})

	# 2a 非道具阶段：这些点必须**不被吞**（漏给桌垫）—— 这才是阶段闸的功劳，去掉闸这里就红
	var blocked := 0
	var still_covered := 0
	for c in pts:
		g._cancel_target()
		if tph.hand_hit(c.pt) >= 0:
			still_covered += 1
		if g._on_table_click(c.pt):
			blocked += 1
	_check(still_covered == pts.size(),
		"（对照）这 %d 个点确实落在牌盒里（实得 %d）——「不被吞」不是空谈" % [pts.size(), still_covered])
	_check(blocked == 0, "不是道具阶段：牌面上这 %d 个点**全都不被吞**（被吞 %d）——阶段闸在干活"
		% [pts.size(), blocked])
	g._cancel_target()

	# 2b 道具阶段：这些点**被吞**，而且命中的正是**它自己那张**牌
	#（点取自"看得见的那块屏幕包围盒的中心"，判据走 hand_hit —— 两条链路对得上才算数）
	g.s_state(s_hand)
	await process_frame
	g._process(0.0)
	var eaten := 0
	var eaten_self := 0
	for c in pts:
		# 每次点之前先清空选中 / 选目标态：这样「点之前的手牌摆位」每次都一样，屏幕包围盒才在点之前算得准
		#（批次 7 起点下去 = 直接出牌，跑腿券 / 快递直达会进选目标态 —— 这里把上一跳的状态先收干净）。
		g._cancel_target()
		g._close_cheat_picker()
		var boxes: Array = []
		for k in tph.hand_count():
			boxes.append(screen_box.call(k))
		if g._on_table_click(c.pt):
			eaten += 1
			if tph.hand_hit(c.pt) == int(c.card) \
					and (boxes[c.card] as Rect2).has_point(c.screen as Vector2):
				eaten_self += 1
	g._cancel_target()
	_check(eaten == pts.size(), "道具阶段：牌面上这 %d 个点都被手牌接收（实得 %d）"
		% [pts.size(), eaten])
	_check(eaten_self == eaten, "被接收的点屏幕上确实画着**它自己那张**牌（%d / %d）"
		% [eaten_self, eaten])

	# 2c 实测取证：**牌底那几格还剩多少可点条带**（批次 5 Task 3 的验收点）。
	#    批次 3 的答案是"未选中 11~19、抬起后外侧两张归零"；今天牌整排下移到木纹留白，
	#    答案是**没有格子被盖住**：近排每格的整条高都能点。
	#    **量的是最坏档**（批次 5 Task 4 改）：**满手 5 张、抬起扇形最外侧那张** —— 外侧那张
	#    画布 y 最高（离格子最近），抬起又把它整体抬高，正是当年"归零"的那一档；
	#    3 张手牌量到的是另一个数（批次 5 是 201.5 / 188.8），钉不住最坏情况。
	#    **批次 10 重取：79.9 / 68.0**（批次 10 T1 是 77.0 / 63.4；批次 5 是 190.0 / 177.0）——
	#    T1 把整排上移到木纹带正中（HAND_BASE_PX 1862 → 1834）**同时** `fit_zoom` 从 0.9116
	#    涨到 0.96374（近排格子在画布上更大、下沿更靠下）⇒ 缝窄了 113 画布像素；T2 把相机
	#    从 5.2 收到 4.7 ⇒ 缝又**宽回来** 2.9 / 4.6 画布像素（`hand_rect` 是拿 3D 相机把牌
	#    投影回画布算的，相机一动它就跟动 —— 见 `table_props.hand_rect` 那段"相机变动会改
	#    你看到它的位置"）。**仍远大于 0**（这条断言要的就是"没盖住"）。
	#    ⚠ 这两个数**跟着 3D 相机走**：改手牌尺寸 / 摆位 / **`CAM_DIST`** 都得回来重取，
	#    改不动就红。这两个数**钉进断言**（不只写在注释里）。
	#    **批次 7 起点击 = 直出**，一次点击不再**留在**选中态（抬起只在那一瞬间发生），
	#    所以这里走**保留的玩法侧选中入口** `_on_item_slot_clicked` 把那张牌抬起来 ——
	#    抬起的表现（`set_hand_selected`）与这条布局约束都还在，量到的仍是同一档。
	g._cancel_target()
	var gap_plain: float = hand_top - lowest_cell
	var sel_card := 0                 # 0 = 扇形最外侧（外侧两张对称，取哪张都一样）
	g._on_item_slot_clicked(g.my_peer, sel_card)
	# 先钉「真的抬起来了」：不然没抬时 gap_sel == gap_plain 也照样过，这条就白测了。
	_check(g.selected_slot == sel_card,
		"选中入口**真的抬起了一张**（selected_slot 期望 %d，实得 %d）" % [sel_card, g.selected_slot])
	var sel_top := INF
	for k in tph.hand_count():
		sel_top = minf(sel_top, tph.hand_rect(k).position.y)
	var gap_sel: float = sel_top - lowest_cell
	print("    [实测] 牌底可点条带：未选中 %.1f 画布像素、抬起（第 %d 张）后 %.1f —— 都不为 0"
		% [gap_plain, sel_card, gap_sel])
	g._cancel_target()
	_check(gap_plain > 0.0 and gap_sel > 0.0,
		"选中 / 未选中两档下，近排格子都还有可点的条带（%.1f / %.1f 画布像素）" % [gap_plain, gap_sel])
	_check(absf(gap_plain - 79.9) <= 1.0 and absf(gap_sel - 68.0) <= 1.0,
		"满手 5 张 + 选中外侧那张，实测值就是注释里那两个数（%.1f / %.1f，期望 79.9 / 68.0）"
			% [gap_plain, gap_sel])

	# ③ 下沿：近排**每一格**（不再需要"找没被盖住的那一格"—— 今天一格都没被盖住）的下沿都必须
	#    **不被消费**，并解算到它自己。这里验的是**下游那一半**（board._index_at 把它解算成这格
	#    → game._on_tile_clicked 打开详情卡）；上游那一半（BoardView 在鼠标松开时 emit
	#    tile_clicked）是既有代码、本任务没碰，`_on_table_click` 返回 false 意味着这次点击
	#    会照原样送进桌垫走到它。
	var idx_bad := 0
	var swallowed := 0
	for i in near_row:
		var cell: Rect2 = cell_of.call(i)
		var low_pt := Vector2(cell.get_center().x, cell.end.y - 3.0)
		if g.board._index_at(low_pt) != i:
			idx_bad += 1
		if g._on_table_click(low_pt):
			swallowed += 1
	_check(idx_bad == 0, "近排每格的下沿采样点都解算到它自己（解错 %d 格）" % idx_bad)
	_check(swallowed == 0, "近排 %d 格的下沿全都能点（被手牌吞掉 %d 格）" % [near_row.size(), swallowed])
	var free_tile: int = near_row[mini(3, near_row.size() - 1)]
	var cell_f: Rect2 = cell_of.call(free_tile)
	var low_f := Vector2(cell_f.get_center().x, cell_f.end.y - 3.0)
	g.info_panel.visible = false
	g._on_tile_clicked(free_tile)          # 桌垫那一端（tile_clicked）接的就是它
	await process_frame
	_check(g.info_panel.visible, "该格（#%d）详情卡打开（_index_at → _on_tile_clicked 这一半打通）" % free_tile)

	print("== 手牌重排：抬起反馈不漂（每次广播都重摆一遍手牌）==")
	g.s_state(s_hand)
	await process_frame
	var y1_plain: float = tph.hand_rect(1).get_center().y      # 抬起前的第二张
	# 批次 7 起点击 = 直出（点一下就把 跑腿券 用掉），要钉「广播重摆不丢抬起反馈」就得走
	# **保留的玩法侧选中入口** —— 它写 selected_slot + set_hand_selected，是抬起反馈的唯一来源。
	g._on_item_slot_clicked(g.my_peer, 1)
	_check(g.selected_slot == 1, "选中第二张（实得 %d）" % g.selected_slot)
	g.s_state(s_hand)                    # 再来一次广播：手牌被重摆
	await process_frame
	_check(g.selected_slot == 1, "广播重摆手牌后选中态不漂（实得 %d）" % g.selected_slot)
	_check(tph.hand_rect(1).get_center().y < y1_plain - 4.0,
		"重摆后抬起反馈还在（抬起的第二张 %.0f，未抬起时是 %.0f）"
			% [tph.hand_rect(1).get_center().y, y1_plain])
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

	print("== 选目标期间：手牌对点击完全透明（终审 R2）==")
	# `_hand_clickable` 补上 `_tgt_stage == ""`：选目标时玩家**正要**点格子 / 四角条，手牌不能抢答成
	# 「改选另一张牌」。修完后手牌在选目标期间对点击**完全透明**：左键落回棋盘 = 选格、
	# 右键 = 既有取消。
	# **批次 5 Task 3 起这条闸仍然必须站岗**，虽然牌已不再盖住任何近排格子（见上一段）：
	# 玩家在选格时点到自己的牌上，那一下同样不能变成"换选另一张牌"。
	g.hp[0].items = [{"id": "共享单车", "cd": 0}, {"id": "跑腿券", "cd": 0}, {"id": "快递直达", "cd": 0}]
	g.s_state(s_disc)
	await process_frame
	g._process(0.0)
	var probe_pt: Vector2 = tph.hand_rect(0).get_center()
	_check(tph.hand_hit(probe_pt) == 0, "（对照）这个点确实落在第一张牌的命中盒里")
	g._begin_tile_target(0, [near_row[0]])
	_check(g._tgt_stage == "tile" and g._tgt_tiles.has(near_row[0]), "进了选地块态、该格可选")
	_check(not g._on_table_click(probe_pt, MOUSE_BUTTON_LEFT),
		"选目标期间：左键点手牌不消费（落回棋盘）")
	_check(not g._on_table_click(probe_pt, MOUSE_BUTTON_RIGHT),
		"选目标期间：右键手牌也不消费（落回棋盘 = 既有取消）")
	_check(g.selected_slot == -1, "选目标期间点牌不改选中态（实得 %d）" % g.selected_slot)
	# 该格的下沿仍照原样落回桌垫（手牌不消费 → 会进 tile_clicked）
	var cell_r0: Rect2 = cell_of.call(near_row[0])
	var low_r0 := Vector2(cell_r0.get_center().x, cell_r0.end.y - 3.0)
	_check(not g._on_table_click(low_r0, MOUSE_BUTTON_LEFT),
		"选目标期间：点近排格子的下沿也不被手牌消费")
	_check(g.board._index_at(low_r0) == near_row[0], "该点仍解算到这格（会照原样进桌垫 → tile_clicked）")
	g._on_tile_clicked(near_row[0])           # 桌垫那一端（tile_clicked）接的就是它
	_check(g._tgt_stage == "", "该格被选中 → 选目标态收尾（实得「%s」）" % g._tgt_stage)
	g._cancel_target()

	print("== 立牌已退场（批次 9）：接口与节点都不在（不留空壳） ==")
	var tpS = g.table3d.table_props
	_check(tpS != null, "TableProps 在")
	if tpS != null:
		_check(not tpS.has_method("set_standees"), "set_standees 已退场")
		_check(not tpS.has_method("standee_hit"), "standee_hit 已退场")
		_check(not tpS.has_method("standee_screen_center"), "standee_screen_center 已退场")
		_check(not tpS.has_method("set_standee_timer"), "set_standee_timer 已退场")
		_check(not tpS.has_method("set_standee_highlight"), "set_standee_highlight 已退场")
		_check(tpS.get_node_or_null("Standees") == null, "桌上没有立牌父节点")
	_check(not g.has_method("_refresh_standees"), "game._refresh_standees 已退场")
	var TP1 = load("res://scripts/table_props.gd")
	var tp_consts: Dictionary = TP1.get_script_constant_map()
	_check(not tp_consts.has("STANDEE_SIZE") and not tp_consts.has("STANDEE_BASE_PX") \
			and not tp_consts.has("BACKPACK_MAX"),
		"立牌常量（STANDEE_* / BACKPACK_MAX）已删")

	print("== 四角身家条可点 → 玩家道具弹窗（批次 9）==")
	g.my_peer = 2
	var s_cb: Dictionary = _state(2, false)
	for p in s_cb.players:
		if int(p.peer) == 1:
			p.stamina = 4
			p.items = [{"id": "招财猫", "cd": 0}, {"id": "黑卡", "cd": 0, "charges": 3}]
	g.s_state(s_cb)
	await process_frame
	await process_frame
	g._process(0.0)
	_check(g.corner_bars[0].root.mouse_filter == Control.MOUSE_FILTER_STOP,
		"四角条吃点击（STOP）")
	# **按 peer 找那条，别写下标假设**：角位是"自己打头、其余按行动序"轮转出来的，
	# my_peer=2 时 seats=[2,3,4,1] ⇒ peer 1 落在第 4 条，不是第 2 条。
	var idx1 := -1
	for i in g.corner_bars.size():
		if int((g.corner_bars[i] as Dictionary).get("peer", GameData.NO_PEER)) == 1:
			idx1 = i
	_check(idx1 >= 0, "peer 1 的四角条在（实得下标 %d）" % idx1)
	g._on_corner_bar_clicked(1)
	await process_frame
	_check(g.player_popup != null and g.player_popup.is_open(), "点四角条 → 道具弹窗打开")
	_check(g.player_popup.item_count == 2, "弹窗里卡牌数与 st 一致（2 件，实得 %d）" % g.player_popup.item_count)
	_check(g.player_popup.stamina_text == "4", "弹窗里能量（体力）值与 st 一致（实得「%s」）" % g.player_popup.stamina_text)
	g.player_popup.close()
	_check(not g.player_popup.is_open(), "关闭后收起")
	# 反向：不可见的那条不该开（人少了 / 自己不在名册时不崩）
	g._on_corner_bar_clicked(999)
	_check(not g.player_popup.is_open(), "点一个不存在的玩家：不开弹窗、也不崩")
	# 真链路：**从条根发一次 gui_input**（走 `_make_corner_bar` 那条 lambda + `get_meta("peer")`），
	# 而不是直调 `_on_corner_bar_clicked` —— 谁哪天把 lambda 改成闭包捕获 peer（dispatch 里点名的
	# 坑），直调那条路照样绿。这里**先换 my_peer 让角位真重排**（seats 从 [2,3,4,1] 变成 [3,4,1,2]），
	# 再点重排后的 bar[1] —— 若 lambda 捕获的是那一刻的旧 peer，就会点错人、这条红。
	g.my_peer = 3
	g.s_state(_state(3, false))
	await process_frame
	await process_frame
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	var bar1: Control = g.corner_bars[1].root
	bar1.gui_input.emit(ev)
	await process_frame
	_check(g.player_popup.is_open() and g.player_popup.open_peer() == int(g.corner_bars[1].peer),
		"经 gui_input 真链路：开在**该条当前挂的那个 peer** 上（meta 路径没被闭包捕获顶掉）")
	# 支撑断言：条根 meta 与 bar.peer 同源（meta 路径万一失效，上面那条会以"点错人"的形式红，
	# 这条则直接指出是 meta 没跟上重排）。
	_check(int(bar1.get_meta("peer", GameData.NO_PEER)) == int(g.corner_bars[1].peer),
		"条根 meta 与 bar.peer 同源（实得 meta=%d / bar=%d）"
			% [int(bar1.get_meta("peer", GameData.NO_PEER)), int(g.corner_bars[1].peer)])
	g.player_popup.close()

	print("== 弹窗关闭路径（终审 fix wave）==")
	# 三条真链路各钉一次 —— 此前只测了直调 `close()`，而"✕ / 点外部 / Esc 都能关"
	# 是本批写明的验收项（`hud_test.gd:1188` 那条 `gui_input` 真链路同风格）。
	# ① 点压暗底（`_dim` 上那条 gui_input lambda，**只认左键**）→ 关。
	g._on_corner_bar_clicked(1)
	await process_frame
	_check(g.player_popup.is_open(), "重开（准备测压暗底）")
	var left_ev := InputEventMouseButton.new()
	left_ev.button_index = MOUSE_BUTTON_LEFT
	left_ev.pressed = true
	g.player_popup._dim.gui_input.emit(left_ev)
	await process_frame
	_check(not g.player_popup.is_open(), "点压暗底（真 gui_input 链路）→ 弹窗关闭")
	# ② 非左键（滚轮 / 右键）**不该**关 —— 同一条 lambda 里那道按键判断。
	g._on_corner_bar_clicked(1)
	await process_frame
	var wheel_ev := InputEventMouseButton.new()
	wheel_ev.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_ev.pressed = true
	g.player_popup._dim.gui_input.emit(wheel_ev)
	await process_frame
	_check(g.player_popup.is_open(), "滚轮点压暗底：不关（只认左键）")
	# ③ Esc 走 `game._unhandled_input` 的**真分支**（不是直调 close）。前置：此刻没有选目标态 /
	# 未选中牌 —— 那两个也吃 Esc，且排在同一函数里更靠前的位置。
	_check(g._tgt_stage == "" and g.selected_slot < 0, "Esc 之前：无选目标态 / 未选中牌（前置）")
	var esc_ev := InputEventKey.new()
	esc_ev.keycode = KEY_ESCAPE
	esc_ev.pressed = true
	g._unhandled_input(esc_ev)
	await process_frame
	_check(not g.player_popup.is_open(), "Esc（真 _unhandled_input 链路）→ 弹窗关闭")

	print("== 弹窗内容：（被动）标签（终审 fix wave）==")
	# 「完成标准」把"被动标记"列为弹窗内容之一，但此前没有断言钉它。招财猫 `type: passive`
	# ⇒ 它那一行后缀里应有「（被动）」。读**行内 Label 的 text**（最强可观察量），不读内部标志。
	var s_pas: Dictionary = _state(3, false)
	for p in s_pas.players:
		if int(p.peer) == 1:
			p.items = [{"id": "招财猫", "cd": 0}]
	g.s_state(s_pas)
	await process_frame
	await process_frame
	g._on_corner_bar_clicked(1)
	await process_frame
	_check(g.player_popup.item_count == 1, "弹窗里 1 件（招财猫，实得 %d）" % g.player_popup.item_count)
	var has_passive := false
	var row_texts: Array = []
	for c in g.player_popup._body.get_children():
		if c is HBoxContainer:
			for l in (c as HBoxContainer).get_children():
				if l is Label:
					var t := String((l as Label).text)
					row_texts.append(t)
					if t.contains("（被动）"):
						has_passive = true
	_check(has_passive, "弹窗里那一行含「（被动）」（招财猫是 passive；实得 %s）" % str(row_texts))
	g.player_popup.close()

	print("== 选目标：高亮搬到四角身家条、点它 = 选中（批次 9）==")
	# 立牌随批次 9 退场 ⇒ "此刻可选中的对手"这份高亮改画在**屏幕四角身家条**上（2px 金边 +
	# 底色提亮，与行动者的 1px 金边分得开）。这里既钉"哪几条亮着"，也钉"点亮的那条点下去真的选中"。
	# 用**强拆令**（两段式：只能选"名下有地"的玩家）—— 它的目标过滤天然分得出"有的亮、有的不亮"。
	g.my_peer = 2
	var s_tg: Dictionary = _state(2, false)
	for p in s_tg.players:
		if int(p.peer) == 2:
			p.items = [{"id": "强拆令", "cd": 0}]   # 给"我"一张两段式牌（`_target_item_id` 读的就是它）
	g.s_state(s_tg)
	await process_frame
	await process_frame
	g._begin_peer_target(0, false, true)           # 直接走入口：进入选玩家态
	await process_frame
	var hot: Array = []
	for b in g.corner_bars:
		if _corner_bar_hot(g, b):
			hot.append(int((b as Dictionary).get("peer", GameData.NO_PEER)))
	# fixture：`_state()` 的四家是 [1 甲(有一号楼) / 2 乙(我) / 3 丙(无地) / 4 丁(已出局)]，
	# `then_prop=true` 只留下"名下有地"的 ⇒ 可选目标**只有 peer 1 一个**。
	_check(hot.size() == 1 and hot[0] == 1,
		"选目标态下**只有** peer 1 那条亮着（实得 %s）" % str(hot))
	# 点那条 → 真的进"选定后"的后果（走既有 _on_seat_clicked）
	g._on_corner_bar_clicked(1)                    # 强拆令这类需要再选一块地 ⇒ 转进选地块段
	_check(String(g._tgt_stage) == "tile" and int(g._tgt_peer) == 1,
		"点亮的条被点 → 走既有选目标链（tgt_stage=「%s」/ tgt_peer=%d）" % [g._tgt_stage, g._tgt_peer])
	g._cancel_target()
	await process_frame
	_check(hot.size() > 0 and not _corner_bar_hot(g, _bar_of(g, 1)),
		"取消选目标后四角条高亮熄灭")

	print("== 棋子动画（批次 11 Task 1）：走子抬 y、传送淡到看不见 ==")
	# 棋子那四样动作（逐格走 / 传送 / 弹入 / 光环）在 3D 里重写了（设计 §4.1）。走子与传送
	# 必须有**可观察量** —— 否则"传送看不见"这类事没法断言。这里量两个只读量：
	# `token_world_pos`（走子的 y 弧）与 `token_alpha`（传送的淡出）。
	g.my_peer = 2
	g.s_state(_state(2, false))
	await process_frame
	var tpA = g.table3d.table_props
	if tpA == null or not tpA.has_method("play_token_move"):
		_check(false, "TableProps 没有 play_token_move（棋子动画未接），本段整段跳过")
	else:
		await create_timer(0.5).timeout      # 等首次弹入（scale 0→1）落定
		# peer 3 的棋子节点（读世界位置与材质模式）：与 layout_test 同一条取法（节点池按 peer 命名）
		# 按 **meta("peer")** 找那枚棋子的节点（位置 / 材质模式）——**不按节点名**：同帧重建时
		# Godot 会把重名的子节点自动改名（table_props 已用 remove_child 规避，但测试不该依赖名字）。
		var trootA: Node = tpA.get_node_or_null("Tokens")
		var tk3: Node3D = null
		if trootA != null:
			for ch in trootA.get_children():
				if (ch as Node).has_meta("peer") and int((ch as Node).get_meta("peer")) == 3:
					tk3 = ch as Node3D
		_check(tk3 != null, "peer 3 的棋子节点在（下面几条要读它）")
		var p3 := int(g._state_player(3).get("pos", 0))
		var base_y: float = tpA.token_world_pos(3).y
		_check(base_y > 0.0, "棋子在桌面上（基准 y=%.3f）" % base_y)
		# 走子走**真入口** `s_move`（@rpc call_local：直调就是本机那一次）；两步、每步 0.4s。
		g.s_move(3, [p3 + 1, p3 + 2], 0.4)
		# 采样窗口覆盖整段动画（2 步 × 0.4s）还有余量；每步一个弧，取全程峰值与终值。
		var max_y := base_y
		for i in 36:
			await create_timer(0.03).timeout
			max_y = maxf(max_y, tpA.token_world_pos(3).y)
		_check(max_y > base_y + 0.03,
			"走子期间棋子的世界 y **抬升过**（%.3f → 峰值 %.3f —— 竖直小跳的弧）" % [base_y, max_y])
		_check(absf(tpA.token_world_pos(3).y - base_y) < 0.01,
			"走完落回桌面高度（%.3f，基准 %.3f）" % [tpA.token_world_pos(3).y, base_y])
		# 传送：`s_tp`（送监 / 传送类道具走的同一条）——淡出 → 瞬移 → 淡入。
		# **放慢 5 倍再采样**：`token_alpha` 只有逐帧采样才抓得住"淡到看不见"那一档，
		# 正常速度下每帧的 alpha 步长（≈0.075/帧）比判据还粗，采不到接近 0 的点。
		var before_tp: Vector3 = tpA.token_world_pos(3)
		Engine.time_scale = 0.2
		g.s_tp(3, 12)
		var min_a := 1.0
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 2600:
			await process_frame
			min_a = minf(min_a, tpA.token_alpha(3))
		Engine.time_scale = 1.0
		_check(min_a < 0.05, "传送期间棋子**淡到看不见**（alpha 最低 %.3f）" % min_a)
		_check(tpA.token_alpha(3) > 0.95, "传送完毕回到不透明（%.3f）" % tpA.token_alpha(3))
		_check(tpA.token_world_pos(3).distance_to(before_tp) > 0.1,
			"传送落点真的变了（%s → %s）" % [before_tp, tpA.token_world_pos(3)])
		# 材质**模式**也要恢复（批次 11 T1 审查 Minor #4）：只把 alpha 写回 1、模式留在 ALPHA 的
		# 实现照样能过上面那条 `token_alpha` —— 但那样的牌在**透明队列**里：不写深度、不投影
		# （批次 8/9 那条先例）。照 `hand` 那组既有断言（读材质、不读标志）。
		var pmat3: StandardMaterial3D = null
		var fmat3: StandardMaterial3D = null
		if tk3 != null:
			pmat3 = (tk3.get_node("Plate") as MeshInstance3D).material_override as StandardMaterial3D
			fmat3 = (tk3.get_node("Face") as MeshInstance3D).material_override as StandardMaterial3D
		_check(pmat3 != null and pmat3.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
			"传送后牌身回到**不透明档**（实得 %s）" % str(pmat3.transparency if pmat3 != null else -1))
		_check(fmat3 != null and fmat3.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
			"传送后正面回到 ALPHA_SCISSOR（实得 %s）" % str(fmat3.transparency if fmat3 != null else -1))

		print("== 传送被打断：材质与模式必须一并恢复（T1 审查 Important #2）==")
		# 走子补间只写 `global_position`/`scale` —— 它**不会**重新置位材质。所以走子若落在传送的
		# 0.38s 窗内（淡出中），被打断的传送会把牌留在**半透明 + 透明队列**（无深度写入、无影子）
		# 直到下一次传送。`_kill_token_tw` 现在无条件把材质恢复成不透明。
		g.s_tp(3, 13)                        # 开始传送：淡出 0.16s → 瞬移 → 淡入 0.22s
		await create_timer(0.08).timeout      # 停在**淡出中**
		_check(tpA.token_alpha(3) < 0.9, "（前置）此刻确实在淡出中（alpha %.3f）" % tpA.token_alpha(3))
		g.s_move(3, [14], 0.3)               # 打断：走子落在传送窗内
		await create_timer(0.5).timeout
		_check(tpA.token_alpha(3) > 0.95,
			"被打断的传送把棋子留回了不透明（alpha %.3f）" % tpA.token_alpha(3))
		if pmat3 != null:
			_check(pmat3.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
				"被打断后牌身回到不透明档（实得 %s）" % str(pmat3.transparency))
		if fmat3 != null:
			_check(fmat3.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
				"被打断后正面回到 ALPHA_SCISSOR（实得 %s）" % str(fmat3.transparency))

		print("== 走子进行中收到广播：棋子不被瞬回（T1 审查 Minor #7）==")
		# `set_tokens` 对正在走子的棋子**不抢位置**（`_moving` 那道闸，同 2D 的 `_animating`）。
		# 少了它，动画中途到达的状态广播会把棋子瞬回起点/落点。
		var p3b := int(g._state_player(3).get("pos", 0))
		g.s_move(3, [p3b + 1, p3b + 2], 0.5)
		await create_timer(0.2).timeout
		_check(tpA.token_moving(3), "走子期间 `token_moving` 为真（闸是开着的）")
		var mid_px := Vector2.ZERO
		if tk3 != null:
			mid_px = g.table3d.world_to_canvas_px(tk3.global_position)
		g.s_state(_state(2, false))          # 中途来一次完整广播（状态里的 pos 还是老格号）
		await process_frame
		if tk3 != null:
			var after_px: Vector2 = g.table3d.world_to_canvas_px(tk3.global_position)
			# 广播若抢了位置会瞬移到某格的落点上（≥ 几十画布像素）；这里只允许"补间又走了一帧"
			_check(after_px.distance_to(mid_px) < 20.0,
				"广播没把走子中的棋子瞬回（%s → %s，瞬回会是几十像素的跳）" % [mid_px, after_px])
		# 走完仍要落在**目的地**（闸不能把收尾也挡掉）
		await create_timer(1.0).timeout
		_check(not tpA.token_moving(3), "走完后 `token_moving` 落回假")
		if tk3 != null:
			var dest_px: Vector2 = g.table3d.world_to_canvas_px(tk3.global_position)
			var want_dest: Vector2 = g.board.token_screen_pos(p3b + 2, int(g._state_player(3).get("color", 0)))
			_check(dest_px.distance_to(want_dest) < 1.0,
				"走完落在目的地的印刷落点上（实得 %s / 期望 %s）" % [dest_px, want_dest])

		print("== 镜头平移（无广播）时，棋子与房子跟着印刷图案走（T1 审查 Important #1 / T2）==")
		# 2D 相机**逐帧**在动（`board._process` 的自动跟随 / 取景），而"跟图案"的实物原先只挂状态广播
		# ⇒ 镜头动过但没广播的那一段里，印在 `_world` 里的格子会滑动、实物不动（实测约半格、~1s 衰减；
		# 对旧 2D 棋子来说——它活在 `_world` 里、任何时刻都钉在格子上——那是**回归**）。
		# `game._process` 现在按"取景键"补推一次（`_refresh_followers_if_cam_moved`）。
		# **批次 11 Task 2 把房子也并进了这同一批**（房子压在格子上 ⇒ 同一条口径）——
		# 下面这段同时钉棋子与房子，就是"纳入逐帧补推"的可执行证据。
		g.board.cam_locked = false
		var st_cam: Dictionary = _state(2, false)    # 回一份干净状态：peer 3 落在老格号上
		var tiles_cam: Array = st_cam.tiles
		tiles_cam[3].level = 2                       # 顺带给 3 号格一棵房子（下面那条要用）
		g.s_state(st_cam)
		await process_frame
		var pcam := int(g._state_player(3).get("pos", 0))
		var slot3 := int(g._state_player(3).get("color", 0))
		var h3c: Node3D = null
		var h0c := Vector2.ZERO
		var h1c := Vector2.ZERO
		var h_want_c := Vector2.ZERO
		if tpH != null and tpH.has_method("set_houses"):
			h3c = _house_node(tpH.get_node_or_null("Houses"), 3)
			if h3c != null:
				h0c = g.table3d.world_to_canvas_px(h3c.global_position)
				h_want_c = g.board.house_screen_pos(3)
		_check(h3c != null and h3c.visible, "（前置）3 号格立着房子薄牌（下面那条要读它）")
		if tk3 != null:
			var w0: Vector2 = g.table3d.world_to_canvas_px(tk3.global_position)
			_check(w0.distance_to(g.board.token_screen_pos(pcam, slot3)) < 1.0,
				"（前置）广播推送后棋子已在印刷落点上")
			if h3c != null:
				_check(h0c.distance_to(h_want_c) < 1.0,
					"（前置）广播推送后房子也在它那条带的印刷落点上")
			g.board.focus_grid(pcam, 2.0, true)        # 只动 2D 镜头（**不广播**）
			await process_frame
			var want1: Vector2 = g.board.token_screen_pos(pcam, slot3)
			_check(want1.distance_to(w0) > 8.0,
				"（前置）镜头动过之后印刷落点确实移了（%.1f 画布像素）" % want1.distance_to(w0))
			if h3c != null:
				h_want_c = g.board.house_screen_pos(3)
				_check(h_want_c.distance_to(h0c) > 8.0,
					"（前置）镜头动过之后房子的印刷落点也移了（%.1f 画布像素）" % h_want_c.distance_to(h0c))
			g._process(0.0)                            # 真入口：game 的逐帧补推
			var w1: Vector2 = g.table3d.world_to_canvas_px(tk3.global_position)
			_check(w1.distance_to(want1) < 1.0,
				"镜头平移后棋子跟着印刷图案重推（实得 %s / 期望 %s）" % [w1, want1])
			if h3c != null:
				h1c = g.table3d.world_to_canvas_px(h3c.global_position)
				_check(h1c.distance_to(h_want_c) < 1.0,
					"**同一批补推里房子也重推了**（实得 %s / 期望 %s）" % [h1c, h_want_c])
			g._process(0.0)
			g._process(0.0)
			_check(g.table3d.world_to_canvas_px(tk3.global_position).is_equal_approx(w1),
				"镜头静止时补推早退（位置一字不变 —— 每帧只比三个浮点数）")
			if h3c != null:
				_check(g.table3d.world_to_canvas_px(h3c.global_position).is_equal_approx(h1c),
					"镜头静止时房子也不重摆（与棋子走同一条早退）")
		g.board.fit_overview(true)

	g.get_tree().paused = false
	g.free()
	if fails == 0:
		print("HUD TEST: ALL PASS")
		quit(0)
	else:
		print("HUD TEST: %d FAILURES" % fails)
		quit(1)
