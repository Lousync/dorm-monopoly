class_name AberrationData
## 畸变（全场事件）数据总表（唯一台账：doc/game-design/畸变.md，图鉴 14 条）。
## 字段：type=持续|非持续；trigger=随机|条件；tag=debuff|buff|中性；
##       dur=持续回合数（0=用开局设置基准 ab_dur；诚信考试=1 即「本回合」）；
##       cond=条件触发参数；implemented=false 不进触发池。
## 两道闸门与顺延队列的规则见畸变.md §二「触发限制」（2026-10-04 定稿）。

# 占位数值（待数值专场回填；改这里即可，不用动 game.gd）
static var FIN_RATE_NC := 0.10   # 金融危机：无房产者扣现金比例
static var FIN_RATE_C := 0.20    # 金融危机：有房产者扣现金比例
static var BIRD_RATE := 0.20     # 枪打出头鸟：强制捐款比例（按现金）
static var FREQ_P := {"低": 0.06, "中": 0.12, "高": 0.25}   # 每回合随机触发概率

const ABERRATIONS := {
	# ---- 图鉴定稿（2026-10-04 全保留） ----
	"诚信考试": {"type": "持续", "trigger": "随机", "tag": "debuff", "dur": 1,
		"desc": "本回合所有玩家不能使用道具（冷却照走、补给照发）。", "implemented": true},
	"金融危机": {"type": "非持续", "trigger": "随机", "tag": "debuff", "dur": 0,
		"desc": "金融风暴来袭：所有人按现金比例被学校扣款，有房产者扣更多！", "implemented": true},
	"调休": {"type": "非持续", "trigger": "随机", "tag": "中性", "dur": 0,
		"desc": "本回合不能转盘；自己的下一回合连转两次。", "implemented": true},
	"停电": {"type": "持续", "trigger": "随机", "tag": "中性", "dur": 0,
		"desc": "全校停电：小卖部 / 黑市不可进入（落店 = 路过）。", "implemented": true},
	"通胀": {"type": "持续", "trigger": "随机", "tag": "中性", "dur": 0,
		"desc": "物价飞涨：全场租金 ×2。", "implemented": true},
	"限电": {"type": "持续", "trigger": "随机", "tag": "debuff", "dur": 0,
		"desc": "每回合开始体力不再 +1。", "implemented": true},
	"隔离": {"type": "持续", "trigger": "随机", "tag": "debuff", "dur": 0,
		"desc": "全员移动点数 −2（下限 0）。", "implemented": true},
	"奖学金季": {"type": "持续", "trigger": "随机", "tag": "buff", "dur": 0,
		"desc": "每人自己的回合开始时 +¥300。", "implemented": true},
	"天降红包": {"type": "非持续", "trigger": "随机", "tag": "buff", "dur": 0,
		"desc": "学校撒钱：所有玩家 +¥500！", "implemented": true},
	"强制捐款": {"type": "非持续", "trigger": "随机", "tag": "debuff", "dur": 0,
		"desc": "所有玩家各扣 ¥500（学校收走）。", "implemented": true},
	"集体感冒": {"type": "非持续", "trigger": "随机", "tag": "debuff", "dur": 0,
		"desc": "流感横行：所有玩家下一回合休眠。", "implemented": true},
	"拆迁": {"type": "非持续", "trigger": "随机", "tag": "debuff", "dur": 0,
		"desc": "一纸拆迁令：全场随机 1~2 块地皮变无主。", "implemented": true},
	# ---- 条件触发 ----
	"房价崩盘": {"type": "持续", "trigger": "条件", "tag": "中性", "dur": 3,   # 持续回合占位，待数值专场
		"cond": {"props": 5},
		"desc": "有人囤到 5 块地皮：全场租金减半。", "implemented": true},
	"枪打出头鸟": {"type": "非持续", "trigger": "条件", "tag": "debuff", "dur": 0,
		"cond": {"cash": 30000},   # 现金门槛占位，待数值专场
		"min_round": 5,   # 第 5 回合起才可能触发（防「预支未来」开局即成出头鸟；2026-10-07 拍板）
		"desc": "有人现金超过门槛：被强制捐款！", "implemented": true},

	# ---- 缩差（中期防贫富悬殊；第 30 回合起才可能随机触发，2026-10-07 拍板） ----
	"斗地主": {"type": "非持续", "trigger": "随机", "tag": "中性", "dur": 0, "min_round": 30,
		"desc": "房产最多的「地主」把自己一块投入最少的地皮无偿过户给末位（保留等级）。", "implemented": true},
	"改革开放": {"type": "非持续", "trigger": "随机", "tag": "buff", "dur": 0, "min_round": 30,
		"desc": "让后富的玩家先富：身家末位随机获得一件紫色道具。", "implemented": true},
}

static func def(id: String) -> Dictionary:
	return ABERRATIONS.get(id, {})
