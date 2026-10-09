class_name GameSettings
## 开局设置对象：房主配置、随开局下发（见 doc/game-design/开局设置.md）。
## 默认值 = 当前常量（「不配置即现状」是硬约定；**两处例外**：破产变卖保底、科技都默认开）。
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

## 「现状」那一档的悬停提示。**必须有**：这一档不是统一的秒数，各环节**各自沿用原常量**
##（掷轮 35 / 决定·抽卡 25 / 道具 12 / 小卖部·黑市 20），而其余挡位是所有窗口统一取该值 ——
## 不点明就容易被读成"现状 = 25 秒"（用户 2026-10-09 就是这么问的）。
## 两处 tier chip 行（大厅设置弹窗 / 对局内暂停面板）共用这一份文案，别再各写一遍。
const TIER_CURRENT_HINT := "「现状」= 各环节沿用各自的原值：掷轮 35 / 决定·抽卡 25 / 道具 12 / 小卖部·黑市 20 秒\n15 / 30 / 60 秒档 = 所有窗口统一取该秒数；「不限时」= 不计时、也不自动托管"

var timeout_tier := TIER_CURRENT

# ---- 畸变（doc/game-design/畸变.md §六；频率「关」即总开关关闭） ----
const AB_FREQS: Array[String] = ["关", "低", "中", "高"]
const AB_FREQ_LABELS := {"关": "关", "低": "低", "中": "中", "高": "高"}
const AB_DURS: Array[String] = ["1", "2", "3", "4"]
const AB_DUR_LABELS := {"1": "1", "2": "2", "3": "3", "4": "4"}

var ab_freq := "关"   # 随机触发频率（关 = 整局不触发）
var ab_dur := 2       # 持续型畸变的默认时长基准（玩家回合数，条目可覆盖）
var ab_cond := true   # 是否允许条件型畸变触发

# ---- 科技（doc/game-design/科技.md；关 = 发车不定档不选卡） ----
## 科技开关：**默认开**（用户 2026-10-09 定）—— 与 `liq_on` 并列，都是「默认值 ≠ 现状」的例外。
var tech_on := true

# 科技等级：随机 = 系统等概率选一档；其余 = 房主指定该档（2026-10-07）
const TECH_TIER_RANDOM := "random"
const TECH_TIERS: Array[String] = [TECH_TIER_RANDOM, "白银", "黄金", "钻石"]
const TECH_TIER_LABELS := {"random": "随机", "白银": "白银", "黄金": "黄金", "钻石": "钻石"}

var tech_tier := TECH_TIER_RANDOM   # "random" = 系统随机选一档；其余 = 指定等级

# ---- A · 经济（开局设置.md §二；数值默认 = GameData 常量） ----
const CASH_MIN := 0
const CASH_MAX := 99999
const SALARY_MIN := 0
const SALARY_MAX := 20000

var start_cash := GameData.START_MONEY    # 起始资金（0 ~ 99999）
var start_salary := GameData.SALARY       # 起点补贴（0 ~ 20000）
var liq_on := true    # 破产变卖保底（例外一于「默认 = 现状」：2026-10-04 定稿即默认开）

# ---- B · 回合与节奏：回合上限档位制（30 默认 / 45 / 60 / 80 / 不限）；0 = 不限 ----
# 档位由用户 2026-10-09 定为 30 / 45 / 60 / 80 / 不限（原 30 / 60 / 90 / 不限）。
const ROUNDS_SW: Array[String] = ["30", "45", "60", "80", "none"]
const ROUNDS_LABELS := {"30": "30 轮", "45": "45 轮", "60": "60 轮", "80": "80 轮", "none": "不限"}

var max_rounds := 30

# ---- C · 胜利条件（单选主选项 + 联动子项；开局设置.md §四） ----
const WIN_MODES: Array[String] = ["rounds", "cash", "last"]
const WIN_LABELS := {
	"rounds": "总资产排名",
	"cash": "目标现金",
	"last": "最后存活",
}
const WIN_CASH_MIN := 1000
const WIN_CASH_MAX := 200000

var win_mode := "rounds"   # 当前默认 = 固定轮数身家最高
var win_cash := 50000      # 目标现金（先到立即胜；1 千 ~ 20 万）

# ---- E/F · 道具与赌场开关（开局设置.md §六/§七 的候选开关先行；总开关随数值专场）
# 注：原「品质权重」开关随 2026-10-10 道具重构作废（抽选已改全池等概率，无权重可调） ----
var shop_on := true     # 小卖部开关：关 = 店面歇业（落格只公告）、机会卡「进店」不发
var black_on := true    # 黑市开关：关 = 机会卡「黑市开张」不发
var casino_on := true   # 赌场开关：关 = 赌场格歇业

## 保存前统一钳制越界值（面板输入、RPC 篡改都兜住）
func clamp_all() -> void:
	start_cash = clampi(start_cash, CASH_MIN, CASH_MAX)
	start_salary = clampi(start_salary, SALARY_MIN, SALARY_MAX)
	# 回合上限是档位制（30/45/60/80/不限=0），非法值回落默认 30。
	# 判据直接读 `ROUNDS_SW` —— 别再手抄一份数字：原写法抄的是 30/60/90，
	# 2026-10-09 改档位（45 / 80 顶上）时那份抄件就成了漏网的旧口径。
	if max_rounds != 0 and not ROUNDS_SW.has(str(max_rounds)):
		max_rounds = 30
	win_cash = clampi(win_cash, WIN_CASH_MIN, WIN_CASH_MAX)
	if not WIN_MODES.has(win_mode):
		win_mode = "rounds"
	if not TECH_TIERS.has(tech_tier):
		tech_tier = TECH_TIER_RANDOM

func copy() -> GameSettings:
	var s := GameSettings.new()
	s.timeout_tier = timeout_tier
	s.ab_freq = ab_freq
	s.ab_dur = ab_dur
	s.ab_cond = ab_cond
	s.tech_on = tech_on
	s.tech_tier = tech_tier
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
