class_name GameData
## 棋盘、事件卡与规则数值。棋盘为 28 格环形（四角各一格，每边 7 格）。

const MAX_PLAYERS := 4
const START_MONEY := 15000
const SALARY := 2000          # 每次踏上起点领取
const MAX_LEVEL := 3          # 装修等级上限
const MAX_ROUNDS := 30        # 回合上限，之后按身家结算
const JAIL_TILE := 7          # 宿委会（反省处）
const PROMPT_TIMEOUT := 25.0  # 购买/升级等待秒数

const PLAYER_COLORS := [
	Color(0.898, 0.282, 0.302),  # 红
	Color(0.231, 0.510, 0.965),  # 蓝
	Color(0.133, 0.773, 0.373),  # 绿
	Color(0.961, 0.620, 0.043),  # 黄
]

const GROUP_NAMES := {
	"daily": "便利店",
	"service": "生活服务",
	"canteen": "餐饮",
	"study": "学习",
	"sport": "运动",
	"teach": "教学",
}

const GROUP_COLORS := {
	"daily": Color(0.878, 0.482, 0.224),
	"service": Color(0.290, 0.624, 0.910),
	"canteen": Color(0.851, 0.325, 0.310),
	"study": Color(0.314, 0.631, 0.310),
	"sport": Color(0.910, 0.773, 0.227),
	"teach": Color(0.608, 0.349, 0.714),
}

const TILE_DESC := {
	"start": "踏上即可领取工资",
	"jail": "被查寝的同学在这里反省",
	"go_jail": "立刻被送往宿委会反省一回合",
	"rest": "卧谈会，放松一下，无事发生",
	"event": "抽取一张宿舍事件卡",
	"fine": "强制缴费，躲不掉",
}

## 28 格棋盘：0=起点(右下角)，沿底边向左，7=宿委会(左下角)，
## 14=卧谈会(左上角)，21=查寝(右上角)。
const TILES := [
	{"type": "start", "name": "起点"},
	{"type": "property", "name": "小卖部", "group": "daily", "price": 1800, "rent": 550},
	{"type": "property", "name": "奶茶店", "group": "daily", "price": 2000, "rent": 600},
	{"type": "event", "name": "机会"},
	{"type": "property", "name": "快递驿站", "group": "service", "price": 2000, "rent": 600},
	{"type": "property", "name": "澡堂", "group": "service", "price": 2200, "rent": 650},
	{"type": "property", "name": "打印店", "group": "service", "price": 2400, "rent": 700},
	{"type": "jail", "name": "宿委会"},
	{"type": "property", "name": "食堂一楼", "group": "canteen", "price": 2800, "rent": 850},
	{"type": "property", "name": "食堂二楼", "group": "canteen", "price": 3000, "rent": 900},
	{"type": "fine", "name": "校医院", "amount": 500},
	{"type": "property", "name": "咖啡屋", "group": "canteen", "price": 3200, "rent": 1000},
	{"type": "event", "name": "命运"},
	{"type": "property", "name": "超市", "group": "daily", "price": 2600, "rent": 800},
	{"type": "rest", "name": "卧谈会"},
	{"type": "property", "name": "图书馆", "group": "study", "price": 3200, "rent": 1000},
	{"type": "property", "name": "自习室", "group": "study", "price": 3400, "rent": 1050},
	{"type": "event", "name": "机会"},
	{"type": "property", "name": "操场", "group": "sport", "price": 3200, "rent": 950},
	{"type": "property", "name": "篮球场", "group": "sport", "price": 3400, "rent": 1000},
	{"type": "property", "name": "体育馆", "group": "sport", "price": 3600, "rent": 1100},
	{"type": "go_jail", "name": "查寝！"},
	{"type": "property", "name": "教学楼A", "group": "teach", "price": 3800, "rent": 1200},
	{"type": "property", "name": "教学楼B", "group": "teach", "price": 4000, "rent": 1300},
	{"type": "event", "name": "命运"},
	{"type": "property", "name": "机房", "group": "study", "price": 3800, "rent": 1250},
	{"type": "fine", "name": "缴电费", "amount": 800},
	{"type": "property", "name": "实验楼", "group": "teach", "price": 4200, "rent": 1400},
]

