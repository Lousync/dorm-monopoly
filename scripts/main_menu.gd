extends Control
## 主菜单：昵称、创建房间、加入房间（IP/IPv6/域名）、局域网房间列表。
## 布局为**双栏门厅**（2026-10-08）：左「品牌区」= 标题 + 小棋盘意象，
## 右「操作区」= 昵称 / 建房·加入页签 / 房间列表；仓库图标挂右上角。
## 早先是 660px 居中单栏把三块面板一路往下堆，左右空一片、背景棋盘环又太亮抢戏。

## 本仓库地址（右上角图标点开它）
const REPO_URL := "https://github.com/Lousync/dorm-monopoly"

var _name_edit: LineEdit
var _port_edit: LineEdit
var _addr_edit: LineEdit
var _join_port_edit: LineEdit
var _create_btn: Button
var _join_btn: Button
var _refresh_btn: Button
var _rooms_box: VBoxContainer
var _status: Label
var _title: Label
var _rooms_sig := ""
var _shot_game := false

# 建房 / 加入 两页签：同一位置只留一页，省掉一半竖向高度（两页等高，切页不跳）
var _tab_row: HBoxContainer
var _host_page: Control
var _join_page: Control

var _at_mode := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			_at_mode = a.substr(11)
		elif a.begins_with("--shot="):
			_take_shot(a.substr(7))
		elif a.begins_with("--shot-lobby="):
			Net.my_name = "房主"
			Net.host_game(7791)
			get_tree().change_scene_to_file.call_deferred("res://scenes/lobby.tscn")
		elif a.begins_with("--shot-game="):
			# 单人开局直达对局（配合 --shot= 用于无干扰的布局截图）
			_shot_game = true
			Net.my_name = "房主"
			Net.host_game(7793)
			get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")
		elif a == "--lab" and OS.is_debug_build():
			# 道具试验场：独立沙盒（item_lab 内部自己 host + 内嵌 game.tscn）；正式版无此入口
			get_tree().change_scene_to_file.call_deferred("res://scenes/item_lab.tscn")
		elif a.begins_with("--lab-case=") and OS.is_debug_build():
			# `--lab-case=名字`：直达试验场并回放该用例（`item_lab._ready` 里读名字，见 §九 D / ⑭）
			get_tree().change_scene_to_file.call_deferred("res://scenes/item_lab.tscn")

	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")

	# 背景：整张环形棋盘铺满窗口（就像对局里那张桌子），再压一层暗纱 + 金色暖光 + 暗角。
	# 棋盘**保持原色**（2026-10-08 试过压暗，用户否了：更丑）；靠内区那块留白承托面板。
	var bg_board := MenuBoardDecor.new()
	bg_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 环做薄一点（每边格数多一点），内区就往外让
	bg_board.count_x = 14
	bg_board.count_y = 10
	bg_board.pad = 0.0
	bg_board.with_center = false
	add_child(bg_board)
	var scrim := ColorRect.new()
	scrim.color = Color(0.030, 0.036, 0.060, 0.18)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	add_child(UIKit.grad_rect(
		[Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.12),
		 Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.0)],
		[0.0, 1.0], true, Vector2(0.5, 0.06), Vector2(0.5, 0.90)))
	add_child(UIKit.grad_rect([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.40)],
		[0.0, 1.0], true, Vector2(0.5, 0.5), Vector2(0.5, -0.14)))

	# ----- 主体：双栏门厅 -----
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(1060, 0)
	page.add_theme_constant_override("separation", 12)
	center.add_child(page)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	page.add_child(body)

	# 入场动画的对象按构建顺序攒着，最后统一错落淡入
	var anim_targets: Array[Control] = []
	var ptext := str(cfg.get_value("net", "port", Net.PORT))

	# ---- 左栏：品牌区（标题 + 转盘）----
	# **没有面板底**（用户 2026-10-08）：直接落在棋盘内区上，不再套一层灰玻璃；
	# 标题两侧的骰子图标、以及标题下的「局域网 4 人联机…」一行，也都按要求去掉了。
	var brand := VBoxContainer.new()
	brand.custom_minimum_size = Vector2(408, 0)
	brand.size_flags_vertical = Control.SIZE_EXPAND_FILL
	brand.add_theme_constant_override("separation", 14)
	body.add_child(brand)
	anim_targets.append(brand)

	# 标题：**普通文字 + 黄色**（用户 2026-10-08：不要描边/投影，也不要呼吸动画；
	# 颜色用对局里的骰子黄 `UIKit.ACCENT`，跟转盘金圈、主按钮同一个色系）
	_title = UIKit.label("宿舍大富翁", 46, UIKit.ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_child(_title)

	# 中央意象：**转盘**（复用对局里那个 13 格转轮 WheelView，尺寸随控件缩放、零新绘制代码）。
	# 原先这里摆的是块小棋盘 —— 跟铺满窗口的背景棋盘重复了，用户要求换掉。
	# 静态摆着当装饰，不 spin_to（那会连带放转盘音效）。
	var hero := WheelView.new()
	hero.custom_minimum_size = Vector2(0, 376)
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	brand.add_child(hero)

	# ---- 右栏：操作区（昵称 / 建房·加入 / 房间列表）----
	var action := VBoxContainer.new()
	action.add_theme_constant_override("separation", 10)
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(action)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	action.add_child(name_row)
	anim_targets.append(name_row)
	name_row.add_child(UIKit.label("昵称", 15))
	_name_edit = UIKit.line_edit("给你的室友起个外号")
	_name_edit.text = cfg.get_value("player", "name", "玩家")
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 12
	name_row.add_child(_name_edit)

	# 建房 / 加入：原先两块独立面板，合并成一个带页签的卡片（竖向省一半）
	var net_panel := UIKit.panel_container(UIKit.PANEL_GLASS, 12, _card_border(), 1, 10)
	action.add_child(net_panel)
	anim_targets.append(net_panel)
	var np := UIKit.margins()
	net_panel.add_child(np)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 9)
	np.add_child(nv)

	_tab_row = UIKit.chip_row(["host", "join"], {"host": "我是房主", "join": "加入房间"}, _on_tab)
	nv.add_child(_tab_row)
	_host_page = _build_host_page(ptext)
	nv.add_child(_host_page)
	_join_page = _build_join_page(ptext)
	nv.add_child(_join_page)

	# 局域网房间列表：升为主视觉，标题右侧挂「刷新」
	var rooms_panel := UIKit.panel_container(UIKit.PANEL_GLASS, 12, _card_border(), 1, 10)
	rooms_panel.custom_minimum_size = Vector2(0, 176)
	rooms_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action.add_child(rooms_panel)
	anim_targets.append(rooms_panel)
	var rp := UIKit.margins()
	rooms_panel.add_child(rp)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	rp.add_child(rv)

	var rooms_head := HBoxContainer.new()
	rooms_head.add_theme_constant_override("separation", 8)
	rv.add_child(rooms_head)
	var rooms_title := UIKit.label("局域网房间", 14, UIKit.TEXT_DIM)
	rooms_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rooms_head.add_child(rooms_title)
	rooms_head.add_child(UIKit.label("每秒自动搜索", 12, UIKit.TEXT_DIM.darkened(0.18)))
	_refresh_btn = UIKit.button("⟳ 刷新", 13)
	_refresh_btn.custom_minimum_size = Vector2(0, 28)
	_refresh_btn.tooltip_text = "立刻重发一轮局域网搜索"
	_refresh_btn.pressed.connect(_on_refresh)
	rooms_head.add_child(_refresh_btn)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 66)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	_rooms_box = VBoxContainer.new()
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_rooms_box)

	_status = UIKit.label("", 14, UIKit.TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(0, 22)
	page.add_child(_status)

	_on_tab("host")

	# 开发者入口：仅在开发模式下显示（dev 开关：启动带 --dev，或设置里 dev.enabled=true；
	# 正式导出版一律关闭——OS.is_debug_build() 门控，见 game.gd 的同款处理）
	var dev_on := bool(cfg.get_value("dev", "enabled", false))
	for a0 in OS.get_cmdline_user_args():
		if a0 == "--dev":
			dev_on = true
	dev_on = dev_on and OS.is_debug_build()
	if dev_on:
		var lab_panel := UIKit.panel_container(UIKit.PANEL, 12, _card_border(), 1, 10)
		var lm := UIKit.margins(10, 10, 8, 8)
		lab_panel.add_child(lm)
		var lv := VBoxContainer.new()
		lv.add_theme_constant_override("separation", 6)
		lm.add_child(lv)
		lv.add_child(UIKit.label("开发者模式已开启", 12, Color(0.55, 0.9, 0.65)))
		var lab_btn := UIKit.button("🧪 道具试验场", 15, "primary")
		lab_btn.pressed.connect(func() -> void:
			get_tree().change_scene_to_file.call_deferred("res://scenes/item_lab.tscn"))
		lv.add_child(lab_btn)
		page.add_child(lab_panel)
		anim_targets.append(lab_panel)

	# 仓库入口：钉在**棋盘内区的右下角**（用户 2026-10-08 指定 —— 落在棋盘里，不是窗口角），
	# 跟着棋盘内框走，窗口尺寸一变也跟着挪。`add_child` 排在最后 = 树序最靠后，
	# Godot 的 GUI 拾取按倒序走，所以它压在面板之上、可点。
	var repo := _repo_button()
	add_child(repo)
	bg_board.pin_corner(repo)

	# 房间列表每 0.4s 刷新一次（逐帧重建会让按钮点不中、悬停闪烁）
	var room_timer := Timer.new()
	room_timer.wait_time = 0.4
	room_timer.autostart = true
	room_timer.timeout.connect(_refresh_rooms)
	add_child(room_timer)

	Net.lobby_joined.connect(_on_lobby_joined)
	Net.join_failed.connect(_on_join_failed)
	Net.kicked.connect(_on_kicked)

	if not Net.last_error.is_empty():
		_set_status(Net.last_error, "danger")
		Net.last_error = ""
	# 掉线重连（协议 §六）：地址栏回填**总是**做（冷启动也填，凭持久化凭证一键回对局）；
	# 但红字提示**只在真实断线那一刻**出现，由 net.gd 的一次性提示位驱动。
	# 原先拿「rejoin_token 非零」当判据 —— 它是持久化的，首局之后首页永远挂着红字，
	# 网络明明正常（用户 2026-10-08 报的 bug）。
	var hint := Net.take_rejoin_hint()
	if not Net.last_join_addr.is_empty():
		_addr_edit.text = Net.last_join_addr
		_on_tab("join")
	if not hint.is_empty():
		_set_status(hint, "danger")

	var mp := Net.multiplayer.multiplayer_peer
	if not _shot_game and mp != null and not (mp is OfflineMultiplayerPeer) and Net.is_host:
		# 已经是房主（例如从大厅返回）→ 直接到大厅
		get_tree().change_scene_to_file.call_deferred("res://scenes/lobby.tscn")
	else:
		Net.start_disco_client()

	# 入场动画：面板错落淡入（标题不再有呼吸动画 —— 用户 2026-10-08 要求去掉）
	for i in anim_targets.size():
		Fx.animate_in(anim_targets[i], 0.05 * i)

	if _at_mode == "host":
		Engine.time_scale = 3.0
		Net.my_name = "房主"
		Net.host_game(7790)
		get_tree().change_scene_to_file.call_deferred("res://scenes/lobby.tscn")
	elif _at_mode == "client" or _at_mode == "reconnect":
		Engine.time_scale = 3.0
		Net.my_name = "重连哥" if _at_mode == "reconnect" else "客户端"
		var addr := "127.0.0.1"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--addr="):
				addr = a.substr(7)
		if _at_mode == "reconnect" and Net.rejoin_token != 0 and not Net.rejoined:
			# 掉线后的第二轮：等一拍（让房主先看到断线）再凭凭证重连认领（协议 §六）
			print("AUTOTEST RECONNECT: rejoining with token")
			await get_tree().create_timer(1.2).timeout
		var err := Net.join_game(addr, 7790)
		if err != OK:
			print("AUTOTEST CLIENT JOIN ERROR ", err)
			get_tree().quit(2)
			return
		get_tree().create_timer(120.0).timeout.connect(func() -> void:
			print("AUTOTEST CLIENT TIMEOUT")
			get_tree().quit(1)
		)

func _card_border() -> Color:
	return Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.85)

