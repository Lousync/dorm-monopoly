class_name GameData
## 棋盘、事件卡与规则数值。
## 棋盘为 56 格环形（18×12 外圈，四角各一格），由 _build_tiles 确定性生成：
## 10 组各 3 块地产沿外圈排布，机会/小卖部/失物招领/特浓咖啡/赌场/休息穿插其间。

const MAX_PLAYERS := 4
const START_MONEY := 20000
const SALARY := 4500
## 破产变卖保底的回收比例：**回收 = 地皮价值（含房屋）× 本比例**，
## 其中地皮价值 = 地价 + 等级 × 升级费（= 该地累计投入，与 `_net_worth` 同一口径）。
## 2026-10-09 用户拍板 30% → **50%**。
## **唯一来源**：`game.gd` 的结算与变卖面板、大厅「游戏设置」弹窗的文案都读它 ——
## 弹窗按 `int(LIQ_RATE * 100)` 显示百分数，别在任何文案里写死（同 TRUST_FUND 那条教训）。
const LIQ_RATE := 0.50
## 绿货「信托基金」每回合开始进账（回合开始结算里发，见 道具图鉴.md）。
## **唯一来源**：game.gd 发钱与 rules_text 面板文案都读它——曾各写各的，面板一度显示成 +100。
const TRUST_FUND := 200
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
	"jail": "被查寝的同学在这里反省（跳过一回合）",
	"go_jail": "立刻被送往宿委会反省一回合（跳过一回合）",
	"rest": "放松一下，无事发生",
	"event": "抽取一张机会卡（机会 / 道具 / 畸变）",
	"item": "翻一翻失物招领箱，捡到一件随机道具",
	"again": "灌一口特浓咖啡，本回合再行动一次",
	"casino": "全员下注玩小游戏，赢家通吃",
	"property": "可购买 / 升级 / 收租金",
	"shop": "三栏货架 · 每家独立补货 · 落地即可逛",
}

## 机会格抽卡的类别概率（2026-10-09 定稿；**写死、不进开局设置**）。
## 畸变总开关为「关」时第三档作废、并入机会卡（实际 90/10/0）。
const CHANCE_P := 0.85
const CHANCE_ITEM_P := 0.10
const CHANCE_AB_P := 0.05

