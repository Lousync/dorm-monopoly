class_name TableHud
extends RefCounted
## 对局内 HUD 的全部控件构建 —— 从 game.gd 的 _build_ui / _build_menu_ui 整段搬出
##（见审查结论：这里原本 ~500 行全是控件搭建，和对局状态机挤在一个文件里）。
##
## 控件直接写回宿主的同名成员（g.log_toast = ...），而不是返回局部变量：
## 原代码里存在「先用后建」的引用（回调里用 vol_slider，而它几十行之后才创建），
## 那正是靠成员变量的晚绑定才成立的；换成局部变量会被 lambda 按值捕获成 null。

## 造一条战报弹出条（屏幕上方居中）。淡入淡出与回收由 game.gd:_push_log_toast 负责。
## 行文本已是 BBCode 安全串（game.gd:_log 把 `[` 转义成 `［`），可直接外包一层 [center]。
static func make_log_toast(line: String) -> Control:
	var pill := UIKit.panel_container(Color(0.055, 0.065, 0.098, 0.88), 10, Color(0, 0, 0, 0), 0, 5)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var m := UIKit.margins(14, 6, 5, 5)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(m)
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.add_theme_font_size_override("normal_font_size", 15)
	# 必须关掉自动换行：RichTextLabel 的最小宽度默认是 0，配合 SHRINK_CENTER
	# 会被挤成一条几乎不可见的窄条。关掉后最小宽度 = 整行文本宽度，气泡才裹得住字。
	rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rtl.text = "[center]%s[/center]" % line
	m.add_child(rtl)
	return pill