# ---------------- 双栏门厅的构件 ----------------

## 建房页（页签「我是房主」）
func _build_host_page(port_text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(0, 78)   # 与加入页等高，切页不跳
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	row.add_child(UIKit.label("端口", 14, UIKit.TEXT_DIM))
	_port_edit = UIKit.line_edit("7777")
	_port_edit.text = port_text
	_port_edit.custom_minimum_size = Vector2(90, 0)
	row.add_child(_port_edit)
	_create_btn = UIKit.button("创建房间", 16, "primary")
	_create_btn.pressed.connect(_on_create)
	row.add_child(_create_btn)
	box.add_child(UIKit.label("同一局域网的室友会自动搜到你的房间", 13, UIKit.TEXT_DIM))
	return box

## 加入页（页签「加入房间」）
func _build_join_page(port_text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(0, 78)   # 与建房页等高，切页不跳
	var addr_row := HBoxContainer.new()
	addr_row.add_theme_constant_override("separation", 8)
	box.add_child(addr_row)
	addr_row.add_child(UIKit.label("地址", 14, UIKit.TEXT_DIM))
	_addr_edit = UIKit.line_edit("留空自动搜索局域网；或输入 IPv4 / IPv6 / 域名，如 2001:da8::1234")
	_addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	addr_row.add_child(_addr_edit)
	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 8)
	box.add_child(port_row)
	port_row.add_child(UIKit.label("端口", 14, UIKit.TEXT_DIM))
	_join_port_edit = UIKit.line_edit("7777")
	_join_port_edit.text = port_text
	_join_port_edit.custom_minimum_size = Vector2(90, 0)
	port_row.add_child(_join_port_edit)
	_join_btn = UIKit.button("加入", 16, "primary")
	_join_btn.pressed.connect(_on_join)
	port_row.add_child(_join_btn)
	var jhint := UIKit.label("IPv6 直连：让房主在大厅里复制「全球 IPv6 地址」发给你", 13, UIKit.TEXT_DIM)
	jhint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	jhint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_row.add_child(jhint)
	return box

## 建房 / 加入 页签切换：同一位置只留一页。
## 局域网房间框**两个页签都显示**（2026-10-08 用户改的口径：做过一版只在「加入房间」下显示，
## 被否 —— 房主自己也常要看有没有别人开了房）。
func _on_tab(id: String) -> void:
	UIKit.chip_select(_tab_row, id)
	if _host_page != null:
		_host_page.visible = id == "host"
	if _join_page != null:
		_join_page.visible = id == "join"

## 状态行按语义分色（原先恒为红色，连「正在连接…」都报红）
func _set_status(text: String, kind := "info") -> void:
	_status.text = text
	var col := UIKit.TEXT_DIM
	match kind:
		"danger":
			col = UIKit.DANGER
		"warn":
			col = UIKit.ACCENT
	_status.add_theme_color_override("font_color", col)

## 手动刷新：立刻重发一轮搜索 + 重建列表，不必干等每秒节拍
func _on_refresh() -> void:
	Net.disco_ping_now()
	_rooms_sig = ""
	_refresh_rooms()
	_refresh_btn.disabled = true
	_refresh_btn.text = "刷新中…"
	await get_tree().create_timer(0.45).timeout
	if is_instance_valid(_refresh_btn):
		_refresh_btn.disabled = false
		_refresh_btn.text = "⟳ 刷新"

## 棋盘内区右下角的仓库入口。图标缺货时退化成纯文字按钮（`UIKit.tex` 对**未导入**的 svg
## 拿不到纹理，新克隆没在编辑器里开过项目时会走到这条路）。
## **无底板**（用户 2026-10-08）：只留图标本身落在棋盘上，不再套一层灰按钮底；
## 悬停/按下给一层极淡的底，保住「这里可点」的手感。
## 尺寸写死：它由 `MenuBoardDecor.pin_corner` 按绝对坐标摆位，不吃容器布局。
func _repo_button() -> Button:
	var b := Button.new()
	var t := UIKit.tex("res://assets/icons/github.svg")
	if t != null:
		b.icon = t
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 24)
		# `icon_alignment` 默认是 **LEFT** —— 只有图标没有文字时，它把图标齐着盒子左边画，
		# 看着就是「没居中」（实测图标左沿 1131 而盒子左沿 1132.7，正是贴边）。
		# 必须显式给 CENTER（用户 2026-10-08 两次报「在背景容器里不居中」）。
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		# 正方形盒子：图标四边等距（先前 44×36，左右比上下多留 4px）
		b.custom_minimum_size = Vector2(40, 40)
	else:
		b.text = "GitHub"
		b.custom_minimum_size = Vector2(0, 36)
	b.size = b.custom_minimum_size
	b.tooltip_text = "在 GitHub 上查看源码"
	b.add_theme_font_size_override("font_size", 13)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var clear := UIKit.stylebox(Color(0, 0, 0, 0), 8)
	b.add_theme_stylebox_override("normal", clear)
	b.add_theme_stylebox_override("focus", clear)
	b.add_theme_stylebox_override("disabled", clear)
	b.add_theme_stylebox_override("hover", UIKit.stylebox(Color(1, 1, 1, 0.08), 8))
	b.add_theme_stylebox_override("pressed", UIKit.stylebox(Color(0, 0, 0, 0.20), 8))
	for s in ["font_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(s, UIKit.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", UIKit.ACCENT)
	b.pressed.connect(func() -> void:
		Fx.play("click", -6.0)
		OS.shell_open(REPO_URL))
	return b