## 事件卡（= 机会卡池，50 张，2026-10-09 批 3 定稿；字段全表见 `doc/game-design/机会卡.md` §二）。
##   t=卡面文本；money=收支；from_each=每位其他室友给你；to_each=你给每位室友；
##   move_steps=前进/后退若干格（途中踩到起点照常领工资）；go_jail=直接送宿委会；
##   gain_item / gain_item_quality=发一件道具；enter_shop / enter_blackshop=进店；
##   以及批 2 的 15 个智斗字段（目标类 / 地皮与位置类 / 抉择与情报类）。
## 结算顺序**不按本表的书写顺序**，按 `game.gd._apply_card` 里那条（= 机会卡.md §三）——
## 但同类内仍照书写顺序排，方便逐行对着设计稿核。
## 分四段（设计稿 §四）：A 指定目标 14 / B 地皮与位置 12 / C 抉择与情报 12 / D 节奏通用 12。
const EVENTS := [
	# ---- A 指定目标（14）：先点名一个玩家，再对他下手 ----
	{"t": "顺走外卖——你顺手拎走了他的外卖，他到现在还在问是谁拿的。", "steal_from": 400},
	{"t": "借笔记不还——借了他的笔记，还的时候夹了张纸条：知识无价。", "steal_from": 800},
	{"t": "蹭网费——连了他一学期的热点，网费总得给点。", "steal_from": 250},
	{"t": "讨债——上学期借你的钱，今天连本带利。", "steal_from": 1000},
	{"t": "快递代取费——你帮他跑了三趟快递站，跑腿费结一下。", "charge_to": 600},
	{"t": "代点名——他翘课你替他答了到，这份人情得折现。", "charge_to": 350},
	{"t": "团建收份子——宿舍团建你先垫的钱，现在挨个收回来。", "charge_to": 500},
	{"t": "收保护费——宿舍楼下归你管，路过都得交点。", "charge_to": 800},
	{"t": "举报夜不归宿——你把他的作息表递给了宿管阿姨。", "jail_to": true},
	{"t": "大功率电器——他宿舍藏了个电磁炉，你顺手举报了。", "jail_to": true},
	{"t": "让他请全宿舍——他今天生日，得请全宿舍喝奶茶。", "each_from_target": 300},
	{"t": "孤立他——宿舍会议一致通过：他负责这周的公共开销。", "each_from_target": 200},
	{"t": "抢他的快递柜——你摸走了他的取件码。", "steal_item_from": true},
	{"t": "借他的充电宝——充电宝在他桌上放了三天，那就是你的了。", "steal_item_from": true},
	# ---- B 地皮与位置（12）：地皮掠夺 / 位置挪动 ----
	{"t": "霸占床位——你俩换了个床位，顺便换了位置。", "swap_pos": true},
	{"t": "占他的座——自习室的座位，谁先坐下算谁的。", "swap_pos": true},
	{"t": "把他拽回宿舍——你一把把他从自习室拽回了宿舍楼。", "pull_target": true},
	{"t": "拉他一起自习——「走走走，陪我回宿舍拿个东西。」", "pull_target": true},
	{"t": "替他请病假——你替他请了三天病假，他只能往回走。", "push_back": 3},
	{"t": "你替他值日——他欠你一次值日，今天先还两格。", "push_back": 2},
	{"t": "甩他在原地——你骑车走了，他还在原地找共享单车。", "push_back": 5},
	{"t": "没收他的房产——宿管查到他违规用电，房本先没收了。", "seize_tile": "take"},
	{"t": "换宿舍楼——你俩商量着换了块地，谁也没吃亏。", "seize_tile": "swap"},
	{"t": "抽签换座——全班重新抽签，位置全打乱了。", "shuffle_pos": true},
	{"t": "半价强买——趁他急用钱，半价把他的地收了。", "force_buy_tile": 50},
	{"t": "三折抄底——他手里那块冷清的地，三折卖你了。", "force_buy_tile": 30},
	# ---- C 抉择与情报（12）：8 张自己挑分支（可能连着要点一次目标）+ 4 张牌堆情报 ----
	{"t": "翘课去兼职——去兼职，还是去上课？", "choices": [
		{"t": "去兼职：+¥1200", "money": 1200},
		{"t": "去上课：前进 4 格", "move_steps": 4}]},
	{"t": "帮室友带饭——收钱，还是白请？", "choices": [
		{"t": "收饭钱：+¥400", "money": 400},
		{"t": "白请：获得一件绿色道具", "gain_item_quality": "绿"}]},
	{"t": "二手出闲置——卖了换钱，还是留着用？", "choices": [
		{"t": "卖掉：+¥600", "money": 600},
		{"t": "留着：获得一件蓝色道具", "gain_item_quality": "蓝"}]},
	{"t": "学生会竞选——拉票，还是弃权？", "choices": [
		{"t": "拉票：每位室友给你 ¥150", "from_each": 150},
		{"t": "弃权：前进 6 格", "move_steps": 6}]},
	{"t": "抢红包——自己留着，还是发到群里？", "choices": [
		{"t": "自己留着：+¥900", "money": 900},
		{"t": "发到群里：每位室友给你 ¥250", "from_each": 250}]},
	{"t": "熬夜赶论文——通宵写完，还是睡大觉？", "choices": [
		{"t": "通宵写完：前进 7 格", "move_steps": 7},
		{"t": "睡大觉：获得一件绿色道具", "gain_item_quality": "绿"}]},
	{"t": "告密还是包庇——宿管在问那天晚上谁没回宿舍。", "choices": [
		{"t": "告密：送他去宿委会", "jail_to": true},
		{"t": "包庇：他给你 ¥600", "steal_from": 600}]},
	{"t": "拉他入伙——叫上他一起，还是自己走？", "choices": [
		{"t": "拉他一起：与他交换位置", "swap_pos": true},
		{"t": "自己走：前进 5 格", "move_steps": 5}]},
	{"t": "小道消息——你听说牌堆下一张是什么。", "peek_deck": 1},
	{"t": "内部消息——你摸到了机会牌堆的一角。", "peek_deck": 3},
	{"t": "重洗牌局——你把牌堆整个重新洗了一遍。", "shuffle_deck": true},
	{"t": "压箱底——你把最上面那张抽出来，塞到了最底下。", "bury_deck": true},
	# ---- D 节奏与通用（12）：纯收支 / 位移 / 送监 / 黑市入口 ----
	{"t": "帮宿管搬水——搬了一下午矿泉水，辛苦费 +600。", "money": 600},
	{"t": "期末奖学金——到账 +2000。", "money": 2000},
	{"t": "刮刮乐中奖——水果摊刮出大奖 +1500。", "money": 1500},
	{"t": "电费欠缴——限时用电，补缴 -800。", "money": -800},
	{"t": "电脑蓝屏——送去维修 -700。", "money": -700},
	{"t": "生日红包——每位室友发来红包 +300。", "from_each": 300},
	{"t": "请全宿舍喝奶茶——每位室友 -300。", "to_each": 300},
	{"t": "共享单车快进——一路绿灯，前进 6 格。", "move_steps": 6},
	{"t": "外卖小哥捎一程——前进 9 格。", "move_steps": 9},
	{"t": "公交卡消磁——只好往后退 3 格。", "move_steps": -3},
	{"t": "突击查寝——直接前往宿委会。", "go_jail": true},
	{"t": "神秘短信——「后门等你——黑市开张」。", "enter_blackshop": true},
]

