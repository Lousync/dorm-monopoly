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

## 表格里金额列的区间（如强制缴费 400~1,500）：从数据算，别在文案里写死
static func _amount_range(table: Array) -> String:
	var lo := 1 << 30
	var hi := 0
	for row in table:
		var v := int(row[1])
		lo = mini(lo, v)
		hi = maxi(hi, v)
	return "%s~%s" % [GameData.fmt_money(lo), GameData.fmt_money(hi)]

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
		"· 滚轮缩放 · 按住拖拽平移",
		"· 点格子看详情 · 点对手座位卡转到 TA 的视角",
		"· %s" % _d("Tab 在众人视角间轮换 · 空格回自己视角"),
		"",
		_h("界面"),
		"· 左上角「暂停」：房主按 → %s" % _d("全场暂停"),
		"  非房主按只对自己生效，屏幕出现「房主已暂停」遮罩就是房主按了暂停",
		"· 右上角「战报」可折叠；面板底部输入框聊天（回车发送）",
		"· 左下角「规则说明」就是本面板，点「收起」回到按钮态",
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
		"· 0：原地待命一回合（仍算完成投掷，之后可用道具）",
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
		"· 地产 %d（%d 组 × 3 块）· 机会/命运 %d · 小卖部 %d" % [
			_count_of("property"), GameData.GROUP_TILES.size(),
			_count_of("event"), _count_of("shop")],
		"· 强制缴费 %d · 兼职奖励 %d · 免费休息 %d · 宿舍赌场 %d" % [
			_count_of("fine"), _count_of("bonus"), _count_of("rest"), _count_of("casino")],
		"",
		_h("地产：沿路径由便宜到贵"),
	]
	var order := ["daily", "service", "canteen", "study", "sport", "teach", "dorm", "fun", "night", "health"]
	for key in order:
		lines.append("· %s　地价 %s　基础租金 %s" % [
			String(GameData.GROUP_NAMES[key]),
			GameData.fmt_money(int(GameData.GROUP_PRICES[key])),
			GameData.fmt_money(int(GameData.GROUP_RENTS[key])),
		])
	lines.append_array([
		"",
		_h("买 / 升级 / 收租"),
		"· 买入价 = 地价；落到自己地块可装修升级",
		# 注意：这里的 50％ 用全角，写成半角 % 会被 String % 运算符当成格式符解析
		"· 升级费 = 地价 × 50％／级，上限 %d 级" % GameData.MAX_LEVEL,
		"· 租金 = 基础租金 × (1 + 装修等级) × （集齐同组 3 块再 ×2）",
		"· %s" % _d("集齐同组 3 块即「垄断」，被拆散立刻取消"),
		"",
		_h("出局与焦土"),
		"· 付不起钱即出局：现金清零、名下地产收归无主且等级清零",
		"· 焦土：被「亡牌飞行员coco」炸毁的地皮无归属、不产租、不算垄断；",
		"  任何玩家落地都要自动捐款累进进度，达标后恢复成%s地产" % _d("无主"),
	])
	return "\n".join(lines)

static func _money() -> String:
	return "\n".join([
		_h("资金"),
		"· 起始资金 %s" % GameData.fmt_money(GameData.START_MONEY),
		"· 踏过或停在起点领工资 %s" % GameData.fmt_money(GameData.SALARY),
		"· 强制缴费格 %s，躲不掉" % _d(_amount_range(GameData.FINES)),
		"· 兼职 / 奖励格 %s，直接入账" % _d(_amount_range(GameData.BONUSES)),
		"",
		_h("机会 / 命运卡"),
		"· ±金额、前进后退、送监、室友发红包、请全宿舍喝奶茶……",
		"· 机会格另有专属卡：被拉进小卖部、公告栏道具券、神秘短信（开黑市）",
		"",
		_h("豁免（空想者的香皂）"),
		"· 持皂免疫 debuff：扣钱、后退、送监、罚款、黑市出口费与挨打……",
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
		_h("小卖部（地图 4 家）"),
		"· 落在地图小卖部格即进店；每家 3 栏货架、各自独立补货",
		"· 点桌面货架卡或底部「买」按钮购买；持黑卡且有次数则免单",
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
		_h("宿舍赌场 · 炸弹猫（地图 %d 格）" % _count_of("casino")),
		"· 落地全员下注 %s（按各自现金封顶），奖池 %s" % [
			GameData.fmt_money(GameData.CASINO_STAKE), _d("赢家通吃")],
		"· 牌堆 12 张：炸弹 ×3 / 拆除 ×2 / 小鱼 ×7",
		"· 抽到炸弹有「拆除」则消耗一张化解，否则出局；最后存活者通吃奖池",
		"· 每人限一次「透视」偷看牌堆顶（只有你自己看得见）",
	])