## 点空白处要收掉输入框的焦点（用户 2026-10-08 报「鼠标点到别处，昵称框还亮着」）。
## 根因：本项目所有按钮都是 `FOCUS_NONE`、面板也不吃键盘焦点，于是点哪儿 LineEdit 都还攥着
## 焦点，`focus` 样式（金色描边）一直挂着。
## 用 `_input`（GUI 之前拿到事件）：点**落在输入框内**就不动它，让 LineEdit 自己处理；
## 落在别处才收焦点，而这次点击照常派发给下面的控件，不会吞掉按钮的点击。
func _input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton) or not (e as InputEventMouseButton).pressed:
		return
	var f := get_viewport().gui_get_focus_owner()
	if f is LineEdit and not f.get_global_rect().has_point(get_viewport().get_mouse_position()):
		f.release_focus()

func _exit_tree() -> void:
	Net.lobby_joined.disconnect(_on_lobby_joined)
	Net.join_failed.disconnect(_on_join_failed)
	Net.kicked.disconnect(_on_kicked)

func _save_cfg() -> void:
	# 必须先载入旧文件再存：这里只管 player/net 两段，直接覆盖保存会把
	# [dev]（开发者模式/道具试验场入口）和 [audio]（音量/静音）等别的段整个抹掉，
	# 表现为「开一局之后开发者模式就没了」（dev_tools.toggle 是先 load 再存的，别学反）。
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("player", "name", Net.my_name)
	cfg.set_value("net", "port", _port_edit.text)
	cfg.save("user://settings.cfg")

