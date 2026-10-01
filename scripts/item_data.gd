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
const ITEM_TIMEOUT := 12.0  # 道具阶段发呆兜底

const ITEMS := {
	"平均主义": {"quality": "紫", "cost": 5, "type": "active", "unique": false, "cooldown": 5,
		"desc": "全体存活玩家现金同步至平均值，精确分摊、总现金守恒。", "implemented": true},
	"作弊器": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "下一次转轮点数由自己选定（0~12），转轮动画照常；选定值按正常规则结算——12 照样额外回合、连续高压照样进监、0 照样待命。", "implemented": true},
	"交换生": {"quality": "蓝", "cost": 3, "type": "active", "unique": false, "cooldown": 3,
		"desc": "指定一名玩家，其道具栏随机一件与本道具互换；冷却随实例走。目标无道具则不可指定（不消耗）。", "implemented": false},
	"招财猫": {"quality": "白", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "本玩家每块地皮租金收入 +50。", "implemented": true},
	"信托基金": {"quality": "绿", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "每个自己回合开始时 +¥100（休眠回合照发）。", "implemented": true},
	"黑卡": {"quality": "橙", "cost": 4, "type": "active", "unique": true, "cooldown": 4,
		"desc": "接下来 3 次购买免费，每次购买耗 1 次（买地皮的橙货也算 1 次）；只免购买对价（小卖部免现金、黑市免地皮），黑市刷新与出口费照旧。", "implemented": false},
	"空想者的香皂": {"quality": "橙", "cost": -1, "type": "passive", "unique": true, "cooldown": 0,
		"desc": "免疫一切 debuff 标签效果；10 回合后融化自动丢弃（回池，他人拾取重新计 10 回合）。", "implemented": false},
	"蛋蛋节": {"quality": "橙", "cost": 1, "type": "consumable", "unique": true, "cooldown": 1,
		"desc": "全员送礼：其余玩家各随机 1 件白/绿/蓝（三档均分），使用者紫 70% / 橙 30%；礼物从当前可获取池随机（排除已被持有的唯一道具）；满包玩家改发 ¥100 现金；用后焚毁不回池。", "implemented": false},
	"亡牌飞行员coco": {"quality": "橙", "cost": 3, "type": "consumable", "unique": true, "cooldown": 3,
		"desc": "每名玩家（含使用者）各自随机一块地皮被摧毁（无地皮跳过；每个受害者独立 debuff 判定，可被香皂免疫）；地皮化作焦土；用后焚毁不回池。", "implemented": false},
	"园中叶": {"quality": "橙", "cost": 0, "type": "active", "unique": true, "cooldown": 0,
		"desc": "效果未定，预留位置。", "implemented": false},
}

static func def(id: String) -> Dictionary:
	return ITEMS.get(id, {})

static func price(quality: String) -> int:
	return int(QUALITY_PRICES.get(quality, 999999))
