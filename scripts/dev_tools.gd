extends Node
## 开发者面板（F1）、道具卡图鉴入口与截图工具 —— 从 game.gd 搬出。
## 见审查结论：这约 270 行是开发/测试脚手架，本不该随生产代码发布在对局引擎里，
## 而且和对局状态机混在一起，翻代码时全是噪音。
##
## 通过 g 反向引用宿主；下面这组转发函数让搬过来的代码保持原样。

var g                       # 宿主：对局场景（game.gd）

# ---------------- 开发者模式 ----------------
var enabled := false            # 原 dev_enabled
var dev_panel: PanelContainer
var dev_state_l: Label
var dev_cam_l: Label
var dev_players: HBoxContainer
var dev_pbtns: Array = []
var dev_sel_peer := 0
var dev_item_opt: OptionButton
var dev_item_desc: Label
var dev_stam_s: HSlider
var dev_tp_spin: SpinBox
var dev_roll_spin: SpinBox
var dev_ts_l: Label
var dev_inject_box: VBoxContainer
var menu_probe := false

# ---------------- 转发给宿主 ----------------

func _log(line: String, color: String = "#dfe3ee") -> void:
	g._log(line, color)

func _broadcast_state() -> void:
	g._broadcast_state()

func _wait(sec: float) -> void:
	await g._wait(sec)

func _player_by_peer(peer: int) -> Dictionary:
	return g._player_by_peer(peer)

func _immune_debuff(p: Dictionary) -> bool:
	return g._immune_debuff(p)

func _grant_item(p: Dictionary, id: String) -> bool:
	return g._grant_item(p, id)

func _has_item(p: Dictionary, id: String) -> bool:
	return g._has_item(p, id)

func _apply_egg_festival(p: Dictionary) -> void:
	g._apply_egg_festival(p)

func _apply_coco(p: Dictionary) -> void:
	g._apply_coco(p)

func _shop_leave(peer: int) -> void:
	g._shop_leave(peer)

func _on_tile_clicked(idx: int) -> void:
	g._on_tile_clicked(idx)

func _open_menu() -> void:
	g._open_menu()

func _menu_resume() -> void:
	g._menu_resume()

