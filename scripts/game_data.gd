class_name GameData
## 棋盘、事件卡与规则数值。
## 棋盘为 56 格环形（18×12 外圈，四角各一格），由 _build_tiles 确定性生成：
## 10 组各 3 块地产沿外圈排布，机会/命运/小卖部/失物招领/特浓咖啡/赌场/休息穿插其间。

const MAX_PLAYERS := 4
const START_MONEY := 20000
const SALARY := 4500
const MAX_LEVEL := 4          # 装修等级上限
## 装修等级配色：1 绿 / 2 蓝 / 3 紫 / 4 金。
## 棋盘上的房子图标与格详情卡的文案共用这一份，避免两处各写一套。
const LEVEL_COLORS := [
	Color(0, 0, 0, 0),        # 0：无房子
	Color(0.42, 0.80, 0.45),  # 1 绿
	Color(0.36, 0.63, 0.94),  # 2 蓝
	Color(0.68, 0.48, 0.92),  # 3 紫
	Color(0.98, 0.80, 0.32),  # 4 金
]
const LEVEL_NAMES := ["未装修", "绿", "蓝", "紫", "金"]
static var MAX_ROUNDS := 30   # 回合上限（static 便于自动化测试覆盖）
const JAIL_TILE := 17         # 宿委会（左下角）
## 「没有这个人 / 没命中」的哨兵值。**同样不能用 -1**：
## 机器人 peer id 从 -1 起编号，拿 -1 当「空」会和「1 号机器人」撞车。
const NO_PEER := -9999

## 「无主」哨兵值。不能用 -1：机器人 peer id 会从 -1 开始编号，会撞车。
const NO_OWNER := -100
const PROMPT_TIMEOUT := 25.0  # 购买/升级等待秒数
const ROLL_TIMEOUT := 35.0    # 玩家发呆代掷秒数
## 赌场注码。放在这里（而不是 casino.gd）是为了让规则说明面板能引用它：
## casino.gd 直接用了 Fx autoload，数据类 preload 它会把 autoload 依赖拖进
## 编译链（--script 模式下 autoload 尚未注册，整条链会编译失败）。
const CASINO_STAKE := 800

const BOARD_COLS := 18
const BOARD_ROWS := 12

## 玩家色板，顺序与 Kenney 棋子贴图一一对应（assets/pieces/piece*_05.png）。
## **取的是贴图的真实主色**：以前这里是另一套色值，于是「格子的归属色条 / 棋子的色片」和
## 「棋盘上的棋子」颜色对不上，玩家认不出某块地是谁的。
## 现在的消费方（**不穷举**，新增消费方请一并核对语义）：棋盘上的**归属色条**、**棋子**、
## 四角身家条的**色片**（`ui_kit.chip`）、**大厅玩家行**的色片（`lobby.gd`）、**道具试验场**的
## 玩家色片（`item_lab.gd`）、战报行的色片（`game.gd`）、飘字/彩带的调色板（`fx.gd`）与 `ui_kit`
## 的色→棋子贴图反查。
##（名册色块 / 座位卡色块 / 3D 立牌底色这几个消费方已随批次 5、批次 9 退场，别再照着旧清单找。）
## 注意 slot0 的贴图虽然文件名叫 Red，实际主色是**橙**（Kenney 的命名）。
const PLAYER_COLORS := [
	Color(0.910, 0.416, 0.090),  # pieceRed_05    #E86A17
	Color(0.118, 0.655, 0.882),  # pieceBlue_05   #1EA7E1
	Color(0.451, 0.804, 0.294),  # pieceGreen_05  #73CD4B
	Color(1.000, 0.800, 0.000),  # pieceYellow_05 #FFCC00
]

## 地产沿路径由便宜到贵：价格线性递增，租金 = 价格 × 比例。
## 原先的「10 组 × 3 块 + 集齐同组租金翻倍」已废除 —— 30 块地彼此独立。
const PROP_BASE_PRICE := 1500    # 第 1 块地的价格
const PROP_PRICE_STEP := 130     # 沿路径每块递增
const PROP_RENT_RATIO := 0.34    # 租金 / 地价（原 30.5%；拆掉翻倍后上调补回一部分）

