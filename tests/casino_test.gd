extends SceneTree
## 赌场小游戏「炸弹猫」规则单测：godot --headless --path . --script tests/casino_test.gd
## 只测纯规则（BombCat）；回合循环 / RPC / 赌桌 UI 仍靠联机回归覆盖。

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
	seed(4242)
	print("== 牌堆构成 ==")
	var d := BombCat.deck()
	_check(d.size() == 12, "牌堆 12 张（实得 %d）" % d.size())
	_check(d.count(BombCat.BOMB) == 3, "炸弹 ×3（实得 %d）" % d.count(BombCat.BOMB))
	_check(d.count(BombCat.DEFUSE) == 2, "拆除 ×2（实得 %d）" % d.count(BombCat.DEFUSE))
	_check(d.count(BombCat.FISH) == 7, "小鱼 ×7（实得 %d）" % d.count(BombCat.FISH))

	print("== 卡面名 ==")
	_check(BombCat.card_name("bomb") == "炸弹", "bomb → 炸弹")
	_check(BombCat.card_name("defuse") == "拆除", "defuse → 拆除")
	_check(BombCat.card_name("fish") == "小鱼", "fish → 小鱼")

	print("== 胜负判定 ==")
	# 只剩一人：通吃
	_check(BombCat.winner([7], [1, 7, 9], {7: 0}) == 7, "场上只剩一人 → 他通吃")
	# 牌堆抽空：小鱼最多者赢
	_check(BombCat.winner([1, 7, 9], [1, 7, 9], {1: 1, 7: 3, 9: 2}) == 7, "小鱼最多者通吃")
	# 同鱼数：取行动顺序里靠前的（比较用 > 而非 >=）
	_check(BombCat.winner([1, 7], [1, 7], {1: 2, 7: 2}) == 1, "同鱼数取行动顺序靠前者")
	# 全员 0 条鱼也要判出人来（best 从 -1 起用 > 比较）
	_check(BombCat.winner([1, 7], [1, 7], {}) == 1, "全员零鱼也能判出赢家")
	# 已出局者不参与评选
	_check(BombCat.winner([7, 9], [1, 7, 9], {1: 9, 7: 1, 9: 2}) == 9,
		"已出局者的小鱼数不参与（1 号被炸掉后 9 号胜）")
	_check(BombCat.winner([], [1], {}) == -1, "无人可判返回 -1")
	# 牌没抽空且还剩多人：保持既有行为（判不出赢家），正常流程不可达
	_check(BombCat.winner([1, 7], [1, 7], {1: 3, 7: 1}, false) == -1,
		"牌堆未空且多人时判不出赢家（保持原行为）")

	if fails == 0:
		print("CASINO TEST: ALL PASS")
		quit(0)
	else:
		print("CASINO TEST: %d FAILURES" % fails)
		quit(1)
