extends Node
## 赌桌小游戏「炸弹猫」的回合主干与赌桌 UI，从 game.gd 搬出（见审查结论：
## game.gd 里 340 行赌场代码零测试覆盖、与对局引擎混在一起）。
##
## 规则本身在 BombCat（纯函数，可单测）；这里只剩流程、RPC 与表现。
## 通过 g 反向引用宿主对局场景，拿到 board / hp / running / my_peer 与几个
## 通用工具；下面这组转发函数是为了让搬过来的代码一行都不用改。
##
## 作为 game 的子节点存在，好让 s_casino_* / c_casino_action 的 RPC 路径在
## 各端一致（两端都在 _ready 里建同名节点）。

var g                       # 宿主：对局场景（game.gd）


var _casino_epoch := 0
var _casino_action := {"epoch": -1, "action": ""}
var _casino_actor := 0          # 当前该出牌的玩家（校验 c_casino_action 来源）
var _casino_layer: Control
var _casino_log: RichTextLabel
var _casino_pot_label: Label
var _casino_deck_label: Label
var _casino_status: Label
var _casino_rows := {}          # peer -> {root, sb, defuse_l, fish_l}
var _casino_btn_peek: Button
var _casino_btn_top: Button
var _casino_btn_bottom: Button
var _casino_my_epoch := -1
var _casino_table_pot := 0        # 桌面赌场设施显示中的奖池
var _casino_order: Array = []

# ---------------- 转发给宿主（让搬过来的代码保持原样） ----------------

func _log(line: String, color: String = "#dfe3ee") -> void:
	g._log(line, color)

func _wait(sec: float) -> void:
	await g._wait(sec)

func _name_by_peer(peer: int) -> String:
	return g._name_by_peer(peer)

func _player_by_peer(peer: int) -> Dictionary:
	return g._player_by_peer(peer)

func _is_managed(p: Dictionary) -> bool:
	return g._is_managed(p)

func _broadcast_state() -> void:
	g._broadcast_state()

func _casino_next_epoch() -> int:
	_casino_epoch += 1
	_casino_action = {"epoch": -1, "action": ""}
	return _casino_epoch

## 等待人类玩家行动；超时默认抽牌堆顶
func _casino_wait_action(epoch: int, timeout: float) -> String:
	var waited := 0.0
	while waited < timeout and g.running:
		await _wait(0.1)
		waited += 0.1
		if int(_casino_action.epoch) == epoch:
			return String(_casino_action.action)
	return "top"

