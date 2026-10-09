extends SceneTree
## 开局设置单测（操作限时挡位）：godot --headless --path . --script tests/settings_test.gd
## 口径见 doc/game-design/开局设置.md §三之一。

var fails := 0

func _initialize() -> void:
	create_timer(0.1).timeout.connect(_run)

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

func _run() -> void:
	print("== 操作限时挡位 ==")
	_test_mapping()
	_test_rules_text()     # 纯静态，无引擎依赖
	_test_object()         # 设置对象：默认值 / copy / 钳制
	_test_broadcast()
	_test_in_game_tier()   # 无 await，直接调
	await _test_window()   # 协程：不等它跑完 quit() 会先执行，断言全部落空（假绿）
	await _test_save_cfg_keeps_sections()   # 同为协程：不 await 会假绿（见上）
	await _test_economy_and_liq()           # 经济设置 + 变卖保底（协程）
	print("SETTINGS TEST: %s" % ("PASS" if fails == 0 else "%d FAILURES" % fails))
	quit(0 if fails == 0 else 1)

func _mk_player(peer: int, nm: String) -> Dictionary:
	return {"peer": peer, "name": nm, "color": peer - 1, "bot": false, "money": 5000,
		"pos": 0, "alive": true, "skip": 0, "sleep": 0, "stamina": 3, "items": [],
		"item_used": false, "cheat_roll": -1}

## 设置对象本体：默认值 = 现状常量（硬约定）；copy 全量；越界钳制
func _test_object() -> void:
	var s := GameSettings.new()
	_check(s.start_cash == GameData.START_MONEY, "起始资金默认 = START_MONEY")
	_check(s.start_salary == GameData.SALARY, "起点补贴默认 = SALARY")
	_check(s.liq_on, "破产变卖保底默认开（例外一：「默认 ≠ 现状」）")
	_check(s.max_rounds == 30 and s.win_mode == "rounds" and s.win_cash == 50000,
		"回合上限 30 / 胜利条件总资产排名 / 目标现金 5 万 默认")
	_check(s.shop_on and s.black_on and s.casino_on, "小卖部 / 黑市 / 赌场默认开")
	_check(s.tech_on, "开局科技默认开（例外二：「默认 ≠ 现状」，2026-10-09 用户定）")
	_check(s.tech_tier == GameSettings.TECH_TIER_RANDOM, "科技等级默认 = 随机")
	var c := s.copy()
	c.start_cash = 40000
	c.win_mode = "cash"
	c.shop_on = false
	_check(s.start_cash == GameData.START_MONEY and s.win_mode == "rounds" and s.shop_on,
		"copy() 是深拷贝语义：改副本不动本体")
	c.clamp_all()
	_check(c.start_cash == 40000 and c.win_mode == "cash" and not c.shop_on, "合法值原样通过钳制")
	var b := GameSettings.new()
	b.start_cash = -5
	b.start_salary = 999999
	b.max_rounds = 47
	b.win_mode = "bogus"
	b.win_cash = 99999999
	b.tech_tier = "bogus"
	b.clamp_all()
	_check(b.start_cash == 0, "起始资金负数钳到 0")
	_check(b.start_salary == GameSettings.SALARY_MAX, "起点补贴越界钳到上限")
	_check(b.max_rounds == 30, "回合上限非法档位（47）回落 30")
	_check(b.win_mode == "rounds", "胜利条件非法值回落 rounds")
	_check(b.win_cash == GameSettings.WIN_CASH_MAX, "目标现金越界钳到上限")
	_check(b.tech_tier == GameSettings.TECH_TIER_RANDOM, "科技等级非法值回落 random")
	# 回合上限档位 2026-10-09 改为 30 / 45 / 60 / 80 / 不限 —— 逐个钉住（原写死 30/60/90）
	for legal in [30, 45, 60, 80, 0]:
		var d := GameSettings.new()
		d.max_rounds = legal
		d.clamp_all()
		_check(d.max_rounds == legal, "回合上限 %d 是合法档位" % legal)
	var e := GameSettings.new()
	e.max_rounds = 90
	e.clamp_all()
	_check(e.max_rounds == 30, "回合上限 90 已换掉（原档位）→ 回落 30")

