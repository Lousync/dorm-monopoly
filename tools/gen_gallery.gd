extends SceneTree
## 图鉴页生成器：把四个玩法数据表和 `道具图鉴.md` 的 prose 合成一张自包含的 HTML 页。
##
##	godot --headless --path . --script tools/gen_gallery.gd
##
## 产物 `doc/game-design/图鉴.html`（**提交进 git，但别手改** —— 改了会被下次生成覆盖）。
## CI 里有一道闸：重新生成后 `git diff --exit-code`，不一致即红（`.github/workflows/ci.yml`）。
##
## 为什么生成、而不是手写：全表约 180 条，手抄一遍必然与代码分叉；而这页是给团队查的，
## 悄悄写错的参考手册比没有更糟。**数据一律从活的 Godot 类里读**（`GameData` / `ItemData` /
## `TechData` / `AberrationData` 都是纯 `class_name` 数据类、不依赖 autoload，
## `--script` 模式下能直接用）——所以这里**不解析 GDScript**，只解析那份 Markdown。
##
## 两条口径：
## 1. **数值以代码为准**；`道具图鉴.md` 只补「效果 / 免疫 / 联动」这类代码里没有的 prose。
## 2. 对不上的地方**自己叫**（`warnings`）：代码有文档没写、文档有代码没写、卡面文案不一致。
##    别靠人记 —— 这三条正是这页会烂掉的方式。
##
## ⚠ **产物里不许出现生成时间戳**（或任何每次跑都不同的东西）：否则 CI 那道
## `git diff --exit-code` 每次都会红，闸门等于没有。Dictionary 在 GDScript 里保插入序、
## 数组保序，所以产物是确定性的。

const TPL_PATH := "res://tools/gallery_template.html"
const OUT_PATH := "res://doc/game-design/图鉴.html"
const DOC_ITEMS := "res://doc/game-design/道具图鉴.md"
const MARK := "__GALLERY_DATA__"

## 图鉴页里图标是**相对产物**的路径（产物在 `doc/game-design/`，往上两层才是仓库根）
const ICON_PREFIX := "../../assets/icons/"

## 数据来源（页面上原样列出）
const SOURCES := [
	"scripts/game_data.gd", "scripts/item_data.gd",
	"scripts/tech_data.gd", "scripts/aberration_data.gd",
	"doc/game-design/道具图鉴.md",
]

const QUALITY_CHARS := "白绿蓝紫橙"

## `GameData.card_kind()` 的五个卡型 → 中文 / 配色 / 图案（配色与抽卡演出的
## `s_card.rpc(..., kind, ...)` 同一套语义，见 事件卡.md §三）
const KIND_LABEL := {"good": "收益", "bad": "损失", "move": "移动", "jail": "查寝", "info": "其他"}
const KIND_COLOR := {"good": "#7ddc9b", "bad": "#f08b7a", "move": "#7cc4f0", "jail": "#f0c064", "info": "#9fb3c0"}
const KIND_GLYPH := {"good": "💰", "bad": "💸", "move": "🚶", "jail": "🚨", "info": "ℹ️"}

const TYPE_LABEL := {"consumable": "一次性", "active": "主动", "passive": "被动"}
const TARGET_LABEL := {"player": "选一名玩家", "tile": "选地图上一格", "own_tile": "选自己名下的一块地皮"}
const THEN_LABEL := {"own_prop": "；再点他名下的一块地皮", "swap_both": "；双方各选一块互换"}

const TAG_LABEL := {"debuff": "负面", "buff": "正面", "中性": "中性"}
const TAG_COLOR := {"debuff": "#f08b7a", "buff": "#7ddc9b", "中性": "#9fb3c0"}
const TIER_GLYPH := {"白银": "🥈", "黄金": "🥇", "钻石": "💎"}

## 畸变里那几个数值是 `AberrationData` 的 static 占位量（待数值专场回填）——
## 读常量、不抄数，文案后面统一标「占位」。
const AB_PLACEHOLDER := "（占位，待数值专场）"

## `道具图鉴.md` 里**与代码同义**的 bullet：代码字段已经能更准地说出同一件事，
## 留着就是两个来源（且迟早对不上）。`卡面文案` 另作对账用，见 `_merge_face()`。
const DOC_SYNONYM_KEYS := ["选目标"]

var _warnings: Array[String] = []


