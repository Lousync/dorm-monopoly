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

## 往视口里塞一次「按下 + 松开」，走真实 GUI 输入链路（`_input` → GUI 拾取都过一遍）。
## 位置用 `global_position`：失焦兜底那处判据读的也是它（见 `UIKit.release_focus_on_click`）。
func _push_click(vp: Viewport, at: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		vp.push_input(ev)

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

	# ---- 开局设置面板扩展（经济 / 回合上限 / 胜利条件 / 开关 / 钳制） ----
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

	# ---- 开新的一局 ⇒ 开局设置回默认（用户 2026-10-09 拍板：预设方案整段删除，
	#      改成「每次开新的一局都展示默认数值 / 开关，房主自行调整」） ----
	# 前置：上面刚把这一局设成了非默认（起始 99999 / 不限 / 目标现金）——那正是"上一局的残留"
	var before := GameSettings.new()
	_check(net.game_settings.start_cash != before.start_cash and net.game_settings.max_rounds != before.max_rounds,
		"（前置）开房之前，设置里留着上一局改过的非默认值")
	# `host_game` = 开了一个新房间 = 新的一局
	net.host_game(7796)
	_check(net.game_settings.start_cash == before.start_cash
		and net.game_settings.max_rounds == before.max_rounds
		and net.game_settings.win_mode == before.win_mode,
		"开房后开局设置回到默认（起始资金 / 回合上限 / 胜利条件）")
	# 弹窗展示的应当就是这份默认值（不是上一局那套）
	lb._settings_btn.pressed.emit()
	_check(lb._set_cash_edit.text == str(before.start_cash), "弹窗展示默认起始资金")
	_check(lb._set_rounds == before.max_rounds, "弹窗展示默认回合上限")
	lb._set_wrap.visible = false
	# 开局科技等级（2026-10-07）：chip 行 4 档，选「钻石」写进设置
	var tier_chips: Dictionary = lb._set_tech_tier_chips.get_meta("chips", {})
	_check(tier_chips.size() == 4, "科技等级 4 档 chip（随机/白银/黄金/钻石）")
	tier_chips["钻石"].pressed.emit()
	lb._on_settings_save()
	_check(net.game_settings.tech_tier == "钻石", "选「钻石」写进设置（tech_tier）")
	lb._set_wrap.visible = false

	# ---- 输入框失焦回归（用户 2026-10-09 报：鼠标点到别处，聊天框仍高亮） ----
	# 与主菜单同一条根因：按钮一律 FOCUS_NONE、面板不吃键盘焦点 ⇒ 点哪儿 LineEdit 都还攥着
	# 焦点，「focus」样式（金色描边）一直挂着。主菜单 2026-10-08 已补 `_input` 兜底，
	# **大厅漏了同一处** —— 这条钉住它（走 `push_input` 的真实 GUI 链路，不是直接调处理函数）。
	var vp: Viewport = lb.get_viewport()
	lb._chat_edit.grab_focus()
	_check(vp.gui_get_focus_owner() == lb._chat_edit, "聊天输入框点一下拿得到焦点")
	_push_click(vp, Vector2(6, 6))          # 屏幕左上角：落在聊天框之外
	_check(vp.gui_get_focus_owner() != lb._chat_edit, "点聊天框之外 → 收掉焦点（不再高亮）")
	# 设置弹窗里的数字框同理：修的是「场景级」那一处兜底，不是只堵了聊天框这一个口子
	lb._set_wrap.visible = true
	lb._set_cash_edit.grab_focus()
	_check(vp.gui_get_focus_owner() == lb._set_cash_edit, "设置弹窗数字框拿得到焦点")
	_push_click(vp, Vector2(6, 6))
	_check(vp.gui_get_focus_owner() != lb._set_cash_edit, "点数字框之外 → 收掉焦点")
	lb._set_wrap.visible = false

	# 「开始游戏！」不再弹设置窗（本测试只有 1 人，can_start 不通过，不会真的换场景）
	lb._start_btn.pressed.emit()
	_check(not lb._set_wrap.visible, "点「开始游戏！」直接开局，不再弹设置弹窗")
	print("SETTINGS UI TEST: %s" % ("PASS" if fails == 0 else "%d FAILURES" % fails))
	quit(0 if fails == 0 else 1)
