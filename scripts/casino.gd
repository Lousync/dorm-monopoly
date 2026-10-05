extends Node
## 赌场小游戏「投骰子」的回合主干与演出（从 game.gd 搬出，见审查结论）。
##
## 房主权威：下注、掷骰、判定都在房主侧；客户端只渲染（抽游戏、骰子）。
## 表现自带：触发时拉起独占整屏的全屏演出层（挂到 `g` 上），不再借用 board 的世界层。
## 作为 game 的子节点存在，好让 s_casino_* 的 RPC 路径在各端一致。

var g                       # 宿主：对局场景（game.gd）

var _casino_table_pot := 0        # 演出层显示中的奖池

# ---------------- 全屏演出层（触发时独占整屏，照小卖部/暂停菜单那套：压暗底 + 居中面板） ----------------
const REEL_SIZE := Vector2(880, 236)
const CARD_W := 200.0
const DRAW_HIT_IDX := 23
const DRAW_COUNT := 28

var _ui_layer: Control
var _reel: Panel
var _track: Control
var _dice_row: HBoxContainer
var _hint_l: Label
var _pot_l: Label
var _dice := {}                 # peer -> Label
var _order: Array = []
var _names := {}                # peer -> 名字

# ---------------- 纯规则（可单测） ----------------
## 点数并列最大者（按 order 顺序返回 peer 数组）
static func max_peers(vals: Dictionary, order: Array) -> Array:
	var mx := 0
	for peer in order:
		mx = maxi(mx, int(vals.get(int(peer), 0)))
	var out: Array = []
	for peer in order:
		if int(vals.get(int(peer), 0)) == mx:
			out.append(int(peer))
	return out

## 奖池按人数平分，余数按顺序逐人 +1
static func split(pot: int, n: int) -> Array:
	var share := int(pot / n)
	var rem := pot - share * n
	var out: Array = []
	for i in n:
		out.append(share + (1 if i < rem else 0))
	return out

# ---------------- 转发给宿主 ----------------
func _log(line: String, color: String = "#dfe3ee") -> void:
	g._log(line, color)

func _wait(sec: float) -> void:
	await g._wait(sec)

func _name_by_peer(peer: int) -> String:
	return g._name_by_peer(peer)

func _player_by_peer(peer: int) -> Dictionary:
	return g._player_by_peer(peer)

func _broadcast_state() -> void:
	g._broadcast_state()

## 落进赌场格：全员下注 → 相机聚焦 + 抽游戏 → 投骰子 → 最大者通吃（平局平分）
func run(p: Dictionary) -> void:
	var alive: Array = g.hp.filter(func(x: Dictionary) -> bool: return bool(x.alive))
	if alive.size() < 2:
		_log("%s 走进赌场，却无人奉陪，悻悻离开" % p.name, "#8a90a5")
		return
	var order: Array = []
	var names := {}
	var pot := 0
	for a in alive:
		var pay: int = mini(GameData.CASINO_STAKE, int(a.money))
		a.money = int(a.money) - pay
		pot += pay
		order.append(int(a.peer))
		names[int(a.peer)] = String(a.name)
	_broadcast_state()
	s_casino_start.rpc("投骰子", GameData.CASINO_STAKE, pot, order, names)
	_log("全员下注 %s，奖池 %s，赢家通吃！" % [
		GameData.fmt_money(GameData.CASINO_STAKE), GameData.fmt_money(pot)], "#f0a0c0")

	await _wait(3.0)   # 相机聚焦 + 抽游戏演出（各端本地播放）

	# 每人同时掷一颗 6 面骰
	var vals := {}
	for peer in order:
		vals[int(peer)] = randi_range(1, 6)
	s_casino_roll.rpc(vals)
	await _wait(2.0)
	if not g.running:
		return

	# 最大者通吃；平局并列者平分（余数按行动顺序逐人 +1）
	var winners: Array = max_peers(vals, order)
	var shares: Array = split(pot, winners.size())
	var maxv := 0
	for peer in winners:
		maxv = maxi(maxv, int(vals[int(peer)]))
	for i in winners.size():
		var wp := _player_by_peer(int(winners[i]))
		wp.money = int(wp.money) + int(shares[i])
	s_casino_end.rpc(winners, pot)
	if winners.size() == 1:
		_log("%s 掷出 %d 点，赢下【投骰子】，独吞奖池 %s！" % [
			_name_by_peer(int(winners[0])), maxv, GameData.fmt_money(pot)], "#f0a0c0")
	else:
		_log("%d 人并列 %d 点，平分奖池 %s" % [
			winners.size(), maxv, GameData.fmt_money(pot)], "#f0a0c0")
	_broadcast_state()
	await _wait(2.8)

