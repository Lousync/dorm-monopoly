class_name ItemData
## 道具系统数据总表（唯一台账：doc/game-design/道具系统.md · 逐件见 doc/game-design/道具图鉴.md）
## implemented=false 的道具不进货架池，效果随批次解锁

const QUALITIES := ["白", "绿", "蓝", "紫", "橙"]
const QUALITY_NAMES := {"白": "普通", "绿": "稀有", "蓝": "超稀有", "紫": "史诗", "橙": "传说"}  # 显示名（内部键仍为颜色字）
const QUALITY_COLORS := {
	"白": Color(0.93, 0.93, 0.93), "绿": Color(0.42, 0.78, 0.55),
	"蓝": Color(0.36, 0.6, 0.92), "紫": Color(0.66, 0.47, 0.92),
	"橙": Color(0.96, 0.62, 0.25),
}
const SHOP_WEIGHTS := {"白": 40, "绿": 30, "蓝": 20, "紫": 5, "橙": 5}  # 橙 5% 定稿，其余待数值专场
const FIND_WEIGHTS := {"白": 45, "绿": 30, "蓝": 18, "紫": 5, "橙": 2}  # 失物招领格：白捡的，要比小卖部略涩
const QUALITY_PRICES := {"白": 600, "绿": 1000, "蓝": 1800, "紫": 3000, "橙": 4500}  # 待数值专场
const REFRESH_BASE := 500   # 小卖部刷新价起点：全局递增、整局不重置（待数值专场）
const REFRESH_STEP := 300
const SHOP_TIMEOUT := 20.0  # 逛店发呆兜底
const SOIL_DONATE := 400    # 落地焦土自动捐款（待数值专场）；恢复目标 = 地价 × 1.0
const ITEM_TIMEOUT := 12.0  # 道具阶段发呆兜底

# ---------------- 黑市（§8：仅由机会卡进入，一切消费用地产） ----------------
const BLACK_WEIGHTS := {"紫": 70, "橙": 30}   # 货架品质权重（紫/橙起步）
const BLACK_COST := {"紫": 1, "橙": 2}        # 每件货的地皮价
const BLACK_REFRESH_COST := 1                  # 刷新固定 1 块地皮（不涨价）
const BLACK_EXIT_COST := 1                     # 出口费 1 块地皮
const BLACK_TIMEOUT := 20.0                    # 逛黑市发呆兜底