## 建整个对局界面（原 _build_ui）
static func build_play_ui(g: Node) -> void:
	# 原来这里铺一张全屏不透明的渐变氛围底（UIKit.decor_bg）。2.5D 之后必须去掉：
	# Godot 里 2D 画布一律合成在 3D 之上，一层铺满屏幕的不透明 Control 会把整张 3D 桌面
	# 整个盖掉（实测：出图只剩渐变，桌子完全看不见）。桌面之外的暗色房间现在由容器里的
	# WorldEnvironment 背景色承担（见 table_3d.gd:_build_environment）。

	# 棋盘视口：2.5D 桌面容器 —— BoardView 住在容器的 SubViewport 里，贴到 3D 桌面上
	g.table3d = TableView3D.new()
	g.add_child(g.table3d)
	g.board = g.table3d.board
	g.board.tile_clicked.connect(g._on_tile_clicked)
	# `seat_clicked` 自批次 5 Task 2 起**没有发射方**了（座位卡退场；"点玩家"批次 9 起由屏幕层
	# 四角身家条直调 `_on_seat_clicked`）。连接保留：它接的是玩法入口，接口不动（同
	# board_view 里 item_slot_clicked 那条先例）。
	g.board.seat_clicked.connect(g._on_seat_clicked)

	# 屏幕层暗角：铺满屏幕、四角压暗（Compatibility 没有 SSAO/景深，氛围靠它补）。
	# 挂在 hud 层之前 —— 压暗 3D 桌面，但不能盖住底栏/名册等屏幕层控件。
	g.table3d.build_vignette(g)

	# 屏幕层：不随摄像机旋转的悬浮控件都挂这里
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(hud)
	# 记一份到 game 上（批次 11 Task 3）：屏幕层容器本身此前只有局部变量，而"悬停信息条挂在
	# **屏幕层**"这条要靠它才断言得出来（`hud_test` 读 `g.hud_layer`）。不改任何行为，只是把
	# 那个容器从一个局部量变成可引用的成员。
	g.hud_layer = hud

	# ---- 悬停棋子的信息条（批次 11 Task 3）----
	# 悬停到桌面上一枚棋子时浮出「昵称 / 身家 / 名次 / 已出局」。**内容与判据一字未改**：
	# 原先它是画布里的一个 PanelContainer（`board_view._token_tip`，批次 11 Task 1 随棋子一起删了），
	# 载体从**画布**搬到**屏幕层**的原因就是用户报的那句「角度不对」——画布上的 Control 随桌垫
	# 一起倾斜、被透视缩小（3D 端读着是歪的）；屏幕层 Control 天然面向镜头。
	# 数据源仍是 `board._peers_info`（`game._on_table_hover` 里读，**单一来源**，不另取 standing）。
	#
	# **z_index = 30 —— 写之前核对过屏幕层现有的 z**（批次 8/9 的 R5 教训）：
	#   屏幕 HUD 带（≤40）：四角身家条 / 动作按钮 / 战报开关与战报栏 / 格详情卡 / 黑市条 **全是 0**
	#      （相对 hud，hud 自身 0），抽卡大字卡 `DeckReveal` **40**；
	#   模态带：玩家道具弹窗 45 / 结算 50 / 弹问 60 / 小卖部与赌场 70 / 菜单与暂停遮罩 80；
	#   特效：飞钞 90 / 飘字 90~95。
	#   取 30 ⇒ 压在那一整片 **0** 之上（设计 §5.4 的「不该被四角身家条与动作按钮盖住」），
	#   又低于抽卡大字卡与所有模态（演出与模态该压住悬停提示）。**别改回 0**：同为 0 时谁在上
	#   由树序决定（`z_as_relative` 默认为真），建节点的顺序一变就会漂 —— 批次 8 的教训。
	# 鼠标透明（`IGNORE`）：它只是个提示，不参与拾取 —— 四角条 / 动作按钮的点击一律穿透过去。
	g.token_tip = UIKit.panel_container(Color(0.055, 0.065, 0.098, 0.94), 10,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.9), 1, 6)
	g.token_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.token_tip.z_index = 30
	g.token_tip.visible = false
	hud.add_child(g.token_tip)
	var ttm := UIKit.margins(12, 12, 7, 7)
	ttm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.token_tip.add_child(ttm)
	var ttv := VBoxContainer.new()
	ttv.add_theme_constant_override("separation", 2)
	ttv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ttm.add_child(ttv)
	g._tip_name = UIKit.label("", 15, UIKit.TEXT)
	g._tip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ttv.add_child(g._tip_name)
	g._tip_sub = UIKit.label("", 12, UIKit.TEXT_DIM)
	g._tip_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ttv.add_child(g._tip_sub)


	# 顶部居中：战报消息弹出条容器。战报框默认收起，消息改在这里飘一条；
	# 顶部左右两角已被暂停按钮与战报开关占掉，中间这块是空的。
	g.log_toast = VBoxContainer.new()
	g.log_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	g.log_toast.offset_left = -390.0
	g.log_toast.offset_right = 390.0
	g.log_toast.offset_top = 52.0
	g.log_toast.offset_bottom = 300.0
	g.log_toast.add_theme_constant_override("separation", 4)
	g.log_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(g.log_toast)

	# 顶部**水平居中**的「畸变生效中」横幅（批次 12 D3 / 设计 §⑫：从右上角搬到中间）。
	# **"中间"= 不再贴右上角**，不是屏幕正中 —— 真放正中会盖住棋盘中心与格详情卡。
	# 落位：`y ≈ 6..48`，**在战报气泡（y ≥ 52）之上**。
	# **批次 13 ② 起名册条搬到了左上角（x ≈ 104..250、y ≈ 10..214）** ⇒ 它与横幅**同占 y 6..48
	# 这一带**，靠 x 分开：横幅是**居中**的（实测宽 200~600 ⇒ 左缘 ≥ 490），够不到 250。
	# `hud_test` 里那条"横幅不与名册条 / 三个角按钮重叠"同时核条本身与每一格，就是钉这件事。
	# 外包一层 `CenterContainer` 才能"贴内容宽度 + 居中"：`PanelContainer` 自己按锚点铺满，
	# 直接给 `CENTER_TOP` 会得到一条固定宽度的长条（文案短时两侧一大片空、还压住更多屏幕）。
	# 显隐仍由 `game._refresh_ab_ui` 只管 `ab_label.visible`（外层容器留着不吃鼠标、不画东西）。
	g.ab_wrap = CenterContainer.new()
	g.ab_wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	g.ab_wrap.offset_top = 6.0
	g.ab_wrap.offset_bottom = 48.0
	g.ab_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(g.ab_wrap)
	g.ab_label = UIKit.panel_container(Color(0.055, 0.065, 0.098, 0.88), 10, Color(0, 0, 0, 0), 0, 5)
	g.ab_label.visible = false
	g.ab_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ab_lm := UIKit.margins(12, 5, 4, 4)
	ab_lm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.ab_label.add_child(ab_lm)
	g.ab_label_l = UIKit.label("", 14, Color("#f0c064"))
	ab_lm.add_child(g.ab_label_l)
	g.ab_wrap.add_child(g.ab_label)


	# 屏幕底部的操作坞（牌垫阶段条 + 操作条 + 共用底板）已随批次 3 Task 6 整条拆除：
	# 掷轮改点桌面上的转盘实体、出牌改点手中牌（批次 7 起再点一下直出）、现金与体力在桌上。
	# 所以这里不再建 mat_bar / action_bar / dock_plate / roll_btn /
	# use_phase_btn / item_btn_box / status_label —— 玩家侧的操作入口只剩桌面上那些实体
	# 与下方的右下角动作按钮（`g.action_btn`）。
	# 注意别顺手把 `_place_overlay_bar`（黑市还在用）也删了。

	# 小卖部全屏界面（触发时独占；照 menu_layer 那套：全屏压暗底 + 居中面板，两者一起显隐）
	g.shop_layer = Control.new()
	g.shop_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.shop_layer.visible = false
	# 高于其它**屏幕层**控件（弹问 60 / 结算 50），否则会被它们压在压暗底之下。
	# 注意：不必再「盖住 board 内部元素」——棋盘住在 SubViewport 里，棋子 20 / 光环 15
	# 那份 z_index 不再跨层穿帮（见 doc/development/架构总览.md §五）。70 这个值保持不变。
	g.shop_layer.z_index = 70
	g.add_child(g.shop_layer)

	var sdim := ColorRect.new()
	sdim.set_anchors_preset(Control.PRESET_FULL_RECT)
	sdim.color = Color(0.03, 0.035, 0.062, 0.72)
	sdim.mouse_filter = Control.MOUSE_FILTER_STOP   # 模态：吞掉落在面板外的点击
	g.shop_layer.add_child(sdim)

	var sc := CenterContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 只有面板吃点击
	g.shop_layer.add_child(sc)

	g.shop_panel = UIKit.panel_container(Color(0.135, 0.095, 0.06, 0.99), 18,
		Color(0.5, 0.36, 0.18), 2, 16)
	g.shop_panel.custom_minimum_size = Vector2(760, 0)
	sc.add_child(g.shop_panel)
	var spm := UIKit.margins(24, 24, 20, 20)
	g.shop_panel.add_child(spm)
	var spv := VBoxContainer.new()
	spv.add_theme_constant_override("separation", 14)
	spm.add_child(spv)

	# 标题行：图标 + 店名 + 右端当前格位说明
	var shead := HBoxContainer.new()
	shead.add_theme_constant_override("separation", 12)
	spv.add_child(shead)
	var sh_icon := TextureRect.new()
	sh_icon.texture = UIKit.icon("daily")
	sh_icon.custom_minimum_size = Vector2(32, 32)
	sh_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sh_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shead.add_child(sh_icon)
	shead.add_child(UIKit.label("小卖部", 26, Color(0.93, 0.88, 0.75)))
	# 现金读数：买按钮置灰时看得出理由（钱不够 / 背包满），不必回头看座位卡
	g.shop_money_l = UIKit.label("", 17, Color(0.95, 0.86, 0.55))
	shead.add_child(g.shop_money_l)
	var sh_sp := Control.new()
	sh_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shead.add_child(sh_sp)
	g.shop_tile_l = UIKit.label("", 14, Color(0.78, 0.7, 0.58))
	shead.add_child(g.shop_tile_l)

	# 「XX 正在挑选」说明条（批次 12 C2 / 设计 §⑧）：小卖部改为**全员可见**之后，
	# 非本人看到的是同一份货架、但**只读**（买 / 刷新 / 离开全置灰）。没有这条，
	# 旁观者只会看到一堆点不动的按钮，不知道发生了什么。
	g.shop_watch_l = UIKit.label("", 15, UIKit.ACCENT)
	g.shop_watch_l.visible = false
	spv.add_child(g.shop_watch_l)

	# 三格货架：卡面 + 价格 + 买按钮
	var sshelf := HBoxContainer.new()
	sshelf.add_theme_constant_override("separation", 20)
	sshelf.alignment = BoxContainer.ALIGNMENT_CENTER
	spv.add_child(sshelf)
	g.shop_cards = []
	g.shop_btns = []
	for i in 3:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		sshelf.add_child(col)
		var holder := CenterContainer.new()          # 空/有货都占同样大，面板不跳
		holder.custom_minimum_size = Vector2(150, 210)
		col.add_child(holder)
		var price_l := UIKit.label("空货位", 13, Color(0.78, 0.7, 0.58))
		price_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(price_l)
		var b := UIKit.button("买", 13)
		b.visible = false
		var bi := i
		b.pressed.connect(func() -> void:
			if g.multiplayer.is_server():
				g._shop_buy(g.my_peer, bi)
			else:
				g.c_shop_buy.rpc(bi)
		)
		col.add_child(b)
		g.shop_cards.append({"holder": holder, "price_l": price_l})
		g.shop_btns.append(b)

	# 底行：品质图例 + 刷新 + 离开
	var sfoot := HBoxContainer.new()
	sfoot.add_theme_constant_override("separation", 10)
	spv.add_child(sfoot)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 5)
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfoot.add_child(legend)
	for qi in ItemData.QUALITIES.size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(13, 13)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.add_theme_stylebox_override("panel", UIKit.stylebox(
			ItemData.QUALITY_COLORS[ItemData.QUALITIES[qi]], 6, Color(0, 0, 0, 0.4), 1))
		legend.add_child(dot)
		legend.add_child(UIKit.label(ItemData.QUALITY_NAMES[ItemData.QUALITIES[qi]], 13,
			Color(0.78, 0.7, 0.58)))
	g.shop_refresh_btn = UIKit.button("刷新", 14)
	g.shop_refresh_btn.pressed.connect(func() -> void:
		if g.multiplayer.is_server():
			g._shop_refresh(g.my_peer)
		else:
			g.c_shop_refresh.rpc()
	)
	sfoot.add_child(g.shop_refresh_btn)
	g.shop_leave_btn = UIKit.button("离开", 14)
	g.shop_leave_btn.pressed.connect(func() -> void:
		if g.multiplayer.is_server():
			g._shop_leave(g.my_peer)
		else:
			g.c_shop_leave.rpc()
	)
	sfoot.add_child(g.shop_leave_btn)

	# 倒计时行（D 方案那条，与座位卡共用同一份状态）：进店后整块棋盘被压暗底盖住，
	# 座位卡上的倒计时也一并看不见——店里的人会看不到自己的时限、到点被静默请出。
	# 数据来源与座位卡完全同一份（game._refresh_op_timer 推送的 _op_*），不另起计时。
	g.shop_timer_row = HBoxContainer.new()
	g.shop_timer_row.add_theme_constant_override("separation", 8)
	g.shop_timer_row.visible = false
	g.shop_timer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spv.add_child(g.shop_timer_row)
	g.shop_timer_kind = UIKit.label("", 15, UIKit.ACCENT)
	g.shop_timer_row.add_child(g.shop_timer_kind)
	g.shop_timer_track = ColorRect.new()
	g.shop_timer_track.color = Color(1, 1, 1, 0.13)
	g.shop_timer_track.custom_minimum_size = Vector2(180, 8)
	g.shop_timer_track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.shop_timer_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.shop_timer_row.add_child(g.shop_timer_track)
	g.shop_timer_fill = ColorRect.new()
	g.shop_timer_fill.color = UIKit.ACCENT
	g.shop_timer_fill.size = Vector2(180, 8)
	g.shop_timer_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.shop_timer_track.add_child(g.shop_timer_fill)
	g.shop_timer_left = UIKit.label("", 15, UIKit.TEXT)
	g.shop_timer_left.custom_minimum_size = Vector2(56, 0)
	g.shop_timer_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g.shop_timer_row.add_child(g.shop_timer_left)

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
	# 收进「📖 规则说明」面板（见 rules_panel.gd / rules_text.gd）——**面板在右上角、不在左下角**：
	# 按钮随批次 12 D2 从屏幕底部搬到右上角与「战报」并列，面板本体在批次 13 ① 跟着搬过去
	# （右缘 −12 / 顶 52）；这一句原写「左下角」是搬之前的事实，2026-10-05 改准。
	g.info_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 6)
	# 不再钉在左下角：悬浮在被点格子的正上方，位置由 game._place_info_panel 逐帧摆
	g.info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	g.info_panel.custom_minimum_size = Vector2(330, 170)
	g.info_panel.size = Vector2(330, 170)
	g.info_panel.visible = false
	g.add_child(g.info_panel)
	g.info_sb = UIKit.stylebox(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1)
	g.info_panel.add_theme_stylebox_override("panel", g.info_sb)
	var im := UIKit.margins(12, 8, 10, 10)
	g.info_panel.add_child(im)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 5)
	im.add_child(iv)
	# 标题行：标题占满，右侧一个关闭按钮。
	# 此前这张卡没有任何关闭途径——只能靠展开右上角「规则说明」把它挤掉（见 game.gd:_set_rules_open）。
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	iv.add_child(head)
	g.info_title = UIKit.label("格子详情", 16, UIKit.ACCENT)
	g.info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.info_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(g.info_title)
	var info_close := UIKit.button("✕", 14)
	info_close.custom_minimum_size = Vector2(32, 26)
	info_close.tooltip_text = "关闭"
	info_close.pressed.connect(func() -> void: g.info_panel.visible = false)
	head.add_child(info_close)
	g.info_body = UIKit.label("点棋盘上任意格子看详情", 13, UIKit.TEXT)
	g.info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 锁死换行宽度：卡片改成显式尺寸（悬浮在格子上方）之后，锚点不再提供宽度，
	# 自动换行的 Label 在未知宽度下会算出爆炸的最小高度，把卡片撑成一块大板
	g.info_body.custom_minimum_size = Vector2(298, 0)
	iv.add_child(g.info_body)

	# ---- 决策区（批次 12 C1 / 设计 §③）：**格详情卡兼作买地/装修面板** ----
	# 弹窗不再屏幕居中：这一块挂进格详情卡里，跟着卡锚在**该格上方**（`_place_info_panel`）。
	# 只有「我有待决、且面板正挂着那一格」时才显示（判据唯一来源 `game._refresh_decision_area`）。
	# ✕ 关掉面板**不等于放弃**：倒计时条（`g._prompt_bar`）的补间跑在面板之外，
	# 关掉只是看不见；再点该格 / 点右下角「回格上决定」就回来。
	g.decision_area = VBoxContainer.new()
	g.decision_area.add_theme_constant_override("separation", 6)
	g.decision_area.visible = false
	iv.add_child(g.decision_area)
	var dsep := ColorRect.new()
	dsep.color = Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.7)
	dsep.custom_minimum_size = Vector2(0, 1)
	dsep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.decision_area.add_child(dsep)
	g.decision_title = UIKit.label("", 15, UIKit.ACCENT)
	g.decision_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.decision_area.add_child(g.decision_title)
	g.decision_text = UIKit.label("", 12, UIKit.TEXT)
	g.decision_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g.decision_text.custom_minimum_size = Vector2(298, 0)
	g.decision_area.add_child(g.decision_text)
	g.decision_bar = UIKit.progress(UIKit.ACCENT)
	g.decision_area.add_child(g.decision_bar)
	# 倒计时条的（重）启动 / 到点放弃都走 `game._prompt_bar_arm` —— 与旧居中弹窗同一份逻辑、
	# 同一个 `_prompt_bar`，只是条子换了个爹。
	g._prompt_bar = g.decision_bar
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 10)
	g.decision_area.add_child(drow)
	g.decision_no = UIKit.button("算了", 14)
	g.decision_no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drow.add_child(g.decision_no)
	g.decision_ok = UIKit.button("买下它！", 14, "primary")
	g.decision_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drow.add_child(g.decision_ok)
	g.decision_no.pressed.connect(g._on_decision_no)
	g.decision_ok.pressed.connect(g._on_decision_yes)

	# 右上：战报 / 聊天（可折叠，保持桌面干净）
	g.log_toggle = UIKit.with_icon(UIKit.button("战报 ▾", 13), "report", 17)
	g.log_toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	g.log_toggle.offset_left = -106
	g.log_toggle.offset_right = -12
	g.log_toggle.offset_top = 12
	g.log_toggle.offset_bottom = 40
	g.log_toggle.pressed.connect(g._toggle_log)
	g.add_child(g.log_toggle)

	g.log_panel = UIKit.panel_container(UIKit.PANEL_GLASS, 12, Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.8), 1, 6)
	g.log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# 宽度 300（原 340）：右侧栏太宽时会压住贴底的黑市操作条，
	# 见 game.gd:_dock_band（贴底条按可用带夹位）
	g.log_panel.offset_left = -300
	g.log_panel.offset_right = -12
	# 顶边 **52**（批次 13 辛 ② 从 134 收回来）。来龙去脉：
	#   * 批次 12 D1 把它从 46 抬到 **134** —— 当时名册条（y 50..128）钉在「战报」按钮之下，
	#     战报栏若仍从 46 起就会把名册条整个盖住（⑩ 明写"名册条不许与展开的战报栏打架"）。
	#   * 批次 13 ② 名册条搬到了**左上角** ⇒ 那条约束作废，134 只剩余量（当时刻意没动它）。
	#   * 批次 13 辛 ② 用户明写「『战报』弹窗离战报按钮这么远干什么」⇒ 收到 **52**，
	#     与「规则说明」面板**同一条顶边**（两枚按钮的实效下沿都是 46，让开 6 像素）。
	# 右边缘仍是 −12、底边仍是 780、宽度不动。（`hud_test` 那条"展开的战报栏不压名册条"
	# 按 `get_global_rect()` 实算、不写死这个数，两边位置都成立。）
	g.log_panel.offset_top = 52
	g.log_panel.offset_bottom = 780
	# 默认收起：消息改在屏幕上方弹出（见 game.gd:_push_log_toast），
	# 战报里的完整记录照旧保留，点「战报 ▾」展开看历史。
	g.log_panel.visible = false
	g.add_child(g.log_panel)
	var lm := UIKit.margins(10, 10, 8, 8)
	g.log_panel.add_child(lm)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	lm.add_child(lv)

	# ---- 「我」那条身家条（屏幕左下角；批次 5 Task 3 建四条，批次 12 D 只留这一条）----
	# **为什么只有一条**（⑩）：他人的信息改由下面的**名册条**承担（批次 13 ② 起在左上角「暂停」旁）
	# —— 四角条是"四个人各占一
	# 个角"，要横着比身家得来回看四个角；顶部一条横着排，一眼看完。而"我自己"的那些读数
	#（身家 / 现金 / 能量）就在手边、要常驻，留在左下角最顺眼。
	# 它取代的是更早的右侧名册栏（名次 + 名字 + 身家），代价（已在设计里接受）：名册栏那行
	# "地产 ×n · 道具 n / 现金"一起消失 —— 地产数仍在棋盘上看得见（格子归属色条 + 格详情卡），
	# 公开背包改由**玩家道具弹窗**承担（批次 9；原先是桌上立牌那排品质色小卡）。
	#
	# **挂谁**：`game._refresh_corner_bars` 取 `game._seat_peers()[0]`（"自己打头"的第一位）
	# = 我；自己不在名册里（观战 / 掉线重连）时就是第 0 家 —— 与批次 5 同一语义。
	g.corner_bars = [_make_corner_bar(g, hud, MY_BAR_SLOT)]

	# ---- 名册条：**v0.8.0 第三次改版已整体删除**（用户 2026-10-06：「将屏幕左上角的玩家
	# 信息块**移到桌面上，做成立牌**」）----
	# 它承载的四件事（名次徽章 / 棋子色小片 / 昵称 / 行动者倒计时）与"点击开道具弹窗"
	# "选目标时描金边"**一条没丢，全部搬到了每名对手座位前的桌面立牌**上
	#（`table_props` 的 `Placards/Placard{peer}`，由 `game._refresh_placards` 刷）。
	# **别在这里把它加回来**：两处同时存在只会互相干扰，而"信息在桌上"正是用户要的那件事。
	# 落点史：桌上立牌（批次 5）→ 屏幕四角条（批次 9）→ 名册条（批次 12 D）→ **桌上立牌（本改版）**。

	# 右下角动作按钮（批次 7）：轮到我掷轮 → 「转动转盘」；掷完进道具阶段 → 「结束回合」。
	# 其余时候整枚隐藏（含"我掷完、正在移动与落地结算"那段 —— 那段没有可做的操作，
	# 显示一枚禁用的「转动转盘」会让玩家以为还能再掷，见 批次7-设计 §5.2）。
	# 落位（批次 12 D2 起）：**贴右下角**（右 20 / 下 20）。它原先悬在"右下角那条四角身家条之上"
	#（-224..-172 那段留白就是为了避开 x∈[-207,-12] / y∈[-160,-56] 的身家条）；⑩ 把那条删了，
	# 于是把它挪到更贴角的位置 —— 与"删掉的右下身家条腾出的地方"对齐（设计 §⑩6）。
	# 下方仍不压东西：贴底的黑市条按屏宽居中（约 x 460..820），离这里很远。
	g.action_btn = UIKit.button("转动转盘", 18, "primary")
	g.action_btn.custom_minimum_size = Vector2(200, 52)
	g.action_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	g.action_btn.offset_left = -220
	g.action_btn.offset_right = -20
	g.action_btn.offset_top = -72
	g.action_btn.offset_bottom = -20
	g.action_btn.visible = false
	g.action_btn.pressed.connect(g._on_action_pressed)
	hud.add_child(g.action_btn)

	# 抽卡演出的屏幕层大字卡（批次 8）：相机不动，卡在屏幕正中演（见 deck_reveal.gd）。
	# 批次 12 C2 起演出停在 HOLD 等「确定」：按钮的那一下由 `game` 接手（房主直接放行 /
	# 客户端回 `c_card_ok`），超时与机器人 / 休眠托管由 `game._await_card_confirm` 兜。
	g.deck_reveal = DeckReveal.new()
	g.deck_reveal.confirmed.connect(g._on_card_confirm)
	hud.add_child(g.deck_reveal)

	var hair := ColorRect.new()
	hair.color = Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.55)
	hair.custom_minimum_size = Vector2(0, 1)
	hair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(hair)

	# ---- 战报 ----
	g.log_head = UIKit.label("第 1/30 轮 · 战报", 13, UIKit.TEXT_DIM)
	lv.add_child(g.log_head)
	g.log_text = RichTextLabel.new()
	g.log_text.scroll_following = true
	g.log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	g.log_text.add_theme_font_size_override("normal_font_size", 13)
	g.log_text.add_theme_constant_override("line_separation", 2)
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

	# ---- 玩家道具弹窗（批次 9）：点四角身家条打开（卡牌 / 能量 / 身家现金）----
	# **挂在 `game` 上、并在本函数最末 append**（终审 fix wave 裁定 R5）。原因不显然，写清楚：
	#
	# Godot 4 的 **GUI 拾取按树序**（子节点倒序），**不看 `z_index`** —— `z_index` 只管绘制。
	# 弹窗的压暗底是 `STOP`（模态靠它），所以"谁先被拾取"决定它挡不挡得住别人：
	#   ① 建在它**之前**的那些屏幕层控件（暂停按钮 / 战报开关 / 战报栏 / 格详情卡 / 黑市条）
	#      在树序上排在它前面 ⇒ 弹窗被优先拾取 ⇒ 压暗底挡得住它们（这正是要的）；
	#      （之前它挂在 `hud` 上、而 `hud` 排在那几个控件之前 ⇒ 反过来，点击会穿透过去。）
	#   ② 结算层(50) / 弹问层(60) 是**运行时懒建**的（`_show_game_over` / `_show_prompt` 里才
	#      new 出来并 append 到 `game`）⇒ 天然比这里更晚 ⇒ 被优先拾取（不吃亏）；
	#   ③ 暂停菜单每次打开都 `move_child(menu_layer, -1)`（`_menu_show`）、小卖部(70) 与赌场
	#      在显示时同样把自己搬到最后 ⇒ 它们仍压在弹窗之上。
	# **注意**：本函数之后 `game._build_ui` 还会挂「规则说明」按钮 / 面板，故 `_build_ui`
	# 末尾把弹窗再 `move_child` 到最末（见那里）—— 别只靠这一处。
	# `z_index = 45` 由 `PlayerPopup._init` 设，**只定绘制带**（高于四角条 / 动作按钮 /
	# 抽卡大字卡 40，低于模态带 50/60/70/80），不再承担模态。
	g.player_popup = PlayerPopup.new()
	g.add_child(g.player_popup)

