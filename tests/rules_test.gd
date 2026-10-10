extends SceneTree
## 规则单元测试：godot --headless --script tests/rules_test.gd

var fails := 0

func _initialize() -> void:
	_test_rent()
	_test_fmt()
	_test_endpoint()
	_test_classify()
	_test_board_shape()
	_test_paths()
	if fails == 0:
		print("RULES TEST: ALL PASS")
		quit(0)
	else:
		print("RULES TEST: %d FAILURES" % fails)
		quit(1)

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

## 所有地产的下标（按路径序）
func _prop_indices() -> Array:
	var out := []
	for i in GameData.TILES.size():
		if GameData.TILES[i].type == "property":
			out.append(i)
	return out

func _test_rent() -> void:
	var idxs: Array = _prop_indices()
	_check(idxs.size() == 30, "30 块地产（实得 %d）" % idxs.size())
	var a: int = idxs[0]
	var tiles := _fresh_tiles()
	_check(GameData.rent_for(a, tiles) == 0, "无主地块租金为 0")
	tiles[a].owner = 1
	var base: int = GameData.TILES[a].rent
	_check(GameData.rent_for(a, tiles) == base, "基础租金")
	tiles[a].level = 2
	_check(GameData.rent_for(a, tiles) == base * 3, "等级租金 Lv2")
	# 每块地彼此独立：把全场都买下也不会出现「成套翻倍」（该机制已废除）
	for j in idxs:
		tiles[j].owner = 1
	_check(GameData.rent_for(a, tiles) == base * 3, "买满全场也不再有成套翻倍")
	tiles[idxs[1]].owner = 2
	_check(GameData.rent_for(a, tiles) == base * 3, "别的地块易主不影响本块租金")
	var any_prop := -1
	for i in GameData.TILES.size():
		if GameData.TILES[i].type == "property":
			any_prop = i
			break
	_check(GameData.upgrade_cost(any_prop) == int(GameData.TILES[any_prop].price * 0.5), "升级费用 = 地价一半")

func _test_fmt() -> void:
	_check(GameData.fmt_money(1234567) == "¥1,234,567", "千分位正数")
	_check(GameData.fmt_money(-500) == "-¥500", "负数")
	_check(GameData.fmt_money(0) == "¥0", "零")

const NetAddrScript := preload("res://scripts/net_addr.gd")

func _test_endpoint() -> void:
	_check(NetAddrScript.parse_endpoint("10.11.28.88", 7777) == ["10.11.28.88", 7777], "纯 IPv4")
	_check(NetAddrScript.parse_endpoint("10.11.28.88:7800", 7777) == ["10.11.28.88", 7800], "IPv4:端口")
	_check(NetAddrScript.parse_endpoint("::1", 7777) == ["::1", 7777], "纯 IPv6")
	_check(NetAddrScript.parse_endpoint("[::1]:9000", 7777) == ["::1", 9000], "方括号 IPv6:端口")
	_check(NetAddrScript.parse_endpoint("2001:db8::1", 7777) == ["2001:db8::1", 7777], "全球 IPv6")
	_check(NetAddrScript.parse_endpoint("", 7777) == [], "空输入")
	_check(NetAddrScript.parse_endpoint("[::1", 7777) == [], "坏括号")
	# fix/0.14.1：大厅「复制地址」给的是带中文标签的文本，粘进来也要能切出地址
	_check(NetAddrScript.parse_endpoint("局域网 IPv4：10.11.151.104:7791", 7777) == ["10.11.151.104", 7791],
		"带标签的一行切出 IPv4")
	_check(NetAddrScript.parse_endpoint("全球 IPv6（跨网直连）：[2001:da8::1]:7791", 7777) == ["2001:da8::1", 7791],
		"带标签的一行切出 IPv6")
	var blob := "局域网 IPv4：10.11.151.104:7791\n全球 IPv6（跨网直连）：[2001:da8::1]:7791"
	_check(NetAddrScript.parse_endpoint(blob, 7777) == ["2001:da8::1", 7791], "整块多行优先切出 IPv6（跨网）")

