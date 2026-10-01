class_name TableHud
extends RefCounted
## 对局内 HUD 的控件构建 —— 从 game.gd 的 _build_ui 整段搬出（见审查结论：
## 这里原本 260+ 行全是控件搭建，和对局状态机挤在一个文件里）。
##
## 构建好的控件以 {变量名: 控件} 返回，game.gd 用 set() 回填到同名成员上，
## 因此宿主侧的引用一行都不用改。回调里需要宿主状态/方法的地方走 g。

## 建整个对局界面；返回 {成员名: 控件}。
static func build_play_ui(g: Node) -> Dictionary:
	# 纯渐变氛围底（棋盘外露出的部分），不撒尘埃保持棋盘清晰
	g.add_child(UIKit.decor_bg(false))

	# 棋盘视口：整屏（四座在桌面世界四周，镜头避开顶栏与底部行动条）
	var board = BoardView.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.overlay_top = 46
	board.overlay_bottom = 70
	g.add_child(board)
	board.tile_clicked.connect(g._on_tile_clicked)
	board.seat_clicked.connect(func(peer: int) -> void:
		if peer == g.my_peer:
			board.go_home_follow(g.my_peer)  # 点自己座位卡：回自己视角并恢复镜头跟随
	)

	# 悬浮事件卡（非牌堆提示，屏幕空间不随视角旋转）
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(hud)

	var card_panel = UIKit.panel_container(Color(0.16, 0.14, 0.08, 0.94), 12, UIKit.ACCENT, 2, 10)
	card_panel.position = Vector2(12, 54)
	card_panel.size = Vector2(430, 96)
	card_panel.visible = false
	card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(card_panel)
	var cm := UIKit.margins(16, 14, 8, 8)
	cm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_panel.add_child(cm)
	var card_label = UIKit.label("", 15, UIKit.ACCENT)
	card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cm.add_child(card_label)


	# 牌垫阶段条（屏幕层，锚定自己座位卡下沿）：状态 / 回合两阶段 / 转动转盘
	var mat_bar = UIKit.panel_container(Color(0.058, 0.062, 0.098, 0.88), 12,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.55), 1, 6)
	mat_bar.custom_minimum_size = Vector2(440, 46)
	mat_bar.visible = false
	g.add_child(mat_bar)
	var mbm := UIKit.margins(12, 10, 7, 7)
	mat_bar.add_child(mbm)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	mbm.add_child(mrow)
	var status_label = UIKit.label("", 13, UIKit.TEXT)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mrow.add_child(status_label)
	var ph1 := UIKit.pill("① 转轮盘", UIKit.TEXT_DIM, 11)
	mrow.add_child(ph1)
	var ph_arrow := UIKit.label("→", 12, UIKit.TEXT_DIM)
	mrow.add_child(ph_arrow)
	var ph2 := UIKit.pill("② 使用道具", UIKit.TEXT_DIM, 11)
	mrow.add_child(ph2)
	var ph1_lab = g._pill_label(ph1)
	var ph2_lab = g._pill_label(ph2)
	var ph1_pill = ph1
	var ph2_pill = ph2
	var ph_arrow_l = ph_arrow

	# 操作条（屏幕层，与视角无关）：转动转盘 / 道具按钮。
	# 它原先挂在牌垫阶段条里，而阶段条在转离自己视角时会整条隐藏（牌垫贴自己
	# 座位卡，转到别人视角就跑到屏幕外）。于是「按 Tab 看别人」会把自己的掷骰
	# 按钮和道具栏一起收走，只能等 35 秒超时代掷（见 fix/v0.0.2）。
	# 拆成独立一层：自己视角时仍贴在自己座位卡下沿，转离视角时改贴屏幕底部。
	var action_bar = UIKit.panel_container(Color(0.058, 0.062, 0.098, 0.88), 12,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.55), 1, 6)
	action_bar.visible = false
	g.add_child(action_bar)
	var abm := UIKit.margins(10, 8, 7, 7)
	action_bar.add_child(abm)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 8)
	abm.add_child(arow)
	var roll_btn = UIKit.button("转动转盘", 15, "normal")
	roll_btn.disabled = true
	arow.add_child(roll_btn)
	var item_btn_box = HBoxContainer.new()
	item_btn_box.add_theme_constant_override("separation", 6)
	item_btn_box.visible = false
	arow.add_child(item_btn_box)

	# 小卖部操作条（行动者的屏幕层按钮；货架公开显示在桌面设施上）
	var shop_bar = UIKit.panel_container(Color(0.058, 0.062, 0.098, 0.88), 12,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.55), 1, 6)
	shop_bar.custom_minimum_size = Vector2(440, 46)
	shop_bar.visible = false
	g.add_child(shop_bar)
	var sbm := UIKit.margins(10, 8, 7, 7)
	shop_bar.add_child(sbm)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	sbm.add_child(srow)
	var shop_btns = []
	for i in 3:
		var b := UIKit.button("买", 12)
		b.visible = false
		var si := i
		b.pressed.connect(func() -> void:
			if g.multiplayer.is_server():
				g._shop_buy(g.my_peer, si)
			else:
				g.c_shop_buy.rpc(si)
		)
		srow.add_child(b)
		shop_btns.append(b)
	var shop_refresh_btn = UIKit.button("刷新", 12)
	shop_refresh_btn.pressed.connect(func() -> void:
		if g.multiplayer.is_server():
			g._shop_refresh(g.my_peer)
		else:
			g.c_shop_refresh.rpc()
	)
	srow.add_child(shop_refresh_btn)
	var leave_btn := UIKit.button("离开", 12)
	leave_btn.pressed.connect(func() -> void:
		if g.multiplayer.is_server():
			g._shop_leave(g.my_peer)
		else:
			g.c_shop_leave.rpc()
	)
	srow.add_child(leave_btn)

	# 黑市操作条（行动者屏幕层；货架不公开，只在行动者面板展示）
	var black_bar = UIKit.panel_container(Color(0.11, 0.055, 0.06, 0.93), 12,
		Color(0.96, 0.55, 0.3, 0.6), 1, 8)
	black_bar.custom_minimum_size = Vector2(360, 0)
	black_bar.visible = false
	g.add_child(black_bar)
	var bbm := UIKit.margins(12, 10, 10, 10)
	black_bar.add_child(bbm)
	var bbv := VBoxContainer.new()
	bbv.add_theme_constant_override("separation", 6)
	bbm.add_child(bbv)
	bbv.add_child(UIKit.label("黑市 · 只收地皮（紫1 / 橙2 / 刷新1 / 出口1）", 12, Color(0.98, 0.7, 0.4)))
	var black_btns = []
	for i in 3:
		var bb := UIKit.button("买", 12)
		var bi := i
		bb.pressed.connect(func() -> void:
			if g.multiplayer.is_server():
				g._black_buy(g.my_peer, bi)
			else:
				g.c_black_buy.rpc(bi)
		)
		bbv.add_child(bb)
		black_btns.append(bb)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)
	bbv.add_child(brow)
	var bref := UIKit.button("刷新（1地）", 12)
	bref.pressed.connect(func() -> void:
		if g.multiplayer.is_server():
			g._black_refresh(g.my_peer)
		else:
			g.c_black_refresh.rpc()
	)
	brow.add_child(bref)
	var bleave := UIKit.button("出口（1地）", 12)
	bleave.pressed.connect(func() -> void:
		if g.multiplayer.is_server():
			g._black_leave(g.my_peer)
		else:
			g.c_black_leave.rpc()
	)
	brow.add_child(bleave)
	var black_hint = UIKit.label("", 11, Color(0.95, 0.5, 0.45))
	black_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	black_hint.custom_minimum_size = Vector2(336, 0)
	bbv.add_child(black_hint)

	# 左上角：选项按钮（打开暂停菜单族，见 _build_menu_ui）
	var opt_btn = UIKit.button("☰ 选项", 13)
	opt_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	opt_btn.offset_left = 12
	opt_btn.offset_top = 10
	opt_btn.offset_right = 92
	opt_btn.offset_bottom = 38
	opt_btn.pressed.connect(g._open_menu)
	g.add_child(opt_btn)
	g._build_menu_ui()

	g.dev.build_panel()

	# 左下角：格子详情卡（点击棋盘格子弹出相关信息）
	var info_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 6)
	info_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	info_panel.offset_left = 14
	info_panel.offset_right = 356
	info_panel.offset_top = -196
	info_panel.offset_bottom = -66
	g.add_child(info_panel)
	var info_sb = UIKit.stylebox(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1)
	info_panel.add_theme_stylebox_override("panel", info_sb)
	var im := UIKit.margins(12, 10, 10, 10)
	info_panel.add_child(im)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 5)
	im.add_child(iv)
	var info_title = UIKit.label("操作提示", 16, UIKit.ACCENT)
	iv.add_child(info_title)
	var info_body = UIKit.label("滚轮缩放 · 拖拽平移 · 点格子看详情\n点对手座位卡或按 Tab 转到 TA 视角 · 空格回自己", 13, UIKit.TEXT)
	info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(info_body)

	# 右上：战报 / 聊天（可折叠，保持桌面干净）
	var log_toggle = UIKit.button("战报 ▴", 13)
	log_toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_toggle.offset_left = -106
	log_toggle.offset_right = -12
	log_toggle.offset_top = 12
	log_toggle.offset_bottom = 40
	log_toggle.pressed.connect(g._toggle_log)
	g.add_child(log_toggle)

	var log_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 6)
	log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_panel.offset_left = -352
	log_panel.offset_right = -12
	log_panel.offset_top = 46
	log_panel.offset_bottom = 780
	log_panel.visible = true
	g.add_child(log_panel)
	var lm := UIKit.margins(10, 10, 8, 8)
	log_panel.add_child(lm)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	lm.add_child(lv)
	var log_head = UIKit.label("第 1/30 轮 · 战报", 13, UIKit.TEXT_DIM)
	lv.add_child(log_head)
	var log_text = RichTextLabel.new()
	log_text.scroll_following = true
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.add_theme_font_size_override("normal_font_size", 13)
	lv.add_child(log_text)
	var chat_row := HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 6)
	lv.add_child(chat_row)
	var chat_edit = UIKit.line_edit("聊天…（回车发送）")
	chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_edit.text_submitted.connect(func(_t: String) -> void:
		Net.send_chat(chat_edit.text)
		chat_edit.clear()
	)
	chat_row.add_child(chat_edit)
	var send_btn := UIKit.button("发送", 14)
	send_btn.pressed.connect(func() -> void:
		Net.send_chat(chat_edit.text)
		chat_edit.clear()
	)
	chat_row.add_child(send_btn)

