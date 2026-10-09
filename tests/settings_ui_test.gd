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

## 往视口里塞一次「移动 + 按下 + 松开」，走真实 GUI 输入链路（`_input` 与 GUI 拾取都过一遍）。
##
## **两处非显然的坑（都实测踩过）**：
##   * `in_local_coords = true` —— 坐标直接按画布空间算，不经窗口→画布的拉伸变换；
##     而 headless 下**根视口只有 64 × 64**（不是项目设的 1280 × 800），
##     于是默认的 false 会把落点算到视口外、事件被直接丢掉 ⇒ 什么都点不中。
##     所以本测试开头先 `root.size = Vector2i(1280, 800)` 把画布撑开（同 `pause_menu_test`）。
##   * 先推一次 `InputEventMouseMotion`：让 Viewport 先把 hover 算出来（与 `pause_menu_test` 同）。
func _push_click(vp: Viewport, at: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = at
	mv.global_position = at
	vp.push_input(mv, true)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		ev.pressed = pressed
		ev.position = at
		ev.global_position = at
		vp.push_input(ev, true)

## 点某个控件的正中（走真实 GUI 拾取，与真机点一下等价）。
## ⚠ 控件必须**真的在可视区内** —— `ScrollContainer` 会把滚出可视区的子节点裁掉，
## 那种控件点不到（本次实测踩到：点第四节里的小卖部开关，怎么点都没反应）。
func _click_control(vp: Viewport, c: Control) -> void:
	_push_click(vp, c.get_global_rect().get_center())

func _run() -> void:
	print("== 大厅游戏设置弹窗 ==")
	# headless 的根视口默认只有 64 × 64 ⇒ 先撑成项目设定的画布尺寸，否则点哪儿都点不中
	root.size = Vector2i(1280, 800)
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
	# 「现状」那一档**不是统一的秒数**（各环节各自沿用原值）⇒ 必须挂悬停说明，否则会被读成
	# "现状 = 25 秒"（用户 2026-10-09 就是这么问的）。文案只有一份来源。
	var cur_chip: Button = chips[GameSettings.TIER_CURRENT]
	_check(cur_chip.tooltip_text == GameSettings.TIER_CURRENT_HINT and not cur_chip.tooltip_text.is_empty(),
		"「现状」chip 挂着悬停说明（GameSettings.TIER_CURRENT_HINT）")
	_check(cur_chip.tooltip_text.contains("35") and cur_chip.tooltip_text.contains("12"),
		"悬停说明里列出了各环节的原值（掷轮 35 / 道具 12 …）")
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
	_check(rounds.size() == 5 and wins.size() == 3, "回合上限 5 档、胜利条件 3 选")
	# 档位守门人（2026-10-09 改为 30/45/60/80/不限）：新档在、旧档 90 不在
	_check(rounds.has("45") and rounds.has("80") and not rounds.has("90"),
		"回合上限档位 = 30/45/60/80/不限（45、80 是新档，90 已换掉）")
	rounds["none"].pressed.emit()
	_check(lb._set_rounds == 0, "点「不限」→ max_rounds = 0")
	# 目标现金金额**只在「目标现金」模式下显示**（用户 2026-10-09）
	_check(not lb._set_wincash_row.visible, "默认「总资产排名」⇒ 目标现金那一行不显示")
	wins["cash"].pressed.emit()
	_check(lb._set_win == "cash", "点「目标现金」→ win_mode = cash")
	_check(lb._set_wincash_row.visible, "选中「目标现金」⇒ 金额那一行出现")
	wins["last"].pressed.emit()
	_check(not lb._set_wincash_row.visible, "换回「最后存活」⇒ 金额那一行又收起")
	wins["cash"].pressed.emit()   # 复位：下面几条要 win = cash
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
	# 破产变卖：条目名与比例（用户 2026-10-09）。比例**必须来自 GameData.LIQ_RATE** ——
	# 写死的话改比例时这行就骗人了（同 TRUST_FUND 那条教训），所以这里钉的是"读常量"本身。
	var liq_lbl := lb._set_liq_sw.get_parent().get_child(0) as Label
	_check(liq_lbl != null and liq_lbl.text.begins_with("破产变卖："),
		"条目名已改为「破产变卖」（实得 %s）" % (liq_lbl.text if liq_lbl != null else "<无>"))
	_check(liq_lbl != null and liq_lbl.text.contains("%d%%" % int(round(GameData.LIQ_RATE * 100.0)))
		and not liq_lbl.text.contains("30%"),
		"回收比例读的是 GameData.LIQ_RATE（现 %d%%），不是写死的旧值" % int(round(GameData.LIQ_RATE * 100.0)))
	# 2026-10-10 科技调整：分节名去掉「开局」这个**系统名**限定（「开局」降为「当前唯一的获得时机」）。
	# 标题不是子节点、是 `SectionBox._draw()` 里画的 ⇒ 只能按私成员名读回（本仓 SectionBox 无 accessor）。
	# ⚠ 必须显式标 `Node`：`lb` 是 `instantiate()` 的无类型返回值 ⇒ `lb._set_tech_sw` 是 Variant，
	# 链式 `get_parent()` 拿不到返回类型，`:=` 会以「Cannot infer the type」编译失败。
	var tech_sec: Node = lb._set_tech_sw.get_parent().get_parent().get_parent()
	_check(tech_sec != null and String(tech_sec.get("_text")) == "科技",
		"设置弹窗分节名 = 「科技」（实得「%s」）" % String(tech_sec.get("_text")))
	# 科技：默认**开**（用户 2026-10-09），等级选择跟着开关显隐
	_check(lb._set_tech_sw.on and lb._set_tech_tier_box.visible,
		"科技默认开 ⇒ 开关是开、等级选择可见")
	var tier_chips: Dictionary = lb._set_tech_tier_chips.get_meta("chips", {})
	_check(tier_chips.size() == 4, "科技等级 4 档 chip（随机/白银/黄金/钻石）")
	_check(String(tier_chips[GameSettings.TECH_TIER_RANDOM].text) == "随机",
		"「随机」档文案 = 随机（去掉了「（掷骰）」）")
	# 开关的显隐联动：这里**不改用真实点击** —— 科技那一节在滚动区下方、被 ScrollContainer
	# 裁掉，点不到（本文件开头那段注释里的坑）。改发它对外的那枚 `toggled` 信号，
	# 与真机点击走的是同一条回调（`_set_tech_sw` 的 on_change）。
	lb._set_tech_sw.set_on(false)
	lb._set_tech_sw.toggled.emit(false)
	_check(not lb._set_tech and not lb._set_tech_tier_box.visible, "关掉科技开关 ⇒ 等级选择收起")
	lb._set_tech_sw.set_on(true)
	lb._set_tech_sw.toggled.emit(true)
	_check(lb._set_tech and lb._set_tech_tier_box.visible, "再打开 ⇒ 等级选择又露出")
	tier_chips["钻石"].pressed.emit()
	lb._on_settings_save()
	_check(net.game_settings.tech_tier == "钻石" and net.game_settings.tech_on,
		"选「钻石」写进设置（tech_tier，且 tech_on 仍为开）")
	lb._set_wrap.visible = false

	# ---- 开关组件（on/off 的行由「关 / 开」两枚 chip 换成 UIKit.Switch，用户 2026-10-09） ----
	# ⚠ 用**第一节「经济」里那个**开关：它在滚动区的可视范围内。点更靠下那些（小卖部…）
	# 会被 `ScrollContainer` 裁掉 ⇒ 点在可视区外、GUI 拾取根本递不到它（本次实测踩到）。
	var vp: Viewport = lb.get_viewport()
	lb._settings_btn.pressed.emit()
	# ⚠ 必须**等一帧**：弹窗刚 `visible = true`，容器布局还没重算 ⇒ 立刻读 `get_global_rect()`
	# 拿到的是过期落点，点过去自然什么都点不中（本次实测踩到）。
	await create_timer(0.1).timeout
	_check(lb._set_liq_sw != null and lb._set_liq_sw.on, "破产变卖保底开关初始为开")
	_click_control(vp, lb._set_liq_sw)
	_check(not lb._set_liq_sw.on and not lb._set_liq, "点开关 → 翻成关、并写回 _set_liq")
	_click_control(vp, lb._set_liq_sw)
	_check(lb._set_liq_sw.on and lb._set_liq, "再点一下 → 翻回开")
	# 回显：`_sync_panel()` 要能把开关刷成 `_set_*` 的值（`animate = false`，不带滑动）
	lb._set_shop = false
	lb._sync_panel()
	_check(not lb._set_shop_sw.on, "`_sync_panel` 把开关刷成关")
	lb._set_shop = true
	lb._sync_panel()
	_check(lb._set_shop_sw.on, "`_sync_panel` 把开关刷成开")
	# 翻成关之后经「确定」写进设置
	_click_control(vp, lb._set_liq_sw)
	lb._on_settings_save()
	_check(not net.game_settings.liq_on, "开关注：关 → 「确定」写进设置（liq_on）")
	lb._set_wrap.visible = false

	# ---- 输入框失焦回归（用户 2026-10-09 报：鼠标点到别处，聊天框仍高亮） ----
	# 与主菜单同一条根因：按钮一律 FOCUS_NONE、面板不吃键盘焦点 ⇒ 点哪儿 LineEdit 都还攥着
	# 焦点，「focus」样式（金色描边）一直挂着。主菜单 2026-10-08 已补 `_input` 兜底，
	# **大厅漏了同一处** —— 这条钉住它（走 `push_input` 的真实 GUI 链路，不是直接调处理函数）。
	lb._chat_edit.grab_focus()
	_check(vp.gui_get_focus_owner() == lb._chat_edit, "聊天输入框点一下拿得到焦点")
	_push_click(vp, Vector2(6, 6))          # 屏幕左上角：落在聊天框之外
	_check(vp.gui_get_focus_owner() != lb._chat_edit, "点聊天框之外 → 收掉焦点（不再高亮）")
	# 设置弹窗里的数字框同理：修的是「场景级」那一处兜底，不是只堵了聊天框这一个口子
	lb._set_wrap.visible = true
	await create_timer(0.1).timeout      # 同上：等布局落定，`get_global_rect()` 才算数
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
