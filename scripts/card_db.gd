class_name CardDB
## 卡牌统一元数据注册表（2026-10-10 引入 · P1）。
##
## 把**道具 / 科技 / 畸变**三张异构数据表的元数据归一成统一的 `CardMeta` 形状，
## 提供跨族查询与一致性自检，便于后续统一管理（编辑器 / 统一图鉴 / 校验）。
##
## **只做加法、渐进迁移**：原三张表（含各自 `def()`）仍是各自系统的唯一真相，
## 本表只是一个**统一只读视图**，不改任何现有消费路径。
##
## **事件族（event）暂不纳入**：现有事件卡设计将在模型统一后整体重做
## （见 `doc/development/plans/卡牌统一元数据模型-P1.md` 与 `未完成项-交接.md`），
## 届时再补 `FAMILY_EVENT` 的归一化条目。
##
## 归一化字段（CardMeta）：
##   id          : String     全局唯一键（各族原键）
##   family      : String     所属卡族（item / tech / aberration）
##   title       : String     显示名（各族均 = id）
##   desc        : String     描述 / 卡面文本
##   category    : String     族内分级：道具 = 品质 / 科技 = 档位 / 畸变 = tag
##   icon        : String     图标键（可能为空）
##   tags        : Array      检索标签（稳定序、去重）
##   implemented : bool       是否已实装
##   raw         : Dictionary  原表条目（系统特有字段；const 表只读，按只读约定使用）

const FAMILY_ITEM := "item"
const FAMILY_TECH := "tech"
const FAMILY_ABERRATION := "aberration"
const FAMILY_EVENT := "event"   # 预留：事件卡重做后接入

## 已接入统一的族（顺序即展示序）。事件族待重做后再加入。
const FAMILIES := [FAMILY_ITEM, FAMILY_TECH, FAMILY_ABERRATION]

## 畸变 tag 的合法取值（`category` 的校验口径，与 `AberrationData` 表一致）。
const ABERR_TAGS := ["debuff", "buff", "中性"]

## 已接入的族清单（副本，防外部改动常量）。
static func families() -> Array:
	return FAMILIES.duplicate()

## 某族的全部条目键（按各族原表顺序）。
static func ids(family: String) -> Array:
	match family:
		FAMILY_ITEM:
			return ItemData.ITEMS.keys()
		FAMILY_TECH:
			return TechData.TECHS.keys()
		FAMILY_ABERRATION:
			return AberrationData.ABERRATIONS.keys()
	return []

static func has(family: String, id: String) -> bool:
	match family:
		FAMILY_ITEM:
			return ItemData.ITEMS.has(id)
		FAMILY_TECH:
			return TechData.TECHS.has(id)
		FAMILY_ABERRATION:
			return AberrationData.ABERRATIONS.has(id)
	return false

## 取某条卡的归一化元数据；未命中返回 `{}`。
static func def(family: String, id: String) -> Dictionary:
	match family:
		FAMILY_ITEM:
			var d: Dictionary = ItemData.ITEMS.get(id, {})
			return _meta_item(id, d) if not d.is_empty() else {}
		FAMILY_TECH:
			var d: Dictionary = TechData.TECHS.get(id, {})
			return _meta_tech(id, d) if not d.is_empty() else {}
		FAMILY_ABERRATION:
			var d: Dictionary = AberrationData.ABERRATIONS.get(id, {})
			return _meta_aberration(id, d) if not d.is_empty() else {}
	return {}

## 某族全部卡的归一化元数据（按原表顺序）。
static func all(family: String) -> Array:
	var out: Array = []
	for id in ids(family):
		out.append(def(family, id))
	return out

## 跨族按 id 定位，返回 `{"family": String, "meta": Dictionary}`；未命中返回 `{}`。
## 各族 id 命名空间独立、目前无重名；若将来重名，按 `FAMILIES` 顺序取首个命中。
static func find(id: String) -> Dictionary:
	for fam in FAMILIES:
		if has(fam, id):
			return {"family": fam, "meta": def(fam, id)}
	return {}

## 一致性自检：返回问题描述列表（空 = 通过）。供单测与后续工具复用。
static func validate() -> Array:
	var problems: Array = []
	var required := ["id", "family", "title", "desc", "category", "icon",
		"tags", "implemented", "raw"]
	for fam in FAMILIES:
		for meta in all(fam):
			var id := String(meta.get("id", ""))
			if id == "":
				problems.append("%s 有条目 id 为空" % fam)
				continue
			for key in required:
				if not meta.has(key):
					problems.append("%s/%s 缺字段 %s" % [fam, id, key])
			if String(meta.get("title", "")) == "":
				problems.append("%s/%s title 为空" % [fam, id])
			if String(meta.get("desc", "")) == "":
				problems.append("%s/%s desc 为空" % [fam, id])
	return problems

# ---------------- 各族归一化 ----------------

static func _meta_item(id: String, d: Dictionary) -> Dictionary:
	var tags: Array = []
	if bool(d.get("unique", false)):
		tags.append("unique")
	if bool(d.get("hidden", false)):
		tags.append("hidden")
	if bool(d.get("bonus", false)):
		tags.append("bonus")
	var tgt := String(d.get("target", ""))
	if tgt != "":
		tags.append("target:" + tgt)
	return {
		"id": id, "family": FAMILY_ITEM, "title": id,
		"desc": String(d.get("desc", "")),
		"category": String(d.get("quality", "")),
		"icon": String(d.get("icon", "")),
		"tags": tags,
		"implemented": bool(d.get("implemented", true)),
		"raw": d,
	}

static func _meta_tech(id: String, d: Dictionary) -> Dictionary:
	return {
		"id": id, "family": FAMILY_TECH, "title": id,
		"desc": String(d.get("desc", "")),
		"category": String(d.get("tier", "")),
		"icon": "",
		"tags": [],
		"implemented": bool(d.get("implemented", true)),
		"raw": d,
	}

static func _meta_aberration(id: String, d: Dictionary) -> Dictionary:
	var tags: Array = []
	var typ := String(d.get("type", ""))
	if typ != "":
		tags.append(typ)
	var trig := String(d.get("trigger", ""))
	if trig != "" and not tags.has(trig):
		tags.append(trig)
	var glyph := ""
	var fam: Dictionary = GameData.CARD_FAMILIES.get("aberr", {})
	glyph = String(fam.get("glyph", ""))
	return {
		"id": id, "family": FAMILY_ABERRATION, "title": id,
		"desc": String(d.get("desc", "")),
		"category": String(d.get("tag", "")),
		"icon": glyph,
		"tags": tags,
		"implemented": bool(d.get("implemented", true)),
		"raw": d,
	}
