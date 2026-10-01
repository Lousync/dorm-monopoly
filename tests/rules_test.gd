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

## 找某组的所有地产下标（按路径序）
func _group_indices(group: String) -> Array:
	var out := []
	for i in GameData.TILES.size():
		if GameData.TILES[i].get("group", "") == group:
			out.append(i)
	return out

func _test_rent() -> void:
	var idxs: Array = _group_indices("canteen")
	_check(idxs.size() == 3 or idxs.size() == 6, "餐饮组存在")
	var a: int = idxs[0]
	var tiles := _fresh_tiles()
	_check(GameData.rent_for(a, tiles) == 0, "无主地块租金为 0")
	tiles[a].owner = 1
	var base: int = GameData.TILES[a].rent
	_check(GameData.rent_for(a, tiles) == base, "基础租金")
	tiles[a].level = 2
	_check(GameData.rent_for(a, tiles) == base * 3, "等级租金 Lv2")
	for j in idxs:
		tiles[j].owner = 1
	_check(GameData.rent_for(a, tiles) == base * 3 * 2, "集齐整组双倍")
	tiles[idxs[1]].owner = 2
	_check(GameData.rent_for(a, tiles) == base * 3, "组被拆散后取消双倍")
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
	var groups := {}
	for t in GameData.TILES:
		match String(t.type):
			"property":
				props += 1
				groups[t.group] = groups.get(t.group, 0) + 1
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
	var all3 := groups.size() == 10
	for g in groups:
		if groups[g] != 3:
			all3 = false
	_check(all3, "10 组各 3 块地产")
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
