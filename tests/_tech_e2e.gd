extends SceneTree
## 科技真实开局链路验证（辅助脚本，不进 CI 套件清单）：
## 模拟真实开房（ENet 服务器 + Net.players 1 真人 2 机器人）→ 对局场景自然 _host_setup
## → 科技阶段开启 → 房主（peer 1）收到选卡弹层 → 走真按钮链路应答 → 全员拿到科技。
## 跑法：godot --headless --path . --script tests/_tech_e2e.gd

var fails := 0

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)
	create_timer(45.0).timeout.connect(func() -> void:
		printerr("TECH E2E: WATCHDOG TIMEOUT")
		quit(1))

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

func _run() -> void:
	seed(20261005)
	var mp := ENetMultiplayerPeer.new()
	if mp.create_server(7796, 3) != OK:
		printerr("TECH E2E: cannot create server")
		quit(1)
		return
	root.multiplayer.multiplayer_peer = mp
	# `--script` 主脚本里不能用 `Net.` 标识符（编译期 Identifier not found），走节点取
	var net = root.get_node_or_null("Net")
	if net == null:
		printerr("  FAIL - 未找到 Net autoload")
		quit(1)
		return
	# 真实开局口径：Net.players 1 真人（peer 1）+ 2 机器人；设置在对局 _ready 拷贝前置好
	net.players = [
		{"peer": 1, "name": "房主", "color": 0, "bot": false},
		{"peer": -1, "name": "机器人A", "color": 1, "bot": true},
		{"peer": -2, "name": "机器人B", "color": 2, "bot": true},
	]
	net.game_settings.tech_on = true
	net.game_settings.ab_freq = "关"
	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	await process_frame
	if g.board == null:
		printerr("对局场景未正确加载（脚本编译失败？）")
		quit(1)
		return

	# 等房主的选卡弹层出现（_host_setup 1.5s 节拍 + 科技阶段全员同时选卡）
	var waited := 0.0
	while waited < 12.0 and g._tech_offer_layer == null:
		await create_timer(0.25).timeout
		waited += 0.25
	_check(g._tech_offer_layer != null, "真实开局链路：房主收到选卡弹层（等待 %.2fs）" % waited)
	_check(String(g._tech_tier) in TechData.TIERS, "本局档位合法（随机定档，必落在 TechData.TIERS 内）")
	_check(g._tech_names_for(1).size() == 3, "房主拿到 3 个候选")
	if g._tech_offer_layer == null:
		printerr("TECH E2E: 弹层未出现，中止")
		quit(1)
		return

	# 走真按钮链路应答：程序化选中第 0 张 + 点「确定」
	var my_offer: Array = g._tech_names_for(1).duplicate()
	g._tech_pick_card(0)
	_check(bool(g._tech_ok.disabled) == false, "选中后「确定」点亮")
	g._tech_ok.pressed.emit()

	# 等科技阶段收尾：三个玩家都有 techs，弹层已收
	waited = 0.0
	while waited < 8.0:
		var done := true
		for p in g.hp:
			if (p.get("techs", []) as Array).is_empty():
				done = false
		if done and not bool(g._tech_open):
			break
		await create_timer(0.25).timeout
		waited += 0.25
	var all_tech := true
	for p in g.hp:
		if (p.get("techs", []) as Array).is_empty():
			all_tech = false
	_check(all_tech, "全员都拿到科技（房主选了「%s」）" % String(my_offer[0]))
	_check(g._tech_offer_layer == null, "应答后选卡弹层已收")
	g.running = false   # 冻结后续回合循环，安静退出

	if fails == 0:
		print("TECH E2E: ALL PASS")
	else:
		printerr("TECH E2E: %d FAILURES" % fails)
	quit(1 if fails > 0 else 0)