## target: "player" = 需选玩家；"tile" = 需点地图选格；"own_tile" = 需点自己名下的一块地皮（顶楼加盖）；缺省 = 自身/全体。
## then: "own_prop" = 选完玩家后再点他名下的一块地皮（两段式，如强拆令/抄家队）。
const ITEMS := {
	# ---- 首批（已实装）----
	"平均主义": {"quality": "紫", "cost": 5, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "所有玩家的现金同步至平均值。", "implemented": true, "icon": "item_balance"},
	"作弊器": {"quality": "紫", "cost": 3, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "下一次转盘的点数由你决定。", "implemented": true, "icon": "item_dice"},
	"交换生": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "与一名指定玩家随机交换一件道具。", "implemented": true, "target": "player", "icon": "item_exchange"},
	"招财猫": {"quality": "白", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "你的每块地皮租金收入 +400。", "implemented": true, "icon": "item_cat"},
	"信托基金": {"quality": "绿", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "你的回合开始时，获得 ¥200。", "implemented": true, "icon": "item_fund"},
	"黑卡": {"quality": "橙", "cost": 4, "type": "active", "unique": true, "cooldown": 4,
		"desc": "接下来 3 次购买免费。", "implemented": true, "icon": "item_blackcard"},
	"空想者的香皂": {"quality": "橙", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "免疫所有负面效果。10 回合后融化。", "implemented": true, "icon": "item_soap"},
	"蛋蛋节": {"quality": "橙", "cost": 1, "type": "consumable", "unique": true, "cooldown": 1,
		"desc": "每位玩家都会获得一份礼物，每局游戏仅限一次。", "implemented": true, "icon": "item_gift"},
	"亡牌飞行员coco": {"quality": "橙", "cost": 3, "type": "consumable", "unique": true, "cooldown": 3,
		"desc": "每位玩家都有一块随机地皮被摧毁，每局游戏仅限一次。", "implemented": true, "icon": "item_pilot"},
	"园中叶": {"quality": "橙", "cost": 0, "type": "active", "unique": true, "cooldown": 0,
		"desc": "？？？", "implemented": false, "icon": "item_leaf"},

	# ---- 白·普通 ----
	"砍价高手": {"quality": "白", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "你购买地皮时少花 ¥300。", "implemented": true, "icon": "item_tag"},
	"兼职中介": {"quality": "白", "cost": 2, "type": "active", "unique": false, "cooldown": 2,
		"desc": "立刻获得 ¥800。", "implemented": true, "icon": "item_parttime"},
	"共享单车": {"quality": "白", "cost": 1, "type": "active", "unique": false, "cooldown": 1,
		"desc": "立刻前进 2 格。", "implemented": true, "icon": "item_bike"},
	"饭卡": {"quality": "白", "cost": 1, "type": "active", "unique": false, "cooldown": 1,
		"desc": "立刻获得 ¥300。", "implemented": true, "icon": "item_mealcard"},
	"跑腿券": {"quality": "白", "cost": 1, "type": "active", "unique": false, "cooldown": 2,
		"desc": "指定一名玩家给你 ¥200。", "implemented": true, "target": "player", "icon": "item_errand"},
	"小抄": {"quality": "白", "cost": 1, "type": "active", "unique": false, "cooldown": 2,
		"desc": "偷看命运牌堆的下一张卡。", "implemented": true, "icon": "item_peek"},
	"许愿池": {"quality": "白", "cost": 1, "type": "active", "unique": false, "cooldown": 2,
		"desc": "立刻随机获得 -¥400~+¥800。", "implemented": true, "icon": "item_fountain"},
	"外卖箱": {"quality": "白", "cost": 1, "type": "active", "unique": false, "cooldown": 2,
		"desc": "前进 1 格并获得 ¥200。", "implemented": true, "icon": "item_takeout"},
	"幸运数7": {"quality": "白", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "你掷出 7 时额外获得 ¥1400。", "implemented": true, "icon": "item_luck"},
	"校园卡": {"quality": "白", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "你每次经过起点时多领 ¥1000。", "implemented": true, "icon": "item_campus"},
	"校历": {"quality": "白", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "你的回合开始时，若体力已满，改为获得 ¥300。", "implemented": true, "icon": "item_cal"},
	"公交卡": {"quality": "白", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "你前进时额外多走 1 格。", "implemented": true, "icon": "item_bus"},

	# ---- 绿·稀有 ----
	"置物架": {"quality": "绿", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "你的道具背包增加 2 格。", "implemented": true, "icon": "item_shelf"},
	"护身符": {"quality": "绿", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "每局游戏你第一次被送进宿委会时免疫。", "implemented": true, "icon": "item_amulet"},
	"占座": {"quality": "绿", "cost": 1, "type": "active", "unique": false, "cooldown": 4,
		"desc": "立刻移动到离你最近的一块自有地皮。", "implemented": true, "icon": "item_seat"},
	"充电宝": {"quality": "绿", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "你的体力上限 +1。", "implemented": true, "icon": "item_powerbank"},
	"夜跑": {"quality": "绿", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "再转一次轮盘。", "implemented": true, "icon": "item_nightrun"},
	"团购拼单": {"quality": "绿", "cost": 2, "type": "active", "unique": false, "cooldown": 2,
		"desc": "你和一名玩家各获得 ¥400。", "implemented": true, "target": "player", "icon": "item_groupbuy"},
	"护腕": {"quality": "绿", "cost": 2, "type": "active", "unique": false, "cooldown": 3,
		"desc": "获得一层护盾，免疫下一次负面效果。", "implemented": true, "icon": "item_shield"},
	"助学贷款": {"quality": "绿", "cost": 1, "type": "active", "unique": false, "cooldown": 2,
		"desc": "立刻获得 ¥1500，之后 3 回合各还 ¥600。", "implemented": true, "icon": "item_loan"},
	"应急基金": {"quality": "绿", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "现金不足 ¥5000 时补足到 ¥5000，每局一次。", "implemented": true, "icon": "item_emergency"},
	"二手交易": {"quality": "绿", "cost": 1, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "弃掉本道具，获得 ¥2000。", "implemented": true, "icon": "item_recycle"},
	"喇叭": {"quality": "绿", "cost": 2, "type": "active", "unique": false, "cooldown": 2,
		"desc": "指定一名玩家下个道具消耗能量 +1。", "implemented": true, "target": "player", "icon": "item_horn"},
	"组队学习": {"quality": "绿", "cost": 2, "type": "active", "unique": false, "cooldown": 3,
		"desc": "你和一名玩家各前进 2 格。", "implemented": true, "target": "player", "icon": "item_team"},
	"二手群接龙": {"quality": "绿", "cost": 2, "type": "consumable", "unique": false, "cooldown": 3,
		"desc": "随机获得一件稀有道具，其消耗 -1，用后丢弃。", "implemented": true, "icon": "item_groupchat"},
	"校园卡充值": {"quality": "绿", "cost": 1, "type": "active", "unique": false, "cooldown": 1,
		"desc": "花 ¥500 恢复 3 点体力。", "implemented": true, "icon": "item_recharge"},

	# ---- 蓝·超稀有 ----
	"换座位": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "与一名指定玩家交换棋子位置。", "implemented": true, "target": "player", "icon": "item_seatswap"},
	"强制募捐": {"quality": "蓝", "cost": 4, "type": "active", "unique": false, "cooldown": 5,
		"desc": "其他所有玩家各给你 ¥500。", "implemented": true, "icon": "item_donate"},
	"雨伞": {"quality": "蓝", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "你不会被事件后退。", "implemented": true, "icon": "item_umbrella"},
	"交换课表": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "与一名指定玩家各随机交换一块地皮。", "implemented": true, "target": "player", "icon": "item_timetable"},
	"时光倒流": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "下一次转盘可以重掷一次，取更高点数。", "implemented": true, "icon": "item_rewind"},
	"抄家队": {"quality": "紫", "cost": 2, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "指定一名玩家的一块地皮降 1 级。", "implemented": true, "target": "player", "then": "own_prop", "icon": "item_raiders"},
	"拼车": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "立刻移动到一名指定玩家所在的格子。", "implemented": true, "target": "player", "icon": "item_carpool"},
	"保安队长": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "指定一名玩家随机一件道具冷却 +2。", "implemented": true, "target": "player", "icon": "item_chief"},
	"反作弊": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 5,
		"desc": "本回合其他所有玩家不能使用道具。", "implemented": true, "icon": "item_ban"},
	"错峰用电": {"quality": "蓝", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "你每回合第一件道具消耗 -1。", "implemented": true, "icon": "item_offpeak"},
	"保安巡逻": {"quality": "紫", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "你收取的租金提高 30%。", "implemented": true, "icon": "item_patrol"},
	"体测": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "指定一名玩家体力 -2。", "implemented": true, "target": "player", "icon": "item_fittest"},
	"换课": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "与一名指定玩家交换体力。", "implemented": true, "target": "player", "icon": "item_swap"},
	"点名": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "指定一名玩家下回合点数 +3。", "implemented": true, "target": "player", "icon": "item_rollcall"},

	# ---- 紫·史诗 ----
	"拆解钳": {"quality": "紫", "cost": 3, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "摧毁一名指定玩家的一件随机道具。", "implemented": true, "target": "player", "icon": "item_wrench"},
	"快递直达": {"quality": "紫", "cost": 4, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "立刻移动到地图上的任意一格。", "implemented": true, "target": "tile", "icon": "item_rocket"},
	"强拆令": {"quality": "紫", "cost": 5, "type": "consumable", "unique": false, "cooldown": 4,
		"desc": "指定一名玩家的一块地皮变为无主。", "implemented": true, "target": "player", "then": "own_prop", "icon": "item_demolish"},
	"时间暂停": {"quality": "紫", "cost": 4, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "指定一名玩家下一回合休眠。", "implemented": true, "target": "player", "icon": "item_pause"},
	"包场": {"quality": "紫", "cost": 4, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "指定一名玩家接下来两个回合不能使用道具。", "implemented": true, "target": "player", "icon": "item_bookout"},
	"重修卡": {"quality": "紫", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "每回合你可以使用两次道具，共三次。", "implemented": true, "icon": "item_retake"},

	# ---- 橙·传说 ----
	"二两寒暑": {"quality": "橙", "cost": 3, "type": "active", "unique": true, "cooldown": 3,
		"desc": "指定一名玩家接下来两个道具的消耗各 +2。", "implemented": true, "target": "player", "icon": "item_thermo"},

	# ---- 紫·新批次（2026-10-04 定稿，待实装：implemented=false 不进货架池） ----
	"老虎机": {"quality": "紫", "cost": 3, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "转三把数字，奖金按点数翻倍，连号豹子更肥。", "implemented": false, "icon": "item_slot"},
	"出老千": {"quality": "紫", "cost": 4, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "开一场赌局，就算没赢也能和赢家平分奖金。", "implemented": false, "icon": "item_gamble"},
	"代课": {"quality": "紫", "cost": 3, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "你的下一笔租金，由房东替你付。", "implemented": false, "icon": "item_substitute"},
	"没收": {"quality": "紫", "cost": 4, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "指定玩家的一件随机道具，直接归你。", "implemented": false, "target": "player", "icon": "item_confiscate"},
	"顶楼加盖": {"quality": "紫", "cost": 3, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "你的一块地皮直接加盖两层。", "implemented": false, "target": "own_tile", "icon": "item_roof"},
	"转专业": {"quality": "紫", "cost": 4, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "与指定玩家各挑一块地皮互换。", "implemented": false, "target": "player", "icon": "item_transfer"},
	"宿舍改造": {"quality": "紫", "cost": 4, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "学校八折收购他的一块地皮，补偿归他。", "implemented": false, "target": "player", "icon": "item_redevelop"},
	"打印店": {"quality": "紫", "cost": 4, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "复印他的随机一件道具（橙货拒印）。", "implemented": false, "target": "player", "icon": "item_copy"},
	"刮刮乐": {"quality": "紫", "cost": 2, "type": "consumable", "unique": false, "cooldown": 0,
		"desc": "刮开涂层，随机 ¥100~¥1000。", "implemented": false, "icon": "item_scratch"},
}

static func def(id: String) -> Dictionary:
	return ITEMS.get(id, {})

static func price(quality: String) -> int:
	return int(QUALITY_PRICES.get(quality, 999999))