## 构建开发者面板（原 _build_ui 里那一段）
func build_panel() -> void:
	# 开发者模式面板（左侧；注入区仅房主可见）
	dev_panel = UIKit.panel_container(Color(0.05, 0.06, 0.1, 0.94), 12, Color(0.45, 0.85, 0.55, 0.5), 1)
	dev_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	dev_panel.offset_left = 8
	dev_panel.offset_top = 56
	dev_panel.offset_right = 276
	dev_panel.offset_bottom = 720
	dev_panel.visible = false
	g.add_child(dev_panel)
	var dm := UIKit.margins(10, 12, 10, 10)
	dev_panel.add_child(dm)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	dm.add_child(dv)
	dv.add_child(UIKit.label("开发者模式（F1 显隐）", 13, Color(0.5, 0.9, 0.5)))
	dev_state_l = UIKit.label("", 11, UIKit.TEXT)
	dv.add_child(dev_state_l)
	dev_cam_l = UIKit.label("", 11, UIKit.TEXT_DIM)
	dv.add_child(dev_cam_l)
	dv.add_child(UIKit.label("玩家（点选后注入）", 11, UIKit.TEXT_DIM))
	dev_players = HBoxContainer.new()
	dev_players.add_theme_constant_override("separation", 4)
	dv.add_child(dev_players)
	dev_inject_box = VBoxContainer.new()
	dev_inject_box.add_theme_constant_override("separation", 5)
	dv.add_child(dev_inject_box)
	var mrow1 := HBoxContainer.new()
	mrow1.add_theme_constant_override("separation", 4)
	dev_inject_box.add_child(mrow1)
	for amt in [["+1千", 1000], ["+1万", 10000], ["-1千", -1000]]:
		var ab := UIKit.button(String(amt[0]), 11)
		var av: int = amt[1]
		ab.pressed.connect(func() -> void: _dev_add_money(av))
		mrow1.add_child(ab)
	var irow := HBoxContainer.new()
	irow.add_theme_constant_override("separation", 4)
	dev_inject_box.add_child(irow)
	dev_item_opt = OptionButton.new()
	for id in ItemData.ITEMS:
		dev_item_opt.add_item(id)
	dev_item_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dev_item_opt.item_selected.connect(func(_i: int) -> void: _dev_item_desc_update())
	irow.add_child(dev_item_opt)
	dev_item_desc = UIKit.label("", 10, UIKit.TEXT_DIM)
	dev_item_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dev_item_desc.custom_minimum_size = Vector2(0, 26)
	dev_inject_box.add_child(dev_item_desc)
	var irow2 := HBoxContainer.new()
	irow2.add_theme_constant_override("separation", 4)
	dev_inject_box.add_child(irow2)
	var give_btn := UIKit.button("发放", 11)
	give_btn.pressed.connect(_dev_grant_item)
	irow2.add_child(give_btn)
	var use_btn := UIKit.button("强制使用", 11)
	use_btn.pressed.connect(_dev_force_use)
	irow2.add_child(use_btn)
	var clear_bag := UIKit.button("清背包", 11)
	clear_bag.pressed.connect(func() -> void: _dev_player_edit(func(p: Dictionary) -> void: p.items = []))
	irow2.add_child(clear_bag)
	var dsrow := HBoxContainer.new()
	dsrow.add_theme_constant_override("separation", 4)
	dev_inject_box.add_child(dsrow)
	dsrow.add_child(UIKit.label("体力", 11, UIKit.TEXT_DIM))
	dev_stam_s = HSlider.new()
	dev_stam_s.min_value = 0
	dev_stam_s.max_value = 5
	dev_stam_s.step = 1
	dev_stam_s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dev_stam_s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dsrow.add_child(dev_stam_s)
	var cds_btn := UIKit.button("清冷却", 11)
	cds_btn.pressed.connect(func() -> void: _dev_player_edit(func(p: Dictionary) -> void:
		for it in p.get("items", []):
			it.cd = 0
	))
	dsrow.add_child(cds_btn)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 4)
	dev_inject_box.add_child(trow)
	trow.add_child(UIKit.label("传送格", 11, UIKit.TEXT_DIM))
	dev_tp_spin = SpinBox.new()
	dev_tp_spin.min_value = 0
	dev_tp_spin.max_value = int(GameData.TILES.size()) - 1
	dev_tp_spin.custom_minimum_size = Vector2(64, 0)
	trow.add_child(dev_tp_spin)
	var tp_btn := UIKit.button("传送", 11)
	tp_btn.pressed.connect(func() -> void: _dev_player_edit(func(p: Dictionary) -> void: p.pos = int(dev_tp_spin.value)))
	trow.add_child(tp_btn)
	trow.add_child(UIKit.label("点数", 11, UIKit.TEXT_DIM))
	dev_roll_spin = SpinBox.new()
	dev_roll_spin.min_value = 0
	dev_roll_spin.max_value = 12
	dev_roll_spin.custom_minimum_size = Vector2(56, 0)
	trow.add_child(dev_roll_spin)
	var fr_btn := UIKit.button("强制", 11)
	fr_btn.pressed.connect(func() -> void: _dev_player_edit(func(p: Dictionary) -> void: p.cheat_roll = int(dev_roll_spin.value)))
	trow.add_child(fr_btn)
	var erow := HBoxContainer.new()
	erow.add_theme_constant_override("separation", 4)
	dev_inject_box.add_child(erow)
	var end_btn := UIKit.button("结束当前等待", 11)
	end_btn.pressed.connect(_dev_end_wait)
	erow.add_child(end_btn)
	erow.add_child(UIKit.label("时间倍率", 11, UIKit.TEXT_DIM))
	for ts in [[".25", 0.25], ["1", 1.0], ["4", 4.0], ["8", 8.0]]:
		var tb := UIKit.button(String(ts[0]), 11)
		var tv: float = ts[1]
		tb.pressed.connect(func() -> void:
			Engine.time_scale = tv
			_dev_ts_update()
		)
		erow.add_child(tb)
	dev_ts_l = UIKit.label("当前 1x", 11, UIKit.TEXT_DIM)
	erow.add_child(dev_ts_l)
	var gal_btn := UIKit.button("道具卡图鉴", 11)
	gal_btn.pressed.connect(g._open_card_gallery)
	dev_inject_box.add_child(gal_btn)
	if not multiplayer.is_server():
		dev_inject_box.visible = false  # 客户端：仅观察

# ================= 开发者模式 =================

func apply_mode() -> void:
	if dev_panel != null and is_instance_valid(dev_panel):
		dev_panel.visible = enabled
	if g.board != null:
		g.board.dev_tile_index = enabled
	_dev_ts_update()

