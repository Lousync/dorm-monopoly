class_name RulesText
## 对局内「📖 规则说明」面板的全部文案 —— 唯一来源。
##
## 内容与 `doc/game-design/*` 同步；数值一律引用 `GameData` / `ItemData` 常量，
## **不在这里写死**，否则改了数值就忘了改说明（这份文案是玩家在局内唯一能查的东西）。
## 正文走 RichTextLabel 的 bbcode，_h() 出小标题、_d() 出次要色。

const C_HEAD := "#f5b342"   # 与 UIKit.ACCENT 同色
const C_DIM := "#9aa2b3"    # 与 UIKit.TEXT_DIM 同色

static func _h(text: String) -> String:
	return "[color=%s][b]%s[/b][/color]" % [C_HEAD, text]

static func _d(text: String) -> String:
	return "[color=%s]%s[/color]" % [C_DIM, text]

## 棋盘上某格型的数量：从 TILES 数出来，写死会在改棋盘时悄悄说谎
static func _count_of(type_name: String) -> int:
	var n := 0
	for d in GameData.TILES:
		if String(d.get("type", "")) == type_name:
			n += 1
	return n

## 掷轮超时说明——「不限时」档要说清「不会被代掷」
static func _roll_rule(tier: String) -> String:
	var sec := GameSettings.turn_seconds(tier, "roll")
	if sec <= 0.0:
		return "· %s" % _d("本局操作不限时：真人可以慢慢来，不会被系统代掷")
	return "· %s" % _d("真人 %.0f 秒不掷由系统代掷" % sec)

## 买地/升级决策超时说明
static func _prompt_rule(tier: String) -> String:
	var sec := GameSettings.turn_seconds(tier, "prompt")
	if sec <= 0.0:
		return "· 买地 / 升级是弹窗询问，本局不限时，不会自动拒绝"
	return "· 买地 / 升级是弹窗询问，%s 视为拒绝" % _d("%.0f 秒不答" % sec)


## 分页：[key, 标签, 正文]
## tier = 本局「操作限时」挡位（见 开局设置.md §三之一）；秒数一律从 GameSettings 取，不写死
static func pages(tier := GameSettings.TIER_CURRENT) -> Array:
	return [
		{"key": "basic", "title": "基础操作", "body": _basic()},
		{"key": "turn", "title": "回合与行动", "body": _turn(tier)},
		{"key": "board", "title": "棋盘与地产", "body": _board()},
		{"key": "money", "title": "经济与胜负", "body": _money()},
		{"key": "item", "title": "道具与事件", "body": _item()},
	]

# ---------------- 各页正文 ----------------

static func _basic() -> String:
	return "\n".join([
		_h("视角"),
		"· 滚轮：在「3D 第一人称」与「2D 桌面」之间连续推移视角（向前滚推向 2D 桌面、向后滚拉回 3D）",
		# 【终审 F1】一期 Task 7 新增的推拉轴（Ctrl+滚轮）此前**没有任何面向玩家的交代**，而这一期
		# **有意**把"读棋盘"从默认档挪走（默认档格里的字只有 6px 量级）⇒ 补救手段必须写进玩家唯一
		# 能查的这份说明。方向照实现写，别凭印象：`table_3d._unhandled_input` 里
		# **Ctrl+前滚 = 拉远**（看屋子）、**Ctrl+后滚 = 推近**（看棋盘），与不按 Ctrl 的滚轮同向。
		"· [b]Ctrl[/b]+滚轮：在 3D 端把相机推近 / 拉远（向后滚推近、向前滚拉远）",
		"  3D 默认那档是「看屋子」的档，格子小、格里的字读不清 ⇒ 要读棋盘上的字请 %s"
			% _d("[b]Ctrl[/b]+滚轮推近，或把滚轮推到底看 2D 桌面"),
		"· 3D 端手里有牌、点一张即可用；2D 端手牌看不见也点不到，但桌上转盘仍可点着掷轮、右下角也能掷",
		"· 点格子看详情 · 点左上角[b]名册条[/b]里对手那一格选中 TA（指向性道具用）",
		# 手牌的三个入口：自己面前那排实物卡（批次 5 起立在近端桌沿）。丢弃这条自批次 3 改到
		# 「手牌右键」之后**规则说明里从没写过**，而它是玩家可见的入口 —— 补上（终审 M7）。
		# 出牌自批次 7 起是**点一下直出**（杀戮尖塔式），不再是"选中 → 点桌垫确认"两段式。
		"· 自己面前那排[b]手牌[/b]：点一张牌 = [b]直接使用[/b]（需要选目标的再点目标）；[b]右键[/b]点牌 = 丢弃（再点一次确认）",
		"· %s" % _d("视角固定在自己座位，全程不旋转"),
		"",
		_h("界面"),
		"· 左上角「暂停」：房主按 → %s" % _d("全场暂停"),
		"  非房主按只对自己生效，屏幕出现「房主已暂停」遮罩就是房主按了暂停",
		"· 右上角「战报」可折叠；面板底部输入框聊天（回车发送）",
		"· 左上角「暂停」旁那条[b]名册条[/b]：其余玩家一格一位（名次 + 棋子色小片 + 昵称），点一格看 TA 的道具与能量",
		"· 左下角是你自己的身家条（身家 / 现金 / 能量）",
		"· 右上角「规则说明」就是本面板（与「战报」互斥：开一个自动收另一个），点「收起」回到按钮态",
		"",
		_h("一局的基本盘"),
		"· 1~4 人，房主即权威服务器；有人掉线由机器人接管",
		"· 轮流行动，所有人各行动一次 = 一回合，共 %d 回合" % GameData.MAX_ROUNDS,
		"· 第 %d 回合结束按身家排名结算" % GameData.MAX_ROUNDS,
	])

