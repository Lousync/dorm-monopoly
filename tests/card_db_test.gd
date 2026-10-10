extends SceneTree
## 卡牌统一元数据注册表（CardDB）单测。
## 跑法：godot --headless --path . --script tests/card_db_test.gd
## 纯数据校验，不加载对局场景。校验口径见
## doc/development/plans/卡牌统一元数据模型-P1.md

var fails := 0

func _initialize() -> void:
	print("== CardDB 统一元数据 ==")

	# 族清单：事件族本批未接入
	_check(CardDB.families() == [CardDB.FAMILY_ITEM, CardDB.FAMILY_TECH, CardDB.FAMILY_ABERRATION],
		"families() 恰为 道具/科技/畸变（事件族未接入）")
	_check(not CardDB.has(CardDB.FAMILY_EVENT, ""), "事件族未接入（FAMILY_EVENT 无条目）")

	# 数量与源表一致
	_check(CardDB.all(CardDB.FAMILY_ITEM).size() == ItemData.ITEMS.size(),
		"道具条目数 = ItemData.ITEMS（%d）" % ItemData.ITEMS.size())
	_check(CardDB.all(CardDB.FAMILY_TECH).size() == TechData.TECHS.size(),
		"科技条目数 = TechData.TECHS（%d）" % TechData.TECHS.size())
	_check(CardDB.all(CardDB.FAMILY_ABERRATION).size() == AberrationData.ABERRATIONS.size(),
		"畸变条目数 = AberrationData.ABERRATIONS（%d）" % AberrationData.ABERRATIONS.size())

	# 逐族：归一化字段完整、category 合法
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
	# 图标统一入口
	if not item_ids_cache().is_empty():
		var iid := String(item_ids_cache()[0])
		_check(CardDB.icon(CardDB.FAMILY_ITEM, iid) == String(ItemData.ITEMS[iid].get("icon", "")),
			"icon 与源表一致")
		_check(CardDB.icon(CardDB.FAMILY_ABERRATION, String(AberrationData.ABERRATIONS.keys()[0])) \
			== String(CardDB.FAMILY_STYLES["aberr"]["glyph"]), "畸变 icon = 家族 glyph")

func item_ids_cache() -> Array:
	return ItemData.ITEMS.keys()
