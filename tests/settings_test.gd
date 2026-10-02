extends SceneTree
## 开局设置单测（操作限时挡位）：godot --headless --path . --script tests/settings_test.gd
## 口径见 doc/game-design/开局设置.md §三之一。

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
	_test_rules_text()     # 纯静态，无引擎依赖
	_test_broadcast()
	_test_in_game_tier()   # 无 await，直接调
	await _test_window()   # 协程：不等它跑完 quit() 会先执行，断言全部落空（假绿）
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
	# s_state 的同步分支：快照里的挡位变化要落进本地 _settings（房主 call_local 与客户端同一段代码）
	g.s_state({"phase": "playing", "round": 1, "max_rounds": 30, "turn": 1,
		"players": [], "tiles": [], "timeout_tier": "60"})
	_check(g._settings.timeout_tier == "60", "快照挡位由 30 变 60 → 本地 _settings 同步")
	g.queue_free()

func _test_in_game_tier() -> void:
	var g := _host_game(7799)
	if g == null:
		return
	g._refresh_tier_ui()
	_check(g.tier_row.visible, "房主看得到可点的挡位 chips")
	_check(not g.tier_readonly.visible, "房主不显示只读行")
	# 小标题只跟 chips 一侧显隐：否则客户端会看到「操作限时」小标题 + 只读行两行同义文本
	_check(g.tier_title.visible == g.tier_row.visible, "小标题与 chips 同步显隐")
	# g 是 Node 类型，动态属性访问返回 Variant，不能写 `:=`（类型推不出来）
	var rev: int = g._timeout_rev
	g._set_timeout_tier("30")
	_check(g._settings.timeout_tier == "30", "点挡位写进 settings")
	_check(g._timeout_rev == rev + 1, "改挡位 → _timeout_rev +1（触发重计时）")
	_check(String(g.st.get("timeout_tier", "")) == "30", "改挡位 → 快照同步")
	_check(g.tier_readonly.text.begins_with("操作限时：30 秒"), "只读行文案跟随挡位")
	g._set_timeout_tier("bogus")
	_check(g._settings.timeout_tier == "30", "非法挡位被拒（回落靠 GameSettings）")
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

## 规则说明文案必须跟着挡位走：非默认档下不能再说「35 秒不掷」这类现状秒数。
## 纯静态（只读 RulesText 的字符串），不依赖引擎与对局。
func _test_rules_text() -> void:
	var none_body := ""
	for pg in RulesText.pages(GameSettings.TIER_NONE):
		none_body += String(pg.body)
	_check(none_body.contains("不限时"), "不限时档：规则正文含「不限时」")
	_check(not none_body.contains("35"), "不限时档：规则正文不含「35」（不写死现状秒数）")
	var t15_body := ""
	for pg in RulesText.pages("15"):
		t15_body += String(pg.body)
	_check(t15_body.contains("15"), "15 秒档：规则正文含「15」")

## 探针：跑一次 _await_turn_window，结果写进 out[0]，arm 次数写进 arm[0]
func _probe(g: Node, kind: String, alive_ref: Array, out: Array, arm: Array) -> void:
	# g 是 Node 类型，动态调用返回 Variant，不能写 `:=`（类型推不出来）
	var r: bool = await g._await_turn_window(kind,
		func() -> bool: return bool(alive_ref[0]),
		func(_sec: float) -> void: arm[0] = int(arm[0]) + 1)
	out[0] = r

func _test_window() -> void:
	var g := _host_game(7797)
	if g == null:
		return
	# _await_turn_window 以 running 为前置，必须把它打开；但不能立刻打开：
	# _host_setup() 同步把 running 设回 true 后又 `await _wait(1.5)` → _broadcast_state()
	# → _run_game()，而 _run_game 只在首个 await（再 0.3 秒）之后才判 `while running`。
	# 若此刻就把 running 设真，t0+1.5s 时那个循环会真的开跑 _play_turn(甲)——今天的绿灯纯属侥幸。
	# 所以先让它死透（1.9s > 1.5+0.3），再打开，只为满足探针的前置条件。
	g.running = false
	await create_timer(1.9).timeout
	g.running = true

	# 不限时：不会托管；环节一结束立刻返回 false
	g._settings.timeout_tier = GameSettings.TIER_NONE
	var alive := [true]
	var out := [null]
	var arm := [0]
	_probe(g, "roll", alive, out, arm)
	await create_timer(0.6).timeout
	_check(out[0] == null, "不限时：0.6 秒内不自动托管")
	_check(int(arm[0]) == 1, "不限时：窗口只 arm 一次")
	alive[0] = false
	await create_timer(0.5).timeout
	_check(out[0] == false, "不限时：环节结束后返回 false")

	# 固定档：不会提前托管；挡位一变就重计时（on_arm 再被调一次）
	g._settings.timeout_tier = "60"
	var alive2 := [true]
	var out2 := [null]
	var arm2 := [0]
	_probe(g, "roll", alive2, out2, arm2)
	await create_timer(0.3).timeout
	_check(int(arm2[0]) == 1, "60 秒档：窗口 arm 一次")
	g._timeout_rev += 1
	await create_timer(0.4).timeout
	_check(int(arm2[0]) == 2, "挡位变化 → 按新值重计时（重新 arm）")
	_check(out2[0] == null, "60 秒档不会提前托管")
	alive2[0] = false
	await create_timer(0.5).timeout
	_check(out2[0] == false, "固定档：环节结束后返回 false")

	# 到点真该托管：15 秒档靠 Engine.time_scale 压成不到 1 秒真实时间
	# （_wait 走 SceneTree 计时器、吃 time_scale；本段自己的等待用 ignore_time_scale 免被压缩）
	Engine.time_scale = 20.0
	g._settings.timeout_tier = "15"
	var alive3 := [true]
	var out3 := [null]
	var arm3 := [0]
	_probe(g, "roll", alive3, out3, arm3)
	await create_timer(2.0, true, false, true).timeout
	_check(out3[0] == true, "15 秒档：到点返回 true（该自动托管）")
	_check(int(arm3[0]) == 1, "15 秒档：到点前只 arm 一次")
	Engine.time_scale = 1.0
	# 守门断言：上面打开 running 只是为了满足探针的前置条件，对局循环必须仍是死的。
	# 旧写法在 t0 就把 running 设真 → t0+1.8s 起 _run_game 会真的跑 _play_turn(甲)，
	# 那一步会推进 _roll_epoch（只增不减）——这条断言就是拿来钉住它的。
	_check(g._roll_epoch == 0, "对局循环未开跑（running 只是探针前置条件）")
	g.queue_free()