static func _turn(tier: String) -> String:
	return "\n".join([
		_h("一回合两阶段"),
		"回合开始结算 → ①转轮盘 → 移动与落地结算 → ②使用道具 → 回合结束",
		"",
		_h("回合开始（被动照常）"),
		"· 体力 +1（上限 5）· 道具冷却 -1 · 信托基金 +%s" % GameData.fmt_money(100),
		"",
		_h("① 转轮盘（0~12）"),
		"· 1~11：前进对应步数",
		"· 12：满值，走完后再%s" % _d("额外行动一次"),
		"· 0：原地待命一回合，脚下格子的内容会%s（角格除外）" % _d("再结算一次"),
		"· 待命仍算完成投掷，之后照常可用道具",
		"· 连续 3 次 ≥10：兴奋过度，被查寝送宿委会（跳过一回合）",
		_roll_rule(tier),
		"",
		_h("移动与落地"),
		"· 逐格跳动；途中踏过起点领工资",
		_prompt_rule(tier),
		"",
		_h("② 使用道具"),
		"· 每回合限用 1 次主动道具（被动不计）· 超时自动跳过",
		"· 使用窗口 = 掷轮结算完成 → 本回合结束（含逛店 / 赌场期间）",
		"",
		_h("休眠 vs 跳过回合（容易搞混）"),
		"· %s 被动照常、系统代掷、买地一律拒绝、商店自动离开" % _d("休眠："),
		"  触发：黑市挨打（进小黑屋）",
		"· %s 整回合被压制，被动也不享受" % _d("跳过回合："),
		"  触发：转轮 0 待命、宿委会反省",
	])

static func _board() -> String:
	var lines := [
		_h("棋盘"),
		"· %d 格环形（%d×%d 外圈）" % [GameData.TILES.size(), GameData.BOARD_COLS, GameData.BOARD_ROWS],
		"· 四角：起点（右下）、宿委会（左下）、卧谈会（免费休息）、查寝！（右上，直接送宿委会）",
		"",
		_h("格型"),
		"· 地产 %d 块（各自独立，无分组）· 机会/命运 %d · 小卖部 %d" % [
			_count_of("property"), _count_of("event"), _count_of("shop")],
		"· 失物招领 %d · 特浓咖啡 %d · 免费休息 %d · 宿舍赌场 %d" % [
			_count_of("item"), _count_of("again"), _count_of("rest"), _count_of("casino")],
		"",
		_h("地产：沿路径由便宜到贵"),
	]
	var n := GameData.PROPERTY_NAMES.size()
	var k_lo := GameData.prop_price(0)
	var k_hi := GameData.prop_price(n - 1)
	lines.append("· 共 %d 块，地价 %s ~ %s（越往后越贵）" % [
		n, GameData.fmt_money(k_lo), GameData.fmt_money(k_hi)])
	lines.append("· 每块地各自独立：租金 = 自己的地价 × %d％（另有装修加成）" % [
		int(roundf(GameData.PROP_RENT_RATIO * 100.0))])
	lines.append("· %s" % _d("没有「集齐成套」一说——买下哪块就只按哪块结算"))
	lines.append_array([
		"",
		_h("买 / 升级 / 收租"),
		"· 买入价 = 地价；落到自己地块可装修升级",
		# 注意：这里的 50％ 用全角，写成半角 % 会被 String % 运算符当成格式符解析
		"· 升级费 = 地价 × 50％／级，上限 %d 级" % GameData.MAX_LEVEL,
		"· 租金 = 基础租金 × (1 + 装修等级)",
		"",
		_h("出局与焦土"),
		"· 付不起钱即出局：现金清零、名下地产收归无主且等级清零",
		"· 焦土：被「亡牌飞行员coco」炸毁的地皮无归属、不产租；",
		"  任何玩家落地都要自动捐款累进进度，达标后恢复成%s地产" % _d("无主"),
	])
	return "\n".join(lines)

