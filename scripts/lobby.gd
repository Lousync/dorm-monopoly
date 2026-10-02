extends Control
## 房间大厅：玩家列表、准备、机器人、开始游戏、本机直连地址、聊天。

var _players_box: VBoxContainer
var _ready_btn: Button
var _add_bot_btn: Button
var _remove_bot_btn: Button
var _start_btn: Button
var _settings_btn: Button
var _addr_label: Label
var _chat_box: RichTextLabel
var _chat_edit: LineEdit
var _room_label: Label

# 房主开局设置弹窗（见 doc/game-design/开局设置.md §三之一）
var _set_wrap: Control
var _set_chips: HBoxContainer
var _set_tier := GameSettings.TIER_CURRENT

var _at_mode := ""
var _shot_path := ""

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			_at_mode = a.substr(11)
		elif a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-lobby="):
			_shot_path = a.substr(13)

	var bg := UIKit.decor_bg()
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 20)
	add_child(root)

	# 左列：玩家与操作
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)

	_room_label = UIKit.title_label("房间大厅", 28)
	left.add_child(_room_label)

	var players_panel := UIKit.panel_container(UIKit.PANEL, 12, _card_border(), 1, 8)
	players_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pm := UIKit.margins(10, 10, 8, 8)
	players_panel.add_child(pm)
	left.add_child(players_panel)

	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 8)
	pm.add_child(_players_box)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	left.add_child(btn_row)
	_ready_btn = UIKit.button("准备", 16)
	_ready_btn.pressed.connect(func() -> void: Net.toggle_ready())
	btn_row.add_child(_ready_btn)
	_add_bot_btn = UIKit.button("＋ 机器人", 15)
	_add_bot_btn.pressed.connect(func() -> void: Net.host_add_bot())
	btn_row.add_child(_add_bot_btn)
	_remove_bot_btn = UIKit.button("－ 机器人", 15)
	_remove_bot_btn.pressed.connect(func() -> void: Net.host_remove_bot())
	btn_row.add_child(_remove_bot_btn)
	_settings_btn = UIKit.button("游戏设置", 15)
	_settings_btn.custom_minimum_size = Vector2(0, 40)
	_settings_btn.tooltip_text = "开局设置（仅房主可改）"
	_settings_btn.pressed.connect(_on_open_settings)
	btn_row.add_child(_settings_btn)
	_start_btn = UIKit.button("开始游戏！", 17, "primary")
	_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_btn.custom_minimum_size = Vector2(0, 40)
	_start_btn.pressed.connect(_on_start)
	btn_row.add_child(_start_btn)
	var leave_btn := UIKit.button("离开", 15, "danger")
	leave_btn.pressed.connect(_on_leave)
	btn_row.add_child(leave_btn)

	# 右列：直连地址 + 聊天
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	root.add_child(right)

	var addr_panel := UIKit.panel_container(UIKit.PANEL, 12, _card_border(), 1, 8)
	var am := UIKit.margins(10, 10, 8, 8)
	addr_panel.add_child(am)
	right.add_child(addr_panel)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 4)
	am.add_child(av)
	av.add_child(UIKit.label("把下面的地址发给室友（加入时填入「地址」框）", 14, UIKit.TEXT_DIM))
	_addr_label = UIKit.label("", 14, UIKit.TEXT)
	_addr_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	av.add_child(_addr_label)
	var copy_row := HBoxContainer.new()
	copy_row.add_theme_constant_override("separation", 6)
	av.add_child(copy_row)
	var copy_btn := UIKit.button("复制地址", 13)
	copy_btn.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_addr_label.text)
		copy_btn.text = "已复制 ✓"
		Fx.play("pop", -6.0)
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(copy_btn):
			copy_btn.text = "复制地址"
	)
	copy_row.add_child(copy_btn)
	copy_row.add_child(UIKit.label("点击复制全部地址", 12, UIKit.TEXT_DIM))

	var chat_panel := UIKit.panel_container(UIKit.PANEL, 12, _card_border(), 1, 8)
	chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var cm := UIKit.margins(10, 10, 8, 8)
	chat_panel.add_child(cm)
	right.add_child(chat_panel)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	cm.add_child(cv)
	cv.add_child(UIKit.label("房间聊天", 14, UIKit.TEXT_DIM))
	_chat_box = RichTextLabel.new()
	_chat_box.scroll_following = true
	_chat_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_box.add_theme_font_size_override("normal_font_size", 14)
	cv.add_child(_chat_box)
	var chat_row := HBoxContainer.new()
	chat_row.add_theme_constant_override("separation", 6)
	cv.add_child(chat_row)
	_chat_edit = UIKit.line_edit("说点什么…（回车发送）")
	_chat_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_edit.text_submitted.connect(func(_t: String) -> void: _send_chat())
	chat_row.add_child(_chat_edit)
	var send_btn := UIKit.button("发送", 14)
	send_btn.pressed.connect(func() -> void: _send_chat())
	chat_row.add_child(send_btn)

	Net.lobby_changed.connect(_refresh)
	Net.chat_received.connect(_refresh_chat)
	Net.connection_lost.connect(_on_conn_lost)

	# 入场：左右两列错落淡入
	Fx.animate_in(left, 0.0)
	Fx.animate_in(right, 0.12)

	_refresh()
	_refresh_chat()
	_build_settings_dialog()

	if _at_mode == "host":
		_autotest_host()
	elif _at_mode == "client":
		_autotest_client()
	elif _shot_path != "":
		_shot()

