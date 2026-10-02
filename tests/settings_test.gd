extends SceneTree
## 开局设置单测（操作限时挡位）：godot --headless --path . --script tests/settings_test.gd
## 口径见 docs/gameplay/开局设置.md §三之一。

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
	print("SETTINGS TEST: %s" % ("PASS" if fails == 0 else "%d FAILURES" % fails))
	quit(0 if fails == 0 else 1)

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