static func _money() -> String:
	return "\n".join([
		_h("资金"),
		"· 起始资金 %s" % GameData.fmt_money(GameData.START_MONEY),
		"· 踏过或停在起点领工资 %s" % GameData.fmt_money(GameData.SALARY),
		"· 钱主要花在%s：买地、装修、交租、小卖部、赌注" % _d("刀刃上"),
		"",
		_h("机会 / 命运卡"),
		"· ±金额、前进后退、送监、室友发红包、请全宿舍喝奶茶……",
		"· 机会格另有专属卡：被拉进小卖部、公告栏道具券、神秘短信（开黑市）",
		"",
		_h("失物招领（地图 %d 格）" % _count_of("item")),
		"· 落地翻箱，按品质权重捡一件随机道具（白 45 / 绿 30 / 蓝 18 / 紫 5 / 橙 2）",
		"· 背包满或该品质缺货则落空",
		"",
		_h("特浓咖啡（地图 %d 格）" % _count_of("again")),
		"· 落地灌一口，本回合%s（再掷一次轮盘并照常结算）" % _d("再行动一次"),
		"",
		_h("豁免（空想者的香皂）"),
		"· 持皂免疫 debuff：扣钱、后退、送监、黑市出口费与挨打……",
		"· %s 租金、购买、赌注、道具消耗是中性，香皂挡不住" % _d("注意："),
		"",
		_h("胜负"),
		"· 只剩 1 人存活 → 该玩家直接获胜（全员破产则学校胜）",
		"· 否则第 %d 回合结束按身家排名" % GameData.MAX_ROUNDS,
		"· 身家 = 现金 + Σ(地价 + 等级 × 升级费用)",
	])

static func _item() -> String:
	return "\n".join([
		_h("体力（⚡）与冷却"),
		"· 体力初始 3、上限 5，每回合开始 +1",
		"· 用消耗 N⚡ 的道具要求体力 ≥ N，用后扣减",
		"· 用掉后该道具进入 %s 回合冷却（跟着道具实例走）" % _d("N"),
		"· 每回合限用 1 次主动道具 · 背包 %d 格" % 5,
		"",
		_h("被动与唯一性"),
		"· 被动道具持有即生效：不耗体力、不进冷却、不占次数，可主动丢弃",
		"· 被动与橙色道具%s（含货架在售），丢弃 / 破产回池" % _d("整局唯一"),
		"· 一次性橙货用后焚毁，不回池",
		"",
		_h("品质与售价（小卖部）"),
		"· 白 %s · 绿 %s · 蓝 %s" % [
			GameData.fmt_money(ItemData.QUALITY_PRICES["白"]),
			GameData.fmt_money(ItemData.QUALITY_PRICES["绿"]),
			GameData.fmt_money(ItemData.QUALITY_PRICES["蓝"])],
		"· 紫 %s · 橙 %s" % [
			GameData.fmt_money(ItemData.QUALITY_PRICES["紫"]),
			GameData.fmt_money(ItemData.QUALITY_PRICES["橙"])],
		"· %s" % _d("逐件道具的效果见 doc/game-design/道具图鉴.md"),
		"",
		_h("小卖部（地图 %d 家）" % _count_of("shop")),
		"· 落在地图小卖部格即进店（整屏切进店内界面）；每家 3 栏货架、各自独立补货",
		"· 进店后点货架旁的「买」按钮购买；持黑卡且有次数则免单",
		"· 刷新费 = %s + %s × 全场刷新次数（整局递增、不重置）" % [
			GameData.fmt_money(ItemData.REFRESH_BASE), GameData.fmt_money(ItemData.REFRESH_STEP)],
		"",
		_h("黑市（仅由机会卡进入，不占地图格）"),
		"· 一切消费用地产：紫 %d 块 · 橙 %d 块 · 刷新 %d 块 · 出口 %d 块" % [
			ItemData.BLACK_COST["紫"], ItemData.BLACK_COST["橙"],
			ItemData.BLACK_REFRESH_COST, ItemData.BLACK_EXIT_COST],
		"· 交哪几块地皮由你自己逐块点选；被收走的地皮回归无主、等级清零",
		"· 凑不出地皮 → 扣当前现金一半 + 小黑屋（休眠一回合）后扔出店",
		"",
		_h("宿舍赌场 · 投骰子（地图 %d 格）" % _count_of("casino")),
		"· 落地全员下注 %s（按各自现金封顶），奖池 %s" % [
			GameData.fmt_money(GameData.CASINO_STAKE), _d("赢家通吃")],
		"· 进入时整屏切进赌场场景并抽游戏（不再是相机推到赌场那一角）",
		"· 每人同时掷一颗 6 面骰，点数最大者通吃奖池（平局并列者平分）",
		"· 破产者观战、机器人自动玩",
	])