## 经济设置生效 + 变卖保底（房间口径见 doc/game-design/经济与胜负.md §三/§四）
func _test_economy_and_liq() -> void:
	print("== 经济设置与破产变卖保底 ==")
	var g := _host_game(7801)
	if g == null:
		return
	# 让 _host_setup 的 1.5 秒余波彻底死透再开 running（口径同 _test_window 的守门注释）
	g.running = false
	await create_timer(1.9).timeout
	g.running = true

	# 回合上限档位：0 = 不限（_rounds_exhausted 永不触发）；30 = 到轮触发
	g._settings.max_rounds = 0
	g.round_no = 999
	_check(not g._rounds_exhausted(), "回合上限 0（不限）：round 999 也不结算")
	g._settings.max_rounds = 30
	g.round_no = 31
	_check(g._rounds_exhausted(), "回合上限 30：round 31 触发结算")
	_check(not g.running, "到轮结算后对局结束")
	g.running = true
	g._settings.max_rounds = 30
	g.round_no = 1
	_check(not g._rounds_exhausted(), "round 1 不触发结算（running 已恢复）")

	# 目标现金：先到设定金额者立即胜
	g._settings.win_mode = "cash"
	g._settings.win_cash = 8000
	var rich := _mk_player(1, "甲")
	var poor := _mk_player(-1, "机器人乙")
	rich.money = 8000
	poor.money = 100
	poor.bot = true
	g.hp = [rich, poor]
	g._check_end()
	_check(not g.running and int(g.winner) == 1, "目标现金模式：达到 8000 立即获胜")
	g.running = true
	rich.money = 7999
	g._check_end()
	_check(g.running, "差 1 块没到目标：不结束（与最后存活判据并存）")

	# 变卖保底·成功：机器人玩家欠 1000，名下两块 Lv1 地 → 卖两块凑足保命
	# （回收价按真实格数据现算：投入 = 地价 + 等级 × 升级费，回收 = 投入 × 30%）
	g._settings.win_mode = "rounds"   # 关掉目标现金，别让变卖中途触发胜利
	g.running = true
	g._settings.liq_on = true
	var seller := _mk_player(1, "甲")
	seller.bot = true
	seller.money = 0
	var payee := _mk_player(-1, "机器人丙")
	payee.bot = true
	payee.money = 0
	g.hp = [seller, payee]
	g.htiles = _fresh_tiles()
	var i1 := _prop_idx(0)
	var i2 := _prop_idx(1)
	g.htiles[i1] = {"owner": 1, "level": 1}
	g.htiles[i2] = {"owner": 1, "level": 1}
	# 回收价按 `GameData.LIQ_RATE` 算 —— **别写死比例**：这里原写的是 0.30，
	# 2026-10-09 比例改 50% 时就成了唯一漏网的那处（其余调用点都读常量）。
	var v1 := int(round(float(int(GameData.TILES[i1].price) + GameData.upgrade_cost(i1)) * GameData.LIQ_RATE))
	var v2 := int(round(float(int(GameData.TILES[i2].price) + GameData.upgrade_cost(i2)) * GameData.LIQ_RATE))
	_check(mini(v1, v2) >= 1000, "前置：最便宜一块的回收价已够覆盖 1000 应付款（%d / %d）" % [v1, v2])
	await g._pay(seller, 1000, payee)
	_check(bool(seller.alive), "变卖保底：凑足应付款后不出局")
	# 凑足即停：只卖投入最低的那块（回收已 ≥ 应付款），另一块保留
	var cheap := i2 if v2 < v1 else i1
	var dear := i1 if cheap == i2 else i2
	var vcheap := mini(v1, v2)
	_check(int(seller.money) == vcheap - 1000, "变卖保底：只卖到凑足为止，余款保留（%d − 1000）" % vcheap)
	_check(int(payee.money) == 1000, "收款方收到足额应付款")
	_check(int(g.htiles[cheap].owner) == GameData.NO_OWNER and int(g.htiles[cheap].level) == 0,
		"变卖后的地皮无主、等级清零")
	_check(int(g.htiles[dear].owner) == 1, "凑足即停：没卖的那块仍是卖家名下")

	# 变卖保底·失败：欠 10 万，全部卖光也凑不足 → 原破产流程出局
	seller.money = 0
	seller.alive = true
	payee.money = 0
	g.htiles = _fresh_tiles()
	g.htiles[i1] = {"owner": 1, "level": 1}
	g.htiles[i2] = {"owner": 1, "level": 1}
	await g._pay(seller, 100000, payee)
	_check(not bool(seller.alive), "凑不足：变卖保底救不回 → 按原破产流程出局")
	_check(int(seller.money) == 0 and int(g.htiles[i1].owner) == GameData.NO_OWNER,
		"破产清算照旧：现金清零、地皮收归学校")

	# 变卖保底·关闭：开关关掉时直接走破产（不进变卖会话）
	g._settings.liq_on = false
	seller.alive = true
	seller.money = 0
	g.htiles = _fresh_tiles()
	g.htiles[i1] = {"owner": 1, "level": 1}
	var epoch_before: int = g._liq_epoch
	await g._pay(seller, 1000, {})
	_check(not bool(seller.alive), "开关关 = 不变卖，付不起直接出局")
	_check(int(g._liq_epoch) == epoch_before, "关闭开关时不开启变卖会话")

	# 付完恰好归零不算破产（付得起就不该碰变卖）
	g._settings.liq_on = true
	seller.alive = true
	seller.money = 1000
	g.htiles = _fresh_tiles()
	g.htiles[i1] = {"owner": 1, "level": 1}
	epoch_before = g._liq_epoch
	await g._pay(seller, 1000, {})
	_check(bool(seller.alive) and int(seller.money) == 0, "付得起、付完归零：不算破产、不触发变卖")
	_check(int(g._liq_epoch) == epoch_before, "付得起时不开启变卖会话")
	g.queue_free()

