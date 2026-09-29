class_name GameData
## 棋盘、事件卡与规则数值。
## 棋盘为 56 格环形（18×12 外圈，四角各一格），由 _build_tiles 确定性生成：
## 10 组各 3 块地产沿外圈排布，机会/命运/缴费/兼职/休息穿插其间。

const MAX_PLAYERS := 4
const START_MONEY := 20000
const SALARY := 4500
const MAX_LEVEL := 3          # 装修等级上限
static var MAX_ROUNDS := 30   # 回合上限（static 便于自动化测试覆盖）
const JAIL_TILE := 17         # 宿委会（左下角）
## 「无主」哨兵值。不能用 -1：机器人 peer id 会从 -1 开始编号，会撞车。
const NO_OWNER := -100
const PROMPT_TIMEOUT := 25.0  # 购买/升级等待秒数
const ROLL_TIMEOUT := 35.0    # 玩家发呆代掷秒数

const BOARD_COLS := 18
const BOARD_ROWS := 12

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
	"dorm": "宿舍楼",
	"fun": "娱乐",
	"night": "夜宵",
	"health": "健康",
}

const GROUP_COLORS := {
	"daily": Color(0.878, 0.482, 0.224),
	"service": Color(0.290, 0.624, 0.910),
	"canteen": Color(0.851, 0.325, 0.310),
	"study": Color(0.314, 0.631, 0.310),
	"sport": Color(0.910, 0.773, 0.227),
	"teach": Color(0.608, 0.349, 0.714),
	"dorm": Color(0.161, 0.678, 0.624),
	"fun": Color(0.859, 0.388, 0.624),
	"night": Color(0.400, 0.459, 0.863),
	"health": Color(0.925, 0.514, 0.529),
}

## 每组地价 / 基础租金（约 30%），沿路径由便宜到贵
const GROUP_PRICES := {
	"daily": 1600, "service": 1900, "canteen": 2200, "study": 2600, "sport": 3000,
	"teach": 3400, "dorm": 3800, "fun": 4200, "night": 4700, "health": 5200,
}
const GROUP_RENTS := {
	"daily": 500, "service": 600, "canteen": 700, "study": 800, "sport": 900,
	"teach": 1000, "dorm": 1150, "fun": 1300, "night": 1400, "health": 1600,
}

const GROUP_TILES := {
	"daily": ["小卖部", "奶茶店", "水果摊", "面包房", "文具店", "便利店"],
	"service": ["快递驿站", "公共澡堂", "打印店", "理发店", "洗衣房", "修车铺"],
	"canteen": ["食堂一楼", "食堂二楼", "咖啡屋", "兰州拉面", "烧烤摊", "火锅店"],
	"study": ["图书馆", "自习室", "电子机房", "通宵教室", "朗读亭", "考研教室"],
	"sport": ["大操场", "篮球场", "体育馆", "游泳池", "网球场", "健身房"],
	"teach": ["教学楼A", "教学楼B", "实验楼", "报告厅", "美术画室", "琴房"],
	"dorm": ["一号楼", "二号楼", "三号楼", "四号楼", "五号楼", "六号楼"],
	"fun": ["桌游吧", "网吧", "KTV", "台球厅", "电竞馆", "剧本杀"],
	"night": ["夜宵摊", "炸鸡店", "麻辣烫", "关东煮", "煎饼摊", "烤冷面"],
	"health": ["校医院", "心理咨询", "牙科室", "校药店", "体检中心", "理疗室"],
}

## 强制缴费格（按铺设顺序取用）
const FINES := [
	["看病挂号", 500], ["缴电费", 800], ["挂科重修", 1000], ["修车摊", 600],
	["丢校园卡", 400], ["社团费", 1200], ["宽带到期", 700], ["打印超支", 900],
	["补考费", 1500], ["班费摊派", 600],
]

