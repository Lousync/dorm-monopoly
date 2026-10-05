class_name TechData
## 开局科技数据总表（唯一台账：doc/game-design/开局科技.md）。
## 每局掷骰定档（1~2 白银 / 3~4 黄金 / 5~6 钻石，等分、全场同档），每人从同档抽三选一，
## 允许多人重复。科技效果一律无 buff/debuff 标签——香皂对科技无效。
## 黄金 / 钻石各 4 条为**草案占池**（2026-10-04），待逐条批改后可整批替换。

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

	# ---- 黄金（草案占池 · 待批） ----
	"风险投资": {"tier": TIER_GOLD,
		"desc": "起始资金 −¥5000，此后每个自己回合开始 +¥800。", "implemented": true},
	"灵活就业": {"tier": TIER_GOLD,
		"desc": "每回合第一件道具消耗 −1（下限 0）。", "implemented": true},
	"宿舍威望": {"tier": TIER_GOLD,
		"desc": "付给他人的租金 −20%。", "implemented": true},
	"地产眼光": {"tier": TIER_GOLD,
		"desc": "本局购买的前 2 块地皮半价。", "implemented": true},

	# ---- 钻石（草案占池 · 待批） ----
	"富二代": {"tier": TIER_DIAMOND,
		"desc": "起始资金 ×2。", "implemented": true},
	"点石成金": {"tier": TIER_DIAMOND,
		"desc": "你收取的租金 +25%。", "implemented": true},
	"卷王": {"tier": TIER_DIAMOND,
		"desc": "每个自己回合开始体力额外 +1（上限照封）。", "implemented": true},
	"天选之人": {"tier": TIER_DIAMOND,
		"desc": "每个自己回合开始 +¥500。", "implemented": true},
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

## 骰子点数 → 等级（1~2 白银 / 3~4 黄金 / 5~6 钻石）
static func tier_by_dice(pips: int) -> String:
	if pips <= 2:
		return TIER_SILVER
	if pips <= 4:
		return TIER_GOLD
	return TIER_DIAMOND