func _test_classify() -> void:
	# 回环（展开式 `0:0:0:0:0:0:0:1`，Godot/Windows 实测就是这个）不该出现在任何一类
	var c: Dictionary = NetAddrScript.classify_addresses([
		"0:0:0:0:0:0:0:1", "::1", "fe80:0:0:0:915:a333:7df9:ebd9",
		"127.0.0.1", "169.254.196.125", "0.0.0.0",
		"2001:da8:a012:389:0:0:0:829", "2001:da8:a012:389:5ad4:323e:fbc7:ec94",
		"2001:db8:1:2:3:4:5:6", "fd12:3456:789a::1",
		"10.11.151.104", "8.8.8.8",
	])
	_check(c.pub6.size() == 2, "全球 IPv6 同 /64 去重为 2（实得 %d）" % c.pub6.size())
	_check(c.lan6.size() == 1, "内网(ULA) IPv6 保留 1")
	_check(c.lan4 == ["10.11.151.104"], "局域网 IPv4")
	_check(c.pub4 == ["8.8.8.8"], "公网 IPv4")
	var all: Array = c.lan4 + c.pub4 + c.lan6 + c.pub6
	_check(not all.has("0:0:0:0:0:0:0:1") and not all.has("::1"), "回环（展开式 + 压缩式）都被过滤")

func _test_board_shape() -> void:
	_check(GameData.TILES.size() == 56, "棋盘 56 格（112 的一半）")
	var cs: Array = GameData.corner_indices()
	var cnames := ["start", "jail", "rest", "go_jail"]
	for k in 4:
		_check(GameData.TILES[cs[k]].type == cnames[k], "角格 %d = %s" % [cs[k], cnames[k]])
	var props := 0
	var events := 0
	var items := 0
	var agains := 0
	var rests := 0
	var casinos := 0
	var shops := 0
	for t in GameData.TILES:
		match String(t.type):
			"property":
				props += 1
			"event":
				events += 1
			"item":
				items += 1
			"again":
				agains += 1
			"rest":
				rests += 1
			"casino":
				casinos += 1
			"shop":
				shops += 1
	_check(props == 30, "30 块地产")
	_check(events == 4, "4 个机会格（三类卡池，替代部分纯给钱格）")
	_check(shops == 6, "6 个小卖部格（实机反馈：4 家太少）")
	_check(items == 4, "4 个失物招领格（随机道具替代固定给钱）")
	_check(agains == 2, "2 个特浓咖啡格（再动一次）")
	_check(rests == 5, "5 个休息格（4 空教室 + 角上卧谈会）")
	_check(casinos == 2, "2 个宿舍赌场格")
	# 纯给钱/扣钱格已全部退场：不许再出现 fine / bonus 类型
	var legacy := 0
	for t in GameData.TILES:
		if String(t.type) == "fine" or String(t.type) == "bonus":
			legacy += 1
	_check(legacy == 0, "不再有强制缴费 / 兼职奖励格")
	# 机会格一律叫「机会」（2026-10-09：命运格并入）
	var fate_left := 0
	for t in GameData.TILES:
		if String(t.type) == "event" and String(t.name) != "机会":
			fate_left += 1
	_check(fate_left == 0, "没有还叫「命运」的事件格（实得 %d 格）" % fate_left)
	# 同侧同类格不相邻：扫每段连续空位（相邻的功能空位不该同型）
	var gap_types: Array = []
	for i in GameData.TILES.size():
		if not GameData.is_corner(i) and String(GameData.TILES[i].type) != "property":
			gap_types.append(String(GameData.TILES[i].type))
		else:
			gap_types.append("")
	var adj_dup := 0
	for i in gap_types.size() - 1:
		if gap_types[i] != "" and gap_types[i] == gap_types[i + 1]:
			adj_dup += 1
	_check(adj_dup == 0, "相邻空位不同型（%d 处连排同型）" % adj_dup)
	# 价位是「打乱后固定」的：30 块地拿到的正好是 30 个价位的一个排列，
	# 且**不再**沿路径递增（那正是这次要去掉的排法）
	var pi: Array = _prop_indices()
	var seen := {}
	var mono := true
	var prev := -1
	for i in pi:
		var p := int(GameData.TILES[i].price)
		seen[p] = true
		if p <= prev:
			mono = false
		prev = p
	_check(seen.size() == 30, "30 块地的价位各不相同（实得 %d 种）" % seen.size())
	_check(not mono, "价位不再沿路径递增（已打乱）")
	var flag := {}
	for rank in GameData.PROP_PRICE_ORDER:
		flag[rank] = true
	_check(GameData.PROP_PRICE_ORDER.size() == 30 and flag.size() == 30,
		"PROP_PRICE_ORDER 是 0~29 的一个排列（%d 项 / %d 种）"
		% [GameData.PROP_PRICE_ORDER.size(), flag.size()])
	# 公式与数据必须一致：改 PROP_* 常量时不会忘了同步 TILES
	_check(int(GameData.TILES[pi[0]].price) == GameData.prop_price(GameData.PROP_PRICE_ORDER[0]),
		"第 1 块地价 = 它那一位的档位价")
	_check(int(GameData.TILES[pi[0]].rent) == GameData.prop_rent(GameData.PROP_PRICE_ORDER[0]),
		"第 1 块租金 = 它那一位的档位租")
	# 地产没有 group 字段了（拆分组后不应残留）
	var leftover := 0
	for i in GameData.TILES.size():
		if GameData.TILES[i].type == "property" and GameData.TILES[i].has("group"):
			leftover += 1
	_check(leftover == 0, "地产已无 group 字段（实得 %d 块残留）" % leftover)
	# 事件卡移动步数合法性
	for e in GameData.EVENTS:
		if e.has("move_steps"):
			_check(int(e.move_steps) != 0, "事件移动步数非零")
	# ---- 机会卡池的规模与构成（2026-10-09 批 3 卡表落地；口径见 机会卡.md §四）----
	_check(GameData.EVENTS.size() == 50, "机会卡 50 张（实得 %d）" % GameData.EVENTS.size())
	# 智斗比例：纯经济/位移/通用卡不超过 15 张
	var plain := 0
	for e in GameData.EVENTS:
		var fighting: bool = e.has("steal_from") or e.has("charge_to") or e.has("jail_to") \
			or e.has("each_from_target") or e.has("steal_item_from") or e.has("seize_tile") \
			or e.has("force_buy_tile") or e.has("swap_pos") or e.has("pull_target") \
			or e.has("push_back") or e.has("shuffle_pos") or e.has("choices") \
			or e.has("peek_deck") or e.has("shuffle_deck") or e.has("bury_deck")
		if not fighting:
			plain += 1
	_check(plain <= 15, "智斗卡占多数（纯通用卡 %d 张 ≤ 15）" % plain)
	# 黑市唯一入口必须在
	var black := 0
	for e in GameData.EVENTS:
		if e.has("enter_blackshop"):
			black += 1
	_check(black >= 1, "机会卡池保留黑市入口（黑市的唯一通道）")