func _initialize() -> void:
	var doc := _parse_item_doc()
	var sections: Array = [
		_section("cards", "事件卡", _entries_cards()),
		_section("items", "道具", _entries_items(doc)),
		_section("techs", "开局科技", _entries_techs()),
		_section("aberrations", "畸变", _entries_aberrations()),
	]
	_report_doc_gaps(doc)   # 缺项要在 entries 之后再补，见函数注释
	var total := 0
	for s in sections:
		total += (s.entries as Array).size()
	_write(sections, total)
	print("GALLERY: %d 条（%s）" % [total, ", ".join(sections.map(
		func(s: Dictionary) -> String: return "%s %d" % [s.title, (s.entries as Array).size()]))])
	if _warnings.is_empty():
		print("GALLERY: 代码与文档一致，无缺项")
	else:
		printerr("GALLERY: %d 条代码/文档不一致（已写进页面顶部警示）:" % _warnings.size())
		for w in _warnings:
			printerr("  - ", w)
	quit(0)


# ---------------------------------------------------------------- 事件卡

func _entries_cards() -> Array:
	var out: Array = []
	for card in GameData.EVENTS:
		var kind := GameData.card_kind(card)
		var rows := _card_rows(card)
		var soap := _card_soap(card)
		if not soap.is_empty():
			rows.append({"k": "香皂", "v": soap})
		out.append({
			"title": String(card.t),
			# 副标题只写「chips 没说的事」：牌堆归属 chip 已经写了，这里补的是它**什么意思**
			"subtitle": "只在「机会」格出现" if card.has("only") else "机会 / 命运两副牌堆都会抽到",
			"glyph": KIND_GLYPH.get(kind, "·"),
			"accent": KIND_COLOR.get(kind, "#4a5b66"),
			"chips": [
				{"t": deck_of(card)},
				{"t": KIND_LABEL.get(kind, kind), "color": KIND_COLOR.get(kind, "")},
			],
			"facets": {"牌堆": deck_of(card), "卡型": KIND_LABEL.get(kind, kind)},
			"rows": rows,
		})
	return out


## 牌堆归属：**没写 `only` 的就是通用卡**，两副牌堆都会抽到（`GameData.events_for` 的口径）
func deck_of(card: Dictionary) -> String:
	return "机会专属" if card.has("only") else "通用"


## 逐字段把效果摊成「键 / 值」行。顺序照 事件卡.md §三 的结算顺序，
## 所以一张多效果卡在页面上读起来跟结算顺序一致。
func _card_rows(card: Dictionary) -> Array:
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


## 香皂（免疫标签）对这张卡意味着什么 —— 口径照 事件卡.md §四「免疫点」，
## **由字段推出、不从文档抄**：那三条规则是完备的，抄一份就多一个会烂的地方。
## 收益 / 中性卡也**照出一行**「不受影响」：查手册的人问的就是「这张卡香皂管不管」，
## 空着等于没回答。
func _card_soap(card: Dictionary) -> String:
	var notes: Array[String] = []
	if card.has("from_each"):
		notes.append("对每名室友**逐个**判定（持皂的那位不用给）")
	if card.has("money") and int(card.money) < 0:
		notes.append("扣款可免疫")
	if card.has("to_each"):
		notes.append("你持皂则整条免疫")
	if card.has("go_jail"):
		notes.append("可免疫")
	if card.has("move_steps") and int(card.move_steps) < 0:
		notes.append("倒退可免疫")
	if notes.is_empty():
		return "不受影响（收益 / 中性）"
	return "；".join(notes)


# ---------------------------------------------------------------- 道具

