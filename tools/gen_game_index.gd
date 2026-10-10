extends SceneTree
## 为 `scripts/game.gd` 生成「区块 → 函数」导航索引，写回文件头的标记块之间。
##
## 为什么要它：`game.gd` 已 8000+ 行、40 万字节，人和 AI 都难在里头定位。有了索引，
## 「先看地图、再 grep」才成为可能。
##
## 为什么必须**生成**而不是手写：本仓 CHANGELOG 自己记着——game.gd 曾从 3439 行
## 拆到 ~2400 行，如今又长回 8000+ 行。手写的索引必然烂，且尺寸闸门会不断把代码外迁、
## 索引只会烂得更快。所以和 `doc/game-design/图鉴.html` 一个路子：生成产物 + 闸门校验。
##
## 用法：
##   godot --headless --path . --script tools/gen_game_index.gd             # 写入
##   godot --headless --path . --script tools/gen_game_index.gd -- --check  # 只校验（闸门）
##
## 按 AGENTS.md §五：**只写区块名与函数名，不写行号**——行号会烂。

const TARGET := "res://scripts/game.gd"
const MARK_BEGIN := "# >>>>>>>>>> 导航索引（由 tools/gen_game_index.gd 生成，勿手改） >>>>>>>>>>"
const MARK_END := "# <<<<<<<<<< 导航索引结束 <<<<<<<<<<"
const WRAP := 96                      # 超长行折行宽度（含前导 "# "）

func _initialize() -> void:
	var check_only := OS.get_cmdline_user_args().has("--check")

	var f := FileAccess.open(TARGET, FileAccess.READ)
	if f == null:
		printerr("GEN FAIL - 打不开 ", TARGET)
		quit(1)
		return
	var text := f.get_as_text()
	f.close()

	var lines := text.split("\n")
	var block := _build_block(lines)

	var begin := -1
	var end := -1
	for i in lines.size():
		if lines[i].begins_with(MARK_BEGIN):
			begin = i
		elif lines[i].begins_with(MARK_END):
			end = i
			break

	var new_lines: PackedStringArray
	if begin >= 0 and end > begin:
		new_lines = PackedStringArray()
		for i in begin:
			new_lines.append(lines[i])
		new_lines.append_array(block)
		for i in range(end + 1, lines.size()):
			new_lines.append(lines[i])
	else:
		# 首次生成：插在 `extends` 与其后的模块 docstring 之后
		var at := 0
		while at < lines.size():
			var s := lines[at].strip_edges()
			if s == "" or s.begins_with("#") or s.begins_with("extends "):
				at += 1
			else:
				break
		new_lines = PackedStringArray()
		for i in at:
			new_lines.append(lines[i])
		new_lines.append_array(block)
		new_lines.append("")
		for i in range(at, lines.size()):
			new_lines.append(lines[i])

	var out := "\n".join(new_lines)

	if check_only:
		if out == text:
			print("GAME INDEX: PASS（索引是最新的）")
			quit(0)
		else:
			printerr("GAME INDEX: STALE - scripts/game.gd 的导航索引已过期")
			printerr("  重跑：godot --headless --path . --script tools/gen_game_index.gd")
			quit(1)
		return

	if out == text:
		print("GAME INDEX: 无变化")
		quit(0)
		return

	var w := FileAccess.open(TARGET, FileAccess.WRITE)
	if w == null:
		printerr("GEN FAIL - 写不了 ", TARGET)
		quit(1)
		return
	w.store_string(out)
	w.close()
	print("GAME INDEX: 已写入（%d 行 → %d 行）" % [lines.size(), new_lines.size()])
	quit(0)

func _banner_name(body: String) -> String:
	## body = '#' 之后的去空白内容。识别 `==== 名称 ====` / `---- 名称 ----`。
	if not (body.begins_with("===") or body.begins_with("---")):
		return ""
	var i := 0
	while i < body.length() and (body[i] == "=" or body[i] == "-"):
		i += 1
	var j := body.length()
	while j > i and (body[j - 1] == "=" or body[j - 1] == "-"):
		j -= 1
	return body.substr(i, j - i).strip_edges()

func _func_name(s: String) -> String:
	## s 已 strip_edges，形如 `func _ready() -> void:`
	for pre in ["static func ", "func "]:
		if s.begins_with(pre):
			var rest := s.substr(pre.length())
			var p := rest.find("(")
			return rest.substr(0, p) if p > 0 else rest
	return ""

func _build_block(lines: PackedStringArray) -> PackedStringArray:
	## 两条规则，都是被生成结果逼出来的：
	##  1. 首个 `# ====` 大横幅**之前**的横幅一律不当区块——那一带是常量/成员变量的分组
	##     （「同步状态」「房主权威」…），底下没有函数；而且 `_ready` 前面根本没有横幅，
	##     不设这条它会挂到上一个变量分组「自动化测试」名下。
	##  2. 没有函数的区块直接不发——否则顶部会多出十几行纯噪音。
	var sections: Array = []          # [{name, funcs: PackedStringArray}]
	var seen_major := false
	for line in lines:
		var s := line.strip_edges()
		if s.begins_with("#"):
			var body := s.substr(1).strip_edges()
			var nm := _banner_name(body)
			if nm != "":
				if seen_major:
					sections.append({"name": nm, "funcs": PackedStringArray()})
				elif body.begins_with("==="):
					seen_major = true
					sections.append({"name": nm, "funcs": PackedStringArray()})
			continue
		var fn := _func_name(s)
		if fn == "":
			continue
		if sections.is_empty():
			sections.append({"name": "文件头（模块注释 / 常量 / 成员 / 生命周期）",
							 "funcs": PackedStringArray()})
		sections[sections.size() - 1]["funcs"].append(fn)

	var out := PackedStringArray()
	out.append(MARK_BEGIN)
	out.append("# 生成器 tools/gen_game_index.gd ｜ 闸门 tests/load_all.gd 会校验它是否过期")
	out.append("# 约定：只列「区块 → 函数名」，不写行号（行号会烂，见 AGENTS.md §五）")
	out.append("#")
	var n_sec := 0
	var n_func := 0
	for sec in sections:
		var funcs: PackedStringArray = sec["funcs"]
		if funcs.is_empty():
			continue
		n_sec += 1
		n_func += funcs.size()
		var cur := "# 【%s】 " % sec["name"]
		for fn in funcs:
			var piece := (fn + ", ")
			if cur.length() + piece.length() > WRAP:
				out.append(cur.rstrip(", "))
				cur = "#     "
			cur += piece
		out.append(cur.rstrip(", "))
	out.append("#")
	out.append("# 合计 %d 个区块 / %d 个函数" % [n_sec, n_func])
	out.append(MARK_END)
	return out