## 兼职/奖励格（按铺设顺序取用）
const BONUSES := [
	["勤工俭学", 600], ["旧书转让", 500], ["问卷之星", 400], ["比赛得奖", 1000],
	["摆摊成功", 800], ["退水费", 400], ["竞赛奖金", 1200], ["帮搬教材", 500],
	["直播爆火", 1500], ["宿舍评比奖", 900], ["二手出清", 600], ["奖学金", 2000],
]

const TILE_DESC := {
	"start": "踏上即可领取工资",
	"jail": "被查寝的同学在这里反省",
	"go_jail": "立刻被送往宿委会反省一回合",
	"rest": "放松一下，无事发生",
	"event": "抽取一张宿舍事件卡",
	"fine": "强制缴费，躲不掉",
	"bonus": "天降横财，直接入账",
	"property": "可购买 / 升级 / 收租金",
}

## 事件卡：t=文本；money=收支；from_each=每位其他室友给你；to_each=你给每位室友；
## move_steps=前进/后退若干格（途中踩到起点照常领工资）；go_jail=直接送宿委会。
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
	{"t": "抢到共享单车一路绿灯，前进 6 格", "move_steps": 6},
	{"t": "外卖小哥顺路捎你一程，前进 9 格", "move_steps": 9},
	{"t": "公交卡突然消磁，只好往后退 3 格", "move_steps": -3},
	{"t": "被突击查寝！直接前往宿委会", "go_jail": true},
	{"t": "今天你过生日！每位室友发来红包 +300", "from_each": 300},
	{"t": "你请全宿舍喝奶茶，每位室友 -300", "to_each": 300},
	{"t": "期末划重点全宿舍押题成功，每位室友凑份子 +500", "from_each": 500},
	{"t": "体育课体测满分，奖励 +600", "money": 600},
	{"t": "社团聚餐 AA 制，你先垫付 -450", "money": -450},
	{"t": "二手教材出给学弟学妹，回血 +450", "money": 450},
	{"t": "网购退货退款到账 +260", "money": 260},
	{"t": "被拉去当运动会裁判，补贴 +380", "money": 380},
	{"t": "游戏皮肤大促，没忍住 -500", "money": -500},
	{"t": "帮室友带饭一周，饭钱赚回来了 +700", "money": 700},
]

## 四角格位置：0 起点(右下) / 34 宿委会(左下) / 56 卧谈会(左上) / 90 查寝(右上)
static func corner_indices() -> Array:
	var c1 := BOARD_COLS - 1
	var side := c1 + (BOARD_ROWS - 2)
	return [0, c1, side + 1, side + 1 + c1]

## ---------- 棋盘几何（纯函数，渲染与单测共用） ----------

## 路径序号 -> 格坐标（0 起点=右下角，沿底边向左）
static func grid_of(i: int) -> Vector2i:
	var W := BOARD_COLS
	var H := BOARD_ROWS
	var c1 := W - 1                 # 底边终点（左下角）
	var c2 := c1 + (H - 2)          # 左边终点（左上角下邻）
	if i <= c1:
		return Vector2i(c1 - i, H - 1)
	if i <= c2:
		return Vector2i(0, H - 1 - (i - c1))
	if i <= c2 + W - 1:
		return Vector2i(i - (c2 + 1), 0)
	return Vector2i(W - 1, i - (c2 + W))

## 格坐标 -> 路径序号（不在外圈返回 -1）
static func index_at_grid(col: int, row: int) -> int:
	var W := BOARD_COLS
	var H := BOARD_ROWS
	var c1 := W - 1
	var c2 := c1 + (H - 2)
	if row == H - 1 and col >= 0 and col <= c1:
		return c1 - col
	if col == 0 and row >= 1 and row <= H - 2:
		return c1 + (H - 1 - row)
	if row == 0 and col >= 0 and col <= W - 1:
		return c2 + 1 + col
	if col == W - 1 and row >= 1 and row <= H - 2:
		return c2 + W + row
	return -1

