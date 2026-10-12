extends SceneTree
## 「道具图鉴.md ↔ item_data.gd」对账器（2026-10-12 从 `tools/gen_gallery.gd` 里切出来的那一半）。
##
##	godot --headless --path . --script tools/check_item_docs.gd
##
## **为什么不生成任何文件**：它原先的搭档 `gen_gallery.gd` 会产出一张网页
## `doc/game-design/图鉴.html`（给团队查的检索页）。那张网页 2026-10-12 **已删除** ——
## 用户把「图鉴」定成**对局里那一个**（`scripts/codex_panel.gd`，数据直读 `CardDB`），
## 于是"同一批数据两处展示"的第二个落点没有了。
##
## 但生成器**真正值钱的是这一半**：`道具图鉴.md` 是逐件道具 prose（效果 / 免疫 / 联动 / 卡面文案）
## 的**唯一来源**，而它与代码之间会不会漂开，此前**只有这个生成器在查**。
## 网页没了就把对账一起丢掉，等于把"文档悄悄过时"重新放行 —— 所以留下来，
## 砍掉出页那一半，改成"只对账、有问题就非零退出"的**闸门**（CI 那一步跑的就是它）。
##
## 三条口径（照抄原生成器的 `_report_doc_gaps`，判据一个字没改）：
##   ① 代码有、文档没写（新加了道具忘了补文档）
##   ② 文档有、代码没写（道具改名 / 删了，文档还留着）
##   ③ 卡面文案两处不一致（`desc` vs 文档的「卡面文案」）
##
## ①判的是「**全文查不到**」，不是「没有独立小节」：有的件本来就不该有独立小节
##（`组队学习·寒暑` 是隐藏件，文档把它写在「组队学习」与`二青会酒寒暑`两条下面的
## `- **强化版「组队学习·寒暑」**：` 里）。只认标题会把这种正常写法报成缺项，
## 而**常驻的假警会训练人忽略整条横幅** —— 那比不报还糟。

const DOC_ITEMS := "res://doc/game-design/道具图鉴.md"

var _warnings: Array[String] = []


func _initialize() -> void:
	var lines := _read_lines(DOC_ITEMS)
	if lines.is_empty():
		printerr("DOC CHECK: 读不到 ", DOC_ITEMS)
		quit(1)
		return
	var doc := _parse_item_doc(lines)
	_report_doc_gaps(doc, lines)
	if _warnings.is_empty():
		print("DOC CHECK: 道具图鉴.md 与 item_data.gd 一致（%d 件，无缺项）" % ItemData.ITEMS.size())
		quit(0)
		return
	printerr("DOC CHECK: %d 条代码/文档不一致：" % _warnings.size())
	for w in _warnings:
		printerr("  - ", w)
	quit(1)


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
	# 品质档**只有一个来源**：`ItemData.QUALITIES`。原先这里硬编码 "白绿蓝紫橙" —— 那是品质档的
	# 第二来源，而这里又是本函数的**准入判据**，忘了同步它，文档条目会**静默解析失败**
	#（条目不进解析结果，只表现为报「文档有代码没写」，定位很难）。改读数据类后改档位只需动 ItemData。
	if not ItemData.QUALITIES.has(inner.substr(0, 1)):
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


func _parse_item_doc(lines: Array) -> Dictionary:
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
		return []
	var out: Array = []
	while not f.eof_reached():
		out.append(f.get_line())
	f.close()
	return out


func _report_doc_gaps(doc: Dictionary, lines: Array) -> void:
	var text := "\n".join(PackedStringArray(lines))   # `String.join` 吃 PackedStringArray，不吃 Array
	for id in ItemData.ITEMS:
		if doc.has(id):
			if not String(doc[id].face).is_empty() \
					and String(doc[id].face) != String(ItemData.ITEMS[id].get("desc", "")):
				_warnings.append("卡面文案不一致：道具「%s」代码「%s」↔ 文档「%s」" % [
					id, ItemData.ITEMS[id].get("desc", ""), doc[id].face])
		elif not text.contains(String(id)):
			_warnings.append("代码有、文档没写：道具「%s」在 道具图鉴.md 里查不到" % id)
	for ln in lines:
		var h := _parse_heading(ln)     # `_parse_heading` 已经挡掉了所有分节标题，这里只可能是条目
		if h.is_empty():
			continue
		var name := String(h.name)
		if not ItemData.ITEMS.has(name):
			_warnings.append("文档有、代码没写：道具图鉴.md 的条目「%s」在 item_data.gd 里找不到" % name)
