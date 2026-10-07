extends Control
## 主菜单：昵称、创建房间、加入房间（IP/IPv6/域名）、局域网房间列表。

var _name_edit: LineEdit
var _port_edit: LineEdit
var _addr_edit: LineEdit
var _join_port_edit: LineEdit
var _create_btn: Button
var _join_btn: Button
var _rooms_box: VBoxContainer
var _status: Label
var _title: Label
var _rooms_sig := ""
var _shot_game := false

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

	# 背景：整张环形棋盘铺满窗口（就像对局里那张桌子），再压一层暗纱 + 金色暖光 + 暗角，
	# 中间留白给操作面板——启动页一眼就是「宿舍大富翁」。
	var bg_board := MenuBoardDecor.new()
	bg_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 环做薄一点（每边格数多一点），内区就往外让 —— 标题与页脚不会贴着环的内沿
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

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(660, 0)
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	# 标题行：双骰子图标 + 描边金字
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 16)
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_row)
	var icon_l := UIKit.dice_icon(40)
	icon_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(icon_l)
	_title = UIKit.title_label("宿舍大富翁", 46)
	title_row.add_child(_title)
	var icon_r := UIKit.dice_icon(40)
	icon_r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(icon_r)

	var sub := UIKit.label("宿舍楼里的财富战争 · 局域网 4 人联机 · IPv6 直连 · 56 格地图", 14, UIKit.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)

	root.add_child(UIKit.vspace(8))

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	root.add_child(name_row)
	name_row.add_child(UIKit.label("昵称", 15))
	_name_edit = UIKit.line_edit("给你的室友起个外号")
	_name_edit.text = cfg.get_value("player", "name", "玩家")
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.max_length = 12
	name_row.add_child(_name_edit)

	# ----- 创建房间 -----
	var create_panel := UIKit.panel_container(UIKit.PANEL_GLASS, 12, _card_border(), 1, 10)
	var cp := UIKit.margins()
	create_panel.add_child(cp)
	root.add_child(create_panel)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	cp.add_child(cv)
	var create_title := UIKit.label("我是房主（4 人联机由你开局）", 16, UIKit.TEXT)
	cv.add_child(create_title)
	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 8)
	cv.add_child(create_row)
	create_row.add_child(UIKit.label("端口", 14, UIKit.TEXT_DIM))
	_port_edit = UIKit.line_edit("7777")
	_port_edit.text = str(cfg.get_value("net", "port", Net.PORT))
	_port_edit.custom_minimum_size = Vector2(90, 0)
	create_row.add_child(_port_edit)
	_create_btn = UIKit.button("创建房间", 16, "primary")
	_create_btn.pressed.connect(_on_create)
	create_row.add_child(_create_btn)
	var create_hint := UIKit.label("同一局域网的室友会自动搜到你的房间", 13, UIKit.TEXT_DIM)
	create_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	create_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(create_hint)

	# ----- 加入房间 -----
	var join_panel := UIKit.panel_container(UIKit.PANEL_GLASS, 12, _card_border(), 1, 10)
	var jp := UIKit.margins()
	join_panel.add_child(jp)
	root.add_child(join_panel)

	var jv := VBoxContainer.new()
	jv.add_theme_constant_override("separation", 8)
	jp.add_child(jv)
	jv.add_child(UIKit.label("加入房间", 16, UIKit.TEXT))
	var addr_row := HBoxContainer.new()
	addr_row.add_theme_constant_override("separation", 8)
	jv.add_child(addr_row)
	addr_row.add_child(UIKit.label("地址", 14, UIKit.TEXT_DIM))
	_addr_edit = UIKit.line_edit("留空自动搜索局域网；或输入 IPv4 / IPv6 / 域名，如 2001:da8::1234")
	_addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	addr_row.add_child(_addr_edit)
	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 8)
	jv.add_child(port_row)
	port_row.add_child(UIKit.label("端口", 14, UIKit.TEXT_DIM))
	_join_port_edit = UIKit.line_edit("7777")
	_join_port_edit.text = str(cfg.get_value("net", "port", Net.PORT))
	_join_port_edit.custom_minimum_size = Vector2(90, 0)
	port_row.add_child(_join_port_edit)
	_join_btn = UIKit.button("加入", 16, "primary")
	_join_btn.pressed.connect(_on_join)
	port_row.add_child(_join_btn)
	var join_hint := UIKit.label("IPv6 直连：让房主在大厅里复制「全球 IPv6 地址」发给你", 13, UIKit.TEXT_DIM)
	port_row.add_child(join_hint)

	# ----- 局域网房间列表 -----
	var rooms_panel := UIKit.panel_container(UIKit.PANEL_GLASS, 12, _card_border(), 1, 10)
	rooms_panel.custom_minimum_size = Vector2(0, 120)
	var rp := UIKit.margins()
	rooms_panel.add_child(rp)
	root.add_child(rooms_panel)

	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	rp.add_child(rv)
	rv.add_child(UIKit.label("局域网房间（自动搜索中…）", 14, UIKit.TEXT_DIM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 66)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	_rooms_box = VBoxContainer.new()
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_rooms_box)

	_status = UIKit.label("", 14, UIKit.DANGER)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(0, 22)
	root.add_child(_status)

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
		root.add_child(lab_panel)

	var footer := UIKit.label("Godot 4 制作 · 拿去和室友玩吧", 12, UIKit.TEXT_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(footer)

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
		_status.text = Net.last_error
		Net.last_error = ""
	# 掉线重连（协议 §六）：手里还攥着凭证且已断开 → 地址栏回填 + 提示，点「加入」即回对局
	var mp_r := Net.multiplayer.multiplayer_peer
	if Net.rejoin_token != 0 and not Net.is_host \
			and (mp_r == null or mp_r is OfflineMultiplayerPeer):
		if not Net.last_join_addr.is_empty():
			_addr_edit.text = Net.last_join_addr
		_status.text = "连接中断——用同一地址点「加入」即可回到对局（座位已由机器人托管）"

	var mp := Net.multiplayer.multiplayer_peer
	if not _shot_game and mp != null and not (mp is OfflineMultiplayerPeer) and Net.is_host:
		# 已经是房主（例如从大厅返回）→ 直接到大厅
		get_tree().change_scene_to_file.call_deferred("res://scenes/lobby.tscn")
	else:
		Net.start_disco_client()

	# 入场动画：面板错落淡入，标题轻轻呼吸
	for i in root.get_child_count():
		var c: Control = root.get_child(i)
		Fx.animate_in(c, 0.05 * i)
	_title.resized.connect(func() -> void: _title.pivot_offset = _title.size * 0.5)
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(_title, "scale", Vector2(1.025, 1.025), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_title, "scale", Vector2.ONE, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

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
		_status.text = "创建失败（端口可能被占用）：%s" % error_string(err)
		return
	Fx.go_to("res://scenes/lobby.tscn")

func _on_join() -> void:
	_apply_name()
	_save_cfg()
	var parsed := Net.parse_endpoint(_addr_edit.text, _parse_port(_join_port_edit))
	if parsed.is_empty():
		_status.text = "请输入房主的 IP（局域网搜索不需要填）"
		return
	_join_to(parsed[0], parsed[1])

func _join_to(ip: String, port: int) -> void:
	_status.text = "正在连接 %s:%d …" % [ip, port]
	_join_btn.disabled = true
	_create_btn.disabled = true
	var err := Net.join_game(ip, port)
	if err != OK:
		_status.text = "连接失败：%s" % error_string(err)
		_join_btn.disabled = false
		_create_btn.disabled = false

func _on_lobby_joined() -> void:
	Fx.go_to("res://scenes/lobby.tscn")

func _on_join_failed(reason: String) -> void:
	_status.text = reason
	_join_btn.disabled = false
	_create_btn.disabled = false

func _on_kicked(reason: String) -> void:
	_status.text = reason
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
		var nx := count_x if count_x > 0 else per_side
		var ny := count_y if count_y > 0 else per_side
		var tw := board.size.x / float(nx + 1)
		var th := board.size.y / float(ny + 1)
		var inner := Rect2(board.position.x + tw, board.position.y + th,
			board.size.x - tw * 2.0, board.size.y - th * 2.0)
		draw_rect(inner, Color(0.128, 0.152, 0.203), true)
		draw_rect(inner, Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.20), false, 2.0)
		var arm := minf(inner.size.x, inner.size.y) * 0.12
		var gc := Color(UIKit.ACCENT.r, UIKit.ACCENT.g, UIKit.ACCENT.b, 0.30)
		var corners := [
			[inner.position.x + 12.0, inner.position.y + 12.0, 1.0, 1.0],
			[inner.end.x - 12.0, inner.position.y + 12.0, -1.0, 1.0],
			[inner.position.x + 12.0, inner.end.y - 12.0, 1.0, -1.0],
			[inner.end.x - 12.0, inner.end.y - 12.0, -1.0, -1.0],
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
