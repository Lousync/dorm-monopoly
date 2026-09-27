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
		tiles.append({"owner": -1, "level": 0})
	return tiles

func _test_rent() -> void:
	var tiles := _fresh_tiles()
	_check(GameData.rent_for(8, tiles) == 0, "无主地块租金为 0")
	tiles[8].owner = 1
	_check(GameData.rent_for(8, tiles) == 850, "基础租金")
	tiles[8].level = 2
	_check(GameData.rent_for(8, tiles) == 850 * 3, "等级租金 Lv2")
	tiles[9].owner = 1
	tiles[11].owner = 1
	_check(GameData.rent_for(8, tiles) == 850 * 3 * 2, "集齐餐饮组双倍")
	tiles[9].owner = 2
	_check(GameData.rent_for(8, tiles) == 850 * 3, "组被拆散后取消双倍")
	_check(GameData.upgrade_cost(27) == 2100, "升级费用 = 地价一半")

func _test_fmt() -> void:
	_check(GameData.fmt_money(1234567) == "¥1,234,567", "千分位正数")
	_check(GameData.fmt_money(-500) == "-¥500", "负数")
	_check(GameData.fmt_money(0) == "¥0", "零")

const NetScript := preload("res://scripts/net.gd")

func _test_endpoint() -> void:
	_check(NetScript.parse_endpoint("10.11.28.88", 7777) == ["10.11.28.88", 7777], "纯 IPv4")
	_check(NetScript.parse_endpoint("10.11.28.88:7800", 7777) == ["10.11.28.88", 7800], "IPv4:端口")
	_check(NetScript.parse_endpoint("::1", 7777) == ["::1", 7777], "纯 IPv6")
	_check(NetScript.parse_endpoint("[::1]:9000", 7777) == ["::1", 9000], "方括号 IPv6:端口")
	_check(NetScript.parse_endpoint("2001:db8::1", 7777) == ["2001:db8::1", 7777], "全球 IPv6")
	_check(NetScript.parse_endpoint("", 7777) == [], "空输入")
	_check(NetScript.parse_endpoint("[::1", 7777) == [], "坏括号")

func _test_board_shape() -> void:
	_check(GameData.TILES.size() == 28, "棋盘 28 格")
	var corners := [0, 7, 14, 21]
	var types := []
	for c in corners:
		types.append(GameData.TILES[c].type)
	_check(types == ["start", "jail", "rest", "go_jail"], "四角为 起点/宿委会/卧谈会/查寝")
	var props := 0
	for t in GameData.TILES:
		if t.type == "property":
			props += 1
	_check(props == 18, "18 块地产")
	# 每组 3 块
	var counts := {}
	for t in GameData.TILES:
		if t.has("group"):
			counts[t.group] = counts.get(t.group, 0) + 1
	var all3 := true
	for g in counts:
		if counts[g] != 3:
			all3 = false
	_check(all3 and counts.size() == 6, "6 组各 3 块")

func _test_paths() -> void:
	# 事件移动路径：从 24 走到 15 会经过起点(0)
	var path: Array = GameData.compute_path_to(24, 15)
	_check(path[0] == 25 and path.has(0) and path[path.size() - 1] == 15, "事件移动经过起点")
	var steps: Array = GameData.compute_path(27, 3)
	_check(steps == [0, 1, 2], "普通移动 27→0→1→2")
	var direct: Array = GameData.compute_path_to(5, 5)
	_check(direct.is_empty(), "原地不移动")