func _fresh_tiles() -> Array:
	var out := []
	for i in GameData.TILES.size():
		out.append({"owner": GameData.NO_OWNER, "level": 0})
	return out

func _prop_idx(offset: int) -> int:
	var n := 0
	for i in GameData.TILES.size():
		if String(GameData.TILES[i].get("type", "")) == "property":
			if n == offset:
				return i
			n += 1
	return -1

## 起一个房主对局实例；running 关掉，只测状态快照（不跑自动回合循环）。
## 顺序照抄 tests/shop_test.gd：先起服务器再挂节点，_host_setup() 里的
## `await _wait(1.5)` 之后 running 已是 false，_run_game() 直接退出。
func _host_game(port: int) -> Node:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, 3) != OK:
		printerr("server create failed"); quit(1); return null
	var mp := MultiplayerAPI.create_default_interface()
	mp.multiplayer_peer = peer
	set_multiplayer(mp, "/root")
	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	g.my_peer = 1
	g.running = false
	g.hp = [_mk_player(1, "甲")]
	g.htiles = []
	for i in GameData.TILES.size():
		g.htiles.append({"owner": GameData.NO_OWNER, "level": 0})
	return g

func _test_broadcast() -> void:
	var g := _host_game(7796)
	if g == null:
		return
	g._broadcast_state()
	_check(String(g.st.get("timeout_tier", "")) == GameSettings.TIER_CURRENT,
		"开局快照带 timeout_tier = 现状")
	g._settings.timeout_tier = "30"
	g._broadcast_state()
	_check(String(g.st.get("timeout_tier", "")) == "30", "房主改挡后快照同步为 30")
	# GameSettings.copy() 的首个消费方：房主拿的是副本，对局内改挡不回写大厅
	# （autoload 标识符在 --script 主脚本里编译不过，按 hud_test 的写法运行时取节点）
	var lobby := root.get_node_or_null("Net")
	_check(lobby != null, "测试环境能取到 autoload Net")
	_check(g._settings != lobby.game_settings, "房主用配置副本，非 autoload 同一对象")
	_check(lobby.game_settings.timeout_tier == GameSettings.TIER_CURRENT, "对局内改挡不回写大厅")
	# s_state 的同步分支：快照里的挡位变化要落进本地 _settings（房主 call_local 与客户端同一段代码）
	g.s_state({"phase": "playing", "round": 1, "max_rounds": 30, "turn": 1,
		"players": [], "tiles": [], "timeout_tier": "60"})
	_check(g._settings.timeout_tier == "60", "快照挡位由 30 变 60 → 本地 _settings 同步")
	g.queue_free()