## 地产铺设：每边若干「3 连排」，两组 3 连拼成一组 6 块。
## 顺序为路径序：底边(6排)→左边(4排)→顶边(6排)→右边(4排)，共 20 排 = 10 组。
static var TILES: Array = _build_tiles()

static func _build_tiles() -> Array:
	var total := BOARD_COLS * 2 + BOARD_ROWS * 2 - 4  # 56
	var corners: Array = corner_indices()  # [0, 17, 28, 45]
	var t := []
	for i in total:
		t.append({})
	t[corners[0]] = {"type": "start", "name": "起点"}
	t[corners[1]] = {"type": "jail", "name": "宿委会"}
	t[corners[2]] = {"type": "rest", "name": "卧谈会"}
	t[corners[3]] = {"type": "go_jail", "name": "查寝！"}

	# 每组一排 3 连（10 组 = 10 排），沿路径由便宜到贵
	var runs := [
		1, 5, 9, 14,          # 底边
		18, 23,               # 左边
		29, 34, 40,           # 顶边
		50,                   # 右边
	]
	var order := ["daily", "service", "canteen", "study", "sport", "teach", "dorm", "fun", "night", "health"]
	for g in order.size():
		var gname: String = order[g]
		var names: Array = GROUP_TILES[gname]
		var base: int = runs[g]
		for j in 3:
			t[base + j] = {
				"type": "property", "name": names[j], "group": gname,
				"price": GROUP_PRICES[gname], "rent": GROUP_RENTS[gname],
			}

	# 剩余格按确定性序列填充：E=机会/命运 F=缴费 B=兼职 R=免费休息
	var xseq := _x_sequence()
	var xi := 0
	var fi := 0
	var bi := 0
	var ei := 0
	for i in total:
		if not t[i].is_empty():
			continue
		match xseq[xi]:
			"E":
				t[i] = {"type": "event", "name": "命运" if ei % 2 == 1 else "机会"}
				ei += 1
			"F":
				var f: Array = FINES[fi % FINES.size()]
				t[i] = {"type": "fine", "name": f[0], "amount": f[1]}
				fi += 1
			"B":
				var b: Array = BONUSES[bi % BONUSES.size()]
				t[i] = {"type": "bonus", "name": b[0], "amount": b[1]}
				bi += 1
			_:
				t[i] = {"type": "rest", "name": "空教室"}
		xi += 1
	if xi != 22:
		push_error("棋盘铺设错误：剩余格 %d != 22" % xi)
	return t

static func _x_sequence() -> Array:
	var a := ["E", "B", "F", "E", "R", "B"]
	var b := ["E", "B", "F", "E", "R", "B"]
	var c := ["E", "B", "R", "E", "F", "B", "E", "R", "F", "E"]
	return a + b + c  # E8 / B6 / F4 / R4，共 22

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

## 前进/后退 N 格的逐步路径（事件卡用，负数倒走）
static func compute_path_steps(start: int, steps: int) -> Array:
	var path := []
	var cur := start
	for i in absi(steps):
		cur = (cur + signi(steps) + TILES.size()) % TILES.size()
		path.append(cur)
	return path

## 当前租金 = 基础租金 × (1+装修等级) × (垄断该组则 ×2)
static func rent_for(idx: int, tiles: Array) -> int:
	var d: Dictionary = TILES[idx]
	if d.type != "property":
		return 0
	var t: Dictionary = tiles[idx]
	if t.get("owner", NO_OWNER) == NO_OWNER:
		return 0
	var rent: int = d.rent * (1 + int(t.get("level", 0)))
	if _group_complete(idx, tiles):
		rent *= 2
	return rent

static func _group_complete(idx: int, tiles: Array) -> bool:
	var group: String = TILES[idx].group
	for i in TILES.size():
		if TILES[i].get("group", "") == group and tiles[i].get("owner", NO_OWNER - 1) != tiles[idx].get("owner", NO_OWNER):
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