func _entries_items(doc: Dictionary) -> Array:
	var out: Array = []
	for id in ItemData.ITEMS:
		var d: Dictionary = ItemData.ITEMS[id]
		var q := String(d.get("quality", ""))
		var implemented := bool(d.get("implemented", false))
		var rows: Array = []
		if not implemented:
			rows.append({"k": "状态", "v": "**未实装**（不进货架池，效果待批次解锁）"})
		rows.append({"k": "售价", "v": _item_price_text(id, q)})
		if d.has("target"):
			var t := String(d.target)
			rows.append({"k": "选目标", "v": TARGET_LABEL.get(t, t) + THEN_LABEL.get(String(d.get("then", "")), "")})
		rows.append_array(_doc_rows(String(id), doc))
		# 卡面文案两处不一致 → 就地标出来（顶部横幅只是汇总，这里才是能直接下手的那个）
		var de: Dictionary = doc.get(id, {})
		if not de.is_empty() and not String(de.face).is_empty() \
				and String(de.face) != String(d.get("desc", "")):
			rows.append({"k": "⚠ 文档", "v": "道具图鉴.md 的「卡面文案」写着 `%s`，与游戏卡面（代码 `desc`）不一致"
				% String(de.face)})
		var chips: Array = [{"t": "%s · %s" % [q, ItemData.QUALITY_NAMES.get(q, q)],
			"color": _hex(ItemData.QUALITY_COLORS.get(q, Color.WHITE))}]
		chips.append({"t": TYPE_LABEL.get(String(d.get("type", "")), String(d.get("type", "")))})
		if String(d.get("type", "")) != "passive":
			chips.append({"t": "%d⚡" % int(d.get("cost", 0))})
		if bool(d.get("unique", false)):
			chips.append({"t": "唯一"})
		var cd := int(d.get("cooldown", 0))
		if cd > 0:
			chips.append({"t": "冷却 %d" % cd})
		if bool(d.get("hidden", false)):
			chips.append({"t": "隐藏件"})
		out.append({
			"title": String(id),
			"subtitle": "",     # 品质 / 类型 / 能量 / 唯一 / 冷却 chips 已经说全了，别再用一句话复述一遍
			"icon": ICON_PREFIX + String(d.get("icon", "")) + ".png",
			"glyph": "🃏",
			"accent": _hex(ItemData.QUALITY_COLORS.get(q, Color.WHITE)),
			"chips": chips,
			"facets": {
				"品质": q,
				"类型": TYPE_LABEL.get(String(d.get("type", "")), ""),
				"唯一": "唯一" if bool(d.get("unique", false)) else "非唯一",
				"状态": "已实装" if implemented else "未实装",
			},
			# 卡面正文 = 代码的 `desc`（与文档的「卡面文案」同义，对账见 `_report_doc_gaps`）
			"body": String(d.get("desc", "")),
			"rows": rows,
			"flag": "" if implemented else "未实装",
			"dim": not implemented,
		})
	return out


func _item_price_text(id: String, q: String) -> String:
	if ItemData.def(id).has("price"):
		return "¥%d（单件覆盖，不随%s档整体定价）" % [ItemData.item_price(id), q]
	return "¥%d（%s档定价）" % [ItemData.item_price(id), q]


## 并上 `道具图鉴.md` 的 prose（效果 / 免疫 / 联动 …）
func _doc_rows(id: String, doc: Dictionary) -> Array:
	if not doc.has(id):
		return []
	var e: Dictionary = doc[id]
	var rows: Array = []
	for r in e.rows:
		if DOC_SYNONYM_KEYS.has(String(r.k)):
			continue
		rows.append(r)
	var note := String(e.get("note", ""))
	if not note.is_empty():
		var clean := note.lstrip("·").strip_edges()
		if not clean.is_empty():
			rows.append({"k": "文档标注", "v": clean})
	return rows


# ---------------------------------------------------------------- 开局科技

func _entries_techs() -> Array:
	var out: Array = []
	for tier in TechData.TIERS:
		for name in TechData.pool(tier):     # 只出 implemented（弃案留空的编号不在池里）
			var col := _hex(TechData.tier_color(tier))
			out.append({
				"title": String(name),
				"subtitle": "开局三选一 · 整局生效",   # 档位由上面那枚彩色 chip 说，副标题别重复它
				"glyph": TIER_GLYPH.get(tier, "🔧"),
				"accent": col,
				"chips": [{"t": tier, "color": col}],
				"facets": {"档位": tier},
				"body": String(TechData.TECHS[name].get("desc", "")),
				"rows": [],
			})
	return out


# ---------------------------------------------------------------- 畸变

func _entries_aberrations() -> Array:
	var out: Array = []
	for id in AberrationData.ABERRATIONS:
		var d: Dictionary = AberrationData.ABERRATIONS[id]
		var tag := String(d.get("tag", "中性"))
		var implemented := bool(d.get("implemented", true))
		var rows: Array = []
		var dur := int(d.get("dur", 0))
		rows.append({"k": "持续", "v": ("%d 回合" % dur) if dur > 0
			else ("跟随开局设置的「持续回合」基准" if String(d.get("type", "")) == "持续" else "触发即结算，不持续")})
		if int(d.get("min_round", 0)) > 0:
			rows.append({"k": "起始回合", "v": "第 %d 回合起才可能触发" % int(d.min_round)})
		if d.has("cond"):
			rows.append({"k": "触发门槛", "v": _ab_cond_text(d.cond)})
		rows.append_array(_ab_values(id, d))
		if not implemented:
			rows.append({"k": "状态", "v": "**未实装**（不进触发池）"})
		# 香皂能不能免：**由标签推出**（tag == debuff ⇔ 免疫），口径见 畸变.md §四
		rows.append({"k": "香皂", "v": "可免疫（debuff）" if tag == "debuff" else "不受影响（非 debuff）"})
		out.append({
			"title": String(id),
			"subtitle": "",     # 类型 / 触发两枚 chip 已经说全了
			"glyph": "🌪️",
			"accent": TAG_COLOR.get(tag, "#9fb3c0"),
			"chips": [
				{"t": String(d.get("type", ""))},
				{"t": String(d.get("trigger", ""))},
				{"t": TAG_LABEL.get(tag, tag), "color": TAG_COLOR.get(tag, "")},
			],
			"facets": {"类型": String(d.get("type", "")), "触发": String(d.get("trigger", "")), "标签": TAG_LABEL.get(tag, tag)},
			"body": String(d.get("desc", "")),
			"rows": rows,
			"dim": not implemented,
		})
	return out


