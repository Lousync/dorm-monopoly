class_name CardDB
## 卡牌统一元数据注册表（2026-10-10 引入 · P1）。
##
## 把**道具 / 科技 / 畸变 / 机会卡**四张异构数据表的元数据归一成统一的 `CardMeta` 形状，
## 提供跨族查询与一致性自检，便于后续统一管理（编辑器 / 统一图鉴 / 校验）。
##
## **只做加法、渐进迁移**：原四张表（含各自 `def()`）仍是各自系统的唯一真相，
## 本表只是一个**统一只读视图**，不改任何现有消费路径。
##
## **事件族（event）2026-10-12 接入**（原「暂不纳入」）：接的是 `GameData.EVENTS` 的
## **现表**、只读 —— 不是 `未完成项-交接.md` ㊸ 说的那场「删表重做」，那件事仍然待办。
## 接入的动因是**对局内图鉴要能查机会卡**：原先只有 `tools/gen_gallery.gd` 会摊这张表
##（产出 `doc/game-design/图鉴.html`），而那张网页 2026-10-12 已随"图鉴改为游戏内唯一入口"
## 删除 ⇒ 摊字段的那套口径（`机会卡.md` §三 结算顺序 / §四 免疫点）搬到这里，成为唯一落点。
##
## 归一化字段（CardMeta）：
##   id          : String     全局唯一键（各族原键；**机会卡没有 id 字段，用卡名 `t`**）
##   family      : String     所属卡族（item / tech / aberration / event）
##   title       : String     显示名（各族均 = id）
##   desc        : String     描述 / 卡面文本
##   category    : String     族内分级：道具 = 品质 / 科技 = 档位 / 畸变 = tag
##   icon        : String     图标键（可能为空）
##   tags        : Array      检索标签（稳定序、去重）
##   implemented : bool       是否已实装
##   raw         : Dictionary  原表条目（系统特有字段；const 表只读，按只读约定使用）
##   rows        : Array       **只有机会卡有**：效果逐字段摊平后的 `[{k, v}]`（图鉴逐行渲染用；
##                             `desc` 是它的单行拼版，供搜索与兜底显示）

const FAMILY_ITEM := "item"
const FAMILY_TECH := "tech"
const FAMILY_ABERRATION := "aberration"
const FAMILY_EVENT := "event"   # 机会卡（2026-10-12 接入；`GameData.EVENTS` 的只读视图）

## 已接入统一的族（**顺序即展示序**：对局内图鉴的分页也照它排）。
## 机会卡排第一 —— 与被删的那张网页（`图鉴.html` 的「事件卡」节）同序。
const FAMILIES := [FAMILY_EVENT, FAMILY_ITEM, FAMILY_TECH, FAMILY_ABERRATION]

## 畸变 tag 的合法取值（`category` 的校验口径，与 `AberrationData` 表一致）。
const ABERR_TAGS := ["debuff", "buff", "中性"]

## ---- 家族三色（卡背 / 正面外框 / 标题 / 光晕 / 家族徽章）----------------------------
## 2026-10-10 由 `GameData.CARD_FAMILIES` **原样迁入**（卡牌统一元数据模型 P2）——
## 这是「卡面家族展示」的唯一来源：`DeckReveal` 的卡背 / 正面、图鉴生成器（`--script` 跑）都读它。
##	键     = 家族键（chance / item / aberr），由 `DeckReveal.show_card()` 显式派生
##	bg    卡背底色；edge 描边 + 光晕 + 标题；tex 牌背 SVG；tint 底纹色调；glyph 家族徽章图标
## ⚠ 本表**不许引 `UIKit.*`**：`UIKit` 是 autoload，`--script`（图鉴生成器）不能 import 它；
##    `chance` 的 edge 与 `UIKit.ACCENT` 同值但各写一份，靠 `tests/chance_test.gd` 钉住"同值"。
## ⚠ `item` 族的 `glyph` 是**预留**：今天没有任何绘制路径会读它（道具卡正面是共用件 `ItemCard`、
##    家族身份只由卡背承担），保留它是为让三族**表结构同形**（`chance_test` 也钉着"三族字段齐"）。
const FAMILY_STYLES := {
	"chance": {
		"bg": Color(0.075, 0.068, 0.045),
		"edge": Color(0.961, 0.702, 0.259),
		"tex": "res://assets/cards/atlas_back_green_darkred.svg",
		"tint": Color(1.0, 0.86, 0.55, 0.30),
		"glyph": "🎲",
	},
	"item": {
		"bg": Color(0.045, 0.062, 0.092),
		"edge": Color(0.42, 0.70, 0.95),
		"tex": "res://assets/cards/atlas_back_blue_brown.svg",
		"tint": Color(0.78, 0.72, 1.0, 0.30),
		"glyph": "📦",   # 预留：无绘制路径读它（道具族不画家族徽章），仅保持三族表结构同形
	},
	"aberr": {
		"bg": Color(0.070, 0.048, 0.105),
		"edge": Color(0.79, 0.65, 1.0),
		# 复用蓝那张：三色里只有机会、道具各有一张现成 SVG，**不新增素材**（AGENTS.md §四 的
		# "能用程序化手段画出来的就别加素材"）。畸变的紫靠底色 + 描边 + 光晕 + 底纹色调做出来。
		"tex": "res://assets/cards/atlas_back_blue_brown.svg",
		"tint": Color(0.82, 0.70, 1.0, 0.34),
		"glyph": "🌀",
	},
}