func _test_paths() -> void:
	var steps: Array = GameData.compute_path(54, 3)
	_check(steps == [55, 0, 1], "普通移动 54→55→0→1")
	var fwd: Array = GameData.compute_path_steps(10, 5)
	_check(fwd == [11, 12, 13, 14, 15], "事件前进 5 格")
	var back: Array = GameData.compute_path_steps(10, -3)
	_check(back == [9, 8, 7], "事件后退 3 格")
	_check(GameData.compute_path_steps(5, 0).is_empty(), "原地不移动")
	var wrap: Array = GameData.compute_path_steps(1, -2)
	_check(wrap == [0, 55], "倒退跨过起点 1→0→55")
	# 每格都能被 grid 坐标还原（棋盘环线无断点）
	var ok := true
	for i in GameData.TILES.size():
		var g := GameData.grid_of(i)
		if GameData.index_at_grid(g.x, g.y) != i:
			ok = false
	_check(ok, "112 格环线坐标换算闭合")
	# 角格坐标核对（右下/左下/左上/右上）
	var corners2: Array = GameData.corner_indices()
	var expect := [
		Vector2i(GameData.BOARD_COLS - 1, GameData.BOARD_ROWS - 1),
		Vector2i(0, GameData.BOARD_ROWS - 1),
		Vector2i(0, 0),
		Vector2i(GameData.BOARD_COLS - 1, 0),
	]
	var ok2 := corners2.size() == 4
	for k in mini(corners2.size(), 4):
		if GameData.grid_of(corners2[k]) != expect[k]:
			ok2 = false
	_check(ok2, "四角坐标正确")