## 四角条的尺寸（屏幕像素）。**写死并显式设成 `custom_minimum_size`**：面板的高度是内容撑出来的
## （名字 + 身家 + 现金 + 倒计时行 + 内外边距），只给 `offset_*` 的话 Godot 会按最小尺寸把它撑大
## —— 底边那两条会朝**下**长进「规则说明」按钮里（实测 63 > 48，压住 5 像素）。
## 写死 + 按它算偏移，两边永远一致。**改条内容（行数 / 字号）必须重取这个数**：
## 取法 = 建完四条之后读一次 `root.get_combined_minimum_size()`（`tests/hud_test.gd` 里有一条
## 断言把两者钉在一起，撑大 / 撑不满都会红）。
##
## 批次 5 修复波（A/B）从 64 提到 **104**：多了**现金那一行小字**（B）与**操作倒计时行**（A），
## 而后者是**常驻占位**（`CORNER_TIMER_ROW_H`，只切内容显隐）—— 所以四条**永远**是同一个高度，
## 行动者那一角的面板不会随窗口开合一开一合。
## 批次 12 D 又从 104 提到 **126**：多了**能量行**（⑩5，`ENERGY_ROW_H`）。同样是"内容撑出来的"
## 那个数 —— 126 = 实测内容最小高（`tests/hud_test.gd` 把写死的值清零后量到的；打印在测试日志里）。
## **改行数 / 字号 / CORNER_TIMER_ROW_H / ENERGY_ROW_H 之后必须重取**（那条断言会红）。
## 条锚在 BOTTOM_LEFT（`my` = 56 是外沿到**屏幕底**的距离，与条高无关）⇒ 条只会朝**上**长，
## 变高不会压到任何东西（左下角原先那枚「规则说明」按钮已在批次 12 D2 搬到右上）。
const CORNER_BAR_SIZE := Vector2(195.0, 126.0)
## 倒计时行的常驻占位高度（屏幕像素）。行本身恒可见（见上），里面三个内容（环节名 / 进度条 /
## 秒数）按"是不是当前行动者"切显隐。
## **必须 ≥ 行内任一控件的自然最小高**（11 号字的两枚标签更高）—— 否则行动者那一角在倒计时
## 出现时会把自己撑高，四条就不再一样高（`tests/hud_test.gd` 有"倒计时出现后那一条没变高"的断言）。
const CORNER_TIMER_ROW_H := 19

