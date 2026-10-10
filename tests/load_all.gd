extends SceneTree
## 加载所有脚本做静态检查：godot --headless --script tests/load_all.gd
## 自动扫描 `scripts/` 与 `tools/`（都是**扫目录**、不硬列清单——此前漏了 item_data.gd /
## item_card.gd，一个「加载检查」静默跳过最新代码比没有更糟）。
## `tools/` 是构建期工具、不进游戏，但同样是仓库里的 GDScript：图鉴生成器语法错了
## 也该在本地这一步就红，而不是等 CI 跑生成时才发现。
## 判解析失败用「方法表为空」：实测 ResourceLoader.load 在编译失败时仍返回非 null
## 资源（只判 null 会把语法错误报成 PASS），而 GDScript.reload() 对活着的 autoload
## 一律返回 22（net.gd/fx.gd 被误报）。编译失败的脚本方法表为 0，正常脚本都非空。

## 另附一道**体积棘轮**（见下 GAME_GD_LINE_BUDGET）：它放在这里，是因为这个脚本
## 是「改完任何 .gd 都先跑」的那一道，最便宜、最不会被忘。

const DIRS := ["res://scripts", "res://tools"]

const GAME_GD := "res://scripts/game.gd"
## 只降不升的棘轮。`game.gd` 是全员热点（近 30 条提交 30 条都动它），而本仓 CHANGELOG
## 自己记着：它曾从 3439 行拆到 ~2400 行，又长回了 8000+ 行 —— 「没有持续约束的拆分
## 会被新功能淹没」。所以这里卡死一个阈值：**要往里加代码，就得先搬点东西出去**。
## 搬完把小一号的数字填回来（棘轮只能往下走）。确实需要放宽时，请连同理由一起改，
## 并同步 AGENTS.md §四。
const GAME_GD_LINE_BUDGET := 8222

func _line_count(p: String) -> int:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return -1
	var t := f.get_as_text()
	f.close()
	return t.split("\n").size()

func _check_size_ratchet() -> int:
	var n := _line_count(GAME_GD)
	if n < 0:
		printerr("SIZE FAIL - 读不到 ", GAME_GD)
		return 1
	if n > GAME_GD_LINE_BUDGET:
		printerr("SIZE FAIL - game.gd 已 %d 行，超出预算 %d 行（多出 %d 行）"
				% [n, GAME_GD_LINE_BUDGET, n - GAME_GD_LINE_BUDGET])
		printerr("  这是一道**只降不升**的棘轮：新代码请写到别的文件去")
		printerr("  （照抄 casino.gd / dev_tools.gd 的「子节点 + var g 反向引用」模式，")
		printerr("   或把纯数据/纯查询下沉进 *_data.gd）。搬完把预算数字调小。")
		return 1
	print("  ok - game.gd %d 行 / 预算 %d 行（余量 %d）"
			% [n, GAME_GD_LINE_BUDGET, GAME_GD_LINE_BUDGET - n])
	return 0

func _initialize() -> void:
	var scripts: Array[String] = []
	for d in DIRS:
		var dir := DirAccess.open(d)
		if dir == null:
			printerr("LOAD FAIL - 打不开 ", d)
			quit(1)
			return
		for f in dir.get_files():
			if f.ends_with(".gd"):
				scripts.append(d + "/" + f)
	scripts.sort()

	var fails := 0
	for s in scripts:
		var res := ResourceLoader.load(s, "GDScript", ResourceLoader.CACHE_MODE_REPLACE)
		if res == null:
			printerr("LOAD FAIL - ", s)
			fails += 1
			continue
		var gd := res as GDScript
		if gd.get_script_method_list().is_empty():
			printerr("PARSE FAIL - ", s)
			fails += 1
		else:
			print("  ok - ", s)

	fails += _check_size_ratchet()

	if fails == 0:
		print("LOAD ALL: PASS（%d 个脚本）" % scripts.size())
		quit(0)
	else:
		print("LOAD ALL: %d FAILURES" % fails)
		quit(1)
