extends SceneTree
## 开局设置单测（操作限时挡位）：godot --headless --path . --script tests/settings_test.gd
## 口径见 docs/gameplay/开局设置.md §三之一。

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
	print("== 操作限时挡位 ==")
	_test_mapping()
	_test_broadcast()
	print("SETTINGS TEST: %s" % ("PASS" if fails == 0 else "%d FAILURES" % fails))
	quit(0 if fails == 0 else 1)

func _mk_player(peer: int, nm: String) -> Dictionary:
	return {"peer": peer, "name": nm, "color": peer - 1, "bot": false, "money": 5000,
		"pos": 0, "alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [],
		"item_used": false, "cheat_roll": -1}

## 起一个房主对局实例；running 关掉，只测状态快照（不跑自动回合循环）。
## 顺序照抄 tests/shop_test.gd：先起服务器再挂节点，_host_setup() 里的
## `await _wait(1.5)` 之后 running 已是 false，_run_game() 直接退出。
func _host_game(port: int) -> Node:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, 3) != OK:
		printerr("server create failed"); quit(1); return null
	var mp := MultiplayerAPI.create_default_interface()
	mp.multiplayer_peer = peer
	set_multiplayer(mp, "/root")
	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.my_peer = 1
	g.running = false
	g.hp = [_mk_player(1, "甲")]
	g.htiles = []
	for i in GameData.TILES.size():
		g.htiles.append({"owner": GameData.NO_OWNER, "level": 0})
	return g

func _test_broadcast() -> void:
	var g := _host_game(7796)
	if g == null:
		return
	g._broadcast_state()
	_check(String(g.st.get("timeout_tier", "")) == GameSettings.TIER_CURRENT,
		"开局快照带 timeout_tier = 现状")
	g._settings.timeout_tier = "30"
	g._broadcast_state()
	_check(String(g.st.get("timeout_tier", "")) == "30", "房主改挡后快照同步为 30")
	# GameSettings.copy() 的首个消费方：房主拿的是副本，对局内改挡不回写大厅
	# （autoload 标识符在 --script 主脚本里编译不过，按 hud_test 的写法运行时取节点）
	var lobby := root.get_node_or_null("Net")
	_check(lobby != null, "测试环境能取到 autoload Net")
	_check(g._settings != lobby.game_settings, "房主用配置副本，非 autoload 同一对象")
	_check(lobby.game_settings.timeout_tier == GameSettings.TIER_CURRENT, "对局内改挡不回写大厅")
	g.queue_free()

func _test_mapping() -> void:
	var cur := GameSettings.TIER_CURRENT
	# 现状档 = 各环节原常量（默认行为与今天完全一致）
	_check(GameSettings.turn_seconds(cur, "roll") == GameData.ROLL_TIMEOUT, "现状·掷轮 = ROLL_TIMEOUT")
	_check(GameSettings.turn_seconds(cur, "prompt") == GameData.PROMPT_TIMEOUT, "现状·决策 = PROMPT_TIMEOUT")
	_check(GameSettings.turn_seconds(cur, "item") == ItemData.ITEM_TIMEOUT, "现状·道具 = ITEM_TIMEOUT")
	_check(GameSettings.turn_seconds(cur, "shop") == ItemData.SHOP_TIMEOUT, "现状·逛店 = SHOP_TIMEOUT")
	_check(GameSettings.turn_seconds(cur, "black") == ItemData.BLACK_TIMEOUT, "现状·黑市 = BLACK_TIMEOUT")
	# 固定档：每个环节各自取该秒数
	for kind in ["roll", "prompt", "item", "shop", "black"]:
		_check(GameSettings.turn_seconds("15", kind) == 15.0, "15 秒档·%s" % kind)
		_check(GameSettings.turn_seconds("30", kind) == 30.0, "30 秒档·%s" % kind)
		_check(GameSettings.turn_seconds("60", kind) == 60.0, "60 秒档·%s" % kind)
		_check(GameSettings.turn_seconds(GameSettings.TIER_NONE, kind) == 0.0, "不限时档·%s" % kind)
	# 未知挡位回落现状
	_check(GameSettings.turn_seconds("bogus", "roll") == GameData.ROLL_TIMEOUT, "未知挡位回落现状")
	# 挡位清单与标签齐备（UI 依赖）
	_check(GameSettings.TIERS.size() == 5 and GameSettings.TIERS[0] == cur, "挡位清单 5 项、首位是现状")
	for t in GameSettings.TIERS:
		_check(GameSettings.TIER_LABELS.has(t), "挡位 %s 有中文标签" % t)
