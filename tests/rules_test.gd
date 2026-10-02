extends SceneTree
## 规则单元测试：godot --headless --script tests/rules_test.gd

var fails := 0

func _initialize() -> void:
	_test_rent()
	_test_fmt()
	_test_endpoint()
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

func _test_board_shape() -> void:
	_check(GameData.TILES.size() == 56, "棋盘 56 格（112 的一半）")
	var cs: Array = GameData.corner_indices()
	var cnames := ["start", "jail", "rest", "go_jail"]
	for k in 4:
		_check(GameData.TILES[cs[k]].type == cnames[k], "角格 %d = %s" % [cs[k], cnames[k]])
	var props := 0
	var events := 0
	var fines := 0
	var bonus := 0
	var rests := 0
	var casinos := 0
	var shops := 0
	for t in GameData.TILES:
		match String(t.type):
			"property":
				props += 1
			"event":
				events += 1
			"fine":
				fines += 1
			"bonus":
				bonus += 1
			"rest":
				rests += 1
			"casino":
				casinos += 1
			"shop":
				shops += 1
	_check(props == 30, "30 块地产")
	_check(events == 2, "2 个机会/命运格（原有 4 格改小卖部）")
	_check(shops == 4, "4 个小卖部格")
	_check(fines == 4, "4 个缴费格")
	_check(bonus == 6, "6 个兼职/奖励格")
	_check(rests == 5, "5 个休息格（4 空教室 + 角上卧谈会）")
	_check(casinos == 2, "2 个宿舍赌场格")
	# 30 块地沿路径由便宜到贵：价格与租金都严格递增（不再有分组与成套翻倍）
	var mono := true
	var prev_p := -1
	var prev_r := -1
	for i in GameData.TILES.size():
		if GameData.TILES[i].type != "property":
			continue
		var p := int(GameData.TILES[i].price)
		var r := int(GameData.TILES[i].rent)
		if p <= prev_p or r <= prev_r:
			mono = false
		prev_p = p
		prev_r = r
	_check(mono, "地价与租金沿路径严格递增")
	# 公式与数据必须一致：改 PROB_* 常量时不会忘了同步 TILES
	var pi: Array = _prop_indices()
	_check(int(GameData.TILES[pi[0]].price) == GameData.prop_price(0)
		and int(GameData.TILES[pi[29]].price) == GameData.prop_price(29),
		"首末地价与 prop_price 公式一致")
	_check(int(GameData.TILES[pi[pi.size() - 1]].rent) == GameData.prop_rent(pi.size() - 1),
		"末块租金与 prop_rent 公式一致")
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