@rpc("authority", "call_local", "reliable")
func s_casino_start(game_name: String, stake: int, pot: int, order: Array, names: Dictionary) -> void:
	_casino_table_pot = pot
	_show()
	_pot_l.text = "奖池 %s" % GameData.fmt_money(pot)
	_enter(order, names)
	_play_draw(game_name)

@rpc("authority", "call_local", "reliable")
func s_casino_roll(vals: Dictionary) -> void:
	_show_rolls(vals)

@rpc("authority", "call_local", "reliable")
func s_casino_end(winners: Array, pot: int) -> void:
	_casino_table_pot = 0
	_mark_winners(winners)
	var txt := ""
	if winners.size() == 1 and int(winners[0]) == g.my_peer:
		txt = "你赢下了 %s 奖池，通吃全场！" % GameData.fmt_money(pot)
		Fx.play("cash", 0.0)
	elif winners.size() == 1:
		txt = "%s 掷出最高点，独吞奖池 %s！" % [_name_by_peer(int(winners[0])), GameData.fmt_money(pot)]
	else:
		txt = "%d 人并列最高点，平分奖池 %s" % [winners.size(), GameData.fmt_money(pot)]
	if _hint_l != null and is_instance_valid(_hint_l):
		_hint_l.text = txt
	var t := create_tween()
	t.tween_interval(2.8)
	t.tween_callback(_finish)

func _finish() -> void:
	_hide()

## 对局结束 / 重置时清理（保留旧接口名，game.gd: _show_game_over 会调用）
func close() -> void:
	_casino_table_pot = 0
	_hide()

# ---------------- 全屏演出层：构建 / 显隐 ----------------

func _build_ui() -> void:
	if _ui_layer != null and is_instance_valid(_ui_layer):
		return
	_ui_layer = Control.new()
	_ui_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_layer.visible = false
	# 高于其它**屏幕层**控件（弹问 60 / 结算 50），否则会被它们压在压暗底之下。
	# 注意：不必再「盖住 board 内部元素」——棋盘住在 SubViewport 里，棋子 20 / 光环 15
	# 那份 z_index 不再跨层穿帮（见 doc/development/架构总览.md §五）。70 这个值保持不变。
	_ui_layer.z_index = 70
	g.add_child(_ui_layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.05, 0.035, 0.94)      # 比暂停菜单更暗：赌场独占整屏
	dim.mouse_filter = Control.MOUSE_FILTER_STOP    # 模态，吞掉面板外的点击
	_ui_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(center)

	var panel := UIKit.panel_container(Color(0.062, 0.155, 0.105, 0.98), 18,
		Color(UIKit.ACCENT_DEEP.r, UIKit.ACCENT_DEEP.g, UIKit.ACCENT_DEEP.b), 2, 18)
	panel.custom_minimum_size = Vector2(960, 0)
	center.add_child(panel)
	var pm := UIKit.margins(28, 28, 22, 22)
	panel.add_child(pm)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	pm.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	var ic := TextureRect.new()
	ic.texture = UIKit.icon("casino")
	ic.custom_minimum_size = Vector2(34, 34)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	head.add_child(UIKit.label("宿舍赌场 · 抽游戏", 26, UIKit.ACCENT_HI))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_pot_l = UIKit.label("奖池 ¥0", 22, UIKit.ACCENT)
	head.add_child(_pot_l)

	_reel = Panel.new()
	_reel.custom_minimum_size = REEL_SIZE
	_reel.clip_contents = true
	_reel.add_theme_stylebox_override("panel", UIKit.card_stylebox(
		Color(0.03, 0.08, 0.05, 0.7), 10,
		Color(UIKit.ACCENT_HI.r, UIKit.ACCENT_HI.g, UIKit.ACCENT_HI.b, 0.4), 1, 8))
	v.add_child(_reel)
	_track = Control.new()
	_reel.add_child(_track)
	var mark := Panel.new()
	mark.position = Vector2(REEL_SIZE.x * 0.5 - 2.0, 0.0)
	mark.size = Vector2(4, REEL_SIZE.y)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_theme_stylebox_override("panel", UIKit.stylebox(UIKit.ACCENT, 0, Color(0, 0, 0, 0), 0))
	_reel.add_child(mark)

	_dice_row = HBoxContainer.new()
	_dice_row.add_theme_constant_override("separation", 48)
	_dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_dice_row.custom_minimum_size = Vector2(0, 110)
	v.add_child(_dice_row)

	_hint_l = UIKit.label("", 20, UIKit.ACCENT)
	_hint_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_hint_l)