## 30 块地的名字，按路径顺序（底边 → 左边 → 顶边 → 右边）。
const PROPERTY_NAMES := [
	"小卖部", "奶茶店", "水果摊",
	"快递驿站", "公共澡堂", "打印店",
	"食堂一楼", "食堂二楼", "咖啡屋",
	"图书馆", "自习室", "电子机房",
	"大操场", "篮球场", "体育馆",
	"教学楼A", "教学楼B", "实验楼",
	"一号楼", "二号楼", "三号楼",
	"桌游吧", "网吧", "KTV",
	"夜宵摊", "炸鸡店", "麻辣烫",
	"校医院", "心理咨询", "牙科室",
]

## 每块地的水印图标：沿用原先按「地段风格」给的 10 枚，每 3 块共用一枚。
## 只影响观感，不参与任何计费。
const PROPERTY_ICONS := [
	"daily", "service", "canteen", "study", "sport",
	"teach", "dorm", "fun", "night", "health",
]

## 价位沿路径的分配顺序：把 30 个价位**打乱后固定**下来 ——
## 同一套盘面每局一致（大富翁类的盘面要能背），但不再是「越往后越贵」。
## 第 k 块地取 prop_price(PROP_PRICE_ORDER[k])。
const PROP_PRICE_ORDER := [
	10, 8, 4, 25, 12, 27, 13, 21, 1, 23,
	0, 9, 3, 19, 20, 28, 29, 7, 17, 15,
	5, 18, 14, 22, 2, 11, 26, 6, 16, 24,
]

## 身家 = 现金 + Σ(地价 + 等级 × 升级费)。**收敛到这一处**，
## 免得房主结算、HUD 名册、棋盘悬停提示各写一遍同样的公式。
static func net_worth_of(peer: int, money: int, tiles: Array) -> int:
	var w := money
	for i in mini(tiles.size(), TILES.size()):
		var t: Dictionary = tiles[i]
		if int(t.get("owner", NO_OWNER)) != peer:
			continue
		w += int(TILES[i].price) + int(t.get("level", 0)) * upgrade_cost(i)
	return w

## 第 k 块地（k = 0..29，按路径序）的价格与租金
static func prop_price(k: int) -> int:
	return PROP_BASE_PRICE + PROP_PRICE_STEP * k

static func prop_rent(k: int) -> int:
	return int(roundf(float(prop_price(k)) * PROP_RENT_RATIO / 10.0)) * 10

const TILE_DESC := {
	"start": "踏上即可领取工资",
	"jail": "被查寝的同学在这里反省",
	"go_jail": "立刻被送往宿委会反省一回合",
	"rest": "放松一下，无事发生",
	"event": "抽取一张宿舍事件卡",
	"item": "翻一翻失物招领箱，捡到一件随机道具",
	"again": "灌一口特浓咖啡，本回合再行动一次",
	"casino": "全员下注玩小游戏，赢家通吃",
	"property": "可购买 / 升级 / 收租金",
	"shop": "三栏货架 · 每家独立补货 · 落地即可逛",
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
	# ---- 机会卡专属事件（only 标记：只在「机会」格出现；命运格不发） ----
	{"t": "路过小卖部，被老板拉进店里逛逛", "enter_shop": true, "only": "机会"},
	{"t": "在公告栏后面捡到一张道具券", "gain_item_quality": "蓝", "only": "机会"},
	{"t": "收到一条神秘短信：后门等你——黑市开张", "enter_blackshop": true, "only": "机会"},
]

## 按格子类型取事件卡池：无 only 的通用卡 + only 命中当前格类型的专属卡（§8）
static func events_for(kind: String) -> Array:
	var out := []
	for e in EVENTS:
		if not e.has("only") or String(e.only) == kind:
			out.append(e)
	return out