## 事件卡：t=文本；money=收支；from_each=每位其他室友给你；to_each=你给每位室友；
## move_to=前进移动到指定格（途中踩到起点照常领工资）；go_jail=直接送宿委会。
const EVENTS := [
	{"t": "帮宿管阿姨搬了一下午矿泉水，辛苦费 +600", "money": 600},
	{"t": "抢到食堂最后一份大鸡腿，幸福感 +400", "money": 400},
	{"t": "丢的快递找到了，平台赔付 +300", "money": 300},
	{"t": "宿舍电费欠费限时用电，补缴 -800", "money": -800},
	{"t": "校园卡丢了，补办 -150", "money": -150},
	{"t": "校园歌手大赛拿了第三名，奖金 +1000", "money": 1000},
	{"t": "熬夜打游戏，早上点名迟到，罚款 -200", "money": -200},
	{"t": "捡到饭卡完璧归赵，失主酬谢 +500", "money": 500},
	{"t": "水果摊刮刮乐中了大奖 +1500", "money": 1500},
	{"t": "期末奖学金到账 +2000", "money": 2000},
	{"t": "电脑蓝屏，送去维修 -700", "money": -700},
	{"t": "室友拼单奶茶，顺手帮你带了一杯 -300", "money": -300},
	{"t": "参加编程马拉松获奖 +1800", "money": 1800},
	{"t": "辅导员夸你宿舍卫生好，奖励 +800", "money": 800},
	{"t": "运动会志愿者补贴 +350", "money": 350},
	{"t": "水卡充值办卡费 -100", "money": -100},
	{"t": "被拉去图书馆通宵自习（移动到图书馆）", "move_to": 15},
	{"t": "坐上外卖小哥的电动车，直接回起点领工资", "move_to": 0},
	{"t": "被突击查寝！直接前往宿委会", "go_jail": true},
	{"t": "今天你过生日！每位室友发来红包 +300", "from_each": 300},
	{"t": "你请全宿舍喝奶茶，每位室友 -300", "to_each": 300},
	{"t": "期末划重点，全宿舍押题成功，每位室友凑钱请你 +500", "from_each": 500},
	{"t": "体育课体测满分，奖励 +600", "money": 600},
]

## 装修升级费用（每级）
static func upgrade_cost(idx: int) -> int:
	return int(TILES[idx].price * 0.5)

## 掷骰逐步路径（每步一个格子编号，含终点）
static func compute_path(start: int, steps: int) -> Array:
	var path := []
	var cur := start
	for i in steps:
		cur = (cur + 1) % TILES.size()
		path.append(cur)
	return path

## 事件「移动到某格」的前进路径
static func compute_path_to(start: int, target: int) -> Array:
	var path := []
	var cur := start
	var guard := 0
	while cur != target and guard < 56:
		cur = (cur + 1) % TILES.size()
		path.append(cur)
		guard += 1
	return path

## 当前租金 = 基础租金 × (1+装修等级) × (垄断该组则 ×2)
static func rent_for(idx: int, tiles: Array) -> int:
	var d: Dictionary = TILES[idx]
	if d.type != "property":
		return 0
	var t: Dictionary = tiles[idx]
	if t.get("owner", -1) == -1:
		return 0
	var rent: int = d.rent * (1 + int(t.get("level", 0)))
	if _group_complete(idx, tiles):
		rent *= 2
	return rent

static func _group_complete(idx: int, tiles: Array) -> bool:
	var group: String = TILES[idx].group
	for i in TILES.size():
		if TILES[i].get("group", "") == group and tiles[i].get("owner", -1) != tiles[idx].get("owner", -2):
			return false
	return true

## 千分位金额显示
static func fmt_money(v: int) -> String:
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + "¥" + s + out