func _ab_cond_text(cond: Dictionary) -> String:
	var parts: Array[String] = []
	if cond.has("props"):
		parts.append("有人持有 ≥ %d 块地皮" % int(cond.props))
	if cond.has("cash"):
		parts.append("有人现金 ≥ ¥%d" % int(cond.cash))
	return "；".join(parts)


## 畸变里那几条「说明里没写数」的，把 `AberrationData` 的占位常量读出来摊开
func _ab_values(id: String, d: Dictionary) -> Array:
	match id:
		"金融危机":
			return [{"k": "数值", "v": "无房产者扣现金 %.0f%%，有房产者 %.0f%%%s" % [
				AberrationData.FIN_RATE_NC * 100.0, AberrationData.FIN_RATE_C * 100.0, AB_PLACEHOLDER]}]
		"枪打出头鸟":
			return [{"k": "数值", "v": "按现金 %.0f%% 强制捐款%s" % [
				AberrationData.BIRD_RATE * 100.0, AB_PLACEHOLDER]}]
		"房价崩盘":
			return [{"k": "数值", "v": "持续 %d 回合%s" % [int(d.get("dur", 0)), AB_PLACEHOLDER]}]
	return []


# ---------------------------------------------------------------- 解析 `道具图鉴.md`

## 只认「条目」标题：`##`/`### 名称（括号内容以品质字开头）`。
## 这条规则顺手排掉**所有分节标题** —— `## 白·普通（9 件）`（括号里是件数）、
## `## 紫·新批次（2026-10-04 定稿…）`、`### 目标比例（大概，不严格）`，一个都不误收。
func _parse_heading(line: String) -> Dictionary:
	var t := line.strip_edges()
	if not (t.begins_with("## ") or t.begins_with("### ")):
		return {}
	t = t.lstrip("#").strip_edges()
	var a := t.find("（")
	var b := t.find("）")
	if a <= 0 or b < a + 2:
		return {}
	var inner := t.substr(a + 1, b - a - 1)
	if not QUALITY_CHARS.contains(inner.substr(0, 1)):
		return {}
	return {"name": t.substr(0, a).strip_edges(), "note": t.substr(b + 1).strip_edges()}


## `- **键**：值` → {k, v}（文档用的是全角冒号）
func _parse_bullet(line: String) -> Dictionary:
	var t := line.strip_edges()
	if not t.begins_with("- **"):
		return {}
	var a := t.find("**：")
	if a < 4:
		return {}
	return {"k": t.substr(4, a - 4), "v": t.substr(a + 3).strip_edges()}


func _parse_item_doc() -> Dictionary:
	var lines := _read_lines(DOC_ITEMS)
	var heads: Array = []
	for ln in lines:
		heads.append(_parse_heading(ln))
	var out := {}
	for i in lines.size():
		var h: Dictionary = heads[i]
		if h.is_empty():
			continue
		var rows: Array = []
		var face := ""
		var j := i + 1
		while j < lines.size() and (heads[j] as Dictionary).is_empty():
			var b := _parse_bullet(lines[j])
			if not b.is_empty():
				if String(b.k) == "卡面文案":
					face = String(b.v).strip_edges().lstrip("`").rstrip("`")
				else:
					rows.append(b)
			j += 1
		var name := String(h.name)
		# 同名重复出现（文档里有分节重组过）→ 留 bullet 更多的那份
		if not out.has(name) or rows.size() > (out[name].rows as Array).size():
			out[name] = {"rows": rows, "face": face, "note": h.note}
	return out


