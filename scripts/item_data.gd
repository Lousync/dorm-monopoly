class_name ItemData
## 道具系统数据总表（唯一台账：docs/道具系统设计.md）
## implemented=false 的道具不进货架池，效果随批次解锁

const QUALITIES := ["白", "绿", "蓝", "紫", "橙"]
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
const ITEM_TIMEOUT := 12.0  # 道具阶段发呆兜底

const ITEMS := {
	"平均主义": {"quality": "紫", "cost": 5, "type": "active", "unique": false, "cooldown": 5,
		"desc": "全体存活玩家现金同步至平均值，精确分摊、总现金守恒", "implemented": true},
	"作弊器": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "选定下一次转轮的点数（0~12），转轮照常按规则结算", "implemented": true},
	"交换生": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "指定一名玩家，其道具栏随机一件与本道具互换", "implemented": false},
	"招财猫": {"quality": "白", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "持有期间：每块地皮租金收入 +50", "implemented": true},
	"信托基金": {"quality": "绿", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "每个自己回合开始时 +¥100（休眠照发）", "implemented": true},
	"黑卡": {"quality": "橙", "cost": 4, "type": "active", "unique": true, "cooldown": 4,
		"desc": "接下来 3 次购买免费（黑市刷新与出口费照旧）", "implemented": false},
	"空想者的香皂": {"quality": "橙", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "免疫一切带 debuff 标签的效果；持有 10 回合后融化回池", "implemented": false},
	"蛋蛋节": {"quality": "橙", "cost": 1, "type": "consumable", "unique": true, "cooldown": 1,
		"desc": "全员送礼：他人白/绿/蓝随机，自己紫70%/橙30%；满包改发 ¥100；用后焚毁", "implemented": false},
	"亡牌飞行员coco": {"quality": "橙", "cost": 3, "type": "consumable", "unique": true, "cooldown": 3,
		"desc": "每名玩家随机一块地皮被摧毁化作焦土；用后焚毁", "implemented": false},
	"园中叶": {"quality": "橙", "cost": 0, "type": "active", "unique": true, "cooldown": 0,
		"desc": "效果未定，预留位置", "implemented": false},
}

static func def(id: String) -> Dictionary:
	return ITEMS.get(id, {})

static func price(quality: String) -> int:
	return int(QUALITY_PRICES.get(quality, 999999))