func toggle() -> void:
	enabled = not enabled
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("dev", "enabled", enabled)
	cfg.save("user://settings.cfg")
	apply_mode()

func _dev_ts_update() -> void:
	if dev_ts_l != null and is_instance_valid(dev_ts_l):
		dev_ts_l.text = "当前 " + String.num(Engine.time_scale, 2) + "x"

func _dev_selected() -> Dictionary:
	var p := _player_by_peer(dev_sel_peer)
	return p

func _dev_edit_selected(edit: Callable) -> void:
	if not multiplayer.is_server():
		return
	var p := _dev_selected()
	if p.is_empty():
		return
	edit.call(p)
	_broadcast_state()

func _dev_add_money(amount: int) -> void:
	_dev_edit_selected(func(p: Dictionary) -> void: p.money = int(p.money) + amount)

func _dev_grant_item() -> void:
	var id := _dev_selected_item()
	if id == "":
		return
	_dev_edit_selected(func(p: Dictionary) -> void: _grant_item(p, id))

func _dev_selected_item() -> String:
	if dev_item_opt == null or dev_item_opt.selected < 0:
		return ""
	return String(ItemData.ITEMS.keys()[dev_item_opt.selected])

func _dev_item_desc_update() -> void:
	var d := ItemData.def(_dev_selected_item())
	dev_item_desc.text = "%s · %d⚡ · %s" % [String(d.get("quality", "?")), int(d.get("cost", 0)), String(d.get("desc", ""))] \
		if String(d.get("type", "")) == "active" else "%s · 被动 · %s" % [String(d.get("quality", "?")), String(d.get("desc", ""))]

func _dev_force_use() -> void:
	if not multiplayer.is_server():
		return
	var id := _dev_selected_item()
	var p := _dev_selected()
	if p.is_empty() or id == "":
		return
	if not _has_item(p, id):
		_grant_item(p, id)
	match id:
		"作弊器":
			p.cheat_roll = clampi(int(dev_roll_spin.value), 0, 12)
			_log("[dev] %s 的下一次转盘点数被锁成 %d" % [p.name, int(dev_roll_spin.value)], "#7fd88f")
		"平均主义":
			var alive: Array = g.hp.filter(func(x) -> bool: return bool(x.alive))
			var total := 0
			for a in alive:
				total += int(a.money)
			var share := int(total / alive.size())
			var rem := total - share * alive.size()
			for a in alive:
				if _immune_debuff(a):
					continue  # 香皂免疫：不被拉平
				a.money = share
			for k in rem:
				if not _immune_debuff(alive[k]):
					alive[k].money = int(alive[k].money) + 1
			_log("[dev] 全场现金已拉平", "#7fd88f")
		"蛋蛋节":
			g.items_consumed["蛋蛋节"] = true
			for i in range(p.items.size() - 1, -1, -1):
				if String(p.items[i].id) == "蛋蛋节":
					p.items.remove_at(i)
			_apply_egg_festival(p)
		"亡牌飞行员coco":
			g.items_consumed["亡牌飞行员coco"] = true
			for i in range(p.items.size() - 1, -1, -1):
				if String(p.items[i].id) == "亡牌飞行员coco":
					p.items.remove_at(i)
			_apply_coco(p)
		_:
			_log("[dev] 【%s】效果尚未实装（被动持有即可生效 / 后续批次）" % id, "#7fd88f")
	_broadcast_state()

func _dev_end_wait() -> void:
	if not multiplayer.is_server():
		return
	match String(g.st.get("await", "")):
		"roll":
			g.roll_received.emit()
		"item":
			g._item_action = {"epoch": g._item_epoch, "action": "skip"}
		"shop":
			_shop_leave(g._shop_peer)

