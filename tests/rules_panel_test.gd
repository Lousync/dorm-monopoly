extends SceneTree
## 「📖 规则说明」回归（fix/v0.1.0；**面板当时在左下角 —— 批次 13 ① 已搬到右上角**，
## 「左下角」只作这条用例写下时的落点留痕，别照它找面板）
##   -- 原「操作提示」已收进规则面板；面板必须真的能展开 / 收起 / 换页
## 走真实 GUI 输入链路（Viewport.push_input），钉的正是「按钮点了没反应」这类问题。
## godot --headless --path . --script tests/rules_panel_test.gd

var fails := 0

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

## 见 tests/pause_menu_test.gd 的同名函数说明
## （in_local_coords=true：坐标按画布空间算，headless 下窗口尺寸与画布不一致）
## 控件为空时直接返回：脚本错误会中断协程，quit() 就再也走不到，
## 整个 SceneTree 会一直挂着（本测试第一版就这么卡死过一次）。
func _click(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	var vp := control.get_viewport()
	var pos := control.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	vp.push_input(mv, true)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		vp.push_input(ev, true)

func _run() -> void:
	root.size = Vector2i(1280, 800)
	# --script 模式下 autoload 不能按全局名引用（编译期尚未注册），运行时从 root 取
	var net = root.get_node_or_null("Net")
	if net != null:
		# 摆一份名册：否则 _host_setup 会对着空 hp 调 _broadcast_state 报错，
		# 噪音会盖住真正的失败；顺带让场景更接近实机（4 人桌）
		net.players = [
			{"peer": 1, "name": "我", "color": 0, "bot": false, "ready": true},
			{"peer": 2, "name": "乙", "color": 1, "bot": true, "ready": true},
			{"peer": 3, "name": "丙", "color": 2, "bot": true, "ready": true},
			{"peer": 4, "name": "丁", "color": 3, "bot": true, "ready": true},
		]
	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.running = false
	for i in 4:
		await process_frame
	await create_timer(0.4).timeout

	print("== 文案数据（RulesText）==")
	var pages: Array = RulesText.pages()
	_check(pages.size() >= 4, "至少 4 页规则（实得 %d）" % pages.size())
	var empty: Array = []
	var leaked: Array = []   # 格式化漏网的占位符，说明 % 拼接写错了
	for p in pages:
		var body := String(p.body)
		if body.strip_edges() == "":
			empty.append(String(p.title))
		if body.contains("%s") or body.contains("%d"):
			leaked.append(String(p.title))
	_check(empty.is_empty(), "每页正文都非空（空页：%s）" % str(empty))
	_check(leaked.is_empty(), "正文里没有漏掉的格式化占位符（%s）" % str(leaked))
	# 数值必须跟着常量走，不能写死
	var money_page := ""
	for p in pages:
		if String(p.key) == "money":
			money_page = String(p.body)
	_check(money_page.contains(GameData.fmt_money(GameData.START_MONEY)),
		"经济页引用起始资金常量（%s）" % GameData.fmt_money(GameData.START_MONEY))
	var basic_page := ""
	for p in pages:
		if String(p.key) == "basic":
			basic_page = String(p.body)
	# 批次 4 起滚轮做的是「3D↔2D 视角推移」，不再说「滚轮缩放」（那是批次 2 的旧操作）。
	# 这条断言存在的意义就是「规则说明不能教已删除的操作」：钉新措辞、并**反过来**钉死旧措辞
	# 不回来 —— 只删掉断言等于放行。
	# 钉的子串要**真能区分新旧**：旧的「滚轮缩放」那句里也有「滚轮」「视角」（「视角恒定」），
	# 只钉这两个词的话正断言对旧文案照样绿。改钉「推移」—— 旧文案里没有。
	_check(basic_page.contains("滚轮") and basic_page.contains("推移"),
		"基础操作页的滚轮说明改写为「视角推移」（不再教已删除的「滚轮缩放」）")
	_check(not basic_page.contains("滚轮缩放"),
		"基础操作页不再出现已被取代的「滚轮缩放」")
	# 选目标的入口换过很多次：座位卡（批次 5 退场）→ 桌上立牌（批次 9 退场）→
	# 四角条（批次 12 D 退场）→ 左上角名册条（批次 13 ②）→ **桌面立牌（v0.8.0 第四次复核）**。
	# ⇒ 今天的入口是**桌面上对手那块立牌**（`table_props` 的 `Placards`）。
	# 正向钉新措辞 + **反向**钉住旧措辞不回来（只删断言等于放行），与上面「滚轮缩放」同款。
	# **反向那条必须钉"右上角名册条"整串**：只钉「名册条」正断言对新旧文案都成立
	#（新旧都含这三个字），等于没钉住搬位 —— 玩家会照着右上角找一个已经不在那儿的东西。
	var all_text := ""
	for p in pages:
		all_text += String(p.body)
	_check(basic_page.contains("立牌") and basic_page.contains("选中"),
		"基础操作页把选目标的入口说成「点桌上对手的立牌」（v0.8.0 四次复核：名册条搬上桌做成了立牌）")
	_check(not (basic_page.contains("名册条") or all_text.contains("名册条")),
		"全部页都不再说「名册条」（它已整体删除，文案跟着改：信息在桌面立牌上）")
	_check(not all_text.contains("右上角名册条") and not all_text.contains("点右上角"),
		"全部页都不再说「右上角名册条 / 点右上角」（批次 13 ② 那两处已搬走）")
	# 反向契约：四角条只剩"我"那一条之后，"点屏幕四角的对手身家条"这句话就是**教错东西**
	_check(not basic_page.contains("点屏幕四角的"),
		"基础操作页不再教「点屏幕四角的对手身家条」（他人的四角条已删）")
	# **「立牌」这个反向契约已作废**（v0.8.0 四次复核）：批次 9 退场的是**老 2D 版那块座位卡式立牌**
	#（带公开背包 / 身家），而今天桌面上**又有了立牌** —— 但那是**名册条的替身**（名次 + 棋子色 +
	# 昵称 + 倒计时），与老那块不是同一样东西（`table_props` 里 `Standees` 仍是 null，
	# 那条反向契约在 `hud_test` 里）。⇒ 这里改成钉**老那块的特征**：不能出现"公开背包"这类说法。
	_check(not all_text.contains("公开背包") and not all_text.contains("座位卡"),
		"全部页都不再出现已退场的老立牌 / 座位卡的说法（公开背包改由玩家道具弹窗承担）")
	_check(not all_text.contains("座位卡"),
		"全部页都不再出现已删除的「座位卡」（任何一页都不许教它）")
	# 手牌右键丢弃（M7）：批次 3 起这条入口就存在，规则说明里却从没写过。
	_check(basic_page.contains("右键") and basic_page.contains("丢弃"),
		"基础操作页写了「手牌右键丢弃」这条入口")
	_check(basic_page.contains("直接使用"),
		"基础操作页写了「点一张牌 = 直接使用」这条出牌入口")
	# 反向钉住旧措辞不回来（同上「滚轮缩放」同款）：只删掉正断言等于放行，
	# 那句「点桌垫「使用道具」确认」教的是批次 7 已删除的两段式出牌。
	_check(not basic_page.contains("点桌垫"),
		"基础操作页不再教「点桌垫使用道具确认」那条已删除的两段式")

	print("== 控件与初始状态 ==")
	_check(g.rules_btn != null and g.rules_panel != null and g.rules_body != null,
		"规则按钮 / 面板 / 正文都已回填")
	_check(g.rules_tabs.size() == pages.size(), "分页标签数与页数一致")
	_check(g.rules_btn.visible and not g.rules_panel.visible, "默认收起：只有按钮可见")

	print("== 点按钮展开 ==")
	_click(g.rules_btn)
	await create_timer(0.3).timeout
	# **批次 13 辛 ① 改写了这一条**：旧断言是"展开后按钮收起"（`rules_btn.visible = not on`），
	# 用户现在的原话是「弹窗规则说明弹窗时，『规则说明』按钮不要消失」⇒ 反过来钉：**按钮恒可见**。
	# 不是放宽：`rules_btn.visible` 必须为真，藏起来就红。
	_check(g.rules_panel.visible and g.rules_btn.visible,
		"点「📖 规则说明」后展开、**按钮仍在**（批次 13 辛 ①）")
	_check(g.rules_body.text.length() > 0, "展开后正文有内容")

	# **批次 13 辛 ①：同一枚按钮现在是开关**（回调从 `_set_rules_open(true)` 改成
	# `_set_rules_open(not rules_open)`）。这里**直接发按钮的 `pressed` 信号**、不走鼠标拾取：
	#   * 要钉的正是"回调改成切换"这件事本身 —— 信号 → lambda → `_set_rules_open` 那条链；
	#   * 鼠标拾取那一段上面那行 `_click(g.rules_btn)` 已经真走过一次，不必重复；
	#   * **更实际的理由**：本套件的宿主对局是**活的**，多等 0.6 秒就可能让**结算层**冒出来
	#     把后续的真点击整个吃掉（实测踩过："收起"那一下点到结算层的压暗底、面板关不掉）。
	#     这里不加 `await`，后面几处点击的时序与改写前**一字不差**。
	# **正着钉新行为**：旧回调下第二次 emit 是空操作 ⇒ 面板仍开着 ⇒ 最后那条红。
	g.rules_btn.pressed.emit()
	_check(not g.rules_panel.visible and g.rules_btn.visible,
		"展开态再发一次 pressed → 收起（同一枚按钮当开关用，按钮恒在）")
	g.rules_btn.pressed.emit()
	_check(g.rules_panel.visible and g.rules_btn.visible,
		"（前置）再发一次又展开、按钮仍在 —— 下面几段按展开态写")

	print("== 换页 ==")
	var turn_btn: Button = g.rules_tabs.get("turn")
	_check(turn_btn != null, "找到「回合与行动」标签")
	var before: String = g.rules_body.text
	_click(turn_btn)
	await create_timer(0.2).timeout
	_check(g.rules_body.text != before, "点标签后正文换页")
	_check(g.rules_body.text.contains("转轮盘"), "换到的是「回合与行动」页")
	_check(g.rules_tab == "turn", "当前页 key 已更新")

	print("== 展开时格详情卡仍让位（面板搬到右上角后这条不变） ==")
	g._on_tile_clicked(0)
	await create_timer(0.2).timeout
	_check(not g.info_panel.visible, "规则展开时格详情卡不弹出（避免互相压住）")

	print("== 收起 ==")
	var close_btn: Button = null
	for b in g.rules_panel.find_children("", "Button", true, false):
		if String((b as Button).text).contains("收起"):
			close_btn = b
	_check(close_btn != null, "找到「收起」按钮")
	_click(close_btn)
	await create_timer(0.2).timeout
	_check(not g.rules_panel.visible and g.rules_btn.visible, "收起后回到按钮态")
	g._on_tile_clicked(0)
	await create_timer(0.2).timeout
	_check(g.info_panel.visible, "收起后格详情卡恢复可弹出")

	print("== 批次 13 ①：面板在右上角、与战报栏互斥 ==")
	# 位置：右边缘贴 −12（与展开的「战报」栏同一条线）、顶边落在仪表盘横条（8..76）之下
	_check(is_equal_approx(g.rules_panel.offset_right, -12.0) and g.rules_panel.offset_top > 76.0,
		"规则面板锚在右上角、仪表盘横条之下（右 %s / 顶 %s）"
			% [str(g.rules_panel.offset_right), str(g.rules_panel.offset_top)])
	# **批次 13 辛 ②：给「战报」栏补一条同款钉**。此前它**一条断言都没有** —— 顶边还是 134
	#（离按钮很远）时这一整套照样全绿，所以"收回按钮正下方"那条改动当时是**静默**的，
	# 谁把它改回去都没人知道（复核 M2 点名的洞）。
	# 判据与上面那条**对称**：既钉当前值 84，也**与两枚按钮的实效下沿比**（而不是只钉一个魔数）。
	# 2026-10-09：顶部加了仪表盘横条（8..76）⇒ 从 52 下移到 84，落在横条之下。
	var btn_bottom: float = maxf((g.rules_btn as Control).get_global_rect().end.y,
		(g.log_toggle as Control).get_global_rect().end.y)
	_check(is_equal_approx(g.log_panel.offset_top, 84.0) and g.log_panel.offset_top > btn_bottom,
		"战报栏顶边贴在仪表盘横条之下（顶 %s / 按钮实效下沿 %.1f）"
			% [str(g.log_panel.offset_top), btn_bottom])
	# 互斥（用户 ① 明写"不能同时打开"）：展开战报 → 规则自动收起
	_check(not g.rules_panel.visible, "（前置）此刻规则面板是收起的")
	g._toggle_log()
	await create_timer(0.1).timeout
	_check(g.log_panel.visible and not g.rules_panel.visible and g.rules_btn.visible,
		"展开战报栏 → 规则面板自动收起")
	# 反向：展开规则 → 战报自动收起
	g._set_rules_open(true)
	await create_timer(0.1).timeout
	_check(g.rules_panel.visible and not g.log_panel.visible,
		"展开规则面板 → 战报栏自动收起")
	g._set_rules_open(false)
	await create_timer(0.1).timeout
	_check(not g.rules_panel.visible and not g.log_panel.visible, "两边都收起（互斥后仍可各自关闭）")

	g.free()
	if fails == 0:
		print("RULES PANEL TEST: ALL PASS")
		quit(0)
	else:
		print("RULES PANEL TEST: %d FAILURES" % fails)
		quit(1)