## **「我」那条身家条**的落位：屏幕左下角（`preset` + 到屏幕边的距离 `mx` / `my`）。
##
## **批次 12 D 起只有这一条**（⑩）：他人的三条四角条（左上 / 右上 / 右下）已删，他们改由
## **名册条**承担（`ROSTER_ROW_SIZE` 那一段）。为什么不保留四角条：
## "别人现在什么身家"是**要横着比**的信息，四个角散在屏幕边上反而要来回看；一条横着排一眼看完。
##
## 落位仍与桌位一一对应的时代（批次 5）不同了 —— 现在只剩"自己"这一位（桌位 = 底），
## `game._seat_peers()[0]` 就是它。位置**对着出图定的**，两条硬约束：
##   ① 不与左上「暂停」（12,10–92,44）抢位：条在**左下角**，两者不同角，天然分开。
##   ② `my` = 20（**批次 13 ②**）：用户明写"和『转动转盘』按钮下限平齐" ——
##      右下角那枚动作按钮的 `offset_bottom = -20` ⇒ 自身条到屏幕底也取 20，两条底边齐平。
##      （原先 56 是为了让开批次 12 之前还在左下角的「规则说明」按钮；那个按钮批次 12 D2 已搬右上、
##      批次 13 ① 连面板也搬走了，左下角彻底空出来，所以能贴到 20。）
##      `my` 是外沿到**屏幕底**的距离，与条高无关 ⇒ 条只会朝**上**长，变高不会压到谁。
const MY_BAR_SLOT := {"preset": Control.PRESET_BOTTOM_LEFT, "mx": 12.0, "my": 20.0}

