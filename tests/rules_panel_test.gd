extends SceneTree
## 左下角「📖 规则说明」回归（fix/v0.1.0）
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
	# 选目标的入口：座位卡随批次 5 退场（入口一度是桌上的立牌）、立牌随批次 9 退场，
	# 现在入口是**屏幕四角的对手身家条**。
	# 正向钉新措辞 + **反向**钉住旧措辞不回来（只删断言等于放行），与上面「滚轮缩放」同款。
	var all_text := ""
	for p in pages:
		all_text += String(p.body)
	_check(basic_page.contains("身家条") and basic_page.contains("选中"),
		"基础操作页把选目标的入口说成「点屏幕四角的对手身家条」（立牌已随批次 9 退场）")
	_check(not all_text.contains("立牌"),
		"全部页都不再出现已退场的「立牌」（反向契约，同「滚轮缩放」那条；查 all_text 与下面「座位卡」那条对齐）")
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
	_check(g.rules_panel.visible and not g.rules_btn.visible, "点「📖 规则说明」后展开、按钮收起")
	_check(g.rules_body.text.length() > 0, "展开后正文有内容")

	print("== 换页 ==")
	var turn_btn: Button = g.rules_tabs.get("turn")
	_check(turn_btn != null, "找到「回合与行动」标签")
	var before: String = g.rules_body.text
	_click(turn_btn)
	await create_timer(0.2).timeout
	_check(g.rules_body.text != before, "点标签后正文换页")
	_check(g.rules_body.text.contains("转轮盘"), "换到的是「回合与行动」页")
	_check(g.rules_tab == "turn", "当前页 key 已更新")

	print("== 展开时会压住左下角，格详情卡让位 ==")
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

	g.free()
	if fails == 0:
		print("RULES PANEL TEST: ALL PASS")
		quit(0)
	else:
		print("RULES PANEL TEST: %d FAILURES" % fails)
		quit(1)