func _exit_tree() -> void:
	Net.lobby_changed.disconnect(_refresh)
	Net.chat_received.disconnect(_refresh_chat)

func _refresh() -> void:
	_room_label.text = "房间：%s（%d/%d 人）" % [Net.room_name, Net.players.size(), Net.MAX_PLAYERS]
	for c in _players_box.get_children():
		c.queue_free()
	for p in Net.players:
		var card := UIKit.panel_container(Color(0.125, 0.14, 0.19, 0.9), 10,
			Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.65), 1, 3)
		var cm := UIKit.margins(10, 10, 6, 6)
		card.add_child(cm)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		cm.add_child(row)
		row.add_child(UIKit.chip(GameData.PLAYER_COLORS[int(p.color)], 20))
		var tags := ""
		if int(p.peer) == 1:
			tags += "（房主）"
		if bool(p.bot):
			tags += "（机器人）"
		var name_l := UIKit.label(p.name + tags, 16, UIKit.TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_l)
		if bool(p.ready) or bool(p.bot):
			row.add_child(UIKit.pill("已准备", UIKit.GOOD, 12))
		elif not bool(p.bot):
			row.add_child(UIKit.pill("未准备", UIKit.TEXT_DIM, 12))
		_players_box.add_child(card)
	if Net.players.size() < Net.MAX_PLAYERS:
		var wait := UIKit.label("（等待其他室友加入，最多 4 人）", 13, UIKit.TEXT_DIM)
		wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_players_box.add_child(wait)

	var human_ready := true
	for p in Net.players:
		if not bool(p.bot) and not bool(p.ready):
			human_ready = false
	_ready_btn.visible = not Net.is_host
	_ready_btn.text = "取消准备" if _i_am_ready() else "准备"
	if not Net.is_host:
		UIKit.restyle_button(_ready_btn, "good" if _i_am_ready() else "normal")
	_add_bot_btn.visible = Net.is_host
	_remove_bot_btn.visible = Net.is_host
	_settings_btn.visible = Net.is_host
	_start_btn.visible = Net.is_host
	_start_btn.disabled = not (Net.players.size() >= 2 and human_ready)
	_start_btn.tooltip_text = "" if not _start_btn.disabled else "需要所有真人都点「准备」"

	if Net.is_host:
		var a := Net.split_addresses()
		var port := Net.host_port if Net.host_port > 0 else Net.PORT
		var lines: Array[String] = []
		# IPv6 必须带方括号，否则朋友粘贴后解析不出端口（见 fix/v0.0.2）
		for ip in a.lan4:
			lines.append("局域网 IPv4：%s" % NetAddr.format_endpoint(ip, port))
		for ip in a.lan6:
			lines.append("内网 IPv6：%s" % NetAddr.format_endpoint(ip, port))
		for ip in a.pub6:
			lines.append("全球 IPv6（跨网直连）：%s" % NetAddr.format_endpoint(ip, port))
		for ip in a.pub4:
			lines.append("公网 IPv4：%s" % NetAddr.format_endpoint(ip, port))
		if lines.is_empty():
			lines.append("未检测到可用地址，室友可尝试 127.0.0.1（同机测试）")
		_addr_label.text = "\n".join(lines)

func _card_border() -> Color:
	return Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.85)

func _i_am_ready() -> bool:
	for p in Net.players:
		if int(p.peer) == Net.multiplayer.get_unique_id():
			return bool(p.ready)
	return false