## 畸变 tag → 展示名 / 展示色（2026-10-10 从当时的图鉴生成器迁入，成为唯一来源；
## 那个生成器 2026-10-12 已随 `图鉴.html` 删除，本节是它留下的那份口径）。
## 畸变没有其它分级色，这里就是它 `category` 的配色口径。
const TAG_LABELS := {"debuff": "负面", "buff": "正面", "中性": "中性"}
const TAG_COLORS := {
	"debuff": Color(0.941, 0.545, 0.478),   # 原 #f08b7a
	"buff": Color(0.490, 0.863, 0.608),     # 原 #7ddc9b
	"中性": Color(0.624, 0.702, 0.753),      # 原 #9fb3c0
}
const TAG_COLOR_FALLBACK := Color(0.624, 0.702, 0.753)

## 已接入的族清单（副本，防外部改动常量）。
static func families() -> Array:
	return FAMILIES.duplicate()

## 家族展示样式（卡背/外框/光晕/徽章）。未命中返回 `{}`。
static func family_style(family: String) -> Dictionary:
	return FAMILY_STYLES.get(family, {})

static func family_styles() -> Dictionary:
	return FAMILY_STYLES

## 某族的**族内分级配色**：道具 = 品质色 / 科技 = 档位色 / 畸变 = tag 色。
## 这是"统一取分级色"的入口；背后的品质/档位色表仍住各自数据类（渐进迁移，不搬迁）。
static func category_color(family: String, category: String) -> Color:
	match family:
		FAMILY_ITEM:
			return ItemData.QUALITY_COLORS.get(category, Color.WHITE)
		FAMILY_TECH:
			return TechData.tier_color(category)
		FAMILY_ABERRATION:
			return TAG_COLORS.get(category, TAG_COLOR_FALLBACK)
		FAMILY_EVENT:
			# 机会卡的分级 = **卡型**（收益 / 损失 / 移动 / 查寝 / 其他），色表仍是
			# `GameData.CARD_KINDS`（演出大字卡读同一张，别在这儿另立一份 hex）。
			return (GameData.CARD_KINDS.get(category, {}) as Dictionary).get("color", Color.WHITE)
	return Color.WHITE

## 某族**族内分级展示名**：道具 = 品质中文 / 畸变 = tag 中文 / 机会卡 = 卡型中文 /
## 科技 = 档位名（无别名）。
static func category_label(family: String, category: String) -> String:
	match family:
		FAMILY_ITEM:
			return String(ItemData.QUALITY_NAMES.get(category, category))
		FAMILY_ABERRATION:
			return String(TAG_LABELS.get(category, category))
		FAMILY_EVENT:
			return String((GameData.CARD_KINDS.get(category, {}) as Dictionary).get("label", category))
	return category

## 某条卡的图标键（可能为空；图标来源统一走这里）。
static func icon(family: String, id: String) -> String:
	return String(def(family, id).get("icon", ""))

## 某族的全部条目键（按各族原表顺序）。
static func ids(family: String) -> Array:
	match family:
		FAMILY_ITEM:
			return ItemData.ITEMS.keys()
		FAMILY_TECH:
			return TechData.TECHS.keys()
		FAMILY_ABERRATION:
			return AberrationData.ABERRATIONS.keys()
		FAMILY_EVENT:
			# 机会卡表是**数组**、条目没有 id 字段（`GameData.EVENTS` 的键名是 `t`）
			# ⇒ 卡名即 id。50 张卡名与其它三族零重名、卡名之间也零重名（`card_db_test` 钉着）。
			var out: Array = []
			for c in GameData.EVENTS:
				out.append(String((c as Dictionary).get("t", "")))
			return out
	return []