## 名册条那一套常量（`ROSTER_X` / `ROSTER_Y` / `ROSTER_SEP` / `ROSTER_ROW_SIZE` /
## `ROSTER_CARD_PAD`）与 `make_chip()` / `slim_card_pad()` **已随名册条整体删除**
##（v0.8.0 第四次复核：信息搬上桌，牌面由 `table_props` **原生**画，不再烘贴图 —— 见那里）。

## 「我」那条身家条上「能量」行的高度（屏幕像素）。行**常驻占位**，内容恒有（读数 + 小格），
## 所以它不是"按需显隐"那一类 —— 写死是为了让 `CORNER_BAR_SIZE` 有一个可核算的加数。
const ENERGY_ROW_H := 19.0

## 一条四角身家条：棋子色小片 + 名次徽章 + 「名字 / 身家 / 现金」三行 + 一条**操作倒计时行**。
## 建一次就不动结构，之后只由 `game._refresh_corner_bars`（名字 / 身家 / 现金 / 徽章 / 描边）
## 与 `game._refresh_corner_timer`（倒计时行）改文字与显隐。
##
## **批次 9 起这条可点**（`mouse_filter = STOP`）：点它 = 开该玩家的**道具弹窗**
##（`game._on_corner_bar_clicked`），选目标态下则是选中 TA。条内子控件仍全是 IGNORE ——
## 点击一律冒泡到条根，由根上那条 `gui_input` 统一接（peer 现读 `root` 的 meta，别闭包捕获）。
## 吃了点击的**影响面已核对**：它只占屏幕四个角，下面没有棋盘可点内容（3D 全景与 2D 端两张
## 出图都确认了棋盘主体远在条内侧；三个角按钮不重叠由 `tests/hud_test.gd` 的断言钉住）。
##
## **现金那一行（B）**：身家 = 现金 + 地产，只报身家时玩家在买卖 / 付租那一刻看不到自己有多少
## 现金（座位卡与右栏名册栏都已退场，桌上的筹码堆 / 体力件也在批次 7 退场）⇒ 身家做大字、现金做第二行小字，
## 四条都显示，口径与名册栏时代一致。
## **倒计时那一行（A）**：环节名 + 细进度条 + 剩余秒数，**只在当前行动者那一条上**出现
##（其余三条的内容藏起来）。行**常驻占位**（只切内容）—— 否则行动者换人时那一条会一开一合。
static func _make_corner_bar(g: Node, parent: Control, slot: Dictionary) -> Dictionary:
	var root := UIKit.panel_container(Color(0.085, 0.095, 0.138, 0.82), 10,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.7), 1, 4)
	# 批次 9：四角条从"只读"变"可点"（点它 = 开该玩家的道具弹窗 / 选目标态下选中 TA）。
	# 条内的子控件**保持 IGNORE**，否则点到名字那块就不冒泡到条根。
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	# **已知且有意接受的副作用**：条根改 STOP 后，**落在条上的滚轮与右键也被它一并吞掉**
	#（`TableView3D._unhandled_input` 里的视角推移、以及棋盘右键取消，都被这个 STOP 抢先收到）。
	# 影响面很小、**判可接受**：四角条底下是木框 / 地板（没有可滚可点的棋盘内容），
	# 规则说明里的"右键取消"主要也是对棋盘说的。**别当 bug 去把 STOP 改回 PASS** —— 改回就点不动了。
	# **按 peer 找那条、别在闭包里捕获 peer**：角位是"自己打头"轮转出来的，人一换这一条就换人
	# ⇒ 回调里现读 `root` 上的 meta（由 `game._refresh_corner_bars` 与 `bar.peer` 同处写）。
	root.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			g._on_corner_bar_clicked(int(root.get_meta("peer", GameData.NO_PEER)))
	)
	var s: Vector2 = CORNER_BAR_SIZE
	root.custom_minimum_size = s
	var preset := int(slot.preset)
	root.set_anchors_preset(preset)
	# 偏移由"离边的距离 + 面板尺寸"算出来 —— 改 CORNER_BAR_SIZE 不必再手改四个角
	var mx: float = float(slot.mx)
	var my: float = float(slot.my)
	var on_left: bool = preset == Control.PRESET_TOP_LEFT or preset == Control.PRESET_BOTTOM_LEFT
	var on_top: bool = preset == Control.PRESET_TOP_LEFT or preset == Control.PRESET_TOP_RIGHT
	if on_left:
		root.offset_left = mx
		root.offset_right = mx + s.x
	else:
		root.offset_left = -mx - s.x
		root.offset_right = -mx
	if on_top:
		root.offset_top = my
		root.offset_bottom = my + s.y
	else:
		root.offset_top = -my - s.y
		root.offset_bottom = -my
	root.visible = false                 # 还没收到状态：一条都不显示
	parent.add_child(root)

	var m := UIKit.margins(9, 10, 5, 5)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(m)
	# 外层竖排：上面是「棋子 / 徽章 / 三行字」，下面挂倒计时行（常驻占位，见函数头）
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 3)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(outer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(row)
	var chip_slot := Control.new()
	chip_slot.custom_minimum_size = Vector2(18, 18)
	chip_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chip_slot)
	var badge_slot := Control.new()
	badge_slot.custom_minimum_size = Vector2(24, 24)
	badge_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge_slot)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var name_l := UIKit.label("", 13, UIKit.TEXT)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.custom_minimum_size = Vector2(84, 0)
	col.add_child(name_l)
	# 身家 = 大字（名次的依据）
	var worth_l := UIKit.label("", 17, UIKit.ACCENT)
	worth_l.custom_minimum_size = Vector2(84, 0)
	col.add_child(worth_l)
	# 现金 = 第二行小字（B）：身家是「现金 + 地产」，买卖 / 付租要看的是这一行
	var money_l := UIKit.label("", 11, UIKit.TEXT_DIM)
	money_l.custom_minimum_size = Vector2(84, 0)
	col.add_child(money_l)

	# 能量（体力）行（批次 12 D1 / 设计 §⑩5）：读数 + 一排点亮/熄灭的小格。
	# **为什么补在这一条上**：批次 7 删掉桌上的体力件、批次 9 把它收进玩家道具弹窗之后，
	# 体力要"点开弹窗"才读得到 —— 而轮到自己行动时最常问的就是"我还有几点能量"。
	# 视觉语言与 `player_popup._fill` 那一排小格**同一套**（亮金 / 熄灭 + 圆角），
	# 只是小一号（12 vs 14）好塞进这条 195 宽的条里。体力上限 6（`_stamina_cap`）⇒ 6×12 + 5×3 = 87。
	var energy_row := HBoxContainer.new()
	energy_row.add_theme_constant_override("separation", 5)
	energy_row.custom_minimum_size = Vector2(0, ENERGY_ROW_H)
	energy_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(energy_row)
	var energy_l := UIKit.label("", 12, UIKit.TEXT)
	energy_l.custom_minimum_size = Vector2(58, 0)
	energy_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	energy_row.add_child(energy_l)
	var pip_box := HBoxContainer.new()
	pip_box.add_theme_constant_override("separation", 3)
	pip_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	energy_row.add_child(pip_box)

	# 操作倒计时行（A）：环节名 + 细进度条 + 剩余秒数。行恒可见（占位），内容按需显隐。
	var timer_row := HBoxContainer.new()
	timer_row.add_theme_constant_override("separation", 5)
	timer_row.custom_minimum_size = Vector2(0, CORNER_TIMER_ROW_H)
	timer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(timer_row)
	var timer_kind := UIKit.label("", 11, UIKit.ACCENT)
	timer_kind.visible = false
	timer_row.add_child(timer_kind)
	var timer_track := ColorRect.new()
	timer_track.color = Color(1, 1, 1, 0.13)
	timer_track.custom_minimum_size = Vector2(0, 6)      # 细进度条
	timer_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timer_track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	timer_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_track.visible = false
	timer_row.add_child(timer_track)
	var timer_fill := ColorRect.new()
	timer_fill.color = UIKit.ACCENT
	timer_fill.size = Vector2(0, 6)                      # 宽度由 _refresh_corner_timer 按剩余比例设
	timer_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_track.add_child(timer_fill)
	var timer_left := UIKit.label("", 11, UIKit.ACCENT)
	timer_left.custom_minimum_size = Vector2(38, 0)
	timer_left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_left.visible = false
	timer_row.add_child(timer_left)

	return {
		"root": root, "chip_slot": chip_slot, "chip": null, "chip_color": -999,
		"badge_slot": badge_slot, "badge": null, "badge_rank": -1,
		"name_l": name_l, "worth_l": worth_l, "money_l": money_l,
		"energy_row": energy_row, "energy_l": energy_l, "pip_box": pip_box,
		"pips": [], "pip_cap": -1,
		"timer_row": timer_row, "timer_kind": timer_kind, "timer_track": timer_track,
		"timer_fill": timer_fill, "timer_left": timer_left,
		"peer": GameData.NO_PEER, "border_active": false,
	}