## 落进赌场格：全员下注，跑一局炸弹猫，赢家通吃
func run(p: Dictionary) -> void:
	var alive: Array = g.hp.filter(func(x) -> bool: return bool(x.alive))
	if alive.size() < 2:
		_log("%s 走进赌场，却无人奉陪，悻悻离开" % p.name, "#8a90a5")
		return
	var pot := 0
	for a in alive:
		var pay: int = mini(GameData.CASINO_STAKE, int(a.money))
		a.money = int(a.money) - pay
		pot += pay
	_broadcast_state()
	var order: Array = []
	for a in alive:
		order.append(int(a.peer))
	s_casino_start.rpc("炸弹猫", GameData.CASINO_STAKE, pot, order)
	_log("全员下注 %s，奖池 %s，赢家通吃！" % [
		GameData.fmt_money(GameData.CASINO_STAKE), GameData.fmt_money(pot)], "#f0a0c0")

	var deck := BombCat.deck()
	var defuse := {}
	var fish := {}
	var used_peek := {}
	for a in alive:
		defuse[int(a.peer)] = 0
		fish[int(a.peer)] = 0
	var table: Array = order.duplicate()
	var idx := 0
	var guard := 0
	while g.running and table.size() > 1 and not deck.is_empty() and guard < 64:
		guard += 1
		var peer: int = table[idx]
		_casino_actor = peer  # 本轮到谁出牌（c_casino_action 据此鉴权）
		var pl := _player_by_peer(peer)
		var epoch := _casino_next_epoch()
		var can_peek: bool = not used_peek.has(peer)
		s_casino_turn.rpc(peer, epoch, defuse, fish, int(deck.size()), not _is_managed(pl) and can_peek)
		var drew := "top"
		if _is_managed(pl):
			await _wait(0.7)
		else:
			drew = await _casino_wait_action(epoch, 9.0)
			while drew == "peek" and g.running:
				used_peek[peer] = true
				s_casino_peek.rpc_id(peer, BombCat.card_name(String(deck.back())))
				s_casino_event.rpc("%s 偷看了牌堆顶" % pl.name, "move")
				epoch = _casino_next_epoch()
				s_casino_turn.rpc(peer, epoch, defuse, fish, int(deck.size()), false)
				drew = await _casino_wait_action(epoch, 7.0)
		if not g.running:
			return
		var card: String = String(deck.pop_back()) if drew != "bottom" else String(deck.pop_front())
		if card == "bomb":
			if int(defuse[peer]) > 0:
				defuse[peer] = int(defuse[peer]) - 1
				s_casino_event.rpc("%s 摸到炸弹，紧急打出【拆除】化解！" % pl.name, "move")
			else:
				s_casino_event.rpc("%s 摸到炸弹，轰！出局！" % pl.name, "bad")
				table.erase(peer)
		elif card == "defuse":
			defuse[peer] = int(defuse[peer]) + 1
			s_casino_event.rpc("%s 摸到一张【拆除】揣进兜里" % pl.name, "move")
		else:
			fish[peer] = int(fish[peer]) + 1
			s_casino_event.rpc("%s 摸到一条小鱼" % pl.name, "good")
		idx += 1
		if idx >= table.size():
			idx = 0
		await _wait(0.85)
	if not g.running:
		return

	var winner := BombCat.winner(table, order, fish, deck.is_empty())
	if winner == -1:
		s_casino_end.rpc(-1, 0)
		_log("赌局不了了之，奖池退还", "#8a90a5")
		return
	var wp := _player_by_peer(winner)
	wp.money = int(wp.money) + pot
	s_casino_end.rpc(winner, pot)
	_log("%s 赢下【炸弹猫】，独吞奖池 %s！" % [wp.name, GameData.fmt_money(pot)], "#f0a0c0")
	_broadcast_state()
	await _wait(2.8)

