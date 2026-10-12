extends SceneTree
## 「📖 图鉴」回归（2026-10-11 加；**2026-10-12 改成屏幕中央的大尺寸模态弹窗**）：
##   -- 按钮真的能展开 / 收起；三页齐全；每页条目数与 `CardDB` 一致；搜索能过滤；
##   -- **落点 = 屏幕正中央 + 大尺寸**（不再是右上角那个 430×472 的小面板）；
##   -- **模态**：压暗底铺满、z 带在"抽卡大字卡之上 / 小卖部·暂停之下"、
##      ✕ / 点压暗底 / Esc / 再点那枚按钮四条路都能关；
##   -- 与「规则说明」「战报」三方互斥；格详情卡让位；
##   -- 道具页真卡的角标不许被 `ScrollContainer` 裁掉（与背包弹窗同一个坑）。
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
func _push_click(vp: Viewport, pos: Vector2) -> void:
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

func _click(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	_push_click(control.get_viewport(), control.get_global_rect().get_center())

## 道具页的条目数：清单下只有一个 `HFlowContainer`，条目就是它的孩子。
func _count_cards(g) -> int:
	var n := 0
	for c in g.codex_list.get_children():
		if c is HFlowContainer:
			n += c.get_child_count()
	return n

## 道具页**渲染出来的 `ItemCard` 节点**（前序）——量角标几何用。
func _item_cards(g, ic_script: GDScript) -> Array:
	var out: Array = []
	for c in g.codex_list.get_children():
		if c is HFlowContainer:
			for cell in c.get_children():
				for n in (cell as Node).find_children("*", "", true, false):
					if n.get_script() == ic_script:
						out.append(n)
	return out

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
	var ICARD = load("res://scripts/item_card.gd")

	print("== 控件回填与初始状态 ==")
	_check(g.codex_btn != null and g.codex_modal != null and g.codex_dim != null
			and g.codex_panel != null and g.codex_search != null and g.codex_list != null,
		"图鉴按钮 / 模态包装 / 压暗底 / 面板 / 搜索框 / 清单都已回填")
	_check(g.codex_tabs.size() == CodexP.TABS.size(),
		"分页标签数与族数一致（实得 %d）" % g.codex_tabs.size())
	_check(g.codex_btn.visible and not g.codex_modal.visible,
		"默认收起：**只有按钮可见**（模态包装整个藏着）")
	# 按钮本身仍是右上角那一簇里的一员（2026-10-12 只改了**弹窗**的落点，按钮没动）
	_check(is_equal_approx(g.codex_btn.offset_top, g.rules_btn.offset_top)
			and is_equal_approx(g.codex_btn.offset_top, g.log_toggle.offset_top),
		"三枚按钮同一条 y（图鉴 %s / 规则 %s / 战报 %s）"
			% [str(g.codex_btn.offset_top), str(g.rules_btn.offset_top), str(g.log_toggle.offset_top)])
	var codex_r: float = (g.codex_btn as Control).get_global_rect().end.x
	var rules_l: float = (g.rules_btn as Control).get_global_rect().position.x
	_check(codex_r <= rules_l + 0.5,
		"图鉴按钮排在「规则说明」左边、不重叠（图鉴右沿 %.1f ≤ 规则左沿 %.1f）" % [codex_r, rules_l])

	print("== 三族都在，且与 CardDB 对得上 ==")
	var missing: Array = []
	for fam in CodexP.TABS:
		if not g.codex_tabs.has(fam):
			missing.append(fam)
	_check(missing.is_empty(), "道具 / 科技 / 畸变三枚标签齐全（缺 %s）" % str(missing))
	_check(g.codex_tab == "item", "默认停在道具页（实得 %s）" % g.codex_tab)

	print("== 点按钮展开：屏幕中央的大尺寸模态 ==")
	_click(g.codex_btn)
	await create_timer(0.3).timeout
	_check(g.codex_modal.visible and g.codex_btn.visible,
		"点「📖 图鉴」后模态出现、**按钮仍在**（同一枚按钮当开关用）")
	# ① 落点 = **屏幕正中央**（旧版是右上角"按钮下方展开"，那两个 offset 断言随落点改写删除）
	var pcen: Vector2 = (g.codex_panel as Control).get_global_rect().get_center()
	var cv: Vector2 = g.size * 0.5
	_check(absf(pcen.x - cv.x) <= 1.0 and absf(pcen.y - cv.y) <= 1.0,
		"面板落在**屏幕正中央**（实得中心 (%.0f, %.0f)，画布中心 (%.0f, %.0f)）"
			% [pcen.x, pcen.y, cv.x, cv.y])
	# ② 大尺寸：明显比旧版那个 430×472 大，且不顶出画布
	var ps: Vector2 = (g.codex_panel as Control).size
	_check(ps.x >= 1000.0 and ps.y >= 600.0 and ps.x <= g.size.x and ps.y <= g.size.y,
		"面板是**大尺寸**且不超出画布（实得 %.0f×%.0f，画布 %.0f×%.0f）"
			% [ps.x, ps.y, g.size.x, g.size.y])
	# ③ 模态：压暗底铺满、吃点击；面板本身不吃空白处（点它不关，见后面那条）
	_check(g.codex_dim.visible and g.codex_dim.mouse_filter == Control.MOUSE_FILTER_STOP,
		"压暗底铺满画布且吃掉落在面板外的点击（STOP）")
	_check((g.codex_dim as Control).size.is_equal_approx(g.size),
		"压暗底与画布同大（%.0f×%.0f）" % [(g.codex_dim as Control).size.x, (g.codex_dim as Control).size.y])
	# ④ z 带：高于抽卡大字卡（40），低于小卖部 / 暂停（70 / 80）—— "只调 z 挡不住点击" 那条见文件头
	_check(g.codex_modal.z_index == 45,
		"模态的 z = 45（与玩家道具弹窗同带，实得 %d）" % g.codex_modal.z_index)
	_check(g.codex_modal.z_index < g.shop_layer.z_index and g.codex_modal.z_index < g.menu_layer.z_index,
		"z 带在小卖部(%d) / 暂停(%d) **之下**（不会盖住那两个模态）"
			% [g.shop_layer.z_index, g.menu_layer.z_index])

	print("== 道具页：条目数 == CardDB ==")
	var n_item := _count_cards(g)
	var want_item: int = CardDB.ids(CardDB.FAMILY_ITEM).size()
	_check(n_item == want_item and want_item > 0,
		"道具页摆了 %d 张卡（CardDB 里 %d 件）" % [n_item, want_item])
	# 道具页摆的必须是**真卡**（`item_card.gd`），不是另画一行文字 —— 图鉴的一半就是"长什么样"
	_check(_item_cards(g, ICARD).size() == want_item,
		"每一件都是 `ItemCard` 真卡（实得 %d）" % _item_cards(g, ICARD).size())

	print("== 道具页的角标不许被 `ScrollContainer` 裁掉（2026-10-12：与背包弹窗同一个坑） ==")
	# 真卡角标是**半出卡外**画的，而清单装在 `ScrollContainer` 里（裁子节点）⇒ 网格贴边就切角标。
	# 判据量**真几何**：横向逐张卡量角标越界量（纵向只量最上面那张 —— 下面的卡是被**正常滚动**切
	# 在可视区外的，不是 bug）。
	var csc := g.codex_panel.find_child("CodexScroll", true, false) as ScrollContainer
	_check(csc != null and csc.clip_contents, "（前置）清单装在会裁子节点的 `CodexScroll` 里")
	if csc != null:
		var cr: Rect2 = csc.get_global_rect()
		var cards := _item_cards(g, ICARD)
		var top_y := INF
		for cd in cards:
			top_y = minf(top_y, (cd as Control).get_global_rect().position.y)
		var over_bad: Array = []
		var worst := 0.0
		for cd in cards:
			var crect: Rect2 = (cd as Control).get_global_rect()
			for leaf_v in (cd as Control).get_children():
				var leaf := leaf_v as Control
				if leaf == null or leaf.size.x <= 0.0 or leaf.size.y <= 0.0:
					continue
				var r: Rect2 = leaf.get_global_rect()
				var over := maxf(cr.position.x - r.position.x, r.end.x - cr.end.x)
				if absf(crect.position.y - top_y) < 0.5:      # 最上面那一行，纵向也量
					over = maxf(over, cr.position.y - r.position.y)
				worst = maxf(worst, over)
				if over > 0.0:
					over_bad.append("%s 第 %d 枚越界 %.1fpx" % [String(cd.id), leaf.get_index(), over])
		var over_show: Array = over_bad.slice(0, mini(over_bad.size(), 6))
		_check(over_bad.is_empty(),
			"角标都在可视区内（最坏一枚越界 %.1fpx；%s）" % [worst, str(over_show)])
		# 最宽的那枚是「一次性」胶囊 —— 留白必须盖得住**最宽**的那种（只算圆角标是手牌那次的翻车原因）
		var probe_card: Control = ICARD.make("蛋蛋节", ICARD.SIZE_SMALL, {})
		var probe_over := Vector4(0, 0, 0, 0)
		for leaf_v2 in probe_card.get_children():
			var leaf2 := leaf_v2 as Control
			if leaf2 == null or leaf2.size.x <= 0.0 or leaf2.size.y <= 0.0:
				continue
			probe_over.x = maxf(probe_over.x, -leaf2.position.x)
			probe_over.y = maxf(probe_over.y, -leaf2.position.y)
			probe_over.z = maxf(probe_over.z, leaf2.position.x + leaf2.size.x - probe_card.size.x)
			probe_over.w = maxf(probe_over.w, leaf2.position.y + leaf2.size.y - probe_card.size.y)
		probe_card.free()
		var cpad := g.codex_panel.find_child("CodexPad", true, false) as MarginContainer
		_check(cpad != null, "清单外面套了一圈留白容器 `CodexPad`（角标探出卡外那些 px 靠它）")
		if cpad != null:
			var got := Vector4(
				float(cpad.get_theme_constant("margin_left")), float(cpad.get_theme_constant("margin_top")),
				float(cpad.get_theme_constant("margin_right")), float(cpad.get_theme_constant("margin_bottom")))
			_check(got.x >= probe_over.x and got.y >= probe_over.y
					and got.z >= probe_over.z and got.w >= probe_over.w,
				"留白盖得住最宽那枚角标（需 左%.1f 上%.1f 右%.1f 下%.1f，实得 左%.0f 上%.0f 右%.0f 下%.0f）"
					% [probe_over.x, probe_over.y, probe_over.z, probe_over.w,
						got.x, got.y, got.z, got.w])

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
	# 长描述按**弹窗内容宽**换行（尺寸变了它得跟着变，别写死旧面板宽那个数）
	var desc_ok := true
	for c in g.codex_list.get_children():
		for n in (c as Node).find_children("", "Label", true, false):
			var lb := n as Label
			if lb.autowrap_mode != TextServer.AUTOWRAP_OFF and lb.custom_minimum_size.x > CodexP.content_w(g) + 1.0:
				desc_ok = false
	_check(desc_ok, "描述换行宽度不超过清单可用宽度（%.0f）" % CodexP.content_w(g))
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
	# 判据两边都读：**标志位 + 模态可见性**。本套件的宿主对局在跑，一次状态广播会让
	# `RulesPanel.refresh` 把规则面板整个重建 —— 那条重建路径 2026-10-11 修过（原先重建后
	# 新面板留成隐藏、而 `rules_open` 仍是 true ⇒ 拿可见性断言会随机红），
	# `rules_panel_test` 末尾有一条专门钉它。这里照旧读可见性，等于顺带再守一道。
	g._set_rules_open(true)
	await create_timer(0.1).timeout
	_check(g.rules_open and g.rules_panel.visible
			and not g.codex_open and not g.codex_modal.visible,
		"展开规则说明 → 图鉴自动收起")
	g._set_codex_open(true)
	await create_timer(0.1).timeout
	_check(g.codex_open and g.codex_modal.visible
			and not g.rules_open and not g.rules_panel.visible,
		"展开图鉴 → 规则说明自动收起")
	g._toggle_log()
	await create_timer(0.1).timeout
	_check(g.log_panel.visible and not g.codex_modal.visible,
		"展开战报 → 图鉴自动收起")

	print("== 格详情卡让位 ==")
	g._set_codex_open(true)
	await create_timer(0.1).timeout
	g._on_tile_clicked(0)
	await create_timer(0.2).timeout
	_check(not g.info_panel.visible, "图鉴展开时格详情卡不弹出（避免互相压住）")

	print("== 四条关闭路径（全走真实链路） ==")
	var vp: Viewport = g.get_viewport()
	# ① ✕
	var close_btn: Button = g.codex_panel.find_child("CodexClose", true, false)
	_check(close_btn != null, "找到面板里的「✕」关闭按钮")
	_click(close_btn)
	await create_timer(0.2).timeout
	_check(not g.codex_modal.visible and g.codex_btn.visible, "点「✕」收起后回到按钮态")
	g._on_tile_clicked(0)
	await create_timer(0.2).timeout
	_check(g.info_panel.visible, "收起后格详情卡恢复可弹出")
	# ② **点压暗底**（面板之外）—— 顺带证明模态真的挡得住下面那些建期控件（那一点落在「暂停」上）
	g._set_codex_open(true)
	await create_timer(0.2).timeout
	_push_click(vp, Vector2(20, 20))
	await create_timer(0.2).timeout
	_check(not g.codex_modal.visible, "点弹窗外面（压暗底）→ 关闭")
	_check(not g.menu_layer.visible, "同一那一点没有穿透到下面的「暂停」按钮（模态挡住建期控件）")
	# ③ 非左键不该关（滚轮点压暗底）—— 同一条 lambda 里那道按键判断
	g._set_codex_open(true)
	await create_timer(0.2).timeout
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	g.codex_dim.gui_input.emit(wheel)
	await create_timer(0.1).timeout
	_check(g.codex_modal.visible, "滚轮点压暗底：不关（只认左键）")
	_check(g.codex_btn != null and g.codex_panel.visible, "面板本身仍在")
	# ④ Esc 走 `game._unhandled_input` 的真分支（前置：此刻没有选目标态 / 未选中牌）
	_check(g._tgt_stage == "" and g.selected_slot < 0, "Esc 之前：无选目标态 / 未选中牌（前置）")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	g._unhandled_input(esc)
	await create_timer(0.1).timeout
	_check(not g.codex_modal.visible, "Esc（真 `_unhandled_input` 链路）→ 关闭")
	# ⑤ 再点那枚按钮 = 第 4 条路（开关本身就是它）
	g._set_codex_open(true)
	await create_timer(0.2).timeout
	_click(g.codex_btn)
	await create_timer(0.2).timeout
	_check(not g.codex_modal.visible and g.codex_btn.visible, "再点「📖 图鉴」→ 收起")

	g.free()
	if fails == 0:
		print("CODEX PANEL TEST: ALL PASS")
		quit(0)
	else:
		print("CODEX PANEL TEST: %d FAILURES" % fails)
		quit(1)
