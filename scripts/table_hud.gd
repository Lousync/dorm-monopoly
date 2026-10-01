class_name TableHud
extends RefCounted
## 对局内 HUD 的全部控件构建 —— 从 game.gd 的 _build_ui / _build_menu_ui 整段搬出
##（见审查结论：这里原本 ~500 行全是控件搭建，和对局状态机挤在一个文件里）。
##
## 控件直接写回宿主的同名成员（g.mat_bar = ...），而不是返回局部变量：
## 原代码里存在「先用后建」的引用（回调里用 vol_slider，而它几十行之后才创建），
## 那正是靠成员变量的晚绑定才成立的；换成局部变量会被 lambda 按值捕获成 null。

## 建整个对局界面（原 _build_ui）
static func build_play_ui(g: Node) -> void:
	# 纯渐变氛围底（棋盘外露出的部分），不撒尘埃保持棋盘清晰
	g.add_child(UIKit.decor_bg(false))

	# 棋盘视口：整屏（四座在桌面世界四周，镜头避开顶栏与底部行动条）
	g.board = BoardView.new()
	g.board.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.board.overlay_top = 46
	g.board.overlay_bottom = 70
	g.add_child(g.board)
	g.board.tile_clicked.connect(g._on_tile_clicked)
	# 点桌面货架卡直接买（来自 main 的「货架可点即买」，合并时这段连接随 _build_ui 搬到了这里）
	g.board.shop_slot_clicked.connect(func(slot: int) -> void:
		if int(g.st.get("shop_peer", 0)) != g.my_peer:
			return
		if g.multiplayer.is_server():
			g._shop_buy(g.my_peer, slot)
		else:
			g.c_shop_buy.rpc(slot)
	)
	g.board.seat_clicked.connect(func(peer: int) -> void:
		if peer == g.my_peer:
			g.board.go_home_follow(g.my_peer)  # 点自己座位卡：回自己视角并恢复镜头跟随
	)

	# 悬浮事件卡（非牌堆提示，屏幕空间不随视角旋转）
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(hud)

	g.card_panel = UIKit.panel_container(Color(0.16, 0.14, 0.08, 0.94), 12, UIKit.ACCENT, 2, 10)
	g.card_panel.position = Vector2(12, 54)
	g.card_panel.size = Vector2(430, 96)
	g.card_panel.visible = false
	g.card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(g.card_panel)
	var cm := UIKit.margins(16, 14, 8, 8)
	cm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.card_panel.add_child(cm)
	g.card_label = UIKit.label("", 15, UIKit.ACCENT)
	g.card_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g.card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	g.card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cm.add_child(g.card_label)


	# 牌垫阶段条（屏幕层，锚定自己座位卡下沿）：状态 / 回合两阶段 / 转动转盘
	g.mat_bar = UIKit.panel_container(Color(0.058, 0.062, 0.098, 0.88), 12,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.55), 1, 6)
	g.mat_bar.custom_minimum_size = Vector2(440, 46)
	g.mat_bar.visible = false
	g.add_child(g.mat_bar)
	var mbm := UIKit.margins(12, 10, 7, 7)
	g.mat_bar.add_child(mbm)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	mbm.add_child(mrow)
	g.status_label = UIKit.label("", 13, UIKit.TEXT)
	g.status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mrow.add_child(g.status_label)
	var ph1 := UIKit.pill("① 转轮盘", UIKit.TEXT_DIM, 11)
	mrow.add_child(ph1)
	var ph_arrow := UIKit.label("→", 12, UIKit.TEXT_DIM)
	mrow.add_child(ph_arrow)
	var ph2 := UIKit.pill("② 使用道具", UIKit.TEXT_DIM, 11)
	mrow.add_child(ph2)
	g.ph1_lab = g._pill_label(ph1)
	g.ph2_lab = g._pill_label(ph2)
	g.ph1_pill = ph1
	g.ph2_pill = ph2
	g.ph_arrow_l = ph_arrow

	# 操作条（屏幕层，与视角无关）：转动转盘 / 道具按钮。
	# 它原先挂在牌垫阶段条里，而阶段条在转离自己视角时会整条隐藏（牌垫贴自己
	# 座位卡，转到别人视角就跑到屏幕外）。于是「按 Tab 看别人」会把自己的掷骰
	# 按钮和道具栏一起收走，只能等 35 秒超时代掷（见 fix/v0.0.2）。
	# 拆成独立一层：自己视角时仍贴在自己座位卡下沿，转离视角时改贴屏幕底部。
	g.action_bar = UIKit.panel_container(Color(0.058, 0.062, 0.098, 0.88), 12,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.55), 1, 6)
	g.action_bar.visible = false
	g.add_child(g.action_bar)
	var abm := UIKit.margins(10, 8, 7, 7)
	g.action_bar.add_child(abm)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 8)
	abm.add_child(arow)
	g.roll_btn = UIKit.with_icon(UIKit.button("转动转盘", 15, "primary"), "dice", 20)
	g.roll_btn.disabled = true
	arow.add_child(g.roll_btn)
	g.item_btn_box = HBoxContainer.new()
	g.item_btn_box.add_theme_constant_override("separation", 6)
	g.item_btn_box.visible = false
	arow.add_child(g.item_btn_box)

	# 小卖部操作条（行动者的屏幕层按钮；货架公开显示在桌面设施上）
	g.shop_bar = UIKit.panel_container(Color(0.058, 0.062, 0.098, 0.88), 12,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.55), 1, 6)
	g.shop_bar.custom_minimum_size = Vector2(440, 46)
	g.shop_bar.visible = false
	g.add_child(g.shop_bar)
	var sbm := UIKit.margins(10, 8, 7, 7)
	g.shop_bar.add_child(sbm)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	sbm.add_child(srow)
	g.shop_btns = []
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
		g.shop_btns.append(b)
	g.shop_refresh_btn = UIKit.button("刷新", 12)
	g.shop_refresh_btn.pressed.connect(func() -> void:
		if g.multiplayer.is_server():
			g._shop_refresh(g.my_peer)
		else:
			g.c_shop_refresh.rpc()
	)
	srow.add_child(g.shop_refresh_btn)
	var leave_btn := UIKit.button("离开", 12)
	leave_btn.pressed.connect(func() -> void:
		if g.multiplayer.is_server():
			g._shop_leave(g.my_peer)
		else:
			g.c_shop_leave.rpc()
	)
	srow.add_child(leave_btn)

	# 黑市操作条（行动者屏幕层；货架不公开，只在行动者面板展示）
	g.black_bar = UIKit.panel_container(Color(0.11, 0.055, 0.06, 0.93), 12,
		Color(0.96, 0.55, 0.3, 0.6), 1, 8)
	g.black_bar.custom_minimum_size = Vector2(360, 0)
	g.black_bar.visible = false
	g.add_child(g.black_bar)
	var bbm := UIKit.margins(12, 10, 10, 10)
	g.black_bar.add_child(bbm)
	var bbv := VBoxContainer.new()
	bbv.add_theme_constant_override("separation", 6)
	bbm.add_child(bbv)
	bbv.add_child(UIKit.label("黑市 · 只收地皮（紫1 / 橙2 / 刷新1 / 出口1）", 12, Color(0.98, 0.7, 0.4)))
	g.black_btns = []
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
		g.black_btns.append(bb)
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
	g.black_hint = UIKit.label("", 11, Color(0.95, 0.5, 0.45))
	g.black_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g.black_hint.custom_minimum_size = Vector2(336, 0)
	bbv.add_child(g.black_hint)

	# 左上角：暂停按钮（打开暂停菜单族，见 g._build_menu_ui）
	g.opt_btn = UIKit.with_icon(UIKit.button("暂停", 13), "pause", 15)
	g.opt_btn.tooltip_text = "暂停对局（房主暂停全场）"
	g.opt_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	g.opt_btn.offset_left = 12
	g.opt_btn.offset_top = 10
	g.opt_btn.offset_right = 92
	g.opt_btn.offset_bottom = 38
	g.opt_btn.pressed.connect(g._open_menu)
	g.add_child(g.opt_btn)
	g._build_menu_ui()

	g.dev.build_panel()

	# 左下角：格子详情卡（点击棋盘格子弹出）。
	# 原先这块是常驻的「操作提示」文本；现改为默认隐藏，操作提示与完整规则
	# 收进左下角的「📖 规则说明」面板（见 rules_panel.gd / rules_text.gd）。
	g.info_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 6)
	g.info_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	g.info_panel.offset_left = 14
	g.info_panel.offset_right = 356
	g.info_panel.offset_top = -196
	g.info_panel.offset_bottom = -66
	g.info_panel.visible = false
	g.add_child(g.info_panel)
	g.info_sb = UIKit.stylebox(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1)
	g.info_panel.add_theme_stylebox_override("panel", g.info_sb)
	var im := UIKit.margins(12, 10, 10, 10)
	g.info_panel.add_child(im)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 5)
	im.add_child(iv)
	g.info_title = UIKit.label("格子详情", 16, UIKit.ACCENT)
	iv.add_child(g.info_title)
	g.info_body = UIKit.label("点棋盘上任意格子看详情", 13, UIKit.TEXT)
	g.info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(g.info_body)

	# 右上：战报 / 聊天（可折叠，保持桌面干净）
	g.log_toggle = UIKit.with_icon(UIKit.button("战报 ▴", 13), "report", 17)
	g.log_toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	g.log_toggle.offset_left = -106
	g.log_toggle.offset_right = -12
	g.log_toggle.offset_top = 12
	g.log_toggle.offset_bottom = 40
	g.log_toggle.pressed.connect(g._toggle_log)
	g.add_child(g.log_toggle)

	g.log_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 6)
	g.log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# 宽度 300（原 340）：右侧栏太宽时底部操作条会被它压住，
	# 见 game.gd:_dock_band（底栏按可用带夹位）
	g.log_panel.offset_left = -300
	g.log_panel.offset_right = -12
	g.log_panel.offset_top = 46
	g.log_panel.offset_bottom = 780
	g.log_panel.visible = true
	g.add_child(g.log_panel)
	var lm := UIKit.margins(10, 10, 8, 8)
	g.log_panel.add_child(lm)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	lm.add_child(lv)
	g.log_head = UIKit.label("第 1/30 轮 · 战报", 13, UIKit.TEXT_DIM)
	lv.add_child(g.log_head)
	g.log_text = RichTextLabel.new()
	g.log_text.scroll_following = true
	g.log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	g.log_text.add_theme_font_size_override("normal_font_size", 13)
	lv.add_child(g.log_text)
	var chat_row := HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 6)
	lv.add_child(chat_row)
	g.chat_edit = UIKit.line_edit("聊天…（回车发送）")
	g.chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.chat_edit.text_submitted.connect(func(_t: String) -> void:
		Net.send_chat(g.chat_edit.text)
		g.chat_edit.clear()
	)
	chat_row.add_child(g.chat_edit)
	var send_btn := UIKit.button("发送", 14)
	send_btn.pressed.connect(func() -> void:
		Net.send_chat(g.chat_edit.text)
		g.chat_edit.clear()
	)
	chat_row.add_child(send_btn)

