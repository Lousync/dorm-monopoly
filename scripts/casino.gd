extends Node
## 赌场小游戏「投骰子」的回合主干与演出（从 game.gd 搬出，见审查结论）。
##
## 房主权威：下注、掷骰、判定都在房主侧；客户端只渲染（相机聚焦、抽游戏、骰子）。
## 表现交给 `board`（相机聚焦 + 赌场区域场景）；本节点只管流程与 RPC。
## 作为 game 的子节点存在，好让 s_casino_* 的 RPC 路径在各端一致。

var g                       # 宿主：对局场景（game.gd）

var _casino_table_pot := 0        # 桌面赌场设施显示中的奖池

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
	if g.board != null:
		g.board.update_casino(pot, "开局中 · %s" % game_name)
		g.board.casino_enter(order, pot, names)
		g.board.focus_casino()
		g.board.casino_play_draw(game_name)

@rpc("authority", "call_local", "reliable")
func s_casino_roll(vals: Dictionary) -> void:
	if g.board != null:
		g.board.casino_show_rolls(vals)
		g.board.update_casino(_casino_table_pot, "掷骰中…")

@rpc("authority", "call_local", "reliable")
func s_casino_end(winners: Array, pot: int) -> void:
	_casino_table_pot = 0
	if g.board != null:
		g.board.casino_mark_winners(winners)
		g.board.update_casino(0, "歇业中")
		var txt := ""
		if winners.size() == 1 and int(winners[0]) == g.my_peer:
			txt = "你赢下了 %s 奖池，通吃全场！" % GameData.fmt_money(pot)
			Fx.play("cash", 0.0)
		elif winners.size() == 1:
			txt = "%s 掷出最高点，独吞奖池 %s！" % [_name_by_peer(int(winners[0])), GameData.fmt_money(pot)]
		else:
			txt = "%d 人并列最高点，平分奖池 %s" % [winners.size(), GameData.fmt_money(pot)]
		g.board.casino_set_hint(txt)
	var t := create_tween()
	t.tween_interval(2.8)
	t.tween_callback(_finish)

func _finish() -> void:
	if g.board != null:
		g.board.casino_leave()

## 对局结束 / 重置时清理（保留旧接口名，game.gd: _show_game_over 会调用）
func close() -> void:
	_casino_table_pot = 0
	if g != null and g.board != null:
		g.board.casino_leave()