## 房主「游戏设置」弹窗：只放「操作限时」一排 chips
func _build_settings_dialog() -> void:
	_set_wrap = Control.new()
	_set_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_set_wrap.visible = false
	add_child(_set_wrap)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # 模态：吞掉落在面板外的点击
	_set_wrap.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_wrap.add_child(center)
	var panel := UIKit.panel_container(UIKit.PANEL_GLASS, 14,
		Color(UIKit.BORDER.r, UIKit.BORDER.g, UIKit.BORDER.b, 0.9), 1, 12)
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var m := UIKit.margins(20, 20, 16, 14)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	v.add_child(UIKit.title_label("游戏设置", 20))
	v.add_child(UIKit.label("操作限时：轮到你时超过该时间没操作，就由系统托管", 13, UIKit.TEXT_DIM))
	_set_chips = UIKit.chip_row(GameSettings.TIERS, GameSettings.TIER_LABELS,
		func(id: String) -> void:
			_set_tier = id
			UIKit.chip_select(_set_chips, id))
	v.add_child(_set_chips)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var cancel := UIKit.button("取消", 15)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func() -> void: _set_wrap.visible = false)
	row.add_child(cancel)
	var ok := UIKit.button("确定", 16, "primary")
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(_on_settings_save)
	row.add_child(ok)

## 「开始游戏！」：直接开局。设置改由旁边的「游戏设置」按钮负责
func _on_start() -> void:
	if not multiplayer.is_server():
		return
	Net.start_game()

## 「游戏设置」：打开设置弹窗（每次打开都从当前配置同步一遍）
func _on_open_settings() -> void:
	if not multiplayer.is_server():
		return
	_set_tier = Net.game_settings.timeout_tier
	UIKit.chip_select(_set_chips, _set_tier)
	_set_wrap.visible = true

## 弹窗「确定」：只保存并关闭，不再顺带开局
func _on_settings_save() -> void:
	Net.game_settings.timeout_tier = _set_tier
	_set_wrap.visible = false

func _on_leave() -> void:
	Net.leave()
	Fx.go_to("res://scenes/main_menu.tscn")

func _on_conn_lost(reason: String) -> void:
	Net.last_error = reason
	# 与对局场景同理：房主暂停中掉线时，新菜单会继承 paused 而完全无响应
	get_tree().paused = false
	Engine.time_scale = 1.0
	Fx.go_to("res://scenes/main_menu.tscn")

func _send_chat() -> void:
	Net.send_chat(_chat_edit.text)
	_chat_edit.clear()

func _refresh_chat() -> void:
	if _chat_box == null:
		return
	_chat_box.clear()
	for line in Net.chat_history:
		_chat_box.append_text(line.replace("[", "［") + "\n")

# ---------------- 自动化测试钩子 ----------------

func _autotest_host() -> void:
	await get_tree().create_timer(1.0).timeout
	# 先等真人客户端加入（最多 12 秒），再补机器人
	var waited := 0.0
	var humans := 0
	while waited < 12.0:
		humans = 0
		for p in Net.players:
			if not bool(p.bot):
				humans += 1
		if humans >= 2:
			break
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	print("AUTOTEST LOBBY humans=", humans)
	while Net.players.size() < Net.MAX_PLAYERS:
		Net.host_add_bot()
		await get_tree().create_timer(0.2).timeout
	var waited2 := 0.0
	while waited2 < 15.0:
		if Net.can_start():
			break
		await get_tree().create_timer(0.5).timeout
		waited2 += 0.5
	if Net.can_start():
		print("AUTOTEST LOBBY START players=", Net.players.size())
		Net.start_game()
	else:
		print("AUTOTEST HOST LOBBY FAIL")
		get_tree().quit(1)

func _autotest_client() -> void:
	await get_tree().create_timer(1.5).timeout
	if Net.players.is_empty():
		print("AUTOTEST CLIENT LOBBY EMPTY")
		get_tree().quit(1)
		return
	Net.toggle_ready()
	print("AUTOTEST CLIENT READY")

## 大厅截图：需要先 host_game，再 --shot=路径
func _shot() -> void:
	for i in 3:
		Net.host_add_bot()
	Net.chat_history = ["房主：开了开了，都进来", "机器人A：来了来了"]
	_refresh_chat()
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot_path)
	print("SHOT SAVED ", _shot_path)
	get_tree().quit(0)