# ================= 房主：初始化与主循环 =================

## 由大厅名册构造对局玩家表。注意把「没真正连上」的玩家标成机器人：
## 大厅→对局有约 0.4 秒淡出窗口，期间掉线的玩家若仍记为真人，
## 他每一手都要等满 35 秒超时才对局才推进（见 fix/v0.0.2）。

## 暂停菜单 / 设置面板 / 各种选择器（原 _build_menu_ui）
static func build_menu_ui(g: Node) -> void:
	g.menu_layer = Control.new()
	g.menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ALWAYS 而非 WHEN_PAUSED：非房主本地打开菜单时对局仍在跑，菜单必须可交互
	g.menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	g.menu_layer.visible = false
	g.add_child(g.menu_layer)

	# 全屏压暗底：视觉上压暗棋盘，同时替菜单吞掉落在面板外的点击（模态）
	g.menu_dim = ColorRect.new()
	g.menu_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.menu_dim.color = Color(0.03, 0.035, 0.062, 0.62)
	g.menu_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	g.menu_layer.add_child(g.menu_dim)

	# 面板名 -> {wrap, panel}，构建完三块面板后统一登记（见本函数末尾）
	g.menu_wraps = {}

	# 非房主看到的「房主已暂停」遮罩
	g.pause_mask = ColorRect.new()
	g.pause_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.pause_mask.color = Color(0.03, 0.03, 0.07, 0.62)
	g.pause_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.pause_mask.visible = false
	g.pause_mask.process_mode = Node.PROCESS_MODE_ALWAYS
	g.add_child(g.pause_mask)
	var pm_lab := UIKit.label("⏸ 房主已暂停 · 等待继续…", 20, UIKit.ACCENT)
	pm_lab.set_anchors_preset(Control.PRESET_FULL_RECT)
	pm_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pm_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pm_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.pause_mask.add_child(pm_lab)

	# 主菜单：继续 / 设置 / 退出
	var mc := CenterContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.menu_layer.add_child(mc)
	g.menu_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.9), 1, 10)
	g.menu_panel.custom_minimum_size = Vector2(320, 0)
	mc.add_child(g.menu_panel)
	var mm := UIKit.margins(20, 20, 16, 14)
	g.menu_panel.add_child(mm)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	mm.add_child(mv)
	g.menu_state = UIKit.label("", 13, UIKit.TEXT_DIM)
	mv.add_child(g.menu_state)
	var cont_btn := UIKit.button("▶ 继续游戏", 15)
	cont_btn.pressed.connect(g._menu_resume)
	mv.add_child(cont_btn)
	var set_btn := UIKit.with_icon(UIKit.button("设置", 15), "gear", 18)
	set_btn.pressed.connect(func() -> void:
		g.vol_slider.value = g.audio_volume * 100.0
		g.mute_check.button_pressed = g.audio_mute
		g._menu_show("settings")
	)
	mv.add_child(set_btn)
	var quit_btn := UIKit.button("⏻ 退出游戏", 15, "danger")
	quit_btn.pressed.connect(func() -> void:
		g.confirm_note.text = "你是房主：退出后对局结束，所有人回到主菜单。" \
			if g.multiplayer.is_server() else "退出后你的回合将由机器人接管，对局继续。"
		g._menu_show("confirm")
	)
	mv.add_child(quit_btn)

	# 设置：音量 / 静音（后续会加更多设置项）
	var sc := CenterContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.menu_layer.add_child(sc)
	g.settings_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.9), 1, 10)
	g.settings_panel.custom_minimum_size = Vector2(320, 0)
	sc.add_child(g.settings_panel)
	var sm := UIKit.margins(20, 20, 16, 14)
	g.settings_panel.add_child(sm)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	sm.add_child(sv)
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 10)
	sv.add_child(vol_row)
	vol_row.add_child(UIKit.label("音效音量", 14, UIKit.TEXT))
	g.vol_slider = HSlider.new()
	g.vol_slider.min_value = 0
	g.vol_slider.max_value = 100
	g.vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.vol_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.vol_slider.value_changed.connect(func(v: float) -> void:
		g.audio_volume = v / 100.0
		g._apply_audio()
	)
	vol_row.add_child(g.vol_slider)
	var mute_row := HBoxContainer.new()
	mute_row.add_theme_constant_override("separation", 10)
	sv.add_child(mute_row)
	mute_row.add_child(UIKit.label("静音", 14, UIKit.TEXT))
	g.mute_check = CheckButton.new()
	g.mute_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.mute_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.mute_check.toggled.connect(func(on: bool) -> void:
		g.audio_mute = on
		g._apply_audio()
	)
	mute_row.add_child(g.mute_check)
	sv.add_child(UIKit.label("—— 更多设置项（后续加入） ——", 12, UIKit.TEXT_DIM))
	var back_btn := UIKit.button("‹ 返回", 14)
	back_btn.pressed.connect(func() -> void: g._menu_show("menu"))
	sv.add_child(back_btn)

	# 退出二次确认
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.menu_layer.add_child(cc)
	g.confirm_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(UIKit.DANGER.r, UIKit.DANGER.g, UIKit.DANGER.b, 0.75), 1, 10)
	g.confirm_panel.custom_minimum_size = Vector2(320, 0)
	cc.add_child(g.confirm_panel)
	var cm2 := UIKit.margins(20, 20, 16, 14)
	g.confirm_panel.add_child(cm2)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cm2.add_child(cv)
	cv.add_child(UIKit.label("确定要退出本局吗？", 15, UIKit.TEXT))
	g.confirm_note = UIKit.label("", 12, UIKit.TEXT_DIM)
	g.confirm_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(g.confirm_note)
	var cbtn_row := HBoxContainer.new()
	cbtn_row.add_theme_constant_override("separation", 10)
	cv.add_child(cbtn_row)
	var cancel_btn := UIKit.button("取消", 14)
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(func() -> void: g._menu_show("menu"))
	cbtn_row.add_child(cancel_btn)
	var sure_btn := UIKit.button("确认退出", 14, "danger")
	sure_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sure_btn.pressed.connect(func() -> void:
		g.get_tree().paused = false
		g._on_exit()
	)
	cbtn_row.add_child(sure_btn)

	# 面板名 -> {外层全屏容器, 内层面板}。切换一律走 game.gd:_menu_show，
	# 它把两者一起切；漏切外层 = 整屏点击被那个全屏 STOP 容器吃光（见 fix/v0.1.0）
	g.menu_wraps = {
		"menu": {"wrap": mc, "panel": g.menu_panel},
		"settings": {"wrap": sc, "panel": g.settings_panel},
		"confirm": {"wrap": cc, "panel": g.confirm_panel},
	}

	# 置顶：压暗底与菜单要盖住棋盘 / 战报栏 / 底部操作条。它们都是本函数之后才
	# 加进 game 的子节点，不置顶的话只有棋盘被压暗，两侧栏和底栏仍是亮的。
	# 置顶同时保证「谁吃鼠标」与「谁在上层」一致（见 fix/v0.1.0 的暂停卡死）。
	g.move_child(g.menu_layer, g.get_child_count() - 1)

	# 作弊器点数选框（0~12，本地弹出）
	g.cheat_picker = Control.new()
	g.cheat_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.cheat_picker.visible = false
	g.add_child(g.cheat_picker)
	var cd_dim := ColorRect.new()
	cd_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd_dim.color = Color(0.04, 0.04, 0.08, 0.55)
	g.cheat_picker.add_child(cd_dim)
	var cc2 := CenterContainer.new()
	cc2.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.cheat_picker.add_child(cc2)
	var cp := UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.8), 1, 10)
	cc2.add_child(cp)
	var cpm := UIKit.margins(20, 20, 14, 12)
	cp.add_child(cpm)
	var cv2 := VBoxContainer.new()
	cv2.add_theme_constant_override("separation", 8)
	cpm.add_child(cv2)
	cv2.add_child(UIKit.label("选定下一次转盘点数（0~12）", 14, UIKit.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	cv2.add_child(grid)
	for v in 13:
		var vb := UIKit.button(str(v), 14)
		var vv := v
		vb.pressed.connect(func() -> void:
			g._send_use_item(g.cheat_slot, vv)
		)
		grid.add_child(vb)
	var cv_cancel := UIKit.button("取消", 13)
	cv_cancel.pressed.connect(g._close_cheat_picker)
	cv2.add_child(cv_cancel)

	# 目标玩家选择器（交换生等选玩家类道具）
	g.target_picker = Control.new()
	g.target_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.target_picker.visible = false
	g.add_child(g.target_picker)
	var td_dim := ColorRect.new()
	td_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	td_dim.color = Color(0.04, 0.04, 0.08, 0.55)
	g.target_picker.add_child(td_dim)
	var tc := CenterContainer.new()
	tc.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.target_picker.add_child(tc)
	var tp := UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(0.66, 0.47, 0.92, 0.8), 1, 10)
	tp.custom_minimum_size = Vector2(320, 0)
	tc.add_child(tp)
	var tpm := UIKit.margins(20, 20, 14, 12)
	tp.add_child(tpm)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 8)
	tpm.add_child(tv)
	tv.add_child(UIKit.label("选择目标玩家", 14, UIKit.ACCENT))
	g.target_btn_box = VBoxContainer.new()
	g.target_btn_box.add_theme_constant_override("separation", 6)
	tv.add_child(g.target_btn_box)
	var tv_cancel := UIKit.button("取消", 13)
	tv_cancel.pressed.connect(g._close_target_picker)
	tv.add_child(tv_cancel)

	# 黑市交地选择器（逐块选自有地皮抵账）
	g.black_picker = Control.new()
	g.black_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.black_picker.visible = false
	g.add_child(g.black_picker)
	var bd_dim := ColorRect.new()
	bd_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	bd_dim.color = Color(0.04, 0.03, 0.05, 0.6)
	g.black_picker.add_child(bd_dim)
	var bcc := CenterContainer.new()
	bcc.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.black_picker.add_child(bcc)
	var bcp := UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(0.96, 0.55, 0.3, 0.85), 1, 10)
	bcp.custom_minimum_size = Vector2(340, 0)
	bcc.add_child(bcp)
	var bcpm := UIKit.margins(20, 20, 14, 12)
	bcp.add_child(bcpm)
	var bcv := VBoxContainer.new()
	bcv.add_theme_constant_override("separation", 8)
	bcpm.add_child(bcv)
	bcv.add_child(UIKit.label("选择要交出的地皮", 14, Color(0.98, 0.7, 0.4)))
	g.black_picker_box = VBoxContainer.new()
	g.black_picker_box.add_theme_constant_override("separation", 6)
	bcv.add_child(g.black_picker_box)