func _apply_name() -> void:
	# 统一走清洗：昵称里的 | 会让整个房间搜不到，换行会伪造战报行（见 fix/v0.0.2）
	Net.my_name = Net.sanitize_name(_name_edit.text)

func _parse_port(e: LineEdit) -> int:
	var p := int(e.text.strip_edges())
	if p < 1024 or p > 65535:
		p = Net.PORT
	return p

func _on_create() -> void:
	_apply_name()
	_save_cfg()
	var err := Net.host_game(_parse_port(_port_edit))
	if err != OK:
		_set_status("创建失败（端口可能被占用）：%s" % error_string(err), "danger")
		return
	Fx.go_to("res://scenes/lobby.tscn")

func _on_join() -> void:
	_apply_name()
	_save_cfg()
	var parsed := Net.parse_endpoint(_addr_edit.text, _parse_port(_join_port_edit))
	if parsed.is_empty():
		_set_status("请输入房主的 IP（局域网搜索不需要填）", "warn")
		return
	_join_to(parsed[0], parsed[1])

func _join_to(ip: String, port: int) -> void:
	_set_status("正在连接 %s:%d …" % [ip, port], "info")
	_join_btn.disabled = true
	_create_btn.disabled = true
	var err := Net.join_game(ip, port)
	if err != OK:
		_set_status("连接失败：%s" % error_string(err), "danger")
		_join_btn.disabled = false
		_create_btn.disabled = false

