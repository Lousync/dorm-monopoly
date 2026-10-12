extends SceneTree
## 卡牌统一元数据注册表（CardDB）单测。
## 跑法：godot --headless --path . --script tests/card_db_test.gd
## 纯数据校验，不加载对局场景。校验口径见
## doc/development/plans/卡牌统一元数据模型-P1.md

var fails := 0

func _initialize() -> void:
	print("== CardDB 统一元数据 ==")

	# 族清单：**四族，机会卡打头**（2026-10-12 接入；顺序即对局内图鉴的分页序）
	_check(CardDB.families() == [CardDB.FAMILY_EVENT, CardDB.FAMILY_ITEM,
			CardDB.FAMILY_TECH, CardDB.FAMILY_ABERRATION],
		"families() 恰为 机会卡/道具/科技/畸变")
	_check(not CardDB.has(CardDB.FAMILY_EVENT, ""), "空 id 不算命中")

	# 数量与源表一致
	_check(CardDB.all(CardDB.FAMILY_EVENT).size() == GameData.EVENTS.size(),
		"机会卡条目数 = GameData.EVENTS（%d）" % GameData.EVENTS.size())
	_check(CardDB.all(CardDB.FAMILY_ITEM).size() == ItemData.ITEMS.size(),
		"道具条目数 = ItemData.ITEMS（%d）" % ItemData.ITEMS.size())
	_check(CardDB.all(CardDB.FAMILY_TECH).size() == TechData.TECHS.size(),
		"科技条目数 = TechData.TECHS（%d）" % TechData.TECHS.size())
	_check(CardDB.all(CardDB.FAMILY_ABERRATION).size() == AberrationData.ABERRATIONS.size(),
		"畸变条目数 = AberrationData.ABERRATIONS（%d）" % AberrationData.ABERRATIONS.size())

	# 逐族：归一化字段完整、category 合法
	_validate_events()
	_validate_items()
	_validate_techs()
	_validate_aberrations()

	# raw 是原表引用、family/title 归一
	var item_ids: Array = ItemData.ITEMS.keys()
	var one: Dictionary = CardDB.def(CardDB.FAMILY_ITEM, String(item_ids[0]))
	_check(not one.is_empty(), "def 命中道具")
	_check(one.raw == ItemData.ITEMS[one.id], "raw 指向原表条目（同一引用）")
	_check(one.family == CardDB.FAMILY_ITEM and one.title == one.id, "道具 family/title 归一")

	# find 跨族定位
	var tech_ids: Array = TechData.TECHS.keys()
	var ab_ids: Array = AberrationData.ABERRATIONS.keys()
	_check(String(CardDB.find(String(item_ids[0])).get("family", "")) == CardDB.FAMILY_ITEM,
		"find 命中道具")
	_check(String(CardDB.find(String(tech_ids[0])).get("family", "")) == CardDB.FAMILY_TECH,
		"find 命中科技")
	_check(String(CardDB.find(String(ab_ids[0])).get("family", "")) == CardDB.FAMILY_ABERRATION,
		"find 命中畸变")
	_check(CardDB.find("不存在的卡").is_empty(), "find 未命中返回空")
	_check(CardDB.def(CardDB.FAMILY_ITEM, "不存在的卡").is_empty(), "def 未命中返回空")

	# 一致性自检
	var problems := CardDB.validate()
	_check(problems.is_empty(), "validate() 无问题")
	for p in problems:
		printerr("    ! ", p)

	_test_family_styles()
	_test_category_accessors()

	if fails == 0:
		print("CARDDB TEST: ALL PASS")
		quit(0)
	else:
		print("CARDDB TEST: %d FAILURES" % fails)
		quit(1)

func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok - ", what)
	else:
		fails += 1
		printerr("  FAIL - ", what)