## 全部事件卡（黑市 / 小卖部开关造成的过滤在 `game._new_event_deck` 里做）。
## 2026-10-09：`only` 机制随「命运」一起退场，这里不再按格型筛。
static func events_for() -> Array:
	return EVENTS.duplicate()

## 抽卡演出的**卡型**（决定卡面配色）：good / bad / move / jail / info 五类（机会卡.md §三）。
## 判定按字段优先级，顺序有意义（一张卡可能同时有 money 与 move_steps，先命中的说话）。
## 2026-10-09 从 `game.gd._card_kind()` 挪来：图鉴生成器（`--script` 跑）要复用它，
## 而它读不到 `game.gd` —— 抄一份就是**会烂的第二来源**（卡型配色会跟演出悄悄不一致）。
static func card_kind(card: Dictionary) -> String:
	# 2026-10-09 批 2（T9~T13）的 15 个新字段：送监单列 jail、位移归 move、抉择与情报归
	# info、目标类与地皮类归 good（都是对**抽卡者**有利的那一侧；中性的 `seize_tile:"swap"`
	# 不在此列、归 move，见下面那两行）。整块插在 `go_jail` 之前
	# ——它们按 机会卡.md §三 的结算次序本来就排在 go_jail 之后，但配色取更重的那一类。
	# `jail_to`（送**别人**去宿委会）又排在最前、先于 `go_jail`（自己进去）：今天还没有同时
	# 带两者的卡，但这是契约，别把顺序调换。
	if card.has("jail_to"):
		return "jail"
	if card.has("choices") or card.has("peek_deck") or card.has("shuffle_deck") or card.has("bury_deck"):
		return "info"
	if card.has("steal_from") or card.has("charge_to") or card.has("each_from_target") \
			or card.has("steal_item_from") or card.has("force_buy_tile") \
			or card.get("seize_tile", "") == "take":
		return "good"
	# `seize_tile:"swap"` **要与 `seize_tile:"take"` 分开判**（2026-10-09 T15 修）：
	# 互换是**中性**（一 debuff 一 buff 相抵，香皂也无效 —— 见 `机会卡.md` §四），
	# 拿它跟"没收他的房产"同色（💰收益）是玩家可见的错话。归 `move`，与同族的 `swap_pos` 同色。
	if card.has("swap_pos") or card.has("pull_target") or card.has("push_back") \
			or card.has("shuffle_pos") or card.has("seize_tile"):
		return "move"
	if card.has("go_jail"):
		return "jail"
	if card.has("move_steps"):
		return "move"
	if card.has("money"):
		return "good" if int(card.money) >= 0 else "bad"
	if card.has("from_each") or card.has("gain_item") or card.has("gain_item_quality"):
		return "good"
	if card.has("to_each"):
		return "bad"
	if card.has("enter_blackshop"):
		return "bad"
	return "info"

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
	# E=机会 S=小卖部 I=失物招领(随机道具) A=特浓咖啡(再动一次) C=赌场 R=免费休息
	var xseq := _x_sequence()
	var xi := 0
	for i in total:
		if not t[i].is_empty():
			continue
		match xseq[xi]:
			"E":
				t[i] = {"type": "event", "name": "机会"}
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
## 合计 S6（小卖部）/ E4（机会）/ I4（失物招领）/ A2（特浓咖啡）/ C2（赌场）/ R4（空教室）。
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