func _show() -> void:
	_build_ui()
	_ui_layer.visible = true
	g.move_child(_ui_layer, g.get_child_count() - 1)   # 压住底栏与两侧栏

func _hide() -> void:
	if _ui_layer != null and is_instance_valid(_ui_layer):
		_ui_layer.visible = false

# ---------------- 全屏演出层：场景 / 抽游戏 / 掷骰 ----------------

## 铺好本局场景（骰子行清空、结果提示清空、记录本局名单）
## 提示必须在这里清：面板是常驻的（`_build_ui` 只建一次），不清就会把上一轮的
## 「XXX 掷出最高点，独吞奖池 ¥X！」一直留到本轮 s_casino_end 覆盖为止——
## 被删的原实现靠每轮重建 Label 天然清空，搬家时漏了。
func _enter(order: Array, names: Dictionary) -> void:
	_order = order
	_names = names
	_dice = {}
	_hint_l.text = ""
	for c in _dice_row.get_children():
		c.queue_free()

## 抽游戏：CSGO 式横向卷轴，定格在命中的游戏
func _play_draw(hit: String) -> void:
	for c in _track.get_children():
		c.queue_free()
	var names := [hit, "❓ 敬请期待", "❓ 敬请期待", "❓ 敬请期待"]
	for i in DRAW_COUNT:
		var nm: String = names[0] if i == DRAW_HIT_IDX else names[(i % 3) + 1]
		var card := Panel.new()
		card.position = Vector2(i * CARD_W, 0)
		card.size = Vector2(CARD_W - 12.0, REEL_SIZE.y)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_theme_stylebox_override("panel", UIKit.card_stylebox(
			Color(0.13, 0.19, 0.29), 10, Color(0.28, 0.38, 0.55), 2, 8))
		var lab := UIKit.label(nm, 22, UIKit.ACCENT_HI if i == DRAW_HIT_IDX else UIKit.TEXT_DIM)
		lab.set_anchors_preset(Control.PRESET_FULL_RECT)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(lab)
		_track.add_child(card)
	_track.position = Vector2(0, 0)
	var target := -(DRAW_HIT_IDX * CARD_W + CARD_W * 0.5 - REEL_SIZE.x * 0.5)
	var tw := create_tween()
	tw.tween_property(_track, "position:x", target - 28.0, 2.6)\
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tw.tween_property(_track, "position:x", target, 0.25)
	Fx.play("card", -2.0)

## 掷骰：为每位玩家起一颗骰子，先滚后定
func _show_rolls(vals: Dictionary) -> void:
	if _dice_row == null or not is_instance_valid(_dice_row):
		return
	for c in _dice_row.get_children():
		c.queue_free()
	_dice = {}
	var faces := ["⚀", "⚁", "⚂", "⚃", "⚄", "⚅"]
	for peer in _order:
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var dl := UIKit.label("⚀", 44, UIKit.TEXT)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(dl)
		var nm := UIKit.label(String(_names.get(int(peer), str(peer))), 15, UIKit.TEXT_DIM)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(nm)
		_dice_row.add_child(col)
		_dice[int(peer)] = dl
	var tw := create_tween()
	for i in 8:
		tw.tween_callback(func() -> void:
			for k in _dice:
				var l: Label = _dice[k]
				if is_instance_valid(l):
					l.text = faces[randi_range(0, 5)]).set_delay(0.08)
	tw.tween_callback(func() -> void:
		for k in _dice:
			var l: Label = _dice[k]
			if is_instance_valid(l):
				l.text = faces[clampi(int(vals.get(k, 1)) - 1, 0, 5)])
	Fx.play("card", -2.0)

## 高亮赢家（平分时多人高亮）
func _mark_winners(winners: Array) -> void:
	for k in _dice:
		var l: Label = _dice[k]
		if not is_instance_valid(l):
			continue
		l.add_theme_color_override("font_color",
			UIKit.ACCENT if winners.has(int(k)) else UIKit.TEXT)
