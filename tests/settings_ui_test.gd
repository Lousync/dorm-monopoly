extends SceneTree
## 大厅「游戏设置」弹窗回归（真实 GUI 输入链路）：godot --headless --path . --script tests/settings_ui_test.gd

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
	print("== 大厅游戏设置弹窗 ==")
	# `--script` 主脚本里不能用 `Net.` 标识符（编译期 Identifier not found），
	# 照 tests/hud_test.gd 的写法从 root 取（Task 2 实测踩到）
	var net = root.get_node_or_null("Net")
	if net == null:
		printerr("  FAIL - 未找到 Net autoload"); quit(1); return
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(7798, 3) != OK:
		printerr("server create failed"); quit(1); return
	var mp := MultiplayerAPI.create_default_interface()
	mp.multiplayer_peer = peer
	set_multiplayer(mp, "/root")
	net.players = [{"peer": 1, "name": "甲", "color": 0, "bot": false, "ready": true}]
	var lb = load("res://scenes/lobby.tscn").instantiate()
	root.add_child(lb)
	await create_timer(0.4).timeout

	_check(not lb._set_wrap.visible, "初始不显示设置弹窗")
	lb._settings_btn.pressed.emit()
	_check(lb._set_wrap.visible, "点「游戏设置」弹出设置弹窗")
	var chips: Dictionary = lb._set_chips.get_meta("chips", {})
	_check(chips.size() == 5, "弹窗里 5 个挡位 chip")
	# 顺序守门人：UI 依赖挡位完整顺序，settings_test 只钉了长度与首项
	var ids: Array[String] = []
	for k in chips.keys():
		ids.append(String(k))
	var want: Array[String] = []
	for t in GameSettings.TIERS:
		want.append(String(t))
	_check(str(ids) == str(want), "chip 顺序 = GameSettings.TIERS（实得 %s）" % str(ids))
	chips["30"].pressed.emit()
	_check(lb._set_tier == "30", "点「30 秒」chip 选中 30 秒")
	lb._on_settings_save()
	_check(net.game_settings.timeout_tier == "30", "「确定」后写进 Net.game_settings")
	_check(not lb._set_wrap.visible, "「确定」只保存并关闭弹窗")
	lb._settings_btn.pressed.emit()
	_check(lb._set_tier == "30", "再次打开时回显上次选的挡位")
	lb._set_wrap.visible = false

	# ---- 开局设置面板扩展（经济 / 回合上限 / 胜利条件 / 开关 / 预设 / 钳制） ----
	lb._settings_btn.pressed.emit()
	var rounds: Dictionary = lb._set_rounds_chips.get_meta("chips", {})
	var wins: Dictionary = lb._set_win_chips.get_meta("chips", {})
	_check(rounds.size() == 4 and wins.size() == 3, "回合上限 4 档、胜利条件 3 选")
	rounds["none"].pressed.emit()
	_check(lb._set_rounds == 0, "点「不限」→ max_rounds = 0")
	wins["cash"].pressed.emit()
	_check(lb._set_win == "cash", "点「目标现金」→ win_mode = cash")
	lb._set_cash_edit.text = "abc200000"   # 杂字符被剥掉，数字留出来钳制
	lb._set_salary_edit.text = "4500"
	lb._set_wincash_edit.text = "50000"
	lb._on_settings_save()
	_check(net.game_settings.start_cash == GameSettings.CASH_MAX,
		"起始资金杂字符剥净后越界钳到 99999")
	_check(net.game_settings.max_rounds == 0, "「不限」写进设置（max_rounds = 0）")
	_check(net.game_settings.win_mode == "cash", "胜利条件写进设置（目标现金）")
	_check(net.game_settings.start_salary == 4500 and net.game_settings.win_cash == 50000,
		"补贴与目标现金按输入写进设置")
	# 预设一键填：大富翁 = 起始 4 万、60 轮
	lb._settings_btn.pressed.emit()
	lb._apply_preset("大富翁")
	lb._sync_panel()
	_check(lb._set_cash_edit.text == "40000" and lb._set_rounds == 60, "预设「大富翁」填起始 4 万、60 轮")
	lb._on_settings_save()
	_check(net.game_settings.start_cash == 40000 and net.game_settings.max_rounds == 60,
		"预设值经「确定」写入设置")
	lb._set_wrap.visible = false
	# 「开始游戏！」不再弹设置窗（本测试只有 1 人，can_start 不通过，不会真的换场景）
	lb._start_btn.pressed.emit()
	_check(not lb._set_wrap.visible, "点「开始游戏！」直接开局，不再弹设置弹窗")
	print("SETTINGS UI TEST: %s" % ("PASS" if fails == 0 else "%d FAILURES" % fails))
	quit(0 if fails == 0 else 1)