func _test_in_game_tier() -> void:
	var g := _host_game(7799)
	if g == null:
		return
	g._refresh_tier_ui()
	_check(g.tier_row.visible, "房主看得到可点的挡位 chips")
	_check(not g.tier_readonly.visible, "房主不显示只读行")
	# 房主那一侧整块（说明 + chips）一起显隐。2026-10-09 统一样式后**小标题由
	# `UIKit.SectionBox` 的 legend 承担**（原先是 `tier_title` 标签）：标题房主 / 客户端
	# 都看得到，切的是盒子里的内容 —— 所以不再有「标题跟着 chips 一起藏」那条不变式。
	_check(g.tier_host_box.visible, "房主：说明 + chips 那一块整体可见")
	# g 是 Node 类型，动态属性访问返回 Variant，不能写 `:=`（类型推不出来）
	var rev: int = g._timeout_rev
	g._set_timeout_tier("30")
	_check(g._settings.timeout_tier == "30", "点挡位写进 settings")
	_check(g._timeout_rev == rev + 1, "改挡位 → _timeout_rev +1（触发重计时）")
	_check(String(g.st.get("timeout_tier", "")) == "30", "改挡位 → 快照同步")
	# 只读行不再重复「操作限时：」前缀 —— 那两个字现在由上面的小节标题（legend）说
	_check(g.tier_readonly.text.begins_with("30 秒"), "只读行文案跟随挡位（前缀由小节标题承担）")
	g._set_timeout_tier("bogus")
	_check(g._settings.timeout_tier == "30", "非法挡位被拒（回落靠 GameSettings）")
	g.queue_free()

func _test_mapping() -> void:
	var cur := GameSettings.TIER_CURRENT
	# 现状档 = 各环节原常量（默认行为与今天完全一致）
	_check(GameSettings.turn_seconds(cur, "roll") == GameData.ROLL_TIMEOUT, "现状·掷轮 = ROLL_TIMEOUT")
	_check(GameSettings.turn_seconds(cur, "prompt") == GameData.PROMPT_TIMEOUT, "现状·决策 = PROMPT_TIMEOUT")
	_check(GameSettings.turn_seconds(cur, "item") == ItemData.ITEM_TIMEOUT, "现状·道具 = ITEM_TIMEOUT")
	_check(GameSettings.turn_seconds(cur, "shop") == ItemData.SHOP_TIMEOUT, "现状·逛店 = SHOP_TIMEOUT")
	_check(GameSettings.turn_seconds(cur, "black") == ItemData.BLACK_TIMEOUT, "现状·黑市 = BLACK_TIMEOUT")
	# 固定档：每个环节各自取该秒数
	for kind in ["roll", "prompt", "item", "shop", "black"]:
		_check(GameSettings.turn_seconds("15", kind) == 15.0, "15 秒档·%s" % kind)
		_check(GameSettings.turn_seconds("30", kind) == 30.0, "30 秒档·%s" % kind)
		_check(GameSettings.turn_seconds("60", kind) == 60.0, "60 秒档·%s" % kind)
		_check(GameSettings.turn_seconds(GameSettings.TIER_NONE, kind) == 0.0, "不限时档·%s" % kind)
	# 未知挡位回落现状
	_check(GameSettings.turn_seconds("bogus", "roll") == GameData.ROLL_TIMEOUT, "未知挡位回落现状")
	# 挡位清单与标签齐备（UI 依赖）
	_check(GameSettings.TIERS.size() == 5 and GameSettings.TIERS[0] == cur, "挡位清单 5 项、首位是现状")
	for t in GameSettings.TIERS:
		_check(GameSettings.TIER_LABELS.has(t), "挡位 %s 有中文标签" % t)

## 主菜单保存昵称/端口不得抹掉其他配置段：曾因新建空 ConfigFile 直接覆盖保存，
## 每开一局就把 [dev]（开发者模式/道具试验场入口）和 [audio]（音量/静音）整段抹掉，
## 表现为「开一局之后开发者模式就没了」。测试会先快照真实 settings.cfg，结束原样还回。
func _test_save_cfg_keeps_sections() -> void:
	print("== 主菜单 _save_cfg 不抹其他配置段 ==")
	const CFG := "user://settings.cfg"
	var raw := FileAccess.get_file_as_string(CFG)   # 真机可能没有此文件（空串）
	var seedc := ConfigFile.new()
	seedc.set_value("dev", "enabled", true)
	seedc.set_value("audio", "volume", 0.5)
	seedc.save(CFG)
	var mm = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(mm)
	await process_frame
	await process_frame
	mm._port_edit.text = "7777"
	mm._save_cfg()
	mm.queue_free()
	var after := ConfigFile.new()
	after.load(CFG)
	_check(bool(after.get_value("dev", "enabled", false)),
		"保存昵称/端口后 [dev] enabled 保留（开发者入口还在）")
	_check(absf(float(after.get_value("audio", "volume", 0.0)) - 0.5) < 0.001,
		"[audio] volume 保留")
	if raw == "":
		DirAccess.open("user://").remove("settings.cfg")   # 原本没有此文件 → 还原成没有
	else:
		var f := FileAccess.open(CFG, FileAccess.WRITE)
		f.store_string(raw)
		f.close()