func refresh_panel() -> void:
	if dev_panel == null or not is_instance_valid(dev_panel) or not dev_panel.visible:
		return
	var lines := ["第%d/%d轮 · await=%s" % [int(g.st.get("round", 0)), int(g.st.get("max_rounds", 0)), String(g.st.get("await", ""))]]
	for p in g.st.get("players", []):
		var its := []
		for it in p.get("items", []):
			its.append(String(it.id) + (("·%d" % int(it.cd)) if int(it.cd) > 0 else ""))
		lines.append("%s ¥%d ⚡%d 格%d %s" % [String(p.name), int(p.money), int(p.get("stamina", 0)),
			int(p.pos), " ".join(its)])
	var shop_txt := ""
	for k in g.st.get("shops", {}):
		var arr: Array = g.st.shops[k].slots
		var names := []
		for id in arr:
			names.append("空" if String(id) == "" else String(id))
		shop_txt += "[%s]" % ",".join(names)
	lines.append("刷¥%d %s" % [int(g.st.get("refresh_price", 0)), shop_txt])
	dev_state_l.text = "\n".join(lines)
	dev_cam_l.text = g.board.cam_info()
	# 玩家选择按钮懒建 + 文本刷新
	if dev_pbtns.is_empty() and g.board.seat_count() > 0:
		for p in g.st.get("players", []):
			var peer := int(p.peer)
			var b := UIKit.button(String(p.name), 11)
			b.toggle_mode = true
			b.pressed.connect(func() -> void:
				dev_sel_peer = peer
				_dev_sel_refresh()
			)
			dev_players.add_child(b)
			dev_pbtns.append({"peer": peer, "btn": b})
	_dev_sel_refresh()

func _dev_sel_refresh() -> void:
	if dev_sel_peer == 0 and not dev_pbtns.is_empty():
		dev_sel_peer = int(dev_pbtns[0].peer)
	for e in dev_pbtns:
		var btn: Button = e.btn
		btn.button_pressed = int(e.peer) == dev_sel_peer

func menu_probe_run() -> void:
	await _wait(2.0)
	print("PROBE open menu...")
	_open_menu()
	await get_tree().create_timer(0.5, true).timeout
	print("PROBE paused=", get_tree().paused, " menu_visible=", g.menu_layer.visible,
		" panel=", g.menu_panel.visible, " state=", g.menu_state.text)
	_menu_resume()
	await get_tree().create_timer(0.5, true).timeout
	print("PROBE resumed paused=", get_tree().paused, " menu_visible=", g.menu_layer.visible)
	_open_menu()
	await get_tree().create_timer(0.5, true).timeout
	print("PROBE reopen paused=", get_tree().paused, " menu_visible=", g.menu_layer.visible)
	_menu_resume()
	await get_tree().create_timer(0.5, true).timeout
	print("PROBE final paused=", get_tree().paused)
	print("PROBE DONE")
	get_tree().quit(0)
func take_shot(path: String) -> void:
	await get_tree().create_timer(0.4).timeout
	while g.board.is_showing_deck_card():
		await get_tree().create_timer(0.25).timeout
	g.board.fit_overview()
	await get_tree().create_timer(0.2).timeout
	g.board.cam_locked = true  # 摆拍期间锁住自动镜头，避免对局推进拽走视角
	if g._shot_rot > 0:
		g.board.rotate_to_edge(g._shot_rot, true)  # 摆拍：转到对应座位的视角
		await get_tree().create_timer(0.15).timeout
	if not path.contains("table"):
		# 对局近景摆拍；路径带 table 则停在围桌全景（验证布局用）
		g.board.focus_grid(27, 0.8, true)
		await get_tree().create_timer(0.15).timeout
		_on_tile_clicked(27)  # 顺便展示格子详情卡
	if not path.contains("plain"):
		g.board.play_deck_card("机会", "good", "帮宿管阿姨搬了一下午矿泉水，辛苦费 +600")
		g.board.spin_wheel(12)
		# 赌局界面预览（单行假数据，验证布局用）
		g.casino.s_casino_start.rpc("炸弹猫", 800, 3200, [g.my_peer])
		g.casino.s_casino_turn.rpc(g.my_peer, 1, {g.my_peer: 1}, {g.my_peer: 2}, 9, true)
		g.casino.s_casino_event.rpc("你 摸到一张【拆除】揣进兜里", "move")
		g.casino.s_casino_event.rpc("你 摸到炸弹，紧急打出【拆除】化解！", "move")
		g.casino.s_casino_event.rpc("你 摸到一条小鱼", "good")
	# 连拍三帧，避开 3 倍速下真实抽卡与摆拍的相互干扰
	for i in 3:
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var p := path if i == 0 else path.replace(".png", "_%d.png" % i)
		get_viewport().get_texture().get_image().save_png(p)
		print("SHOT SAVED ", p)
	get_tree().quit(0)

func _dev_player_edit(edit: Callable) -> void:
	if not multiplayer.is_server():
		return
	var p := _dev_selected()
	if p.is_empty():
		return
	edit.call(p)
	_broadcast_state()
