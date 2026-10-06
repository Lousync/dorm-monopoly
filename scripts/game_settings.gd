class_name GameSettings
## 开局设置对象：房主配置、随开局下发（见 doc/game-design/开局设置.md）。
## 默认值 = 当前常量（「不配置即现状」是硬约定；唯一例外：破产变卖保底默认开）。
## 房主在大厅写这份对象，game.gd 的 `_settings` 拿的是 copy() 副本；
## 客户端经状态快照逐字段同步（见 game.gd s_state）。

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

# ---- A · 经济（开局设置.md §二；数值默认 = GameData 常量） ----
const CASH_MIN := 0
const CASH_MAX := 99999
const SALARY_MIN := 0
const SALARY_MAX := 20000
const SW: Array[String] = ["off", "on"]
const SW_LABELS := {"off": "关", "on": "开"}

var start_cash := GameData.START_MONEY    # 起始资金（0 ~ 99999）
var start_salary := GameData.SALARY       # 起点补贴（0 ~ 20000）
var liq_on := true    # 破产变卖保底（唯一例外于「默认 = 现状」：2026-10-04 定稿即默认开）

# ---- B · 回合与节奏：回合上限档位制（30 默认 / 60 / 90 / 不限）；0 = 不限 ----
const ROUNDS_SW: Array[String] = ["30", "60", "90", "none"]
const ROUNDS_LABELS := {"30": "30 轮", "60": "60 轮", "90": "90 轮", "none": "不限"}

var max_rounds := 30

# ---- C · 胜利条件（单选主选项 + 联动子项；开局设置.md §四） ----
const WIN_MODES: Array[String] = ["rounds", "cash", "last"]
const WIN_LABELS := {
	"rounds": "到轮身家结算",
	"cash": "目标现金",
	"last": "最后存活",
}
const WIN_CASH_MIN := 1000
const WIN_CASH_MAX := 200000

var win_mode := "rounds"   # 当前默认 = 固定轮数身家最高
var win_cash := 50000      # 目标现金（先到立即胜；1 千 ~ 20 万）

# ---- E/F · 道具与赌场开关（开局设置.md §六/§七 的候选开关先行；总开关与权重随数值专场） ----
var shop_on := true     # 小卖部开关：关 = 店面歇业（落格只公告）、机会卡「进店」不发
var black_on := true    # 黑市开关：关 = 机会卡「黑市开张」不发
var casino_on := true   # 赌场开关：关 = 赌场格歇业

## 保存前统一钳制越界值（面板输入、RPC 篡改都兜住）
func clamp_all() -> void:
	start_cash = clampi(start_cash, CASH_MIN, CASH_MAX)
	start_salary = clampi(start_salary, SALARY_MIN, SALARY_MAX)
	# 回合上限是档位制（30/60/90/不限=0），非法值回落默认 30
	if max_rounds != 0 and max_rounds != 30 and max_rounds != 60 and max_rounds != 90:
		max_rounds = 30
	win_cash = clampi(win_cash, WIN_CASH_MIN, WIN_CASH_MAX)
	if not WIN_MODES.has(win_mode):
		win_mode = "rounds"

func copy() -> GameSettings:
	var s := GameSettings.new()
	s.timeout_tier = timeout_tier
	s.ab_freq = ab_freq
	s.ab_dur = ab_dur
	s.ab_cond = ab_cond
	s.tech_on = tech_on
	s.start_cash = start_cash
	s.start_salary = start_salary
	s.liq_on = liq_on
	s.max_rounds = max_rounds
	s.win_mode = win_mode
	s.win_cash = win_cash
	s.shop_on = shop_on
	s.black_on = black_on
	s.casino_on = casino_on
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