## 规则说明文案必须跟着挡位走：非默认档下不能再说「35 秒不掷」这类现状秒数。
## 纯静态（只读 RulesText 的字符串），不依赖引擎与对局。
func _test_rules_text() -> void:
	var none_body := ""
	for pg in RulesText.pages(GameSettings.TIER_NONE):
		none_body += String(pg.body)
	_check(none_body.contains("不限时"), "不限时档：规则正文含「不限时」")
	_check(not none_body.contains("35"), "不限时档：规则正文不含「35」（不写死现状秒数）")
	var t15_body := ""
	for pg in RulesText.pages("15"):
		t15_body += String(pg.body)
	_check(t15_body.contains("15"), "15 秒档：规则正文含「15」")

## 探针：跑一次 _await_turn_window，结果写进 out[0]，arm 次数写进 arm[0]
func _probe(g: Node, kind: String, alive_ref: Array, out: Array, arm: Array) -> void:
	# g 是 Node 类型，动态调用返回 Variant，不能写 `:=`（类型推不出来）
	var r: bool = await g._await_turn_window(kind,
		func() -> bool: return bool(alive_ref[0]),
		func(_sec: float) -> void: arm[0] = int(arm[0]) + 1)
	out[0] = r

func _test_window() -> void:
	var g := _host_game(7797)
	if g == null:
		return
	# _await_turn_window 以 running 为前置，必须把它打开；但不能立刻打开：
	# _host_setup() 同步把 running 设回 true 后又 `await _wait(1.5)` → _broadcast_state()
	# → _run_game()，而 _run_game 只在首个 await（再 0.3 秒）之后才判 `while running`。
	# 若此刻就把 running 设真，t0+1.5s 时那个循环会真的开跑 _play_turn(甲)——今天的绿灯纯属侥幸。
	# 所以先让它死透（1.9s > 1.5+0.3），再打开，只为满足探针的前置条件。
	g.running = false
	await create_timer(1.9).timeout
	g.running = true

	# 不限时：不会托管；环节一结束立刻返回 false
	g._settings.timeout_tier = GameSettings.TIER_NONE
	var alive := [true]
	var out := [null]
	var arm := [0]
	_probe(g, "roll", alive, out, arm)
	await create_timer(0.6).timeout
	_check(out[0] == null, "不限时：0.6 秒内不自动托管")
	_check(int(arm[0]) == 1, "不限时：窗口只 arm 一次")
	alive[0] = false
	await create_timer(0.5).timeout
	_check(out[0] == false, "不限时：环节结束后返回 false")

	# 固定档：不会提前托管；挡位一变就重计时（on_arm 再被调一次）
	g._settings.timeout_tier = "60"
	var alive2 := [true]
	var out2 := [null]
	var arm2 := [0]
	_probe(g, "roll", alive2, out2, arm2)
	await create_timer(0.3).timeout
	_check(int(arm2[0]) == 1, "60 秒档：窗口 arm 一次")
	g._timeout_rev += 1
	await create_timer(0.4).timeout
	_check(int(arm2[0]) == 2, "挡位变化 → 按新值重计时（重新 arm）")
	_check(out2[0] == null, "60 秒档不会提前托管")
	alive2[0] = false
	await create_timer(0.5).timeout
	_check(out2[0] == false, "固定档：环节结束后返回 false")

	# 到点真该托管：15 秒档靠 Engine.time_scale 压成不到 1 秒真实时间
	# （_wait 走 SceneTree 计时器、吃 time_scale；本段自己的等待用 ignore_time_scale 免被压缩）
	Engine.time_scale = 20.0
	g._settings.timeout_tier = "15"
	var alive3 := [true]
	var out3 := [null]
	var arm3 := [0]
	_probe(g, "roll", alive3, out3, arm3)
	await create_timer(2.0, true, false, true).timeout
	_check(out3[0] == true, "15 秒档：到点返回 true（该自动托管）")
	_check(int(arm3[0]) == 1, "15 秒档：到点前只 arm 一次")
	Engine.time_scale = 1.0
	# 守门断言：上面打开 running 只是为了满足探针的前置条件，对局循环必须仍是死的。
	# 旧写法在 t0 就把 running 设真 → t0+1.8s 起 _run_game 会真的跑 _play_turn(甲)，
	# 那一步会推进 _roll_epoch（只增不减）——这条断言就是拿来钉住它的。
	_check(g._roll_epoch == 0, "对局循环未开跑（running 只是探针前置条件）")
	g.queue_free()
