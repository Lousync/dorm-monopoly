class_name BombCat
## 赌桌小游戏「炸弹猫」的纯规则（可单测，不碰 UI / RPC / 房间状态）。
## 从 game.gd 抽出来：那里的赌场代码（约 340 行，含牌堆、回合循环、5 个 RPC 与
## 一整层 UI）此前没有任何测试覆盖，规则与表现搅在一起无从下手（见审查结论）。

const BOMB := "bomb"
const DEFUSE := "defuse"
const FISH := "fish"

## 12 张牌堆：炸弹 ×3、拆除 ×2、小鱼 ×7（README「宿舍赌场」一节）。
static func deck() -> Array:
	var d := [BOMB, BOMB, BOMB, DEFUSE, DEFUSE]
	for i in 7:
		d.append(FISH)
	d.shuffle()
	return d

static func card_name(c: String) -> String:
	match c:
		BOMB: return "炸弹"
		DEFUSE: return "拆除"
		_: return "小鱼"

## 胜负判定：场上只剩一人则他通吃；牌堆抽空则小鱼最多者通吃。
## deck_empty=false（还剩多人且牌没抽空）判不出赢家，返回 -1 —— 正常流程不可达：
## 回合循环的条件是 `table.size() > 1 and not deck.is_empty()`，退出必然满足其一。
## 保留该分支只为不改变既有行为（见审查结论）。
static func winner(table: Array, order: Array, fish: Dictionary, deck_empty := true) -> int:
	if table.size() == 1:
		return int(table[0])
	if not deck_empty:
		return -1
	var best := -1
	var win := -1
	for peer in order:
		if table.has(peer) and int(fish.get(peer, 0)) > best:
			best = int(fish.get(peer, 0))
			win = int(peer)
	return win