## 四角格位置：0 起点(右下) / 34 宿委会(左下) / 56 卧谈会(左上) / 90 查寝(右上)
## 该格子是不是四个角上的**地标格**（起点 / 宿委会 / 卧谈会 / 查寝）。
## 注意不能按格型判：`rest` 是「免费休息」，四角上的卧谈会和沿途 4 个空教室共用这个格型，
## 按格型判会把空教室也当成角格（会套上角格的金棕底与金色字）。
static func is_corner(idx: int) -> bool:
	return corner_indices().has(idx)

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

	# 30 块地产沿路径铺：每 3 块一排（共 10 排），名字 / 地价 / 租金逐块给
	var runs := [
		1, 5, 9, 14,          # 底边
		18, 23,               # 左边
		29, 34, 40,           # 顶边
		50,                   # 右边
	]
	for k in PROPERTY_NAMES.size():
		var rank: int = PROP_PRICE_ORDER[k]     # 价位按固定乱序分配，不再沿路径递增
		t[runs[int(k / 3)] + (k % 3)] = {
			"type": "property", "name": PROPERTY_NAMES[k],
			"icon": PROPERTY_ICONS[int(k / 3)],
			"price": prop_price(rank), "rent": prop_rent(rank),
		}

	# 剩余格按确定性序列填充：
	# E=机会/命运 S=小卖部 I=失物招领(随机道具) A=特浓咖啡(再动一次) C=赌场 R=免费休息
	var xseq := _x_sequence()
	var xi := 0
	var ei := 0
	for i in total:
		if not t[i].is_empty():
			continue
		match xseq[xi]:
			"E":
				t[i] = {"type": "event", "name": "命运" if ei % 2 == 1 else "机会"}
				ei += 1
			"S":
				t[i] = {"type": "shop", "name": "小卖部"}
			"I":
				t[i] = {"type": "item", "name": "失物招领"}
			"A":
				t[i] = {"type": "again", "name": "特浓咖啡"}
			"C":
				t[i] = {"type": "casino", "name": "宿舍赌场"}
			_:
				t[i] = {"type": "rest", "name": "空教室"}
		xi += 1
	if xi != 22:
		push_error("棋盘铺设错误：剩余格 %d != 22" % xi)
	return t

## 功能格铺设序列（按剩余空位的路径序填充，分组只为好读）：
## 底边+左边前段 / 左边后段+顶边 / 右边 —— 同侧同类格不相邻。
## 合计 S6（小卖部）/ E4（机会命运）/ I4（失物招领）/ A2（特浓咖啡）/ C2（赌场）/ R4（空教室）。
static func _x_sequence() -> Array:
	var a := ["S", "I", "A", "C", "R", "S", "E", "S"]
	var b := ["S", "R", "C", "E", "I", "E", "R"]
	var c := ["S", "I", "E", "R", "I", "A", "S"]
	return a + b + c

## 装修升级费用（每级）
static func upgrade_cost(idx: int) -> int:
	return int(TILES[idx].price * 0.5)

## 装修等级 → 配色（越界一律钳到 0..MAX_LEVEL）
static func level_color(l: int) -> Color:
	return LEVEL_COLORS[clampi(l, 0, MAX_LEVEL)]

## 装修等级 → 颜色名（用于格详情卡文案）
static func level_name(l: int) -> String:
	return LEVEL_NAMES[clampi(l, 0, MAX_LEVEL)]

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

## 当前租金 = 基础租金 × (1 + 装修等级)。每块地独立，没有组与翻倍。
static func rent_for(idx: int, tiles: Array) -> int:
	var d: Dictionary = TILES[idx]
	if d.type != "property":
		return 0
	var t: Dictionary = tiles[idx]
	if t.get("owner", NO_OWNER) == NO_OWNER:
		return 0
	return int(d.rent) * (1 + int(t.get("level", 0)))


## 千分位金额显示
static func fmt_money(v: int) -> String:
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + "¥" + s + out
