extends SceneTree
## 对局暂停菜单回归（fix/v0.1.0）
##   -- 点开左上角「暂停」后整屏卡死、菜单上的按钮点不动
## 走真实 GUI 输入链路（Viewport.push_input）而不是 emit_signal("pressed")，
## 这样才能钉住「控件被别的控件挡住 / 被暂停态卡住」这类只有真实链路才暴露的问题。
## godot --headless --path . --script tests/pause_menu_test.gd

var fails := 0

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

## 在控件中心推一次鼠标左键点击（含一次 move，让 Viewport 先算出 hover）。
## in_local_coords=true：坐标直接按画布空间算，不经窗口→画布的拉伸变换
## （headless 下窗口尺寸与画布尺寸不一致，默认的 false 会让事件落到窗口外被丢弃）。
func _click(control: Control) -> void:
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

func _btn_text(root_node: Node, text: String) -> Button:
	for n in root_node.find_children("", "Button", true, false):
		if String((n as Button).text).contains(text):
			return n
	return null

## 诊断：忠实模拟 Viewport 的 GUI 拾取（子节点逆序优先，再判自身），
## 返回 Viewport 真正会命中的那个控件。
func _pick(n: Node, pos: Vector2) -> Control:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return null
	var kids := n.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var hit := _pick(kids[i], pos)
		if hit != null:
			return hit
	if n is Control:
		var c := n as Control
		if c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(pos):
			return c
	return null

## 诊断：列出点击位置上「会吃鼠标」的可见控件（自下而上，最后一项最上层）
func _blockers_at(root_node: Node, pos: Vector2) -> Array:
	var out: Array = []
	var stack: Array = [root_node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Control:
			var c := n as Control
			if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE \
					and c.get_global_rect().has_point(pos):
				out.append("%s(%s)" % [c.name, c.get_class()])
	return out

## 诊断：把控件一路标到根，看清它在树里的位置
func _path_of(c: Control) -> String:
	var parts: Array = []
	var n: Node = c
	while n != null:
		parts.push_front(String(n.name))
		n = n.get_parent()
	return "/".join(parts)

func _run() -> void:
	# headless 的根窗口默认只有 64x64，画布却按 1280 拉伸；先摆成与实机一致的尺寸，
	# 否则控件布局与真机不符，点击坐标也会落在窗口外
	root.size = Vector2i(1280, 800)
	# --script 模式下 autoload 不能按全局名引用（编译期尚未注册），运行时从 root 取
	var net = root.get_node_or_null("Net")
	if net != null:
		# 摆一份名册：否则 _host_setup 会对着空 hp 调 _broadcast_state 报错，噪音盖住真失败
		net.players = [
			{"peer": 1, "name": "我", "color": 0, "bot": false, "ready": true},
			{"peer": 2, "name": "乙", "color": 1, "bot": true, "ready": true},
		]
	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.running = false  # 冻结主循环，本测试手动摆状态
	for i in 4:
		await process_frame
	await create_timer(0.4).timeout

	print("viewport size = ", root.size, " visible_rect = ", root.get_visible_rect())

	# 左上角入口按钮应已改名「暂停」（原先叫「选项」）
	_check(g.opt_btn != null, "左上角入口按钮已建立")
	print("  info: 入口按钮文案 = ", g.opt_btn.text if g.opt_btn != null else "<null>")

	print("== 对照实验：未暂停时点入口按钮，菜单必须打开（证明探针能送进事件）==")
	_click(g.opt_btn)
	await create_timer(0.2).timeout
	_check(g.menu_layer.visible and g.get_tree().paused,
		"未暂停时点「暂停」入口 → 菜单打开且全场暂停")
	if not g.menu_layer.visible:
		print("PAUSE MENU TEST: 探针无法送达事件，中止")
		quit(1)
		return
	# 先收起，回到干净状态
	g._menu_resume()
	await create_timer(0.1).timeout

	print("== 打开暂停菜单 ==")
	g._open_menu()
	await create_timer(0.2).timeout
	_check(g.get_tree().paused, "打开菜单后全场已暂停")
	_check(g.menu_layer.visible, "暂停菜单层可见")
	_check(g.menu_panel.visible, "主菜单面板可见")

	var cont := _btn_text(g.menu_panel, "继续")
	_check(cont != null, "找到「继续游戏」按钮")
	if cont == null:
		print("PAUSE MENU TEST: SCENE LOAD FAILED")
		quit(1)
		return
	var pos := cont.get_global_rect().get_center()
	print("  info: 按钮 rect=", cont.get_global_rect(), " pos=", pos)
	print("  info: 按钮 can_process=", cont.can_process(),
		" menu_layer.can_process=", g.menu_layer.can_process())
	print("  info: 该位置会吃鼠标的控件（自下而上）= ", _blockers_at(root, pos))
	var winner := _pick(root, pos)
	print("  info: Viewport 拾取命中的控件 = ",
		("%s → %s" % [winner.name, _path_of(winner)]) if winner != null else "<无>")
	print("  info: 期望命中 = ", cont.name, " → ", _path_of(cont))

	_click(cont)
	await create_timer(0.2).timeout
	_check(not g.menu_layer.visible, "点「继续游戏」后菜单关闭（此前卡死在此）")
	_check(not g.get_tree().paused, "继续后解除全场暂停")

	print("== 暂停中仍能用菜单（设置 / 退出确认）==")
	g._open_menu()
	await create_timer(0.2).timeout
	var set_btn := _btn_text(g.menu_panel, "设置")
	_check(set_btn != null, "找到「设置」按钮")
	_click(set_btn)
	await create_timer(0.2).timeout
	_check(g.settings_panel.visible, "点「设置」后设置面板可见（暂停态下按钮可点）")
	var back := _btn_text(g.settings_panel, "返回")
	_check(back != null, "找到「返回」按钮")
	_click(back)
	await create_timer(0.2).timeout
	_check(g.menu_panel.visible, "「返回」回到主菜单面板")

	var quit_btn := _btn_text(g.menu_panel, "退出")
	_check(quit_btn != null, "找到「退出游戏」按钮")
	_click(quit_btn)
	await create_timer(0.2).timeout
	_check(g.confirm_panel.visible, "点「退出游戏」后二次确认可见")
	var cancel := _btn_text(g.confirm_panel, "取消")
	_check(cancel != null, "找到「取消」按钮")
	_click(cancel)
	await create_timer(0.2).timeout
	_check(g.menu_panel.visible and not g.confirm_panel.visible, "「取消」回到主菜单面板")

	g.get_tree().paused = false
	g.free()

	if fails == 0:
		print("PAUSE MENU TEST: ALL PASS")
		quit(0)
	else:
		print("PAUSE MENU TEST: %d FAILURES" % fails)
		quit(1)
