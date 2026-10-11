extends SceneTree
## 「📖 图鉴」回归（2026-10-11 加）：右上角那枚按钮 + 其下方展开的三族图鉴面板。
##   -- 按钮真的能展开 / 收起；三页齐全；每页条目数与 `CardDB` 一致；搜索能过滤；
##   -- 与「规则说明」「战报」三方互斥；落点在右上角、不与另两枚按钮重叠。
## 走真实 GUI 输入链路（Viewport.push_input）—— 与 `rules_panel_test.gd` 同一套骨架。
## godot --headless --path . --script tests/codex_panel_test.gd

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

## 道具页的条目数：清单下只有一个 `HFlowContainer`，条目就是它的孩子。
func _count_cards(g) -> int:
	var n := 0
	for c in g.codex_list.get_children():
		if c is HFlowContainer:
			n += c.get_child_count()
	return n

## 文字页（科技 / 畸变）的条目数：清单下每个 `VBoxContainer` 就是一条。
## （"没有匹配的条目"那句是 `Label`，两样都不算 ⇒ 无结果时两边都数出 0。）
func _count_rows(g) -> int:
	var n := 0
	for c in g.codex_list.get_children():
		if c is VBoxContainer:
			n += 1
	return n

func _run() -> void:
	root.size = Vector2i(1280, 800)
	# --script 模式下 autoload 不能按全局名引用（编译期尚未注册），运行时从 root 取
	var net = root.get_node_or_null("Net")
	if net != null:
		net.players = [
			{"peer": 1, "name": "我", "color": 0, "bot": false, "ready": true},
			{"peer": 2, "name": "乙", "color": 1, "bot": true, "ready": true},
			{"peer": 3, "name": "丙", "color": 2, "bot": true, "ready": true},
			{"peer": 4, "name": "丁", "color": 3, "bot": true, "ready": true},
		]
	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.running = false
	# **脚手架那局不跑科技**（口径同 `tests/hud_test.gd` / `item_test` 那几条）：2026-10-09 起
	# `tech_on` 默认开，而 `_host_setup` 是在 `await _wait(1.5)` **之后**才读它 ⇒ 在这里关来得及。
	# **这条对本文件是必需、不是洁癖**：定档演出是一块 z75 的全屏压暗底（`MOUSE_FILTER_STOP`），
	# 后面跟着等真人三选一、迟迟不走 —— 本套件步数多，后面每一次真点击都会被它整个吃掉
	#（实测：点「图鉴」那一下被 z75 拦掉，`codex_open` 始终 false）。
	g._settings.tech_on = false
	# `lab_mode`：快照的 `phase` 读 `running or lab_mode` —— 只关 `running` 会让它落到 "ended"，
	# `s_state` 随即给 g 挂**结算层**（z50 全屏压暗底），同样吃掉所有真点击。
	g.lab_mode = true
	for i in 4:
		await process_frame
	await create_timer(0.4).timeout

	# **`CodexPanel` 一律运行时 `load`**（同本文件里 `ICARD` 那条）：静态写类名会把
	# codex_panel.gd → item_card.gd → ui_kit.gd（引用了 autoload `Fx`）拽进本脚本的静态依赖链，
	# 而 `--script` 入口下此时 autoload 还没注册 ⇒ 整链编译失败。
	var CodexP = load("res://scripts/codex_panel.gd")

	print("== 控件回填与初始状态 ==")
	_check(g.codex_btn != null and g.codex_panel != null and g.codex_search != null
			and g.codex_list != null,
		"图鉴按钮 / 面板 / 搜索框 / 清单都已回填")
	_check(g.codex_tabs.size() == CodexP.TABS.size(),
		"分页标签数与族数一致（实得 %d）" % g.codex_tabs.size())
	_check(g.codex_btn.visible and not g.codex_panel.visible, "默认收起：只有按钮可见")

	print("== 三族都在，且与 CardDB 对得上 ==")
	var missing: Array = []
	for fam in CodexP.TABS:
		if not g.codex_tabs.has(fam):
			missing.append(fam)
	_check(missing.is_empty(), "道具 / 科技 / 畸变三枚标签齐全（缺 %s）" % str(missing))
	_check(g.codex_tab == "item", "默认停在道具页（实得 %s）" % g.codex_tab)

	print("== 点按钮展开 ==")
	_click(g.codex_btn)
	await create_timer(0.3).timeout
	_check(g.codex_panel.visible and g.codex_btn.visible,
		"点「📖 图鉴」后展开、**按钮仍在**（同一枚按钮当开关用）")

	print("== 道具页：条目数 == CardDB ==")
	var n_item := _count_cards(g)
	var want_item: int = CardDB.ids(CardDB.FAMILY_ITEM).size()
	_check(n_item == want_item and want_item > 0,
		"道具页摆了 %d 张卡（CardDB 里 %d 件）" % [n_item, want_item])
	# 道具页摆的必须是**真卡**（`item_card.gd`），不是另画一行文字 —— 图鉴的一半就是"长什么样"
	var ICARD = load("res://scripts/item_card.gd")
	var real_cards := 0
	for c in g.codex_list.get_children():
		if c is HFlowContainer:
			for cell in c.get_children():
				for sub in cell.get_children():
					for leaf in sub.get_children():
						if leaf.get_script() == ICARD:
							real_cards += 1
	_check(real_cards == want_item, "每一件都是 `ItemCard` 真卡（实得 %d）" % real_cards)

	print("== 搜索过滤 ==")
	g.codex_search.text = "黑卡"
	g.codex_search.text_changed.emit("黑卡")
	var n_hit := _count_cards(g)
	_check(n_hit >= 1 and n_hit < want_item, "搜「黑卡」⇒ 只剩 %d 张（全量 %d）" % [n_hit, want_item])
	g.codex_search.text = "绝不可能存在的道具名"
	g.codex_search.text_changed.emit(g.codex_search.text)
	_check(_count_cards(g) == 0, "搜一个不存在的词 ⇒ 清单为空")
	var hint_ok := false
	for c in g.codex_list.get_children():
		if c is Label and String((c as Label).text).contains("没有匹配"):
			hint_ok = true
	_check(hint_ok, "无结果时给一句「没有匹配的条目」")
	g.codex_search.text = ""
	g.codex_search.text_changed.emit("")
	_check(_count_cards(g) == want_item, "清空搜索 ⇒ 全部回来")

	print("== 换页：科技 / 畸变 ==")
	var b_tech: Button = g.codex_tabs.get("tech")
	var b_aber: Button = g.codex_tabs.get("aberration")
	_check(b_tech != null and b_aber != null, "找到「科技」「畸变」两枚标签")
	_click(b_tech)
	await create_timer(0.2).timeout
	var want_tech: int = CardDB.ids(CardDB.FAMILY_TECH).size()
	_check(g.codex_tab == "tech" and _count_rows(g) == want_tech and want_tech > 0,
		"科技页列了 %d 条（CardDB 里 %d 条）" % [_count_rows(g), want_tech])
	_click(b_aber)
	await create_timer(0.2).timeout
	var want_aber: int = CardDB.ids(CardDB.FAMILY_ABERRATION).size()
	_check(g.codex_tab == "aberration" and _count_rows(g) == want_aber and want_aber > 0,
		"畸变页列了 %d 条（CardDB 里 %d 条）" % [_count_rows(g), want_aber])
	# 换页要能**切回去**（每页只是重刷清单，别把某一页刷没了）
	CodexP.select_tab(g, "item")
	await create_timer(0.1).timeout
	_check(_count_cards(g) == want_item, "切回道具页仍是全量")

	print("== 与「规则说明」「战报」互斥 ==")
	_check(g._set_codex_open != null, "（前置）互斥入口在")
	# ⚠ 判据读**标志位**、不读 `rules_panel.visible`：本套件的宿主对局在跑，一次状态广播会让
	# `RulesPanel.refresh` 把规则面板**整个重建**（新面板 `visible=false`，而它那句"恢复展开态"
	# 因为 `rules_open` 还是 true 被早退挡掉）⇒ 拿 `rules_panel.visible` 断言会**随机红**，
	# 且红的是与本功能无关的既有毛病（见交付说明）。图鉴面板不重建，两边都读得。
	g._set_rules_open(true)
	await create_timer(0.1).timeout
	_check(g.rules_open and not g.codex_open and not g.codex_panel.visible,
		"展开规则说明 → 图鉴自动收起")
	g._set_codex_open(true)
	await create_timer(0.1).timeout
	_check(g.codex_open and g.codex_panel.visible and not g.rules_open,
		"展开图鉴 → 规则说明自动收起")
	g._toggle_log()
	await create_timer(0.1).timeout
	_check(g.log_panel.visible and not g.codex_panel.visible,
		"展开战报 → 图鉴自动收起")

	print("== 格详情卡让位 ==")
	g._set_codex_open(true)
	await create_timer(0.1).timeout
	g._on_tile_clicked(0)
	await create_timer(0.2).timeout
	_check(not g.info_panel.visible, "图鉴展开时格详情卡不弹出（避免互相压住）")

	print("== 落点：右上角、不与另两枚按钮重叠 ==")
	_check(is_equal_approx(g.codex_panel.offset_right, -12.0) and is_equal_approx(g.codex_panel.offset_top, 84.0),
		"图鉴面板锚在右上角、顶边与规则面板同一条（右 %s / 顶 %s）"
			% [str(g.codex_panel.offset_right), str(g.codex_panel.offset_top)])
	# **按钮不许与「规则说明」叠**：图鉴排在它左边（`codex_panel.RULES_LEFT` 那条约定）。
	var codex_r: float = (g.codex_btn as Control).get_global_rect().end.x
	var rules_l: float = (g.rules_btn as Control).get_global_rect().position.x
	_check(codex_r <= rules_l + 0.5,
		"图鉴按钮排在「规则说明」左边、不重叠（图鉴右沿 %.1f ≤ 规则左沿 %.1f）" % [codex_r, rules_l])
	# 同一行：三枚按钮的顶边应当一致（视觉上一簇）
	_check(is_equal_approx(g.codex_btn.offset_top, g.rules_btn.offset_top)
			and is_equal_approx(g.codex_btn.offset_top, g.log_toggle.offset_top),
		"三枚按钮同一条 y（图鉴 %s / 规则 %s / 战报 %s）"
			% [str(g.codex_btn.offset_top), str(g.rules_btn.offset_top), str(g.log_toggle.offset_top)])

	print("== 收起 ==")
	var close_btn: Button = null
	for b in g.codex_panel.find_children("", "Button", true, false):
		if String((b as Button).text).contains("收起"):
			close_btn = b
	_check(close_btn != null, "找到「收起」按钮")
	_click(close_btn)
	await create_timer(0.2).timeout
	_check(not g.codex_panel.visible and g.codex_btn.visible, "收起后回到按钮态")
	g._on_tile_clicked(0)
	await create_timer(0.2).timeout
	_check(g.info_panel.visible, "收起后格详情卡恢复可弹出")

	g.free()
	if fails == 0:
		print("CODEX PANEL TEST: ALL PASS")
		quit(0)
	else:
		print("CODEX PANEL TEST: %d FAILURES" % fails)
		quit(1)