@rpc("authority", "call_local", "reliable")
func s_casino_start(game_name: String, stake: int, pot: int, order: Array) -> void:
	close()
	_casino_order = order
	_casino_table_pot = pot
	g.board.update_casino(pot, "开局中 · %s" % game_name)
	_casino_layer = Control.new()
	_casino_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_casino_layer.z_index = 55
	_casino_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_casino_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_casino_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_casino_layer.add_child(center)
	var panel := UIKit.panel_container(UIKit.PANEL, 14, Color(0.93, 0.30, 0.55), 2, 10)
	panel.custom_minimum_size = Vector2(540, 0)
	center.add_child(panel)
	var pm := UIKit.margins(20, 20, 16, 16)
	panel.add_child(pm)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pm.add_child(v)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	v.add_child(title_row)
	title_row.add_child(UIKit.label("宿舍赌场 · %s" % game_name, 20, Color(0.98, 0.58, 0.78)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)
	_casino_pot_label = UIKit.label("奖池 %s" % GameData.fmt_money(pot), 17, UIKit.ACCENT)
	title_row.add_child(_casino_pot_label)
	v.add_child(UIKit.label("每人入局费 %s · 赢家通吃 · 摸到炸弹没【拆除】就出局" % GameData.fmt_money(stake),
		13, UIKit.TEXT_DIM))
	var rows_panel := UIKit.panel_container(Color(0.10, 0.11, 0.16, 0.6), 10)
	v.add_child(rows_panel)
	var rm := UIKit.margins(10, 10, 6, 6)
	rows_panel.add_child(rm)
	var rows_box := VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 4)
	rm.add_child(rows_box)
	for peer in order:
		var row := PanelContainer.new()
		var sb := UIKit.stylebox(Color(0, 0, 0, 0), 8, Color(0, 0, 0, 0), 1)
		row.add_theme_stylebox_override("panel", sb)
		var m := UIKit.margins(6, 6, 3, 3)
		row.add_child(m)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		m.add_child(h)
		var pidx := order.find(peer)
		h.add_child(UIKit.chip(GameData.PLAYER_COLORS[pidx % GameData.PLAYER_COLORS.size()], 14))
		var nm := UIKit.label(_name_by_peer(int(peer)), 14, UIKit.TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nm)
		var dl := UIKit.label("拆除 ×0", 13, Color(0.66, 0.52, 0.95))
		h.add_child(dl)
		var fl := UIKit.label("小鱼 ×0", 13, UIKit.GOOD)
		h.add_child(fl)
		rows_box.add_child(row)
		_casino_rows[int(peer)] = {"root": row, "sb": sb, "defuse_l": dl, "fish_l": fl}
	_casino_deck_label = UIKit.label("牌堆剩余 12 张", 13, UIKit.TEXT_DIM)
	v.add_child(_casino_deck_label)
	_casino_log = RichTextLabel.new()
	_casino_log.scroll_following = true
	_casino_log.custom_minimum_size = Vector2(0, 108)
	_casino_log.add_theme_font_size_override("normal_font_size", 13)
	v.add_child(_casino_log)
	_casino_status = UIKit.label("", 14, UIKit.TEXT)
	_casino_status.custom_minimum_size = Vector2(0, 20)
	v.add_child(_casino_status)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	v.add_child(btn_row)
	_casino_btn_peek = UIKit.button("透视一次（看牌堆顶）", 14)
	_casino_btn_peek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_casino_btn_peek.pressed.connect(func() -> void: _on_casino_action("peek"))
	btn_row.add_child(_casino_btn_peek)
	_casino_btn_top = UIKit.button("抽牌堆顶", 14, "primary")
	_casino_btn_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_casino_btn_top.pressed.connect(func() -> void: _on_casino_action("top"))
	btn_row.add_child(_casino_btn_top)
	_casino_btn_bottom = UIKit.button("抽牌堆底", 14)
	_casino_btn_bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_casino_btn_bottom.pressed.connect(func() -> void: _on_casino_action("bottom"))
	btn_row.add_child(_casino_btn_bottom)
	for b in [_casino_btn_peek, _casino_btn_top, _casino_btn_bottom]:
		b.disabled = true
	_casino_my_epoch = -1
	Fx.play("card", -2.0)

@rpc("authority", "call_local", "reliable")
func s_casino_turn(peer: int, epoch: int, defuse: Dictionary, fish: Dictionary, deck_left: int, interactive: bool) -> void:
	g.board.update_casino(_casino_table_pot, "轮到 %s · 牌堆剩 %d 张" % [_name_by_peer(peer), deck_left])
	if _casino_layer == null or not is_instance_valid(_casino_layer):
		return
	_casino_deck_label.text = "牌堆剩余 %d 张" % deck_left
	for k in _casino_rows:
		var row: Dictionary = _casino_rows[k]
		var active: bool = int(k) == peer
		var sb: StyleBoxFlat = row.sb
		sb.bg_color = Color(0.93, 0.30, 0.55, 0.12) if active else Color(0, 0, 0, 0)
		sb.border_color = Color(0.93, 0.30, 0.55, 0.6) if active else Color(0, 0, 0, 0)
		row.defuse_l.text = "拆除 ×%d" % int(defuse.get(k, 0))
		row.fish_l.text = "小鱼 ×%d" % int(fish.get(k, 0))
	var my: bool = peer == g.my_peer and interactive
	_casino_my_epoch = epoch if my else -1
	_casino_btn_top.disabled = not my
	_casino_btn_bottom.disabled = not my
	_casino_btn_peek.disabled = not my or not interactive
	if my:
		_casino_status.text = "轮到你！选择从哪抽一张（透视可先偷看牌堆顶）"
		_casino_status.add_theme_color_override("font_color", UIKit.ACCENT)
	else:
		_casino_status.text = "等待 %s 行动…" % _name_by_peer(peer)
		_casino_status.add_theme_color_override("font_color", UIKit.TEXT_DIM)

