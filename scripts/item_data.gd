class_name ItemData
## 道具系统数据总表（唯一台账：docs/道具系统设计.md）
## implemented=false 的道具不进货架池，效果随批次解锁

const QUALITIES := ["白", "绿", "蓝", "紫", "橙"]
const QUALITY_NAMES := {"白": "普通", "绿": "稀有", "蓝": "超稀有", "紫": "史诗", "橙": "传说"}  # 显示名（内部键仍为颜色字）
const QUALITY_COLORS := {
	"白": Color(0.93, 0.93, 0.93), "绿": Color(0.42, 0.78, 0.55),
	"蓝": Color(0.36, 0.6, 0.92), "紫": Color(0.66, 0.47, 0.92),
	"橙": Color(0.96, 0.62, 0.25),
}
const SHOP_WEIGHTS := {"白": 40, "绿": 30, "蓝": 20, "紫": 5, "橙": 5}  # 橙 5% 定稿，其余待数值专场
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

const ITEMS := {
	"平均主义": {"quality": "紫", "cost": 5, "type": "active", "unique": false, "cooldown": 5,
		"desc": "所有玩家的现金同步至平均值。", "implemented": true},
	"作弊器": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "下一次转盘的点数由你决定。", "implemented": true},
	"交换生": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "与一名指定玩家随机交换一件道具。", "implemented": true},
	"招财猫": {"quality": "白", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "你的每块地皮租金收入 +50。", "implemented": true},
	"信托基金": {"quality": "绿", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "你的回合开始时，获得 ¥100。", "implemented": true},
	"黑卡": {"quality": "橙", "cost": 4, "type": "active", "unique": true, "cooldown": 4,
		"desc": "接下来 3 次购买免费。", "implemented": true},
	"空想者的香皂": {"quality": "橙", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "免疫所有负面效果。10 回合后融化。", "implemented": true},
	"蛋蛋节": {"quality": "橙", "cost": 1, "type": "consumable", "unique": true, "cooldown": 1,
		"desc": "每位玩家都会获得一份礼物，每局游戏仅限一次。", "implemented": true},
	"亡牌飞行员coco": {"quality": "橙", "cost": 3, "type": "consumable", "unique": true, "cooldown": 3,
		"desc": "每位玩家都有一块随机地皮被摧毁，每局游戏仅限一次。", "implemented": true},
	"园中叶": {"quality": "橙", "cost": 0, "type": "active", "unique": true, "cooldown": 0,
		"desc": "？？？", "implemented": false},
}

static func def(id: String) -> Dictionary:
	return ITEMS.get(id, {})

static func price(quality: String) -> int:
	return int(QUALITY_PRICES.get(quality, 999999))