# ================= 房主：初始化与主循环 =================

## 由大厅名册构造对局玩家表。注意把「没真正连上」的玩家标成机器人：
## 大厅→对局有约 0.4 秒淡出窗口，期间掉线的玩家若仍记为真人，
## 他每一手都要等满 35 秒超时才对局才推进（见 fix/v0.0.2）。

	return {
		"action_bar": action_bar,
		"black_bar": black_bar,
		"black_btns": black_btns,
		"black_hint": black_hint,
		"board": board,
		"card_label": card_label,
		"card_panel": card_panel,
		"chat_edit": chat_edit,
		"info_body": info_body,
		"info_panel": info_panel,
		"info_sb": info_sb,
		"info_title": info_title,
		"item_btn_box": item_btn_box,
		"log_head": log_head,
		"log_panel": log_panel,
		"log_text": log_text,
		"log_toggle": log_toggle,
		"mat_bar": mat_bar,
		"opt_btn": opt_btn,
		"ph_arrow_l": ph_arrow_l,
		"ph1_lab": ph1_lab,
		"ph1_pill": ph1_pill,
		"ph2_lab": ph2_lab,
		"ph2_pill": ph2_pill,
		"roll_btn": roll_btn,
		"shop_bar": shop_bar,
		"shop_btns": shop_btns,
		"shop_refresh_btn": shop_refresh_btn,
		"status_label": status_label,
	}
