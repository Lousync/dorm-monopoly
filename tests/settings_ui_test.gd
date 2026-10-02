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
	# 「开始游戏！」不再弹设置窗（本测试只有 1 人，can_start 不通过，不会真的换场景）
	lb._start_btn.pressed.emit()
	_check(not lb._set_wrap.visible, "点「开始游戏！」直接开局，不再弹设置弹窗")
	print("SETTINGS UI TEST: %s" % ("PASS" if fails == 0 else "%d FAILURES" % fails))
	quit(0 if fails == 0 else 1)