## 机会卡（2026-10-12 接入）：category 必须是**卡型**（`GameData.card_kind` 的五个取值），
## desc 由效果行拼出来、`rows` 非空且每行都有 k/v —— 这三条一起保证「图鉴上那张卡读得出来」。
func _validate_events() -> void:
	var bad: Array = []
	var kinds: Array = []
	for meta in CardDB.all(CardDB.FAMILY_EVENT):
		if not GameData.CARD_KINDS.has(String(meta.category)):
			bad.append("%s=%s" % [meta.id, meta.category])
		if String(meta.desc) == "":
			bad.append("%s 缺 desc" % meta.id)
		var rows: Array = meta.get("rows", [])
		if rows.is_empty():
			bad.append("%s 无 rows" % meta.id)
		for r in rows:
			if String((r as Dictionary).get("k", "")) == "" or String((r as Dictionary).get("v", "")) == "":
				bad.append("%s 有空行" % meta.id)
		if not kinds.has(String(meta.category)):
			kinds.append(String(meta.category))
	_check(bad.is_empty(), "机会卡 category ∈ CARD_KINDS 且 desc/rows 齐（异常：%s）" % str(bad))
	# 五个卡型都要有人用 —— 只覆盖两三个的话，图鉴的卡型配色等于没验过
	_check(kinds.size() >= 4, "机会卡覆盖 ≥4 种卡型（实得 %d：%s）" % [kinds.size(), str(kinds)])
	# 卡名当 id：跨族与族内都不许重名（`CardDB.find` 按族序取首个命中，重名会静默取错）
	var seen := {}
	var dup: Array = []
	for fam in CardDB.FAMILIES:
		for id in CardDB.ids(fam):
			var key := String(id)
			if seen.has(key):
				dup.append(key)
			seen[key] = fam
	_check(dup.is_empty(), "四族卡名全局唯一（重复：%s）" % str(dup))
	# 香皂那一行是**免疫口径**、不是效果 ⇒ 按字段推出的结论要自洽。
	# **按字段找卡、不写死卡名**：机会卡的"标题"是「卡名——风味文案」一整句
	#（`t` 就是玩家在大字卡上看到的那行字），写死进测试会跟着文案改动一起烂。
	var to_each_id := ""
	var pure_id := ""
	for id in CardDB.ids(CardDB.FAMILY_EVENT):
		var raw: Dictionary = CardDB.def(CardDB.FAMILY_EVENT, String(id)).raw
		if to_each_id == "" and raw.has("to_each"):
			to_each_id = String(id)
		if pure_id == "" and raw.has("money") and int(raw.money) > 0 and not raw.has("choices"):
			pure_id = String(id)
	_check(to_each_id != "" and CardDB.event_soap(to_each_id).contains("你持皂则整条免疫"),
		"请客类卡：抽卡者持皂整条免疫（口径照 机会卡.md §四）")
	_check(pure_id != "" and CardDB.event_soap(pure_id).contains("不受影响"),
		"纯收益卡：香皂不受影响")
	var rows: Array = CardDB.event_rows(pure_id)
	_check(rows.size() >= 2 and String((rows[rows.size() - 1] as Dictionary).k) == "香皂",
		"效果行末尾恒有「香皂」一行")
	_check(String(rows[0].k) == "金额", "效果行按结算顺序排（金额打头，机会卡.md §三）")

func _validate_items() -> void:
	var bad: Array = []
	for meta in CardDB.all(CardDB.FAMILY_ITEM):
		if not ItemData.QUALITIES.has(String(meta.category)):
			bad.append("%s=%s" % [meta.id, meta.category])
		if String(meta.desc) == "":
			bad.append("%s 缺 desc" % meta.id)
	_check(bad.is_empty(), "道具 category ∈ QUALITIES 且 desc 非空（异常：%s）" % str(bad))

func _validate_techs() -> void:
	var bad: Array = []
	for meta in CardDB.all(CardDB.FAMILY_TECH):
		if not TechData.TIERS.has(String(meta.category)):
			bad.append("%s=%s" % [meta.id, meta.category])
		if String(meta.desc) == "":
			bad.append("%s 缺 desc" % meta.id)
	_check(bad.is_empty(), "科技 category ∈ TIERS 且 desc 非空（异常：%s）" % str(bad))