@rpc("authority", "call_local", "reliable")
func s_casino_event(text: String, kind: String) -> void:
	if _casino_log == null or not is_instance_valid(_casino_log):
		return
	var col := "#dfe3ee"
	match kind:
		"good": col = "#74d188"
		"bad": col = "#ef7b74"
		"move": col = "#8fb7f2"
	_log_text_append(_casino_log, text, col)
	if kind == "bad":
		Fx.play("bust", -6.0)

func _log_text_append(rt: RichTextLabel, text: String, col: String) -> void:
	var safe := text.replace("[", "［")
	rt.append_text("[color=%s]%s[/color]\n" % [col, safe])

@rpc("authority", "call_remote", "reliable")
func s_casino_peek(card: String) -> void:
	if _casino_log == null or not is_instance_valid(_casino_log):
		return
	_log_text_append(_casino_log, "（透视）牌堆顶是【%s】" % card, "#f0c064")

@rpc("authority", "call_local", "reliable")
func s_casino_end(winner_peer: int, pot: int) -> void:
	_casino_table_pot = 0
	g.board.update_casino(0, "歇业中")
	if _casino_layer == null or not is_instance_valid(_casino_layer):
		return
	_casino_my_epoch = -1
	for b in [_casino_btn_peek, _casino_btn_top, _casino_btn_bottom]:
		b.disabled = true
	if winner_peer == -1:
		_casino_status.text = "赌局不了了之…"
	elif winner_peer == g.my_peer:
		_casino_status.text = "你赢下了 %s 奖池，通吃全场！" % GameData.fmt_money(pot)
		_casino_status.add_theme_color_override("font_color", UIKit.ACCENT)
		Fx.play("cash", 0.0)
	else:
		_casino_status.text = "%s 独吞奖池 %s！" % [_name_by_peer(winner_peer), GameData.fmt_money(pot)]
		_casino_status.add_theme_color_override("font_color", Color(0.98, 0.58, 0.78))
	var t := create_tween()
	t.tween_interval(2.6)
	t.tween_callback(close)

func _on_casino_action(action: String) -> void:
	if _casino_my_epoch < 0:
		return
	var epoch := _casino_my_epoch
	_casino_my_epoch = -1
	for b in [_casino_btn_peek, _casino_btn_top, _casino_btn_bottom]:
		b.disabled = true
	if multiplayer.is_server():
		_casino_action = {"epoch": epoch, "action": action}
	else:
		c_casino_action.rpc_id(1, epoch, action)

@rpc("any_peer", "call_remote", "reliable")
func c_casino_action(epoch: int, action: String) -> void:
	if not multiplayer.is_server():
		return
	# epoch 通过 s_casino_turn 广播给所有人，不能用来鉴权；
	# 必须确认来源就是当局出牌的玩家，否则旁观者能抢先替 TA 出牌（见 fix/v0.0.2）。
	if multiplayer.get_remote_sender_id() != _casino_actor:
		return
	_casino_action = {"epoch": epoch, "action": action}

func close() -> void:
	_casino_my_epoch = -1
	if _casino_layer != null and is_instance_valid(_casino_layer):
		_casino_layer.queue_free()
	_casino_layer = null
	_casino_rows = {}
	_casino_log = null
