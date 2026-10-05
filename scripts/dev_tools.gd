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
## `--fps=秒数`：帧率实测的采样窗口长度（批次 6 Task 3 / 设计稿 §八 风险 1）。
## 0 = 不测。见 `fps_probe_run`。
var fps_probe := 0.0
## `--fps-houses=1`：采样前把**所有地产格**灌到满级装修（批次 11 T4 加，**默认关**，与批次 6/10 的
## 旧口径一字不差）。用途：量"**满盘装修**"这一最坏档 —— 房子薄牌是批次 11 新增的 56 个节点，
## 而**机器人根本不会主动装修**（实测：预热 60 秒只到第 9 轮、场上 **0 块房子**），所以"打到 15 轮
## 再采"采不到满盘，只能像 `level` 摆拍那样**在房主侧注入局面**（不动玩法代码）。见 `fps_probe_run`。
var fps_houses := false

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
	# 快速到特殊格：传送选中玩家并触发落点结算（赌场会直接跑一局演出）
	var jrow := HBoxContainer.new()
	jrow.add_theme_constant_override("separation", 4)
	dev_inject_box.add_child(jrow)
	jrow.add_child(UIKit.label("快速到", 11, UIKit.TEXT_DIM))
	for e in [["赌场", "casino"], ["小卖部", "shop"], ["机会", "event"], ["起点", "start"]]:
		var jb := UIKit.button(String(e[0]), 11)
		var jk: String = String(e[1])
		jb.pressed.connect(func() -> void: _dev_jump(jk))
		jrow.add_child(jb)
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
	if not OS.is_debug_build():
		return   # 正式导出版没有开发者模式：F1 不能把开关拨回来（面板也从未显示）
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
			int(p.get("pos", -1)), " ".join(its)])
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
	# 玩家选择按钮懒建 + 文本刷新。
	# 判据原来是 `board.seat_count() > 0`（"座位卡建出来了 = 玩家表已知"）；座位卡已随
	# 批次 5 Task 2 退场，改成直接看状态里的玩家表 —— 同一件事，少绕一层。
	if dev_pbtns.is_empty() and not (g.st.get("players", []) as Array).is_empty():
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
## 帧率实测（批次 6 Task 3）：在**默认对局取景**下逐帧量真实帧时间，打印平均值与最差一帧后退出。
##
## 用法：`-- --autotest=host --rounds=9999 --fps=8`
##   * **`--` 分隔符是必需的、不是笔误**：本项目所有开关都从 `OS.get_cmdline_user_args()` 读，
##     而它只返回 `--` 之后的参数 —— 少了它探针**永远不启动**、自动对局会一直跑下去
##     （复审实测：不加 `--` 跑到 240 s 被杀；加了约 20 s 出数）。
##   * 走 `--autotest=host` 是为了**四家都在**（`--shot-game=1` 不补机器人 ⇒ 名册条是空的，
##     量出来的不是"默认对局"的量）；
##   * `--rounds=9999` 只是让自动对局别在采样结束前自己收尾退出（本探针先退）。
##   * **别配 `--headless`**：探针逐帧等 `RenderingServer.frame_post_draw`，而 dummy 渲染器
##     **不发这个信号** ⇒ 探针会**挂死**（下面函数入口有一道直接退出的闸，见那里）。
##
## 口径（**照实记**，别把它读成"任何场景都这个数"）：
##   * 计时用 `Time.get_ticks_usec()`（**真实时间**，不受 `Engine.time_scale` 影响）；
##   * 采样从"对局真的跑起来之后 + 2 秒"开始（跳过建场与 shader 编译那几帧）；
##   * 采样期间把 `Engine.time_scale` 按回 **1.0**：自动对局默认 3 倍速，那是"逻辑跑得快"
##     而不是"渲染更重"，按回 1.0 量到的才是玩家自己玩时的那一档节奏。
##   * 加 `--fps-houses=1` 可先**灌满盘装修**再采（批次 11 T4 加的最坏档开关，见 `fps_houses`）——
##     机器人从不主动装修，不注入就只能量到 round=1、0 块房子的空盘。
##   * 逐帧 `await RenderingServer.frame_post_draw` = 一帧一次，量的就是帧时间本身。
##   * 单帧 >100ms 会**额外**打一行 `FPSPROBE SLOW`（附当时的 await / phase / draw call / 物件数），
##     用来判断长帧是"场景内容变重了"还是别的原因 —— 正常跑不会刷屏。
func fps_probe_run() -> void:
	# 无头直接退出：探针逐帧等 `RenderingServer.frame_post_draw`，而 dummy 渲染器不发它 ⇒
	# 配 `--headless` 跑会**永远不返回**（不报错、不退出，看着像卡死）。这条闸把它变成一句人话。
	if DisplayServer.get_name() == "headless":
		print("FPSPROBE SKIP headless（dummy 渲染器不发 frame_post_draw，探针在这里会挂死）")
		get_tree().quit(0)
		return
	var waited := 0.0
	while not g.running and waited < 40.0:
		await get_tree().create_timer(0.25, true, false, true).timeout
		waited += 0.25
	await get_tree().create_timer(2.0, true, false, true).timeout
	# **满盘装修注入**（`--fps-houses=1`，批次 11 T4）：把每一块**地产格**灌到满级装修再采 ——
	# 这是房子薄牌的最坏档。**为什么必须注入**：机器人**从不主动装修**（实测预热 60 秒只到第 9 轮、
	# 场上 0 块房子），"让机器人打到 15 轮再采"采不到满盘。注入手法与 `take_shot` 的 `level` 分支
	# **同类**：只在**房主侧**改 `htiles` 再广播，玩法代码一行不改（旧口径不传这个开关 ⇒ 一字不差）。
	if fps_houses and g.multiplayer.is_server():
		for i in g.htiles.size():
			if String(GameData.TILES[i].get("type", "")) == "property":
				g.htiles[i].owner = g.my_peer
				g.htiles[i].level = GameData.MAX_LEVEL
		g._broadcast_state()
		await get_tree().create_timer(0.3, true, false, true).timeout
	Engine.time_scale = 1.0
	# 采样起点的**局面自述**（批次 11 T4）：帧率数字必须连着"当时场上有几块房子"一起读 ——
	# 旧口径开采在 round=1、0 块房子，那种数字不能拿来代表"满盘装修"。
	print("FPSPROBE state round=%d houses=%d nodes=%d" % [
		int(g.st.get("round", 0)), (g._house_levels as Array).filter(func(x): return int(x) > 0).size(),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	var t0 := Time.get_ticks_usec()
	var last := t0
	var frames := 0
	var sum := 0.0
	var worst := 0.0
	var worst_at := 0.0
	var times: Array[float] = []
	var slow17 := 0
	var slow33 := 0
	while float(Time.get_ticks_usec() - t0) / 1000000.0 < fps_probe:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000000.0
		last = now
		sum += dt
		frames += 1
		times.append(dt)
		if dt > worst:
			worst = dt
			worst_at = float(now - t0) / 1000000.0
		if dt > 0.0167:
			slow17 += 1
		if dt > 0.0333:
			slow33 += 1
		if dt > 0.1:
			print("FPSPROBE SLOW t=%.2f dt_ms=%.0f await=%s phase=%s round=%d proc_ms=%.1f draw=%d obj=%d nodes=%d" % [
				float(now - t0) / 1000000.0, dt * 1000.0, String(g.st.get("await", "")),
				String(g.st.get("phase", "")), int(g.st.get("round", 0)),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
				int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	times.sort()
	var n := maxf(float(frames), 1.0)
	print("FPSPROBE seconds=%.1f frames=%d avg_ms=%.3f avg_fps=%.1f p50_ms=%.3f p95_ms=%.3f p99_ms=%.3f worst_ms=%.3f worst_fps=%.1f worst_at_s=%.2f over16.7=%d over33.3=%d"
		% [fps_probe, frames, sum / n * 1000.0, n / maxf(sum, 0.0001),
			times[int(n * 0.5)] * 1000.0, times[mini(int(n * 0.95), frames - 1)] * 1000.0,
			times[mini(int(n * 0.99), frames - 1)] * 1000.0,
			worst * 1000.0, 1.0 / maxf(worst, 0.0001), worst_at, slow17, slow33])
	get_tree().quit(0)

func take_shot(path: String) -> void:
	await get_tree().create_timer(0.4).timeout
	# 批次 12 C2 起演出**停在 HOLD 等「确定」**（`request_close()` 才收）⇒ 这里不能无限等：
	# 抽卡者是真人而摆拍里没人点按钮时它会一直亮着，把整张摆拍卡死。等到上限就替它收掉。
	var wait_guard := 0
	while g.deck_reveal != null and g.deck_reveal.is_showing() and wait_guard < 24:
		await get_tree().create_timer(0.25).timeout
		wait_guard += 1
	if g.deck_reveal != null and g.deck_reveal.is_showing():
		g.deck_reveal.request_close()
		await get_tree().create_timer(0.4).timeout
	g.board.fit_overview()
	await get_tree().create_timer(0.2).timeout
	# 摆拍期间默认锁住自动镜头（避免对局推进拽走视角）；文件名带 freecam 时不锁，
	# 这样后面的 focus_grid 拉近才生效 —— 用来复现「玩家自己看到的近景」
	g.board.cam_locked = not path.contains("freecam")
	# （原 _shot_rot 分支已随转视角一起删除，见 v0.5.0 批次 1）
	# 文件名带 tilt：把 **3D 视角**推到中段（view_t=0.5）出图，用来和 3D / 2D 两端对比构图。
	# 走**真接口**（table3d.snap_view），不手搓相机 —— 手搓的那份数学会和 _apply_camera 漂开，
	# 摆出来的图就不再是玩家真能滚到的那一档（视角推移后尤其：俯角与距离是一起插值的）。
	# 只动 3D 视角；SubViewport 内的 2D 相机（focus_grid 那一套）不受影响。
	# 建议配 table 用（如 xx_tilt_table_plain.png），停在围桌全景做纯视角对比。
	if path.contains("tilt") and g.table3d != null:
		g.table3d.snap_view(0.5)
	# 文件名带 view2d：推到 2D 端（view_t=1，接近正俯视、只看桌上地图）出图。与 tilt 同形：
	# 没有这个分支就拍不出 2D 端那张图（default 只能拍到 3D 端）。
	if path.contains("view2d") and g.table3d != null:
		g.table3d.snap_view(1.0)
	if not path.contains("table"):
		# 对局近景摆拍；路径带 table 则停在围桌全景（验证布局用）
		# 倍率是「全景的倍数」：2.0 ≈ 屏幕时代那个 0.8（0.8/0.40，见 board_view 顶部常量）
		g.board.focus_grid(27, 2.0, true)
		await get_tree().create_timer(0.15).timeout
		_on_tile_clicked(27)  # 顺便展示格子详情卡
	if path.contains("rules"):
		g._set_rules_open(true)  # 摆拍：展开右上角「规则说明」（批次 13 ① 起面板从左下角搬来）
	if path.contains("logopen"):
		# 摆拍（批次 12 D）：展开右上角**战报栏**，用来核对"展开的战报栏不压名册条"。
		# **批次 13 ② 起名册条搬到了左上角 ⇒ 两者已天然分居左右、不会打架**；这条图仍照拍
		# （战报栏的顶边还留在 134，见 `table_hud` 那段"约束已作废、值暂留"的说明）。
		# 走**真入口** `_toggle_log`（与玩家点「战报 ▾」同一条路），不直改 `log_panel.visible`。
		# 用法：`--autotest=host --rounds=6 --shot=shots/xx_logopen_table_plain.png`
		g._toggle_log()
	if path.contains("abshow") and g.multiplayer.is_server():
		# 摆拍（批次 12 D）：让**畸变横幅**亮起来（批次 12 D3 起它在顶部**水平居中**、y≈6..48）。
		# 走真路：写房主的 `_ab_active` 再 `_broadcast_state()` —— 横幅的显隐读的就是快照的
		# `aberrations` 字段（`_refresh_ab_ui`），与真实触发同一条链，不直调那个刷新函数。
		# 用法：`--autotest=host --rounds=6 --shot=shots/xx_abshow_table_plain.png`
		g._ab_active = [{"id": "断网", "left": 3}]
		g._broadcast_state()
		await get_tree().create_timer(0.25).timeout
	if path.contains("pause"):
		# 摆拍：打开暂停菜单。**这张 PNG 证明不了卡与菜单的层级**：`--shot=pause` 是先开菜单、
		# 之后才 `show_card`（门是 `not path.contains("plain") or path.contains("card")`，所以不带
		# `plain` 的 pause 图**会**调 show_card），而房主暂停会把树 `paused`、`DeckReveal._process`
		# 随之停 ⇒ 卡的初值 `alpha=0` 永远推不上去 —— 拍到的永远是"没有卡"。
		# 「卡在菜单之下」由 `hud_test` 的显式 z 断言钉住（`deck_reveal.z_index < menu_layer.z_index`），
		# 别从这张图得出反向结论。
		g._open_menu()
	if path.contains("deckout"):
		# 抽卡「抽出」摆拍（批次 8 起演出在**屏幕层**，相机不再参与）：这里不再需要先把注视点
		# 挪到牌堆（旧版是给 `play_deck_card` 的推近兜底），只等一拍让场景稳定。
		await get_tree().create_timer(0.2).timeout
	if not path.contains("plain") or path.contains("card"):
		g.deck_reveal.show_card("机会", "good", "帮宿管阿姨搬了一下午矿泉水，辛苦费 +600")
		# 批次 12 C2 起演出**停在 HOLD 等「确定」**：按钮要 CARD_TIME（2.14s）之后才出镜，
		# 而下面那三帧连拍落在 0.6/1.2/1.8s ⇒ 不处理的话一张都拍不到按钮。
		# 这里用**真接口**（`dev_force_confirm` + `tick` 快进）把它推到"停住等确定"那一档；
		# `deckout` 要的正是"刚抽出"那一瞬，不动它。
		if not path.contains("deckout"):
			g.deck_reveal.dev_force_confirm = true
			g.deck_reveal.set_can_confirm(true)
			g.deck_reveal.tick(DeckReveal.CARD_TIME + 0.01)
		# deckout **不转轮**：`spin_wheel` 会把镜头焦点改到转盘（`focus_point`），
		# 演出一开始镜头就往转盘跑（牌堆 / 桌面被挪开），拍不到抽卡这一幕。
		if not path.contains("deckout"):
			g.board.spin_wheel(12)
	if path.contains("itemreveal"):
		# 摆拍（批次 12 C3 / ⑪ 失物招领）：演出**道具卡面**（覆盖上面那张机会卡）——
		# 同一段四相位、同一个「确定」。用法：`--autotest=host --rounds=6
		# --shot=shots/b12_c_itemreveal_card.png`（文件名含 `card` ⇒ 走上面那条出图门）。
		g.deck_reveal.show_card("失物招领", "good", "【失物招领】捡到了【招财猫】！", "招财猫")
		g.deck_reveal.dev_force_confirm = true
		g.deck_reveal.set_can_confirm(true)
		g.deck_reveal.tick(DeckReveal.CARD_TIME + 0.01)
	if path.contains("level") and g.multiplayer.is_server():
		# 摆拍：给前几块地各设一个装修等级（1..MAX_LEVEL），
		# 方便核对格子上的房子图标与等级配色——机器人要很久才会主动装修，抓不到
		var done := 0
		for i in g.htiles.size():
			if String(GameData.TILES[i].get("type", "")) != "property":
				continue
			g.htiles[i].owner = g.my_peer
			g.htiles[i].level = done + 1
			done += 1
			if done >= GameData.MAX_LEVEL:
				break
		g._broadcast_state()
		await get_tree().create_timer(0.35).timeout
	if path.contains("hand") and g.multiplayer.is_server():
		# 摆拍：给自己发几张**不同品质**的道具。开局背包是空的，「手里握着牌」拍不出来；
		# 与 level 分支同类（只在对局里注入状态，不动玩法代码）。
		var me: Dictionary = g._player_by_peer(g.my_peer)
		if not me.is_empty():
			for hid_v in ["招财猫", "作弊器", "包租婆", "黑卡", "共享单车"]:
				g._grant_item(me, String(hid_v))
		g._broadcast_state()
		await get_tree().create_timer(0.35).timeout
	if path.contains("tip") and g.multiplayer.is_server():
		# 摆拍（批次 11 Task 3）：把**屏幕层悬停信息条**显出来 —— 它只在鼠标悬停到棋子上时出现，
		# 而静态截图里没有鼠标 ⇒ 走**真入口** `g._on_table_hover(棋子的画布落点)` 注入这一次悬停
		#（与 hand / level / popup 同类：只注入局面 / 表现状态，玩法代码一行不改）。
		# 用法：`--autotest=host --rounds=6 --shot=shots/b11_tip_table_plain.png`
		#   `table` → 停在围桌全景（不拉近、不弹格详情卡）；`plain` → 跳过抽卡与赌局浮层
		#  （那两样会盖住屏幕中段；**别**再带 card）。
		# 悬停**自己**那枚棋子：它一定在名册里、`board._peers_info` 里也一定有它。
		await get_tree().create_timer(0.2).timeout
		var me_tip: Dictionary = g._player_by_peer(g.my_peer)
		if not me_tip.is_empty():
			g._on_table_hover(g.board.token_screen_pos(
				int(me_tip.get("pos", 0)), int(me_tip.get("color", 0))))
			await get_tree().create_timer(0.2).timeout
	if path.contains("handhover") and g.multiplayer.is_server():
		# 摆拍（批次 12 B3）：把**手牌悬停放大**拍出来 —— 静态截图里没有鼠标 ⇒ 走**真入口**
		# `g._on_table_hover(那张牌的画布落点)` 注入这一次悬停（与 tip / popup 同类：只注入表现状态，
		# 玩法代码一行不改）。文件名同时带 `hand` ⇒ 上面那段会先发几张牌（空手没得悬停）。
		# 等 0.12s 的补间走完再出图。用法：`--autotest=host --rounds=6 --shot=shots/xx_handhover_table_plain.png`
		await get_tree().create_timer(0.2).timeout
		var tp_h = g.table3d.table_props
		if tp_h != null and tp_h.hand_count() > 1:
			g._on_table_hover(tp_h.hand_rect(1).get_center())
			await get_tree().create_timer(0.4).timeout
	if path.contains("popup") and g.multiplayer.is_server():
		# 摆拍（终审 fix wave）：开一个**对手**的道具弹窗，核对"卡牌图标 / 名称 / 能量小格 /
		# 身家现金都读得出、面板居中"。与 hand / level / target 同类 —— 只在对局里注入**局面状态**，
		# 玩法代码一行不改。手上有道具的家才有东西看：没有就先给 TA 发几件，再广播。
		# **走真入口** `_on_corner_bar_clicked`（与玩家点身家条 / 名册行走同一条路），不直调 `_open_player_popup`。
		# 用法：`--autotest=host --rounds=6 --shot=shots/b9_popup_table_plain.png`
		#   `table` → 停在围桌全景（不拉近、不弹格详情卡）；`plain` → 跳过抽卡与赌局浮层
		#   （那两样会抢镜；**别**再带上 `card`）。
		var pick := GameData.NO_PEER
		for pp in g.st.get("players", []):
			if int(pp.peer) != g.my_peer:
				pick = int(pp.peer)
				break
		if pick != GameData.NO_PEER:
			var opp: Dictionary = g._player_by_peer(pick)
			if not opp.is_empty() and (opp.get("items", []) as Array).is_empty():
				for hid_v in ["招财猫", "黑卡", "包租婆"]:
					g._grant_item(opp, String(hid_v))
			g._broadcast_state()
			await get_tree().create_timer(0.35).timeout
			g._on_corner_bar_clicked(pick)
			await get_tree().create_timer(0.3).timeout
	if not path.contains("plain") and not path.contains("card"):
		# 赌局界面预览（单行假数据，验证布局用）。路径带 card 时跳过赌局，
		# 否则弹层会盖住正在翻的抽卡
		g.casino.s_casino_start.rpc("投骰子", 800, 3200, [g.my_peer], {g.my_peer: "房主"})
		g.casino.s_casino_roll.rpc({g.my_peer: 5})
	if path.contains("target") and g.multiplayer.is_server() and not g.htiles.is_empty():
		# 摆拍（批次 9）：停在**选目标态**，核对"可选中的**名册格**亮着、其余不亮"
		#（落点史：桌上立牌 → 屏幕四角条（批次 9）→ 名册条右上（批次 12 D）→ **名册条左上角、
		# 「暂停」旁一列（批次 13 ②）**；高亮由 `_refresh_corner_highlight`
		# 在批次 9 Task 3 接上，出图名 `xx_target_plain.png`）。
		# 用**强拆令**（两段式：只能选"名下有地"的玩家）—— 它的目标过滤天然分得出
		# "有的亮、有的不亮"，正是这条反馈要展示的对比（跑腿券那种"谁都能选"的拍不出对比）。
		# 为了让这张图**可复现**：先把地皮归属清干净、只给**最后一家**两块地
		#（同 level / hand 那类"只注入局面状态"的摆拍手法，玩法代码一行不改）。
		for i in g.htiles.size():
			g.htiles[i].owner = GameData.NO_OWNER
			g.htiles[i].level = 0
		var last_peer: int = int(g.hp[g.hp.size() - 1].peer) if not g.hp.is_empty() else g.my_peer
		var given := 0
		for i in g.htiles.size():
			if String(GameData.TILES[i].get("type", "")) != "property":
				continue
			g.htiles[i].owner = last_peer
			given += 1
			if given >= 2:
				break
		g._broadcast_state()
		await get_tree().create_timer(0.35).timeout
		var me_t: Dictionary = g._player_by_peer(g.my_peer)
		if not me_t.is_empty():
			g._grant_item(me_t, "强拆令")
			g._broadcast_state()
			await get_tree().create_timer(0.3).timeout
			var slot_t := 0
			for k in (me_t.get("items", []) as Array).size():
				if String(me_t.items[k].id) == "强拆令":
					slot_t = k
			g.selected_slot = slot_t
			if g.table3d != null and g.table3d.table_props != null:
				g.table3d.table_props.set_hand_selected(slot_t)
			g._begin_peer_target(slot_t, false, true)
			await get_tree().create_timer(0.25).timeout
	if path.contains("decision") and g.multiplayer.is_server():
		# 摆拍（批次 12 C1 / ③）：**格详情卡兼作买地/装修面板** —— 面板锚在该格上方、
		# 带「买下它！」/「算了」与倒计时条，右下角动作按钮同时变「回格上决定」。
		# 走**真接口** `_arm_decision`（`_show_prompt` 的另一半），只伪造"我有待决"这件事，
		# 玩法代码一行不改（同 level / hand / tip / target 那些注入分支）。
		# 用法：`--autotest=host --rounds=6 --shot=shots/b12_c_decision_table_plain.png`
		#（文件名必须含 `plain` —— 否则会先演一张机会卡，把面板盖住；也要含 `table`
		#  免得 `focus_grid(27)` 弹出来的格详情卡跟它打架）。
		await get_tree().create_timer(0.2).timeout
		var prop := -1
		var best_c := 1e18
		for i in g.htiles.size():
			if String(GameData.TILES[i].get("type", "")) != "property":
				continue
			var sp_i = g.table3d.viewport_to_screen(g.board.tile_screen_pos(i))
			if sp_i == null:
				continue
			# 挑**离屏幕中心最近**的那块地：面板锚在它上方，中心附近一定放得下（不会被夹到屏边）
			var dc: float = (sp_i as Vector2).distance_to(g.size * 0.5)
			if dc < best_c:
				best_c = dc
				prop = i
		if prop >= 0:
			var me_d: Dictionary = g._player_by_peer(g.my_peer)
			if not me_d.is_empty():
				me_d.pos = prop        # 本机棋子挪到那格 —— 面板锚的就是"我脚下这一格"
			g._awaiting_prompt = g.my_peer
			g._prompt_tile = prop
			g._broadcast_state()   # ⇒ await="prompt"/await_peer=我，动作按钮变「回格上决定」
			await get_tree().create_timer(0.3).timeout
			g._arm_decision(1, prop, "购买地产",
				"要买下【%s】吗？\n售价 %s · 基础租金 %s\n你的现金 %s" % [
					String(GameData.TILES[prop].name),
					GameData.fmt_money(int(GameData.TILES[prop].price)),
					GameData.fmt_money(int(GameData.TILES[prop].rent)),
					GameData.fmt_money(int(me_d.get("money", 0)))], "买下它！")
			await get_tree().create_timer(0.3).timeout
			# 冻住树：倒计时条别在出图那几帧里跑掉，自动对局也别再推进（把这张图钉成可复现）
			get_tree().paused = true
	if path.contains("shopwatch") and g.multiplayer.is_server():
		# 摆拍（批次 12 C2 / ⑧）：**非本人**看到的小卖部（只读：按钮全灰 + 「XX 正在挑选」）。
		# 借真接口开一间店的货架（`_stock_shop`），再把「正在逛的人」指到别的玩家身上 ——
		# 本机于是成了旁观视角。用法：
		# `--autotest=host --rounds=6 --shot=shots/b12_c_shopwatch_table_plain.png`
		var idx_s := -1
		for i in GameData.TILES.size():
			if String(GameData.TILES[i].get("type", "")) == "shop":
				idx_s = i
				break
		var other: Dictionary = {}
		for x in g.hp:
			if int(x.peer) != g.my_peer:
				other = x
				break
		if idx_s >= 0 and not other.is_empty():
			g._shop_tile = idx_s
			if not g.shops.has(idx_s):
				g.shops[idx_s] = {"slots": ["", "", ""]}
			g._stock_shop(idx_s)
			g._shop_peer = int(other.peer)
			g._broadcast_state()
			await get_tree().create_timer(0.35).timeout
			get_tree().paused = true   # 冻住：自动对局下一拍会把 _shop_peer 改掉
	# 文件名带 deckout：抽卡「抽出」只有 `DeckReveal.OUT` = 0.34s，常规三帧的第一帧（0.6s）
	# 已经落在翻面之后 —— 拍不到"卡刚亮出来的那一刻"。这里按两个时间点各补一张（**不等 0.6s**）：
	#   0.06s（卡片刚起）与 0.16s（快到位）。批次 8 起演出在屏幕层、相机不参与 ⇒ 不再需要
	#   **freecam**（那是给旧版推近用的），例如 `--shot-game=1 --shot=shots/xx_deckout_card.png`。
	if path.contains("deckout"):
		for tm in [["0.06", "a"], ["0.16", "b"]]:
			await get_tree().create_timer(float(String(tm[0]))).timeout
			await RenderingServer.frame_post_draw
			var po := path.replace(".png", "_out%s.png" % String(tm[1]))
			get_viewport().get_texture().get_image().save_png(po)
			print("SHOT SAVED ", po)
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

## 找到第一种指定格型的路径序号（找不到返回 -1）
func _find_tile(kind: String) -> int:
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == kind:
			return i
	return -1

## 快速传送：选中玩家移到目标格并触发落点结算（赌场→跑一局演出；小卖部→开店）
func _dev_jump(kind: String) -> void:
	if not multiplayer.is_server():
		return
	var idx := _find_tile(kind)
	var p := _dev_selected()
	if idx < 0 or p.is_empty():
		_log("[dev] 找不到「%s」格" % kind, "#7fd88f")
		return
	p.pos = idx
	_broadcast_state()
	g.board.focus_grid(idx, 2.3, true)   # 2.3 倍全景 ≈ 屏幕时代的 0.9
	_log("[dev] %s 传送到「%s」（格 %d），触发落点结算" % [String(p.name), kind, idx], "#7fd88f")
	await g._resolve_tile(p)
