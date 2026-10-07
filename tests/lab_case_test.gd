extends SceneTree
## 道具试验场用例保存/回放（⑭）：存 → 改动 → 回放 → 逐项还原
## godot --headless --path . --script tests/lab_case_test.gd
##
## 只测 `LabCase`（序列化 / 注入），不拉整个试验场场景 —— 与 `item_lab.gd` 共用同一套
## `lab_mode` 的 `game`（真实玩法逻辑、不跑回合循环），保证注入面与真实沙盒一致。

var fails := 0

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

func _run() -> void:
	print("== 道具试验场用例保存/回放（⑭） ==")
	var net = root.get_node_or_null("Net")
	if net == null:
		printerr("  FAIL - 未找到 Net autoload"); quit(1); return
	# 一个本机 server：`_broadcast_state()` 的 `s_state.rpc` 需要多人在位（无 client 也可）。
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(7799, 3) != OK:
		printerr("  FAIL - server create failed"); quit(1); return
	var mp := MultiplayerAPI.create_default_interface()
	mp.multiplayer_peer = peer
	set_multiplayer(mp, "/root")
	net.players = [
		{"peer": 1, "name": "房主", "color": 0, "bot": false, "ready": true},
		{"peer": -1, "name": "机器人A", "color": 1, "bot": true, "ready": true},
		{"peer": -2, "name": "机器人B", "color": 2, "bot": true, "ready": true},
		{"peer": -3, "name": "机器人C", "color": 3, "bot": true, "ready": true},
	]
	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.enter_lab_mode()
	g.lab_reset()
	await process_frame

	# 造一个有特征的状态（含实例字段：黑卡 charges）
	g.hp[0].money = 12345
	g.hp[0].stamina = 2
	g.hp[0].pos = 7
	g.hp[0].items = [{"id": "招财猫", "cd": 0}, {"id": "黑卡", "cd": 3, "charges": 2}]
	g.htiles[3].owner = 1
	g.htiles[3].level = 2
	g.htiles[9].soil = true
	g.refresh_count = 4
	g.round_no = 6
	g.items_consumed = {"蛋蛋节": true}
	var shop_key := int((g.shops.keys() as Array)[0])
	g.shops[shop_key] = {"slots": ["招财猫", "黑卡", ""]}

	var path := LabCase.save("unit_case", g)
	_check(path != "" and FileAccess.file_exists(path), "用例已写入 %s" % path)

	# 打乱：把状态改掉，再回放
	g.hp[0].money = 0
	g.hp[0].items = []
	g.htiles[3].owner = GameData.NO_OWNER
	g.htiles[9].soil = false
	g.refresh_count = 0
	g.round_no = 1
	g.items_consumed = {}
	g.shops = {}
	LabCase.apply(g, LabCase.load_data("unit_case"))

	_check(int(g.hp[0].money) == 12345, "钱还原（实得 %d）" % int(g.hp[0].money))
	_check(int(g.hp[0].stamina) == 2 and int(g.hp[0].pos) == 7, "体力 / 位置还原")
	_check(g.hp[0].items.size() == 2 and String(g.hp[0].items[1].id) == "黑卡"
		and int(g.hp[0].items[1].charges) == 2 and int(g.hp[0].items[1].cd) == 3,
		"背包（含 charges / cd 实例字段）还原")
	_check(int(g.htiles[3].owner) == 1 and int(g.htiles[3].level) == 2, "地块 owner / level 还原")
	_check(bool(g.htiles[9].soil), "焦土还原")
	_check(int(g.refresh_count) == 4 and int(g.round_no) == 6, "刷新数 / 回合还原")
	_check(bool(g.items_consumed.get("蛋蛋节", false)), "items_consumed 还原")
	_check(g.shops.has(shop_key) and String(g.shops[shop_key].slots[1]) == "黑卡", "货架还原")

	# 文件名消毒：路径穿越被挡（不许留 / 与 ..）
	var safe := LabCase.safe_name("../../etc/passwd")
	_check(not safe.contains("/") and not safe.contains(".."), "文件名消毒（无 / 与 ..，实得 '%s'）" % safe)

	# 清理测试用例（不进仓库、不留垃圾）
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	net.players = []
	g.free()
	if fails == 0:
		print("LAB CASE TEST: ALL PASS")
	else:
		print("LAB CASE TEST: %d FAILURES" % fails)
	quit(0 if fails == 0 else 1)