func _validate_aberrations() -> void:
	var bad: Array = []
	for meta in CardDB.all(CardDB.FAMILY_ABERRATION):
		if not CardDB.ABERR_TAGS.has(String(meta.category)):
			bad.append("%s=%s" % [meta.id, meta.category])
		if String(meta.desc) == "":
			bad.append("%s 缺 desc" % meta.id)
	_check(bad.is_empty(), "畸变 category ∈ ABERR_TAGS 且 desc 非空（异常：%s）" % str(bad))

func _test_family_styles() -> void:
	# 家族样式（2026-10-10 从 GameData.CARD_FAMILIES 迁入）：三族表结构同形
	var fields := ["bg", "edge", "tex", "tint", "glyph"]
	for famkey in ["chance", "item", "aberr"]:
		var ok := CardDB.FAMILY_STYLES.has(famkey)
		_check(ok, "FAMILY_STYLES 含家族 %s" % famkey)
		if ok:
			for f in fields:
				_check((CardDB.FAMILY_STYLES[famkey] as Dictionary).has(f),
					"家族 %s 有字段 %s" % [famkey, f])
	_check(CardDB.family_style("chance") == CardDB.FAMILY_STYLES["chance"], "family_style 取到家族样式")
	_check(CardDB.family_style("不存在").is_empty(), "family_style 未命中返回空")
	_check(CardDB.family_styles().size() == 3, "family_styles 恰三族")

func _test_category_accessors() -> void:
	# 分级配色 / 展示名：道具取品质、科技取档位、畸变取 tag
	_check(CardDB.category_color(CardDB.FAMILY_ITEM, "金") == ItemData.QUALITY_COLORS["金"],
		"道具分级色 = ItemData.QUALITY_COLORS")
	_check(CardDB.category_label(CardDB.FAMILY_ITEM, "金") == String(ItemData.QUALITY_NAMES["金"]),
		"道具分级名 = ItemData.QUALITY_NAMES")
	_check(CardDB.category_color(CardDB.FAMILY_TECH, TechData.TIER_GOLD) \
		== TechData.tier_color(TechData.TIER_GOLD), "科技分级色 = TechData.tier_color")
	_check(CardDB.category_color(CardDB.FAMILY_ABERRATION, "debuff") == CardDB.TAG_COLORS["debuff"],
		"畸变分级色 = CardDB.TAG_COLORS")
	_check(CardDB.category_label(CardDB.FAMILY_ABERRATION, "debuff") == "负面",
		"畸变分级名 = TAG_LABELS 中文")
	# 机会卡的分级 = **卡型**，色与名都从 `GameData.CARD_KINDS` 取（演出大字卡读同一张表）
	_check(CardDB.category_color(CardDB.FAMILY_EVENT, "bad") == GameData.CARD_KINDS["bad"].color,
		"机会卡分级色 = GameData.CARD_KINDS")
	_check(CardDB.category_label(CardDB.FAMILY_EVENT, "bad") == String(GameData.CARD_KINDS["bad"].label),
		"机会卡分级名 = CARD_KINDS 的 label")
	_check(CardDB.category_color(CardDB.FAMILY_EVENT, "不存在") == Color.WHITE
			and CardDB.category_label(CardDB.FAMILY_EVENT, "不存在") == "不存在",
		"未知卡型不炸（色给白、名回原样）")
	# 图标统一入口
	if not item_ids_cache().is_empty():
		var iid := String(item_ids_cache()[0])
		_check(CardDB.icon(CardDB.FAMILY_ITEM, iid) == String(ItemData.ITEMS[iid].get("icon", "")),
			"icon 与源表一致")
		_check(CardDB.icon(CardDB.FAMILY_ABERRATION, String(AberrationData.ABERRATIONS.keys()[0])) \
			== String(CardDB.FAMILY_STYLES["aberr"]["glyph"]), "畸变 icon = 家族 glyph")

func item_ids_cache() -> Array:
	return ItemData.ITEMS.keys()