static func has(family: String, id: String) -> bool:
	match family:
		FAMILY_ITEM:
			return ItemData.ITEMS.has(id)
		FAMILY_TECH:
			return TechData.TECHS.has(id)
		FAMILY_ABERRATION:
			return AberrationData.ABERRATIONS.has(id)
		FAMILY_EVENT:
			return not event_def(id).is_empty()
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
		FAMILY_EVENT:
			var e := event_def(id)
			return _meta_event(id, e) if not e.is_empty() else {}
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
	var fam: Dictionary = FAMILY_STYLES.get("aberr", {})
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

# ---------------- 机会卡（`GameData.EVENTS` 的只读视图） ----------------
#
# 这一节**整体搬自 `tools/gen_gallery.gd`**（2026-10-12 该生成器随 `图鉴.html` 一起删除）。
# 搬的是**口径**、不是排版：那是「机会卡.md §三 结算顺序 / §四 免疫点」在代码里的唯一一份实现，
# 网页没了它就没落点了。**改字段就回来改这里** —— 另写一份必然与这里漂开。
#
# 与网页版的唯一差别：**去掉 Markdown 的 `**粗体**` 标记**（原来那页会渲染，图鉴用的是普通
# Label、星号会照原样显示出来）。

## 按卡名取机会卡原始条目（`GameData.EVENTS` 是**数组**、条目没有 id 字段，键名是 `t`）。
## 未命中返回 `{}`。线性扫 50 条 —— 只在切页 / 搜索时跑，不值得再养一份索引。
static func event_def(id: String) -> Dictionary:
	for c in GameData.EVENTS:
		var card := c as Dictionary
		if String(card.get("t", "")) == id:
			return card
	return {}

## 机会卡的效果行（逐字段摊平 + 末尾一行「香皂」）。**顺序照 `机会卡.md` §三 的结算顺序**：
## 一张多效果卡在界面上读起来与结算顺序一致。
static func event_rows(id: String) -> Array:
	var card := event_def(id)
	if card.is_empty():
		return []
	var rows := _event_effect_rows(card)
	rows.append({"k": "香皂", "v": event_soap(id)})
	return rows

## 机会卡的描述文本 = 效果行的单行拼版。用途有二：图鉴的**搜索词**命中它、
## `CardMeta.desc` 的兜底显示（`validate()` 也要求 desc 非空）。
static func event_desc_text(id: String) -> String:
	var parts := PackedStringArray()
	for r in event_rows(id):
		parts.append("%s %s" % [String((r as Dictionary).get("k", "")), String((r as Dictionary).get("v", ""))])
	return "；".join(parts)

## 逐字段把效果摊成「键 / 值」行，顺序照 `机会卡.md` §三：
## 钱 → 传送 → 智斗字段（目标类 → 地皮与位置类 → 抉择与情报类）→ 移动 → 得道具 → 进店。
static func _event_effect_rows(card: Dictionary) -> Array:
	var rows: Array = []
	if card.has("money"):
		var m := int(card.money)
		rows.append({"k": "金额", "v": ("+¥%d（进账）" if m >= 0 else "−¥%d（扣款）") % absi(m)})
	if card.has("from_each"):
		rows.append({"k": "室友给钱", "v": "每位其他存活玩家给你 ¥%d" % int(card.from_each)})
	if card.has("to_each"):
		rows.append({"k": "请客", "v": "你给每位其他存活玩家 ¥%d" % int(card.to_each)})
	if card.has("go_jail"):
		rows.append({"k": "传送", "v": "直接前往宿委会（下一回合跳过）"})
	if card.has("steal_from"):
		rows.append({"k": "夺取", "v": "从选定目标处夺取 ¥%d" % int(card.steal_from)})
	if card.has("charge_to"):
		rows.append({"k": "索取", "v": "向选定目标收取 ¥%d" % int(card.charge_to)})
	if card.has("each_from_target"):
		rows.append({"k": "请客", "v": "选定目标给每位其他存活玩家 ¥%d（收钱方含抽卡者本人）" % int(card.each_from_target)})
	if card.has("steal_item_from"):
		rows.append({"k": "抢道具", "v": "从选定目标随机夺一件道具"})
	if card.has("jail_to"):
		rows.append({"k": "送回宿委会", "v": "选定目标跳过下一回合"})
	if card.has("seize_tile"):
		rows.append({"k": "夺地", "v": "夺走目标投入最少的一块地" if String(card.seize_tile) == "take"
			else "与目标各随机一块地互换"})
	if card.has("force_buy_tile"):
		rows.append({"k": "强买", "v": "以原价 %d%% 强买目标投入最少的一块地" % int(card.force_buy_tile)})
	if card.has("swap_pos"):
		rows.append({"k": "换位", "v": "与选定目标交换棋子位置（不结算落点）"})
	if card.has("pull_target"):
		rows.append({"k": "拉人", "v": "把选定目标拉到你当前格（照常结算落点）"})
	if card.has("push_back"):
		rows.append({"k": "推退", "v": "选定目标后退 %d 格（照常结算落点）" % int(card.push_back)})
	if card.has("shuffle_pos"):
		rows.append({"k": "洗位", "v": "全场玩家位置随机重排"})
	if card.has("choices"):
		# `String.join` 吃 PackedStringArray、**不吃 Array** ⇒ 先中转一道（本仓已踩过）。
		var labels := PackedStringArray()
		for o in (card.choices as Array):
			labels.append(String((o as Dictionary).get("t", "?")))
		rows.append({"k": "抉择", "v": " / ".join(labels)})
	if card.has("peek_deck"):
		rows.append({"k": "情报", "v": "私密偷看机会牌堆顶 %d 张" % int(card.peek_deck)})
	if card.has("shuffle_deck"):
		rows.append({"k": "情报", "v": "重洗机会牌堆"})
	if card.has("bury_deck"):
		rows.append({"k": "情报", "v": "把牌堆顶一张塞到底部"})
	if card.has("move_steps"):
		var n := int(card.move_steps)
		rows.append({"k": "移动", "v": ("前进 %d 格" if n >= 0 else "后退 %d 格") % absi(n)})
	if card.has("gain_item"):
		rows.append({"k": "得道具", "v": "获得「%s」（背包满作废）" % String(card.gain_item)})
	if card.has("gain_item_quality"):
		rows.append({"k": "得道具", "v": "随机获得一件「%s」档道具（唯一池过滤；缺货 / 满包作废）"
			% String(card.gain_item_quality)})
	if card.has("enter_shop"):
		rows.append({"k": "进店", "v": "进入一家随机小卖部"})
	if card.has("enter_blackshop"):
		rows.append({"k": "进店", "v": "进入黑市"})
	return rows