func _read_lines(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("GALLERY: 读不到 ", path)
		return []
	var out: Array = []
	while not f.eof_reached():
		out.append(f.get_line())
	f.close()
	return out


## 代码 ↔ 文档 的对账。**这三条正是这页会烂掉的方式**，所以做成会叫的清单：
##   ① 代码有、文档没写（新加了道具忘了补文档）→ 页面少一块 prose
##   ② 文档有、代码没写（道具改名 / 删了，文档还留着）→ 页面上多一个孤儿条目
##   ③ 卡面文案两处不一致（`desc` vs 文档的「卡面文案」）→ 页面与游戏卡面对不上
func _report_doc_gaps(doc: Dictionary) -> void:
	for id in ItemData.ITEMS:
		if not doc.has(id):
			_warnings.append("代码有、文档没写：道具「%s」在 道具图鉴.md 里没有条目" % id)
		elif not doc[id].face.is_empty() and String(doc[id].face) != String(ItemData.ITEMS[id].get("desc", "")):
			_warnings.append("卡面文案不一致：道具「%s」代码「%s」↔ 文档「%s」" % [
				id, ItemData.ITEMS[id].get("desc", ""), doc[id].face])
	var lines := _read_lines(DOC_ITEMS)
	for ln in lines:
		var h := _parse_heading(ln)     # `_parse_heading` 已经挡掉了所有分节标题，这里只可能是条目
		if h.is_empty():
			continue
		var name := String(h.name)
		if not ItemData.ITEMS.has(name):
			_warnings.append("文档有、代码没写：道具图鉴.md 的条目「%s」在 item_data.gd 里找不到" % name)


# ---------------------------------------------------------------- 输出

func _section(id: String, title: String, entries: Array) -> Dictionary:
	var facets: Array = []
	var keys: Array = []
	for e in entries:                       # 「有哪些 facet」照第一件条目里出现的先后
		for k in e.facets:
			if not keys.has(k):
				keys.append(k)
	for k in keys:
		var present: Array = []
		for e in entries:
			if e.facets.has(k) and not present.has(e.facets[k]):
				present.append(e.facets[k])
		var vals: Array = []
		for v in _facet_order(id, k):        # 规范顺序优先（品质 白→橙、档位 白银→钻石…）
			if present.has(v):
				vals.append(v)
		for v in present:                    # 规范表没覆盖到的值，按首次出现序补在后面
			if not vals.has(v):
				vals.append(v)
		facets.append({"key": k, "values": vals})
	return {"id": id, "title": title, "entries": entries, "facets": facets}


## 筛选按钮的**规范顺序**。不写这张表的话，顺序就是「数据里谁先出现」——品质会排成
## 紫蓝白绿橙（照 `ITEMS` 的表序），查手册的人一眼懵。取的都是代码里已有的序表
## （`ItemData.QUALITIES` / `TechData.TIERS`），不另立一份。
func _facet_order(sec: String, key: String) -> Array:
	match sec:
		"cards":
			match key:
				"牌堆": return ["通用", "机会专属"]
				"卡型": return [KIND_LABEL["good"], KIND_LABEL["bad"], KIND_LABEL["move"],
					KIND_LABEL["jail"], KIND_LABEL["info"]]
		"items":
			match key:
				"品质": return ItemData.QUALITIES.duplicate()
				"类型": return ["一次性", "主动", "被动"]
				"唯一": return ["唯一", "非唯一"]
				"状态": return ["已实装", "未实装"]
		"techs":
			if key == "档位":
				return TechData.TIERS.duplicate()
		"aberrations":
			match key:
				"类型": return ["持续", "非持续"]
				"触发": return ["随机", "条件"]
				"标签": return [TAG_LABEL["debuff"], TAG_LABEL["buff"], TAG_LABEL["中性"]]
	return []


func _write(sections: Array, total: int) -> void:
	var tpl := FileAccess.get_file_as_string(TPL_PATH)
	if tpl.is_empty() or not tpl.contains(MARK):
		printerr("GALLERY: 模板读不到或缺 %s 标记：%s" % [MARK, TPL_PATH])
		quit(1)
		return
	# **不缩进**：这份 JSON 是生成产物，要评审的是源数据（`item_data.gd` 那些），不是它的 diff；
	# 缩进版会把这页从 ~110KB 撑到 ~270KB，而每改一次数据就在 git 里多存一整份。
	var json := JSON.stringify({
		"total": total,
		"sources": SOURCES,
		"sections": sections,
		"warnings": _warnings,
	}, "", true)
	# `<` 转成 <：数据里只要出现 `</script>` 就会把页面撕开，而 `<` 是合法 JSON 转义
	json = json.replace("<", "\\u003c")
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("GALLERY: 写不进 ", OUT_PATH)
		quit(1)
		return
	f.store_string(tpl.replace(MARK, json))
	f.close()


func _hex(c: Color) -> String:
	return "#" + c.to_html(false)