## **`make_chip()` 已随名册条整体删除**（v0.8.0 第四次复核）。
## 它一度被用来把名册格烘成贴图贴到桌面立牌上 —— 用户 2026-10-06 否掉了那条路：
## 「不要这个贴图，一是尺寸不对，二是文字模糊」。现在牌面由 `table_props._make_placard`
## **原生**用 `Label3D` + 几何画（矢量渲染，缩到多小都清楚），不经过任何 Control。

# ================= 房主：初始化与主循环 =================

## 由大厅名册构造对局玩家表。注意把「没真正连上」的玩家标成机器人：
## 大厅→对局有约 0.4 秒淡出窗口，期间掉线的玩家若仍记为真人，
## 他每一手都要等满 35 秒超时才对局才推进（见 fix/v0.0.2）。

## 暂停菜单 / 设置面板 / 各种选择器（原 _build_menu_ui）


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
	# 模态层按 z 显式置顶：菜单挂在 `game`(z 0) 下、自身原先没有 z_index ⇒ 实效 0，
	# 挡不住后来出现的屏幕层控件（抽卡大字卡 DeckReveal 实效 40）。小卖部(70) 本来就已盖过
	# 菜单的 0 ⇒ 这一笔顺带把既有那条潜在缺口也补上：模态带 = 菜单 80 / 小卖部 70 /
	# 弹问 60 / 结算 50，全部高于屏幕 HUD 带（≤40）。**别靠树序**（`z_as_relative` 为真，
	# 谁在上会随建节点 / `move_child` 的顺序漂）。
	g.menu_layer.z_index = 80
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
	# 与 `menu_layer` 同档（80，同属"模态 / 暂停遮罩带"）：房主暂停会把树 `paused`，
	# 客户机上冻住的抽卡大字卡（DeckReveal 实效 z 40）收不掉；没有这一笔时 `pause_mask`
	# 实效 0 ⇒ 「⏸ 房主已暂停 · 等待继续…」会被那张卡盖住。显式置顶，别靠树序。
	g.pause_mask.z_index = 80
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
	# 操作限时（房主可点，客户端只读；见 doc/game-design/开局设置.md §三之一）
	# 小标题与只读行互斥显隐，文案由 game.gd 的 _refresh_tier_ui() 统一填（本行只建空标签）
	g.tier_title = UIKit.label("操作限时", 14, UIKit.TEXT)
	sv.add_child(g.tier_title)
	g.tier_row = UIKit.chip_row(GameSettings.TIERS, GameSettings.TIER_LABELS,
		func(id: String) -> void: g._set_timeout_tier(id))
	sv.add_child(g.tier_row)
	g.tier_readonly = UIKit.label("", 13, UIKit.TEXT_DIM)
	sv.add_child(g.tier_readonly)
	# 畸变（房主可点，客户端只读；规则见 doc/game-design/畸变.md）
	g.ab_title = UIKit.label("畸变（全场事件）", 14, UIKit.TEXT)
	sv.add_child(g.ab_title)
	var abr1 := HBoxContainer.new()
	abr1.add_theme_constant_override("separation", 10)
	sv.add_child(abr1)
	abr1.add_child(UIKit.label("触发频率", 13, UIKit.TEXT_DIM))
	g.ab_row = UIKit.chip_row(GameSettings.AB_FREQS, GameSettings.AB_FREQ_LABELS,
		func(id: String) -> void: g._set_ab_freq(id))
	abr1.add_child(g.ab_row)
	var abr2 := HBoxContainer.new()
	abr2.add_theme_constant_override("separation", 10)
	sv.add_child(abr2)
	abr2.add_child(UIKit.label("持续回合", 13, UIKit.TEXT_DIM))
	g.ab_dur_row = UIKit.chip_row(GameSettings.AB_DURS, GameSettings.AB_DUR_LABELS,
		func(id: String) -> void: g._set_ab_dur(id))
	abr2.add_child(g.ab_dur_row)
	var abr3 := HBoxContainer.new()
	abr3.add_theme_constant_override("separation", 10)
	sv.add_child(abr3)
	abr3.add_child(UIKit.label("条件触发", 13, UIKit.TEXT_DIM))
	g.ab_cond_row = UIKit.chip_row(GameSettings.AB_COND_SW, GameSettings.AB_COND_LABELS,
		func(id: String) -> void: g._set_ab_cond(id))
	abr3.add_child(g.ab_cond_row)
	g.ab_readonly = UIKit.label("", 13, UIKit.TEXT_DIM)
	sv.add_child(g.ab_readonly)
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

	# 指向性道具目标提示条（顶部居中）：**点屏幕四角的身家条 / 点格子**选目标（玩家卡随批次 5
	# 的座位卡、桌上立牌随批次 9 一起退场了，选人的落点在屏幕层四角条上）；
	# 取消 = 点此「取消」或 Esc / 右键单击（拖拽平移不触发）
	g.target_hint = Control.new()
	g.target_hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.target_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.target_hint.visible = false
	g.add_child(g.target_hint)
	var th_wrap := CenterContainer.new()
	th_wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	th_wrap.offset_top = 52
	th_wrap.offset_bottom = 100
	th_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.target_hint.add_child(th_wrap)
	var th := UIKit.panel_container(UIKit.PANEL_GLASS, 12,
		Color(1.0, 0.86, 0.35, 0.85), 1, 8)
	th_wrap.add_child(th)
	var th_row := HBoxContainer.new()
	th_row.add_theme_constant_override("separation", 12)
	th.add_child(th_row)
	g.target_hint_l = UIKit.label("", 15, UIKit.ACCENT)
	th_row.add_child(g.target_hint_l)
	var th_cancel := UIKit.button("取消", 13)
	th_cancel.pressed.connect(g._cancel_target)
	th_row.add_child(th_cancel)

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