func _on_lobby_joined() -> void:
	Fx.go_to("res://scenes/lobby.tscn")

func _on_join_failed(reason: String) -> void:
	_set_status(reason, "danger")
	_join_btn.disabled = false
	_create_btn.disabled = false

func _on_kicked(reason: String) -> void:
	_set_status(reason, "danger")
	_join_btn.disabled = false
	_create_btn.disabled = false

func _refresh_rooms() -> void:
	if _rooms_box == null:
		return
	# 加入失败/被踢会让 Net._reset_peer 停掉发现器，而它只在 _ready 启动过一次；
	# 这里每次刷新兜底重启，否则房间列表会永久空白（见 fix/v0.0.2）。
	Net.ensure_disco_client()
	# 内容没变化就不重建，避免按钮闪烁/点不中
	var sig := ""
	var now := Time.get_ticks_msec()
	var alive := []
	for ip in Net.found_rooms.keys():
		var r: Dictionary = Net.found_rooms[ip]
		if now - int(r.time) > 6000:
			continue
		alive.append(ip)
		sig += "%s|%s|%s|%s|%d\n" % [ip, r.name, r.count, r.get("state", "lobby"), int(r.get("port", 0))]
	if sig == _rooms_sig:
		return
	_rooms_sig = sig
	for c in _rooms_box.get_children():
		c.queue_free()
	for ip in alive:
		var r2: Dictionary = Net.found_rooms[ip]
		var state := String(r2.get("state", "lobby"))
		var tag := ""
		var unjoinable := false
		match state:
			"playing":
				tag = " · 游戏中"
				unjoinable = true
			"full":
				tag = " · 已满"
				unjoinable = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var rport := int(r2.get("port", 0))
		var addr_txt: String = String(ip) if rport <= 0 else "%s:%d" % [ip, rport]
		var info := UIKit.label("%s（%s%s）— %s" % [r2.name, r2.count, tag, addr_txt], 14,
			UIKit.TEXT_DIM if unjoinable else UIKit.TEXT)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(info)
		var btn := UIKit.button("加入", 13, "normal" if not unjoinable else "danger")
		btn.disabled = unjoinable
		btn.pressed.connect(_on_room_join.bind(ip))
		row.add_child(btn)
		_rooms_box.add_child(row)
	if _rooms_box.get_child_count() == 0:
		_rooms_box.add_child(UIKit.label("（暂无，房主创建后自动出现；也可直接输入 IP 加入）", 13, UIKit.TEXT_DIM))

