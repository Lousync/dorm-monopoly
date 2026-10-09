class_name TechData
## 开局科技数据总表（唯一台账：doc/game-design/开局科技.md）。
## 每局**随机定档**（三档等概率、全场同档），每人从同档抽三选一，
## 允许多人重复。科技效果一律无 buff/debuff 标签——香皂对科技无效。
## 三档均已定稿实装（2026-10-07，黄金 19 条、编号 16 弃案留空；钻石 20 条）。

const TIER_SILVER := "白银"
const TIER_GOLD := "黄金"
const TIER_DIAMOND := "钻石"
const TIERS: Array[String] = [TIER_SILVER, TIER_GOLD, TIER_DIAMOND]

## 白银定稿 20 条目标：当前 20 条全部定稿（编号 4/6/17 弃案留空，见开局科技.md）
const TECHS := {
	# ---- 白银（2026-10-04 定稿） ----
	"助学金": {"tier": TIER_SILVER,
		"desc": "起始资金 +¥2000。", "implemented": true},
	"精力充沛": {"tier": TIER_SILVER,
		"desc": "体力上限 5 → 6（与充电宝可叠加）。", "implemented": true},
	"兼职达人": {"tier": TIER_SILVER,
		"desc": "每次经过自己的地皮时 +¥300。", "implemented": true},
	"二手教材": {"tier": TIER_SILVER,
		"desc": "开局随机获得一件白档道具。", "implemented": true},
	"零花钱规划": {"tier": TIER_SILVER,
		"desc": "每个自己回合开始 +¥100。", "implemented": true},
	"勤工俭学": {"tier": TIER_SILVER,
		"desc": "每次使用主动道具后 +¥100。", "implemented": true},
	"学生折扣": {"tier": TIER_SILVER,
		"desc": "小卖部购买道具每件立减 ¥200。", "implemented": true},
	"摸鱼时刻": {"tier": TIER_SILVER,
		"desc": "你掷出 0（原地待命）时 +¥500。", "implemented": true},
	"眼尖手快": {"tier": TIER_SILVER,
		"desc": "失物招领捡到的道具品质 +1 档（橙封顶）。", "implemented": true},
	"装修返现": {"tier": TIER_SILVER,
		"desc": "你升级地皮时每级 +¥150。", "implemented": true},
	"赌场熟客": {"tier": TIER_SILVER,
		"desc": "每次参与赌场小游戏（无论输赢）+¥1000。", "implemented": true},
	"厄运保单": {"tier": TIER_SILVER,
		"desc": "事件卡扣钱对你无效，每局可抵消 4 次。", "implemented": true},
	"旧物回收": {"tier": TIER_SILVER,
		"desc": "丢弃道具时每件回收 ¥150。", "implemented": true},
	"满分奖励": {"tier": TIER_SILVER,
		"desc": "你掷出 12（满值）时 +¥300。", "implemented": true},
	"反思津贴": {"tier": TIER_SILVER,
		"desc": "你在宿委会反省的回合开始时 +¥500。", "implemented": true},
	"助困金": {"tier": TIER_SILVER,
		"desc": "现金低于 ¥1000 时，每个自己回合开始额外 +¥500。", "implemented": true},
	"起点打卡": {"tier": TIER_SILVER,
		"desc": "恰好停在起点时额外 +¥400。", "implemented": true},
	"喜报频传": {"tier": TIER_SILVER,
		"desc": "你抽事件卡获得钱时，额外 +¥200。", "implemented": true},
	"心理素质": {"tier": TIER_SILVER,
		"desc": "你不会被「连续三次 ≥10」查寝带走。", "implemented": true},
	"开疆拓土": {"tier": TIER_SILVER,
		"desc": "名下地皮首次达到 5 / 10 / 15 块时，各 +¥800。", "implemented": true},

	# ---- 黄金（2026-10-07 定稿 19 条；编号 16「样板房」弃案留空） ----
	"风险投资": {"tier": TIER_GOLD,
		"desc": "起始资金 −¥5000，此后每个自己回合开始 +¥500。", "implemented": true},
	"灵活就业": {"tier": TIER_GOLD,
		"desc": "每回合第一件道具消耗 −1（下限 0）。", "implemented": true},
	"宿舍威望": {"tier": TIER_GOLD,
		"desc": "付给他人的租金 −30%。", "implemented": true},
	"地产眼光": {"tier": TIER_GOLD,
		"desc": "本局购买的前 2 块地皮半价。", "implemented": true},
	"工资上调": {"tier": TIER_GOLD,
		"desc": "每次经过起点（踏过 / 停在）额外 +¥1500（与「校园卡」各自独立生效）。", "implemented": true},
	"装修师傅": {"tier": TIER_GOLD,
		"desc": "你升级地皮的费用 −25%（向下取整）。", "implemented": true},
	"置业补贴": {"tier": TIER_GOLD,
		"desc": "你每购买一块地皮 +¥500。", "implemented": true},
	"定期存款": {"tier": TIER_GOLD,
		"desc": "每个自己回合开始获得现金 ×2% 的利息（向下取整，单次上限 ¥600）。", "implemented": true},
	"能量回收": {"tier": TIER_GOLD,
		"desc": "每次使用主动道具后，50% 概率退回 1⚡。", "implemented": true},
	"赌运加持": {"tier": TIER_GOLD,
		"desc": "你在赌场获胜时，额外 +¥3000。", "implemented": true},
	"活力全开": {"tier": TIER_GOLD,
		"desc": "你的体力上限 +2（与「精力充沛」「充电宝」同类效果、可叠加）。", "implemented": true},
	"手速惊人": {"tier": TIER_GOLD,
		"desc": "你使用道具后的冷却 −1（下限 1；无冷却的道具不受影响）。", "implemented": true},
	"名师指点": {"tier": TIER_GOLD,
		"desc": "开局随机获得一件蓝档道具。", "implemented": true},
	"孤注一掷": {"tier": TIER_GOLD,
		"desc": "起始资金 −¥6000，开局随机获得一件紫档道具。", "implemented": true},
	"会员卡": {"tier": TIER_GOLD,
		"desc": "你在小卖部购买道具立减 20%（向下取整；与「学生折扣」先打折后立减；黑市不适用）。", "implemented": true},
	"小金库": {"tier": TIER_GOLD,
		"desc": "你的现金首次达到 ¥30000 时 +¥5000（一次性）。", "implemented": true},
	"闲不住": {"tier": TIER_GOLD,
		"desc": "你转出 0 时不再原地待命，改为前进 2 格（不再算「掷出 0」）。", "implemented": true},
	"悔棋": {"tier": TIER_GOLD,
		"desc": "每局 1 次：转出 ≤6 时可重转一次（须在落地结算前决定，旧点数作废）。", "implemented": true},
	"面壁功深": {"tier": TIER_GOLD,
		"desc": "你在宿委会反省结束时，随机获得一件蓝档道具。", "implemented": true},

	# ---- 钻石（2026-10-07 定稿 20 条） ----
	"富二代": {"tier": TIER_DIAMOND,
		"desc": "起始资金 ×2。", "implemented": true},
	"点石成金": {"tier": TIER_DIAMOND,
		"desc": "你收取的租金 +25%。", "implemented": true},
	"卷王": {"tier": TIER_DIAMOND,
		"desc": "每个自己回合开始体力额外 +1（上限照封）。", "implemented": true},
	"天选之人": {"tier": TIER_DIAMOND,
		"desc": "每个自己回合开始 +¥500。", "implemented": true},
	"双开": {"tier": TIER_DIAMOND,
		"desc": "你每回合可使用 2 件道具（体力、冷却闸照常）。", "implemented": true},
	"熟能生巧": {"tier": TIER_DIAMOND,
		"desc": "你的道具使用后不进入冷却（体力闸照常）。", "implemented": true},
	"天命在握": {"tier": TIER_DIAMOND,
		"desc": "每局 4 次：转轮前可直接指定本次点数（1~11；连续 ≥10 查寝计数照常）。", "implemented": true},
	"任意门": {"tier": TIER_DIAMOND,
		"desc": "每局 2 次：移动阶段可改为任选一格前往（按落点正常结算）。", "implemented": true},
	"东山再起": {"tier": TIER_DIAMOND,
		"desc": "你首次破产时不出局：现金回 ¥8000，地产与道具保留（每局一次）。", "implemented": true},
	"复利": {"tier": TIER_DIAMOND,
		"desc": "每个自己回合开始获得现金 ×2.5% 的利息（向下取整，单次上限 ¥1000）。", "implemented": true},
	"批发拿地": {"tier": TIER_DIAMOND,
		"desc": "你购买地皮立减 25%（向下取整；与「地产眼光」可叠加）。", "implemented": true},
	"金饭碗": {"tier": TIER_DIAMOND,
		"desc": "每次经过起点（踏过 / 停在）额外 +¥4000。", "implemented": true},
	"欧皇附体": {"tier": TIER_DIAMOND,
		"desc": "开局随机获得一件橙档道具。", "implemented": true},
	"金字招牌": {"tier": TIER_DIAMOND,
		"desc": "到轮按身家结算时，你名下每块地皮按 1.3 倍计入。", "implemented": true},
	"大器晚成": {"tier": TIER_DIAMOND,
		"desc": "第 15 轮起，每个自己回合开始 +¥1000。", "implemented": true},
	"谈判专家": {"tier": TIER_DIAMOND,
		"desc": "付给他人的租金 −40%（与「宿舍威望」乘算叠加 = 付 42%）。", "implemented": true},
	"广置家业": {"tier": TIER_DIAMOND,
		"desc": "名下地皮首次达到 2 / 4 / 6 块时，各 +¥5000。", "implemented": true},
	"预支未来": {"tier": TIER_DIAMOND,
		"desc": "开局立得 ¥30000，此后本局经过起点不再领工资。", "implemented": true},
	"接收大员": {"tier": TIER_DIAMOND,
		"desc": "有玩家破产出局时，你可按 5 折优先收购其任意几块地皮（每局限 1 次）。", "implemented": true},
	"淘宝达人": {"tier": TIER_DIAMOND,
		"desc": "你落在失物招领格时，捡到的道具品质保底紫档（与「眼尖手快」取高不叠算）。", "implemented": true},
}

static func def(name: String) -> Dictionary:
	return TECHS.get(name, {})

## 某档的科技名池（按表序）
static func pool(tier: String) -> Array:
	var out: Array = []
	for name in TECHS:
		if String(TECHS[name].tier) == tier and bool(TECHS[name].implemented):
			out.append(name)
	return out

## 随机定一档（三档等概率 = 各 1/3）。
## 2026-10-09 取代原 `tier_by_dice(pips)`：原路是「掷 1~6 点 → 1~2 白银 / 3~4 黄金 / 5~6 钻石」，
## 均匀掷 6 面骰再映射到 3 档，概率**本就是各 1/3** —— 去掉骰子不改分布、不动平衡。
static func random_tier() -> String:
	return TIERS[randi_range(0, TIERS.size() - 1)]