## 香皂（免疫标签）对这张卡意味着什么 —— 口径照 `机会卡.md` §四「免疫点」，
## **由字段推出、不从文档抄**：那三条规则是完备的，抄一份就多一个会烂的地方。
## 收益 / 中性卡也**照出一行**「不受影响」：查的人问的就是「这张卡香皂管不管」，
## 空着等于没回答。
static func event_soap(id: String) -> String:
	var card := event_def(id)
	if card.is_empty():
		return ""
	var notes: Array[String] = []
	if card.has("from_each"):
		notes.append("对每名室友逐个判定（持皂的那位不用给）")
	if card.has("money") and int(card.money) < 0:
		notes.append("扣款可免疫")
	if card.has("to_each"):
		notes.append("你持皂则整条免疫")
	if card.has("go_jail"):
		notes.append("可免疫")
	if card.has("move_steps") and int(card.move_steps) < 0:
		notes.append("倒退可免疫")
	# 目标类那 8 个都是 debuff ⇒ **目标**持皂则整条免疫（判的是目标那一方，不是抽卡者）；
	# 其余（互换 / 换位 / 洗位 / 情报）是中性 ⇒ 香皂无效，落到下面那句兜底里。
	var target_debuff := ["steal_from", "charge_to", "each_from_target", "steal_item_from",
		"jail_to", "force_buy_tile", "pull_target", "push_back"]
	for f in target_debuff:
		if card.has(f):
			notes.append("目标持皂则整条免疫")
			break
	# 「雨伞」只挡**后退类**移动（同 `move_steps < 0` 那一处）：`push_back` 另加一道，
	# `pull_target` 是**拉**不是**推**、雨伞不管它（口径照 `机会卡.md` §四「免疫点」表）。
	if card.has("push_back"):
		notes.append("目标持伞也免疫（后退类）")
	if card.has("seize_tile"):
		notes.append("夺地：目标持皂则整条免疫" if String(card.seize_tile) == "take" else "互换：中性，香皂无效")
	# 抉择卡没有自己的效果：免不免疫要看**最终选中哪一支**（各支走同一套字段判定）。
	if card.has("choices"):
		notes.append("按所选分支逐项判定")
	if notes.is_empty():
		return "不受影响（收益 / 中性）"
	return "；".join(notes)

static func _meta_event(id: String, card: Dictionary) -> Dictionary:
	var kind := GameData.card_kind(card)
	var fam: Dictionary = GameData.CARD_KINDS.get(kind, {})
	return {
		"id": id, "family": FAMILY_EVENT, "title": id,
		"desc": event_desc_text(id),
		"category": kind,
		"icon": String(fam.get("glyph", "")),
		"tags": [kind],
		"implemented": true,
		"raw": card,
		"rows": event_rows(id),
	}