func _on_room_join(ip: String) -> void:
	_apply_name()
	_save_cfg()
	# 优先用房主广播里的端口：房主可能用非默认端口，加入方的端口框未必对得上
	#（此前一律用本地端口框 → 非默认端口永远连不上，见 fix/v0.0.2）
	var r: Dictionary = Net.found_rooms.get(ip, {})
	var port := int(r.get("port", 0))
	if port <= 0:
		port = _parse_port(_join_port_edit)
	_join_to(ip, port)

## 截图（用于界面检查）：--shot=保存路径
func _take_shot(path: String) -> void:
	await get_tree().create_timer(1.0).timeout
	# 造点假房间数据让列表不空（要在 start_disco_client 清空之后注入）
	Net.found_rooms["10.11.28.88"] = {"name": "小明 的房间", "count": "2/4", "state": "lobby", "time": Time.get_ticks_msec()}
	Net.found_rooms["10.11.28.66"] = {"name": "夜战宿舍 的房间", "count": "4/4", "state": "playing", "time": Time.get_ticks_msec()}
	_rooms_sig = ""
	_refresh_rooms()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT SAVED ", path)
	get_tree().quit(0)

class MenuBoardDecor extends Control:
	## 主菜单的「桌面主场」：程序绘制的俯视棋盘意象 —— 环岛格带 + 四色棋子 + 两粒骰子。
	## 纯绘制、零素材依赖；配色复用对局内的骰子黄与玩家色。
	const PALETTE := [
		Color(0.42, 0.80, 0.45), Color(0.36, 0.63, 0.94), Color(0.68, 0.48, 0.92),
		Color(0.98, 0.80, 0.32), Color(0.93, 0.42, 0.52), Color(0.42, 0.78, 0.82),
	]
	const PIPS := {
		1: [4], 2: [0, 8], 3: [0, 4, 8], 4: [0, 2, 6, 8], 5: [0, 2, 4, 6, 8], 6: [0, 2, 3, 5, 6, 8],
	}
	var per_side := 7          # 每边的格数（含角）；count_x / count_y 给了就按轴的格数走
	var count_x := 0           # 横向格数（0 = 用 per_side）—— 铺满当背景时用它把格子做成近方形
	var count_y := 0           # 纵向格数（0 = 用 per_side）
	var pad := 10.0            # 棋盘离控件边缘的留白（当背景时给 0，让环贴着窗口边）
	var with_center := true    # 中央是否画两粒骰子（当背景时留空给操作面板）

	## 内区四角那对金色括号：距内区角点 CORNER_INSET，臂长 = min(内区宽, 高) × CORNER_ARM_K。
	## 钉在角上的控件（`pin_corner`）要按 `CORNER_INSET + 线宽` 让位，别按臂长。
	const CORNER_INSET := 12.0
	const CORNER_ARM_K := 0.12

	var corner_node: Control = null      # 钉在内区右下角的控件（仓库图标用）
	var corner_inset := Vector2(16.0, 14.0)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 60.0 or h < 60.0:
			return
		var board := Rect2(pad, pad, w - pad * 2.0, h - pad * 2.0)
		# 桌面：深色毡面 + 金色描边
		draw_rect(board, Color(0.105, 0.125, 0.175), true)
		draw_rect(board, Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.45), false, 2.0)
		# 环岛格带
		var rects := ring_rects(board)
		for i in rects.size():
			var r: Rect2 = rects[i]
			var c: Color = PALETTE[i % PALETTE.size()]
			draw_rect(r, c.darkened(0.50), true)
			draw_rect(Rect2(r.position.x + 1.0, r.position.y + 1.0, r.size.x - 2.0, r.size.y * 0.22), c, true)
		# 中央场地：比环稍亮的毡面 + 金色内框 + 四角括号，
		# 让它读起来是「桌面」而不是一块黑板（对标对局里那张桌子的衬底）
		var inner := inner_rect()
		draw_rect(inner, Color(0.128, 0.152, 0.203), true)
		draw_rect(inner, Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.20), false, 2.0)
		var arm := minf(inner.size.x, inner.size.y) * CORNER_ARM_K
		var gc := Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.30)
		var corners := [
			[inner.position.x + CORNER_INSET, inner.position.y + CORNER_INSET, 1.0, 1.0],
			[inner.end.x - CORNER_INSET, inner.position.y + CORNER_INSET, -1.0, 1.0],
			[inner.position.x + CORNER_INSET, inner.end.y - CORNER_INSET, 1.0, -1.0],
			[inner.end.x - CORNER_INSET, inner.end.y - CORNER_INSET, -1.0, -1.0],
		]
		for cn in corners:
			var px: float = cn[0]
			var py: float = cn[1]
			var sx: float = cn[2]
			var sy: float = cn[3]
			draw_rect(Rect2(px if sx > 0.0 else px - arm, py - 3.0, arm, 3.0), gc, true)
			draw_rect(Rect2(px - 3.0, py if sy > 0.0 else py - arm, 3.0, arm), gc, true)
		# 四名玩家的棋子坐在环上（直接用对局里的 Kenney 棋子贴图，和游戏里同一批）
		for k in 4:
			var r: Rect2 = rects[int(rects.size() * k / 4) % rects.size()]
			var tex: Texture2D = UIKit.piece_tex(k)
			if tex == null:
				continue
			var mid := r.position + r.size * 0.5
			var ps := r.size.x * 0.98
			var dst := Rect2(mid - Vector2(ps, ps) * 0.5 + Vector2(0, r.size.y * 0.12), Vector2(ps, ps))
			draw_circle(mid + Vector2(0, r.size.y * 0.30), ps * 0.34, Color(0, 0, 0, 0.38))
			draw_texture_rect(tex, dst, false)
		# 中央：两粒骰子（当背景铺满时由调用方关掉，把中间让给操作面板）
		if with_center:
			draw_die(Vector2(w * 0.5 - 32.0, h * 0.5 - 10.0), 30.0, 3)
			draw_die(Vector2(w * 0.5 + 4.0, h * 0.5 + 6.0), 26.0, 5)

	## 「内区」矩形（环以内那块场地）。**与 _draw 用的是同一份算法**——
	## 仓库图标就钉在它的右下角，两处若各算各的，图标迟早跑到环上去。
	func inner_rect() -> Rect2:
		var board := Rect2(pad, pad, size.x - pad * 2.0, size.y - pad * 2.0)
		var nx := count_x if count_x > 0 else per_side
		var ny := count_y if count_y > 0 else per_side
		var tw := board.size.x / float(nx + 1)
		var th := board.size.y / float(ny + 1)
		return Rect2(board.position.x + tw, board.position.y + th,
			board.size.x - tw * 2.0, board.size.y - th * 2.0)

	## 把 `c` 钉在内区右下角，并随窗口尺寸自动跟随（仓库图标用）。
	## 留白必须**盖过金色括号的线宽**：括号画在 `end - CORNER_INSET` 处、线宽 3px，
	## 所以 inset 得大于 `CORNER_INSET + 3`，否则图标压在金线上（用户 2026-10-08 报的）。
	## ⚠ 这里是**让线宽**，不是让臂长 —— 曾经误按臂长（0.12 × 内区宽）退让，
	## 图标被推到内区正中间，「位置飞了」。
	func pin_corner(c: Control, inset := Vector2(22.0, 22.0)) -> void:
		corner_node = c
		corner_inset = inset
		resized.connect(_place_corner)
		c.resized.connect(_place_corner)
		_place_corner.call_deferred()

	func _place_corner() -> void:
		if corner_node == null:
			return
		corner_node.position = inner_rect().end - corner_node.size - corner_inset

	## 环岛格：上边连同左右上角一次画满，其余三边依次接续，不重复画角
	func ring_rects(b: Rect2) -> Array:
		var out: Array = []
		var nx := count_x if count_x > 0 else per_side
		var ny := count_y if count_y > 0 else per_side
		var tw := b.size.x / float(nx + 1)
		var th := b.size.y / float(ny + 1)
		for i in nx + 1:                                             # 上边（含左上、右上角）
			out.append(Rect2(b.position.x + tw * i, b.position.y, tw, th))
		for j in range(1, ny + 1):                                   # 右边（含右下角）
			out.append(Rect2(b.position.x + b.size.x - tw, b.position.y + th * j, tw, th))
		for k in range(1, nx + 1):                                   # 下边（向左接续到左下角）
			out.append(Rect2(b.position.x + b.size.x - tw * float(k + 1), b.position.y + b.size.y - th, tw, th))
		for m in range(1, ny):                                       # 左边（两角已画）
			out.append(Rect2(b.position.x, b.position.y + b.size.y - th * float(m + 1), tw, th))
		return out

	func draw_die(pos: Vector2, s: float, value: int) -> void:
		var body := Rect2(pos, Vector2(s, s))
		draw_rect(body, Color(0.95, 0.95, 0.93), true)
		draw_rect(body, Color(0.70, 0.70, 0.68), false, 1.5)
		var u := s / 3.0
		for idx in PIPS.get(value, []):
			var cx := pos.x + u * (float(int(idx) % 3) + 0.5)
			var cy := pos.y + u * (float(int(idx) / 3) + 0.5)
			draw_circle(Vector2(cx, cy), u * 0.14, Color(0.16, 0.17, 0.22))
