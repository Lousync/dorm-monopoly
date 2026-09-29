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

	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")

	var bg := ColorRect.new()
	bg.color = UIKit.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(640, 0)
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	_title = UIKit.label("宿舍大富翁", 42, UIKit.ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_title)

	var sub := UIKit.label("宿舍楼里的财富战争 · 局域网 4 人联机 · IPv6 直连 · 112 格大地图", 14, UIKit.TEXT_DIM)
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
	var create_panel := UIKit.panel_container(UIKit.PANEL, 10)
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
	var join_panel := UIKit.panel_container(UIKit.PANEL, 10)
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
	var rooms_panel := UIKit.panel_container(UIKit.PANEL, 10)
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

	var mp := Net.multiplayer.multiplayer_peer
	if mp != null and not (mp is OfflineMultiplayerPeer) and Net.is_host:
		# 已经是房主（例如从大厅返回）→ 直接到大厅
		get_tree().change_scene_to_file.call_deferred("res://scenes/lobby.tscn")
	else:
		Net.start_disco_client()

	# 入场动画：面板错落淡入，标题轻轻呼吸
	for i in root.get_child_count():
		var c: Control = root.get_child(i)
		Fx.animate_in(c, 0.05 * i)
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(_title, "scale", Vector2(1.025, 1.025), 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_title, "scale", Vector2.ONE, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if _at_mode == "host":
		Engine.time_scale = 3.0
		Net.my_name = "房主"
		Net.host_game(7790)
		get_tree().change_scene_to_file.call_deferred("res://scenes/lobby.tscn")
	elif _at_mode == "client":
		Engine.time_scale = 3.0
		Net.my_name = "客户端"
		var addr := "127.0.0.1"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--addr="):
				addr = a.substr(7)
		var err := Net.join_game(addr, 7790)
		if err != OK:
			print("AUTOTEST CLIENT JOIN ERROR ", err)
			get_tree().quit(2)
			return
		get_tree().create_timer(120.0).timeout.connect(func() -> void:
			print("AUTOTEST CLIENT TIMEOUT")
			get_tree().quit(1)
		)

func _exit_tree() -> void:
	Net.lobby_joined.disconnect(_on_lobby_joined)
	Net.join_failed.disconnect(_on_join_failed)
	Net.kicked.disconnect(_on_kicked)

func _save_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", Net.my_name)
	cfg.set_value("net", "port", _port_edit.text)
	cfg.save("user://settings.cfg")

func _apply_name() -> void:
	Net.my_name = _name_edit.text.strip_edges()
	if Net.my_name.is_empty():
		Net.my_name = "玩家"

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
	# 内容没变化就不重建，避免按钮闪烁/点不中
	var sig := ""
	var now := Time.get_ticks_msec()
	var alive := []
	for ip in Net.found_rooms.keys():
		var r: Dictionary = Net.found_rooms[ip]
		if now - int(r.time) > 6000:
			continue
		alive.append(ip)
		sig += "%s|%s|%s|%s\n" % [ip, r.name, r.count, r.get("state", "lobby")]
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
		var info := UIKit.label("%s（%s%s）— %s" % [r2.name, r2.count, tag, ip], 14,
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
	_join_to(ip, _parse_port(_join_port_edit))

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
