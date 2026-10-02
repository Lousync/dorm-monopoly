class_name GameSettings
## 开局设置对象：房主配置、随开局下发（见 docs/gameplay/开局设置.md）。
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

func copy() -> GameSettings:
	var s := GameSettings.new()
	s.timeout_tier = timeout_tier
	return s

## 某环节的操作窗口秒数；<= 0 表示不限时。
## kind: roll / prompt / item / shop / black
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
		"item": return ItemData.ITEM_TIMEOUT
		"shop": return ItemData.SHOP_TIMEOUT
		"black": return ItemData.BLACK_TIMEOUT
	return GameData.PROMPT_TIMEOUT
