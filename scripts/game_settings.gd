class_name GameSettings
## 开局设置对象：房主配置、随开局下发（见 doc/game-design/开局设置.md）。
## 目前只有「操作限时挡位」一项；后续设置项往这里追加字段。

const TIER_CURRENT := "current"   # 现状：各环节沿用原常量
const TIER_NONE := "none"         # 不限时：不自动托管

const TIERS: Array[String] = [TIER_CURRENT, "15", "30", "60", TIER_NONE]
const TIER_LABELS := {
	"current": "现状",
	"15": "15 秒",
	"30": "30 秒",
	"60": "60 秒",
	"none": "不限时",
}

var timeout_tier := TIER_CURRENT

# ---- 畸变（doc/game-design/畸变.md §六；频率「关」即总开关关闭） ----
const AB_FREQS: Array[String] = ["关", "低", "中", "高"]
const AB_FREQ_LABELS := {"关": "关", "低": "低", "中": "中", "高": "高"}
const AB_DURS: Array[String] = ["1", "2", "3", "4"]
const AB_DUR_LABELS := {"1": "1", "2": "2", "3": "3", "4": "4"}
const AB_COND_SW: Array[String] = ["off", "on"]
const AB_COND_LABELS := {"off": "关", "on": "开"}

var ab_freq := "关"   # 随机触发频率（关 = 整局不触发）
var ab_dur := 2       # 持续型畸变的默认时长基准（玩家回合数，条目可覆盖）
var ab_cond := true   # 是否允许条件型畸变触发

# ---- 开局科技（doc/game-design/开局科技.md；关 = 发车不定档不选卡） ----
const TECH_SW: Array[String] = ["off", "on"]
const TECH_SW_LABELS := {"off": "关", "on": "开"}

var tech_on := false  # 科技开关（默认关）

func copy() -> GameSettings:
	var s := GameSettings.new()
	s.timeout_tier = timeout_tier
	s.ab_freq = ab_freq
	s.ab_dur = ab_dur
	s.ab_cond = ab_cond
	s.tech_on = tech_on
	return s

## 某环节的操作窗口秒数；<= 0 表示不限时。
## kind: roll / prompt / item / shop / black / card
# 未知挡位会掉到最后一段、按「现状」取值（回落，见 §三之一）
static func turn_seconds(tier: String, kind: String) -> float:
	match tier:
		"15": return 15.0
		"30": return 30.0
		"60": return 60.0
		TIER_NONE: return 0.0
	match kind:
		"roll": return GameData.ROLL_TIMEOUT
		"prompt": return GameData.PROMPT_TIMEOUT
		# 抽卡演出的「确定」（批次 12 C2）：与「决定」同一份秒数（两者都是"要点一下的确认"）
		"card": return GameData.PROMPT_TIMEOUT
		"item": return ItemData.ITEM_TIMEOUT
		"shop": return ItemData.SHOP_TIMEOUT
		"black": return ItemData.BLACK_TIMEOUT
	return GameData.PROMPT_TIMEOUT
